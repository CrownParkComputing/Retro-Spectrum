/*
 * audio_backend_stub.cpp — Silence.
 *
 * For the Linux host build and the headless tests, which have no device to
 * open and no reason to want one: the core still mixes, and
 * speccy_core_get_audio_level still reports, so anything that checks the
 * emulator is producing sound works without a sound card being present.
 */
#include "audio_backend.h"

extern "C" {

int32_t speccy_audio_start(int32_t) { return 0; }
void speccy_audio_stop(void) {}
void speccy_audio_set_muted(int32_t) {}

}
