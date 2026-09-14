-- The bars around a battle, and the arithmetic that fills them.
--
-- A battle asks the renderer for a WHITE surround: Renderer:endFrame clears
-- the void to PaletteFX.paperShade for any state that sets `letterboxWhite`,
-- and a battle sets it.  That is right for the game it was written for -- the
-- field is white paper, so a white surround makes the paper look like it runs
-- off the screen instead of stopping at a rectangle.
--
-- Put a BACKDROP in the field and the reasoning inverts.  The paper is gone,
-- the surround is the only white left, and instead of disappearing it becomes
-- a bright frame around the art.  A WIDE battle is 304x144 -- very wide and no
-- taller -- so in an ordinary window the bars above and below it are the
-- biggest thing on the screen.  That is the white bar at the top of a wide
-- arena, and Gen1Arena now bleeds the backdrop's own edge into it.
--
-- What can be wrong here is arithmetic: a bar an edge short, a corner left as
-- paper, a rectangle with a negative width.  None of that needs a window, so
-- bleedRects is pure and this drives it directly.
--
-- Run:  luajit tests/arenableed_test.lua

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

-- Gen1Arena reads love.graphics.rectangle at chunk scope -- it shims that call
-- to swap the battle's field fill for a backdrop -- so `love` has to exist for
-- the file to load at all.  A stub, because nothing under test draws: the
-- geometry is bleedRects and it returns numbers.
_G.love = _G.love or { graphics = {} }
love.graphics.rectangle = love.graphics.rectangle or function() end
love.graphics.setColor = love.graphics.setColor or function() end
love.graphics.getColor = love.graphics.getColor or function() return 1, 1, 1, 1 end
love.graphics.getCanvas = love.graphics.getCanvas or function() return nil end
love.graphics.setCanvas = love.graphics.setCanvas or function() end
love.graphics.clear = love.graphics.clear or function() end
love.graphics.newQuad = love.graphics.newQuad
  or function(x, y, w, h) return { x = x, y = y, w = w, h = h } end
love.graphics.draw = love.graphics.draw or function() end

-- Gen1Arena installs at chunk scope off `local mod = ...`, so this is the
-- only other thing it needs.
local mod = {
  id = "gen1_wild_ui_nightly",
  exports = {},
  stored = {},
  hooked = {},
  events_on = {},
}
mod.options = {
  define = function() end,
  get = function(_, key) return mod.stored[key] end,
  set = function(_, key, value) mod.stored[key] = value end,
}
mod.log = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  mod.log[level] = function() end
end
mod.hooks = { wrap = function(_, name, fn) mod.hooked[name] = fn end }
mod.events = { on = function(_, name, fn) mod.events_on[name] = fn end }
mod.assets = { path = function(_, p) return p end }
mod.storage = { writeBytes = function() return true end }
mod.content = {}

load_("main.lua", mod)

local bleedRects = mod.exports.bleedRects
ok(type(bleedRects) == "function", "bleedRects is exposed")
local bleedCover = mod.exports.bleedCover
ok(type(bleedCover) == "function", "and the cover fit with it")
ok(mod.hooked["render.letterbox"] ~= nil,
  "and the mod takes the seam the engine documents for void art")

-- ---------------------------------------------- one picture, one scale

