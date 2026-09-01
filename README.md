## EngineC (LuauC)
part of IT26 program
this is in alpha open testing expect bugs please, also go to the issues page to report issues this is very much appreciated

EngineC (or LuauC, devs call it EngineC but the scripting language is LuauC) is a superset of Luau, with the scripting being semi-compiled, with functions being compiled into Luau, and stored into ApplicationSupport.

## How to use

First, download the .rbxm file from the releases page, and insert it into roblox studio, ungroup as instructed.
Then find the EngineC_StudioPlugin file, and save as a local plugin (this one is extremely buggy and I can't figure out how to fix it). Open up the plugin and you will find a script editor, once again, this is extremely experimental and buggy.
you might be better off creating a regular script and importing EngineC dependancies.

## CLI DEPRECIATED BTW!!!!!!!!!
Homebrew (mac only, i haven't managed to implement Windows support, uhh i will try to later on.)
```
brew install IntellegixLabs/homebrew-enginec/enginec
```

## VSCode Extention (Outsiders' Edition)
this includes compiler and the colouring thingy, find in [Releases](https://github.com/IntellegixLabs/EngineC-roblox-LuauC/releases) page. (GET THE FIXED VERSION PLEASE)
the VSCode Extention MAY have stuff differentiating from the Roblox Studio edition.

to install it, go to the vscode extentions tab, go to those 3 dots on the top right side of the tab, then click it, then press "install from VSIX", select the .vsix file and you SHOULD be good to go (hopefully).

go to the bottom to see more about Outsiders' Edition

## Syntax

In LuauC, you have to first write (only if u are doing this is a regular luau script) `
``local ReplicatedStorage = game:GetService("ReplicatedStorage")``

`local EngineC = require(ReplicatedStorage.EngineC)`

ehh it might be very buggy, and with alot of flagging by roblox studio since it does not recognize most of the syntaxes.

Afterwards, no matter if you are using the EngineC you will need to use the `#include EngineC` line right at the start, this should tell EngineC to use the LuauC compiler.

the entire block in the lexer for syntaxes is just:
`local KEYWORDS = {
	["end"] = true, ["public"] = true, ["local"] = true, ["function"] = true,
	["namespace"] = true, ["pipeline"] = true, ["true"] = true, ["false"] = true,
	["int"] = true, ["float"] = true, ["bool"] = true, ["string"] = true,
	["class"] = true, ["var"] = true, ["using"] = true, ["from"] = true, ["plugin"] = true,
	["maybe"] = true, ["nil"] = true, ["vector"] = true,
	["static"] = true, ["enum"] = true, ["void"] = true, ["object"] = true,
}`

doc:
# EngineC README Fixes
Tested against the actual compiler/runtime. Found two actual issues.

## 1. Syntax for functions wrappers
All examples of physics, graphics, `object`, GUI, event handlers and `public DataStore` in the README are presented without the needed `public` function wrapper.
It will produce the following error:

`EngineC structure error: top-level X must be inside a class, variable, or function`

The compiler allows only `#include`, `using`, `var`, `class`, `static class`, `enum` and `public` (function) declarations at top level. Everything else must go into the following form:

```
public <Namespace> <name>[args] #
    ... your code ...
end
```

**Fix:** Add a "Functions" section with this syntax, and wrap all existing examples with that syntax.

## 2. `object` does not replace on id reuse
In contrast to `createSphere` and `createMesh`, `Runtime.objectCreate` does not check for the existence of an object with the same `id` before creating new Part. Double `object Part[id="x"]` declaration leaves a duplicated Part in `Workspace.EngineC_Sim` rather than replace old one.

**Fix:** Add such check to `objectCreate`, like in `createSphere` and `createMesh`.
# EngineC v0.1

The EngineC watermark is applied to running games and exported assets, not the Studio authoring plugin UI.

## Quick start
Every EngineC source must begin with:

`#include EngineC`

Compile source through the EngineC compiler or the Live Parser plugin. EngineC source is stored as raw text in a ModuleScript or StringValue; it is not normal Luau.

## Imports
Multiple includes use separate lines and commas:

```
#include EngineC,
#include Physics,
#include Graphics,
using physics from Physics,
using graphics from Graphics,
```

Extra libraries live in ReplicatedStorage.AdditionalDependencies.
`using metadistro` is built in and starts per-player profiling.

## Values and variables
```
var speed: int = 30`
var ratio: float = 0.5
var enabled: bool = true
var title: string = "Runner"
var optional: maybe = nil`
```

`int` is numeric. `maybe` is optional and can contain `nil`.

## Arrays
Arrays use DreamBerd-style indexes. The first item is `-1`, then `0`, then `1`:

`var flags: maybe = {true, false}`

## Classes and enums
```
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
```
Unnamed classes must be nested in a named class or function.

## Void references
`void` is a safe EngineC object reference. No `*` or `&` is needed:

`var void target = probe`

References resolve to EngineC runtime objects; they are not raw memory pointers.

## Declarative objects
```
object Part[id = "probe"]
    size = {2, 4, 6}
    position = {1, 5, 2}
    color = "Bright blue"
end
```
## Physics
```
physics.setVelocity[id = "probe", x = 0, y = 10, z = 0]
physics.impulse[id = "probe", x = 0, y = 25, z = 0]
```
Other physics commands include model3d.sphere, physics.body, gravity fields, forces, and simulation loops.

## Graphics
```
graphics.glow[id = "probe", color = "Bright blue", brightness = 3]
graphics.trail[id = "probe", lifetime = 0.25]
graphics.shader[id = "probe"] >> "vortex" <<
```
## Engine controls
Engine controls accept values or Luau source strings:
```
engine.physics.solverIterations:: >> 12 <<
engine.physics.gravity:: >> 98.1 <<
engine.graphics.renderSubdivisions:: >> 4 <<
engine.graphics.blur:: >> false <<
engine.performance.smooth:: >> true <<

```
Vectors use `::vector::`:

`engine.physics.gravityDirection::vector:: >> {0, -1, 0} <<`

## GUI markup
```
using gui from EngineC,

gui.window[id = "main", size = {400, 200}]
    gui.layout.vertical[spacing = 12]
        gui.text[id = "title"] >> "EngineC Control Center" <<
        gui.button[id = "go"] >> "Go" <<
        gui.slider[id = "scale", min = 1, max = 200]
    end
end
```
## Functional event handlers
```
on.click[target = "go"]
    physics.impulse[id = "probe", x = 0, y = 10, z = 0]
end

on.change[target = "scale"]
    engine.graphics.renderSubdivisions:: >> 2 <<
end
```
## Persistent data

public DataStore:["user-123"] = 30

This uses Roblox DataStoreService and requires a published experience with Studio API access enabled.

## Plugins
After including a dependency, call its functions with:

`plugin TestPlugin.greet[name = "hello"]`

Plugins are ModuleScripts inside AdditionalDependencies.

## MetaDistro
```
#include EngineC
using metadistro

```
The server assigns each player a potato, okay, medium, high, or immortal tier and stores the tier and metadata budget on the Player. Roblox does not permit arbitrary client file uploads, so MetaDistro distributes server-owned content tiers instead.

## Live Parser plugin (depreciated)
Export and install ServerStorage.EngineC_LiveParserPlugin as a Studio local plugin. Select an EngineC script, then use:

`liveparse (game.ServerStorage.EngineC_FeatureTest)`
`export (game.ServerStorage.EngineC_FeatureTest)`

The plugin previews GUI markup, reparses on edits, and packages EngineC plus AdditionalDependencies.


















## Outsiders' Edition 
wow, you came!


## What this even is:

This is a Edition made for VSCode and to work outside of roblox studio, this is primarily so that roblox studio will stop screaming at developers during use, i have indeed resulted to remove the GUI Markup features and sort of started again from scratch, so alot of things may differentiate. i genuinely think the already existing GUI maker in roblox studio is decent enough, i don't really want to recreate React Native but for roblox studio or something like that.

## Why the name:

its outside of roblox studio



## Why VS Code?

Studio plugins were unreliable, and Roblox Studio kept reporting EngineC syntax errors. In addition, switching to VS Code offers:
- Distract-free environment
- Real-time syntax highlighting and suggestions
- Automatic compilation to Luau
- Pre-installed compiler (no extra dependencies needed)
- USAGE OUTSIDE OF ROBLOX STUDIO YES YES YES YES LETS GOO YES YES YES YES YES YES YES YES YES - README.md writer, IntellegixLabs

## Changes from Previous Editions

This version is all about the core features of the language and drops:
- GUI markup (native tools are enough in Roblox Studio)
- Built-in bindings for physics and graphics
- Live parser plugin
- Studio plugin

yes, i will try to re-implement physics and graphics with a new library and dependancy(s)
i need to take a short break

## Features

- **Typed variables**: `int`, `number`, `local`
- **Arrays**: DreamBerd style indexing `-1`, `0`, `1`
- **Dependency system**: `#include` for MainDependancies and AdditionalDependancies
- **Automatic compiling**: compiles `.ec` to `.lua` upon saving the file
- Syntax highlighting and code suggestions
- Automatic formatting (WIP, very buggy, only works like 0.0000001% of the time, or just never.): smart insertion of blocks for classes and functions

## Example Code

```ec
#include EngineC

local arr = {1, 2, 3}
local first = arr[-1]

class MyClass
end
```

Installation of `.vsix` in VS Code -> Open `.ec` files -> Compile using `Cmd + Alt + C` (for macOS)(does thy shortcut work? Yesn't).

## Dependencies

Additional Lua modules should be added to `AdditionalDependancies/` and included with `#include` and `using`.
