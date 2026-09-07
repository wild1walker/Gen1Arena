-- Headless coverage of BACKDROPS' Gold selection (main.lua).
--
-- The drawing needs a window and cannot be tested here.  The SELECTION can,
-- and it is the whole of what is Gen 2-specific: a map header and a battle in,
-- one slot name out.  Everything below drives those pure functions.
--
-- The claim this file is really defending is that no new art was needed.  All
-- twenty backdrops in the pack are FireRed TERRAIN scenes; six of them are
-- named after Kanto bosses only because FireRed assigned them that way, and
-- three of those six (Giovanni's snowfield, Lorelei's ice cave, Agatha's
-- desert) belong to people who are not in Gold, Silver or Crystal at all.  So
-- the tests at the bottom check that every one of the twenty has a home here
-- and that nothing points at a file the package does not carry.
--
-- Run:  luajit tests/arenagen2_test.lua

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

_G.love = _G.love or { graphics = {} }
love.graphics.rectangle = love.graphics.rectangle or function() end
love.graphics.setColor = love.graphics.setColor or function() end
love.graphics.getCanvas = love.graphics.getCanvas or function() return nil end
love.graphics.setCanvas = love.graphics.setCanvas or function() end
love.graphics.clear = love.graphics.clear or function() end
love.graphics.draw = love.graphics.draw or function() end
love.graphics.newQuad = love.graphics.newQuad
  or function(x, y, w, h) return { x = x, y = y, w = w, h = h } end
love.graphics.newImage = love.graphics.newImage or function()
  error("no images in this harness", 0)
end

