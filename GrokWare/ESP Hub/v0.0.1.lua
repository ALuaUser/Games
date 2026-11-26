--[[
    Universal ESP + Aimbot
    UI: LiteUI (Grokware v0.0.7)
    Works in most Roblox games (player-based).
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[Universal] LiteUI failed:", Lite)
    return
end

----------------------------------------------------------------
-- Services
----------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local LP  = Players.LocalPlayer
local Cam = Workspace.CurrentCamera

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    -- ESP
    esp         = true,
    boxes       = true,
    names       = true,
    health      = true,
    distance    = true,
    tracers     = true,
    chams       = true,
    teamCheck   = true,
    maxDist     = 2000,
    colEnemy    = Color3.fromRGB(255, 70, 70),
    colAlly     = Color3.fromRGB(70, 180, 255),

    -- Aimbot
    aimbot      = false,
    aimKey      = Enum.KeyCode.E,
    aimHold     = true,
    aimSmooth   = 0.25,
    aimPart     = "Head", -- Head | HumanoidRootPart | UpperTorso
    aimFov      = 150,
    showFov     = true,
    wallcheck   = true,
    aimTeamCheck = true,
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function alive(char)
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function isEnemy(pl)
    if not pl or pl == LP then return false end
    if not CFG.teamCheck and not CFG.aimTeamCheck then return true end
    if pl.Team == nil or LP.Team == nil then return true end
    return pl.Team ~= LP.Team
end

local function getPart(char, prefer)
    prefer = prefer or "Head"
    return char:FindFirstChild(prefer)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function visible(from, to, char)
    if not CFG.wallcheck then return true end
    rayParams.FilterDescendantsInstances = { LP.Character, char }
    return Workspace:Raycast(from, to - from, rayParams) == nil
end

----------------------------------------------------------------
-- FOV circle
----------------------------------------------------------------
local fovCircle
pcall(function()
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1.5
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
    fovCircle.Transparency = 0.4
    fovCircle.Visible = false
end)

RunService.RenderStepped:Connect(function()
    if not fovCircle then return end
    local show = CFG.showFov and CFG.aimbot
    fovCircle.Visible = show
    if show then
        fovCircle.Radius = CFG.aimFov
        fovCircle.Position = Cam.ViewportSize / 2
    end
end)

----------------------------------------------------------------
-- Target pick (aimbot)
----------------------------------------------------------------
local function pickTarget()
    local center = Cam.ViewportSize / 2
    local best, bestDist = nil, CFG.aimFov
    local origin = Cam.CFrame.Position

    for _, pl in ipairs(Players:GetPlayers()) do
        if not isEnemy(pl) then continue end
        if CFG.aimTeamCheck and pl.Team and LP.Team and pl.Team == LP.Team then continue end
        local char = pl.Character
        if not alive(char) then continue end
        local part = getPart(char, CFG.aimPart)
        if not part then continue end

        local sp, on = Cam:WorldToViewportPoint(part.Position)
        if not on or sp.Z < 0 then continue end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d >= bestDist then continue end
        if not visible(origin, part.Position, char) then continue end

        best, bestDist = part, d
    end
    return best
end

----------------------------------------------------------------
-- Aimbot
----------------------------------------------------------------
local holding = false
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.aimKey then holding = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CFG.aimKey then holding = false end
end)

RunService.RenderStepped:Connect(function()
    if not CFG.aimbot then return end
    if CFG.aimHold and not holding then return end
    local part = pickTarget()
    if not part then return end
    local goal = CFrame.lookAt(Cam.CFrame.Position, part.Position)
    Cam.CFrame = Cam.CFrame:Lerp(goal, math.clamp(CFG.aimSmooth, 0.05, 1))
end)

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------
local drawings = {} -- [player] = { box, name, health, tracer, chams }

local function clearPlayer(pl)
    local d = drawings[pl]
    if not d then return end
    for _, x in pairs(d) do
        pcall(function()
            if typeof(x) == "Instance" then
                x:Destroy()
            elseif x and x.Remove then
                x:Remove()
            end
        end)
    end
    drawings[pl] = nil
end

local function dnew(kind)
    if not Drawing then return nil end
    local ok2, o = pcall(Drawing.new, kind)
    return ok2 and o or nil
end

local function ensure(pl)
    if drawings[pl] then return drawings[pl] end
    local d = {}
    d.box = dnew("Square")
    if d.box then d.box.Thickness = 1; d.box.Filled = false; d.box.Visible = false end
    d.name = dnew("Text")
    if d.name then d.name.Size = 13; d.name.Center = true; d.name.Outline = true; d.name.Visible = false end
    d.health = dnew("Line")
    if d.health then d.health.Thickness = 2; d.health.Visible = false end
    d.tracer = dnew("Line")
    if d.tracer then d.tracer.Thickness = 1; d.tracer.Visible = false end
    drawings[pl] = d
    return d
end

local function worldBox(char)
    local parts = {}
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            table.insert(parts, p)
        end
    end
    if #parts == 0 then
        local r = char:FindFirstChild("HumanoidRootPart")
        if r then
            local sp, on = Cam:WorldToViewportPoint(r.Position)
            if on and sp.Z > 0 then
                return Vector2.new(sp.X - 20, sp.Y - 30), Vector2.new(40, 60)
            end
        end
        return nil
    end

    local minV = Vector3.new(1e9, 1e9, 1e9)
    local maxV = Vector3.new(-1e9, -1e9, -1e9)
    for _, p in ipairs(parts) do
        local cf, sz = p.CFrame, p.Size / 2
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                for _, szz in ipairs({ -1, 1 }) do
                    local w = cf * Vector3.new(sx * sz.X, sy * sz.Y, szz * sz.Z)
                    minV = Vector3.new(math.min(minV.X, w.X), math.min(minV.Y, w.Y), math.min(minV.Z, w.Z))
                    maxV = Vector3.new(math.max(maxV.X, w.X), math.max(maxV.Y, w.Y), math.max(maxV.Z, w.Z))
                end
            end
        end
    end

    local corners = {
        Vector3.new(minV.X, minV.Y, minV.Z), Vector3.new(maxV.X, minV.Y, minV.Z),
        Vector3.new(minV.X, maxV.Y, minV.Z), Vector3.new(maxV.X, maxV.Y, minV.Z),
        Vector3.new(minV.X, minV.Y, maxV.Z), Vector3.new(maxV.X, minV.Y, maxV.Z),
        Vector3.new(minV.X, maxV.Y, maxV.Z), Vector3.new(maxV.X, maxV.Y, maxV.Z),
    }
    local min2, max2 = Vector2.new(1e9, 1e9), Vector2.new(-1e9, -1e9)
    local any = false
    for _, c in ipairs(corners) do
        local sp, on = Cam:WorldToViewportPoint(c)
        if on and sp.Z > 0 then
            any = true
            min2 = Vector2.new(math.min(min2.X, sp.X), math.min(min2.Y, sp.Y))
            max2 = Vector2.new(math.max(max2.X, sp.X), math.max(max2.Y, sp.Y))
        end
    end
    if not any then return nil end
    return min2, max2 - min2
end

local function updateEsp()
    if not CFG.esp then
        for pl in pairs(drawings) do clearPlayer(pl) end
        return
    end

    local origin = Cam.CFrame.Position
    local screenBottom = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y)
    local keep = {}

    for _, pl in ipairs(Players:GetPlayers()) do
        if pl == LP then continue end
        local char = pl.Character
        if not alive(char) then continue end

        local enemy = isEnemy(pl)
        if CFG.teamCheck and not enemy then
            -- still allow allies if teamCheck only filters color; show everyone unless teamCheck hides allies
            -- with teamCheck on we still draw allies in ally color
        end

        local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
        if not root then continue end
        local dist = (root.Position - origin).Magnitude
        if dist > CFG.maxDist then continue end

        keep[pl] = true
        local d = ensure(pl)
        local color = enemy and CFG.colEnemy or CFG.colAlly

        -- chams
        if CFG.chams then
            local hl = d.chams
            if not hl or not hl.Parent then
                hl = Instance.new("Highlight")
                hl.Name = "UniChams"
                hl.FillTransparency = 0.55
                hl.OutlineTransparency = 0.2
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = char
                d.chams = hl
            end
            hl.Adornee = char
            hl.FillColor = color
            hl.OutlineColor = color
            hl.Enabled = true
        elseif d.chams then
            d.chams.Enabled = false
        end

        local topLeft, size = worldBox(char)
        if not topLeft then
            if d.box then d.box.Visible = false end
            if d.name then d.name.Visible = false end
            if d.health then d.health.Visible = false end
            if d.tracer then d.tracer.Visible = false end
            continue
        end

        if d.box then
            d.box.Visible = CFG.boxes
            d.box.Color = color
            d.box.Position = topLeft
            d.box.Size = size
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local hp = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 1

        if d.name then
            d.name.Visible = CFG.names or CFG.distance
            d.name.Color = color
            local bits = {}
            if CFG.names then table.insert(bits, pl.Name) end
            if CFG.distance then table.insert(bits, string.format("[%dm]", math.floor(dist))) end
            if CFG.health and hum then table.insert(bits, string.format("%dHP", math.floor(hum.Health))) end
            d.name.Text = table.concat(bits, " ")
            d.name.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y - 14)
        end

        if d.health then
            d.health.Visible = CFG.health
            local h = size.Y * hp
            d.health.From = Vector2.new(topLeft.X - 4, topLeft.Y + size.Y)
            d.health.To   = Vector2.new(topLeft.X - 4, topLeft.Y + size.Y - h)
            d.health.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 40)
        end

        if d.tracer then
            d.tracer.Visible = CFG.tracers
            d.tracer.Color = color
            d.tracer.From = screenBottom
            d.tracer.To = Vector2.new(topLeft.X + size.X / 2, topLeft.Y + size.Y)
        end
    end

    for pl in pairs(drawings) do
        if not keep[pl] then clearPlayer(pl) end
    end
