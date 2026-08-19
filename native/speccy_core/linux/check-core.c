/*
 * check-core.c - proves libspeccycore.so works with nothing else involved.
 *
 * dlopens the bridge exactly as a Flutter host will, boots the core, runs
 * frames and asserts the framebuffer is real. This is the gate before any
 * Dart is written: DosboxMultiplatform shipped a complete Flutter UI over a
 * stub core, and this exists so that cannot happen here.
 *
 * Every check below is something that would otherwise cost a device
 * round-trip to discover.
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "speccy_bridge.h"

static void *lib = NULL;
static int failures = 0;

#define SYM(name) \
    do { \
        *(void **)(&p_##name) = dlsym(lib, #name); \
        if(!p_##name) { fprintf(stderr, "FAIL: missing export %s\n", #name); exit(1); } \
    } while(0)

#define CHECK(cond, msg) \
    do { \
        if(cond) { printf("  ok   %s\n", msg); } \
        else { printf("  FAIL %s\n", msg); ++failures; } \
    } while(0)

static void (*p_speccy_core_init)(const char *, const char *);
static void (*p_speccy_core_set_rom)(int32_t, const void *, int32_t);
static void (*p_speccy_core_set_font)(const void *, int32_t);
static int32_t (*p_speccy_core_start)(void);
static void (*p_speccy_core_stop)(void);
static int32_t (*p_speccy_core_is_running)(void);
static const char *(*p_speccy_core_run_frame)(void);
static const uint32_t *(*p_speccy_core_get_framebuffer)(int32_t *, int32_t *);
static int32_t (*p_speccy_core_get_frame_counter)(void);
static int32_t (*p_speccy_core_drain_audio)(void *, int32_t);
static void (*p_speccy_core_key_event)(int32_t, int32_t);
static int32_t (*p_speccy_core_file_type_supported)(const char *);
static int32_t (*p_speccy_core_open_file)(const char *);
static void (*p_speccy_core_reset)(void);
static int32_t (*p_speccy_core_save_state)(const char *);
static int32_t (*p_speccy_core_load_state)(const char *);
static int32_t (*p_speccy_core_tape_state)(void);

/* Load one ROM file into the core. Returns 0 on success. */
static int load_rom(const char *dir, const char *name, int id)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", dir, name);
    FILE *f = fopen(path, "rb");
    if(!f) { fprintf(stderr, "  (cannot open %s)\n", path); return -1; }
    static unsigned char buf[16384];
    size_t n = fread(buf, 1, sizeof(buf), f);
    fclose(f);
    p_speccy_core_set_rom(id, buf, (int32_t)n);
    return 0;
}

