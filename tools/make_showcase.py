#!/usr/bin/env python3
"""Draw docs/*.png: what the backdrops actually look like.

Every tile in every sheet is a file straight out of assets/backdrops/, scaled
by a whole number with no resampling, so what a reader sees is the art the mod
loads and not an impression of it.  Nothing here is drawn, composited or
touched up.

    python3 tools/make_showcase.py           # redraw every sheet
    python3 tools/make_showcase.py towns     # ... or just the ones named

Sheets:
    scenes    the terrain and room slots, one tile each
    bosses    the six fights that carry a scene of their own
    towns     the per-town roof recolour, all ten side by side
    gyms      the per-town gym wall recolour
    layouts   one scene in both of the engine's layouts

Labels are set in Inter (SIL Open Font Licence 1.1, Rasmus Andersson), fetched
once into tools/.cache/.  The backdrops themselves are the Battle Backgrounds
Patch FR's -- see CREDITS.md, and carry those names with any of this art.

Needs Pillow:  pip install Pillow
"""

import pathlib
import re
import sys
import urllib.request

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OG = ROOT / "assets" / "backdrops" / "og"
WIDE = ROOT / "assets" / "backdrops" / "wide"
CACHE = ROOT / "tools" / ".cache"
DOCS = ROOT / "docs"

BG = (0x14, 0x17, 0x1a)
FRAME = (0x2a, 0x30, 0x36)
TEXT = (0xe8, 0xec, 0xf0)
MUTED = (0x93, 0x9d, 0xa8)

SCALE = 2            # whole-number, nearest-neighbour
PAD = 20
GAP = 14
NAME = 16            # slot-name type size
NOTE = 13            # the line under it


def gfont(weight, size):
    """Inter, fetched once and kept in tools/.cache/."""
    path = CACHE / f"Inter-{weight}.ttf"
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        css = f"https://fonts.googleapis.com/css2?family=Inter:wght@{weight}"
        with urllib.request.urlopen(css, timeout=30) as r:
            sheet = r.read().decode()
        m = re.search(r"url\((https://[^)]+\.ttf)\)", sheet)
        if not m:
            raise SystemExit(f"no TrueType URL for Inter {weight}")
        with urllib.request.urlopen(m.group(1), timeout=30) as r:
            path.write_bytes(r.read())
    return ImageFont.truetype(str(path), size)


