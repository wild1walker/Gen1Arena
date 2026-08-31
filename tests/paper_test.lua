-- Gen1Arena: the paper laid under a battle pic.
--
-- Run from anywhere:  luajit tests/paper_test.lua
--
-- The mod draws nothing this suite can look at directly -- everything it does
-- happens inside LOVE calls -- so LOVE is stubbed and the calls are recorded.
-- The one that matters is the fill that goes down before the engine draws a
-- battler: whether it happens at all, where it lands, and how big it is.
--
-- The pics are the real shapes the question is about.  A matted Gen 1 pic is
-- a body the extractor's colour-0 flood ate holes in (Mew's back pic keeps 145
-- of the 400 pixels in its own bounding box); a mod's replacement pic is
-- solid, carries its own alpha and must be left alone.  Both are built here
-- rather than read off disk so the suite needs no ROM and no assets.

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local root = here:match("^(.*)[/\\]tests$") or (here .. "/..")

-- ------------------------------------------------------------ tiny asserts

local passed, failed = 0, 0
local function check(cond, what)
  if cond then passed = passed + 1
  else failed = failed + 1; print("FAIL: " .. what) end
end
local function eq(got, want, what)
  check(got == want, ("%s (got %s, want %s)")
    :format(what, tostring(got), tostring(want)))
end

-- ------------------------------------------------------------- pic fixtures

-- px[y][x] = { r, g, b, a } in 0..1.  `newPic` takes rows of characters:
--   "."  transparent (what the matte flood turned white into)
--   "#"  black ink        "o" mid grey        "w" opaque white
local SHADE = {
  ["#"] = { 0, 0, 0, 1 },
  ["o"] = { 0.33, 0.33, 0.33, 1 },
  ["w"] = { 1, 1, 1, 1 },
  ["."] = { 1, 1, 1, 0 },
}

local PicMT = {
  __index = {
    setFilter = function() end,
    getWidth = function(self) return self.w end,
    getHeight = function(self) return self.h end,
    getDimensions = function(self) return self.w, self.h end,
  },
}

local function newPic(rows, extraColors)
  local h, w = #rows, #rows[1]
  local px = {}
  for y = 1, h do
    px[y] = {}
    for x = 1, w do
      local c = rows[y]:sub(x, x)
      px[y][x] = SHADE[c] or SHADE["."]
    end
  end
  -- a true-colour pic: enough distinct opaque colours that it cannot be the
  -- four-shade kind, painted over the shape's opaque pixels
  if extraColors then
    local n = 0
    for y = 1, h do
      for x = 1, w do
        if px[y][x][4] > 0 then
          n = n + 1
          px[y][x] = { (n % 17) / 17, (n % 13) / 13, (n % 11) / 11, 1 }
        end
      end
    end
  end
  return setmetatable({ w = w, h = h, px = px, __image = true }, PicMT)
end

-- A pale mon after the matte flood: an outline with the body eaten out.
local HOLLOW_ROWS = {
  "..######..",
  ".#......#.",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  ".#......#.",
  "..######..",
}
local HOLLOW = newPic(HOLLOW_ROWS)

-- The same silhouette with its body intact: nothing was lost, so nothing is
-- owed back.
local SOLID_ROWS = {
  "..######..",
  ".#wwwwww#.",
  "#wwoowwww#",
  "#wwoowwww#",
  "#wwwwwwww#",
  "#wwwwwwww#",
  "#wwwwwwww#",
  "#wwwwwwww#",
  ".#wwwwww#.",
  "..######..",
}
local SOLID = newPic(SOLID_ROWS)

-- An undamaged mon with an awkward silhouette: a body with a plume coming off
-- it, the way a Crystal Koffing's gas is.  Most of its bounding box is empty
-- and none of that emptiness is a hole -- so by "how much of the box is not
-- ink" it looks as eaten as the outline above, and it is not eaten at all.
-- The real frames this stands for score 0.51 by that measure and 0.00 by the
-- one the mod uses.
local PLUME_ROWS = {
  "....##....",
  "....##....",
  "...#o#....",
  "...#o#....",
  ".########.",
  "#oooooooo#",
  "#oooooooo#",
  "#oooooooo#",
  ".########.",
  "..######..",
}
local PLUME = newPic(PLUME_ROWS)

-- The damage the paper is for, in a shape nothing else about it looks odd:
-- a solid body with the flood having eaten a window through the middle.
local WINDOW_ROWS = {
  "..######..",
  ".#oooooo#.",
  "#o......o#",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  "#o......o#",
  ".#oooooo#.",
  "..######..",
}
local WINDOW = newPic(WINDOW_ROWS)

-- A sprite mod's replacement: hollow-looking by the same measure, but in full
-- colour, so its alpha is its own and honest.
local TRUECOLOR = newPic({
  "..######..",
  ".#......#.",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  "#........#",
  ".#......#.",
  "..######..",
}, true)

