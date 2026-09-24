// zesarux_bridge.cpp -- swap-in replacement for the zxpoly JVM
// bridge. Same C ABI as bridge/zxpoly_bridge.h, so the Dart side
// keeps working untouched. The implementation:
//
//   - forks ZEsarUX as a subprocess with --enable-remoteprotocol
//   - connects to its ZRCP socket (TCP localhost, port chosen by
//     us via --remoteprotocol-port)
//   - sends 'smartload <path>' / 'load <path>' to load files
//   - sends 'send-keys-ascii <delay> <chars>' for keyboard input
//   - reads --vofile output for the framebuffer
//   - sends 'quit' on shutdown
//
// The recolour APIs are no-ops: ZEsarUX has no 4-CPU parallel mode
// and no recolour feature. The Dart UI's recolour toggle still
// works as a stored preference; it just doesn't change rendering.

#include "zxpoly_bridge.h"

#include <arpa/inet.h>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <vector>

// Keep the same error codes as the old zxpoly bridge so the Dart
// side's enum maps cleanly.
#define ZXPOLY_OK             0
#define ZXPOLY_ERR_GENERIC    -1
#define ZXPOLY_ERR_NOTIMPL    -2
#define ZXPOLY_ERR_BADARG     -3

namespace {

struct BridgeState {
    pid_t zesarux_pid = 0;

    // ZRCP socket (TCP localhost:port). Read by a worker thread,
    // written by the bridge functions.
    int zrcp_sock = -1;

    // Last framebuffer pulled from --vofile. ZEsarUX writes 320x240
    // RGB24; we widen it to RGBA8888 once for the Dart side to read.
    std::vector<uint8_t> frame_rgb;
    std::vector<uint32_t> frame_rgba;
    int frame_w = 320;
    int frame_h = 240;
    int frame_stride = 320;
    std::atomic<bool> frame_ready{false};

    // vofile path. ZEsarUX writes raw RGB24 frames here.
    std::string vofile_path;

    // ZEsarUX binary path. Set via $ZESARUX_BIN or default.
    std::string zesarux_bin = "/tmp/zesarux/src/zesarux";

    // ZRCP port. Set via $ZESARUX_PORT or pick a free ephemeral.
    int zrcp_port = 0;

