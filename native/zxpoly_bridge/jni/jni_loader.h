/*
 * jni_loader.h - C++ wrapper that hosts the raydac/zxpoly engine.
 *
 * The bridge has no C++ emulation logic of its own; every entry point
 * in bridge/zxpoly_bridge.cpp calls into this class, which holds the
 * loaded JVM and the cached class/method references for the zxpoly
 * classes the bridge actually uses.
 *
 * The JNI types (JavaVM*, JNIEnv*, jclass, jobject) are hidden behind
 * opaque void* in this header so the file compiles on hosts that
 * don't have a JDK or NDK in their include path. The real types are
 * recovered inside jni_loader.cpp, which is the only TU that pulls
 * in <jni.h>.
 *
 * Phase 2 status (this commit): skeleton. The class cache is
 * populated for every zxpoly class the bridge is expected to touch,
 * but most method bodies still throw `jni_pending_error` -- the
 * bridge returns ZXPOLY_ERR_NOTIMPL for everything except lifecycle
 * setters and the recolour flag until each JNI call lands in a
 * follow-up commit.
 *
 * The classes we cache (all in com.igormaznitsa.zxpoly.*):
 *
 *   Motherboard                    -- the machine; step() is the only
 *                                     per-frame primitive; no runFrame()
 *   VideoController                -- framebuffer; 512x384 in ZX-Poly
 *                                     mode, 256x192 in standard mode
 *   Beeper                         -- audio mixer; SndBufferContainer
 *                                     carries the AudioFormat and the
 *                                     sample buffer
 *   KeyboardKempstonAndTapeIn      -- ZXKEY_* constants; row-major keys
 *   KempstonMouse                  -- joystick input
 *   TapeSourceFactory              -- tape loading (read paths)
 *   RomData                        -- ROM images
 *
 * The phase 2.2 commit fills in the JNI method bodies; 2.3 wires the
 * auto-recolour preprocess on top.
 */
#ifndef RETRO_SPECTRUM_ZXPOLY_JNI_LOADER_H
#define RETRO_SPECTRUM_ZXPOLY_JNI_LOADER_H

#include <atomic>
#include <cstdint>
#include <string>

namespace retro::zxpoly {

/** Where the bridge expects to find zxpoly.jar at runtime.
 *  On Android the Gradle build drops it into jniLibs/<abi>/zxpoly.jar
 *  and the runtime classpath is set in start(); on Linux the JVM is
 *  launched with -Djava.class.path=... pointing at the Maven output. */
struct JvmLaunchOptions {
    std::string class_path;        // path(s) to zxpoly.jar
    int heap_mb = 256;             // -Xmx
    bool verbose = false;          // -verbose:class,jni
};

/** Snapshot of a single fetched frame from the JVM.
 *  The buffer is borrowed from the JVM and only valid until the next
 *  step() call; copy it before crossing any thread boundary. */
struct FrameBuffer {
    int32_t width = 0;
    int32_t height = 0;
    int32_t stride = 0;            // pixels per row (>= width)
    const uint8_t *pixels = nullptr;  // RGBA8888, top-down
};

/** Snapshot of the audio buffer the JVM has queued for us.
 *  Borrowed like FrameBuffer; copy before the next step() call. */
struct AudioBuffer {
    int sample_rate = 0;
    int channels = 0;
    int bytes_per_sample = 0;
    int frames = 0;
    const uint8_t *samples = nullptr;
};

/** One-stop wrapper over the JVM. Singleton; the bridge owns it. */
class JniLoader {
public:
    JniLoader();
    ~JniLoader();

    int start(const JvmLaunchOptions &opts);
    void stop();

    bool ready() const { return ready_.load(); }

    int create_motherboard(int sample_rate);
    int open_file(const char *path);
    const char *step_frame(FrameBuffer *out_frame, AudioBuffer *out_audio);
    int key_event(int key, int flags);
    int kempston(int mask);
    int get_framebuffer(FrameBuffer *out);
    int drain_audio(uint8_t *dst, int max_bytes);
    int set_sample_rate(int rate);
    int reset();
    int set_paused(bool paused);
    int set_rom(int slot, const uint8_t *data, int size);

    int set_recolour(bool enabled);
    bool recolour() const { return recolour_.load(); }

    const std::string &last_error() const { return last_error_; }

private:
    /** Lazily look up (and cache) a jclass by FQN. Returns null if
     *  the JVM cannot resolve the class. The real type of the
     *  returned handle is jclass, hidden as void* here so the header
     *  compiles without <jni.h>. */
    void *find_class(const char *fqcn);

    /** If a JNI exception is pending, capture the message in
     *  last_error_, clear the exception, return ZXPOLY_ERR_GENERIC.
     *  Otherwise return ZXPOLY_OK. */
    int check_exception(const char *context);

private:
    /** Opaque handles. Inside jni_loader.cpp these recover the real
     *  JNI types (JavaVM*, JNIEnv*, jclass, jobject). Hidden in the
     *  header so the file compiles without <jni.h> in the include
     *  path -- the bridge builds on a Linux host that has neither
     *  JDK nor NDK available, and only the Android / Linux-JDK
     *  builds actually link the JNI side. */
    void *jvm_ = nullptr;
    void *env_ = nullptr;
    void *cls_motherboard_ = nullptr;
    void *cls_video_ = nullptr;
    void *cls_audio_format_ = nullptr;
    void *cls_snd_buffer_ = nullptr;
    void *cls_keyboard_ = nullptr;
    void *cls_kempston_mouse_ = nullptr;
    void *cls_tape_factory_ = nullptr;
    void *cls_rom_data_ = nullptr;
    void *motherboard_ = nullptr;

    std::atomic<bool> ready_{false};
    std::atomic<bool> paused_{false};
    std::atomic<bool> recolour_{true};
    int sample_rate_ = 44100;
    std::string last_error_;

    /** Cached jfieldID for KeyboardKempstonAndTapeIn.keyboardLines (J),
     *  obtained via reflection at create_motherboard time. There is no
     *  public setter on KeyboardKempstonAndTapeIn -- it is driven by
     *  the Swing UI -- so the bridge writes through reflection. */
    void *keyboard_lines_field_ = nullptr;

    /** Cached jfieldID for KempstonMouse.kempstonSignals (I). */
    void *kempston_signals_field_ = nullptr;

    /** ZX-Poly mode runs at 69888 t-states per 50 Hz frame. The
     *  bridge keeps a running accumulator; on every step_frame call
     *  we drive Motherboard.step() with the right interrupt flags
     *  for the slice of t-states being executed. */
    int tstates_in_frame_ = 0;
    int frame_chunk_ = 69888 / 50;   // ~1398 t-states per 50 Hz step
};

} // namespace retro::zxpoly

#endif /* RETRO_SPECTRUM_ZXPOLY_JNI_LOADER_H */
