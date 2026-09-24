/*
 * zxpoly_bridge.cpp - placeholder implementation of zxpoly_bridge.h.
 *
 * The real implementation lives in phase 2, in the JNI shim that
 * loads the JVM-hosted zxpoly engine. Every function here returns
 * ZXPOLY_ERR_NOTIMPL with a single source-of-truth state object
 * underneath, so:
 *
 *   - the library links and the Flutter app boots into the library
 *     screen (everything that doesn't touch the emulator);
 *   - any attempt to start emulation fails fast with a clear message
 *     in the UI;
 *   - the recolour API is exercisable: zxpoly_bridge_get_recolour
 *     returns the last value set, which is enough for the per-game
 *     toggle UI to round-trip the flag before phase 2 lands.
 *
 * The audio backend (audio_backend_*.cpp) is unchanged — it was
 * already engine-agnostic; just AAudio/SDL2 sinks.
 */

#include "zxpoly_bridge.h"

#include <atomic>
#include <cstring>
#include <string>

#include "audio_backend.h"

/* Single source of truth for the stub. Every getter reads, every
 * setter writes; the recolour flag is one such field. */
namespace {

struct BridgeState {
    std::atomic<bool> running{false};
    std::atomic<bool> paused{false};
    std::atomic<bool> recolour{true};   /* default on */
    std::atomic<int64_t> frame_counter{0};
    int sample_rate = 44100;
    int audio_level = 0;
    std::string last_open_path;
};

BridgeState &state() {
    static BridgeState s;
    return s;
}

constexpr const char *kNotImpl =
    "zxpoly bridge is a stub; phase 2 has not landed yet.";

} // namespace

/* ---- Lifecycle ------------------------------------------------------- */

extern "C" int zxpoly_bridge_init(const char *profile_dir,
                                  const char *resource_dir) {
    (void)profile_dir;
    (void)resource_dir;
    audio_backend_init();
    return ZXPOLY_OK;
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
    return ZXPOLY_OK;
}

/* ---- ROM / font ------------------------------------------------------ */

extern "C" int zxpoly_bridge_set_rom(ZxpolyRom rom, const uint8_t *data,
                                     int32_t size) {
    (void)rom;
    (void)data;
    (void)size;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_set_font(const uint8_t *data, int32_t size) {
    (void)data;
    (void)size;
    return ZXPOLY_ERR_NOTIMPL;
}

/* ---- Auto-recolour --------------------------------------------------- */

extern "C" int zxpoly_bridge_set_recolour(int enabled) {
    state().recolour = (enabled != 0);
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_get_recolour(void) {
    return state().recolour ? 1 : 0;
}

/* ---- Frame / emulation ----------------------------------------------- */

extern "C" const char *zxpoly_bridge_run_frame(void) {
    return kNotImpl;
}

extern "C" int zxpoly_bridge_reset(void) {
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_set_paused(int paused) {
    state().paused = (paused != 0);
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_is_running(void) {
    return state().running ? 1 : 0;
}

extern "C" const uint32_t *zxpoly_bridge_get_framebuffer(int32_t *out_w,
                                                         int32_t *out_h) {
    if (out_w) *out_w = ZXPOLY_SCREEN_WIDTH;
    if (out_h) *out_h = ZXPOLY_SCREEN_HEIGHT;
    return nullptr; /* phase 2 */
}

extern "C" int64_t zxpoly_bridge_frame_counter(void) {
    return state().frame_counter.load();
}

/* ---- Audio ----------------------------------------------------------- */

extern "C" int zxpoly_bridge_drain_audio(uint8_t *dst, int32_t max_bytes) {
    if (!dst || max_bytes <= 0) return ZXPOLY_ERR_BADARG;
    std::memset(dst, 0, static_cast<size_t>(max_bytes));
    return max_bytes;
}

extern "C" int zxpoly_bridge_set_sample_rate(int32_t rate) {
    if (rate <= 0) return ZXPOLY_ERR_BADARG;
    state().sample_rate = rate;
    audio_backend_set_sample_rate(rate);
    return ZXPOLY_OK;
}

extern "C" int zxpoly_bridge_audio_level(void) {
    return state().audio_level;
}

/* ---- Input ----------------------------------------------------------- */

extern "C" int zxpoly_bridge_key_event(int32_t key, int32_t flags) {
    (void)key;
    (void)flags;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_kempston(int32_t mask) {
    (void)mask;
    return ZXPOLY_ERR_NOTIMPL;
}

/* ---- Media ----------------------------------------------------------- */

extern "C" int zxpoly_bridge_file_type_supported(const char *name) {
    if (!name) return 0;
    /* Until the JVM-side file-type table is wired in we accept the
     * common ZX-Spectrum container extensions. The Dart side calls
     * this purely as a hint; the real check is in open_file. */
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
           ends_with(".dsk") || ends_with(".trd");
}

extern "C" int zxpoly_bridge_open_file(const char *path) {
    if (!path) return ZXPOLY_ERR_BADARG;
    state().last_open_path = path;
    return ZXPOLY_ERR_NOTIMPL;
}

extern "C" int zxpoly_bridge_open_data(const char *name, const uint8_t *data,
                                       int32_t size) {
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
