/*
 * audio_backend_android.cpp - AAudio sink placeholder.
 *
 * Phase 2 wires AAudio here, mirroring the AAudio path the previous
 * speccy_core/android build used. Until then this is a no-op so the
 * library links and the JVM-side audio path can hand bytes to it.
 *
 * Diagnostic logging uses fprintf rather than android/log.h so the
 * file compiles cleanly on a Linux host (where clangd parses it for
 * tooling) and on the Android NDK alike. The real release build will
 * route the AAudio path through __android_log_print directly.
 */
#include "audio_backend.h"

#include <cstdio>

extern "C" void audio_backend_init(void) {
    std::fputs("zxpoly.audio: audio_backend_init (stub)\n", stderr);
}

extern "C" void audio_backend_shutdown(void) {
    std::fputs("zxpoly.audio: audio_backend_shutdown (stub)\n", stderr);
}

extern "C" void audio_backend_set_sample_rate(int rate) {
    std::fprintf(stderr, "zxpoly.audio: audio_backend_set_sample_rate %d (stub)\n", rate);
}