int main(int argc, char **argv)
{
    const char *so = argc > 1 ? argv[1] : "./libspeccycore.so";
    const char *res_dir = argc > 2 ? argv[2] : NULL;
    const char *media = argc > 3 ? argv[3] : NULL;

    lib = dlopen(so, RTLD_NOW);
    if(!lib) { fprintf(stderr, "FAIL: dlopen %s: %s\n", so, dlerror()); return 1; }
    printf("dlopen %s ok\n", so);

    SYM(speccy_core_init);
    SYM(speccy_core_set_rom);
    SYM(speccy_core_set_font);
    SYM(speccy_core_start);
    SYM(speccy_core_stop);
    SYM(speccy_core_is_running);
    SYM(speccy_core_run_frame);
    SYM(speccy_core_get_framebuffer);
    SYM(speccy_core_get_frame_counter);
    SYM(speccy_core_drain_audio);
    SYM(speccy_core_key_event);
    SYM(speccy_core_file_type_supported);
    SYM(speccy_core_open_file);
    SYM(speccy_core_reset);
    SYM(speccy_core_save_state);
    SYM(speccy_core_load_state);
    SYM(speccy_core_tape_state);
    printf("all exports resolved\n");

    printf("\n[scenario] boot\n");
    p_speccy_core_init("/tmp/retro-spectrum-check", res_dir ? res_dir : "");
    if(res_dir)
    {
        char rp[1024];
        snprintf(rp, sizeof(rp), "%s/rom", res_dir);
        load_rom(rp, "sos128_0.rom", SPECCY_ROM_SOS128_0);
        load_rom(rp, "sos128_1.rom", SPECCY_ROM_SOS128_1);
        load_rom(rp, "sos48.rom",    SPECCY_ROM_SOS48);
        load_rom(rp, "service.rom",  SPECCY_ROM_SERVICE);
        load_rom(rp, "dos513f.rom",  SPECCY_ROM_DOS);
    }
    CHECK(p_speccy_core_start() == 0, "core starts");
    CHECK(p_speccy_core_is_running() == 1, "reports running");

    printf("\n[scenario] frames advance\n");
    const char *err = NULL;
    for(int i = 0; i < 100; ++i)
    {
        err = p_speccy_core_run_frame();
        if(err) { printf("  run_frame returned '%s' at frame %d\n", err, i); break; }
    }
    CHECK(err == NULL, "100 frames with no error");
    CHECK(p_speccy_core_get_frame_counter() == 100, "frame counter advanced to 100");

    printf("\n[scenario] framebuffer is real\n");
    int32_t w = 0, h = 0;
    const uint32_t *fb = p_speccy_core_get_framebuffer(&w, &h);
    CHECK(fb != NULL, "framebuffer non-NULL");
    CHECK(w == SPECCY_SCREEN_WIDTH && h == SPECCY_SCREEN_HEIGHT, "dimensions are 320x240");

    /* The ROM boot screen must produce more than one colour. A single flat
     * colour means the core ran but rendered nothing -- the exact failure a
     * stub core hides. */
    int distinct = 0;
    uint32_t seen[16];
    for(int i = 0; i < w * h; ++i)
    {
        int known = 0;
        for(int j = 0; j < distinct; ++j)
            if(seen[j] == fb[i]) { known = 1; break; }
        if(!known && distinct < 16) seen[distinct++] = fb[i];
    }
    printf("  (%d distinct colours in frame)\n", distinct);
    CHECK(distinct > 1, "frame is not a flat fill");

    /* Alpha must be opaque or a Flutter host draws an invisible screen. */
    CHECK((fb[0] & 0xff000000u) == 0xff000000u, "alpha channel is opaque");

    printf("\n[scenario] audio drains\n");
    static unsigned char abuf[65536];
    int total = 0;
    for(int i = 0; i < 50; ++i)
    {
        p_speccy_core_run_frame();
        total += p_speccy_core_drain_audio(abuf, sizeof(abuf));
    }
    printf("  (%d bytes over 50 frames)\n", total);
    CHECK(total > 0, "audio produced bytes");

    printf("\n[scenario] media\n");
    CHECK(p_speccy_core_file_type_supported("game.tap") == 1, "tap recognised");
    CHECK(p_speccy_core_file_type_supported("game.z80") == 1, "z80 recognised");
    CHECK(p_speccy_core_file_type_supported("game.xyz") == 0, "unknown ext rejected");
    if(media)
    {
        CHECK(p_speccy_core_open_file(media) == 0, "opens supplied media");
        for(int i = 0; i < 200; ++i) p_speccy_core_run_frame();
        CHECK(p_speccy_core_run_frame() == NULL, "still running after load");
    }

    printf("\n[scenario] save state\n");
    /* .sna only: eFileTypeSNA is the one file type overriding Store(), so a
     * .z80 path silently fails. That cost a debugging session to find. */
    CHECK(p_speccy_core_save_state("/tmp/retro-spectrum-check/state.z80") == -1,
          ".z80 save correctly refused (load-only format)");
    CHECK(p_speccy_core_save_state("/tmp/retro-spectrum-check/state.sna") == 0,
          ".sna save succeeds");
    CHECK(p_speccy_core_load_state("/tmp/retro-spectrum-check/state.sna") == 0,
          ".sna load succeeds");
    CHECK(p_speccy_core_run_frame() == NULL, "runs after state load");
    CHECK(p_speccy_core_tape_state() == -1, "no tape reported when none inserted");

    printf("\n[scenario] reset and restart\n");
    p_speccy_core_reset();
    CHECK(p_speccy_core_run_frame() == NULL, "runs after reset");
    p_speccy_core_stop();
    CHECK(p_speccy_core_is_running() == 0, "stops cleanly");
    CHECK(p_speccy_core_start() == 0, "restarts in the same process");
    p_speccy_core_stop();

    printf("\n%s (%d failure%s)\n", failures ? "FAILED" : "PASSED",
           failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
