#!/usr/bin/env python3
"""Makes the launcher icon fill its square instead of floating in it.

Two separate faults produced one symptom -- a small icon on a big plate:

  1. There was no mipmap-anydpi-v26/, so Android took the legacy path and
     shrank ic_launcher.png onto a white backing plate. Every other Retro-*
     app ships an adaptive icon; this one never got one.

  2. The adaptive FOREGROUND art filled about half of its canvas. Adaptive
     icons then crop the outer ~18% on every side, so half of a half is what
     actually reached the screen.

This crops each foreground to the art's real bounds and rescales it to the
full canvas, then writes the adaptive-icon XML. Run from flutter_app:

    python3 tool/fill_launcher_icon.py
"""

import os
from PIL import Image

RES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "android", "app", "src", "main", "res")

DENSITIES = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")

ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""


def fill(path):
    """Rescale the art in `path` so it spans the whole canvas."""
    im = Image.open(path).convert("RGBA")
    box = im.split()[3].getbbox()          # the art, without its padding
    if box is None:
        return None
    art = im.crop(box)
    side = max(art.size)
    # Square it first, so a non-square logo keeps its proportions rather than
    # being stretched to fit.
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
    out = square.resize(im.size, Image.LANCZOS)
    out.save(path)
    return im.size, box


def main():
    for density in DENSITIES:
        fg = os.path.join(RES, f"mipmap-{density}", "ic_launcher_foreground.png")
        if not os.path.exists(fg):
            print(f"  skip {density}: no foreground")
            continue
        size, box = fill(fg)
        print(f"  {density}: art {box[2]-box[0]}x{box[3]-box[1]} -> {size[0]}x{size[1]}")

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w") as handle:
            handle.write(ADAPTIVE)
        print(f"  wrote mipmap-anydpi-v26/{name}")


if __name__ == "__main__":
    main()
