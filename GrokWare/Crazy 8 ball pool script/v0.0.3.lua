--[[
    8 Ball Hub  ·  LiteUI (your v0.0.4, unmodified)
    Header card + tabs layout matches the LiteUI example
    RightAlt = UI  |  RightShift = aimbot
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
    LiteUI  v1.2.0   (animation pass — API is unchanged from 1.1.0)
    A flat, minimal UI library for Roblox: cards, tabs, collapsible panels, settings.

    ── Quick start ──────────────────────────────────────────────
    local ui   = Lite.new({ Name = "MyHUD", Key = Enum.KeyCode.RightShift })
    local card = ui:Card({ Title = "Hello", Subtitle = "World", Value = "42" })
    local tab  = ui:Tabs({ "Main", "Settings" })
    tab.Main:Toggle({ Name = "Enabled", Flag = "enabled", Default = true, Callback = print })
    ui:Settings({ Panel = tab.Settings })
    ui:Show()

    ── API ──────────────────────────────────────────────────────
    Lite.new(opts)  opts: Name, Width(264), Key, Theme("dark"), Opacity(.96), Scale(1),
                          X, Y, Parent, DisplayOrder, Save(true), SaveFile
    Lite.Themes     table of palettes; add your own before calling Lite.new

    Window:  :Card(opts)  :Panel(opts)  :Tabs(names, opts)  :Settings(opts)
             :Notify{Title,Text,Duration,Tone}
             :Show() :Hide() :Toggle() :Destroy()
             :SetTheme(n) :SetOpacity(v) :SetScale(v) :SetKey(keyCode)
             :OnDestroy(fn)    .Flags (saved values)   .Alive

    Card:    :Set{Title,Subtitle,Value,Tone}  :SetTone(key | Color3)  :Minimize(bool)
             :SetPinned(bool) :IsPinned() :AddButton(text, fn) :Attach(panel, closed, open)
             opts: Title, Subtitle, Value, Tone, Closable, Minimizable, Pinnable, OnPin

    Tabs:    local tab, bar = ui:Tabs({"A","B"}, {MaxHeight=250, Default="A"})
             tab.A / tab.B are Panels.   bar:Select("B")

    Panel:   :SetOpen(bool) :IsOpen()
             opts: Name, Open, Persist, MaxHeight (scrolls when taller)
             :Section(text)  :Label{Text,Tone}  :Paragraph(text)  :Separator()
             :Button{Name,Callback,Tone}
             :Toggle{Name,Default,Flag,Callback}
             :Slider{Name,Min,Max,Step,Default,Flag,Format,Suffix,Callback}
             :Choice{Name,Options,Default,Flag,Callback}            (click to cycle)
             :Dropdown{Name,Options,Default,Multi,Flag,Callback}    (expands inline)
             :TextBox{Name,Placeholder,Default,Numeric,OnlyEnter,Flag,Callback}
             :ColorPicker{Name,Default,Flag,Callback}
             :Keybind{Name,Default,Flag,Callback,Press}
             :Bar{Name,Min,Max,Default,Format,Tone}  ->  :Set(v) :SetTone(key)
             :List{Max,Empty}  ->  :Push(name, value)  :Clear()

    Elements with a Flag are saved/restored, and their Callback is called once
    on load with the restored value.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

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
}

local Window, Card, Panel = {}, {}, {}
Window.__index, Card.__index, Panel.__index = Window, Card, Panel

local QUINT = Enum.EasingStyle.Quint
local BACK = Enum.EasingStyle.Back
local QUAD = Enum.EasingStyle.Quad
local OUT = Enum.EasingDirection.Out
local IN = Enum.EasingDirection.In
local GAP = 6 -- vertical gap between boxes and between panel elements

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function tween(obj, props, t, style, dir, delay)
    t = t or 0.2
    if t == 0 then
        for k, v in pairs(props) do
            obj[k] = v
        end
        return
    end
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(t, style or QUAD, dir or OUT, 0, false, delay or 0),
        props
    )
    tw:Play()
    return tw
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

-- Text "dips" on press and springs back on release
local function pressFx(btn, base, dip)
    base = base or btn.TextSize
    dip = dip or 2
    local down = false
    btn.MouseButton1Down:Connect(function()
        down = true
        tween(btn, { TextSize = base - dip }, 0.07)
    end)
    local function release()
        if down then
            down = false
            tween(btn, { TextSize = base }, 0.35, BACK)
        end
    end
    btn.MouseButton1Up:Connect(release)
    btn.MouseLeave:Connect(release)
end

-- Slider knob grows on hover and a bit more while dragged.
-- Returns a function to call when a drag starts.
local function knobFx(win, hit, knob, small, big)
    local dragging = false
    local function size(s)
        tween(knob, { Size = UDim2.fromOffset(s, s) }, 0.22, BACK)
    end
    hit.MouseEnter:Connect(function()
        if not dragging then
            size(small + 3)
        end
    end)
    hit.MouseLeave:Connect(function()
        if not dragging then
            size(small)
        end
    end)
    return function()
        dragging = true
        size(big)
        win._sliderEnd = function()
            dragging = false
            size(small)
        end
    end
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
    tween(entry.obj, { [entry.prop] = self:_color(key) }, instant and 0 or 0.25, QUAD)
end

function Window:_applyTheme(animate)
    local alive = {}
    for _, e in ipairs(self._registry) do
        if e.obj.Parent ~= nil then
            table.insert(alive, e)
            tween(e.obj, { [e.prop] = self:_color(e.key) }, animate and 0.4 or 0, QUAD)
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
        flags = {},
    })
    self.Flags = self.S.flags
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
        if self._toastGui then
            self._toastGui:Destroy()
        end
        for _, c in ipairs(self._conns) do
            c:Disconnect()
        end
        for _, fn in ipairs(self._onDestroy) do
            pcall(fn)
        end
    end)

    self:_installInput()
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
            if self._sliderEnd then
                local fn = self._sliderEnd
                self._sliderEnd = nil
                fn()
            end
            self:_save()
        end
        local d = self._drag
        self._drag = nil
        if d and d.moved then
            local x, y = self:_snap(self._rest.X.Offset, self._rest.Y.Offset)
            self._rest = UDim2.fromOffset(x, y)
            -- springy settle into the snapped position
            tween(self.Root, { Position = self._rest }, 0.45, BACK)
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
    self.Root.Position = self._rest + UDim2.fromOffset(0, -14)
    self._scale.Scale = self.S.scale * 0.94
    tween(self.Root, { GroupTransparency = 0 }, 0.35, QUAD)
    tween(self.Root, { Position = self._rest }, 0.55, QUINT)
    tween(self._scale, { Scale = self.S.scale }, 0.6, BACK)
end

function Window:Hide(onDone)
    if not self.Alive then
        return
    end
    self._shown = false
    tween(self.Root, {
        GroupTransparency = 1,
        Position = self._rest + UDim2.fromOffset(0, 10),
    }, 0.25, QUINT, IN)
    tween(self._scale, { Scale = self.S.scale * 0.96 }, 0.25, QUINT, IN)
    task.delay(0.26, function()
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
    if self._shown then
        tween(self._scale, { Scale = self.S.scale }, 0.2, QUAD)
    else
        self._scale.Scale = self.S.scale
    end
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
        Size = UDim2.fromOffset(self.Width, height),
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
        Size = UDim2.fromOffset(W - 122, 20),
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
        Size = UDim2.fromOffset(W - 122, 18),
        Font = Enum.Font.BuilderSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = tostring(opts.Subtitle or ""),
    }, f)
    self:_themed(card.SubLabel, "TextColor3", "sub")

    card.Divider = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, W - 94, 0.5, 0),
        Size = UDim2.fromOffset(1, 40),
        BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
    }, f)
    self:_themed(card.Divider, "BackgroundColor3", "line")

    card.ValueLabel = make("TextButton", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(W - 86, 0),
        Size = UDim2.fromOffset(76, FULL_H),
        Font = Enum.Font.BuilderSansExtraBold,
        TextSize = 34,
        Text = tostring(opts.Value or "–"),
        AutoButtonColor = false,
    }, f)
    card._toneEntry = self:_themed(card.ValueLabel, "TextColor3", opts.Tone or "sub")

    card.PinLabel = make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(W - 86, FULL_H - 13), -- rests lower, slides up when pinned
        Size = UDim2.fromOffset(76, 12),
        Font = Enum.Font.BuilderSansMedium,
        TextSize = 11,
        Text = "pinned",
        TextTransparency = 1,
    }, f)
    self:_themed(card.PinLabel, "TextColor3", "sub")

    -- hover reveals header buttons (always visible on touch-only devices)
    if not self._touchOnly then
        local stroke = f:FindFirstChildOfClass("UIStroke")
        f.MouseEnter:Connect(function()
            tween(stroke, { Transparency = 0.78 }, 0.25)
            for i, b in ipairs(card._buttons) do
                tween(b.Instance, { TextTransparency = 0 }, 0.22, QUAD, OUT, (i - 1) * 0.04)
            end
        end)
        f.MouseLeave:Connect(function()
            tween(stroke, { Transparency = 0.9 }, 0.3)
            for _, b in ipairs(card._buttons) do
                tween(b.Instance, { TextTransparency = 1 }, 0.18)
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
        tween(b, { TextColor3 = win:_color("text") }, 0.15)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { TextColor3 = win:_color("sub") }, 0.2)
    end)
    pressFx(b, 16, 4)
    if callback then
        b.MouseButton1Click:Connect(callback)
    end

    local obj = { Instance = b }
    function obj:SetText(t)
        b.Text = t
        if win._shown then
            b.TextSize = 12
            tween(b, { TextSize = 16 }, 0.35, BACK)
        end
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

local function fadeText(win, label, text, hidden)
    if label.Text == text then
        return
    end
    label.Text = text
    if win._shown and not hidden then
        label.TextTransparency = 0.75
        tween(label, { TextTransparency = 0 }, 0.3)
    end
end

function Card:Set(t)
    local win = self.Window
    if t.Title ~= nil then
        fadeText(win, self.TitleLabel, tostring(t.Title), false)
    end
    if t.Subtitle ~= nil then
        fadeText(win, self.SubLabel, tostring(t.Subtitle), self._mini)
    end
    if t.Value ~= nil then
        local v = tostring(t.Value)
        local vl = self.ValueLabel
        if v ~= vl.Text then
            vl.Text = v
            if win._shown then
                local ts = self._mini and 20 or 34
                vl.TextTransparency = 1
                vl.TextSize = ts - 8
                vl.Position = UDim2.fromOffset(self._width - 86, 8)
                tween(vl, { TextTransparency = 0 }, 0.25)
                tween(vl, { TextSize = ts }, 0.45, BACK)
                tween(vl, { Position = UDim2.fromOffset(self._width - 86, 0) }, 0.45, QUINT)
            end
        end
    end
    if t.Tone then
        self:SetTone(t.Tone)
    end
end

function Card:_updatePin(instant)
    local show = self._pinned and not self._mini
    local baseY = self._full - 19
    local d = instant and 0 or 0.35
    tween(self.PinLabel, {
        TextTransparency = show and 0 or 1,
        Position = UDim2.fromOffset(self._width - 86, show and baseY or baseY + 6),
    }, d, QUINT)
end

function Card:SetPinned(p)
    local was = self._pinned
    self._pinned = p and true or false
    self:_updatePin()
    if self._pinned ~= was and self.Window._shown and not self._mini then
        local vl = self.ValueLabel
        vl.TextSize = 38
        tween(vl, { TextSize = 34 }, 0.5, BACK)
    end
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
    local d = instant and 0 or 0.4

    if self._miniBtn then
        self._miniBtn:SetText(m and "+" or "–")
    end
    tween(self.Frame, { Size = UDim2.fromOffset(self._width, m and self._miniH or self._full) }, d, QUINT)
    tween(self.TitleLabel, {
        Position = UDim2.fromOffset(16, m and 8 or 14),
        TextSize = m and 15 or 17,
    }, d, QUINT)
    tween(self.SubLabel, { TextTransparency = m and 1 or 0 }, instant and 0 or 0.25, QUAD, OUT, m and 0 or 0.1)
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

    local open = opts.Open == true
    if opts.Persist and opts.Name then
        panel._flagKey = "_open:" .. opts.Name
        open = self:_flagGet(panel._flagKey, open)
    end

    -- inner CanvasGroup so a panel's contents can fade in/out as one
    local fade = make("CanvasGroup", {
        Name = "Fade",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        GroupTransparency = open and 0 or 1,
    }, f)
    panel._fade = fade

    local content = fade
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
        }, fade)
        self:_themed(content, "ScrollBarImageColor3", "sub")
    end
    make("UIListLayout", {
        Padding = UDim.new(0, GAP),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, content)
    panel._pad = make("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
    }, content)
    panel.Content = content

    panel._open = open
    if open then
        f.Visible = true
    end
    return panel
end

