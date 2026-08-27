-- EngineC Live Parser local plugin.
local Selection = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")
local localEngine = script.Parent and script.Parent:FindFirstChild("EngineC")
local EngineC = require(localEngine or game:GetService("ReplicatedStorage"):WaitForChild("EngineC"))

if not plugin then
	warn("EngineC_LiveParserPlugin must be exported and installed as a Studio local plugin")
	return
end

local toolbar = plugin:CreateToolbar("EngineC")
local toggleButton = toolbar:CreateButton("EngineCPreview", "Preview selected EngineC script", "")
local exportButton = toolbar:CreateButton("EngineCExport", "Package selected EngineC script and dependencies", "")
local wrapButton = toolbar:CreateButton("EngineCWrap", "Wrap selected EngineC source as valid Luau", "")
toggleButton.ClickableWhenViewportHidden = true
exportButton.ClickableWhenViewportHidden = true
local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, true, 420, 640, 280, 360)
local widget = plugin:CreateDockWidgetPluginGui("EngineC_LiveParser", widgetInfo)
widget.Title = "EngineC Live Parser"

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
root.Parent = widget

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 42)
status.Position = UDim2.fromOffset(8, 8)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(220, 220, 220)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Text = "Select an EngineC script."
status.Parent = root

local commandInput = Instance.new("TextBox")
commandInput.Position = UDim2.fromOffset(8, 64)
commandInput.Size = UDim2.new(1, -16, 0, 30)
commandInput.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
commandInput.TextColor3 = Color3.fromRGB(235, 235, 235)
commandInput.Font = Enum.Font.Code
commandInput.TextXAlignment = Enum.TextXAlignment.Left
commandInput.ClearTextOnFocus = false
commandInput.PlaceholderText = "liveparse (file)  |  export (file)  |  wrap (file)"
commandInput.Text = ""
commandInput.Parent = root

local terminalOutput = Instance.new("TextLabel")
terminalOutput.Position = UDim2.fromOffset(8, 98)
terminalOutput.Size = UDim2.new(1, -16, 0, 42)
terminalOutput.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
terminalOutput.TextColor3 = Color3.fromRGB(170, 220, 170)
terminalOutput.Font = Enum.Font.Code
terminalOutput.TextSize = 12
terminalOutput.TextXAlignment = Enum.TextXAlignment.Left
terminalOutput.TextYAlignment = Enum.TextYAlignment.Top
terminalOutput.TextWrapped = true
terminalOutput.Text = "> EngineC terminal ready."
terminalOutput.Parent = root

local editor = Instance.new("TextBox")
editor.Position = UDim2.fromOffset(8, 148)
editor.Size = UDim2.new(1, -16, 0, 220)
editor.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
editor.TextColor3 = Color3.fromRGB(235, 235, 235)
editor.Font = Enum.Font.Code
editor.TextSize = 13
editor.TextXAlignment = Enum.TextXAlignment.Left
editor.TextYAlignment = Enum.TextYAlignment.Top
editor.TextWrapped = false
editor.MultiLine = true
editor.ClearTextOnFocus = false
editor.PlaceholderText = "EngineC source editor"
editor.Text = ""
editor.Parent = root

local saveButton = Instance.new("TextButton")
saveButton.Position = UDim2.fromOffset(8, 374)
saveButton.Size = UDim2.fromOffset(110, 28)
saveButton.Text = "Save EngineC"
saveButton.Parent = root

local preview = Instance.new("ScrollingFrame")
preview.Position = UDim2.fromOffset(8, 410)
preview.Size = UDim2.new(1, -16, 1, -418)
preview.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
preview.BorderSizePixel = 0
preview.AutomaticCanvasSize = Enum.AutomaticSize.Y
preview.CanvasSize = UDim2.new()
preview.ScrollBarThickness = 8
preview.Parent = root

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = preview

local function clearPreview()
	for _, child in ipairs(preview:GetChildren()) do
		if not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function argValue(node, key)
	for _, arg in ipairs(node.args or {}) do
		if arg.key == key and arg.value then
			return arg.value.value
		end
	end
	return nil
end

local function sizeValue(node)
	local size = argValue(node, "size")
	if type(size) == "table" then
		local x = size[1] or size[-1] or 100
		local y = size[2] or size[0] or 40
		return UDim2.fromOffset(tonumber(x) or 100, tonumber(y) or 40)
	end
	return UDim2.new(1, 0, 0, 40)
end

