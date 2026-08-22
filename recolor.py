#!/usr/bin/env python3
"""Per-town recolours taken from the engine's own overworld colouring.

The authority here is `world.roofByMapIndex` in data/palettes_gbc.lua. It is
indexed by map index (the eleven city maps, 0..10) and holds exactly two
colours per town -- a roof light and a roof dark:

    0 Pallet     white / grey        6 Celadon    mint / green
    1 Viridian   green               7 Fuchsia    magenta / rose
    2 Pewter     blue-grey stone     8 Cinnabar   red
    3 Cerulean   sky blue            9 Indigo     violet
    4 Lavender   purple             10 Saffron    yellow / gold
    5 Vermilion  orange

That is the whole difference between one Kanto town and the next in the GBC
overworld: the ROOFS change and nothing else does. Grass stays green, water
stays blue, paths and stone stay as they are. So that is what these recolours
do, and why an earlier full-scene tint was wrong -- it was inventing a
difference the game does not have.

Two passes:

1. TOWN -- the roof browns are remapped onto that town's roof pair by
   luminance. The town art cooperates: its only saturated warm colours are the
   two roof browns (hue 20/28, sat ~0.7). Tree green (146) and water blue
   (195/228) are far outside the mask, and every structural colour -- stone,
   wood, path -- sits below 0.35 saturation. No positional guard needed.

2. GYM -- walls only, rotated to the town's roof hue. A whole-scene tint would
   drag the floor and the Poke Ball with it, and the ball should read as the
   same ball in every gym. The gym art does NOT separate on position, because
   the wall's bottom edge is diagonal; it separates on hue. Wall planks sit at
   324-360/0-5, the floor's orange at 24-31. The y<62 guard exists only
   because the Poke Ball's red is the same red as the wall.
"""

import colorsys
import os
import re
import sys
from pathlib import Path
from PIL import Image

PALETTES = os.environ.get(
    "GEN1RECOMP_PALETTES", "../gen1recomp/data/palettes_gbc.lua")

# map index -> tag, per pokered's map ordering
TOWNS = {
    0: "pallet", 1: "viridian", 2: "pewter", 3: "cerulean", 4: "lavender",
    5: "vermilion", 6: "celadon", 7: "fuchsia", 8: "cinnabar", 9: "indigo",
    10: "saffron",
}

TOWN_SLOTS = ["town", "trainer_town", "plateau"]
GYM_SLOTS = ["gym", "leader", "trainer_gym"]

ROOF_HUE = (12, 40)
ROOF_MIN_SAT = 0.55
WALL_ROWS = 62


def roof_pairs():
    src = open(PALETTES).read()
    i = src.index("    roofByMapIndex = {")
    blk = src[i:i + 1400]
    out = {}
    for m in re.finditer(
            r"\[(\d+)\] = \{\s*\{\s*(\d+), (\d+), (\d+),?\s*\},"
            r"\s*\{\s*(\d+), (\d+), (\d+),?\s*\},", blk):
        idx = int(m.group(1))
        if idx in TOWNS:
            out[TOWNS[idx]] = (
                tuple(int(m.group(k)) for k in (2, 3, 4)),
                tuple(int(m.group(k)) for k in (5, 6, 7)))
    return out


