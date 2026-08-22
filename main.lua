-- Gen1Arena -- 2D battle backdrops for Gen1Recomp.
--
-- The engine paints an opaque paper field over the whole battle canvas
-- (BattleState:drawClassic and WideBattle.draw both open with a full-surface
-- rectangle fill).  Everything else in the battle -- HUDs, text box, mon
-- pics, animation OAM -- draws on top of that field.  So the insertion point
-- for a backdrop is exactly that one fill: replace it with an image and the
-- rest of the battle composites over the image unchanged.
--
-- This mod does that by wrapping the two draw entry points and, for the
-- duration of the original call, swapping in a shim for
-- love.graphics.rectangle that recognizes the field fill by its geometry and
-- substitutes a backdrop draw.  Every other rectangle the battle draws --
-- HP bars, the minimize blob, menu chrome -- passes straight through.
--
-- Why the shim rather than copying the function body: the body is ~90 lines
-- and changes between engine releases.  Matching on "a fill of the full
-- battle surface at the origin" is a much smaller thing to be wrong about,
-- and when it stops matching the mod degrades to vanilla rather than
-- crashing or drawing a stale half-frame.

local ok_bs, BattleState = pcall(require, "src.battle.BattleState")
local ok_wb, WideBattle = pcall(require, "src.battle.WideBattle")

local mod = ...

local OG_W, OG_H = 160, 144
local WIDE_W, WIDE_H = 304, 144

-- ---------------------------------------------------------------- assets

local BACKDROP_DIR = "assets/backdrops/"

-- Backdrop images, keyed by the name they are looked up under.  Loaded once
-- and cached; a missing file is a nil here, not an error, so a partial pack
-- works and simply falls back for the slots it has not filled.
local images = {}
local loaded = false

local function loadImage(layout, name)
  local key = layout .. "/" .. name
  if images[key] ~= nil then return images[key] or nil end
  local path = mod.path .. "/" .. BACKDROP_DIR .. key .. ".png"
  local ok, img = pcall(love.graphics.newImage, path)
  if ok and img then
    -- Nearest filtering: these are pixel backdrops sitting behind pixel
    -- sprites, and the whole composite is integer-scaled afterwards.
    img:setFilter("nearest", "nearest")
    images[key] = img
  else
    images[key] = false
  end
  return images[key] or nil
end

-- ------------------------------------------------------------- selection

-- Both combined: encounter kind narrows first, then the map's tileset.
-- Lookup order for a wild battle in a cave is:
--   wild_cave -> cave -> wild -> default
-- so a pack can be as coarse or as fine as its author wants.  Only
-- "default" is required.

local TILESET_SLOT = {
  OVERWORLD   = "field",
  PLATEAU     = "plateau",
  FOREST      = "forest",
  FOREST_GATE = "indoor",
  CAVERN      = "cave",
  UNDERGROUND = "cave",
  CEMETERY    = "tower",
  MANSION     = "mansion",
  GYM         = "gym",
  DOJO        = "gym",
  CLUB        = "club",
  -- FireRed picks a battle scene by terrain, and every one of these is a
  -- building: a wild battle inside gets the generic Indoors scene, a trainer
  -- battle inside gets the Indoor Trainer scene. Routing them to `indoor`
  -- gets both for free, because `trainer_indoor` outranks `indoor` in the
  -- lookup. Pokemon Mansion and the Power Plant are the two that actually
  -- have wild encounters, and they were showing the Indoor Trainer scene to
  -- a wild Ditto.
  FACILITY    = "indoor",
  SHIP        = "ship",
  SHIP_PORT   = "port",
  LAB         = "indoor",
  MUSEUM      = "museum",
  POKECENTER  = "indoor",
  MART        = "indoor",
  HOUSE       = "indoor",
  INTERIOR    = "indoor",
  -- Found by the audit, not by the palette data: Red's and Copycat's houses
  -- carry their own tilesets, which are not in palettes_gbc.lua.
  REDS_HOUSE_1 = "indoor",
  REDS_HOUSE_2 = "indoor",
  LOBBY       = "indoor",
  GATE        = "indoor",
}

