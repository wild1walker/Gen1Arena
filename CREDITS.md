# Credits

## Battle backdrop art

Every image under `assets/backdrops/` is derived from the **Battle
Backgrounds Patch FR** for Pokemon FireRed. None of it was drawn for this
mod. The pack's authors ask for credit whenever it is used, and that
request is the condition this repository ships under:

> **LibertyTwins · princess-phoenix · carchagui · aveontrainer ·
> WesleyFG · kWharever · worldslayer608 · knizz**

If you use this mod, fork it, restyle it, or lift a single backdrop out of
it, carry those names with it. They are the reason there is anything to
look at behind a battle.

### What this mod did to their work

Nothing that changes authorship. The pipeline is mechanical:

- `palettize.py` — a per-image saturation curve and a 5-bit channel
  quantise, so GBA-authored art sits next to GBC sprites without reading
  washed out. No redrawing; the flat pixel-art blocking is left intact.
- `convert.py` — crops and mirror-pads the 240x112 GBA field to the two
  layouts the engine actually draws (160x144 and 304x144). Nothing is
  resampled: one backdrop pixel is one sprite pixel.
- `recolor.py` — remaps roof and gym-wall colours onto each Kanto town's
  roof pair, read out of the engine's own `palettes_gbc.lua`, and applies
  the GRAYMON palette to the Pokemon Tower.

The composition, the linework and the colour choices in every scene are
theirs.

### Scene assignments

The pack remaps most of FireRed's battle scenes onto the Gym scene. This
mod restores FireRed's own split instead — gym trainers, gym leaders,
Giovanni, each Elite Four member and the Champion each get the scene the
art was originally drawn for. The mapping is in the README's slot table,
and the source for it is `Backgrounds Table.txt` in the original pack.

## Also owed

- **Gen1Recomp** — the engine this mod patches, and the source of the
  overworld roof palettes in `data/palettes_gbc.lua` that drive the
  per-town recolours.
- **Pokemon Red / Blue / FireRed** are Nintendo / Creatures / GAME FREAK.
  This is an unofficial fan mod, distributed free, with no affiliation
  with or endorsement by any of them.

## Redistribution note

Parts of the source pack are original fan art and parts are derived from
FireRed's own assets, and the files do not distinguish between the two.
Only the subset of backdrops this mod actually loads is committed here —
see `HANDOFF.md`. If you are one of the pack's authors and want a change
in how your work is credited or carried here, that request is honoured.

Mod by **Wild**.