local function renderNode(node, parent)
	local path = node.path or ""
	local current = parent
	if path == "gui.window" then
		local frame = Instance.new("Frame")
		frame.Name = tostring(argValue(node, "id") or "window")
		frame.Size = sizeValue(node)
		frame.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
		frame.Parent = parent
		current = frame
	elseif path == "gui.panel" then
		local frame = Instance.new("Frame")
		frame.Name = tostring(argValue(node, "id") or "panel")
		frame.Size = sizeValue(node)
		frame.BackgroundColor3 = Color3.fromRGB(58, 58, 70)
		frame.Parent = parent
		current = frame
	elseif path == "gui.layout.vertical" or path == "gui.layout.horizontal" then
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = if path == "gui.layout.horizontal" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, tonumber(argValue(node, "spacing")) or 0)
		layout.Parent = parent
	elseif path == "gui.text" then
		local label = Instance.new("TextLabel")
		label.Name = tostring(argValue(node, "id") or "text")
		label.Size = UDim2.new(1, 0, 0, 32)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = tostring(node.value and node.value.value or "")
		label.Parent = parent
	elseif path == "gui.button" then
		local button = Instance.new("TextButton")
		button.Name = tostring(argValue(node, "id") or "button")
		button.Size = UDim2.new(1, 0, 0, 34)
		button.Text = tostring(node.value and node.value.value or "")
		button.Parent = parent
	elseif path == "gui.slider" then
		local slider = Instance.new("TextBox")
		slider.Name = tostring(argValue(node, "id") or "slider")
		slider.Size = UDim2.new(1, 0, 0, 34)
		slider.Text = tostring(argValue(node, "min") or 0)
		slider.PlaceholderText = "slider " .. tostring(argValue(node, "min") or 0) .. " - " .. tostring(argValue(node, "max") or 100)
		slider.Parent = parent
	end
	for _, child in ipairs(node.body or {}) do
		renderNode(child, current)
	end
end

local selectedScript
local function getSelectedScript()
	local selected = Selection:Get()
	if #selected == 1 and selected[1]:IsA("LuaSourceContainer") then
		return selected[1]
	end
	return nil
end

local function refresh()
	selectedScript = getSelectedScript()
	clearPreview()
	if not selectedScript then
		status.Text = "Select one EngineC Script, LocalScript, or ModuleScript."
		return
	end
	local sourceText = selectedScript.Source
	local pairedSource = selectedScript.Parent:FindFirstChild(selectedScript.Name .. ".enginec")
	if pairedSource and pairedSource:IsA("StringValue") then
		sourceText = pairedSource.Value
	end
	if not editor:IsFocused() then
		editor.Text = sourceText
	end
	local result = EngineC.compile(sourceText)
	if not result.ok then
		status.Text = "Parse error: " .. tostring(result.error)
		return
	end
	status.Text = "Live parsed: " .. selectedScript:GetFullName()
	for _, node in ipairs(result.ast or {}) do
		renderNode(node, preview)
	end
end

local function makeWrapper(rawSource)
	local equals = "="
	while rawSource:find("]" .. equals .. "]", 1, true) do
		equals ..= "="
	end
	local openDelimiter = "[" .. equals .. "["
	local closeDelimiter = "]" .. equals .. "]"
	return table.concat({
		'local EngineC = require(game:GetService("ReplicatedStorage"):WaitForChild("EngineC"))',
		"local source = " .. openDelimiter,
		rawSource,
		closeDelimiter,
		"local result, ranOk, runErr = EngineC.run(source)",
		"if not result.ok or not ranOk then error(runErr or result.error) end",
	}, string.char(10))
end

local function wrapFile(sourceScript, sourceText)
	if not sourceScript then
		status.Text = "Select one EngineC script before wrapping."
		return
	end
	local rawSource = sourceText or sourceScript.Source
	local wrapper = makeWrapper(rawSource)
	local rawValue = sourceScript.Parent:FindFirstChild(sourceScript.Name .. ".enginec")
	if not rawValue then
		rawValue = Instance.new("StringValue")
		rawValue.Name = sourceScript.Name .. ".enginec"
		rawValue.Parent = sourceScript.Parent
	end
	rawValue.Value = rawSource
	rawValue:SetAttribute("EngineCSource", true)
	rawValue:SetAttribute("EngineCVersion", "v0.1")
	rawValue:SetAttribute("EngineCWatermark", "EngineC v0.1 | powered by EngineC")
	sourceScript.Source = wrapper
	status.Text = "Wrapped " .. sourceScript:GetFullName() .. "; raw EngineC source is stored beside it."
end