-- Gen 1 stores no battle terrain, but the ENGINE knows how the encounter
-- started, which is the thing that actually matters. Four distinguishable
-- flavours of wild battle:
--
--   fishing  BattleState.newWild(..., { hooked = true }) from goFishing.
--            The flag is not kept on the battle -- it only picks introText --
--            so newWild is wrapped below to stash it.
--   surf     the overworld player is still flagged surfing underneath the
--            battle; the flag survives the fight because you resume surfing.
--   static   the scripted NPC encounters (Snorlax, the birds, Mewtwo, the
--            Vermilion Machop). These come through newWild with no opts and
--            never get a checkpointOrigin, which is what separates them from
--            a rolled grass encounter.
--   wild     everything else -- a normal roll in grass or a cave.
--
-- Water kinds outrank the tileset in the lookup (see pickBackdrop): fishing
-- on a route has to show water, not the route's grass.
local WATER_KIND = { fishing = true, surf = true, trainer_surf = true }

-- Which water you are on, not what you are doing on it. FireRed picks Sea vs
-- Pond per map, and so does this: surfing and fishing on the same water get
-- the same backdrop.
--
-- Kanto's open sea is the south and east coast. Everything else -- the
-- Cerulean and Viridian ponds, the Nugget Bridge river, Route 4's pool, the
-- Safari Zone, the Power Plant pond -- is inland and gets the Lake.
--
-- This list is hand-classified from Kanto's geography, NOT read out of the
-- game data; nothing in the map tables distinguishes a sea tile from a pond
-- tile. DIAGNOSTIC logs the resolved slot per map, so a wrong call here is
-- visible rather than silent.
local OCEAN_MAP = {
  PALLET_TOWN = true,      -- the south shore
  VERMILION_CITY = true,   -- the harbour
  VERMILION_DOCK = true,
  CINNABAR_ISLAND = true,
  FUCHSIA_CITY = true,     -- opens onto the Route 19 coast
  ROUTE_12 = true,         -- the east coast, the long fishing route
  ROUTE_13 = true,
  ROUTE_19 = true,         -- the southern sea routes
  ROUTE_20 = true,
  ROUTE_21 = true,
}

-- FireRed keeps separate battle scenes for a gym's junior trainers and its
-- leader, and gives Giovanni, each Elite Four member and the Champion one of
-- their own -- see "Backgrounds Table.txt" in the source pack. The patch we
-- took the art from collapses all of those onto the Gym scene; these
-- assignments restore the vanilla split, which is what the art was drawn for.
local BOSS_CLASS = {
  OPP_BROCK = "leader", OPP_MISTY = "leader", OPP_LT_SURGE = "leader",
  OPP_ERIKA = "leader", OPP_KOGA = "leader", OPP_SABRINA = "leader",
  OPP_BLAINE = "leader",
  -- Giovanni keeps his own scene in all three fights: Rocket Hideout,
  -- Silph Co. 11F and Viridian Gym.
  OPP_GIOVANNI = "giovanni",
  OPP_LORELEI = "lorelei", OPP_BRUNO = "bruno",
  OPP_AGATHA = "agatha", OPP_LANCE = "lance",
  -- RIVAL3 is the Champion and nothing else; RIVAL1 and RIVAL2 are the
  -- earlier fights and stay on their room's backdrop.
  OPP_RIVAL3 = "champion",
}

-- A boss's own scene outranks the room, the same way water does.
local BOSS_KIND = {
  leader = true, giovanni = true, lorelei = true, bruno = true,
  agatha = true, lance = true, champion = true,
}

local function kindSlot(battle)
  local kind = battle and battle.kind
  if kind == "trainer" then
    local boss = battle.oppClass and BOSS_CLASS[battle.oppClass]
    if boss then return boss end
    local overworld = battle.game and battle.game.overworld
    local player = overworld and overworld.player
    if player and player.surfing then return "trainer_surf" end
    return "trainer"
  end
  if kind == "safari" then return "safari" end
  if kind == "link" then return "link" end

  if battle.kaHooked then return "fishing" end
  local overworld = battle.game and battle.game.overworld
  local player = overworld and overworld.player
  if player and player.surfing then return "surf" end
  local origin = battle.checkpointOrigin
  if not (origin and origin.kind == "wild_encounter") then return "static" end
  return "wild"
end

-- The tileset of the map the battle was started from.  A link battle has no
-- meaningful map, and a battle entered from a script may run while the world
-- is mid-transition, so every step here is defensive: no tileset simply
-- means the kind-only and default slots are used.
-- game.world is the world DATA (text, map table). The live overworld -- and
-- with it the map you walked in from -- is game.overworld. Getting this wrong
-- is silent: every battle just resolves to `default`.
local function currentTileset(battle)
  local game = battle and battle.game
  local overworld = game and game.overworld
  local map = overworld and overworld.map
  local def = map and map.def
  return def and def.tileset or nil
