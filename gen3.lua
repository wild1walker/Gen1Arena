-- BACKDROPS on FireRed, LeafGreen and Emerald.
--
-- Every picture this mod carries was drawn for FireRed's battle field in the
-- first place -- see CREDITS.md: the Battle Backgrounds Patch FR, 240x112
-- GBA terrain art -- and the Red and Gold arms spend a good deal of code
-- fitting it to 160x144 and 304x144 surfaces it was never drawn for.  This is
-- the arm where it simply goes home.
--
-- THE SEAM is `BattleBg.draw(id, enemyOx, playerOx, bgOx)`
-- (src/core/game3/battle/bg.lua), the one call that paints a GBA battle's
-- background, intro slide included.  The cart has already decided the
-- terrain by then -- grass, long grass, sand, water, pond, mountain, cave,
-- building, or a scene of its own for a gym, a leader, an Elite Four room --
-- so this does not second-guess the cart's geography.  It takes the cart's
-- answer, narrows it with what the map says (a forest, a town, an ice cave,
-- a volcano, the Tower, the Mansion, a ship), and paints the matching
-- picture instead.  A terrain with no picture -- underwater, a link battle,
-- Emerald's Battle Frontier, its legendary scenes, the Hoenn Elite Four --
-- keeps the cart's own background: nothing here is better than wrong.
--
-- NO PLATFORMS, deliberately.  A GBA battle stands its Pokemon on two
-- ovals, and the cart keeps them as separate layers for the intro slide
-- (BattleChrome.terrain: enemyPlat, playerPlat) -- but those layers are
-- whole opaque 8x8 tiles, not cut-out ovals: every tile in the platform's
-- region that is not the row's commonest, baked with colour 0 opaque
-- (src/import/gba/battle_chrome_extract.lua split_terrain_layers).  Laid
-- over another picture they are blocks of the cart's own ground.  The pack's
-- art stands the Pokemon on its own ground, as it does on Red and Gold.
--
-- THE FIT is 1:1, never scaled: the art's pixels are GBA pixels.  The WIDE
-- files are the original 240 columns with 32 mirrored either side; this takes
-- the middle 240.  The picture is anchored on its ground -- its last picture
-- row at the field's bottom edge, y = 112, where the message box starts --
-- and where the art runs out at the top (the wide files keep 104 of the 112
-- rows) the top rows are mirrored upward, which is how the art was padded
-- sideways too.  Below 112 is the art's own flat band, behind the box.

local FIELD_W, FIELD_H, SCREEN_H = 240, 112, 160

-- The cart's sheet key -> the picture it means, where one is drawn.
local TERRAIN_SLOT = {
  grass = "field", long_grass = "field", plain = "field",
  sand = "port",               -- a beach; Emerald's desert is a map below
  water = "sea", pond = "lake",
  mountain = "plateau",
  cave = "cave",
  building = "indoor", indoor_1 = "indoor", indoor_2 = "indoor",
  gym = "gym", leader = "leader",
  lorelei = "lorelei", bruno = "bruno", agatha = "agatha", lance = "lance",
  champion = "champion",
}

-- Scenes the art was drawn for FireRed's rooms and that Emerald's rooms of the
-- same name are not: Wallace's champion room is under water.
local FRLG_ONLY = { champion = true, lorelei = true, bruno = true,
                    agatha = true, lance = true }

