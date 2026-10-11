--// Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

--// Assets
local LOGO_ID = "rbxassetid://134634058667875"
local LOGO_SIZE = 24

local REF_W, REF_H = 530, 550
local INNER_W, INNER_H = REF_W - 20, REF_H - 44 -- inner frame
local CONTENT_W = INNER_W - 20
local COLUMN_GAP = 10

local function sx(px) return px / REF_W end
local function sy(px) return px / REF_H end

--// Clean up previous execution
do
	local genv = type(getgenv) == "function" and getgenv() or nil
	if genv and genv.__VeluneLib and genv.__VeluneLib.Unload then
		pcall(genv.__VeluneLib.Unload, genv.__VeluneLib)
	end
end

--// Theme
local function darker(color)
	local h, s, v = color:ToHSV()
	return Color3.fromHSV((h - 0.02) % 1, math.clamp(s + 0.08, 0, 1), v * 0.86)
end

local Theme = {
	Accent = Color3.fromRGB(255, 197, 121), -- #ffc579
	Accent2 = nil,
	Background = Color3.fromRGB(13, 13, 16),
	Panel = Color3.fromRGB(26, 26, 31),
	Element = Color3.fromRGB(30, 30, 37),
	Text = Color3.fromRGB(236, 236, 242),
	SubText = Color3.fromRGB(139, 139, 150),
	White = Color3.new(1, 1, 1),
	Success = Color3.fromRGB(126, 232, 192),
	Error = Color3.fromRGB(255, 107, 107),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}
Theme.Accent2 = darker(Theme.Accent)

local library = {
	Version = "0.4.0",
	Flags = {},
	Elements = {},
	Windows = {},
	KeySystems = {},
	Theme = Theme,
	_listening = false,
	_lastBind = 0,
}

--// Helpers
local accentListeners = {}

local function onAccent(fn)
	table.insert(accentListeners, fn)
	fn()
end

function library:SetAccent(color)
	Theme.Accent = color
	Theme.Accent2 = darker(color)
	for _, fn in ipairs(accentListeners) do
		pcall(fn)
	end
end

