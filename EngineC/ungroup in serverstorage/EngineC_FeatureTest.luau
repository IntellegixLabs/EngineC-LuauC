#include EngineC,
#include Physics,
#include Graphics,
using physics from Physics,
using graphics from Graphics,

public demo run #
    var flags: maybe = {true, false}
    var void target = probe
    object Part[id = "probe"]
        size = {2, 4, 6}
        position = {1, 5, 2}
        color = "Bright blue"
    end
    physics.setVelocity[id = "probe", x = 0, y = 10, z = 0]
    graphics.glow[id = "probe", color = "Bright blue", brightness = 3]
end