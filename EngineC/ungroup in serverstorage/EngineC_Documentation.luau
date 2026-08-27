return [[
# EngineC v0.1

The EngineC watermark is applied to running games and exported assets, not the Studio authoring plugin UI.

## Quick start
Every EngineC source must begin with:

#include EngineC

Compile source through the EngineC compiler or the Live Parser plugin. EngineC source is stored as raw text in a ModuleScript or StringValue; it is not normal Luau.

## Imports
Multiple includes use separate lines and commas:

#include EngineC,
#include Physics,
#include Graphics,
using physics from Physics,
using graphics from Graphics,

Extra libraries live in ReplicatedStorage.AdditionalDependencies.
`using metadistro` is built in and starts per-player profiling.

## Values and variables

var speed: int = 30
var ratio: float = 0.5
var enabled: bool = true
var title: string = "Runner"
var optional: maybe = nil

`int` is numeric. `maybe` is optional and can contain `nil`.

## Arrays
Arrays use DreamBerd-style indexes. The first item is -1, then 0, then 1:

var flags: maybe = {true, false}

## Classes and enums

class PlayerRig
    var health: int = 100
end

class PlayerRig
    class [int = 30]
        var armor: int = 5
    end
end

static class GraphicsConfig
    var quality: int = 3
end

enum RenderMode [Basic = 1, Cinematic = 2]

Unnamed classes must be nested in a named class or function.

## Void references
`void` is a safe EngineC object reference. No `*` or `&` is needed:

var void target = probe

References resolve to EngineC runtime objects; they are not raw memory pointers.

## Declarative objects

object Part[id = "probe"]
    size = {2, 4, 6}
    position = {1, 5, 2}
    color = "Bright blue"
end

## Physics

physics.setVelocity[id = "probe", x = 0, y = 10, z = 0]
physics.impulse[id = "probe", x = 0, y = 25, z = 0]

Other physics commands include model3d.sphere, physics.body, gravity fields, forces, and simulation loops.

## Graphics

graphics.glow[id = "probe", color = "Bright blue", brightness = 3]
graphics.trail[id = "probe", lifetime = 0.25]
graphics.shader[id = "probe"] >> "vortex" <<

## Engine controls
Engine controls accept values or Luau source strings:

engine.physics.solverIterations:: >> 12 <<
engine.physics.gravity:: >> 98.1 <<
engine.graphics.renderSubdivisions:: >> 4 <<
engine.graphics.blur:: >> false <<
engine.performance.smooth:: >> true <<

Vectors use `::vector::`:

engine.physics.gravityDirection::vector:: >> {0, -1, 0} <<

## GUI markup

using gui from EngineC,

gui.window[id = "main", size = {400, 200}]
    gui.layout.vertical[spacing = 12]
        gui.text[id = "title"] >> "EngineC Control Center" <<
        gui.button[id = "go"] >> "Go" <<
        gui.slider[id = "scale", min = 1, max = 200]
    end
end

## Functional event handlers

on.click[target = "go"]
    physics.impulse[id = "probe", x = 0, y = 10, z = 0]
end

on.change[target = "scale"]
    engine.graphics.renderSubdivisions:: >> 2 <<
end

## Persistent data

public DataStore:["user-123"] = 30

This uses Roblox DataStoreService and requires a published experience with Studio API access enabled.

## Plugins
After including a dependency, call its functions with:

plugin TestPlugin.greet[name = "hello"]

Plugins are ModuleScripts inside AdditionalDependencies.

## MetaDistro

#include EngineC
using metadistro

The server assigns each player a potato, okay, medium, high, or immortal tier and stores the tier and metadata budget on the Player. Roblox does not permit arbitrary client file uploads, so MetaDistro distributes server-owned content tiers instead.

## Live Parser plugin
Export and install ServerStorage.EngineC_LiveParserPlugin as a Studio local plugin. Select an EngineC script, then use:

liveparse (game.ServerStorage.EngineC_FeatureTest)
export (game.ServerStorage.EngineC_FeatureTest)

The plugin previews GUI markup, reparses on edits, and packages EngineC plus AdditionalDependencies.

EngineC v0.1 | powered by EngineC
]]