local function tween(obj, props, time, style, dir)
	local tw = TweenService:Create(
		obj,
		TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function create(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function stroke(parent, color, transparency, thickness)
	return create("UIStroke", {
		Color = color or Theme.White,
		Transparency = transparency or 0.9,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function padding(parent, l, t, r, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0),
		PaddingBottom = UDim.new(0, b or 0),
		Parent = parent,
	})
end

local function accentGradient(parent, rotation)
	local g = create("UIGradient", { Rotation = rotation or 0, Parent = parent })
	onAccent(function()
		g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
	end)
	return g
end

local function hover(obj, enter, leave)
	obj.MouseEnter:Connect(enter)
	obj.MouseLeave:Connect(leave)
end

local function makeLabel(parent, text, props)
	local p = {
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return create("TextLabel", p)
end

local function flagOf(o)
	return (o.flag and o.flag ~= "") and o.flag or o.text
end

local function isBusy()
	return library._listening or (tick() - library._lastBind) < 0.15
end

local KeyNames = {
	LeftShift = "LShift", RightShift = "RShift",
	LeftControl = "LCtrl", RightControl = "RCtrl",
	LeftAlt = "LAlt", RightAlt = "RAlt",
	Return = "Enter", Backspace = "Back",
}

local function keyName(key)
	if not key or key == Enum.KeyCode.Unknown then
		return "None"
	end
	return KeyNames[key.Name] or key.Name
end

local function getGuiParent()
	local ok, ui = pcall(function()
		return gethui and gethui()
	end)
	if ok and ui then
		return ui
	end
	if pcall(function() return CoreGui:GetChildren() end) then
		return CoreGui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

--[[
	makeScaler: creates a child frame that always fills `parent` exactly, but whose
	contents are laid out on a fixed design canvas and then uniformly scaled by k.
	(Size = 1/k of the parent, UIScale = k -> the net result is the parent's size.)
	This is what makes text, rows, paddings and strokes follow the window size.
]]
local function makeScaler(parent, getK, mult)
	local f = create("Frame", {
		Name = "Scaler",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local us = create("UIScale", { Parent = f })
	local function update()
		local k = math.max(getK(), 0.05)
		f.Size = UDim2.fromScale(1 / k, 1 / k)
		us.Scale = k * (mult and mult.v or 1)
	end
	update()
	return f, update
end

--// Classes
local Window, Tab, Section = {}, {}, {}
Window.__index = Window
Tab.__index = Tab
Section.__index = Section

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
function library.NewWindow(a, b, c)
	local title, subtitle
	if type(a) == "table" then
		title, subtitle = b, c
	else
		title, subtitle = a, b
	end
	title = tostring(title or "velune.gg")
	subtitle = tostring(subtitle or "")

	local self = setmetatable({
		Title = title,
		Subtitle = subtitle,
		Tabs = {},
		ActiveTab = nil,
		Open = true,
		MenuKey = Enum.KeyCode.End,
		Connections = {},
		_notifOrder = 0,
		_openToken = 0,
		_sizeMult = 1,
	}, Window)

	local gui = create("ScreenGui", {
		Name = HttpService:GenerateGUID(false),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		end
	end)
	gui.Parent = getGuiParent()
	self.Gui = gui

	-- viewport size (falls back to the camera while the gui has not laid out yet)
	local function vpSize()
		local s = gui.AbsoluteSize
		if s.X <= 0 or s.Y <= 0 then
			local cam = workspace.CurrentCamera
			s = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		end
		return s
	end
	self._vp = vpSize

	-- Root: sized as a fraction of the screen, locked to a vertical aspect ratio
	local root = create("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.95, self:_heightScale()),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	create("UIAspectRatioConstraint", {
		AspectRatio = REF_W / REF_H,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = root,
	})

	-- DARK FIX: the CanvasGroup itself stays transparent. The gradient lives on a
	-- separate background frame so it never multiplies the children's colors.
	local main = create("CanvasGroup", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = root,
	})
	-- scale radius = 12px at the design width, follows the window size
	create("UICorner", { CornerRadius = UDim.new(12 / REF_W, 0), Parent = main })

	-- design canvas: everything below is laid out on REF_W x REF_H and scaled
	local pop = { v = 0.95 }
	local function getK()
		local vp = vpSize()
		return math.min(vp.X * 0.95 / REF_W, vp.Y * self:_heightScale() / REF_H)
	end
	local canvas, updateScale = makeScaler(main, getK, pop)
	self._updateScale = updateScale
	self._pop = pop
	self._popValue = create("NumberValue", { Value = 0.95 })
	self._popValue.Changed:Connect(function(v)
		pop.v = v
		updateScale()
	end)

	local bg = create("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = canvas,
	})
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(30, 30, 37), Color3.fromRGB(14, 14, 18)),
		Rotation = 65,
		Parent = bg,
	})

	-- soft accent glow at the top (glass feel)
	local glow = create("Frame", {
		Name = "Glow",
		Size = UDim2.new(1, 0, sy(120), 0),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	do
		local g = create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0.86, 1),
			Parent = glow,
		})
		onAccent(function()
			g.Color = ColorSequence.new(Theme.Accent)
		end)
	end

	-- thin accent line at very top
	local topLine = create("Frame", {
		Name = "TopLine",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	do
		local g = create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = topLine,
		})
		onAccent(function()
			g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
		end)
	end

	-- Header
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, sy(34), 0),
		BackgroundTransparency = 1,
		Parent = canvas,
	})

	-- Logo: bare image with a subtle accent glow (stacked tinted copies, no box)
	local logoHolder = create("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(sx(16), 0, 0.5, 0),
		Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),
		BackgroundTransparency = 1,
		Parent = header,
	})
	local glowLayers = {
		{ scale = 1.75, base = 0.94 },
		{ scale = 1.42, base = 0.89 },
		{ scale = 1.18, base = 0.82 },
	}
	for _, layer in ipairs(glowLayers) do
		local img = create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(layer.scale, layer.scale),
			BackgroundTransparency = 1,
			Image = LOGO_ID,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = layer.base,
			Parent = logoHolder,
		})
		onAccent(function()
			img.ImageColor3 = Theme.Accent
		end)
		-- very slow breathing so the glow feels alive but stays subtle
		TweenService:Create(
			img,
			TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ ImageTransparency = math.min(layer.base + 0.07, 1) }
		):Play()
	end
	create("ImageLabel", {
		Name = "LogoImage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = LOGO_ID,
		ScaleType = Enum.ScaleType.Fit,
		Parent = logoHolder,
	})

	-- Title: "velune" + accent-colored ".gg" + gray subtitle
	local titleHolder = create("Frame", {
		Position = UDim2.fromScale(sx(16 + LOGO_SIZE + 9), 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = header,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = titleHolder,
	})
	local titleBase, titleRest = title:match("^([^%.]+)(%..*)$")
	local titleLabel = create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		RichText = true,
		Text = title,
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		Parent = titleHolder,
	})
	onAccent(function()
		if titleBase then
			titleLabel.Text = string.format('%s<font color="#%s">%s</font>', titleBase, Theme.Accent:ToHex(), titleRest)
		else
			titleLabel.Text = title
		end
	end)
	create("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = subtitle,
		Font = Theme.Font,
		TextSize = 11,
		TextColor3 = Theme.SubText,
		Parent = titleHolder,
	})
	local hint = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1 - sx(16), 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "[" .. keyName(self.MenuKey) .. "]",
		Font = Theme.Font,
		TextSize = 11,
		TextColor3 = Theme.SubText,
		TextTransparency = 0.3,
		Parent = header,
	})
	self.Hint = hint

	-- Inner frame (the second border in the reference style)
	local inner = create("Frame", {
		Name = "Inner",
		Position = UDim2.fromScale(sx(10), sy(34)),
		Size = UDim2.fromScale(1 - sx(20), 1 - sy(44)),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	corner(inner, 8)
	stroke(inner, Theme.White, 0.9)

	-- Tab bar (tabs share the full width evenly)
	local tabBar = create("Frame", {
		Name = "TabBar",
		Size = UDim2.new(1, 0, 30 / INNER_H, 0),
		BackgroundTransparency = 1,
		Parent = inner,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})
	create("Frame", {
		Position = UDim2.fromScale(0, 30 / INNER_H),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Parent = inner,
	})

	-- Content
	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromScale(10 / INNER_W, 40 / INNER_H),
		Size = UDim2.fromScale(1 - 20 / INNER_W, 1 - 48 / INNER_H),
		BackgroundTransparency = 1,
		Parent = inner,
	})

	-- Border (on top, inside the canvas group so it fades)
	local edge = create("Frame", {
		Name = "Edge",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = canvas,
	})
	corner(edge, 12)
	do
		local s = stroke(edge, Theme.White, 0.45, 1)
		local g = create("UIGradient", { Rotation = 35, Parent = s })
		onAccent(function()
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Accent),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 70, 82)),
				ColorSequenceKeypoint.new(1, Theme.Accent2),
			})
		end)
	end

	-- screen-level UI (notifications / watermark) scales with the screen height
	local function guiK()
		return math.clamp(vpSize().Y / 1080, 0.6, 1.6)
	end

	-- Notification holder
	local notifRoot = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.99, 0.98),
		Size = UDim2.fromScale(0.5, 0.96),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local notifCanvas, updateNotifScale = makeScaler(notifRoot, guiK)
	local notifHolder = create("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 260, 1, 0),
		BackgroundTransparency = 1,
		Parent = notifCanvas,
	})
	create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = notifHolder,
	})

	-- Watermark
	local wm = create("Frame", {
		Name = "Watermark",
		Position = UDim2.fromScale(0.012, 0.06),
		Size = UDim2.new(0, 0, 0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local wmScale = create("UIScale", { Scale = guiK(), Parent = wm })
	corner(wm, 7)
	stroke(wm, Theme.White, 0.9)
	local wmLine = create("Frame", {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 0, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = wm,
	})
	accentGradient(wmLine, 0)
	local wmLabel = create("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		RichText = true,
		Text = "",
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.Text,
		Parent = wm,
	})
	padding(wmLabel, 10, 0, 10, 0)

	local fps = 60
	local acc, frames = 0, 0
	local function updateWatermark()
		wmLabel.Text = string.format(
			'<font color="#%s"><b>%s</b></font>  <font color="#8b8b96">%s%d fps</font>',
			Theme.Accent:ToHex(),
			title,
			subtitle ~= "" and (subtitle .. "  |  ") or "",
			fps
		)
	end
	onAccent(updateWatermark)
	self:_connect(RunService.RenderStepped, function(dt)
		acc += dt
		frames += 1
		if acc >= 0.5 then
			fps = math.floor(frames / acc + 0.5)
			acc, frames = 0, 0
			if wm.Visible then
				updateWatermark()
			end
		end
	end)

	-- react to screen size changes (rotation, resize, different devices)
	self:_connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		updateScale()
		updateNotifScale()
		wmScale.Scale = guiK()
	end)

	self.Root, self.Main, self.Canvas = root, main, canvas
	self.TabBar, self.Content = tabBar, content
	self.NotifHolder, self.WatermarkFrame = notifHolder, wm

	-- Dragging (position is stored as Scale so it stays put on any resolution)
	do
		local dragging, dragStart, startPos = false, nil, nil
		header.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = root.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)
		self:_connect(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local d = input.Position - dragStart
				local vp = vpSize()
				tween(root, {
					Position = UDim2.fromScale(startPos.X.Scale + d.X / vp.X, startPos.Y.Scale + d.Y / vp.Y),
				}, 0.08, Enum.EasingStyle.Sine)
			end
		end)
	end

	-- Menu toggle key
	self:_connect(UserInputService.InputBegan, function(input, gp)
		if gp or isBusy() then
			return
		end
		if input.KeyCode == self.MenuKey and self.MenuKey ~= Enum.KeyCode.Unknown then
			self:SetOpen(not self.Open)
		end
	end)

	table.insert(library.Windows, self)
	self.Open = false
	self:SetOpen(true)
	self:SetWatermark(true)
	return self
end
library.new = library.NewWindow

function Window:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.Connections, c)
	return c
end

-- fraction of the screen height the window uses (bigger on small screens)
function Window:_heightScale()
	local vp = self._vp and self._vp() or Vector2.new(1920, 1080)
	local base = (vp.Y < 720) and 0.92 or 0.64
	return math.clamp(base * self._sizeMult, 0.3, 0.96)
end

-- multiplier on the window size (1 = default). Useful for phones / tiny screens.
function Window:SetSize(mult)
	self._sizeMult = math.clamp(tonumber(mult) or 1, 0.5, 1.5)
	self.Root.Size = UDim2.fromScale(0.95, self:_heightScale())
	self._updateScale()
end

function Window:SetOpen(state)
	if state == self.Open then
		return
	end
	self.Open = state
	self._openToken += 1
	local token = self._openToken
	if state then
		self.Root.Visible = true
		self._popValue.Value = 0.95
		tween(self.Main, { GroupTransparency = 0 }, 0.3)
		tween(self._popValue, { Value = 1 }, 0.4, Enum.EasingStyle.Back)
	else
		tween(self.Main, { GroupTransparency = 1 }, 0.2)
		tween(self._popValue, { Value = 0.96 }, 0.2)
		task.delay(0.22, function()
			if self._openToken == token and not self.Open then
				self.Root.Visible = false
			end
		end)
	end
end

function Window:Toggle()
	self:SetOpen(not self.Open)
end

function Window:SetMenuKey(key)
	self.MenuKey = key
	self.Hint.Text = "[" .. keyName(key) .. "]"