function Panel:_height()
    local n = #self._items
    if n == 0 then
        return 16
    end
    local h = 16 + GAP * (n - 1)
    for _, it in ipairs(self._items) do
        h += it.h
    end
    if self._max then
        h = math.min(h, self._max)
    end
    return h
end

function Panel:_apply(instant, fromH)
    local f = self.Frame
    local W = self.Window.Width
    instant = instant or not self.Window._ready
    local d = instant and 0 or 0.35

    if self._open then
        local wasVisible = f.Visible
        f.Visible = true
        if not instant and fromH and not wasVisible then
            f.Size = UDim2.fromOffset(W, fromH) -- morph from the previous tab's height
        end
        tween(f, { Size = UDim2.fromOffset(W, self:_height()) }, d, QUINT)
    else
        if not f.Visible then
            return
        end
        tween(f, { Size = UDim2.fromOffset(W, 0) }, d, QUINT)
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

function Panel:SetOpen(open, instant, fromH)
    open = open and true or false
    local changed = open ~= self._open
    self._open = open
    if self._flagKey then
        self.Window:_flagSet(self._flagKey, self._open)
    end

    local inst = instant or not self.Window._ready
    if open then
        if inst then
            self._fade.GroupTransparency = 0
        elseif changed then
            self._fade.GroupTransparency = 1
            self._pad.PaddingTop = UDim.new(0, 20)
            tween(self._fade, { GroupTransparency = 0 }, 0.3, QUAD, OUT, 0.05)
            tween(self._pad, { PaddingTop = UDim.new(0, 8) }, 0.5, QUINT)
        end
    else
        if inst then
            self._fade.GroupTransparency = 1
        elseif changed then
            tween(self._fade, { GroupTransparency = 1 }, 0.15)
        end
    end

    self:_apply(instant, fromH)
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
    b.MouseEnter:Connect(function()
        tween(b, { BackgroundTransparency = 0.3 }, 0.15)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { BackgroundTransparency = 0 }, 0.2)
    end)
    pressFx(b, 13, 2)
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
            t = tostring(t)
            if l.Text ~= t then
                l.Text = t
                if win._shown then
                    l.TextTransparency = 0.7
                    tween(l, { TextTransparency = 0 }, 0.3)
                end
            end
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
        tween(b, { BackgroundTransparency = 0.4 }, 0.18)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { BackgroundTransparency = 0 }, 0.25)
    end)
    b.MouseButton1Down:Connect(function()
        tween(b, { BackgroundTransparency = 0.7 }, 0.06)
    end)
    b.MouseButton1Up:Connect(function()
        tween(b, { BackgroundTransparency = 0.4 }, 0.3)
    end)
    pressFx(b, 14, 2)
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
    rowLabel(win, row, o.Name or "Toggle", 150)

    local function knobPos(v, stretched)
        if v then
            return UDim2.new(0, stretched and 14 or 18, 0.5, 0)
        end
        return UDim2.new(0, 2, 0.5, 0)
    end

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
        Position = knobPos(value, false),
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
        tween(knob, {
            Position = knobPos(v, false),
            Size = UDim2.fromOffset(14, 14),
        }, 0.4, BACK)
        win:_flagSet(o.Flag, v)
        if not silent and o.Callback then
            task.spawn(o.Callback, v)
        end
    end

    -- knob stretches while pressed, then springs into place
    local pressed = false
    click.MouseButton1Down:Connect(function()
        pressed = true
        tween(knob, {
            Size = UDim2.fromOffset(19, 14),
            Position = knobPos(obj.Value, true),
        }, 0.12)
    end)
    local function relax()
        if pressed then
            pressed = false
            tween(knob, {
                Size = UDim2.fromOffset(14, 14),
                Position = knobPos(obj.Value, false),
            }, 0.3, BACK)
        end
    end
    click.MouseButton1Up:Connect(relax)
    click.MouseLeave:Connect(relax)
    click.MouseButton1Click:Connect(function()
        obj:Set(not obj.Value)
    end)

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
    local function draw(instant)
        local a = (max > min) and (obj.Value - min) / (max - min) or 0
        local d = instant and 0 or 0.12
        tween(fill, { Size = UDim2.fromScale(a, 1) }, d)
        tween(knob, { Position = UDim2.new(a, 0, 0.5, 0) }, d)
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
    draw(true)

    local grab = knobFx(win, hit, knob, 12, 16)
    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            grab()
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
        if win._shown then
            btn.TextTransparency = 0.8
            tween(btn, { TextTransparency = 0 }, 0.3)
        end
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
        if win._shown then
            btn.TextTransparency = 0.8
            tween(btn, { TextTransparency = 0 }, 0.3)
        end
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
            if k ~= Enum.KeyCode.Escape and k ~= Enum.KeyCode.Unknown then
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
        tween(row, { Size = UDim2.new(1, 0, 0, item.h) }, win._ready and 0.3 or 0, QUINT)
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

        -- newest entry slides in from the left
        if win._shown then
            nameLbls[1].TextTransparency = 1
            valLbls[1].TextTransparency = 1
            nameLbls[1].Position = UDim2.fromOffset(-14, 0)
            valLbls[1].Position = UDim2.new(1, -36, 0, 0)
            tween(nameLbls[1], {
                TextTransparency = 0,
                Position = UDim2.fromOffset(0, 0),
            }, 0.5, QUINT)
            tween(valLbls[1], {
                TextTransparency = 0,
                Position = UDim2.new(1, -50, 0, 0),
            }, 0.5, QUINT, OUT, 0.04)
        end
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
        tween(row, { Size = UDim2.new(1, 0, 0, item.h) }, win._ready and 0.3 or 0, QUINT)
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

    -- accent outline that fades in while the box is focused
    local focusStroke = make("UIStroke", {
        Thickness = 1,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, box)
    win:_themed(focusStroke, "Color", "accent")
    box.Focused:Connect(function()
        tween(focusStroke, { Transparency = 0.15 }, 0.2)
    end)

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
        tween(focusStroke, { Transparency = 1 }, 0.3)
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
    function obj:Set(v, instant)
        v = math.clamp(v, min, max)
        self.Value = v
        local a = max > min and (v - min) / (max - min) or 0
        tween(fill, { Size = UDim2.fromScale(a, 1) }, instant and 0 or 0.55, QUINT)
        out.Text = fmt(v)
    end
    function obj:SetTone(key)
        win:_setKey(fillE, key)
    end
    obj:Set(obj.Value, true)
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

    local listF = make("CanvasGroup", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, HEAD_H + 4),
        Size = UDim2.new(1, 0, 0, #options * ITEM_H),
        Visible = false,
        GroupTransparency = 1,
    }, row)

    local obj = { Value = value }
    local entries, btns = {}, {}

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
            tween(listF, { GroupTransparency = 0 }, 0.3, QUAD, OUT, 0.05)
            -- options slide in one after another
            for i, b in ipairs(btns) do
                b.Position = UDim2.fromOffset(-12, (i - 1) * ITEM_H)
                tween(b, { Position = UDim2.fromOffset(0, (i - 1) * ITEM_H) }, 0.5, QUINT, OUT, (i - 1) * 0.035)
            end
        else
            tween(listF, { GroupTransparency = 1 }, 0.15)
            task.delay(0.32, function()
                if not open then
                    listF.Visible = false
                end
            end)
        end
        tween(row, { Size = UDim2.new(1, 0, 0, item.h) }, 0.35, QUINT)
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
        btns[i] = b
        win:_themed(b, "BackgroundColor3", "track")
        entries[i] = win:_themed(b, "TextColor3", isSel(opt) and "accent" or "text")
        make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, b)
        b.MouseEnter:Connect(function()
            tween(b, { BackgroundTransparency = 0.35 }, 0.15)
        end)
        b.MouseLeave:Connect(function()
            tween(b, { BackgroundTransparency = 0 }, 0.2)
        end)
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
        if win._shown then
            head.TextTransparency = 0.8
            tween(head, { TextTransparency = 0 }, 0.3)
        end
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
    swatch.MouseEnter:Connect(function()
        tween(swatch, { Size = UDim2.fromOffset(48, 20) }, 0.25, BACK)
    end)
    swatch.MouseLeave:Connect(function()
        tween(swatch, { Size = UDim2.fromOffset(44, 20) }, 0.25, BACK)
    end)

    local body = make("CanvasGroup", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, HEAD_H + 6),
        Size = UDim2.new(1, 0, 0, 3 * (BAR_H + 2)),
        Visible = false,
        GroupTransparency = 1,
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

        local grab = knobFx(win, hit, knob, 12, 15)
        hit.InputBegan:Connect(function(input)
            if isPress(input) then
                grab()
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
            body.Position = UDim2.fromOffset(0, HEAD_H - 4)
            tween(body, { GroupTransparency = 0 }, 0.3, QUAD, OUT, 0.06)
            tween(body, { Position = UDim2.fromOffset(0, HEAD_H + 6) }, 0.5, QUINT)
        else
            tween(body, { GroupTransparency = 1 }, 0.15)
            task.delay(0.32, function()
                if not open then
                    body.Visible = false
                end
            end)
        end
        tween(row, { Size = UDim2.new(1, 0, 0, item.h) }, 0.35, QUINT)
        self:_apply()
    end)

    if o.Flag and o.Callback then
        task.defer(o.Callback, obj.Value)
    end
    return obj
end

