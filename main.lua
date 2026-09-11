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
--
-- So they are only offered in developer mode -- POKEPORT_DEV=1, or
-- --developer.  `mod.developer` is the engine's own answer and the only one
-- reachable from a sandboxed mod: neither the POKEPORT_DEV_MODE global nor
-- os.getenv is, so a row nobody can reach is the alternative.
--
-- The nightly channel sets this to `true` outright, because that channel IS
-- the developer build and a toggle behind a flag nobody running a nightly has
-- set is a toggle nobody running a nightly can use.  On a release build --
-- this one -- both rows go with `mod.developer`.
local DEV = mod.developer == true

local function devOption(key)
  if not DEV then return false end
  return mod.options:get(key) and true or false
end

-- ------- which generation
--
-- Asked once and cached: a boot cannot change generation.  Declared up here
-- rather than beside the selection tables because `loadImage` below reads it,
-- and a local read above its own declaration is not that local at all -- it
-- is a global fetch, and nil.
local isGen2
local function gen2()
  if isGen2 == nil then
    isGen2 = false
    local okV, GameVersion = pcall(require, "src.core.GameVersion")
    if okV and type(GameVersion) == "table"
        and type(GameVersion.generation) == "function" then
      local okCall, generation = pcall(GameVersion.generation)
      isGen2 = okCall and generation == 2
    end
  end
  return isGen2
end

-- ------------------------------------------------- the same art, renamed
--
-- Every one of the twenty backdrops in this pack is a FireRed TERRAIN scene.
-- FireRed itself assigns six of them to Kanto bosses -- and that assignment,
-- not the art, is what is Kanto-specific:
--
--     14 Snow          -> Giovanni      17 Desert   -> Agatha
--     15 Snow Cave     -> Lorelei       18 Volcano  -> Lance
--     16 Snow Mountain -> Bruno         19 Space    -> Champion
--
-- Giovanni, Lorelei and Agatha are not in Gold, Silver or Crystal at all, so
-- on a Gen 2 boot three finished scenes -- a snowfield, an ice cave and a
-- desert -- would otherwise sit in the package unreachable.  Johto has a use
-- for two of them immediately, and one of those is exact: the ICE PATH is an
-- ice cave, which is what 15 is a painting of.
--
-- So a Gen 2 slot may name a file drawn for something else.  The alias is
-- here rather than in the tables so that the tables can say what a place IS
-- ("ice_path") instead of which Kanto character happens to own the picture of
-- it, and so the provenance is recorded in one place.
--
-- Nothing is copied and no file is renamed on disk: the credit in CREDITS.md
-- is for the art, and the art has not changed.
local GEN2_SLOT_FILE = {
  -- places
  ice_path = "lorelei",        -- 15 Snow Cave -- the Ice Path, exactly
  -- the Elite Four, the Champion, and the fight on Mt Silver
  will = "champion",           -- 19 Space -- Will is the psychic
  koga = "agatha",             -- 17 Desert
  karen = "lorelei",           -- 15 Snow Cave -- shares with the Ice Path
  red = "giovanni",            -- 14 Snow -- Mt Silver's summit is snow
  -- BRUNO keeps 16 Snow Mountain and LANCE keeps 18 Volcano: both are in this
  -- game, and both keep the scene the art was drawn for them.
}

-- ---------------------------------------------------------------- assets

local BACKDROP_DIR = "assets/backdrops/"

-- Backdrop images, keyed by the name they are looked up under.  Loaded once
-- and cached; a missing file is a nil here, not an error, so a partial pack
-- works and simply falls back for the slots it has not filled.
local images = {}
local loaded = false

local function loadImage(layout, name)
  -- On Gold a slot may be an alias for a file drawn under another name; see
  -- GEN2_SLOT_FILE below.  Resolved here so every caller in the chain --
  -- variant, place, water, boss, fallback -- gets it without asking.
  if gen2() and GEN2_SLOT_FILE[name] then name = GEN2_SLOT_FILE[name] end
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

-- ---------------------------------------------------------------- Gold
--
-- Gold, Silver and Crystal pick a backdrop the same way, out of different
-- facts.  Everything below replaces the four INPUTS to `pickBackdrop`; the
-- chain itself -- kind narrows, then place, then the town's colour, with
-- water and a boss outranking the room -- is the same code and is not
-- duplicated.
--
-- Three of the inputs are better here than on Red, because Gold's map header
-- carries what Red made this file guess:
--
--   `tileset`      the same idea, different names and twenty-eight of them
--                  (thirty-six on Crystal).
--   `environment`  TOWN / ROUTE / INDOOR / CAVE / GATE / DUNGEON, straight
--                  off the header.  Red has no such field, which is why its
--                  arm needs NOT_A_BUILDING to guess whether an unmapped
--                  tileset is a room; here an unmapped tileset still gets a
--                  right answer.
--   `landmark`     which town you are in, by name.  Red's arm hand-lists the
--                  eleven city maps and tests a map index against them; Gold
--                  says so itself, so a town variant is a table lookup and a
--                  romhack's new town is one row.

local TILESET_SLOT_GEN2 = {
  -- The three overworld tilesets.  Routes and towns share them exactly as
  -- OVERWORLD is shared on Red, so `environment` is what separates the two
  -- below -- Red has to use a map index for the same job.
  TILESET_JOHTO = "field",
  TILESET_JOHTO_MODERN = "field",
  TILESET_KANTO = "field",

  -- Buildings.  All of these route to `indoor`, which gets the wild scene and
  -- the Indoor Trainer scene together, because `trainer_indoor` outranks
  -- `indoor` in the lookup -- the same trick the Gen 1 arm plays with
  -- FACILITY and the rest.
  TILESET_HOUSE = "indoor",
  TILESET_PLAYERS_HOUSE = "indoor",
  TILESET_PLAYERS_ROOM = "indoor",
  TILESET_TRADITIONAL_HOUSE = "indoor",
  TILESET_POKECENTER = "indoor",
  TILESET_MART = "indoor",
  TILESET_LAB = "indoor",
  TILESET_GATE = "indoor",
  TILESET_FACILITY = "indoor",
  TILESET_TRAIN_STATION = "indoor",
  TILESET_RADIO_TOWER = "indoor",
  TILESET_LIGHTHOUSE = "indoor",
  -- The rooms the Elite Four and the Champion stand in.  A boss outranks the
  -- room (BOSS_KIND, below), so these only decide what a battle in one of
  -- those rooms that is NOT the boss looks like -- which on the cart is
  -- nothing, and on a romhack is a hallway rather than a grass field.
  TILESET_ELITE_FOUR_ROOM = "indoor",
  TILESET_CHAMPIONS_ROOM = "indoor",

  TILESET_PORT = "port",
  TILESET_MANSION = "mansion",
  -- Goldenrod's and Celadon's Game Corners.  `club` is the Fighting Dojo art
  -- on Red, which is the closest thing in the pack to a room full of people.
  TILESET_GAME_CORNER = "club",
  -- Sprout Tower, the Tin Tower and the Burned Tower -- and they take the
  -- PLAIN interior, not the `tower` slot.
  --
  -- `tower.png` is not a picture of a tower.  It is the same 10 Indoors art
  -- as `indoor`, `club`, `mansion`, `museum` and `ship` -- byte for byte --
  -- with one thing done to it: GRAYMON, at 0.80 strength, baked in by
  -- recolor.py.  And GRAYMON is a Gen 1 fact.  Red routes its tower by
  -- `FieldDefaults.byTileset = { CEMETERY = "GRAYMON" }`, so the Pokemon
  -- Tower wears a mourning palette rather than Lavender's roofs.
  --
  -- Gold has neither a CEMETERY tileset nor a GRAYMON, and does not give a
  -- tower a palette of its own at all: its map colours come from
  -- `environments[environment][daytime]` (RomExtractorGen2:678-701), which
  -- is shared by every INDOOR map on the cart.  So the faithful answer for
  -- Sprout Tower really is the same room a Pokemon Center gets -- and
  -- Lavender's grey-violet on a Johto pagoda is just wrong.
  --
  -- Crystal's `specialTilesets` is the list of tilesets the cart DOES give
  -- their own colours to, and it is six: the Ice Path, the mansion, the
  -- Radio Tower, houses, the Battle Tower and the PokeCom Center.  No tower
  -- is on it.
  TILESET_TOWER = "indoor",

  TILESET_CAVE = "cave",
  TILESET_DARK_CAVE = "cave",
  -- The Ice Path takes 15 Snow Cave rather than the plain cave: the art is
  -- an ice cave, and on this cart nobody else is using it.
  TILESET_ICE_PATH = "ice_path",
  TILESET_UNDERGROUND = "cave",
  TILESET_RUINS_OF_ALPH = "cave",

  -- The National Park, which is outdoors and has grass in it.
  TILESET_PARK = "field",
  TILESET_FOREST = "forest",

  -- Crystal's eight extra tilesets.  The five WORD_ROOMs are the Ruins of
  -- Alph puzzle chambers, which are underground.
  TILESET_BATTLE_TOWER_OUTSIDE = "town",
  TILESET_BATTLE_TOWER_INSIDE = "indoor",
  TILESET_POKECOM_CENTER = "indoor",
  TILESET_BETA_WORD_ROOM = "cave",
  TILESET_HO_OH_WORD_ROOM = "cave",
  TILESET_KABUTO_WORD_ROOM = "cave",
  TILESET_OMANYTE_WORD_ROOM = "cave",
  TILESET_AERODACTYL_WORD_ROOM = "cave",
}

