# zxpoly bridge — the new engine under Retro-Spectrum

This directory replaces `native/speccy_core/`. The Flutter UI calls into
the bridge exactly as before; the bridge no longer talks to
UnrealSpeccyPortable — it talks to the **Java** engine
[raydac/zxpoly](https://github.com/raydac/zxpoly), loaded into the
process via JNI, with the parallel 4-CPU colour model underneath.

## Why a bridge, and why JNI

zxpoly is Java, Maven-built, JDK 22+. Retro-Spectrum is C++ (the audio
backends and the JNI loader) plus Flutter/Dart on top. The two meet at a
JNI boundary:

```
Dart (dart:ffi)  ──▶  C ABI in this directory
                       │
                       ▼
                   zxpoly_bridge.cpp
                       │  JNI calls
                       ▼
                   JVM (zxpoly.jar)
```

The C ABI is the same shape as before (`speccy_bridge.h` → renamed to
`zxpoly_bridge.h`). The Dart side does not change shape — only the
function it ultimately calls.

## Auto-recolour: the feature this whole swap exists for

zxpoly has four parallel Z80s each owning a colour channel. To use it
on a stock ZX-Spectrum game, the loader runs on CPU 0 and the game's
graphics data is pre-distributed across the other three CPUs. The
distribution is what the bridge calls **the recolour preprocess**.

It runs synchronously inside `zxpoly_bridge_open_file()` so the first
presented frame is already the recoloured version. No "engine warming
up" window, no toggle-flicker, no async state to manage.

The user-facing contract is a single boolean on the bridge:

```c
int  zxpoly_bridge_set_recolour(int enabled);   // 0 = off, 1 = on
int  zxpoly_bridge_get_recolour(void);          // current state
```

Default: `recolour = 1`. The Dart side maps this to a per-game toggle
in the library, default on. Toggle off and the bridge skips the
preprocess — the four CPUs still run (in SIMD lockstep) but on the
original un-recoloured graphics, giving the classic 8-colour-per-cell
Spectrum look.

## What the bridge has to do (phase 2)

The bridge is split into the same three pieces the old `speccy_core`
had, with the audio paths preserved verbatim (they were already
AAudio/SDL2 sinks, not engine-specific) and the engine-specific bits
replaced:

| File | Purpose |
| --- | --- |
| `bridge/zxpoly_bridge.{h,cpp}` | The plain-C ABI the Dart side calls |
| `bridge/audio_backend_android.cpp` | AAudio sink (unchanged) |
| `bridge/audio_backend_stub.cpp`   | No-op sink for headless tests |
| `android/CMakeLists.txt`          | Builds `libzxpolycore.so`, links zxpoly.jar |
| `android/jni_loader.cpp`          | `JNI_CreateJavaVM` + class lookup cache |
| `linux/CMakeLists.txt`            | Same library, JVM hosted by app-side launcher |
| `linux/jni_loader.cpp`            | JVM hosted by the executable |

The engine itself is **not vendored into this repo**. `zxpoly/` is a
git submodule of the [CrownParkComputing fork of zxpoly](
https://github.com/CrownParkComputing/zxpoly ) (created once the swap
is committed; upstream is `raydac/zxpoly`). The fork exists only so we
can hold a `cpc` branch with the Android-targeted patches.

## Current state — placeholder only

This directory is empty today. The phase 2 commit will add:

- `zxpoly_bridge.h` — the C ABI, with `set_recolour` / `get_recolour`
  alongside the 40 entry points the old `speccy_bridge.h` had.
- `zxpoly_bridge.cpp` — the implementation. Stubs return
  `ZXPOLY_ERR_UNIMPLEMENTED` until the JNI side is in.
- `jni_loader.cpp` — `JNI_CreateJavaVM`, cached class refs.
- `android/`, `linux/` — per-platform glue.

Until then, the working build still uses the old UnrealSpeccyPortable
engine at `native/speccy_core/`, which the Flutter UI continues to
talk to via the unchanged Dart FFI bindings.

## Build commands (placeholder)

```sh
# Submodule bootstrap (phase 2):
git submodule add https://github.com/CrownParkComputing/zxpoly.git \
    native/zxpoly_bridge/zxpoly
git -C native/zxpoly_bridge/zxpoly checkout cpc

# Linux build:
cmake -S native/zxpoly_bridge/linux -B native/zxpoly_bridge/linux/out \
    -DZXPOLY_SRC=$PWD/native/zxpoly_bridge/zxpoly
cmake --build native/zxpoly_bridge/linux/out -j

# Headless CI gate (mirrors the old check-core.sh):
native/zxpoly_bridge/linux/check-bridge.sh
```

## Migration from `speccy_core/`

| Was | Becomes |
| --- | --- |
| `native/speccy_core/bridge/speccy_bridge.h` | `native/zxpoly_bridge/bridge/zxpoly_bridge.h` |
| `native/speccy_core/bridge/speccy_bridge.cpp` | `native/zxpoly_bridge/bridge/zxpoly_bridge.cpp` |
| `libspeccycore.so` | `libzxpolycore.so` |
| `applicationId = "app.simplespeccy"` | `applicationId = "app.zxpoly"` |
| `SPECCY_SRC = $HOME/StudioProjects/SimpleSpeccy` | `ZXPOLY_SRC = native/zxpoly_bridge/zxpoly` (submodule) |
| Per-game `recolour` flag | Per-game `recolour` flag, default on |

The Flutter UI source tree (`flutter_app/`) is unchanged in shape —
only the FFI binding library name and the new `setRecolour` / `getRecolour`
calls land there.
