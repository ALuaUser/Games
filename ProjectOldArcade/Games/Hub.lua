--[[
    OldArcade  -  Hub
    The launcher. Upload Hub.lua, Snake.lua and Minesweeper.lua to the same folder of a
    public GitHub repo, set BASE below, then run:

        loadstring(game:HttpGet("https://raw.githubusercontent.com/YOU/REPO/main/Hub.lua"))()

    Picking a game downloads that game's file with loadstring and removes the hub.
    The game's "‹ Hub" button downloads this hub again and removes the game.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- Theme + helpers
----------------------------------------------------------------
local Theme = {
    bg = Color3.fromRGB(20, 21, 24),
    panel = Color3.fromRGB(30, 31, 36),
    track = Color3.fromRGB(46, 48, 55),
    line = Color3.fromRGB(255, 255, 255),
    text = Color3.fromRGB(236, 237, 240),
    sub = Color3.fromRGB(135, 139, 148),
    accent = Color3.fromRGB(120, 200, 150),
    warn = Color3.fromRGB(224, 175, 104),
    danger = Color3.fromRGB(228, 108, 108),
    blue = Color3.fromRGB(104, 160, 228),
    purple = Color3.fromRGB(176, 136, 234),
    gold = Color3.fromRGB(242, 202, 92),
    orange = Color3.fromRGB(238, 150, 84),
    apple = Color3.fromRGB(236, 88, 88),
    rock = Color3.fromRGB(86, 90, 100),
}

local FONT = Enum.Font.BuilderSans
local FONT_M = Enum.Font.BuilderSansMedium
local FONT_B = Enum.Font.BuilderSansBold
local FONT_XB = Enum.Font.BuilderSansExtraBold

local QUAD = Enum.EasingStyle.Quad
local QUINT = Enum.EasingStyle.Quint
local BACK = Enum.EasingStyle.Back
local OUT = Enum.EasingDirection.Out
local IN = Enum.EasingDirection.In
local CENTER = Enum.TextXAlignment.Center
local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right

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

local function corner(obj, r)
    return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, obj)
end

local function round(obj)
    return make("UICorner", { CornerRadius = UDim.new(1, 0) }, obj)
end

local function stroke(obj, color, transparency, thickness)
    return make("UIStroke", {
        Color = color or Theme.line,
        Transparency = transparency or 0.9,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function label(parent, o)
    return make("TextLabel", {
        BackgroundTransparency = 1,
        Position = o.Position or UDim2.new(),
        Size = o.Size or UDim2.fromScale(1, 1),
        AnchorPoint = o.AnchorPoint or Vector2.zero,
        Font = o.Font or FONT,
        TextSize = o.TextSize or 14,
        TextColor3 = o.Color or Theme.text,
        TextXAlignment = o.XAlign or LEFT,
        TextYAlignment = o.YAlign or Enum.TextYAlignment.Center,
        TextWrapped = o.Wrapped or false,
        RichText = o.RichText or false,
        Text = o.Text or "",
        ZIndex = o.ZIndex or 1,
        Visible = o.Visible ~= false,
    }, parent)
end

local function button(parent, o, callback)
    local base = o.Color or Theme.track
    local hover = o.Hover or base:Lerp(Color3.new(1, 1, 1), 0.12)
    local ts = o.TextSize or 14
    local b = make("TextButton", {
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = base,
        Position = o.Position or UDim2.new(),
        Size = o.Size or UDim2.fromOffset(100, 28),
        AnchorPoint = o.AnchorPoint or Vector2.zero,
        Font = o.Font or FONT_B,
        TextSize = ts,
        TextColor3 = o.TextColor or Theme.text,
        Text = o.Text or "",
        ZIndex = o.ZIndex or 1,
        Visible = o.Visible ~= false,
    }, parent)
    corner(b, o.Radius or 8)
    local down = false
    b.MouseEnter:Connect(function()
        tween(b, { BackgroundColor3 = hover }, 0.12)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { BackgroundColor3 = base }, 0.2)
        if down then
            down = false
            tween(b, { TextSize = ts }, 0.3, BACK)
        end
    end)
    b.MouseButton1Down:Connect(function()
        down = true
        tween(b, { TextSize = ts - 2 }, 0.07)
    end)
    b.MouseButton1Up:Connect(function()
        if down then
            down = false
            tween(b, { TextSize = ts }, 0.35, BACK)
        end
    end)
    if callback then
        b.MouseButton1Click:Connect(callback)
    end
    return b
end

----------------------------------------------------------------
-- Save data (high scores, settings)
----------------------------------------------------------------
local Store = { data = {}, token = 0, file = "OldArcade_Saves.json", attr = "OldArcade_Saves" }

function Store:load()
    local raw
    if type(isfile) == "function" and type(readfile) == "function" then
        local ok, res = pcall(function()
            if isfile(self.file) then
                return readfile(self.file)
            end
        end)
        if ok then
            raw = res
        end
    end
    if not raw then
        raw = player:GetAttribute(self.attr)
    end
    if type(raw) == "string" then
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok and type(data) == "table" then
            self.data = data
        end
    end
end

function Store:get(key, default)
    local v = self.data[key]
    if v == nil then
        return default
    end
    return v
end

function Store:set(key, value)
    self.data[key] = value
    self.token += 1
    local mine = self.token
    task.delay(0.5, function()
        if mine ~= self.token then
            return
        end
        local ok, raw = pcall(HttpService.JSONEncode, HttpService, self.data)
        if not ok then
            return
        end
        pcall(player.SetAttribute, player, self.attr, raw)
        if type(writefile) == "function" then
            pcall(writefile, self.file, raw)
        end
    end)
end

Store:load()


local ENV = (getgenv and getgenv()) or _G

----------------------------------------------------------------
-- CONFIG  -  point BASE at the raw folder of your GitHub repo (keep the trailing "/")
--            e.g. https://raw.githubusercontent.com/MyName/MyRepo/main/
----------------------------------------------------------------
local BASE = "https://raw.githubusercontent.com/ALuaUser/Games/refs/heads/main/ProjectOldArcade/Games/"

local GAMES = {
    {
        Name = "Snake",
        File = "Snake.lua",
        Letter = "S",
        Accent = Theme.accent,
        Desc = "Eat, grow, don't crash. 3 modes, power-ups, bonus gems and high scores.",
    },
    {
        Name = "Minesweeper",
        File = "Minesweeper.lua",
        Letter = "M",
        Accent = Theme.blue,
        Desc = "Classic rules: chording, ? marks, hints, 3BV and best times.",
    },
    { Name = "Tetris", Letter = "T", Accent = Theme.purple, Desc = "Stack the blocks, clear the lines." },
    { Name = "Pong", Letter = "P", Accent = Theme.warn, Desc = "The one that started it all." },
    { Name = "Breakout", Letter = "B", Accent = Theme.danger, Desc = "Smash every brick with the ball." },
    { Name = "2048", Letter = "2", Accent = Theme.orange, Desc = "Slide and merge your way to 2048." },
}
-- (to add a game: upload GameName.lua to the repo and add an entry with File = "GameName.lua")

-- games read this to find their way back here
ENV.OldArcade = { Base = BASE, Hub = BASE .. "Hub.lua" }

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
for _, n in ipairs({ "OldArcade_Hub", "OldArcade_Snake", "OldArcade_Minesweeper" }) do
    local o = playerGui:FindFirstChild(n)
    if o then
        o:Destroy()
    end
end

local gui = make("ScreenGui", {
    Name = "OldArcade_Hub",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 200,
}, playerGui)

local W, H = 620, 440
local win = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, -12),
    Size = UDim2.fromOffset(W, H),
    BackgroundColor3 = Theme.bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)