-- ------------------------------------------------------------- the LOVE stub

local rects = {}            -- every love.graphics.rectangle call, in order
local currentCanvas = nil
local color = { 1, 1, 1, 1 }

-- The engine draws the battle under a translate and a scale for the
-- letterboxed surface, and clips to it.  The mod measures a pic by drawing it
-- into a scratch canvas of its own, which only lands at 0,0 if that transform
-- is reset first -- so the stub models the transform rather than ignoring it.
-- Without it this suite cannot see the difference between a readback that
-- works and one that reads a handful of stray pixels, which is exactly how a
-- white box behind a Crystal sprite shipped.
local transformed = false
local stack = {}

local function newImageData(px, w, h)
  return {
    getDimensions = function() return w, h end,
    getPixel = function(_, x, y)
      local p = px[y + 1] and px[y + 1][x + 1]
      if not p then return 0, 0, 0, 0 end
      return p[1], p[2], p[3], p[4]
    end,
  }
end

-- The window's DPI scale, which love.graphics.newCanvas takes unless it is
-- told otherwise.  1 on a desktop -- which is why measuring a corner of the
-- pic and calling it the mon shipped twice -- and 3 on the phone the white
-- box was photographed on.
--
-- `ignorePin` is a host that takes the size and disregards the dpiscale
-- setting.  The measurement is supposed to survive that too, by reading what
-- actually came back instead of what it asked for.
local dpiScale = 1
local ignorePin = false