local function saveEditorSource()
	local sourceScript = selectedScript or getSelectedScript()
	if not sourceScript then
		status.Text = "Select one EngineC script before saving."
		return
	end
	local sourceText = editor.Text
	local result = EngineC.compile(sourceText)
	if not result.ok then
		status.Text = "Cannot save: " .. tostring(result.error)
		return
	end
	wrapFile(sourceScript, sourceText)
	status.Text = "Saved " .. sourceScript:GetFullName()
	refresh()
end

local function exportPackage()
	local sourceScript = getSelectedScript()
	if not sourceScript then
		status.Text = "Select one EngineC script before exporting."
		return
	end
	local serverStorage = game:GetService("ServerStorage")
	local package = serverStorage:FindFirstChild("EngineCPluginPackage")
	if package then
		package:Destroy()
	end
	package = Instance.new("Folder")
	package.Name = "EngineCPluginPackage"
	package:SetAttribute("EngineCVersion", "v0.1")
	package:SetAttribute("EngineCWatermark", "EngineC v0.1 | powered by EngineC")
	package.Parent = serverStorage

	local engineCopy = game:GetService("ReplicatedStorage"):WaitForChild("EngineC"):Clone()
	engineCopy.Name = "EngineC"
	engineCopy.Parent = package
	local dependencies = game:GetService("ReplicatedStorage"):FindFirstChild("AdditionalDependencies")
	if dependencies then
		dependencies:Clone().Parent = package
	end

	local pluginMain = script:Clone()
	pluginMain.Name = "PluginMain"
	pluginMain.Parent = package

	local sourceValue = Instance.new("StringValue")
	sourceValue.Name = sourceScript.Name .. ".enginec"
	local pairedSource = sourceScript.Parent:FindFirstChild(sourceScript.Name .. ".enginec")
	sourceValue.Value = if pairedSource and pairedSource:IsA("StringValue") then pairedSource.Value else sourceScript.Source
	sourceValue:SetAttribute("EngineCVersion", "v0.1")
	sourceValue:SetAttribute("EngineCWatermark", "EngineC v0.1 | powered by EngineC")
	sourceValue.Parent = package

	local manifest = Instance.new("StringValue")
	manifest.Name = "EngineC_Manifest"
	manifest.Value = "EngineC v0.1 | powered by EngineC | source=" .. sourceScript.Name
	manifest.Parent = package
	Selection:Set({ package })
	status.Text = "Package created in ServerStorage.EngineCPluginPackage; select PluginMain inside it and save as a local plugin."
end

local function appendTerminal(text)
	terminalOutput.Text = terminalOutput.Text .. "\n> " .. text
end

local function resolveFile(spec)
	spec = spec:gsub("^%s+", ""):gsub("%s+$", "")
	if spec == "" then
		return getSelectedScript()
	end
	spec = spec:gsub("^game%.", "")
	local current = game
	for segment in spec:gmatch("[^%.]+") do
		current = current:FindFirstChild(segment)
		if not current then
			break
		end
	end
	if current and current:IsA("LuaSourceContainer") then
		return current
	end
	for _, item in ipairs(game:GetDescendants()) do
		if item.Name == spec and item:IsA("LuaSourceContainer") then
			return item
		end
	end
	return nil
end

local function executeCommand(command)
	local action, file = command:match("^(%S+)%s*%((.-)%)%s*$")
	if not action then
		appendTerminal("usage: liveparse (file) or export (file)")
		return
	end
	local target = resolveFile(file)
	if not target then
		appendTerminal("file not found: " .. file)
		return
	end
	Selection:Set({ target })
	if action == "liveparse" then
		refresh()
		appendTerminal("live parsed " .. target:GetFullName())
	elseif action == "edit" then
		refresh()
		editor:CaptureFocus()
		appendTerminal("editing " .. target:GetFullName())
	elseif action == "export" then
		refresh()
		exportPackage()
		appendTerminal("exported " .. target:GetFullName())
	elseif action == "wrap" then
		wrapFile(target)
		appendTerminal("wrapped " .. target:GetFullName())
	else
		appendTerminal("unknown command: " .. action)
	end
end

exportButton.Click:Connect(exportPackage)
wrapButton.Click:Connect(function()
	wrapFile(getSelectedScript())
end)
saveButton.Activated:Connect(saveEditorSource)
commandInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		executeCommand(commandInput.Text)
		commandInput.Text = ""
	end
end)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled then
		refresh()
	end
end)
Selection.SelectionChanged:Connect(refresh)
ScriptEditorService.TextDocumentDidChange:Connect(function(document)
	local ok, scriptInstance = pcall(function()
		return document.Script
	end)
	if ok and scriptInstance == selectedScript then
		task.defer(refresh)
	end
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if widget.Enabled then
		refresh()
	end
end)
refresh()