#!/usr/bin/env python3
"""Convert the FireRed Battle Backgrounds patch resources into Kanto Arenas
backdrops.

Source art is a 240x112 GBA battlefield sitting in a 256x512 sheet (the art is
duplicated in the top and bottom halves; only the top-left 240x112 matters).

Targets, read out of the engine source rather than guessed:
  OG    battlefield 160x96   (BattleState:drawClassic scissors pics to y<96)
  WIDE  battlefield 304x104  (WideBattle.FIELD_BOTTOM = 104)

Both surfaces are 144 tall; the rows below the battlefield sit under an opaque
message window, so they are filled with a flat colour sampled from the art
rather than stretched (stretching the bottom row produces vertical streaks).

Everything stays at native resolution - no resampling - so a backdrop pixel is
the same size as a sprite pixel. The cost is cropping: OG shows the middle 160
columns of 240, and WIDE mirror-pads 32 columns onto each side.
"""

from PIL import Image
from pathlib import Path
from collections import Counter
import sys

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])

ART_W, ART_H = 240, 112
SURFACE_H = 144
OG_W, OG_FIELD_H = 160, 96
WIDE_W, WIDE_FIELD_H = 304, 104

# FireRed background -> Kanto Arenas slot. Multiple slots may share one image.
MAPPING = {
    # Terrain scenes, unchanged from FireRed's own use of them.
    "0 Grass":      ["default", "field", "safari"],
    "1 Forest":     ["forest"],
    "7 Cave":       ["cave"],
    "6 Mountain":   ["plateau"],
    "2 Beach":      ["port"],
    "4 Sea":        ["sea", "deck"],
    "5 Lake":       ["lake"],
    "3 Underwater": ["water_cave"],

    # FireRed's trainer scenes, per "Backgrounds Table.txt":
    #   8  Indoor Trainer   9  Outdoor Trainer
    #   11 Gym Trainer      12 Gym Leader        13 Pokemon Tower
    "8 Lab":        ["trainer_indoor"],
    "9 Route":      ["trainer", "trainer_field"],
    "11 Neutral":   ["trainer_gym"],
    "12 Gym":       ["gym", "leader"],
    # 13 is FireRed's Pokemon Tower scene, but the patch author drew it as an
    # outdoor town view -- a paved plaza under open sky, for a battle on the
    # fourth floor of a building. The tower takes the Indoors art instead and
    # 13 keeps the town slots it genuinely suits.
    "13 Town":      ["town", "trainer_town"],

    # The five "homeless" backgrounds were never homeless -- they are the
    # boss scenes, and Space is the Champion.
    "14 Snow":          ["giovanni"],
    "15 Snow Cave":     ["lorelei"],
    "16 Snow Mountain": ["bruno"],
    "17 Desert":        ["agatha"],
    "18 Volcano":       ["lance"],
    "19 Space":         ["champion"],

    # Generic interiors. FireRed hardcodes this one to Trainer Tower, which
    # Kanto does not have, so it serves as the building fallback instead.
    "10 Indoors":   ["indoor", "museum", "club", "mansion", "ship", "tower"],
}


def load_art(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA").crop((0, 0, ART_W, ART_H))


def fill_colour(art: Image.Image):
    """Dominant colour of the lowest few rows - the ground the art sits on."""
    band = art.crop((0, art.height - 4, art.width, art.height))
    return Counter(band.getdata()).most_common(1)[0][0]


def compose(art: Image.Image, width: int, field_h: int) -> Image.Image:
    # Take the BOTTOM field_h rows: the mons stand at the bottom of the field,
    # so the ground line has to land there. Sky is what gets trimmed.
    band = art.crop((0, ART_H - field_h, ART_W, ART_H))
    out = Image.new("RGBA", (width, SURFACE_H), fill_colour(art))

    if width <= ART_W:
        # Centre-crop: keep native pixels, show less scene.
        left = (ART_W - width) // 2
        out.paste(band.crop((left, 0, left + width, field_h)), (0, 0))
    else:
        # Mirror-pad the sides. Better than stretching an edge column, which
        # smears whatever detail that column happens to contain.
        pad = (width - ART_W) // 2
        rest = width - ART_W - pad
        out.paste(band.crop((0, 0, pad, field_h))
                      .transpose(Image.FLIP_LEFT_RIGHT), (0, 0))
        out.paste(band, (pad, 0))
        out.paste(band.crop((ART_W - rest, 0, ART_W, field_h))
                      .transpose(Image.FLIP_LEFT_RIGHT), (pad + ART_W, 0))
    return out


def main():
    for layout, (w, fh) in {"og": (OG_W, OG_FIELD_H),
                            "wide": (WIDE_W, WIDE_FIELD_H)}.items():
        (OUT / layout).mkdir(parents=True, exist_ok=True)

    written = 0
    for stem, slots in MAPPING.items():
        path = SRC / f"{stem}.png"
        if not path.exists():
            print(f"  MISSING {stem}")
            continue
        art = load_art(path)
        for layout, (w, fh) in {"og": (OG_W, OG_FIELD_H),
                                "wide": (WIDE_W, WIDE_FIELD_H)}.items():
            img = compose(art, w, fh)
            for slot in slots:
                img.save(OUT / layout / f"{slot}.png")
                written += 1
        print(f"  {stem:14} -> {', '.join(slots)}")
    print(f"{written} files written")


if __name__ == "__main__":
    main()
