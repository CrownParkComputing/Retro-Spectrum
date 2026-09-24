# Retro-Spectrum

A ZX-Spectrum emulator for Android, iOS and Linux, built on
[raydac/zxpoly](https://github.com/raydac/zxpoly) — a multi-CPU
ZX-Spectrum 128 concept emulator written in Java (GPL-3.0).

## What makes this app different from every other Spectrum emulator

zxpoly runs **four Z80 CPUs in parallel**, each owning one of the colour
channels R, G, B and Y. The four independent video RAMs combine into a
single 4-bit-per-pixel frame, which eliminates the ZX Spectrum's
attribute-clash problem without changing ROM or OS.

Retro-Spectrum exposes this as a feature you can turn on per game:

- **Recolour** toggle on every game card, default on.
- On launch, the engine redistributes the game's graphics data across
  the four parallel CPUs and runs the original loader on CPU 0 — so
  the first presented frame is already the full-colour version. No
  flicker, no "wait for the engine to catch up".
- Toggle it off and the game runs unmodified on the same four CPUs in
  SIMD lockstep — a faithful rendering of the original 8-colour-per-cell
  Spectrum look, useful for comparison.

This is what the app exists to do. The auto-recolour is not an
afterthought; it is the product.

## Project layout

```
Retro-Spectrum/
├── flutter_app/                    Dart/Flutter UI (library, settings,
│                                   emulator screen, on-screen controls)
├── native/zxpoly_bridge/           JNI shim over the Java zxpoly engine
│   ├── bridge/                     Plain-C ABI the Dart side calls
│   ├── android/                    AAudio sink, JNI loader, Gradle glue
│   ├── linux/                      SDL2/Pulse sink, shared library build
│   └── zxpoly/                     Maven submodule of raydac/zxpoly (phase 2)
├── docs/                           Native build, recolour pipeline notes
└── store/play/                     Play Console listing assets
```

## Status

The Flutter UI, library, on-screen controls, audio settings, input
settings, paths setup and lifecycle wiring are working over the existing
UnrealSpeccyPortable engine. The swap to zxpoly is in progress on the
`restructure/zxpoly-swap` branch — see
[`native/zxpoly_bridge/README.md`](native/zxpoly_bridge/README.md) for
the bridge contract and `docs/zxpoly-swap.md` for the full plan.

## License

The Flutter UI and the bridge are Crown Park Computing Ltd, GPL-3.0-or-later.
The zxpoly engine is raydac / Igor Maznitsa, GPL-3.0. The full
corresponding source for any release is published alongside it on the
Play Store listing.
