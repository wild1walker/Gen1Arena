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

love.graphics = {
  rectangle = function(mode, x, y, w, h)
    fills[#fills + 1] = { kind = "rect", x = x, y = y, w = w, h = h }
  end,
  setColor = function() end,
  getColor = function() return 1, 1, 1, 1 end,
  push = function() end,
  pop = function() end,
  origin = function() end,
  setScissor = function() end,
  setShader = function() end,
  setBlendMode = function() end,
  getCanvas = function() return nil end,
  setCanvas = function() end,
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
  newCanvas = function()
    return { newImageData = function() return IMAGE_DATA end }
  end,
  draw = function(image, a, b, c, d)
    draws[#draws + 1] = { image = image, a = a, b = b, c = c, d = d }
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
  Chrome.printThrough("HELLO", 1, 14, Chrome.DEFAULT_BOX_PALETTE)
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
  }
  -- The class behind it, so `self:drawEnemyHud()` reaches the wrapped method
  -- the way it does on a live instance.
  return setmetatable(self, { __index = BattleState })
end

local function frame(self)
  fills, draws, drawn, keyed, prints = {}, {}, {}, {}, {}
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
  frame(screen())

  local blits = picBlits()
  eq(#blits, 4, "two pics, and each one drawn twice: its paper, then it")
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
  local realCanvas = love.graphics.newCanvas
  love.graphics.newCanvas = function()
    return { newImageData = function()
      return {
        getDimensions = function() return 8, 8 end,
        getPixel = function(_, x, y) return 0, 0, 0, 1 end,
      }
    end }
  end
  eq(mod.exports.picPaperImage(solid), nil,
     "a pic with no hole in it builds no paper and costs one readback")
  love.graphics.newCanvas = realCanvas
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
  local realCanvas = love.graphics.newCanvas
  love.graphics.newCanvas = function()
    return { newImageData = function()
      return {
        getDimensions = function() return w, h end,
        getPixel = function(_, x, y)
          local v = plot(x, y)
          return v, v, v, 1
        end,
      }
    end }
  end
  return img, function() love.graphics.newCanvas = realCanvas end
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
  -- Replacement art: too many colours to be a 2bpp pic, and it carries its own
  -- alpha.  Refused, by the same test the paper arm uses.
  local img, restore = shadePic(8, 8, function(x, y) return (x * 8 + y) / 64 end)
  local cut = mod.exports.picCutoutImage(img)
  restore()
  eq(cut, nil, "full-colour replacement art is left alone")
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
  local realCanvas = love.graphics.newCanvas
  love.graphics.newCanvas = function()
    return { newImageData = function()
      return {
        getDimensions = function() return 8, 8 end,
        getPixel = function(_, x, y)
          if x == 0 then return 1, 1, 1, 0 end
          return 0, 0, 0, 1
        end,
      }
    end }
  end
  local cut = mod.exports.picCutoutImage(img)
  love.graphics.newCanvas = realCanvas
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

io.write(("arena gen2 paper: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
