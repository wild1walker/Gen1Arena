-- TIME OF DAY: a Gold backdrop after sunset is the backdrop as Gold paints the
-- world at night.
--
-- "Gen1arena on gen2 lacks night version for backgrounds, when playing after
-- sunset."  No night art was drawn for this.  The cart already says what
-- night does to colour -- its eight background palettes, once for DAY and
-- once for NITE -- so the backdrop goes through the transform fitted to those
-- pairs.  These cases are about the fit (does it reproduce the cart's own
-- night from the cart's own day?) and about WHERE it applies, which is the
-- half a player notices when it is wrong: a night-blue gym is a bug.
--
-- The palettes below are pokecrystal's gfx/tilesets/bg_tiles.pal, 5-bit
-- channels times eight, in the order Palettes.bgSet hands them over.
--
-- Run:  luajit tests/arenadaytime_test.lua

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end
local function near(actual, expected, tolerance, description)
  local good = type(actual) == "number"
    and math.abs(actual - expected) <= tolerance
  if not good then
    description = ("%s (got %s, wanted %s +/- %s)")
      :format(description, tostring(actual), tostring(expected),
              tostring(tolerance))
  end
  ok(good, description)
end

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

-- ------------------------------------------------------------- the palettes

local function set(rows)
  local out = {}
  for slot, row in ipairs(rows) do
    out[slot] = {}
    for i = 1, 4 do
      local c = row[i]
      out[slot][i] = { c[1] * 8, c[2] * 8, c[3] * 8 }
    end
  end
  return out
end

local DAY = set({
  { { 27, 31, 27 }, { 21, 21, 21 }, { 13, 13, 13 }, { 7, 7, 7 } },
  { { 27, 31, 27 }, { 31, 19, 24 }, { 30, 10, 6 }, { 7, 7, 7 } },
  { { 22, 31, 10 }, { 12, 25, 1 }, { 5, 14, 0 }, { 7, 7, 7 } },
  { { 31, 31, 31 }, { 8, 12, 31 }, { 1, 4, 31 }, { 7, 7, 7 } },
  { { 27, 31, 27 }, { 31, 31, 7 }, { 31, 16, 1 }, { 7, 7, 7 } },
  { { 27, 31, 27 }, { 24, 18, 7 }, { 20, 15, 3 }, { 7, 7, 7 } },
  { { 27, 31, 27 }, { 15, 31, 31 }, { 5, 17, 31 }, { 7, 7, 7 } },
  { { 31, 31, 16 }, { 31, 31, 16 }, { 14, 9, 0 }, { 0, 0, 0 } },
})
local NITE = set({
  { { 15, 14, 24 }, { 11, 11, 19 }, { 7, 7, 12 }, { 0, 0, 0 } },
  { { 15, 14, 24 }, { 14, 7, 17 }, { 13, 0, 8 }, { 0, 0, 0 } },
  { { 15, 14, 24 }, { 8, 13, 19 }, { 0, 11, 13 }, { 0, 0, 0 } },
  { { 15, 14, 24 }, { 5, 5, 17 }, { 3, 3, 10 }, { 0, 0, 0 } },
  { { 30, 30, 11 }, { 16, 14, 18 }, { 16, 14, 10 }, { 0, 0, 0 } },
  { { 15, 14, 24 }, { 12, 9, 15 }, { 8, 4, 5 }, { 0, 0, 0 } },
  { { 15, 14, 24 }, { 13, 12, 23 }, { 11, 9, 20 }, { 0, 0, 0 } },
  { { 31, 31, 16 }, { 31, 31, 16 }, { 14, 9, 0 }, { 0, 0, 0 } },
})
local MORN = set({
  { { 28, 31, 16 }, { 21, 21, 21 }, { 13, 13, 13 }, { 7, 7, 7 } },
  { { 28, 31, 16 }, { 31, 19, 24 }, { 30, 10, 6 }, { 7, 7, 7 } },
  { { 22, 31, 10 }, { 12, 25, 1 }, { 5, 14, 0 }, { 7, 7, 7 } },
  { { 31, 31, 31 }, { 8, 12, 31 }, { 1, 4, 31 }, { 7, 7, 7 } },
  { { 28, 31, 16 }, { 31, 31, 7 }, { 31, 16, 1 }, { 7, 7, 7 } },
  { { 28, 31, 16 }, { 24, 18, 7 }, { 20, 15, 3 }, { 7, 7, 7 } },
  { { 28, 31, 16 }, { 15, 31, 31 }, { 5, 17, 31 }, { 7, 7, 7 } },
  { { 31, 31, 16 }, { 31, 31, 16 }, { 14, 9, 0 }, { 0, 0, 0 } },
})
local SETS = { DAY = DAY, NITE = NITE, MORN = MORN }

-- ------------------------------------------------------------- the harness

_G.love = _G.love or { graphics = {} }
love.graphics.rectangle = love.graphics.rectangle or function() end
love.graphics.setColor = love.graphics.setColor or function() end
love.graphics.draw = love.graphics.draw or function() end
love.graphics.newImage = love.graphics.newImage or function()
  error("no images in this harness", 0)
end

local generation = 2
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  get = function() return generation == 2 and "gold" or "red" end,
  isYellow = function() return false end,
}