-- The map narrows the cart's terrain.  Patterns on the map id with its game
-- prefix taken off; first match wins.  Each is a place whose own scene is in
-- the pack: the art's forest, ice cave, volcano, Tower, Mansion, ship, museum.
local MAP_SLOT = {
  { "FOREST", "forest" }, { "WOODS", "forest" },
  { "ICEFALL_CAVE", "lorelei" }, { "SHOAL_CAVE", "lorelei" },
  { "MT_EMBER", "lance" }, { "FIERY_PATH", "lance" },
  { "MAGMA_HIDEOUT", "lance" }, { "MT_CHIMNEY", "lance" },
  { "POKEMON_TOWER", "tower" }, { "MT_PYRE", "tower" },
  { "POKEMON_MANSION", "mansion" },
  -- FireRed spells it SSANNE (MAP_SSANNE_1F_CORRIDOR -> FR_SSANNE_...), and
  -- Emerald SS_TIDAL.  Checked against both carts' map_groups constants.
  { "SSANNE", "ship" }, { "SS_TIDAL", "ship" }, { "ABANDONED_SHIP", "ship" },
  { "MUSEUM", "museum" },
  { "SAFARI_ZONE", "safari" },
  { "FAN_CLUB", "club" },
  { "ROUTE111", "agatha" },     -- the desert; the art's desert is Agatha's
}
-- Which of those may override which terrain: a forest is grass under the
-- trees, a volcano is a cave or a mountain, a room is a building.  So a
-- trainer standing on the Safari Zone's water still gets the water.
local NARROWS = {
  forest = { grass = true, long_grass = true, plain = true },
  lorelei = { cave = true }, lance = { cave = true, mountain = true },
  tower = { building = true, indoor_1 = true, indoor_2 = true },
  mansion = { building = true, indoor_1 = true, indoor_2 = true },
  ship = { building = true, indoor_1 = true, indoor_2 = true },
  museum = { building = true, indoor_1 = true, indoor_2 = true },
  club = { building = true, indoor_1 = true, indoor_2 = true },
  safari = { grass = true, long_grass = true, plain = true },
  agatha = { sand = true },
}

