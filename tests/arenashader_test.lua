-- The backdrop is a PHOTOGRAPH, and a photograph must not go through the
-- shade remap.
--
-- Reported three times as "the battle is all greyscale", and the screenshot
-- said it in one line: every pixel of the game screen was one of three DMG
-- shades, and the ONE thing still in colour was the EXP bar -- which is the
-- one thing that calls `love.graphics.setShader()` before it paints
-- (Gen1BattleUI xpbar.lua: "exempt from the palette pass").
--
-- Gen1Arena's paints are substituted INTO the cart's own draw, from a shim on
-- `love.graphics.rectangle`, so whatever shader the caller had bound is still
-- bound when they run.  For a flat fill that changes nothing.  For a FireRed
-- terrain scene it is the whole picture: PaletteFX's shader answers every
-- pixel with one of four palette entries chosen off its RED channel, so the
-- photograph comes back as four greys and the mod reads as if it never ran.
--
-- Two things have to hold, and only one of them is obvious:
--
--   * the shader is DOWN while the art is drawn;
--   * it is back UP afterwards, exactly as it was -- this runs in the middle
--     of the cart's draw, and the shade remap after it is the cart's.  A
--     guard that cleared and left cleared would trade a greyscale backdrop
--     for an uncolourised battle.
--
-- Run:  luajit tests/arenashader_test.lua

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

local function slurp(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local body = handle:read("*a")
  handle:close()
  return body
end
local function load_(path, ...)
  return assert(load(slurp(path), "@" .. path))(...)
end

-- ------------------------------------------------------------- the harness

local bound = nil
_G.love = _G.love or { graphics = {} }
love.graphics = love.graphics or {}
love.graphics.rectangle = function() end
love.graphics.setColor = function() end
love.graphics.getColor = function() return 1, 1, 1, 1 end
love.graphics.getCanvas = function() return nil end
love.graphics.setCanvas = function() end
love.graphics.clear = function() end
love.graphics.draw = function() end
love.graphics.newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end
love.graphics.getShader = function() return bound end
love.graphics.setShader = function(sh) bound = sh or nil end

local mod = { id = "gen1_wild_ui", exports = {}, stored = {}, hooked = {} }
mod.options = { define = function() end,
                get = function(_, key) return mod.stored[key] end,
                set = function(_, key, value) mod.stored[key] = value end }
mod.log = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  mod.log[level] = function() end
end
mod.hooks = { wrap = function(_, name, fn) mod.hooked[name] = fn end }
mod.events = { on = function() end }
mod.assets = { path = function(_, p) return p end }
mod.storage = { writeBytes = function() return true end }
mod.content = {}

load_("main.lua", mod)

local paint = mod.exports.paintsWithoutShader
ok(type(paint) == "function", "the mod publishes the guard its art paints use")

-- ------------------------------------------------------ down, then back up

do
  io.write("the art is drawn with no shader, and the caller's is handed back\n")
  local SHADER = { "the cart's shade remap" }
  bound = SHADER
  local sawDuring = "not run"
  paint(function() sawDuring = love.graphics.getShader() end)
  eq(sawDuring, nil, "nothing is bound while the picture is drawn")
  eq(bound, SHADER, "and the caller's shader is exactly what it was after")
end

do
  io.write("with nothing bound it touches nothing\n")
  bound = nil
  local calls = 0
  local realSet = love.graphics.setShader
  love.graphics.setShader = function(sh) calls = calls + 1 realSet(sh) end
  paint(function() end)
  love.graphics.setShader = realSet
  eq(calls, 0, "no setShader at all -- there was nothing to put down")
  eq(bound, nil, "and nothing is bound after")
end

do
  io.write("and a draw that raises still hands the shader back\n")
  -- The paints are inside the cart's own draw.  Leaving a battle running with
  -- no shade remap because one picture failed to load would be a worse bug
  -- than the one this fixes.
  local SHADER = { "the cart's shade remap" }
  bound = SHADER
  local raised = false
  local okCall, err = pcall(paint, function() error("no such backdrop", 0) end)
  raised = not okCall
  ok(raised, "the error is not swallowed")
  eq(tostring(err), "no such backdrop", "and it is the caller's own error")
  eq(bound, SHADER, "with the shader put back on the way out")
end

-- ------------------------------- and BOTH art paints actually go through it
--
-- Read out of the source rather than restated, because the bug was never in
-- the guard -- it was in a draw that did not use one.  A picture painted
-- outside this is the whole of the report.

do
  io.write("every full-colour paint in the file is inside the guard\n")
  local src = slurp("main.lua")

  local field = src:match("local function paintField%(%).-\nend")
  ok(field and field:find("withoutShader", 1, true) ~= nil,
    "the field paint -- the backdrop that replaces the battle's white")
  ok(field and field:find("drawCover", 1, true) ~= nil,
    "...and it is drawCover that it wraps")

  -- The bars around a wide battle carry the same picture's edge.
  local bleed = src:match("\n(  local g = love%.graphics\n  g%.setColor%(1, 1, 1, 1%)\n.-\n  end%)\n)")
  ok(bleed ~= nil, "the bleed into the letterbox bars is found")
  ok(bleed and bleed:find("withoutShader", 1, true) ~= nil,
    "and it is inside the guard too -- bars in four greys beside a field in "
    .. "colour would be worse than either")
end

io.write(("\narenashader: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
