#!/usr/bin/env bash
# Builds libspeccycore.so for Android and drops it into the Flutter app's
# jniLibs, where Dart loads it by bare name.
#
# Mirrors Retro-C64's and Retro-Saturn's android/build.sh: the NDK's CMake
# toolchain, one ABI at a time, at the API level the family standardises on.
#
#   native/speccy_core/android/build.sh                    # arm64-v8a
#   ANDROID_ABI=x86_64 native/speccy_core/android/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Android/Sdk/ndk/28.2.13676358}}"
# 26 matches minSdk in flutter_app/android/app/build.gradle.kts. A core built
# above minSdk is an app that installs on devices it cannot run on.
API="${ANDROID_API:-26}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
SPECCY_SRC="${SPECCY_SRC:-$HOME/StudioProjects/SimpleSpeccy}"
BUILD_DIR="${BUILD_DIR:-$HERE/build/$ANDROID_ABI}"

if [ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]; then
    echo "FATAL: NDK toolchain not found at $NDK/build/cmake/android.toolchain.cmake" >&2
    echo "Set ANDROID_NDK_HOME or ANDROID_NDK_ROOT." >&2
    exit 1
fi
if [ ! -f "$SPECCY_SRC/speccy_handler.cpp" ]; then
    echo "FATAL: SimpleSpeccy engine sources not found at $SPECCY_SRC." >&2
    echo "The engine is upstream and not vendored here:" >&2
    echo "  git clone https://github.com/CrownParkComputing/SimpleSpeccy.git $SPECCY_SRC" >&2
    exit 1
fi

echo "==> configuring ($ANDROID_ABI, android-$API)"
cmake -S "$HERE" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="android-${API}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSPECCY_SRC="$SPECCY_SRC"

echo "==> building"
cmake --build "$BUILD_DIR" -j "$(nproc)"

DEST="$REPO_ROOT/flutter_app/android/app/src/main/jniLibs/$ANDROID_ABI"
mkdir -p "$DEST"
cp -f "$BUILD_DIR/libspeccycore.so" "$DEST/libspeccycore.so"

echo
echo "Installed: $DEST/libspeccycore.so"
file -b "$DEST/libspeccycore.so"
