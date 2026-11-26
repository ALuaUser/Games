--[[
    R1 Battle Royale · ESP + Aim Assist
    Bundled with LiteUI v1.2.0 (your v0.0.5)
]]

--[[
    LiteUI  —  all-in-one script
    Part 1: the UI library
    Part 2: example usage (edit or delete it, then build your own UI)
]]

----------------------------------------------------------------
-- PART 1: LIBRARY
----------------------------------------------------------------
--[[
    LiteUI  v1.2.0
    A flat, minimal UI library for Roblox: cards, tabs, collapsible panels, settings.

    ── Quick start ──────────────────────────────────────────────
    local ui   = Lite.new({ Name = "MyHUD", Key = Enum.KeyCode.RightShift })
    local card = ui:Card({ Title = "Hello", Subtitle = "World", Value = "42" })
    local tab  = ui:Tabs({ "Main", "Utility", "Settings" })   -- window widens to fit the tab names
    tab.Main:Toggle({ Name = "Enabled", Flag = "enabled", Default = true, Callback = print })
    ui:Settings({ Panel = tab.Settings })
    ui:Show()

    ── API ──────────────────────────────────────────────────────
    Lite.new(opts)  opts: Name, Width(264, grows to fit tabs), Key, Theme("dark"), Opacity(.96),
                          Scale(1), X, Y, Parent, DisplayOrder, Save(true), SaveFile, MobileButton(true)
    Lite.Themes     dark, light, ocean, mocha, rose, forest  (add your own before Lite.new)

    Window:  :Card(opts)  :Panel(opts)  :Tabs(names, opts)  :Settings(opts)
             :Notify{Title,Text,Duration,Tone}      toast, bottom-right
             :Prompt{Title,Text,Yes,No,Tone,Callback(bool)}   confirm dialog
             :Watermark{Text,FPS,Ping,Position}     small fps / ping badge
             :Show() :Hide() :Toggle() :Destroy()
             :SetTheme(n) :SetOpacity(v) :SetScale(v) :SetKey(k) :SetWidth(px) :SetAccent(Color3|nil)
             :ExportConfig() :ImportConfig(json) :ResetConfig()
             :OnDestroy(fn)    .Flags (saved values)   .Alive

    Card:    :Set{Title,Subtitle,Value,Tone}  :SetTone(key | Color3)  :Minimize(bool)
             :SetPinned(bool) :IsPinned() :AddButton(text, fn) :Attach(panel, closed, open)
             opts: Title, Subtitle, Value, Tone, Closable, Minimizable, Pinnable, OnPin

    Tabs:    local tab, bar = ui:Tabs({"A","B"}, {MaxHeight=250, Default="A", MaxWidth=460})
             tab.A / tab.B are Panels.   bar:Select("B")
             Width grows so every tab name fits; past MaxWidth the tab bar scrolls.

    Panel:   :SetOpen(bool) :IsOpen()
             opts: Name, Open, Persist, MaxHeight (scrolls when taller)
             :Section(text)  :Label{Text,Tone}  :Paragraph(text)  :Separator()
             :Button{Name,Callback,Tone}   :ButtonRow{ {Name,Callback,Tone}, ... }
             :Toggle{Name,Default,Flag,Callback,Keybind}   (Keybind adds a key chip)
             :Slider{Name,Min,Max,Step,Default,Flag,Format,Suffix,Callback}
             :Choice{Name,Options,Default,Flag,Callback}            (click to cycle)
             :Dropdown{Name,Options,Default,Multi,Flag,Callback}    (expands inline)
             :TextBox{Name,Placeholder,Default,Numeric,OnlyEnter,Flag,Callback}
             :ColorPicker{Name,Default,Flag,Callback}
             :Keybind{Name,Default,Flag,Callback,Press}
             :Bar{Name,Min,Max,Default,Format,Tone}  ->  :Set(v) :SetTone(key)
             :List{Max,Empty}  ->  :Push(name, value)  :Clear()

    Every element also takes  Tooltip = "text"  and returns an object with
             :SetVisible(bool)  :SetEnabled(bool)  :Destroy()  .Row

    Elements with a Flag are saved/restored, and their Callback is called once
    on load with the restored value.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Lite = { Version = "1.2.0" }

----------------------------------------------------------------
-- Themes
----------------------------------------------------------------
Lite.Themes = {
    dark = {
        bg = Color3.fromRGB(20, 21, 24),
        line = Color3.fromRGB(255, 255, 255),
        text = Color3.fromRGB(236, 237, 240),
        sub = Color3.fromRGB(135, 139, 148),
        accent = Color3.fromRGB(120, 200, 150),
        warn = Color3.fromRGB(224, 175, 104),
        danger = Color3.fromRGB(228, 108, 108),
        track = Color3.fromRGB(46, 48, 55),
    },
    light = {
        bg = Color3.fromRGB(248, 248, 250),
        line = Color3.fromRGB(0, 0, 0),
        text = Color3.fromRGB(28, 29, 33),
        sub = Color3.fromRGB(112, 116, 126),
        accent = Color3.fromRGB(38, 148, 92),
        warn = Color3.fromRGB(190, 128, 40),
        danger = Color3.fromRGB(196, 62, 62),
        track = Color3.fromRGB(214, 216, 222),
    },
    ocean = {
        bg = Color3.fromRGB(14, 22, 34),
        line = Color3.fromRGB(180, 215, 255),
        text = Color3.fromRGB(226, 238, 252),
        sub = Color3.fromRGB(110, 140, 175),
        accent = Color3.fromRGB(90, 190, 230),
        warn = Color3.fromRGB(232, 184, 108),
        danger = Color3.fromRGB(232, 110, 110),
        track = Color3.fromRGB(32, 48, 68),
    },
    mocha = {
        bg = Color3.fromRGB(30, 24, 22),
        line = Color3.fromRGB(255, 240, 225),
        text = Color3.fromRGB(240, 230, 220),
        sub = Color3.fromRGB(150, 135, 125),
        accent = Color3.fromRGB(214, 160, 110),
        warn = Color3.fromRGB(232, 200, 110),
        danger = Color3.fromRGB(224, 110, 100),
        track = Color3.fromRGB(54, 45, 41),
    },
    rose = {
        bg = Color3.fromRGB(28, 20, 26),
        line = Color3.fromRGB(255, 230, 240),
        text = Color3.fromRGB(244, 232, 238),
        sub = Color3.fromRGB(150, 125, 140),
        accent = Color3.fromRGB(232, 130, 160),
        warn = Color3.fromRGB(230, 184, 110),
        danger = Color3.fromRGB(230, 100, 110),
        track = Color3.fromRGB(52, 38, 48),
    },
    forest = {
        bg = Color3.fromRGB(17, 24, 20),
        line = Color3.fromRGB(200, 255, 215),
        text = Color3.fromRGB(228, 240, 230),
        sub = Color3.fromRGB(120, 145, 128),
        accent = Color3.fromRGB(110, 200, 130),
        warn = Color3.fromRGB(222, 188, 110),
        danger = Color3.fromRGB(226, 108, 108),
        track = Color3.fromRGB(36, 50, 42),
    },
}

local Window, Card, Panel = {}, {}, {}
Window.__index, Card.__index, Panel.__index = Window, Card, Panel

local QUINT = Enum.EasingStyle.Quint
local GAP = 6 -- vertical gap between boxes and between panel elements

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function tween(obj, props, t, style, dir)
    t = t or 0.2
    if t == 0 then
        for k, v in pairs(props) do
            obj[k] = v
        end
        return
    end
    TweenService:Create(
        obj,
        TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    ):Play()
end

local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do
        o[k] = v
    end
    o.Parent = parent
    return o
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

local function keyOf(v, fallback)
    if typeof(v) == "EnumItem" then
        return v
    end
    if type(v) == "string" then
        local ok, k = pcall(function()
            return Enum.KeyCode[v]
        end)
        if ok and k then
            return k
        end
    end
    return fallback
end

local function capitalize(s)
    return (tostring(s):gsub("^%l", string.upper))
end

----------------------------------------------------------------
-- Window: construction, settings, theme
----------------------------------------------------------------
function Window:_load(defaults)
    local raw
    if self._saveOn then
        if type(isfile) == "function" and type(readfile) == "function" then
            local ok, res = pcall(function()
                if isfile(self._file) then
                    return readfile(self._file)
                end
            end)
            if ok then
                raw = res
            end
        end
        if not raw then
            raw = Players.LocalPlayer:GetAttribute(self._attr)
        end
    end

    local out = table.clone(defaults)
    if type(raw) == "string" then
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok and type(data) == "table" then
            for k, def in pairs(defaults) do
                if type(data[k]) == type(def) then
                    out[k] = data[k]
                end
            end
        end
    end

    out.opacity = math.clamp(out.opacity, 0.5, 1)
    out.scale = math.clamp(out.scale, 0.5, 2)
    if not Lite.Themes[out.theme] then
        out.theme = "dark"
    end
    return out
end

function Window:_save()
    if not self._saveOn then
        return
    end
    self._saveToken += 1
    local mine = self._saveToken
    task.delay(0.4, function()
        if mine ~= self._saveToken then
            return
        end
        local ok, raw = pcall(HttpService.JSONEncode, HttpService, self.S)
        if not ok then
            return
        end
        pcall(Players.LocalPlayer.SetAttribute, Players.LocalPlayer, self._attr, raw)
        if type(writefile) == "function" then
            pcall(writefile, self._file, raw)
        end
    end)
end

function Window:_flagGet(key, default)
    if key == nil then
        return default
    end
    local v = self.S.flags[key]
    if v ~= nil and (default == nil or type(v) == type(default)) then
        return v
    end
    return default
end

function Window:_flagSet(key, value)
    if key == nil then
        return
    end
    self.S.flags[key] = value
    self:_save()
end

function Window:_color(key)
    if typeof(key) == "Color3" then
        return key
    end
    if key == "accent" and self._accent then
        return self._accent
    end
    local t = Lite.Themes[self.S.theme] or Lite.Themes.dark
    return t[key] or Lite.Themes.dark[key] or Color3.fromRGB(255, 0, 255)
end

function Window:_themed(obj, prop, key)
    local e = { obj = obj, prop = prop, key = key }
    table.insert(self._registry, e)
    obj[prop] = self:_color(key)
    return e
end

function Window:_setKey(entry, key, instant)
    entry.key = key
    tween(entry.obj, { [entry.prop] = self:_color(key) }, instant and 0 or 0.2)
end

function Window:_applyTheme(animate)
    local alive = {}
    for _, e in ipairs(self._registry) do
        if e.obj.Parent ~= nil then
            table.insert(alive, e)
            tween(e.obj, { [e.prop] = self:_color(e.key) }, animate and 0.25 or 0)
        end
    end
    self._registry = alive
end

function Lite.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Window)

    self.Name = opts.Name or "LiteUI"
    self.Width = opts.Width or 264
    self.Alive = true
    self._conns, self._registry, self._boxes, self._binds = {}, {}, {}, {}
    self._onDestroy = {}
    self._onWidth = {}
    self._order = 0
    self._shown = false
    self._ready = false
    self._saveToken = 0
    self._saveOn = opts.Save ~= false
    self._file = opts.SaveFile or ("LiteUI_" .. self.Name .. ".json")
    self._attr = "LiteUI_" .. self.Name
    self._touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

    local keyDefault = keyOf(opts.Key, Enum.KeyCode.RightShift)
    self.S = self:_load({
        x = opts.X or 18,
        y = opts.Y or 120,
        opacity = opts.Opacity or 0.96,
        scale = opts.Scale or 1,
        theme = opts.Theme or "dark",
        key = keyDefault.Name,
        accent = "",
        flags = {},
    })
    self.Flags = self.S.flags
    do
        local okA, cA = pcall(Color3.fromHex, self.S.accent)
        self._accent = okA and cA or nil
    end
    self._key = keyOf(self.S.key, keyDefault)

    local parent = opts.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")
    local old = parent:FindFirstChild(self.Name)
    if old then
        old:Destroy()
    end

    self.Gui = make("ScreenGui", {
        Name = self.Name,
        ResetOnSpawn = false,
        DisplayOrder = opts.DisplayOrder or 100,
        IgnoreGuiInset = true,
        Enabled = false,
    }, parent)

    local vp = viewport()
    self.S.x = math.clamp(self.S.x, 0, math.max(vp.X - self.Width, 0))
    self.S.y = math.clamp(self.S.y, 0, math.max(vp.Y - 72, 0))
    self._rest = UDim2.fromOffset(self.S.x, self.S.y)

    -- CanvasGroup lets everything fade in/out together
    self.Root = make("CanvasGroup", {
        Name = "Root",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(self.Width, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = self._rest,
        GroupTransparency = 1,
    }, self.Gui)
    self._scale = make("UIScale", { Scale = self.S.scale }, self.Root)
    make("UIListLayout", {
        Padding = UDim.new(0, GAP),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, self.Root)

    self.Gui.Destroying:Connect(function()
        self.Alive = false
        if self._auxGui then
            self._auxGui:Destroy()
        end
        for _, c in ipairs(self._conns) do
            c:Disconnect()
        end
        for _, fn in ipairs(self._onDestroy) do
            pcall(fn)
        end
    end)

    self:_installInput()
    if self._touchOnly and opts.MobileButton ~= false then
        self:_mobileButton()
    end
    task.defer(function()
        self._ready = true
    end)
    return self
end

function Window:OnDestroy(fn)
    table.insert(self._onDestroy, fn)
end

----------------------------------------------------------------
-- Window: input (hotkey, keybinds, drag + snap, sliders)
----------------------------------------------------------------
local SNAP, MARGIN, TOP_M = 16, 12, 44

function Window:_beginDrag(input)
    self._drag = {
        moved = false,
        sx = input.Position.X,
        sy = input.Position.Y,
        pos = self.Root.Position,
    }
end

function Window:_snap(x, y)
    local vp, sz = viewport(), self.Root.AbsoluteSize
    if x < SNAP + MARGIN then
        x = MARGIN
    elseif x + sz.X > vp.X - SNAP - MARGIN then
        x = vp.X - sz.X - MARGIN
    end
    if y < SNAP + TOP_M then
        y = TOP_M
    elseif y + sz.Y > vp.Y - SNAP - MARGIN then
        y = vp.Y - sz.Y - MARGIN
    end
    return x, y
end

function Window:_installInput()
    local function track(c)
        table.insert(self._conns, c)
    end

    track(UserInputService.InputBegan:Connect(function(input, processed)
        if self._rebinding and input.UserInputType == Enum.UserInputType.Keyboard then
            local cb = self._rebinding
            self._rebinding = nil
            cb(input.KeyCode)
            return
        end
        if processed then
            return
        end
        if self._key ~= Enum.KeyCode.Unknown and input.KeyCode == self._key then
            self:Toggle()
            return
        end
        for _, b in ipairs(self._binds) do
            if b.Press and b.Value ~= Enum.KeyCode.Unknown and b.Value == input.KeyCode then
                task.spawn(b.Press)
            end
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not isMove(input) then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            self:_moveTip()
        end
        if self._slider then
            self._slider(input.Position.X)
            return
        end
        local d = self._drag
        if not d then
            return
        end
        local dx, dy = input.Position.X - d.sx, input.Position.Y - d.sy
        if not d.moved and (dx * dx + dy * dy) > 9 then
            d.moved = true
        end
        if d.moved then
            local vp, sz = viewport(), self.Root.AbsoluteSize
            self._rest = UDim2.fromOffset(
                math.clamp(d.pos.X.Offset + dx, 0, math.max(vp.X - sz.X, 0)),
                math.clamp(d.pos.Y.Offset + dy, 0, math.max(vp.Y - sz.Y, 0))
            )
            self.Root.Position = self._rest
        end
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if not isPress(input) then
            return
        end
        if self._slider then
            self._slider = nil
            self:_save()
        end
        local d = self._drag
        self._drag = nil
        if d and d.moved then
            local x, y = self:_snap(self._rest.X.Offset, self._rest.Y.Offset)
            self._rest = UDim2.fromOffset(x, y)
            tween(self.Root, { Position = self._rest }, 0.2, QUINT)
            self.S.x, self.S.y = x, y
            self:_save()
        end
    end))
end

----------------------------------------------------------------
-- Window: show / hide / setters
----------------------------------------------------------------
function Window:Show()
    if not self.Alive then
        return
    end
    self._shown = true
    self.Gui.Enabled = true
    self.Root.Position = self._rest + UDim2.fromOffset(0, -8)
    tween(self.Root, { GroupTransparency = 0, Position = self._rest }, 0.3)
end

function Window:Hide(onDone)
    if not self.Alive then
        return
    end
    self._shown = false
    tween(self.Root, {
        GroupTransparency = 1,
        Position = self._rest + UDim2.fromOffset(0, 8),
    }, 0.22, QUINT)
    task.delay(0.22, function()
        if self.Alive and not self._shown then
            self.Gui.Enabled = false
        end
        if onDone then
            onDone()
        end
    end)
end

function Window:Toggle()
    if self._shown then
        self:Hide()
    else
        self:Show()
    end
end

function Window:Destroy()
    if not self.Alive then
        return
    end
    self:Hide(function()
        if self.Alive then
            self.Gui:Destroy()
        end
    end)
end

function Window:SetTheme(name)
    if not Lite.Themes[name] then
        return
    end
    self.S.theme = name
    self:_applyTheme(true)
    self:_save()
end

function Window:SetOpacity(v)
    self.S.opacity = math.clamp(v, 0.5, 1)
    for _, b in ipairs(self._boxes) do
        b.BackgroundTransparency = 1 - self.S.opacity
    end
    self:_save()
end

function Window:SetScale(v)
    self.S.scale = math.clamp(v, 0.5, 2)
    self._scale.Scale = self.S.scale
    self:_save()
end

function Window:SetKey(key)
    self._key = keyOf(key, Enum.KeyCode.Unknown)
    self.S.key = self._key.Name
    self:_save()
end

function Window:_box(name, height)
    self._order += 1
    local f = make("Frame", {
        Name = name,
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1 - self.S.opacity,
        BorderSizePixel = 0,
        LayoutOrder = self._order,
        ClipsDescendants = true,
    }, self.Root)
    self:_themed(f, "BackgroundColor3", "bg")
    make("UICorner", { CornerRadius = UDim.new(0, 10) }, f)
    local st = make("UIStroke", { Thickness = 1, Transparency = 0.9 }, f)
    self:_themed(st, "Color", "line")
    table.insert(self._boxes, f)
    return f
end

----------------------------------------------------------------
-- Card
----------------------------------------------------------------
function Window:Card(opts)
    opts = opts or {}
    local win = self
    local W = self.Width
    local FULL_H, MINI_H = opts.Height or 72, 36

    self._cardCount = (self._cardCount or 0) + 1
    local card = setmetatable({
        Window = self,
        _buttons = {},
        _index = self._cardCount,
        _pinned = false,
        _mini = false,
        _full = FULL_H,
        _miniH = MINI_H,
        _width = W,
        _onPin = opts.OnPin,
    }, Card)

    local f = self:_box("Card", FULL_H)
    f.Active = true
    card.Frame = f

    card.TitleLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 14),
        Size = UDim2.new(1, -122, 0, 20),
        Font = Enum.Font.BuilderSansBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(opts.Title or ""),
    }, f)
    self:_themed(card.TitleLabel, "TextColor3", "text")

    card.SubLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 37),
        Size = UDim2.new(1, -122, 0, 18),
        Font = Enum.Font.BuilderSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(opts.Subtitle or ""),
    }, f)
    self:_themed(card.SubLabel, "TextColor3", "sub")

    card.Divider = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(1, -94, 0.5, 0),
        Size = UDim2.fromOffset(1, 40),
        BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
    }, f)
    self:_themed(card.Divider, "BackgroundColor3", "line")

    card.ValueLabel = make("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -86, 0, 0),
        Size = UDim2.fromOffset(76, FULL_H),
        Font = Enum.Font.BuilderSansExtraBold,
        TextSize = 34,
        Text = tostring(opts.Value or "–"),
        AutoButtonColor = false,
    }, f)
    card._toneEntry = self:_themed(card.ValueLabel, "TextColor3", opts.Tone or "sub")

    card.PinLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -86, 0, FULL_H - 19),
        Size = UDim2.fromOffset(76, 12),
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 11,
        Text = "pinned",
        TextTransparency = 1,
    }, f)
    self:_themed(card.PinLabel, "TextColor3", "sub")

    -- hover reveals header buttons (always visible on touch-only devices)
    if not self._touchOnly then
        f.MouseEnter:Connect(function()
            for _, b in ipairs(card._buttons) do
                tween(b.Instance, { TextTransparency = 0 }, 0.15)
            end
        end)
        f.MouseLeave:Connect(function()
            for _, b in ipairs(card._buttons) do
                tween(b.Instance, { TextTransparency = 1 }, 0.15)
            end
        end)
    end

    if opts.Draggable ~= false then
        f.InputBegan:Connect(function(input)
            if isPress(input) then
                win:_beginDrag(input)
            end
        end)
    end

    if opts.Pinnable ~= false then
        card.ValueLabel.MouseButton1Click:Connect(function()
            card:SetPinned(not card._pinned)
        end)
    end

    if opts.Closable ~= false then
        card:AddButton("×", function()
            win:Destroy()
        end)
    end
    if opts.Minimizable ~= false then
        card._miniBtn = card:AddButton("–", function()
            card:Minimize(not card._mini)
        end)
        if self:_flagGet("_mini:" .. card._index, false) then
            card:Minimize(true, true)
        end
    end

    return card