_G.love = {
  graphics = {
    newImage = function(path) return newPic({ "w" }) end,
    newCanvas = function(w, h, settings)
      local s = dpiScale
      if settings and settings.dpiscale and not ignorePin then
        s = settings.dpiscale
      end
      local c = { w = w, h = h, scale = s, px = {}, __canvas = true }
      function c:newImageData()
        return newImageData(self.px, self.w * self.scale, self.h * self.scale)
      end
      return c
    end,
    getCanvas = function() return currentCanvas end,
    setCanvas = function(c) currentCanvas = c end,
    clear = function() end,
    push = function() stack[#stack + 1] = transformed end,
    pop = function() transformed = table.remove(stack) end,
    origin = function() transformed = false end,
    translate = function() transformed = true end,
    scale = function() transformed = true end,
    setScissor = function() end,
    getColor = function() return color[1], color[2], color[3], color[4] end,
    setColor = function(r, g, b, a)
      color = { r or 1, g or 1, b or 1, a or 1 }
    end,
    getShader = function() return nil end,
    setShader = function() end,
    getBlendMode = function() return "alpha", "alphamultiply" end,
    setBlendMode = function() end,
    -- the readback the mod does: whatever is drawn into a canvas IS that
    -- canvas's pixels, which is the only property the measurement relies on
    draw = function(img, ...)
      if currentCanvas and currentCanvas.__canvas and img and img.px then
        -- under the battle's transform a draw at 0,0 lands off a canvas this
        -- small, so nothing arrives -- which is what the bug actually saw
        if transformed then return end
        -- a canvas at DPI scale n holds n physical pixels per drawn one, so
        -- the pic arrives magnified and the readback is that much bigger
        local s = currentCanvas.scale or 1
        if s == 1 then
          currentCanvas.px = img.px
          return
        end
        local out = {}
        for y = 1, #img.px * s do
          out[y] = {}
          local src = img.px[math.floor((y - 1) / s) + 1]
          for x = 1, #img.px[1] * s do
            out[y][x] = src[math.floor((x - 1) / s) + 1]
          end
        end
        currentCanvas.px = out
      end
    end,
    rectangle = function(mode, x, y, w, h)
      rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
    end,
  },
}

-- --------------------------------------------------------------- the mod

local defaults = {}
local mod = {
  path = root,
  -- what the loader hands a mod: the environment resolved once, copied on as
  -- plain data.  A sandboxed mod cannot read POKEPORT_DEV_MODE itself.
  developer = false,
  log = setmetatable({}, { __index = function() return function() end end }),
  options = {
    define = function(_, list)
      for _, o in ipairs(list) do defaults[o.key] = o.default end
    end,
    get = function(_, key) return defaults[key] end,
  },
  events = { on = function(_, name, fn) defaults["@" .. name] = fn end },
  -- The Loader hands every mod one of these (Loader.lua:1268) and this mod
  -- publishes its bleed geometry through it, so the stand-in needs it to be
  -- a table rather than nil.
  exports = {},
  -- and the mod wraps render.letterbox to paint the bars around a wide
  -- battle.  Nothing in this file drives that hook; it is here so requiring
  -- the mod does not stop at it.
  hooks = { wrap = function(_, name, fn) defaults["#" .. name] = fn end },
}

-- The engine stand-in.  Only what the mod actually touches: the two draw
-- entry points it wraps, and the pic lookup its paper asks for.
local BattleState = {}
BattleState.__index = BattleState
function BattleState:picImage(sprite) return sprite end
function BattleState:drawBattlerPic(battler, x, y, scale)
  self.drewPic = { battler = battler, x = x, y = y, scale = scale }
end
function BattleState:drawClassic()
  -- the engine's own letterbox transform is up for the whole battle draw
  love.graphics.translate(24, 16)
  love.graphics.scale(3, 3)
  -- the field fill the mod substitutes its backdrop for
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  self:drawBattlerPic(self.player, 8, 40, 2)
  love.graphics.origin()
end
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.battle.WideBattle"] = nil

local chunk = assert(loadfile(root .. "/main.lua"))
chunk(mod)
assert(defaults["@game.ready"], "the mod registered no game.ready")
defaults["@game.ready"]({ game = {} })
check(BattleState.__gen1arena, "the mod patched BattleState")

-- ------------------------------------------------------------------ helpers

-- Run one battle draw and hand back the fills it laid down, minus the
-- full-surface field fill the backdrop replaced.
local function drawWith(sprite, battler)
  rects = {}
  local battle = setmetatable(
    { player = battler or { sprite = sprite }, game = {} }, BattleState)
  battle.drawClassic(battle)
  local out = {}
  for _, r in ipairs(rects) do
    if not (r.x == 0 and r.y == 0 and r.w == 160 and r.h == 144) then
      out[#out + 1] = r
    end
  end
  return out, battle
end

-- ------------------------------------------------------------------- tests

do
  -- The case in the report: a pale mon over a backdrop.  Without the paper it
  -- is an outline with the scenery showing through the middle of it.
  local fills, battle = drawWith(HOLLOW)
  eq(#fills, 1, "a hollowed pic gets paper laid under it")
  local r = fills[1]
  if r then
    eq(r.mode, "fill", "and it is a filled rect, not an outline")
    -- HOLLOW's content box is the whole 10x10 pic, drawn at 8,40 scale 2
    eq(r.x, 8, "the paper starts at the pic's own left edge")
    eq(r.y, 40, "and its top edge")
    eq(r.w, 20, "and is the content box wide, at the pic's scale")
    eq(r.h, 20, "and the content box high")
  end
  check(battle.drewPic ~= nil, "and the engine still draws the pic itself")
end

do
  -- Nothing was eaten out of this one, so boxing it would be a white square
  -- over the backdrop bought for nothing.
  local fills = drawWith(SOLID)
  eq(#fills, 0, "a pic that kept its body gets no paper")
end

do
  -- A sprite mod's own art carries real alpha: the holes are the artist's.
  local fills = drawWith(TRUECOLOR)
  eq(#fills, 0, "true-colour replacement art is left alone")
end

do
  -- The measurement is cached per image, so a second battle costs no readback
  -- and still lays the paper.
  local fills = drawWith(HOLLOW)
  eq(#fills, 1, "the cached measurement still lays paper on the next battle")
end

do
  -- MON PAPER off hands the frame back exactly as the mod drew it before.
  defaults.pic_paper = false
  local fills = drawWith(HOLLOW)
  eq(#fills, 0, "MON PAPER off lays none")
  defaults.pic_paper = true
end

do
  -- Every path drawBattlerPic can take that does NOT put the whole pic at the
  -- x/y it was handed: paper laid at the base position would sit behind
  -- nothing, or behind the wrong thing.
  local elsewhere = {
    { "a fainted battler", { sprite = HOLLOW, fainted = true } },
    { "a substitute", { sprite = HOLLOW, substituteHP = 30 } },
  }
  for _, case in ipairs(elsewhere) do
    local fills = drawWith(HOLLOW, case[2])
    eq(#fills, 0, case[1] .. " gets no paper")
  end

  -- and the fx states, which the engine keeps beside the battler
  local hidden = { sprite = HOLLOW }
  local fills = drawWith(HOLLOW, hidden)
  eq(#fills, 1, "a plain battler still gets it")

  rects = {}
  local battle = setmetatable({ player = hidden, game = {} }, BattleState)
  battle.picFx = { [hidden] = { hidden = true } }
  battle.drawClassic(battle)
  local n = 0
  for _, r in ipairs(rects) do
    if not (r.x == 0 and r.y == 0 and r.w == 160 and r.h == 144) then
      n = n + 1
    end
  end
  eq(n, 0, "a hidden pic gets no paper")
end

-- ------- the dev rows are not in a player's face

-- DIAGNOSTIC and FIELD TEST are maintenance tools, and FIELD TEST is a trap on
-- a shipped cart: the row does not say what it does, and finding out leaves
-- every battle magenta. Outside developer mode they are not offered -- and not
-- READ either, so a value left set by an older install cannot strand anyone.

do
  local offered = {}
  for key in pairs(defaults) do offered[key] = true end
  check(offered.enabled, "BACKDROPS is offered to everyone")
  check(offered.pic_paper, "and so is MON PAPER")
  check(not offered.diagnostic, "DIAGNOSTIC is not offered outside dev mode")
  check(not offered.field_test, "nor is FIELD TEST")
end

do
  -- and in developer mode both come back, unchanged
  local devDefaults = {}
  local devMod = {
    path = root,
    developer = true,
    log = setmetatable({}, { __index = function() return function() end end }),
    options = {
      define = function(_, list)
        for _, o in ipairs(list) do devDefaults[o.key] = o.default end
      end,
      get = function(_, key) return devDefaults[key] end,
    },
    events = { on = function() end },
    exports = {},
    hooks = { wrap = function() end },
  }
  assert(loadfile(root .. "/main.lua"))(devMod)
  check(devDefaults.diagnostic ~= nil, "developer mode offers DIAGNOSTIC")
  check(devDefaults.field_test ~= nil, "and FIELD TEST")
  check(devDefaults.field_test == false, "with the magenta field off to start")
end

do
  -- An Unown O is a ring, and the hole is the letter.  It is the highest
  -- enclosure in the whole Crystal sprite pack at 0.282, which is why the line
  -- is at 0.35 and not at 0.20.
  local UNOWN_O = newPic({
    "..######..",
    ".########.",
    "###....###",
    "###....###",
    "###....###",
    "###....###",
    "###....###",
    "###....###",
    "###....###",
    ".########.",
  })
  eq(#drawWith(UNOWN_O), 0, "art with an honest hole in it gets no paper")
end

do
  -- An irregular silhouette is not a damaged one.
  --
  -- This is the white box in the report, and it is the second half of it: a
  -- Crystal Koffing's frames are solid, and the three of nine that put its gas
  -- plume out have a bounding box mostly full of the space around the plume.
  -- Under "how much of the box is not ink" those three frames scored 0.51 and
  -- the other six 0.26, so a healthy sprite crossed the line three times per
  -- animation cycle and the paper blinked on and off behind it.
  local fills = drawWith(PLUME)
  eq(#fills, 0, "an awkward shape with no hole in it gets no paper")
end

do
  -- And the damage itself, in a shape with nothing else odd about it.
  local fills = drawWith(WINDOW)
  eq(#fills, 1, "a body with a window eaten through it still gets paper")
end

-- ------------------------------------------------- the readback's own scale
--
-- love.graphics.newCanvas(w, h) takes the window's DPI SCALE unless it is told
-- not to.  On the phone this was photographed on that is 3, so a 56x56 request
-- is a 168x168 canvas, the pic lands in it three times the size, and the
-- readback is 168x168.  Reading the pic's own 56x56 out of that is the pic's
-- top-left EIGHTEEN pixels, magnified -- a corner, which has few enough
-- colours to look like four-shade art and is empty enough to look eaten.  The
-- paper then went down in a box measured off that corner: on the enemy side,
-- 14x24 hard against the right edge of the pic, which is what the screenshot
-- shows.  At scale 1 none of it happens, which is why it shipped twice.

do
  -- A FRESH pic for each of these: the measurement is cached per image, and
  -- reusing the one measured at DPI 1 would hide the whole thing.
  dpiScale = 3
  local fills = drawWith(newPic(HOLLOW_ROWS))
  eq(#fills, 1, "at DPI 3 the hollowed pic is still measured as hollowed")
  local r = fills[1]
  if r then
    eq(r.x, 8, "and the paper starts where it does at DPI 1")
    eq(r.y, 40, "on both axes")
    eq(r.w, 20, "at the same width")
    eq(r.h, 20, "and the same height")
  end
end

do
  -- A host that takes the size and ignores the dpiscale setting is measured
  -- correctly anyway, because the measurement reads what came back rather than
  -- what it asked for.
  ignorePin = true
  local fills = drawWith(newPic(HOLLOW_ROWS))
  eq(#fills, 1, "a host that ignores the pin still gets a measurement")
  local r = fills[1]
  if r then
    eq(r.w, 20, "of the same width as at DPI 1")
    eq(r.h, 20, "and the same height")
  end
end

do
  -- The solid pic stays solid at 3 as well: a scaled readback must not turn
  -- an undamaged mon into a corner that looks eaten.
  eq(#drawWith(newPic(SOLID_ROWS)), 0, "and a solid pic still gets none at DPI 3")
  eq(#drawWith(newPic(PLUME_ROWS)), 0, "nor does an awkward one")
  ignorePin = false
  dpiScale = 1
end

print(("%d/%d checks passed  (Gen1Arena paper)")
  :format(passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