end

function Window:SetWatermark(state)
	self.WatermarkFrame.Visible = state and true or false
end

function Window:Destroy()
	for _, c in ipairs(self.Connections) do
		pcall(function() c:Disconnect() end)
	end
	self.Connections = {}
	if self._popValue then
		self._popValue:Destroy()
	end
	if self.Gui then
		self.Gui:Destroy()
	end
	local i = table.find(library.Windows, self)
	if i then
		table.remove(library.Windows, i)
	end
end

function library:Unload()
	for i = #library.Windows, 1, -1 do
		library.Windows[i]:Destroy()
	end
	for i = #library.KeySystems, 1, -1 do
		library.KeySystems[i]:Destroy()
	end
	library._listening = false
	table.clear(accentListeners)
end

--// Notifications
function Window:Notify(title, text, duration)
	if type(title) == "table" then
		local t = title
		title, text, duration = t.title or t.Title, t.text or t.Text, t.duration or t.Duration
	end
	title = tostring(title or self.Title)
	text = tostring(text or "")
	duration = duration or 4

	local width = 260
	local textH = 0
	if text ~= "" then
		textH = TextService:GetTextSize(text, 12, Enum.Font.Gotham, Vector2.new(width - 30, 1000)).Y
	end
	local h = 12 + 16 + (textH > 0 and (textH + 4) or 0) + 14

	self._notifOrder += 1
	local wrapper = create("Frame", {
		Size = UDim2.new(1, 0, 0, h),
		BackgroundTransparency = 1,
		LayoutOrder = self._notifOrder,
		Parent = self.NotifHolder,
	})
	local card = create("CanvasGroup", {
		Position = UDim2.new(0, 50, 0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = wrapper,
	})
	corner(card, 8)
	stroke(card, Theme.White, 0.88)
	local bar = create("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = card,
	})
	accentGradient(bar, 90)
	create("TextLabel", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -28, 0, 16),
		BackgroundTransparency = 1,
		Text = title,
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	if text ~= "" then
		create("TextLabel", {
			Position = UDim2.fromOffset(16, 30),
			Size = UDim2.new(1, -30, 0, textH),
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
	end
	local prog = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = card,
	})
	accentGradient(prog, 0)

	tween(card, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, 0.4)
	tween(prog, { Size = UDim2.new(0, 0, 0, 2) }, duration, Enum.EasingStyle.Linear)

	task.delay(duration, function()
		if not wrapper.Parent then
			return
		end
		tween(card, { Position = UDim2.new(0, 40, 0, 0), GroupTransparency = 1 }, 0.3)
		task.wait(0.28)
		if wrapper.Parent then
			tween(wrapper, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
			task.wait(0.22)
			wrapper:Destroy()
		end
	end)
end

function library.Notify(a, b, c, d)
	local w = library.Windows[#library.Windows]
	if not w then
		return
	end
	if a == library then
		return w:Notify(b, c, d)
	end
	return w:Notify(a, b, c)
end

--------------------------------------------------------------------------------
-- TABS
--------------------------------------------------------------------------------
local function makeColumn(page, i)
	local c = create("ScrollingFrame", {
		Name = "Column" .. i,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageTransparency = 0.3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = page,
	})
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
	-- top padding leaves room for the section titles that sit on the border line
	padding(c, 0, 9, 5, 4)
	onAccent(function()
		c.ScrollBarImageColor3 = Theme.Accent
	end)
	return c
end

-- columns are laid out purely with Scale (gap included)
function Tab:_layout()
	local n = #self.Columns
	local gap = COLUMN_GAP / CONTENT_W
	local w = (1 - gap * (n - 1)) / n
	for i, c in ipairs(self.Columns) do
		c.Position = UDim2.fromScale((i - 1) * (w + gap), 0)
		c.Size = UDim2.fromScale(w, 1)
	end
end

function Tab:_getColumn(i)
	while #self.Columns < i do
		table.insert(self.Columns, makeColumn(self.Page, #self.Columns + 1))
	end
	self:_layout()
	return self.Columns[i]
end

function Window:AddTab(name)
	name = tostring(name)
	local tab = setmetatable({ Name = name, Window = self, _secOrder = 0 }, Tab)

	local btn = create("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = name,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		LayoutOrder = #self.Tabs + 1,
		Parent = self.TabBar,
	})

	-- faint accent wash behind the active tab (only the lower half)
	local tint = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = btn,
	})
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = tint,
	})
	onAccent(function()
		tint.BackgroundColor3 = Theme.Accent
	end)

	local bar = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = btn,
	})
	corner(bar, 2)
	accentGradient(bar, 0)

	local page = create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Content,
	})

	tab.Button, tab.Bar, tab.Tint, tab.Page = btn, bar, tint, page
	tab.Columns = { makeColumn(page, 1), makeColumn(page, 2) }
	tab:_layout()

	btn.MouseButton1Click:Connect(function()
		tab:Select()
	end)
	hover(btn, function()
		if self.ActiveTab ~= tab then
			tween(btn, { TextColor3 = Theme.Text }, 0.15)
		end
	end, function()
		if self.ActiveTab ~= tab then
			tween(btn, { TextColor3 = Theme.SubText }, 0.15)
		end
	end)

	table.insert(self.Tabs, tab)
	local n = #self.Tabs
	for _, t in ipairs(self.Tabs) do
		t.Button.Size = UDim2.new(1 / n, 0, 1, 0)
	end
	if not self.ActiveTab then
		tab:Select(true)
	end
	return tab
end

function Tab:Select(instant)
	local w = self.Window
	for _, t in ipairs(w.Tabs) do
		local active = (t == self)
		tween(t.Bar, { Size = active and UDim2.new(1, -10, 0, 2) or UDim2.new(0, 0, 0, 2) }, 0.25)
		tween(t.Tint, { BackgroundTransparency = active and 0.88 or 1 }, 0.25)
		tween(t.Button, { TextColor3 = active and Theme.Text or Theme.SubText }, 0.2)
		t.Page.Visible = active
	end
	w.ActiveTab = self
	if not instant then
		self.Page.Position = UDim2.fromScale(0, 0.012)
		tween(self.Page, { Position = UDim2.fromScale(0, 0) }, 0.3)
	end
end

--------------------------------------------------------------------------------
-- SECTIONS  ( ── Title ──────── style box, title sits on the border line )
--------------------------------------------------------------------------------
function Tab:AddSection(name, column)
	column = math.clamp(math.floor(tonumber(column) or 1), 1, 3)
	self._secOrder += 1

	local box = create("Frame", {
		Name = "Section",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
		LayoutOrder = self._secOrder,
		Parent = self:_getColumn(column),
	})
	-- glass sheen: a little brighter at the top, fading down
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0, 0.6),
		Parent = box,
	})

	local function line(props)
		props.BackgroundColor3 = props.BackgroundColor3 or Theme.White
		props.BackgroundTransparency = props.BackgroundTransparency or 0.88
		props.BorderSizePixel = 0
		props.Parent = box
		return create("Frame", props)
	end

	-- border: left, right, bottom
	line({ Size = UDim2.new(0, 1, 1, 0) })
	line({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0) })
	line({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1) })

	-- border: top, split around the title
	local titleText = tostring(name or "Section")
	local tw = TextService:GetTextSize(titleText, 12, Theme.Font, Vector2.new(1000, 20)).X
	local leftSeg = line({
		Size = UDim2.fromOffset(10, 1),
		BackgroundTransparency = 0.3,
	})
	onAccent(function()
		leftSeg.BackgroundColor3 = Theme.Accent
	end)
	makeLabel(box, titleText, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.fromOffset(tw + 2, 14),
		TextColor3 = Theme.Text,
	})
	local rightX = 16 + tw + 2 + 6
	line({
		Position = UDim2.fromOffset(rightX, 0),
		Size = UDim2.new(1, -rightX, 0, 1),
	})

	-- content holder (auto-sizes; the box follows it)
	local holder = create("Frame", {
		Name = "Holder",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = box,
	})
	padding(holder, 10, 14, 10, 10)
	create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
	-- AbsoluteSize is in real pixels, but the box lives on the scaled design canvas,
	-- so convert back to design units using the canvas scale.
	local canvasScale = self.Window.Canvas:FindFirstChildOfClass("UIScale")
	local function sync()
		local k = canvasScale and canvasScale.Scale or 1
		box.Size = UDim2.new(1, 0, 0, holder.AbsoluteSize.Y / math.max(k, 0.05))
	end
	if canvasScale then
		canvasScale:GetPropertyChangedSignal("Scale"):Connect(sync)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	sync()

	local section = setmetatable({ Frame = holder, Box = box, Tab = self, Window = self.Window, _order = 0 }, Section)
	self.LastSection = section
	return section
