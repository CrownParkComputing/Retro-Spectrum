// jvm_opts.cpp -- find which JVM option combination crashes.
// Tests different combinations to narrow down.

#include <jni.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>

int main(int argc, char **argv) {
    if (argc < 2) { std::fprintf(stderr, "usage: %s <test_name>\n", argv[0]); return 1; }

    void *lib = dlopen("libjvm.so", RTLD_NOW);
    if (!lib) return 1;
    auto create = (jint (*)(JavaVM **, void **, void *))
                  dlsym(lib, "JNI_CreateJavaVM");

    char cp[4096], jh[1024], xmx[32];
    std::snprintf(xmx, sizeof(xmx), "-Xmx256m");
    std::snprintf(cp, sizeof(cp), "-Djava.class.path=/home/jon/games/spectrum/zxpoly-emul.jar");
    std::snprintf(jh, sizeof(jh), "-Djava.home=/usr/lib/jvm/java-26-openjdk");

    const char *name = argv[1];
    JavaVMOption opts[8];
    int n = 0;
    opts[n++].optionString = xmx;
    opts[n++].optionString = cp;
    opts[n++].optionString = jh;
    if (std::strcmp(name, "client") == 0) {
        opts[n++].optionString = const_cast<char *>("-client");
    } else if (std::strcmp(name, "serial") == 0) {
        opts[n++].optionString = const_cast<char *>("-XX:+UseSerialGC");
    } else if (std::strcmp(name, "xint") == 0) {
        opts[n++].optionString = const_cast<char *>("-Xint");
    } else if (std::strcmp(name, "all") == 0) {
        opts[n++].optionString = const_cast<char *>("-client");
        opts[n++].optionString = const_cast<char *>("-XX:+UseSerialGC");
        opts[n++].optionString = const_cast<char *>("-Xint");
    } else if (std::strcmp(name, "base") == 0) {
        // no extra options
    } else if (std::strcmp(name, "client-xint") == 0) {
        opts[n++].optionString = const_cast<char *>("-client");
        opts[n++].optionString = const_cast<char *>("-Xint");
    }

    JavaVMInitArgs args{JNI_VERSION_1_8, n, opts, JNI_TRUE};
    JavaVM *vm = nullptr;
    void *env_holder = nullptr;
    std::fprintf(stderr, "[opts=%s n=%d] ", name, n);
    jint rc = create(&vm, &env_holder, &args);
    if (rc != JNI_OK) { std::fprintf(stderr, "rc=%d (CreateVM fail)\n", rc); return 2; }

    JNIEnv *e = nullptr;
    vm->GetEnv((void**)&e, JNI_VERSION_1_8);

    // Now do something heavy: FindClass + getDeclaredFields + read static
    jclass mb = e->FindClass("com/igormaznitsa/zxpoly/components/Motherboard");
    std::fprintf(stderr, "Motherboard=%p ", (void*) mb);

    if (mb) {
        // Try allocating a small Java object to stress the allocator
        jclass str_cls = e->FindClass("java/lang/String");
        if (str_cls) {
            jstring s = e->NewStringUTF("hello");
            std::fprintf(stderr, "str=%p ", (void*) s);
            e->DeleteLocalRef(s);
        }
        // Get a static field from Motherboard if any
        jclass cls_cls = e->FindClass("java/lang/Class");
        if (cls_cls) {
            jmethodID getName = e->GetMethodID(cls_cls, "getName",
                                              "()Ljava/lang/String;");
            if (getName && mb) {
                jstring name_s = (jstring)e->CallObjectMethod(mb, getName);
                std::fprintf(stderr, "name=%p ", (void*) name_s);
                if (name_s) {
                    const char *n = e->GetStringUTFChars(name_s, nullptr);
                    std::fprintf(stderr, "(\"%s\") ", n ? n : "?");
                    e->ReleaseStringUTFChars(name_s, n);
                }
                e->DeleteLocalRef(name_s);
            }
        }
    }

    std::fprintf(stderr, "OK\n");
    vm->DestroyJavaVM();
    return 0;
}
