-- What a backdrop takes away from Gold's battle, and how it is given back.
--
-- Gold draws its battle against PAPER: `drawPanel` opens with `Chrome.clear()`
-- and everything after it is drawn knowing that whatever it does not paint is
-- white.  Put a picture there instead and three of the cart's own assumptions
-- become visible bugs, all three of which were reported from the Crystal cart:
--
--   * every HUD string paints its own paper cell first, because a tilemap
--     cell is opaque -- so the name, the level and the HP numbers each
--     arrived as a white block hugging its own text.
--   * the HP and exp bars are opaque 2bpp sheets, colour 0 and all, so each
--     bar arrived as a white slab with a bar drawn on it.
--   * the pics have holes in them, because the extractor's matte leaks
--     wherever the art runs off the edge of its own frame -- so you could see
--     the arena through the player's shirt.
--
-- The first fix put PLATES behind the HUD blocks and was rejected on sight:
-- "there shouldn't be the big black or white box behind all that stuff.  Look
-- gen 1 looks much cleaner."  So the assertions here are about paper being
-- TAKEN AWAY rather than added -- and the one place it is still added, inside
-- the pic, is asserted to be the pic's own shape and not a rectangle.
--
-- The pic measurement is exercised for real rather than stubbed -- the
-- graphics stub below carries enough canvas for `readPic` to read an
-- ImageData back -- because which pixels are a hole is the half of that fix
-- with somewhere to go wrong.
--
-- Run:  luajit tests/arenagen2paper_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

-- ------------------------------------------------------------- the harness

-- One synthetic pic: a hollow 16x16 ring -- ink round a 12x12 edge with a
-- 10x10 transparent hole inside it, and nothing but transparency outside.
-- The hole is what the paper is for; the outside is what it must not touch.
local PIC_W, PIC_H = 16, 16
local function ringPixel(x, y)
  local edge = x == 2 or x == 13 or y == 2 or y == 13
  local inside = x >= 2 and x <= 13 and y >= 2 and y <= 13
  if not inside then return 0, 0, 0, 0 end
  if edge then return 0, 0, 0, 1 end
  return 0, 0, 0, 0            -- the hollow the paper is for
end

local IMAGE = {
  getDimensions = function() return PIC_W, PIC_H end,
}

local IMAGE_DATA = {
  getDimensions = function() return PIC_W, PIC_H end,
  getPixel = function(_, x, y) return ringPixel(x, y) end,
}

local fills, draws, keyed, prints
-- What a scratch canvas reads back as, and how many were made: a canvas made
-- inside a frame is a readback inside a draw, which is the stutter.
local CANVAS_DATA = function() return IMAGE_DATA end
local readbacks = 0
_G.love = _G.love or {}

-- The ImageData the paper mask is built into, so a case can ask which pixels
-- it actually painted.
local function newImageData(w, h)
  local data = { width = w, height = h, pixels = {}, filled = 0 }
  data.setPixel = function(self, x, y, r, g, b, a)
    self.pixels[y * self.width + x] = { r, g, b, a }
    if (a or 0) > 0.5 then self.filled = self.filled + 1 end
  end
  data.at = function(self, x, y) return self.pixels[y * self.width + x] end
  return data
end
love.image = { newImageData = newImageData }

-- The colour a fill was painted in, which is the whole assertion for the
-- letterbox bars: black or white is the difference between an edge and a
-- frame, and both are a `rectangle("fill", ...)` otherwise identical.
local pen = { 1, 1, 1, 1 }

-- The transform, the scissor, the blend mode and the canvas, kept just far
-- enough for CLEAR BOXES to be asked where it painted the field again: a
-- translate and one uniform scale, `push("all")` restoring the rest the way
-- the real one does.  Every fill and every draw is stamped with the order it
-- happened in and the scissor it happened under.
local xf = { x = 0, y = 0, s = 1 }
local scissor, blend, canvasNow = nil, "alpha", nil
local stack = {}
local seq = 0
local function stamp(entry)
  seq = seq + 1
  entry.at, entry.scissor, entry.blend = seq, scissor, blend
  entry.xf = { x = xf.x, y = xf.y, s = xf.s }
  return entry
end

love.graphics = {
  rectangle = function(mode, x, y, w, h)
    fills[#fills + 1] = stamp({ kind = "rect", x = x, y = y, w = w, h = h,
                          color = { pen[1], pen[2], pen[3] }, alpha = pen[4] })
  end,
  setColor = function(r, g, b, a) pen = { r or 0, g or 0, b or 0, a or 1 } end,
  getColor = function() return pen[1], pen[2], pen[3], pen[4] end,
  push = function(kind)
    stack[#stack + 1] = { xf = { x = xf.x, y = xf.y, s = xf.s },
      all = kind == "all", pen = pen, scissor = scissor, blend = blend,
      canvas = canvasNow }
  end,
  pop = function()
    local top = table.remove(stack)
    if not top then return end
    xf = top.xf
    if top.all then
      pen, scissor, blend, canvasNow = top.pen, top.scissor, top.blend,
        top.canvas
    end
  end,
  origin = function() xf = { x = 0, y = 0, s = 1 } end,
  translate = function(dx, dy)
    xf.x, xf.y = xf.x + dx * xf.s, xf.y + dy * xf.s
  end,
  scale = function(k) xf.s = xf.s * k end,
  transformPoint = function(x, y) return xf.x + x * xf.s, xf.y + y * xf.s end,
  setScissor = function(x, y, w, h)
    scissor = x and { x, y, w, h } or nil
  end,
  getScissor = function()
    if scissor then return scissor[1], scissor[2], scissor[3], scissor[4] end
  end,
  intersectScissor = function(x, y, w, h)
    if scissor then
      local x2 = math.min(x + w, scissor[1] + scissor[3])
      local y2 = math.min(y + h, scissor[2] + scissor[4])
      x, y = math.max(x, scissor[1]), math.max(y, scissor[2])
      w, h = math.max(0, x2 - x), math.max(0, y2 - y)
    end
    scissor = { x, y, w, h }
  end,
  setShader = function() end,
  setBlendMode = function(mode) blend = mode end,
  getCanvas = function() return canvasNow end,
  setCanvas = function(c) canvasNow = c end,
  clear = function() end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  -- Two callers, told apart by what they hand over: a backdrop arrives as a
  -- path, the pic's paper mask as the ImageData it was just painted into.
  newImage = function(source)
    if type(source) == "table" and source.pixels then
      return { mask = source, setFilter = function() end,
               getDimensions = function() return source.width, source.height end }
    end
    return { getDimensions = function() return 160, 144 end,
             setFilter = function() end, getWidth = function() return 160 end,
             getHeight = function() return 144 end }
  end,
  -- ONE kind of canvas, whose pixels are whatever picture is in front of it
  -- now -- which is what a real one is.  The mod keeps a scratch canvas per
  -- pic size and draws each pic into it, so a stub that froze its pixels at
  -- creation would hand every later pic the first pic's pixels.
  newCanvas = function()
    readbacks = readbacks + 1
    return { newImageData = function() return CANVAS_DATA() end }
  end,
  draw = function(image, a, b, c, d)
    draws[#draws + 1] = stamp({ image = image, a = a, b = b, c = c, d = d })
  end,
}

package.loaded["src.core.GameVersion"] = {
  generation = function() return 2 end,
  get = function() return "gold" end,
  isYellow = function() return false end,
}

