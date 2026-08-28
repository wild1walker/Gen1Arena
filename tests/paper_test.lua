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
local HOLLOW = newPic({
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
})

-- The same silhouette with its body intact: nothing was lost, so nothing is
-- owed back.
local SOLID = newPic({
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
})

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

local function newImageData(px, w, h)
  return {
    getPixel = function(_, x, y)
      local p = px[y + 1] and px[y + 1][x + 1]
      if not p then return 0, 0, 0, 0 end
      return p[1], p[2], p[3], p[4]
    end,
  }
end

_G.love = {
  graphics = {
    newImage = function(path) return newPic({ "w" }) end,
    newCanvas = function(w, h)
      local c = { w = w, h = h, px = {}, __canvas = true }
      function c:newImageData() return newImageData(self.px, self.w, self.h) end
      return c
    end,
    getCanvas = function() return currentCanvas end,
    setCanvas = function(c) currentCanvas = c end,
    clear = function() end,
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
        currentCanvas.px = img.px
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
  log = setmetatable({}, { __index = function() return function() end end }),
  options = {
    define = function(_, list)
      for _, o in ipairs(list) do defaults[o.key] = o.default end
    end,
    get = function(_, key) return defaults[key] end,
  },
  events = { on = function(_, name, fn) defaults["@" .. name] = fn end },
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
  -- the field fill the mod substitutes its backdrop for
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  self:drawBattlerPic(self.player, 8, 40, 2)
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

print(("%d/%d checks passed  (Gen1Arena paper)")
  :format(passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
