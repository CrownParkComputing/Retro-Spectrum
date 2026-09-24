/*
 * audio_backend.h - engine-agnostic audio sink.
 *
 * The previous build over UnrealSpeccyPortable had the same three
 * functions; the bridge handed the engine's audio buffer through
 * unchanged. The swap to zxpoly doesn't touch this layer — audio
 * still comes out of the JVM as a byte stream, the AAudio sink on
 * Android and the SDL2/Pulse sink on Linux still apply.
 */
#ifndef RETRO_SPECTRUM_AUDIO_BACKEND_H
#define RETRO_SPECTRUM_AUDIO_BACKEND_H

#ifdef __cplusplus
extern "C" {
#endif

void audio_backend_init(void);
void audio_backend_shutdown(void);
void audio_backend_set_sample_rate(int rate);

#ifdef __cplusplus
}
#endif

#endif /* RETRO_SPECTRUM_AUDIO_BACKEND_H */