-- Reported with a screenshot: a crisp rectangle of backdrop in the middle of
-- a Crystal battle and a visibly bigger, blurrier copy of the same scene
-- around it, with a hard seam between them.
--
-- The field is painted ON the battle surface and the engine scales that
-- surface to the window.  The bars used to be filled by cover-fitting the
-- same picture to the WHOLE WINDOW instead -- a different and always larger
-- scale -- so the screen carried one photograph at two magnifications with
-- the surface's edge as the join.
--
-- This is the arithmetic that replaced it: the picture's scale and origin, in
-- window pixels, taken from where the SURFACE landed.
do
  io.write("the bars are the same picture at the same scale\n")

  local surfaceFit = mod.exports.bleedSurfaceFit
  ok(type(surfaceFit) == "function", "the placement is exposed")

  -- 160x144 doubled and centred in a 400x400 window.
  local view = { ww = 400, wh = 400, ox = 40, oy = 56, vpw = 320, vph = 288 }

  -- A WIDE picture on the classic surface: `drawCover` centres it at 1:1, so
  -- its middle 160 columns are the field and 72 columns hang off each side.
  local sx, sy, dx, dy = surfaceFit(304, 144, 160, 144, view)
  eq(sx, 2, "the picture is drawn at the surface's own scale, not the window's")
  eq(sy, 2, "on both axes")
  eq(dx, 40 - 72 * 2,
     "starting 72 authored columns left of the surface, which is exactly what "
     .. "a 304-wide picture has to spare against a 160-wide one")
  eq(dy, 56, "and level with it")

  -- The same picture, same surface, under BATTLE SIZE = FILL: the engine puts
  -- the surface on screen at a fractional scale, and the picture follows it
  -- rather than being re-fitted to the window.
  local fill = { ww = 400, wh = 400, ox = 20, oy = 0, vpw = 360, vph = 324 }
  sx, sy, dx = surfaceFit(304, 144, 160, 144, fill)
  eq(sx, 360 / 160, "FILL's fractional scale is the surface's, and the "
     .. "picture takes it too -- which is the whole of the seam")
  eq(dx, 20 - 72 * (360 / 160), "and the offset scales with it")

  -- An OG picture on the classic surface covers it exactly, so there is
  -- nothing outside it: the origin IS the surface's origin.
  sx, sy, dx, dy = surfaceFit(160, 144, 160, 144, view)
  eq(sx, 2, "an exactly-sized picture is 1:1 on the surface")
  eq(dx, 40, "and starts where the surface starts")
  eq(dy, 56, "on both axes -- there is no outside to show")

  -- A degenerate view has no answer rather than a wrong one.
  eq(tostring(surfaceFit(304, 144, 160, 144,
                         { ww = 400, wh = 400, vpw = 0, vph = 0 })),
     "nil", "a surface with no area is not a placement")
  eq(tostring(surfaceFit(0, 144, 160, 144, view)), "nil",
     "and neither is a picture with none")
end

-- --------------------------------------- which size of the art it asks for

do
  io.write("the art is picked for the shape, not for the setting\n")

  local artLayout = mod.exports.arenaArtLayout
  local seeView = mod.exports.arenaSeeView
  ok(type(artLayout) == "function" and type(seeView) == "function",
     "the choice and the view it reads are both exposed")

  -- Nothing seen yet: the surface is all there is, so the classic art is right.
  seeView(nil)
  eq(artLayout("og"), "og", "with no frame behind it, the surface's own size")
  eq(artLayout("wide"), "wide", "and a wide surface is always wide")

  -- A window exactly the surface's width: no bars, nothing to spare, no
  -- reason to reach for a bigger picture.
  seeView({ ww = 320, wh = 400, ox = 0, oy = 56, vpw = 320, vph = 288 })
  eq(artLayout("og"), "og", "a window with no side bars keeps the small art")

  -- Side bars: a 160-wide picture has nothing outside itself to put in them,
  -- and a 304-wide one has 72 authored columns each side.  This is the
  -- reported case -- BATTLE SIZE = FILL, classic layout, a wide window.
  seeView({ ww = 1000, wh = 400, ox = 340, oy = 56, vpw = 320, vph = 288 })
  eq(artLayout("og"), "wide",
     "side bars ask for the wide art even on the classic surface, because "
     .. "that is the only picture with anything to put in them")
  eq(artLayout("wide"), "wide", "and the wide surface is unchanged")

  -- A one-pixel remainder from an odd window is not a bar.
  seeView({ ww = 321, wh = 400, ox = 0, oy = 56, vpw = 320, vph = 288 })
  eq(artLayout("og"), "og", "a rounding remainder is not somewhere to put a picture")

  seeView(nil)
end

local function by(rects)
  local out = {}
  for _, r in ipairs(rects or {}) do out[r.slice] = r end
  return out
end

-- Every pixel of the window is either the surface or exactly one bar.
local function covers(rects, view)
  local area = 0
  for _, r in ipairs(rects or {}) do
    if r.w <= 0 or r.h <= 0 then return false, "a rectangle with no area" end
    area = area + r.w * r.h
  end
  local want = view.ww * view.wh - view.vpw * view.vph
  if area ~= want then
    return false, ("bars cover %d of the %d that are not the surface")
      :format(area, want)
  end
  return true
end

-- ---------------------------------------------------------------- the bars

io.write("a wide battle in an ordinary window\n")
do
  -- 304x144 blown up to 912x432 and centred in a 1000x700 window: the bars
  -- above and below are 134 tall, which is the complaint.
  local view = { ww = 1000, wh = 700, ox = 44, oy = 134, vpw = 912, vph = 432 }
  local rects = bleedRects(view)
  local b = by(rects)

  ok(b.top, "there is a bar above the battle")
  eq(b.top.y, 0, "starting at the top of the window")
  eq(b.top.h, 134, "as tall as the gap")
  eq(b.top.x, view.ox, "and only as wide as the surface")
  eq(b.top.w, view.vpw, "...which the corners finish off")

  eq(b.bottom.y, view.oy + view.vph, "the bar below starts where it ends")
  eq(b.bottom.h, view.wh - (view.oy + view.vph), "and runs to the window")

  eq(b.left.w, 44, "the side bars are the horizontal remainder")
  eq(b.right.x, view.ox + view.vpw, "the right one starting past the surface")
  eq(b.right.w, view.ww - (view.ox + view.vpw), "and running to the edge")

  ok(b.tl and b.tr and b.bl and b.br, "all four corners are filled")
  eq(b.tl.w, view.ox, "a corner is as wide as the side beside it")
  eq(b.tl.h, view.oy, "and as tall as the bar above it")

  local whole, why = covers(rects, view)
  ok(whole, "and between them they leave no paper: " .. tostring(why))
