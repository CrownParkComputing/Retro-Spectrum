// zxpoly_smoke.cpp -- drive the bridge directly, no Flutter.
//
// Boots the JVM, constructs a Motherboard, opens a .tap, runs N
// frames, and prints the frame counter + framebuffer hash so you
// can see the emulation is actually progressing. Built into a
// standalone executable that loads libzxpolycore.so at runtime.
//
// Usage:
//   ./zxpoly_smoke /path/to/game.tap [frames]
//
// Default frames = 300 (5 seconds at 60Hz; the ZX Spectrum loader
// usually needs more like 800-1500 frames to finish a tape load,
// so pass e.g. 2000 if you want to see the title screen).

#include <dlfcn.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

extern "C" {

// The bridge ABI. Mirrors src/bridge/zxpoly_bridge.h.
int  zxpoly_bridge_init(const char *profile, const char *resource);
int  zxpoly_bridge_start(void);
int  zxpoly_bridge_open_file(const char *path);
const char *zxpoly_bridge_run_frame(void);
int  zxpoly_bridge_set_recolour(int enabled);
const uint32_t *zxpoly_bridge_get_framebuffer(int32_t *w, int32_t *h);
int64_t zxpoly_bridge_frame_counter(void);
int  zxpoly_bridge_recolour_now(void);
void zxpoly_bridge_stop(void);
const char *zxpoly_bridge_last_error(void);

}  // extern C

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s game.tap [frames]\n", argv[0]);
        return 1;
    }
    const char *path = argv[1];
    int frames = (argc > 2) ? std::atoi(argv[2]) : 300;

    void *h = dlopen("libzxpolycore.so", RTLD_NOW);
    if (!h) {
        std::fprintf(stderr, "dlopen libzxpolycore.so: %s\n", dlerror());
        std::fprintf(stderr,
            "(run from native/zxpoly_bridge/linux/out/, "
            "or set LD_LIBRARY_PATH to point there)\n");
        return 1;
    }

    auto init  = (int  (*)(const char *, const char *))         dlsym(h, "zxpoly_bridge_init");
    auto start = (int  (*)())                                    dlsym(h, "zxpoly_bridge_start");
    auto open  = (int  (*)(const char *))                       dlsym(h, "zxpoly_bridge_open_file");
    auto step  = (const char *(*)())                            dlsym(h, "zxpoly_bridge_run_frame");
    auto setR  = (int  (*)(int))                                dlsym(h, "zxpoly_bridge_set_recolour");
    auto fb    = (const uint32_t *(*)(int32_t *, int32_t *))    dlsym(h, "zxpoly_bridge_get_framebuffer");
    auto cnt   = (int64_t(*)())                                  dlsym(h, "zxpoly_bridge_frame_counter");
    auto recol = (int  (*)())                                    dlsym(h, "zxpoly_bridge_recolour_now");
    auto stop  = (void(*)())                                     dlsym(h, "zxpoly_bridge_stop");
    auto err_  = (const char *(*)())                             dlsym(h, "zxpoly_bridge_last_error");
    if (!init || !start || !open || !step || !fb || !cnt || !stop) {
        std::fprintf(stderr, "dlsym: missing symbol(s)\n");
        return 1;
    }

    std::printf("[init] booting JVM...\n");
    if (init("/tmp/zxpoly-smoke-profile", "/tmp/zxpoly-smoke-resource") != 0) {
        std::fprintf(stderr, "[init] failed: %s\n", err_ ? err_() : "(no message)");
        return 1;
    }
    std::printf("[init] ok\n");

    if (setR) setR(1);
    if (start() != 0) { std::fprintf(stderr, "[start] failed\n"); return 1; }

    std::printf("[open] %s\n", path);
    int rc = open(path);
    std::printf("[open] rc=%d\n", rc);
    if (rc != 0) return 1;

    std::printf("[step] running %d frames...\n", frames);
    uint64_t last_hash = 0;
    for (int i = 0; i < frames; ++i) {
        const char *err = step();
        if (err) {
            std::printf("[step] frame %d: error '%s'\n", i, err);
            break;
        }
        // Hash the framebuffer every 30 frames so we can see whether
        // the screen is changing.
        if (i % 30 == 0) {
            int32_t w = 0, h = 0;
            const uint32_t *px = fb(&w, &h);
            uint64_t h_ = 0;
            if (px && w > 0 && h > 0) {
                for (int j = 0; j < w * h; j += 17) {
                    h_ = h_ * 31 + px[j];
                }
            }
            if (h_ != last_hash) {
                last_hash = h_;
                std::printf("[step] frame %d: fb %dx%d hash=%016lx\n",
                            i, w, h, (unsigned long) h_);
            }
        }
    }

    std::printf("[step] final frame counter = %lld\n", (long long) cnt());

    if (recol) {
        std::printf("[recolour] calling recolour_now()\n");
        int rc = recol();
        std::printf("[recolour] rc=%d\n", rc);
    }

    if (stop) stop();
    dlclose(h);
    return 0;
}