end

function Tab:_current()
	if not self.LastSection then
		self:AddSection(self.Name, 1)
	end
	return self.LastSection
end

function Section:_row(height)
	self._order += 1
	return create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
		Parent = self.Frame,
	})
end

--------------------------------------------------------------------------------
-- ELEMENTS
--------------------------------------------------------------------------------

--// Separator
function Section:AddSeparator(o)
	if type(o) ~= "table" then
		o = { text = o }
	end
	local row = self:_row(14)
	local text = o.text and tostring(o.text) or nil
	if not text or text == "" then
		create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Parent = row,
		})
		return
	end
	local w = TextService:GetTextSize(text, 11, Theme.Font, Vector2.new(1000, 20)).X
	makeLabel(row, text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w + 2, 14),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local function ln(right)
		create("Frame", {
			AnchorPoint = Vector2.new(right and 1 or 0, 0.5),
			Position = UDim2.new(right and 1 or 0, 0, 0.5, 0),
			Size = UDim2.new(0.5, -(w / 2 + 8), 0, 1),
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Parent = row,
		})
	end
	ln(false)
	ln(true)
end

--// Label
function Section:AddLabel(text)
	if type(text) == "table" then
		text = text.text
	end
	self._order += 1
	local lbl = makeLabel(self.Frame, tostring(text or ""), {
		Size = UDim2.new(1, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = self._order,
	})
	local obj = {}
	function obj:SetText(t)
		lbl.Text = tostring(t)
	end
	return obj
end

--// Toggle
function Section:AddToggle(text, default, callback)
	local o
	if type(text) == "table" then
		o = text
	else
		if type(default) == "function" then
			callback, default = default, false
		end
		o = { text = text, default = default, callback = callback }
	end
	o.text = tostring(o.text or "Toggle")
	local flag = flagOf(o)

	local row = self:_row(20)
	local btn = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	})
	local box = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		Parent = btn,
	})
	corner(box, 4)
	local bs = stroke(box, Theme.White, 0.88)
	local fill = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0, 0),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = box,
	})
	corner(fill, 3)
	accentGradient(fill, 45)
	local label = makeLabel(btn, o.text, {
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -24, 1, 0),
	})

	local obj = { Value = false }
	function obj:Set(v, silent)
		v = v and true or false
		self.Value = v
		library.Flags[flag] = v
		tween(fill, {
			Size = v and UDim2.fromScale(0.57, 0.57) or UDim2.fromScale(0, 0),
			BackgroundTransparency = v and 0 or 1,
		}, 0.22, Enum.EasingStyle.Back)
		tween(label, { TextColor3 = v and Theme.Text or Theme.SubText }, 0.2)
		tween(bs, { Color = v and Theme.Accent or Theme.White, Transparency = v and 0.5 or 0.88 }, 0.2)
		if not silent and o.callback then
			task.spawn(o.callback, v)
		end
	end
	function obj:Get()
		return self.Value
	end
	onAccent(function()
		if obj.Value then
			bs.Color = Theme.Accent
		end
	end)

	btn.MouseButton1Click:Connect(function()
		obj:Set(not obj.Value)
	end)
	hover(btn, function()
		if not obj.Value then
			tween(label, { TextColor3 = Theme.Text }, 0.15)
		end
	end, function()
		if not obj.Value then
			tween(label, { TextColor3 = Theme.SubText }, 0.15)
		end
	end)

	obj:Set(o.default == true, true)
	library.Elements[flag] = obj
	return obj
end

--// Button
function Section:AddButton(text, callback)
	local o
	if type(text) == "table" then
		o = text
	else
		o = { text = text, callback = callback }
	end
	o.text = tostring(o.text or "Button")

	local row = self:_row(24)
	local btn = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = o.text,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.Text,
		Parent = row,
	})
	corner(btn, 5)
	local bs = stroke(btn, Theme.White, 0.9)

	local function base()
		return Theme.Element
	end
	hover(btn, function()
		tween(btn, { BackgroundColor3 = base():Lerp(Theme.Accent, 0.12) }, 0.15)
		tween(bs, { Color = Theme.Accent, Transparency = 0.6 }, 0.15)
	end, function()
		tween(btn, { BackgroundColor3 = base() }, 0.15)
		tween(bs, { Color = Theme.White, Transparency = 0.9 }, 0.15)
	end)
	btn.MouseButton1Click:Connect(function()
		btn.BackgroundColor3 = base():Lerp(Theme.Accent, 0.35)
		tween(btn, { BackgroundColor3 = base():Lerp(Theme.Accent, 0.12) }, 0.35)
		if o.callback then
			task.spawn(o.callback)
		end
	end)

	local obj = {}
	function obj:SetText(t)
		btn.Text = tostring(t)
	end
	return obj
end