end

function Card:AddButton(text, callback)
    local win = self.Window
    local slot = #self._buttons
    local b = make("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -22 - slot * 20, 0, 3),
        Size = UDim2.fromOffset(18, 18),
        Font = Enum.Font.BuilderSansBold,
        TextSize = 16,
        Text = text,
        TextTransparency = win._touchOnly and 0 or 1,
        AutoButtonColor = false,
        ZIndex = 5,
    }, self.Frame)
    win:_themed(b, "TextColor3", "sub")
    b.MouseEnter:Connect(function()
        tween(b, { TextColor3 = win:_color("text") }, 0.12)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { TextColor3 = win:_color("sub") }, 0.12)
    end)
    if callback then
        b.MouseButton1Click:Connect(callback)
    end

    local obj = { Instance = b }
    function obj:SetText(t)
        b.Text = t
    end
    table.insert(self._buttons, obj)
    return obj
end

-- Adds a header button that opens/closes a panel and swaps its glyph
function Card:Attach(panel, closedGlyph, openGlyph)
    closedGlyph = closedGlyph or "▾"
    openGlyph = openGlyph or "▴"
    local btn
    btn = self:AddButton(panel:IsOpen() and openGlyph or closedGlyph, function()
        panel:SetOpen(not panel:IsOpen())
        btn:SetText(panel:IsOpen() and openGlyph or closedGlyph)
    end)
    return btn
end

