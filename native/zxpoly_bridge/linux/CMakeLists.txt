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

# ---- Bridge sources ---------------------------------------------------
# Phase 1 stub. See bridge/zxpoly_bridge.h for the full surface and
# native/zxpoly_bridge/README.md for the phase 2 plan.
add_library(zxpoly_core SHARED
    ../bridge/zxpoly_bridge.cpp
    ../bridge/audio_backend_stub.cpp)

# Force the output filename to `libzxpolycore.so` (no underscore between
# `zxpoly` and `core`). The project() name is `zxpoly_core` for CMake
# target addressing, but the Dart side dlopens `libzxpolycore.so` and
# a mismatch fails the very first dlopen() in the Flutter app.
set_target_properties(zxpoly_core PROPERTIES OUTPUT_NAME zxpolycore)

target_include_directories(zxpoly_core PUBLIC ../bridge)
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
#   # The Java side is built by Maven; the bridge loads zxpoly.jar at
#   # runtime via JNI, with the JVM launched in-process by
#   # jni_loader.cpp.
