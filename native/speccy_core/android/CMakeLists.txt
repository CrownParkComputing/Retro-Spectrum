# Android build of the Retro-Spectrum core bridge.
#
# The counterpart to native/speccy_core/linux/CMakeLists.txt, and the same
# shape on purpose: the same engine sources, the same bridge, the same
# headless assumptions. The engine has no window and no GL context here
# either -- it renders palette-indexed bytes and the bridge converts them --
# so nothing platform-specific is needed beyond the io backend.
#
# Driven by build.sh, which points it at the NDK toolchain.
cmake_minimum_required(VERSION 3.22)
project(speccy_core_android CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

if(NOT DEFINED SPECCY_SRC)
    set(SPECCY_SRC "$ENV{HOME}/StudioProjects/SimpleSpeccy")
endif()
if(NOT EXISTS "${SPECCY_SRC}/speccy_handler.cpp")
    message(FATAL_ERROR
        "SimpleSpeccy sources not found at ${SPECCY_SRC}. "
        "Pass -DSPECCY_SRC=/path/to/SimpleSpeccy.")
endif()

find_package(Threads REQUIRED)

# ---- Engine sources -----------------------------------------------------
# Identical selection to the Linux build; see that file for why each
# exclusion is there.
file(GLOB_RECURSE SPECCY_CORE_SRC
    "${SPECCY_SRC}/z80/*.cpp"
    "${SPECCY_SRC}/snapshot/*.cpp"
    "${SPECCY_SRC}/devices/*.cpp"
    "${SPECCY_SRC}/tools/*.cpp")
list(APPEND SPECCY_CORE_SRC
    "${SPECCY_SRC}/file_type.cpp"
    "${SPECCY_SRC}/file_type_zip.cpp"
    "${SPECCY_SRC}/options_common.cpp"
    "${SPECCY_SRC}/speccy.cpp"
    "${SPECCY_SRC}/speccy_handler.cpp"
    "${SPECCY_SRC}/platform/platform.cpp"
    "${SPECCY_SRC}/platform/io.cpp"
    # Bionic has select(); this is the same file the Linux build uses, and
    # the engine has no Android-specific io backend of its own.
    "${SPECCY_SRC}/platform/linux/io_select_linux.cpp")

list(FILTER SPECCY_CORE_SRC EXCLUDE REGEX
    "tools/igdb|tools/image_loader|snapshot/screenshot")

set(SPECCY_3RD
    "${SPECCY_SRC}/3rdparty/minizip/unzip.c"
    "${SPECCY_SRC}/3rdparty/minizip/ioapi.c"
    "${SPECCY_SRC}/3rdparty/tinyxml2/tinyxml2.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../linux/linux_io.cpp")

add_library(speccycore SHARED
    ${SPECCY_CORE_SRC}
    ${SPECCY_3RD}
    "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/speccy_bridge.cpp")

target_include_directories(speccycore PRIVATE
    "${SPECCY_SRC}"
    "${SPECCY_SRC}/3rdparty"
    "${SPECCY_SRC}/3rdparty/minizip"
    "${SPECCY_SRC}/3rdparty/tinyxml2"
    "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")

# _LINUX, on Android, deliberately: Bionic is close enough for what the
# engine asks of it (select, POSIX file IO), and the engine has no _ANDROID
# path of its own. This mirrors what the Linux build defines.
target_compile_definitions(speccycore PRIVATE
    USE_EXTERN_RESOURCES USE_CONFIG USE_ZIP _LINUX)

# libz is part of the NDK sysroot, so no pkg-config -- unlike the Linux
# build, which finds it through PkgConfig::ZLIB.
target_link_libraries(speccycore PRIVATE z Threads::Threads)

target_compile_options(speccycore PRIVATE -w)

set_target_properties(speccycore PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