function Card:SetTone(key, instant)
    self.Window:_setKey(self._toneEntry, key, instant)
end

function Card:Set(t)
    if t.Title ~= nil then
        self.TitleLabel.Text = tostring(t.Title)
    end
    if t.Subtitle ~= nil then
        self.SubLabel.Text = tostring(t.Subtitle)
    end
    if t.Value ~= nil then
        local v = tostring(t.Value)
        if v ~= self.ValueLabel.Text then
            self.ValueLabel.Text = v
            if self.Window._shown then
                self.ValueLabel.TextTransparency = 1
                tween(self.ValueLabel, { TextTransparency = 0 }, 0.25)
            end
        end
    end
    if t.Tone then
        self:SetTone(t.Tone)
    end
end

function Card:_updatePin(instant)
    tween(self.PinLabel, {
        TextTransparency = (self._pinned and not self._mini) and 0 or 1,
    }, instant and 0 or 0.2)
end

function Card:SetPinned(p)
    self._pinned = p and true or false
    self:_updatePin()
    if self._onPin then
        task.spawn(self._onPin, self._pinned)
    end
end

function Card:IsPinned()
    return self._pinned
end

function Card:Minimize(state, instant)
    self._mini = state and true or false
    local m = self._mini
    local d = instant and 0 or 0.3

    if self._miniBtn then
        self._miniBtn:SetText(m and "+" or "–")
    end
    tween(self.Frame, { Size = UDim2.new(1, 0, 0, m and self._miniH or self._full) }, d, QUINT)
    tween(self.TitleLabel, {
        Position = UDim2.fromOffset(16, m and 8 or 14),
        TextSize = m and 15 or 17,
    }, d, QUINT)
    tween(self.SubLabel, { TextTransparency = m and 1 or 0 }, instant and 0 or 0.2)
    tween(self.Divider, { Size = UDim2.fromOffset(1, m and 18 or 40) }, d, QUINT)
    tween(self.ValueLabel, {
        Size = UDim2.fromOffset(76, m and self._miniH or self._full),
        TextSize = m and 20 or 34,
    }, d, QUINT)
    self:_updatePin(instant)

    if not instant then
        self.Window:_flagSet("_mini:" .. self._index, self._mini)
    end
end

----------------------------------------------------------------
-- Panel
----------------------------------------------------------------
function Window:Panel(opts)
    opts = opts or {}
    local panel = setmetatable({ Window = self, _items = {} }, Panel)

    local f = self:_box(opts.Name or "Panel", 0)
    f.Visible = false
    panel.Frame = f
    panel._max = opts.MaxHeight

    local content = f
    if opts.MaxHeight then
        content = make("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 3,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.Never,
        }, f)
        self:_themed(content, "ScrollBarImageColor3", "sub")
    end
    make("UIListLayout", {
        Padding = UDim.new(0, GAP),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, content)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
    }, content)
    panel.Content = content

    local open = opts.Open == true
    if opts.Persist and opts.Name then
        panel._flagKey = "_open:" .. opts.Name
        open = self:_flagGet(panel._flagKey, open)
    end
    panel._open = open
    if open then
        f.Visible = true
    end
    return panel
end

function Panel:_height()
    local n, h = 0, 16
    for _, it in ipairs(self._items) do
        if not it.hidden then
            n += 1
            h += it.h
        end
    end
    if n == 0 then
        return 16
    end
    h += GAP * (n - 1)
    if self._max then
        h = math.min(h, self._max)
    end
    return h
end

function Panel:_apply(instant)
    local f = self.Frame
    instant = instant or not self.Window._ready
    local d = instant and 0 or 0.3

    if self._open then
        f.Visible = true
        tween(f, { Size = UDim2.new(1, 0, 0, self:_height()) }, d, QUINT)
    else
        if not f.Visible then
            return
        end
        tween(f, { Size = UDim2.new(1, 0, 0, 0) }, d, QUINT)
        if instant then
            f.Visible = false
        else
            task.delay(d + 0.02, function()
                if not self._open then
                    f.Visible = false
                end
            end)
        end
    end
end

function Panel:SetOpen(open, instant)
    self._open = open and true or false
    if self._flagKey then
        self.Window:_flagSet(self._flagKey, self._open)
    end
    self:_apply(instant)
end

function Panel:IsOpen()
    return self._open
end

function Panel:_row(h)
    local item = { h = h }
    item.row = make("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, h),
        LayoutOrder = #self._items + 1,
    }, self.Content)
    table.insert(self._items, item)
    self:_apply()
    return item.row, item
end

local function rowLabel(win, row, text, width)
    local l = make("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, width, 1, 0),
        Font = Enum.Font.BuilderSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = text,
    }, row)
    win:_themed(l, "TextColor3", "sub")
    return l
end

local function smallButton(win, row, text, width)
    local b = make("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(width, 24),
        BorderSizePixel = 0,
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 13,
        Text = text,
        AutoButtonColor = false,
    }, row)
    win:_themed(b, "BackgroundColor3", "track")
    win:_themed(b, "TextColor3", "text")
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    return b
end

function Panel:Label(o)
    if type(o) == "string" then
        o = { Text = o }
    end
    o = o or {}
    local win = self.Window
    local row = self:_row(20)
    local l = make("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.BuilderSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = o.Text or "",
    }, row)
    win:_themed(l, "TextColor3", o.Tone or "sub")
    return {
        Instance = l,
        Set = function(_, t)
            l.Text = tostring(t)
        end,
    }
end

function Panel:Separator()
    local row = self:_row(1)
    local l = make("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
    }, row)
    self.Window:_themed(l, "BackgroundColor3", "line")
end

function Panel:Button(o)
    o = o or {}
    local win = self.Window
    local row = self:_row(26)
    local b = make("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 14,
        Text = o.Name or "Button",
        AutoButtonColor = false,
    }, row)
    win:_themed(b, "BackgroundColor3", "track")
    win:_themed(b, "TextColor3", o.Tone or "text")
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    b.MouseEnter:Connect(function()
        tween(b, { BackgroundTransparency = 0.4 }, 0.12)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { BackgroundTransparency = 0 }, 0.12)
    end)
    b.MouseButton1Click:Connect(function()
        if o.Callback then
            task.spawn(o.Callback)
        end
    end)
    return {
        Instance = b,
        SetText = function(_, t)
            b.Text = t
        end,
    }
end

function Panel:Toggle(o)
    o = o or {}
    local win = self.Window
    local value = win:_flagGet(o.Flag, o.Default == true)
    local row = self:_row(26)
    local nameLbl = rowLabel(win, row, o.Name or "Toggle", 150)

    local track = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(34, 18),
        BorderSizePixel = 0,
    }, row)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local trackE = win:_themed(track, "BackgroundColor3", value and "accent" or "track")
    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, value and 18 or 2, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BorderSizePixel = 0,
    }, track)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
    win:_themed(knob, "BackgroundColor3", "text")

    local click = make("TextButton", {
        BackgroundTransparency = 1,
        Text = "",
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
    }, row)

    local obj = { Value = value }
    function obj:Set(v, silent)
        v = v and true or false
        self.Value = v
        win:_setKey(trackE, v and "accent" or "track")
        tween(knob, { Position = UDim2.new(0, v and 18 or 2, 0.5, 0) }, 0.15)
        win:_flagSet(o.Flag, v)
        if not silent and o.Callback then
            task.spawn(o.Callback, v)
        end
    end
    click.MouseButton1Click:Connect(function()
        obj:Set(not obj.Value)
    end)

    if o.Keybind ~= nil then
        local def = keyOf(o.Keybind, Enum.KeyCode.Unknown)
        local fk = o.Flag and (o.Flag .. "_key")
        local kc = keyOf(win:_flagGet(fk, def.Name), def)
        local function label()
            return kc == Enum.KeyCode.Unknown and "None" or kc.Name
        end
        nameLbl.Size = UDim2.new(0, 124, 1, 0)
        local chip = smallButton(win, row, label(), 64)
        chip.Position = UDim2.new(1, -42, 0.5, 0)
        chip.TextTruncate = Enum.TextTruncate.AtEnd
        local bind = {
            Value = kc,
            Press = function()
                obj:Set(not obj.Value)
            end,
        }
        table.insert(win._binds, bind)
        chip.MouseButton1Click:Connect(function()
            if win._rebinding then
                win._rebinding(Enum.KeyCode.Escape)
            end
            chip.Text = "…"
            win._rebinding = function(k)
                if k == Enum.KeyCode.Escape then
                    chip.Text = label()
                    return
                elseif k == Enum.KeyCode.Backspace then
                    k = Enum.KeyCode.Unknown
                end
                kc = k
                bind.Value = k
                win:_flagSet(fk, k.Name)
                chip.Text = label()
            end
        end)
    end

    if o.Flag and o.Callback then
        task.defer(o.Callback, value)
    end
    return obj
end

function Panel:Slider(o)
    o = o or {}
    local win = self.Window
    local min, max, step = o.Min or 0, o.Max or 100, o.Step or 0
    local fmt = o.Format or function(v)
        return tostring(v) .. (o.Suffix or "")
    end

    local function norm(v)
        v = math.clamp(v, min, max)
        if step > 0 then
            v = min + math.floor((v - min) / step + 0.5) * step
        end
        return math.floor(v * 10000 + 0.5) / 10000
    end

    local value = norm(tonumber(win:_flagGet(o.Flag, o.Default or min)) or min)
    local row = self:_row(26)
    rowLabel(win, row, o.Name or "Slider", 80)

    local out = make("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 40, 1, 0),
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "",
    }, row)
    win:_themed(out, "TextColor3", "text")

    local hit = make("TextButton", {
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.new(0, 84, 0, 0),
        Size = UDim2.new(1, -128, 1, 0),
    }, row)
    local track = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 4),
        BorderSizePixel = 0,
    }, hit)
    win:_themed(track, "BackgroundColor3", "track")
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, track)
    win:_themed(fill, "BackgroundColor3", "accent")
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BorderSizePixel = 0,
    }, hit)
    win:_themed(knob, "BackgroundColor3", "text")
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    local obj = { Value = value }
    local function draw()
        local a = (max > min) and (obj.Value - min) / (max - min) or 0
        fill.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        out.Text = fmt(obj.Value)
    end
    function obj:Set(v, silent)
        self.Value = norm(v)
        draw()
        win:_flagSet(o.Flag, self.Value)
        if not silent and o.Callback then
            task.spawn(o.Callback, self.Value)
        end
    end
    draw()

    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            win._slider = function(x)
                local a = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
                obj:Set(min + a * (max - min))
            end
            win._slider(input.Position.X)
        end
    end)

    if o.Flag and o.Callback then
        task.defer(o.Callback, value)
    end
    return obj
end

