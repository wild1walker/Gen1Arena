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
local ok_rend, Renderer = pcall(require, "src.render.Renderer")

local mod = ...

-- ------- and the one case where a backdrop is the wrong answer entirely
--
-- A voxel mod draws the battle over the MAP.  There is a whole diorama behind
-- the fight already, so a picture painted into the field is at best a second
-- background nobody asked for and at worst a fight with the mod drawing the
-- first one: DRAMALESS_SHAPE suppresses the engine's field fill by shimming
-- `love.graphics.rectangle`, which is the same call this mod shims to REPLACE
-- that fill.  Two mods swapping one function for the length of one draw is a
-- coin toss decided by load order.
--
-- So this stands down, and the test is the renderer rather than a list of mod
-- ids.  Every voxel fork -- the Dramatic Shape lineage, DRAMALESS_SHAPE,
-- potato_voxel -- presents its battle the same way, through
-- `Renderer:setWorldOverride`, and the renderer clears that in `beginFrame`.
-- So a non-nil `worldOverride` is exactly "something has replaced the world
-- image on THIS frame", which is the question, asked of the engine, with no
-- mod named.  A fork with its 3D battles switched off never sets it and this
-- never fires -- which is right: then there IS no diorama and the backdrop is
-- wanted.
--
-- Read at draw time and not cached: the forks set it from their own
-- `BattleState:draw` wrap before calling through to the engine's, so it is
-- already there when this mod's wrap around drawClassic runs.
--
-- Two conditions, and the first one is not optional.  A world override ALONE
-- is not a voxel mod: the engine sets one for its OWN render pipelines
-- (OverworldController -> Pipelines.drawWorld -> Renderer:setWorldOverride),
-- so reading the override by itself would stand this mod down for a pipeline
-- mod, or for the engine's own world-background battle, neither of which puts
-- a diorama behind the fight.  The first draft of this did exactly that.
--
-- So: a voxel mod is installed AND something replaced the world image on this
-- frame.  With no voxel mod the first test fails and nothing else is even
-- asked, which makes this change inert for the overwhelming majority of
-- installs -- the ones with no voxel mod at all.
local function worldTaken()
  local voxel = mod.voxel
  if not (voxel and voxel.id()) then return false end
  if not (ok_rend and type(Renderer) == "table") then return false end
  return Renderer.worldOverride ~= nil
end

local OG_W, OG_H = 160, 144
local WIDE_W, WIDE_H = 304, 144

-- ------------------------------------------------------------ the dev rows
--
-- DIAGNOSTIC and FIELD TEST are maintenance tools, not settings.  One writes
-- an audit of every map in the game to mod storage; the other paints the
-- battlefield flat magenta.  Neither answers a question a player has, and
-- FIELD TEST in particular is a trap on a shipped cart: the row says nothing
-- about what it does, and flipping it to find out leaves every battle magenta
-- until it is found again.
--
-- So they are only offered in developer mode -- POKEPORT_DEV=1, or
-- --developer.  Nothing is lost: the person those two rows are for is the
-- person already running the game that way, and both work there exactly as
-- they always did.
--
-- mod.developer is the engine's own answer, and the only one reachable from
-- here.  A mod runs in a sandbox whose `_G` is its own table
-- (src/mods/Sandbox.lua sets env._G = env) and whose `os` is four clock
-- functions, so neither the POKEPORT_DEV_MODE global nor os.getenv can be
-- seen from inside one -- reading the global answers nil for everybody,
-- developer included, which is a row nobody can reach rather than a row a
-- player cannot.  The loader resolves the environment once at construction
-- and copies the verdict onto the handle as plain data, for exactly this.
--
-- Asked through this rather than straight off the option set, because rows
-- that go away have to take their stored values with them.  A player who
-- turned FIELD TEST on once to see what it did, and then took an update,
-- would otherwise keep a magenta battlefield with no row left to turn it off.
-- Asked through this rather than straight off the option set, because rows
-- that go away have to take their stored values with them.  A player who
-- turned FIELD TEST on once to see what it did, and then took an update,
-- would otherwise keep a magenta battlefield with no row left to turn it off.
local DEV = mod.developer == true

