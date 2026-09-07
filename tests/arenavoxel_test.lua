-- Gen1Arena stands down while a voxel mod is drawing the battle.
--
-- A voxel mod draws the battle over the MAP, so there is already a world
-- behind the fight.  A backdrop painted into the field is then a second
-- background nobody asked for -- and worse than redundant: DRAMALESS_SHAPE
-- suppresses the engine's field fill by shimming `love.graphics.rectangle`,
-- which is the same call this mod shims to REPLACE that fill.  Two mods
-- swapping one function for the length of one draw is a coin toss decided by
-- load order.
--
-- The test is the renderer rather than a list of mod ids.  Every fork presents
-- its battle through `Renderer:setWorldOverride`, and the renderer clears that
-- in `beginFrame` -- so a non-nil `worldOverride` is exactly "something
-- replaced the world image on THIS frame", asked of the engine, with no mod
-- named.  A fork with its 3D battles switched off never sets it, and then the
-- backdrop is wanted and drawn.
--
-- Run:  luajit tests/arenavoxel_test.lua

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

_G.love = { graphics = {
  rectangle = function() end, setColor = function() end,
  getColor = function() return 1, 1, 1, 1 end,
  getCanvas = function() return nil end, setCanvas = function() end,
  clear = function() end, draw = function() end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
} }

-- The engine's Renderer is a singleton table; the mod reads one field off it.
local Renderer = { worldOverride = nil }
package.preload["src.render.Renderer"] = function() return Renderer end

-- The bundle's voxel resolver, as the facade hands it to a feature.
-- `installed` is what mod.voxel.id() answers: nil when there is no voxel mod,
-- which is most installs.
local installed = nil
local mod = { id = "gen1_wild_ui_nightly", exports = {}, stored = {},
              hooked = {}, events_on = {},
              voxel = { id = function() return installed end } }
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

local worldTaken = mod.exports.worldTaken
ok(type(worldTaken) == "function", "the decision is exposed")

io.write("who is drawing the world behind this battle\n")

do
  installed = "BATTLE_ART_VOXEL_FORK"
  Renderer.worldOverride = nil
  eq(worldTaken(), false,
     "a voxel mod installed but not presenting: the backdrop is still ours")

  -- What every fork actually hands the renderer: a canvas.
  Renderer.worldOverride = { canvas = true }
  eq(worldTaken(), true, "presenting a world: drawing the battle over the map")

  Renderer.worldOverride = nil
  eq(worldTaken(), false,
     "and it is cleared each frame, so the answer goes back on its own")
end

io.write("a world override ALONE is not a voxel mod\n")
do
  -- The defect in the first draft, found by reading the engine rather than by
  -- it breaking: OverworldController calls setWorldOverride for the engine's
  -- OWN render pipelines, so reading the override by itself stood this mod
  -- down for a pipeline mod, or for the engine's world-background battle.
  -- With no voxel mod installed this change must be completely inert.
  installed = nil
  Renderer.worldOverride = { canvas = true }
  eq(worldTaken(), false,
     "no voxel mod, so a world override is somebody else's pipeline")
  Renderer.worldOverride = nil
  eq(worldTaken(), false, "and with neither, plainly nothing")
end

io.write("and it is asked of the engine, not of a mod list\n")
do
  -- The point of reading the renderer: a fork this mod has never heard of,
  -- or one whose 3D battles are switched off, is answered correctly without
  -- anybody adding an id anywhere.
  installed = "some_fork_nobody_has_heard_of"
  Renderer.worldOverride = { canvas = true }
  ok(worldTaken(), "an unknown fork that presents a world stands this down")
  Renderer.worldOverride = nil
  ok(not worldTaken(),
     "and a fork with 3D battles off never sets it, so the backdrop stays")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
