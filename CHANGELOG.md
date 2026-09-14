# Changelog

## 0.28.0

- **One photograph, at one scale.** Reported with a Crystal battle at BATTLE
  SIZE = FILL: a crisp rectangle of backdrop in the middle of the screen and a
  visibly bigger, blurrier copy of the same scene around it, with a hard seam
  between them. It reads as a cut-out, and the cause was arithmetic.

  The field is painted **on the battle surface** — 160×144 or 304×144 — and
  the engine then scales that surface to the window. The bars around it were
  being filled by cover-fitting the *same picture to the whole window*, which
  is a different and always larger scale. So the screen carried one photograph
  at two magnifications with the surface's edge as the join, and the wider the
  window the worse it got.

  The bars take the surface's own scale and the surface's own alignment now,
  so the composite is one continuous image and the seam cannot exist. Nothing
  is stretched to reach: a bar the picture does not cover keeps the surround's
  colour rather than a blown-up smear of the field.

- **The art is picked for the shape of the screen, not for the setting.**
  BATTLE LAYOUT picks the *surface*; the art used to be picked to match it.
  That is right only while the surface is the whole picture. The moment the
  window is wider — which is what BATTLE SIZE = FILL does on any normal
  monitor — there are side bars, and a 160-wide picture has nothing outside
  itself to put in them.

  A 304×144 backdrop has 72 authored columns to spare on each side of a
  160-wide surface, so that is what gets asked for as soon as there are bars,
  on the classic surface too. It is centred at 1:1, so the field is exactly
  the picture it always was and the bars are the rest of the same photograph.

  Every slot has both sizes — all 31 scenes and all 27 town variants — so this
  changes which file is loaded and nothing else. Gold's recoloured town roofs
  have no wide version and fall through to the plain scene, as they already do
  when their folder is absent.

## 0.27.0

- **EDGE TO EDGE off left the backdrop standing in a white frame.** Reported
  with two screenshots side by side, every other mod disabled, on a PC window
  and on a handheld both.

  The white was never this mod's paint. `Renderer:endFrame` fills the void
  around the screen with the paper shade for any state that sets
  `letterboxWhite`, and a battle sets it *because its field is white paper* —
  so the paper reads as running off the edges of the screen instead of
  stopping at a rectangle. Put a photograph in the field and the paper is
  gone: the surround is then the only white left, and a white rectangle
  around a picture is a frame, not an edge.

  So turning the toggle off no longer means "leave the bars alone". The
  picture stops at the surface and the bars go where the engine puts them for
  a screen that never asked for paper — flat black, the same thing BATTLE BG
  = BLACK and FAITHFUL RATIO's mobile lock already give. EDGE TO EDGE is back
  to meaning the one thing it says: whether the picture reaches the edges.

  Through UI LETTERBOX rather than over it. The bar colour is composed with
  `Letterbox.fill` handed BLACK as the authored colour instead of the paper
  shade, so AUTO — the mode that was deducing white from `letterboxWhite` —
  comes back black, while BLACK, WHITE and PALETTE still come back as
  whatever the player asked for. Only the deduction changes.

  A battle the backdrop did not take is untouched: white paper running off
  the edge of the screen is right when the field really is white paper, and
  blacking that out would be this mod changing a battle it never entered.

## 0.26.0

- **A full-colour trainer is cut out of its square too.** Reported as "some
  trainers didn't appear with the background removed", with a screenshot of a
  SAILOR in a white box beside a player whose box was gone.

  The gate was a colour **count**: four is a 2bpp cart pic exactly, and a
  replacement trainer — skin, bandana, shirt, shading — has a dozen. Every one
  was refused, and the refusal was cached, so it kept its square for the whole
  battle while the cart's own pics were cut beside it.

  The count was standing in for a question it only answers by accident: *is
  this a figure in a field?* The **border** answers it directly — a figure
  standing in a square has the field, and only the field, all the way round
  it. Art that bleeds to its own edge does not, and is still left alone. The
  count stays as the free first gate, so nothing about the cart's own pics
  changes.

## 0.25.1

- **CI is green again.** `arenagen2paper_test.lua` asserted that an engine
  checkout is present, so on a runner that has none — which is every runner —
  it reported a failure instead of a skip. The reads that actually need a tree
  were already behind `if ENGINE`; the reads of this repo's own `main.lua`
  never needed one. No shipped behaviour changes.

## 0.25.0

- **The backdrop is painted with no shader bound.** Reported three times as
  "the battle is all greyscale", and the screenshot said it in one line: every
  pixel of the game screen was one of three DMG shades, and the one thing
  still in colour was the EXP bar — which is the one thing that calls
  `love.graphics.setShader()` before it paints.

  These draws are substituted *into* the cart's own draw, from a shim on
  `love.graphics.rectangle`, so whatever shader the caller had bound was still
  bound. For a flat fill that changes nothing. For a photograph it is the whole
  picture: the palette shader answers every pixel with one of four entries
  chosen off its red channel, so a FireRed terrain scene came back as four
  greys and the mod read as if it had never run. The bars around a wide battle
  carried the same picture and the same bug.

  The shader is put down for the length of the paint and handed back exactly
  as it was — this is the middle of the cart's draw, and the shade remap after
  it is the cart's.