end

local seen = {}

-- Per-map overrides, checked before the tileset. Some maps are the wrong
-- shape for their tileset: the S.S. Anne's open decks carry the SHIP tileset
-- along with the cabins and corridors, so a tileset-only rule puts you in a
-- panelled room while you are standing outside on the sea.
--
-- These ids come from the extracted ROM data (data.maps), not from anything
-- shipped with the engine, so if one is wrong it fails silently back to the
-- tileset. DIAGNOSTIC logs the map id on every first-seen tileset so a
-- mismatch is visible.
local MAP_SLOT = {
  SS_ANNE_BOW   = "deck",   -- the foredeck, and the rival fight
  SS_ANNE_3F    = "deck",   -- top-deck walkway, open to the sky
  VERMILION_DOCK = "port",

  -- All four found by the audit; every one of these carries a tileset that
  -- belongs to a different kind of building.
  OAKS_LAB      = "indoor",    -- DOJO tileset. The rival fight that opens the
                               -- game was resolving to a gym; as a building it
                               -- gets the Indoor Trainer scene like any other.
  CINNABAR_GYM  = "gym",       -- FACILITY tileset, so Blaine looked like Silph
  SAFFRON_GYM   = "gym",       -- FACILITY tileset, same for Sabrina
  SILPH_CO_11F  = "indoor",    -- INTERIOR tileset, so Giovanni's floor did not
                               -- match the ten floors below it

  -- Roofs. Both are open air on an interior tileset. Neither hosts a battle
  -- today, but a mod that adds one should not get a living room.
  CELADON_MART_ROOF    = "town",
  CELADON_MANSION_ROOF = "town",
}

local CITY_MAPS = {
  pallet = { "PALLET_TOWN" },
  viridian = { "VIRIDIAN_CITY", "VIRIDIAN_GYM" },
  pewter = { "PEWTER_CITY", "PEWTER_GYM" },
  cerulean = { "CERULEAN_CITY", "CERULEAN_GYM" },
  lavender = { "LAVENDER_TOWN",
    "POKEMON_TOWER_1F", "POKEMON_TOWER_2F", "POKEMON_TOWER_3F",
    "POKEMON_TOWER_4F", "POKEMON_TOWER_5F", "POKEMON_TOWER_6F",
    "POKEMON_TOWER_7F" },
  vermilion = { "VERMILION_CITY", "VERMILION_GYM" },
  celadon = { "CELADON_CITY", "CELADON_GYM" },
  fuchsia = { "FUCHSIA_CITY", "FUCHSIA_GYM" },
  cinnabar = { "CINNABAR_ISLAND", "CINNABAR_GYM" },
  saffron = { "SAFFRON_CITY", "SAFFRON_GYM" },
  indigo = { "INDIGO_PLATEAU" },
}

-- map id -> recolour directory. Only the town exteriors and the gyms: those
-- are the only things that differ between towns in the GBC overworld, where
-- the roofs change and nothing else does. Interiors are untouched, because a
-- Pokemon Center looks the same in every city.
local MAP_VARIANT = {}
for tag, ids in pairs(CITY_MAPS) do
  for _, id in ipairs(ids) do MAP_VARIANT[id] = tag end
end

-- Map.isFlyTown's test: the eleven city maps are indices 0..10. Towns and
-- routes share the OVERWORLD tileset, so without this every battle in Pallet
-- or Cerulean would come up against open route grass.
local NUM_CITY_MAPS = 11

local function currentMapId(battle)
  local game = battle and battle.game
  local overworld = game and game.overworld
  local map = overworld and overworld.map
  return map and map.id or nil
end

-- Pure: mapId + def -> place slot. Kept free of the live battle so the audit
-- below can run it over every map in the game without starting a fight.
local function slotFor(mapId, def)
  local tileset = def and def.tileset
  if not tileset then return nil end
  local override = mapId and MAP_SLOT[mapId]
  if override then return override end
  if tileset == "OVERWORLD" and def.index and def.index < NUM_CITY_MAPS then
    return "town"
  end
  return TILESET_SLOT[tileset]
end

local function tilesetSlot(battle)
  local tileset = currentTileset(battle)
  if not tileset then return nil end
  local mapId = currentMapId(battle)
  local game = battle.game
  local overworld = game and game.overworld
  local def = overworld and overworld.map and overworld.map.def
  local slot = slotFor(mapId, def)
  if mod.options:get("diagnostic") and not seen[mapId or tileset] then
    seen[mapId or tileset] = true
    mod.log:info("map %s (tileset %s) -> %s", tostring(mapId), tileset,
      slot or "(unmapped, using default)")
  end
  return slot
