/*
 * zxpoly_bridge.cpp - the plain-C ABI the Dart side calls.
 *
 * Every entry delegates to the JniLoader singleton, which hosts the
 * JVM and owns the cached class refs. Phase 2 wires the JNI calls
 * one at a time; until each lands, JniLoader returns ZXPOLY_ERR_NOTIMPL
 * and the bridge propagates.
 *
 * The framebuffer path is the one place we have to copy out of the
 * JVM: dart:ffi reads the bytes via Pointer<Uint8> and the JVM-side
 * pointer is only valid for the current frame. We keep one
 * persistent RGBA8888 buffer (the bridge owns it) and hand Dart the
 * pointer.
 *
 * Lifecycle / recolour setters always return OK: those are local
 * state on the bridge and on the JniLoader, not JNI calls.
 */
#include "zxpoly_bridge.h"
#include "../jni/jni_loader.h"

#include <atomic>
#include <cstring>
#include <vector>

#include "audio_backend.h"

namespace {

retro::zxpoly::JniLoader &jvm() {
    static retro::zxpoly::JniLoader instance;
    return instance;
}

struct BridgeState {
    std::atomic<bool> running{false};
    std::atomic<int64_t> frame_counter{0};
    int sample_rate = 44100;
    int audio_level = 0;
    std::string last_open_path;

    // Last fetched framebuffer, copied out of the JVM. The pointer
    // is stable for the lifetime of the bridge.
    std::vector<uint32_t> pixels;
    int32_t fb_w = 0, fb_h = 0, fb_stride = 0;

    // Last fetched audio buffer. Likewise bridge-owned.
    std::vector<uint8_t> audio;
};

BridgeState &state() {
    static BridgeState s;
    return s;
}

retro::zxpoly::JvmLaunchOptions default_options() {
    retro::zxpoly::JvmLaunchOptions o;
    // The bridge does not know where zxpoly.jar lives at compile time.
    // The host process is expected to set ZXPOLY_JAR (a colon-
    // separated class path, same as -Djava.class.path) before the
    // bridge's first call. Fall back to the conventional Linux and
    // Android locations so dev builds work without configuration.
    const char *cp = std::getenv("ZXPOLY_JAR");
    if (cp && *cp) {
        o.class_path = cp;
    } else {
        o.class_path = "./zxpoly.jar";
    }
    const char *mx = std::getenv("ZXPOLY_HEAP_MB");
    if (mx && *mx) o.heap_mb = std::atoi(mx);
    return o;
}

} // namespace

/* ---- Lifecycle ------------------------------------------------------- */

extern "C" int zxpoly_bridge_init(const char *profile_dir,
                                  const char *resource_dir) {
    (void)profile_dir;
    (void)resource_dir;
    auto opts = default_options();
    int rc = jvm().start(opts);
    if (rc != ZXPOLY_OK) return rc;
    audio_backend_init();
    return jvm().create_motherboard(state().sample_rate);
}