end

io.write("a surface that fills the window edge to edge\n")
do
  local view = { ww = 912, wh = 432, ox = 0, oy = 0, vpw = 912, vph = 432 }
  local rects = bleedRects(view)
  eq(#rects, 0, "no bars, and none drawn -- not eight empty rectangles")
end

io.write("a surface as wide as the window but not as tall\n")
do
  -- the usual wide case on a 16:9 display
  local view = { ww = 960, wh = 540, ox = 0, oy = 43, vpw = 960, vph = 454 }
  local rects = bleedRects(view)
  local b = by(rects)
  ok(b.top and b.bottom, "a bar above and below")
  ok(not b.left and not b.right, "and none at the sides, because there is no gap")
  ok(not b.tl and not b.tr, "nor corners")
  local whole, why = covers(rects, view)
  ok(whole, "still no paper anywhere: " .. tostring(why))
end

io.write("a view that says nothing useful\n")
do
  eq(bleedRects(nil), nil, "no view at all")
  eq(bleedRects({}), nil, "an empty one")
  eq(bleedRects({ ww = 100, wh = 100, vpw = 0, vph = 0 }), nil,
    "a surface with no size: there is nothing to bleed from")
  eq(bleedRects({ ww = 0, wh = 0, vpw = 10, vph = 10 }), nil,
    "and a window with no size has nowhere to put it")
end

io.write("a surface hanging off the edge of the window\n")
do
  -- The renderer clamps, but the hook is handed numbers rather than promises:
  -- a negative remainder must produce no bar rather than a rectangle drawn
  -- backwards across the screen.
  local view = { ww = 200, wh = 200, ox = -20, oy = -20, vpw = 300, vph = 300 }
  local rects = bleedRects(view)
  for _, r in ipairs(rects) do
    ok(r.w > 0 and r.h > 0, r.slice .. " has a positive size or is not there")
  end
  eq(#rects, 0, "which here means no bars at all")
end

-- --------------------------------------------------- what fills a bar

-- It was the picture's one-pixel edge stretched outward, which is exact where
-- the bars are thin and a field of horizontal stripes where they are not: on
-- a landscape phone the bars are wider than the surface between them, and one
-- source row becomes a six-pixel band across two thirds of the window.
--
-- Now the bars show the same picture, scaled to COVER the window, each one
-- showing the part that falls where it is.  The property that makes this the
-- right answer rather than merely a different one is below: the cover scale
-- and the surface scale converge as the bars shrink, so the seam closes by
-- itself and a thin-bar window looks exactly as continuous as it used to.

io.write("the cover always reaches every corner\n")
do
  local scale, dx, dy = bleedCover(160, 144, 800, 400)
  ok(160 * scale >= 800 - 0.001, "wide enough")
  ok(144 * scale >= 400 - 0.001, "and tall enough")
  ok(dx <= 0.001 and dy <= 0.001, "so the overhang is outside, not inside")
  eq(dx * 2 + 160 * scale, 800, "and centred on the axis that overhangs")

  local tall = select(1, bleedCover(160, 144, 300, 900))
  ok(144 * tall >= 900 - 0.001, "a tall window covers on the other axis")
  ok(160 * tall >= 300 - 0.001, "...and still spans the short one")
end

io.write("and closes on the surface's own scale as the bars shrink\n")
do
  -- The surface is drawn at vpw/iw.  A window barely wider than the surface
  -- gives a cover scale within a whisker of it, which is why the seam is not
  -- visible until the bars are wide enough for the picture to be worth
  -- looking at anyway.
  local iw, ih = 160, 144
  local vpw, vph = 640, 576                 -- the surface at 4x
  local surface = vpw / iw

  local snug = select(1, bleedCover(iw, ih, vpw + 8, vph + 8))
  ok(math.abs(snug - surface) < 0.02 * surface,
    "eight pixels of bar is a two percent scale step, which is no seam")

  local wide = select(1, bleedCover(iw, ih, vpw * 2, vph))
  ok(wide > surface, "a window twice as wide zooms in rather than stretching")
  ok(wide <= surface * 2 + 0.001, "and no further than covering asks for")
end

io.write("a degenerate window is not a window\n")
do
  eq(bleedCover(0, 144, 800, 400), nil, "no picture")
  eq(bleedCover(160, 0, 800, 400), nil, "...on either axis")
  eq(bleedCover(160, 144, 0, 400), nil, "no window")
  eq(bleedCover(160, 144, 800, 0), nil, "...on either axis")
end

-- ------------------------------------------- where the picture stops being
-- a picture
--
-- Every backdrop is authored with its last rows in ONE flat colour, because
-- those are the rows the cart's message box sits on: 48 of them on the
-- 160-wide art, exactly the box's six tiles, and 40 on the 304-wide art.  On
-- the game screen nobody ever sees them.
--
-- The BARS see them.  On the classic surface this mod bleeds the wide art
-- into the wings either side, and out there the cart has no message box -- so
-- the band arrives as a slab of flat colour across the bottom of both wings.
-- That is the report, with the two of them circled in red: *"there is still a
-- bar of solid color at the bottom, can we make it so those are cut off?"*
--
-- Measured off the file rather than declared, so the answer follows the art.

-- An ImageData as LOVE hands one over, from a row-painting function.
local function fakeData(w, h, at)
  return {
    getDimensions = function() return w, h end,
    getPixel = function(_, x, y)
      local r, g, b = at(x, y)
      return r, g, b, 1
    end,
  }
end

local bandTop = mod.exports.arenaBandTop

do
  io.write("the flat band is measured off the picture\n")
  local made = {}
  love.image = { newImageData = function(path) return made[path] end }

  -- The wide art: 40 flat rows under 104 rows of scenery.
  made["wide"] = fakeData(304, 144, function(x, y)
    if y >= 104 then return 0.87, 1, 0.32 end
    return (x % 7) / 7, (y % 5) / 5, 0.5
  end)
  eq(bandTop("wide", 304, 144), 104, "the wide art's band starts at row 104")

  -- The classic art: 48, which is the message box's six tiles exactly.
  made["og"] = fakeData(160, 144, function(x, y)
    if y >= 96 then return 0.87, 1, 0.32 end
    return (x % 7) / 7, (y % 5) / 5, 0.5
  end)
  eq(bandTop("og", 160, 144), 96, "and the classic art's at row 96")

  -- A single flat edge row is ordinary art, not a band, and trimming it would
  -- take a row off every backdrop that happens to end on one colour.
  made["edge"] = fakeData(304, 144, function(x, y)
    if y >= 143 then return 0, 0, 0 end
    return (x % 7) / 7, (y % 5) / 5, 0.5
  end)
  eq(bandTop("edge", 304, 144), nil, "a one-row edge is not a band")

  -- ...and a picture that is mostly one colour is a flat backdrop with
  -- nothing to trim, not a picture with an enormous band.
  made["flat"] = fakeData(304, 144, function(_, y)
    if y >= 20 then return 0.2, 0.2, 0.2 end
    return 0.9, 0.9, 0.9
  end)
  eq(bandTop("flat", 304, 144), nil,
     "and neither is a band over half the picture")

  -- A file the host will not hand back, or hands back at another size, is
  -- measured as no band rather than guessed at.
  eq(bandTop("missing", 304, 144), nil, "an unreadable file has no band")
  made["wrong"] = fakeData(160, 144, function() return 0, 0, 0 end)
  eq(bandTop("wrong", 304, 144), nil, "and neither has one at the wrong size")

  love.image = nil
  eq(bandTop("wide", 304, 144), nil,
     "a host with no love.image trims nothing, which is what it did before")
end

do
  io.write("...and the bars are clamped to it\n")
  -- Source-shape, because the clamp is one `math.min` inside `coverQuads` and
  -- coverQuads needs a live Image to drive.  What can go wrong here is the
  -- clamp being dropped, or being written against `ih` again, and both of
  -- those are visible in the text.
  local handle = assert(io.open("main.lua", "r"))
  local text = handle:read("*a")
  handle:close()
  ok(text:find("local floorV = pictureBottom(img) or ih", 1, true) ~= nil,
     "the bars take the picture's floor, and the whole picture when it has "
     .. "no band")
  ok(text:find("local v1 = math.min(floorV, (r.y + r.h - dy) / sy)",
                1, true) ~= nil,
     "and every bar's source rectangle stops there")
  ok(text:find("surfW or 0, surfH or 0, floorV)", 1, true) ~= nil,
     "with the floor in the quad cache's key, or the first backdrop's band "
     .. "would be used for every backdrop after it")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