end

-- Tilesets that are not the inside of a building. Everything else falls back
-- to `indoor` rather than to `default`, so an unmapped interior gets a room
-- instead of a grass field. Caves and forests are listed here because they are
-- not buildings either -- they have their own art, but if that art is ever
-- missing, grass is a better wrong answer for them than a hallway.
local NOT_A_BUILDING = {
  OVERWORLD = true, PLATEAU = true, SHIP_PORT = true,
  FOREST = true, CAVERN = true, UNDERGROUND = true,
}

local function pickBackdrop(battle, layout)
  local kind = kindSlot(battle)
  local place = tilesetSlot(battle)
  local variant = MAP_VARIANT[currentMapId(battle) or ""]
  local img

  -- A gym leader DOES take their town's colour -- the whole point is that
  -- Misty's gym is blue and Blaine's is red. The Elite Four, Giovanni and the
  -- Champion do not: their scenes are deliberately their own.
  --
  -- Water is excluded for the same reason it outranks the tileset below. The
  -- eleven city maps carry OVERWORLD and resolve to `town`, so without this a
  -- Tentacool surfed into off Cinnabar came up against Cinnabar's rooftops --
  -- the town variant answered before the water rule was ever reached. There is
  -- no per-town water art for it to have meant instead: a variant folder holds
  -- town, gym and gym-trainer scenes and nothing else.
  if variant and not WATER_KIND[kind]
      and (kind == "leader" or not BOSS_KIND[kind]) then
    local function tinted(name)
      return loadImage(layout, variant .. "/" .. name)
    end
    if place then
      img = tinted(kind .. "_" .. place) or tinted(place)
      if img then return img end
    end
    img = tinted(kind)
    if img then return img end
  end

  if place then
    img = loadImage(layout, kind .. "_" .. place)
    if img then return img end
  end

  -- On water, the water wins: a hooked Goldeen on Route 4 must not come up
  -- against a grass field just because Route 4's tileset is OVERWORLD. A boss
  -- wins for the same reason -- Agatha's room is CEMETERY, and she should get
  -- her own scene rather than the Pokemon Tower's.
  if WATER_KIND[kind] then
    -- Water inside a cave is neither sea nor pond: Seafoam and Cerulean Cave
    -- have no sky, and the Sea backdrop is mostly sky.
    if place == "cave" then
      img = loadImage(layout, "water_cave")
      if img then return img end
    end
    local body = OCEAN_MAP[currentMapId(battle) or ""] and "sea" or "lake"
    img = loadImage(layout, body)
    if img then return img end
  elseif BOSS_KIND[kind] then
    img = loadImage(layout, kind)
    if img then return img end
  end

  if place then
    img = loadImage(layout, place)
    if img then return img end
  end
  img = loadImage(layout, kind)
  if img then return img end
  local tileset = currentTileset(battle)
  if tileset and not NOT_A_BUILDING[tileset] then
    img = loadImage(layout, "indoor")
    if img then return img end
  end
  return loadImage(layout, "default")
end

-- ------------------------------------------------------------------ draw

-- Cover the surface with the backdrop without distorting it: scale to the
-- larger of the two axis ratios and centre the overflow.  A backdrop authored
-- at exactly 160x144 or 304x144 lands 1:1 and this is a no-op.
local function drawCover(img, w, h)
  local iw, ih = img:getDimensions()
  if iw == w and ih == h then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
    return
  end
  local scale = math.max(w / iw, h / ih)
  local dx = (w - iw * scale) * 0.5
  local dy = (h - ih * scale) * 0.5
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, dx, dy, 0, scale, scale)
end

-- ------------------------------------------------------------- the patch

local active = false          -- inside a wrapped battle draw
local pendingImage = nil      -- backdrop chosen for this frame
local pendingW, pendingH = OG_W, OG_H
local outerCanvas = nil       -- the canvas bound when the battle draw began
local consumed = false        -- the field fill has already been replaced
local realRectangle = love.graphics.rectangle

