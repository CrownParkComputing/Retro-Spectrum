/*
 * audio_backend_android.cpp — AAudio output for the Speccy bridge.
 *
 * The data callback drains the core directly. Because speccy_core_drain_audio
 * is a pull API there is no ring buffer here and no writer thread: AAudio
 * asks for N frames on its own high-priority callback thread and the core
 * fills them. Fewer moving parts than the Saturn and C64 backends, which
 * have to buffer because their cores push.
 *
 * A short buffer underrun is normal at load time -- the Z80 is busy decoding
 * a tape and not mixing much -- so a short read is padded with silence
 * rather than treated as an error. Stopping the stream on the first hiccup
 * would silence the whole session.
 */
#include "audio_backend.h"
#include "speccy_bridge.h"

#include <aaudio/AAudio.h>
#include <atomic>
#include <string.h>

namespace {

AAudioStream *g_stream = nullptr;
std::atomic<bool> g_muted{false};

aaudio_data_callback_result_t on_data(AAudioStream *, void *,
                                      void *audio_data, int32_t num_frames)
{
    /* int16 stereo: two channels, two bytes each. */
    const int32_t wanted = num_frames * 2 * (int32_t)sizeof(int16_t);

    if (g_muted.load(std::memory_order_relaxed)) {
        memset(audio_data, 0, (size_t)wanted);
        /* Drained anyway, so a muted stretch does not come back as a
         * backlog of stale samples the moment sound is turned on again. */
        static int16_t sink[4096];
        int32_t left = wanted;
        while (left > 0) {
            const int32_t chunk = left < (int32_t)sizeof(sink) ? left : (int32_t)sizeof(sink);
            const int32_t got = speccy_core_drain_audio(sink, chunk);
            if (got <= 0) break;
            left -= got;
        }
        return AAUDIO_CALLBACK_RESULT_CONTINUE;
    }

    const int32_t got = speccy_core_drain_audio(audio_data, wanted);
    if (got < wanted) {
        /* Silence for the rest. See the note above: underruns are expected
         * while a tape is loading. */
        memset((uint8_t *)audio_data + (got > 0 ? got : 0), 0,
               (size_t)(wanted - (got > 0 ? got : 0)));
    }
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

} // namespace

extern "C" {

int32_t speccy_audio_start(int32_t sample_rate)
{
    if (g_stream) return 0;

    AAudioStreamBuilder *builder = nullptr;
    if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK || !builder) {
        return -1;
    }

    AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setSampleRate(builder, sample_rate);
    AAudioStreamBuilder_setChannelCount(builder, 2);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
    /* LowLatency with an Exclusive stream where the device allows it: this
     * is a game, and audio arriving late is worse than audio arriving
     * imperfectly. Android falls back to Shared on its own if it must. */
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setDataCallback(builder, on_data, nullptr);

    AAudioStream *stream = nullptr;
    const aaudio_result_t rc = AAudioStreamBuilder_openStream(builder, &stream);
    AAudioStreamBuilder_delete(builder);
    if (rc != AAUDIO_OK || !stream) return -2;

    if (AAudioStream_requestStart(stream) != AAUDIO_OK) {
        AAudioStream_close(stream);
        return -3;
    }

    g_stream = stream;
    return 0;
}

void speccy_audio_stop(void)
{
    AAudioStream *stream = g_stream;
    if (!stream) return;
    g_stream = nullptr;
    /* Stop before close so the callback is not running as the stream is
     * torn down under it. */
    AAudioStream_requestStop(stream);
    AAudioStream_close(stream);
}

void speccy_audio_set_muted(int32_t muted)
{
    g_muted.store(muted != 0, std::memory_order_relaxed);
}

}