extern "C" int zxpoly_bridge_start(void) {
    state().running = true;
    state().frame_counter = 0;
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_stop(void) {
    state().running = false;
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_dispose(void) {
    audio_backend_shutdown();
    jvm().stop();
    return ZXPOLY_OK;
}

/* ---- ROM / font ------------------------------------------------------ */

extern "C" int zxpoly_bridge_set_rom(ZxpolyRom rom, const uint8_t *data,
                                     int32_t size) {
    return jvm().set_rom(static_cast<int>(rom), data, size);
}

extern "C" int zxpoly_bridge_set_font(const uint8_t *data, int32_t size) {
    // ZX-Poly has no separate font slot; the system font comes from
    // the ROM image via set_rom(). Accept and ignore.
    (void)data;
    (void)size;
    return ZXPOLY_OK;
}

/* ---- Auto-recolour --------------------------------------------------- */

extern "C" int zxpoly_bridge_set_recolour(int enabled) {
    return jvm().set_recolour(enabled != 0);
}

extern "C" int zxpoly_bridge_get_recolour(void) {
    return jvm().recolour() ? 1 : 0;
}

/* ---- Frame / emulation ----------------------------------------------- */

extern "C" const char *zxpoly_bridge_run_frame(void) {
    if (!state().running.load()) return nullptr;

    retro::zxpoly::FrameBuffer fb{};
    retro::zxpoly::AudioBuffer ab{};
    const char *err = jvm().step_frame(&fb, &ab);
    if (err) return err;

    // Copy the framebuffer out of the JVM's borrow window. zxpoly is
    // 512x384 RGBA in ZX-Poly mode and 256x192 in standard mode; the
    // bridge keeps the most recent frame in a persistent vector.
    if (fb.pixels && fb.width > 0 && fb.height > 0) {
        state().fb_w = fb.width;
        state().fb_h = fb.height;
        state().fb_stride = fb.stride ? fb.stride : fb.width;
        const size_t px = static_cast<size_t>(fb.stride ? fb.stride : fb.width)
                        * static_cast<size_t>(fb.height);
        state().pixels.assign(
            reinterpret_cast<const uint32_t *>(fb.pixels),
            reinterpret_cast<const uint32_t *>(fb.pixels) + px);
    }

    if (ab.samples && ab.frames > 0) {
        const size_t bytes = static_cast<size_t>(ab.frames) *
                             static_cast<size_t>(ab.channels) *
                             static_cast<size_t>(ab.bytes_per_sample);
        state().audio.assign(ab.samples, ab.samples + bytes);
    }

    state().frame_counter.fetch_add(1);
    return nullptr;
}

extern "C" int zxpoly_bridge_reset(void) {
    return jvm().reset();
}

extern "C" int zxpoly_bridge_set_paused(int paused) {
    return jvm().set_paused(paused != 0);
}

extern "C" int zxpoly_bridge_is_running(void) {
    return state().running.load() ? 1 : 0;
}

extern "C" const uint32_t *zxpoly_bridge_get_framebuffer(int32_t *out_w,
                                                         int32_t *out_h) {
    if (out_w) *out_w = state().fb_w;
    if (out_h) *out_h = state().fb_h;
    if (state().pixels.empty()) return nullptr;
    return state().pixels.data();
}

extern "C" int64_t zxpoly_bridge_frame_counter(void) {
    return state().frame_counter.load();
}

/* ---- Audio ----------------------------------------------------------- */

extern "C" int zxpoly_bridge_drain_audio(uint8_t *dst, int32_t max_bytes) {
    if (!dst || max_bytes <= 0) return ZXPOLY_ERR_BADARG;
    return jvm().drain_audio(dst, max_bytes);
}

extern "C" int zxpoly_bridge_set_sample_rate(int32_t rate) {
    if (rate <= 0) return ZXPOLY_ERR_BADARG;
    state().sample_rate = rate;
    return jvm().set_sample_rate(rate);
}

extern "C" int zxpoly_bridge_audio_level(void) {
    return state().audio_level;
}

/* ---- Input ----------------------------------------------------------- */

extern "C" int zxpoly_bridge_key_event(int32_t key, int32_t flags) {
    return jvm().key_event(key, flags);
}

extern "C" int zxpoly_bridge_kempston(int32_t mask) {
    return jvm().kempston(mask);
}

/* ---- Media ----------------------------------------------------------- */

extern "C" int zxpoly_bridge_file_type_supported(const char *name) {
    if (!name) return 0;
    auto ends_with = [&](const char *suf) {
        const size_t n = std::strlen(name);
        const size_t m = std::strlen(suf);
        return n >= m &&
               std::equal(suf, suf + m, name + n - m,
                          [](char a, char b) {
                              return std::tolower(a) == std::tolower(b);
                          });
    };
    return ends_with(".tap") || ends_with(".tzx") ||
           ends_with(".z80") || ends_with(".sna") ||
           ends_with(".sze") || ends_with(".zxp") ||
           ends_with(".dsk") || ends_with(".trd");
}

extern "C" int zxpoly_bridge_open_file(const char *path) {
    if (!path) return ZXPOLY_ERR_BADARG;
    state().last_open_path = path;
    return jvm().open_file(path);
}

extern "C" int zxpoly_bridge_open_data(const char *name, const uint8_t *data,
                                       int32_t size) {
    // TODO phase 2.2: spool data to a temp file under profile_dir and
    // route through open_file. The Dart side uses this for downloaded
    // blobs that have not been written to disk yet.
    (void)name;
    (void)data;
    (void)size;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_save_file(const char *path) {
    (void)path;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_tape_state(void) {
    return 0;
}

extern "C" int zxpoly_bridge_tape_toggle(void) {
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_disk_changed(void) {
    return 0;
}

/* ---- Save states ----------------------------------------------------- */

extern "C" int zxpoly_bridge_save_state(const char *path) {
    (void)path;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_load_state(const char *path) {
    (void)path;
    return ZXPOLY_ERR_NOTIMPL;
}

/* ---- Options --------------------------------------------------------- */

extern "C" int zxpoly_bridge_get_option_int(const char *name,
                                            int32_t fallback) {
    (void)name;
    return fallback;
}

extern "C" int zxpoly_bridge_set_option_int(const char *name, int32_t value) {
    (void)name;
    (void)value;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_get_option_bool(const char *name,
                                             int32_t fallback) {
    (void)name;
    return fallback;
}

extern "C" int zxpoly_bridge_set_option_bool(const char *name, int32_t value) {
    (void)name;
    (void)value;
    return ZXPOLY_ERR_NOTIMPL;
}
