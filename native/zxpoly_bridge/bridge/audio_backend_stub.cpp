/*
 * audio_backend_stub.cpp - the host-side fallback when no platform
 * audio sink is linked (Linux headless tests, CI gates). Same shape
 * the previous build used; unchanged by the zxpoly swap.
 */
#include "audio_backend.h"

#include <cstdio>

extern "C" void audio_backend_init(void) {
    std::fputs("audio_backend_init (stub)\n", stderr);
}

extern "C" void audio_backend_shutdown(void) {
    std::fputs("audio_backend_shutdown (stub)\n", stderr);
}

extern "C" void audio_backend_set_sample_rate(int rate) {
    std::fprintf(stderr, "audio_backend_set_sample_rate %d (stub)\n", rate);
}