function Panel:Choice(o)
    o = o or {}
    local win = self.Window
    local options = o.Options or {}
    local value = win:_flagGet(o.Flag, o.Default or options[1])
    if not table.find(options, value) then
        value = options[1]
    end

    local row = self:_row(26)
    rowLabel(win, row, o.Name or "Choice", 100)
    local btn = smallButton(win, row, capitalize(value or "-"), 96)

    local obj = { Value = value }
    function obj:Set(v, silent)
        if not table.find(options, v) then
            return
        end
        self.Value = v
        btn.Text = capitalize(v)
        win:_flagSet(o.Flag, v)
        if not silent and o.Callback then
            task.spawn(o.Callback, v)
        end
    end
    btn.MouseButton1Click:Connect(function()
        if #options == 0 then
            return
        end
        local idx = table.find(options, obj.Value) or 0
        obj:Set(options[idx % #options + 1])
    end)

    if o.Flag and o.Callback then
        task.defer(o.Callback, value)
    end
    return obj
end

function Panel:Keybind(o)
    o = o or {}
    local win = self.Window
    local default = keyOf(o.Default, Enum.KeyCode.Unknown)
    local kc = keyOf(win:_flagGet(o.Flag, default.Name), default)

    local row = self:_row(26)
    rowLabel(win, row, o.Name or "Keybind", 100)
    local function label()
        return kc == Enum.KeyCode.Unknown and "None" or kc.Name
    end
    local btn = smallButton(win, row, label(), 96)

    local obj = { Value = kc, Press = o.Press }
    function obj:Set(k, silent)
        kc = k
        self.Value = k
        btn.Text = label()
        win:_flagSet(o.Flag, k.Name)
        if not silent and o.Callback then
            task.spawn(o.Callback, k)
        end
    end

    btn.MouseButton1Click:Connect(function()
        if win._rebinding then
            win._rebinding(Enum.KeyCode.Escape)
        end
        btn.Text = "Press a key…"
        win._rebinding = function(k)
            if k == Enum.KeyCode.Backspace then
                obj:Set(Enum.KeyCode.Unknown)
            elseif k ~= Enum.KeyCode.Escape and k ~= Enum.KeyCode.Unknown then
                obj:Set(k)
            else
                btn.Text = label()
            end
        end
    end)

    table.insert(win._binds, obj)
    if o.Flag and o.Callback then
        task.defer(o.Callback, kc)
    end
    return obj
end

function Panel:List(o)
    o = o or {}
    local win = self.Window
    local max, rowH = o.Max or 5, 22
    local row, item = self:_row(rowH)

    local nameLbls, valLbls = {}, {}
    for i = 1, max do
        local y = (i - 1) * rowH
        local n = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, y),
            Size = UDim2.new(1, -54, 0, rowH),
            Font = Enum.Font.BuilderSans,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "",
            Visible = false,
        }, row)
        win:_themed(n, "TextColor3", "text")
        local v = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -50, 0, y),
            Size = UDim2.fromOffset(50, rowH),
            Font = Enum.Font.BuilderSansBold,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right,
            Text = "",
            Visible = false,
        }, row)
        win:_themed(v, "TextColor3", "sub")
        nameLbls[i], valLbls[i] = n, v
    end

    local empty = make("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, rowH),
        Font = Enum.Font.BuilderSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = o.Empty or "Nothing yet",
    }, row)
    win:_themed(empty, "TextColor3", "sub")

    local entries = {}
    local obj = {}
    local function render()
        for i = 1, max do
            local e = entries[i]
            nameLbls[i].Visible = e ~= nil
            valLbls[i].Visible = e ~= nil
            if e then
                nameLbls[i].Text = e.name
                valLbls[i].Text = tostring(e.value)
            end
        end
        empty.Visible = #entries == 0
        item.h = math.max(#entries, 1) * rowH
        row.Size = UDim2.new(1, 0, 0, item.h)
        self:_apply()
    end

    function obj:Push(name, value)
        for i, e in ipairs(entries) do
            if e.name == name then
                table.remove(entries, i)
                break
            end
        end
        table.insert(entries, 1, { name = tostring(name), value = value })
        while #entries > max do
            table.remove(entries)
        end
        render()
    end

    function obj:Clear()
        entries = {}
        render()
    end

    render()
    return obj
end

----------------------------------------------------------------
-- More elements: Section, Paragraph, TextBox, Bar, Dropdown, ColorPicker
----------------------------------------------------------------
function Panel:Section(text)
    local win = self.Window
    local row = self:_row(18)
    local l = make("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.BuilderSansBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = tostring(text or ""),
    }, row)
    win:_themed(l, "TextColor3", "text")
    return {
        Instance = l,
        Set = function(_, t)
            l.Text = tostring(t)
        end,
    }
end

function Panel:Paragraph(o)
    if type(o) == "string" then
        o = { Text = o }
    end
    o = o or {}
    local win = self.Window
    local row, item = self:_row(18)
    local l = make("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.BuilderSans,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = "",
    }, row)
    win:_themed(l, "TextColor3", o.Tone or "sub")

    local function set(t)
        l.Text = tostring(t)
        local size = TextService:GetTextSize(l.Text, 13, Enum.Font.BuilderSans, Vector2.new(win.Width - 28, 1000))
        item.h = math.max(math.ceil(size.Y), 16)
        row.Size = UDim2.new(1, 0, 0, item.h)
        self:_apply()
    end
    set(o.Text or "")
    return {
        Instance = l,
        Set = function(_, t)
            set(t)
        end,
    }
end

function Panel:TextBox(o)
    o = o or {}
    local win = self.Window
    local value = tostring(win:_flagGet(o.Flag, o.Default or ""))
    local row = self:_row(26)
    rowLabel(win, row, o.Name or "Text", 80)

    local box = make("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(1, -84, 0, 24),
        BorderSizePixel = 0,
        Font = Enum.Font.BuilderSans,
        TextSize = 13,
        Text = value,
        PlaceholderText = o.Placeholder or "",
        ClearTextOnFocus = o.ClearOnFocus == true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    win:_themed(box, "BackgroundColor3", "track")
    win:_themed(box, "TextColor3", "text")
    win:_themed(box, "PlaceholderColor3", "sub")
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
    make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)

    if o.Numeric then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local clean = box.Text:gsub("[^%d%.%-]", "")
            if clean ~= box.Text then
                box.Text = clean
            end
        end)
    end

    local obj = { Value = value, Instance = box }
    function obj:Set(v, silent)
        v = tostring(v)
        self.Value = v
        box.Text = v
        win:_flagSet(o.Flag, v)
        if not silent and o.Callback then
            task.spawn(o.Callback, v)
        end
    end
    box.FocusLost:Connect(function(enter)
        if o.OnlyEnter and not enter then
            box.Text = obj.Value
            return
        end
        obj:Set(box.Text)
    end)

    if o.Flag and o.Callback then
        task.defer(o.Callback, value)
    end
    return obj
end

function Panel:Bar(o)
    o = o or {}
    local win = self.Window
    local min, max = o.Min or 0, o.Max or 100
    local fmt = o.Format or function(v)
        return tostring(v)
    end

    local row = self:_row(26)
    rowLabel(win, row, o.Name or "Bar", 80)
    local out = make("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 40, 1, 0),
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "",
    }, row)
    win:_themed(out, "TextColor3", "text")

    local track = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 84, 0.5, 0),
        Size = UDim2.new(1, -128, 0, 6),
        BorderSizePixel = 0,
    }, row)
    win:_themed(track, "BackgroundColor3", "track")
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, track)
    local fillE = win:_themed(fill, "BackgroundColor3", o.Tone or "accent")
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

    local obj = { Value = o.Default or min }
    function obj:Set(v)
        v = math.clamp(v, min, max)
        self.Value = v
        local a = max > min and (v - min) / (max - min) or 0
        tween(fill, { Size = UDim2.fromScale(a, 1) }, 0.2)
        out.Text = fmt(v)
    end
    function obj:SetTone(key)
        win:_setKey(fillE, key)
    end
    obj:Set(obj.Value)
    return obj
end

function Panel:Dropdown(o)
    o = o or {}
    local win = self.Window
    local options = o.Options or {}
    local multi = o.Multi == true
    local ITEM_H, HEAD_H = 24, 26

    local value
    if multi then
        value = {}
        local saved = win:_flagGet(o.Flag, type(o.Default) == "table" and o.Default or {})
        for _, v in ipairs(saved) do
            if table.find(options, v) and not table.find(value, v) then
                table.insert(value, v)
            end
        end
    else
        value = win:_flagGet(o.Flag, o.Default or options[1])
        if not table.find(options, value) then
            value = options[1]
        end
    end

    local row, item = self:_row(HEAD_H)
    row.ClipsDescendants = true
    local lbl = rowLabel(win, row, o.Name or "Dropdown", 80)
    lbl.Size = UDim2.fromOffset(80, HEAD_H)

    local head = smallButton(win, row, "", 140)
    head.AnchorPoint = Vector2.new(1, 0)
    head.Position = UDim2.new(1, 0, 0, 1)

    local listF = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, HEAD_H + 4),
        Size = UDim2.new(1, 0, 0, #options * ITEM_H),
        Visible = false,
    }, row)

    local obj = { Value = value }
    local entries = {}

    local function isSel(opt)
        if multi then
            return table.find(value, opt) ~= nil
        end
        return value == opt
    end
    local function summary()
        if multi then
            if #value == 0 then
                return "None"
            elseif #value <= 2 then
                return table.concat(value, ", ")
            end
            return #value .. " selected"
        end
        return tostring(value)
    end
    local function refresh(instant)
        head.Text = summary()
        for i, opt in ipairs(options) do
            win:_setKey(entries[i], isSel(opt) and "accent" or "text", instant)
        end
    end

    local open = false
    local function setOpen(state)
        open = state
        item.h = open and (HEAD_H + 4 + #options * ITEM_H - 2) or HEAD_H
        if open then
            listF.Visible = true
        end
        tween(row, { Size = UDim2.new(1, 0, 0, item.h) }, 0.25, QUINT)
        if not open then
            task.delay(0.27, function()
                if not open then
                    listF.Visible = false
                end
            end)
        end
        self:_apply()
    end
    head.MouseButton1Click:Connect(function()
        setOpen(not open)
    end)

    for i, opt in ipairs(options) do
        local b = make("TextButton", {
            Position = UDim2.fromOffset(0, (i - 1) * ITEM_H),
            Size = UDim2.new(1, 0, 0, ITEM_H - 2),
            BorderSizePixel = 0,
            Font = Enum.Font.BuilderSans,
            TextSize = 13,
            Text = tostring(opt),
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
        }, listF)
        win:_themed(b, "BackgroundColor3", "track")
        entries[i] = win:_themed(b, "TextColor3", isSel(opt) and "accent" or "text")
        make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, b)
        b.MouseButton1Click:Connect(function()
            if multi then
                local nv = table.clone(value)
                local idx = table.find(nv, opt)
                if idx then
                    table.remove(nv, idx)
                else
                    table.insert(nv, opt)
                end
                obj:Set(nv)
            else
                obj:Set(opt)
                setOpen(false)
            end
        end)
    end

    function obj:Set(v, silent)
        if multi then
            if type(v) ~= "table" then
                return
            end
            local nv = {}
            for _, x in ipairs(v) do
                if table.find(options, x) and not table.find(nv, x) then
                    table.insert(nv, x)
                end
            end
            value = nv
        else
            if not table.find(options, v) then
                return
            end
            value = v
        end
        self.Value = value
        refresh()
        win:_flagSet(o.Flag, multi and table.clone(value) or value)
        if not silent and o.Callback then
            task.spawn(o.Callback, value)
        end
    end

    refresh(true)
    if o.Flag and o.Callback then
        task.defer(o.Callback, value)
    end
    return obj
end