end

RunService.RenderStepped:Connect(function()
    pcall(updateEsp)
end)

Players.PlayerRemoving:Connect(clearPlayer)

----------------------------------------------------------------
-- LiteUI
----------------------------------------------------------------
Lite.Themes.uni = {
    bg     = Color3.fromRGB(16, 18, 24),
    line   = Color3.fromRGB(42, 48, 60),
    text   = Color3.fromRGB(235, 240, 245),
    sub    = Color3.fromRGB(140, 150, 165),
    accent = Color3.fromRGB(90, 160, 255),
    warn   = Color3.fromRGB(255, 190, 60),
    danger = Color3.fromRGB(255, 80, 80),
    track  = Color3.fromRGB(30, 34, 44),
}

local ui = Lite.new({
    Title = "Universal",
    Subtitle = "ESP · Aimbot",
    Width = 340,
    Theme = "uni",
})

local tab = ui:Tabs({ "ESP", "Aimbot", "Settings" }, { MaxHeight = 300 })

----------------------------------------------------------------
-- ESP tab
----------------------------------------------------------------
local esp = tab.ESP
esp:Section("Display")
esp:Toggle({ Name = "Enable ESP", Flag = "esp", Default = CFG.esp, Callback = function(v)
    CFG.esp = v
    if not v then for pl in pairs(drawings) do clearPlayer(pl) end end
end })
esp:Toggle({ Name = "Boxes", Flag = "boxes", Default = CFG.boxes, Callback = function(v) CFG.boxes = v end })
esp:Toggle({ Name = "Names", Flag = "names", Default = CFG.names, Callback = function(v) CFG.names = v end })
esp:Toggle({ Name = "Health bar", Flag = "health", Default = CFG.health, Callback = function(v) CFG.health = v end })
esp:Toggle({ Name = "Distance", Flag = "distance", Default = CFG.distance, Callback = function(v) CFG.distance = v end })
esp:Toggle({ Name = "Tracers", Flag = "tracers", Default = CFG.tracers, Callback = function(v) CFG.tracers = v end })
esp:Toggle({ Name = "Chams", Flag = "chams", Default = CFG.chams, Callback = function(v) CFG.chams = v end })
esp:Slider({ Name = "Max distance", Flag = "maxDist", Min = 100, Max = 5000, Default = CFG.maxDist, Step = 50, Callback = function(v) CFG.maxDist = v end })

