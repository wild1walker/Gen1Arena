io.stdout:setvbuf("no")
function love.errorhandler(msg)
  io.write("ERROR: ", tostring(msg), "\n", debug.traceback("", 2), "\n")
  return function() return 1 end
end
-- A picture of the composite, so an arena change can be LOOKED at before it
-- ships.
--
-- Three arena changes in a row were reasoned out on paper, shipped, and came
-- back "it looks really bad now" / "very broken".  Every one of them was a
-- rectangle in the wrong place, and every one of them would have been obvious
-- in one screenshot.  There is no ROM in this container so the cart cannot
-- boot -- but the arena's bar geometry does not need the cart.  It needs the
-- engine's numbers (tools/arenaview/engine.lua, transcribed with line
-- references), the real backdrop PNGs, and the real `bleedInto`.
--
-- Run:  xvfb-run -a love tools/arenaview --out /tmp/shots
--
-- Writes one PNG per case, and prints the rectangles it drew so a number can
-- be checked without opening the image.

local ROOT = (...) and "" or ""
package.path = "./?.lua;./tools/arenaview/?.lua;" .. package.path

local E = require("engine")

-- The case being composed.  The engine reads the window off
-- love.graphics.getDimensions and the playfield off the touch skin; here both
-- come from the case, so one process can render every display size.
local CURRENT = { w = 640, h = 480 }

local OUT = "arenaview"
for i = 1, #arg do
  if arg[i] == "--out" then OUT = arg[i + 1] end
end

-- LOVE resolves an image path inside its SOURCE directory, which when this is
-- run as `love tools/arenaview` is the harness folder and not the repo.  The
-- mod asks for "./assets/backdrops/...", relative to the repo root, and it is
-- right to: that is where it asks from inside a bundle.  So the real file is
-- read off the real filesystem and handed over as FileData, which is the one
-- difference between this harness and a cartridge.
local realDimensions = love.graphics.getDimensions
love.graphics.getDimensions = function() return CURRENT.w, CURRENT.h end
love.graphics.getWidth = function() return CURRENT.w end
love.graphics.getHeight = function() return CURRENT.h end

local realNewImageData = love.image.newImageData
love.image.newImageData = function(source, ...)
  if type(source) == "string" then
    local handle = io.open((source:gsub("^%./", "")), "rb")
    if not handle then error("no such file: " .. source, 0) end
    local bytes = handle:read("*a")
    handle:close()
    return realNewImageData(love.filesystem.newFileData(bytes, source), ...)
  end
  return realNewImageData(source, ...)
end

local realNewImage = love.graphics.newImage
love.graphics.newImage = function(source, ...)
  if type(source) == "string" then
    local handle = io.open((source:gsub("^%./", "")), "rb")
    if not handle then error("no such file: " .. source, 0) end
    local bytes = handle:read("*a")
    handle:close()
    return realNewImage(love.filesystem.newFileData(bytes, source), ...)
  end
  return realNewImage(source, ...)
end

-- ------------------------------------------------------------- the stubs
--
-- Only what `bleedInto` and the Gold arm reach for.  love.graphics is the
-- REAL one: that is the whole point.

local Letterbox
Letterbox = {
  mode = "auto",
  fill = function(r, g, b, paper)
    if Letterbox.mode == "black" then return 0, 0, 0 end
    if Letterbox.mode == "white" then return 1, 1, 1 end
    if Letterbox.mode == "palette" and paper then
      local pr, pg, pb = paper()
      if pr then return pr, pg, pb end
    end
    return r, g, b
  end,
}
package.loaded["src.render.Letterbox"] = Letterbox
package.loaded["src.render.PaletteFX"] = {
  paperShade = function() return 0.94, 0.94, 0.86 end,
  markTrueColor = function() end,
  setMarkOffset = function() end,
}
package.loaded["src.core.Game"] = { data = {} }
package.loaded["src.core.GameVersion"] = {
  generation = function() return 2 end,
  get = function() return "crystal" end,
  isYellow = function() return false end,
}
package.loaded["src.render.GbcPalette"] = {
  use = function() return true end, useKeyed = function() return true end,
}