function Panel:ColorPicker(o)
    o = o or {}
    local win = self.Window
    local def = typeof(o.Default) == "Color3" and o.Default or Color3.fromRGB(120, 200, 150)
    local ok, saved = pcall(Color3.fromHex, tostring(win:_flagGet(o.Flag, def:ToHex())))
    local color = ok and saved or def
    local h, s, v = color:ToHSV()
    local HEAD_H, BAR_H = 26, 20

    local row, item = self:_row(HEAD_H)
    row.ClipsDescendants = true
    local lbl = rowLabel(win, row, o.Name or "Color", 150)
    lbl.Size = UDim2.fromOffset(150, HEAD_H)

    local swatch = make("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 3),
        Size = UDim2.fromOffset(44, 20),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = color,
    }, row)
    make("UICorner", { CornerRadius = UDim.new(0, 6) }, swatch)
    local sst = make("UIStroke", { Thickness = 1, Transparency = 0.8 }, swatch)
    win:_themed(sst, "Color", "line")

    local body = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, HEAD_H + 6),
        Size = UDim2.new(1, 0, 0, 3 * (BAR_H + 2)),
        Visible = false,
    }, row)

    local obj = { Value = color }
    local grads, knobs = {}, {}
    local commit -- forward

    local function miniSlider(i, setAlpha)
        local hit = make("TextButton", {
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            Position = UDim2.fromOffset(0, (i - 1) * (BAR_H + 2)),
            Size = UDim2.new(1, 0, 0, BAR_H),
        }, body)
        local track = make("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, 0, 0, 8),
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
        }, hit)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
        grads[i] = make("UIGradient", {}, track)
        local knob = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(12, 12),
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
        }, hit)
        make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
        make("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.35 }, knob)
        knobs[i] = knob

        hit.InputBegan:Connect(function(input)
            if isPress(input) then
                win._slider = function(x)
                    setAlpha(math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1))
                end
                win._slider(input.Position.X)
            end
        end)
    end

    local rainbow = {}
    for k = 0, 6 do
        table.insert(rainbow, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 1, 1)))
    end

    local function draw()
        local c = Color3.fromHSV(h, s, v)
        obj.Value = c
        swatch.BackgroundColor3 = c
        grads[1].Color = ColorSequence.new(rainbow)
        grads[2].Color = ColorSequence.new(Color3.fromHSV(h, 0, v), Color3.fromHSV(h, 1, v))
        grads[3].Color = ColorSequence.new(Color3.fromHSV(h, s, 0), Color3.fromHSV(h, s, 1))
        knobs[1].Position = UDim2.new(h, 0, 0.5, 0)
        knobs[2].Position = UDim2.new(s, 0, 0.5, 0)
        knobs[3].Position = UDim2.new(v, 0, 0.5, 0)
    end
    commit = function()
        draw()
        win:_flagSet(o.Flag, obj.Value:ToHex())
        if o.Callback then
            task.spawn(o.Callback, obj.Value)
        end
    end

    miniSlider(1, function(a)
        h = a
        commit()
    end)
    miniSlider(2, function(a)
        s = a
        commit()
    end)
    miniSlider(3, function(a)
        v = a
        commit()
    end)
    draw()

    function obj:Set(c, silent)
        h, s, v = c:ToHSV()
        draw()
        win:_flagSet(o.Flag, self.Value:ToHex())
        if not silent and o.Callback then
            task.spawn(o.Callback, self.Value)
        end
    end

    local open = false
    swatch.MouseButton1Click:Connect(function()
        open = not open
        item.h = open and (HEAD_H + 6 + 3 * (BAR_H + 2)) or HEAD_H
        if open then
            body.Visible = true
        end
        tween(row, { Size = UDim2.new(1, 0, 0, item.h) }, 0.25, QUINT)
        if not open then
            task.delay(0.27, function()
                if not open then
                    body.Visible = false
                end
            end)
        end
        self:_apply()
    end)

    if o.Flag and o.Callback then
        task.defer(o.Callback, obj.Value)
    end
    return obj
end

----------------------------------------------------------------
-- ButtonRow
----------------------------------------------------------------
function Panel:ButtonRow(list)
    local win = self.Window
    local row = self:_row(26)
    local n = #list
    local objs = {}
    local wOff = -6 * (n - 1) / n

    for i, o in ipairs(list) do
        local b = make("TextButton", {
            Position = UDim2.new((i - 1) / n, (i - 1) * (wOff + 6), 0, 0),
            Size = UDim2.new(1 / n, wOff, 1, 0),
            BorderSizePixel = 0,
            Font = Enum.Font.BuilderSansMedium,
            TextSize = 14,
            Text = o.Name or "Button",
            AutoButtonColor = false,
        }, row)
        win:_themed(b, "BackgroundColor3", "track")
        win:_themed(b, "TextColor3", o.Tone or "text")
        make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        b.MouseEnter:Connect(function()
            tween(b, { BackgroundTransparency = 0.4 }, 0.12)
        end)
        b.MouseLeave:Connect(function()
            tween(b, { BackgroundTransparency = 0 }, 0.12)
        end)
        b.MouseButton1Click:Connect(function()
            if o.Callback then
                task.spawn(o.Callback)
            end
        end)
        if o.Tooltip then
            win:_tooltip(b, o.Tooltip)
        end
        objs[i] = {
            Instance = b,
            SetText = function(_, t)
                b.Text = t
            end,
        }
    end
    return { Buttons = objs }
end

----------------------------------------------------------------
-- Common element methods: SetVisible / SetEnabled / Destroy / Tooltip
----------------------------------------------------------------
local ELEMENTS = {
    "Label", "Section", "Paragraph", "Separator", "Button", "ButtonRow", "Toggle",
    "Slider", "Choice", "Dropdown", "TextBox", "ColorPicker", "Keybind", "Bar", "List",
}
for _, name in ipairs(ELEMENTS) do
    local raw = Panel[name]
    Panel[name] = function(panel, o)
        local before = #panel._items
        local obj = raw(panel, o)
        if type(obj) ~= "table" then
            obj = {}
        end
        local item = panel._items[before + 1]
        if not item then
            return obj
        end
        local win = panel.Window
        obj.Row = item.row

        function obj:SetVisible(v)
            item.hidden = not v
            item.row.Visible = v and true or false
            panel:_apply()
        end

        function obj:SetEnabled(e)
            if not item.shield then
                item.shield = make("TextButton", {
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 0.4,
                    BorderSizePixel = 0,
                    Text = "",
                    AutoButtonColor = false,
                    ZIndex = 50,
                    Visible = false,
                }, item.row)
                win:_themed(item.shield, "BackgroundColor3", "bg")
            end
            item.shield.Visible = not e
        end

        function obj:Destroy()
            for idx, it in ipairs(panel._items) do
                if it == item then
                    table.remove(panel._items, idx)
                    break
                end
            end
            item.row:Destroy()
            panel:_apply()
        end

        if type(o) == "table" and o.Tooltip then
            win:_tooltip(item.row, o.Tooltip)
        end
        return obj
    end
end

----------------------------------------------------------------
-- Window: width, aux gui, tooltips, toasts, prompt, watermark
----------------------------------------------------------------
function Window:SetWidth(w, instant)
    w = math.floor(w + 0.5)
    if w == self.Width then
        return
    end
    self.Width = w
    tween(self.Root, { Size = UDim2.fromOffset(w, 0) }, instant and 0 or 0.25, QUINT)

    -- keep the window on screen after widening
    local vp = viewport()
    local x = math.clamp(self._rest.X.Offset, 0, math.max(vp.X - w * self._scale.Scale, 0))
    self._rest = UDim2.fromOffset(x, self._rest.Y.Offset)
    self.S.x = x
    if self._shown then
        tween(self.Root, { Position = self._rest }, instant and 0 or 0.25, QUINT)
    else
        self.Root.Position = self._rest
    end

    for _, fn in ipairs(self._onWidth) do
        pcall(fn)
    end
    self:_save()
end

function Window:_aux()
    if not self._auxGui then
        self._auxGui = make("ScreenGui", {
            Name = self.Name .. "_Aux",
            ResetOnSpawn = false,
            DisplayOrder = self.Gui.DisplayOrder + 1,
            IgnoreGuiInset = true,
        }, self.Gui.Parent)
    end
    return self._auxGui
end

function Window:_tooltip(target, text)
    target.MouseEnter:Connect(function()
        self._tipToken = (self._tipToken or 0) + 1
        local mine = self._tipToken
        task.delay(0.4, function()
            if mine == self._tipToken and self.Alive then
                self:_showTip(text)
            end
        end)
    end)
    target.MouseLeave:Connect(function()
        self._tipToken = (self._tipToken or 0) + 1
        self:_hideTip()
    end)
end

function Window:_showTip(text)
    if not self._tip then
        local f = make("Frame", {
            Name = "Tooltip",
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 0.04,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 300,
        }, self:_aux())
        self:_themed(f, "BackgroundColor3", "bg")
        make("UICorner", { CornerRadius = UDim.new(0, 7) }, f)
        local st = make("UIStroke", { Thickness = 1, Transparency = 0.85 }, f)
        self:_themed(st, "Color", "line")
        make("UIPadding", {
            PaddingTop = UDim.new(0, 6),
            PaddingBottom = UDim.new(0, 6),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        }, f)
        local l = make("TextLabel", {
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.fromOffset(0, 0),
            Font = Enum.Font.BuilderSans,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "",
        }, f)
        make("UISizeConstraint", { MaxSize = Vector2.new(240, math.huge) }, l)
        self:_themed(l, "TextColor3", "text")
        self._tip, self._tipLabel = f, l
    end
    self._tipLabel.Text = tostring(text)
    self._tip.Visible = true
    self:_moveTip()
end

function Window:_moveTip()
    if not self._tip or not self._tip.Visible then
        return
    end
    local m = UserInputService:GetMouseLocation()
    local vp, sz = viewport(), self._tip.AbsoluteSize
    self._tip.Position = UDim2.fromOffset(
        math.min(m.X + 14, vp.X - sz.X - 6),
        math.min(m.Y + 18, vp.Y - sz.Y - 6)
    )
end

function Window:_hideTip()
    if self._tip then
        self._tip.Visible = false
    end
end

function Window:Notify(o)
    if type(o) == "string" then
        o = { Text = o }
    end
    o = o or {}
    if not self.Alive then
        return
    end

    if not self._toastHolder then
        self._toastHolder = make("Frame", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -18, 1, -18),
            Size = UDim2.fromOffset(260, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        }, self:_aux())
        make("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }, self._toastHolder)
    end

    self._toastN = (self._toastN or 0) + 1
    local t = make("CanvasGroup", {
        LayoutOrder = self._toastN,
        Size = UDim2.fromOffset(260, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
    }, self._toastHolder)
    self:_themed(t, "BackgroundColor3", "bg")
    make("UICorner", { CornerRadius = UDim.new(0, 10) }, t)
    local st = make("UIStroke", { Thickness = 1, Transparency = 0.9 }, t)
    self:_themed(st, "Color", "line")

    local accent = make("Frame", {
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(0, 3, 1, -16),
        BorderSizePixel = 0,
    }, t)
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, accent)
    self:_themed(accent, "BackgroundColor3", o.Tone or "accent")

    local body = make("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, t)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 20),
        PaddingRight = UDim.new(0, 12),
    }, body)
    make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, body)

    if o.Title then
        local tl = make("TextLabel", {
            LayoutOrder = 1,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Font = Enum.Font.BuilderSansBold,
            TextSize = 14,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = tostring(o.Title),
        }, body)
        self:_themed(tl, "TextColor3", "text")
    end
    if o.Text then
        local xl = make("TextLabel", {
            LayoutOrder = 2,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Font = Enum.Font.BuilderSans,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = tostring(o.Text),
        }, body)
        self:_themed(xl, "TextColor3", "sub")
    end

    local gone = false
    local function dismiss()
        if gone then
            return
        end
        gone = true
        tween(t, { GroupTransparency = 1 }, 0.25)
        task.delay(0.3, function()
            if t.Parent then
                t:Destroy()
            end
        end)
    end
    t.InputBegan:Connect(function(input)
        if isPress(input) then
            dismiss()
        end
    end)

    tween(t, { GroupTransparency = 0 }, 0.25)
    task.delay(o.Duration or 4, dismiss)