--// Textbox
function Section:AddBox(o, placeholder, callback)
	if type(o) ~= "table" then
		o = { text = o, placeholder = placeholder, callback = callback }
	end
	o.text = tostring(o.text or "Box")
	local flag = flagOf(o)

	local row = self:_row(44)
	makeLabel(row, o.text, { Size = UDim2.new(1, 0, 0, 14) })
	local tb = create("TextBox", {
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 25),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.1,
		Text = tostring(o.default or ""),
		PlaceholderText = o.placeholder or "",
		PlaceholderColor3 = Color3.fromRGB(95, 95, 105),
		TextColor3 = Theme.Text,
		Font = Theme.Font,
		TextSize = 12,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	corner(tb, 5)
	padding(tb, 8, 0, 8, 0)
	local bs = stroke(tb, Theme.White, 0.9)

	local obj = { Value = tb.Text }
	function obj:Set(v, silent)
		v = tostring(v)
		tb.Text = v
		self.Value = v
		library.Flags[flag] = v
		if not silent and o.callback then
			task.spawn(o.callback, v, false)
		end
	end
	function obj:Get()
		return tb.Text
	end

	if o.numeric then
		tb:GetPropertyChangedSignal("Text"):Connect(function()
			local f = tb.Text:gsub("[^%d%.%-]", "")
			if f ~= tb.Text then
				tb.Text = f
			end
		end)
	end
	tb.Focused:Connect(function()
		tween(bs, { Color = Theme.Accent, Transparency = 0.45 }, 0.15)
	end)
	tb.FocusLost:Connect(function(enter)
		tween(bs, { Color = Theme.White, Transparency = 0.9 }, 0.15)
		obj.Value = tb.Text
		library.Flags[flag] = tb.Text
		if o.callback then
			task.spawn(o.callback, tb.Text, enter)
		end
	end)

	library.Flags[flag] = tb.Text
	library.Elements[flag] = obj
	return obj
end

--// Slider  (rectangular box with a fill, same look as the checkbox)
function Section:AddSlider(text, a, b, c, d)
	local o
	if type(text) == "table" then
		o = text
	elseif type(a) == "table" then
		o = a
		o.text = text
	else
		o = { text = text, min = a, max = b, default = c, callback = d }
	end
	o.text = tostring(o.text or "Slider")
	local min, max = o.min or 0, o.max or 100
	local dec = o.decimals or 0
	local mult = 10 ^ dec
	local suffix = o.suffix or ""
	local flag = flagOf(o)

	local function fmt(v)
		if dec > 0 then
			return string.format("%." .. dec .. "f", v) .. suffix
		end
		return tostring(math.floor(v + 0.5)) .. suffix
	end

	local row = self:_row(36)
	makeLabel(row, o.text, { Size = UDim2.new(0.7, 0, 0, 14) })
	local valueLabel = makeLabel(row, "", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.3, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Text,
	})

	-- the box (the whole thing is the hit area)
	local track = create("TextButton", {
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	corner(track, 4)
	local ts = stroke(track, Theme.White, 0.88)

	-- inset area so the fill sits inside the box like the checkbox fill
	local area = create("Frame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundTransparency = 1,
		Parent = track,
	})
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = area,
	})
	corner(fill, 3)
	accentGradient(fill, 45)

	local obj = { Value = min }
	function obj:Set(v, silent)
		v = math.clamp(tonumber(v) or min, min, max)
		v = math.floor(v * mult + 0.5) / mult
		local changed = v ~= self.Value
		self.Value = v
		library.Flags[flag] = v
		local pct = (max == min) and 0 or (v - min) / (max - min)
		tween(fill, { Size = UDim2.fromScale(pct, 1) }, 0.08, Enum.EasingStyle.Sine)
		valueLabel.Text = fmt(v)
		if changed and not silent and o.callback then
			task.spawn(o.callback, v)
		end
	end
	function obj:Get()
		return self.Value
	end

	local dragging, hovering = false, false
	local function refreshStroke()
		if dragging then
			tween(ts, { Color = Theme.Accent, Transparency = 0.5 }, 0.15)
		elseif hovering then
			tween(ts, { Color = Theme.White, Transparency = 0.7 }, 0.15)
		else
			tween(ts, { Color = Theme.White, Transparency = 0.88 }, 0.15)
		end
	end
	local function update(x)
		local pct = math.clamp((x - area.AbsolutePosition.X) / math.max(area.AbsoluteSize.X, 1), 0, 1)
		obj:Set(min + (max - min) * pct)
	end
	hover(track, function()
		hovering = true
		refreshStroke()
	end, function()
		hovering = false
		refreshStroke()
	end)
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			refreshStroke()
			update(input.Position.X)
		end
	end)
	self.Window:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input.Position.X)
		end
	end)
	self.Window:_connect(UserInputService.InputEnded, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			refreshStroke()
		end
	end)

	obj.Value = nil
	obj:Set(o.default or min, true)
	library.Elements[flag] = obj
	return obj
end