esp:Section("Filters")
esp:Toggle({ Name = "Team check (colour)", Flag = "teamCheck", Default = CFG.teamCheck, Callback = function(v) CFG.teamCheck = v end })

esp:Section("Colours")
local PRESETS = {
    Red = Color3.fromRGB(255, 70, 70),
    Orange = Color3.fromRGB(255, 160, 40),
    Green = Color3.fromRGB(70, 220, 100),
    Cyan = Color3.fromRGB(60, 200, 255),
    Blue = Color3.fromRGB(70, 120, 255),
    Purple = Color3.fromRGB(180, 80, 255),
    White = Color3.fromRGB(240, 240, 240),
}
local names = { "Red", "Orange", "Green", "Cyan", "Blue", "Purple", "White" }
esp:Dropdown({ Name = "Enemy", Flag = "colEnemy", Options = names, Default = "Red",
    Callback = function(v) CFG.colEnemy = PRESETS[v] or CFG.colEnemy end })
esp:Dropdown({ Name = "Ally", Flag = "colAlly", Options = names, Default = "Cyan",
    Callback = function(v) CFG.colAlly = PRESETS[v] or CFG.colAlly end })

----------------------------------------------------------------
-- Aimbot tab
----------------------------------------------------------------
local aim = tab.Aimbot
aim:Section("Aimbot")
aim:Toggle({ Name = "Enable Aimbot", Flag = "aimbot", Default = CFG.aimbot, Callback = function(v) CFG.aimbot = v end })
aim:Toggle({ Name = "Hold key (E)", Flag = "aimHold", Default = CFG.aimHold, Callback = function(v) CFG.aimHold = v end })
aim:Slider({ Name = "Smoothness", Flag = "aimSmooth", Min = 0.05, Max = 1, Default = CFG.aimSmooth, Step = 0.01, Callback = function(v) CFG.aimSmooth = v end })
aim:Slider({ Name = "FOV", Flag = "aimFov", Min = 40, Max = 500, Default = CFG.aimFov, Step = 5, Callback = function(v) CFG.aimFov = v end })
aim:Dropdown({
    Name = "Aim part",
    Flag = "aimPart",
    Options = { "Head", "UpperTorso", "HumanoidRootPart" },
    Default = CFG.aimPart,
    Callback = function(v) CFG.aimPart = v end,
})
aim:Toggle({ Name = "Show FOV ring", Flag = "showFov", Default = CFG.showFov, Callback = function(v) CFG.showFov = v end })
aim:Toggle({ Name = "Wall check", Flag = "wallcheck", Default = CFG.wallcheck, Callback = function(v) CFG.wallcheck = v end })
aim:Toggle({ Name = "Team check", Flag = "aimTeamCheck", Default = CFG.aimTeamCheck, Callback = function(v) CFG.aimTeamCheck = v end })
aim:Label({ Text = "Hold E (or toggle hold off) to aim" })

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------
local set = tab.Settings
set:Section("UI")
ui:Settings({ Panel = set })
set:Separator()
set:Section("Profiles")
ui:Profiles({ Panel = set })
set:Separator()
set:Button({
    Name = "Unload",
    Callback = function()
        CFG.esp = false
        CFG.aimbot = false
        for pl in pairs(drawings) do clearPlayer(pl) end
        if fovCircle then pcall(function() fovCircle:Remove() end) end
        ui:Destroy()
    end,
})

----------------------------------------------------------------
-- Boot
----------------------------------------------------------------
ui:Show()
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Universal",
        Text = "ESP + Aimbot loaded",
        Duration = 3,
    })
end)
print("[Universal] ESP + Aimbot loaded")
