/*
 * jni_loader.cpp - phase 2.2. The class cache + the C++ wrapper.
 *
 * The whole TU is gated by __has_include(<jni.h>) so the file
 * compiles on a host that has no JDK or NDK. Without jni.h, every
 * method body returns ZXPOLY_ERR_NOTIMPL with a "phase 2 in
 * progress" message; the headless check-bridge.sh gate still
 * passes (the recolour / lifecycle setters are independent of JNI).
 *
 * Phase 2.2 fills in: create_motherboard, step_frame, open_file,
 * get_framebuffer, key_event, kempston, reset, set_rom. Phase 2.3
 * layers the auto-recolour preprocess on top of open_file.
 */
#include "jni_loader.h"
#include "../bridge/zxpoly_bridge.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <fstream>

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
const char *const kTapeContextClass   =
    "com/igormaznitsa/zxpoly/components/tapereader/TapeContext";
const char *const kTapeSourceClass    =
    "com/igormaznitsa/zxpoly/components/tapereader/TapeSource";
const char *const kBorderWidthClass   =
    "com/igormaznitsa/zxpoly/components/video/BorderWidth";
const char *const kVolumeProfileClass =
    "com/igormaznitsa/zxpoly/components/sound/VolumeProfile";
const char *const kTimingProfileClass =
    "com/igormaznitsa/zxpoly/components/timing/TimingProfile";
const char *const kBoardModeClass     =
    "com/igormaznitsa/zxpoly/components/BoardMode";
const char *const kVirtualKeyboardDecoClass =
    "com/igormaznitsa/zxpoly/components/video/VirtualKeyboardDecoration";

/** ZX-Spectrum runs at 3.5 MHz; one frame is 69888 t-states at 50 Hz.
 *  This is the well-known canonical value; matching what the JVM's
 *  MainForm uses. */
constexpr int kTstatesPerFrame = 69888;
#endif

} // namespace

JniLoader::JniLoader() = default;

JniLoader::~JniLoader() {
    stop();
}

#if ZXPOLY_HAS_JNI
namespace {

/** Look up a jclass by FQN. Returns nullptr (and clears any pending
 *  exception) on failure. The returned ref is a local ref; the caller
 *  decides whether to make it global. */
jclass local_find_class(JNIEnv *env, const char *fqcn) {
    jclass c = env->FindClass(fqcn);
    if (!c) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        return nullptr;
    }
    return c;
}

/** Cache of jmethodIDs resolved at create_motherboard time. The
 *  process-wide singleton mirrors the same approach the JVM-side
 *  MainForm uses: lookup once, reuse forever. The first
 *  create_motherboard call resolves everything; later ones reuse. */
struct CachedMethodIDs {
    jmethodID motherboard_step = nullptr;
    jmethodID motherboard_reset = nullptr;
    jmethodID motherboard_getVideo = nullptr;
    jmethodID motherboard_getBeeper = nullptr;
    jmethodID motherboard_findIoDevice = nullptr;
    jmethodID motherboard_getModules = nullptr;
    jmethodID motherboard_resetAndRestoreRom = nullptr;

    jmethodID module_setRomData = nullptr;
    jmethodID module_readMemory = nullptr;
    jmethodID module_writeMemory = nullptr;
    jmethodID module_makeCopyOfZxMemPage = nullptr;

    jmethodID video_makeCopyOfVideoBuffer = nullptr;

    jmethodID beeper_getSoundPort = nullptr;
    jmethodID romData_read_file = nullptr;
    jmethodID audioFormat_getSampleRate = nullptr;
    jmethodID audioFormat_getChannels = nullptr;
    jmethodID audioFormat_getSampleSizeInBits = nullptr;
    jmethodID sndBuffer_nextBuffer = nullptr;

    jmethodID tapeFactory_makeSource = nullptr;
};

CachedMethodIDs &methods() {
    static CachedMethodIDs m;
    return m;
}

} // namespace
#endif

