/*
 * zxpoly_bridge.h - Plain-C ABI for the raydac/zxpoly engine.
 *
 * No JNI in this header. Callable from dart:ffi on Android, iOS, Linux.
 * Modelled on the 40 entry points in the old speccy_bridge.h, plus
 * the new recolour API:
 *
 *   int zxpoly_bridge_set_recolour(int enabled);
 *   int zxpoly_bridge_get_recolour(void);
 *
 * Default on. Per-game toggle in the UI maps to set_recolour before
 * zxpoly_bridge_open_file(). The recolour preprocess runs synchronously
 * inside open_file when recolour is on; the first presented frame is
 * already the full-colour version. See docs/zxpoly-swap.md.
 *
 * Phase 2 note: every function here currently returns ZXPOLY_ERR_NOTIMPL
 * until the JNI side lands. The header is the contract; the cpp is the
 * stub. Both Flutter UI and CI can build against this today.
 */
#ifndef RETRO_SPECTRUM_ZXPOLY_BRIDGE_H
#define RETRO_SPECTRUM_ZXPOLY_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Error codes — every function returning int32 returns one of these.
 * 0 is the only success code; the rest are negative. */
#define ZXPOLY_OK              0
#define ZXPOLY_ERR_GENERIC    -1   /* unspecified failure */
#define ZXPOLY_ERR_NOTIMPL    -2   /* phase 2 stub */
#define ZXPOLY_ERR_BADARG     -3   /* null pointer, bad enum, etc. */
#define ZXPOLY_ERR_NOMEM      -4
#define ZXPOLY_ERR_NOFILE     -5   /* media file not found / unreadable */
#define ZXPOLY_ERR_BADFILE    -6   /* media file present but not a recognised format */
#define ZXPOLY_ERR_NOROM      -7   /* ROM slot unset when required */

/* The framebuffer is 4-bit-per-pixel (4 parallel VRAMs combine into a
 * single index) rendered to RGBA8888 by the bridge, exactly the same
 * conversion the old speccy_bridge_get_framebuffer did. The Dart side
 * decodes RGBA8888 directly via ui.decodeImageFromPixels. */
#define ZXPOLY_SCREEN_WIDTH   320
#define ZXPOLY_SCREEN_HEIGHT  240

/* ---- Lifecycle ------------------------------------------------------- */

int  zxpoly_bridge_init(const char *profile_dir, const char *resource_dir);
int  zxpoly_bridge_start(void);
int  zxpoly_bridge_stop(void);
int  zxpoly_bridge_dispose(void);

/* ---- ROM / font ------------------------------------------------------ */

/* ZX-Spectrum 48K and 128K ROMs. The ids are pinned to the order
 * zxpoly expects; do not renumber. */
typedef enum {
    ZXPOLY_ROM_SOS128_0 = 0,
    ZXPOLY_ROM_SOS128_1 = 1,
    ZXPOLY_ROM_SOS48    = 2,
    ZXPOLY_ROM_SERVICE  = 3,
    ZXPOLY_ROM_DOS      = 4,
} ZxpolyRom;

int  zxpoly_bridge_set_rom(ZxpolyRom rom, const uint8_t *data, int32_t size);
int  zxpoly_bridge_set_font(const uint8_t *data, int32_t size);

/* ---- Auto-recolour --------------------------------------------------- */

/* The whole point of this swap. 1 = run the recolour preprocess on
 * open_file; 0 = run the original graphics unmodified. Default 1.
 * Per-game toggle in the UI calls this before open_file. */
int  zxpoly_bridge_set_recolour(int enabled);
int  zxpoly_bridge_get_recolour(void);

/* Run the recolour preprocess against the currently-loaded game
 * state. The Dart UI calls this after the loader has populated the
 * screen -- .tap loading is multi-second and the recolour algorithm
 * needs the loaded memory map. Returns 0 on success or a negative
 * ZXPOLY_ERR_*. Until the JNI side is implemented, returns
 * ZXPOLY_ERR_NOTIMPL. */
int  zxpoly_bridge_recolour_now(void);

/* Last error message, or empty string. Stable across calls; the
 * underlying buffer is owned by the bridge. */
const char *zxpoly_bridge_last_error(void);

/* ---- Frame / emulation ----------------------------------------------- */

/* Advance one frame. Returns null on success, otherwise a static
 * error string the Dart side surfaces to the user. */
const char *zxpoly_bridge_run_frame(void);
int  zxpoly_bridge_reset(void);
int  zxpoly_bridge_set_paused(int paused);
int  zxpoly_bridge_is_running(void);

/* Returns a pointer to the most-recent framebuffer in RGBA8888.
 * out_w / out_h receive the dimensions (always ZXPOLY_SCREEN_WIDTH /
 * HEIGHT today, but the API exposes them so a future zxpoly mode
 * can change them). The pointer is owned by the bridge; do not free. */
const uint32_t *zxpoly_bridge_get_framebuffer(int32_t *out_w, int32_t *out_h);
int64_t zxpoly_bridge_frame_counter(void);

/* ---- Audio ----------------------------------------------------------- */

/* Drain audio into the caller's buffer. Returns the number of bytes
 * actually written, or a negative error. */
int  zxpoly_bridge_drain_audio(uint8_t *dst, int32_t max_bytes);
int  zxpoly_bridge_set_sample_rate(int32_t rate);
int  zxpoly_bridge_audio_level(void);

/* ---- Input ----------------------------------------------------------- */

/* Keyboard event. flags: 0 = press, 1 = release (mirrors the old
 * speccy_bridge_key_event). The keycode is a row-major Spectrum matrix
 * index; the Dart side translates from logical keys. */
int  zxpoly_bridge_key_event(int32_t key, int32_t flags);
int  zxpoly_bridge_kempston(int32_t mask);

/* ---- Media ----------------------------------------------------------- */

/* True if the file extension / magic suggests a known type. Cheap. */
int  zxpoly_bridge_file_type_supported(const char *name);

/* Open a tape / snapshot / cartridge file from disk. Runs the recolour
 * preprocess synchronously when zxpoly_bridge_get_recolour() returns
 * non-zero. */
int  zxpoly_bridge_open_file(const char *path);

/* Open media that the Dart side has already loaded into memory
 * (downloaded blob, content URI, etc). */
int  zxpoly_bridge_open_data(const char *name, const uint8_t *data, int32_t size);

/* Save current media state back to disk (.z80/.sna format chosen by
 * the bridge based on what was opened). */
int  zxpoly_bridge_save_file(const char *path);

/* Tape / disk introspection. */
int  zxpoly_bridge_tape_state(void);
int  zxpoly_bridge_tape_toggle(void);
int  zxpoly_bridge_disk_changed(void);

/* ---- Save states ----------------------------------------------------- */

/* zxpoly has no serialise API today; both return ZXPOLY_ERR_NOTIMPL
 * until the upstream engine grows one. The save state format will be
 * four-CPU-state plus the four parallel VRAMs. */
int  zxpoly_bridge_save_state(const char *path);
int  zxpoly_bridge_load_state(const char *path);

/* ---- Options --------------------------------------------------------- */

int  zxpoly_bridge_get_option_int(const char *name, int32_t fallback);
int  zxpoly_bridge_set_option_int(const char *name, int32_t value);
int  zxpoly_bridge_get_option_bool(const char *name, int32_t fallback);
int  zxpoly_bridge_set_option_bool(const char *name, int32_t value);

#ifdef __cplusplus
}
#endif

#endif /* RETRO_SPECTRUM_ZXPOLY_BRIDGE_H */
