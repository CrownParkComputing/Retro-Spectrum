// jvm_minimal.cpp -- the absolute minimum JNI_CreateJavaVM test.
// No classpath, no class lookup, no Motherboard construction, no
// audio, no nothing. Just dlopen libjvm, call JNI_CreateJavaVM,
// and exit. If this still SIGSEGVs, the JVM-in-JNI is the bug,
// not our bridge.

#include <jni.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>

int main(int argc, char **argv) {
    void *lib = dlopen("libjvm.so", RTLD_NOW);
    if (!lib) { std::fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    auto create = (jint (*)(JavaVM **, void **, void *))
                  dlsym(lib, "JNI_CreateJavaVM");
    if (!create) { std::fprintf(stderr, "dlsym: %s\n", dlerror()); return 1; }

    JavaVMOption opts[2];
    char xmx[32];
    std::snprintf(xmx, sizeof(xmx), "-Xmx128m");
    opts[0].optionString = xmx;
    opts[1].optionString = const_cast<char *>("-Djava.home=/usr/lib/jvm/java-26-openjdk");
    JavaVMInitArgs args{
        JNI_VERSION_1_8, 2, opts,
        JNI_TRUE
    };

    JavaVM *vm = nullptr;
    void *env_holder = nullptr;
    std::fprintf(stderr, "[minimal] calling JNI_CreateJavaVM...\n");
    jint rc = create(&vm, &env_holder, &args);
    std::fprintf(stderr, "[minimal] rc=%d, vm=%p\n", rc, (void*) vm);
    if (rc != JNI_OK) return 2;
    std::fprintf(stderr, "[minimal] SUCCESS\n");
    vm->DestroyJavaVM();
    dlclose(lib);
    return 0;
}