local bgSetCalls = 0
package.loaded["src.world.gen2.Palettes"] = {
  bgSet = function(data, def, daytime)
    bgSetCalls = bgSetCalls + 1
    if data == "broken" then error("no palettes", 0) end
    return SETS[daytime]
  end,
}

local mod = {
  id = "gen1_wild_ui_nightly",
  path = "modules/Gen1Arena",
  exports = {},
  stored = {},
  hooked = {},
  events_on = {},
}
mod.options = {
  define = function(_, rows) mod.rows = rows end,
  get = function(_, key) return mod.stored[key] end,
  set = function(_, key, value) mod.stored[key] = value end,
}
mod.log = setmetatable({}, { __index = function() return function() end end })
mod.hooks = { wrap = function(_, name, fn) mod.hooked[name] = fn end }
mod.events = { on = function(_, name, fn) mod.events_on[name] = fn end }
mod.assets = { path = function(_, p) return p end }
mod.storage = { writeBytes = function() return true end }
mod.content = {}

load_("main.lua", mod)

local fit = mod.exports.arenaFitDaytime
local tintFor = mod.exports.arenaDaytimeTint
local apply = mod.exports.arenaApplyTransform
local FALLBACK = mod.exports.arenaDaytimeFallback

-- ------------------------------------------------------------- the fit

do
  io.write("the fit reproduces the cart's own night from its own day\n")
  local tf = fit(DAY, NITE, "NITE")
  ok(tf ~= nil, "a transform is fitted")
  -- Every DAY colour, put through it, against the NITE colour the cart has in
  -- the same slot -- the lit window and the text palette excepted, which the
  -- fit leaves out on purpose.
  local sum, n = 0, 0
  for slot = 1, 7 do
    for i = 1, 4 do
      local d, o = DAY[slot][i], NITE[slot][i]
      if not (slot == 5 and i == 1) then
        local r, g, b = apply(tf, d[1] / 255, d[2] / 255, d[3] / 255)
        for k, v in ipairs({ r, g, b }) do
          local err = (v - o[k] / 255) * 31
          sum, n = sum + err * err, n + 1
        end
      end
    end
  end
  local rms = math.sqrt(sum / n)
  ok(rms < 3, ("within 3 of 31 on average across the pairs (rms %.2f)")
       :format(rms))

  -- The sky.  Day's palest colour is 27,31,27; the cart's night is 15,14,24.
  local r, g, b = apply(tf, 27 * 8 / 255, 31 * 8 / 255, 27 * 8 / 255)
  ok(b > r and b > g, "the palest day colour comes out BLUE at night, which "
     .. "is what makes it Gold's night rather than a dimmer day")
  ok(r < 0.7 and g < 0.7, "and darker")

  -- And the fallback is the same fit, written down.
  for _, row in ipairs({ "r", "g", "b" }) do
    for k = 1, 3 do
      near(tf[row][k], FALLBACK.NITE[row][k], 0.01,
           ("the fallback's %s row matches the fit (%d)"):format(row, k))
    end
  end
  for k = 1, 3 do
    near(tf.bias[k], FALLBACK.NITE.bias[k], 0.01, "and its offset " .. k)
  end