-- Gold's palette machinery, reduced to the two binds the HUD tiles go
-- through.  Which of the two a tile was drawn under is the whole assertion:
-- `useKeyed` is the shader that makes colour 0 transparent.
local GbcPalette = {
  use = function() keyed[#keyed + 1] = "opaque"; return true end,
  useKeyed = function() keyed[#keyed + 1] = "keyed"; return true end,
}
package.loaded["src.render.GbcPalette"] = GbcPalette

-- Gold's Chrome.  `printThrough` fills its paper cell the way the real one
-- does -- through `love.graphics.rectangle`, which is exactly what the arm
-- swallows -- and then "draws" its glyphs.
local Chrome
Chrome = {
  SCREEN_W = 20,
  SCREEN_H = 18,
  DEFAULT_BOX_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
  },
  paletteFill = function(x, y, w, h)
    fills[#fills + 1] = { kind = "paper", x = x, y = y, w = w, h = h }
  end,
  -- The real one IS a whole-surface palette fill, and that is the whole
  -- reason one shim on paletteFill covers the panel, the wide surface and
  -- the animation view's exposed strip alike.
  printThrough = function(text, tx, ty, palette)
    love.graphics.rectangle("fill", tx * 8, ty * 8, #tostring(text) * 8, 8)
    prints[#prints + 1] = { text = text, palette = palette }
    return #tostring(text) * 8
  end,
}
Chrome.clear = function()
  Chrome.paletteFill(0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
end
-- A box is Font.drawBox through the palette: its paper is one fill the size of
-- the box, then the border tiles.  Recorded as kind "box" so the cases below
-- can tell a box's paper from a string's.
Chrome.paletteBox = function(tx, ty, tw, th)
  love.graphics.setColor(1, 1, 1, 1)
  local before = #fills
  love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  if fills[before + 1] then fills[before + 1].kind = "box" end
  borders = (borders or 0) + 1
end
Chrome.box = function(tx, ty, tw, th) Chrome.paletteBox(tx, ty, tw, th) end
Chrome.cursorThrough = function(tx, ty)
  love.graphics.setColor(1, 1, 1, 1)
  local before = #fills
  love.graphics.rectangle("fill", tx * 8, ty * 8, 8, 8)
  if fills[before + 1] then fills[before + 1].kind = "cursor" end
end
Chrome.printRightThrough = function(text, txEnd, ty, palette)
  return Chrome.printThrough(text, txEnd, ty, palette)
end
package.loaded["src.ui.gen2.Chrome"] = Chrome

-- The engine's own brightness approximation, which the arm borrows to veil
-- the picture through an end-of-battle fade.
package.loaded["src.ui.gen2.BattleAnimView"] = {
  palVeil = function(byte)
    if not byte then return 0 end
    local sum = 0
    for index = 0, 3 do sum = sum + math.floor(byte / (4 ^ index)) % 4 end
    return (sum - 6) / 6
  end,
}

-- The HUD's tiles.  Only the two things the arm reaches for: a tile drawn
-- with a palette (the bars) and one drawn with none (the border).
local BattleHud = {}
BattleHud.drawTile = function(self, key, first, tile, tx, ty, colors)
  fills[#fills + 1] = { kind = "tile", colors = colors }
  GbcPalette.use(colors or { { 255, 255, 255 } })
  return true
end
package.loaded["src.ui.gen2.BattleHud"] = BattleHud

-- Gold's BattleState, reduced to the methods the arm wraps and the state they
-- read.  `src.battle.BattleState` is the name the mod requires: on a Gen 2
-- boot the loader answers it with a write-through facade onto Gold's class,
-- so patching this table is patching Gold's.
local drawn
local BattleState = {}
BattleState.hasBattleSides = function(self) return self.battle ~= nil end
BattleState.wideLayout = function() return false end
-- The one call every layout reaches the battle through, and the one the arm
-- wraps: `draw`, `drawWidescreen` and WideBattle.draw all come here, each
-- having set up its own transform, and battle.overlay is raised at the end.
BattleState.drawScene = function(self, bodyFn)
  drawn[#drawn + 1] = "scene"
  if bodyFn then bodyFn() else self:drawPanel() end
end
BattleState.drawPanel = function(self)
  drawn[#drawn + 1] = "panel"
  Chrome.clear()
  -- drawHud's own order: the enemy HUD, then both pics, then the player's.
  self:drawEnemyHud()
  if self.drawsPics ~= false then
    self:drawPic({ species = "X" }, false)
    self:drawPic({ species = "X" }, true)
  end
  self:drawPlayerHud()
  -- The bottom strip, which is NOT the HUD: its box really does have paper.
  Chrome.box(0, 12, 20, 6)
  Chrome.printThrough("HELLO", 1, 14, Chrome.DEFAULT_BOX_PALETTE)
  -- In the box's gutter, as Gold's menu cursor is: its column 0 is the
  -- border, and a cell there stands in for the border tile.
  Chrome.cursorThrough(1, 16, Chrome.DEFAULT_BOX_PALETTE)
  if self.extra then self.extra() end
  -- A piece of chrome that fills part of the screen -- the START menu's own
  -- block is one -- which must not be mistaken for the field.
  if self.partialFill then Chrome.paletteFill(0, 104, 80, 40) end
end
BattleState.drawEnemyHud = function(self)
  drawn[#drawn + 1] = "enemy"
  Chrome.printThrough("RATTATA", 1, 0)
  BattleHud.drawTile(BattleHud, "hpBar", 0x60, 0x62, 2, 2,
                     { { 255, 255, 255 }, { 0, 255, 0 }, { 0, 128, 0 },
                       { 0, 0, 0 } })
  BattleHud.drawTile(BattleHud, "enemyBorder", 0x6c, 0x6d, 1, 2)
end
BattleState.drawPlayerHud = function(self)
  drawn[#drawn + 1] = "player"
  Chrome.printRightThrough("18/18", 18, 10)
end
BattleState.drawPic = function(self, mon, back)
  drawn[#drawn + 1] = "pic"
  -- the plain blit `drawPic` ends in: image, x, y, rotation, scale, scale
  love.graphics.draw(IMAGE, 40, 48, 0, 2, 2)
end
-- UI LETTERBOX and the paper reader, the two the bar colour is composed from.
-- Real shapes: `Letterbox.fill(r, g, b, paper)` returns the caller's own
-- colour on AUTO and overrides it on the other three, and `paperShade` is the
-- live ramp's paper.
local Letterbox
Letterbox = {
  mode = "auto",
  fill = function(r, g, b, paper)
    if Letterbox.mode == "black" then return 0, 0, 0 end
    if Letterbox.mode == "white" then return 1, 1, 1 end
    if Letterbox.mode == "palette" and paper then
      local pr, pg, pb = paper()
      if pr then return pr, pg, pb end
    end
    return r, g, b
  end,
}
package.loaded["src.render.Letterbox"] = Letterbox
package.loaded["src.render.PaletteFX"] = {
  paperShade = function() return 0.9, 0.9, 0.8 end,
  markTrueColor = function() end,
  setMarkOffset = function() end,
}
package.loaded["src.core.Game"] = { data = {} }

package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.battle.WideBattle"] = nil

local mod = {
  id = "gen1_wild_ui_nightly",
  path = "modules/Gen1Arena",
  exports = {},
  stored = {},
  hooked = {},
  events_on = {},
  logged = {},
}
mod.options = {
  define = function(_, rows) mod.rows = rows end,
  get = function(_, key) return mod.stored[key] end,
  set = function(_, key, value) mod.stored[key] = value end,
}
mod.log = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  mod.log[level] = function(_, format, ...)
    mod.logged[#mod.logged + 1] = select("#", ...) > 0
      and tostring(format):format(...) or tostring(format)
  end
end
mod.hooks = { wrap = function(_, name, fn) mod.hooked[name] = fn end }
mod.events = { on = function(_, name, fn) mod.events_on[name] = fn end }
mod.assets = { path = function(_, p) return p end }
mod.storage = { writeBytes = function() return true end }
mod.content = {}

load_("main.lua", mod)
assert(type(mod.events_on["game.ready"]) == "function", "no game.ready")
mod.events_on["game.ready"]({ game = {} })

ok(BattleState.__gen1arena, "the Gold arm installed")

-- ---------------------------------------------------------------- the rows

do
  io.write("the option row\n")
  local keys = {}
  for _, row in ipairs(mod.rows or {}) do keys[row.key] = row end
  ok(keys.hud_clear, "CLEAR HUD is offered on Gold")
  eq(keys.hud_clear and keys.hud_clear.default, true, "and defaults on")
  ok(not keys.hud_paper, "and the plate's row is gone with the plates")
  ok(keys.pic_paper, "MON PAPER is there on both generations")
end

-- ------------------------------------------------------------- the frames

-- A battle screen as the engine hands one over.  Whether a backdrop is found
-- for it is what `consumed` turns on.
local function screen(opts)
  opts = opts or {}
  local self = {
    battle = opts.battle ~= false and { wild = true } or nil,
    drawsPics = opts.drawsPics,
    partialFill = opts.partialFill,
    extra = opts.extra,
  }
  -- The class behind it, so `self:drawEnemyHud()` reaches the wrapped method
  -- the way it does on a live instance.
  return setmetatable(self, { __index = BattleState })
end

local function frame(self)
  fills, draws, drawn, keyed, prints = {}, {}, {}, {}, {}
  xf, scissor, blend, canvasNow, stack = { x = 0, y = 0, s = 1 }, nil,
    "alpha", nil, {}
  BattleState.drawScene(self)
end

local function kinds(want)
  local out = {}
  for _, f in ipairs(fills) do
    if f.kind == want then out[#out + 1] = f end
  end
  return out
end

-- Whether a backdrop was found for this frame is the one thing everything
-- below turns on, and it is not a flag a test can set: the arm decides it by
-- taking the engine's `Chrome.clear` call.  So it is READ instead, off the
-- mark the arm leaves for UI THEME.
local function tookTheField(self)
  return self.gen1wildArenaField == true
end

do
  io.write("no backdrop, nothing touched\n")
  mod.stored.enabled = false
  local self = screen()
  frame(self)
  eq(tookTheField(self), false, "the field is the cart's")
  eq(#kinds("rect"), 3,
     "so every HUD string keeps its own paper cell -- against the cart's "
     .. "white field it is invisible, and taking it away would be a change "
     .. "for its own sake")
  eq(keyed[1], "opaque", "and the bars keep the shader the cart drew them on")
  mod.stored.enabled = nil
end

do
  io.write("a backdrop, and the HUD's paper goes\n")
  local self = screen({ drawsPics = false })
  frame(self)
  ok(tookTheField(self),
     "the arm took the field, which is what everything below is about")

  eq(#kinds("paper"), 0,
     "no plate behind either HUD: the big box behind all that stuff is what "
     .. "was reported, not what was missing")

  local rects = kinds("rect")
  eq(#rects, 1, "one paper cell survives the frame")
  eq(rects[1] and rects[1].y, 14 * 8,
     "and it is the bottom strip's, which is a real box -- the two HUD "
     .. "strings drew their glyphs onto the picture with nothing behind them")

  eq(keyed[1], "keyed",
     "the HP bar's tiles are bound through the shader that keys colour 0 "
     .. "away, so the bar loses its white slab and keeps its two hues")
  eq(keyed[2], "keyed", "and so is the border")
end

do
  io.write("the field goes down before the scene, not inside it\n")
  local self = screen({ drawsPics = false })
  frame(self)
  -- Gen1NightlyIndex#2: an attack does not move the background, it moves the
  -- BG SCROLL -- BattleAnimView bakes the panel and blits it back a scanline
  -- at a time.  A field inside that canvas is dragged across the screen with
  -- everything else, so it has to be under it instead.
  ok(draws[1] and draws[1].image and draws[1].image.getWidth,
     "the backdrop is the first thing drawn this frame")
  eq(draws[1] and draws[1].a, 0, "at the origin")
  eq(draws[1] and draws[1].b, 0, "on both axes")
  local sceneAt
  for i, what in ipairs(drawn) do
    if what == "scene" then sceneAt = i break end
  end
  eq(sceneAt, 1, "and the scene composites over it")

  eq(#kinds("paper"), 0,
     "the panel's own whole-surface fill is swallowed, so the picture is "
     .. "what shows through wherever the panel paints nothing")
end

do
  io.write("a partial fill is left alone\n")
  local self = screen({ drawsPics = false, partialFill = true })
  frame(self)
  local paper = kinds("paper")
  eq(#paper, 1, "a fill that is not the whole surface is a real piece of "
     .. "chrome and goes through")
  eq(paper[1] and paper[1].w, 80, "at its own size")
end

do
  io.write("the HUD keeps the cart's ink under DARK\n")
  -- The theme rewrites Chrome.DEFAULT_BOX_PALETTE in place, so this is what a
  -- dark page looks like from inside the arm.
  local vanilla = Chrome.DEFAULT_BOX_PALETTE
  Chrome.DEFAULT_BOX_PALETTE = {
    { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 255, 255, 255 },
  }
  frame(screen({ drawsPics = false }))

  -- "The stuff over the arena shouldn't turn to white font when dark mode is
  -- on."  A theme is for BOXES: it owns the paper as well as the ink, so it
  -- can flip both and stay legible.  The HUD over a backdrop has no paper --
  -- it is ink on a photograph -- so flipping it is guessing at the picture.
  local inkOf = {}
  for _, printed in ipairs(prints) do
    inkOf[printed.text] = printed.palette and printed.palette[4][1]
  end
  eq(inkOf["RATTATA"], 0,
     "the enemy's name is printed in the cart's black, not the theme's white")
  eq(inkOf["18/18"], 0, "and so are the HP numbers")
  -- And the rule's other half, which is what makes it a rule rather than an
  -- opt-out: the bottom strip is a BOX.  The theme owns its paper as well as
  -- its ink, so it can flip both and stay legible -- and it must, or DARK
  -- would print black text on a black box.
  eq(inkOf["HELLO"], 255,
     "while the bottom strip, which has paper of its own, still goes dark")

  local tiles = kinds("tile")
  eq(#tiles, 2, "both tiles drew")
  ok(tiles[1] and tiles[1].colors and tiles[1].colors[2][2] == 255,
     "a tile the cart coloured keeps the cart's colours")
  ok(tiles[2] and tiles[2].colors ~= nil,
     "and a tile the cart drew with no palette at all is given one, or it "
     .. "comes out flat black rather than in the ink beside it")
  eq(tiles[2] and tiles[2].colors and tiles[2].colors[4][1], 0,
     "in the same black the text is in")

  Chrome.DEFAULT_BOX_PALETTE = vanilla
end

do
  io.write("CLEAR HUD off\n")
  mod.stored.hud_clear = false
  frame(screen({ drawsPics = false }))
  eq(#kinds("rect"), 3, "the cart's own white blocks come back")
  eq(keyed[1], "opaque", "and its own shader with them")
  mod.stored.hud_clear = nil
end

-- ---------------------------------------------------------- under the pics

local function picBlits()
  local out = {}
  for _, d in ipairs(draws) do
    if d.a == 40 and d.b == 48 then out[#out + 1] = d end
  end
  return out
end

do
  io.write("paper inside a pic\n")
  local outside = love.graphics.draw
  -- The FIRST frame a pic is on screen only asks for its paper: building it
  -- reads the pic back and makes a texture, and doing either inside the draw
  -- is the stutter at the start of a battle on a handheld.
  local before = readbacks
  frame(screen())
  eq(readbacks, before, "the first frame reads nothing back inside the draw")
  eq(#picBlits(), 2, "so it draws the two pics and no paper yet")
  ok(mod.exports.paperQueued() >= 1, "and remembers the pic as wanted")

  -- The update builds it, between frames, one picture per call.
  local guard = 0
  while mod.exports.buildQueuedCutouts() and guard < 20 do guard = guard + 1 end
  eq(mod.exports.paperQueued(), 0, "the update drains what was asked for")

  frame(screen())
  local blits = picBlits()
  eq(#blits, 4, "from the next frame: two pics, and each one drawn twice -- "
     .. "its paper, then it")
  ok(blits[1] and blits[1].image and blits[1].image.mask,
     "the paper goes down first, or it would cover the pic")
  eq(blits[2] and blits[2].image, IMAGE, "and the pic itself second")
  eq(blits[2] and blits[2].d, 2,
     "at the scale the ENGINE passed, not one re-derived -- and the paper "
     .. "takes the same one")
  eq(blits[1] and blits[1].d, 2, "so the two land on each other")

  eq(#kinds("paper"), 0,
     "and it is not a fill: a rectangle is the wrong shape for a mon, which "
     .. "is what the white box behind the pics was")

  eq(love.graphics.draw, outside,
     "the draw is put back: the shim is for the length of one drawPic and "
     .. "no longer")
end

do
  io.write("MON PAPER off\n")
  mod.stored.pic_paper = false
  frame(screen())
  eq(#picBlits(), 2, "one draw per pic, and it is the pic")
  mod.stored.pic_paper = nil
end

-- ----------------------------------------------------------- the pic's shape

do
  io.write("the paper's shape\n")
  local shape = mod.exports.picPaperImage
  ok(type(shape) == "function", "the shaping is exposed")
  if type(shape) == "function" then
    local paper = shape(IMAGE)
    ok(paper ~= nil and paper ~= false, "a pic with a hole in it gets paper")
    local mask = paper and paper.mask
    if mask then
      eq(mask.width, PIC_W, "the mask is the pic's own size, so it can be "
         .. "drawn with the pic's own coordinates")
      eq(mask.height, PIC_H, "on both axes")
      eq(mask.filled, 10 * 10,
         "and it is exactly the hole: ten by ten inside a twelve-wide ring")
      ok(mask:at(7, 7) ~= nil, "the middle of the hole is paper")
      eq(mask:at(2, 2), nil, "the ink is not")
      eq(mask:at(0, 0), nil,
         "and neither is the space around the mon, which is the picture")
    end
  end
end

do
  io.write("a pic with nothing to fill\n")
  -- A solid block: opaque throughout, so there is no hole and no paper -- and
  -- a mod's full-colour replacement art, which has too many shades to be a
  -- 2bpp pic, is refused for the same reason the Gen 1 arm refuses it.
  local solid = { getDimensions = function() return 8, 8 end }
  local was = CANVAS_DATA
  CANVAS_DATA = function()
    return {
      getDimensions = function() return 8, 8 end,
      getPixel = function(_, x, y) return 0, 0, 0, 1 end,
    }
  end
  eq(mod.exports.picPaperImage(solid), nil,
     "a pic with no hole in it builds no paper and costs one readback")
  CANVAS_DATA = was
end

-- ---- cutting a cart pic out of its square
--
-- The paper above is for art that already has transparency around it.  A CART
-- pic has none: the whole square is opaque and the space around the figure is
-- shade 0, which the remap keeps as an opaque colour 0.  On the cart that is
-- invisible against the white battle field; over a BACKDROP it is a white box.
--
-- Cut out rather than recoloured -- "can you just cut them out of that square.
-- Not replace the color" -- and the whole point of the flood fill is that it
-- cuts only what the EDGES can reach.  A trainer's white shirt is enclosed by
-- the figure, so it survives; keying the shader instead would take it.

-- An image whose pixels come from `plot(x, y)` as a shade in 0..1.
local function shadePic(w, h, plot)
  local img = { getDimensions = function() return w, h end,
                setFilter = function() end }
  local was = CANVAS_DATA
  CANVAS_DATA = function()
    return {
      getDimensions = function() return w, h end,
      getPixel = function(_, x, y)
        local v = plot(x, y)
        return v, v, v, 1
      end,
    }
  end
  return img, function() CANVAS_DATA = was end
end

do
  -- An 8x8 "trainer": a 4x4 body of ink at (2,2)-(5,5) with a 2x2 WHITE SHIRT
  -- enclosed inside it at (3,3)-(4,4), standing in a white field.
  local function plot(x, y)
    local inBody = x >= 2 and x <= 5 and y >= 2 and y <= 5
    local inShirt = x >= 3 and x <= 4 and y >= 3 and y <= 4
    if inBody and not inShirt then return 0 end   -- ink
    return 1                                       -- field AND shirt: shade 0
  end
  local img, restore = shadePic(8, 8, plot)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  ok(cut ~= nil, "a cart pic in a white square builds a cut-out")
  local mask = cut and cut.mask
  ok(mask ~= nil, "which is a real image")
  if mask then
    local function alphaAt(x, y)
      local p = mask:at(x, y)
      return p and p[4] or nil
    end
    eq(alphaAt(0, 0), 0, "the corner of the square is cut away")
    eq(alphaAt(7, 7), 0, "and so is the far corner")
    eq(alphaAt(1, 4), 0, "and the field beside the figure")
    eq(alphaAt(2, 2), 1, "the figure's own ink is kept")
    eq(alphaAt(3, 3), 1,
       "and the SHIRT is kept -- enclosed white the edges cannot reach")
    eq(alphaAt(4, 4), 1, "all of it")
    -- Colour survives the cut, so a host that ignores alpha shows the pic it
    -- always did rather than a black hole.
    local corner = mask:at(0, 0)
    eq(corner and corner[1], 1, "and the cut pixels keep their colour")
  end
end

do
  -- "There are sprites where white areas are being ignored and/or cropped
  -- incorrectly."  The player's back pic is cut off by its own frame, so the
  -- figure runs into the bottom edge -- and a white shirt inside it touches
  -- that edge as well.  The flood used to start from every field pixel on the
  -- border, poured in through the shirt, and the backdrop showed through
  -- Kris's back.
  local function plot(x, y)
    local inBody = x >= 2 and x <= 7 and y >= 3
    local inShirt = x >= 3 and x <= 6 and y >= 5
    if inBody and not inShirt then return 0 end
    return 1
  end
  local img, restore = shadePic(10, 10, plot)
  local cut = mod.exports.picCutoutImage(img, true)
  restore()
  local mask = cut and cut.mask
  ok(mask ~= nil, "a back pic cut off at the waist is still cut out")
  if mask then
    local function alphaAt(x, y)
      local px = mask:at(x, y)
      return px and px[4] or nil
    end
    eq(alphaAt(4, 9), 1,
       "the white shirt where it meets the bottom edge is KEPT")
    eq(alphaAt(5, 6), 1, "and the shirt above it")
    eq(alphaAt(0, 9), 0, "the field beside the body on that edge is cut")
    eq(alphaAt(9, 9), 0, "on both sides")
    eq(alphaAt(4, 1), 0, "and the field above the head")
  end
end

do
  -- ...and ONLY a back pic.  A trainer facing you stands on the bottom edge,
  -- and the field between two feet that reach it is outside.  The first
  -- version closed every edge of every pic, and over Crystal's own trainers
  -- that left a white wedge between the legs of the Lass, the Picnicker, the
  -- Biker, Bruno and Red.
  local function plot(x, y)
    local leftLeg = x >= 2 and x <= 3 and y >= 4
    local rightLeg = x >= 6 and x <= 7 and y >= 4
    local body = x >= 2 and x <= 7 and y >= 1 and y <= 4
    if leftLeg or rightLeg or body then return 0 end
    return 1
  end
  local img, restore = shadePic(10, 10, plot)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  local mask = cut and cut.mask
  ok(mask ~= nil, "a trainer standing on the bottom edge is cut out")
  if mask then
    local px = mask:at(4, 9)
    eq(px and px[4], 0, "and the field between the feet is cut with the rest")
    px = mask:at(5, 6)
    eq(px and px[4], 0, "all the way up to the body")
  end
end

do
  -- Replacement art that BLEEDS TO ITS OWN EDGE.  A gradient across the whole
  -- square is not a figure standing in a field, and the border says so: no
  -- single colour runs all the way round it.  Left alone.
  local img, restore = shadePic(8, 8, function(x, y) return (x * 8 + y) / 64 end)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  eq(cut, nil, "full-colour art that reaches its own edge is left alone")
end

-- ---- a FULL-COLOUR trainer standing in a white square
--
-- Reported as "some trainers didn't appear with the background removed", with
-- a screenshot of a SAILOR in a white box beside a player whose box was gone.
--
-- The gate was a colour COUNT: four is a 2bpp cart pic exactly, and a
-- replacement trainer -- skin, bandana, shirt, shading -- has a dozen.  Every
-- one was refused, and the refusal was cached, so it kept its square for the
-- whole battle while the cart's own pics were cut beside it.
--
-- The count was standing in for "is this a figure in a field", which the
-- BORDER answers directly.  This is that pic: many colours, fully opaque, and
-- white all the way round.

do
  local COLOURS = { 0.95, 0.62, 0.41, 0.27, 0.13, 0.72, 0.55, 0.34 }
  local img, restore = shadePic(10, 10, function(x, y)
    -- a white field, and a figure of eight shades that never touches an edge
    if x == 0 or y == 0 or x == 9 or y == 9 then return 1 end
    if x < 2 or y < 2 or x > 7 or y > 7 then return 1 end
    return COLOURS[((x * 3 + y * 5) % #COLOURS) + 1]
  end)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  ok(cut ~= nil,
    "a full-colour trainer standing in a white square is cut out of it")

  local mask = cut and cut.__data
  if mask then
    local corner = mask:at(0, 0)
    eq(corner and corner[4], 0, "the corner of the square is cut to alpha 0")
    local inside = mask:at(5, 5)
    ok(inside and inside[4] == 1, "and the figure is left opaque")
  end
end

do
  -- ...and the same pic with ONE white pixel of its own on the border is not
  -- a figure in a field any more.  The guard is the whole border, not a
  -- corner: a picture that reaches its edge is a picture, not a square.
  local COLOURS = { 0.95, 0.62, 0.41, 0.27, 0.13, 0.72, 0.55, 0.34 }
  local img, restore = shadePic(10, 10, function(x, y)
    if x == 0 and y == 5 then return 0.27 end     -- one pixel of the figure
    if x == 0 or y == 0 or x == 9 or y == 9 then return 1 end
    if x < 2 or y < 2 or x > 7 or y > 7 then return 1 end
    return COLOURS[((x * 3 + y * 5) % #COLOURS) + 1]
  end)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  eq(cut, nil, "art whose figure touches the border is left alone")
end

do
  -- A pic with no field the edges can see: nothing to cut, and cutting the
  -- lightest shade anyway would eat the picture.
  local img, restore = shadePic(8, 8, function() return 0 end)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  eq(cut, nil, "a pic that is all ink is not sitting in a square")
end

do
  -- Art that already has transparency is the PAPER's case, not this one.
  local img = { getDimensions = function() return 8, 8 end,
                setFilter = function() end }
  local was = CANVAS_DATA
  CANVAS_DATA = function()
    return {
      getDimensions = function() return 8, 8 end,
      getPixel = function(_, x, y)
        if x == 0 then return 1, 1, 1, 0 end
        return 0, 0, 0, 1
      end,
    }
  end
  local cut = mod.exports.picCutoutImage(img)
  CANVAS_DATA = was
  eq(cut, nil, "a pic that already has alpha is left to the paper arm")
end

-- ---- the cut-out is asked for in the draw and BUILT between frames
--
-- 0.32.62 shipped it on and it broke a battle over a backdrop: flipped on
-- iOS, a crash on Android.  0.32.65 switched it off.  The cause was never the
-- cut-out itself -- it was building one INSIDE the draw: a readback binds a
-- scratch canvas and `newImage` makes a whole new texture, both with the
-- battle's canvas bound.  picPaperImage did the same readback but bailed
-- before `newImage` for any pic with no holes, which is every cart pic, so it
-- almost never reached the texture and the difference never showed.
--
-- What this pins is the SPLIT that fixes it, because the split is the whole
-- of the fix and it is invisible in the output: the draw's `cutoutFor` must
-- never build, and `buildQueuedCutouts` -- called from `core.update`, where
-- nothing is bound -- must be the only thing that does.
do
  local rows = mod.rows or {}
  local cutout, paper
  for _, row in ipairs(rows) do
    if row.key == "pic_cutout" then cutout = row end
    if row.key == "pic_paper" then paper = row end
  end
  ok(cutout ~= nil, "PIC CUTOUT is offered as a switch")
  eq(cutout and cutout.label, "PIC CUTOUT",
     "named for what it cuts -- trainers as well as mons")
  eq(cutout and cutout.default, true,
     "and it ships ON, now that the build is out of the draw")
  eq(paper and paper.default, true, "while MON PAPER, which is safe, stays on")
end

do
  -- The same 8x8 "trainer" the builder is tested on above: a body of ink in a
  -- white field, which is what a cart pic is.
  local function plot(x, y)
    return (x >= 2 and x <= 5 and y >= 2 and y <= 5) and 0 or 1
  end
  local img, restore = shadePic(8, 8, plot)
  local readCanvas = love.graphics.newCanvas   -- the readback shadePic installed
  local realImage = love.graphics.newImage

  local cutoutFor = mod.exports.cutoutFor
  local build = mod.exports.buildQueuedCutouts
  local queued = mod.exports.cutoutQueued
  ok(type(cutoutFor) == "function" and type(build) == "function",
     "the two halves are separate functions")

  -- The blocks above drive the shipped drawPic wrap, which asks for cut-outs
  -- of its own; drained here so the counts below are this block's.
  while build() do end
  eq(queued(), 0, "starting from an empty queue")

  -- THE DRAW.  Making a texture here is the crash, so both makers are taken
  -- away for the length of the call: asking has to survive with neither.
  local function noBuilding(why)
    love.graphics.newCanvas = function() error(why, 0) end
    love.graphics.newImage = function() error(why, 0) end
  end
  local function buildingAgain()
    love.graphics.newCanvas, love.graphics.newImage = readCanvas, realImage
  end

  noBuilding("a texture was made inside the draw -- this is the crash")
  local askOk, first = pcall(cutoutFor, img)
  buildingAgain()
  ok(askOk, "asking for a cut-out in the draw builds nothing at all")
  eq(first, nil, "so the first frame draws the cart's own square")
  eq(queued(), 1, "and the pic is remembered as wanted")

  noBuilding("a texture was made inside the draw -- this is the crash")
  pcall(cutoutFor, img)
  buildingAgain()
  eq(queued(), 1, "asking twice queues it once")

  -- THE UPDATE.  Nothing is bound here, so this is where it may build.
  eq(build(), img, "the update builds what was asked for")
  eq(queued(), 0, "and the queue empties")
  eq(build(), nil, "an update with nothing waiting builds nothing")

  -- And from the next frame the draw has it, still without building.
  noBuilding("the draw built a second time")
  local hitOk, cut = pcall(cutoutFor, img)
  buildingAgain()
  ok(hitOk, "the draw reads the cache without building again")
  ok(cut ~= nil, "and gets the cut-out from the frame after it asked")
  restore()
end

-- ---- a QUAD is not a picture in a square
--
-- The engine draws through one for exactly three things: a Crystal animation
-- frame out of a sheet, the substitute doll, and the faint slide's crop.
-- Cutting the sheet those come out of stopped the animation playing -- a sheet
-- is a strip of frames whose "field" runs between them, and the frame the quad
-- picks is a window onto it, not a figure standing in a square.
do
  -- Resolved here rather than assumed: `ENGINE` was not a local in this file,
  -- so the three reads below were skipping in silence -- an assertion that
  -- never runs is the same as one that agrees with you.
  local ENGINE
  do
    local candidates = { os.getenv("GEN1RECOMP") }
    for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
      for _, name in ipairs({ "gen1recompog", "gen1recomp", "bryanthaboi/gen1recomp" }) do
        candidates[#candidates + 1] = prefix .. "/" .. name
      end
    end
    for _, dir in ipairs(candidates) do
      local probe = io.open(dir .. "/src/ui/gen2/BattleState.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
  -- A SKIP, not a failure.  The worry this line was written for is real -- an
  -- assertion that never runs agrees with you -- but it is about the reads
  -- that need an ENGINE, and every one of those is already behind `if ENGINE`
  -- below.  The reads of THIS repo's own main.lua need no tree and always
  -- run.  Asserting the tree exists turned "no engine checked out" into a red
  -- build, which is what CI has been for two releases: every other suite here
  -- skips cleanly and this one shouted.
  if ENGINE then
    ok(true, "an engine tree is found, so the engine reads below run too")
  else
    io.write("  (skipped: no engine tree to read gen2/BattleState.lua from)\n")
  end
  local armSrc = assert(io.open("main.lua")):read("*a")
  ok(armSrc:find('local quad = first ~= nil and type(first) ~= "number"',
                 1, true) ~= nil,
     "the shim tells a quad draw from a plain one")
  -- A quad draw is left ENTIRELY alone -- no cut and no paper.  Cutting one
  -- stopped the animation; the PAPER arm was still reading the sheet back
  -- through a scratch canvas MID-DRAW the first time it saw one, which is the
  -- same bind that flipped and crashed the pics in 0.32.62, done to the very
  -- texture the animation is drawn out of on the frame it starts.
  ok(armSrc:find("if quad then\n          love.graphics.draw = shim\n"
                 .. "          return realDraw(image, first, ...)", 1, true) ~= nil,
     "a quad draw returns before either arm touches it")
  ok(armSrc:find("local cut = trainerPic and mod.options:get(\"pic_cutout\")",
                 1, true) ~= nil,
     "so the cut is reached only by a plain blit of a trainer")
  -- TRAINERS ONLY.  A mon's pic is animated on Crystal -- frames out of a
  -- sheet, the doll and the faint crop through quads of their own -- and every
  -- one is the same texture through a different window.  Cutting any of it
  -- means the animation stops being the cart's.  A mon over a backdrop is
  -- already answered by MON PAPER, which paints and never replaces.
  ok(armSrc:find("local trainerPic = (back and self.showPlayerTrainer)",
                 1, true) ~= nil,
     "the arm asks whether this call is drawing a TRAINER")
  if ENGINE then
    local text = assert(io.open(ENGINE .. "/src/ui/gen2/BattleState.lua")):read("*a")
    ok(text:find("local trainerBack = back and self.showPlayerTrainer", 1, true) ~= nil,
       "off the same flag the engine branches on for the player's box")
    ok(text:find("local enemyTrainer = (not back) and self.showEnemyTrainer",
                 1, true) ~= nil,
       "and the same one for the enemy's")
  end
  -- The engine's own three quad sites, so a fourth appearing is noticed.
  local battle = ENGINE and io.open(ENGINE .. "/src/ui/gen2/BattleState.lua")
  if battle then
    local text = battle:read("*a") battle:close()
    ok(text:find("G.draw(animSheet, animQuad, px, py, 0, scale, scale)",
                 1, true) ~= nil,
       "a Crystal animation frame is drawn through a quad")
    ok(text:find("G.draw(doll, dollQuad, px, py)", 1, true) ~= nil,
       "so is the substitute doll")
    ok(text:find("G.draw(image, self:cropQuad(image, visible)", 1, true) ~= nil,
       "and so is the faint slide's crop")
  end
end

-- ------------------------------------------------- the bars, with the
-- picture stopping at the surface
--
-- Reported with two screenshots side by side: EDGE TO EDGE on, and EDGE TO
-- EDGE off with the backdrop standing in a bright white frame.  Every other
-- mod disabled, on a PC window and on a handheld both.
--
-- The white is not this mod's paint, it is the engine's, and it is the engine
-- answering a question this mod has changed the answer to: `Renderer:endFrame`
-- fills the void with the paper shade for any state that sets
-- `letterboxWhite`, and a battle sets it because its field IS white paper.
-- Replace the field with a photograph and the paper is gone; the surround is
-- then the only white left and reads as a frame rather than as an edge.
--
-- These drive the real `render.letterbox` hook, after a real frame, because
-- what was wrong is a BRANCH and not arithmetic: the toggle used to return
-- before anything was painted at all.

local function bars(view)
  local hook = mod.hooked["render.letterbox"]
  local called = false
  hook(function() called = true end, view)
  return called
end

-- 160x144 doubled and centred in a 400x400 window: bars on all four sides.
local VIEW = { ww = 400, wh = 400, ox = 40, oy = 56, vpw = 320, vph = 288 }

local function isBlack(f)
  return f.color and f.color[1] == 0 and f.color[2] == 0 and f.color[3] == 0
end

do
  io.write("EDGE TO EDGE off still answers for the bars\n")
  Letterbox.mode = "auto"
  mod.stored.bleed = false
  local self = screen({ drawsPics = false })
  frame(self)
  ok(tookTheField(self), "the arm took the field")
  local before = #fills
  ok(bars(VIEW), "the hook passes the frame along either way")

  local painted = {}
  for i = before + 1, #fills do
    if fills[i].kind == "rect" then painted[#painted + 1] = fills[i] end
  end
  eq(#painted, 8,
     "all eight bars are painted -- four sides and the four corners the "
     .. "sides do not reach")

  local white = 0
  for _, f in ipairs(painted) do if not isBlack(f) then white = white + 1 end end
  eq(white, 0,
     "and every one of them BLACK: the engine's own default for a screen "
     .. "that never asked for paper, which is what this one is now")
  mod.stored.bleed = nil
end

do
  io.write("...but never over what the player asked for\n")
  mod.stored.bleed = false

  Letterbox.mode = "white"
  local self = screen({ drawsPics = false })
  frame(self)
  local before = #kinds("rect")
  bars(VIEW)
  local last = fills[#fills]
  ok(last and last.kind == "rect" and not isBlack(last),
     "UI LETTERBOX = WHITE keeps its white: the deduction from "
     .. "letterboxWhite is what was wrong, not a setting with a row on it")
  ok(#kinds("rect") > before, "and the bars are still painted")

  Letterbox.mode = "palette"
  self = screen({ drawsPics = false })
  frame(self)
  bars(VIEW)
  last = fills[#fills]
  ok(last and last.color and last.color[1] == 0.9,
     "and PALETTE still takes the ramp's own paper")

  Letterbox.mode = "auto"
  mod.stored.bleed = nil
end

do
  io.write("EDGE TO EDGE on, and a picture with nothing outside itself\n")
  -- The harness's backdrop is square and covers the whole surface once
  -- `drawCover` has scaled it, so there is no part of it that falls in a bar.
  -- That used to be filled anyway, by cover-fitting the same picture to the
  -- WHOLE WINDOW -- a bigger scale than the surface got -- which is the seam
  -- the report was about: one photograph at two magnifications with the
  -- surface's edge as the join.  There is nothing honest to draw here, so the
  -- bars are the surround's own colour and the picture is not stretched into
  -- them.
  local self = screen({ drawsPics = false })
  frame(self)
  local before = #fills
  local drawsBefore = #draws
  bars(VIEW)

  local painted = {}
  for i = before + 1, #fills do
    if fills[i].kind == "rect" then painted[#painted + 1] = fills[i] end
  end
  eq(#painted, 8, "all eight bars are answered for")
  eq(#draws, drawsBefore,
     "and nothing is drawn into them: a backdrop that ends at the surface has "
     .. "nothing outside itself to show, and inventing something to fill them "
     .. "with is what 0.29.0 got wrong -- a flat slab of field colour across "
     .. "the bottom quarter of a phone screen")
end


do
  io.write("a battle the backdrop did not take keeps the cart's surround\n")
  mod.stored.enabled = false
  mod.stored.bleed = false
  local self = screen()
  frame(self)
  eq(tookTheField(self), false, "the field is the cart's own white")
  local before = #kinds("rect")
  bars(VIEW)
  eq(#kinds("rect"), before,
     "so the bars are left alone: white paper running off the edge of the "
     .. "screen is RIGHT when the field really is white paper, and blacking "
     .. "it out would be this mod changing a battle it never touched")
  mod.stored.enabled = nil
  mod.stored.bleed = nil
end

do
  io.write("BATTLE BG = WORLD keeps the world round the battle\n")
  -- *"With the mod enabled, the background is always black"* -- a portrait
  -- phone, BATTLE BG = WORLD, the overworld showing under the battle with the
  -- mod off and black there with it on.  Gold raises the hook twice on a
  -- WORLD frame and the one after the battle says `worldActive = false`, so
  -- the payload cannot be what decides this: the battle's own `bgMode` is.
  -- Driven exactly as Game2:drawScene drives it -- the world call first, the
  -- battle, then the second call.
  local self = screen({ drawsPics = false })
  self.bgMode = function() return "world" end
  local view = { ww = 400, wh = 800, ox = 40, oy = 56, vpw = 320, vph = 288 }
  local before = #(fills or {})
  bars({ ww = view.ww, wh = view.wh, ox = view.ox, oy = view.oy,
         vpw = view.vpw, vph = view.vph, worldActive = true })
  frame(self)
  ok(tookTheField(self), "the backdrop is still in the field")
  local afterFrame = #fills
  local drawsAfterFrame = #draws
  ok(bars(view), "the hook passes the frame along")
  eq(#kinds("rect") - #(function()
       local out = {}
       for i = 1, afterFrame do
         if fills[i].kind == "rect" then out[#out + 1] = fills[i] end
       end
       return out
     end)(), 0,
     "and paints nothing into the bars: the overworld the engine drew there "
     .. "is what the player chose to see")
  eq(#draws, drawsAfterFrame, "nor draws the picture into them")
  ok(mod.exports.arenaSurroundIsWorld(self), "the battle is read as WORLD")

  -- ...and the two other modes still get the bars, so this is a reading of
  -- the player's choice rather than the bars switched off.
  self.bgMode = function() return "white" end
  frame(self)
  local whiteBefore = #kinds("rect")
  bars(view)
  ok(#kinds("rect") > whiteBefore, "WHITE still has its bars answered for")
  self.bgMode = function() return "black" end
  frame(self)
  local blackBefore = #kinds("rect")
  bars(view)
  ok(#kinds("rect") > blackBefore, "and so does BLACK")
  ok(not mod.exports.arenaSurroundIsWorld(self), "which is not read as WORLD")
  local _ = before
end

-- ------------------------------------------- the rectangle the bars are the
-- complement OF
--
-- Everything above assumes the payload `render.letterbox` hands over names
-- the rectangle the battle was drawn in.  On Gen 2 it does not.
--
-- src/core/Game2.lua:1424 builds it as `Chrome.fitScale(w, h)` and
-- `160 * scale` by `144 * scale` -- the CLASSIC panel at the CLASSIC integer
-- scale, with no reference to the battle, its layout or its BATTLE SIZE.  A
-- wide battle is a 304x144 surface at `battle:battlePanelScale(w, h)` placed
-- by `Chrome.fitOriginFor(w, h, scale, 38, 18)` (src/ui/gen2/WideBattle.lua:50),
-- which on a 1600x900 window is 40,90 1520x720 against the payload's
-- 320,18 960x864.
--
-- Bars built from the payload therefore paint 280 columns of BLACK ONTO THE
-- BATTLE down each side, and leave the 90 rows of real surround above and
-- below it to whatever the engine painted -- which is the report, twice
-- over: *"a giant white box around the top"*, and *"the background filled,
-- but then a square pasted on top of a zoomed in background and zoomed in
-- ui, very broken"*.
--
-- So the rect is asked of the engine, through the engine's own two calls, at
-- the moment the battle draws.  These are the numbers, and then the bars that
-- come out of them.
local WIN_W, WIN_H = 1600, 900

love.graphics.getDimensions = function() return WIN_W, WIN_H end
-- src/ui/gen2/Chrome.lua:91, with no touch-skin cutout and no position lift.
Chrome.fitOriginFor = function(w, h, scale, tilesW, tilesH)
  return math.floor((w - tilesW * 8 * scale) / 2),
         math.floor((h - tilesH * 8 * scale) / 2)
end
-- src/ui/gen2/BattleState.lua:306 for a wide FIXED battle: the integer fit of
-- the 38x18 tile surface.
BattleState.battlePanelScale = function(_, w, h)
  return math.max(1, math.floor(math.min(w / 304, h / 144)))
end

do
  io.write("the panel rect is the engine's, not the payload's\n")
  local rect = mod.exports.arenaPanelRect(
    { battlePanelScale = BattleState.battlePanelScale }, 304, 144)
  ok(rect ~= nil, "a live battle answers where its surface went")
  if rect then
    eq(rect.scale, 5, "a 304x144 surface fits a 1600x900 window five times")
    eq(rect.ox, 40, "centred horizontally")
    eq(rect.oy, 90, "and vertically")
    eq(rect.vpw, 1520, "1520 wide")
    eq(rect.vph, 720, "and 720 tall -- none of which is the payload's "
       .. "320,18 960x864")
  end
  -- A state the engine never gave the method to (Gen 1, or a Gold build
  -- older than battlePanelScale) falls back rather than guessing.
  eq(mod.exports.arenaPanelRect({}, 304, 144), nil,
     "and a state that cannot answer gets no rect at all, so the payload "
     .. "is used -- which is still right on Gen 1 and on a classic fixed "
     .. "Gold battle")
end

do
  io.write("...and the bars are drawn around THAT\n")
  local wasWide = BattleState.wideLayout
  BattleState.wideLayout = function() return true end
  mod.stored.bleed = false          -- flat bars, so this is pure geometry
  local self = screen()
  frame(self)
  ok(tookTheField(self), "the wide battle took the field")

  -- The payload, exactly as Game2:letterbox builds it for this window.
  local before = #fills
  bars({ ww = WIN_W, wh = WIN_H, ox = 320, oy = 18, vpw = 960, vph = 864,
         scale = 6, dpiX = 1, dpiY = 1 })
  local painted = {}
  for i = before + 1, #fills do
    if fills[i].kind == "rect" then painted[#painted + 1] = fills[i] end
  end
  ok(#painted > 0, "the bars are painted")

  -- Not one of them may touch the battle.
  local onto = 0
  for _, r in ipairs(painted) do
    if r.x < 40 + 1520 and r.x + r.w > 40
       and r.y < 90 + 720 and r.y + r.h > 90 then
      onto = onto + 1
    end
  end
  eq(onto, 0, "no bar overlaps the battle panel -- the payload's rect would "
     .. "have put 280 columns of black down each side of it")

  -- ...and between them they have to cover every pixel that is not the
  -- battle, or the engine's paper shows through as a frame.
  local covered = {}
  for _, r in ipairs(painted) do
    for y = r.y, r.y + r.h - 1, 30 do
      for x = r.x, r.x + r.w - 1, 40 do
        covered[math.floor(y) .. ":" .. math.floor(x)] = true
      end
    end
  end
  local holes = 0
  for y = 0, WIN_H - 1, 30 do
    for x = 0, WIN_W - 1, 40 do
      local inPanel = x >= 40 and x < 1560 and y >= 90 and y < 810
      if not inPanel and not covered[y .. ":" .. x] then holes = holes + 1 end
    end
  end
  eq(holes, 0, "and every pixel outside the battle IS a bar, so the white "
     .. "frame the report opened with has nowhere left to show")

  BattleState.wideLayout = wasWide
  mod.stored.bleed = nil
end

do
  io.write("CLEAR BOXES: the boxes' paper at the strength picked\n")
  -- "Full white can be a bit aggressive on the colored battle background, a
  -- transparent option will combine best of both ... 0-100% transparency
  -- with steps of 10%."
  local row
  for _, r in ipairs(mod.rows or {}) do
    if r.key == "box_clear" then row = r end
  end
  ok(row, "CLEAR BOXES is a row on Gold")
  eq(row and row.default, 0, "and it ships OFF: the cart's own solid boxes")
  eq(row and #row.choices, 11, "OFF and ten steps of ten")
  eq(row and row.choices[11][1], "100%", "up to 100%")

  local function boxFill()
    for _, f in ipairs(fills) do if f.kind == "box" then return f end end
    return nil
  end

  frame(screen({ drawsPics = false }))
  eq(boxFill() and boxFill().alpha, 1, "OFF: the strip's box is solid paper")
  eq(#kinds("rect"), 1, "and its string keeps its own paper cell")
  eq(#kinds("cursor"), 1, "and so does the cursor")

  mod.stored.box_clear = 30
  frame(screen({ drawsPics = false }))
  local f = boxFill()
  ok(f and math.abs(f.alpha - 0.7) < 1e-9,
     "30%: the box's paper is laid at seven tenths")
  eq(pen[4], 1, "and the pen is handed back at full strength")
  eq(#kinds("rect"), 0,
     "the string's own cell goes -- the box under it is already its paper, "
     .. "and a second layer would print a band behind the line")
  eq(#kinds("cursor"), 0, "and so does the cursor's")
  local hello
  for _, printed in ipairs(prints) do
    if printed.text == "HELLO" then hello = printed end
  end
  eq(hello and hello.palette, Chrome.DEFAULT_BOX_PALETTE,
     "while the string keeps the box's own ink, theme and all -- the HUD's "
     .. "black is for ink on a photograph, and this is ink in a box")

  mod.stored.box_clear = 100
  frame(screen({ drawsPics = false }))
  eq(boxFill(), nil, "100%: no paper at all, border and ink on the picture")

  -- Only the bottom strip.  Gold draws boxes OVER the HUD and the pics too --
  -- FIGHT's type/PP box over the player's back at (0,8), the YES/NO over the
  -- player's HUD at (14,7) -- and those hide what is under them on the cart.
  -- See-through, they printed their text across the mon and the HP numbers.
  mod.stored.box_clear = 50
  local function overHud()
    Chrome.box(0, 8, 11, 5)
    Chrome.printThrough("TYPE/", 1, 9, Chrome.DEFAULT_BOX_PALETTE)
    Chrome.box(14, 7, 6, 5)
    Chrome.cursorThrough(15, 8, Chrome.DEFAULT_BOX_PALETTE)
  end
  frame(screen({ drawsPics = false, extra = overHud }))
  local boxes = kinds("box")
  eq(#boxes, 3, "the strip's box and the two over the HUD each lay paper")
  eq(boxes[2] and boxes[2].alpha, 1, "the box over the back pic keeps it solid")
  eq(boxes[3] and boxes[3].alpha, 1, "and so does the YES/NO over the HUD")
  eq(#kinds("rect"), 1, "a line in a solid box keeps its own paper cell")
  eq(#kinds("cursor"), 1, "and so does a cursor in one")

  -- The strip's boxes nest: the command menu is drawn inside the message
  -- box, OVER a message that is still up -- the Dude's tutorial, and the
  -- locked-in fallback to the menu, both keep it.  Paper laid twice is twice
  -- as opaque, so the strip read 50% on the left and 75% on the right; no
  -- paper at all let the message's tail print through FIGHT.  The inner box
  -- puts the backdrop back under itself and lays one layer on that.
  local function backdropDraws()
    local out = {}
    for _, d in ipairs(draws) do
      if d.image and d.image.getWidth then out[#out + 1] = d end
    end
    return out
  end
  local function near(a, b) return a and b and math.abs(a - b) < 1e-9 end
  local function sameRect(r, x, y, w, h)
    return r and r[1] == x and r[2] == y and r[3] == w and r[4] == h
  end
  local tail
  local function menu()
    tail = Chrome.printThrough("RATTATA APPEARED", 1, 16,
      Chrome.DEFAULT_BOX_PALETTE)
    Chrome.box(8, 12, 12, 6)
    Chrome.printThrough("FIGHT", 10, 14, Chrome.DEFAULT_BOX_PALETTE)
  end
  frame(screen({ drawsPics = false, extra = menu }))
  boxes = kinds("box")
  eq(#boxes, 2, "the menu over the message box lays its own paper")
  ok(boxes[1] and near(boxes[1].alpha, 0.5) and boxes[2]
     and near(boxes[2].alpha, 0.5),
     "one layer each, at the strength picked")
  local field = backdropDraws()
  eq(#field, 2, "the field went down once for the frame and once under the "
     .. "menu")
  local again = field[2]
  ok(again and sameRect(again.scissor, 64, 96, 96, 48),
     "and the second time only inside the menu's own rect")
  ok(again and again.at < boxes[2].at,
     "before the menu's paper -- so the paper goes on the backdrop, not on "
     .. "the message box's paper")
  local line
  for _, printed in ipairs(prints) do
    if printed.text == "RATTATA APPEARED" then line = printed end
  end
  ok(line and tail == 16 * 8, "with the message's tail printed under it first")
  eq(scissor, nil, "and the scissor is handed back")
  eq(#kinds("rect"), 0, "a line in the inner box still loses its cell")

  -- Drawn the way the panel is: under a transform of the caller's
  -- (Chrome.withPanel's translate and scale), and with the strip under one of
  -- its own on top (WideBattle's).  The field goes back where drawScene put
  -- it, not where the box is drawn from.
  local function shifted()
    love.graphics.push()
    love.graphics.translate(8, 0)
    Chrome.box(8, 12, 11, 6)
    love.graphics.pop()
  end
  fills, draws, drawn, keyed, prints = {}, {}, {}, {}, {}
  xf, scissor, blend, canvasNow, stack = { x = 10, y = 20, s = 2 }, nil,
    "alpha", nil, {}
  BattleState.drawScene(screen({ drawsPics = false, extra = shifted }))
  field = backdropDraws()
  again = field[2]
  ok(again and sameRect(again.scissor, 10 + (8 + 64) * 2, 20 + 96 * 2, 88 * 2,
     48 * 2), "under a scaled panel the scissor is the box on the surface")
  ok(again and again.xf.x == 10 and again.xf.y == 20 and again.xf.s == 2,
     "and the field is painted in drawScene's transform, not the strip's")
  ok(field[1] and again and field[1].xf.x == again.xf.x
     and field[1].xf.s == again.xf.s, "the same one it went down in")

  -- WideBattle docks the strip below the field on a tall screen.  A box
  -- wholly below it has nothing of the arena's under it -- only the
  -- playfield's opaque paper, which one more layer of paper does not change.
  local function docked()
    love.graphics.push()
    love.graphics.translate(0, 200)
    Chrome.box(8, 12, 12, 6)
    love.graphics.pop()
  end
  frame(screen({ drawsPics = false, extra = docked }))
  eq(#backdropDraws(), 1, "nothing is repainted wholly outside the field")
  boxes = kinds("box")
  ok(boxes[2] and near(boxes[2].alpha, 0.5),
     "and the box is laid at the strength picked")

  -- On a 16:9 screen it hangs over the field's bottom edge by 18 rows: the
  -- part over the field is put back, so the menu is one layer there like the
  -- rest of the strip, not two.
  local function overhang()
    love.graphics.push()
    love.graphics.translate(0, 18)
    Chrome.box(8, 12, 12, 6)
    love.graphics.pop()
  end
  frame(screen({ drawsPics = false, extra = overhang }))
  field = backdropDraws()
  eq(#field, 2, "a box half over the field has that half put back")
  ok(field[2] and sameRect(field[2].scissor, 64, 96 + 18, 96, 144 - 114),
     "clipped to where the box and the field overlap")
  boxes = kinds("box")
  ok(boxes[2] and near(boxes[2].alpha, 0.5) and field[2]
     and field[2].at < boxes[2].at, "and then laid once, on top")

  -- An animation bakes the panel into a canvas of its own, laid over the
  -- surface the field is on: there the box's rect is cleared to nothing.
  local LAYER = {}
  local function baked()
    local was = canvasNow
    love.graphics.setCanvas(LAYER)
    Chrome.box(8, 12, 12, 6)
    love.graphics.setCanvas(was)
  end
  frame(screen({ drawsPics = false, extra = baked }))
  eq(#backdropDraws(), 1, "on an animation's layer the field is not painted")
  local erased
  for _, f in ipairs(fills) do
    if f.blend == "replace" and f.alpha == 0 then erased = f end
  end
  ok(erased and erased.x == 64 and erased.y == 96 and erased.w == 96
     and erased.h == 48, "the rect is cleared back to transparent instead")
  eq(blend, "alpha", "and the blend mode is handed back")

  -- The continue arrow sits ON the message box's bottom border, (18,17).  On
  -- the cart its tile replaces the border's; see-through, its cell dropped
  -- left the arrow drawn across the border's lines.
  local function arrow()
    Chrome.printThrough("v", 18, 17, Chrome.DEFAULT_BOX_PALETTE)
  end
  frame(screen({ drawsPics = false, extra = arrow }))
  field = backdropDraws()
  ok(field[2] and sameRect(field[2].scissor, 144, 136, 8, 8),
     "the border under the arrow is taken out")
  local cell = kinds("rect")[1]
  ok(cell and cell.x == 144 and cell.y == 136 and near(cell.alpha, 0.5)
     and cell.at > field[2].at, "and its cell laid at the box's strength")

  -- CLEAR HUD = OFF asks for the cart's HUD, paper cells and all; CLEAR BOXES
  -- is about the boxes and leaves the HUD's text alone.
  mod.stored.hud_clear = false
  frame(screen({ drawsPics = false }))
  local cells = 0
  for _, f in ipairs(kinds("rect")) do
    if f.y < 12 * 8 then cells = cells + 1 end
  end
  eq(cells, 2, "with CLEAR HUD off, both HUD lines keep their paper cells")
  mod.stored.hud_clear = nil

  -- And only over a backdrop: on Gold's own white field there is nothing
  -- behind a box to see.
  mod.stored.box_clear = 50
  mod.stored.enabled = false
  frame(screen({ drawsPics = false }))
  eq(boxFill() and boxFill().alpha, 1,
     "with no backdrop the box is the cart's, whatever the row says")
  mod.stored.enabled = nil
  mod.stored.box_clear = nil
end

-- TIME OF DAY runs last: it reloads the module into a fresh mod, and every
-- wrapper from then on reads THAT mod's options.
do
  io.write("TIME OF DAY: the field at night goes through the cart's night\n")
  -- The shader is the GPU half of TIME OF DAY: an affine map of RGB fitted to
  -- the live map's DAY and NITE palettes.  What is asserted here is the DRAW:
  -- the backdrop is painted with that shader bound and its four uniforms
  -- sent, the shader the caller had is put back, and a host with no shaders
  -- gets a tint through setColor instead of nothing.
  local bound, sent = nil, {}
  local SHADER = { send = function(_, name, value) sent[name] = value end }
  local realSet, realGet, realNew = love.graphics.setShader,
    love.graphics.getShader, love.graphics.newShader
  love.graphics.setShader = function(s) bound = s end
  love.graphics.getShader = function() return bound end
  love.graphics.newShader = function() return SHADER end
  local day = {}
  for slot = 1, 8 do
    day[slot] = { { 216, 248, 216 }, { 168, 168, 168 }, { 104, 104, 104 },
                  { 56, 56, 56 } }
  end
  package.loaded["src.world.gen2.Palettes"] = {
    bgSet = function(_, _, daytime)
      if daytime == "DAY" then return day end
      local out = {}
      for slot = 1, 8 do
        out[slot] = {}
        for i = 1, 4 do
          local c = day[slot][i]
          out[slot][i] = { c[1] * 0.5, c[2] * 0.5, c[3] * 0.9 }
        end
      end
      return out
    end,
  }

  local function nightScreen(daytime)
    local self = screen({ drawsPics = false })
    self.game = { world = {
      daytime = daytime, palettes = "live",
      map = { def = { id = "ROUTE_29", tileset = "TILESET_JOHTO",
                      environment = "ROUTE", group = 24 } },
      currentLandmarkId = function() return "LANDMARK_ROUTE_29" end,
    } }
    return self
  end

  local seen
  local realDraw = love.graphics.draw
  love.graphics.draw = function(image, ...)
    if type(image) == "table" and image.getWidth then
      seen = seen or { shader = bound }
    end
    return realDraw(image, ...)
  end

  local caller = { "the caller's shader" }
  bound = caller
  seen, sent = nil, {}
  frame(nightScreen("NITE"))
  ok(seen and seen.shader == SHADER,
     "the backdrop is drawn with the TIME OF DAY shader bound")
  ok(sent.rowR and sent.rowG and sent.rowB and sent.offset,
     "and its transform sent: three rows and an offset")
  eq(bound, caller, "and the caller's shader is back afterwards")

  bound, seen = nil, nil
  frame(nightScreen("DAY"))
  ok(seen and seen.shader == nil,
     "by day the backdrop is drawn with no shader at all, as before")

  -- No shaders on this host: the period's answer for white, as a tint.
  local tints = {}
  local realColor = love.graphics.setColor
  love.graphics.setColor = function(r, g, b, a)
    tints[#tints + 1] = { r, g, b }
    return realColor(r, g, b, a)
  end
  love.graphics.newShader = function() error("no shaders here", 0) end
  -- A fresh load, so the one compile attempt is made against this host.
  local fresh = { id = mod.id, path = mod.path, exports = {}, stored = {},
                  hooked = {}, events_on = {}, logged = {} }
  for k, v in pairs(mod) do if fresh[k] == nil then fresh[k] = v end end
  fresh.options = {
    define = function() end,
    get = function(_, key) return fresh.stored[key] end,
    set = function(_, key, value) fresh.stored[key] = value end,
  }
  fresh.hooks = { wrap = function(_, name, fn) fresh.hooked[name] = fn end }
  fresh.events = { on = function(_, name, fn) fresh.events_on[name] = fn end }
  BattleState.__gen1arena = nil
  BattleState.drawScene = function(self, bodyFn)
    drawn[#drawn + 1] = "scene"
    if bodyFn then bodyFn() else self:drawPanel() end
  end
  load_("main.lua", fresh)
  fresh.events_on["game.ready"]({ game = {} })
  tints = {}
  frame(nightScreen("NITE"))
  local tinted = false
  for _, c in ipairs(tints) do
    if c[1] < 0.9 and c[3] > c[1] then tinted = true end
  end
  ok(tinted, "a host with no shaders paints the backdrop through a night tint")

  love.graphics.setShader, love.graphics.getShader = realSet, realGet
  love.graphics.newShader, love.graphics.draw = realNew, realDraw
  love.graphics.setColor = realColor
  package.loaded["src.world.gen2.Palettes"] = nil
end

io.write(("arena gen2 paper: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
