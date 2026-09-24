# Linux build of the ZEsarUX-backed engine bridge. Same shape as
# the old zxpoly_bridge/linux/CMakeLists.txt, just simpler: no
# JNI, no libjvm -- only the ZEsarUX subprocess + ZRCP socket
# machinery the C ABI talks to.
cmake_minimum_required(VERSION 3.16)
project(emulator_bridge CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Threads REQUIRED)

# ---- Bridge sources ----------------------------------------------------
add_library(emulator_bridge SHARED
    ../bridge/zesarux_bridge.cpp)

target_include_directories(emulator_bridge PUBLIC ../bridge)
target_link_libraries(emulator_bridge PRIVATE Threads::Threads)

# A standalone smoke test that drives the bridge directly (no
# Flutter). Same shape as zxpoly_bridge/linux/zxpoly_smoke.cpp.
add_executable(emulator_smoke emulator_smoke.cpp)
target_link_libraries(emulator_smoke PRIVATE emulator_bridge Threads::Threads)
