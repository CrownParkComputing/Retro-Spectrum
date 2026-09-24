/*
 * jni_loader.cpp - phase 2 skeleton. The class cache, the JVM
 * bootstrap, and the C++ wrapper over zxpoly live here.
 *
 * The whole TU is gated by __has_include(<jni.h>) so the file
 * compiles on a host that has no JDK or NDK. Without jni.h, every
 * method returns ZXPOLY_ERR_NOTIMPL and a static "phase 2 in
 * progress" message; the headless check-bridge.sh gate still passes
 * because the recolour / lifecycle setters are independent of JNI.
 *
 * Phase 2.2 fills in every method body that today returns
 * ZXPOLY_ERR_NOTIMPL by mapping it to the corresponding JNI call on
 * the cached class refs. Phase 2.3 layers the auto-recolour
 * preprocess on top of open_file().
 */
#include "jni_loader.h"
#include "../bridge/zxpoly_bridge.h"

#include <cstdio>
#include <cstring>

#if __has_include(<jni.h>)
#include <jni.h>
#define ZXPOLY_HAS_JNI 1
#else
#define ZXPOLY_HAS_JNI 0
#endif

namespace retro::zxpoly {

namespace {

constexpr const char *kPending =
    "zxpoly JNI bridge: phase 2 in progress; method not wired yet.";

#if ZXPOLY_HAS_JNI
const char *const kMotherboardClass   =
    "com/igormaznitsa/zxpoly/components/Motherboard";
const char *const kVideoClass         =
    "com/igormaznitsa/zxpoly/components/video/VideoController";
const char *const kAudioFormatClass   =
    "javax/sound/sampled/AudioFormat";
const char *const kSndBufferClass     =
    "com/igormaznitsa/zxpoly/components/sound/SndBufferContainer";
const char *const kKeyboardClass      =
    "com/igormaznitsa/zxpoly/components/KeyboardKempstonAndTapeIn";
const char *const kKempstonMouseClass =
    "com/igormaznitsa/zxpoly/components/KempstonMouse";
const char *const kTapeFactoryClass   =
    "com/igormaznitsa/zxpoly/components/tapereader/TapeSourceFactory";
const char *const kRomDataClass       =
    "com/igormaznitsa/zxpoly/components/RomData";
#endif

} // namespace

JniLoader::JniLoader() = default;

JniLoader::~JniLoader() {
    stop();
}

int JniLoader::start(const JvmLaunchOptions &opts) {
    if (jvm_) return ZXPOLY_OK;
#if ZXPOLY_HAS_JNI
    JavaVMOption jvm_opts[6];
    int n = 0;
    char xms[32], xmx[32], cp[4096];
    std::snprintf(xms, sizeof(xms), "-Xms%dm", opts.heap_mb / 2);
    std::snprintf(xmx, sizeof(xmx), "-Xmx%dm", opts.heap_mb);
    std::snprintf(cp,  sizeof(cp),  "-Djava.class.path=%s",
                  opts.class_path.c_str());
    jvm_opts[n].optionString = xms; n++;
    jvm_opts[n].optionString = xmx; n++;
    jvm_opts[n].optionString = cp;  n++;
    if (opts.verbose) {
        jvm_opts[n].optionString = const_cast<char *>("-verbose:class,jni");
        n++;
    }
    JavaVMInitArgs args{
        JNI_VERSION_1_8, n, jvm_opts,
        /* ignore unrecognized */ JNI_TRUE
    };

    JavaVM *jvm = nullptr;
    JNIEnv *env = nullptr;
    jint rc = JNI_CreateJavaVM(&jvm, &env, &args);
    if (rc != JNI_OK || !jvm) {
        last_error_ = "JNI_CreateJavaVM failed";
        return ZXPOLY_ERR_GENERIC;
    }
    jvm_ = jvm;
    env_ = env;

    // Eagerly resolve the classes we know we will need. Methods on
    // each are looked up lazily on first use so we do not pay for the
    // hundreds of jmethodIDs the JVM exposes.
    cls_motherboard_    = find_class(kMotherboardClass);
    cls_video_          = find_class(kVideoClass);
    cls_audio_format_   = find_class(kAudioFormatClass);
    cls_snd_buffer_     = find_class(kSndBufferClass);
    cls_keyboard_       = find_class(kKeyboardClass);
    cls_kempston_mouse_ = find_class(kKempstonMouseClass);
    cls_tape_factory_   = find_class(kTapeFactoryClass);
    cls_rom_data_       = find_class(kRomDataClass);

    if (!cls_motherboard_ || !cls_video_ || !cls_audio_format_ ||
        !cls_snd_buffer_ || !cls_keyboard_ || !cls_kempston_mouse_ ||
        !cls_tape_factory_ || !cls_rom_data_) {
        last_error_ = "one or more zxpoly classes did not resolve";
        stop();
        return ZXPOLY_ERR_GENERIC;
    }
    return ZXPOLY_OK;
#else
    last_error_ = "JNI not available on this build host (no <jni.h>)";
    (void)opts;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

void JniLoader::stop() {
#if ZXPOLY_HAS_JNI
    JNIEnv *env = static_cast<JNIEnv *>(env_);
    if (env) {
        if (motherboard_)        env->DeleteGlobalRef(static_cast<jobject>(motherboard_));
        if (cls_motherboard_)    env->DeleteGlobalRef(static_cast<jclass>(cls_motherboard_));
        if (cls_video_)          env->DeleteGlobalRef(static_cast<jclass>(cls_video_));
        if (cls_audio_format_)   env->DeleteGlobalRef(static_cast<jclass>(cls_audio_format_));
        if (cls_snd_buffer_)     env->DeleteGlobalRef(static_cast<jclass>(cls_snd_buffer_));
        if (cls_keyboard_)       env->DeleteGlobalRef(static_cast<jclass>(cls_keyboard_));
        if (cls_kempston_mouse_) env->DeleteGlobalRef(static_cast<jclass>(cls_kempston_mouse_));
        if (cls_tape_factory_)   env->DeleteGlobalRef(static_cast<jclass>(cls_tape_factory_));
        if (cls_rom_data_)       env->DeleteGlobalRef(static_cast<jclass>(cls_rom_data_));
    }
    if (jvm_) {
        static_cast<JavaVM *>(jvm_)->DestroyJavaVM();
    }
#endif
    motherboard_ = nullptr;
    cls_motherboard_ = nullptr;
    cls_video_ = nullptr;
    cls_audio_format_ = nullptr;
    cls_snd_buffer_ = nullptr;
    cls_keyboard_ = nullptr;
    cls_kempston_mouse_ = nullptr;
    cls_tape_factory_ = nullptr;
    cls_rom_data_ = nullptr;
    env_ = nullptr;
    jvm_ = nullptr;
    ready_.store(false);
}

int JniLoader::create_motherboard(int sample_rate) {
    if (sample_rate > 0) sample_rate_ = sample_rate;
    if (!jvm_) return ZXPOLY_ERR_GENERIC;
    // TODO phase 2.2: invoke Motherboard's 15-arg constructor with the
    // sane defaults -- 128K mode, ZX-Poly palette, no Covox, no
    // TurboSound, Kempston mouse off, attribute-port FF on, ULA Plus
    // off. Stash the result as a global ref in motherboard_.
    return ZXPOLY_ERR_NOTIMPL;
}

int JniLoader::open_file(const char *path) {
    if (!path) return ZXPOLY_ERR_BADARG;
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    // TODO phase 2.2: dispatch on extension:
    //   .tap/.tzx         -> TapeSourceFactory.read(path) + KeyboardKempstonAndTapeIn.setTape(...)
    //   .z80/.sna         -> read snapshot bytes + apply to motherboard memory map
    // and then (phase 2.3) run the auto-recolour preprocess if recolour() is true.
    return ZXPOLY_ERR_NOTIMPL;
}

const char *JniLoader::step_frame(FrameBuffer *out_frame,
                                  AudioBuffer *out_audio) {
    if (!jvm_ || !motherboard_) return kPending;
    if (paused_.load()) return nullptr;
    // TODO phase 2.2: implement the interrupt / tstate loop on top of
    // Motherboard.step(). This is the bulk of the work in 2.2 -- the
    // JVM has no runFrame() primitive; the bridge drives the
    // scheduling itself.
    (void)out_frame; (void)out_audio;
    return kPending;
}

int JniLoader::key_event(int key, int flags) {
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    // TODO phase 2.2: find the KeyboardKempstonAndTapeIn IoDevice via
    // motherboard.findIoDevice(...) and call setKeyState(ZXKEY_<row*8+col>,
    // pressed). The mapping from the 40-entry row-major index to the
    // ZXKEY_* constants is the same one SimpleSpeccy's android.cpp
    // uses; we lift it into a small table in the bridge.
    (void)key; (void)flags;
    return ZXPOLY_ERR_NOTIMPL;
}

int JniLoader::kempston(int mask) {
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    // TODO phase 2.2: get the KempstonMouse IoDevice, write the mask.
    (void)mask;
    return ZXPOLY_ERR_NOTIMPL;
}

int JniLoader::get_framebuffer(FrameBuffer *out) {
    if (!out) return ZXPOLY_ERR_BADARG;
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    // TODO phase 2.2: VideoController exposes the 512x384 RGBA buffer;
    // bridge reads it through getPixels() (TBD by reading the source)
    // and copies into out->pixels. We do not copy -- the bridge
    // returns the JVM-side pointer and the consumer copies.
    out->width = 0;
    out->height = 0;
    return ZXPOLY_ERR_NOTIMPL;
}

int JniLoader::drain_audio(uint8_t *dst, int max_bytes) {
    if (!dst || max_bytes <= 0) return ZXPOLY_ERR_BADARG;
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    // TODO phase 2.2: SndBufferContainer exposes a poll() returning
    // mixed samples. We hand them straight to the AAudio sink.
    std::memset(dst, 0, static_cast<size_t>(max_bytes));
    return max_bytes;
}

int JniLoader::set_sample_rate(int rate) {
    if (rate <= 0) return ZXPOLY_ERR_BADARG;
    sample_rate_ = rate;
    return ZXPOLY_OK;
}

int JniLoader::reset() {
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    return ZXPOLY_ERR_NOTIMPL;
}

int JniLoader::set_paused(bool paused) {
    paused_.store(paused);
    return ZXPOLY_OK;
}

int JniLoader::set_rom(int slot, const uint8_t *data, int size) {
    if (!data || size <= 0) return ZXPOLY_ERR_BADARG;
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
    (void)slot;
    return ZXPOLY_ERR_NOTIMPL;
}

int JniLoader::set_recolour(bool enabled) {
    recolour_.store(enabled);
    return ZXPOLY_OK;
}

#if ZXPOLY_HAS_JNI
namespace {
void *opaque_find_class(JNIEnv *env, const char *fqcn) {
    jclass local = env->FindClass(fqcn);
    if (!local) {
        if (env->ExceptionCheck()) env->ExceptionDescribe();
        return nullptr;
    }
    jclass global = static_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    return global;
}
} // namespace
#endif

void *JniLoader::find_class(const char *fqcn) {
#if ZXPOLY_HAS_JNI
    JNIEnv *env = static_cast<JNIEnv *>(env_);
    if (!env || !fqcn) return nullptr;
    return opaque_find_class(env, fqcn);
#else
    (void)fqcn;
    return nullptr;
#endif
}

} // namespace retro::zxpoly
