# Building the Spectrum core

The core is UnrealSpeccy Portable, from the SimpleSpeccy checkout. It is
**not vendored into this repo** -- the same convention Retro-C64 uses for
`VICE_SRC`. SimpleSpeccy stays the upstream and is tracked separately.

```sh
# Everything: configure, build, and run every scenario.
native/speccy_core/linux/check-core.sh

SKIP_BUILD=1 native/speccy_core/linux/check-core.sh   # reuse out/
SPECCY_SRC=/path/to/SimpleSpeccy native/speccy_core/linux/check-core.sh
```

`check-core.sh` is the gate before any Flutter work. DosboxMultiplatform
shipped a complete Flutter UI over `StubDosboxCore` and still does not run a
game; this exists so that cannot happen here.

## What the headless build leaves out, and why

No SDL, no GL, no window. That is possible because the core renders 8-bit
palette indices into `eUla::Screen()` and every backend converts them itself --
so `speccy_core_get_framebuffer` does the same conversion to RGBA8888, using
the palette built by the same bit formula as `platform/gles2/gles2.cpp`. The
colours a Flutter host draws therefore match the SDL2 and Android builds
exactly.

Consequently these are excluded from the source list:

| Excluded | Reason |
| --- | --- |
| `platform/sdl2`, `platform/gles2`, `platform/custom_ui` | No window, no GL context. |
| `tools/igdb`, `tools/image_loader` | Pull JNI / libpng / nlohmann-json; only the in-engine game browser used them, and Flutter replaces it. |
| `snapshot/screenshot` | The one thing wanting libpng. A host screenshots the framebuffer it is already drawing. |

`USE_UI` is deliberately **not** defined: the in-engine widget toolkit is
replaced by Flutter widgets.

## Traps found while getting this to link

- **`tools/options.cpp` does `#include <tinyxml2.h>`, with angle brackets.**
  Without `3rdparty/tinyxml2` on the include path the system
  `/usr/include/tinyxml2.h` wins, which declares `XMLNode::Value()`
  out-of-line where the vendored header inlines it. The `.so` then links with
  exactly one undefined symbol.
- **`Init`/`Done` are `static` in every adapter.** `android.cpp` and
  `sdl2.cpp` each define their own; the bridge defines a third
  (`CoreInit`/`CoreDone`). There is no `xPlatform::Init` to call.
- **Setting an option needs `Apply()` as well as `Set()`**, as
  `android.cpp`'s `SetOption` template does. `Set()` alone does nothing
  visible.
- **`xOptions::eOption<T>::Find` returns `eOption<T>*`,** not `eOptionInt*`.
- **Only `.sna` can be saved.** `eFileTypeSNA` is the sole `eFileType`
  overriding `Store()`; `.z80` and `.szx` are load-only.

## ROMs

Supplied as buffers via `speccy_core_set_rom` (the `-DUSE_EXTERN_RESOURCES`
path the Android build uses), not read from disk. Ids match `android.cpp`'s
`InitRom` switch exactly -- do not renumber them. ROMs are never committed.
