-- BACKDROPS on FireRed, LeafGreen and Emerald: gen3.lua.
--
-- The art was drawn for FireRed's battle field, so on a GBA boot it goes back
-- there 1:1 through `BattleBg.draw`.  What is asserted:
--
--   * WHICH picture: the cart's own terrain key, narrowed by the map -- a
--     forest, a town and its roof colours, an ice cave, a volcano, the Tower,
--     a ship, Emerald's desert -- and the kind of battle; and NO picture,
--     which is the cart's own background, for a terrain the pack has none for
--     (underwater, Emerald's own scenes).
--   * WHERE: the middle 240 columns of a wide file, the picture's ground on
--     the field's bottom edge, the missing top rows mirrored upward, the band
--     under the field -- never scaled.
--   * and NOT the cart's platform layers: they are opaque tiles of the
--     cart's own ground, not cut-out ovals.
--
-- Run:  luajit tests/arenagen3_test.lua

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

local function readFile(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

local function load_(path, ...)
  local source = assert(readFile(path), path .. " is missing")
  return assert(load(source, "@" .. path))(...)
end

-- ------------------------------------------------------------- graphics

-- A PNG's size is in its header; the pixels are stood in for: a 304-wide
-- file has its flat 40-row band from row 104 (as every wide band file does),
-- and anything else is picture to the bottom.
local function pngSize(path)
  local body = readFile(path)
  if not body or #body < 24 then return nil end
  local function u32(at)
    local a, b, c, d = body:byte(at, at + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

local draws, quads = {}, 0
local function newImage(w, h, path)
  return {
    path = path,
    getDimensions = function() return w, h end,
    getWidth = function() return w end,
    getHeight = function() return h end,
    setFilter = function() end,
  }
end
love = {
  image = {
    newImageData = function(path)
      local w, h = pngSize(path)
      if not w then error("no such file: " .. tostring(path)) end
      return {
        path = path,
        getDimensions = function() return w, h end,
        getPixel = function(_, x, y)
          if w == 304 and y >= 104 then return 0.2, 0.3, 0.4, 1 end
          return (x % 7) / 7, (y % 5) / 5, 0.5, 1
        end,
      }
    end,
  },
  graphics = {
    newImage = function(source)
      if type(source) == "table" then
        local w, h = source:getDimensions()
        return newImage(w, h, source.path)
      end
      local w, h = pngSize(source)
      if not w then error("no such file") end
      return newImage(w, h, source)
    end,
    newQuad = function(x, y, w, h, iw, ih)
      quads = quads + 1
      return { x = x, y = y, w = w, h = h, iw = iw, ih = ih }
    end,
    draw = function(image, a, b, c, r, sx, sy)
      if type(a) == "table" and a.w then
        draws[#draws + 1] = { image = image, quad = a, x = b, y = c, sx = sx or 1,
                              sy = sy or 1 }
      else
        draws[#draws + 1] = { image = image, x = a, y = b }
      end
    end,
    setColor = function() end,
  },
}

-- ------------------------------------------------------------- the cart

local Map = { current = "FR_ROUTE_1", def = { mapType = 3 } }
function Map.currentDef() return Map.def end
local profile = "frlg"
local battle = { wild = true }
local baseCalls = 0
local BattleBg = {}
function BattleBg.sheetKey(id) return id end   -- ids here are the keys
function BattleBg.draw() baseCalls = baseCalls + 1; return "the cart's" end
local plates = {}
local BattleChrome = {}
function BattleChrome.terrain(key)
  if key == "underwater" then return nil end
  plates[key] = plates[key] or {
    enemyPlat = { plate = "enemy " .. key },
    playerPlat = { plate = "player " .. key },
  }
  return plates[key]
end
package.loaded["src.core.game3.map"] = Map
package.loaded["src.core.game3.profile"] = { family = function() return profile end }
package.loaded["src.core.game3.battle"] = { getState = function() return battle end }
package.loaded["src.core.game3.battle.bg"] = BattleBg
package.loaded["src.ui.game3.battle_chrome"] = BattleChrome

local function armMod()
  local self = { stored = {}, schema = {}, exports = {},
                 path = "." }
  self.options = {
    define = function(_, rows) for _, r in ipairs(rows) do self.schema[r.key] = r end end,
    get = function(_, key)
      local v = self.stored[key]
      if v == nil and self.schema[key] then return self.schema[key].default end
      return v
    end,
  }
  -- The engine's mod log has info, warn and error and nothing else
  -- (src/mods/Loader.lua); any other level is nil, as it is through the
  -- bundle's facade.
  self.logged = {}
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error" }) do
    self.log[level] = function(_, fmt, ...)
      self.logged[#self.logged + 1] = level .. ": "
        .. (select("#", ...) > 0 and fmt:format(...) or fmt)
    end
  end
  return self
end

local mod = armMod()
load_("gen3.lua")(mod)
local choose = mod.exports.choose

local function picked(key, mapId, mapType, opts)
  opts = opts or {}
  Map.current = mapId
  Map.def = { mapType = mapType }
  profile = opts.family or "frlg"
  battle = { wild = not opts.trainer }
  local _, name = choose(key)
  return name
end

-- ------------------------------------------------------------- which

do
  io.write("which picture, on FireRed\n")
  eq(picked("grass", "FR_ROUTE_1", 3), "field", "grass on a route is the field")
  eq(picked("grass", "FR_ROUTE_1", 3, { trainer = true }), "trainer_field",
     "and a trainer there gets the trainer's field")
  eq(picked("long_grass", "FR_VIRIDIAN_FOREST", 3), "forest",
     "the grass of Viridian Forest is the forest")
  eq(picked("grass", "FR_CERULEAN_CITY", 2), "cerulean/town",
     "grass in Cerulean is Cerulean, in its own roof colours")
  eq(picked("grass", "FR_PALLET_TOWN", 1, { trainer = true }), "pallet/town",
     "a trainer in a town with no trainer scene gets the town")
  eq(picked("gym", "FR_CERULEAN_CITY_GYM", 8, { trainer = true }),
     "cerulean/trainer_gym", "a junior trainer in Misty's gym gets her gym's")
  eq(picked("leader", "FR_CERULEAN_CITY_GYM", 8, { trainer = true }),
     "cerulean/gym", "and Misty gets her gym in its colours")
  eq(picked("water", "FR_ROUTE_19", 3), "sea", "the cart's water is the sea")
  eq(picked("pond", "FR_ROUTE_6", 3), "lake", "its pond is the lake")
  eq(picked("water", "FR_SEAFOAM_ISLANDS_B3F", 4), "water_cave",
     "water underground is neither: Seafoam has no sky")
  eq(picked("cave", "FR_MT_MOON_1F", 4), "cave", "a cave is the cave")
  eq(picked("cave", "FR_ICEFALL_CAVE_FRONT", 4), "lorelei",
     "Icefall Cave is the ice cave")
  eq(picked("cave", "FR_MT_EMBER_RUBY_PATH_B1F", 4), "lance",
     "Mt. Ember's insides are the volcano")
  eq(picked("mountain", "FR_FIVE_ISLAND_ROCKY_SHORE", 3), "plateau",
     "the cart's mountain is the rocky hillside")
  eq(picked("building", "FR_POKEMON_TOWER_3F", 8), "tower",
     "the Pokemon Tower is the Tower")
  -- FireRed's own spelling: MAP_SSANNE_1F_CORRIDOR.
  eq(picked("building", "FR_SSANNE_1F_CORRIDOR", 8, { trainer = true }),
     "ship", "the S.S. Anne is the ship, trainers and all")
  eq(picked("building", "FR_SILPH_CO_5F", 8, { trainer = true }),
     "trainer_indoor", "any other room's trainer gets the trainers' room")
  eq(picked("building", "FR_SILPH_CO_5F", 8), "indoor", "and a wild one the room")
  eq(picked("indoor_2", "FR_ROCKET_HIDEOUT_B1F", 8), "indoor",
     "FireRed's two indoor scenes are rooms")
  eq(picked("lorelei", "FR_POKEMON_LEAGUE_LORELEIS_ROOM", 8, { trainer = true }),
     "lorelei", "Lorelei's room is the scene drawn for it")
  eq(picked("champion", "FR_POKEMON_LEAGUE_CHAMPIONS_ROOM", 8, { trainer = true }),
     "champion", "and so is the Champion's")
  eq(picked("grass", "FR_SAFARI_ZONE_CENTER", 3), "safari",
     "the Safari Zone's grass is the safari")
  eq(picked("water", "FR_SAFARI_ZONE_CENTER", 3), "sea",
     "but its water is still water")
  eq(picked("underwater", "FR_ROUTE_19", 5), nil,
     "underwater: no picture, the cart's own background")
  eq(picked("link", "FR_UNION_ROOM", 8), nil, "and nor for a link battle")
end

do
  io.write("which picture, on Emerald\n")
  local em = { family = "rse" }
  eq(picked("sand", "EM_ROUTE111", 3, em), "agatha",
     "Route 111's sand is the desert")
  eq(picked("sand", "EM_ROUTE113", 3, em), nil,
     "Route 113's ash is sand to the cart, and keeps the cart's own ash")
  eq(picked("grass", "EM_ROUTE111", 3, em), "field",
     "and its grass is not")
  eq(picked("sand", "EM_ROUTE109", 3, em), "port", "a beach is the beach")
  eq(picked("long_grass", "EM_PETALBURG_WOODS", 3, em), "forest",
     "Petalburg Woods is the forest")
  eq(picked("cave", "EM_SHOAL_CAVE_LOW_TIDE_ICE_ROOM", 4, em), "lorelei",
     "Shoal Cave is the ice cave")
  eq(picked("cave", "EM_MAGMA_HIDEOUT_1F", 4, em), "lance",
     "the Magma Hideout is the volcano")
  eq(picked("building", "EM_MT_PYRE_1F", 8, em), "tower",
     "Mt. Pyre's halls are the Tower")
  eq(picked("grass", "EM_LITTLEROOT_TOWN", 1, em), "town",
     "a Hoenn town is a town, in no Kanto colours")
  eq(picked("champion", "EM_EVER_GRANDE_CITY_CHAMPIONS_ROOM", 8,
            { family = "rse", trainer = true }), nil,
     "Wallace's room is under water: the cart's own scene")
  eq(picked("sidney", "EM_EVER_GRANDE_CITY_SIDNEYS_ROOM", 8,
            { family = "rse", trainer = true }), nil,
     "and the Hoenn Elite Four keep theirs")
  eq(picked("groudon", "EM_CAVE_OF_ORIGIN_B1F", 4, em), nil,
     "as do the legendary scenes")
end

-- ------------------------------------------------------------- the paint

local function drawAt(key, mapId, mapType, eOx, pOx)
  draws = {}
  baseCalls = 0
  Map.current, Map.def, profile, battle = mapId, { mapType = mapType }, "frlg",
    { wild = true }
  return BattleBg.draw(key, eOx or 0, pOx or 0, 0)
end

do
  io.write("the paint: 1:1, on its ground\n")
  local result = drawAt("cave", "FR_MT_MOON_1F", 4)
  eq(result, true, "a pictured terrain answers as the cart's draw does")
  eq(baseCalls, 0, "and the cart's own background is not drawn under it")
  local body, pad, under = draws[1], draws[2], draws[3]
  ok(body and body.quad and body.image.path:find("wide/cave.png", 1, true),
     "the wide cave file")
  eq(body.quad.x, 32, "its middle 240 columns: 32 in, past the mirror padding")
  eq(body.quad.w, 240, "240 wide")
  eq(body.quad.h, 104, "all 104 picture rows, the band left out")
  eq(body.y, 8, "with its ground on the field's bottom edge: 112 - 104")
  eq(body.sx, 1, "never scaled across")
  eq(body.sy, 1, "or down")
  eq(pad.quad.y, 0, "the top 8 rows are the picture's own top")
  eq(pad.quad.h, 8, "eight of them")
  eq(pad.sy, -1, "mirrored upward")
  eq(pad.y, 8, "from the picture's top edge")
  eq(under.y, 112, "under the field, behind the box")
  eq(under.quad.y, 104, "the band")
  eq(under.sy, 48, "down to the bottom of the screen")

  eq(#draws, 3, "and nothing else: the cart's platform layers are opaque "
     .. "tiles of its own ground, not ovals, and stay off the picture")

  drawAt("grass", "FR_ROUTE_1", 3)
  eq(draws[1].image.path:match("wide/(.*)$"), "field.png", "the field")
  eq(draws[1].quad.x, 8, "a 256-wide file gives its middle 240 from 8")
  eq(draws[1].quad.h, 112, "a file with no band has 112 rows to give")
  eq(draws[1].y, 0, "and fills the field to the top")
  ok(draws[2].quad == nil or draws[2].sy ~= -1, "with nothing to mirror")

  drawAt("grass", "FR_ROUTE_1", 3, 37, -21)
  for _, d in ipairs(draws) do
    ok(not d.image.plate, "nor during the intro slide")
  end

  -- Every frame of every battle asks: once the answer is in hand, a frame
  -- that changes nothing requires nothing and decides nothing again.
  local asked = 0
  local realRequire = require
  require = function(name) asked = asked + 1; return realRequire(name) end
  for _ = 1, 50 do drawAt("grass", "FR_ROUTE_1", 3) end
  require = realRequire
  eq(asked, 0, "fifty frames of one battle: no module looked up again")
  drawAt("grass", "FR_VIRIDIAN_FOREST", 3)
  eq(draws[1].image.path:match("wide/(.*)$"), "forest.png",
     "and a new map is a new answer")

  eq(drawAt("underwater", "FR_ROUTE_19", 5), "the cart's",
     "no picture: the cart's own draw, and its own answer")

  eq(baseCalls, 1, "called once")

  -- A failure inside the paint is the cart's background, said once, and
  -- never an error out of the cart's draw.
  local realQuad = love.graphics.newQuad
  love.graphics.newQuad = function() error("out of quads") end
  local broken = armMod()
  local cartDraw = BattleBg.draw
  BattleBg.draw = function() baseCalls = baseCalls + 1; return "the cart's" end
  load_("gen3.lua")(broken)
  local okDraw, answer = pcall(BattleBg.draw, "lake", 0, 0, 0)
  Map.current, Map.def = "FR_ROUTE_6", { mapType = 3 }
  okDraw, answer = pcall(BattleBg.draw, "pond", 0, 0, 0)
  eq(okDraw, true, "a paint that fails does not fail the cart's draw")
  eq(answer, "the cart's", "the cart draws its own instead")
  pcall(BattleBg.draw, "pond", 0, 0, 0)
  local warns = 0
  for _, line in ipairs(broken.logged) do
    if line:find("^warn") then warns = warns + 1 end
  end
  eq(warns, 1, "and says so once, not once a frame")
  love.graphics.newQuad = realQuad
  BattleBg.draw = cartDraw

  mod.stored.enabled = false
  eq(drawAt("cave", "FR_MT_MOON_1F", 4), "the cart's",
     "BACKDROPS off: the untouched game")
  mod.stored.enabled = nil

  -- A pack missing a file falls through to the next candidate, then to the
  -- cart.
  local realNew = love.image.newImageData
  love.image.newImageData = function(path)
    if path:find("trainer_field", 1, true) then error("missing") end
    return realNew(path)
  end
  local realImage = love.graphics.newImage
  love.graphics.newImage = function(source)
    if type(source) == "string" and source:find("trainer_field", 1, true) then
      error("missing")
    end
    return realImage(source)
  end
  local fresh = armMod()
  BattleBg.draw = function() baseCalls = baseCalls + 1; return "the cart's" end
  load_("gen3.lua")(fresh)
  Map.current, Map.def, profile, battle = "FR_ROUTE_1", { mapType = 3 }, "frlg",
    { wild = false }
  local _, name = fresh.exports.choose("grass")
  eq(name, "field", "a missing trainer scene falls back to the place")
  love.image.newImageData, love.graphics.newImage = realNew, realImage
end

-- ------------------------------------------- the standalone mod's door

do
  io.write("main.lua on a Gen 3 boot\n")
  -- Installed on its own, the mod always starts at main.lua.  On a GBA boot
  -- that has to hand over to gen3.lua BEFORE it requires anything: every
  -- module main.lua names is Red's or Gold's, and on Gen 3 a require of one is
  -- a line on the player's MODS error list.
  local asked = {}
  local realRequire = require
  require = function(name)
    asked[#asked + 1] = name
    return realRequire(name)
  end
  local standalone = armMod()
  standalone.generation = 3
  standalone.read = function(_, path) return readFile(path) end
  local before = BattleBg.draw
  load_("main.lua", standalone)
  require = realRequire
  ok(BattleBg.draw ~= before, "the GBA arm is installed")
  ok(standalone.schema.enabled ~= nil, "with its own row")
  for _, name in ipairs(asked) do
    ok(name:find("game3", 1, true) or name == "src.core.GameVersion",
       "and nothing but the GBA's modules is required: " .. name)
  end
  BattleBg.draw = before
end

io.write(("arena gen3: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