--// Dropdown
function Section:AddDropdown(text, options, default, callback)
	local o
	if type(text) == "table" then
		o = text
	else
		if type(default) == "function" then
			callback, default = default, nil
		end
		o = { text = text, options = options, default = default, callback = callback }
	end
	o.text = tostring(o.text or "Dropdown")
	local flag = flagOf(o)

	local COLLAPSED = 44
	local row = self:_row(COLLAPSED)
	row.ClipsDescendants = true
	makeLabel(row, o.text, { Size = UDim2.new(1, 0, 0, 14) })

	local btn = create("TextButton", {
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 25),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	corner(btn, 5)
	local bs = stroke(btn, Theme.White, 0.9)
	local valueLabel = makeLabel(btn, "", {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -30, 1, 0),
		TextColor3 = Theme.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local arrow = makeLabel(btn, "+", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0, 12, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	corner(list, 5)
	stroke(list, Theme.White, 0.92)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	onAccent(function()
		list.ScrollBarImageColor3 = Theme.Accent
	end)

	local obj = { Value = nil, Options = o.options or {}, IsOpen = false }
	local optionButtons = {}

	local function listHeight()
		return math.min(#obj.Options, 5) * 22
	end
	local function resize()
		local h = obj.IsOpen and (48 + listHeight() + 2) or COLLAPSED
		tween(row, { Size = UDim2.new(1, 0, 0, h) }, 0.25)
		arrow.Text = obj.IsOpen and "-" or "+"
	end
	local function refreshVisual()
		valueLabel.Text = obj.Value ~= nil and tostring(obj.Value) or (o.placeholder or "none")
		valueLabel.TextColor3 = obj.Value ~= nil and Theme.Text or Theme.SubText
		for _, e in ipairs(optionButtons) do
			e.Btn.TextColor3 = (e.Opt == obj.Value) and Theme.Accent or Theme.SubText
		end
	end
	onAccent(refreshVisual)

	local function rebuild()
		for _, e in ipairs(optionButtons) do
			e.Btn:Destroy()
		end
		optionButtons = {}
		for i, opt in ipairs(obj.Options) do
			local b = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundColor3 = Theme.White,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = tostring(opt),
				Font = Theme.Font,
				TextSize = 12,
				TextColor3 = Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = i,
				Parent = list,
			})
			padding(b, 8, 0, 8, 0)
			hover(b, function()
				tween(b, { BackgroundTransparency = 0.94 }, 0.12)
			end, function()
				tween(b, { BackgroundTransparency = 1 }, 0.12)
			end)
			b.MouseButton1Click:Connect(function()
				obj:Set(opt)
				obj:Close()
			end)
			table.insert(optionButtons, { Opt = opt, Btn = b })
		end
		list.Size = UDim2.new(1, 0, 0, listHeight())
		refreshVisual()
		if obj.IsOpen then
			resize()
		end
	end

	function obj:Open()
		self.IsOpen = true
		tween(bs, { Color = Theme.Accent, Transparency = 0.5 }, 0.15)
		resize()
	end
	function obj:Close()
		self.IsOpen = false
		tween(bs, { Color = Theme.White, Transparency = 0.9 }, 0.15)
		resize()
	end
	function obj:Set(v, silent)
		self.Value = v
		library.Flags[flag] = v
		refreshVisual()
		if not silent and o.callback and v ~= nil then
			task.spawn(o.callback, v)
		end
	end
	function obj:Get()
		return self.Value
	end
	function obj:Refresh(newOptions, keep)
		self.Options = newOptions or {}
		if not keep or not table.find(self.Options, self.Value) then
			self.Value = nil
			library.Flags[flag] = nil
		end
		rebuild()
	end

	btn.MouseButton1Click:Connect(function()
		if obj.IsOpen then
			obj:Close()
		else
			obj:Open()
		end
	end)
	hover(btn, function()
		if not obj.IsOpen then
			tween(bs, { Transparency = 0.7 }, 0.15)
		end
	end, function()
		if not obj.IsOpen then
			tween(bs, { Transparency = 0.9 }, 0.15)
		end
	end)

	rebuild()
	if o.default ~= nil then
		obj:Set(o.default, true)
	end
	library.Elements[flag] = obj
	return obj
end

--// Keybind
function Section:AddBind(text, default, callback, changed)
	local o
	if type(text) == "table" then
		o = text
	else
		o = { text = text, default = default, callback = callback, changed = changed }
	end
	o.text = tostring(o.text or "Keybind")
	local flag = flagOf(o)

	local row = self:_row(20)
	makeLabel(row, o.text, { Size = UDim2.new(1, -60, 1, 0) })
	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	corner(btn, 4)
	padding(btn, 8, 0, 8, 0)
	local bs = stroke(btn, Theme.White, 0.9)
	local keyLabel = makeLabel(btn, "", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 11,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local obj = { Value = Enum.KeyCode.Unknown, Listening = false }
	local function refresh()
		keyLabel.Text = obj.Listening and "..." or ("[" .. keyName(obj.Value) .. "]")
		keyLabel.TextColor3 = obj.Listening and Theme.Accent or Theme.Text
	end
	onAccent(refresh)

	function obj:Set(key, silent)
		if typeof(key) == "string" then
			key = Enum.KeyCode[key] or Enum.KeyCode.Unknown
		end
		self.Value = key or Enum.KeyCode.Unknown
		library.Flags[flag] = self.Value
		refresh()
		if not silent and o.changed then
			task.spawn(o.changed, self.Value)
		end
	end
	function obj:Get()
		return self.Value
	end

	btn.MouseButton1Click:Connect(function()
		obj.Listening = true
		library._listening = true
		refresh()
		tween(bs, { Color = Theme.Accent, Transparency = 0.4 }, 0.15)
	end)

	self.Window:_connect(UserInputService.InputBegan, function(input, gp)
		if obj.Listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				obj.Listening = false
				library._listening = false
				library._lastBind = tick()
				tween(bs, { Color = Theme.White, Transparency = 0.9 }, 0.15)
				obj:Set(input.KeyCode == Enum.KeyCode.Escape and Enum.KeyCode.Unknown or input.KeyCode)
			end
			return
		end
		if gp or isBusy() then
			return
		end
		if obj.Value ~= Enum.KeyCode.Unknown and input.KeyCode == obj.Value and o.callback then
			task.spawn(o.callback, obj.Value)
		end
	end)

	obj:Set(o.default or Enum.KeyCode.Unknown, true)
	library.Elements[flag] = obj
	return obj
end

--// Forward element methods from Tab -> current section
for _, name in ipairs({ "AddSeparator", "AddLabel", "AddToggle", "AddButton", "AddBox", "AddSlider", "AddDropdown", "AddBind" }) do
	Tab[name] = function(self, ...)
		local sec = self:_current()
		return sec[name](sec, ...)
	end
end

--------------------------------------------------------------------------------
-- KEY SYSTEM
-- One call: library.NewKeySystem({ ... }) -> small centered window with a key box,
-- a "Check Key" button and a "Get Key" button.
--
-- Options (all optional):
--   Title        string   window title            (default "Velune Key System")
--   Subtitle     string   gray text next to title (default "")
--   Heading      string   big text in the box     (default "Authentication Required")
--   Description  string   small text under it     (default "Enter your key to continue.")
--   Placeholder  string   textbox placeholder     (default "Enter your key...")
--   CheckText    string   check button text       (default "Check Key")
--   GetKeyText   string   get key button text     (default "Get Key")
--   Link         string   copied to clipboard when Get Key is pressed (if no OnGetKey)
--   Closable     bool     show the X button       (default true)
--   CloseOnSuccess bool   close after valid key   (default true)
--   OnCheck(key, ks)  -> return true / false [, message]. May yield (HTTP etc.)
--   OnGetKey(ks)      custom Get Key behaviour (replaces the clipboard default)
--   OnSuccess(key, ks) runs after OnCheck returned true
--   OnClose(ks)       runs when the X button is pressed
--------------------------------------------------------------------------------
local KeySystem = {}
KeySystem.__index = KeySystem

local KS_W, KS_H = 300, 260

function library.NewKeySystem(opts)
	if type(opts) ~= "table" then
		opts = {}
	end
	local title = tostring(opts.Title or "Velune Key System")
	local subtitle = tostring(opts.Subtitle or "")

	local self = setmetatable({
		Options = opts,
		Connections = {},
		Closed = false,
		_busy = false,
	}, KeySystem)

	local function kx(px) return px / KS_W end
	local function ky(px) return px / KS_H end

	local gui = create("ScreenGui", {
		Name = HttpService:GenerateGUID(false),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		end
	end)
	gui.Parent = getGuiParent()
	self.Gui = gui

	local function vpSize()
		local s = gui.AbsoluteSize
		if s.X <= 0 or s.Y <= 0 then
			local cam = workspace.CurrentCamera
			s = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		end
		return s
	end
	local function heightScale()
		return (vpSize().Y < 720) and 0.7 or 0.42
	end

	-- Root: fraction of the screen, locked to the window's aspect ratio
	local root = create("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, heightScale()),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	create("UIAspectRatioConstraint", {
		AspectRatio = KS_W / KS_H,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = root,
	})

	local main = create("CanvasGroup", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = root,
	})
	create("UICorner", { CornerRadius = UDim.new(12 / KS_W, 0), Parent = main })

	local pop = { v = 0.92 }
	local function getK()
		local vp = vpSize()
		return math.min(vp.X * 0.9 / KS_W, vp.Y * heightScale() / KS_H)
	end
	local canvas, updateScale = makeScaler(main, getK, pop)
	local popValue = create("NumberValue", { Value = 0.92 })
	popValue.Changed:Connect(function(v)
		pop.v = v
		updateScale()
	end)
	self._popValue = popValue
	self.Root, self.Main, self.Canvas = root, main, canvas

	-- background (same glass look as the main window)
	local bg = create("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = canvas,
	})
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(30, 30, 37), Color3.fromRGB(14, 14, 18)),
		Rotation = 65,
		Parent = bg,
	})

	local glow = create("Frame", {
		Name = "Glow",
		Size = UDim2.new(1, 0, ky(110), 0),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	do
		local g = create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0.86, 1),
			Parent = glow,
		})
		onAccent(function()
			g.Color = ColorSequence.new(Theme.Accent)
		end)
	end

	local topLine = create("Frame", {
		Name = "TopLine",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	do
		local g = create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = topLine,
		})
		onAccent(function()
			g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
		end)
	end

	-- Header: logo + title
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, ky(34), 0),
		BackgroundTransparency = 1,
		Parent = canvas,
	})

	local logoHolder = create("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(kx(16), 0, 0.5, 0),
		Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),
		BackgroundTransparency = 1,
		Parent = header,
	})
	for _, layer in ipairs({
		{ scale = 1.75, base = 0.94 },
		{ scale = 1.42, base = 0.89 },
		{ scale = 1.18, base = 0.82 },
		}) do
		local img = create("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(layer.scale, layer.scale),
			BackgroundTransparency = 1,
			Image = LOGO_ID,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = layer.base,
			Parent = logoHolder,
		})
		onAccent(function()
			img.ImageColor3 = Theme.Accent
		end)
		TweenService:Create(
			img,
			TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ ImageTransparency = math.min(layer.base + 0.07, 1) }
		):Play()
	end
	create("ImageLabel", {
		Name = "LogoImage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = LOGO_ID,
		ScaleType = Enum.ScaleType.Fit,
		Parent = logoHolder,
	})

	local titleHolder = create("Frame", {
		Position = UDim2.fromScale(kx(16 + LOGO_SIZE + 9), 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = header,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = titleHolder,
	})
	-- "Velune" in white, the rest in the accent color
	local tFirst, tRest = title:match("^(%S+)%s+(.+)$")
	local titleLabel = create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		RichText = true,
		Text = title,
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		Parent = titleHolder,
	})
	onAccent(function()
		if tFirst then
			titleLabel.Text = string.format('%s <font color="#%s">%s</font>', tFirst, Theme.Accent:ToHex(), tRest)
		else
			titleLabel.Text = title
		end
	end)
	if subtitle ~= "" then
		create("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(0, 0, 0, 20),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = subtitle,
			Font = Theme.Font,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			Parent = titleHolder,
		})
	end

	-- close button (top right)
	if opts.Closable ~= false then
		local closeBtn = create("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "x",
			Font = Theme.Font,
			TextSize = 14,
			TextColor3 = Theme.SubText,
			Parent = header,
		})
		hover(closeBtn, function()
			tween(closeBtn, { TextColor3 = Theme.Accent }, 0.15)
		end, function()
			tween(closeBtn, { TextColor3 = Theme.SubText }, 0.15)
		end)
		closeBtn.MouseButton1Click:Connect(function()
			if opts.OnClose then
				task.spawn(opts.OnClose, self)
			end
			self:Close()
		end)
	end

	-- Inner frame
	local inner = create("Frame", {
		Name = "Inner",
		Position = UDim2.fromScale(kx(10), ky(34)),
		Size = UDim2.fromScale(1 - kx(20), 1 - ky(44)),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	corner(inner, 8)
	stroke(inner, Theme.White, 0.9)

	makeLabel(inner, tostring(opts.Heading or "Authentication Required"), {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	makeLabel(inner, tostring(opts.Description or "Enter your key to continue."), {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	makeLabel(inner, "Key", {
		Position = UDim2.fromOffset(16, 76),
		Size = UDim2.new(1, -32, 0, 14),
	})
	local boxHolder = create("Frame", {
		Name = "BoxHolder",
		Position = UDim2.fromOffset(16, 94),
		Size = UDim2.new(1, -32, 0, 30),
		BackgroundTransparency = 1,
		Parent = inner,
	})
	local tb = create("TextBox", {
		Name = "KeyBox",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.1,
		Text = "",
		PlaceholderText = tostring(opts.Placeholder or "Enter your key..."),
		PlaceholderColor3 = Color3.fromRGB(95, 95, 105),
		TextColor3 = Theme.Text,
		Font = Theme.Font,
		TextSize = 12,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = boxHolder,
	})
	corner(tb, 5)
	padding(tb, 10, 0, 10, 0)
	local tbStroke = stroke(tb, Theme.White, 0.9)
	self.Textbox = tb

	tb.Focused:Connect(function()
		tween(tbStroke, { Color = Theme.Accent, Transparency = 0.45 }, 0.15)
	end)

	local statusLabel = makeLabel(inner, "", {
		Position = UDim2.fromOffset(16, 134),
		Size = UDim2.new(1, -32, 0, 14),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- buttons
	local function makeButton(text, primary, position, size)
		local btn = create("TextButton", {
			Position = position,
			Size = size,
			BackgroundColor3 = Theme.Element,
			BackgroundTransparency = 0.1,
			AutoButtonColor = false,
			Text = text,
			Font = primary and Theme.FontBold or Theme.Font,
			TextSize = 12,
			TextColor3 = Theme.Text,
			Parent = inner,
		})
		corner(btn, 5)
		local bs = stroke(btn, Theme.White, 0.9)
		local function base()
			return primary and Theme.Element:Lerp(Theme.Accent, 0.16) or Theme.Element
		end
		local function restStroke()
			if primary then
				return Theme.Accent, 0.65
			end
			return Theme.White, 0.9
		end
		onAccent(function()
			btn.BackgroundColor3 = base()
			local c, t = restStroke()
			bs.Color, bs.Transparency = c, t
		end)
		hover(btn, function()
			tween(btn, { BackgroundColor3 = base():Lerp(Theme.Accent, 0.14) }, 0.15)
			tween(bs, { Color = Theme.Accent, Transparency = 0.5 }, 0.15)
		end, function()
			local c, t = restStroke()
			tween(btn, { BackgroundColor3 = base() }, 0.15)
			tween(bs, { Color = c, Transparency = t }, 0.15)
		end)
		btn.MouseButton1Down:Connect(function()
			btn.BackgroundColor3 = base():Lerp(Theme.Accent, 0.35)
			tween(btn, { BackgroundColor3 = base():Lerp(Theme.Accent, 0.14) }, 0.35)
		end)
		return btn
	end

	local checkBtn = makeButton(
		tostring(opts.CheckText or "Check Key"), true,
		UDim2.new(0, 16, 0, 160), UDim2.new(0.5, -20, 0, 30)
	)
	local getBtn = makeButton(
		tostring(opts.GetKeyText or "Get Key"), false,
		UDim2.new(0.5, 4, 0, 160), UDim2.new(0.5, -20, 0, 30)
	)
	self.CheckButton, self.GetKeyButton = checkBtn, getBtn

	-- animated border on top of everything
	local edge = create("Frame", {
		Name = "Edge",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = canvas,
	})
	corner(edge, 12)
	do
		local s = stroke(edge, Theme.White, 0.45, 1)
		local g = create("UIGradient", { Rotation = 35, Parent = s })
		onAccent(function()
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Accent),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 70, 82)),
				ColorSequenceKeypoint.new(1, Theme.Accent2),
			})
		end)
	end

	--// behaviour
	function self:SetStatus(text, kind)
		statusLabel.Text = tostring(text or "")
		if kind == "success" then
			statusLabel.TextColor3 = Theme.Success
		elseif kind == "error" then
			statusLabel.TextColor3 = Theme.Error
		else
			statusLabel.TextColor3 = Theme.SubText
		end
		statusLabel.TextTransparency = 1
		tween(statusLabel, { TextTransparency = 0 }, 0.2)
	end

	function self:GetKey()
		return (tb.Text:match("^%s*(.-)%s*$"))
	end

	function self:SetKey(k)
		tb.Text = tostring(k or "")
	end

	function self:Shake()
		task.spawn(function()
			for _, off in ipairs({ 6, -6, 4, -4, 0 }) do
				if self.Closed then
					return
				end
				tween(boxHolder, { Position = UDim2.fromOffset(16 + off, 94) }, 0.045, Enum.EasingStyle.Sine)
				task.wait(0.045)
			end
		end)
		tween(tbStroke, { Color = Theme.Error, Transparency = 0.35 }, 0.15)
		task.delay(0.8, function()
			if not self.Closed then
				tween(tbStroke, { Color = Theme.White, Transparency = 0.9 }, 0.2)
			end
		end)
	end

	function self:Check()
		if self._busy or self.Closed then
			return
		end
		local key = self:GetKey()
		if key == "" then
			self:SetStatus("Please enter a key", "error")
			self:Shake()
			return
		end
		self._busy = true
		local oldText = checkBtn.Text
		checkBtn.Text = "Checking..."
		self:SetStatus("")
		task.spawn(function()
			if not opts.OnCheck then
				self:SetStatus("No OnCheck callback set", "error")
			else
				local ok, res, msg = pcall(opts.OnCheck, key, self)
				if not ok then
					self:SetStatus("Callback error, see console", "error")
					warn("[velune.gg] KeySystem OnCheck error: " .. tostring(res))
				elseif res == true then
					self:SetStatus(msg or "Key valid", "success")
					if opts.OnSuccess then
						task.spawn(opts.OnSuccess, key, self)
					end
					if opts.CloseOnSuccess ~= false then
						task.delay(0.8, function()
							self:Close()
						end)
					end
				elseif res == false then
					self:SetStatus(msg or "Invalid key", "error")
					self:Shake()
				end
			end
			if not self.Closed then
				checkBtn.Text = oldText
			end
			self._busy = false
		end)
	end

	function self:GetKeyPressed()
		if opts.OnGetKey then
			task.spawn(function()
				local ok, err = pcall(opts.OnGetKey, self)
				if not ok then
					warn("[velune.gg] KeySystem OnGetKey error: " .. tostring(err))
				end
			end)
			return
		end
		if type(setclipboard) == "function" and opts.Link then
			local ok = pcall(setclipboard, tostring(opts.Link))
			self:SetStatus(ok and "Copied link" or "Could not copy link", ok and "success" or "error")
		elseif not opts.Link then
			self:SetStatus("No link set", "error")
		else
			self:SetStatus("Clipboard unavailable", "error")
		end
	end

	function self:Close()
		if self.Closed then
			return
		end
		self.Closed = true
		tween(main, { GroupTransparency = 1 }, 0.2)
		tween(popValue, { Value = 0.94 }, 0.2)
		task.delay(0.25, function()
			self:Destroy()
		end)
	end

	function self:Destroy()
		self.Closed = true
		for _, c in ipairs(self.Connections) do
			pcall(function() c:Disconnect() end)
		end
		self.Connections = {}
		pcall(function() popValue:Destroy() end)
		pcall(function() gui:Destroy() end)
		local i = table.find(library.KeySystems, self)
		if i then
			table.remove(library.KeySystems, i)
		end
	end

	checkBtn.MouseButton1Click:Connect(function()
		self:Check()
	end)
	getBtn.MouseButton1Click:Connect(function()
		self:GetKeyPressed()
	end)
	tb.FocusLost:Connect(function(enter)
		tween(tbStroke, { Color = Theme.White, Transparency = 0.9 }, 0.15)
		if enter then
			self:Check()
		end
	end)

	-- dragging (by the header)
	do
		local dragging, dragStart, startPos = false, nil, nil
		header.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = root.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)
		table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local d = input.Position - dragStart
				local vp = vpSize()
				tween(root, {
					Position = UDim2.fromScale(startPos.X.Scale + d.X / vp.X, startPos.Y.Scale + d.Y / vp.Y),
				}, 0.08, Enum.EasingStyle.Sine)
			end
		end))
	end

	-- keep it scaled on resize / rotation
	table.insert(self.Connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		root.Size = UDim2.fromScale(0.9, heightScale())
		updateScale()
	end))

	table.insert(library.KeySystems, self)

	-- open animation
	tween(main, { GroupTransparency = 0 }, 0.3)
	tween(popValue, { Value = 1 }, 0.4, Enum.EasingStyle.Back)

	return self