corner(win, 12)
stroke(win, Theme.line, 0.88)
local uiScale = make("UIScale", { Scale = 1 }, win)

local function fitScale()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    return math.clamp(math.min((vp.X - 20) / W, (vp.Y - 20) / H), 0.4, 1)
end
local baseScale = fitScale()
uiScale.Scale = baseScale * 0.93
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        baseScale = fitScale()
        uiScale.Scale = baseScale
    end)
end

local top = make("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Theme.panel,
    BorderSizePixel = 0,
    ZIndex = 5,
}, win)
label(top, {
    Text = "ARCADE",
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -150, 1, 0),
    Font = FONT_XB,
    TextSize = 16,
    ZIndex = 6,
})

local closing = false
local function closeHub()
    if closing then
        return
    end
    closing = true
    tween(uiScale, { Scale = baseScale * 0.94 }, 0.2, QUAD, IN)
    task.delay(0.22, function()
        if gui.Parent then
            gui:Destroy()
        end
    end)
end

button(top, {
    Text = "×",
    TextSize = 20,
    Position = UDim2.new(1, -38, 0, 6),
    Size = UDim2.fromOffset(28, 28),
    Color = Theme.panel,
    Hover = Theme.danger,
    ZIndex = 6,
}, closeHub)

local dragging
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = { input = input, start = Vector2.new(input.Position.X, input.Position.Y), pos = win.Position }
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input == dragging.input or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = Vector2.new(input.Position.X, input.Position.Y) - dragging.start
        win.Position = UDim2.new(
            dragging.pos.X.Scale,
            dragging.pos.X.Offset + d.X,
            dragging.pos.Y.Scale,
            dragging.pos.Y.Offset + d.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if dragging and (input == dragging.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging = nil
    end
end)

label(win, {
    Text = "Choose a game",
    Position = UDim2.fromOffset(20, 54),
    Size = UDim2.fromOffset(300, 24),
    Font = FONT_B,
    TextSize = 20,
})
label(win, {
    Text = "Classic arcade games, rebuilt from scratch.",
    Position = UDim2.fromOffset(20, 78),
    Size = UDim2.fromOffset(400, 18),
    TextSize = 14,
    Color = Theme.sub,
})

local grid = make("ScrollingFrame", {
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 110),
    Size = UDim2.fromOffset(W, H - 110 - 34),
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.sub,
    ScrollBarImageTransparency = 0.4,
}, win)
make("UIGridLayout", {
    CellSize = UDim2.fromOffset(184, 116),
    CellPadding = UDim2.fromOffset(12, 12),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)
make("UIPadding", {
    PaddingLeft = UDim.new(0, 20),
    PaddingRight = UDim.new(0, 20),
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 16),
}, grid)

