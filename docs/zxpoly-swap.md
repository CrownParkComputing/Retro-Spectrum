# zxpoly swap — long-form plan

Why Retro-Spectrum is changing its backend from UnrealSpeccyPortable to
[raydac/zxpoly](https://github.com/raydac/zxpoly), what that means for
existing users, and how the work is sequenced.

## The product reason

ZX-Spectrum games have an attribute clash: every 8×8 cell of the
screen has one colour pair shared by all 64 pixels in that cell. Move
a sprite across a cell boundary and it suddenly picks up the wrong
colours.

zxpoly sidesteps this by emulating **four Z80 CPUs in parallel**, each
owning one of R, G, B and Y, with their own 128K video RAM. The four
video RAMs combine into a 4-bit-per-pixel frame. The original Spectrum
loader runs on CPU 0; the game's graphics data is pre-distributed
across the other three CPUs; from the game's perspective the
attribute clash simply isn't there.

This means Retro-Spectrum can ship a **per-game auto-recolour** that
is automatic and one-tap reversible. The user picks a game from their
library, sees the full-colour version on first launch, and has a
toggle on the game card to fall back to the original look for
comparison. That is the feature this app exists to provide.

## What is being replaced

The current engine is the [CrownParkComputing fork of UnrealSpeccy
Portable](https://github.com/CrownParkComputing/SimpleSpeccy) — a
single Z80, 8-bit palette indices, attribute clash intact. The engine
sits on disk at `$HOME/StudioProjects/SimpleSpeccy` and is read by
CMake at configure time; it is not vendored into the Retro-Spectrum
repo. The bridge between the engine and the Flutter UI is a plain-C
ABI at `native/speccy_core/bridge/speccy_bridge.{h,cpp}` with 40
entry points modelled on SimpleSpeccy's original Android JNI.

After the swap:

- Engine on disk becomes a git submodule at
  `native/zxpoly_bridge/zxpoly` pointing at the CPC fork of zxpoly
  (branch `cpc`).
- Bridge ABI is rewritten as JNI calls into a JVM-hosted zxpoly,
  exposing the same 40 entry points plus `set_recolour` /
  `get_recolour`.
- Library name changes from `libspeccycore` to `libzxpolycore`.
- Play Store package changes from `app.simplespeccy` to `app.zxpoly`.
- The per-game `recolour` flag (default on) becomes the only new
  user-facing concept.

## What this means for existing SimpleSpeccy users

Retro-Spectrum's public promise today is that it ships under
`app.simplespeccy` so existing SimpleSpeccy installs upgrade in place.
That promise goes away. After the swap:

- The Play Store package is `app.zxpoly`, a separate install. Existing
  SimpleSpeccy users do not auto-upgrade.
- The library card model is the same (the user's `.tap`, `.z80`,
  `.sna` files are still the inputs) but the in-game rendering is
  different and **most existing games will not boot unmodified on the
  4-CPU configuration**. Stock ZX-Spectrum software drives one CPU.
- The recolour preprocess makes the common case work (the loader
  runs on CPU 0, the rest of the game's data is distributed), but
  games that actively use the bus or share state between the four
  CPUs in unexpected ways will need patching.

The Play Store listing copy needs to reflect this honestly: the app is
no longer "the Spectrum emulator" but "a recolouring-friendly Spectrum
emulator powered by zxpoly". The CPC site entry for retro-spectrum at
`src/data/apps.ts` is updated alongside.

## Sequencing

The work is split across four branches and three commits on this
branch:

| Branch | Work |
| --- | --- |
| `restructure/zxpoly-swap` (this one) | Rename directories and library, drop the SimpleSpeccy CMake dependency, rename the Play package, stub the bridge so the codebase still builds. CPC site entry updated. **No engine integration yet.** |
| `feature/zxpoly-jni-loader` | `JNI_CreateJavaVM`, class lookup cache, exception handling, JVM lifecycle on Android and Linux. The host process loads `zxpoly.jar` and can construct an emulator. |
| `feature/zxpoly-bridge` | The 40-entry-point ABI in `zxpoly_bridge.cpp` calling JNI methods. Audio, video, input, media, save state. |
| `feature/zxpoly-recolour-pipeline` | The recolour preprocess: read the game, distribute graphics data across CPUs 1–3, hand the loader to CPU 0. Synchronous inside `openFile()`. UI integration: per-game toggle on `MediaEntry`, default on. |

Each branch is small enough to review on its own. The first one
(renames only) does not break the working build — it just makes
`app.simplespeccy` → `app.zxpoly`, the library name, and removes the
disk-path dependency.

## What the bridge has to be careful about

zxpoly uses Java FFM (Foreign Function & Memory API) via input4j for
joystick. The bridge has to map Android MotionEvent / Linux evdev
into that model without going through the JVM on every event — at
50 Hz input poll that would dominate the render thread.

Audio is a JVM-side mixer (input4j, plus whatever zxpoly itself
synthesises). The AAudio sink on Android and SDL2 on Linux still
apply; the bridge hands the JVM output buffer through unchanged.

Save states are an open question. zxpoly does not (as of writing)
expose a serialise/deserialize API — the four-CPU state would all
have to be captured at once, and there is no obvious way for the JVM
side to give us a stable byte layout. We will probably skip save
states in the first release and treat that as a separate piece of
work once zxpoly itself grows the API.