-- Per-map overrides, checked before the tileset -- Gold's twin of MAP_SLOT.
--
-- Four things the header cannot say, each of which left a finished backdrop
-- with nothing pointing at it:
--
--   the gyms       Gold has no GYM tileset.  A gym sits on whatever tileset
--                  its town uses, so without this a gym TRAINER got the
--                  town's field and the Gym scene went unreached.  (The
--                  LEADER was always fine: a boss outranks the room.)
--   the Fast Ship  the S.S. Aqua, which is the S.S. Anne's counterpart and
--                  the reason a `ship` and a `deck` scene exist at all.
--   Mt Silver      `SILVER_CAVE_OUTSIDE` is the mountainside, not a cave --
--                  which is what 6 Craggy is a painting of, and the only
--                  outdoor crag in the game now that Indigo Plateau has no
--                  outdoor map of its own.
--   the Den        Clair's second test is a cave with water in it.
--
-- Gym names are listed rather than matched on a `_GYM` suffix: Blackthorn's
-- two floors are `BLACKTHORN_GYM_1F` / `_2F` and Blaine's is `SEAFOAM_GYM`,
-- so a suffix rule would miss three of the sixteen and silently.
local MAP_SLOT_GEN2 = {
  -- Johto's eight
  VIOLET_GYM = "gym", AZALEA_GYM = "gym", GOLDENROD_GYM = "gym",
  ECRUTEAK_GYM = "gym", CIANWOOD_GYM = "gym", OLIVINE_GYM = "gym",
  MAHOGANY_GYM = "gym",
  BLACKTHORN_GYM_1F = "gym", BLACKTHORN_GYM_2F = "gym",
  -- Kanto's eight.  Blaine's gym moved to the Seafoam Islands.
  PEWTER_GYM = "gym", CERULEAN_GYM = "gym", VERMILION_GYM = "gym",
  CELADON_GYM = "gym", FUCHSIA_GYM = "gym", SAFFRON_GYM = "gym",
  SEAFOAM_GYM = "gym", VIRIDIAN_GYM = "gym",

  -- The S.S. Aqua.  1F is the deck level -- open air, and the reason the
  -- Gen 1 arm gives the S.S. Anne's bow and top walkway their own slot --
  -- while the cabins and the hold below are the panelled interior.
  FAST_SHIP_1F = "deck",
  FAST_SHIP_B1F = "ship",
  FAST_SHIP_CABINS_NNW_NNE_NE = "ship",
  FAST_SHIP_CABINS_SW_SSW_NW = "ship",
  FAST_SHIP_CABINS_SE_SSE_CAPTAINS_CABIN = "ship",

  -- The mountainside outside Silver Cave, where RED is.
  SILVER_CAVE_OUTSIDE = "plateau",

  -- Water in a cave, which is neither sea nor pond: no sky, so the Sea scene
  -- (mostly sky) is wrong and the Lake is wrong for the same reason.  Red
  -- reaches 3 Underwater through Seafoam and Cerulean Cave; Johto has rather
  -- more of it, and it was going unused.
  DRAGONS_DEN_B1F = "water_cave",
  TOHJO_FALLS = "water_cave",
  SLOWPOKE_WELL_B1F = "water_cave",
  SLOWPOKE_WELL_B2F = "water_cave",
  UNION_CAVE_B2F = "water_cave",
  -- The Whirl Islands are a sea cave throughout, and the chamber at the
  -- bottom of them is where Lugia is.
  WHIRL_ISLAND_B1F = "water_cave",
  WHIRL_ISLAND_B2F = "water_cave",
  WHIRL_ISLAND_LUGIA_CHAMBER = "water_cave",
  WHIRL_ISLAND_CAVE = "water_cave",

  -- The Ruins of Alph's outside is a walled dig under open sky, not a
  -- chamber: `TILESET_RUINS_OF_ALPH` sends the whole landmark underground,
  -- and this is the one map of it that is not.
  RUINS_OF_ALPH_OUTSIDE = "field",

  -- The Burned Tower's basement is where the three beasts are, and it is a
  -- collapsed pit rather than a room -- the floor above it is the interior.
  BURNED_TOWER_B1F = "cave",
}

-- The header's own classification, used when the tileset is not in the table
-- above -- a romhack's tileset, or one a later engine adds.  Red has nothing
-- like this: its arm falls back to NOT_A_BUILDING, which is a guess.
local ENVIRONMENT_SLOT_GEN2 = {
  TOWN = "town",
  ROUTE = "field",
  INDOOR = "indoor",
  CAVE = "cave",
  GATE = "indoor",
  DUNGEON = "cave",
}