local function devOption(key)
  if not DEV then return false end
  return mod.options:get(key) and true or false
end

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
  if devOption("diagnostic") and not seen[mapId or tileset] then
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
-- ...and the one to carry into the bars around it, claimed by the letterbox
-- pass at the end of the same frame.  See the note over bleedInto.
local bleedImage, bleedW, bleedH = nil, OG_W, OG_H
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
  if devOption("field_test") then
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

-- ------------------------------------------------- the bars around it
--
-- A battle asks the renderer for a WHITE surround.  `Renderer:endFrame`
-- clears the void around the blit to `PaletteFX.paperShade` for any state
-- that sets `letterboxWhite`, and a battle sets it -- which is exactly right
-- for the game it was written for.  The battle field is white paper, so a
-- white surround makes that paper look like it runs off the edges of the
-- screen instead of stopping at a rectangle.
--
-- Put a picture in the field and that reasoning inverts.  The paper is gone
-- and the surround is the only white left, so instead of disappearing it
-- becomes a bright frame around the art -- and the wider the surface, the
-- more of it there is.  A WIDE battle is 304x144: very wide and no taller, so
-- in an ordinary window the bars above and below it are the biggest thing on
-- the screen.  That is the white bar at the top of a wide arena.
--
-- So the backdrop is carried into the bars.  `render.letterbox` is the seam
-- the engine documents for exactly this ("SGB borders / custom void art in
-- the bars around the 160x144 (or world) blit"), and it runs after the void
-- is cleared and before the game canvas is drawn, so the playfield still
-- lands on top and nothing here can cover the battle.
--
-- It is drawn by EDGE CLAMP rather than by scaling the picture up to the
-- window.  The bars have to continue the field, and a magnified copy of the
-- same image behind a 1:1 copy of it meets at a visible seam -- two different
-- scales of the same tree.  Stretching the outermost row of pixels instead
-- gives the bars the colour the field already has where it meets them: sky at
-- the top, ground at the bottom, and no seam at all, which is what a backdrop
-- painted to the edge of its frame is asking for.
-- ------- how a bar is filled
--
-- It was the picture's one-pixel edge, stretched outward: the left column
-- into the left bar, the top row into the top bar, a corner pixel into each
-- corner.  That is exact where the bars are thin -- the colour at the seam is
-- the colour the field ends on, so there is no line -- and it falls apart
-- where they are not.  On a landscape phone the bars are wider than the
-- surface between them, and a backdrop with sky, hill and grass in it becomes
-- a field of horizontal stripes: one band per source row, six screen pixels
-- tall, for two thirds of the window.  A player called it broken and was
-- right.
--
-- So the bars show the SAME PICTURE, scaled to cover the window, and each bar
-- shows the part of it that falls where that bar is.  What that buys:
--
--   * the bars carry real detail rather than a smear of one column;
--   * the cover scale is max(ww/iw, wh/ih) and the surface's is vpw/iw, so as
--     the bars shrink the two converge and the seam closes by itself.  Thin
--     bars look exactly as continuous as the stretch did; wide ones degrade
--     into a zoomed backdrop instead of stripes.
--
-- Cover means cover, so every bar's source rectangle is inside the picture
-- and there is nothing to clamp.  Quads rather than a scissor because a
-- scissor is in physical pixels and this pass is not the only thing that
-- decides the transform -- a quad is exact whatever the display is doing.
--
-- Cut once per (picture, window) rather than once per frame: the eight of
-- them only change when the window does.
local quadCache = setmetatable({}, { __mode = "k" })

-- Where the picture lands when it is scaled to cover (ww, wh).
local function coverFit(iw, ih, ww, wh)
  if not (iw > 0 and ih > 0 and ww > 0 and wh > 0) then return nil end
  local scale = math.max(ww / iw, wh / ih)
  return scale, (ww - iw * scale) * 0.5, (wh - ih * scale) * 0.5
end

local function coverQuads(img, iw, ih, view, rects)
  local scale, dx, dy = coverFit(iw, ih, view.ww or 0, view.wh or 0)
  if not scale then return nil end
  local key = ("%d:%d:%d:%d:%d:%d")
    :format(view.ww or 0, view.wh or 0, view.ox or 0, view.oy or 0,
            view.vpw or 0, view.vph or 0)
  local cached = quadCache[img]
  if cached and cached.key == key then return cached, scale, dx, dy end
  cached = { key = key, quads = {} }
  for i, r in ipairs(rects) do
    cached.quads[i] = love.graphics.newQuad(
      (r.x - dx) / scale, (r.y - dy) / scale,
      r.w / scale, r.h / scale, iw, ih)
  end
  quadCache[img] = cached
  return cached, scale, dx, dy
end

-- FAITHFUL RATIO's mobile lock, asked the way the renderer asks it.
local function faithfulLocked()
  local ok, FaithfulRes = pcall(require, "src.core.FaithfulRes")
  if not ok or type(FaithfulRes) ~= "table" then return false end
  if type(FaithfulRes.scaleCap) ~= "function" then return false end
  local capped, value = pcall(FaithfulRes.scaleCap)
  return capped and value and true or false
end

-- Which bars there are, and where each one goes.  Pure: `view` in, a list of
-- { slice, x, y, w, h } out, in the order they are drawn.  `slice` names which
-- one-pixel edge of the picture is stretched into that rectangle.
--
-- Separated from the drawing because this is the whole of what can be wrong
-- here -- a bar an edge short, a corner left as paper, a rectangle with a
-- negative width -- and none of it needs a window to check.  tests/
-- arenableed_test.lua drives it directly.
local function bleedRects(view)
  if type(view) ~= "table" then return nil end
  local ox, oy = view.ox or 0, view.oy or 0
  local vpw, vph = view.vpw or 0, view.vph or 0
  local ww, wh = view.ww or 0, view.wh or 0
  if vpw <= 0 or vph <= 0 or ww <= 0 or wh <= 0 then return nil end

  local right = ww - (ox + vpw)      -- the bar to the right of the surface
  local below = wh - (oy + vph)      -- ...and under it
  local out = {}
  local function add(slice, x, y, w, h)
    if w > 0 and h > 0 then
      out[#out + 1] = { slice = slice, x = x, y = y, w = w, h = h }
    end
  end

  -- The four sides first, each the full length of the surface it borders,
  -- then the corners, which the sides do not reach.
  add("top", ox, 0, vpw, oy)
  add("bottom", ox, oy + vph, vpw, below)
  add("left", 0, oy, ox, vph)
  add("right", ox + vpw, oy, right, vph)
  add("tl", 0, 0, ox, oy)
  add("tr", ox + vpw, 0, right, oy)
  add("bl", 0, oy + vph, ox, below)
  add("br", ox + vpw, oy + vph, right, below)
  return out
end

local function bleedInto(view)
  local img = bleedImage
  -- Claimed, not read: the hook runs once per frame after the battle drew,
  -- and a frame with no battle draw in it must not inherit the last one's
  -- picture.  Clearing on the way past is what makes that true without a
  -- frame counter.
  bleedImage = nil
  if not img then return end
  if mod.options:get("bleed") == false then return end
  -- Nothing painted the field this frame, so there is no edge to stretch.
  -- The bars belong to whatever took the world.
  if worldTaken() then return end
  -- BATTLE BG "world" runs the world pass, which takes the whole window and
  -- leaves no bars to fill.
  if view and view.worldActive then return end
  -- FAITHFUL RATIO's mobile lock promises the display outside the GB screen
  -- stays black (src/core/FaithfulRes.lua), and the renderer honours that
  -- ahead of the paper surround.  A backdrop in the bars would break the same
  -- promise, so it stands down for the same reason the paper does.
  if faithfulLocked() then return end

  local rects = bleedRects(view)
  if not rects or not rects[1] then return end

  local iw, ih = img:getDimensions()
  if iw <= 0 or ih <= 0 then return end
  local cut, scale = coverQuads(img, iw, ih, view, rects)
  if not cut then return end

  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  -- Eight draws at most, each the part of the covering picture that falls
  -- where that bar is, at the cover's own scale.
  for i, r in ipairs(rects) do
    local quad = cut.quads[i]
    if quad then g.draw(img, quad, r.x, r.y, 0, scale, scale) end
  end
end

-- Published for tests/arenavoxel_test.lua: the one decision that stands this
-- whole mod down, and the one that is silent when it is wrong.
mod.exports.worldTaken = worldTaken
mod.exports.bleedRects = bleedRects
mod.exports.bleedCover = coverFit

-- ------------------------------------------------------- the paper behind

-- Gen 1 pics are matted: the extractor floods colour 0 (white) in from the
-- image border and turns it transparent (ImageWriter.matteColor0), so a pic
-- can sit on a non-white surface without a white box around it.  The flood is
-- 4-connected and stops only at ink, so wherever a mon's own white touches
-- the edge of the box -- or reaches it through a gap in the outline -- the
-- flood pours into the BODY and hollows it out.  On hardware that is
-- invisible: the field behind is the same white, so a hollow pic and a solid
-- one look identical.  Put a backdrop there instead and the hole is a window.
--
-- It is worst exactly where it is least wanted.  A pale mon is nearly all
-- colour 0, so almost nothing of it survives the flood: Mew's back pic keeps
-- 145 of the 400 pixels in its own bounding box and reads as a bare outline
-- with the lava showing through it.  A dark mon keeps its body and is fine.
-- That is why it is SOME POKéMON and not all of them, and why it looks like
-- the mon went invisible rather than like the mod drew it wrong.
--
-- So put the paper back, under the pic and nowhere else: fill the pic's own
-- content box with the field shade it was matted against, then let the engine
-- draw the pic over it.  That is the composition the Game Boy showed, and the
-- box is the mon's own bounding box rather than the whole 32x32 or 56x56 pic
-- rect, so it is as tight as the art allows.
--
-- Only pics that ACTUALLY lost something get it, which keeps this off every
-- surface that does not need it:
--
--   * more than 4 opaque colours means true-colour art -- a sprite mod's
--     Crystal replacement, which carries its own honest alpha and must not be
--     boxed.  A four-shade pic, plain or palette-baked, is the matted kind.
--   * under 30% of the content box transparent means the flood took nothing
--     but the corners of a round mon.  Measured art splits cleanly here:
--     unmatted mod pics score 0.00, and the matted pics that break score
--     0.47 (a front) and 0.64 (Mew's back).
--
-- Measured once per image and cached weakly, so a species costs one readback
-- the first time it is on screen and nothing after that.
local PAPER_MAX_COLORS = 4
-- How much of the pic's box is transparency the mon's own ink is on both
-- sides of, in both axes -- a hole through the body rather than the space
-- around it.
--
-- This used to be plain emptiness: how much of the bounding box was not
-- opaque.  That reads a shape as damaged for being an irregular shape.  A
-- Crystal Koffing with a gas plume measures 0.51 empty on the frames the
-- plume is out and 0.26 on the frames it is not, so a solid, undamaged sprite
-- crossed a 0.30 line three times per animation cycle and the paper blinked
-- on and off behind it.
--
-- Enclosure does not care what silhouette the mon has, only whether there is
-- a window through it -- which is the whole complaint: "the mon went
-- invisible", the backdrop showing where the body should be.
--
-- The line is set off the art rather than guessed.  All 8563 images in the
-- Crystal sprite pack were measured: the highest is 0.282, an Unown O, which
-- is a ring and honestly has a hole in it; the Koffing above runs 0.00 to
-- 0.05, and only 67 images reach 0.20 at all.  A pic the flood reduced to a
-- bare outline is 0.47 to 0.64.  0.35 sits in the gap with room on both
-- sides.
local PAPER_MIN_ENCLOSED = 0.35
local PAPER_MAX_SIDE = 128
-- A mon is not eight pixels across.  The smallest Gen 1 front pic is 5x5
-- tiles and its content fills most of that, so a box under this is a piece of
-- something rather than a whole pic -- which is what both of the ways this has
-- gone wrong produced.  A floor on the COLOUR count would catch the same
-- fragments and is deliberately not here: a pale mon the flood ate can be
-- reduced to a bare black outline, one colour and nothing else, and that pic
-- is exactly the one the paper exists for.
local PAPER_MIN_SIDE = 8

local paperBox = setmetatable({}, { __mode = "k" })

-- The pic's pixels, read back off a scratch canvas.  LOVE hands out no way to
-- read an Image directly, and the mod never sees the path the engine loaded
-- it from, so the picture has to be drawn to be looked at.  "replace" so the
-- alpha arrives exactly as the pic carries it rather than blended.
local function readPic(img)
  local w, h = img:getDimensions()
  -- DPISCALE IS LOAD-BEARING.  love.graphics.newCanvas(w, h) takes the
  -- window's DPI scale unless it is told otherwise, so on a phone at scale 3
  -- a 56x56 request is a 168x168 canvas, the pic is drawn into it three times
  -- the size, and newImageData hands back 168x168.  The measurement below
  -- then read the first 56x56 of that -- the top-left EIGHTEEN pixels of the
  -- sprite, magnified -- and answered on a corner: one colour, mostly empty,
  -- which passes both tests and lays paper in a box that is nowhere near the
  -- mon.  On a desktop at scale 1 none of it happens, which is why this
  -- shipped twice.
  --
  -- Pinned here, and the measurement checks what actually came back as well,
  -- so a host that ignores the request is measured correctly rather than
  -- measured wrong.
  local ok, pinned = pcall(love.graphics.newCanvas, w, h, { dpiscale = 1 })
  local canvas = (ok and pinned) or love.graphics.newCanvas(w, h)
  local prevCanvas = love.graphics.getCanvas()
  -- push("all") carries the colour, blend mode, shader and scissor; the canvas
  -- is not part of that state, so it is saved and put back by hand.
  love.graphics.push("all")
  -- ORIGIN IS LOAD-BEARING.  This runs inside the battle draw, where the
  -- engine has a translate and a scale in effect for the letterboxed surface,
  -- and a draw at 0,0 under that transform lands somewhere other than 0,0 --
  -- mostly outside a canvas the size of one pic.  Measuring what came back
  -- then answered on a handful of stray pixels: too few colours, so
  -- full-colour replacement art passed the four-shade test, and mostly empty,
  -- so it passed the hollow test as well.  The result was paper laid under a
  -- Crystal sprite that needed none, in a box that was not where the sprite
  -- was.  The scissor goes for the same reason: the battle clips to its own
  -- rect, and a clip in outer coordinates would cut this canvas to nothing.
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setShader()
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, 0, 0)
  love.graphics.setCanvas(prevCanvas)
  love.graphics.pop()
  return canvas:newImageData()
end

local function measurePic(img)
  local w, h = img:getDimensions()
  if w < 1 or h < 1 or w > PAPER_MAX_SIDE or h > PAPER_MAX_SIDE then
    return false
  end
  local data = readPic(img)

  -- What came back, not what was asked for.  A canvas carries a DPI scale and
  -- the readback is in ITS pixels, so this can be a whole-number multiple of
  -- the pic even with the scale pinned above.  Reading the pic's own w by h
  -- out of a bigger image reads one CORNER of it and answers on that; measure
  -- all of what arrived and divide the box back down instead.  Anything that
  -- is not a clean square multiple is a geometry this cannot reason about, and
  -- painting a white rectangle on a guess is the failure being fixed.
  local dw, dh = w, h
  if type(data.getDimensions) == "function" then
    local ok, gw, gh = pcall(data.getDimensions, data)
    if ok and tonumber(gw) and tonumber(gh) then dw, dh = gw, gh end
  end
  if dw < w or dh < h or dw % w ~= 0 or dh % h ~= 0 or dw / w ~= dh / h then
    return false
  end
  local ratio = dw / w

  local opaque = {}
  local minX, minY, maxX, maxY = dw, dh, -1, -1
  local colors, nColors = {}, 0
  for y = 0, dh - 1 do
    local row = y * dw
    for x = 0, dw - 1 do
      local r, g, b, a = data:getPixel(x, y)
      if a > 0.5 then
        opaque[row + x] = true
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if y < minY then minY = y end
        if y > maxY then maxY = y end
        if nColors <= PAPER_MAX_COLORS then
          local key = math.floor(r * 255 + 0.5) * 65536
                    + math.floor(g * 255 + 0.5) * 256
                    + math.floor(b * 255 + 0.5)
          if not colors[key] then
            colors[key] = true
            nColors = nColors + 1
          end
        end
      end
    end
  end
  if maxX < minX or nColors > PAPER_MAX_COLORS then return false end

  local bw, bh = maxX - minX + 1, maxY - minY + 1
  if bw / ratio < PAPER_MIN_SIDE or bh / ratio < PAPER_MIN_SIDE then
    return false
  end

  -- How far the ink reaches along each row and each column.  A transparent
  -- pixel with ink on both sides of it in its row AND in its column is inside
  -- the mon; one that runs out to the edge of the box in either axis is the
  -- space around the mon, whatever shape that space happens to be.
  local rowFirst, rowLast, colFirst, colLast = {}, {}, {}, {}
  for y = minY, maxY do
    local row = y * dw
    for x = minX, maxX do
      if opaque[row + x] then
        if not rowFirst[y] then rowFirst[y] = x end
        rowLast[y] = x
      end
    end
  end
  for x = minX, maxX do
    for y = minY, maxY do
      if opaque[y * dw + x] then
        if not colFirst[x] then colFirst[x] = y end
        colLast[x] = y
      end
    end
  end

  local enclosed = 0
  for y = minY, maxY do
    local row = y * dw
    local rf, rl = rowFirst[y], rowLast[y]
    if rf then
      for x = rf + 1, rl - 1 do
        if not opaque[row + x] then
          local cf, cl = colFirst[x], colLast[x]
          if cf and y > cf and y < cl then enclosed = enclosed + 1 end
        end
      end
    end
  end
  if enclosed / (bw * bh) < PAPER_MIN_ENCLOSED then return false end

  return { x = minX / ratio, y = minY / ratio,
           w = bw / ratio, h = bh / ratio }
end

local function picPaperBox(img)
  if paperBox[img] == nil then
    local ok, box = pcall(measurePic, img)
    paperBox[img] = (ok and box) or false
    if not ok then
      mod.log:warn("could not measure a pic for its paper: %s", tostring(box))
    end
  end
  return paperBox[img] or nil
end

-- Whether drawBattlerPic is about to draw the pic whole, at the x/y/scale it
-- was handed.  Every other path it can take -- the substitute doll, the faint
-- sink, a minimize blob, an fx offset -- draws something else or somewhere
-- else, and paper laid at the base position would sit behind none of it.  A
-- fade is the one exception: same pic, same place, just dimmer.
local function drawsPlainPic(battle, battler)
  if battler.fainted then return false end
  local faintFx = false
  if type(battle.fxFaintActive) == "function" then
    local ok, active = pcall(battle.fxFaintActive, battle, battler)
    faintFx = ok and active or false
  end
  if faintFx then return false end
  if battler.substituteHP then return false end
  local pf = battle.picFx and battle.picFx[battler]
  if not pf then return true end
  if pf.fade then return true end
  if pf.kind or pf.hidden or pf.minimized then return false end
  return (pf.ox or 0) == 0 and (pf.oy or 0) == 0
end

-- White, because that is the shade the engine's own field fill lays down and
-- the shade the pic was matted against.  It goes onto the same canvas the pic
-- does, so the zone pass shades the paper and the mon together and the patch
-- lands on the display mode's paper rather than beside it.
local function drawPicPaper(battle, battler, x, y, scale)
  local img = battle:picImage(battler.sprite)
  if not img then return end
  local box = picPaperBox(img)
  if not box then return end
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(1, 1, 1, a)
  realRectangle("fill", x + box.x * scale, y + box.y * scale,
                box.w * scale, box.h * scale)
  love.graphics.setColor(r, g, b, a)
end

-- One wrapper for both layouts.  `surface` gives the dimensions of the fill
-- to match, which is the only thing that differs between OG and WIDE.
local function wrap(original, surfaceW, surfaceH, layout)
  return function(...)
    local battle = ...
    if not mod.options:get("enabled") then return original(...) end
    -- A voxel mod is already drawing a world behind this battle; see
    -- worldTaken.
    if worldTaken() then return original(...) end
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
    -- Only when a backdrop actually replaced the field.  With BACKDROPS off,
    -- or on a battle no slot answered, the engine's own white field is still
    -- there and the white bars around it are the right colour for it.
    if consumed then
      bleedImage, bleedW, bleedH = pendingImage, surfaceW, surfaceH
    end
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

  -- The paper under the pics.  Wrapped here rather than shimmed inside the
  -- draw because this is the one call both layouts and both sides go through
  -- for a mon that is simply standing there, and it arrives with the battler,
  -- the placement and the scale already resolved -- so the paper lands where
  -- the pic is going to land, at whatever size the engine picked, with no
  -- second copy of backPlacement here to drift out of step with the engine's.
  --
  -- `consumed` gates it: paper is only wanted where a backdrop actually
  -- replaced the field this frame.  With BACKDROPS off, or on a battle no
  -- slot answered, the engine's own white field is still there and there is
  -- nothing to put back.
  local battlerPic = BattleState.drawBattlerPic
  if battlerPic then
    BattleState.drawBattlerPic = function(self, battler, x, y, scale)
      if active and consumed and battler
         and mod.options:get("pic_paper") then
        local ok, err = pcall(function()
          if drawsPlainPic(self, battler) then
            drawPicPaper(self, battler, x, y, scale or 1)
          end
        end)
        if not ok then
          mod.log:warn("the pic paper was not laid: %s", tostring(err))
        end
      end
      return battlerPic(self, battler, x, y, scale)
    end
  end

  if ok_wb and WideBattle and WideBattle.draw then
    local wide = WideBattle.draw
    WideBattle.draw = wrap(wide, WIDE_W, WIDE_H, "wide")
  end
end

-- --------------------------------------------------------------- options

local optionRows = {
  { key = "enabled", type = "toggle", label = "BACKDROPS", default = true },
  { key = "pic_paper", type = "toggle", label = "MON PAPER", default = true },
  -- The bars around the battle.  On, the backdrop's own edge is stretched
  -- into them so the picture runs off the screen; off, they are the paper
  -- white the engine gives a battle, which with a backdrop up reads as a
  -- bright frame around the art -- and in a WIDE battle as a big white bar
  -- above and below it.  See bleedInto.
  { key = "bleed", type = "toggle", label = "EDGE TO EDGE", default = true },
}

if DEV then
  optionRows[#optionRows + 1] =
    { key = "diagnostic", type = "toggle", label = "DIAGNOSTIC", default = false }
  optionRows[#optionRows + 1] =
    { key = "field_test", type = "toggle", label = "FIELD TEST", default = false }
end

mod.options:define(optionRows)

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

-- The bars, every frame, after the void is cleared and before the playfield
-- is drawn over the middle of it.
mod.hooks:wrap("render.letterbox", function(nextLink, view)
  local ok, err = pcall(bleedInto, view)
  if not ok then
    bleedImage = nil
    mod.log:warn("the backdrop did not reach the bars: %s", tostring(err))
  end
  return nextLink(view)
end)

mod.events:on("game.ready", function(ev)
  loaded = true
  install()
  if BattleState and BattleState.__gen1arena then
    mod.log:info("patched battle draw (og + wide)")
  else
    mod.log:warn("could not patch BattleState -- backdrops will not appear")
  end
  if devOption("diagnostic") then
    local ok, err = pcall(audit, ev and ev.game)
    if not ok then mod.log:warn("audit failed: %s", tostring(err)) end
  end
end)

return {}