----------------------------------------------------------------
-- Tabs: a segmented bar with a sliding pill; each tab is a normal Panel
----------------------------------------------------------------
function Window:Tabs(names, opts)
    opts = opts or {}
    local win = self
    self._tabCount = (self._tabCount or 0) + 1
    local flagKey = "_tab:" .. self._tabCount
    local n = #names

    local box = self:_box("Tabs", 34)

    -- sliding highlight behind the selected tab
    local innerW = self.Width - 8
    local bw = (innerW - 4 * (n - 1)) / n
    local pill = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 4, 0.5, 0),
        Size = UDim2.fromOffset(bw, 26),
        BorderSizePixel = 0,
        ZIndex = 1,
    }, box)
    win:_themed(pill, "BackgroundColor3", "track")
    make("UICorner", { CornerRadius = UDim.new(0, 7) }, pill)

    local holder = make("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2,
    }, box)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, holder)
    make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, holder)

    local bar = { Panels = {}, Current = nil }
    local parts, index = {}, {}

    for i, name in ipairs(names) do
        index[name] = i
        local b = make("TextButton", {
            LayoutOrder = i,
            Size = UDim2.new(1 / n, -4 * (n - 1) / n, 0, 26),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = Enum.Font.BuilderSansMedium,
            TextSize = 14,
            Text = name,
            AutoButtonColor = false,
        }, holder)
        parts[name] = { btn = b, tx = win:_themed(b, "TextColor3", "sub") }
        bar.Panels[name] = self:Panel({ Name = name, MaxHeight = opts.MaxHeight })

        b.MouseButton1Click:Connect(function()
            bar:Select(name)
        end)
        b.MouseEnter:Connect(function()
            if bar.Current ~= name then
                tween(b, { TextColor3 = win:_color("text") }, 0.15)
            end
        end)
        b.MouseLeave:Connect(function()
            if bar.Current ~= name then
                tween(b, { TextColor3 = win:_color("sub") }, 0.2)
            end
        end)
        pressFx(b, 14, 1)
    end

    function bar:Select(name, instant)
        local target = self.Panels[name]
        if not target then
            return
        end

        -- remember where the previous tab ended so the new one can morph from it
        local prev = self.Current and self.Panels[self.Current]
        local fromH
        if prev and prev ~= target and prev.Frame.Visible then
            fromH = prev.Frame.Size.Y.Offset
        end

        self.Current = name
        local x = 4 + (index[name] - 1) * (bw + 4)
        tween(pill, { Position = UDim2.new(0, x, 0.5, 0) }, instant and 0 or 0.4, QUINT)

        for _, nm in ipairs(names) do
            local sel = nm == name
            win:_setKey(parts[nm].tx, sel and "text" or "sub", instant)
            if sel then
                self.Panels[nm]:SetOpen(true, instant, fromH)
            else
                self.Panels[nm]:SetOpen(false, true)
            end
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
-- Notifications (toasts, bottom-right, click to dismiss)
----------------------------------------------------------------
function Window:Notify(o)
    if type(o) == "string" then
        o = { Text = o }
    end
    o = o or {}
    if not self.Alive then
        return
    end

    if not self._toastHolder then
        self._toastGui = make("ScreenGui", {
            Name = self.Name .. "_Toasts",
            ResetOnSpawn = false,
            DisplayOrder = self.Gui.DisplayOrder + 1,
            IgnoreGuiInset = true,
        }, self.Gui.Parent)
        self._toastHolder = make("Frame", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -18, 1, -18),
            Size = UDim2.fromOffset(260, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        }, self._toastGui)
        make("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }, self._toastHolder)
    end

    self._toastN = (self._toastN or 0) + 1

    -- wrapper lets the toast slide sideways inside the layout, and collapse on exit
    local wrap = make("Frame", {
        LayoutOrder = self._toastN,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(260, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, self._toastHolder)

    local t = make("CanvasGroup", {
        Position = UDim2.fromOffset(48, 0),
        Size = UDim2.fromOffset(260, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
    }, wrap)
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

    local duration = o.Duration or 4
    local gone = false
    local function dismiss()
        if gone then
            return
        end
        gone = true
        tween(t, {
            GroupTransparency = 1,
            Position = UDim2.fromOffset(48, 0),
        }, 0.3, QUINT, IN)
        task.delay(0.22, function()
            if not wrap.Parent then
                return
            end
            -- collapse the gap smoothly so the other toasts glide down
            local h = wrap.AbsoluteSize.Y
            wrap.AutomaticSize = Enum.AutomaticSize.None
            wrap.ClipsDescendants = true
            wrap.Size = UDim2.fromOffset(260, h)
            tween(wrap, { Size = UDim2.fromOffset(260, 0) }, 0.3, QUINT)
            task.delay(0.34, function()
                if wrap.Parent then
                    wrap:Destroy()
                end
            end)
        end)
    end
    t.InputBegan:Connect(function(input)
        if isPress(input) then
            dismiss()
        end
    end)

    tween(t, { GroupTransparency = 0 }, 0.3)
    tween(t, { Position = UDim2.fromOffset(0, 0) }, 0.55, BACK)
    -- the accent bar drains to show the time left
    tween(accent, { Size = UDim2.new(0, 3, 0, 0) }, duration, Enum.EasingStyle.Linear, OUT, 0.3)
    task.delay(duration, dismiss)
end

----------------------------------------------------------------
-- Ready-made settings panel (opacity, size, theme, hotkey)
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
    return panel
end


----------------------------------------------------------------

getgenv().Lite = Lite
_G.Lite = Lite

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local lp = Players.LocalPlayer
local Shared = RS:WaitForChild("Shared")
local Net = RS:WaitForChild("Net")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local Physics = Shared:WaitForChild("Physics")
local TablePhys = require(Physics:WaitForChild("Table"))
local Ball = require(Physics:WaitForChild("Ball"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local Aim = require(Physics:WaitForChild("Aim"))
local CueMod = require(Physics:WaitForChild("Cue"))
local ShotFinder = require(Shared:WaitForChild("Bots"):WaitForChild("ShotFinder"))
local ShotJudge = require(Shared:WaitForChild("Rules"):WaitForChild("ShotJudge"))
local CuePlacement = require(Shared:WaitForChild("Rules"):WaitForChild("CuePlacement"))
local cv = workspace:WaitForChild("ClientVisuals")

local G = getgenv()
for _, k in ipairs({ "BOLA8HUB", "BOLA8", "BOLA8_LINEAS" }) do
    local old = G[k]
    if old then
        pcall(old.destroy or old.stop or function() end)
        G[k] = nil
    end
end

local S = {
    enabled = false,
    action = "Auto",
    strategy = "Normal",

    autoPlace = true,
    autoPocket = true,
    usePosition = true,
    positionWeight = 1.0,
    mouseAim = true,
    breakPower = 1.0,

    allowBank = true,
    allowDouble = true,
    allowKick = true,
    allowCombo = true,
    brute = true,
    bruteStep = 0.5,
    budget = 4.0,
    maxCut = 80,
    maxPower = 1.0,

    robustChecks = 2,
    robustEps = 0.10,
    strict = false,
    powerVariants = 5,
    useSpin = false,
    spinAmount = 0.5,

    multiStep = 2.0,
    multiMin = 2,
    multiSpin = true,

    aiMult = 2,
    aiSpin = true,
    aiGoal = "Balanced",
    learn = true,

    humanize = false,
    delayMin = 0.6,
    delayMax = 1.6,
    angleNoise = 0.0,
    powerNoise = 0.0,
    missChance = 0.0,

    showPlan = true,
    showAim = false,
    thickness = Config.Guideline.LineWidthStuds or 0.08,
    planColor = Color3.fromRGB(80, 255, 120),
    aimColor = Color3.fromRGB(255, 255, 255),
    notify = true,
}

local KEYS = { toggle = "RightShift", replan = "R", lines = "T" }
local function keyName(v) return (tostring(v):match("([%w_]+)$")) or tostring(v) end

local H = { S = S, running = true, busy = false, plans = {}, done = {}, retries = {}, conns = {}, stats = { shots = 0 } }
G.BOLA8HUB = H

local Finder = Config.Bots.Finder
local finderOrig = {}
for _, k in ipairs({ "MaxCutDegrees", "MaxPower", "CandidatesTried" }) do finderOrig[k] = Finder[k] end
local function applyFinder()
    pcall(function()
        Finder.MaxCutDegrees = S.maxCut
        Finder.MaxPower = S.maxPower
        Finder.CandidatesTried = (S.strategy == "Impossible" or S.strategy == "Multi-ball" or S.strategy == "Evolutionary AI") and 24 or 12
    end)
end
applyFinder()

local radius = Config.Balls.RadiusInches
local diameter = 2 * radius
local fixedStep = Config.Physics.FixedStep
local MP = Config.Multiplayer
local GEO = TablePhys.build({ pocketsOpen = true })
local halfL, halfW = GEO.halfLength, GEO.halfWidth
local ELEV = Config.Cue.CueElevationDegrees

local function log(msg) print("[8Ball Hub] " .. tostring(msg)) end
local function note(title, text)
    if not S.notify then return end
    if H.ui then
        pcall(function()
            H.ui:Notify({ Title = tostring(title), Text = tostring(text), Duration = 3 })
        end)
    else
        print("[8Ball Hub]", title, text)
    end
end

local function wrap(a)
    while a > math.pi do a -= 2 * math.pi end
    while a < -math.pi do a += 2 * math.pi end
    return a
end
local function dist(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end
local function unit(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local m = math.sqrt(dx * dx + dy * dy)
    if m < 1e-9 then return 0, 0 end
    return dx / m, dy / m
end
local function gauss()
    return math.sqrt(-2 * math.log(math.max(1e-9, math.random()))) * math.cos(2 * math.pi * math.random())
end

local function unpackBalls(s)
    local t = {}
    if type(s.balls[1]) == "table" then return s.balls end
    for i = 1, #s.balls, 4 do
        table.insert(t, {
            id = (i - 1) / 4, x = s.balls[i], y = s.balls[i + 1],
            z = s.balls[i + 2] or 0, pocketed = s.balls[i + 3] == 1,
        })
    end
    return t
end
local function findBall(balls, id)
    for _, b in ipairs(balls) do if b.id == id then return b end end
    return nil
end
local function groupOf(id)
    local ok, g = pcall(ShotJudge.group, id)
    return ok and g or nil
end

local HttpService = game:GetService("HttpService")
local MEM_FILE = "ball8_memory.json"
local Mem = { version = 1, breaks = {}, kinds = {}, shots = 0 }
local memDirty, memLastSave = false, 0

local function memLoad()
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(MEM_FILE)) end)
    if ok and type(data) == "table" then
        Mem.breaks = type(data.breaks) == "table" and data.breaks or {}
        Mem.kinds = type(data.kinds) == "table" and data.kinds or {}
        Mem.shots = tonumber(data.shots) or 0
        return true
    end
    return false
end
local function memSave(force)
    if not memDirty then return end
    if not force and os.clock() - memLastSave < 5 then return end
    local ok = pcall(function() writefile(MEM_FILE, HttpService:JSONEncode(Mem)) end)
    if ok then memDirty, memLastSave = false, os.clock() end
end
local function memClear()
    Mem.breaks, Mem.kinds, Mem.shots = {}, {}, 0
    memDirty = true
    memSave(true)
end
memLoad()

local function kindBonus(kind)
    if not S.learn then return 0 end
    local k = Mem.kinds[kind]
    if not k or k.n < 3 then return 0 end
    local r = (k.ok + 2) / (k.n + 3)
    return (r - 0.67) * 600
end

local function recordBreak(y, off, pow, spin, score, real)
    local list = Mem.breaks
    for _, e in ipairs(list) do
        if math.abs(e.y - y) < 0.6 and math.abs(e.off - off) < 0.006 and math.abs(e.pow - pow) < 0.03 then
            e.trials += 1
            e.pots += real
            e.score = math.max(e.score or 0, score or 0)
            return
        end
    end
    table.insert(list, {
        y = y, off = off, pow = pow, sx = spin and spin.x or 0, sy = spin and spin.y or 0,
        score = score or 0, trials = 1, pots = real,
    })
    table.sort(list, function(a, b)
        local ra, rb = a.pots / a.trials, b.pots / b.trials
        if ra ~= rb then return ra > rb end
        return (a.score or 0) > (b.score or 0)
    end)
    while #list > 40 do table.remove(list) end
end

local function memBreakSeeds(y)
    local out = {}
    for _, e in ipairs(Mem.breaks) do
        if math.abs(e.y - y) < 1.5 then table.insert(out, e) end
        if #out >= 6 then break end
    end
    return out
end
local function memBestBreakY()
    local e = Mem.breaks[1]
    return e and e.y or nil
end

local snaps = {}
local checkOutcome
H.conns[#H.conns + 1] = Net.TableState.OnClientEvent:Connect(function(s)
    if type(s) == "table" and s.id then
        snaps[s.id] = s
        if H.pending then pcall(checkOutcome, s) end
    end
end)

local function mySeat()
    for _, s in pairs(snaps) do
        if s.seats then
            for _, seat in ipairs(s.seats) do
                if seat.userId == lp.UserId then return s, seat.team end
            end
        end
    end
    return nil, nil
end

checkOutcome = function(s)
    local p = H.pending
    if not p then return end
    if os.clock() - p.t > 60 then H.pending = nil return end
    if s.id ~= p.tableId or not s.shot then return end
    local sh = s.shot
    if sh.shooter ~= lp.UserId or sh.turnId ~= p.turnId then return end
    H.pending = nil
    if not S.learn then return end

    local startB = sh.start and unpackBalls({ balls = sh.start }) or {}
    local finB = sh.final and unpackBalls({ balls = sh.final }) or {}
    local was = {}
    for _, b in ipairs(startB) do if b.pocketed then was[b.id] = true end end
    local actualSet, realPots = {}, 0
    for _, b in ipairs(finB) do
        if b.pocketed and not was[b.id] then
            actualSet[b.id] = true
            if b.id ~= 0 then realPots += 1 end
        end
    end
    local success = not actualSet[0]
    for _, id in ipairs(p.pred or {}) do
        if not actualSet[id] then success = false end
    end

    local k = Mem.kinds[p.kind] or { n = 0, ok = 0 }
    k.n += 1
    if success then k.ok += 1 end
    Mem.kinds[p.kind] = k
    Mem.shots += 1
    if p.isBreak and p.y then
        recordBreak(p.y, p.off or 0, p.power, p.spin, p.score, realPots)
    end
    memDirty = true
    memSave()
    note("Learning", string.format("%s: %s (potted %d). Reliability %s: %d/%d",
        p.kind, success and "matched the prediction" or "did NOT match the prediction", realPots, p.kind, k.ok, k.n))
end

local function currentAim(tableId)
    local guide = cv:FindFirstChild("Guideline")
    if not guide then return nil end
    local pl = Placement.forTable(tableId)
    if not pl then return nil end
    for _, name in ipairs({ "Path", "LeftEdge", "RightEdge" }) do
        local strip = guide:FindFirstChild(name)
        if strip and strip.Transparency < 1 then
            local lv = strip.CFrame.LookVector
            if math.abs(lv.X) > 1e-4 or math.abs(lv.Z) > 1e-4 then
                return (Placement.aimAngle(pl, lv.X, lv.Z) + math.pi) % (2 * math.pi)
            end
        end
    end
    return nil
end

local degPerPixel = math.rad(Config.Input.AimDegreesPerPixel or 0.18)
local function rotateTo(tableId, target)
    local cur = currentAim(tableId)
    if not cur then return false end
    local sign = 1
    for _ = 1, 3 do
        local err = wrap(target - cur)
        if math.abs(err) < 0.003 then return true end
        local m = lp:GetMouse()
        local vp = workspace.CurrentCamera.ViewportSize
        pcall(mousemoverel, vp.X / 2 - m.X, vp.Y / 2 - m.Y)
        task.wait(0.04)
        pcall(mouse1press)
        task.wait(0.03)
        pcall(mousemoverel, -sign * err / degPerPixel, 0)
        task.wait(0.10)
        pcall(mouse1release)
        task.wait(0.10)
        local after = currentAim(tableId)
        if not after then return false end
        local observed = wrap(after - cur)
        if observed * err < 0 and math.abs(observed) > 0.01 then sign = -sign end
        cur = after
    end
    return math.abs(wrap(target - cur)) < 0.02
end

local function clampSpinVec(sx, sy)
    local ok, a, b = pcall(CueMod.clampSpin, sx, sy)
    if ok and a then return { x = a, y = b } end
    return { x = sx, y = sy }
end

local function nearestPocketDist(x, y)
    local best = 1e9
    for _, p in ipairs(GEO.pockets) do
        local d = dist(x, y, p.x, p.y)
        if d < best then best = d end
    end
    return best
end

local function simulateFull(st, cand, spin, opts)
    local mult = (opts and opts.mult) or 1
    local track = opts and opts.track
    local dt = fixedStep * mult
    local simBalls, cueObj = {}, nil
    for _, b in ipairs(st.balls) do
        if b.id == 0 or not b.pocketed then
            local nb = Ball.new(b.id, b.x, b.y)
            table.insert(simBalls, nb)
            if b.id == 0 then cueObj = nb end
        end
    end
    if not cueObj then return nil end
    local ok, simState = pcall(Simulation.newState, st.geometry, simBalls)
    if not ok or not simState then return nil end
    local ok2 = pcall(Simulation.strike, simState, {
        angle = cand.angle, power = cand.power,
        spin = spin or { x = 0, y = 0 }, elevation = ELEV,
    })
    if not ok2 then return nil end

    local events, firstHit = {}, nil
    local minDist, hitSet, nHit = {}, {}, 0
    for stepIdx = 1, math.floor(8 / dt) do
        pcall(Simulation.step, simState, dt, events)
        for _, e in ipairs(events) do
            if e.type == "ballHit" then
                if not firstHit and (e.ball == 0 or e.other == 0) then
                    firstHit = (e.ball == 0) and e.other or e.ball
                end
                if track and not hitSet[e.ball .. ":" .. e.other] then
                    hitSet[e.ball .. ":" .. e.other] = true
                    nHit += 1
                end
            end
        end
        if track and stepIdx % 4 == 0 then
            for _, b in ipairs(simBalls) do
                if b.id ~= 0 and not b.pocketed then
                    local d = nearestPocketDist(b.x, b.y)
                    if d < (minDist[b.id] or 1e9) then minDist[b.id] = d end
                end
            end
        end
        local moving = false
        for _, b in ipairs(simBalls) do
            if Ball.isMoving(b) then moving = true break end
        end
        if not moving then break end
        table.clear(events)
    end

    local res = {
        scratch = cueObj.pocketed == true, cueX = cueObj.x, cueY = cueObj.y,
        firstHit = firstHit, pocketedIds = {}, pocketOf = {}, balls = {},
        minDist = minDist, nHit = nHit,
    }
    for _, b in ipairs(simBalls) do
        table.insert(res.balls, { id = b.id, x = b.x, y = b.y, z = 0, pocketed = b.pocketed == true })
        if b.pocketed and b.id ~= 0 then
            table.insert(res.pocketedIds, b.id)
            local pk = b.pocket
            res.pocketOf[b.id] = (type(pk) == "table") and pk.id or pk
        end
    end
    return res
end

local function openingNear(x, y, margin)
    for _, p in ipairs(GEO.pockets) do
        if dist(x, y, p.x, p.y) < p.radius + margin then return true end
    end
    return false
end

local function nextShotValue(st, res, team)
    local nst = { geometry = GEO, balls = res.balls, groups = st.groups, team = team, phase = {} }
    local ok, cands = pcall(ShotFinder.candidates, nst, res.cueX, res.cueY)
    if not ok or not cands then return 0, 0 end
    return math.min(#cands, 4), (cands[1] and cands[1].score or 0)
end

local function evaluateShot(st, cand, res)
    if not res or res.scratch or res.firstHit == nil then return nil end
    local group = st.groups and st.groups[st.team]
    local okL, legal = pcall(ShotJudge.legalTarget, st.balls, group, res.firstHit)
    if okL and legal == false then return nil end

    local okS, _, elig = pcall(ShotFinder.status, st)
    local eightLegal = okS and elig == true
    local good, bad, win = 0, 0, false
    for _, id in ipairs(res.pocketedIds) do
        if id == 8 then
            if not eightLegal then return nil end
            local pk = res.pocketOf[8]
            if st.called and pk and pk ~= st.called then return nil end
            win = true
        else
            local g = groupOf(id)
            if group == nil or g == group then good += 1 else bad += 1 end
        end
    end
    if not cand.safe and good == 0 and not win then return nil end

    local extra = st.extra or (st.multi and 450 or 25)
    local score = 1000 + (win and 2000 or 0) + extra * math.max(0, good - 1) - 120 * bad
    if cand.ball and not win then
        for _, id in ipairs(res.pocketedIds) do
            if id == cand.ball then score += 40 break end
        end
    end

    if S.usePosition and not win then
        local n, best = nextShotValue(st, res, st.team)
        local pw = S.positionWeight * (st.posMul or 1)
        score += pw * (n * 45 + math.min(best * 8000, 120))
        local edge = math.min(halfL - math.abs(res.cueX), halfW - math.abs(res.cueY))
        if edge < 3 then score -= 40 * pw end
        if openingNear(res.cueX, res.cueY, 5) then score -= 60 * pw end
        for _, b in ipairs(res.balls) do
            if b.id ~= 0 and not b.pocketed and dist(b.x, b.y, res.cueX, res.cueY) < diameter * 1.15 then
                score -= 50 * pw
                break
            end
        end
    end
    return score, { good = good, bad = bad, win = win }
end

local function pathClear(st, ax, ay, bx, by, i1, i2)
    for _, o in ipairs(st.balls) do
        if not o.pocketed and o.id ~= 0 and o.id ~= i1 and o.id ~= i2 then
            if ShotFinder.segmentDistance(o.x, o.y, ax, ay, bx, by) < diameter - 1e-6 then return false end
        end
    end
    return true
end

local function inside(x, y)
    return math.abs(x) < halfL - radius and math.abs(y) < halfW - radius
end

local RAILS = {
    { axis = "y", c = halfW - radius }, { axis = "y", c = -(halfW - radius) },
    { axis = "x", c = halfL - radius }, { axis = "x", c = -(halfL - radius) },
}
local function reflect(px, py, r)
    if r.axis == "y" then return px, 2 * r.c - py end
    return 2 * r.c - px, py
end
local function railHit(ax, ay, ux, uy, r)
    local t
    if r.axis == "y" then
        if math.abs(uy) < 1e-9 then return nil end
        t = (r.c - ay) / uy
    else
        if math.abs(ux) < 1e-9 then return nil end
        t = (r.c - ax) / ux
    end
    if t <= 0 then return nil end
    return ax + ux * t, ay + uy * t, t
end

local function cutBetween(cx, cy, gx, gy, ux, uy)
    local dx, dy = unit(cx, cy, gx, gy)
    return math.acos(math.clamp(dx * ux + dy * uy, -1, 1))
end

local function genBanks(st, cue, ids, depth)
    local out = {}
    local seqs = {}
    for _, r in ipairs(RAILS) do table.insert(seqs, { r }) end
    if depth >= 2 then
        for _, r1 in ipairs(RAILS) do
            for _, r2 in ipairs(RAILS) do
                if r1 ~= r2 and not (r1.axis == r2.axis and r1.c == -r2.c and false) then
                    table.insert(seqs, { r1, r2 })
                end
            end
        end
    end
    for _, id in ipairs(ids) do
        local b = findBall(st.balls, id)
        if b and not b.pocketed then
            for _, p in ipairs(GEO.pockets) do
                for _, seq in ipairs(seqs) do
                    if #seq == depth then
                        local px, py = p.x, p.y
                        for i = #seq, 1, -1 do px, py = reflect(px, py, seq[i]) end
                        local ux, uy = unit(b.x, b.y, px, py)
                        local gx, gy = b.x - ux * diameter, b.y - uy * diameter
                        if inside(gx, gy) then
                            local hx, hy = railHit(b.x, b.y, ux, uy, seq[1])
                            local legOk = hx ~= nil and math.abs(hx) <= halfL and math.abs(hy) <= halfW
                            if legOk and pathClear(st, b.x, b.y, hx, hy, id) and pathClear(st, cue.x, cue.y, gx, gy, id) then
                                local cut = cutBetween(cue.x, cue.y, gx, gy, ux, uy)
                                if cut <= math.rad(85) then
                                    local total = dist(b.x, b.y, px, py) + dist(cue.x, cue.y, gx, gy)
                                    table.insert(out, {
                                        angle = math.atan2(gy - cue.y, gx - cue.x), ball = id, pocket = p.id,
                                        kind = (#seq == 1) and "BANK" or "2 BANKS",
                                        prio = math.cos(cut) / (1 + total / 120) / (#seq),
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.prio > b.prio end)
    return out
end

local function genKicks(st, cue, ids)
    local out = {}
    for _, id in ipairs(ids) do
        local b = findBall(st.balls, id)
        if b and not b.pocketed then
            for _, p in ipairs(GEO.pockets) do
                local ux, uy = unit(b.x, b.y, p.x, p.y)
                local gx, gy = b.x - ux * diameter, b.y - uy * diameter
                if inside(gx, gy) and pathClear(st, b.x, b.y, p.x, p.y, id) then
                    for _, r in ipairs(RAILS) do
                        local mx, my = reflect(gx, gy, r)
                        local dx, dy = unit(cue.x, cue.y, mx, my)
                        local hx, hy = railHit(cue.x, cue.y, dx, dy, r)
                        if hx and math.abs(hx) < halfL and math.abs(hy) < halfW
                            and pathClear(st, cue.x, cue.y, hx, hy, id) and pathClear(st, hx, hy, gx, gy, id) then
                            local cut = cutBetween(hx, hy, gx, gy, ux, uy)
                            if cut <= math.rad(70) then
                                local total = dist(cue.x, cue.y, hx, hy) + dist(hx, hy, gx, gy) + dist(b.x, b.y, p.x, p.y)
                                table.insert(out, {
                                    angle = math.atan2(my - cue.y, mx - cue.x), ball = id, pocket = p.id,
                                    kind = "KICK", prio = math.cos(cut) / (1 + total / 100) * 0.8,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.prio > b.prio end)
    return out
end

local function genCombos(st, cue, ids)
    local out = {}
    for _, aBall in ipairs(st.balls) do
        if aBall.id ~= 0 and not aBall.pocketed then
            for _, tid in ipairs(ids) do
                local t = findBall(st.balls, tid)
                if t and not t.pocketed and t.id ~= aBall.id then
                    for _, p in ipairs(GEO.pockets) do
                        local ux, uy = unit(t.x, t.y, p.x, p.y)
                        local gtx, gty = t.x - ux * diameter, t.y - uy * diameter
                        if inside(gtx, gty) and pathClear(st, t.x, t.y, p.x, p.y, t.id, aBall.id) then
                            local ax, ay = unit(aBall.x, aBall.y, gtx, gty)
                            local gax, gay = aBall.x - ax * diameter, aBall.y - ay * diameter
                            if inside(gax, gay)
                                and pathClear(st, aBall.x, aBall.y, gtx, gty, aBall.id, t.id)
                                and pathClear(st, cue.x, cue.y, gax, gay, aBall.id) then
                                local cut1 = cutBetween(cue.x, cue.y, gax, gay, ax, ay)
                                local cut2 = math.acos(math.clamp(ax * ux + ay * uy, -1, 1))
                                if cut1 <= math.rad(70) and cut2 <= math.rad(60) then
                                    local total = dist(cue.x, cue.y, gax, gay) + dist(aBall.x, aBall.y, gtx, gty) + dist(t.x, t.y, p.x, p.y)
                                    table.insert(out, {
                                        angle = math.atan2(gay - cue.y, gax - cue.x), ball = t.id, pocket = p.id,
                                        kind = "COMBO", prio = math.cos(cut1) * math.cos(cut2) / (1 + total / 90) * 0.7,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.prio > b.prio end)
    return out
end

local function genBrute(st, cue, ids, tEnd)
    local out, best = {}, {}
    local legalSet = {}
    for _, id in ipairs(ids) do legalSet[id] = true end
    local step = math.max(0.1, S.bruteStep)
    local deg = 0
    local n = 0
    while deg < 360 do
        local a = math.rad(deg)
        local ok, tr = pcall(Aim.trace, st, { angle = a, power = 0.7, spin = { x = 0, y = 0 }, elevation = ELEV }, 1)
        if ok and tr and tr.contact == "ball" and tr.objectId and legalSet[tr.objectId] then
            local ob = findBall(st.balls, tr.objectId)
            if ob and (tr.objectDirX ~= 0 or tr.objectDirY ~= 0) then
                for _, p in ipairs(GEO.pockets) do
                    local vx, vy = p.x - ob.x, p.y - ob.y
                    local fwd = vx * tr.objectDirX + vy * tr.objectDirY
                    if fwd > 0 then
                        local lat = math.abs(vx * tr.objectDirY - vy * tr.objectDirX)
                        local window = p.radius * 0.85
                        if lat < window and pathClear(st, ob.x, ob.y, p.x, p.y, ob.id) then
                            local key = ob.id .. ":" .. p.id
                            if not best[key] or lat < best[key].lat then
                                best[key] = {
                                    lat = lat, angle = a, ball = ob.id, pocket = p.id, kind = "BRUTE FORCE",
                                    prio = (1 - lat / window) / (1 + fwd / 80) * 0.6,
                                }
                            end
                        end
                    end
                end
            end
        end
        deg += step
        n += 1
        if n % 40 == 0 then
            task.wait()
            if os.clock() > tEnd then break end
        end
    end
    for _, c in pairs(best) do table.insert(out, c) end
    table.sort(out, function(a, b) return a.prio > b.prio end)
    return out
end

local LADDER = { 0.7, 0.5, 0.9, 0.35, 1.0 }

local function spinFor(kx, ky)
    return clampSpinVec(kx * S.spinAmount * (Config.Cue.MaxSpinOffset or 1), ky * S.spinAmount * (Config.Cue.MaxSpinOffset or 1))
end

local function robustCount(st, c, spin)
    local n = S.robustChecks
    if n <= 0 then return 0, 0 end
    local e = math.rad(S.robustEps)
    local tests = { { -e, 1 }, { e, 1 }, { 0, 0.97 }, { 0, 1.03 }, { -2 * e, 1 }, { 2 * e, 1 } }
    local ok = 0
    for i = 1, math.min(n, #tests) do
        local da, pf = tests[i][1], tests[i][2]
        local t = { angle = c.angle + da, power = math.clamp(c.power * pf, Config.Input.MinPowerToShoot, 1), ball = c.ball, safe = c.safe }
        if evaluateShot(st, c, simulateFull(st, t, spin)) then ok += 1 end
        task.wait()
    end
    return ok, math.min(n, #tests)
end

local function safePlay(st, cue, tEnd)
    local ids = ShotFinder.ownIds(st)
    table.sort(ids, function(a, b)
        local ba, bb = findBall(st.balls, a), findBall(st.balls, b)
        return dist(cue.x, cue.y, ba.x, ba.y) < dist(cue.x, cue.y, bb.x, bb.y)
    end)
    local best, bestScore
    local opp = st.team and (3 - st.team) or nil
    for i = 1, math.min(5, #ids) do
        local b = findBall(st.balls, ids[i])
        if b and pathClear(st, cue.x, cue.y, b.x, b.y, b.id) then
            local ang = math.atan2(b.y - cue.y, b.x - cue.x)
            for _, pw in ipairs({ 0.12, 0.2, 0.3 }) do
                local c = { angle = ang, power = math.max(Config.Input.MinPowerToShoot, pw), ball = b.id, safe = true }
                local res = simulateFull(st, c)
                local sc = evaluateShot(st, c, res)
                if not sc and res and not res.scratch and res.firstHit then
                    local okL, legal = pcall(ShotJudge.legalTarget, st.balls, st.groups and st.groups[st.team], res.firstHit)
                    local ate8 = false
                    for _, id in ipairs(res.pocketedIds) do if id == 8 then ate8 = true end end
                    if (not okL or legal ~= false) and not ate8 then sc = 500 end
                end
                if sc then
                    if opp and st.groups and #st.groups > 0 then
                        local nst = { geometry = GEO, balls = res.balls, groups = st.groups, team = opp, phase = {} }
                        local okC, cands = pcall(ShotFinder.candidates, nst, res.cueX, res.cueY)
                        if okC and cands then sc -= #cands * 70 end
                    end
                    if not bestScore or sc > bestScore then
                        bestScore = sc
                        best = { angle = c.angle, power = c.power, ball = b.id, pocket = nil, kind = "SAFE", safe = true, score = sc }
                    end
                end
                task.wait()
            end
        end
        if os.clock() > tEnd + 1.5 then break end
    end
    if best then return best end
    local okF, safe = pcall(ShotFinder.safePlan, st, cue.x, cue.y)
    if okF and safe then
        return { angle = safe.angle, power = safe.power, ball = safe.ball, kind = "SAFE", safe = true, score = 0 }
    end
    return nil
end

local function spinVariants()
    return { spinFor(0, 0.6), spinFor(0, -0.6), spinFor(0.6, 0), spinFor(-0.6, 0) }
end

local function genSweepLoose(st, cue, ids, tEnd, stepDeg)
    local out, legalSet = {}, {}
    for _, id in ipairs(ids) do legalSet[id] = true end
    local deg, n = 0, 0
    while deg < 360 do
        local a = math.rad(deg)
        local ok, tr = pcall(Aim.trace, st, { angle = a, power = 0.7, spin = { x = 0, y = 0 }, elevation = ELEV }, 1)
        if ok and tr and tr.contact == "ball" and tr.objectId and legalSet[tr.objectId] then
            local ob = findBall(st.balls, tr.objectId)
            if ob then
                local bestLat = 1e9
                for _, p in ipairs(GEO.pockets) do
                    local vx, vy = p.x - ob.x, p.y - ob.y
                    local fwd = vx * tr.objectDirX + vy * tr.objectDirY
                    if fwd > 0 then bestLat = math.min(bestLat, math.abs(vx * tr.objectDirY - vy * tr.objectDirX)) end
                end
                table.insert(out, { angle = a, ball = tr.objectId, kind = "MULTI", prio = 1 / (1 + bestLat / 4) })
            end
        end
        deg += stepDeg
        n += 1
        if n % 40 == 0 then
            task.wait()
            if os.clock() > tEnd then break end
        end
    end
    table.sort(out, function(a, b) return a.prio > b.prio end)
    return out
end

local function multiEval(st, c, spin)
    local res = simulateFull(st, c, spin)
    local sc, info = evaluateShot(st, c, res)
    return sc, info, res
end

local function planMulti(st, cue, ids, tEnd)
    local seeds = {}
    local function add(list, maxN)
        for i = 1, math.min(maxN, #list) do table.insert(seeds, list[i]) end
    end
    for _, c in ipairs(ShotFinder.pots(st, 8, cue.x, cue.y)) do
        table.insert(seeds, { angle = c.angle, ball = c.ball, pocket = c.pocket, calPower = c.power, prio = 2 + (c.score or 0) })
    end
    add(genBanks(st, cue, ids, 1), 8)
    add(genCombos(st, cue, ids), 8)
    add(genKicks(st, cue, ids), 8)
    local step = math.max(0.5, S.multiStep)
    add(genSweepLoose(st, cue, ids, tEnd, step), 40)
    table.sort(seeds, function(a, b) return a.prio > b.prio end)

    local top = {}
    local function push(p)
        table.insert(top, p)
        table.sort(top, function(a, b) return a.score > b.score end)
        while #top > 4 do table.remove(top) end
    end
    local seedEnd = os.clock() + math.max(0, tEnd - os.clock()) * 0.6
    for _, sd in ipairs(seeds) do
        if os.clock() > seedEnd then break end
        local powers = sd.calPower and { sd.calPower, S.maxPower } or { 0.8, 0.6, 1.0 }
        for _, pw in ipairs(powers) do
            local c = { angle = sd.angle, power = math.clamp(pw, Config.Input.MinPowerToShoot, S.maxPower), ball = sd.ball }
            local sc, info, res = multiEval(st, c)
            if sc then
                push({ angle = c.angle, power = c.power, ball = sd.ball, pocket = sd.pocket, score = sc,
                    count = info.good + (info.win and 1 or 0), pred = res.pocketedIds })
            end
            task.wait()
        end
    end
    if #top == 0 then return nil end

    local best
    for i = 1, math.min(3, #top) do
        local cur = top[i]
        for _ = 1, 3 do
            local nbrs = {}
            for _, da in ipairs({ 0.5, -0.5, 0.2, -0.2, 0.08, -0.08 }) do
                table.insert(nbrs, { da = math.rad(da), pf = 1, spin = cur.spin })
            end
            for _, pf in ipairs({ 0.94, 1.06 }) do table.insert(nbrs, { da = 0, pf = pf, spin = cur.spin }) end
            if S.multiSpin then
                for _, sp in ipairs(spinVariants()) do table.insert(nbrs, { da = 0, pf = 1, spin = sp }) end
            end
            local improved = false
            for _, nb in ipairs(nbrs) do
                if os.clock() > tEnd then break end
                local c = { angle = cur.angle + nb.da, power = math.clamp(cur.power * nb.pf, Config.Input.MinPowerToShoot, S.maxPower), ball = cur.ball }
                local sc, info, res = multiEval(st, c, nb.spin)
                if sc and sc > cur.score then
                    cur = { angle = c.angle, power = c.power, ball = cur.ball, pocket = cur.pocket, score = sc,
                        count = info.good + (info.win and 1 or 0), spin = nb.spin, pred = res.pocketedIds }
                    improved = true
                end
                task.wait()
            end
            if not improved or os.clock() > tEnd then break end
        end
        if not best or cur.score > best.score then best = cur end
    end
    best = best or top[1]
    best.kind = "MULTI"
    return best
end

local function planBreak(st, cue, apex, tEnd)
    local base = math.atan2(apex.y - cue.y, apex.x - cue.x)
    local best
    local spins = { false }
    if S.multiSpin then for _, sp in ipairs(spinVariants()) do table.insert(spins, sp) end end
    for _, pw in ipairs({ math.min(1, S.maxPower), 0.92, 0.84 }) do
        for _, off in ipairs({ 0, 0.5, -0.5, 1, -1, 1.6, -1.6, 2.6, -2.6, 4, -4 }) do
            for _, sp in ipairs(spins) do
                if os.clock() > tEnd then break end
                local c = { angle = base + math.rad(off), power = math.clamp(pw, Config.Input.MinPowerToShoot, 1), safe = true }
                local sc, info, res = multiEval(st, c, sp or nil)
                if sc and (not best or sc > best.score) then
                    best = { angle = c.angle, power = c.power, score = sc, kind = "BREAK", spin = sp or nil,
                        count = info and info.good or 0, pred = res.pocketedIds }
                end
                task.wait()
            end
        end
    end
    return best
end

local function planAI(st, cue, ids, tEnd, isBreak)
    local legalSet = {}
    for _, id in ipairs(ids) do legalSet[id] = true end
    local spinMax = Config.Cue.MaxSpinOffset or 1
    local mult = math.clamp(math.floor(S.aiMult), 1, 3)
    local minP = Config.Input.MinPowerToShoot
    local t0 = os.clock()
    local span = math.max(0.3, tEnd - t0)

    local function ev(a, m)
        local power = math.clamp(a.pow, minP, S.maxPower)
        local spin
        if S.aiSpin and (math.abs(a.sx) + math.abs(a.sy)) > 0.02 then
            spin = clampSpinVec(a.sx * spinMax, a.sy * spinMax)
        end
        local c = { angle = a.ang, power = power }
        local res = simulateFull(st, c, spin, { mult = m, track = true })
        if not res then return -5000, nil, nil, spin, power end
        local sc, info = evaluateShot(st, c, res)
        if sc then return sc, res, info, spin, power end
        local f = -1000
        if res.scratch then f -= 400 end
        if res.firstHit == nil then f -= 500 end
        local prox = 0
        for id, d in pairs(res.minDist or {}) do
            if legalSet[id] then prox += math.max(0, 1 - d / 18) end
        end
        f += 130 * prox + 6 * math.min(res.nHit or 0, 12)
        return f, res, nil, spin, power
    end

    local pop = {}
    local function addInd(a, m)
        local f, res, info, spin, power = ev(a, m)
        local ind = { ang = a.ang, pow = a.pow, sx = a.sx, sy = a.sy, fit = f, valid = info ~= nil, info = info, spin = spin, power = power }
        table.insert(pop, ind)
        return ind
    end
    local function rs() return S.aiSpin and (math.random() * 2 - 1) * 0.5 or 0 end

    local seeds = {}
    if isBreak then
        local apex = findBall(st.balls, 1)
        if apex then
            local base = math.atan2(apex.y - cue.y, apex.x - cue.x)
            if S.learn then
                for _, e in ipairs(memBreakSeeds(cue.y)) do
                    table.insert(seeds, {
                        ang = base + e.off, pow = e.pow,
                        sx = (spinMax ~= 0) and (e.sx / spinMax) or 0, sy = (spinMax ~= 0) and (e.sy / spinMax) or 0,
                    })
                end
            end
            for _, off in ipairs({ 0, 1, -1, 2.5, -2.5 }) do
                for _, pw in ipairs({ 1.0, 0.9 }) do
                    table.insert(seeds, { ang = base + math.rad(off), pow = pw, sx = 0, sy = 0 })
                end
            end
        end
    else
        for _, c in ipairs(ShotFinder.pots(st, 5, cue.x, cue.y)) do
            table.insert(seeds, { ang = c.angle, pow = c.power, sx = 0, sy = 0 })
            table.insert(seeds, { ang = c.angle, pow = math.min(1, c.power * 1.15), sx = 0, sy = 0 })
        end
        for _, list in ipairs({ genBanks(st, cue, ids, 1), genCombos(st, cue, ids), genKicks(st, cue, ids) }) do
            for i = 1, math.min(4, #list) do
                table.insert(seeds, { ang = list[i].angle, pow = 0.75, sx = 0, sy = 0 })
            end
        end
    end
    local stage1End = t0 + span * 0.45
    for _, a in ipairs(seeds) do
        if os.clock() > stage1End then break end
        addInd(a, mult)
        task.wait()
    end
    local N = isBreak and 40 or 36
    local order = {}
    for i = 0, N - 1 do table.insert(order, i) end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    for _, i in ipairs(order) do
        if os.clock() > stage1End then break end
        addInd({ ang = (i + math.random()) / N * 2 * math.pi, pow = 0.4 + 0.6 * math.random(), sx = rs(), sy = rs() }, mult)
        task.wait()
    end
    if #pop == 0 then return nil end
    table.sort(pop, function(a, b) return a.fit > b.fit end)

    local islands = {}
    for _, ind in ipairs(pop) do
        local distinct = true
        for _, isl in ipairs(islands) do
            if math.abs(wrap(ind.ang - isl.ind.ang)) < math.rad(4) and math.abs(ind.pow - isl.ind.pow) < 0.2 then
                distinct = false
                break
            end
        end
        if distinct then
            table.insert(islands, { ind = ind, sig = { ang = 0.05, pow = 0.10, s = 0.20 } })
            if #islands >= 3 then break end
        end
    end
    local stage2End = tEnd - span * 0.15
    local gen = 0
    while os.clock() < stage2End and #islands > 0 do
        gen += 1
        for _, isl in ipairs(islands) do
            if os.clock() > stage2End then break end
            local bestChild
            for _ = 1, 3 do
                local p = isl.ind
                local a = {
                    ang = p.ang + gauss() * isl.sig.ang,
                    pow = math.clamp(p.pow + gauss() * isl.sig.pow, 0.1, 1),
                    sx = S.aiSpin and math.clamp(p.sx + gauss() * isl.sig.s, -1, 1) or 0,
                    sy = S.aiSpin and math.clamp(p.sy + gauss() * isl.sig.s, -1, 1) or 0,
                }
                local child = addInd(a, mult)
                if not bestChild or child.fit > bestChild.fit then bestChild = child end
                task.wait()
            end
            if bestChild and bestChild.fit > isl.ind.fit then
                isl.ind = bestChild
                isl.sig.ang = math.min(0.2, isl.sig.ang * 1.2)
                isl.sig.pow = math.min(0.25, isl.sig.pow * 1.2)
                isl.sig.s = math.min(0.4, isl.sig.s * 1.2)
            else
                isl.sig.ang = math.max(0.0004, isl.sig.ang * 0.82)
                isl.sig.pow = math.max(0.004, isl.sig.pow * 0.82)
                isl.sig.s = math.max(0.02, isl.sig.s * 0.82)
            end
        end
    end

    table.sort(pop, function(a, b) return a.fit > b.fit end)
    local finalists, seen = {}, {}
    for _, ind in ipairs(pop) do
        if ind.valid then
            local k = string.format("%.4f:%.3f", ind.ang % (2 * math.pi), ind.pow)
            if not seen[k] then
                seen[k] = true
                table.insert(finalists, ind)
                if #finalists >= 5 then break end
            end
        end
    end
    local verified = {}
    for _, ind in ipairs(finalists) do
        local f, res, info, spin, power = ev(ind, 1)
        if info then
            table.insert(verified, {
                angle = ind.ang, power = power, spin = spin, ball = res.firstHit, pocket = nil,
                score = f, count = info.good + (info.win and 1 or 0), kind = isBreak and "BREAK AI" or "AI",
                pred = res.pocketedIds,
            })
        end
        task.wait()
    end
    if #verified == 0 then return nil end
    table.sort(verified, function(a, b) return a.score > b.score end)

    if S.robustChecks > 0 and not isBreak then
        for i = 1, math.min(2, #verified) do
            local p = verified[i]
            local ok, n = robustCount(st, { angle = p.angle, power = p.power, ball = p.ball }, p.spin)
            p.score += 90 * ok - 160 * (n - ok)
            p.robust = n > 0 and (ok / n) or 1
        end
        table.sort(verified, function(a, b) return a.score > b.score end)
    end
    H.stats.aiEvals = #pop
    return verified[1]
end

local function planShot(snap, team, budgetOverride)
    local balls = unpackBalls(snap)
    local cue = findBall(balls, 0)
    if not cue then return nil end
    local st = { geometry = GEO, balls = balls, groups = snap.groups, team = team, phase = {}, called = snap.calledPocket }

    local strat = S.strategy
    st.multi = (strat == "Multi-ball")
    local isAI = (strat == "Evolutionary AI")
    if isAI then
        st.extra = ({ ["More balls"] = 450, ["Balanced"] = 150, ["Position"] = 25 })[S.aiGoal] or 150
        st.posMul = (S.aiGoal == "Position") and 1.8 or 1
    end
    local heavy = (strat == "Impossible" or strat == "Multi-ball" or isAI)
    local budget = budgetOverride or (heavy and S.budget or math.min(S.budget, 2.0))
    local tEnd = os.clock() + budget

    if snap.breakShot then
        local apex = findBall(balls, 1)
        if apex then
            if isAI then
                local pa = planAI(st, cue, ShotFinder.ownIds(st), tEnd, true)
                if pa then return pa end
            end
            if st.multi then
                local pb = planBreak(st, cue, apex, tEnd)
                if pb then return pb end
            end
            return { angle = math.atan2(apex.y - cue.y, apex.x - cue.x), power = S.breakPower, kind = "BREAK", score = 0 }
        end
    end

    local ids = ShotFinder.ownIds(st)

    if strat == "Safe" then
        return safePlay(st, cue, tEnd)
    end

    if isAI then
        local m = planAI(st, cue, ids, tEnd, false)
        if m then return m end
        strat = "Aggressive"
        st.extra, st.posMul = nil, nil
        tEnd = os.clock() + 2.0
    end

    if st.multi then
        local m = planMulti(st, cue, ids, tEnd)
        if m and m.count >= S.multiMin then return m end
        strat = "Aggressive"
        st.multi = false
        tEnd = os.clock() + 2.0
    end

    local pool = {}
    local function consider(c, powers, maxSucc, calibrated)
        local succ = 0
        local bestForCand
        for _, pw in ipairs(powers) do
            if os.clock() > tEnd then break end
            local cc = { angle = c.angle, power = math.clamp(pw, Config.Input.MinPowerToShoot, S.maxPower), ball = c.ball }
            local res = simulateFull(st, cc)
            local sc = evaluateShot(st, cc, res)
            if sc then
                succ += 1
                local plan = {
                    angle = cc.angle, power = cc.power, ball = c.ball, pocket = c.pocket,
                    kind = c.kind or "DIRECT", score = sc, res = res, pred = res.pocketedIds,
                }
                if not bestForCand or sc > bestForCand.score then bestForCand = plan end
                if succ >= maxSucc then break end
            end
            task.wait()
        end
        if bestForCand then table.insert(pool, bestForCand) end
    end

    local function directs()
        local pots = ShotFinder.pots(st, 8, cue.x, cue.y)
        for _, cand in ipairs(pots) do
            if st.called and cand.ball == 8 and cand.pocket ~= st.called then continue end
            local b = cand.power
            local pv = {
                b, math.min(S.maxPower, b * 1.08), math.max(Config.Input.MinPowerToShoot, b * 0.88),
                math.max(Config.Input.MinPowerToShoot, b * 0.75), math.min(S.maxPower, b * 1.25),
            }
            local list = {}
            for i = 1, math.min(S.powerVariants, #pv) do list[i] = pv[i] end
            consider({ angle = cand.angle, ball = cand.ball, pocket = cand.pocket, kind = "DIRECT" }, list, 3)
            if os.clock() > tEnd then break end
        end
    end

    local function runGen(list, maxN)
        for i = 1, math.min(maxN, #list) do
            local c = list[i]
            if st.called and c.ball == 8 and c.pocket ~= st.called then continue end
            consider(c, LADDER, 2)
            if os.clock() > tEnd then break end
        end
    end

    directs()
    local wantMore = (strat ~= "Normal") or (#pool == 0)
    if wantMore then
        if S.allowBank then runGen(genBanks(st, cue, ids, 1), 8) end
        if S.allowCombo then runGen(genCombos(st, cue, ids), 6) end
        if S.allowKick then runGen(genKicks(st, cue, ids), 6) end
        if strat == "Impossible" then
            if S.allowDouble then runGen(genBanks(st, cue, ids, 2), 8) end
            if S.brute then runGen(genBrute(st, cue, ids, tEnd), 12) end
        end
    end

    if #pool == 0 then
        return safePlay(st, cue, tEnd)
    end

    for _, p in ipairs(pool) do p.score += kindBonus(p.kind) end
    table.sort(pool, function(a, b) return a.score > b.score end)

    if S.robustChecks > 0 then
        local survivors = {}
        for i = 1, math.min(3, #pool) do
            local p = pool[i]
            local ok, n = robustCount(st, p, p.spin)
            p.robust = n > 0 and (ok / n) or 1
            p.score += 90 * ok - 160 * (n - ok)
            if not S.strict or ok == n then table.insert(survivors, p) end
        end
        if #survivors > 0 then pool = survivors end
        table.sort(pool, function(a, b) return a.score > b.score end)
    end

    local best = pool[1]

    if S.useSpin and best and not best.safe then
        local variants = { spinFor(0, 0.6), spinFor(0, -0.6), spinFor(0.6, 0), spinFor(-0.6, 0) }
        for _, sp in ipairs(variants) do
            local c = { angle = best.angle, power = best.power, ball = best.ball }
            local sc = evaluateShot(st, c, simulateFull(st, c, sp))
            if sc and sc > best.score + 15 then
                best.score, best.spin = sc, sp
            end
            task.wait()
        end
    end
    return best
end

local function choosePlacement(snap, team)
    local balls = unpackBalls(snap)
    local function movedBalls(x, y)
        local t = {}
        for _, b in ipairs(balls) do
            if b.id == 0 then
                table.insert(t, { id = 0, x = x, y = y, z = 0, pocketed = false })
            else
                table.insert(t, { id = b.id, x = b.x, y = b.y, z = b.z or 0, pocketed = b.pocketed })
            end
        end
        return t
    end

    if snap.breakShot then
        local x = MP.BreakLineX
        local isAI = S.strategy == "Evolutionary AI"
        local ys = (S.strategy == "Multi-ball") and { 0, 3, -3, 6, -6, 9, -9 }
            or (isAI and { 0, 4, -4, 8, -8 } or { 0 })
        if isAI and S.learn then
            local my = memBestBreakY()
            if my then
                local dup = false
                for _, y in ipairs(ys) do if math.abs(y - my) < 0.5 then dup = true end end
                if not dup then table.insert(ys, 1, my) end
            end
        end
        local bPlan, by, bs
        local function tryY(y, budget)
            if not CuePlacement.valid({ geometry = GEO, balls = balls }, x, y, true, 0) then return end
            local fake = {
                id = snap.id, epoch = snap.epoch, turnId = snap.turnId, groups = snap.groups,
                breakShot = true, balls = movedBalls(x, y),
            }
            local plan = planShot(fake, team, budget)
            local sc = plan and plan.score or 0
            if not bs or sc > bs then bs, bPlan, by = sc, plan, y end
        end
        if isAI then
            for _, y in ipairs(ys) do tryY(y, math.max(0.6, S.budget * 0.5 / #ys)) end
            if by then tryY(by, math.max(1.0, S.budget * 0.5)) end
        else
            for _, y in ipairs(ys) do tryY(y, math.max(0.8, S.budget / #ys)) end
        end
        if bPlan then return x, by, bPlan end
        return nil
    end

    local scored, count = {}, 0
    local x = -halfL + 3
    while x <= halfL - 3 do
        local y = -halfW + 3
        while y <= halfW - 3 do
            local st = { geometry = GEO, balls = balls, groups = snap.groups, team = team, phase = {} }
            if CuePlacement.valid(st, x, y, false, 0) then
                local nst = { geometry = GEO, balls = movedBalls(x, y), groups = snap.groups, team = team, phase = {} }
                local ok, cands = pcall(ShotFinder.candidates, nst, x, y)
                if ok and cands and #cands > 0 then
                    local sum = 0
                    for i = 1, math.min(3, #cands) do sum += cands[i].score end
                    table.insert(scored, { x = x, y = y, q = sum })
                end
            end
            y += 3
        end
        x += 3
        count += 1
        if count % 4 == 0 then task.wait() end
    end
    table.sort(scored, function(a, b) return a.q > b.q end)

    local bestPlan, bx, by, bs
    for i = 1, math.min(4, #scored) do
        local p = scored[i]
        local fake = {
            id = snap.id, epoch = snap.epoch, turnId = snap.turnId, groups = snap.groups,
            breakShot = false, calledPocket = snap.calledPocket, balls = movedBalls(p.x, p.y),
        }
        local plan = planShot(fake, team, math.min(S.budget, 1.2))
        if plan then
            local sc = (plan.score or 0) + (plan.safe and -2000 or 0)
            if not bs or sc > bs then bs, bestPlan, bx, by = sc, plan, p.x, p.y end
        end
        task.wait()
    end
    if bestPlan then return bx, by, bestPlan end
    if scored[1] then return scored[1].x, scored[1].y, nil end
    return nil
end

H.planShot = planShot
H.choosePlacement = choosePlacement

local function fire(snap, shot, cueX, cueY)
    local balls = unpackBalls(snap)
    local cue = findBall(balls, 0)
    Net.ShotFired:FireServer({
        epoch = snap.epoch, turnId = snap.turnId, tableId = snap.id,
        angle = shot.angle, power = math.clamp(shot.power, Config.Input.MinPowerToShoot, 1),
        spin = shot.spin or { x = 0, y = 0 }, elevation = ELEV,
        cueX = cueX or (cue and cue.x), cueY = cueY or (cue and cue.y),
    })
end
local function placeCue(snap, x, y)
    Net.MatchAction:FireServer({
        kind = "Place", tableId = snap.id, epoch = snap.epoch, turnId = snap.turnId, x = x, y = y, seq = 1,
    })
end
local function callPocket(snap, pocket)
    Net.MatchAction:FireServer({
        kind = "Pocket", tableId = snap.id, epoch = snap.epoch, turnId = snap.turnId, pocket = pocket,
    })
end

local function humanizeShot(shot)
    local s = { angle = shot.angle, power = shot.power, spin = shot.spin }
    if S.angleNoise > 0 then s.angle += math.rad(gauss() * S.angleNoise) end
    if S.powerNoise > 0 then s.power = math.clamp(s.power * (1 + gauss() * S.powerNoise / 100), Config.Input.MinPowerToShoot, 1) end
    if S.missChance > 0 and math.random() * 100 < S.missChance then
        s.angle += math.rad((math.random() < 0.5 and -1 or 1) * (1.2 + math.random() * 1.5))
    end
    return s
end

local function execute(snap, team, entry)
    local phase = snap.phase
    if S.humanize then task.wait(S.delayMin + math.random() * math.max(0, S.delayMax - S.delayMin)) end

    if phase == "PocketChoice" then
        if S.autoPocket and entry.pocket then
            callPocket(snap, entry.pocket)
            note("Pocket", "Called for the 8: " .. tostring(entry.pocket))
        end
        return
    end

    local plan = entry.plan
    if not plan then
        note("No shot", "No valid shot found")
        return
    end

    local cx, cy
    if phase == "Placement" then
        if not S.autoPlace or not entry.px then return end
        placeCue(snap, entry.px, entry.py)
        cx, cy = entry.px, entry.py
        task.wait(0.35)
    end

    local shot = humanizeShot(plan)
    if phase ~= "Placement" and S.mouseAim then
        pcall(function() rotateTo(snap.id, shot.angle) end)
        task.wait(0.10)
    end

    if S.action == "Auto" then
        fire(snap, shot, cx, cy)
        H.stats.shots += 1
        if S.learn then
            local pend = {
                t = os.clock(), tableId = snap.id, turnId = snap.turnId, kind = plan.kind, pred = plan.pred,
                isBreak = snap.breakShot == true, power = shot.power, spin = shot.spin, score = plan.score,
            }
            if pend.isBreak and cy then
                local balls = unpackBalls(snap)
                local apex = findBall(balls, 1)
                if apex then
                    pend.y = cy
                    pend.off = wrap(shot.angle - math.atan2(apex.y - cy, apex.x - cx))
                end
            end
            H.pending = pend
        end
        local title = plan.count and (plan.kind .. " x" .. plan.count) or plan.kind
        note(title, string.format("ball %s pocket %s power %.2f", tostring(plan.ball), tostring(plan.pocket), shot.power))
        log(string.format("%s ball=%s pocket=%s ang=%.4f pow=%.3f", plan.kind, tostring(plan.ball), tostring(plan.pocket), shot.angle, shot.power))
    end
end

local function turnKey(snap)
    return table.concat({ snap.id, snap.epoch or 0, snap.turnId or 0, snap.phase }, ":")
end

local function computeEntry(snap, team)
    local entry = { status = "computing", t = os.clock() }
    local phase = snap.phase
    if phase == "Placement" then
        local px, py, plan = choosePlacement(snap, team)
        entry.px, entry.py, entry.plan = px, py, plan
    elseif phase == "PocketChoice" then
        local plan = planShot({ id = snap.id, epoch = snap.epoch, turnId = snap.turnId, balls = snap.balls, groups = snap.groups }, team)
        if plan and plan.ball == 8 and plan.pocket then
            entry.pocket = plan.pocket
        else
            local ok, p = pcall(ShotFinder.eightPocket, GEO, unpackBalls(snap))
            if ok then entry.pocket = p end
        end
        entry.plan = plan
    else
        entry.plan = planShot(snap, team)
    end
    entry.status = "ready"
    return entry
end

local function pruneCache()
    local n = 0
    for _ in pairs(H.plans) do n += 1 end
    if n > 10 then
        local oldestK, oldestT
        for k, e in pairs(H.plans) do
            if not oldestT or (e.t or 0) < oldestT then oldestK, oldestT = k, e.t or 0 end
        end
        if oldestK then H.plans[oldestK] = nil end
    end
end

H.conns[#H.conns + 1] = Net.ShotRejected.OnClientEvent:Connect(function(reason)
    log("Shot rejected: " .. tostring(reason))
    local k = H.lastKey
    if k then
        H.retries[k] = (H.retries[k] or 0) + 1
        if H.retries[k] <= 2 then H.done[k] = nil end
    end
end)

function H.replan()
    local snap = mySeat()
    if snap then
        H.plans[turnKey(snap)] = nil
        H.done[turnKey(snap)] = nil
    end
end

task.spawn(function()
    while H.running do
        task.wait(0.15)
        if H.busy then continue end
        local snap, team = mySeat()
        if not snap or snap.shooter ~= lp.UserId then continue end
        local phase = snap.phase
        local actionable = phase == "Aiming" or phase == "PocketChoice" or (phase == "Placement" and snap.ballInHand == true)
        if not actionable then continue end

        local key = turnKey(snap)
        local entry = H.plans[key]
        if not entry then
            if S.enabled or S.showPlan then
                H.busy = true
                H.plans[key] = { status = "computing", t = os.clock() }
                pruneCache()
                task.spawn(function()
                    local ok, res = pcall(computeEntry, snap, team)
                    if ok then
                        H.plans[key] = res
                    else
                        H.plans[key] = { status = "ready", t = os.clock() }
                        log("Error while computing: " .. tostring(res))
                    end
                    H.busy = false
                end)
            end
        elseif entry.status == "ready" and S.enabled and S.action ~= "Suggest only" and not H.done[key] then
            H.done[key] = true
            H.lastKey = key
            H.busy = true
            task.spawn(function()
                local ok, err = pcall(execute, snap, team, entry)
                if not ok then log("Error while executing: " .. tostring(err)) end
                H.busy = false
            end)
        end
    end
end)

local folder = Instance.new("Folder")
folder.Name = "Ball8HubLines"
folder.Parent = workspace

local function mkPart(name)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Material = Enum.Material.Neon
    p.Transparency = 1
    p.Size = Vector3.new(0.1, 0.1, 0.1)
    p.Parent = folder
    return p
end
local P = {
    planCue = mkPart("PlanCue"), planObj = mkPart("PlanObject"), planBounce = mkPart("PlanBounce"),
    planPocket = mkPart("PlanPocket"), planGhost = mkPart("PlanGhost"),
    aimCue = mkPart("AimCue"), aimObj = mkPart("AimObject"), aimBounce = mkPart("AimBounce"), aimGhost = mkPart("AimGhost"),
}
local heightInches = Config.Guideline.HeightAboveClothInches or 0.5

local function hideGroup(prefix)
    for k, p in pairs(P) do
        if string.sub(k, 1, #prefix) == prefix then p.Transparency = 1 end
    end
end
local function setLine(part, pl, ax, ay, bx, by, color, alpha)
    local x1, y1, z1 = Placement.toWorld(pl, ax, ay, heightInches)
    local x2, y2, z2 = Placement.toWorld(pl, bx, by, heightInches)
    local a, b = Vector3.new(x1, y1, z1), Vector3.new(x2, y2, z2)
    local len = (b - a).Magnitude
    if len < 0.02 then part.Transparency = 1 return end
    part.Color = color
    part.Size = Vector3.new(S.thickness, S.thickness, len)
    part.CFrame = CFrame.lookAt((a + b) / 2, b)
    part.Transparency = alpha or 0.1
end
local function setDot(part, pl, x, y, color, scale)
    local wx, wy, wz = Placement.toWorld(pl, x, y, heightInches)
    part.Color = color
    local sz = S.thickness * (scale or 3)
    part.Size = Vector3.new(sz, sz, sz)
    part.CFrame = CFrame.new(wx, wy, wz)
    part.Transparency = 0.1
end

local function drawTrace(prefix, st, pl, angle, color, pocket)
    local tr = Aim.trace(st, { angle = angle, power = 0.5, spin = { x = 0, y = 0 }, elevation = ELEV }, 1)
    if tr.contact == "none" then hideGroup(prefix) return end
    local cueLine, objLine, bounce, ghost = P[prefix .. "Cue"], P[prefix .. "Obj"], P[prefix .. "Bounce"], P[prefix .. "Ghost"]
    setLine(cueLine, pl, tr.startX, tr.startY, tr.ghostX, tr.ghostY, color, 0.1)
    setDot(ghost, pl, tr.ghostX, tr.ghostY, Color3.fromRGB(255, 80, 80))
    local lines = Aim.fullLines(st, tr)
    if tr.contact == "ball" and tr.objectId then
        local obj = findBall(st.balls, tr.objectId)
        if obj and lines.object then
            setLine(objLine, pl, obj.x, obj.y, obj.x + tr.objectDirX * lines.object, obj.y + tr.objectDirY * lines.object, Color3.fromRGB(255, 170, 0), 0.1)
        else
            objLine.Transparency = 1
        end
    else
        objLine.Transparency = 1
    end
    if lines.cue and (tr.cueDirX ~= 0 or tr.cueDirY ~= 0) then
        setLine(bounce, pl, tr.ghostX, tr.ghostY, tr.ghostX + tr.cueDirX * lines.cue, tr.ghostY + tr.cueDirY * lines.cue, Color3.fromRGB(0, 220, 255), 0.15)
    else
        bounce.Transparency = 1
    end
end

H.conns[#H.conns + 1] = RunService.RenderStepped:Connect(function()
    if not H.running then return end
    local snap, team = mySeat()
    if not snap or (not S.showPlan and not S.showAim) then hideGroup("plan") hideGroup("aim") return end
    local pl = Placement.forTable(snap.id)
    if not pl then hideGroup("plan") hideGroup("aim") return end
    local st = { geometry = GEO, balls = unpackBalls(snap) }

    if S.showAim and snap.phase == "Aiming" then
        local a = currentAim(snap.id)
        if a then pcall(drawTrace, "aim", st, pl, a, S.aimColor) else hideGroup("aim") end
    else
        hideGroup("aim")
    end

    local entry = H.plans[turnKey(snap)]
    if S.showPlan and snap.shooter == lp.UserId and snap.phase == "Aiming" and entry and entry.plan and entry.plan.angle then
        pcall(drawTrace, "plan", st, pl, entry.plan.angle, S.planColor)
        if entry.plan.pocket then
            for _, pk in ipairs(GEO.pockets) do
                if pk.id == entry.plan.pocket then setDot(P.planPocket, pl, pk.x, pk.y, S.planColor, 6) end
            end
        else
            P.planPocket.Transparency = 1
        end
    else
        hideGroup("plan")
        P.planPocket.Transparency = 1
    end
end)

H.conns[#H.conns + 1] = UIS.InputBegan:Connect(function(io, gp)
    if gp then return end
    local n = io.KeyCode.Name
    if n == KEYS.toggle then
        S.enabled = not S.enabled
        note("Aimbot", S.enabled and "ENABLED" or "DISABLED")
        if H.setToggle then pcall(H.setToggle, S.enabled) end
    elseif n == KEYS.replan then
        H.replan()
        note("Replanning", "Recomputing the shot")
    elseif n == KEYS.lines then
        S.showPlan = not S.showPlan
    end
end)

function H.destroy()
    H.running = false
    memDirty = true
    memSave(true)
    for _, c in ipairs(H.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() folder:Destroy() end)
    for k, v in pairs(finderOrig) do pcall(function() Finder[k] = v end) end
    if H.window then pcall(function() H.window:Destroy() end) end
    log("Hub unloaded.")
end


----------------------------------------------------------------
-- LiteUI  (same pattern as your v0.0.4 example)
----------------------------------------------------------------
local Lite = getgenv().Lite or _G.Lite
assert(type(Lite) == "table" and type(Lite.new) == "function", "LiteUI failed to load")

local ui = Lite.new({
    Name = "8BallHub",
    Key = Enum.KeyCode.RightAlt,
    Theme = "dark",
    Save = true,
    SaveFile = "bola8hub_liteui.json",
})
H.ui = ui
H.window = ui

-- Header card (matches your example layout)
local card = ui:Card({
    Title = "8 Ball Hub",
    Subtitle = "Aimbot · solver · guides",
    Value = "OFF",
    Tone = "accent",
})

-- Tabs: first return = panels table (see your example: local tab, tabs = ui:Tabs)
local tab = ui:Tabs(
    { "Aimbot", "Shots", "AI", "Multi", "Precision", "Lines", "Settings" },
    { MaxHeight = 250, Default = "Aimbot" }
)

----------------------------------------------------------------
-- Aimbot
----------------------------------------------------------------
do
    local main = tab.Aimbot
    main:Section("Main control")
    main:Toggle({
        Name = "Enable aimbot",
        Flag = "enabled",
        Default = false,
        Callback = function(v)
            S.enabled = v
            card:Set({ Value = v and "ON" or "OFF" })
            card:SetTone(v and "accent" or "sub")
            note("Aimbot", v and "ENABLED" or "DISABLED")
        end,
    })
    H.setToggle = function(v)
        S.enabled = v
        card:Set({ Value = v and "ON" or "OFF" })
    end
    main:Dropdown({
        Name = "Action",
        Flag = "action",
        Options = { "Auto", "Aim only", "Suggest only" },
        Default = "Auto",
        Callback = function(v) S.action = v end,
    })
    main:Dropdown({
        Name = "Strategy",
        Flag = "strategy",
        Options = { "Normal", "Aggressive", "Impossible", "Multi-ball", "Evolutionary AI", "Safe" },
        Default = "Normal",
        Callback = function(v)
            S.strategy = v
            applyFinder()
        end,
    })
    main:Separator()
    main:Toggle({ Name = "Auto place cue ball", Flag = "autoPlace", Default = true, Callback = function(v) S.autoPlace = v end })
    main:Toggle({ Name = "Auto call 8 pocket", Flag = "autoPocket", Default = true, Callback = function(v) S.autoPocket = v end })
    main:Toggle({ Name = "Position play", Flag = "usePosition", Default = true, Callback = function(v) S.usePosition = v end })
    main:Toggle({ Name = "Mouse aim", Flag = "mouseAim", Default = true, Callback = function(v) S.mouseAim = v end })
    main:Slider({
        Name = "Break power",
        Flag = "breakPower",
        Min = 0.5, Max = 1, Step = 0.05, Default = 1,
        Callback = function(v) S.breakPower = v end,
    })
    main:Separator()
    main:Button({
        Name = "Replan now (R)",
        Callback = function()
            H.replan()
            note("Replanning", "Recomputing the shot")
        end,
    })
end

----------------------------------------------------------------
-- Shots (Impossible)
----------------------------------------------------------------
do
    local t = tab.Shots
    t:Section("Allowed shot types")
    t:Toggle({ Name = "Bank shots", Flag = "allowBank", Default = true, Callback = function(v) S.allowBank = v end })
    t:Toggle({ Name = "Double bank", Flag = "allowDouble", Default = true, Callback = function(v) S.allowDouble = v end })
    t:Toggle({ Name = "Kick shots", Flag = "allowKick", Default = true, Callback = function(v) S.allowKick = v end })
    t:Toggle({ Name = "Combos", Flag = "allowCombo", Default = true, Callback = function(v) S.allowCombo = v end })
    t:Toggle({ Name = "Fine angle sweep", Flag = "brute", Default = true, Callback = function(v) S.brute = v end })
    t:Separator()
    t:Section("Finder limits")
    t:Slider({ Name = "Sweep resolution", Flag = "bruteStep", Min = 0.1, Max = 2, Step = 0.05, Default = 0.5, Suffix = "°", Callback = function(v) S.bruteStep = v end })
    t:Slider({ Name = "Max compute time", Flag = "budget", Min = 1, Max = 12, Step = 0.5, Default = 4, Suffix = "s", Callback = function(v) S.budget = v end })
    t:Slider({ Name = "Max cut", Flag = "maxCut", Min = 30, Max = 88, Step = 1, Default = 80, Suffix = "°", Callback = function(v) S.maxCut = v applyFinder() end })
    t:Slider({ Name = "Max power", Flag = "maxPower", Min = 0.5, Max = 1, Step = 0.05, Default = 1, Callback = function(v) S.maxPower = v applyFinder() end })
end

----------------------------------------------------------------
-- AI
----------------------------------------------------------------
do
    local t = tab.AI
    t:Section("Evolutionary AI")
    t:Paragraph("Pick strategy “Evolutionary AI” on the Aimbot tab. Tests angles, power and spin in real physics.")
    t:Dropdown({
        Name = "Goal",
        Flag = "aiGoal",
        Options = { "More balls", "Balanced", "Position" },
        Default = "Balanced",
        Callback = function(v) S.aiGoal = v end,
    })
    t:Slider({ Name = "Exploration speed", Flag = "aiMult", Min = 1, Max = 3, Step = 1, Default = 2, Callback = function(v) S.aiMult = v end })
    t:Toggle({ Name = "Allow spin", Flag = "aiSpin", Default = true, Callback = function(v) S.aiSpin = v end })
    t:Separator()
    t:Section("Memory")
    t:Toggle({ Name = "Learn and use memory", Flag = "learn", Default = true, Callback = function(v) S.learn = v end })
    t:Button({
        Name = "View statistics",
        Callback = function()
            local lines = {}
            for kind, k in pairs(Mem.kinds) do
                table.insert(lines, string.format("%s %d/%d", kind, k.ok, k.n))
            end
            table.sort(lines)
            local b = Mem.breaks[1]
            local bt = b and string.format(" | best break: %.1f in, %.1f avg (%d)", b.y, b.pots / b.trials, b.trials) or ""
            note("Memory", string.format("%d shots. %s%s", Mem.shots, #lines > 0 and table.concat(lines, ", ") or "no data", bt))
        end,
    })
    t:Button({
        Name = "Save memory now",
        Callback = function()
            memDirty = true
            memSave(true)
            note("Memory", "Saved")
        end,
    })
    t:Button({
        Name = "Clear memory",
        Tone = "danger",
        Callback = function()
            memClear()
            note("Memory", "Cleared")
        end,
    })
end

----------------------------------------------------------------
-- Multi
----------------------------------------------------------------
do
    local t = tab.Multi
    t:Section("Multi-ball")
    t:Paragraph("Use strategy Multi-ball on Aimbot. Searches for the shot that pots the most balls.")
    t:Slider({ Name = "Sweep resolution", Flag = "multiStep", Min = 0.5, Max = 5, Step = 0.5, Default = 2, Suffix = "°", Callback = function(v) S.multiStep = v end })
    t:Slider({ Name = "Minimum balls", Flag = "multiMin", Min = 1, Max = 6, Step = 1, Default = 2, Callback = function(v) S.multiMin = v end })
    t:Toggle({ Name = "Try spin", Flag = "multiSpin", Default = true, Callback = function(v) S.multiSpin = v end })
end

----------------------------------------------------------------
-- Precision
----------------------------------------------------------------
do
    local t = tab.Precision
    t:Section("Precision control")
    t:Slider({ Name = "Tolerance tests", Flag = "robustChecks", Min = 0, Max = 6, Step = 1, Default = 2, Callback = function(v) S.robustChecks = v end })
    t:Slider({ Name = "Angle error", Flag = "robustEps", Min = 0.02, Max = 0.5, Step = 0.01, Default = 0.1, Suffix = "°", Callback = function(v) S.robustEps = v end })
    t:Toggle({ Name = "Strict mode", Flag = "strict", Default = false, Callback = function(v) S.strict = v end })
    t:Slider({ Name = "Powers per shot", Flag = "powerVariants", Min = 1, Max = 5, Step = 1, Default = 5, Callback = function(v) S.powerVariants = v end })
    t:Slider({ Name = "Position weight", Flag = "positionWeight", Min = 0, Max = 2.5, Step = 0.1, Default = 1, Callback = function(v) S.positionWeight = v end })
    t:Separator()
    t:Section("Spin")
    t:Toggle({ Name = "Use spin for position", Flag = "useSpin", Default = false, Callback = function(v) S.useSpin = v end })
    t:Slider({ Name = "Spin amount", Flag = "spinAmount", Min = 0.1, Max = 1, Step = 0.05, Default = 0.5, Callback = function(v) S.spinAmount = v end })
    t:Separator()
    t:Section("Humanize")
    t:Toggle({ Name = "Random delay", Flag = "humanize", Default = false, Callback = function(v) S.humanize = v end })
    t:Slider({ Name = "Min delay", Flag = "delayMin", Min = 0, Max = 6, Step = 0.1, Default = 0.6, Suffix = "s", Callback = function(v) S.delayMin = v end })
    t:Slider({ Name = "Max delay", Flag = "delayMax", Min = 0, Max = 8, Step = 0.1, Default = 1.6, Suffix = "s", Callback = function(v) S.delayMax = v end })
    t:Slider({ Name = "Angle noise", Flag = "angleNoise", Min = 0, Max = 2, Step = 0.01, Default = 0, Suffix = "°", Callback = function(v) S.angleNoise = v end })
    t:Slider({ Name = "Power noise", Flag = "powerNoise", Min = 0, Max = 15, Step = 0.5, Default = 0, Suffix = "%", Callback = function(v) S.powerNoise = v end })
    t:Slider({ Name = "Miss chance", Flag = "missChance", Min = 0, Max = 50, Step = 1, Default = 0, Suffix = "%", Callback = function(v) S.missChance = v end })
end

----------------------------------------------------------------
-- Lines
----------------------------------------------------------------
do
    local t = tab.Lines
    t:Section("Table guides")
    t:Toggle({ Name = "Show suggested shot (T)", Flag = "showPlan", Default = true, Callback = function(v) S.showPlan = v end })
    t:Toggle({ Name = "Show current aim", Flag = "showAim", Default = false, Callback = function(v) S.showAim = v end })
    t:Slider({ Name = "Thickness", Flag = "thickness", Min = 0.03, Max = 0.3, Step = 0.01, Default = S.thickness, Callback = function(v) S.thickness = v end })
    t:ColorPicker({
        Name = "Plan color",
        Flag = "planColor",
        Default = S.planColor,
        Callback = function(c) S.planColor = c end,
    })
    t:ColorPicker({
        Name = "Aim color",
        Flag = "aimColor",
        Default = S.aimColor,
        Callback = function(c) S.aimColor = c end,
    })
    t:Toggle({ Name = "Notifications", Flag = "notify", Default = true, Callback = function(v) S.notify = v end })
end

----------------------------------------------------------------
-- Settings (built-in Lite settings + hub controls)
----------------------------------------------------------------
ui:Settings({ Panel = tab.Settings })
do
    local t = tab.Settings
    t:Separator()
    t:Section("Hotkeys")
    t:Keybind({
        Name = "Toggle aimbot",
        Flag = "keyToggle",
        Default = Enum.KeyCode.RightShift,
        Callback = function(v) KEYS.toggle = keyName(v) end,
    })
    t:Keybind({
        Name = "Replan",
        Flag = "keyReplan",
        Default = Enum.KeyCode.R,
        Callback = function(v) KEYS.replan = keyName(v) end,
    })
    t:Keybind({
        Name = "Show / hide lines",
        Flag = "keyLines",
        Default = Enum.KeyCode.T,
        Callback = function(v) KEYS.lines = keyName(v) end,
    })
    t:Separator()
    t:Section("Hub")
    t:Paragraph("RightAlt toggles this UI. Aimbot starts disabled.")
    t:Button({
        Name = "Unload hub",
        Tone = "danger",
        Callback = function()
            H.destroy()
        end,
    })
    t:Paragraph("Solver: 8 Ball Hub · UI: LiteUI (your v0.0.4)")
end

ui:OnDestroy(function()
    if H.running then
        pcall(function()
            H.running = false
            memDirty = true
            memSave(true)
            for _, c in ipairs(H.conns) do
                pcall(function() c:Disconnect() end)
            end
            pcall(function()
                if folder then folder:Destroy() end
            end)
            for k, v in pairs(finderOrig) do
                pcall(function() Finder[k] = v end)
            end
        end)
    end
end)

function H.destroy()
    H.running = false
    memDirty = true
    memSave(true)
    for _, c in ipairs(H.conns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        if folder then folder:Destroy() end
    end)
    for k, v in pairs(finderOrig) do
        pcall(function() Finder[k] = v end)
    end
    if H.ui then
        local u = H.ui
        H.ui, H.window = nil, nil
        pcall(function() u:Destroy() end)
    end
    log("Hub unloaded.")
end

ui:Show()
ui:Notify({
    Title = "8 Ball Hub",
    Text = "LiteUI loaded. Aimbot OFF · RightAlt hides UI · RightShift toggles aimbot.",
    Duration = 5,
    Tone = "accent",
})

log("Hub loaded (LiteUI). Aimbot DISABLED by default.")
return "8Ball Hub loaded (LiteUI)"
