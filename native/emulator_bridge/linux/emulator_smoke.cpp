// emulator_smoke.cpp -- drive the ZEsarUX-backed bridge directly,
// no Flutter. Same shape as native/zxpoly_bridge/linux/zxpoly_smoke.cpp.
//
//   ./emulator_smoke /home/jon/games/spectrum/Alien8.tap 600
//
// Loads the file into a freshly-spawned ZEsarUX, runs N frames,
// and reports whether the framebuffer changes between polls.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

extern "C" {

int  zxpoly_bridge_init(const char *profile, const char *resource);
int  zxpoly_bridge_start(void);
int  zxpoly_bridge_open_file(const char *path);
const char *zxpoly_bridge_run_frame(void);
const uint32_t *zxpoly_bridge_get_framebuffer(int32_t *w, int32_t *h);
int64_t zxpoly_bridge_frame_counter(void);
const char *zxpoly_bridge_last_error(void);
int  zxpoly_bridge_stop(void);
void zxpoly_bridge_dispose(void);

}  // extern C

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s game.tap [frames]\n", argv[0]);
        return 1;
    }
    const char *path = argv[1];
    int frames = (argc > 2) ? std::atoi(argv[2]) : 300;

    std::printf("[init] booting ZEsarUX subprocess...\n");
    if (zxpoly_bridge_init("/tmp/retro-spectrum-profile",
                           "/tmp/retro-spectrum-resource") != 0) {
        std::fprintf(stderr, "[init] failed: %s\n",
                     zxpoly_bridge_last_error());
        return 2;
    }
    std::printf("[init] ok\n");

    if (zxpoly_bridge_start() != 0) {
        std::fprintf(stderr, "[start] failed\n");
        return 3;
    }

    std::printf("[open] %s\n", path);
    int rc = zxpoly_bridge_open_file(path);
    std::printf("[open] rc=%d\n", rc);
    if (rc != 0) return 4;

    std::printf("[step] running %d frames...\n", frames);
    uint64_t last_hash = 0;
    for (int i = 0; i < frames; ++i) {
        const char *err = zxpoly_bridge_run_frame();
        if (err) {
            std::printf("[step] frame %d: error '%s'\n", i, err);
            break;
        }
        if (i % 30 == 0) {
            int32_t w = 0, h = 0;
            const uint32_t *px = zxpoly_bridge_get_framebuffer(&w, &h);
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

    std::printf("[step] final frame counter = %lld\n",
                (long long) zxpoly_bridge_frame_counter());

    zxpoly_bridge_dispose();
    return 0;
}
