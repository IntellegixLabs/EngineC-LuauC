--!strict
--[[
	EngineC.Runtime
	Stage 6 of the pipeline: the kernel-level hook layer. This is what the
	Luau CodeGen output actually calls into -- real Roblox engine access for
	physics (custom gravity/vortex/radial force solvers), graphics (shader-
	style visual approximations via particles/lighting), and the per-step
	simulation loop.

	Everything here uses genuine Roblox APIs (RunService.Heartbeat,
	BasePart/AssemblyLinearVelocity, Attachment/VectorForce, ParticleEmitter,
	PointLight, Lighting post-effects) -- there is no such thing as a custom
	Roblox physics/graphics "engine override" at the C++ level from Lua, so
	this layer implements the closest real analogue for each EngineC feature:
	  - engine.modify["solverIterations"]  -> Workspace:SetAttribute + used to
	    scale our own iterative solver's substeps
	  - engine.modify["gravityMode"]="custom" -> disables Workspace.Gravity,
	    routes gravity entirely through registered gravity_field sources
	  - graphics.shader >> "vortex" <<     -> spin + particle + light rig
	  - graphics.distort["space"]          -> Lighting blur/color post-fx
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Runtime = {}

-- ===== registries =====
Runtime.objects = {} :: { [string]: any }      -- id -> { part, radius, mass, gravity, merged }
Runtime.loops = {} :: { [string]: RBXScriptConnection }
Runtime._lastDt = 1 / 60                        -- updated every Heartbeat; read by attract()
Runtime.engineState = {
	solverIterations = 8,
	gravityMode = "default",
}

function Runtime.deref(pointer: any): any
	if type(pointer) == "table" and type(pointer.__EngineCPointer) == "string" then
		return Runtime.objects[pointer.__EngineCPointer]
	end
	return pointer
end

local function getContainer(): Folder
	local ws = Workspace
	local f = ws:FindFirstChild("EngineC_Sim")
	if not f then
		f = Instance.new("Folder")
		f.Name = "EngineC_Sim"
		f.Parent = ws
	end
	return f :: Folder
end

-- ===== 3D modeling =====
local function createSphere(id: string, args: { [string]: any })
	-- Clean up existing object with same id to prevent orphaned parts
	local existing = Runtime.objects[id]
	if existing and existing.part then
		existing.part:Destroy()
	end
	local radius = tonumber(args.radius) or 4
	local part = Instance.new("Part")
	part.Name = id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.Position = Vector3.new((#Runtime.objects) * (radius * 3), radius + 5, 0)
	part.Anchored = false
	part.CanCollide = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromHSV(math.random(), 0.6, 1)
	part.Parent = getContainer()

	Runtime.objects[id] = { part = part, radius = radius, mass = 1, id = id }
	return part
end

local function createMesh(id: string, args: { [string]: any })
	-- simplified: a mesh block acts as a generic solid placeholder
	-- Clean up existing object with same id to prevent orphaned parts
	local existing = Runtime.objects[id]
	if existing and existing.part then
		existing.part:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = id
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(4, 4, 4)
	part.Anchored = false
	part.Parent = getContainer()
	Runtime.objects[id] = { part = part, radius = 2, mass = 1, id = id }
	return part
end

function Runtime.batchCreate(items: { any })
	for _, item in ipairs(items) do
		if item.kind == "create_sphere" then
			createSphere(item.id, item.args)
		elseif item.kind == "create_mesh" then
			createMesh(item.id, item.args)
		end
	end
end

-- ===== declarative objects =====
local function objectCreate(id: string, _parent: string?, args: { [string]: any })
	if args._objectType ~= "Part" then
		error("object currently supports only Part")
	end
	local container = getContainer()
	local part = Instance.new("Part")
	part.Name = id
	local size = args.size
	if type(size) == "table" then
		part.Size = Vector3.new(tonumber(size[-1]) or 4, tonumber(size[0]) or 4, tonumber(size[1]) or 4)
	end
	if type(args.position) == "table" then
		part.Position = Vector3.new(tonumber(args.position[-1]) or 0, tonumber(args.position[0]) or 5, tonumber(args.position[1]) or 0)
	end
	if type(args.color) == "string" then
		local ok, brickColor = pcall(BrickColor.new, args.color)
		if ok then part.BrickColor = brickColor end
	end
	part.Parent = container
	Runtime.objects[id] = { part = part, radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2, mass = 1, id = id }
end

-- ===== physics =====
local function physicsBody(id: string, parentId: string?, args: { [string]: any })
	local mass = tonumber(args.mass) or 1
	local target = parentId and Runtime.objects[parentId]
	if target and target.part then
		local part: BasePart = target.part
		local volume = math.max(part.Size.X * part.Size.Y * part.Size.Z, 0.01)
		local density = math.clamp(mass / volume, 0.01, 100)
		part.CustomPhysicalProperties = PhysicalProperties.new(density, 0.3, 0.5, 1, 1)
		target.mass = mass
	end
end

local function physicsImpulse(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if not (target and target.part) then
		error("physics.impulse target was not found: " .. tostring(id))
	end
	local impulse = Vector3.new(tonumber(args.x) or 0, tonumber(args.y) or 0, tonumber(args.z) or 0)
	target.part.AssemblyLinearVelocity += impulse
end

local function physicsVelocity(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if not (target and target.part) then
		error("physics.setVelocity target was not found: " .. tostring(id))
	end
	target.part.AssemblyLinearVelocity = Vector3.new(tonumber(args.x) or 0, tonumber(args.y) or 0, tonumber(args.z) or 0)
end

local function gravityField(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if target then
		target.gravity = {
			strength = tonumber(args.strength) or 1000,
			falloff = tonumber(args.falloff) or 2,
			radius = tonumber(args.radius) or 100,
		}
	end
end

local function vortexForce(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if target then
		target.vortex = {
			spin = tonumber(args.spin) or 1,
			pull = tonumber(args.pull) or 1,
			turbulence = tonumber(args.turbulence) or 0,
		}
	end
end

local function radialForce(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if target then
		target.radial = {
			strength = tonumber(args.strength) or 1,
			radius = tonumber(args.radius) or 50,
		}
	end
end

-- mutual attraction between two named bodies (used inside physics.loop)
local function attract(idA: string, idB: string)
	local a, b = Runtime.objects[idA], Runtime.objects[idB]
	if not (a and b) or a.merged or b.merged then return end
	if not (a.part and b.part) then return end
	local delta = b.part.Position - a.part.Position
	local dist = math.max(delta.Magnitude, 1)
	local dir = delta.Unit
	local forceMag = ((a.mass or 1) * (b.mass or 1)) / (dist * dist) * 0.5
	local dt = Runtime._lastDt
	a.part.AssemblyLinearVelocity += dir * forceMag * dt
	b.part.AssemblyLinearVelocity -= dir * forceMag * dt
end

-- merges two bodies once they're close enough: survivor absorbs mass/volume, loser destroyed
local function mergeBodies(idA: string, idB: string)
	local a, b = Runtime.objects[idA], Runtime.objects[idB]
	if not (a and b) or a.merged or b.merged then return end
	if not (a.part and b.part) then return end
	local dist = (a.part.Position - b.part.Position).Magnitude
	if dist > (a.radius + b.radius) * 0.6 then return end

	local survivor, loser = a, b
	if b.mass > a.mass then survivor, loser = b, a end

	local newMass = (survivor.mass or 1) + (loser.mass or 1)
	local newRadius = ((survivor.radius or 1) ^ 3 + (loser.radius or 1) ^ 3) ^ (1 / 3)
	survivor.mass = newMass
	survivor.radius = newRadius
	if survivor.part then
		survivor.part.Size = Vector3.new(newRadius * 2, newRadius * 2, newRadius * 2)
		local volume = math.max(survivor.part.Size.X * survivor.part.Size.Y * survivor.part.Size.Z, 0.01)
		survivor.part.CustomPhysicalProperties = PhysicalProperties.new(
			math.clamp(newMass / volume, 0.01, 100), 0.3, 0.5, 1, 1)
	end

	loser.merged = true
	if loser.part then
		loser.part:Destroy()
	end
end

-- ===== graphics =====
local function applyShader(id: string, parentId: string?, styleName: any)
	local target = parentId and Runtime.objects[parentId]
	if not (target and target.part) then return end
	local part: BasePart = target.part

	if styleName == "vortex" then
		local light = Instance.new("PointLight")
		light.Color = part.Color
		light.Range = part.Size.X * 3
		light.Brightness = 3
		light.Parent = part

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(part.Color)
		emitter.Lifetime = NumberRange.new(0.5, 1.2)
		emitter.Rate = 40
		emitter.Speed = NumberRange.new(2, 6)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = part

		local av = Instance.new("BodyAngularVelocity")
		av.AngularVelocity = Vector3.new(0, 8, 0)
		av.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
		av.Parent = part
	end
end

local function graphicsGlow(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if not (target and target.part) then
		error("graphics.glow target was not found: " .. tostring(id))
	end
	local color = target.part.Color
	if type(args.color) == "string" then
		local ok, brickColor = pcall(BrickColor.new, args.color)
		if ok then
			color = brickColor.Color
		end
	end
	local light = target.part:FindFirstChild("EngineC_Glow") or Instance.new("PointLight")
	light.Name = "EngineC_Glow"
	light.Color = color
	light.Brightness = tonumber(args.brightness) or 2
	light.Range = tonumber(args.range) or 16
	light.Parent = target.part
end

local function graphicsTrail(id: string, args: { [string]: any })
	local target = Runtime.objects[id]
	if not (target and target.part) then
		error("graphics.trail target was not found: " .. tostring(id))
	end
	local attachment0 = target.part:FindFirstChild("EngineC_TrailA") or Instance.new("Attachment")
	attachment0.Name = "EngineC_TrailA"
	attachment0.Position = Vector3.new(0, 1, 0)
	attachment0.Parent = target.part
	local attachment1 = target.part:FindFirstChild("EngineC_TrailB") or Instance.new("Attachment")
	attachment1.Name = "EngineC_TrailB"
	attachment1.Position = Vector3.new(0, -1, 0)
	attachment1.Parent = target.part
	local trail = target.part:FindFirstChild("EngineC_Trail") or Instance.new("Trail")
	trail.Name = "EngineC_Trail"
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = tonumber(args.lifetime) or 0.5
	trail.Parent = target.part
end

local function particleEmit(args: { [string]: any })
	local rate = tonumber(args.rate) or 20
	local color = args.color
	local container = getContainer()
	local anchor = Instance.new("Part")
	anchor.Name = (args.id or "emitter") .. "_anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = container
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = rate
	if type(color) == "string" then
		local ok, c3 = pcall(function() return BrickColor.new(color).Color end)
		if ok then emitter.Color = ColorSequence.new(c3) end
	end
	emitter.Parent = anchor
end

-- global "space distortion" visual: approximated via Lighting post-processing
local function distortSpace(intensity: number)
	local blur = Lighting:FindFirstChild("EngineC_Blur") :: BlurEffect?
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "EngineC_Blur"
		blur.Parent = Lighting
	end
	blur.Size = math.clamp(intensity * 24, 0, 56)

	local cc = Lighting:FindFirstChild("EngineC_ColorCorrection") :: ColorCorrectionEffect?
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "EngineC_ColorCorrection"
		cc.Parent = Lighting
	end
	cc.Saturation = -math.clamp(intensity, 0, 1) * 0.5
	cc.Contrast = math.clamp(intensity, 0, 1) * 0.3
end

local function warp(intensity: number)
	distortSpace(intensity)
end

-- ===== engine control =====
function Runtime.engineOverride(subsystem: any, mods: { { key: string, value: any } })
	for _, m in ipairs(mods) do
		local k = m.key
		if k == "solverIterations" then
			Runtime.engineState.solverIterations = tonumber(m.value) or Runtime.engineState.solverIterations
		elseif k == "gravityMode" then
			Runtime.engineState.gravityMode = m.value
			if m.value == "custom" then
				Workspace.Gravity = 0
			else
				Workspace.Gravity = 196.2 -- restore default Roblox gravity
			end
		elseif k == "renderSubdivisions" then
			Runtime.engineState.renderSubdivisions = tonumber(m.value)
		end
	end
end

-- ===== simulation loop =====
function Runtime.startLoop(id: string, stepFn: (dt: number) -> ())
	if Runtime.loops[id] then
		Runtime.loops[id]:Disconnect()
	end
	Runtime.loops[id] = RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(stepFn, dt)
		if not ok then
			warn("[EngineC] sim_loop '" .. id .. "' error: " .. tostring(err))
		end
	end)
end

function Runtime.stopLoop(id: string)
	if Runtime.loops[id] then
		Runtime.loops[id]:Disconnect()
		Runtime.loops[id] = nil
	end
end

-- global per-frame gravity solver driven by registered gravity_field sources
-- solverIterations controls substep count for numerical stability
RunService.Heartbeat:Connect(function(dt: number)
	Runtime._lastDt = dt
	local substeps = math.clamp(Runtime.engineState.solverIterations, 1, 16)
	local subDt = dt / substeps
	for _ = 1, substeps do
		for sourceId, source in pairs(Runtime.objects) do
			if source.gravity and source.part and not source.merged then
				local g = source.gravity
				for otherId, other in pairs(Runtime.objects) do
					if otherId ~= sourceId and other.part and not other.merged then
						local delta = source.part.Position - other.part.Position
						local dist = delta.Magnitude
						if dist < g.radius and dist > 0.1 then
							local falloffFactor = 1 / (dist ^ g.falloff)
							local accel = g.strength * falloffFactor
							other.part.AssemblyLinearVelocity += delta.Unit * accel * subDt
						end
					end
				end
			end
		end
	end
end)

local function writePublicData(storeName: string, args: { [string]: any })
	local key = args.key
	if key == nil then
		error("public DataStore requires a key")
	end
	local store = DataStoreService:GetDataStore(storeName)
	store:SetAsync(tostring(key), args.value)
end

local function callPlugin(path: string, args: { [string]: any })
	local libraryName, memberPath = path:match("^([^.]+)%.(.+)$")
	if not libraryName or not memberPath then
		error("plugin call must use Library.member syntax")
	end
	local package = script.Parent.Parent
	local folder = package:FindFirstChild("AdditionalDependencies")
		or game:GetService("ReplicatedStorage"):WaitForChild("AdditionalDependencies")
	local module = folder:FindFirstChild(libraryName)
	if not module or not module:IsA("ModuleScript") then
		error(("plugin library %s was not found in AdditionalDependencies"):format(libraryName))
	end
	local current = require(module)
	for segment in string.gmatch(memberPath, "[^.]+") do
		if type(current) ~= "table" then
			error(("plugin member %s is not a table"):format(segment))
		end
		current = current[segment]
	end
	if type(current) ~= "function" then
		error(("plugin member %s is not callable"):format(path))
	end
	local callArgs = {}
	for key, value in pairs(args) do
		if key ~= "_pluginPath" then
			callArgs[key] = value
		end
	end
	current(callArgs)
end

local function guiParent(parentId: string?): Instance
	if parentId then
		local parent = Runtime.objects[parentId]
		if parent and parent.instance then
			return parent.instance
		end
	end
	error("GUI parent was not found")
end

local function guiSize(args: { [string]: any }): UDim2
	local size = args.size
	if type(size) == "table" then
		return UDim2.fromOffset(tonumber(size[-1]) or 100, tonumber(size[0]) or 100)
	end
	return UDim2.fromOffset(tonumber(args.width) or 100, tonumber(args.height) or 40)
end

local function createGuiWindow(id: string, args: { [string]: any })
	local existing = StarterGui:FindFirstChild("EngineC_" .. id)
	if existing then
		existing:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "EngineC_" .. id
	screen.ResetOnSpawn = false
	screen.Parent = StarterGui
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.Size = guiSize(args)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	frame.Parent = screen
	Runtime.objects[id] = { kind = "gui", instance = frame, screen = screen }
end

local function createGuiPanel(id: string, parentId: string?, args: { [string]: any })
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.Size = guiSize(args)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	frame.Parent = guiParent(parentId)
	Runtime.objects[id] = { kind = "gui", instance = frame }
end

local function createGuiLayout(id: string, parentId: string?, direction: Enum.FillDirection, args: { [string]: any })
	local container = guiParent(parentId)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, tonumber(args.spacing) or 0)
	layout.Parent = container
	Runtime.objects[id] = { kind = "gui_layout", instance = container, layout = layout }
end

local function createGuiText(id: string, parentId: string?, args: { [string]: any })
	local label = Instance.new("TextLabel")
	label.Name = id
	label.Size = UDim2.new(1, 0, 0, 32)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = tostring(args.value or "")
	label.Parent = guiParent(parentId)
	Runtime.objects[id] = { kind = "gui", instance = label }
end

local function createGuiButton(id: string, parentId: string?, args: { [string]: any })
	local button = Instance.new("TextButton")
	button.Name = id
	button.Size = UDim2.new(1, 0, 0, 36)
	button.Text = tostring(args.value or "")
	button.Parent = guiParent(parentId)
	Runtime.objects[id] = { kind = "gui", instance = button }
end

local function createGuiSlider(id: string, parentId: string?, args: { [string]: any })
	local slider = Instance.new("TextBox")
	slider.Name = id
	slider.Size = UDim2.new(1, 0, 0, 32)
	slider.Text = tostring(args.min or 0)
	slider.PlaceholderText = "slider"
	slider:SetAttribute("Min", args.min or 0)
	slider:SetAttribute("Max", args.max or 100)
	slider.Parent = guiParent(parentId)
	Runtime.objects[id] = { kind = "gui", instance = slider }
end

function Runtime.bindEvent(id: string, args: { [string]: any }, handler: () -> ())
	local targetId = args.target
	if type(targetId) ~= "string" then
		error("event handler requires a target")
	end
	local targetObject = Runtime.objects[targetId]
	if not (targetObject and targetObject.instance) then
		error("event target was not found: " .. targetId)
	end
	local instance = targetObject.instance
	local runHandler = handler
	local eventPath = args._eventPath
	if eventPath == "on.click" and instance:IsA("GuiButton") then
		instance.Activated:Connect(runHandler)
	elseif eventPath == "on.change" and instance:IsA("TextBox") then
		instance.FocusLost:Connect(runHandler)
	else
		error("event type is not supported by target: " .. eventPath)
	end
end

local META_TIERS = {
	{ name = "potato", threshold = 0.25, budget = 8 },
	{ name = "okay", threshold = 0.5, budget = 24 },
	{ name = "medium", threshold = 0.7, budget = 56 },
	{ name = "high", threshold = 0.88, budget = 110 },
	{ name = "immortal", threshold = 1, budget = 220 },
}

local function applyMetaTier(player: Player, score: number)
	local normalized = math.clamp(score, 0, 1)
	local selected = META_TIERS[1]
	for _, tier in ipairs(META_TIERS) do
		if normalized >= tier.threshold then
			selected = tier
		end
	end
	player:SetAttribute("EngineC_MetaDistroTier", selected.name)
	player:SetAttribute("EngineC_MetadataBudget", selected.budget)
end

local function profileMetaDistro()
	if not RunService:IsServer() then
		return
	end
	local reportEvent = game:GetService("ReplicatedStorage"):FindFirstChild("EngineC_MetaDistroReport")
	if not reportEvent then
		reportEvent = Instance.new("RemoteEvent")
		reportEvent.Name = "EngineC_MetaDistroReport"
		reportEvent.Parent = game:GetService("ReplicatedStorage")
	end
	local remote = reportEvent :: RemoteEvent
	if not remote:GetAttribute("EngineC_Connected") then
		remote:SetAttribute("EngineC_Connected", true)
		remote.OnServerEvent:Connect(function(player, score)
			if type(score) == "number" then
				applyMetaTier(player, score)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		applyMetaTier(player, 0)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		applyMetaTier(player, 0)
	end
	Workspace:SetAttribute("EngineC_MetaDistroProfiled", true)
end

function Runtime.profileHardware()
	profileMetaDistro()
end

local function engineControl(path: string, value: any)
	local control = path:gsub("::vector::$", ""):gsub("::$", "")
	if control == "engine.physics.solverIterations" then
		Runtime.engineOverride("physics", { { key = "solverIterations", value = value } })
	elseif control == "engine.physics.gravity" then
		Workspace.Gravity = tonumber(value) or Workspace.Gravity
	elseif control == "engine.physics.gravityDirection" and typeof(value) == "Vector3" then
		Runtime.engineState.gravityDirection = value
		Workspace:SetAttribute("EngineC_GravityDirection", value)
	elseif control == "engine.graphics.renderSubdivisions" then
		Runtime.engineState.renderSubdivisions = tonumber(value) or Runtime.engineState.renderSubdivisions
	elseif control == "engine.graphics.blur" then
		local blur = Lighting:FindFirstChild("EngineC_Blur") :: BlurEffect?
		if blur then
			if type(value) == "boolean" then
				blur.Enabled = value
			else
				blur.Enabled = true
				blur.Size = math.clamp(tonumber(value) or 0, 0, 56)
			end
		end
	elseif control == "engine.performance.smooth" then
		Workspace:SetAttribute("EngineC_SmoothGameplay", value == true)
	else
		warn("[EngineC] unsupported engine control: " .. path)
	end
end

-- ===== opcode dispatch table (called from CodeGen-emitted Luau) =====
local DISPATCH: { [string]: (id: string?, parent: string?, args: { [string]: any }) -> () } = {
	create_sphere = function(id, _parent, args) createSphere(id :: string, args) end,
	create_mesh = function(id, _parent, args) createMesh(id :: string, args) end,
	object_create = function(id, parent, args) objectCreate(id :: string, parent, args) end,
	build_model = function(id, _parent, args) createMesh(id :: string, args) end,
	import_model = function(id, _parent, args) createMesh(id :: string, args) end,

	physics_body = function(id, parent, args) physicsBody(id :: string, parent, args) end,
	physics_impulse = function(id, _parent, args) physicsImpulse(id :: string, args) end,
	physics_velocity = function(id, _parent, args) physicsVelocity(id :: string, args) end,
	gravity_field = function(id, _parent, args) gravityField(id :: string, args) end,
	vortex_force = function(id, _parent, args) vortexForce(id :: string, args) end,
	radial_force = function(id, _parent, args) radialForce(id :: string, args) end,

	joint_hinge = function() end,
	joint_ball = function() end,
	joint_spring = function() end,
	joint_prismatic = function() end,
	collider_box = function() end,
	collider_sphere = function() end,
	primitive_cube = function() end,
	material = function() end,
	connect = function() end,
	axis = function() end,
	limit = function() end,
	pipeline = function() end,
	["physics.force.radial.apply"] = function() end,
	["physics.force.vortex.apply"] = function() end,
	["joint.hinge.damp"] = function() end,

	function_decl = function(id, _parent, _args) Runtime.objects[id] = Runtime.objects[id] or { kind = "function" } end,
	class_decl = function(id, parent, args)
		local classObject = Runtime.objects[id] or { kind = "class" }
		classObject.parent = parent
		classObject.fields = classObject.fields or {}
		for key, value in pairs(args) do
			if key ~= "value" and key ~= "typ" then
				classObject.fields[key] = value
			end
		end
		Runtime.objects[id] = classObject
	end,
	static_class_decl = function(id, parent, args)
		local classObject = Runtime.objects[id] or { kind = "static_class", static = true }
		classObject.parent = parent
		classObject.fields = classObject.fields or {}
		for key, value in pairs(args) do
			if key ~= "value" and key ~= "typ" then
				classObject.fields[key] = value
			end
		end
		Runtime.objects[id] = classObject
	end,
	enum_decl = function(id, _parent, args)
		Runtime.enums = Runtime.enums or {}
		Runtime.enums[id] = {}
		for key, value in pairs(args) do
			if key ~= "value" and key ~= "typ" then
				Runtime.enums[id][key] = value
			end
		end
	end,
	var_decl = function(id, parent, args)
		local owner = parent and Runtime.objects[parent]
		if owner and (owner.kind == "class" or owner.kind == "static_class" or owner.kind == "function") then
			owner.fields = owner.fields or {}
			owner.fields[id] = args.value
			return
		end
		Runtime.vars = Runtime.vars or {}
		Runtime.vars[id] = args.value
	end,
	public_datastore = function(id, _parent, args) writePublicData(id :: string, args) end,
	plugin_call = function(id, _parent, args) callPlugin(id :: string, args) end,
	engine_control = function(id, _parent, args) engineControl(id :: string, args.value) end,
	metadistro_profile = function() profileMetaDistro() end,
	gui_window = function(id, _parent, args) createGuiWindow(id :: string, args) end,
	gui_panel = function(id, parent, args) createGuiPanel(id :: string, parent, args) end,
	gui_layout_horizontal = function(id, parent, args) createGuiLayout(id :: string, parent, Enum.FillDirection.Horizontal, args) end,
	gui_layout_vertical = function(id, parent, args) createGuiLayout(id :: string, parent, Enum.FillDirection.Vertical, args) end,
	gui_text = function(id, parent, args) createGuiText(id :: string, parent, args) end,
	gui_button = function(id, parent, args) createGuiButton(id :: string, parent, args) end,
	gui_slider = function(id, parent, args) createGuiSlider(id :: string, parent, args) end,
	console_log = function(_id, _parent, args)
		print("[EngineC] " .. tostring(args.value))
	end,
	event_handler = function() end,

	shader = function(id, parent, args) applyShader(id :: string, parent, args.value) end,
	graphics_glow = function(id, _parent, args) graphicsGlow(id :: string, args) end,
	graphics_trail = function(id, _parent, args) graphicsTrail(id :: string, args) end,
	distort = function(_id, _parent, args) distortSpace(tonumber(args.value) or 0) end,
	warp = function(_id, _parent, args) warp(tonumber(args.value) or 0) end,
	particle_emit = function(_id, _parent, args) particleEmit(args) end,

	engine_modify = function(id, _parent, args)
		-- Standalone engine.modify (outside an engine.override block):
		-- route to engineOverride so the modification actually takes effect.
		if id then
			Runtime.engineOverride("engine", { { key = id, value = args.value } })
		end
	end,
	engine_inject = function() end,
	engine_event = function() end,

	attract = function(_id, _parent, args) attract(args[1], args[2]) end,
	merge = function(_id, _parent, args) mergeBodies(args[1], args[2]) end,
}

function Runtime.exec(opName: string, id: string?, parent: string?, args: { [string]: any })
	local handler = DISPATCH[opName]
	if handler then
		handler(id, parent, args)
	else
		warn("[EngineC] no runtime handler for op '" .. opName .. "'")
	end
end

return Runtime
