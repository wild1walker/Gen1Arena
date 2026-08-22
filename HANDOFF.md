# Handoff — opening a PR for Gen1Arena

Read this before writing anything public.

## Attribution and privacy — non-negotiable

The author of this mod is to be referred to as **Wild**. Nothing else.

Do **not** put any of the following into commits, commit messages, branch
names, PR titles or descriptions, issue comments, code comments, file
metadata, or the README:

- Any real name, username, handle, email address, or account link
- Any filesystem path containing a home directory or user name
  (`/home/<name>/`, `/Users/<name>/`, `C:\Users\<name>\`)
- Any save-directory path from the author's machine, playthrough IDs, or save
  file contents
- Screenshots or captures containing a desktop, taskbar, window title,
  browser tab, notification, or device name
- Hardware, OS build, location, timezone, or hostname details
- Chat logs, transcripts, or any statement about who commissioned or
  requested the work
- Anything from the author's ROM dump or extracted game data

If a path is needed as an example, use a placeholder: `<love-save-dir>`,
`<playthrough-id>`, `~/…`.

Git specifics: set `user.name` to `Wild` and use a no-reply email. Check
`git log`, `git config --get user.email`, and any `Co-authored-by:` trailers
before pushing — the default identity on a machine will leak otherwise.
Squash before opening the PR if the history was made under a different name.

If a reviewer asks who built it or why, the answer is that Wild built it. Do
not elaborate.

## The art question -- decided, not closed

**Status: Wild's call is to ship the art the mod uses, with credit carried
prominently.** That decision is recorded here so this section is not read as
still-open. Everything below remains true and still governs anything further.

What was done: only the backdrops `pickBackdrop` can actually reach are
committed (see "What art ships" in the README), not the whole generated set
and not the source pack. Credit sits at the top of the README and in
`CREDITS.md`, and names every author of the pack.

What is still true: the redistribution terms are not resolved, only credited.
If one of the pack's authors objects, honour it. A PR to an upstream project
is a separate decision from a repo of Wild's own, and the paragraphs below
still apply to it.

**The bundled art is not clearly redistributable.** It comes from the
"Battle Backgrounds Patch FR" for Pokémon FireRed. Its authors ask for credit:

> LibertyTwins, princess-phoenix, carchagui, aveontrainer, WesleyFG,
> kWharever, worldslayer608, knizz

Two separate problems:

1. Some of that pack is original fan art and some is derived from FireRed's
   own assets. It is not possible to tell which is which from the files.
2. Gen1Recomp's mod rules forbid shipping ROM-derived content in a mod.

This is fine for a private install. It is **not** fine for a public
repository or a PR to an upstream project. Before opening a PR, do one of:

- **Split the repo**: publish the code, the three build scripts and the slot
  spec, and have users supply their own art pack. `convert.py` already takes
  a source directory, so this is mostly a matter of not committing
  `assets/backdrops/`.
- **Get explicit permission** from the pack's authors and record it.
- **Replace the art** with something originally drawn or clearly licensed.

Do not open a PR to an upstream project that carries `assets/backdrops/`
without resolving this. Raise it with Wild rather than deciding unilaterally.

## What is in this archive

    manifest.json          mod manifest (api 2, needs `engine_internals`)
    main.lua               the whole mod
    README.md              design notes, slot table, verification notes
    HANDOFF.md             this file
    convert.py             GBA source art -> layout-correct backdrops
    palettize.py           chroma correction into ADVANCED's palette range
    recolor.py             per-town roof recolours, gym walls, tower GRAYMON
    CREDITS.md             art credit, in full
    assets/backdrops/      generated art — see the art question above

## Build order

The three scripts run in sequence; each takes the previous one's output.

    python3 palettize.py <FR-Resources-dir> corrected/
    python3 convert.py   corrected/          assets/backdrops/
    python3 recolor.py   assets/backdrops/

`recolor.py` reads the engine's palette data. Point it at a checkout:

    GEN1RECOMP_PALETTES=/path/to/gen1recomp/data/palettes_gbc.lua \
      python3 recolor.py assets/backdrops/

## Things a reviewer will ask about

- **`engine_internals`.** The mod patches `BattleState.drawClassic`,
  `WideBattle.draw` and `BattleState.newWild`. It cannot work without it. The
  draw patches match the field fill by geometry and degrade to vanilla rather
  than crashing if the engine refactors. See the comments at the top of
  `main.lua`.
- **Swapping `love.graphics.rectangle`.** Deliberate, scoped to a single
  call, and restored in the same function. The alternative was copying a
  ~90-line function body that changes between releases.
- **`OCEAN_MAP` is hand-classified.** Nothing in the map data distinguishes a
  sea tile from a pond tile. This is the one table with no data behind it and
  should be labelled as such, not defended as derived.
- **The tower diverges from FireRed on purpose.** Documented in the README.

## Not yet verified

The DIAGNOSTIC audit's `G`/`W` columns were broken in the only run performed
against real data — `encDef.grass` is a `{rate, slots, buckets}` record and
the check tested `#enc.grass`, which is 0 for a record. Fixed in the code, but
never re-run. So the water paths (`sea`, `lake`, `water_cave`) and the
grass-encounter maps are reasoned, not observed. Say so if asked; do not claim
they are verified.
