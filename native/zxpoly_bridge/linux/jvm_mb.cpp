// jvm_mb.cpp -- test the actual Motherboard constructor call.
// If this crashes, the issue is the Motherboard.<init> itself.

#include <jni.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <string>

int main() {
    void *lib = dlopen("libjvm.so", RTLD_NOW);
    if (!lib) return 1;
    auto create = (jint (*)(JavaVM **, void **, void *))
                  dlsym(lib, "JNI_CreateJavaVM");
    char xmx[32], cp[4096], jh[1024];
    std::snprintf(xmx, sizeof(xmx), "-Xmx256m");
    std::snprintf(cp, sizeof(cp), "-Djava.class.path=/home/jon/games/spectrum/zxpoly-emul.jar");
    std::snprintf(jh, sizeof(jh), "-Djava.home=/usr/lib/jvm/java-26-openjdk");
    JavaVMOption opts[] = { {xmx}, {cp}, {jh} };
    JavaVMInitArgs args{JNI_VERSION_1_8, 3, opts, JNI_TRUE};
    JavaVM *vm = nullptr;
    void *env_holder = nullptr;
    if (create(&vm, &env_holder, &args) != JNI_OK) return 2;
    JNIEnv *e = nullptr;
    vm->GetEnv((void**)&e, JNI_VERSION_1_8);

    std::fprintf(stderr, "[mb] FindClass(BorderWidth)...\n");
    jclass bw_cls = e->FindClass(
        "com/igormaznitsa/zxpoly/components/video/BorderWidth");
    std::fprintf(stderr, "[mb] bw_cls=%p\n", (void*) bw_cls);
    if (e->ExceptionCheck()) { e->ExceptionDescribe(); e->ExceptionClear(); }

    std::fprintf(stderr, "[mb] GetStaticFieldID(UNIVERSAL)...\n");
    jfieldID bw_field = e->GetStaticFieldID(bw_cls, "UNIVERSAL",
        "Lcom/igormaznitsa/zxpoly/components/video/BorderWidth;");
    std::fprintf(stderr, "[mb] bw_field=%p\n", (void*) bw_field);
    if (e->ExceptionCheck()) { e->ExceptionDescribe(); e->ExceptionClear(); }

    std::fprintf(stderr, "[mb] GetStaticObjectField...\n");
    jobject border = e->GetStaticObjectField(bw_cls, bw_field);
    std::fprintf(stderr, "[mb] border=%p\n", (void*) border);

    // Now try the GetMethodID that crashes: Beeper.getSoundPort
    std::fprintf(stderr, "[mb] GetMethodID(Beeper.getSoundPort)...\n");
    jclass bp = e->FindClass("com/igormaznitsa/zxpoly/components/sound/Beeper");
    jmethodID gsp = e->GetMethodID(bp, "getSoundPort",
        "()Ljava/util/Optional;");
    std::fprintf(stderr, "[mb] gsp=%p\n", (void*) gsp);
    if (e->ExceptionCheck()) {
        std::fprintf(stderr, "[mb] exception pending, clearing\n");
        e->ExceptionClear();
    }

    vm->DestroyJavaVM();
    return 0;
}
