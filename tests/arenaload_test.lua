-- What a Gold battle costs on its first frames, and where that cost went.
--
-- "There is some lag in the animation that switches from world view to battle
-- view -- not when encountering a wild pokemon but when engaging into a
-- trainer battle ... at least, on sbc-portmaster version."
--
-- Three things BACKDROPS did on the first frames of a battle, every one of
-- them invisible on a desktop and a stall on a handheld GPU:
--
--   * each backdrop PNG was decoded TWICE the first time it was used -- once
--     for the texture, once more to measure its flat bottom band.
--   * MON PAPER read each pic back off the GPU INSIDE the draw, into a canvas
--     made for the purpose.  A trainer battle has one more pic than a wild one
--     -- the trainer's -- and cuts that one out of its square as well.
--   * the backdrops a trainer battle asks for (`trainer_town`, a gym's) were
--     first decoded on the frame that battle started.
--
-- So: one decode; pics read off their FILE where Gold says which file (no GPU
-- in it at all), and anything still read back is read back between frames on
-- a canvas that is kept; and a map's likely backdrops loaded on entering it,
-- one per update, on updates with nothing else to do.
--
-- Run:  luajit tests/arenaload_test.lua

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

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

-- ------------------------------------------------------------- the harness

-- Backdrop files: every name exists except those listed missing.  A decode is
-- counted per path, which is the number this whole file is about.
local decodes, textures, canvases = {}, 0, 0
local MISSING = {}
local function fileData(w, h, pixel)
  return {
    getDimensions = function() return w, h end,
    getPixel = function(_, x, y) return pixel(x, y) end,
  }
end

_G.love = {
  image = {
    newImageData = function(a, b)
      if type(a) == "string" then
        local name = a:match("([%w_]+)%.png$")
        if MISSING[name] then error("no such file: " .. a, 0) end
        decodes[a] = (decodes[a] or 0) + 1
        -- 16x16, its last ten rows one flat colour: a band
        return fileData(16, 16, function(_, y)
          if y >= 6 then return 0.5, 0.5, 0.5, 1 end
          return y / 16, 0.2, 0.3, 1
        end)
      end
      -- an ImageData the mod builds itself (a mask, a cut-out)
      local data = { w = a, h = b, px = {} }
      data.getDimensions = function() return a, b end
      data.setPixel = function(self, x, y, r, g, bb, al)
        self.px[y * a + x] = { r, g, bb, al }
      end
      return data
    end,
  },
  graphics = {
    newImage = function(source)
      textures = textures + 1
      if type(source) == "string" then
        local name = source:match("([%w_]+)%.png$")
        if MISSING[name] then error("no such file: " .. source, 0) end
        -- A texture made from a PATH decodes the PNG too.
        decodes[source] = (decodes[source] or 0) + 1
      end
      local w, h = 16, 16
      if type(source) == "table" and source.getDimensions then
        w, h = source.getDimensions()
      end
      return { getDimensions = function() return w, h end,
               setFilter = function() end, source = source }
    end,
    newCanvas = function()
      canvases = canvases + 1
      return { newImageData = function()
        return fileData(8, 8, function(x, y)
          return (x >= 2 and x <= 5 and y >= 2 and y <= 5) and 0 or 1, 0, 0, 1
        end)
      end }
    end,
    getCanvas = function() return nil end,
    setCanvas = function() end,
    push = function() end, pop = function() end,
    origin = function() end, setScissor = function() end,
    setShader = function() end, setBlendMode = function() end,
    setColor = function() end, clear = function() end,
    draw = function() end, rectangle = function() end,
    newQuad = function() return {} end,
  },
}

package.loaded["src.core.GameVersion"] = {
  generation = function() return 2 end,
  get = function() return "gold" end,
  isYellow = function() return false end,
}

-- Gold's own asset reader: a file's pixels, on the CPU.
local fromDisk = {}
package.loaded["src.render.Assets"] = {
  imageData = function(path)
    fromDisk[#fromDisk + 1] = path
    return fileData(8, 8, function(x, y)
      return (x >= 2 and x <= 5 and y >= 2 and y <= 5) and 0 or 1, 0, 0, 1
    end)
  end,
}

local mod = {
  id = "gen1_wild_ui_nightly", path = "modules/Gen1Arena",
  exports = {}, stored = {}, hooked = {}, events_on = {},
}
mod.options = {
  define = function() end,
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

local function update()
  return mod.hooked["core.update"](function() return "next" end, GAME, 1 / 60)
end

-- ------------------------------------------------------------- one decode

do
  io.write("a backdrop is decoded once\n")
  local band = mod.exports.arenaBandTop
  ok(type(band) == "function", "the band measure is exposed")
  -- Through the map-entry pre-load, which is the ordinary way a backdrop is
  -- first loaded now.
  GAME = { world = { map = { def = { id = "ROUTE_29", tileset = "TILESET_JOHTO",
                                    environment = "ROUTE", group = 24 } } } }
  mod.events_on["map.entered"]({})
  for _ = 1, 8 do update() end
  local any, twice = 0, 0
  for _, n in pairs(decodes) do
    any = any + 1
    if n > 1 then twice = twice + 1 end
  end
  ok(any > 0, "the pre-load decoded the route's backdrops")
  eq(twice, 0, "and decoded none of them twice: the band is measured off the "
     .. "same pixels the texture is made from")
end

-- ------------------------------------------------------------- the pre-load

do
  io.write("the map's backdrops are loaded ahead, one per update\n")
  decodes = {}
  GAME = { world = { map = { def = { id = "VIOLET_CITY", tileset = "TILESET_JOHTO",
                                    environment = "TOWN", group = 10 } } } }
  mod.events_on["map.entered"]({})
  eq(next(decodes), nil, "entering a map decodes nothing on the spot")
  update()
  local afterFirst = 0
  for _ in pairs(decodes) do afterFirst = afterFirst + 1 end
  eq(afterFirst, 0, "the first update only lays out the jobs")
  local steps = 0
  repeat
    local before = 0
    for _ in pairs(decodes) do before = before + 1 end
    update()
    steps = steps + 1
  until mod.exports.arenaPrewarmPending() == nil or steps > 10
  eq(mod.exports.arenaPrewarmPending(), nil, "and the list drains")
  ok(steps >= 3, "over several updates rather than one -- a wild battle, a "
     .. "trainer's and water, each its own")
  local trainer = false
  for path in pairs(decodes) do
    if path:find("trainer", 1, true) then trainer = true end
  end
  ok(trainer, "and a TRAINER scene is among them, which is the one a wild "
     .. "battle never touched and the first trainer used to pay for")

  -- A battle asking now finds everything already there.
  decodes = {}
  for _ = 1, 5 do update() end
  eq(next(decodes), nil, "nothing more is loaded once the list is done")
end

do
  io.write("BACKDROPS off loads nothing ahead\n")
  decodes = {}
  mod.stored.enabled = false
  GAME = { world = { map = { def = { id = "ROUTE_30", tileset = "TILESET_JOHTO",
                                    environment = "ROUTE", group = 26 } } } }
  mod.events_on["map.entered"]({})
  for _ = 1, 6 do update() end
  eq(next(decodes), nil, "the pre-load stands down with the feature")
  mod.stored.enabled = nil
end

-- ------------------------------------------------------------- off the disk

do
  io.write("a pic with a known file is read off the disk\n")
  local trainerPic = { getDimensions = function() return 8, 8 end,
                       setFilter = function() end }
  local state = { enemyTrainerImage = trainerPic,
                  enemyTrainerPath = "gfx/trainers/sailor.png",
                  picCache = {} }
  mod.exports.arenaNotePicPath(state, trainerPic)
  eq(mod.exports.arenaPicPath(trainerPic), "gfx/trainers/sailor.png",
     "the trainer's pic is matched to the path Gold loaded it from")
  local before = canvases
  fromDisk = {}
  local cut = mod.exports.picCutoutImage(trainerPic)
  ok(cut ~= nil, "it is cut out of its square")
  eq(canvases, before, "with no canvas made and nothing read back off the GPU")
  eq(fromDisk[1], "gfx/trainers/sailor.png",
     "because its pixels came from its file")

  -- A mon's pic is found by the key it is cached under.
  local monPic = { getDimensions = function() return 8, 8 end }
  local monState = { picCache = { ["gfx/pokemon/zubat/front.png"] = monPic } }
  mod.exports.arenaNotePicPath(monState, monPic)
  eq(mod.exports.arenaPicPath(monPic), "gfx/pokemon/zubat/front.png",
     "a mon's pic by its picCache key")

  -- A file that is not the picture's size is not the picture.
  local odd = { getDimensions = function() return 9, 9 end }
  mod.exports.arenaNotePicPath({ playerBackImage = odd,
                                 playerBackPath = "x.png" }, odd)
  before = canvases
  mod.exports.picCutoutImage(odd)
  ok(canvases > before, "a pic whose file does not match is read back instead")
end

do
  io.write("a readback that is still needed reuses its canvas\n")
  local a = { getDimensions = function() return 8, 8 end }
  local b = { getDimensions = function() return 8, 8 end }
  local before = canvases
  mod.exports.picPaperImage(a)
  mod.exports.picPaperImage(b)
  ok(canvases - before <= 1, "two pics of one size share one scratch canvas")
end

io.write(("arena load: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