local statusLbl = label(win, {
    Position = UDim2.fromOffset(20, H - 28),
    Size = UDim2.fromOffset(W - 40, 20),
    TextSize = 13,
    Color = Theme.sub,
})
local function setStatus(text, color)
    statusLbl.Text = text
    statusLbl.TextColor3 = color or Theme.sub
end
if BASE:find("YOUR_USERNAME", 1, true) then
    setStatus("Edit BASE at the top of Hub.lua to point at your GitHub repo.", Theme.warn)
end

----------------------------------------------------------------
-- LAUNCHING A GAME (download -> compile -> remove hub -> run)
----------------------------------------------------------------
local busy = false
local function launch(g)
    if busy then
        return
    end
    busy = true
    setStatus("Loading " .. g.Name .. "...", Theme.sub)
    task.spawn(function()
        local ok, body = pcall(function()
            return game:HttpGet(BASE .. g.File .. "?t=" .. os.time())
        end)
        if not ok or type(body) ~= "string" or #body < 50 then
            setStatus("Couldn't download " .. g.File .. ". Check BASE and that the repo is public.", Theme.danger)
            busy = false
            return
        end
        if body:sub(1, 3) == "404" then
            setStatus(g.File .. " was not found (404). Check the file name in your repo.", Theme.danger)
            busy = false
            return
        end
        local fn, err = loadstring(body)
        if not fn then
            setStatus("Script error in " .. g.File .. ": " .. tostring(err), Theme.danger)
            busy = false
            return
        end
        if gui.Parent then
            gui:Destroy()
        end
        task.spawn(fn)
    end)
end

local function makeCard(g, order)
    local playable = g.File ~= nil
    local c = make("TextButton", {
        AutoButtonColor = false,
        Text = "",
        BackgroundColor3 = Theme.panel,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, grid)
    corner(c, 12)
    local st = stroke(c, Theme.line, 0.9)

    local icon = make("Frame", {
        Position = UDim2.fromOffset(14, 14),
        Size = UDim2.fromOffset(40, 40),
        BackgroundColor3 = g.Accent,
        BackgroundTransparency = playable and 0 or 0.75,
        BorderSizePixel = 0,
    }, c)
    corner(icon, 10)
    label(icon, {
        Text = g.Letter,
        Font = FONT_XB,
        TextSize = 22,
        Color = playable and Color3.fromRGB(18, 22, 20) or g.Accent,
        XAlign = CENTER,
    })
    label(c, {
        Text = g.Name,
        Position = UDim2.fromOffset(64, 14),
        Size = UDim2.fromOffset(110, 22),
        Font = FONT_B,
        TextSize = 17,
        Color = playable and Theme.text or Theme.sub,
    })
    label(c, {
        Text = playable and "Playable" or "Coming soon",
        Position = UDim2.fromOffset(64, 36),
        Size = UDim2.fromOffset(110, 16),
        TextSize = 12,
        Font = FONT_B,
        Color = playable and Theme.accent or Theme.sub,
    })
    label(c, {
        Text = g.Desc,
        Position = UDim2.fromOffset(14, 62),
        Size = UDim2.fromOffset(156, 46),
        TextSize = 12,
        Color = Theme.sub,
        Wrapped = true,
        YAlign = Enum.TextYAlignment.Top,
    })

    c.MouseEnter:Connect(function()
        tween(st, { Transparency = playable and 0.6 or 0.8, Color = playable and g.Accent or Theme.line }, 0.2)
        tween(c, { BackgroundColor3 = Theme.panel:Lerp(Color3.new(1, 1, 1), 0.04) }, 0.2)
    end)
    c.MouseLeave:Connect(function()
        tween(st, { Transparency = 0.9, Color = Theme.line }, 0.25)
        tween(c, { BackgroundColor3 = Theme.panel }, 0.25)
    end)
    c.Activated:Connect(function()
        if playable then
            launch(g)
        else
            for i, dx in ipairs({ 4, -4, 3, -3, 0 }) do
                task.delay((i - 1) * 0.04, function()
                    icon.Position = UDim2.fromOffset(14 + dx, 14)
                end)
            end
        end
    end)
end

for i, g in ipairs(GAMES) do
    makeCard(g, i)
end

tween(win, { Position = UDim2.fromScale(0.5, 0.5) }, 0.55, QUINT)
tween(uiScale, { Scale = baseScale }, 0.6, BACK)