-- Draw the backdrop, or a flat magenta field when FIELD TEST is on. Magenta
-- answers one question: if the field turns magenta the patch is running and
-- the image is being lost downstream; if it stays white the patch never fired.
--
-- This used to share the DIAGNOSTIC toggle with the logging and the audit,
-- which meant anyone running the audit had to play through a magenta game to
-- get it. Separate toggles: DIAGNOSTIC logs, FIELD TEST paints.
local function paintField()
  if mod.options:get("field_test") then
    love.graphics.setColor(1, 0, 1, 1)
    realRectangle("fill", 0, 0, pendingW, pendingH)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  drawCover(pendingImage, pendingW, pendingH)
end

local function rectangleShim(mode, x, y, w, h, ...)
  if active and not consumed and mode == "fill"
     and x == 0 and y == 0 and w == pendingW and h == pendingH then
    consumed = true
    local current = love.graphics.getCanvas()
    if current ~= outerCanvas then
      -- Classic colorized path: this fill is going into BattleState.bgCanvas,
      -- which drawZonePass then re-shades through the 4-colour palette shader
      -- -- an image baked in here would be crushed to four shades.  So clear
      -- that canvas to TRANSPARENT instead and paint the backdrop on the
      -- canvas underneath.  The shader returns vec4(mapped, p.a), so the
      -- transparency survives the zone pass and the backdrop shows through
      -- everywhere the HUD and text box do not paint.
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setCanvas(outerCanvas)
      paintField()
      love.graphics.setCanvas(current)
    else
      -- WIDE, and the flat no-shader fallback: the fill goes straight to the
      -- surface everything else composites onto, so substitution is enough.
      paintField()
    end
    return
  end
  return realRectangle(mode, x, y, w, h, ...)
end

-- One wrapper for both layouts.  `surface` gives the dimensions of the fill
-- to match, which is the only thing that differs between OG and WIDE.
local function wrap(original, surfaceW, surfaceH, layout)
  return function(...)
    local battle = ...
    if not mod.options:get("enabled") then return original(...) end
    -- The nickname prompt deliberately blanks the field to white; leave it.
    if battle and battle.blankForAskName then return original(...) end

    local img = pickBackdrop(battle, layout)
    if not img then return original(...) end

    pendingImage, pendingW, pendingH = img, surfaceW, surfaceH
    outerCanvas = love.graphics.getCanvas()
    consumed, active = false, true
    love.graphics.rectangle = rectangleShim

    local ok, err = pcall(original, ...)

    love.graphics.rectangle = realRectangle
    active, pendingImage, outerCanvas = false, nil, nil

    if not ok then error(err, 0) end
    return nil
  end
end

local function install()
  if not (ok_bs and BattleState) then return end
  if BattleState.__gen1arena then return end
  BattleState.__gen1arena = true

  -- goFishing passes { hooked = true } but newWild only uses it to choose
  -- introText, so the fact is lost by the time we draw. Keep it.
  local newWild = BattleState.newWild
  if newWild then
    BattleState.newWild = function(game, species, level, opts)
      local battle = newWild(game, species, level, opts)
      if battle then battle.kaHooked = opts and opts.hooked or nil end
      return battle
    end
  end

  local classic = BattleState.drawClassic
  if classic then
    BattleState.drawClassic = wrap(classic, OG_W, OG_H, "og")
  end

  if ok_wb and WideBattle and WideBattle.draw then
    local wide = WideBattle.draw
    WideBattle.draw = wrap(wide, WIDE_W, WIDE_H, "wide")
  end
end

-- --------------------------------------------------------------- options

mod.options:define({
  { key = "enabled", type = "toggle", label = "BACKDROPS", default = true },
  { key = "diagnostic", type = "toggle", label = "DIAGNOSTIC", default = false },
  { key = "field_test", type = "toggle", label = "FIELD TEST", default = false },
})

