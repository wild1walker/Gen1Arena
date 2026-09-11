# Changelog

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

