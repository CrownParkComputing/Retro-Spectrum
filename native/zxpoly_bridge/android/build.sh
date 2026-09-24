#!/bin/sh
# Build the zxpoly Android bridge against an NDK toolchain.
#
# This is the phase 1 stub. Phase 2 adds the JNI loader and the link
# against zxpoly.jar that the Gradle build drops into jniLibs/.
#
# Run from the project root:
#   native/zxpoly_bridge/android/build.sh
# or with explicit NDK + ABI:
#   ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/26.1 \
#   ANDROID_ABI=arm64-v8a \
#   native/zxpoly_bridge/android/build.sh
set -e

ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Android/Sdk/ndk}}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-26}"
BUILD_DIR="${BUILD_DIR:-native/zxpoly_bridge/android/build}"

if [ ! -d "${ANDROID_NDK_HOME}" ]; then
    echo "ANDROID_NDK_HOME=${ANDROID_NDK_HOME} does not exist." >&2
    echo "Set ANDROID_NDK_HOME or install the NDK." >&2
    exit 1
fi

cmake \
    -S native/zxpoly_bridge/android \
    -B "${BUILD_DIR}" \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${ANDROID_ABI}" \
    -DANDROID_PLATFORM="${ANDROID_PLATFORM}" \
    -DCMAKE_BUILD_TYPE=Release

cmake --build "${BUILD_DIR}" -j