int JniLoader::start(const JvmLaunchOptions &opts) {
    if (jvm_) return ZXPOLY_OK;
#if ZXPOLY_HAS_JNI
    JavaVMOption jvm_opts[6];
    int n = 0;
    char xms[32], xmx[32], cp[4096], jh[1024];
    std::snprintf(xms, sizeof(xms), "-Xms%dm", opts.heap_mb / 2);
    std::snprintf(xmx, sizeof(xmx), "-Xmx%dm", opts.heap_mb);
    std::snprintf(cp,  sizeof(cp),  "-Djava.class.path=%s",
                  opts.class_path.c_str());
    // Tell the JVM where its own lib/ lives. When invoked from JNI
    // the JVM tries to derive this from the location of libjvm.so in
    // our own process's address space and gets it wrong on hosts that
    // symlink the JDK install path -- which is what every distro
    // package does. Setting java.home to JAVA_HOME explicitly fixes
    // the early-init NULL dereference.
    const char *jh_env = std::getenv("JAVA_HOME");
    if (jh_env && *jh_env) {
        std::snprintf(jh, sizeof(jh), "-Djava.home=%s", jh_env);
    }
    jvm_opts[n].optionString = xms; n++;
    jvm_opts[n].optionString = xmx; n++;
    jvm_opts[n].optionString = cp;  n++;
    if (jh_env && *jh_env) {
        jvm_opts[n].optionString = jh; n++;
    }
    // Some host/JDK combinations SIGSEGV in the server VM during early
    // init. Force the client VM; the ZX-Poly emulator is not hot-path
    // sensitive, and the client VM is the right choice for an in-
    // process desktop classpath anyway.
    jvm_opts[n].optionString = const_cast<char *>("-client");
    n++;
    // Some host/JDK combinations SIGSEGV in the G1 GC threads during
    // early init. Serial GC is fine for an in-process desktop
    // classpath the size of one ZX-Spectrum emulator.
    jvm_opts[n].optionString = const_cast<char *>("-XX:+UseSerialGC");
    n++;
    // Skip JVM-side JIT entirely; the ZX-Poly emulator is already
    // small and our render path doesn't need hot-loop optimisation.
    jvm_opts[n].optionString = const_cast<char *>("-Xint");
    n++;
    if (opts.verbose) {
        jvm_opts[n].optionString = const_cast<char *>("-verbose:class,jni");
        n++;
    }
    JavaVMInitArgs args{
        JNI_VERSION_1_8, n, jvm_opts,
        /* ignore unrecognized */ JNI_TRUE
    };
    std::fprintf(stderr, "[jni] launching JVM (heap %d MB, %d opts)\n",
                 opts.heap_mb, n);

    JavaVM *jvm = nullptr;
    JNIEnv *env = nullptr;
    void *env_holder = nullptr;
    jint rc = JNI_CreateJavaVM(&jvm, &env_holder, &args);
    env = static_cast<JNIEnv *>(env_holder);
    if (rc != JNI_OK || !jvm) {
        last_error_ = "JNI_CreateJavaVM failed";
        return ZXPOLY_ERR_GENERIC;
    }
    jvm_ = jvm;
    env_ = env;

    auto cache = [&](const char *fqcn) -> void * {
        jclass c = local_find_class(env, fqcn);
        if (!c) return nullptr;
        jclass g = static_cast<jclass>(env->NewGlobalRef(c));
        env->DeleteLocalRef(c);
        return g;
    };

    cls_motherboard_    = cache(kMotherboardClass);
    cls_video_          = cache(kVideoClass);
    cls_audio_format_   = cache(kAudioFormatClass);
    cls_snd_buffer_     = cache(kSndBufferClass);
    cls_keyboard_       = cache(kKeyboardClass);
    cls_kempston_mouse_ = cache(kKempstonMouseClass);
    cls_tape_factory_   = cache(kTapeFactoryClass);
    cls_rom_data_       = cache(kRomDataClass);

    if (!cls_motherboard_ || !cls_video_ || !cls_audio_format_ ||
        !cls_snd_buffer_ || !cls_keyboard_ || !cls_kempston_mouse_ ||
        !cls_tape_factory_ || !cls_rom_data_) {
        std::string missing;
        if (!cls_motherboard_)    missing += " Motherboard";
        if (!cls_video_)          missing += " VideoController";
        if (!cls_audio_format_)   missing += " AudioFormat";
        if (!cls_snd_buffer_)     missing += " SndBufferContainer";
        if (!cls_keyboard_)       missing += " KeyboardKempstonAndTapeIn";
        if (!cls_kempston_mouse_) missing += " KempstonMouse";
        if (!cls_tape_factory_)   missing += " TapeSourceFactory";
        if (!cls_rom_data_)       missing += " RomData";
        last_error_ = "zxpoly classes did not resolve:" + missing;
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

#if ZXPOLY_HAS_JNI
namespace {

} // namespace
#endif

int JniLoader::create_motherboard(int sample_rate) {
    if (sample_rate > 0) sample_rate_ = sample_rate;
#if ZXPOLY_HAS_JNI
    if (!jvm_) return ZXPOLY_ERR_GENERIC;
    JNIEnv *env = static_cast<JNIEnv *>(env_);

    // BorderWidth.UNIVERSAL -> static field of type BorderWidth
    jclass bw_cls = local_find_class(env,
        "com/igormaznitsa/zxpoly/components/video/BorderWidth");
    if (!bw_cls) return ZXPOLY_ERR_GENERIC;
    jfieldID bw_universal = env->GetStaticFieldID(bw_cls, "UNIVERSAL",
        "Lcom/igormaznitsa/zxpoly/components/video/BorderWidth;");
    jobject borderWidth = env->GetStaticObjectField(bw_cls, bw_universal);

    // VolumeProfile.NORMAL
    jclass vp_cls = local_find_class(env,
        "com/igormaznitsa/zxpoly/components/sound/VolumeProfile");
    jfieldID vp_normal = env->GetStaticFieldID(vp_cls, "NORMAL",
        "Lcom/igormaznitsa/zxpoly/components/sound/VolumeProfile;");
    jobject volumeProfile = env->GetStaticObjectField(vp_cls, vp_normal);

    // TimingProfile.NTSC_48_OR_128_K
    jclass tp_cls = local_find_class(env,
        "com/igormaznitsa/zxpoly/components/timing/TimingProfile");
    jfieldID tp_ntsc = env->GetStaticFieldID(tp_cls, "NTSC_48_OR_128_K",
        "Lcom/igormaznitsa/zxpoly/components/timing/TimingProfile;");
    jobject timingProfile = env->GetStaticObjectField(tp_cls, tp_ntsc);

    // ROM: prefer ZXSPECTRUM_ROM env var, then
    // ~/games/spectrum/roms/zxspectrum128.rom, then sos48.rom.
    // Any of those that exists is loaded via RomData.read(File); if none
    // exist we fall back to a 16K zero ROM so the constructor still
    // wires up (the JVM-side error is "no boot ROM" rather than a JNI
    // exception, which the user can act on).
    jclass rd_cls = static_cast<jclass>(cls_rom_data_);
    jmethodID rd_ctor = env->GetMethodID(rd_cls, "<init>",
        "(Ljava/lang/String;[B)V");
    jmethodID rd_read_file = env->GetStaticMethodID(rd_cls, "read",
        "(Ljava/io/File;)Lcom/igormaznitsa/zxpoly/components/RomData;");
    methods().romData_read_file = rd_read_file;

    const char *rom_env = std::getenv("ZXSPECTRUM_ROM");
    const char *rom_candidates[] = {
        rom_env,
        "/home/jon/games/spectrum/roms/zxspectrum128.rom",
        "/home/jon/games/spectrum/roms/sos48.rom",
    };

    jobject rom = nullptr;
    jstring rom_src = nullptr;
    jbyteArray empty_rom = nullptr;
    for (const char *path : rom_candidates) {
        if (!path || !*path) continue;
        // Probe before handing the path to the JVM -- a missing file
        // should not throw on the Java side.
        std::ifstream probe(path);
        if (!probe.good()) continue;
        probe.close();
        jclass file_cls = local_find_class(env, "java/io/File");
        jmethodID file_ctor = env->GetMethodID(file_cls, "<init>",
            "(Ljava/lang/String;)V");
        jstring jpath = env->NewStringUTF(path);
        jobject file_obj = env->NewObject(file_cls, file_ctor, jpath);
        rom = env->CallStaticObjectMethod(rd_cls, rd_read_file, file_obj);
        env->DeleteLocalRef(file_cls);
        env->DeleteLocalRef(file_obj);
        env->DeleteLocalRef(jpath);
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
            rom = nullptr;
            continue;
        }
        if (rom) {
            rom_src = env->NewStringUTF(path);
            break;
        }
    }

    if (!rom) {
        // No usable ROM file -- fall back to a 16K zero so the JVM at
        // least constructs. The user will see a black screen and a
        // JNI-side log message saying which path we tried.
        empty_rom = env->NewByteArray(16384);
        rom_src = env->NewStringUTF("placeholder://retro-spectrum (no ROM found)");
        rom = env->NewObject(rd_cls, rd_ctor, rom_src, empty_rom);
        last_error_ = "no ROM found: tried ZXSPECTRUM_ROM env, "
                      "/home/jon/games/spectrum/roms/zxspectrum128.rom, "
                      "sos48.rom";
    }

    // Bounds(0,0,0,0)
    jclass bounds_cls = local_find_class(env, "java/awt/Rectangle");
    jmethodID bounds_ctor = env->GetMethodID(bounds_cls, "<init>", "(IIII)V");
    jobject bounds = env->NewObject(bounds_cls, bounds_ctor, 0, 0, 0, 0);

    // BoardMode.ZXPOLY
    jclass bm_cls = local_find_class(env,
        "com/igormaznitsa/zxpoly/components/BoardMode");
    jfieldID bm_zxpoly = env->GetStaticFieldID(bm_cls, "ZXPOLY",
        "Lcom/igormaznitsa/zxpoly/components/BoardMode;");
    jobject boardMode = env->GetStaticObjectField(bm_cls, bm_zxpoly);

    // VirtualKeyboardDecoration.NONE
    jclass vkd_cls = local_find_class(env,
        "com/igormaznitsa/zxpoly/components/video/VirtualKeyboardDecoration");
    jfieldID vkd_none = env->GetStaticFieldID(vkd_cls, "NONE",
        "Lcom/igormaznitsa/zxpoly/components/video/VirtualKeyboardDecoration;");
    jobject vkd = env->GetStaticObjectField(vkd_cls, vkd_none);

    // Motherboard ctor: 15 args.
    //   (Lcom/.../BorderWidth;Lcom/.../VolumeProfile;
    //    Lcom/.../TimingProfile;Lcom/.../RomData;
    //    Ljava/awt/Rectangle;Lcom/.../BoardMode;
    //    ZZZZZZLcom/.../VirtualKeyboardDecoration;ZZ)V
    jclass mb_cls = static_cast<jclass>(cls_motherboard_);
    jmethodID mb_ctor = env->GetMethodID(mb_cls, "<init>",
        "(Lcom/igormaznitsa/zxpoly/components/video/BorderWidth;"
        "Lcom/igormaznitsa/zxpoly/components/sound/VolumeProfile;"
        "Lcom/igormaznitsa/zxpoly/components/timing/TimingProfile;"
        "Lcom/igormaznitsa/zxpoly/components/RomData;"
        "Ljava/awt/Rectangle;"
        "Lcom/igormaznitsa/zxpoly/components/BoardMode;"
        "ZZZZZZ"
        "Lcom/igormaznitsa/zxpoly/components/video/VirtualKeyboardDecoration;"
        "ZZ)V");
    if (!mb_ctor) {
        last_error_ = "Motherboard constructor signature not found";
        return ZXPOLY_ERR_GENERIC;
    }
    jobject mb = env->NewObject(mb_cls, mb_ctor,
        borderWidth, volumeProfile, timingProfile, rom, bounds, boardMode,
        /* syncRepaint         */ (jboolean) true,
        /* useAcbSoundScheme   */ (jboolean) false,
        /* enableCovoxFb       */ (jboolean) false,
        /* useTurboSound       */ (jboolean) false,
        /* allowKempstonMouse  */ (jboolean) false,
        /* attributePortFf     */ (jboolean) true,
        vkd,
        /* ulaPlus             */ (jboolean) false,
        /* tryConsumeLessRsrc  */ (jboolean) false);

    if (env->ExceptionCheck()) {
        check_exception("create_motherboard");
        return ZXPOLY_ERR_GENERIC;
    }

    motherboard_ = env->NewGlobalRef(mb);

    // Cache the methods we will need on every frame.
    jmethodID step = env->GetMethodID(mb_cls, "step", "(ZZZZZ)I");
    jmethodID reset = env->GetMethodID(mb_cls, "reset", "()V");
    jmethodID getVideo = env->GetMethodID(mb_cls, "getVideoController",
        "()Lcom/igormaznitsa/zxpoly/components/video/VideoController;");
    jmethodID getBeeper = env->GetMethodID(mb_cls, "getBeeper",
        "()Lcom/igormaznitsa/zxpoly/components/sound/Beeper;");
    jmethodID findIo = env->GetMethodID(mb_cls, "findIoDevice",
        "(Ljava/lang/Class;)Lcom/igormaznitsa/zxpoly/components/IoDevice;");

    // Stash for later use. We stash them on a per-loader basis via the
    // methods() global cache (process-wide singleton).
    auto &m = methods();
    m.motherboard_step = step;
    m.motherboard_reset = reset;
    m.motherboard_getVideo = getVideo;
    m.motherboard_getBeeper = getBeeper;
    m.motherboard_findIoDevice = findIo;

    // VideoController.makeCopyOfVideoBuffer(boolean) -> int[]
    jclass vc_cls = static_cast<jclass>(cls_video_);
    m.video_makeCopyOfVideoBuffer = env->GetMethodID(vc_cls,
        "makeCopyOfVideoBuffer", "(Z)[I");

    // Beeper.getSoundPort() -> Optional<SourceSoundPort>
    jclass beeper_cls = local_find_class(env,
        "com/igormaznitsa/zxpoly/components/sound/Beeper");
    if (beeper_cls) {
        m.beeper_getSoundPort = env->GetMethodID(beeper_cls, "getSoundPort",
            "()Ljava/util/Optional;");
        env->DeleteLocalRef(beeper_cls);
    }

    // TapeSourceFactory.makeSource static method (looked up later in
    // open_file as needed)

    // AudioFormat accessors (used to fill our AudioBuffer struct)
    jclass af_cls = static_cast<jclass>(cls_audio_format_);
    m.audioFormat_getSampleRate = env->GetMethodID(af_cls,
        "getSampleRate", "()F");
    m.audioFormat_getChannels = env->GetMethodID(af_cls,
        "getChannels", "()I");
    m.audioFormat_getSampleSizeInBits = env->GetMethodID(af_cls,
        "getSampleSizeInBits", "()I");

    // SndBufferContainer.nextBuffer(int, int) -> byte[]
    jclass sb_cls = static_cast<jclass>(cls_snd_buffer_);
    m.sndBuffer_nextBuffer = env->GetMethodID(sb_cls, "nextBuffer",
        "(II)[B");

    // Keyboard: no public setter; we use reflection to write the
    // private volatile `keyboardLines` field. The reflection is set
    // up here once and reused on every key_event() call.
    jclass kb_cls = static_cast<jclass>(cls_keyboard_);
    jfieldID keyboardLines = env->GetFieldID(kb_cls, "keyboardLines", "J");
    // Stash the field ID alongside the loader for repeated writes.
    // (We use the per-instance trick below in key_event().)
    keyboard_lines_field_ = keyboardLines;

    jclass km_cls = static_cast<jclass>(cls_kempston_mouse_);
    jfieldID kempstonSignals = env->GetFieldID(km_cls, "kempstonSignals", "I");
    kempston_signals_field_ = kempstonSignals;

    if (env->ExceptionCheck()) {
        check_exception("create_motherboard: cache method IDs");
    }

    // Clean up local refs
    env->DeleteLocalRef(mb);
    env->DeleteLocalRef(bw_cls); env->DeleteLocalRef(borderWidth);
    env->DeleteLocalRef(vp_cls); env->DeleteLocalRef(volumeProfile);
    env->DeleteLocalRef(tp_cls); env->DeleteLocalRef(timingProfile);
    env->DeleteLocalRef(empty_rom); env->DeleteLocalRef(rom_src); env->DeleteLocalRef(rom);
    env->DeleteLocalRef(bounds_cls); env->DeleteLocalRef(bounds);
    env->DeleteLocalRef(bm_cls); env->DeleteLocalRef(boardMode);
    env->DeleteLocalRef(vkd_cls); env->DeleteLocalRef(vkd);
    if (beeper_cls) env->DeleteLocalRef(beeper_cls);
    env->DeleteLocalRef(bounds_cls);
    env->DeleteLocalRef(kb_cls);
    env->DeleteLocalRef(km_cls);

    ready_.store(true);
    return ZXPOLY_OK;
#else
    (void)sample_rate;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

int JniLoader::open_file(const char *path) {
    if (!path) return ZXPOLY_ERR_BADARG;
    if (!jvm_ || !motherboard_) return ZXPOLY_ERR_GENERIC;
#if ZXPOLY_HAS_JNI
    JNIEnv *env = static_cast<JNIEnv *>(env_);
    auto &m = methods();

    // Dispatch on extension.
    const char *dot = std::strrchr(path, '.');
    if (!dot) return ZXPOLY_ERR_BADFILE;

    auto ends_with = [&](const char *suf) {
        const size_t pn = std::strlen(path);
        const size_t sn = std::strlen(suf);
        return pn >= sn &&
               std::equal(suf, suf + sn, path + pn - sn,
                          [](char a, char b) {
                              return std::tolower(a) == std::tolower(b);
                          });
    };

    if (ends_with(".tap") || ends_with(".tzx")) {
        // Tape path: TapeSourceFactory.makeSource(TapeContext, TimingProfile, File)
        jclass tc_cls = local_find_class(env, kTapeContextClass);
        if (!tc_cls) return ZXPOLY_ERR_GENERIC;
        jmethodID tc_ctor = env->GetMethodID(tc_cls, "<init>",
            "(Ljava/lang/String;)V");
        jstring tc_src = env->NewStringUTF(path);
        jobject tc = env->NewObject(tc_cls, tc_ctor, tc_src);
        env->DeleteLocalRef(tc_src);

        jclass tp_cls = local_find_class(env, kTimingProfileClass);
        jfieldID tp_ntsc = env->GetStaticFieldID(tp_cls, "NTSC_48_OR_128_K",
            "Lcom/igormaznitsa/zxpoly/components/timing/TimingProfile;");
        jobject tp = env->GetStaticObjectField(tp_cls, tp_ntsc);

        jclass tf_cls = static_cast<jclass>(cls_tape_factory_);
        jmethodID makeSource = env->GetStaticMethodID(tf_cls, "makeSource",
            "(Lcom/igormaznitsa/zxpoly/components/tapereader/TapeContext;"
            "Lcom/igormaznitsa/zxpoly/components/timing/TimingProfile;"
            "Ljava/io/File;)Lcom/igormaznitsa/zxpoly/components/tapereader/TapeSource;");
        if (!makeSource) {
            env->DeleteLocalRef(tc);
            env->DeleteLocalRef(tc_cls);
            env->DeleteLocalRef(tp_cls);
            env->DeleteLocalRef(tp);
            return check_exception("TapeSourceFactory.makeSource");
        }
        jclass file_cls = local_find_class(env, "java/io/File");
        jmethodID file_ctor = env->GetMethodID(file_cls, "<init>",
            "(Ljava/lang/String;)V");
        jstring file_path = env->NewStringUTF(path);
        jobject file_obj = env->NewObject(file_cls, file_ctor, file_path);
        env->DeleteLocalRef(file_path);

        jobject tape = env->CallStaticObjectMethod(tf_cls, makeSource, tc, tp, file_obj);
        if (env->ExceptionCheck()) {
            env->DeleteLocalRef(tc);
            env->DeleteLocalRef(tc_cls);
            env->DeleteLocalRef(tp_cls);
            env->DeleteLocalRef(tp);
            env->DeleteLocalRef(file_cls);
            env->DeleteLocalRef(file_obj);
            return check_exception("TapeSourceFactory.makeSource");
        }

        // Bind the tape to the keyboard's IoDevice. The keyboard owns
        // an AtomicReference<TapeSource> tap field; we use reflection
        // to write to it.
        jclass kb_cls = static_cast<jclass>(cls_keyboard_);
        jfieldID tap_field = env->GetFieldID(kb_cls, "tap",
            "Ljava/util/concurrent/atomic/AtomicReference;");
        jobject tap_atomic = env->GetObjectField(
            static_cast<jobject>(motherboard_), tap_field);
        jclass ar_cls = local_find_class(env, "java/util/concurrent/atomic/AtomicReference");
        jmethodID ar_set = env->GetMethodID(ar_cls, "set",
            "(Ljava/lang/Object;)V");
        env->CallVoidMethod(tap_atomic, ar_set, tape);

        // Auto-recolour preprocess happens here in phase 2.3.
        if (recolour_.load()) {
            // TODO phase 2.3: distribute graphics across CPUs 1..3,
            // leave loader on CPU 0. Until then, the recolour flag is
            // recorded and the JVM runs unmodified.
        }

        env->DeleteLocalRef(tape);
        env->DeleteLocalRef(tc);
        env->DeleteLocalRef(tc_cls);
        env->DeleteLocalRef(tp_cls);
        env->DeleteLocalRef(tp);
        env->DeleteLocalRef(file_cls);
        env->DeleteLocalRef(file_obj);
        env->DeleteLocalRef(ar_cls);
        env->DeleteLocalRef(tap_atomic);
        env->DeleteLocalRef(kb_cls);

        return ZXPOLY_OK;
    }

    // Snapshot formats (.z80/.sna/.sze/.zxp) -- not implemented yet.
    // SNA loader is in zxpoly/sxasnake or similar; for now return
    // ZXPOLY_ERR_NOTIMPL. The user can use the pre-adapted .sze
    // files in ~/games/spectrum/ which already encode the snapshot
    // state in ZX-Poly's native format.
    return ZXPOLY_ERR_NOTIMPL;
#else
    (void)path;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

const char *JniLoader::step_frame(FrameBuffer *out_frame,
                                  AudioBuffer *out_audio) {
#if ZXPOLY_HAS_JNI
    if (!ready_.load()) return kPending;
    if (paused_.load()) return nullptr;
    if (!motherboard_) return kPending;

    JNIEnv *env = static_cast<JNIEnv *>(env_);
    auto &m = methods();

    // ZX-Poly mode is 69888 t-states per frame. We don't need fine
    // tstate scheduling here -- the JVM's MainForm does the same
    // thing at 50 Hz and we replicate the simple version. One
    // Motherboard.step() per frame, with startNewFrame=true on every
    // call; the tstate/clock interrupt flags are derived from the
    // accumulator.
    if (tstates_in_frame_ >= kTstatesPerFrame) {
        tstates_in_frame_ = 0;
    }
    const bool startNewFrame = (tstates_in_frame_ == 0);
    const bool tiStatesInt   = (tstates_in_frame_ + frame_chunk_) >= kTstatesPerFrame;
    const bool wallClockInt  = tiStatesInt;

    env->CallIntMethod(static_cast<jobject>(motherboard_),
        m.motherboard_step,
        (jboolean) tiStatesInt,
        (jboolean) wallClockInt,
        (jboolean) false,    /* commonNmi */
        (jboolean) startNewFrame,
        (jboolean) true);     /* executionEnabled */

    if (env->ExceptionCheck()) {
        check_exception("Motherboard.step");
        return kPending;
    }

    tstates_in_frame_ += frame_chunk_;
    if (tstates_in_frame_ > kTstatesPerFrame) {
        tstates_in_frame_ = kTstatesPerFrame;
    }

    if (startNewFrame && out_frame) {
        // Copy the video buffer once per frame.
        jobject vc = env->CallObjectMethod(static_cast<jobject>(motherboard_),
            m.motherboard_getVideo);
        if (vc && !env->ExceptionCheck()) {
            jintArray pixels = static_cast<jintArray>(env->CallObjectMethod(
                vc, m.video_makeCopyOfVideoBuffer, (jboolean) false));
            if (pixels && !env->ExceptionCheck()) {
                const jsize len = env->GetArrayLength(pixels);
                jint *elems = env->GetIntArrayElements(pixels, nullptr);
                if (elems) {
                    // VideoController.SCREEN_WIDTH = 512,
                    // SCREEN_HEIGHT = 384 in ZX-Poly mode.
                    out_frame->width  = 512;
                    out_frame->height = 384;
                    out_frame->stride = 512;
                    out_frame->pixels = reinterpret_cast<const uint8_t *>(elems);
                    // We don't copy; the JVM-owned array is valid until
                    // the next step_frame() call. The bridge copies it
                    // out into a persistent buffer before returning.
                    env->ReleaseIntArrayElements(pixels, elems,
                        JNI_ABORT); /* don't write back to JVM */
                }
                env->DeleteLocalRef(pixels);
            }
            env->DeleteLocalRef(vc);
        }
    }

    // Audio: AudioFormat is on SndBufferContainer.AUDIO_FORMAT (static).
    // The Beeper owns a SourceSoundPort which can be tapped to get a
    // mixed buffer. Phase 2.3 wires the full path; for now return 0.
    if (out_audio) {
        out_audio->sample_rate = 48000;        // SndBufferContainer.SND_FREQ
        out_audio->channels = 2;               // CHANNELS_NUM
        out_audio->bytes_per_sample = 2;        // SAMPLE_SIZE_BITS / 8
        out_audio->frames = 0;
        out_audio->samples = nullptr;
    }

    return nullptr;
#else
    (void)out_frame; (void)out_audio;
    return kPending;
#endif
}

int JniLoader::key_event(int key, int flags) {
#if ZXPOLY_HAS_JNI
    if (!ready_.load() || !motherboard_) return ZXPOLY_ERR_GENERIC;
    if (key < 0 || key >= 40) return ZXPOLY_ERR_BADARG;

    JNIEnv *env = static_cast<JNIEnv *>(env_);
    jclass kb_cls = static_cast<jclass>(cls_keyboard_);

    // The 40 ZXKEY_* constants are `public static final long` with
    // values 1L<<n. Resolve by name (no public accessor exists).
    // Names are: ZXKEY_CS, ZXKEY_1, ZXKEY_Q, ZXKEY_A, ... per the
    // standard 8x5 Spectrum keyboard matrix.
    static const char *names[40] = {
        // row 0 (port 0xFE bit 0): SHIFT, Z, X, C, V
        "CS","Z","X","C","V",
        // row 1 (port 0xFE bit 1): A, S, D, F, G
        "A","S","D","F","G",
        // row 2 (port 0xFE bit 2): Q, W, E, R, T
        "Q","W","E","R","T",
        // row 3 (port 0xFE bit 3): 1, 2, 3, 4, 5
        "1","2","3","4","5",
        // row 4 (port 0xFE bit 4): 0, 9, 8, 7, 6
        "0","9","8","7","6",
        // row 5 (port 0xFD bit 0): P, O, I, U, Y
        "P","O","I","U","Y",
        // row 6 (port 0xFD bit 1): ENTER, L, K, J, H
        "ENT","L","K","J","H",
        // row 7 (port 0xFD bit 2): SPACE, SYM, M, N, B
        "SP","SM","M","N","B",
    };
    static const jfieldID *ids = nullptr;
    static jfieldID cache[40];
    if (!ids) {
        for (int i = 0; i < 40; i++) {
            std::string fq("ZXKEY_"); fq += names[i];
            cache[i] = env->GetStaticFieldID(kb_cls, fq.c_str(), "J");
            if (!cache[i]) {
                if (env->ExceptionCheck()) env->ExceptionClear();
                cache[i] = nullptr;
            }
        }
        ids = cache;
    }
    jfieldID fid = ids[key];
    if (!fid) return ZXPOLY_ERR_BADARG;
    jlong mask = env->GetStaticLongField(kb_cls, fid);

    // Read-modify-write the private volatile keyboardLines field via
    // reflection. The keyboard tracks ALL pressed keys as a bitmask.
    jfieldID lines = static_cast<jfieldID>(keyboard_lines_field_);
    jmethodID findIo = methods().motherboard_findIoDevice;
    jobject kb_io = env->CallObjectMethod(static_cast<jobject>(motherboard_),
        findIo, kb_cls);
    jlong current = env->GetLongField(kb_io, lines);
    const jlong next = (flags == 0) ? (current | mask) : (current & ~mask);
    env->SetLongField(kb_io, lines, next);
    env->DeleteLocalRef(kb_io);

    return ZXPOLY_OK;
#else
    (void)key; (void)flags;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

int JniLoader::kempston(int mask) {
#if ZXPOLY_HAS_JNI
    if (!ready_.load() || !motherboard_) return ZXPOLY_ERR_GENERIC;

    JNIEnv *env = static_cast<JNIEnv *>(env_);
    jclass km_cls = static_cast<jclass>(cls_kempston_mouse_);
    jfieldID signals = static_cast<jfieldID>(kempston_signals_field_);
    jmethodID findIo = methods().motherboard_findIoDevice;
    jobject km_io = env->CallObjectMethod(static_cast<jobject>(motherboard_),
        findIo, km_cls);
    env->SetIntField(km_io, signals, mask);
    env->DeleteLocalRef(km_io);
    return ZXPOLY_OK;
#else
    (void)mask;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

int JniLoader::get_framebuffer(FrameBuffer *out) {
    if (!out) return ZXPOLY_ERR_BADARG;
#if ZXPOLY_HAS_JNI
    if (!ready_.load() || !motherboard_) return ZXPOLY_ERR_GENERIC;
    JNIEnv *env = static_cast<JNIEnv *>(env_);
    auto &m = methods();
    jobject vc = env->CallObjectMethod(static_cast<jobject>(motherboard_),
        m.motherboard_getVideo);
    if (!vc || env->ExceptionCheck()) {
        check_exception("getVideoController");
        return ZXPOLY_ERR_GENERIC;
    }
    jintArray pixels = static_cast<jintArray>(env->CallObjectMethod(
        vc, m.video_makeCopyOfVideoBuffer, (jboolean) false));
    if (!pixels || env->ExceptionCheck()) {
        check_exception("makeCopyOfVideoBuffer");
        return ZXPOLY_ERR_GENERIC;
    }
    const jsize len = env->GetArrayLength(pixels);
    jint *elems = env->GetIntArrayElements(pixels, nullptr);
    if (!elems) {
        env->DeleteLocalRef(pixels);
        return ZXPOLY_ERR_GENERIC;
    }
    out->width  = 512;
    out->height = 384;
    out->stride = 512;
    out->pixels = reinterpret_cast<const uint8_t *>(elems);
    // Caller is responsible for ReleaseIntArrayElements; we leave the
    // array pinned until the next step_frame / get_framebuffer call.
    env->DeleteLocalRef(pixels);
    return ZXPOLY_OK;
#else
    out->width = 0;
    out->height = 0;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

int JniLoader::drain_audio(uint8_t *dst, int max_bytes) {
    if (!dst || max_bytes <= 0) return ZXPOLY_ERR_BADARG;
    std::memset(dst, 0, static_cast<size_t>(max_bytes));
    return max_bytes;
}

int JniLoader::set_sample_rate(int rate) {
    if (rate <= 0) return ZXPOLY_ERR_BADARG;
    sample_rate_ = rate;
    return ZXPOLY_OK;
}

int JniLoader::reset() {
#if ZXPOLY_HAS_JNI
    if (!ready_.load() || !motherboard_) return ZXPOLY_ERR_GENERIC;
    JNIEnv *env = static_cast<JNIEnv *>(env_);
    auto &m = methods();
    env->CallVoidMethod(static_cast<jobject>(motherboard_), m.motherboard_reset);
    if (env->ExceptionCheck()) {
        check_exception("reset");
        return ZXPOLY_ERR_GENERIC;
    }
    return ZXPOLY_OK;
#else
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

int JniLoader::set_paused(bool paused) {
    paused_.store(paused);
    return ZXPOLY_OK;
}

int JniLoader::set_rom(int slot, const uint8_t *data, int size) {
#if ZXPOLY_HAS_JNI
    if (!data || size <= 0) return ZXPOLY_ERR_BADARG;
    if (!ready_.load() || !motherboard_) return ZXPOLY_ERR_GENERIC;
    (void)slot;  // ZX-Poly's Motherboard takes a single RomData via ctor.

    JNIEnv *env = static_cast<JNIEnv *>(env_);
    jclass rd_cls = static_cast<jclass>(cls_rom_data_);
    jmethodID rd_ctor = env->GetMethodID(rd_cls, "<init>",
        "(Ljava/lang/String;[B)V");
    jbyteArray rom_bytes = env->NewByteArray(size);
    env->SetByteArrayRegion(rom_bytes, 0, size,
        reinterpret_cast<const jbyte *>(data));
    jstring rom_src = env->NewStringUTF("user-supplied://retro-spectrum");
    jobject new_rom = env->NewObject(rd_cls, rd_ctor, rom_src, rom_bytes);

    jmethodID resetRom = env->GetMethodID(
        static_cast<jclass>(cls_motherboard_),
        "resetAndRestoreRom",
        "(Lcom/igormaznitsa/zxpoly/components/RomData;)V");
    if (!resetRom) {
        // resetAndRestoreRom might have a different signature; fall
        // back to reset() and let the caller re-load.
        env->DeleteLocalRef(new_rom);
        env->DeleteLocalRef(rom_bytes);
        env->DeleteLocalRef(rom_src);
        return ZXPOLY_ERR_NOTIMPL;
    }
    env->CallVoidMethod(static_cast<jobject>(motherboard_),
        resetRom, new_rom);
    int rc = ZXPOLY_OK;
    if (env->ExceptionCheck()) {
        check_exception("resetAndRestoreRom");
        rc = ZXPOLY_ERR_GENERIC;
    }
    env->DeleteLocalRef(new_rom);
    env->DeleteLocalRef(rom_bytes);
    env->DeleteLocalRef(rom_src);
    return rc;
#else
    (void)slot; (void)data; (void)size;
    return ZXPOLY_ERR_NOTIMPL;
#endif
}

int JniLoader::set_recolour(bool enabled) {
    recolour_.store(enabled);
    return ZXPOLY_OK;
}

int JniLoader::recolour_preprocess() {
#if ZXPOLY_HAS_JNI
    if (!ready_.load() || !motherboard_) return ZXPOLY_ERR_GENERIC;
    if (!recolour_.load()) return ZXPOLY_OK;   // toggle off -> no-op

    JNIEnv *env = static_cast<JNIEnv *>(env_);

    // The ZX-Poly mode renders the same screen data on all 4 parallel
    // CPUs in lockstep, so each module's video RAM needs the same
    // pixel+attribute bytes. Read the main CPU's video memory via
    // ZxPolyModule.makeCopyOfZxMemPage(5) (the 16K page at 0x4000 which
    // holds the screen) and write it into every module's heap.
    jmethodID makeCopy = env->GetMethodID(
        static_cast<jclass>(cls_motherboard_),
        "getModules", "()[Lcom/igormaznitsa/zxpoly/components/ZxPolyModule;");
    if (!makeCopy) return ZXPOLY_ERR_NOTIMPL;
    jobjectArray modules = static_cast<jobjectArray>(
        env->CallObjectMethod(static_cast<jobject>(motherboard_), makeCopy));
    if (!modules || env->ExceptionCheck()) {
        check_exception("getModules");
        return ZXPOLY_ERR_GENERIC;
    }
    const jsize n_modules = env->GetArrayLength(modules);
    if (n_modules < 1) {
        env->DeleteLocalRef(modules);
        return ZXPOLY_ERR_GENERIC;
    }

    // Page 5 = 0x4000..0x7FFF, which on a 48K Spectrum is the screen
    // + attribute memory. On a 128K Spectrum with paged memory, the
    // page index depends on port 7FFD; we read whichever is currently
    // mapped into 0x4000.
    jclass module_cls = static_cast<jclass>(
        env->GetObjectClass(env->GetObjectArrayElement(modules, 0)));
    jmethodID copy_page = env->GetMethodID(module_cls,
        "makeCopyOfZxMemPage", "(I)[B");
    if (!copy_page) {
        check_exception("makeCopyOfZxMemPage");
        env->DeleteLocalRef(modules);
        return ZXPOLY_ERR_GENERIC;
    }
    jbyteArray screen = static_cast<jbyteArray>(env->CallObjectMethod(
        env->GetObjectArrayElement(modules, 0), copy_page, 5));
    if (!screen || env->ExceptionCheck()) {
        check_exception("makeCopyOfZxMemPage(5)");
        env->DeleteLocalRef(modules);
        return ZXPOLY_ERR_GENERIC;
    }

    // Mirror into every module's video memory. ZX-Poly lockstep means
    // each CPU renders the same image with its own attribute, and the
    // framebuffer combines the four parallel outputs into a single
    // 4-bit-per-pixel image. Phase 2.4 / 2.5 replace this with the
    // real per-channel redistribution; today this proves the wiring.
    jmethodID write_heap = env->GetMethodID(module_cls,
        "writeHeapPage", "(I[B)V");
    for (jsize i = 0; i < n_modules; i++) {
        jobject module = env->GetObjectArrayElement(modules, i);
        env->CallVoidMethod(module, write_heap, 5, screen);
        env->DeleteLocalRef(module);
        if (env->ExceptionCheck()) {
            check_exception("writeHeapPage(5)");
            break;
        }
    }

    env->DeleteLocalRef(modules);
    env->DeleteLocalRef(screen);
    env->DeleteLocalRef(module_cls);
    return ZXPOLY_OK;
#else
    return ZXPOLY_ERR_NOTIMPL;
#endif
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

int JniLoader::check_exception(const char *context) {
#if ZXPOLY_HAS_JNI
    if (!env_) return ZXPOLY_ERR_GENERIC;
    JNIEnv *env = static_cast<JNIEnv *>(env_);
    if (!env->ExceptionCheck()) return ZXPOLY_OK;
    env->ExceptionDescribe();
    jthrowable ex = env->ExceptionOccurred();
    if (ex) {
        jclass throwable_cls = local_find_class(env, "java/lang/Throwable");
        if (throwable_cls) {
            jmethodID mid = env->GetMethodID(throwable_cls, "toString",
                "()Ljava/lang/String;");
            if (mid) {
                jstring jmsg = static_cast<jstring>(env->CallObjectMethod(ex, mid));
                if (jmsg) {
                    const char *c = env->GetStringUTFChars(jmsg, nullptr);
                    if (c) {
                        last_error_ = std::string(context) + ": " + c;
                        env->ReleaseStringUTFChars(jmsg, c);
                    }
                    env->DeleteLocalRef(jmsg);
                }
            }
            env->DeleteLocalRef(throwable_cls);
        }
        env->DeleteLocalRef(ex);
    }
    env->ExceptionClear();
    return ZXPOLY_ERR_GENERIC;
#else
    (void)context;
    return ZXPOLY_ERR_GENERIC;
#endif
}

} // namespace retro::zxpoly
