-- The Gen 2 battle composite, transcribed from the engine rather than guessed.
--
-- Every number here has a source line in gen1recomp and is repeated in the
-- comment above it, because the whole point of this file is that it is NOT a
-- model of what the engine probably does: three arena changes in a row were
-- reasoned out on paper, shipped, and judged worse on the user's phone, and
-- each time the thing that was wrong was a rectangle nobody could see.
--
-- What it reproduces, in the engine's own order, for a WIDE Gen 2 battle:
--
--   src/ui/gen2/WideBattle.lua:47  WideBattle.draw
--     Chrome.letterbox(w, h, 1, 1, 1)      the whole window, paper
--     panel at fitOriginFor(38, 18 tiles) * battlePanelScale
--   src/core/Game2.lua:1744       paintBattleSurround  (BG black/world only)
--   src/core/Game2.lua:1422       Game2:letterbox      the mod hook
--
-- and the one fact this harness exists to make visible:
--
--   Game2:letterbox hands the mod `vpw = 160 * Chrome.fitScale(w, h)`.
--   That is the CLASSIC panel at the CLASSIC integer scale.  A wide battle
--   is 304 x 144 at `battlePanelScale`, which is a different size AND a
--   different origin.  So on Gen 2 the payload the arena builds all of its
--   geometry from does not describe the rectangle the battle was drawn in.

local E = {}

E.SCREEN_W, E.SCREEN_H = 20, 18          -- Chrome.SCREEN_W / SCREEN_H
E.WIDE_TILES_W, E.WIDE_TILES_H = 38, 18  -- WideBattle.TILES_W / TILES_H
E.WIDE_W, E.WIDE_H = 304, 144
E.OG_W, E.OG_H = 160, 144
E.FIELD_X = 72                           -- WideBattle.FIELD_X
E.EXTRA_TILES = 18                       -- WideBattle.EXTRA_TILES

-- src/render/Playfield.lua:34.  With no touch skin the playfield IS the
-- window; with one it is the cutout the skin leaves, which is the case on a
-- phone and is why `skin` is a parameter rather than an assumption.
function E.playfield(w, h, skin)
  if skin then return skin.x, skin.y, skin.w, skin.h end
  return 0, 0, w, h
end

-- src/ui/gen2/Chrome.lua:86.  Integer, floor, never below 1.
function E.fitScaleFor(w, h, tilesW, tilesH, skin)
  local _, _, pw, ph = E.playfield(w, h, skin)
  return math.max(1, math.floor(math.min(pw / (tilesW * 8), ph / (tilesH * 8))))
end

function E.fitScale(w, h, skin)
  return E.fitScaleFor(w, h, E.SCREEN_W, E.SCREEN_H, skin)
end

-- src/ui/gen2/Chrome.lua:110.  A skin being active zeroes the lift outright
-- (ScreenPosition.skinActive), so on a phone this is 0 and the panel is
-- centred in the cutout.
function E.positionLift(w, h, panelH, skin, mode, safeTop)
  if skin then return 0 end
  mode = mode or "center"
  if mode == "center" then return 0 end
  local _, _, _, ph = E.playfield(w, h, skin)
  local slack = ph - panelH
  if slack <= 0 then return 0 end
  local centered = math.floor(slack / 2)
  local target = mode == "top" and 0 or math.floor(slack / 4)
  safeTop = math.floor(safeTop or 0)
  if safeTop > 0 and target < safeTop then target = math.min(safeTop, centered) end
  return centered - target
end

-- src/ui/gen2/Chrome.lua:91
function E.fitOriginFor(w, h, scale, tilesW, tilesH, skin, mode, safeTop)
  local x, y, pw, ph = E.playfield(w, h, skin)
  local panelH = tilesH * 8 * scale
  return x + math.floor((pw - tilesW * 8 * scale) / 2),
         y + math.floor((ph - panelH) / 2)
           - E.positionLift(w, h, panelH, skin, mode, safeTop)
end

function E.fitOrigin(w, h, scale, skin, mode, safeTop)
  return E.fitOriginFor(w, h, scale, E.SCREEN_W, E.SCREEN_H, skin, mode, safeTop)
end

-- src/ui/gen2/WideBattle.lua:13 and src/ui/gen2/BattleState.lua:266.
-- Fractional on purpose: FILL is the setting that trades the pixel grid for
-- the height of the window.
function E.fillScale(w, h, surfW, surfH, skin)
  local _, _, pw, ph = E.playfield(w, h, skin)
  return math.max(1, math.min(pw / surfW, ph / surfH))
end

-- src/ui/gen2/BattleState.lua:306, battlePanelScale.
function E.battlePanelScale(w, h, wide, fill, skin)
  local surfW = wide and E.WIDE_W or E.OG_W
  local surfH = wide and E.WIDE_H or E.OG_H
  if fill then return E.fillScale(w, h, surfW, surfH, skin) end
  return E.fitScaleFor(w, h, surfW / 8, surfH / 8, skin)
end

-- Where the battle panel ACTUALLY lands: the rect WideBattle.draw clips and
-- translates to (src/ui/gen2/WideBattle.lua:49-53), and the one
-- paintBattleSurround paints around (src/core/Game2.lua:1758-1764).
function E.panelRect(w, h, opts)
  local wide, fill, skin = opts.wide, opts.fill, opts.skin
  local surfW = wide and E.WIDE_W or E.OG_W
  local surfH = wide and E.WIDE_H or E.OG_H
  local scale = E.battlePanelScale(w, h, wide, fill, skin)
  local ox, oy = E.fitOriginFor(w, h, scale, surfW / 8, surfH / 8, skin,
                               opts.mode, opts.safeTop)
  return ox, oy, surfW * scale, surfH * scale, scale, surfW, surfH
end

-- What `render.letterbox` hands a mod on Gen 2 (src/core/Game2.lua:1424-1435).
-- Note what it does NOT consult: the battle, its layout, or its fit.
function E.hookView(w, h, opts)
  local skin = opts.skin
  local scale = E.fitScale(w, h, skin)
  local ox, oy = E.fitOrigin(w, h, scale, skin, opts.mode, opts.safeTop)
  return {
    ww = w, wh = h, pw = w, ph = h,
    ox = ox, oy = oy,
    vpw = E.OG_W * scale, vph = E.OG_H * scale,
    scale = scale, dpiX = 1, dpiY = 1,
    worldActive = false,
  }
end

return E
