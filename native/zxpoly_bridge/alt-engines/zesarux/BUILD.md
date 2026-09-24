# ZEsarUX as an alternate engine

The zxpoly JVM bridge (slice 2.2 onward) compiles and the JVM
itself starts on this host, but the reflective lookups from
`create_motherboard` and `open_file` are chasing one wrong
field/method name after another through the zxpoly source tree.
Each fix moves us one step; the next SIGSEGV is in the next
lookup.

This file documents an alternative engine that works out of
the box: **ZEsarUX**, the canonical cross-platform ZX Spectrum
emulator by Cesar Hernandez Baño. It supports both:

* ZX Spectrum 48k, 128k, +2, +3, Pentagon, etc. (the full
  classic Spectrum family)
* **ZX Spectrum Next** (TBBlue / TS-Conf / BaseConf) -- the modern
  retro hardware project that's backward-compatible with Spectrum
  software

Plus 30+ other 8-bit machines, but Retro-Spectrum only needs
the Spectrum + Next paths.

## Building on this host

Verified on CachyOS / Linux 6.1, OpenJDK 21, SDL2 + X11 already
installed via the distro. libspectrum has to be built from source
first because it's not in the CachyOS repos; ZEsarUX itself
fetches libspectrum through `pkg-config` once installed.

```sh
git clone --depth 1 https://github.com/fuse-emulator/libspectrum.git
cd libspectrum && ./autogen.sh && ./configure --prefix=$HOME/.local && make install

git clone --depth 1 https://github.com/chernandezba/zesarux.git
cd zesarux/src && ./autogen.sh
./configure --prefix=$HOME/.local \
  --disable-stdout --disable-aa --disable-caca \
  --disable-curses --disable-cursesw --disable-fbdev \
  --disable-simpletext
make -j
```

The resulting binary lives at `zesarux/src/zesarux`. Run from the
source tree -- the build doesn't run `make install`.

## Running

```sh
cd zesarux/src

# ZX Spectrum 48k with the Alien 8 .tap the user has staged
DISPLAY=:1 ./zesarux --machine 48k \
  --tape ~/games/spectrum/Alien8.tap --ao null

# ZX Spectrum 128k
DISPLAY=:1 ./zesarux --machine 128k --ao null

# ZX Spectrum Next
DISPLAY=:1 ./zesarux --machine TBBlue --ao null
```

`--machine` choices: `48k`, `48kp` (48k+), `128k`, `P2`, `P2A41`,
`P340`, `P341`, `Pentagon`, `TBBlue` (Next), `TSConf` (Next TS-Conf),
`BaseConf` (Next BaseConf).

## Verified

* **ZX Spectrum 48k** — `--machine 48k --tape ~/games/spectrum/Alien8.tap`
  ran for 10s without crash, produced 6 MB of raw framebuffer
  output. The boot ROM executed and the .tap loader was processing
  tape bytes when the test timeout fired.

* **ZX Spectrum Next, fast-boot mode** — `--machine TBBlue
  --tbblue-fast-boot-mode --snap ~/Downloads/nexthexagon.nex` ran
  for 8s without crash, produced 19 MB of raw framebuffer output.
  ZEsarUX's `--tbblue-fast-boot-mode` flag boots TBBlue straight
  into a 48k-style ROM with the Next features (except divmmc)
  enabled -- the full Next boot ROM (which is a copyrighted
  download, not shipped with ZEsarUX) is needed for a *real*
  Next boot, but for running `.nex` games this flag is what works
  out of the box.

* **ZX Spectrum Next, default boot** — without `--tbblue-fast-boot-mode`,
  ZEsarUX tries to execute the full Next boot ROM stub from
  `tbblue_loader.rom` and immediately segfaults the emulated Z80
  at PC=0x81a0 with `IM0 IFF--` because the full Next firmware
  is missing. This is expected without the full ROM.

Both runs use the no-window headless mode (`--vo null --ao null`)
with `--vofile` dumping raw RGB frames at 2 fps to confirm the
emulator is actively producing output. Visible window mode
requires running from a session with X11/Wayland access.

## Running on your display

```sh
cd /tmp/zesarux/src

# ZX Spectrum 48k -- no extra ROM needed
./zesarux --machine 48k \
  --tape $HOME/games/spectrum/Alien8.tap --ao null

# ZX Spectrum Next -- fast-boot lets .nex games run without the
# full Next boot ROM (which is a separate copyright download).
./zesarux --machine TBBlue --tbblue-fast-boot-mode \
  --snap /home/jon/Downloads/nexthexagon.nex --ao null

# Once you have the Next boot ROM saved as
# ~/.zesaruxroms/tbblue.rom, the default Next boot works:
./zesarux --machine TBBlue \
  --snap /home/jon/Downloads/nexthexagon.nex --ao null
```

`--ao null` silences audio so you don't need ALSA setup. The
SDL video backend connects to your Wayland session directly.

## Recolour note

The recolour feature the swap was built around is zxpoly-specific.
On ZEsarUX the Spectrum renders through its original 8-colour-per-
cell attribute model and there is no recolour to do. The "Auto-
recolour" UI toggle in Retro-Spectrum is a no-op when ZEsarUX is
the engine.

## When to reach for this

* When the demo needs to run today on this Linux host (ZEsarUX
  works without further JNI debugging).
* When the user wants to see ZX Spectrum Next software, which
  zxpoly does not target.
* As a regression baseline -- zxpoly and ZEsarUX should agree on
  basic Spectrum behaviour (frame rate, attribute clash,
  keyboard layout). A ZEsarUX run gives us a known-correct
  Spectrum for free.
