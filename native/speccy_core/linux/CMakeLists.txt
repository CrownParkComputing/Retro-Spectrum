# Headless Linux build of the Retro-Spectrum core bridge.
#
# Builds libspeccycore.so -- the UnrealSpeccy Portable engine plus the plain-C
# bridge -- with no SDL, no GL and no window. This is what check-core.sh
# dlopens, and it is the gate the plan puts before any Flutter work: the core
# must boot a title and render frames with nothing else involved.
#
#   cmake -S native/speccy_core/linux -B native/speccy_core/linux/out
#   cmake --build native/speccy_core/linux/out -j
#
cmake_minimum_required(VERSION 3.16)
project(speccy_core CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# SPECCY_SRC points at the SimpleSpeccy checkout, the same convention
# Retro-C64 uses for VICE_SRC. The engine is deliberately NOT vendored into
# this repo: SimpleSpeccy stays the upstream and is tracked separately.
if(NOT DEFINED SPECCY_SRC)
    set(SPECCY_SRC "$ENV{HOME}/StudioProjects/SimpleSpeccy")
endif()
if(NOT EXISTS "${SPECCY_SRC}/speccy_handler.cpp")
    message(FATAL_ERROR
        "SimpleSpeccy sources not found at ${SPECCY_SRC}. "
        "Pass -DSPECCY_SRC=/path/to/SimpleSpeccy.")
endif()

find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(ZLIB REQUIRED IMPORTED_TARGET zlib)

# ---- Engine sources -----------------------------------------------------
# The portable engine only. No platform/sdl2, no platform/gles2, no
# platform/custom_ui: this build has no window and no GL context, which is
# possible because the core renders palette-indexed bytes and the bridge does
# the colour conversion itself.
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
    "${SPECCY_SRC}/platform/linux/io_select_linux.cpp")

# IGDB and the image loader pull JNI / libpng / nlohmann-json and are only
# used by the in-engine game browser, which a Flutter host replaces.
# snapshot/screenshot.cpp is the only thing that wants libpng, and it exists
# to write .png screenshots. A Flutter host screenshots from the framebuffer
# it is already drawing, so dropping it keeps the .so free of libpng.
list(FILTER SPECCY_CORE_SRC EXCLUDE REGEX
    "tools/igdb|tools/image_loader|snapshot/screenshot")

set(SPECCY_3RD
    "${SPECCY_SRC}/3rdparty/minizip/unzip.c"
    "${SPECCY_SRC}/3rdparty/minizip/ioapi.c"
    "${SPECCY_SRC}/3rdparty/tinyxml2/tinyxml2.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/linux_io.cpp")

add_library(speccycore SHARED
    ${SPECCY_CORE_SRC}
    ${SPECCY_3RD}
    "${CMAKE_CURRENT_SOURCE_DIR}/../bridge/speccy_bridge.cpp")

target_include_directories(speccycore PRIVATE
    "${SPECCY_SRC}"
    "${SPECCY_SRC}/3rdparty"
    "${SPECCY_SRC}/3rdparty/minizip"
    # tools/options.cpp does #include <tinyxml2.h>. Without this the system
    # /usr/include/tinyxml2.h wins, and it declares XMLNode::Value()
    # out-of-line where the vendored header inlines it -- the .so then links
    # with exactly one undefined symbol.
    "${SPECCY_SRC}/3rdparty/tinyxml2"
    "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")

# USE_EXTERN_RESOURCES: ROMs arrive as buffers via speccy_core_set_rom rather
# than being read from disk, the same path the Android build uses.
# No USE_UI: the in-engine widget toolkit is replaced by Flutter widgets.
target_compile_definitions(speccycore PRIVATE
    USE_EXTERN_RESOURCES USE_CONFIG USE_ZIP _LINUX)

target_link_libraries(speccycore PRIVATE PkgConfig::ZLIB Threads::Threads)

# The engine is old C++ and warns heavily; -w matches what build/linux does.
target_compile_options(speccycore PRIVATE -w)

# ---- Host-side check ----------------------------------------------------
add_executable(check_core "${CMAKE_CURRENT_SOURCE_DIR}/check-core.c")
target_include_directories(check_core PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../bridge")
target_link_libraries(check_core PRIVATE ${CMAKE_DL_LIBS})