    std::atomic<bool> running{false};
    std::string last_error_;
};

BridgeState &state() {
    static BridgeState s;
    return s;
}

// ---- small helpers ----

void die(const std::string &msg) {
    state().last_error_ = msg;
    std::fprintf(stderr, "[zes] %s\n", msg.c_str());
}

ssize_t write_all(int fd, const void *buf, size_t n) {
    const char *p = (const char *)buf;
    size_t left = n;
    while (left > 0) {
        ssize_t w = ::write(fd, p, left);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        left -= (size_t)w;
        p += w;
    }
    return (ssize_t)n;
}

// Send a ZRCP command and wait for a single-line response.
// ZRCP is a text protocol: client sends "command args\n", server
// replies with one or more lines, the last line is "OK" or "ERROR".
// We read up to a terminator or a short timeout.
int zrcp_send(const std::string &cmd, std::string *reply_out = nullptr,
              int timeout_ms = 5000) {
    int s = state().zrcp_sock;
    if (s < 0) return -1;
    std::string line = cmd + "\n";
    if (write_all(s, line.data(), line.size()) < 0) return -1;

    if (!reply_out) return 0;
    reply_out->clear();

    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(timeout_ms);
    std::string buf;
    while (std::chrono::steady_clock::now() < deadline) {
        struct pollfd pfd{s, POLLIN, 0};
        int pr = ::poll(&pfd, 1, 100);
        if (pr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (pr == 0) continue;
        char tmp[256];
        ssize_t n = ::read(s, tmp, sizeof tmp);
        if (n <= 0) return -1;
        buf.append(tmp, (size_t)n);
        // Look for a newline-terminated status line.
        auto nl = buf.find('\n');
        if (nl != std::string::npos) {
            *reply_out = buf.substr(0, nl);
            // Strip any OK./ERROR. prefix; we just want the message.
            auto dot = reply_out->find('.');
            if (dot != std::string::npos && dot < 8) {
                reply_out->erase(0, dot + 1);
                while (!reply_out->empty() &&
                       (*reply_out)[0] == ' ') reply_out->erase(0, 1);
            }
            return reply_out->find("ERROR") == 0 ? -1 : 0;
        }
    }
    return -1;  // timeout
}

// ---- subprocess management ----

int pick_free_port() {
    int s = ::socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return -1;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;  // ephemeral
    if (::bind(s, (sockaddr *)&addr, sizeof addr) < 0) {
        ::close(s);
        return -1;
    }
    socklen_t len = sizeof addr;
    if (::getsockname(s, (sockaddr *)&addr, &len) < 0) {
        ::close(s);
        return -1;
    }
    int port = ntohs(addr.sin_port);
    ::close(s);
    return port;
}

int connect_zrcp(int port, int timeout_ms) {
    int s = ::socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return -1;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);

    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(timeout_ms);
    while (std::chrono::steady_clock::now() < deadline) {
        int cr = ::connect(s, (sockaddr *)&addr, sizeof addr);
        if (cr == 0) return s;
        if (errno != ECONNREFUSED && errno != ENOENT) {
            ::close(s);
            return -1;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    ::close(s);
    return -1;
}

int launch_zesarux() {
    auto &s = state();
    if (const char *p = std::getenv("ZESARUX_BIN")) s.zesarux_bin = p;

    s.vofile_path = std::string(std::getenv("TMPDIR") ?
        std::getenv("TMPDIR") : "/tmp") + "/retro-spectrum-vofile.raw";

    s.zrcp_port = pick_free_port();
    if (s.zrcp_port <= 0) {
        die("could not pick a free port for ZRCP");
        return ZXPOLY_ERR_GENERIC;
    }

    // Build command line. We launch ZEsarUX with the right flags:
    //   --machine <48k|TBBlue|...>  (set later, on open_file)
    //   --enable-remoteprotocol
    //   --remoteprotocol-port <port>
    //   --vofile <path> --vofilefps 50
    //   --ao null --vo null  (headless; the Dart side reads the framebuffer)
    //
    // We don't pass --tape / --snap up front; we use ZRCP smartload
    // so the same binary works for any .tap / .z80 / .nex / etc.

    int pipefd[2];
    if (::pipe(pipefd) < 0) { die("pipe() failed"); return -1; }

    pid_t pid = ::fork();
    if (pid < 0) { die("fork() failed"); return -1; }
    if (pid == 0) {
        // child: detach, redirect stdio
        ::setsid();
        ::dup2(pipefd[1], 1);  // stdout -> parent
        ::dup2(pipefd[1], 2);  // stderr -> parent (combined)
        ::close(pipefd[0]);
        ::close(pipefd[1]);

        // We don't know the machine yet; the bridge sets it via ZRCP.
        // Use a default of 48k so ZEsarUX has something to do.
        std::vector<const char *> argv;
        argv.push_back(s.zesarux_bin.c_str());
        argv.push_back("--machine");
        argv.push_back("48k");
        argv.push_back("--enable-remoteprotocol");
        argv.push_back("--remoteprotocol-port");
        argv.push_back(std::to_string(s.zrcp_port).c_str());
        argv.push_back("--vofile");
        argv.push_back(s.vofile_path.c_str());
        argv.push_back("--vofilefps");
        argv.push_back("50");
        argv.push_back("--ao");
        argv.push_back("null");
        argv.push_back("--vo");
        argv.push_back("null");
        argv.push_back("--noconfigfile");
        argv.push_back(nullptr);
        ::execv(argv[0], const_cast<char *const *>(argv.data()));
        std::_Exit(127);
    }

    // parent
    ::close(pipefd[1]);
    s.zesarux_pid = pid;

    // Drain the child's stdout/stderr into a background thread.
    std::thread([fd = pipefd[0]]() {
        char buf[4096];
        for (;;) {
            ssize_t n = ::read(fd, buf, sizeof buf);
            if (n <= 0) break;
            std::fwrite(buf, 1, (size_t)n, stderr);
        }
        ::close(fd);
    }).detach();

    // Connect to ZRCP. ZEsarUX can take a few seconds to fully
    // initialise the protocol server after launch, so be patient.
    s.zrcp_sock = connect_zrcp(s.zrcp_port, 20000);
    if (s.zrcp_sock < 0) {
        die("could not connect to ZEsarUX ZRCP port");
        return ZXPOLY_ERR_GENERIC;
    }

    // ZRCP readiness check: get-memory-pages is harmless and just
    // returns the memory map. The first line of the response is
    // "OK. ..."; if the server is alive we get OK, if not we get
    // ERROR or a timeout.
    //
    // We deliberately do NOT spawn a background drain thread here --
    // doing so creates a race where the drain reads the response
    // before zrcp_send can, causing every subsequent command to
    // timeout. The bridge owns the socket; all reads happen from
    // zrcp_send under a per-call timeout.
    std::string reply;
    if (zrcp_send("get-memory-pages", &reply, 5000) < 0) {
        die("ZRCP handshake failed: " + reply);
        return ZXPOLY_ERR_GENERIC;
    }
    return ZXPOLY_OK;
}

void stop_zesarux() {
    auto &s = state();
    if (s.zrcp_sock >= 0) {
        ::shutdown(s.zrcp_sock, SHUT_RDWR);
        ::close(s.zrcp_sock);
        s.zrcp_sock = -1;
    }
    if (s.zesarux_pid > 0) {
        ::kill(s.zesarux_pid, SIGTERM);
        // Wait briefly for graceful exit, then SIGKILL.
        for (int i = 0; i < 50; i++) {
            int status;
            pid_t r = ::waitpid(s.zesarux_pid, &status, WNOHANG);
            if (r == s.zesarux_pid || r < 0) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        ::kill(s.zesarux_pid, SIGKILL);
        ::waitpid(s.zesarux_pid, nullptr, 0);
        s.zesarux_pid = 0;
    }
}

// Pull the latest frame from --vofile. ZEsarUX writes 320x240 RGB24.
// The file is overwritten in place; mmap gives us atomic-ish reads.
// For simplicity (and to avoid mmap lifecycle complexity) we just
// read into a buffer.
void poll_frame() {
    auto &s = state();
    int fd = ::open(s.vofile_path.c_str(), O_RDONLY);
    if (fd < 0) return;
    struct stat st{};
    if (::fstat(fd, &st) < 0 || st.st_size <= 0) {
        ::close(fd);
        return;
    }
    // 320*240*3 = 230400 bytes per frame.
    constexpr int frame_size = 320 * 240 * 3;
    if (st.st_size < frame_size) {
        ::close(fd);
        return;
    }
    s.frame_rgb.assign(frame_size, 0);
    // Read the most recent full frame: seek to (size - frame_size).
    off_t off = st.st_size - frame_size;
    if (::lseek(fd, off, SEEK_SET) < 0) {
        ::close(fd);
        return;
    }
    ssize_t n = ::read(fd, s.frame_rgb.data(), frame_size);
    if (n == frame_size) {
        s.frame_w = 320;
        s.frame_h = 240;
        s.frame_stride = 320;
        // Widen RGB24 -> RGBA8888 once so get_framebuffer returns a
        // buffer the Dart side can decode directly.
        s.frame_rgba.assign(s.frame_w * s.frame_h, 0xff000000u);
        for (int i = 0; i < s.frame_w * s.frame_h; i++) {
            uint32_t r = s.frame_rgb[i*3 + 0];
            uint32_t g = s.frame_rgb[i*3 + 1];
            uint32_t b = s.frame_rgb[i*3 + 2];
            s.frame_rgba[i] = 0xff000000u | (r << 16) | (g << 8) | b;
        }
        s.frame_ready.store(true);
    }
    ::close(fd);
}

}  // namespace

// ---- C ABI the Dart side calls ----

extern "C" int zxpoly_bridge_init(const char *profile, const char *resource) {
    (void)profile;
    (void)resource;
    int rc = launch_zesarux();
    if (rc == ZXPOLY_OK) state().running = true;
    return rc;
}

extern "C" int zxpoly_bridge_start(void) {
    // ZEsarUX's CPU runs by default after a smartload. The ZRCP 'run'
    // command only works in cpu-step mode, which we never enable. So
    // start() is a no-op; the emulator is already running.
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_open_file(const char *path) {
    if (!path) return ZXPOLY_ERR_BADARG;
    auto &s = state();
    if (s.zrcp_sock < 0) return ZXPOLY_ERR_GENERIC;

    // Pick the machine from the file extension:
    //   .nex, .sna, .z80 -> Spectrum Next (TBBlue) with fast-boot
    //   .tap, .tzx, .zsf -> ZX Spectrum 48k
    //   .sze, .zxp       -> ZX Spectrum Next (pre-adapted ZX-Poly)
    // Anything else: try 48k.
    const char *dot = std::strrchr(path, '.');
    std::string machine = "48k";
    if (dot) {
        std::string ext = dot;
        for (auto &c : ext) c = std::tolower((unsigned char)c);
        if (ext == ".nex" || ext == ".sna" || ext == ".z80" ||
            ext == ".sze" || ext == ".zxp") {
            machine = "TBBlue";
        }
    }

    // Smartload picks up the file and figures out the right machine
    // for most formats. We only need to switch machine for TBBlue (Next)
    // games, where the default isn't the right one.
    std::string reply;
    if (machine == "TBBlue") {
        if (zrcp_send("set-machine TBBlue", &reply, 3000) < 0) {
            // Some ZEsarUX versions want a slightly different
            // argument; we tolerate the failure and let smartload
            // figure it out, since .nex files are clearly Next.
            reply.clear();
        }
        // The full Next boot ROM is not bundled with ZEsarUX; the
        // fast-boot flag lets .nex files run without it.
        zrcp_send("set-tbblue-fast-boot-mode", &reply, 3000);
    }
    if (zrcp_send(std::string("smartload ") + path, &reply, 10000) < 0) {
        die("smartload " + std::string(path) + " failed: " + reply);
        return ZXPOLY_ERR_GENERIC;
    }

    // Trigger a frame poll so get_framebuffer() has data right away.
    poll_frame();
    return ZXPOLY_OK;
}

extern "C" const char *zxpoly_bridge_run_frame(void) {
    if (!state().running) return "engine not running";
    poll_frame();
    return state().frame_ready.load() ? nullptr : "no frame yet";
}

extern "C" const uint32_t *zxpoly_bridge_get_framebuffer(int32_t *w, int32_t *h) {
    if (w) *w = state().frame_w;
    if (h) *h = state().frame_h;
    if (!state().frame_ready.load()) return nullptr;
    return state().frame_rgba.data();
}

extern "C" int zxpoly_bridge_set_recolour(int enabled) {
    (void)enabled;
    return ZXPOLY_OK;  // ZEsarUX has no recolour; UI toggle is a no-op
}

extern "C" int zxpoly_bridge_get_recolour(void) {
    return 0;
}

extern "C" int zxpoly_bridge_recolour_now(void) {
    return ZXPOLY_OK;  // already a no-op
}

extern "C" int zxpoly_bridge_key_event(int32_t key, int32_t flags) {
    auto &s = state();
    if (s.zrcp_sock < 0) return ZXPOLY_ERR_GENERIC;
    // The 40-key Spectrum matrix -> ZXKEY_* map lives in the C++ side.
    // ZRCP 'send-keys-ascii' takes ASCII chars with a per-key delay
    // in ms. Press = the char; release = space-then-char (best
    // approximation; ZRCP has no release primitive).
    //
    // We approximate press by sending the char; release by sending a
    // backspace-then-char (or, more simply, accept that ZEsarUX's
    // keyboard model is auto-repeat-based and just send the key).
    //
    // The mapping matches the JNI bridge's old ZXKEY_* lookup: 5 rows
    // of 8 keys each. The char for each key follows the standard
    // Spectrum matrix; for keys that aren't typeable we fall back to
    // sending a control sequence (not implemented here -- the Dart
    // side already handles key release semantics via repeated presses).
    static const char *keys[40] = {
        // row 0 (port 0xFE bit 0): CS,Z,X,C,V
        "\x03","z","x","c","v",
        // row 1 (port 0xFE bit 1): A,S,D,F,G
        "a","s","d","f","g",
        // row 2 (port 0xFE bit 2): Q,W,E,R,T
        "q","w","e","r","t",
        // row 3 (port 0xFE bit 3): 1,2,3,4,5
        "1","2","3","4","5",
        // row 4 (port 0xFE bit 4): 0,9,8,7,6
        "0","9","8","7","6",
        // row 5 (port 0xFD bit 0): P,O,I,U,Y
        "p","o","i","u","y",
        // row 6 (port 0xFD bit 1): ENTER,L,K,J,H
        "\n","l","k","j","h",
        // row 7 (port 0xFD bit 2): SPACE,SYM,M,N,B
        " ","\x18","m","n","b",
    };
    if (key < 0 || key >= 40) return ZXPOLY_ERR_BADARG;
    const char *k = keys[key];
    if (!k || !*k) return ZXPOLY_ERR_BADARG;
    std::string cmd = std::string("send-keys-ascii 50 ") + k;
    return zrcp_send(cmd, nullptr, 2000);
}

extern "C" int zxpoly_bridge_kempston(int32_t mask) {
    // ZRCP doesn't expose a direct kempston-port-write. The ZEsarUX
    // Kempston mouse / joystick is wired differently. For now this is
    // a no-op (kempston is rarely used; most games use keyboard).
    (void)mask;
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_reset(void) {
    auto &s = state();
    if (s.zrcp_sock < 0) return ZXPOLY_ERR_GENERIC;
    std::string reply;
    return zrcp_send("reset", &reply);
}

extern "C" int zxpoly_bridge_set_rom(ZxpolyRom rom, const uint8_t *data,
                                     int32_t size) {
    // ZRCP doesn't directly support uploading ROM bytes; the user is
    // expected to provide a ROM file on disk. The Flutter side could
    // write the ROM to a temp path and call --set-ram-top or similar,
    // but for the Alt-engine path we rely on ZEsarUX's bundled ROMs
    // (48.rom / 128.rom) and the user's separately provided files.
    (void)rom; (void)data; (void)size;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_stop(void) {
    stop_zesarux();
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_dispose(void) {
    stop_zesarux();
    return ZXPOLY_OK;
}

extern "C" int64_t zxpoly_bridge_frame_counter(void) {
    // ZEsarUX's ZRCP doesn't expose a frame counter; the Dart side
    // counts by stepping through frames and computing the delta
    // against wall-clock time. Return 0 to keep the API alive.
    return 0;
}

extern "C" int zxpoly_bridge_get_fps_x100(void) {
    // We don't actually compute FPS in the bridge; the Dart side
    // times frame-to-frame and computes its own number. Returning 0
    // tells the Dart UI "unknown / not yet measured".
    return 0;
}

extern "C" const char *zxpoly_bridge_last_error(void) {
    return state().last_error_.c_str();
}