def luminance(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def gbc_quantize(rgb):
    return tuple(min(255, round(round(v / 255 * 31) / 31 * 255)) for v in rgb)


# ---------------------------------------------------------------- 1. roofs

def recolour_roofs(img, pair):
    """Remap the roof browns onto this town's roof light/dark pair."""
    light, dark = pair
    # The art's roof shades, measured: (206,132,66) light, (140,74,41) dark.
    lo, hi = 74.0, 152.0

    out = img.convert("RGBA")
    px = out.load()
    w, h = out.size
    cache = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            key = (r, g, b)
            m = cache.get(key)
            if m is None:
                hh, ss, _vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                deg = hh * 360
                if ROOF_HUE[0] <= deg <= ROOF_HUE[1] and ss >= ROOF_MIN_SAT:
                    t = (luminance(key) - lo) / (hi - lo)
                    t = max(0.0, min(1.0, t))
                    m = gbc_quantize(tuple(
                        round(dark[k] + (light[k] - dark[k]) * t)
                        for k in range(3)))
                else:
                    m = key
                cache[key] = m
            px[x, y] = (m[0], m[1], m[2], a)
    return out


# ------------------------------------------------------------ 2. gym walls

def recolour_walls(img, pair):
    """Rotate the wall's reds to the town's roof hue. Floor and ball stay."""
    light = pair[0]
    th, ts, _ = colorsys.rgb_to_hsv(*[v / 255 for v in light])
    sat_scale = min(1.0, ts * 1.15) if ts > 0.05 else 0.12

    out = img.convert("RGBA")
    px = out.load()
    w, h = out.size
    wall = round(WALL_ROWS * h / 144)
    cache = {}
    for y in range(min(wall, h)):
        for x in range(w):
            r, g, b, a = px[x, y]
            key = (r, g, b)
            m = cache.get(key)
            if m is None:
                hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                deg = hh * 360
                if (deg >= 300 or deg <= 12) and ss > 0.30:
                    m = gbc_quantize(tuple(round(c * 255) for c in
                        colorsys.hsv_to_rgb(th, min(1.0, ss * sat_scale), vv)))
                else:
                    m = key
                cache[key] = m
            px[x, y] = (m[0], m[1], m[2], a)
    return out


# ------------------------------------------------------------ 3. the tower

# FieldDefaults routes the Pokemon Tower by TILESET, not by map:
# `byTileset = { CEMETERY = "GRAYMON" }`. So the tower does not wear Lavender's
# palette at all -- it wears GRAYMON, and every CEMETERY map gets it. That
# makes this a change to the base `tower` slot rather than a per-town variant.
#
# GRAYMON is white / (214,132,181) / (123,107,148) / black. Used whole it comes
# out PINK: its midtone is a dusty rose and most of the art's luminance lands
# on it. Only the third stop, the grey-violet, gives the drained look the name
# promises -- so that is the one used here. This is an interpretation of the
# palette, not a transcription of it.
GRAYMON_STOP = (123, 107, 148)
TOWER_STRENGTH = 0.80
TOWER_DUSK = 0.85


def graymon(img):
    stops = [(255, 255, 255), GRAYMON_STOP, (0, 0, 0)]
    ramp = sorted(stops, key=luminance, reverse=True)
    ramp_l = [luminance(c) for c in ramp]

    def at(l):
        if l >= ramp_l[0]:
            return ramp[0]
        for i in range(len(ramp) - 1):
            hi, lo = ramp_l[i], ramp_l[i + 1]
            if lo <= l <= hi:
                t = 0.0 if hi == lo else (hi - l) / (hi - lo)
                a, b = ramp[i], ramp[i + 1]
                return tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))
        return ramp[-1]

    out = img.convert("RGBA")
    px = out.load()
    w, h = out.size
    cache = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            key = (r, g, b)
            m = cache.get(key)
            if m is None:
                t = at(luminance(key) * TOWER_DUSK)
                m = gbc_quantize(tuple(
                    round(key[k] + (t[k] - key[k]) * TOWER_STRENGTH)
                    for k in range(3)))
                cache[key] = m
            px[x, y] = (m[0], m[1], m[2], a)
    return out


def main():
    root = Path(sys.argv[1])
    pairs = roof_pairs()

    # The tower is not a per-town variant: every CEMETERY map wears GRAYMON.
    for layout in ("og", "wide"):
        f = root / layout / "tower.png"
        if f.exists():
            graymon(Image.open(f)).save(f)
            print(f"  tower     {layout}: GRAYMON {GRAYMON_STOP}")

    for tag, pair in sorted(pairs.items()):
        for layout in ("og", "wide"):
            srcdir = root / layout
            if not srcdir.is_dir():
                continue
            dstdir = srcdir / tag
            dstdir.mkdir(parents=True, exist_ok=True)
            n = 0
            for slot in TOWN_SLOTS:
                f = srcdir / f"{slot}.png"
                if f.exists():
                    recolour_roofs(Image.open(f), pair).save(dstdir / f.name)
                    n += 1
            for slot in GYM_SLOTS:
                f = srcdir / f"{slot}.png"
                if f.exists():
                    recolour_walls(Image.open(f), pair).save(dstdir / f.name)
                    n += 1
            if layout == "wide":
                print(f"  {tag:10} roof {pair[0]} / {pair[1]}  ({n} files)")


if __name__ == "__main__":
    main()
