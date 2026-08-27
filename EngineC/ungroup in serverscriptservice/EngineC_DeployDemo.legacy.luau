--!strict
--[[
	EngineC_DeployDemo
	Demonstrates Compiler.deploy(): every top-level EngineC declaration
	(var / class / public ... # ... end) is compiled to its OWN Script
	instance under ServerScriptService.ApplicationSupport, named
	<name>_<kind> ("maxSpeed_var", "PlayerRig_class", "bootstrap_function", ...).
	Those files require EngineC.Runtime themselves and run the moment
	they're created -- this script's job is just to compile + write them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EngineC = require(ReplicatedStorage.EngineC)

local NL = string.char(10)
local SOURCE = table.concat({
	'var maxSpeed: float = 42',
	'',
	'class PlayerRig[id="rig1"]',
	'    physics.body[id="rig1_phys", mass: float=80]',
	'        collider.box[size=1,2,1]',
	'        material["skin"]',
	'    end',
	'end',
	'',
	'public engine.core bootstrap[id="enginec_kernel"] #',
	'    engine.override["physics"]',
	'        engine.modify["solverIterations": int] >> 64 <<',
	'        engine.modify["gravityMode"] >> "custom" <<',
	'    end',
	'end',
	'',
	'public physics.sim black_hole_pair[id="bh_system"] #',
	'    model3d.sphere[id="bh1", radius=20]',
	'        physics.body[id="bh1_phys", mass: float=5000]',
	'        graphics.shader[id="bh1_shader"] >> "vortex" <<',
	'    end',
	'    model3d.sphere[id="bh2", radius=20]',
	'        physics.body[id="bh2_phys", mass: float=5000]',
	'        graphics.shader[id="bh2_shader"] >> "vortex" <<',
	'    end',
	'    physics.field.gravity[id="bh1"]',
	'        strength: float = 9000',
	'        falloff: float = 2.0',
	'        radius: float = 120',
	'    end',
	'    physics.field.gravity[id="bh2"]',
	'        strength: float = 9000',
	'        falloff: float = 2.0',
	'        radius: float = 120',
	'    end',
	'    physics.loop[id="bh_collision"]',
	'        attract["bh1", "bh2"]',
	'        merge["bh1", "bh2"]',
	'        graphics.distort["space"] >> 0.8 <<',
	'    end',
	'end',
}, NL)

print("[EngineC] deploying " .. #SOURCE .. " bytes of EngineC source ...")

local files = EngineC.Compiler.deploy(SOURCE)

for _, f in ipairs(files) do
	if f.ok then
		print("[EngineC]  ✓ ServerScriptService.ApplicationSupport." .. f.name)
	else
		warn("[EngineC]  ✗ " .. f.name .. " -- " .. tostring(f.error))
	end
end

print("[EngineC] deploy complete: " .. #files .. " file(s) written")