end

function Window:Prompt(o)
    if type(o) == "string" then
        o = { Text = o }
    end
    o = o or {}
    if not self.Alive then
        return
    end

    local dim = make("TextButton", {
        Name = "Prompt",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 200,
    }, self:_aux())

    local dlg = make("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(o.Width or 300, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
    }, dim)
    self:_themed(dlg, "BackgroundColor3", "bg")
    make("UICorner", { CornerRadius = UDim.new(0, 12) }, dlg)
    local st = make("UIStroke", { Thickness = 1, Transparency = 0.88 }, dlg)
    self:_themed(st, "Color", "line")
    make("UIPadding", {
        PaddingTop = UDim.new(0, 16),
        PaddingBottom = UDim.new(0, 16),
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, dlg)
    make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, dlg)

    local function label(text, order, font, size, key)
        local l = make("TextLabel", {
            LayoutOrder = order,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Font = font,
            TextSize = size,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = tostring(text),
        }, dlg)
        self:_themed(l, "TextColor3", key)
    end
    if o.Title then
        label(o.Title, 1, Enum.Font.BuilderSansBold, 17, "text")
    end
    if o.Text then
        label(o.Text, 2, Enum.Font.BuilderSans, 14, "sub")
    end

    local btnRow = make("Frame", {
        LayoutOrder = 4,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 34),
    }, dlg)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, btnRow)

    local done = false
    local function finish(result)
        if done then
            return
        end
        done = true
        tween(dim, { BackgroundTransparency = 1 }, 0.2)
        tween(dlg, { GroupTransparency = 1 }, 0.2)
        task.delay(0.22, function()
            dim:Destroy()
        end)
        if o.Callback then
            task.spawn(o.Callback, result)
        end
    end

    local function button(text, order, primary, result)
        local b = make("TextButton", {
            LayoutOrder = order,
            Size = UDim2.fromOffset(92, 30),
            BorderSizePixel = 0,
            Font = Enum.Font.BuilderSansMedium,
            TextSize = 14,
            Text = text,
            AutoButtonColor = false,
        }, btnRow)
        make("UICorner", { CornerRadius = UDim.new(0, 7) }, b)
        self:_themed(b, "BackgroundColor3", primary and (o.Tone or "accent") or "track")
        self:_themed(b, "TextColor3", primary and "bg" or "text")
        b.MouseEnter:Connect(function()
            tween(b, { BackgroundTransparency = 0.25 }, 0.12)
        end)
        b.MouseLeave:Connect(function()
            tween(b, { BackgroundTransparency = 0 }, 0.12)
        end)
        b.MouseButton1Click:Connect(function()
            finish(result)
        end)
    end
    if o.No ~= false then
        button(o.No or "Cancel", 1, false, false)
    end
    button(o.Yes or "OK", 2, true, true)

    tween(dim, { BackgroundTransparency = 0.5 }, 0.2)
    tween(dlg, { GroupTransparency = 0 }, 0.2)
end

function Window:Watermark(o)
    o = o or {}
    local f = make("Frame", {
        Name = "Watermark",
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        AnchorPoint = o.AnchorPoint or Vector2.new(1, 0),
        Position = o.Position or UDim2.new(1, -18, 0, 44),
        BackgroundTransparency = 1 - self.S.opacity,
        BorderSizePixel = 0,
    }, self:_aux())
    self:_themed(f, "BackgroundColor3", "bg")
    table.insert(self._boxes, f)
    make("UICorner", { CornerRadius = UDim.new(0, 8) }, f)
    local st = make("UIStroke", { Thickness = 1, Transparency = 0.9 }, f)
    self:_themed(st, "Color", "line")
    make("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
    }, f)
    local label = make("TextLabel", {
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 13,
        Text = tostring(o.Text or self.Name),
    }, f)
    self:_themed(label, "TextColor3", "text")

    local acc, frames = 0, 0
    local conn = RunService.Heartbeat:Connect(function(dt)
        frames += 1
        acc += dt
        if acc < 0.5 then
            return
        end
        local parts = { tostring(o.Text or self.Name) }
        if o.FPS ~= false then
            table.insert(parts, math.floor(frames / acc + 0.5) .. " fps")
        end
        if o.Ping ~= false then
            local ok, ping = pcall(function()
                return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            end)
            if ok and ping then
                table.insert(parts, math.floor(ping + 0.5) .. " ms")
            end
        end
        label.Text = table.concat(parts, "   ·   ")
        acc, frames = 0, 0
    end)
    table.insert(self._conns, conn)

    local obj = { Frame = f, Label = label }
    function obj:SetText(t)
        o.Text = t
    end
    function obj:SetVisible(v)
        f.Visible = v and true or false
    end
    function obj:Destroy()
        conn:Disconnect()
        f:Destroy()
    end
    return obj
end

function Window:_mobileButton()
    local b = make("TextButton", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 10, 0.5, 0),
        Size = UDim2.fromOffset(40, 40),
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Font = Enum.Font.BuilderSansBold,
        TextSize = 14,
        Text = "UI",
        AutoButtonColor = false,
    }, self:_aux())
    self:_themed(b, "BackgroundColor3", "bg")
    self:_themed(b, "TextColor3", "text")
    make("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
    local st = make("UIStroke", { Thickness = 1, Transparency = 0.85 }, b)
    self:_themed(st, "Color", "line")
    b.MouseButton1Click:Connect(function()
        self:Toggle()
    end)
end

----------------------------------------------------------------
-- Accent override + config import/export/reset
----------------------------------------------------------------
function Window:SetAccent(color)
    if typeof(color) == "Color3" then
        self.S.accent = color:ToHex()
        self._accent = color
    else
        self.S.accent = ""
        self._accent = nil
    end
    self:_applyTheme(true)
    self:_save()
end

function Window:ExportConfig()
    return HttpService:JSONEncode(self.S)
end

function Window:ImportConfig(json)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, tostring(json))
    if not ok or type(data) ~= "table" then
        return false
    end
    if type(data.flags) == "table" then
        for k, v in pairs(data.flags) do
            self.S.flags[k] = v
        end
    end
    if type(data.theme) == "string" and Lite.Themes[data.theme] then
        self:SetTheme(data.theme)
    end
    if type(data.opacity) == "number" then
        self:SetOpacity(data.opacity)
    end
    if type(data.scale) == "number" then
        self:SetScale(data.scale)
    end
    if type(data.accent) == "string" then
        local okc, c = pcall(Color3.fromHex, data.accent)
        self:SetAccent(okc and c or nil)
    end
    self:_save()
    return true
end

function Window:ResetConfig()
    for k in pairs(self.S.flags) do
        self.S.flags[k] = nil
    end
    self:SetOpacity(0.96)
    self:SetScale(1)
    self:SetTheme("dark")
    self:SetAccent(nil)
    self:_save()
end

----------------------------------------------------------------
-- Tabs: a segmented bar; each tab is a normal Panel.
-- The window widens so every tab name fits; past MaxWidth the bar scrolls.
----------------------------------------------------------------
function Window:Tabs(names, opts)
    opts = opts or {}
    local win = self
    self._tabCount = (self._tabCount or 0) + 1
    local flagKey = "_tab:" .. self._tabCount
    local n = #names
    local PAD, GAPX, EDGE = 24, 4, 4
    local maxW = opts.MaxWidth or 460

    -- measure each tab label and grow the window if needed
    local widths, total = {}, 0
    for i, name in ipairs(names) do
        local tw = TextService:GetTextSize(name, 14, Enum.Font.BuilderSansMedium, Vector2.new(1000, 100)).X
        widths[i] = math.ceil(tw) + PAD
        total += widths[i]
    end
    local needed = total + GAPX * (n - 1) + EDGE * 2
    self:SetWidth(math.min(math.max(self.Width, needed), maxW), not self._ready)

    local box = self:_box("Tabs", 34)
    local scroller = make("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ElasticBehavior = Enum.ElasticBehavior.Never,
    }, box)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, GAPX),
    }, scroller)
    make("UIPadding", { PaddingLeft = UDim.new(0, EDGE), PaddingRight = UDim.new(0, EDGE) }, scroller)

    scroller.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            local maxX = math.max(scroller.AbsoluteCanvasSize.X - scroller.AbsoluteSize.X, 0)
            scroller.CanvasPosition = Vector2.new(
                math.clamp(scroller.CanvasPosition.X - input.Position.Z * 48, 0, maxX),
                0
            )
        end
    end)

    local bar = { Panels = {}, Current = nil }
    local parts = {}

    for i, name in ipairs(names) do
        local b = make("TextButton", {
            LayoutOrder = i,
            Size = UDim2.fromOffset(widths[i], 26),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.BuilderSansMedium,
            TextSize = 14,
            Text = name,
            AutoButtonColor = false,
        }, scroller)
        make("UICorner", { CornerRadius = UDim.new(0, 7) }, b)
        win:_themed(b, "BackgroundColor3", "track")
        parts[name] = { btn = b, tx = win:_themed(b, "TextColor3", "sub") }
        bar.Panels[name] = self:Panel({ Name = name, MaxHeight = opts.MaxHeight })

        b.MouseButton1Click:Connect(function()
            bar:Select(name)
        end)
        b.MouseEnter:Connect(function()
            if bar.Current ~= name then
                tween(b, { TextColor3 = win:_color("text") }, 0.12)
            end
        end)
        b.MouseLeave:Connect(function()
            if bar.Current ~= name then
                tween(b, { TextColor3 = win:_color("sub") }, 0.12)
            end
        end)
    end

    -- spread leftover width evenly so the bar always fills the window
    local function layout()
        local inner = win.Width - EDGE * 2
        local extra = inner - GAPX * (n - 1) - total
        local share = extra > 0 and extra / n or 0
        for i, name in ipairs(names) do
            parts[name].btn.Size = UDim2.fromOffset(math.floor(widths[i] + share), 26)
        end
    end
    layout()
    table.insert(self._onWidth, layout)

    local function reveal(btn)
        local sc = win._scale.Scale
        local vw = scroller.AbsoluteSize.X / sc
        local cw = scroller.AbsoluteCanvasSize.X / sc
        if cw <= vw + 1 then
            return
        end
        local bx = (btn.AbsolutePosition.X - scroller.AbsolutePosition.X) / sc + scroller.CanvasPosition.X
        local target = math.clamp(bx - (vw - btn.AbsoluteSize.X / sc) / 2, 0, cw - vw)
        tween(scroller, { CanvasPosition = Vector2.new(target, 0) }, 0.2)
    end

    function bar:Select(name, instant)
        if not self.Panels[name] then
            return
        end
        self.Current = name
        for _, nm in ipairs(names) do
            local sel = nm == name
            win:_setKey(parts[nm].tx, sel and "text" or "sub", instant)
            tween(parts[nm].btn, { BackgroundTransparency = sel and 0 or 1 }, instant and 0 or 0.15)
            if sel then
                self.Panels[nm]:SetOpen(true, instant)
            else
                self.Panels[nm]:SetOpen(false, true)
            end
        end
        if not instant then
            reveal(parts[name].btn)
        end
        win:_flagSet(flagKey, name)
    end

    local start = win:_flagGet(flagKey, opts.Default or names[1])
    if not bar.Panels[start] then
        start = names[1]
    end
    bar:Select(start, true)
    return bar.Panels, bar
end

