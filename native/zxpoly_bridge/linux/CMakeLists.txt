# Headless Linux build of the zxpoly bridge.
#
# Builds libzxpolycore.so -- the plain-C ABI in bridge/zxpoly_bridge.h
# plus the no-op audio sink in bridge/audio_backend_stub.cpp. The JVM
# is launched by the host process in phase 2; this build is the gate
# that runs before any Flutter work, so a stub-only library that links
# and dlopens is enough today.
#
#   cmake -S native/zxpoly_bridge/linux -B native/zxpoly_bridge/linux/out
#   cmake --build native/zxpoly_bridge/linux/out -j
cmake_minimum_required(VERSION 3.16)
project(zxpoly_core CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Threads REQUIRED)

# When the host has a JDK in PATH, expose its include directory to
# the C++ preprocessor so the JNI bridge (which gates every method
# on `__has_include(<jni.h>)`) actually lights up. On hosts without
# a JDK this is a no-op -- the gate stays closed and every method
# returns ZXPOLY_ERR_NOTIMPL, which is the documented behaviour.
if(DEFINED ENV{JAVA_HOME})
    set(_zxpoly_jdk_include "$ENV{JAVA_HOME}/include")
    if(EXISTS "${_zxpoly_jdk_include}/jni.h")
        message(STATUS
            "JNI headers from JAVA_HOME=$ENV{JAVA_HOME} -> bridge will "
            "load the JVM at runtime")
        # jni_md.h lives under a platform subdir; on Linux that's
        # include/linux/jni_md.h. Include both so the preprocessor
        # finds the architecture-specific typedefs jni.h pulls in.
        include_directories(SYSTEM "${_zxpoly_jdk_include}")
        if(EXISTS "${_zxpoly_jdk_include}/linux/jni_md.h")
            include_directories(SYSTEM "${_zxpoly_jdk_include}/linux")
        endif()
        # libjvm.so exposes JNI_CreateJavaVM and friends; link the
        # bridge against it so dlopen succeeds at runtime. On Android
        # libjvm lives in libnativehelper -- the Android CMakeLists
        # points the linker at it instead.
        find_library(_zxpoly_libjvm
            NAMES jvm
            PATHS "$ENV{JAVA_HOME}/lib" "$ENV{JAVA_HOME}/lib/server"
            NO_DEFAULT_PATH REQUIRED)
        message(STATUS
            "Linking bridge against libjvm at ${_zxpoly_libjvm}")
    else()
        message(STATUS
            "JAVA_HOME is set but jni.h is missing at "
            "${_zxpoly_jdk_include}; bridge stays in stub mode")
    endif()
endif()

# ---- Bridge sources ---------------------------------------------------
# Phase 1 stub. See bridge/zxpoly_bridge.h for the full surface and
# native/zxpoly_bridge/README.md for the phase 2 plan.
add_library(zxpoly_core SHARED
    ../bridge/zxpoly_bridge.cpp
    ../jni/jni_loader.cpp
    ../bridge/audio_backend_stub.cpp)

# Force the output filename to `libzxpolycore.so` (no underscore between
# `zxpoly` and `core`). The project() name is `zxpoly_core` for CMake
# target addressing, but the Dart side dlopens `libzxpolycore.so` and
# a mismatch fails the very first dlopen() in the Flutter app.
set_target_properties(zxpoly_core PROPERTIES OUTPUT_NAME zxpolycore)

target_include_directories(zxpoly_core PUBLIC ../bridge ../jni)
if(_zxpoly_libjvm)
    target_link_libraries(zxpoly_core PRIVATE ${_zxpoly_libjvm})
endif()
target_link_libraries(zxpoly_core PRIVATE Threads::Threads)

# A standalone smoke test that drives the bridge directly (no
# Flutter). Lets you confirm the JNI bridge is alive end-to-end
# before the GUI is involved.
add_executable(zxpoly_smoke zxpoly_smoke.cpp)
target_link_libraries(zxpoly_smoke PRIVATE Threads::Threads)

# Engine integration (phase 2):
#
#   set(ZXPOLY_SRC "$ENV{HOME}/StudioProjects/zxpoly" CACHE PATH
#       "Path to the zxpoly checkout, or the submodule at "
#       "native/zxpoly_bridge/zxpoly")
#   if(NOT EXISTS "${ZXPOLY_SRC}/pom.xml")
#       message(FATAL_ERROR "zxpoly sources not found at ${ZXPOLY_SRC}. "
#                            "Pass -DZXPOLY_SRC=/path/to/zxpoly.")
#   endif()
#   # The Java side is built by Maven; the bridge loads zxpoly.jar at
#   # runtime via JNI, with the JVM launched in-process by
#   # jni_loader.cpp.