def grid(tiles, cols, out, scale=SCALE, crop=None):
    """Lay out (path, name, note) tiles in a grid, each captioned.

    `crop` is a box taken out of every tile before it is scaled, for a sheet
    whose point lives in one corner of the art -- a roof, a gym wall -- and
    would be a handful of pixels at whole-scene size.
    """
    bold, plain = gfont(600, NAME), gfont(400, NOTE)
    shots = [(Image.open(p).convert("RGB").crop(crop) if crop
              else Image.open(p).convert("RGB"), n, note)
             for p, n, note in tiles]
    tw, th = shots[0][0].width * scale, shots[0][0].height * scale
    noted = any(s[2] for s in shots)
    caption = NAME + 6 + (NOTE + 4 if noted else 0)
    rows = (len(shots) + cols - 1) // cols

    width = PAD * 2 + cols * tw + (cols - 1) * GAP
    height = PAD * 2 + rows * (th + 10 + caption) + (rows - 1) * GAP
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)

    for i, (shot, name, note) in enumerate(shots):
        x = PAD + (i % cols) * (tw + GAP)
        y = PAD + (i // cols) * (th + 10 + caption + GAP)
        draw.rectangle((x - 1, y - 1, x + tw, y + th), outline=FRAME)
        img.paste(shot.resize((tw, th), Image.NEAREST), (x, y))
        draw.text((x, y + th + 10), name, font=bold, fill=TEXT)
        if note:
            draw.text((x, y + th + 10 + NAME + 6), note, font=plain, fill=MUTED)

    DOCS.mkdir(exist_ok=True)
    img.save(out)
    print(f"  {out.relative_to(ROOT)}  {width}x{height}  ({len(shots)} tiles)")


SHEETS = {}


def sheet(fn):
    SHEETS[fn.__name__] = fn
    return fn


@sheet
def scenes():
    """The terrain and room slots -- what a battle lands on, and when."""
    grid([
        (OG / "field.png", "field", "route grass, and the Safari Zone"),
        (OG / "forest.png", "forest", "Viridian Forest"),
        (OG / "cave.png", "cave", "caves and tunnels"),
        (OG / "water_cave.png", "water_cave", "surfing inside a cave"),
        (OG / "sea.png", "sea", "open coast, and the SS Anne decks"),
        (OG / "lake.png", "lake", "inland water, and every fishing rod"),
        (OG / "port.png", "port", "the Vermilion dock"),
        (OG / "plateau.png", "plateau", "Indigo Plateau"),
        (OG / "tower.png", "tower", "Pokemon Tower"),
        (OG / "gym.png", "gym", "gym leaders"),
        (OG / "trainer.png", "trainer", "a trainer on a route"),
        (OG / "indoor.png", "indoor", "anything inside a building"),
    ], 4, DOCS / "scenes.png")


@sheet
def bosses():
    """A boss scene outranks the room the fight happens in."""
    grid([
        (OG / "giovanni.png", "giovanni", "all three of his fights"),
        (OG / "lorelei.png", "lorelei", "Elite Four"),
        (OG / "bruno.png", "bruno", "Elite Four"),
        (OG / "agatha.png", "agatha", "Elite Four"),
        (OG / "lance.png", "lance", "Elite Four"),
        (OG / "champion.png", "champion", "OPP_RIVAL3, and nothing else"),
    ], 3, DOCS / "bosses.png")


@sheet
def towns():
    """Roofs change from town to town.  Nothing else does."""
    order = ["pallet", "viridian", "pewter", "cerulean", "lavender",
             "vermilion", "celadon", "fuchsia", "cinnabar", "saffron"]
    # Cropped to the roofline: at whole-scene size the recolour is a dozen
    # pixels in one corner, and the sheet would show ten identical plazas.
    grid([(OG / t / "town.png", t.upper(), "") for t in order],
         5, DOCS / "towns.png", scale=3, crop=(0, 0, 150, 46))


@sheet
def gyms():
    """Gym walls rotate to the town's roof hue; the floor and ball do not."""
    order = ["pewter", "cerulean", "vermilion", "celadon",
             "fuchsia", "saffron", "cinnabar", "viridian"]
    grid([(OG / t / "gym.png", t.upper(), "") for t in order],
         4, DOCS / "gyms.png", scale=2, crop=(0, 0, 160, 96))


@sheet
def layouts():
    """The same scene, cropped for each of the engine's two layouts."""
    bold, plain = gfont(600, NAME), gfont(400, NOTE)
    shots = [(Image.open(OG / "field.png").convert("RGB"), "OG", "160x144"),
             (Image.open(WIDE / "field.png").convert("RGB"), "WIDE", "304x144")]
    tiles = [(s.resize((s.width * SCALE, s.height * SCALE), Image.NEAREST), n, d)
             for s, n, d in shots]

    caption = NAME + 6 + NOTE + 4
    width = PAD * 2 + sum(t.width for t, _, _ in tiles) + GAP
    height = PAD * 2 + max(t.height for t, _, _ in tiles) + 10 + caption
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)

    x = PAD
    for tile, name, dims in tiles:
        draw.rectangle((x - 1, PAD - 1, x + tile.width, PAD + tile.height),
                       outline=FRAME)
        img.paste(tile, (x, PAD))
        draw.text((x, PAD + tile.height + 10), name, font=bold, fill=TEXT)
        draw.text((x, PAD + tile.height + 10 + NAME + 6), dims,
                  font=plain, fill=MUTED)
        x += tile.width + GAP

    DOCS.mkdir(exist_ok=True)
    img.save(DOCS / "layouts.png")
    print(f"  docs/layouts.png  {width}x{height}  (2 tiles)")


def main(argv):
    wanted = [a.lower() for a in argv] or list(SHEETS)
    unknown = [w for w in wanted if w not in SHEETS]
    if unknown:
        print(f"no such sheet: {', '.join(unknown)}", file=sys.stderr)
        print(f"try: {', '.join(SHEETS)}", file=sys.stderr)
        return 1
    for name in wanted:
        SHEETS[name]()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