-- Gold's Chrome, reduced to the calls the arm goes through.  paletteFill is a
-- REAL rectangle, because the arm's rectangleShim recognises the field by its
-- exact 0,0,w,h shape and nothing else.
local Chrome
Chrome = {
  SCREEN_W = 20, SCREEN_H = 18,
  DEFAULT_BOX_PALETTE = { {255,255,255},{255,255,255},{255,255,255},{0,0,0} },
  paletteFill = function(x, y, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x, y, w, h)
  end,
  printThrough = function(text, tx, ty)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", tx * 8, ty * 8, #tostring(text) * 8, 8)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", tx * 8, ty * 8 + 2, #tostring(text) * 8 - 2, 4)
    love.graphics.setColor(1, 1, 1, 1)
    return #tostring(text) * 8
  end,
}
Chrome.clear = function()
  Chrome.paletteFill(0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
end
Chrome.fitScaleFor = function(w, h, tw, th)
  return E.fitScaleFor(w, h, tw, th, CURRENT.skin)
end
Chrome.fitOriginFor = function(w, h, scale, tw, th)
  return E.fitOriginFor(w, h, scale, tw, th, CURRENT.skin)
end
Chrome.printRightThrough = Chrome.printThrough
package.loaded["src.ui.gen2.Chrome"] = Chrome
package.loaded["src.ui.gen2.BattleHud"] = {
  drawTile = function() return true end,
}
package.loaded["src.ui.gen2.BattleAnimView"] = { palVeil = function() return 0 end }

-- Gold's BattleState, reduced to the two things the arm wraps -- drawScene,
-- which is where the field is replaced, and drawPic -- plus a panel body that
-- paints WHERE the cart's chrome sits.  The chrome is schematic on purpose:
-- what this harness is asked about is which rectangle is which colour, and a
-- real glyph would only make that harder to read.
local BattleState = {}
BattleState.hasBattleSides = function(self) return self.battle ~= nil end
BattleState.wideLayout = function(self) return self.wide == true end
BattleState.drawScene = function(self, bodyFn)
  if bodyFn then bodyFn() else self:drawPanel() end
end
local function hudBox(x, y, w, h)
  local g = love.graphics
  g.setColor(1, 1, 1, 1); g.rectangle("fill", x, y, w, h)
  g.setColor(0, 0, 0, 1); g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  g.setColor(1, 1, 1, 1)
end
-- WideBattle.drawSurface, call for call (src/ui/gen2/WideBattle.lua:24):
-- the whole-surface palette fill, the 160-wide field clear at FIELD_X, the
-- pics, both HUDs, then drawBottom(EXTRA_TILES) -- whose message box is
-- `Chrome.box(0, 12, 20 + ox, 6)` (src/ui/gen2/BattleState.lua:4491), i.e.
-- tile row 12 for 6 rows across the FULL 38-tile width.
BattleState.drawPanel = function(self)
  local g = love.graphics
  local w = self.wide and E.WIDE_W or E.OG_W
  -- the field fill the arm substitutes the backdrop for
  Chrome.paletteFill(0, 0, w, E.OG_H)
  local fieldX = self.wide and E.FIELD_X or 0
  g.push()
  g.translate(fieldX, 0)
  Chrome.clear()                     -- the 160x144 field clear, also swallowed
  -- the two pics
  g.setColor(0, 0, 0, 0.75)
  g.rectangle("fill", 88, 8, 56, 56)
  g.rectangle("fill", 16, 40, 56, 56)
  g.setColor(1, 1, 1, 1)
  g.pop()
  hudBox(fieldX + 2, 8, 88, 28)          -- enemy HUD
  hudBox(fieldX + 72, 72, 86, 34)        -- player HUD
  if self.bottomUI ~= false then
    -- Chrome.box(0, 12, 20 + ox, 6): full width, tile rows 12..17.
    local ox = self.wide and E.EXTRA_TILES or 0
    hudBox(0, 12 * 8, (20 + ox) * 8, 6 * 8)
  end
end
BattleState.battlePanelScale = function(self, w, h)
  return E.battlePanelScale(w, h, self.wide, CURRENT.fill, CURRENT.skin)
end
BattleState.drawPic = function() end
BattleState.drawEnemyHud = function() end
BattleState.drawPlayerHud = function() end
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.ui.gen2.BattleState"] = BattleState

local mod = {
  id = "gen1arena", path = ".", exports = {}, stored = {}, hooked = {},
  events_on = {}, content = {},
}
mod.options = {
  define = function(_, rows) mod.rows = rows end,
  get = function(_, key) return mod.stored[key] end,
  set = function(_, key, value) mod.stored[key] = value end,
}
mod.log = {}
for _, level in ipairs({ "info", "warn", "error", "debug" }) do
  mod.log[level] = function(_, format, ...)
    io.write("  [", level, "] ",
      select("#", ...) > 0 and tostring(format):format(...) or tostring(format),
      "\n")
  end
end
mod.hooks = { wrap = function(_, name, fn) mod.hooked[name] = fn end }
mod.events = { on = function(_, name, fn) mod.events_on[name] = fn end }
mod.assets = { path = function(_, p) return p end }
mod.storage = { writeBytes = function() return true end }

-- ------------------------------------------------------------- the cases

local CASES = {}
local function case(name, opts) CASES[#CASES + 1] = { name = name, opts = opts } end

-- A phone held upright, with the on-screen pad's cutout, and the same phone
-- turned sideways.  Sizes are the ones the reports came from: a tall display
-- where the panel is small and the surround is most of the screen.
local PHONE_P = { w = 1080, h = 2340, skin = { x = 0, y = 0, w = 1080, h = 1500 } }
local PHONE_L = { w = 2340, h = 1080, skin = nil }
local DESKTOP = { w = 1600, h = 900, skin = nil }

local DISPLAYS = { { "phone-portrait", PHONE_P }, { "phone-landscape", PHONE_L },
                   { "desktop", DESKTOP } }

for _, d in ipairs(DISPLAYS) do
  for _, layout in ipairs({ "wide", "classic" }) do
    for _, fit in ipairs({ "fixed", "fill" }) do
      for _, lb in ipairs({ "auto", "black" }) do
        case(("%s-%s-%s-%s"):format(d[1], layout, fit, lb), {
          w = d[2].w, h = d[2].h, skin = d[2].skin,
          wide = layout == "wide", fill = fit == "fill", letterbox = lb,
        })
      end
    end
  end
end

-- The same screen with the cart's message box DOWN, which is what an attack
-- animation and the send-out both look like.  The bottom of the picture has
-- nothing over it there, and the wide backdrops are authored with a flat
-- band across their last 40 rows.
for _, d in ipairs(DISPLAYS) do
  case(("%s-wide-fixed-black-nobox"):format(d[1]), {
    w = d[2].w, h = d[2].h, skin = d[2].skin,
    wide = true, fill = false, letterbox = "black", bottomUI = false,
  })
end

-- ------------------------------------------------------------- the frame

local function compose(o)
  local g = love.graphics
  CURRENT = o
  Letterbox.mode = o.letterbox

  -- 1. src/ui/gen2/WideBattle.lua:49 -- Chrome.letterbox(w, h, 1, 1, 1).
  --    The WHOLE window, in the paper colour, through UI LETTERBOX.
  local lr, lg, lb = Letterbox.fill(1, 1, 1, function()
    return require("src.render.PaletteFX").paperShade()
  end)
  g.setColor(lr, lg, lb, 1)
  g.rectangle("fill", 0, 0, o.w, o.h)
  g.setColor(1, 1, 1, 1)

  -- 2. the panel, where the engine actually puts it.
  local px, py, pw, ph, scale, surfW, surfH = E.panelRect(o.w, o.h, o)
  local state = setmetatable({ battle = {}, wide = o.wide,
                               bottomUI = o.bottomUI },
                             { __index = BattleState })
  g.push("all")
  g.setScissor(px, py, pw, ph)
  g.translate(px, py)
  g.scale(scale, scale)
  local baseScene = BattleState.drawScene
  BattleState.drawScene(state, function() BattleState.drawPanel(state) end)
  g.pop()

  -- 3. the mod hook, with the payload Game2:letterbox really builds.
  local view = E.hookView(o.w, o.h, o)
  local hook = mod.hooked["render.letterbox"]
  if hook then hook(function() end, view) end

  return { panel = { px, py, pw, ph, scale }, view = view,
           surf = { surfW, surfH }, field = state.gen1wildArenaField }
end

function love.load()
  love.filesystem.createDirectory(OUT)
  local main = assert(io.open("main.lua", "r"))
  local source = main:read("*a"); main:close()
  assert(load(source, "@main.lua"))(mod)
  assert(mod.events_on["game.ready"], "no game.ready")
  mod.events_on["game.ready"]({ game = {} })
  assert(mod.hooked["render.letterbox"], "the letterbox hook is not installed")


  for _, c in ipairs(CASES) do
    local o = c.opts
    local canvas = love.graphics.newCanvas(o.w, o.h)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(1, 0, 1, 1)     -- magenta: anything unpainted is a bug
    -- The arm sets bleedImage on its way through drawScene; the hook claims it.
    local info = compose(o)
    love.graphics.setCanvas()
    local name = OUT .. "/" .. c.name .. ".png"
    canvas:newImageData():encode("png", name)
    io.write(("%-34s panel %d,%d %dx%d @%.3f   view %d,%d %dx%d @%d   field=%s\n")
      :format(c.name, info.panel[1], info.panel[2], info.panel[3],
              info.panel[4], info.panel[5], info.view.ox, info.view.oy,
              info.view.vpw, info.view.vph, info.view.scale,
              tostring(info.field)))
  end
  io.write("saved under ", love.filesystem.getSaveDirectory(), "/", OUT, "\n")
  love.event.quit()
end

function love.draw() end