-- Full audit: every map in the game, with the backdrop it resolves to and
-- what kinds of battle it can host.
--
--   G  rolled grass encounters      (data.encounters[map].grass)
--   W  rolled water encounters      (data.encounters[map].water)
--   T  trainer NPCs                 (objects carrying trainerClass)
--   S  static wild encounters       (objects carrying pokemon -- Snorlax,
--                                    the birds, Mewtwo, the Machop)
--
-- Every map is walked, not just the ones with encounters, because a map can
-- host a battle with none of the four marks: the rival in Oak's Lab, Oak in
-- Pallet Town and the Chief in Celadon are script `start_battle` rows with no
-- trainer object behind them. Those maps would be invisible to an
-- encounter-driven audit and are exactly the ones worth checking.
--
-- Script battles need no special handling at draw time -- the script runs
-- while the player is still standing on the map, so game.overworld.map is
-- already right.
local function audit(game)
  local data = game and game.data
  local maps = data and data.maps
  if not maps then
    mod.log:warn("audit: no map data loaded")
    return
  end
  local encounters = data.encounters or {}

  -- Which slots actually have art, resolved once per distinct slot.
  local haveArt = {}
  local function artExists(slot)
    if haveArt[slot] == nil then
      haveArt[slot] = (loadImage("wide", slot) ~= nil)
        or (loadImage("og", slot) ~= nil)
    end
    return haveArt[slot]
  end

  local rows, problems = {}, {}
  for mapId, def in pairs(maps) do
    local enc = encounters[mapId] or {}
    local trainers, statics = 0, 0
    for _, obj in ipairs(def.objects or {}) do
      if obj.trainerClass then trainers = trainers + 1 end
      if obj.pokemon then statics = statics + 1 end
    end
    -- encDef.grass / .water are { rate, slots, buckets } records, NOT arrays.
    -- The first version of this audit tested #enc.grass, which is 0 for a
    -- record, so every map in Kanto reported no wild encounters.
    local function rolls(t)
      return t and (t.rate or 0) > 0 and #(t.slots or {}) > 0
    end
    local marks =
      (rolls(enc.grass) and "G" or "-") ..
      (rolls(enc.water) and "W" or "-") ..
      ((trainers > 0) and "T" or "-") ..
      ((statics > 0) and "S" or "-")

    local slot = slotFor(mapId, def)
    local note = ""
    if not slot then
      -- pickBackdrop falls a building back to `indoor`; the audit has to
      -- model that or it reports (default) for maps that resolve fine.
      local tileset = def.tileset
      if tileset and not NOT_A_BUILDING[tileset] then
        slot = "indoor"
        note = "  <-- unmapped tileset " .. tileset .. ", using indoor fallback"
      else
        note = "  <-- UNMAPPED TILESET " .. tostring(tileset)
      end
    end
    if slot and not artExists(slot) then
      note = "  <-- NO ART FOR SLOT"
    end
    if note ~= "" then problems[#problems + 1] = mapId .. note end

    rows[#rows + 1] = {
      id = mapId,
      tileset = def.tileset or "?",
      marks = marks,
      slot = slot or "(default)",
      note = note,
      battles = (marks ~= "----"),
    }
  end

  table.sort(rows, function(a, b)
    if a.tileset ~= b.tileset then return a.tileset < b.tileset end
    return a.id < b.id
  end)

  -- Logger keeps only the last 200 lines and prints to stdout, which on iOS
  -- is nowhere useful. So the full table goes to a file and the log gets just
  -- the problems, which always fit.
  local encCount = 0
  for _ in pairs(encounters) do encCount = encCount + 1 end

  local out = { ("gen1arena audit -- %d maps, %d encounter tables")
                  :format(#rows, encCount),
                "flags: G=grass W=water T=trainers S=static", "" }
  for _, r in ipairs(rows) do
    out[#out + 1] = ("%-30s %-12s %s -> %s%s")
      :format(r.id, r.tileset, r.marks, r.slot, r.note)
  end
  out[#out + 1] = ""
  out[#out + 1] = ("%d problems"):format(#problems)
  for _, p in ipairs(problems) do out[#out + 1] = "  " .. p end

  local body = table.concat(out, "\n")
  local ok, code, message = mod.storage:writeBytes(game, "audit", body)
  if ok then
    mod.log:info("audit written: mod_storage/<version>/<playthrough>/"
      .. "gen1arena/audit.bin (%d maps, %d problems)", #rows, #problems)
  else
    mod.log:warn("audit file failed (%s: %s) -- dumping problems only",
      tostring(code), tostring(message))
  end

  if #problems == 0 then
    mod.log:info("audit: no unmapped tilesets, no missing art")
  else
    mod.log:warn("audit: %d problems", #problems)
    for _, p in ipairs(problems) do mod.log:warn("  %s", p) end
  end
end

mod.events:on("game.ready", function(ev)
  loaded = true
  install()
  if BattleState and BattleState.__gen1arena then
    mod.log:info("patched battle draw (og + wide)")
  else
    mod.log:warn("could not patch BattleState -- backdrops will not appear")
  end
  if mod.options:get("diagnostic") then
    local ok, err = pcall(audit, ev and ev.game)
    if not ok then mod.log:warn("audit failed: %s", tostring(err)) end
  end
end)

return {}
