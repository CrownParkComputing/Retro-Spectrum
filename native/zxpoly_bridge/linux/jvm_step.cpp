// jvm_step.cpp -- narrow down which call after JNI_CreateJavaVM
// causes the SIGSEGV. Each test isolates one more step.
//
//   step 1: JNI_CreateJavaVM only -- passes (proven)
//   step 2: FindClass on javax.sound.sampled.AudioFormat
//   step 3: FindClass on com.igormaznitsa.zxpoly.components.Motherboard
//   step 4: GetMethodID on Motherboard's 15-arg ctor
//   step 5: NewObject on that ctor
//
// Run with: ./jvm_step N   (where N is 1..5)

#include <jni.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <string>

static JavaVM *vm = nullptr;

static int do_create() {
    void *lib = dlopen("libjvm.so", RTLD_NOW);
    if (!lib) { std::fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    auto create = (jint (*)(JavaVM **, void **, void *))
                  dlsym(lib, "JNI_CreateJavaVM");
    JavaVMOption opts[2];
    char xmx[32]; std::snprintf(xmx, sizeof(xmx), "-Xmx256m");
    char cp[4096]; std::snprintf(cp, sizeof(cp),
        "-Djava.class.path=/home/jon/games/spectrum/zxpoly-emul.jar");
    char jh[1024]; std::snprintf(jh, sizeof(jh),
        "-Djava.home=/usr/lib/jvm/java-26-openjdk");
    opts[0].optionString = xmx;
    opts[1].optionString = cp;
    JavaVMInitArgs args{JNI_VERSION_1_8, 2, opts, JNI_TRUE};
    void *env_holder = nullptr;
    jint rc = create(&vm, &env_holder, &args);
    std::fprintf(stderr, "[step 1] JNI_CreateJavaVM rc=%d, vm=%p\n",
                 rc, (void*) vm);
    return (rc == JNI_OK) ? 0 : 2;
}

static JNIEnv *env() {
    JNIEnv *e = nullptr;
    if (vm) vm->GetEnv((void**)&e, JNI_VERSION_1_8);
    return e;
}

int main(int argc, char **argv) {
    int step = (argc > 1) ? std::atoi(argv[1]) : 1;
    if (step < 1 || step > 5) {
        std::fprintf(stderr, "usage: %s <1..5>\n", argv[0]); return 1;
    }

    // Add the classpath + java.home to whatever step we run.
    if (do_create() != 0) return 2;

    if (step >= 2) {
        JNIEnv *e = env();
        jclass c = e->FindClass("javax/sound/sampled/AudioFormat");
        std::fprintf(stderr, "[step 2] AudioFormat = %p\n", (void*) c);
    }

    if (step >= 3) {
        JNIEnv *e = env();
        jclass c = e->FindClass("com/igormaznitsa/zxpoly/components/Motherboard");
        std::fprintf(stderr, "[step 3] Motherboard = %p\n", (void*) c);
        if (!c) {
            e->ExceptionDescribe();
            e->ExceptionClear();
        }
    }

    if (step >= 4) {
        JNIEnv *e = env();
        jclass mb = e->FindClass("com/igormaznitsa/zxpoly/components/Motherboard");
        jmethodID ctor = e->GetMethodID(mb, "<init>",
            "(Lcom/igormaznitsa/zxpoly/components/video/BorderWidth;"
            "Lcom/igormaznitsa/zxpoly/components/sound/VolumeProfile;"
            "Lcom/igormaznitsa/zxpoly/components/timing/TimingProfile;"
            "Lcom/igormaznitsa/zxpoly/components/RomData;"
            "Ljava/awt/Rectangle;"
            "Lcom/igormaznitsa/zxpoly/components/BoardMode;"
            "ZZZZZZ"
            "Lcom/igormaznitsa/zxpoly/components/video/VirtualKeyboardDecoration;"
            "ZZ)V");
        std::fprintf(stderr, "[step 4] Motherboard.<init> = %p\n",
                     (void*) ctor);
        if (!ctor) {
            e->ExceptionDescribe();
            e->ExceptionClear();
        }
    }

    if (step >= 5) {
        JNIEnv *e = env();
        std::fprintf(stderr, "[step 5] would call NewObject -- SKIPPED\n");
    }

    if (vm) vm->DestroyJavaVM();
    return 0;
}
