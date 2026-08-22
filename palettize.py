#!/usr/bin/env python3
"""Bring the FireRed battle backgrounds into Gen1Recomp's ADVANCED palette space.

Measured gap (weighted over every pixel of the 20 source backgrounds):

    FR pack        mean S = 0.372   mean V = 0.713
    ADVANCED       mean S = 0.674   mean V = 0.771

So the mismatch is almost entirely CHROMA, not brightness. That's why the
backgrounds read as washed out next to the mon sprites rather than as too dark
or too bright, and it's why a plain brightness/contrast tweak wouldn't have
fixed it.

Two passes, in this order:

1. Saturation curve. Rather than forcing every image to one saturation number
   (which would wreck the deliberately neutral interiors), fit a per-image
   exponent g so that mean(S**g) lands on that image's own target. Because it
   is a power curve, the relative ordering of every colour is preserved -- the
   shading inside the art still reads as shading.

   Colourful images (Grass, Forest, Sea) get pulled 70% of the way to the
   ADVANCED mean. Near-neutral ones (Indoors, Lab, Neutral) get a gentler lift
   capped well below it, because a grey lab wall is SUPPOSED to be grey; the
   problem there was washout, not neutrality.

2. GBC grid quantisation. Every resulting channel is rounded onto the Game
   Boy Color's 5-bit ladder, so no pixel is a colour the hardware could not
   have shown. See gbc_quantize() for why this replaced a nearest-neighbour
   snap into the SuperPalette gamut, which measured well and looked wrong.

Both passes run on the PALETTE, not the pixels: the sources are <=16-colour
indexed art, so the flat pixel-art blocking survives exactly.
"""

import colorsys
import sys
from pathlib import Path
from PIL import Image

GBC_MEAN_S = 0.674

# ---------------------------------------------------------------- colour

def srgb_to_lab(rgb):
    def lin(u):
        u /= 255.0
        return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(v) for v in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.00000
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def gbc_quantize(rgb):
    """Round each channel onto the Game Boy Color's 5-bit grid (32 levels).

    This replaced a nearest-neighbour snap into the 446-colour SuperPalette
    union, which looked principled and was wrong. That snap did not preserve
    LUMINANCE ORDER: Cave's mid-dark rock was pulled UP (32,41,49 -> 58,66,82)
    while its darkest shade was pulled DOWN to pure black (24,24,32 -> 0,0,0),
    because the SuperPalettes carry very few dark-but-not-black entries. The
    dark end of the ramp got stretched apart and drew hard black rims round
    the cave mouths that the original art never had.

    Quantising instead is monotonic per channel, so it can never reorder two
    shades or invent a rim -- and it still puts every colour on the grid the
    hardware could actually display, which was the real point.
    """
    return tuple(min(255, round(round(v / 255 * 31) / 31 * 255)) for v in rgb)


# ------------------------------------------------------------ saturation

def fit_gamma(sats, weights, target):
    """Exponent g with weighted mean(s**g) == target. Bisection; g<1 boosts."""
    total = sum(weights)
    if total == 0:
        return 1.0

    def mean(g):
        return sum(w * (s ** g) for s, w in zip(sats, weights)) / total

    lo, hi = 0.15, 4.0
    if mean(lo) < target:      # cannot reach it even fully boosted
        return lo
    if mean(hi) > target:
        return hi
    for _ in range(60):
        mid = (lo + hi) / 2
        if mean(mid) > target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def target_for(current, value):
    """How saturated this image SHOULD be.

    A grey interior should stay a grey interior -- pushing every background to
    one number would turn the Lab into a colour test card. So neutrals get a
    modest washout fix and everything else gets pulled most of the way to the
    ADVANCED mean.

    Dark scenes (Cave, Volcano) are held back further. At full strength Cave
    went a flat electric blue and got DARKER, which is the exact direction
    that makes a Gen 1 back sprite read as a silhouette -- the sprites borrow
    the field for their light shades.
    """
    if current < 0.25:
        return min(0.35, current * 1.9)
    strength = 0.70 if value >= 0.50 else 0.35
    return current + strength * (GBC_MEAN_S - current)


# ----------------------------------------------------------------- main

def correct(path: Path):
    im = Image.open(path).convert("RGBA")
    art = im.crop((0, 0, 240, 112))
    counts = {}
    for n, c in art.getcolors(70000):
        counts[c[:3]] = counts.get(c[:3], 0) + n

    cols = list(counts)
    weights = [counts[c] for c in cols]
    hsvs = [colorsys.rgb_to_hsv(*[v / 255 for v in c]) for c in cols]
    sats = [h[1] for h in hsvs]

    total = sum(weights)
    current = sum(s * w for s, w in zip(sats, weights)) / total
    meanv = sum(h[2] * w for h, w in zip(hsvs, weights)) / total
    g = fit_gamma(sats, weights, target_for(current, meanv))

    # Dark scenes get lifted toward the ADVANCED mean value as well, so the
    # player's back sprite keeps something to read against.
    vgain = 1.04 if meanv >= 0.50 else 1.18

    shifted = {}
    for c, (h, s, v) in zip(cols, hsvs):
        s2 = min(1.0, s ** g)
        v2 = min(1.0, v * vgain)
        shifted[c] = tuple(round(x * 255) for x in colorsys.hsv_to_rgb(h, s2, v2))

    mapping = {c: gbc_quantize(shifted[c]) for c in cols}

    out = im.copy().convert("RGBA")
    px = out.load()
    w, h_ = out.size
    for y in range(h_):
        for x in range(w):
            r, gg, b, a = px[x, y]
            m = mapping.get((r, gg, b))
            if m:
                px[x, y] = (m[0], m[1], m[2], a)

    after = sum(colorsys.rgb_to_hsv(*[v / 255 for v in mapping[c]])[1] * wt
                for c, wt in zip(cols, weights)) / total
    print(f"  {path.stem:20} S {current:.3f} -> {after:.3f}  "
          f"(gamma {g:.2f}, {len(cols)} shades kept)")
    return out


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    for f in sorted(src.glob("[0-9]*.png")):
        correct(f).save(dst / f.name)


if __name__ == "__main__":
    main()