----------------------------------------------------------------
-- Ready-made settings panel (opacity, size, theme, hotkey, accent, config)
----------------------------------------------------------------
function Window:Settings(opts)
    opts = opts or {}
    local panel = opts.Panel or self:Panel({ Name = "Settings", Open = opts.Open })

    panel:Slider({
        Name = "Opacity",
        Min = 0.5,
        Max = 1,
        Step = 0.05,
        Default = self.S.opacity,
        Format = function(v)
            return math.floor(v * 100 + 0.5) .. "%"
        end,
        Callback = function(v)
            self:SetOpacity(v)
        end,
    })
    panel:Slider({
        Name = "Size",
        Min = 0.8,
        Max = 1.3,
        Step = 0.05,
        Default = self.S.scale,
        Format = function(v)
            return string.format("%.2fx", v)
        end,
        Callback = function(v)
            self:SetScale(v)
        end,
    })

    local names = {}
    for k in pairs(Lite.Themes) do
        table.insert(names, k)
    end
    table.sort(names)
    panel:Choice({
        Name = "Theme",
        Options = names,
        Default = self.S.theme,
        Callback = function(v)
            self:SetTheme(v)
        end,
    })
    panel:Keybind({
        Name = "Hotkey",
        Default = self._key,
        Callback = function(k)
            self:SetKey(k)
        end,
    })

    local accent = panel:ColorPicker({
        Name = "Accent",
        Default = self:_color("accent"),
        Callback = function(c)
            self:SetAccent(c)
        end,
    })
    panel:Button({
        Name = "Reset accent",
        Callback = function()
            self:SetAccent(nil)
            accent:Set(self:_color("accent"), true)
        end,
    })

    panel:Separator()
    panel:ButtonRow({
        {
            Name = "Copy config",
            Callback = function()
                if type(setclipboard) == "function" then
                    setclipboard(self:ExportConfig())
                    self:Notify({ Title = "Config copied", Text = "Paste it into the Import box to restore it." })
                else
                    self:Notify({ Title = "Clipboard unavailable", Text = "This executor has no setclipboard.", Tone = "warn" })
                end
            end,
        },
        {
            Name = "Reset all",
            Tone = "danger",
            Callback = function()
                self:Prompt({
                    Title = "Reset all settings?",
                    Text = "Saved values return to their defaults. Re-run the script to refresh every control.",
                    Yes = "Reset",
                    Tone = "danger",
                    Callback = function(ok)
                        if ok then
                            self:ResetConfig()
                            self:Notify({ Title = "Settings reset", Tone = "warn" })
                        end
                    end,
                })
            end,
        },
    })
    local imp
    imp = panel:TextBox({
        Name = "Import",
        Placeholder = "paste config + Enter",
        OnlyEnter = true,
        Callback = function(text)
            if text == "" then
                return
            end
            local ok = self:ImportConfig(text)
            self:Notify({
                Title = ok and "Config imported" or "Import failed",
                Text = ok and "Re-run the script to refresh every control." or "That doesn't look like a valid config.",
                Tone = ok and "accent" or "danger",
            })
            imp:Set("", true)
        end,
    })
    return panel
end


----------------------------------------------------------------

getgenv().Lite = Lite
_G.Lite = Lite

----------------------------------------------------------------
-- R1 ESP + Aim Assist  (world-stable ESP + sticky aim)
----------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Lite = getgenv().Lite or _G.Lite
assert(Lite and Lite.new, "LiteUI failed to load")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CFG = {
    EspPlayers = true,
    EspBots = true,
    EspNames = true,
    EspDistance = true,
    EspTracers = true,
    EspBoxes = true,
    EspHealth = true,
    MaxDistance = 2000,
    PlayerColor = Color3.fromRGB(80, 200, 255),
    BotColor = Color3.fromRGB(255, 90, 90),
    TracerFrom = "Bottom", -- Bottom | Center | Mouse

    AimEnabled = false,
    AimFov = 140,
    AimSmooth = 0.38, -- higher = slower / less flicky (0.05..0.7)
    AimPart = "Head",
    AimTeamCheck = true,
    AimSticky = true,
    AimStickyBoost = 2.4, -- FOV multiplier while locked
    AimLoseTime = 0.55, -- seconds off-target before drop
    AimSwitchRatio = 0.62, -- only switch if new target is this much closer
    ShowFov = true,
    FovColor = Color3.fromRGB(0, 255, 200),
}

local H = {
    drawings = {},
    lock = nil,       -- BasePart currently locked
    lockUntil = 0,
    conns = {},
    binds = {},
}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function cam()
    return Workspace.CurrentCamera
end

local function w2s(world)
    local c = cam()
    if not c then
        return Vector2.zero, false, 0
    end
    local v, on = c:WorldToViewportPoint(world)
    return Vector2.new(v.X, v.Y), on and v.Z > 0, v.Z
end

