--[[
    OldArcade  -  Snake
    Standalone game file. Run it from the Hub (Hub.lua), or directly with:
        loadstring(game:HttpGet("<raw url of Snake.lua>"))()

    Controls   WASD / Arrow keys / D-Pad / swipe / on-screen arrows (touch)
               P or Space = pause      R = restart      Enter = start
    Modes      Classic / Wrap / Obstacles      Speeds  Slow / Normal / Fast / Insane
    Food       Apple, bonus gem, power-ups (slow-mo, ghost, 2x score, shrink)
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

----------------------------------------------------------------
-- SNAKE
----------------------------------------------------------------
local function SnakeGame(ctx)
    local root = ctx.Parent -- 620 x 400
    local store = ctx.Store
    local alive = true
    local conns = {}
    local rng = Random.new()

    local function connect(signal, fn)
        conns[#conns + 1] = signal:Connect(fn)
    end

    ------------------------------------------------------------
    -- Settings
    ------------------------------------------------------------
    local MODES = { "Classic", "Wrap", "Obstacles" }
    local MODE_DESC = {
        Classic = "Walls are deadly. The original.",
        Wrap = "Walls teleport you to the other side.",
        Obstacles = "Deadly walls plus rocks that multiply.",
    }
    local MODE_COLOR = { Classic = Theme.danger, Wrap = Theme.blue, Obstacles = Theme.warn }
    local SPEED_NAMES = { "Slow", "Normal", "Fast", "Insane" }
    local SPEED_BASE = { Slow = 0.17, Normal = 0.125, Fast = 0.092, Insane = 0.065 }
    local SIZES = { 15, 20, 26 }
    local SIZE_NAMES = { "Small  (15x15)", "Medium  (20x20)", "Large  (26x26)" }

    local POWERS = {
        slow = { name = "SLOW-MO", color = Theme.blue, glyph = "S", dur = 8 },
        ghost = { name = "GHOST", color = Theme.purple, glyph = "G", dur = 6 },
        double = { name = "2x SCORE", color = Theme.gold, glyph = "2x", dur = 10 },
        shrink = { name = "SHRINK", color = Theme.orange, glyph = "-", dur = 0 },
    }
    local POWER_LIST = { "slow", "ghost", "double", "shrink" }
    local FX_ORDER = { "ghost", "double", "slow" }

    local saved = store:get("snake.cfg", {})
    local cfg = {
        mode = (saved.mode and table.find(MODES, saved.mode)) and saved.mode or "Classic",
        speed = (saved.speed and SPEED_BASE[saved.speed]) and saved.speed or "Normal",
        size = (saved.size and SIZES[saved.size]) and saved.size or 2,
    }

    local HEAD_COLOR = Color3.fromRGB(160, 236, 186)
    local TAIL_COLOR = Color3.fromRGB(62, 142, 100)
    local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

    ------------------------------------------------------------
    -- Game state
    ------------------------------------------------------------
    local state = "menu" -- menu | countdown | playing | paused | over
    local N, cell, pad = 20, 18, 1
    local board, boardStroke
    local segs, eyes, pupils, headScale = {}, {}, {}, nil
    local body, prevBody = {}, {}
    local dir = { x = 1, y = 0 }
    local queue = {}
    local occ = {}
    local rocks, rockFrames, rockCount = {}, {}, 0
    local food, bonus, power
    local score, foods, level, sinceBonus = 0, 0, 1, 0
    local best, newBest = 0, false
    local gt, acc = 0, 0
    local fx, fxDur = { slow = 0, ghost = 0, double = 0 }, { slow = 1, ghost = 1, double = 1 }
    local ghostShown = false
    local cdToken = 0
    local chips = {}

    -- forward declarations
    local setupGame, showOverlay, hideOverlay, countdown, die, updateHUD, startGame
    local pause, resume, toMenu, updateButtons, buildBoard

    local function active(name)
        return fx[name] > gt
    end

    local function bestKey()
        return "snake.best." .. cfg.mode .. "." .. cfg.speed .. "." .. SIZES[cfg.size]
    end

    ------------------------------------------------------------
    -- Sidebar (HUD)
    ------------------------------------------------------------
    local side = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 16),
        Size = UDim2.fromOffset(186, 368),
    }, root)

    label(side, {
        Text = "SNAKE",
        TextSize = 24,
        Font = FONT_XB,
        Color = Theme.accent,
        Size = UDim2.new(1, 0, 0, 28),
    })
    local modeLbl = label(side, {
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 0, 16),
        TextSize = 13,
        Color = Theme.sub,
    })

    local scoreCard = make("Frame", {
        Position = UDim2.fromOffset(0, 54),
        Size = UDim2.fromOffset(186, 76),
        BackgroundColor3 = Theme.panel,
        BorderSizePixel = 0,
    }, side)
    corner(scoreCard, 10)
    label(scoreCard, {
        Text = "SCORE",
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.fromOffset(100, 14),
        TextSize = 12,
        Font = FONT_B,
        Color = Theme.sub,
    })
    local scoreLbl = label(scoreCard, {
        Text = "0",
        Position = UDim2.fromOffset(14, 22),
        Size = UDim2.fromOffset(158, 46),
        TextSize = 40,
        Font = FONT_XB,
    })

    local function miniStat(x, title)
        local f = make("Frame", {
            Position = UDim2.fromOffset(x, 138),
            Size = UDim2.fromOffset(58, 46),
            BackgroundColor3 = Theme.panel,
            BorderSizePixel = 0,
        }, side)
        corner(f, 8)
        label(f, {
            Text = title,
            Position = UDim2.fromOffset(0, 6),
            Size = UDim2.new(1, 0, 0, 12),
            TextSize = 11,
            Font = FONT_B,
            Color = Theme.sub,
            XAlign = CENTER,
        })
        return label(f, {
            Text = "0",
            Position = UDim2.fromOffset(0, 19),
            Size = UDim2.new(1, 0, 0, 22),
            TextSize = 20,
            Font = FONT_XB,
            XAlign = CENTER,
        })
    end
    local bestLbl = miniStat(0, "BEST")
    local lenLbl = miniStat(64, "LENGTH")
    local lvlLbl = miniStat(128, "LEVEL")

    label(side, {
        Text = "NEXT LEVEL",
        Position = UDim2.fromOffset(0, 192),
        Size = UDim2.fromOffset(100, 12),
        TextSize = 11,
        Font = FONT_B,
        Color = Theme.sub,
    })
    local progLbl = label(side, {
        Text = "0/5",
        Position = UDim2.fromOffset(86, 192),
        Size = UDim2.fromOffset(100, 12),
        TextSize = 11,
        Font = FONT_B,
        Color = Theme.sub,
        XAlign = RIGHT,
    })
    local progTrack = make("Frame", {
        Position = UDim2.fromOffset(0, 209),
        Size = UDim2.fromOffset(186, 6),
        BackgroundColor3 = Theme.track,
        BorderSizePixel = 0,
    }, side)
    round(progTrack)
    local progFill = make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
    }, progTrack)
    round(progFill)

    local fxList = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 226),
        Size = UDim2.fromOffset(186, 76),
    }, side)
    make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, fxList)

    local touch = UserInputService.TouchEnabled
    if touch then
        local arrows = { { "←", -1, 0 }, { "↑", 0, -1 }, { "↓", 0, 1 }, { "→", 1, 0 } }
        for i, a in ipairs(arrows) do
            button(side, {
                Text = a[1],
                Font = Enum.Font.GothamBold,
                TextSize = 18,
                Position = UDim2.fromOffset((i - 1) * 48, 302),
                Size = UDim2.fromOffset(42, 32),
            }, function()
                if state == "playing" or state == "countdown" then
                    -- defined below; resolved at call time
                    ctx._turn(a[2], a[3])
                end
            end)
        end
    else
        label(side, {
            Text = "WASD / Arrows to steer\nP or Space to pause",
            Position = UDim2.fromOffset(0, 304),
            Size = UDim2.fromOffset(186, 30),
            TextSize = 12,
            Color = Theme.sub,
            Wrapped = true,
            YAlign = Enum.TextYAlignment.Top,
        })
    end

    local primaryBtn = button(side, {
        Text = "Play",
        Color = Theme.accent,
        TextColor = Color3.fromRGB(16, 30, 22),
        Position = UDim2.fromOffset(0, 340),
        Size = UDim2.fromOffset(90, 28),
    }, function()
        ctx._primary()
    end)
    button(side, {
        Text = "Menu",
        Position = UDim2.fromOffset(96, 340),
        Size = UDim2.fromOffset(90, 28),
    }, function()
        toMenu()
    end)

    ------------------------------------------------------------
    -- Board holder + overlays
    ------------------------------------------------------------
    local holder = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(218, 20),
        Size = UDim2.fromOffset(360, 360),
    }, root)

    local cdLabel = label(holder, {
        Size = UDim2.fromScale(1, 1),
        TextSize = 60,
        Font = FONT_XB,
        XAlign = CENTER,
        ZIndex = 25,
        Visible = false,
    })
    local banner = label(holder, {
        Position = UDim2.fromOffset(0, 120),
        Size = UDim2.new(1, 0, 0, 60),
        TextSize = 30,
        Font = FONT_XB,
        XAlign = CENTER,
        ZIndex = 24,
        Visible = false,
    })

    local overlay = make("CanvasGroup", {
        BackgroundColor3 = Color3.fromRGB(10, 11, 13),
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 20,
    }, holder)
    corner(overlay, 10)
    local overlayName

    local function newPanel()
        return make("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Visible = false,
        }, overlay)
    end
    local ovMenu, ovPause, ovOver = newPanel(), newPanel(), newPanel()
    local panels = { menu = ovMenu, pause = ovPause, over = ovOver }

    local function selector(parent, y, title, names, getIdx, setIdx)
        label(parent, {
            Text = title,
            Position = UDim2.fromOffset(36, y),
            Size = UDim2.fromOffset(70, 30),
            TextSize = 13,
            Font = FONT_B,
            Color = Theme.sub,
        })
        local box = make("Frame", {
            Position = UDim2.fromOffset(112, y),
            Size = UDim2.fromOffset(212, 30),
            BackgroundColor3 = Theme.track,
            BorderSizePixel = 0,
        }, parent)
        corner(box, 8)
        local valueLbl = label(box, { XAlign = CENTER, Font = FONT_B, TextSize = 14 })
        local function refresh()
            valueLbl.Text = names[getIdx()]
        end
        local function cycle(d)
            local n = #names
            setIdx((getIdx() - 1 + d) % n + 1)
            refresh()
            valueLbl.TextTransparency = 0.7
            tween(valueLbl, { TextTransparency = 0 }, 0.25)
        end
        button(box, { Text = "‹", Size = UDim2.fromOffset(32, 30), TextSize = 22 }, function()
            cycle(-1)
        end)
        button(box, {
            Text = "›",
            Position = UDim2.fromOffset(180, 0),
            Size = UDim2.fromOffset(32, 30),
            TextSize = 22,
        }, function()
            cycle(1)
        end)
        refresh()
        return refresh
    end

    -- Menu overlay -------------------------------------------------
    label(ovMenu, {
        Text = "SNAKE",
        Position = UDim2.fromOffset(0, 16),
        Size = UDim2.new(1, 0, 0, 40),
        TextSize = 36,
        Font = FONT_XB,
        Color = Theme.accent,
        XAlign = CENTER,
    })
    local menuDesc = label(ovMenu, {
        Position = UDim2.fromOffset(0, 58),
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 14,
        Color = Theme.sub,
        XAlign = CENTER,
    })

    local function onConfig(sizeChanged)
        store:set("snake.cfg", { mode = cfg.mode, speed = cfg.speed, size = cfg.size })
        if sizeChanged then
            buildBoard()
        end
        if boardStroke then
            tween(boardStroke, { Color = MODE_COLOR[cfg.mode] }, 0.3)
        end
        setupGame()
    end

    selector(ovMenu, 96, "MODE", MODES, function()
        return table.find(MODES, cfg.mode)
    end, function(i)
        cfg.mode = MODES[i]
        onConfig(false)
    end)
    selector(ovMenu, 136, "SPEED", SPEED_NAMES, function()
        return table.find(SPEED_NAMES, cfg.speed)
    end, function(i)
        cfg.speed = SPEED_NAMES[i]
        onConfig(false)
    end)
    selector(ovMenu, 176, "BOARD", SIZE_NAMES, function()
        return cfg.size
    end, function(i)
        cfg.size = i
        onConfig(true)
    end)

    local menuBest = label(ovMenu, {
        Position = UDim2.fromOffset(0, 220),
        Size = UDim2.new(1, 0, 0, 20),
        TextSize = 15,
        Font = FONT_B,
        XAlign = CENTER,
    })
    button(ovMenu, {
        Text = "PLAY",
        Color = Theme.accent,
        TextColor = Color3.fromRGB(16, 30, 22),
        TextSize = 18,
        Position = UDim2.fromOffset(80, 254),
        Size = UDim2.fromOffset(200, 42),
        Radius = 10,
    }, function()
        startGame()
    end)
    label(ovMenu, {
        Text = touch and "Swipe on the screen or use the arrow buttons" or "Press Enter or Space to start",
        Position = UDim2.fromOffset(0, 308),
        Size = UDim2.new(1, 0, 0, 16),
        TextSize = 12,
        Color = Theme.sub,
        XAlign = CENTER,
    })

    -- Pause overlay ------------------------------------------------
    label(ovPause, {
        Text = "PAUSED",
        Position = UDim2.fromOffset(0, 80),
        Size = UDim2.new(1, 0, 0, 44),
        TextSize = 34,
        Font = FONT_XB,
        XAlign = CENTER,
    })
    button(ovPause, {
        Text = "Resume",
        Color = Theme.accent,
        TextColor = Color3.fromRGB(16, 30, 22),
        TextSize = 16,
        Position = UDim2.fromOffset(80, 148),
        Size = UDim2.fromOffset(200, 38),
        Radius = 10,
    }, function()
        resume()
    end)
    button(ovPause, {
        Text = "Restart",
        TextSize = 15,
        Position = UDim2.fromOffset(80, 196),
        Size = UDim2.fromOffset(200, 36),
        Radius = 10,
    }, function()
        startGame()
    end)
    button(ovPause, {
        Text = "Menu",
        TextSize = 15,
        Position = UDim2.fromOffset(80, 242),
        Size = UDim2.fromOffset(200, 36),
        Radius = 10,
    }, function()
        toMenu()
    end)

    -- Game over overlay --------------------------------------------
    local overTitle = label(ovOver, {
        Text = "GAME OVER",
        Position = UDim2.fromOffset(0, 40),
        Size = UDim2.new(1, 0, 0, 44),
        TextSize = 34,
        Font = FONT_XB,
        Color = Theme.danger,
        XAlign = CENTER,
    })
    local overReason = label(ovOver, {
        Position = UDim2.fromOffset(0, 86),
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 14,
        Color = Theme.sub,
        XAlign = CENTER,
    })
    local overScore = label(ovOver, {
        Position = UDim2.fromOffset(0, 112),
        Size = UDim2.new(1, 0, 0, 56),
        TextSize = 52,
        Font = FONT_XB,
        XAlign = CENTER,
    })
    local overBadge = label(ovOver, {
        Text = "NEW BEST!",
        Position = UDim2.fromOffset(0, 170),
        Size = UDim2.new(1, 0, 0, 20),
        TextSize = 16,
        Font = FONT_XB,
        Color = Theme.gold,
        XAlign = CENTER,
    })
    local overStats = label(ovOver, {
        Position = UDim2.fromOffset(0, 194),
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 13,
        Color = Theme.sub,
        XAlign = CENTER,
    })
    button(ovOver, {
        Text = "Play again",
        Color = Theme.accent,
        TextColor = Color3.fromRGB(16, 30, 22),
        TextSize = 16,
        Position = UDim2.fromOffset(80, 244),
        Size = UDim2.fromOffset(200, 40),
        Radius = 10,
    }, function()
        startGame()
    end)
    button(ovOver, {
        Text = "Menu",
        TextSize = 15,
        Position = UDim2.fromOffset(80, 292),
        Size = UDim2.fromOffset(200, 36),
        Radius = 10,
    }, function()
        toMenu()
    end)

    function showOverlay(name)
        overlayName = name
        for n, p in pairs(panels) do
            p.Visible = n == name
            if n == name then
                p.Position = UDim2.fromOffset(0, 14)
                tween(p, { Position = UDim2.fromOffset(0, 0) }, 0.45, QUINT)
            end
        end
        overlay.Visible = true
        overlay.GroupTransparency = 1
        tween(overlay, { GroupTransparency = 0 }, 0.3)
    end

    function hideOverlay()
        overlayName = nil
        tween(overlay, { GroupTransparency = 1 }, 0.2)
        task.delay(0.22, function()
            if alive and overlayName == nil then
                overlay.Visible = false
            end
        end)
    end

    ------------------------------------------------------------
    -- Board construction
    ------------------------------------------------------------
    local function cellCenter(x, y)
        return UDim2.fromOffset(x * cell + cell / 2, y * cell + cell / 2)
    end

    function buildBoard()
        if board then
            board:Destroy()
        end
        N = SIZES[cfg.size]
        cell = math.floor(360 / N)
        pad = math.max(1, math.floor(cell * 0.07))
        local px = cell * N

        board = make("Frame", {
            Name = "Board",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(px, px),
            BackgroundColor3 = Color3.fromRGB(21, 23, 27),
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, holder)
        corner(board, 6)
        boardStroke = stroke(board, MODE_COLOR[cfg.mode], 0.35, 2)

        local tiles = make("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            ZIndex = 1,
        }, board)
        for y = 0, N - 1 do
            for x = 0, N - 1 do
                if (x + y) % 2 == 0 then
                    make("Frame", {
                        Position = UDim2.fromOffset(x * cell, y * cell),
                        Size = UDim2.fromOffset(cell, cell),
                        BackgroundColor3 = Color3.fromRGB(26, 28, 33),
                        BorderSizePixel = 0,
                    }, tiles)
                end
            end
        end

        segs, eyes, pupils, headScale = {}, {}, {}, nil
        rockFrames = {}
        food, bonus, power = nil, nil, nil
    end

    local function getSeg(i)
        local s = segs[i]
        if s then
            return s
        end
        local size = cell - 2 * pad
        s = make("Frame", {
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(size, size),
            ZIndex = i == 1 and 6 or 4,
            Visible = false,
        }, board)
        make("UICorner", { CornerRadius = UDim.new(0, math.floor(cell * 0.32)) }, s)
        if i == 1 then
            headScale = make("UIScale", { Scale = 1 }, s)
            local e = math.max(4, math.floor(cell * 0.32))
            for k = 1, 2 do
                local eye = make("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Size = UDim2.fromOffset(e, e),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel = 0,
                    ZIndex = 7,
                }, s)
                round(eye)
                local pupil = make("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromScale(0.5, 0.5),
                    BackgroundColor3 = Color3.fromRGB(14, 16, 18),
                    BorderSizePixel = 0,
                    ZIndex = 8,
                }, eye)
                round(pupil)
                eyes[k], pupils[k] = eye, pupil
            end
        end
        segs[i] = s
        return s
    end

    local function updateEyes(instant)
        if not eyes[1] then
            return
        end
        local hs = cell - 2 * pad
        for k = 1, 2 do
            local sign = k == 1 and 1 or -1
            local px, py = -dir.y * sign, dir.x * sign
            local cx = hs / 2 + dir.x * hs * 0.2 + px * hs * 0.24
            local cy = hs / 2 + dir.y * hs * 0.2 + py * hs * 0.24
            tween(eyes[k], { Position = UDim2.fromOffset(cx, cy) }, instant and 0 or 0.1)
        end
    end

    local function syncSegs()
        for i = 1, #body do
            getSeg(i).Visible = true
        end
        for i = #body + 1, #segs do
            segs[i].Visible = false
        end
    end

    local function recolor()
        local n = #body
        local ghost = active("ghost")
        for i = 1, n do
            local s = segs[i]
            if s then
                local t = n > 1 and (i - 1) / (n - 1) or 0
                local c = HEAD_COLOR:Lerp(TAIL_COLOR, t)
                if i % 2 == 0 then
                    c = c:Lerp(Color3.new(0, 0, 0), 0.07)
                end
                s.BackgroundColor3 = c
                s.BackgroundTransparency = ghost and 0.5 or 0
            end
        end
        if eyes[1] then
            for k = 1, 2 do
                eyes[k].BackgroundTransparency = 0
                pupils[k].BackgroundTransparency = 0
            end
        end
    end

    local function render(alpha)
        for i = 1, #body do
            local s = segs[i]
            if s then
                local cur = body[i]
                local pv = prevBody[math.min(i, #prevBody)] or cur
                local dx, dy = cur.x - pv.x, cur.y - pv.y
                local x, y
                if math.abs(dx) > 1 or math.abs(dy) > 1 then
                    x, y = cur.x, cur.y -- wrapped around, snap
                else
                    x, y = pv.x + dx * alpha, pv.y + dy * alpha
                end
                s.Position = UDim2.fromOffset(x * cell + pad, y * cell + pad)
            end
        end
    end

    local function buildOcc()
        occ = {}
        for _, c in ipairs(body) do
            occ[c.y * N + c.x] = true
        end
    end

    ------------------------------------------------------------
    -- Effects: particles, floating text, banners
    ------------------------------------------------------------
    local function burst(x, y, color, count)
        local cx, cy = x * cell + cell / 2, y * cell + cell / 2
        for _ = 1, count do
            local p = make("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromOffset(cx, cy),
                Size = UDim2.fromOffset(math.max(3, cell * 0.22), math.max(3, cell * 0.22)),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
                ZIndex = 9,
            }, board)
            round(p)
            local a = rng:NextNumber(0, math.pi * 2)
            local d = rng:NextNumber(cell * 0.8, cell * 2.4)
            local t = rng:NextNumber(0.35, 0.6)
            tween(p, {
                Position = UDim2.fromOffset(cx + math.cos(a) * d, cy + math.sin(a) * d),
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(1, 1),
            }, t, QUINT)
            task.delay(t + 0.05, function()
                p:Destroy()
            end)
        end
    end

    local function floatText(text, x, y, color)
        local px = math.clamp(x * cell + cell / 2, 50, cell * N - 50)
        local py = math.clamp(y * cell, 14, cell * N - 14)
        local l = label(board, {
            Text = text,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(px, py),
            Size = UDim2.fromOffset(100, 20),
            TextSize = 16,
            Font = FONT_XB,
            Color = color or Theme.text,
            XAlign = CENTER,
            ZIndex = 12,
        })
        l.TextStrokeTransparency = 0.6
        tween(l, { Position = UDim2.fromOffset(px, py - 26) }, 0.8, QUINT)
        tween(l, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.4, QUAD, OUT, 0.45)
        task.delay(0.9, function()
            l:Destroy()
        end)
    end

    local bannerToken = 0
    local function showBanner(text, color)
        bannerToken += 1
        local my = bannerToken
        banner.Text = text
        banner.TextColor3 = color or Theme.text
        banner.TextTransparency = 1
        banner.TextSize = 18
        banner.Visible = true
        tween(banner, { TextTransparency = 0, TextSize = 34 }, 0.4, BACK)
        task.delay(1, function()
            if alive and my == bannerToken then
                tween(banner, { TextTransparency = 1 }, 0.4)
                task.delay(0.42, function()
                    if my == bannerToken then
                        banner.Visible = false
                    end
                end)
            end
        end)
    end

    ------------------------------------------------------------
    -- HUD
    ------------------------------------------------------------
    local function punch(lbl, base, big)
        lbl.TextSize = big
        tween(lbl, { TextSize = base }, 0.4, BACK)
    end

    function updateHUD()
        scoreLbl.Text = tostring(score)
        bestLbl.Text = tostring(best)
        lenLbl.Text = tostring(#body)
        lvlLbl.Text = tostring(level)
        local into = foods % 5
        progLbl.Text = into .. "/5"
        tween(progFill, { Size = UDim2.fromScale(into / 5, 1) }, 0.35, QUINT)
        modeLbl.Text = cfg.mode .. "  ·  " .. cfg.speed
        menuDesc.Text = MODE_DESC[cfg.mode]
        menuBest.Text = "Best score:  " .. store:get(bestKey(), 0)
    end

    function updateButtons()
        if state == "playing" or state == "countdown" then
            primaryBtn.Text = "Pause"
        elseif state == "paused" then
            primaryBtn.Text = "Resume"
        else
            primaryBtn.Text = "Play"
        end
    end

    local function addScore(pts, x, y, color, tag)
        score += pts
        if score > best then
            best = score
            newBest = true
        end
        updateHUD()
        punch(scoreLbl, 40, 48)
        floatText("+" .. pts .. (tag or ""), x, y, color)
    end

    local function chipFor(name)
        local c = chips[name]
        if c then
            return c
        end
        local info = POWERS[name]
        local f = make("Frame", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = Theme.panel,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            LayoutOrder = table.find(FX_ORDER, name),
        }, fxList)
        corner(f, 6)
        local fill = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = info.color,
            BackgroundTransparency = 0.65,
            BorderSizePixel = 0,
        }, f)
        label(f, {
            Text = info.name,
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -60, 1, 0),
            TextSize = 12,
            Font = FONT_B,
            Color = info.color,
            ZIndex = 2,
        })
        local tm = label(f, {
            Position = UDim2.new(1, -52, 0, 0),
            Size = UDim2.fromOffset(44, 22),
            TextSize = 12,
            Font = FONT_B,
            XAlign = RIGHT,
            ZIndex = 2,
        })
        f.Position = UDim2.fromOffset(-20, 0)
        c = { frame = f, fill = fill, time = tm }
        chips[name] = c
        return c
    end

    local function updateChips()
        for _, name in ipairs(FX_ORDER) do
            local on = active(name) and state ~= "menu"
            local c = chips[name]
            if on then
                c = chipFor(name)
                local rem = fx[name] - gt
                c.fill.Size = UDim2.fromScale(math.clamp(rem / fxDur[name], 0, 1), 1)
                c.time.Text = string.format("%.1fs", rem)
                c.frame.Visible = rem > 2 or (os.clock() * 6) % 2 < 1.3
            elseif c then
                c.frame:Destroy()
                chips[name] = nil
            end
        end
    end

    local function clearChips()
        for name, c in pairs(chips) do
            c.frame:Destroy()
            chips[name] = nil
        end
    end

    ------------------------------------------------------------
    -- Spawning
    ------------------------------------------------------------
    local function pickFree(minDist, pred)
        local hx, hy = body[1].x, body[1].y
        local list, n = {}, 0
        for y = 0, N - 1 do
            for x = 0, N - 1 do
                local k = y * N + x
                if
                    not occ[k]
                    and not rocks[k]
                    and not (food and food.k == k)
                    and not (bonus and bonus.k == k)
                    and not (power and power.k == k)
                then
                    if
                        (not minDist or math.abs(x - hx) + math.abs(y - hy) >= minDist)
                        and (not pred or pred(x, y))
                    then
                        n += 1
                        list[n] = k
                    end
                end
            end
        end
        if n == 0 then
            return nil
        end
        return list[rng:NextInteger(1, n)]
    end

    local function blockedAround(x, y)
        local n = 0
        for _, d in ipairs(DIRS4) do
            local nx, ny = x + d[1], y + d[2]
            if nx < 0 or nx >= N or ny < 0 or ny >= N or rocks[ny * N + nx] then
                n += 1
            end
        end
        return n
    end

    local function newItemFrame(x, y, size, color, cornerRadius)
        local f = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = cellCenter(x, y),
            Size = UDim2.fromOffset(0, 0),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            ZIndex = 3,
        }, board)
        make("UICorner", { CornerRadius = cornerRadius }, f)
        local us = make("UIScale", { Scale = 1 }, f)
        tween(f, { Size = UDim2.fromOffset(size, size) }, 0.45, BACK)
        return f, us
    end

    local function removeItem(item)
        local f = item.frame
        tween(f, { Size = UDim2.fromOffset(0, 0) }, 0.16, QUAD, IN)
        task.delay(0.18, function()
            f:Destroy()
        end)
    end

    local function spawnFood()
        local k = pickFree(nil, cfg.mode == "Obstacles" and function(x, y)
            return blockedAround(x, y) < 3
        end or nil)
        if not k then
            return
        end
        local x, y = k % N, math.floor(k / N)
        local f, us = newItemFrame(x, y, cell * 0.78, Theme.apple, UDim.new(1, 0))
        local hl = make("Frame", {
            Position = UDim2.fromScale(0.2, 0.18),
            Size = UDim2.fromScale(0.22, 0.22),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
        }, f)
        round(hl)
        local leaf = make("Frame", {
            Position = UDim2.fromScale(0.5, -0.08),
            Size = UDim2.fromScale(0.38, 0.2),
            Rotation = -28,
            BackgroundColor3 = Color3.fromRGB(110, 200, 120),
            BorderSizePixel = 0,
        }, f)
        round(leaf)
        food = { k = k, x = x, y = y, frame = f, scale = us }
    end

    local function spawnBonus()
        local k = pickFree(3, cfg.mode == "Obstacles" and function(x, y)
            return blockedAround(x, y) < 3
        end or nil)
        if not k then
            return
        end
        local x, y = k % N, math.floor(k / N)
        local f, us = newItemFrame(x, y, cell * 0.62, Theme.gold, UDim.new(0, 2))
        f.Rotation = 45
        local inner = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(0.5, 0.5),
            BackgroundColor3 = Color3.fromRGB(255, 240, 180),
            BorderSizePixel = 0,
        }, f)
        corner(inner, 1)
        bonus = { k = k, x = x, y = y, frame = f, scale = us, t0 = gt, dur = 8 }
        floatText("BONUS!", x, y, Theme.gold)
    end

    local function spawnPower()
        local kind = POWER_LIST[rng:NextInteger(1, #POWER_LIST)]
        local info = POWERS[kind]
        local k = pickFree(3, cfg.mode == "Obstacles" and function(x, y)
            return blockedAround(x, y) < 3
        end or nil)
        if not k then
            return
        end
        local x, y = k % N, math.floor(k / N)
        local f, us = newItemFrame(x, y, cell * 0.74, info.color, UDim.new(0.3, 0))
        label(f, {
            Text = info.glyph,
            Size = UDim2.fromScale(1, 1),
            TextSize = math.max(9, math.floor(cell * 0.5)),
            Font = FONT_XB,
            Color = Color3.fromRGB(18, 18, 22),
            XAlign = CENTER,
        })
        power = { k = k, x = x, y = y, frame = f, scale = us, kind = kind, t0 = gt, dur = 9 }
    end

    local function connectedWithRocks()
        local hx, hy = body[1].x, body[1].y
        local start = hy * N + hx
        local seen = { [start] = true }
        local queueK, qi, reached = { start }, 1, 1
        while qi <= #queueK do
            local k = queueK[qi]
            qi += 1
            local x, y = k % N, math.floor(k / N)
            for _, d in ipairs(DIRS4) do
                local nx, ny = x + d[1], y + d[2]
                if nx >= 0 and nx < N and ny >= 0 and ny < N then
                    local nk = ny * N + nx
                    if not seen[nk] and not rocks[nk] then
                        seen[nk] = true
                        reached += 1
                        queueK[#queueK + 1] = nk
                    end
                end
            end
        end
        return reached == N * N - rockCount
    end

    local function addRocks(count)
        for _ = 1, count do
            for _ = 1, 20 do
                local k = pickFree(5)
                if not k then
                    break
                end
                rocks[k] = true
                rockCount += 1
                if connectedWithRocks() then
                    local x, y = k % N, math.floor(k / N)
                    local size = cell - 2 * pad
                    local r = make("Frame", {
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = cellCenter(x, y),
                        Size = UDim2.fromOffset(0, 0),
                        BackgroundColor3 = Theme.rock,
                        BorderSizePixel = 0,
                        ZIndex = 2,
                    }, board)
                    corner(r, 3)
                    local top = make("Frame", {
                        Position = UDim2.fromScale(0.12, 0.12),
                        Size = UDim2.fromScale(0.76, 0.3),
                        BackgroundColor3 = Color3.new(1, 1, 1),
                        BackgroundTransparency = 0.88,
                        BorderSizePixel = 0,
                    }, r)
                    corner(top, 2)
                    tween(r, { Size = UDim2.fromOffset(size, size) }, 0.45, BACK)
                    rockFrames[k] = r
                    break
                else
                    rocks[k] = nil
                    rockCount -= 1
                end
            end
        end
    end

    ------------------------------------------------------------
    -- Game flow
    ------------------------------------------------------------
    local function tickTime()
        local base = SPEED_BASE[cfg.speed]
        local t = math.max(base * (0.95 ^ (level - 1)), base * 0.52)
        if active("slow") then
            t *= 1.55
        end
        return t
    end

    function setupGame()
        for _, r in pairs(rockFrames) do
            r:Destroy()
        end
        rocks, rockFrames, rockCount = {}, {}, 0
        if food then
            food.frame:Destroy()
        end
        if bonus then
            bonus.frame:Destroy()
        end
        if power then
            power.frame:Destroy()
        end
        food, bonus, power = nil, nil, nil
        clearChips()

        score, foods, level, sinceBonus = 0, 0, 1, 0
        newBest = false
        best = store:get(bestKey(), 0)
        gt, acc = 0, 0
        fx = { slow = 0, ghost = 0, double = 0 }
        ghostShown = false
        dir = { x = 1, y = 0 }
        queue = {}

        local sx, sy = math.floor(N / 3), math.floor(N / 2)
        body = { { x = sx + 2, y = sy }, { x = sx + 1, y = sy }, { x = sx, y = sy } }
        prevBody = table.move(body, 1, #body, 1, {})
        buildOcc()

        if cfg.mode == "Obstacles" then
            addRocks(math.floor(N * 0.22))
        end
        spawnFood()

        syncSegs()
        recolor()
        updateEyes(true)
        render(1)
        updateHUD()
        board.Position = UDim2.fromScale(0.5, 0.5)
    end

    local function levelUp()
        level += 1
        showBanner("LEVEL " .. level, Theme.accent)
        punch(lvlLbl, 20, 28)
        if cfg.mode == "Obstacles" then
            addRocks(2)
        end
    end

    local function applyPower(kind, x, y)
        local info = POWERS[kind]
        if kind == "shrink" then
            for _ = 1, 3 do
                if #body > 3 then
                    table.remove(body)
                end
            end
            buildOcc()
            syncSegs()
        else
            fx[kind] = gt + info.dur
            fxDur[kind] = info.dur
        end
        floatText(info.name, x, y, info.color)
        burst(x, y, info.color, 12)
    end

    local function step()
        if #queue > 0 then
            dir = table.remove(queue, 1)
            updateEyes(false)
        end
        local head = body[1]
        local nx, ny = head.x + dir.x, head.y + dir.y
        local ghost = active("ghost")

        if nx < 0 or nx >= N or ny < 0 or ny >= N then
            if cfg.mode == "Wrap" or ghost then
                nx, ny = (nx + N) % N, (ny + N) % N
            else
                die("You hit the wall.")
                return
            end
        end

        local k = ny * N + nx
        if rocks[k] and not ghost then
            die("You hit a rock.")
            return
        end

        local eatFood = food and food.k == k
        local eatBonus = bonus and bonus.k == k
        local eatPower = power and power.k == k
        local grow = eatFood or eatBonus

        if not ghost and occ[k] then
            local tail = body[#body]
            local isTail = tail.x == nx and tail.y == ny
            if not (isTail and not grow) then
                die("You ate yourself.")
                return
            end
        end

        prevBody = table.move(body, 1, #body, 1, {})
        table.insert(body, 1, { x = nx, y = ny })
        if not grow then
            table.remove(body)
        end
        buildOcc()

        if eatFood then
            local mult = active("double") and 2 or 1
            local pts = (10 + (level - 1) * 2) * mult
            local f = food
            food = nil
            removeItem(f)
            burst(f.x, f.y, Theme.apple, 10)
            addScore(pts, f.x, f.y, mult == 2 and Theme.gold or Theme.text)
            foods += 1
            sinceBonus += 1
            if foods % 5 == 0 then
                levelUp()
            end
            spawnFood()
            if sinceBonus >= 6 and not bonus then
                sinceBonus = 0
                spawnBonus()
            end
            if not power and rng:NextNumber() < 0.2 then
                spawnPower()
            end
        end

        if eatBonus then
            local b = bonus
            bonus = nil
            removeItem(b)
            local remaining = math.clamp((b.t0 + b.dur - gt) / b.dur, 0, 1)
            local mult = active("double") and 2 or 1
            local pts = math.floor(20 + 80 * remaining) * mult
            burst(b.x, b.y, Theme.gold, 16)
            addScore(pts, b.x, b.y, Theme.gold, " BONUS")
        end

        if eatPower then
            local p = power
            power = nil
            removeItem(p)
            applyPower(p.kind, p.x, p.y)
        end

        if eatFood or eatBonus or eatPower then
            if headScale then
                headScale.Scale = 1.28
                tween(headScale, { Scale = 1 }, 0.35, BACK)
            end
        end

        syncSegs()
        recolor()
        updateHUD()

        if #body + rockCount >= N * N then
            die("You filled the whole board!", true)
        end
    end

    function die(reason, won)
        if state == "over" then
            return
        end
        state = "over"
        cdToken += 1
        cdLabel.Visible = false
        updateButtons()

        local saveBest = newBest and score > 0
        if saveBest then
            store:set(bestKey(), best)
        end
        updateHUD()

        -- feedback: red flash, shake, snake melts away
        local flash = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Theme.danger,
            BackgroundTransparency = won and 1 or 0.55,
            BorderSizePixel = 0,
            ZIndex = 30,
        }, board)
        tween(flash, { BackgroundTransparency = 1 }, 0.6)
        task.delay(0.65, function()
            flash:Destroy()
        end)

        if not won then
            task.spawn(function()
                for i = 1, 7 do
                    if not alive then
                        return
                    end
                    local m = math.floor((8 - i) * 0.9)
                    board.Position = UDim2.new(0.5, rng:NextInteger(-m, m), 0.5, rng:NextInteger(-m, m))
                    task.wait(0.035)
                end
                if alive then
                    board.Position = UDim2.fromScale(0.5, 0.5)
                end
            end)
        end

        for i = 1, #body do
            local s = segs[i]
            local d = math.min(i * 0.018, 0.6)
            tween(s, { BackgroundColor3 = won and Theme.gold or Theme.danger }, 0.15, QUAD, OUT, d)
            tween(s, { BackgroundTransparency = 1 }, 0.45, QUAD, OUT, 0.35 + d)
        end
        if eyes[1] then
            for k = 1, 2 do
                tween(eyes[k], { BackgroundTransparency = 1 }, 0.3, QUAD, OUT, 0.3)
                tween(pupils[k], { BackgroundTransparency = 1 }, 0.3, QUAD, OUT, 0.3)
            end
        end

        task.delay(1.0, function()
            if not alive or state ~= "over" then
                return
            end
            overTitle.Text = won and "YOU WIN!" or "GAME OVER"
            overTitle.TextColor3 = won and Theme.accent or Theme.danger
            overReason.Text = reason
            overScore.Text = tostring(score)
            overBadge.Visible = saveBest
            overStats.Text = "Length " .. #body .. "   ·   Level " .. level .. "   ·   Best " .. best
            showOverlay("over")
            punch(overScore, 52, 62)
        end)
    end

    function countdown()
        state = "countdown"
        cdToken += 1
        local my = cdToken
        hideOverlay()
        updateButtons()
        task.spawn(function()
            for i = 3, 1, -1 do
                if not alive or my ~= cdToken then
                    return
                end
                cdLabel.Visible = true
                cdLabel.Text = tostring(i)
                cdLabel.TextTransparency = 0
                cdLabel.TextSize = 40
                tween(cdLabel, { TextSize = 88 }, 0.45, QUINT)
                tween(cdLabel, { TextTransparency = 1 }, 0.2, QUAD, OUT, 0.32)
                task.wait(0.5)
            end
            if not alive or my ~= cdToken then
                return
            end
            cdLabel.Visible = false
            acc = 0
            state = "playing"
            updateButtons()
        end)
    end

    function startGame()
        setupGame()
        countdown()
    end

    function pause()
        if state ~= "playing" and state ~= "countdown" then
            return
        end
        cdToken += 1
        cdLabel.Visible = false
        state = "paused"
        updateButtons()
        showOverlay("pause")
    end

    function resume()
        if state ~= "paused" then
            return
        end
        countdown()
    end

    function toMenu()
        cdToken += 1
        cdLabel.Visible = false
        state = "menu"
        setupGame()
        updateButtons()
        showOverlay("menu")
    end

    ------------------------------------------------------------
    -- Input
    ------------------------------------------------------------
    local function turn(dx, dy)
        if state ~= "playing" and state ~= "countdown" then
            return
        end
        local last = queue[#queue] or dir
        if (dx == last.x and dy == last.y) or (dx == -last.x and dy == -last.y) then
            return
        end
        if #queue < 2 then
            queue[#queue + 1] = { x = dx, y = dy }
        end
    end
    ctx._turn = turn

    local function primary()
        if state == "playing" or state == "countdown" then
            pause()
        elseif state == "paused" then
            resume()
        else
            startGame()
        end
    end
    ctx._primary = primary

    local K = Enum.KeyCode
    local KEYDIRS = {
        [K.W] = { 0, -1 }, [K.Up] = { 0, -1 }, [K.DPadUp] = { 0, -1 },
        [K.S] = { 0, 1 }, [K.Down] = { 0, 1 }, [K.DPadDown] = { 0, 1 },
        [K.A] = { -1, 0 }, [K.Left] = { -1, 0 }, [K.DPadLeft] = { -1, 0 },
        [K.D] = { 1, 0 }, [K.Right] = { 1, 0 }, [K.DPadRight] = { 1, 0 },
    }
    local boundKeys = {}
    for key in pairs(KEYDIRS) do
        table.insert(boundKeys, key)
    end
    for _, key in ipairs({ K.Space, K.P, K.R, K.Return, K.ButtonStart }) do
        table.insert(boundKeys, key)
    end

    local ACTION = "OldArcadeSnake"
    ContextActionService:BindActionAtPriority(ACTION, function(_, inputState, input)
        if inputState == Enum.UserInputState.Begin then
            local code = input.KeyCode
            local d = KEYDIRS[code]
            if d then
                turn(d[1], d[2])
            elseif code == K.Space or code == K.P or code == K.ButtonStart then
                primary()
            elseif code == K.Return then
                if state ~= "playing" and state ~= "countdown" then
                    primary()
                end
            elseif code == K.R then
                if state ~= "menu" then
                    startGame()
                end
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.ContextActionPriority.High.Value, unpack(boundKeys))

    -- touch swipe
    local swipe
    connect(UserInputService.InputBegan, function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        swipe = { input = input, pos = Vector2.new(input.Position.X, input.Position.Y) }
    end)
    connect(UserInputService.InputChanged, function(input)
        if swipe and input == swipe.input then
            local p = Vector2.new(input.Position.X, input.Position.Y)
            local d = p - swipe.pos
            if d.Magnitude > 22 then
                if math.abs(d.X) > math.abs(d.Y) then
                    turn(d.X > 0 and 1 or -1, 0)
                else
                    turn(0, d.Y > 0 and 1 or -1)
                end
                swipe.pos = p
            end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if swipe and input == swipe.input then
            swipe = nil
        end
    end)
    connect(UserInputService.WindowFocusReleased, function()
        if state == "playing" then
            pause()
        end
    end)

    ------------------------------------------------------------
    -- Main loop
    ------------------------------------------------------------
    connect(RunService.Heartbeat, function(dt)
        if not alive then
            return
        end
        dt = math.min(dt, 0.1)
        local now = os.clock()

        if state == "playing" then
            gt += dt
            acc += dt
            local tt = tickTime()
            local steps = 0
            while acc >= tt and state == "playing" and steps < 3 do
                acc -= tt
                steps += 1
                step()
                tt = tickTime()
            end
            if acc > tt then
                acc = tt
            end

            if bonus and gt >= bonus.t0 + bonus.dur then
                removeItem(bonus)
                bonus = nil
            end
            if power and gt >= power.t0 + power.dur then
                removeItem(power)
                power = nil
            end

            local g = active("ghost")
            if g ~= ghostShown then
                ghostShown = g
                recolor()
            end
        end

        if state ~= "over" then
            render(math.clamp(acc / tickTime(), 0, 1))
        end

        if food then
            food.scale.Scale = 1 + 0.07 * math.sin(now * 6)
        end
        if bonus then
            local rem = bonus.t0 + bonus.dur - gt
            local frac = math.clamp(rem / bonus.dur, 0, 1)
            bonus.scale.Scale = (0.6 + 0.4 * frac) * (1 + 0.08 * math.sin(now * 8))
            bonus.frame.Rotation = 45 + math.sin(now * 3) * 15
            bonus.frame.Visible = rem > 2 or (now * 8) % 2 < 1
        end
        if power then
            local rem = power.t0 + power.dur - gt
            power.scale.Scale = 1 + 0.08 * math.sin(now * 7)
            power.frame.Rotation = math.sin(now * 4) * 8
            power.frame.Visible = rem > 2.5 or (now * 8) % 2 < 1
        end

        updateChips()
    end)

    ------------------------------------------------------------
    -- Start
    ------------------------------------------------------------
    buildBoard()
    setupGame()
    updateButtons()
    showOverlay("menu")

    local self = {}
    function self:Destroy()
        alive = false
        cdToken += 1
        ContextActionService:UnbindAction(ACTION)
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
        side:Destroy()
        holder:Destroy()
    end
    return self
end


----------------------------------------------------------------
-- WINDOW SHELL  (loaded standalone from the Hub; "‹ Hub" returns to it)
----------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G
local CFG = ENV.OldArcade -- set by Hub.lua: { Base = ..., Hub = ... }

local playerGui = player:WaitForChild("PlayerGui")
for _, n in ipairs({ "OldArcade_Snake", "OldArcade_Hub" }) do
    local o = playerGui:FindFirstChild(n)
    if o then
        o:Destroy()
    end
end

local gui = make("ScreenGui", {
    Name = "OldArcade_Snake",
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
local TITLE = 'ARCADE  <font color="#878b94">/  SNAKE</font>'
local titleLbl = label(top, {
    Text = TITLE,
    RichText = true,
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -150, 1, 0),
    Font = FONT_XB,
    TextSize = 16,
    ZIndex = 6,
})

local gameObj
local closing = false

local function shutdown()
    if closing then
        return
    end
    closing = true
    if gameObj then
        pcall(function()
            gameObj:Destroy()
        end)
        gameObj = nil
    end
    tween(uiScale, { Scale = baseScale * 0.94 }, 0.2, QUAD, IN)
    task.delay(0.22, function()
        if gui.Parent then
            gui:Destroy()
        end
    end)
end

-- fetch + compile the hub first; only tear this game down if that worked
local function backToHub()
    if closing then
        return
    end
    if not (CFG and CFG.Hub) then
        shutdown()
        return
    end
    titleLbl.Text = "Loading hub..."
    task.spawn(function()
        local ok, body = pcall(function()
            return game:HttpGet(CFG.Hub .. "?t=" .. os.time())
        end)
        local fn = ok and type(body) == "string" and loadstring(body)
        if not fn then
            titleLbl.Text = '<font color="#e46c6c">Could not load the hub. Check your connection.</font>'
            task.delay(3, function()
                if not closing then
                    titleLbl.Text = TITLE
                end
            end)
            return
        end
        shutdown()
        task.spawn(fn)
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
}, shutdown)

if CFG and CFG.Hub then
    button(top, {
        Text = "‹  Hub",
        TextSize = 14,
        Position = UDim2.new(1, -118, 0, 6),
        Size = UDim2.fromOffset(72, 28),
        Color = Theme.track,
        ZIndex = 6,
    }, backToHub)
end

-- drag by the top bar
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

gui.Destroying:Connect(function()
    if not closing then
        closing = true
        if gameObj then
            pcall(function()
                gameObj:Destroy()
            end)
            gameObj = nil
        end
    end
end)

local content = make("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 40),
    Size = UDim2.fromOffset(W, H - 40),
}, win)

local okCreate, result = pcall(SnakeGame, { Parent = content, Store = Store })
if okCreate then
    gameObj = result
else
    warn("[OldArcade] SNAKE failed to start: " .. tostring(result))
    label(content, {
        Text = "Failed to start:\n" .. tostring(result),
        Position = UDim2.fromOffset(24, 24),
        Size = UDim2.fromOffset(570, 200),
        TextSize = 14,
        Color = Theme.danger,
        Wrapped = true,
        YAlign = Enum.TextYAlignment.Top,
    })
end

tween(win, { Position = UDim2.fromScale(0.5, 0.5) }, 0.55, QUINT)
tween(uiScale, { Scale = baseScale }, 0.6, BACK)