-- Which town's colour a map takes.
--
-- Keyed on the map's GROUP, not on its landmark, and that is not an
-- implementation detail -- it is what the cart does.  A town variant is a
-- roof recolour (see recolor.py), and Gold's roofs come from
-- `RoofPals[group]`: one morn/day pair and one night pair per map group,
-- copied over PAL_BG_ROOF's colours 1 and 2
-- (src/import/RomExtractorGen2.lua:718-726, Palettes.bgSet's roof block).
-- So a group IS a roof colour, and every map in it -- the town, its gym, its
-- routes -- shares one.
--
-- Red does the same thing one level down: `roofByMapIndex` is per city map,
-- because Red's eleven cities are eleven maps.  Gold has 26 groups, 22 of
-- which contain a named town, and those 22 are these.
--
-- The four groups with no town in them (9, 15, 19, 20 -- route and dungeon
-- groups) have no entry and take the plain scene, which is right: there is no
-- town there to be the colour of.
local GROUP_VARIANT_GEN2 = {
  -- Johto
  [24] = "new_bark",     [26] = "cherrygrove",  [10] = "violet",
  [8]  = "azalea",       [11] = "goldenrod",    [4]  = "ecruteak",
  [1]  = "olivine",      [22] = "cianwood",     [2]  = "mahogany",
  [5]  = "blackthorn",
  -- Kanto
  [13] = "pallet",       [23] = "viridian",     [14] = "pewter",
  [7]  = "cerulean",     [12] = "vermilion",    [21] = "celadon",
  [17] = "fuchsia",      [25] = "saffron",      [6]  = "cinnabar",
  [18] = "lavender",     [16] = "indigo",
}

-- Where a Gen 2 town's recoloured art lives.
--
-- Under `gen2/` rather than beside Red's eleven folders, because the roofs
-- really are different colours: Gold repaints Kanto, so its Cerulean is not
-- Red's Cerulean, and a shared folder would put Red's roof pair on Gold's
-- town.  recolor.py writes this set from a Gold import's own palette data.
--
-- Absent is the ordinary case and is handled rather than guarded: a folder
-- that is not there loads nothing, the variant block falls through, and the
-- town gets the plain scene.  Dropping the folders in is then the whole
-- change -- no edit here.
local GEN2_VARIANT_DIR = "gen2/"

-- Sea or pond, by landmark, and hand-classified from the geography exactly as
-- the Gen 1 arm's OCEAN_MAP is -- nothing in the map data distinguishes a sea
-- tile from a lake tile on either cart.  Everything not named here is inland
-- and gets the Lake.
--
-- Johto's coast is the west and the south: Olivine and Cianwood face the open
-- water, Routes 40 and 41 are the crossing between them, and Routes 26 to 28
-- run along the sea back to Kanto.  Kanto's is the same south and east coast
-- the Gen 1 arm names, because it is the same coast.
local OCEAN_LANDMARK_GEN2 = {
  -- Johto
  LANDMARK_OLIVINE_CITY = true,
  LANDMARK_ROUTE_40 = true,
  LANDMARK_ROUTE_41 = true,
  LANDMARK_CIANWOOD_CITY = true,
  LANDMARK_ROUTE_27 = true,
  LANDMARK_ROUTE_28 = true,
  LANDMARK_FAST_SHIP = true,
  -- Kanto -- the same coast OCEAN_MAP names, by landmark instead of by map
  LANDMARK_PALLET_TOWN = true,
  LANDMARK_VERMILION_CITY = true,
  LANDMARK_CINNABAR_ISLAND = true,
  LANDMARK_FUCHSIA_CITY = true,
  LANDMARK_ROUTE_12 = true,
  LANDMARK_ROUTE_13 = true,
  LANDMARK_ROUTE_19 = true,
  LANDMARK_ROUTE_20 = true,
  LANDMARK_ROUTE_21 = true,
}

-- The bosses, by trainer class.
--
-- Sixteen gym leaders take the Leader scene and their town's colour, which is
-- the whole point of a town variant: Falkner's gym is Violet's and Whitney's
-- is Goldenrod's, the same way Misty's is Cerulean's on Red.
--
-- The Elite Four is a different four people, and the six boss scenes are six
-- FireRed TERRAIN paintings that FireRed happened to hand to Kanto's -- so
-- they are simply re-dealt.  Bruno and Lance are in both games and keep the
-- scene each was drawn for; the three whose owners do not exist here
-- (Giovanni's snowfield, Lorelei's ice cave, Agatha's desert) are free, and
-- go to the three fights that had none.  See GEN2_SLOT_FILE for which file
-- each of these names.
--
--     WILL      Space          the psychic gets the starfield
--     KOGA      Desert
--     BRUNO     Snow Mountain  his own, in both games
--     KAREN     Snow Cave
--     CHAMPION  Volcano        Lance's own; he is the Champion here
--     RED       Snow           the summit of Mt Silver
--
-- So every one of the twenty backdrops has a home on a Gen 2 boot, exactly as
-- it does on a Gen 1 one, and no new art was needed for any of it.
local BOSS_CLASS_GEN2 = {
  -- Johto's eight
  FALKNER = "leader", BUGSY = "leader", WHITNEY = "leader",
  MORTY = "leader", CHUCK = "leader", JASMINE = "leader",
  PRYCE = "leader", CLAIR = "leader",
  -- Kanto's eight.  BLUE is one of them: he has Viridian's gym here.
  BROCK = "leader", MISTY = "leader", LT_SURGE = "leader",
  ERIKA = "leader", JANINE = "leader", SABRINA = "leader",
  BLAINE = "leader", BLUE = "leader",
  -- the Elite Four, then the Champion
  WILL = "will", KOGA = "koga", BRUNO = "bruno", KAREN = "karen",
  CHAMPION = "lance",
  -- the fight at the top of Mt Silver
  RED = "red",
}

-- A boss slot whose file is missing falls to the Leader scene rather than to
-- the room behind them -- a hallway would read as the mod having missed them.
--
-- Nothing reaches this today: every boss slot on both generations resolves to
-- a file that ships. It is the guard for a partial pack, which the asset
-- loader is built to allow.
local BOSS_FALLBACK = {
  will = "leader", koga = "leader", karen = "leader", red = "leader",
  lorelei = "leader", bruno = "leader", agatha = "leader",
  lance = "leader", giovanni = "leader", champion = "leader",
}

-- A boss's own scene outranks the room, the same way water does.
local BOSS_KIND = {
  leader = true, giovanni = true, lorelei = true, bruno = true,
  agatha = true, lance = true, champion = true,
  -- Gen 2's own four, plus the fight on Mt Silver.
  will = true, koga = true, karen = true, red = true,
}

-- Gold's live world.  `game.overworld` is Red's singleton and does not exist
-- here; `game.world` is the World instance, and it is read fresh every time
-- because a battle outlives none of it.
local function gen2World(battle)
  local game = battle and battle.game
  return game and game.world or nil
end

-- What the world was doing when the battle STARTED, recorded there rather
-- than asked here.
--
-- Both facts are stable for the length of a fight and neither is readable
-- once it has begun: `playerState` keeps saying "surfing" (which is right --
-- you resume surfing afterwards) but a fished encounter leaves no trace at
-- all, because Gold's fishing goes through `World:startBattle({ wild = ... })`
-- with nothing to say it was fished.  This is the same thing the Gen 1 arm
-- does by stashing `kaHooked` on the battle at `newWild` time, moved to the
-- one call Gold builds every battle through.
local ARENA_ENCOUNTER = "__gen1ArenaEncounter"

local function gen2Encounter(battle)
  local world = gen2World(battle)
  return world and rawget(world, ARENA_ENCOUNTER) or nil
end

local function kindSlotGen2(battle)
  local model = battle and battle.battle
  local encounter = gen2Encounter(battle)

  if model and model.trainer then
    local class = model.trainer.class or model.trainer.classId
    local boss = class and BOSS_CLASS_GEN2[class]
    if boss then return boss end
    if encounter and encounter.surfing then return "trainer_surf" end
    return "trainer"
  end

  -- Gold has no Safari Zone and no link battle on this path, so the two kinds
  -- the Gen 1 arm answers for them cannot arise and are not tested for.
  if encounter then
    if encounter.fished then return "fishing" end
    if encounter.surfing then return "surf" end
    -- A battle the world started without rolling one -- a script's Sudowoodo,
    -- the roamers, a legendary -- is the same thing Red calls `static`.
    if not encounter.rolled then return "static" end
  end
  return "wild"
end

local function currentMapDefGen2(battle)
  local world = gen2World(battle)
  local map = world and world.map
  return map and map.def or nil
end

local function currentLandmarkGen2(battle)
  local world = gen2World(battle)
  if not (world and type(world.currentLandmarkId) == "function") then
    return nil
  end
  local ok, id = pcall(world.currentLandmarkId, world)
  return ok and id or nil
end

-- The place slot, from the header rather than from a guess.  Tileset first,
-- because it is the more specific of the two; the environment behind it, so
-- an unmapped tileset still lands somewhere sensible instead of on `default`.
local function slotForGen2(def)
  if not def then return nil end
  local override = def.id and MAP_SLOT_GEN2[def.id]
  if override then return override end
  local slot = def.tileset and TILESET_SLOT_GEN2[def.tileset]
  if slot then
    -- Routes and towns share the three overworld tilesets exactly as they
    -- share OVERWORLD on Red.  Red separates them with a map index; Gold's
    -- header says which it is.
    if slot == "field" and def.environment == "TOWN" then return "town" end
    return slot
  end
  return def.environment and ENVIRONMENT_SLOT_GEN2[def.environment] or nil
end

local function kindSlot(battle)
  if gen2() then return kindSlotGen2(battle) end
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
  if gen2() then
    local def = currentMapDefGen2(battle)
    return def and def.tileset or nil
  end
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
  if gen2() then
    local def = currentMapDefGen2(battle)
    return def and def.id or nil
  end
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
  local def, slot
  if gen2() then
    def = currentMapDefGen2(battle)
    slot = slotForGen2(def)
  else
    local game = battle.game
    local overworld = game and game.overworld
    def = overworld and overworld.map and overworld.map.def
    slot = slotFor(mapId, def)
  end
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
  -- Which town's colour, if any.  Red asks the map id; Gold asks the header's
  -- landmark, which answers for every map in the town rather than for the two
  -- that were hand-listed.
  local variant
  if gen2() then
    local def = currentMapDefGen2(battle)
    local tag = def and def.group and GROUP_VARIANT_GEN2[def.group]
    variant = tag and (GEN2_VARIANT_DIR .. tag) or nil
  else
    variant = MAP_VARIANT[currentMapId(battle) or ""]
  end
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
    local open
    if gen2() then
      open = OCEAN_LANDMARK_GEN2[currentLandmarkGen2(battle) or ""]
    else
      open = OCEAN_MAP[currentMapId(battle) or ""]
    end
    img = loadImage(layout, open and "sea" or "lake")
    if img then return img end
  elseif BOSS_KIND[kind] then
    img = loadImage(layout, kind)
    if img then return img end
    -- A boss whose own scene has not been drawn takes the Leader scene rather
    -- than the room behind them.  Nothing on Red reaches this -- every boss
    -- slot there has a file -- but Will, Koga, Karen and RED have none yet,
    -- and a hallway would read as the mod having missed them.
    local instead = BOSS_FALLBACK[kind]
    if instead then
      img = loadImage(layout, instead)
      if img then return img end
    end
  end

  if place then
    img = loadImage(layout, place)
    if img then return img end
  end
  img = loadImage(layout, kind)
  if img then return img end
  -- The last guess before `default`: is this the inside of a building?
  --
  -- Red has to infer it from the tileset, because nothing in its map data
  -- says.  Gold's header does say -- so on a Gen 2 boot this asks the
  -- environment and gets an answer rather than a guess, and a tileset nobody
  -- has mapped still puts a wild encounter in the right kind of room.
  if gen2() then
    local def = currentMapDefGen2(battle)
    local env = def and def.environment
    if env == "INDOOR" or env == "GATE" then
      img = loadImage(layout, "indoor")
      if img then return img end
    end
  else
    local tileset = currentTileset(battle)
    if tileset and not NOT_A_BUILDING[tileset] then
      img = loadImage(layout, "indoor")
      if img then return img end
    end
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
-- ------- and it is painted with NO SHADER BOUND
--
-- Reported three times as "the battle is all greyscale", and the screenshot
-- says it in one line: every pixel on the screen is one of three DMG shades,
-- and the ONE thing still in colour is the EXP bar -- which is the one thing
-- that calls `love.graphics.setShader()` before it paints (Gen1BattleUI
-- xpbar.lua, "exempt from the palette pass").
--
-- These draws are substituted INTO somebody else's draw, from a shim on
-- `love.graphics.rectangle`, so whatever shader the caller had bound is still
-- bound when they run.  For a fill that does not matter -- a flat colour
-- through the shade remap is still a flat colour.  For a PHOTOGRAPH it is the
-- whole picture: PaletteFX's shader answers every pixel with one of four
-- palette entries chosen off its RED channel, so a FireRed terrain scene
-- comes back as four greys and this mod reads as if it never ran.
--
-- So the shader is put down for the length of the paint and handed back
-- exactly as it was.  Not cleared and left cleared: this is the middle of the
-- cart's own draw, and the shade remap after it is the cart's.
local function withoutShader(draw)
  local g = love.graphics
  local had = g.getShader and g.getShader() or nil
  if had then g.setShader() end
  local ok, err = pcall(draw)
  if had then g.setShader(had) end
  if not ok then error(err, 0) end
end

local function paintField()
  if devOption("field_test") then
    love.graphics.setColor(1, 0, 1, 1)
    realRectangle("fill", 0, 0, pendingW, pendingH)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  withoutShader(function()
    drawCover(pendingImage, pendingW, pendingH)
  end)
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
  -- where that bar is, at the cover's own scale.  Through no shader, for the
  -- reason under paintField: this is the same photograph, and bars in four
  -- greys beside a field in colour would be worse than either.
  withoutShader(function()
    for i, r in ipairs(rects) do
      local quad = cut.quads[i]
      if quad then g.draw(img, quad, r.x, r.y, 0, scale, scale) end
    end
  end)
end

-- Published for tests/arenavoxel_test.lua: the one decision that stands this
-- whole mod down, and the one that is silent when it is wrong.
-- Published for tests/arenashader_test.lua: the guard every full-colour paint
-- in this file goes through, and the one whose absence is invisible until a
-- screenshot comes back in four greys.
mod.exports.paintsWithoutShader = withoutShader

mod.exports.worldTaken = worldTaken
mod.exports.bleedRects = bleedRects
mod.exports.bleedCover = coverFit

-- The Gen 2 selection, for tests.  All of it is pure -- a map header and a
-- battle in, a slot name out -- which is exactly the part that can be wrong
-- and exactly the part a headless harness can drive.
mod.exports.gen2SlotFor = slotForGen2
mod.exports.gen2KindSlot = kindSlotGen2
mod.exports.gen2Tilesets = TILESET_SLOT_GEN2
mod.exports.gen2Environments = ENVIRONMENT_SLOT_GEN2
mod.exports.gen2GroupVariant = GROUP_VARIANT_GEN2
mod.exports.gen2SlotFile = GEN2_SLOT_FILE
mod.exports.gen2BossClass = BOSS_CLASS_GEN2
mod.exports.gen2Ocean = OCEAN_LANDMARK_GEN2
mod.exports.gen2MapSlots = MAP_SLOT_GEN2

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

-- Exposed for the headless suite: it is a pure question about one image --
-- which box of it is the mon rather than the space around it -- and getting
-- it wrong lays a white rectangle in the wrong place over a picture.
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

mod.exports.picPaperBox = picPaperBox

-- ------- the paper as the PIC'S OWN SHAPE
--
-- A rectangle is the wrong shape for this and shipping one is what produced
-- the second half of the report: "there shouldn't be the big black or white
-- box behind all that stuff".  A mon is not a rectangle, so paper the size of
-- its bounding box is a sticker with the mon printed in the middle of it.
--
-- What is actually wanted is the paper the CART had under the pic and nowhere
-- else: the holes inside the silhouette filled, and the space around it left
-- as the picture.  So the shape is measured off the art and drawn as an
-- image, not as a fill.
--
-- ------- why there are holes at all
--
-- Gen 2's pics are matted on the way out of the ROM
-- (ImageWriter.matteColor0, called by RomExtractorGen2:writeCompressedPic):
-- the white AROUND the mon is flooded to transparent from the four edges of
-- the frame, and the white INSIDE it is meant to survive.  That flood leaks
-- wherever the art runs off the edge of its own frame -- the player's
-- back-pic is bottom-aligned and cut by the frame, so a white pixel on the
-- bottom row is a seed, and the flood walks up through the trainer and takes
-- his shirt with it.  The result is a trainer you can see the arena through,
-- which is exactly what was reported and exactly what a white field used to
-- hide.
--
-- ------- so the frame closes the silhouette
--
-- The flood is run again here, backwards, with one rule the extractor's did
-- not have: a border pixel is only OUTSIDE if it lies past the ink on its own
-- edge.  Wherever the art runs into the frame, the frame is treated as the
-- art's own edge and the flood does not start there.
--
--   * the back-pic, cut off at the bottom: the bottom row has ink at both
--     ends, so nothing between them seeds, and the shirt comes back.
--   * a pic with padding under it: the bottom row has no ink at all, so the
--     whole row seeds and the padding stays picture.
--
-- Everything transparent the flood does not reach is inside the mon, and that
-- is the paper.  A pic with no holes builds no image and costs one readback.
--
-- Drawn through whatever palette the engine has bound for the pic, as white,
-- so it lands on colour 0 -- the mon's own white, which is what the hole was.
local paperImage = setmetatable({}, { __mode = "k" })

-- The first and last index along one edge that carries ink, or nil when the
-- edge is empty.  `at(i)` answers whether index i is opaque.
local function edgeSpan(count, at)
  local first, last
  for i = 0, count - 1 do
    if at(i) then
      if not first then first = i end
      last = i
    end
  end
  return first, last
end

local function buildPaperImage(img)
  if not (love.image and type(love.image.newImageData) == "function") then
    return false
  end
  local w, h = img:getDimensions()
  if w < 1 or h < 1 or w > PAPER_MAX_SIDE or h > PAPER_MAX_SIDE then
    return false
  end
  local data = readPic(img)

  -- Same readback geometry check measurePic makes, and for the same reason: a
  -- host that ignored the pinned dpiscale hands back a whole-number multiple
  -- of the pic, and reading the pic's own w by h out of it reads a corner.
  local dw, dh = w, h
  if type(data.getDimensions) == "function" then
    local ok, gw, gh = pcall(data.getDimensions, data)
    if ok and tonumber(gw) and tonumber(gh) then dw, dh = gw, gh end
  end
  if dw < w or dh < h or dw % w ~= 0 or dh % h ~= 0 or dw / w ~= dh / h then
    return false
  end
  local ratio = dw / w
  local half = math.floor(ratio / 2)

  local opaque, colors, nColors = {}, {}, 0
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x * ratio + half, y * ratio + half)
      if a > 0.5 then
        opaque[row + x] = true
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
  -- Replacement art that is already coloured needs none of this: its colour 0
  -- is not a hole, it is a colour.  The same four-shade test the Gen 1 arm
  -- uses, and the same reason.
  if nColors == 0 or nColors > PAPER_MAX_COLORS then return false end

  local outside, qx, qy, head = {}, {}, {}, 1
  local function push(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local key = y * w + x
    if outside[key] or opaque[key] then return end
    outside[key] = true
    qx[#qx + 1], qy[#qy + 1] = x, y
  end
  local function seedRow(y)
    local first, last = edgeSpan(w, function(x) return opaque[y * w + x] end)
    for x = 0, w - 1 do
      if not first or x < first or x > last then push(x, y) end
    end
  end
  local function seedColumn(x)
    local first, last = edgeSpan(h, function(y) return opaque[y * w + x] end)
    for y = 0, h - 1 do
      if not first or y < first or y > last then push(x, y) end
    end
  end
  seedRow(0)
  seedRow(h - 1)
  seedColumn(0)
  seedColumn(w - 1)
  while head <= #qx do
    local x, y = qx[head], qy[head]
    head = head + 1
    push(x - 1, y)
    push(x + 1, y)
    push(x, y - 1)
    push(x, y + 1)
  end

  local filled = 0
  local out = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      if not (opaque[row + x] or outside[row + x]) then
        out:setPixel(x, y, 1, 1, 1, 1)
        filled = filled + 1
      end
    end
  end
  if filled == 0 then return false end
  local image = love.graphics.newImage(out)
  if type(image.setFilter) == "function" then
    pcall(image.setFilter, image, "nearest", "nearest")
  end
  return image
end

-- ------- cutting a pic out of its square
--
-- The paper above is for art that ALREADY has transparency around it: it puts
-- back the holes the mon's own white left inside its body.  A cart pic is the
-- other case entirely, and it is the one behind "trainers have white box
-- around them in battle intros".
--
-- Gold's extracted trainer and mon pics are 2bpp with the field BAKED IN: the
-- whole square is opaque and the space around the figure is shade 0.  The
-- remap keeps that (`vec4(rgb, px.a)` -- shade 0 becomes colour 0, which is
-- white for a trainer palette, and stays OPAQUE), so on the cart it is
-- invisible against the white battle field and over a BACKDROP it is a white
-- box.
--
-- The fix asked for is to CUT THE FIGURE OUT of the square rather than
-- recolour the square: "can you just cut them out of that square. Not replace
-- the color."  Which is right -- a recoloured square is still a square, and
-- picking its colour means guessing at the picture behind it.
--
-- So: the same flood fill, seeded on the pic's own FIELD SHADE instead of on
-- transparency.  What the flood reaches from the edges is the space around the
-- figure and is cut to alpha 0; what it cannot reach is enclosed -- a
-- trainer's white shirt, the white of an eye -- and is left exactly as it is.
-- That is the whole difference between this and keying the shader, which would
-- take the shirt with it.
--
-- Only for art that is the cart's: fully opaque, and few enough colours to be
-- a 2bpp pic.  Replacement art already carries its own alpha and its colour 0
-- "is not a hole, it is a colour", so it is left alone by the same test the
-- paper uses.
local cutoutImage = setmetatable({}, { __mode = "k" })

local function buildCutout(img)
  if not (love.image and type(love.image.newImageData) == "function") then
    return false
  end
  local w, h = img:getDimensions()
  if w < 1 or h < 1 or w > PAPER_MAX_SIDE or h > PAPER_MAX_SIDE then
    return false
  end
  local data = readPic(img)
  local dw, dh = w, h
  if type(data.getDimensions) == "function" then
    local ok, gw, gh = pcall(data.getDimensions, data)
    if ok and tonumber(gw) and tonumber(gh) then dw, dh = gw, gh end
  end
  if dw < w or dh < h or dw % w ~= 0 or dh % h ~= 0 or dw / w ~= dh / h then
    return false
  end
  local ratio = dw / w
  local half = math.floor(ratio / 2)

  -- One pass: every pixel's colour, and the lightest of them.  The remap keys
  -- off the RED channel (GbcPalette's shader reads `px.r`), so lightest by red
  -- is the same shade the hardware would call 0.
  local px, colors, nColors = {}, {}, 0
  local field, fieldRed = nil, -1
  local tooMany = false
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x * ratio + half, y * ratio + half)
      -- A pic that already has transparency is not this case: it is either
      -- replacement art or a pic the paper arm above already handles.
      if a <= 0.5 then return false end
      local key = math.floor(r * 255 + 0.5) * 65536
                + math.floor(g * 255 + 0.5) * 256
                + math.floor(b * 255 + 0.5)
      px[row + x] = key
      if not (colors[key] or tooMany) then
        colors[key] = true
        nColors = nColors + 1
        if nColors > PAPER_MAX_COLORS then tooMany = true end
      end
      if r > fieldRed then field, fieldRed = key, r end
    end
  end
  -- A single-colour square is not a picture with a field around it.
  if nColors < 2 or not field then return false end

  -- ------- and the same square, in art that is not 2bpp
  --
  -- Reported as "some trainers didn't appear with the background removed",
  -- with a screenshot of a SAILOR in a white box beside a player whose box
  -- was gone.  The count above is why: four colours is a cart pic exactly,
  -- and a replacement trainer -- skin, bandana, shirt, shading -- has a dozen.
  -- Every one of them was refused and cached as refused, so it kept its
  -- square for the whole battle while the cart's own pics were cut.
  --
  -- The count was standing in for a question it only answers by accident:
  -- IS THIS A FIGURE IN A FIELD.  A cart pic is, and has four colours; a
  -- photograph is not, and has hundreds.  Asked directly, the answer is the
  -- BORDER -- a figure standing in a square has the field, and only the
  -- field, all the way round it.  Replacement art that bleeds to its own edge
  -- does not, and is still left alone.
  --
  -- Kept as a second gate rather than replacing the first, because the first
  -- is free and true of every pic the cart ships: a 2bpp pic is let through
  -- on the count alone, exactly as before, and nothing about those changes.
  if tooMany then
    for x = 0, w - 1 do
      if px[x] ~= field or px[(h - 1) * w + x] ~= field then return false end
    end
    for y = 0, h - 1 do
      local row = y * w
      if px[row] ~= field or px[row + w - 1] ~= field then return false end
    end
  end

  -- `opaque` here means "part of the figure", so the flood fill below is the
  -- one above with transparency swapped for the field shade.
  local opaque = {}
  for i = 0, w * h - 1 do
    if px[i] ~= field then opaque[i] = true end
  end

  local outside, qx, qy, head = {}, {}, {}, 1
  local function push(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local key = y * w + x
    if outside[key] or opaque[key] then return end
    outside[key] = true
    qx[#qx + 1], qy[#qy + 1] = x, y
  end
  for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
  for y = 0, h - 1 do push(0, y); push(w - 1, y) end
  while head <= #qx do
    local x, y = qx[head], qy[head]
    head = head + 1
    push(x - 1, y)
    push(x + 1, y)
    push(x, y - 1)
    push(x, y + 1)
  end

  -- Nothing reachable is nothing to cut: a pic whose field the edges cannot
  -- see is not sitting in a square and is left alone.
  local cut = 0
  for i = 0, w * h - 1 do
    if outside[i] then cut = cut + 1 end
  end
  if cut == 0 then return false end

  local out = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local r, g, b = data:getPixel(x * ratio + half, y * ratio + half)
      -- Colour is copied even where it is cut, so a host that ignores alpha
      -- shows the pic it always did rather than a black hole.
      out:setPixel(x, y, r, g, b, outside[row + x] and 0 or 1)
    end
  end
  local image = love.graphics.newImage(out)
  if type(image.setFilter) == "function" then
    pcall(image.setFilter, image, "nearest", "nearest")
  end
  return image
end

-- ------- asked in the draw, built between frames
--
-- Building a cut-out READS the pic (a scratch canvas, bound and drawn into)
-- and then makes a WHOLE NEW TEXTURE.  Both of those inside `drawPic` -- with
-- the battle's canvas bound and the frame half-painted -- is what 0.32.62
-- shipped, and it is what a GLES driver refuses: "on iOS, the image gets
-- flipped, on android it just crashes".  A readback that disagrees about
-- orientation stops being a misplaced hole and becomes the whole sprite upside
-- down; a mid-pass render-target switch is a crash outright.
--
-- So the two halves are separated in time, which is what the note at the draw
-- site said the right build was:
--
--   in the draw   `cutoutFor` is a CACHE READ.  A pic it has not seen is
--                 remembered as wanted and the original is drawn, so the very
--                 first frame a trainer appears on is the cart's own square
--                 and nothing else changes.
--   between       `Arena.buildQueuedCutouts` runs on `core.update`, where no
--   frames        canvas is bound and no transform is in effect, and builds
--                 what was asked for.  From the next frame the cut-out is
--                 there.
--
-- One pic per update, deliberately.  A battle asks for at most two and a
-- readback is not free; draining a whole queue on one frame is a stutter at
-- the exact moment the intro is sliding.
local cutoutWanted, cutoutQueue = setmetatable({}, { __mode = "k" }), {}

local function cutoutFor(img)
  local hit = cutoutImage[img]
  if hit ~= nil then return hit or nil end
  if not cutoutWanted[img] then
    cutoutWanted[img] = true
    cutoutQueue[#cutoutQueue + 1] = img
  end
  return nil
end

-- Exposed for the headless suite for the same reason picPaperImage is: it is a
-- pure question about one image -- which of its pixels are the square around
-- the figure -- and getting it wrong cuts a hole in a picture.  This is the
-- BUILD, and calling it is what the update below does; the draw calls
-- `cutoutFor` instead and never reaches here.
local function picCutoutImage(img)
  if cutoutImage[img] == nil then
    local ok, built = pcall(buildCutout, img)
    cutoutImage[img] = (ok and built) or false
    if not ok then
      mod.log:warn("could not cut a pic from its square: %s", tostring(built))
    end
  end
  return cutoutImage[img] or nil
end

-- Called from `core.update`.  Returns the image it built, or nil when there
-- was nothing waiting -- which is what the test drives.
local function buildQueuedCutouts()
  local img = table.remove(cutoutQueue, 1)
  if not img then return nil end
  cutoutWanted[img] = nil
  picCutoutImage(img)
  return img
end

mod.exports.picCutoutImage = picCutoutImage
-- The two halves, published for the headless suite: the test drives them in
-- the order the game does -- ask in a draw, build on an update -- and asserts
-- that the draw itself never builds.
mod.exports.cutoutFor = cutoutFor
mod.exports.buildQueuedCutouts = buildQueuedCutouts
mod.exports.cutoutQueued = function() return #cutoutQueue end

-- Exposed for the headless suite the same way picPaperBox is: it is a pure
-- question about one image -- which pixels of it are a hole through the mon
-- -- and getting it wrong paints over a picture.
local function picPaperImage(img)
  if paperImage[img] == nil then
    local ok, built = pcall(buildPaperImage, img)
    paperImage[img] = (ok and built) or false
    if not ok then
      mod.log:warn("could not shape a pic's paper: %s", tostring(built))
    end
  end
  return paperImage[img] or nil
end

mod.exports.picPaperImage = picPaperImage

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

-- ------------------------------------------- what started this battle, on Gold
--
-- Red keeps three of these facts on the battle already: `kind`, `oppClass`
-- and a `checkpointOrigin` that says whether the encounter was rolled, plus
-- the surfing flag still set on the player underneath.  This mod only has to
-- add the fourth, which it does by stashing `hooked` on the way through
-- `newWild`.
--
-- Gold keeps none of them past the moment the battle opens.  `World:
-- startBattle({ wild = ... })` is the one call every wild encounter goes
-- through -- rolled, fished, scripted and roaming alike -- and it is handed a
-- built Mon and nothing about where it came from.  So the facts are recorded
-- there, at the one instant all of them are still true, and read back off the
-- world for the length of the fight.
--
-- Two are read directly at that instant:
--   surfing  `FieldMoves.isSurfing(world.playerState)`, which is Gold's own
--            test and the one its field-move code uses.
--   rolled   whether the world got here through its own encounter roll.
--
-- The third has to be caught earlier.  A fished encounter is indistinguishable
-- at `startBattle` -- both the animated cast (`useRod` -> `beginFishing`) and
-- the direct path (`tryFishing`) call it with a plain wild Mon -- so
-- `rollFishing`, which both go through and nothing else does, leaves a flag
-- for the next battle to claim.
local function installGen2Encounter()
  local okWorld, World = pcall(require, "src.world.gen2.World")
  if not (okWorld and type(World) == "table") then
    mod.log:warn("no src.world.gen2.World -- every battle will read as a "
      .. "plain wild one")
    return
  end
  if rawget(World, "__gen1arenaEncounter") then return end
  World.__gen1arenaEncounter = true

  local FieldMoves
  do
    local okFM, found = pcall(require, "src.world.gen2.FieldMoves")
    if okFM and type(found) == "table" then FieldMoves = found end
  end

  local function surfing(world)
    if not (FieldMoves and type(FieldMoves.isSurfing) == "function") then
      return false
    end
    local ok, yes = pcall(FieldMoves.isSurfing, world.playerState)
    return ok and yes or false
  end

  -- The fishing flag.  Set on the roll, claimed by the next battle to start,
  -- and cleared either way -- so a cast that hooks nothing, or one the player
  -- walks away from, cannot colour a battle they walk into afterwards.
  local PENDING_FISH = "__gen1ArenaFished"

  local rollFishing = World.rollFishing
  if type(rollFishing) == "function" then
    World.rollFishing = function(self, ...)
      local outcome, wild = rollFishing(self, ...)
      rawset(self, PENDING_FISH, outcome == "battle")
      return outcome, wild
    end
  end

  -- Whether the world rolled this encounter itself, rather than a script or a
  -- roamer handing it one.  `tryWildEncounter` is Gold's roll, and it is the
  -- only caller that means "you walked into this".
  local PENDING_ROLL = "__gen1ArenaRolled"

  local tryWild = World.tryWildEncounter
  if type(tryWild) == "function" then
    World.tryWildEncounter = function(self, ...)
      rawset(self, PENDING_ROLL, true)
      local ok, a, b = pcall(tryWild, self, ...)
      rawset(self, PENDING_ROLL, nil)
      if not ok then error(a, 0) end
      return a, b
    end
  end

  local startBattle = World.startBattle
  if type(startBattle) ~= "function" then
    mod.log:warn("src.world.gen2.World has no startBattle -- every battle "
      .. "will read as a plain wild one")
    return
  end

  World.startBattle = function(self, opts, ...)
    rawset(self, ARENA_ENCOUNTER, {
      fished = rawget(self, PENDING_FISH) == true,
      surfing = surfing(self),
      -- A trainer battle is never "rolled", and never asks.
      rolled = rawget(self, PENDING_ROLL) == true,
    })
    rawset(self, PENDING_FISH, nil)
    return startBattle(self, opts, ...)
  end
end

-- ------------------------------------------------------- the patch, on Gold
--
-- Simpler than Red's by a long way, and worth saying why rather than leaving
-- the asymmetry looking like an oversight.
--
-- Red's field is a `love.graphics.rectangle` fill buried inside a draw that
-- may or may not be going to a canvas the zone pass will re-shade, so this
-- mod shims `rectangle` itself, matches the fill by its exact geometry, and
-- has two arms for where the paint has to land.  Gold's field is a PALETTE
-- FILL of the whole surface, and there are exactly three of them:
--
--     Chrome.clear()                        -- BattleState:drawPanel
--     Chrome.paletteFill(0,0,304,144)       -- WideBattle.drawSurface
--     Chrome.paletteFill(0,0,160,144)       -- BattleAnimView:fillBackground
--
-- all three of which are `Chrome.paletteFill` at the origin, so one shim on
-- that one function is the whole seam.  Gold's colour is already in the
-- picture too, so there is no shade pass to dodge and no second canvas to
-- choose between.
--
-- ------- and the field is painted BEFORE the scene, not instead of the fill
--
-- This is the part that changed in 0.32.32, and it is the answer to
-- Gen1NightlyIndex#2 -- *"Battle background is tied to the pokemon sprite, so
-- any attack moves the whole background"*.
--
-- An attack does not move the background on hardware.  It moves the BG
-- SCROLL: `BattleAnimView:present` bakes the whole panel into a canvas and
-- blits it back one scanline at a time at each row's own SCX, which is what
-- a shake, a wobble and the intro's sliding bands all are.  On the cart the
-- field inside that canvas is flat white, so a scrolled scanline of it is
-- indistinguishable from an unscrolled one and nothing appears to move.  Put
-- a photograph in the same canvas and every one of those effects drags the
-- photograph across the screen.
--
-- So the field is not painted inside the panel at all any more.  It goes down
-- FIRST, on the surface the scene composites onto, and the panel above it is
-- left transparent where the fill would have been -- the bake canvas is
-- cleared to transparent already (`BattleAnimView:bake`), so the shaken rows
-- carry the mons, the HUD and the boxes and nothing else, and the picture
-- underneath them stays where it is.
--
-- `drawScene` is the one place that works for both layouts: `draw`,
-- `drawWidescreen` and `WideBattle.draw` all reach the scene through it, each
-- having already set up its own transform, and the overlay hook is raised at
-- the end of it -- so a field painted at the top of `drawScene` is under
-- everything and in the right coordinates whichever way the battle is drawn.
--
-- The one thing the picture gives up by leaving the bake is the per-effect
-- rBGP byte, which is how a move's white flash reaches the background.  The
-- fade at the END of a battle is reproduced instead, because it is long
-- enough to notice: `exitFadeBgp` is read at paint time and turned into a
-- veil with the engine's own approximation of a palette byte's brightness
-- (`BattleAnimView.palVeil`, which exists for the shaderless path and says
-- exactly this).  A one-frame attack flash does not reach the picture, and
-- that is the trade: a still background that does not flash, against one that
-- flashes and slides.
local function installGen2()
  local okChrome, Chrome = pcall(require, "src.ui.gen2.Chrome")
  if not (okChrome and type(Chrome) == "table"
          and type(Chrome.paletteFill) == "function") then
    mod.log:warn("no src.ui.gen2.Chrome to patch -- backdrops will not appear")
    return
  end

  local baseScene = BattleState.drawScene
  if type(baseScene) ~= "function" then
    mod.log:warn("src.ui.gen2.BattleState has no drawScene -- backdrops will "
      .. "not appear")
    return
  end

  -- The engine's own approximation of what a DMG palette byte does to the
  -- brightness of a whole screen: +1 solid black, -1 solid white, 0 nothing.
  -- Borrowed rather than re-derived -- it is the same question the shaderless
  -- animation path asks, and a second answer here would drift from it.
  local palVeil
  do
    local okView, BattleAnimView = pcall(require, "src.ui.gen2.BattleAnimView")
    if okView and type(BattleAnimView) == "table"
        and type(BattleAnimView.palVeil) == "function" then
      palVeil = BattleAnimView.palVeil
    end
  end

  local function veilOver(self)
    if not palVeil then return end
    local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
    if not (okGbc and type(GbcPalette) == "table") then return end
    local byte
    if type(self.exitFadeBgp) == "function" then
      local okByte, found = pcall(self.exitFadeBgp, self)
      if okByte then byte = found end
    end
    byte = byte or GbcPalette.bgp
    if not byte then return end
    local okVeil, veil = pcall(palVeil, byte)
    if not (okVeil and type(veil) == "number") or veil == 0 then return end
    local shade = veil > 0 and 0 or 1
    local r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(shade, shade, shade, math.min(1, math.abs(veil)))
    realRectangle("fill", 0, 0, pendingW, pendingH)
    love.graphics.setColor(r, g, b, a)
  end

  -- The three whole-surface fills, and only those.  A partial fill is a real
  -- piece of chrome -- the START menu's own block, a text box's arrow cell --
  -- and swallowing one would put a hole in it.
  local realFill = Chrome.paletteFill

  Chrome.paletteFill = function(px, py, pw, ph, ...)
    if active and consumed and px == 0 and py == 0
       and (pw or 0) >= Chrome.SCREEN_W * 8
       and (ph or 0) >= Chrome.SCREEN_H * 8 then
      return
    end
    return realFill(px, py, pw, ph, ...)
  end

  -- ------- WHAT A BACKDROP TAKES AWAY, AND HAS TO PUT BACK
  --
  -- Gold's battle screen is drawn against PAPER.  `drawPanel` opens with
  -- `Chrome.clear()`, and everything after it -- the HUDs, the pics, the
  -- boxes -- is drawn in the knowledge that whatever it does not paint is
  -- white.  Two of those things stop being true the moment a picture is
  -- there instead, and both were reported as soon as anyone played a battle
  -- on Gold:
  --
  --   * the HUD arrives in WHITE BLOCKS.  Every string paints its own paper
  --     cell (`Chrome.printThrough` fills `width x 8` with the palette's
  --     colour 0 before it draws a glyph, because a tilemap cell is opaque),
  --     and the HP and exp bars are 2bpp sheets written OPAQUE, colour 0 and
  --     all (RomExtractorGen2:extractMenuGfx -- "the bar's rule is shade 3
  --     while its fill is shade 1/2"), so the bar cells are a white slab with
  --     a bar drawn on it.  Neither is a dark-mode bug and neither is right
  --     in LIGHT; it is the tilemap showing.
  --   * the pics have holes in them.  See picPaperImage above.
  --
  -- ------- and the answer is to take the paper away, not to add more
  --
  -- The first shipped fix put a PLATE behind each HUD block -- one rectangle
  -- through the box palette, so the ragged cells became one clean one.  That
  -- was the wrong instinct and it was rejected on sight: "there shouldn't be
  -- the big black or white box behind all that stuff.  Look gen 1 looks much
  -- cleaner."  Which is exactly right, and the reason Red looks cleaner is
  -- that Red's HUD has no paper at all -- `Font.draw` puts black glyphs on
  -- transparent straight onto whatever is behind them.
  --
  -- So Gold's HUD is given the same nothing, with the engine's own switches:
  --
  --   the text   `Chrome.printThrough` draws its glyphs from a page that is
  --              already ink-on-transparent, so the block is ONLY that paper
  --              rect.  It is swallowed for the length of a HUD draw and the
  --              glyphs land on the picture, exactly as Red's do.
  --   the tiles  `GbcPalette` already has a shader for "colour 0 is
  --              transparent" -- the hardware OBJ-behind-BG rule, keyedShader
  --              -- so the HUD's tiles are bound through THAT instead.  The
  --              bar keeps its two hues and its black rule and loses the slab
  --              around it; the empty half of the bar shows the picture, the
  --              way the empty half of a bar on white paper shows the paper.
  --
  -- Nothing is repainted, reordered or re-placed: the HUD is still the
  -- cart's, drawn by the cart, in the cart's own order and its own colours.
  -- The only thing taken away is the white the cart was entitled to assume.
  --
  -- And it is taken away ONLY while a backdrop is up.  On a battle with no
  -- backdrop the field is still Gold's white fill and the paper is invisible
  -- against it, so nothing is touched and the screen is the cart's exactly.
  local keying = false

  -- ------- and the HUD does NOT take the theme
  --
  -- The first cut of this drew the HUD through the LIVE box palette, so under
  -- UI THEME > DARK the names, the levels, the HP numbers and the border came
  -- out WHITE.  Reported immediately: *"the stuff over the arena shouldn't
  -- turn to white font when dark mode is on.  That stuff should stay the same
  -- so it doesn't make it hard to read."*  Which is the right call and the
  -- rule is worth naming, because it decides every case like it:
  --
  --   A THEME IS FOR BOXES.  Dark ink on dark paper is the problem a theme
  --   exists to solve, and it solves it by owning both -- so the bottom
  --   strip, the YES/NO box and the four command buttons all go dark
  --   together and stay legible.  The HUD over a backdrop has no paper at
  --   all: it is ink on a PHOTOGRAPH, which the theme does not own and
  --   cannot reason about.  Flipping that ink to white is not theming it,
  --   it is guessing at the picture -- and half the backdrops in this mod
  --   are bright.
  --
  -- Red settles it the same way and always has: its battle HUD is black
  -- whatever else the theme is doing, because `Font.draw` is black.  So while
  -- a backdrop is up, the HUD is drawn through the CART's own four numbers --
  -- white paper (swallowed anyway) and black ink -- and the theme reaches the
  -- boxes and stops there.
  --
  -- `gen1wildUnthemed` is how that survives the OTHER half of the suite.
  -- UI THEME reaches a page that prints through its own palette by
  -- substituting the paper and the ink into it (runtime/theme2.lua), and a
  -- battle over a backdrop is exactly the shape it looks for: a palette that
  -- is not the box palette, on a page the theme has claimed.  Without the
  -- mark, whichever of the two wraps ended up outermost would decide, and the
  -- HUD would go white again on the frames the theme won.  With it, the
  -- answer does not depend on load order.
  local CART_PALETTE = {
    { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
    gen1wildUnthemed = true,
  }

  -- The HUD BORDER is the one part drawn with no palette at all: `placeBorder`
  -- calls `drawTile` without one, so its 1bpp black-on-transparent tiles come
  -- out flat black.  That is already the ink this wants, and it is given one
  -- explicitly rather than left to the default so it cannot drift from the
  -- text beside it.
  local function hudInk() return CART_PALETTE[4] end

  -- The two HUD draws.  Wrapped rather than switched from `drawPanel`
  -- because the window has to close over the HUD and nothing else: the pics
  -- are drawn between them (drawHud is enemy HUD, pics, player HUD) and a pic
  -- keyed to transparent would lose its own colour 0 -- which is the hole
  -- picPaperImage just filled.
  local function unpapered(name)
    local base = BattleState[name]
    if type(base) ~= "function" then
      mod.log:warn("src.ui.gen2.BattleState has no %s; that HUD keeps its "
        .. "white blocks over a backdrop", name)
      return
    end
    BattleState[name] = function(self, ...)
      if not (active and consumed
              and mod.options:get("hud_clear") ~= false) then
        return base(self, ...)
      end
      keying = true
      local ok, err = pcall(base, self, ...)
      keying = false
      if not ok then error(err, 0) end
    end
  end

  unpapered("drawEnemyHud")
  unpapered("drawPlayerHud")

  -- ------- the text's paper cell
  --
  -- Swallowed by shimming the fill for the length of the call rather than by
  -- reimplementing the two print functions: the glyph loop, the TTF arm, the
  -- rBGP fold and the invert reversal are all Chrome's, they are all still
  -- wanted, and a second copy of them here would be wrong the first time any
  -- of it moved.  `love.graphics.rectangle` is captured per call for the same
  -- reason the pic shim captures `draw` per call -- another mod may have
  -- wrapped it since install, and restoring a snapshot taken before it would
  -- take that mod's wrapper off for good.
  for _, name in ipairs({ "printThrough", "printRightThrough" }) do
    local base = Chrome[name]
    if type(base) == "function" then
      -- Both signatures put the palette fourth (`text, tx, ty, palette` and
      -- `text, txEnd, ty, palette`), so one substitution serves both: the
      -- cart's own numbers in place of the themed ones, for the reason under
      -- CART_PALETTE.
      Chrome[name] = function(text, a, b, palette, ...)
        if not keying then return base(text, a, b, palette, ...) end
        local realRect = love.graphics.rectangle
        love.graphics.rectangle = function() end
        local ok, width = pcall(base, text, a, b, CART_PALETTE, ...)
        love.graphics.rectangle = realRect
        if not ok then error(width, 0) end
        return width
      end
    else
      mod.log:warn("src.ui.gen2.Chrome has no %s; the HUD text keeps its "
        .. "white cells over a backdrop", name)
    end
  end

  -- ------- the tiles' colour 0
  --
  -- `GbcPalette.use` rather than the call sites: BattleHud draws every tile
  -- it lays through `GbcPalette.with`, and `drawExpBarEnd` -- which does not
  -- go through `drawTile` at all -- through the same.  One substitution
  -- covers the bar cells, the end cap, the "HP:" badge, the exp bar, the
  -- caught mark, the party-icon corner and the ball rows.
  --
  -- The balls and the end cap were written transparent already (they are OBJ
  -- sheets), so for those this is the shader they were drawn through anyway.
  local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
  if okGbc and type(GbcPalette) == "table"
      and type(GbcPalette.use) == "function"
      and type(GbcPalette.useKeyed) == "function" then
    local realUse = GbcPalette.use
    GbcPalette.use = function(colors)
      if keying then return GbcPalette.useKeyed(colors) end
      return realUse(colors)
    end
  else
    mod.log:warn("no src.render.GbcPalette keyed shader; the HP and exp bars "
      .. "keep their white slab over a backdrop")
  end

  local okHud, BattleHud = pcall(require, "src.ui.gen2.BattleHud")
  if okHud and type(BattleHud) == "table"
      and type(BattleHud.drawTile) == "function" then
    local baseTile = BattleHud.drawTile
    BattleHud.drawTile = function(self, key, firstTile, tile, tx, ty, colors,
                                  mirror)
      if colors == nil and keying then
        local ink = hudInk()
        -- Colours 0 to 2 are never drawn: the sheet is 1bpp, so its only two
        -- shades are 0 (keyed away) and 3.
        if ink then colors = { ink, ink, ink, ink } end
      end
      return baseTile(self, key, firstTile, tile, tx, ty, colors, mirror)
    end
  else
    mod.log:warn("no src.ui.gen2.BattleHud; the HUD border stays flat black "
      .. "under UI THEME")
  end

  -- ------- paper under the pics
  --
  -- The placement is the ENGINE's, read off the blit rather than re-derived:
  -- `drawPic` works out the box, the centring, the ground line, the resize
  -- square and the slide, and a second copy of that arithmetic here would be
  -- wrong the first time any of it moved.  So `love.graphics.draw` is shimmed
  -- for the length of one `drawPic` call and every image it lays is preceded
  -- by its own paper, at the same coordinates, the same quad and the same
  -- scale -- which covers the plain blit, the faint sink's crop, a Crystal
  -- animation frame and the substitute doll without knowing which one it is
  -- looking at.
  local basePic = BattleState.drawPic
  if type(basePic) == "function" then
    BattleState.drawPic = function(self, mon, back, ...)
      if not (active and consumed and mod.options:get("pic_paper") ~= false) then
        return basePic(self, mon, back, ...)
      end
      -- ------- who may be cut
      --
      -- TRAINERS ONLY.  The report this feature came back for was "trainers
      -- still have white squares behind them", and a trainer's class pic is
      -- the one battle picture that is a figure standing in a white field and
      -- nothing else.
      --
      -- A MON's pic is not.  Crystal animates it -- the frames come out of a
      -- sheet, the substitute doll and the faint slide's crop come through
      -- quads of their own -- and every one of those is the same texture seen
      -- through a different window.  Cutting any of it means the animation is
      -- no longer the cart's, and "they don't play their animation every time
      -- you click on them" is what that costs.  A mon over a backdrop is
      -- already answered by MON PAPER, which paints and never replaces.
      --
      -- Read off the same two flags `BattleState:drawPic` itself branches on
      -- for the trainer boxes, rather than guessed at from the image.
      local trainerPic = (back and self.showPlayerTrainer)
        or ((not back) and self.showEnemyTrainer)
      -- Captured per call, not at install: another mod may have wrapped the
      -- draw since, and restoring a snapshot taken before it would take that
      -- mod's wrapper off for good.
      local realDraw = love.graphics.draw
      local shim
      shim = function(image, first, ...)
        -- Shaping a pic READS it, and reading it draws it to a scratch canvas
        -- -- through this very function.  The shim stands down for the length
        -- of that so the readback is the engine's own draw and not a recursion.
        love.graphics.draw = realDraw
        -- The cart's own pics come first: they have no transparency at all, so
        -- there is no hole for the paper to fill and the whole square is the
        -- thing to deal with.  A cut-out is the SAME image with the space
        -- around the figure taken to alpha 0, so it goes through the engine's
        -- own remap exactly as the original did.
        --
        -- 0.32.62 shipped this on and it broke the one thing it needed to
        -- work with -- a battle over a BACKDROP: "on iOS, the image gets
        -- flipped, on android it just crashes".  Only over a backdrop,
        -- because that is the only time this arm runs at all, which is why
        -- exactly one mod appeared to be at fault.  0.32.65 switched it off.
        --
        -- The cause was never the cut-out.  It was building one HERE: a
        -- readback binds a scratch canvas and `newImage` makes a whole new
        -- texture, both inside the draw with the battle's canvas bound and
        -- the frame half-painted.  A mid-pass render-target switch is what a
        -- GLES driver refuses, and a readback that disagrees about
        -- orientation is the sprite upside down rather than a misplaced hole.
        -- `picPaperImage` did the same readback but bailed before `newImage`
        -- for any pic with no holes, which is every cart pic, so it almost
        -- never reached the texture and the difference never showed.
        --
        -- `cutoutFor` is now a CACHE READ.  A pic it has not seen is
        -- remembered as wanted and the original is drawn this frame; the
        -- build happens on `core.update`, between frames, with nothing bound.
        -- So the first frame a trainer appears on is the cart's own square
        -- and every frame after it is the cut-out -- and no texture is ever
        -- made inside a draw.
        -- A QUAD IS NOT A PICTURE IN A SQUARE.
        --
        -- The engine draws through one for exactly three things -- a Crystal
        -- animation frame out of a sheet, the substitute doll, and the faint
        -- slide's crop -- and cutting the sheet those come out of stopped the
        -- animation playing.  None of them is a lone figure standing in a
        -- field: a sheet is a strip of frames whose "field" runs between them,
        -- and the frame the quad picks is a window onto it.
        --
        -- So a quad draw is handed straight through, and the paper arm keeps
        -- the case it always had.  The cut is for the plain blit, which is the
        -- one that was ever a square.
        -- A QUAD DRAW IS LEFT ENTIRELY ALONE -- no cut, and no paper either.
        --
        -- Cutting one stopped the animation (0.32.76 answered that half), but
        -- the PAPER arm was still reading the sheet back through a scratch
        -- canvas, mid-draw, the first time it saw one -- the same bind that
        -- flipped and crashed the pics in 0.32.62, done to the very texture
        -- the animation is being drawn out of, on the frame it starts.  "They
        -- still aren't playing their animation every time" is what that costs,
        -- and "every time" is the tell: it is the FIRST sight of a sheet that
        -- pays for the readback, not the later ones.
        --
        -- Nothing is owed here anyway.  A frame out of a sheet, the substitute
        -- doll and the faint slide's crop are all windows onto a texture whose
        -- box already had its paper laid by the plain blit.
        local quad = first ~= nil and type(first) ~= "number"
        if quad then
          love.graphics.draw = shim
          return realDraw(image, first, ...)
        end
        local cut = trainerPic and mod.options:get("pic_cutout") ~= false
          and cutoutFor(image) or nil
        local paper = (not cut) and picPaperImage(image) or nil
        love.graphics.draw = shim
        -- Through whatever the engine has bound for this pic, so the paper is
        -- the mon's own colour 0 -- deliberately NOT the page's paper, which
        -- in a dark game would print black patches through a white mon.
        if paper then realDraw(paper, first, ...) end
        return realDraw(cut or image, first, ...)
      end
      love.graphics.draw = shim
      local ok, err = pcall(basePic, self, mon, back, ...)
      love.graphics.draw = realDraw
      if not ok then error(err, 0) end
    end
  else
    mod.log:warn("src.ui.gen2.BattleState has no drawPic; the pics keep the "
      .. "backdrop showing through them")
  end

  BattleState.drawScene = function(self, bodyFn, ...)
    -- A battle with no sides yet draws "NO BATTLE" on a cleared screen; there
    -- is nothing to put a backdrop behind, and picking one would ask the
    -- world for a map that is halfway through changing.
    local sides = type(self.hasBattleSides) == "function"
      and self:hasBattleSides()
    if not (self and self.battle and sides) then
      self.gen1wildArenaField = nil
      return baseScene(self, bodyFn, ...)
    end
    if mod.options:get("enabled") == false then
      self.gen1wildArenaField = nil
      return baseScene(self, bodyFn, ...)
    end

    -- Gold has a wide layout of its own -- `battleLayout = "wide"`, which
    -- WideBattle draws at 304x144 through this same call -- so the slot is
    -- picked off the layout rather than assumed to be `og`.  The mod has
    -- always shipped both sets of art; the Gold arm just never asked for the
    -- wide one.
    local wide = type(self.wideLayout) == "function" and self:wideLayout()
    local layout = wide and "wide" or "og"
    local width = wide and WIDE_W or OG_W
    local height = wide and WIDE_H or OG_H

    local chosen
    local okPick, problem = pcall(function()
      chosen = pickBackdrop(self, layout)
    end)
    if not okPick then
      mod.log:warn("no backdrop this frame: %s", tostring(problem))
    end
    if not chosen then
      -- With BACKDROPS off, or on a battle no slot answered, Gold's own white
      -- field is still there and everything below is the cart's.
      self.gen1wildArenaField = nil
      return baseScene(self, bodyFn, ...)
    end

    active, consumed = true, true
    pendingImage, pendingW, pendingH = chosen, width, height

    -- Down FIRST, on the surface the scene composites onto, so an attack's
    -- scanline scroll moves the panel over it instead of moving it.
    local okPaint, paintProblem = pcall(function()
      paintField()
      veilOver(self)
    end)
    if not okPaint then
      mod.log:warn("the field was not painted: %s", tostring(paintProblem))
    end

    bleedImage, bleedW, bleedH = chosen, width, height
    -- What UI THEME needs to know about this frame, on the instance rather
    -- than through an export, because it is a fact about ONE battle screen
    -- on ONE frame: is the field a picture, or is it the four numbers the
    -- theme owns?
    --
    -- The theme excludes battles outright, and the reason it gives is exact:
    -- Gold's field IS a whole-screen fill through the box palette, so theming
    -- a battle would paint every field black.  That is true of a battle the
    -- backdrop did not take, and false of one it did -- there the fill never
    -- happens and the field is art, which no palette reaches.  So the boxes
    -- and the bottom strip can go dark while the picture stays a picture.
    self.gen1wildArenaField = true

    local okDraw, err = pcall(baseScene, self, bodyFn, ...)
    active, consumed, pendingImage = false, false, nil
    if not okDraw then error(err, 0) end
  end

  mod.log:info("patched Gold's battle field (og, wide)")
end

local function install()
  if not (ok_bs and BattleState) then return end
  if BattleState.__gen1arena then return end
  BattleState.__gen1arena = true

  if gen2() then
    installGen2()
    installGen2Encounter()
    return
  end

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
  -- Cuts the cart's own pics out of their baked white square instead of
  -- letting it show as a box over a backdrop.  OFF until it is built outside
  -- the draw: see the note in the pic shim.  On a host where it works it is
  -- the better picture; on one where it does not it is a crash, and a crash
  -- is not a trade.
  -- Trainers as well as mons -- the report that brought it back was
  -- "trainers still have white squares behind them", and a trainer's class
  -- pic goes through the very same `drawPic`.  On, now that the build is out
  -- of the draw and the crash it caused is gone with it.
  { key = "pic_cutout", type = "toggle", label = "PIC CUTOUT", default = true },
  -- The bars around the battle.  On, the backdrop's own edge is stretched
  -- into them so the picture runs off the screen; off, they are the paper
  -- white the engine gives a battle, which with a backdrop up reads as a
  -- bright frame around the art -- and in a WIDE battle as a big white bar
  -- above and below it.  See bleedInto.
  { key = "bleed", type = "toggle", label = "EDGE TO EDGE", default = true },
}

-- Gold only, and the other half of MON PAPER: appended rather than declared
-- above, the same way the DEV rows are, because a row that cannot do anything
-- is worse than a missing one.
--
-- Gold's battle HUD assumes the white field it is drawn on.  Every string
-- paints its own paper cell first (a tilemap cell is opaque), and the HP and
-- exp bars are opaque 2bpp sheets whose colour 0 is a white slab around the
-- bar.  On a white field none of that is visible; over a backdrop the name,
-- the level, the HP numbers and both bars each arrive in a white block.  ON
-- takes the paper away and leaves the glyphs and the bars on the picture,
-- which is what Red's HUD has always looked like.  OFF is the cart's own
-- blocks, in case one of them turns out to be load-bearing.
--
-- Red needs no row: its HUD glyphs are drawn with no paper under them at all,
-- which is why this was never a Gen 1 bug.
if gen2() then
  optionRows[#optionRows + 1] =
    { key = "hud_clear", type = "toggle", label = "CLEAR HUD", default = true }
end

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
-- ------- where a cut-out is actually built
--
-- `core.update` runs before anything is drawn: no canvas is bound, no
-- transform is in effect, and a texture made here is made the way any other
-- asset is.  That is the whole of the fix for the crash 0.32.62 caused --
-- the readback and the `newImage` are the same code, in a different place.
--
-- One per frame, and only while the feature is on: a battle asks for at most
-- two pics and a readback is not free, so draining a queue in one go would be
-- a stutter at exactly the moment the intro is sliding.  Its failure costs a
-- cut-out and nothing else -- the pic that could not be cut is drawn as the
-- cart drew it, square and all.
mod.hooks:wrap("core.update", function(nextLink, game, dt)
  if mod.options:get("pic_cutout") ~= false then
    local ok, problem = pcall(buildQueuedCutouts)
    if not ok then
      mod.log:warn("a pic could not be cut from its square: %s",
                   tostring(problem))
    end
  end
  return nextLink(game, dt)
end)

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