-- A Gen 2 boot, as far as the mod's own probe is concerned.
package.loaded["src.core.GameVersion"] = {
  generation = function() return 2 end,
  get = function() return "gold" end,
  isYellow = function() return false end,
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

local slotFor = mod.exports.gen2SlotFor
local kindSlot = mod.exports.gen2KindSlot
local TILESETS = mod.exports.gen2Tilesets
local ENVIRONMENTS = mod.exports.gen2Environments
local GROUP_VARIANT = mod.exports.gen2GroupVariant
local SLOT_FILE = mod.exports.gen2SlotFile
local BOSSES = mod.exports.gen2BossClass
local OCEAN = mod.exports.gen2Ocean
local MAP_SLOTS = mod.exports.gen2MapSlots

ok(type(slotFor) == "function", "the Gold place rule is exposed")
ok(type(kindSlot) == "function", "and the Gold kind rule")

-- ------------------------------------------------------------- the place

local function def(t)
  return t
end

do
  io.write("the place, from Gold's own map header\n")

  eq(slotFor(nil), nil, "no header is no slot")
  eq(slotFor(def({})), nil, "a header with neither field is no slot")

  eq(slotFor(def({ tileset = "TILESET_CAVE" })), "cave", "a cave is a cave")
  eq(slotFor(def({ tileset = "TILESET_FOREST" })), "forest",
     "Ilex Forest is a forest")
  eq(slotFor(def({ tileset = "TILESET_PORT" })), "port", "Olivine's port")
  eq(slotFor(def({ tileset = "TILESET_GAME_CORNER" })), "club",
     "the Game Corner takes the one crowded-room scene in the pack")
  -- The tower, and why it is NOT the `tower` slot here.
  --
  -- `tower.png` is the same 10 Indoors art as `indoor` with GRAYMON baked
  -- into it, and GRAYMON is Red's CEMETERY rule.  Gold has no CEMETERY, no
  -- GRAYMON, and no per-tower palette at all -- every INDOOR map shares one
  -- BG set -- so the plain room is the faithful answer and Lavender's
  -- grey-violet on a Johto pagoda is not.
  eq(slotFor(def({ tileset = "TILESET_TOWER" })), "indoor",
     "Sprout Tower and the Tin Tower take the PLAIN interior, not Lavender's "
     .. "mourning palette")
  eq(slotFor(def({ id = "BURNED_TOWER_B1F", tileset = "TILESET_TOWER" })),
     "cave", "...and the Burned Tower's basement is a collapsed pit")

  -- 3 Underwater was reached by one map before this; Johto has rather more
  -- water underground than Kanto does.
  for _, id in ipairs({ "TOHJO_FALLS", "SLOWPOKE_WELL_B1F", "UNION_CAVE_B2F",
                        "WHIRL_ISLAND_LUGIA_CHAMBER", "DRAGONS_DEN_B1F" }) do
    eq(slotFor(def({ id = id, tileset = "TILESET_CAVE" })), "water_cave",
       id .. " is water in a cave -- no sky, so neither the Sea nor the Lake")
  end

  eq(slotFor(def({ id = "RUINS_OF_ALPH_OUTSIDE",
                   tileset = "TILESET_RUINS_OF_ALPH" })), "field",
     "the Ruins' outside is a dig under open sky, not a chamber")

  -- A gym is a map, not a tileset: Gold has no GYM tileset at all, so a gym
  -- sits on whatever its town uses and has to be named.
  eq(slotFor(def({ id = "GOLDENROD_GYM", tileset = "TILESET_JOHTO_MODERN",
                   environment = "INDOOR" })), "gym",
     "Whitney's gym is a gym, not Goldenrod's tileset")
  eq(slotFor(def({ id = "BLACKTHORN_GYM_1F", tileset = "TILESET_CAVE" })),
     "gym", "and Clair's, whose two floors are named _1F and _2F")
  eq(slotFor(def({ id = "SEAFOAM_GYM", tileset = "TILESET_CAVE" })), "gym",
     "and Blaine's, which moved to the Seafoam Islands")
  eq(slotFor(def({ id = "FAST_SHIP_1F" })), "deck",
     "the S.S. Aqua's deck level is open air")
  eq(slotFor(def({ id = "FAST_SHIP_B1F" })), "ship",
     "...and her hold is not")
  eq(slotFor(def({ id = "SILVER_CAVE_OUTSIDE", tileset = "TILESET_CAVE" })),
     "plateau",
     "the mountainside outside Silver Cave is a crag, whatever its tileset "
     .. "says")

  -- The Ice Path is the case the whole re-deal exists for.
  eq(slotFor(def({ tileset = "TILESET_ICE_PATH" })), "ice_path",
     "the ICE PATH gets its own slot rather than the plain cave")
  eq(SLOT_FILE.ice_path, "lorelei",
     "...which is FireRed's 15 Snow Cave -- an ice cave, drawn for Lorelei, "
     .. "who is not in this game")

  -- Routes and towns share the three overworld tilesets, exactly as they
  -- share OVERWORLD on Red.  Red separates them with a map index; Gold's
  -- header says which it is.
  eq(slotFor(def({ tileset = "TILESET_JOHTO", environment = "ROUTE" })),
     "field", "Route 29 is a field")
  eq(slotFor(def({ tileset = "TILESET_JOHTO", environment = "TOWN" })),
     "town", "New Bark Town is a town, on the same tileset")
  eq(slotFor(def({ tileset = "TILESET_KANTO", environment = "TOWN" })),
     "town", "and so is Kanto's half")

  -- The fallback Red does not have.
  eq(slotFor(def({ tileset = "TILESET_SOMETHING_NEW", environment = "CAVE" })),
     "cave",
     "a tileset nobody mapped still lands right, because Gold's header says "
     .. "what kind of place it is -- Red has to guess this")
  eq(slotFor(def({ tileset = "TILESET_SOMETHING_NEW", environment = "INDOOR" })),
     "indoor", "...and a room is a room")
  eq(slotFor(def({ environment = "DUNGEON" })), "cave",
     "a header with no tileset at all still answers")
end

-- -------------------------------------------------------------- the kind

local function battle(t)
  t = t or {}
  local world = { [ "__gen1ArenaEncounter" ] = t.encounter }
  return {
    game = { world = world },
    battle = t.model or { wild = true },
  }
end

do
  io.write("the kind, from what the world was doing when it started\n")

  eq(kindSlot(battle()), "wild", "a plain encounter is wild")

  eq(kindSlot(battle({ encounter = { rolled = true } })), "wild",
     "a rolled one too")
  eq(kindSlot(battle({ encounter = { rolled = false } })), "static",
     "one the world did not roll -- a script's, a roamer's -- is static")
  eq(kindSlot(battle({ encounter = { fished = true, rolled = false } })),
     "fishing", "a fished one is fishing")
  eq(kindSlot(battle({ encounter = { surfing = true, rolled = true } })),
     "surf", "and one begun while surfing is surf")
  eq(kindSlot(battle({ encounter = { fished = true, surfing = true } })),
     "fishing", "fishing outranks surfing: you are casting, not swimming")

  local function trainer(class, encounter)
    return battle({ model = { trainer = { class = class } },
                    encounter = encounter })
  end

  eq(kindSlot(trainer("YOUNGSTER")), "trainer", "an ordinary trainer")
  eq(kindSlot(trainer("YOUNGSTER", { surfing = true })), "trainer_surf",
     "...and one fought from the water")
  eq(kindSlot(trainer("FALKNER")), "leader", "Falkner is a leader")
  eq(kindSlot(trainer("BLUE")), "leader",
     "and so is BLUE -- he has Viridian's gym in this game")
  eq(kindSlot(trainer("CHAMPION")), "lance",
     "the Champion is Lance, and keeps the scene drawn for Lance")
  eq(kindSlot(trainer("RED")), "red", "the fight on Mt Silver is its own")
end

-- ------------------------------------------------------------ the towns

do
  io.write("the town variant, keyed on the map group\n")

  -- Keyed on GROUP because that is what a roof colour is keyed on: Gold's
  -- RoofPals is indexed by map group, so every map in a group shares one roof
  -- pair, and a town variant IS a roof recolour.
  eq(GROUP_VARIANT[24], "new_bark", "group 24 is New Bark")
  eq(GROUP_VARIANT[11], "goldenrod", "group 11 is Goldenrod")
  eq(GROUP_VARIANT[7], "cerulean", "group 7 is Cerulean -- Kanto is in here")
  eq(GROUP_VARIANT[16], "indigo", "and group 16 is the Plateau")

  local count = 0
  for _ in pairs(GROUP_VARIANT) do count = count + 1 end
  eq(count, 21, "twenty-one towns across the two regions")

  -- The four groups that are routes and dungeons have no town to be the
  -- colour of, and must not claim one.
  for _, group in ipairs({ 9, 15, 19, 20 }) do
    eq(GROUP_VARIANT[group], nil,
       ("group %d has no town in it and takes no variant"):format(group))
  end
end

-- ------------------------------------------------------------- the water

do
  io.write("sea or pond\n")
  ok(OCEAN.LANDMARK_OLIVINE_CITY, "Olivine faces the open sea")
  ok(OCEAN.LANDMARK_ROUTE_41, "and the crossing to Cianwood is sea")
  ok(OCEAN.LANDMARK_CINNABAR_ISLAND, "Kanto's south coast is still sea")
  eq(OCEAN.LANDMARK_LAKE_OF_RAGE, nil, "the Lake of Rage is a lake")
  eq(OCEAN.LANDMARK_ROUTE_32, nil, "and Route 32's river is not the sea")
end

-- ------------------------------------------- every backdrop has a home

do
  io.write("all twenty scenes, and no dangling file\n")

  -- Every file the Gen 2 tables can ask for, actually on disk.
  local function exists(name)
    local f = io.open("assets/backdrops/og/" .. name
                      .. ".png", "r")
    if f then f:close() return true end
    return false
  end

  local asked = {}
  local function want(slot, why)
    local file = SLOT_FILE[slot] or slot
    asked[file] = true
    ok(exists(file), ("%s -> %s.png exists (%s)"):format(slot, file, why))
  end

  for _, slot in pairs(TILESETS) do want(slot, "a tileset names it") end
  for _, slot in pairs(MAP_SLOTS) do want(slot, "a map names it") end
  for _, slot in pairs(ENVIRONMENTS) do want(slot, "an environment names it") end
  for _, slot in pairs(BOSSES) do want(slot, "a boss names it") end
  want("sea", "open water")
  want("lake", "inland water")
  want("water_cave", "water underground")
  want("trainer", "a trainer")
  want("default", "the last resort")

  -- The three whose owners are not in this game are reached anyway, through
  -- the re-deal -- which is the point of the whole exercise.
  ok(asked.giovanni, "14 Snow is reached on Gold (RED, on Mt Silver)")
  ok(asked.lorelei, "15 Snow Cave is reached (KAREN, and the Ice Path)")
  ok(asked.agatha, "17 Desert is reached (KOGA)")
  ok(asked.bruno, "16 Snow Mountain is reached (BRUNO, in both games)")
  ok(asked.lance, "18 Volcano is reached (the Champion)")
  ok(asked.champion, "19 Space is reached (WILL)")

  -- The four the header alone could not reach, each of which left a finished
  -- backdrop with nothing pointing at it until MAP_SLOT_GEN2 landed.
  ok(asked.gym,
     "12 Gym is reached: Gold has no GYM tileset, so a gym trainer needs the "
     .. "map named")
  ok(asked.deck, "4 Sea's deck crop is reached (the S.S. Aqua's 1F)")
  ok(asked.ship, "10 Indoors' ship crop is reached (her cabins and hold)")
  ok(asked.plateau,
     "6 Craggy is reached (SILVER_CAVE_OUTSIDE -- the mountainside RED is "
     .. "at the top of)")

  -- And the one that genuinely has nowhere to go, stated rather than left to
  -- look like an oversight.
  eq(asked.museum, nil,
     "the museum crop is unreached on Gold -- there is no museum in this "
     .. "game -- but it is byte-identical to `indoor`, so no picture is lost")
  eq(asked.tower, nil,
     "and so is the GRAYMON'd tower, deliberately: it is Red's mourning "
     .. "palette, and the art under it is `indoor`, which Gold's towers get")
end

io.write(("arena gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
