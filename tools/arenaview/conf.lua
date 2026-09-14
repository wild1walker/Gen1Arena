function love.conf(t)
  t.window.width, t.window.height = 640, 480
  t.window.visible = false
  t.identity = "arenaview"
  t.console = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.physics = false
  t.modules.joystick = false
end
