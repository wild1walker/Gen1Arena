# Changelog

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

