--[[
    OldArcade  -  Minesweeper
    Standalone game file. Run it from the Hub (Hub.lua), or directly with:
        loadstring(game:HttpGet("<raw url of Minesweeper.lua>"))()

    Boards     Beginner 9x9/10 - Intermediate 16x16/40 - Expert 30x16/99 - Custom
    Controls   Left click reveal - Right click flag - click a number (or left+right / middle) to chord
               F = flag mode - H = hint - R = new game
               Touch: tap to reveal, hold to flag, tap a number to chord
    Extras     First click always safe, ? marks, hints, 3BV, best times + win rate
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
-- MINESWEEPER
----------------------------------------------------------------
local function MinesweeperGame(ctx)
    local root = ctx.Parent -- 620 x 400
    local store = ctx.Store
    local alive = true
    local conns = {}
    local rng = Random.new()
    local touch = UserInputService.TouchEnabled

    local function connect(signal, fn)
        conns[#conns + 1] = signal:Connect(fn)
    end

    ------------------------------------------------------------
    -- Settings
    ------------------------------------------------------------
    local DIFFS = { "Beginner", "Intermediate", "Expert", "Custom" }
    local PRESETS = {
        Beginner = { cols = 9, rows = 9, mines = 10 },
        Intermediate = { cols = 16, rows = 16, mines = 40 },
        Expert = { cols = 30, rows = 16, mines = 99 },
    }
    local COLS_OPT = { 8, 10, 12, 16, 20, 24, 30 }
    local ROWS_OPT = { 8, 10, 12, 16, 20 }
    local DENS_OPT = { 10, 15, 20, 25 }
    local COLS_NAMES, ROWS_NAMES = {}, {}
    for i, v in ipairs(COLS_OPT) do
        COLS_NAMES[i] = v .. " columns"
    end
    for i, v in ipairs(ROWS_OPT) do
        ROWS_NAMES[i] = v .. " rows"
    end
    local DENS_NAMES = { "Low  (10%)", "Normal  (15%)", "High  (20%)", "Extreme  (25%)" }
    local MARK_NAMES = { "Off", "On" }

    local saved = store:get("mines.cfg", {})
    local cfg = {
        diff = (saved.diff and table.find(DIFFS, saved.diff)) and saved.diff or "Beginner",
        cols = (saved.cols and COLS_OPT[saved.cols]) and saved.cols or 4,
        rows = (saved.rows and ROWS_OPT[saved.rows]) and saved.rows or 4,
        dens = (saved.dens and DENS_OPT[saved.dens]) and saved.dens or 2,
        marks = saved.marks == true,
    }

    local function dims()
        local p = PRESETS[cfg.diff]
        if p then
            return p.cols, p.rows, p.mines
        end
        local c, r = COLS_OPT[cfg.cols], ROWS_OPT[cfg.rows]
        return c, r, math.max(1, math.floor(c * r * DENS_OPT[cfg.dens] / 100 + 0.5))
    end

    local function statKey()
        return PRESETS[cfg.diff] and cfg.diff or nil
    end

    local NUM_COLORS = {
        Color3.fromRGB(96, 165, 250),
        Color3.fromRGB(110, 205, 130),
        Color3.fromRGB(240, 110, 110),
        Color3.fromRGB(160, 135, 245),
        Color3.fromRGB(238, 150, 90),
        Color3.fromRGB(80, 204, 204),
        Color3.fromRGB(232, 232, 238),
        Color3.fromRGB(150, 152, 162),
    }
    local HIDDEN = Color3.fromRGB(62, 66, 76)
    local HOVER = Color3.fromRGB(80, 85, 98)
    local REVEALED = Color3.fromRGB(27, 29, 34)
    local MINE_BG = Color3.fromRGB(64, 44, 50)
    local PIECE = Color3.fromRGB(226, 229, 236)

    ------------------------------------------------------------
    -- State
    ------------------------------------------------------------
    local state = "menu" -- menu | ready | playing | won | lost
    local cols, rows, total, mineCount, cs = 9, 9, 81, 10, 30
    local board, boardStroke
    local cells, nb = {}, {}
    local mine, adj, st = {}, {}, {} -- st: 0 hidden, 1 revealed, 2 flag, 3 question
    local revealed, flags = 0, 0
    local startTime, elapsed = 0, 0
    local assisted, hints, bv = false, 0, 0
    local flagMode = false
    local longFired, holdToken = false, 0
    local bannerToken = 0
    local overlayName
    local gameId = 0

    local buildBoard, resetGame, toMenu, startNew, showOverlay, hideOverlay
    local layoutMenu, updateLED, updateInfo, lose, win, toggleFlag, onReveal, chord

    local function pos(i)
        return (i - 1) % cols, math.floor((i - 1) / cols)
    end

    ------------------------------------------------------------
    -- Sidebar
    ------------------------------------------------------------
    local side = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 16),
        Size = UDim2.fromOffset(186, 368),
    }, root)

    label(side, {
        Text = "MINESWEEPER",
        TextSize = 20,
        Font = FONT_XB,
        Color = Theme.blue,
        Size = UDim2.new(1, 0, 0, 26),
    })
    local subLbl = label(side, {
        Position = UDim2.fromOffset(0, 26),
        Size = UDim2.new(1, 0, 0, 16),
        TextSize = 13,
        Color = Theme.sub,
    })

    local function led(x)
        local f = make("Frame", {
            Position = UDim2.fromOffset(x, 52),
            Size = UDim2.fromOffset(62, 36),
            BackgroundColor3 = Color3.fromRGB(14, 10, 11),
            BorderSizePixel = 0,
        }, side)
        corner(f, 6)
        stroke(f, Theme.line, 0.9)
        return label(f, {
            Text = "000",
            Font = Enum.Font.Code,
            TextSize = 28,
            Color = Theme.danger,
            XAlign = CENTER,
        })
    end
    local mineLed = led(0)
    local timeLed = led(124)

    local face
    face = button(side, {
        Text = ":)",
        TextSize = 20,
        Position = UDim2.fromOffset(72, 52),
        Size = UDim2.fromOffset(42, 36),
        Color = Theme.panel,
        Radius = 8,
    }, function()
        if state ~= "menu" then
            startNew()
        end
    end)
    local faceBase = face.Text
    local function setFace(text)
        if state == "won" or state == "lost" then
            return
        end
        face.Text = text
    end

    local function miniStat(x, title)
        local f = make("Frame", {
            Position = UDim2.fromOffset(x, 98),
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
            Text = "-",
            Position = UDim2.fromOffset(0, 19),
            Size = UDim2.new(1, 0, 0, 22),
            TextSize = 18,
            Font = FONT_XB,
            XAlign = CENTER,
        })
    end
    local bestLbl = miniStat(0, "BEST")
    local wonLbl = miniStat(64, "WON")
    local rateLbl = miniStat(128, "WIN %")

    label(side, {
        Text = "CLEARED",
        Position = UDim2.fromOffset(0, 152),
        Size = UDim2.fromOffset(100, 12),
        TextSize = 11,
        Font = FONT_B,
        Color = Theme.sub,
    })
    local progLbl = label(side, {
        Text = "0/0",
        Position = UDim2.fromOffset(86, 152),
        Size = UDim2.fromOffset(100, 12),
        TextSize = 11,
        Font = FONT_B,
        Color = Theme.sub,
        XAlign = RIGHT,
    })
    local progTrack = make("Frame", {
        Position = UDim2.fromOffset(0, 169),
        Size = UDim2.fromOffset(186, 6),
        BackgroundColor3 = Theme.track,
        BorderSizePixel = 0,
    }, side)
    round(progTrack)
    local progFill = make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.blue,
        BorderSizePixel = 0,
    }, progTrack)
    round(progFill)

    local flagBtn, hintBtn
    local flagHover = false
    local function paintFlagBtn()
        local bg = Theme.track
        if flagMode then
            bg = Theme.danger
        elseif flagHover then
            bg = Theme.track:Lerp(Color3.new(1, 1, 1), 0.12)
        end
        tween(flagBtn, {
            BackgroundColor3 = bg,
            TextColor3 = flagMode and Color3.fromRGB(30, 14, 14) or Theme.text,
        }, 0.15)
        flagBtn.Text = flagMode and "Flag: ON" or "Flag mode"
    end
    flagBtn = make("TextButton", {
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = Theme.track,
        Position = UDim2.fromOffset(0, 188),
        Size = UDim2.fromOffset(90, 28),
        Font = FONT_B,
        TextSize = 13,
        TextColor3 = Theme.text,
        Text = "Flag mode",
    }, side)
    corner(flagBtn, 8)
    flagBtn.MouseEnter:Connect(function()
        flagHover = true
        paintFlagBtn()
    end)
    flagBtn.MouseLeave:Connect(function()
        flagHover = false
        paintFlagBtn()
    end)
    flagBtn.MouseButton1Click:Connect(function()
        flagMode = not flagMode
        paintFlagBtn()
    end)
    hintBtn = button(side, {
        Text = "Hint",
        TextSize = 13,
        Position = UDim2.fromOffset(96, 188),
        Size = UDim2.fromOffset(90, 28),
    }, function()
        ctx._hint()
    end)

    local helpLbl = label(side, {
        Text = touch and "Tap to reveal, hold to flag.\nTap a number to chord."
            or "Left click: reveal\nRight click: flag\nClick a number: chord  (or middle click)\nF flag mode · H hint · R new",
        Position = UDim2.fromOffset(0, 228),
        Size = UDim2.fromOffset(186, 80),
        TextSize = 12,
        Color = Theme.sub,
        Wrapped = true,
        YAlign = Enum.TextYAlignment.Top,
    })

    -- result card (shown after a game ends)
    local resCard = make("Frame", {
        Position = UDim2.fromOffset(0, 226),
        Size = UDim2.fromOffset(186, 104),
        BackgroundColor3 = Theme.panel,
        BorderSizePixel = 0,
        Visible = false,
    }, side)
    corner(resCard, 10)
    local resStroke = stroke(resCard, Theme.accent, 0.5)
    local resTitle = label(resCard, {
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, -28, 0, 26),
        Font = FONT_XB,
        TextSize = 22,
    })
    local resLine1 = label(resCard, {
        Position = UDim2.fromOffset(14, 38),
        Size = UDim2.new(1, -28, 0, 16),
        TextSize = 13,
        Color = Theme.text,
    })
    local resLine2 = label(resCard, {
        Position = UDim2.fromOffset(14, 56),
        Size = UDim2.new(1, -28, 0, 16),
        TextSize = 13,
        Color = Theme.sub,
    })
    local resBadge = label(resCard, {
        Position = UDim2.fromOffset(14, 78),
        Size = UDim2.new(1, -28, 0, 18),
        TextSize = 13,
        Font = FONT_XB,
        Color = Theme.gold,
    })

    button(side, {
        Text = "New game",
        Color = Theme.blue,
        TextColor = Color3.fromRGB(12, 22, 36),
        Position = UDim2.fromOffset(0, 340),
        Size = UDim2.fromOffset(90, 28),
    }, function()
        if state ~= "menu" then
            startNew()
        end
    end)
    button(side, {
        Text = "Menu",
        Position = UDim2.fromOffset(96, 340),
        Size = UDim2.fromOffset(90, 28),
    }, function()
        toMenu()
    end)

    ------------------------------------------------------------
    -- Board holder, banner, menu overlay
    ------------------------------------------------------------
    local holder = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(210, 16),
        Size = UDim2.fromOffset(394, 368),
    }, root)

    local banner = label(holder, {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        TextSize = 40,
        Font = FONT_XB,
        XAlign = CENTER,
        ZIndex = 24,
        Visible = false,
    })
    banner.TextStrokeTransparency = 0.5

    local function showBanner(text, color)
        bannerToken += 1
        local my = bannerToken
        banner.Text = text
        banner.TextColor3 = color or Theme.text
        banner.TextTransparency = 1
        banner.TextStrokeTransparency = 1
        banner.TextSize = 22
        banner.Visible = true
        tween(banner, { TextTransparency = 0, TextStrokeTransparency = 0.5, TextSize = 44 }, 0.4, BACK)
        task.delay(1.1, function()
            if alive and my == bannerToken then
                tween(banner, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.4)
                task.delay(0.42, function()
                    if my == bannerToken then
                        banner.Visible = false
                    end
                end)
            end
        end)
    end

    -- the setup screen is shown INSTEAD of the board (never on top of it),
    -- so nothing can ever sit over the cells while you play
    local overlay = make("Frame", {
        BackgroundColor3 = Color3.fromRGB(16, 17, 20),
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 20,
    }, holder)
    corner(overlay, 10)
    stroke(overlay, Theme.blue, 0.6, 2)
    local ovMenu = make("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
    }, overlay)

    local function selectorRow(title, getNames, getIdx, setIdx)
        local f = make("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(394, 30),
            Visible = false,
        }, ovMenu)
        label(f, {
            Text = title,
            Position = UDim2.fromOffset(40, 0),
            Size = UDim2.fromOffset(76, 30),
            TextSize = 13,
            Font = FONT_B,
            Color = Theme.sub,
        })
        local box = make("Frame", {
            Position = UDim2.fromOffset(116, 0),
            Size = UDim2.fromOffset(238, 30),
            BackgroundColor3 = Theme.track,
            BorderSizePixel = 0,
        }, f)
        corner(box, 8)
        local valueLbl = label(box, { XAlign = CENTER, Font = FONT_B, TextSize = 14 })
        local function refresh()
            valueLbl.Text = getNames()[getIdx()]
        end
        local function cycle(d)
            local n = #getNames()
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
            Position = UDim2.fromOffset(206, 0),
            Size = UDim2.fromOffset(32, 30),
            TextSize = 22,
        }, function()
            cycle(1)
        end)
        refresh()
        return { frame = f, refresh = refresh }
    end

    label(ovMenu, {
        Text = "MINESWEEPER",
        Position = UDim2.fromOffset(0, 14),
        Size = UDim2.new(1, 0, 0, 38),
        TextSize = 32,
        Font = FONT_XB,
        Color = Theme.blue,
        XAlign = CENTER,
    })
    local menuDesc = label(ovMenu, {
        Position = UDim2.fromOffset(0, 54),
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 14,
        Color = Theme.sub,
        XAlign = CENTER,
    })

    local function onConfig()
        store:set("mines.cfg", {
            diff = cfg.diff,
            cols = cfg.cols,
            rows = cfg.rows,
            dens = cfg.dens,
            marks = cfg.marks,
        })
        local c, r = dims()
        if c ~= cols or r ~= rows then
            buildBoard()
        else
            resetGame()
        end
        state = "menu"
        layoutMenu()
        updateInfo()
    end

    local rowDiff = selectorRow("DIFFICULTY", function()
        return DIFFS
    end, function()
        return table.find(DIFFS, cfg.diff)
    end, function(i)
        cfg.diff = DIFFS[i]
        onConfig()
    end)
    local rowMarks = selectorRow("? MARKS", function()
        return MARK_NAMES
    end, function()
        return cfg.marks and 2 or 1
    end, function(i)
        cfg.marks = i == 2
        onConfig()
    end)
    local rowCols = selectorRow("WIDTH", function()
        return COLS_NAMES
    end, function()
        return cfg.cols
    end, function(i)
        cfg.cols = i
        onConfig()
    end)
    local rowRows = selectorRow("HEIGHT", function()
        return ROWS_NAMES
    end, function()
        return cfg.rows
    end, function(i)
        cfg.rows = i
        onConfig()
    end)
    local rowMines = selectorRow("MINES", function()
        return DENS_NAMES
    end, function()
        return cfg.dens
    end, function(i)
        cfg.dens = i
        onConfig()
    end)

    local menuStats = label(ovMenu, {
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.fromOffset(0, 200),
        TextSize = 14,
        Font = FONT_B,
        XAlign = CENTER,
        Wrapped = true,
        YAlign = Enum.TextYAlignment.Top,
    })
    local playBtn = button(ovMenu, {
        Text = "PLAY",
        Color = Theme.blue,
        TextColor = Color3.fromRGB(12, 22, 36),
        TextSize = 18,
        Position = UDim2.fromOffset(97, 250),
        Size = UDim2.fromOffset(200, 42),
        Radius = 10,
    }, function()
        startNew()
    end)
    local menuHint = label(ovMenu, {
        Text = "Your first click is always safe.",
        Position = UDim2.fromOffset(0, 330),
        Size = UDim2.new(1, 0, 0, 16),
        TextSize = 12,
        Color = Theme.sub,
        XAlign = CENTER,
    })

    function layoutMenu()
        local custom = cfg.diff == "Custom"
        local y = custom and 84 or 112
        local function place(row, show)
            if show and not row.frame.Visible then
                row.frame.Position = UDim2.fromOffset(0, y + 10)
            end
            row.frame.Visible = show
            if show then
                tween(row.frame, { Position = UDim2.fromOffset(0, y) }, 0.35, QUINT)
                y += 38
            end
        end
        place(rowDiff, true)
        place(rowMarks, true)
        place(rowCols, custom)
        place(rowRows, custom)
        place(rowMines, custom)
        tween(menuStats, { Position = UDim2.fromOffset(0, y + 4) }, 0.35, QUINT)
        tween(playBtn, { Position = UDim2.fromOffset(97, y + 44) }, 0.35, QUINT)
        tween(menuHint, { Position = UDim2.fromOffset(0, y + 96) }, 0.35, QUINT)
    end

    function showOverlay()
        overlayName = "menu"
        overlay.Visible = true
        if board then
            board.Visible = false
        end
        ovMenu.Position = UDim2.fromOffset(0, 14)
        tween(ovMenu, { Position = UDim2.fromOffset(0, 0) }, 0.45, QUINT)
    end

    function hideOverlay()
        overlayName = nil
        overlay.Visible = false
        if board then
            board.Visible = true
        end
    end

    ------------------------------------------------------------
    -- Cell visuals
    ------------------------------------------------------------
    local function part(i, name)
        local cd = cells[i]
        local p = cd.parts[name]
        if p then
            return p
        end
        local btn = cd.btn
        if name == "num" then
            p = make("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Font = FONT_XB,
                TextSize = math.max(9, math.floor(cs * 0.62)),
                Text = "",
                TextTransparency = 1,
                ZIndex = 2,
                Visible = false,
            }, btn)
        elseif name == "flag" then
            p = make("Frame", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                ZIndex = 2,
                Visible = false,
            }, btn)
            make("UIScale", { Scale = 1 }, p)
            make("Frame", {
                Position = UDim2.fromScale(0.47, 0.2),
                Size = UDim2.fromScale(0.1, 0.58),
                BackgroundColor3 = PIECE,
                BorderSizePixel = 0,
                ZIndex = 2,
            }, p)
            make("Frame", {
                Position = UDim2.fromScale(0.14, 0.2),
                Size = UDim2.fromScale(0.34, 0.3),
                BackgroundColor3 = Theme.danger,
                BorderSizePixel = 0,
                ZIndex = 2,
            }, p)
            make("Frame", {
                Position = UDim2.fromScale(0.3, 0.76),
                Size = UDim2.fromScale(0.4, 0.1),
                BackgroundColor3 = PIECE,
                BorderSizePixel = 0,
                ZIndex = 2,
            }, p)
        elseif name == "q" then
            p = make("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Font = FONT_XB,
                TextSize = math.max(9, math.floor(cs * 0.62)),
                TextColor3 = Theme.gold,
                Text = "?",
                ZIndex = 2,
                Visible = false,
            }, btn)
        elseif name == "mine" then
            p = make("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromScale(0.52, 0.52),
                BackgroundColor3 = PIECE,
                BorderSizePixel = 0,
                ZIndex = 2,
                Visible = false,
            }, btn)
            round(p)
            make("UIScale", { Scale = 1 }, p)
            local dot = make("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromScale(0.35, 0.35),
                BackgroundColor3 = Color3.fromRGB(30, 31, 36),
                BorderSizePixel = 0,
                ZIndex = 3,
            }, p)
            round(dot)
        elseif name == "wrong" then
            p = make("TextLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
                Font = FONT_XB,
                TextSize = math.max(10, math.floor(cs * 0.8)),
                TextColor3 = Theme.danger,
                Text = "×",
                ZIndex = 4,
                Visible = false,
            }, btn)
        end
        cd.parts[name] = p
        return p
    end

    local function hideParts(i, except)
        for name, p in pairs(cells[i].parts) do
            if name ~= except then
                p.Visible = false
            end
        end
    end

    local function paintHidden(i, delay)
        hideParts(i)
        tween(cells[i].btn, { BackgroundColor3 = HIDDEN }, 0.2, QUAD, OUT, delay or 0)
    end

    local function paintFlag(i)
        hideParts(i, "flag")
        local p = part(i, "flag")
        p.Visible = true
        local sc = p:FindFirstChildOfClass("UIScale")
        sc.Scale = 1.5
        tween(sc, { Scale = 1 }, 0.3, BACK)
    end

    local function paintQuestion(i)
        hideParts(i, "q")
        part(i, "q").Visible = true
    end

    local function paintReveal(i, delay)
        local cd = cells[i]
        hideParts(i)
        tween(cd.btn, { BackgroundColor3 = REVEALED }, 0.18, QUAD, OUT, delay)
        local n = adj[i]
        if n > 0 then
            local l = part(i, "num")
            l.Text = tostring(n)
            l.TextColor3 = NUM_COLORS[n]
            l.Visible = true
            l.TextTransparency = 1
            tween(l, { TextTransparency = 0 }, 0.2, QUAD, OUT, delay + 0.05)
        end
    end

    local function paintMine(i, delay, exploded)
        local cd = cells[i]
        hideParts(i)
        tween(cd.btn, { BackgroundColor3 = exploded and Theme.danger or MINE_BG }, 0.15, QUAD, OUT, delay)
        local p = part(i, "mine")
        p.BackgroundColor3 = exploded and Color3.fromRGB(26, 27, 30) or PIECE
        p.Visible = false
        local gid = gameId
        task.delay(delay, function()
            if not alive or gid ~= gameId or not p.Parent then
                return
            end
            p.Visible = true
            local sc = p:FindFirstChildOfClass("UIScale")
            sc.Scale = exploded and 2 or 0.2
            tween(sc, { Scale = 1 }, 0.35, BACK)
        end)
    end

    local function paintWrong(i, delay)
        local cd = cells[i]
        tween(cd.btn, { BackgroundColor3 = MINE_BG }, 0.15, QUAD, OUT, delay)
        local gid = gameId
        task.delay(delay, function()
            if alive and gid == gameId and cd.btn.Parent then
                part(i, "wrong").Visible = true
            end
        end)
    end

    local function flashCell(i, color, times)
        local gid = gameId
        task.spawn(function()
            local btn = cells[i].btn
            for _ = 1, times or 3 do
                if not alive or gid ~= gameId or not btn.Parent then
                    return
                end
                tween(btn, { BackgroundColor3 = color }, 0.18)
                task.wait(0.22)
                local back = st[i] == 1 and REVEALED or HIDDEN
                tween(btn, { BackgroundColor3 = back }, 0.18)
                task.wait(0.22)
            end
        end)
    end

    ------------------------------------------------------------
    -- Info / stats
    ------------------------------------------------------------
    local function getStats()
        local k = statKey()
        if not k then
            return nil
        end
        return store:get("mines.stats." .. k, { played = 0, won = 0 })
    end

    local function getBest()
        local k = statKey()
        if not k then
            return nil
        end
        return store:get("mines.best." .. k, nil)
    end

    function updateLED()
        local left = mineCount - flags
        mineLed.Text = left < 0 and string.format("-%02d", math.min(-left, 99)) or string.format("%03d", math.min(left, 999))
        timeLed.Text = string.format("%03d", math.min(math.floor(elapsed), 999))
    end

    function updateInfo()
        subLbl.Text = cfg.diff .. "  ·  " .. cols .. "x" .. rows .. "  ·  " .. mineCount
        menuDesc.Text = cols .. " x " .. rows .. " board  ·  " .. mineCount .. " mines"
        local s, b = getStats(), getBest()
        bestLbl.Text = b and string.format("%.1fs", b) or "-"
        if s then
            wonLbl.Text = tostring(s.won)
            rateLbl.Text = s.played > 0 and (math.floor(s.won / s.played * 100 + 0.5) .. "%") or "-"
            menuStats.Text = (b and ("Best time:  " .. string.format("%.2fs", b)) or "No best time yet")
                .. "\n"
                .. s.won
                .. " won of "
                .. s.played
                .. " played"
        else
            wonLbl.Text = "-"
            rateLbl.Text = "-"
            menuStats.Text = "Custom boards don't track records"
        end
        local safe = total - mineCount
        progLbl.Text = revealed .. "/" .. safe
        tween(progFill, { Size = UDim2.fromScale(safe > 0 and revealed / safe or 0, 1) }, 0.3, QUINT)
        updateLED()
    end

    ------------------------------------------------------------
    -- Game logic
    ------------------------------------------------------------
    local function compute3BV()
        local seen, count = {}, 0
        for i = 1, total do
            if not mine[i] and adj[i] == 0 and not seen[i] then
                count += 1
                seen[i] = true
                local q, qi = { i }, 1
                while qi <= #q do
                    local k = q[qi]
                    qi += 1
                    for _, j in ipairs(nb[k]) do
                        if not mine[j] and not seen[j] then
                            seen[j] = true
                            if adj[j] == 0 then
                                q[#q + 1] = j
                            end
                        end
                    end
                end
            end
        end
        for i = 1, total do
            if not mine[i] and not seen[i] then
                count += 1
            end
        end
        return count
    end

    local function placeMines(first)
        local excluded = { [first] = true }
        for _, j in ipairs(nb[first]) do
            excluded[j] = true
        end
        local pool = {}
        for i = 1, total do
            if not excluded[i] then
                pool[#pool + 1] = i
            end
        end
        if #pool < mineCount then
            pool = {}
            for i = 1, total do
                if i ~= first then
                    pool[#pool + 1] = i
                end
            end
        end
        for k = 1, mineCount do
            local pick = rng:NextInteger(k, #pool)
            pool[k], pool[pick] = pool[pick], pool[k]
            mine[pool[k]] = true
        end
        for i = 1, total do
            local n = 0
            for _, j in ipairs(nb[i]) do
                if mine[j] then
                    n += 1
                end
            end
            adj[i] = n
        end
        bv = compute3BV()
    end

    local function revealFrom(i)
        if st[i] == 1 or st[i] == 2 then
            return
        end
        local queue, head = { i }, 1
        local depth = { [i] = 0 }
        st[i] = 1
        revealed += 1
        while head <= #queue do
            local k = queue[head]
            head += 1
            paintReveal(k, math.min(depth[k] * 0.022, 0.7))
            if adj[k] == 0 then
                for _, j in ipairs(nb[k]) do
                    if st[j] == 0 or st[j] == 3 then
                        st[j] = 1
                        revealed += 1
                        depth[j] = depth[k] + 1
                        queue[#queue + 1] = j
                    end
                end
            end
        end
    end

    local function checkWin()
        if state == "playing" and revealed >= total - mineCount then
            win()
        end
    end

    function onReveal(i)
        if state ~= "ready" and state ~= "playing" then
            return
        end
        if st[i] == 1 then
            chord(i)
            return
        end
        if flagMode then
            toggleFlag(i)
            return
        end
        if st[i] == 2 then
            return
        end
        if state == "ready" then
            placeMines(i)
            state = "playing"
            startTime = os.clock()
        end
        if mine[i] then
            lose(i)
            return
        end
        revealFrom(i)
        updateInfo()
        checkWin()
    end

    function chord(i)
        if state ~= "playing" or st[i] ~= 1 or adj[i] == 0 then
            return
        end
        local f = 0
        for _, j in ipairs(nb[i]) do
            if st[j] == 2 then
                f += 1
            end
        end
        if f ~= adj[i] then
            for _, j in ipairs(nb[i]) do
                if st[j] == 0 or st[j] == 3 then
                    flashCell(j, HOVER, 1)
                end
            end
            return
        end
        local hit
        for _, j in ipairs(nb[i]) do
            if st[j] == 0 or st[j] == 3 then
                if mine[j] then
                    hit = hit or j
                else
                    revealFrom(j)
                end
            end
        end
        if hit then
            lose(hit)
            return
        end
        updateInfo()
        checkWin()
    end

    function toggleFlag(i)
        if state ~= "ready" and state ~= "playing" then
            return
        end
        local s = st[i]
        if s == 1 then
            return
        end
        if s == 0 then
            st[i] = 2
            flags += 1
            paintFlag(i)
        elseif s == 2 then
            flags -= 1
            if cfg.marks then
                st[i] = 3
                paintQuestion(i)
            else
                st[i] = 0
                paintHidden(i)
            end
        else
            st[i] = 0
            paintHidden(i)
        end
        updateLED()
    end

    local function recordResult(won)
        local k = statKey()
        local result = { newBest = false }
        if not k then
            return result
        end
        local s = store:get("mines.stats." .. k, { played = 0, won = 0 })
        s = { played = s.played + 1, won = s.won + (won and 1 or 0) }
        store:set("mines.stats." .. k, s)
        if won and not assisted then
            local b = store:get("mines.best." .. k, nil)
            if not b or elapsed < b then
                store:set("mines.best." .. k, elapsed)
                result.newBest = true
            end
        end
        return result
    end

    local function showResult(title, color, line1, line2, badge)
        resCard.Visible = true
        helpLbl.Visible = false
        resTitle.Text = title
        resTitle.TextColor3 = color
        resStroke.Color = color
        resLine1.Text = line1
        resLine2.Text = line2
        resBadge.Text = badge or ""
        resCard.Position = UDim2.fromOffset(0, 240)
        tween(resCard, { Position = UDim2.fromOffset(0, 226) }, 0.45, QUINT)
        resTitle.TextSize = 30
        tween(resTitle, { TextSize = 22 }, 0.45, BACK)
    end

    function lose(i)
        state = "lost"
        elapsed = os.clock() - startTime
        face.Text = "X("
        recordResult(false)

        paintMine(i, 0, true)
        local ci, ri = pos(i)
        for j = 1, total do
            if j ~= i then
                local cj, rj = pos(j)
                local d = math.min(math.max(math.abs(cj - ci), math.abs(rj - ri)) * 0.035, 0.9) + 0.15
                if mine[j] and st[j] ~= 2 then
                    paintMine(j, d, false)
                elseif not mine[j] and st[j] == 2 then
                    paintWrong(j, d)
                end
            end
        end

        local flash = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Theme.danger,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
            ZIndex = 30,
        }, board)
        tween(flash, { BackgroundTransparency = 1 }, 0.55)
        task.delay(0.6, function()
            flash:Destroy()
        end)
        local gid = gameId
        task.spawn(function()
            for k = 1, 8 do
                if not alive or gid ~= gameId then
                    return
                end
                local m = math.floor((9 - k) * 0.9)
                board.Position = UDim2.new(0.5, rng:NextInteger(-m, m), 0.5, rng:NextInteger(-m, m))
                task.wait(0.035)
            end
            if alive and gid == gameId then
                board.Position = UDim2.fromScale(0.5, 0.5)
            end
        end)

        showBanner("BOOM!", Theme.danger)
        local safe = total - mineCount
        showResult(
            "BOOM!",
            Theme.danger,
            string.format("Cleared %d%%  (%d/%d)", safe > 0 and math.floor(revealed / safe * 100) or 0, revealed, safe),
            string.format("Time %.1fs  ·  3BV %d", elapsed, bv),
            nil
        )
        updateInfo()
    end

    function win()
        state = "won"
        elapsed = os.clock() - startTime
        face.Text = "B)"
        local res = recordResult(true)

        -- plant flags on every remaining mine
        local gid = gameId
        local n = 0
        for i = 1, total do
            if mine[i] and st[i] ~= 2 then
                n += 1
                st[i] = 2
                local d = math.min(n * 0.015, 0.8)
                task.delay(d, function()
                    if alive and gid == gameId and cells[i] and cells[i].btn.Parent then
                        paintFlag(i)
                    end
                end)
            end
        end
        flags = mineCount
        updateInfo()

        -- confetti
        local colors = { Theme.accent, Theme.blue, Theme.gold, Theme.purple, Theme.orange, Theme.danger }
        local bh = rows * cs
        for _ = 1, 36 do
            task.delay(rng:NextNumber(0, 0.5), function()
                if not alive or gid ~= gameId or not board.Parent then
                    return
                end
                local x, y = rng:NextNumber(0, cols * cs), rng:NextNumber(0, bh)
                local p = make("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromOffset(x, y),
                    Size = UDim2.fromOffset(6, 6),
                    BackgroundColor3 = colors[rng:NextInteger(1, #colors)],
                    BorderSizePixel = 0,
                    Rotation = rng:NextInteger(0, 90),
                    ZIndex = 15,
                }, board)
                tween(p, {
                    Position = UDim2.fromOffset(x + rng:NextInteger(-30, 30), y + rng:NextInteger(30, 80)),
                    BackgroundTransparency = 1,
                    Rotation = p.Rotation + rng:NextInteger(-180, 180),
                }, 0.9, QUINT)
                task.delay(1, function()
                    p:Destroy()
                end)
            end)
        end

        showBanner("CLEARED!", Theme.accent)
        local badge
        if assisted then
            badge = "Hints used - no record"
        elseif res.newBest then
            badge = "NEW BEST TIME!"
        end
        showResult(
            "CLEARED!",
            Theme.accent,
            string.format("Time %.2fs", elapsed),
            string.format("3BV %d  ·  %.2f 3BV/s", bv, elapsed > 0 and bv / elapsed or 0),
            badge
        )
    end

    ------------------------------------------------------------
    -- Hint solver (uses only what the player can see)
    ------------------------------------------------------------
    local function findHint()
        local knownMine, knownSafe = {}, {}
        local changed = true
        while changed do
            changed = false
            for i = 1, total do
                if st[i] == 1 and adj[i] > 0 then
                    local unknown, minesKnown = {}, 0
                    for _, j in ipairs(nb[i]) do
                        if st[j] ~= 1 then
                            if knownMine[j] then
                                minesKnown += 1
                            elseif not knownSafe[j] then
                                unknown[#unknown + 1] = j
                            end
                        end
                    end
                    local remaining = adj[i] - minesKnown
                    if #unknown > 0 then
                        if remaining == 0 then
                            for _, j in ipairs(unknown) do
                                knownSafe[j] = true
                            end
                            changed = true
                        elseif remaining == #unknown then
                            for _, j in ipairs(unknown) do
                                knownMine[j] = true
                            end
                            changed = true
                        end
                    end
                end
            end
        end
        local fallbackSafe
        for j in pairs(knownSafe) do
            if st[j] ~= 1 then
                if st[j] ~= 2 then
                    return "safe", j
                end
                fallbackSafe = fallbackSafe or j
            end
        end
        if fallbackSafe then
            return "badflag", fallbackSafe
        end
        for j in pairs(knownMine) do
            if st[j] ~= 2 then
                return "mine", j
            end
        end
        return nil
    end

    ctx._hint = function()
        if state == "ready" then
            showBanner("Click anywhere to begin", Theme.blue)
            return
        end
        if state ~= "playing" then
            return
        end
        local kind, i = findHint()
        assisted = true
        hints += 1
        if kind == "safe" then
            flashCell(i, Theme.accent, 3)
            showBanner("Safe cell", Theme.accent)
        elseif kind == "mine" then
            flashCell(i, Theme.danger, 3)
            showBanner("Mine here", Theme.danger)
        elseif kind == "badflag" then
            flashCell(i, Theme.warn, 3)
            showBanner("Wrong flag!", Theme.warn)
        else
            hints -= 1
            assisted = hints > 0
            showBanner("No sure move - guess!", Theme.warn)
        end
    end

    ------------------------------------------------------------
    -- Board construction
    ------------------------------------------------------------
    local function safe(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                warn("[OldArcade/Minesweeper] " .. tostring(err))
            end
        end
    end

    local function wire(i, btn)
        btn.MouseEnter:Connect(safe(function()
            if (st[i] == 0 or st[i] == 3) and (state == "ready" or state == "playing") then
                tween(btn, { BackgroundColor3 = HOVER }, 0.08)
            end
        end))
        btn.MouseLeave:Connect(safe(function()
            if st[i] == 0 or st[i] == 3 then
                tween(btn, { BackgroundColor3 = HIDDEN }, 0.12)
            end
        end))
        btn.InputBegan:Connect(safe(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton2 then
                if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                    longFired = true -- swallow the left click that follows
                    chord(i)
                else
                    toggleFlag(i)
                end
            elseif t == Enum.UserInputType.MouseButton3 then
                chord(i)
            elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                longFired = false
                if
                    t == Enum.UserInputType.MouseButton1
                    and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                then
                    longFired = true
                    chord(i)
                end
                if state == "ready" or state == "playing" then
                    setFace(":O")
                end
                if t == Enum.UserInputType.Touch then
                    holdToken += 1
                    local my = holdToken
                    task.delay(0.4, function()
                        if alive and my == holdToken and (state == "ready" or state == "playing") and st[i] ~= 1 then
                            longFired = true
                            toggleFlag(i)
                        end
                    end)
                end
            end
        end))
        btn.InputEnded:Connect(safe(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                holdToken += 1
                if state == "ready" or state == "playing" then
                    setFace(faceBase)
                end
            end
        end))
        btn.Activated:Connect(safe(function()
            if longFired then
                longFired = false
                return
            end
            onReveal(i)
        end))
    end

    function resetGame()
        gameId += 1
        local _, _, m = dims()
        mineCount = m
        mine, adj, st = {}, {}, {}
        revealed, flags = 0, 0
        elapsed, startTime = 0, 0
        assisted, hints, bv = false, 0, 0
        for i = 1, total do
            st[i] = 0
            local c, r = pos(i)
            paintHidden(i, (c + r) * 0.008)
        end
        face.Text = faceBase
        resCard.Visible = false
        helpLbl.Visible = true
        bannerToken += 1
        banner.Visible = false
        if board then
            board.Position = UDim2.fromScale(0.5, 0.5)
        end
        updateInfo()
    end

    function buildBoard()
        if board then
            board:Destroy()
        end
        cols, rows, mineCount = dims()
        total = cols * rows
        cs = math.clamp(math.floor(math.min(386 / cols, 356 / rows)), 12, 36)

        board = make("Frame", {
            Name = "Board",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(cols * cs + 1, rows * cs + 1),
            BackgroundColor3 = Color3.fromRGB(16, 17, 20),
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, holder)
        corner(board, 6)
        boardStroke = stroke(board, Theme.blue, 0.55, 2)
        board.Visible = overlayName == nil

        nb, cells = {}, {}
        local radius = cs >= 20 and 4 or 2
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                local i = r * cols + c + 1
                local list = {}
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if not (dr == 0 and dc == 0) then
                            local nc, nr = c + dc, r + dr
                            if nc >= 0 and nc < cols and nr >= 0 and nr < rows then
                                list[#list + 1] = nr * cols + nc + 1
                            end
                        end
                    end
                end
                nb[i] = list

                local btn = make("TextButton", {
                    AutoButtonColor = false,
                    Active = true,
                    Selectable = false,
                    Text = "",
                    BorderSizePixel = 0,
                    BackgroundColor3 = HIDDEN,
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(c * cs + 1, r * cs + 1),
                    Size = UDim2.fromOffset(cs - 1, cs - 1),
                }, board)
                make("UICorner", { CornerRadius = UDim.new(0, radius) }, btn)
                cells[i] = { btn = btn, parts = {} }
                wire(i, btn)
                tween(btn, { BackgroundTransparency = 0 }, 0.3, QUAD, OUT, (c + r) * 0.012)
            end
        end
        resetGame()
    end

    ------------------------------------------------------------
    -- Flow
    ------------------------------------------------------------
    function startNew()
        resetGame()
        state = "ready"
        hideOverlay()
    end

    function toMenu()
        state = "menu"
        resetGame()
        layoutMenu()
        showOverlay()
    end

    ------------------------------------------------------------
    -- Keys (sunk so the character doesn't react)
    ------------------------------------------------------------
    local K = Enum.KeyCode
    local ACTION = "OldArcadeMines"
    ContextActionService:BindActionAtPriority(ACTION, function(_, inputState, input)
        if inputState == Enum.UserInputState.Begin then
            local code = input.KeyCode
            if code == K.F then
                flagMode = not flagMode
                paintFlagBtn()
            elseif code == K.H then
                ctx._hint()
            elseif code == K.R or code == K.N then
                if state ~= "menu" then
                    startNew()
                end
            elseif code == K.Space or code == K.Return then
                if state == "menu" or state == "won" or state == "lost" then
                    startNew()
                end
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.ContextActionPriority.High.Value, K.F, K.H, K.R, K.N, K.Space, K.Return)

    ------------------------------------------------------------
    -- Timer
    ------------------------------------------------------------
    connect(RunService.Heartbeat, function()
        if not alive then
            return
        end
        if state == "playing" then
            elapsed = os.clock() - startTime
            timeLed.Text = string.format("%03d", math.min(math.floor(elapsed), 999))
        end
    end)

    -- releasing the mouse/finger anywhere puts the face back to normal
    connect(UserInputService.InputEnded, function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            holdToken += 1
            if state == "ready" or state == "playing" then
                setFace(faceBase)
            end
        end
    end)

    ------------------------------------------------------------
    -- Start
    ------------------------------------------------------------
    buildBoard()
    layoutMenu()
    state = "menu"
    updateInfo()
    showOverlay()

    local self = {}
    function self:Destroy()
        alive = false
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
for _, n in ipairs({ "OldArcade_Minesweeper", "OldArcade_Hub" }) do
    local o = playerGui:FindFirstChild(n)
    if o then
        o:Destroy()
    end
end

local gui = make("ScreenGui", {
    Name = "OldArcade_Minesweeper",
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
local TITLE = 'ARCADE  <font color="#878b94">/  MINESWEEPER</font>'
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

local okCreate, result = pcall(MinesweeperGame, { Parent = content, Store = Store })
if okCreate then
    gameObj = result
else
    warn("[OldArcade] MINESWEEPER failed to start: " .. tostring(result))
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
