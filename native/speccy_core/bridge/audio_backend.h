/*
 * audio_backend.h — Sound output for the Speccy bridge.
 *
 * Pull, not push: speccy_core_drain_audio is the core's own shape (as
 * Emulator.UpdateAudio and sdl2_audio.cpp both use it), so the platform
 * device asks the core for samples when it needs them rather than the core
 * pushing into a ring the backend owns. That removes a buffer and a thread
 * compared with the Saturn and C64 bridges, which are push-shaped because
 * their cores hand samples out from their own audio threads.
 *
 * Implemented per platform:
 *   audio_backend_android.cpp — AAudio
 *   audio_backend_stub.cpp    — silence, for headless builds and tests
 */
#ifndef SPECCY_AUDIO_BACKEND_H
#define SPECCY_AUDIO_BACKEND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opens the device at `sample_rate` Hz, 16-bit stereo. Returns 0 on
 * success. Safe to call twice; the second call is a no-op. */
int32_t speccy_audio_start(int32_t sample_rate);

/* Closes the device. Safe to call when not started.
 *
 * This matters more than it looks: an open output stream holds an AudioMix
 * wake lock for as long as it exists, which keeps the CPU awake even when
 * nothing is playing. Pausing is not enough -- see the same bug and fix in
 * Retro-Amiga's music_player. */
void speccy_audio_stop(void);

/* Silences output without closing the device, for pause. */
void speccy_audio_set_muted(int32_t muted);

#ifdef __cplusplus
}
#endif

#endif /* SPECCY_AUDIO_BACKEND_H */