end
library.KeySystem = library.NewKeySystem

--------------------------------------------------------------------------------
-- CONFIGS
--------------------------------------------------------------------------------
local FOLDER = "velune.gg"
local CFG_FOLDER = FOLDER .. "/configs"

local function fsOk()
	return type(writefile) == "function" and type(readfile) == "function" and type(isfolder) == "function"
		and type(makefolder) == "function" and type(listfiles) == "function"
end

local function ensureFolders()
	if not isfolder(FOLDER) then
		makefolder(FOLDER)
	end
	if not isfolder(CFG_FOLDER) then
		makefolder(CFG_FOLDER)
	end
end

local function cleanName(name)
	return (tostring(name or ""):gsub("[^%w_%- ]", ""))
end

function library:GetConfigs()
	if not fsOk() then
		return {}
	end
	ensureFolders()
	local out = {}
	for _, path in ipairs(listfiles(CFG_FOLDER)) do
		local n = path:match("([^/\\]+)%.json$")
		if n then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

function library:SaveConfig(name)
	if not fsOk() then
		return false, "Filesystem not available"
	end
	name = cleanName(name)
	if name == "" then
		return false, "Invalid config name"
	end
	ensureFolders()
	local data = {}
	for flag, val in pairs(library.Flags) do
		if tostring(flag):sub(1, 1) ~= "_" then
			local t = typeof(val)
			if t == "boolean" or t == "number" or t == "string" then
				data[flag] = val
			elseif t == "EnumItem" then
				data[flag] = { __kc = val.Name }
			end
		end
	end
	local ok, err = pcall(function()
		writefile(CFG_FOLDER .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	end)
	return ok, err
end

function library:LoadConfig(name)
	if not fsOk() then
		return false, "Filesystem not available"
	end
	name = cleanName(name)
	local path = CFG_FOLDER .. "/" .. name .. ".json"
	if name == "" or not (type(isfile) == "function" and isfile(path)) then
		return false, "Config not found"
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok then
		return false, "Corrupt config"
	end
	for flag, val in pairs(data) do
		local el = library.Elements[flag]
		if el and el.Set then
			if type(val) == "table" and val.__kc then
				val = Enum.KeyCode[val.__kc] or Enum.KeyCode.Unknown
			end
			pcall(el.Set, el, val)
		end
	end
	return true
end

function library:DeleteConfig(name)
	if not fsOk() or type(delfile) ~= "function" then
		return false, "Filesystem not available"
	end
	name = cleanName(name)
	local path = CFG_FOLDER .. "/" .. name .. ".json"
	if type(isfile) == "function" and isfile(path) then
		delfile(path)
		return true
	end
	return false, "Config not found"
end

--------------------------------------------------------------------------------
-- SETTINGS TAB
--------------------------------------------------------------------------------
function library.CreateSettingsTab(a, b)
	local window = b or a
	local tab = window:AddTab("Settings")

	local main = tab:AddSection("Main", 1)
	main:AddBind({
		text = "Menu Key",
		flag = "_menukey",
		default = window.MenuKey,
		changed = function(key)
			window:SetMenuKey(key)
		end,
	})
	main:AddToggle({
		text = "Watermark",
		flag = "_watermark",
		default = true,
		callback = function(v)
			window:SetWatermark(v)
		end,
	})
	main:AddDropdown({
		text = "Menu Size",
		flag = "_menusize",
		options = { "75%", "90%", "100%", "115%", "130%" },
		default = "100%",
		callback = function(name)
			local n = tonumber((tostring(name):gsub("%%", "")))
			if n then
				window:SetSize(n / 100)
			end
		end,
	})
	main:AddSeparator({ text = "Server" })
	main:AddButton("Rejoin Server", function()
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end)
	end)
	main:AddButton("Rejoin Game", function()
		pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
	end)
	main:AddSeparator({ text = "Interface" })
	main:AddButton("Unload", function()
		library:Unload()
	end)

	local presets = {
		["Velune Orange"] = Color3.fromRGB(255, 197, 121),
		["Rose"] = Color3.fromRGB(255, 143, 177),
		["Mint"] = Color3.fromRGB(126, 232, 192),
		["Sky"] = Color3.fromRGB(142, 197, 255),
		["Lavender"] = Color3.fromRGB(183, 161, 255),
		["Crimson"] = Color3.fromRGB(255, 107, 107),
	}
	local presetNames = { "Velune Orange", "Rose", "Mint", "Sky", "Lavender", "Crimson" }

	-- the window is narrower now, so Theme + Config share column 2
	local theme = tab:AddSection("Theme", 2)
	theme:AddDropdown({
		text = "Accent Preset",
		flag = "_accentpreset",
		options = presetNames,
		default = "Velune Orange",
		callback = function(name)
			if presets[name] then
				library:SetAccent(presets[name])
			end
		end,
	})

	local cfg = tab:AddSection("Config", 2)
	local nameBox = cfg:AddBox({ text = "Config Name", flag = "_cfgname", placeholder = "my config" })
	local list = cfg:AddDropdown({
		text = "Config",
		flag = "_cfglist",
		options = library:GetConfigs(),
		placeholder = "none",
	})
	local function note(ok, msg, success)
		window:Notify(ok and "Config" or "Config error", ok and success or tostring(msg), 3)
	end
	cfg:AddButton("Load", function()
		local sel = list:Get()
		if not sel then return note(false, "Select a config first") end
		local ok, err = library:LoadConfig(sel)
		note(ok, err, "Loaded " .. sel)
	end)
	cfg:AddButton("Save", function()
		local sel = list:Get()
		if not sel then return note(false, "Select a config first") end
		local ok, err = library:SaveConfig(sel)
		note(ok, err, "Saved " .. sel)
	end)
	cfg:AddButton("Create", function()
		local n = cleanName(nameBox:Get())
		if n == "" then return note(false, "Enter a config name") end
		local ok, err = library:SaveConfig(n)
		if ok then
			list:Refresh(library:GetConfigs())
			list:Set(n, true)
		end
		note(ok, err, "Created " .. n)
	end)
	cfg:AddButton("Delete", function()
		local sel = list:Get()
		if not sel then return note(false, "Select a config first") end
		local ok, err = library:DeleteConfig(sel)
		if ok then
			list:Refresh(library:GetConfigs())
		end
		note(ok, err, "Deleted " .. sel)
	end)

	return tab
end

--------------------------------------------------------------------------------
do
	local genv = type(getgenv) == "function" and getgenv() or nil
	if genv then
		genv.__VeluneLib = library
	end
end

return library
