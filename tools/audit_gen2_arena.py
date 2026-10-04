#!/usr/bin/env python3
"""Replay BACKDROPS' Gold rules over every map header in Crystal.

    python3 tools/audit_gen2_arena.py <pokecrystal checkout> [--all]

The in-game DIAGNOSTIC audit walks the maps of the game you are playing, and
that needs a cartridge.  This reads the same facts out of pret's disassembly
instead -- the tileset, the environment, the time-of-day palette and the
fishing group from data/maps/maps.asm -- and runs them through the tables in
main.lua, read out of the file rather than copied here, so
the answer is the shipped code's.

Prints one row per distinct (place, tileset, environment, palette) with the
maps that land there, then the water every map with a fishing group gets.
Read it for the wrong KIND of place: a town plaza under grass, a room under
the sky.  "Some locations have mismatched background" was answered this way.

Nothing here needs a ROM; pokecrystal is source.
"""

from __future__ import annotations

import collections
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent.parent
ARENA = HERE / "main.lua"


def lua_table(source, name):
    """name -> value for a flat `local NAME = { KEY = "value", ... }`."""
    match = re.search(r"local %s = \{(.*?)\n\}" % name, source, re.S)
    if not match:
        raise SystemExit("audit: %s is not in %s" % (name, ARENA))
    return dict(re.findall(r'\[?"?(\w+)"?\]?\s*=\s*"(\w+)"', match.group(1)))


def lua_set(source, name):
    match = re.search(r"local %s = \{(.*?)\n\}" % name, source, re.S)
    if not match:
        raise SystemExit("audit: %s is not in %s" % (name, ARENA))
    return set(re.findall(r"(\w+)\s*=\s*true", match.group(1)))


def headers(root):
    maps = (root / "data" / "maps" / "maps.asm").read_text(encoding="utf-8")
    consts = (root / "constants" / "map_constants.asm").read_text(
        encoding="utf-8")
    ids = re.findall(r"map_const (\w+),", consts)
    rows = [tuple(part.strip() for part in line.split(","))
            for line in re.findall(r"^\s*map (.*)$", maps, re.M)
            if line.count(",") == 7]
    if len(ids) != len(rows):
        raise SystemExit("audit: %d map constants but %d headers"
                         % (len(ids), len(rows)))
    return [(map_id,) + row for map_id, row in zip(ids, rows)]


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    root = pathlib.Path(argv[0])
    source = ARENA.read_text(encoding="utf-8")
    tilesets = lua_table(source, "TILESET_SLOT_GEN2")
    overrides = lua_table(source, "MAP_SLOT_GEN2")
    environments = lua_table(source, "ENVIRONMENT_SLOT_GEN2")
    sea = lua_set(source, "SEA_FISH")
    lake = lua_set(source, "LAKE_FISH")
    ocean = lua_set(source, "OCEAN_LANDMARK_GEN2")

    def place(map_id, tileset, environment):
        if map_id in overrides:
            return overrides[map_id]
        slot = tilesets.get(tileset)
        if slot:
            if slot == "field" and environment == "TOWN":
                return "town"
            return slot
        return environments.get(environment, "(default)")

    grouped = collections.defaultdict(list)
    water = []
    for row in headers(root):
        map_id, _, tileset, environment, landmark, _, _, palette, fish = row
        grouped[(place(map_id, tileset, environment), tileset, environment,
                 palette)].append(map_id)
        group = fish.replace("FISHGROUP_", "")
        # Water in a building is not a battle anybody has; water in a cave is
        # `water_cave` whatever the fish say.
        if environment not in ("TOWN", "ROUTE"):
            continue
        if group in sea:
            water.append((map_id, "sea", "fish " + group))
        elif group in lake:
            water.append((map_id, "lake", "fish " + group))
        else:
            answer = "sea" if landmark in ocean else "lake"
            water.append((map_id, answer, "landmark list"))

    for key in sorted(grouped, key=lambda k: (k[0], k[1], k[2], k[3])):
        slot, tileset, environment, palette = key
        print("%-10s %-28s %-8s %-13s %s" % (slot, tileset, environment,
                                             palette, " ".join(grouped[key])))
    print()
    if "--all" in argv:
        for map_id, answer, why in water:
            print("%-34s %-5s (%s)" % (map_id, answer, why))
    else:
        seas = sorted(map_id for map_id, answer, _ in water if answer == "sea")
        print("sea: " + " ".join(seas))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