local function myRoot()
    local ch = LP.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getTeam(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then
        return plr:GetAttribute("TPS_Team") or plr:GetAttribute("Team") or (plr.Team and plr.Team.Name)
    end
    return model:GetAttribute("TPS_Team") or model:GetAttribute("Team")
end

local function myTeam()
    return LP:GetAttribute("TPS_Team") or LP:GetAttribute("Team") or (LP.Team and LP.Team.Name)
end

local function alive(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    if model:GetAttribute("TPS_Down") == true then
        return false
    end
    return true
end

local function aimPart(model)
    return model:FindFirstChild(CFG.AimPart)
        or model:FindFirstChild("Head")
        or model:FindFirstChild("HumanoidRootPart")
end

local function collect()
    local out = {}
    if CFG.EspPlayers or CFG.AimEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character and alive(p.Character) then
                out[#out + 1] = {
                    model = p.Character,
                    name = (p.DisplayName ~= "" and p.DisplayName) or p.Name,
                    isBot = false,
                    team = getTeam(p.Character),
                }
            end
        end
    end
    if CFG.EspBots or CFG.AimEnabled then
        local folder = Workspace:FindFirstChild("TPS_Bots")
        if folder then
            for _, bot in ipairs(folder:GetChildren()) do
                if bot:IsA("Model") and alive(bot) then
                    out[#out + 1] = {
                        model = bot,
                        name = bot.Name,
                        isBot = true,
                        team = getTeam(bot),
                    }
                end
            end
        end
    end
    return out
end

----------------------------------------------------------------
-- DRAWING POOL
----------------------------------------------------------------
local function killDraw(model)
    local d = H.drawings[model]
    if not d then
        return
    end
    for _, v in pairs(d) do
        if typeof(v) == "table" then
            for _, line in pairs(v) do
                pcall(function()
                    line:Remove()
                end)
            end
        else
            pcall(function()
                v:Remove()
            end)
        end
    end
    H.drawings[model] = nil
end

local function getDraw(model, isBot)
    local d = H.drawings[model]
    if d then
        return d
    end
    local color = isBot and CFG.BotColor or CFG.PlayerColor
    local box = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1.5
        l.Color = color
        l.Visible = false
        box[i] = l
    end
    local tracer = Drawing.new("Line")
    tracer.Thickness = 1.2
    tracer.Color = color
    tracer.Visible = false
    local name = Drawing.new("Text")
    name.Size = 13
    name.Center = true
    name.Outline = true
    name.Color = color
    name.Visible = false
    local hp = Drawing.new("Line")
    hp.Thickness = 2
    hp.Visible = false
    d = { box = box, tracer = tracer, name = name, hp = hp, isBot = isBot }
    H.drawings[model] = d
    return d
end

-- Pure world AABB projected through the *current* camera.
-- Never uses camera-relative offsets, so ADS / look changes cannot drag the boxes.
local function box2d(hrp)
    local pos = hrp.Position
    local half = Vector3.new(1.15, 2.65, 1.15)
    local corners = {
        pos + Vector3.new( half.X,  half.Y,  half.Z),
        pos + Vector3.new( half.X,  half.Y, -half.Z),
        pos + Vector3.new(-half.X,  half.Y, -half.Z),
        pos + Vector3.new(-half.X,  half.Y,  half.Z),
        pos + Vector3.new( half.X, -half.Y,  half.Z),
        pos + Vector3.new( half.X, -half.Y, -half.Z),
        pos + Vector3.new(-half.X, -half.Y, -half.Z),
        pos + Vector3.new(-half.X, -half.Y,  half.Z),
    }
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false
    for i = 1, 8 do
        local s, on = w2s(corners[i])
        if on then
            any = true
            if s.X < minX then minX = s.X end
            if s.Y < minY then minY = s.Y end
            if s.X > maxX then maxX = s.X end
            if s.Y > maxY then maxY = s.Y end
        end
    end
    if not any then
        return nil
    end
    return minX, minY, maxX, maxY
end

local function tracerOrigin()
    local c = cam()
    local vs = c and c.ViewportSize or Vector2.new(1920, 1080)
    if CFG.TracerFrom == "Center" then
        return Vector2.new(vs.X / 2, vs.Y / 2)
    elseif CFG.TracerFrom == "Mouse" then
        local inset = GuiService:GetGuiInset()
        return Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    end
    return Vector2.new(vs.X / 2, vs.Y)
end

----------------------------------------------------------------
-- AIM (strong sticky + hysteresis, no position fight)
----------------------------------------------------------------
local function aimHeld()
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

local function mouseCenter()
    local inset = GuiService:GetGuiInset()
    return Vector2.new(Mouse.X, Mouse.Y + inset.Y)
end

local function validLock(part)
    if not part or not part.Parent then
        return false
    end
    local model = part:FindFirstAncestorOfClass("Model")
    if not model or not alive(model) then
        return false
    end
    return true
end

local function screenDistTo(part)
    local s, on = w2s(part.Position)
    if not on then
        return math.huge, s, false
    end
    return (s - mouseCenter()).Magnitude, s, true
end

local function pickTarget()
    local team = myTeam()
    local center = mouseCenter()
    local fov = CFG.AimFov
    local best, bestD = nil, fov

    -- Strong sticky: keep current lock unless it is dead or far outside sticky FOV for a while
    if CFG.AimSticky and H.lock and validLock(H.lock) then
        local d, _, on = screenDistTo(H.lock)
        if on and d < fov * CFG.AimStickyBoost then
            H.lockUntil = os.clock() + CFG.AimLoseTime
            -- still scan for a *much* closer target (hysteresis)
            local switchThresh = d * CFG.AimSwitchRatio
            for _, t in ipairs(collect()) do
                if CFG.AimTeamCheck and not t.isBot and team and t.team and t.team == team then
                    continue
                end
                local part = aimPart(t.model)
                if not part or part == H.lock then
                    continue
                end
                local s, on2 = w2s(part.Position)
                if not on2 then
                    continue
                end
                local nd = (s - center).Magnitude
                if nd < switchThresh and nd < bestD then
                    bestD = nd
                    best = part
                end
            end
            if best then
                H.lock = best
                H.lockUntil = os.clock() + CFG.AimLoseTime
                return best
            end
            return H.lock
        end
        -- grace period after leaving sticky FOV
        if os.clock() < H.lockUntil then
            return H.lock
        end
        H.lock = nil
    end

    -- fresh pick
    for _, t in ipairs(collect()) do
        if CFG.AimTeamCheck and not t.isBot and team and t.team and t.team == team then
            continue
        end
        local part = aimPart(t.model)
        if not part then
            continue
        end
        local s, on = w2s(part.Position)
        if not on then
            continue
        end
        local d = (s - center).Magnitude
        if d < bestD then
            bestD = d
            best = part
        end
    end

    if best then
        H.lock = best
        H.lockUntil = os.clock() + CFG.AimLoseTime
    end
    return best
end

local function stepAim(dt)
    if not CFG.AimEnabled or not aimHeld() then
        -- only clear lock when button is released so sticky survives brief FOV exits
        if not aimHeld() then
            H.lock = nil
        end
        return
    end
    local c = cam()
    if not c then
        return
    end
    local part = pickTarget()
    if not part then
        return
    end

    -- Use the *current* camera position every frame so we never freeze the game's ADS offset.
    -- Only blend the look vector. This stops the "ESP slides with look" desync.
    local origin = c.CFrame.Position
    local want = part.Position - origin
    if want.Magnitude < 0.08 then
        return
    end
    want = want.Unit
    local cur = c.CFrame.LookVector

    -- Frame-rate independent exponential smooth. Higher AimSmooth = slower.
    local smooth = math.clamp(CFG.AimSmooth, 0.05, 0.85)
    local t = 1 - math.pow(smooth, math.clamp(dt * 60, 0.02, 5))
    t = math.clamp(t, 0.015, 0.42) -- hard cap so it never snaps

    local blended = cur:Lerp(want, t)
    if blended.Magnitude < 1e-4 then
        return
    end
    -- Preserve camera position exactly; only change orientation
    c.CFrame = CFrame.lookAt(origin, origin + blended.Unit)
end

----------------------------------------------------------------
-- ESP (always world positions, fresh camera)
----------------------------------------------------------------
local function updateESP()
    local c = cam()
    if not c then
        return
    end
    local root = myRoot()
    local seen = {}
    local targets = collect()

    for _, t in ipairs(targets) do
        local show = (t.isBot and CFG.EspBots) or (not t.isBot and CFG.EspPlayers)
        if not show then
            continue
        end
        local model = t.model
        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then
            continue
        end
        local dist = root and (root.Position - hrp.Position).Magnitude or 0
        if dist > CFG.MaxDistance then
            killDraw(model)
            continue
        end
        seen[model] = true
        local d = getDraw(model, t.isBot)
        local color = t.isBot and CFG.BotColor or CFG.PlayerColor
        local head = model:FindFirstChild("Head") or hrp
        local top, onTop = w2s(head.Position + Vector3.new(0, 1.05, 0))
        local mid, onMid = w2s(hrp.Position)

        if CFG.EspBoxes then
            local minX, minY, maxX, maxY = box2d(hrp)
            if minX then
                local pts = {
                    Vector2.new(minX, minY),
                    Vector2.new(maxX, minY),
                    Vector2.new(maxX, maxY),
                    Vector2.new(minX, maxY),
                }
                for i = 1, 4 do
                    d.box[i].From = pts[i]
                    d.box[i].To = pts[i % 4 + 1]
                    d.box[i].Color = color
                    d.box[i].Visible = true
                end
                if CFG.EspHealth then
                    local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                    local x = minX - 4
                    d.hp.From = Vector2.new(x, maxY)
                    d.hp.To = Vector2.new(x, maxY - (maxY - minY) * ratio)
                    d.hp.Color = Color3.fromRGB(255 * (1 - ratio), 255 * ratio, 50)
                    d.hp.Visible = true
                else
                    d.hp.Visible = false
                end
            else
                for i = 1, 4 do
                    d.box[i].Visible = false
                end
                d.hp.Visible = false
            end
        else
            for i = 1, 4 do
                d.box[i].Visible = false
            end
            d.hp.Visible = false
        end

        if CFG.EspTracers and onMid then
            d.tracer.From = tracerOrigin()
            d.tracer.To = mid
            d.tracer.Color = color
            d.tracer.Visible = true
        else
            d.tracer.Visible = false
        end

        if (CFG.EspNames or CFG.EspDistance) and onTop then
            local label = ""
            if CFG.EspNames then
                label = (t.isBot and "[BOT] " or "") .. t.name
            end
            if CFG.EspDistance then
                label = label .. string.format(" [%dm]", math.floor(dist))
            end
            d.name.Text = label
            d.name.Position = Vector2.new(top.X, top.Y - 14)
            d.name.Color = color
            d.name.Visible = true
        else
            d.name.Visible = false
        end
    end

    for model in pairs(H.drawings) do
        if not seen[model] then
            killDraw(model)
        end
    end
end

----------------------------------------------------------------
-- FOV circle + render loop (correct priority order)
----------------------------------------------------------------
local fov = Drawing.new("Circle")
fov.Thickness = 1.4
fov.NumSides = 64
fov.Filled = false
fov.Transparency = 0.7
fov.Visible = false

-- Aim runs just after the camera so it can gently override look for this frame.
-- ESP runs after aim so boxes are projected with the final CFrame of the frame.
local AIM_PRIO = Enum.RenderPriority.Camera.Value + 1
local ESP_PRIO = Enum.RenderPriority.Camera.Value + 2

RunService:BindToRenderStep("R1Aim", AIM_PRIO, function(dt)
    pcall(stepAim, dt)
end)
table.insert(H.binds, "R1Aim")

RunService:BindToRenderStep("R1ESP", ESP_PRIO, function()
    local c = cam()
    if not c then
        return
    end
    if CFG.ShowFov and CFG.AimEnabled then
        local inset = GuiService:GetGuiInset()
        fov.Position = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
        fov.Radius = CFG.AimFov
        fov.Color = CFG.FovColor
        fov.Visible = true
    else
        fov.Visible = false
    end
    pcall(updateESP)
end)
table.insert(H.binds, "R1ESP")

Players.PlayerRemoving:Connect(function(p)
    if p.Character then
        killDraw(p.Character)
    end
end)

local function cleanup()
    for _, name in ipairs(H.binds) do
        pcall(function()
            RunService:UnbindFromRenderStep(name)
        end)
    end
    H.binds = {}
    for _, c in ipairs(H.conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    H.conns = {}
    for m in pairs(H.drawings) do
        killDraw(m)
    end
    pcall(function()
        fov:Remove()
    end)
    H.lock = nil
end

----------------------------------------------------------------
-- LiteUI (GrokWare / your v0.0.5)
----------------------------------------------------------------
local ui = Lite.new({
    Name = "R1ESPAim",
    Width = 300,
    Key = Enum.KeyCode.RightShift,
    Theme = "dark",
    Save = true,
    SaveFile = "r1_esp_aim_liteui.json",
})

local card = ui:Card({
    Title = "R1 ESP / Aim",
    Subtitle = "World ESP · Sticky aim",
    Value = "OK",
    Tone = "accent",
})

local tab = ui:Tabs({ "ESP", "Aim", "Settings" }, { MaxHeight = 280, MaxWidth = 420 })

do
    local t = tab.ESP
    t:Section("Targets")
    t:Toggle({
        Name = "Player ESP",
        Flag = "EspPlayers",
        Default = CFG.EspPlayers,
        Callback = function(v)
            CFG.EspPlayers = v
        end,
    })
    t:Toggle({
        Name = "Bot ESP (TPS_Bots)",
        Flag = "EspBots",
        Default = CFG.EspBots,
        Callback = function(v)
            CFG.EspBots = v
        end,
    })
    t:Separator()
    t:Section("Elements")
    t:Toggle({
        Name = "Names",
        Flag = "EspNames",
        Default = CFG.EspNames,
        Callback = function(v)
            CFG.EspNames = v
        end,
    })
    t:Toggle({
        Name = "Distance",
        Flag = "EspDistance",
        Default = CFG.EspDistance,
        Callback = function(v)
            CFG.EspDistance = v
        end,
    })
    t:Toggle({
        Name = "Boxes",
        Flag = "EspBoxes",
        Default = CFG.EspBoxes,
        Callback = function(v)
            CFG.EspBoxes = v
        end,
    })
    t:Toggle({
        Name = "Tracers",
        Flag = "EspTracers",
        Default = CFG.EspTracers,
        Callback = function(v)
            CFG.EspTracers = v
        end,
    })
    t:Toggle({
        Name = "Health bar",
        Flag = "EspHealth",
        Default = CFG.EspHealth,
        Callback = function(v)
            CFG.EspHealth = v
        end,
    })
    t:Slider({
        Name = "Max distance",
        Flag = "MaxDistance",
        Min = 200,
        Max = 4000,
        Step = 50,
        Default = CFG.MaxDistance,
        Suffix = "m",
        Callback = function(v)
            CFG.MaxDistance = v
        end,
    })
    t:Choice({
        Name = "Tracer origin",
        Flag = "TracerFrom",
        Options = { "Bottom", "Center", "Mouse" },
        Default = CFG.TracerFrom,
        Callback = function(v)
            CFG.TracerFrom = v
        end,
    })
    t:ColorPicker({
        Name = "Player color",
        Flag = "PlayerColor",
        Default = CFG.PlayerColor,
        Callback = function(c)
            CFG.PlayerColor = c
        end,
    })
    t:ColorPicker({
        Name = "Bot color",
        Flag = "BotColor",
        Default = CFG.BotColor,
        Callback = function(c)
            CFG.BotColor = c
        end,
    })
end

do
    local t = tab.Aim
    t:Section("Aim assist")
    t:Toggle({
        Name = "Enable (hold RMB)",
        Flag = "AimEnabled",
        Default = CFG.AimEnabled,
        Callback = function(v)
            CFG.AimEnabled = v
            card:Set({ Value = v and "AIM" or "OK" })
            if not v then
                H.lock = nil
            end
        end,
    })
    t:Toggle({
        Name = "Sticky target",
        Flag = "AimSticky",
        Default = CFG.AimSticky,
        Tooltip = "Stays on one target; only switches if a much closer one appears",
        Callback = function(v)
            CFG.AimSticky = v
        end,
    })
    t:Toggle({
        Name = "Team check",
        Flag = "AimTeamCheck",
        Default = CFG.AimTeamCheck,
        Callback = function(v)
            CFG.AimTeamCheck = v
        end,
    })
    t:Toggle({
        Name = "Show FOV",
        Flag = "ShowFov",
        Default = CFG.ShowFov,
        Callback = function(v)
            CFG.ShowFov = v
        end,
    })
    t:Slider({
        Name = "FOV",
        Flag = "AimFov",
        Min = 40,
        Max = 400,
        Step = 5,
        Default = CFG.AimFov,
        Callback = function(v)
            CFG.AimFov = v
        end,
    })
    t:Slider({
        Name = "Smoothness",
        Flag = "AimSmooth",
        Min = 0.08,
        Max = 0.7,
        Step = 0.01,
        Default = CFG.AimSmooth,
        Tooltip = "Higher = slower, less flicky",
        Callback = function(v)
            CFG.AimSmooth = v
        end,
    })
    t:Choice({
        Name = "Aim part",
        Flag = "AimPart",
        Options = { "Head", "HumanoidRootPart" },
        Default = CFG.AimPart,
        Callback = function(v)
            CFG.AimPart = v
        end,
    })
    t:ColorPicker({
        Name = "FOV color",
        Flag = "FovColor",
        Default = CFG.FovColor,
        Callback = function(c)
            CFG.FovColor = c
        end,
    })
    t:Paragraph("Hold RMB to aim. Sticky + hysteresis stops target flicker. ESP is pure world projection every frame so ADS / looking around cannot drag the boxes.")
end

ui:Settings({ Panel = tab.Settings })
tab.Settings:Separator()
tab.Settings:Button({
    Name = "Unload",
    Tone = "danger",
    Callback = function()
        cleanup()
        ui:Destroy()
    end,
})

ui:OnDestroy(function()
    cleanup()
end)

ui:Show()
ui:Notify({
    Title = "R1 ESP / Aim",
    Text = "RightShift toggles UI · Hold RMB for aim",
    Duration = 4,
    Tone = "accent",
})
print("[R1 ESP/Aim] LiteUI loaded — world ESP + sticky aim")