end

do
  io.write("the morning is a warmer day\n")
  local tf = fit(DAY, MORN, "MORN")
  ok(tf ~= nil, "a morning transform is fitted")
  local r, g, b = apply(tf, 27 * 8 / 255, 31 * 8 / 255, 27 * 8 / 255)
  ok(r > b, "day's palest colour leans warm in the morning")
  local r2, g2, b2 = apply(tf, 12 * 8 / 255, 25 * 8 / 255, 1 * 8 / 255)
  near(g2, 25 * 8 / 255, 0.02, "and the grass is the grass")
end

do
  io.write("nothing to fit is no transform, not a guess\n")
  eq(fit(nil, NITE, "NITE"), nil, "no day set")
  eq(fit(DAY, {}, "NITE"), nil, "an empty night set")
  local flat = set({
    { { 10, 10, 10 }, { 10, 10, 10 }, { 10, 10, 10 }, { 10, 10, 10 } },
    { { 10, 10, 10 }, { 10, 10, 10 }, { 10, 10, 10 }, { 10, 10, 10 } },
    { { 10, 10, 10 }, { 10, 10, 10 }, { 10, 10, 10 }, { 10, 10, 10 } },
  })
  eq(fit(flat, flat, "MORN"), nil,
     "a set whose colours are all one leaves the equations singular")
end

-- ------------------------------------------------------------- where

local function battleAt(t)
  local world = {
    daytime = t.daytime,
    palettes = t.palettes == nil and "live" or t.palettes,
    map = { def = { environment = t.environment or "ROUTE", group = t.group } },
  }
  return { game = { world = world } }
end

do
  io.write("outdoors after sunset, and nowhere else\n")
  ok(tintFor(battleAt({ daytime = "NITE" }), "field"),
     "a route at night is tinted")
  ok(tintFor(battleAt({ daytime = "NITE", environment = "TOWN" }), "town"),
     "and a town")
  ok(tintFor(battleAt({ daytime = "MORN" }), "field"), "and a morning route")
  eq(tintFor(battleAt({ daytime = "DAY" }), "field"), nil,
     "the day is the picture as it was drawn")
  ok(tintFor(battleAt({ daytime = "NITE", environment = "CAVE" }), "forest"),
     "Ilex Forest, which the cart pins to night, takes it")
  eq(tintFor(battleAt({ daytime = "NITE", environment = "CAVE" }), "cave"),
     nil, "a cave the cart pins to night does not: a cave scene is a cave")
  eq(tintFor(battleAt({ daytime = "NITE" }), "gym"), nil,
     "nor does a gym -- and a building's header pins DAY anyway")
  eq(tintFor(battleAt({ daytime = "NITE" }), "indoor"), nil, "nor a room")
  eq(tintFor(battleAt({ daytime = "DARK" }), "field"), nil,
     "DARK is a cave before FLASH, and is left alone")
  eq(tintFor(battleAt({ daytime = "NITE" }), nil), nil,
     "a battle with no place has nothing to tint")

  mod.stored.daytime = false
  eq(tintFor(battleAt({ daytime = "NITE" }), "field"), nil,
     "TIME OF DAY off is the day picture, always")
  mod.stored.daytime = nil

end

do
  io.write("fitted once per place and period, from the live palettes\n")
  local before = bgSetCalls
  tintFor(battleAt({ daytime = "NITE", group = 99 }), "field")
  local after = bgSetCalls
  eq(after - before, 2, "the first night on a map reads the DAY and NITE sets")
  tintFor(battleAt({ daytime = "NITE", group = 99 }), "field")
  eq(bgSetCalls, after, "and the second reads nothing")

  local broken = tintFor(battleAt({ daytime = "NITE", group = 98,
                                    palettes = "broken" }), "field")
  ok(broken == FALLBACK.NITE,
     "an engine whose palettes cannot be read gets the cart's numbers, "
     .. "written down")
end

do
  io.write("the row\n")
  local found
  for _, row in ipairs(mod.rows or {}) do
    if row.key == "daytime" then found = row end
  end
  ok(found, "TIME OF DAY is a row on Gold")
  eq(found and found.default, true, "and defaults on")
end

io.write(("arena daytime: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
