# Android build of the zxpoly bridge.
#
# Builds libzxpolycore.so -- the plain-C ABI in bridge/zxpoly_bridge.h
# plus the AAudio sink in bridge/audio_backend_android.cpp. The JVM-
# hosted zxpoly engine is added in phase 2 by way of:
#
#   add_subdirectory(${ZXPOLY_SRC}/native ${CMAKE_BINARY_DIR}/zxpoly_native)
#
# Until then, the bridge is a stub: the library links, the Flutter app
# boots into the library screen, and any attempt to start emulation
# fails with the message from zxpoly_bridge_run_frame().
#
# Driven by build.sh, which points it at the NDK toolchain.
cmake_minimum_required(VERSION 3.22)
project(zxpoly_core_android CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Threads REQUIRED)

# ---- Bridge sources ---------------------------------------------------
# Phase 1 stub. Every entry point in zxpoly_bridge.h returns
# ZXPOLY_ERR_NOTIMPL except set/get_recolour and the lifecycle +
# audio drain no-ops. The phase 2 commit adds the JNI loader.
add_library(zxpoly_core SHARED
    ../bridge/zxpoly_bridge.cpp
    ../jni/jni_loader.cpp
    ../bridge/audio_backend_android.cpp)

# Force the output filename to `libzxpolycore.so` (no underscore between
# `zxpoly` and `core`). The project() name is `zxpoly_core` for CMake
# target addressing, but the Dart side dlopens `libzxpolycore.so` and
# a mismatch fails the very first dlopen() in the Flutter app.
set_target_properties(zxpoly_core PROPERTIES OUTPUT_NAME zxpolycore)

target_include_directories(zxpoly_core PUBLIC ../bridge ../jni)
target_link_libraries(zxpoly_core PRIVATE Threads::Threads)

# Engine integration (phase 2):
#
#   set(ZXPOLY_SRC "$ENV{HOME}/StudioProjects/zxpoly" CACHE PATH
#       "Path to the zxpoly checkout, or the submodule at "
#       "native/zxpoly_bridge/zxpoly")
#   if(NOT EXISTS "${ZXPOLY_SRC}/pom.xml")
#       message(FATAL_ERROR "zxpoly sources not found at ${ZXPOLY_SRC}. "
#                            "Pass -DZXPOLY_SRC=/path/to/zxpoly.")
#   endif()
#   # The Java side is built by Gradle / Maven, not CMake. The bridge
#   # loads the resulting zxpoly.jar from jniLibs/ at runtime via JNI.