-- Places whose ground the pack has no picture of, where the cart's terrain
-- would otherwise land on a wrong one: Emerald's Route 113 is SAND to the
-- cart (env_rse.lua's ash rule), and the sand picture is a tropical beach.
-- The cart's own ash background stays.
local KEEP_CART = {
  { "ROUTE113", { sand = true } },
}

-- Kanto's towns have their own roof colours in the pack, generated for Red
-- (wide/<town>/town.png, gym.png, trainer_gym.png).  FireRed's map ids carry
-- the town as a prefix -- FR_CERULEAN_CITY, FR_CERULEAN_CITY_GYM -- so the
-- same folder answers.
local TOWN_VARIANT = {
  PALLET_TOWN = "pallet", VIRIDIAN_CITY = "viridian", PEWTER_CITY = "pewter",
  CERULEAN_CITY = "cerulean", VERMILION_CITY = "vermilion",
  LAVENDER_TOWN = "lavender", CELADON_CITY = "celadon",
  FUCHSIA_CITY = "fuchsia", SAFFRON_CITY = "saffron",
  CINNABAR_ISLAND = "cinnabar", INDIGO_PLATEAU = "indigo",
}

local BOSS = { leader = true, lorelei = true, bruno = true, agatha = true,
               lance = true, champion = true }

local MAP_TYPE_TOWN, MAP_TYPE_CITY, MAP_TYPE_UNDERGROUND = 1, 2, 4

return function(mod)
  mod.options:define({
    { key = "enabled", type = "toggle", label = "BACKDROPS", default = true },
  })

  -- `require`, never `package.loaded`: the sandbox's package is a shim whose
  -- `loaded` is empty (src/mods/LegacyCompat.lua packageShim).  Kept once
  -- found: this is asked every frame of every battle, and each require
  -- through the loader's shim is not free.
  local modules = {}
  local function engine(name)
    local hit = modules[name]
    if hit then return hit end
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then
      modules[name] = module
      return module
    end
    return nil
  end

  local BattleBg = engine("src.core.game3.battle.bg")
  if not BattleBg or type(BattleBg.draw) ~= "function" then
    mod.log:warn("src.core.game3.battle.bg has no draw; Gen 3 battles keep "
      .. "the cart's backgrounds")
    return
  end

  -- ------- the pictures

  local images = {}
  local function loadPicture(name)
    if images[name] ~= nil then return images[name] or nil end
    local path = tostring(mod.path) .. "/assets/backdrops/wide/" .. name .. ".png"
    local img, data
    if love.image and type(love.image.newImageData) == "function" then
      local okData, decoded = pcall(love.image.newImageData, path)
      if okData and decoded then
        local okImage, made = pcall(love.graphics.newImage, decoded)
        if okImage and made then img, data = made, decoded end
      end
    end
    if not img then
      local ok, made = pcall(love.graphics.newImage, path)
      if ok and made then img = made end
    end
    if not img then
      images[name] = false
      return nil
    end
    if img.setFilter then img:setFilter("nearest", "nearest") end
    local w, h = img:getDimensions()
    -- Where the picture stops: the flat band under it is the rows whose
    -- every sampled pixel is the bottom-left one.
    local top = h
    if data and type(data.getPixel) == "function" then
      local okBase, r0, g0, b0 = pcall(data.getPixel, data, 0, h - 1)
      if okBase then
        for y = h - 1, 0, -1 do
          local flat = true
          for x = 0, w - 1, 4 do
            local r, g, b = data:getPixel(x, y)
            if r ~= r0 or g ~= g0 or b ~= b0 then flat = false break end
          end
          if not flat then break end
          top = y
        end
      end
    end
    images[name] = { image = img, w = w, h = h, picture = top }
    return images[name]
  end

  -- ------- which picture

  local function mapFacts()
    local Map = engine("src.core.game3.map")
    if not Map then return nil, nil end
    local id = Map.current
    local def = type(Map.currentDef) == "function" and Map.currentDef() or nil
    local bare = type(id) == "string" and id:gsub("^%u%u_", "") or nil
    return bare, def and tonumber(def.mapType) or nil
  end

  local function family()
    local Profile = engine("src.core.game3.profile")
    if Profile and type(Profile.family) == "function" then
      local ok, which = pcall(Profile.family)
      if ok then return which end
    end
    return nil
  end

  -- `wild` is a boolean on every Gen 3 battle (battle/state.lua: `opts.wild
  -- and true or false`), so a trainer is `false` and no battle is nil.
  local function trainerBattle()
    local Battle = engine("src.core.game3.battle")
    local st = Battle and type(Battle.getState) == "function" and Battle.getState()
      or nil
    return type(st) == "table" and st.wild == false
  end

  -- The lookup, most particular first: the town's own colour, the kind of
  -- battle in this place, the place, and the cart's terrain.  nil is the
  -- cart's own background.
  local function decide(key, frlg, mapId, mapType, trainer)
    local slot = TERRAIN_SLOT[key]
    if not slot then return nil end
    if FRLG_ONLY[slot] and not frlg then return nil end

    if mapId then
      for _, rule in ipairs(KEEP_CART) do
        if mapId:find(rule[1], 1, true) and rule[2][key] then return nil end
      end
    end
    if mapId then
      for _, rule in ipairs(MAP_SLOT) do
        if mapId:find(rule[1], 1, true) and NARROWS[rule[2]][key] then
          slot = rule[2]
          break
        end
      end
    end
    -- Water in a cave is neither the sea nor a pond: Seafoam has no sky.
    if (key == "water" or key == "pond") and mapType == MAP_TYPE_UNDERGROUND then
      slot = "water_cave"
    end
    -- Grass in a town is the town.
    if slot == "field" and (mapType == MAP_TYPE_TOWN or mapType == MAP_TYPE_CITY) then
      slot = "town"
    end

    -- A boss's scene is already the trainer's: Misty gets her gym, not the
    -- junior trainers' half of it.
    local kind = trainer and not BOSS[slot] and "trainer" or nil
    local candidates = {}
    if frlg and mapId and (slot == "town" or slot == "gym" or slot == "leader") then
      for prefix, folder in pairs(TOWN_VARIANT) do
        if mapId:sub(1, #prefix) == prefix then
          local own = slot == "leader" and "gym" or slot
          if kind then candidates[#candidates + 1] = folder .. "/" .. kind .. "_" .. own end
          candidates[#candidates + 1] = folder .. "/" .. own
          break
        end
      end
    end
    if kind then candidates[#candidates + 1] = kind .. "_" .. slot end
    candidates[#candidates + 1] = slot
    for _, name in ipairs(candidates) do
      local picture = loadPicture(name)
      if picture then return picture, name end
    end
    return nil
  end

  -- The answer only changes with the terrain, the map or the kind of battle,
  -- and the draw asks every frame: kept until one of those moves, compared
  -- field by field so a frame that changes nothing allocates nothing.
  local memo = {}
  local function choose(key)
    local frlg = family() ~= "rse"
    local mapId, mapType = mapFacts()
    local trainer = trainerBattle()
    if memo.set and memo.key == key and memo.frlg == frlg
        and memo.mapId == mapId and memo.mapType == mapType
        and memo.trainer == trainer then
      return memo.picture, memo.name
    end
    local picture, name = decide(key, frlg, mapId, mapType, trainer)
    memo.set, memo.key, memo.frlg = true, key, frlg
    memo.mapId, memo.mapType, memo.trainer = mapId, mapType, trainer
    memo.picture, memo.name = picture, name
    return picture, name
  end

  -- ------- the paint

  local quads = setmetatable({}, { __mode = "k" })
  local function quadsFor(p)
    local q = quads[p]
    if q then return q end
    local g = love.graphics
    local sx = math.max(0, math.floor((p.w - FIELD_W) / 2))
    local sw = math.min(FIELD_W, p.w)
    local rows = math.min(FIELD_H, p.picture)
    q = {
      sx = sx, sw = sw, rows = rows,
      -- the picture's bottom `rows` rows, onto the field's bottom
      body = g.newQuad(sx, p.picture - rows, sw, rows, p.w, p.h),
      -- what is missing at the top, mirrored up out of the picture's own top
      pad = rows < FIELD_H
        and g.newQuad(sx, 0, sw, FIELD_H - rows, p.w, p.h) or nil,
      -- under the field, behind the box: the band, or the last picture row
      under = p.h > p.picture
        and g.newQuad(sx, p.picture, sw, 1, p.w, p.h)
        or g.newQuad(sx, p.picture - 1, sw, 1, p.w, p.h),
    }
    quads[p] = q
    return q
  end

  local function paint(p)
    local g = love.graphics
    local q = quadsFor(p)
    g.setColor(1, 1, 1, 1)
    local top = FIELD_H - q.rows
    g.draw(p.image, q.body, 0, top)
    if q.pad then
      g.draw(p.image, q.pad, 0, top, 0, 1, -1)
    end
    g.draw(p.image, q.under, 0, FIELD_H, 0, 1, SCREEN_H - FIELD_H)
  end

  -- One picture for this terrain, painted; false for the cart's own.
  local last
  local function paintFor(id)
    local key = BattleBg.sheetKey(id)
    if type(key) ~= "string" then return false end
    local picture, name = choose(key)
    if not picture then return false end
    if name ~= last then
      -- info, not debug: the engine's mod log has info, warn and error and
      -- nothing else (src/mods/Loader.lua), and the facade hands an absent
      -- level back as nil.  Once per change of scene, so it is not a flood.
      mod.log:info("%s battle on %s", key, name)
      last = name
    end
    paint(picture)
    return true
  end

  -- This runs every frame of every battle.  Anything that goes wrong in it
  -- is the CART'S background on screen rather than an error in its draw: the
  -- feature is decoration, the battle is not.  Said once.
  local base = BattleBg.draw
  local complained = false
  BattleBg.draw = function(id, enemyOx, playerOx, bgOx, ...)
    if mod.options:get("enabled") ~= false then
      local ok, drew = pcall(paintFor, id)
      if ok and drew then return true end
      if not ok and not complained then
        complained = true
        mod.log:warn("Gen 3 backdrop failed; the cart's background instead: %s",
                     tostring(drew))
      end
    end
    return base(id, enemyOx, playerOx, bgOx, ...)
  end

  mod.exports.choose = choose
  mod.exports.TERRAIN_SLOT = TERRAIN_SLOT
end
