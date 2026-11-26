--[[
    Voxel Wars  ·  Full Utility Hub
    PlaceId: 78884249003161
    UI: LiteUI (Grokware v0.0.7)

    Combat   — aimbot, silent aim, no recoil/spread
    Visuals  — boxes, names, health, distance, tracers, chams
    Movement — speed, fly, noclip
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[VoxelWars] LiteUI failed:", Lite)
    return
end

----------------------------------------------------------------
-- Services
----------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local LP  = Players.LocalPlayer
local Cam = Workspace.CurrentCamera

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    -- Combat / Aimbot
    aimbot          = false,
    aimbotKey       = Enum.KeyCode.E,
    aimbotHold      = true,
    aimSmooth       = 0.22,
    aimPart         = "Head", -- Head | UpperTorso
    aimFov          = 140,
    aimShowFov      = true,

    -- Silent
    silent          = true,
    silentFov       = 160,
    hitChance       = 90,
    headChance      = 60,
    wallcheck       = true,
    wallbang        = false, -- force target + aim through walls
    targetPlayers   = true,
    targetBots      = true,
    teamCheck       = true,

    -- Weapon
    noRecoil        = true,
    noSpread        = true,

    -- Visuals
    espEnabled      = true,
    espBoxes        = true,
    espNames        = true,
    espHealth       = true,
    espDistance     = true,
    espTracers      = true,
    espChams        = true,
    espPlayers      = true,
    espBots         = true,
    espAllies       = false,
    maxEspDist      = 1500,
    colEnemy        = Color3.fromRGB(255, 70, 70),
    colAlly         = Color3.fromRGB(70, 180, 255),
    colBot          = Color3.fromRGB(255, 180, 40),

    -- Movement
    speedOn         = false,
    speedVal        = 28,
    flyOn           = false,
    flySpeed        = 60,
    noclipOn        = false,
}

----------------------------------------------------------------
-- Fire remotes + ballistics
----------------------------------------------------------------
local FIRE = {}
local remotesFolder = ReplicatedStorage:FindFirstChild("Voxel")
    and ReplicatedStorage.Voxel:FindFirstChild("Remotes")
if remotesFolder then
    for _, n in ipairs({
        "FireRifle", "FireSMG", "FireLMG", "FirePistol", "FireDMR",
        "FireSniper", "FireShotgun", "FireHandCannon", "FireMinigun",
        "FireAA", "FireRocket", "FireFlame",
    }) do
        local r = remotesFolder:FindFirstChild(n)
        if r then FIRE[r] = n end
    end
end

local Ballistics
pcall(function()
    Ballistics = require(ReplicatedStorage.Voxel.Ballistics)
end)

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function alive(model)
    if not model then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0 and model:GetAttribute("Alive") ~= false
end

local function isEnemyPlayer(pl)
    if not pl or pl == LP then return false end
    if not CFG.teamCheck then return true end
    if pl.Team == nil or LP.Team == nil then return true end
    return pl.Team ~= LP.Team
end

local function isEnemyBot(model)
    if not CFG.teamCheck then return true end
    local myTeam = tostring(LP.Team)
    local botTeam = model:GetAttribute("Team")
    if botTeam == nil then return true end
    return tostring(botTeam) ~= myTeam
end

local function getPart(model, prefer)
    prefer = prefer or CFG.aimPart
    return model:FindFirstChild(prefer)
        or model:FindFirstChild("Head")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("HumanoidRootPart")
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function visible(from, to, model)
    -- wallbang OR wallcheck off = always allow
    if CFG.wallbang or not CFG.wallcheck then return true end
    rayParams.FilterDescendantsInstances = { LP.Character, model }
    local hit = Workspace:Raycast(from, to - from, rayParams)
    return hit == nil or (hit.Instance and hit.Instance:IsDescendantOf(model))
end

----------------------------------------------------------------
-- Target picker (FOV, players + bots)
----------------------------------------------------------------
local function pickTarget(fov)
    fov = fov or CFG.silentFov
    local center = Cam.ViewportSize / 2
    local best, bestDist = nil, fov
    local origin = Cam.CFrame.Position

    local function consider(model, isBot)
        if not alive(model) then return end
        local part = getPart(model)
        if not part then return end
        local sp, onScreen = Cam:WorldToViewportPoint(part.Position)
        if not onScreen or sp.Z < 0 then return end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d >= bestDist then return end
        if not visible(origin, part.Position, model) then return end
        best, bestDist = model, d
    end

    if CFG.targetPlayers then
        for _, pl in ipairs(Players:GetPlayers()) do
            if isEnemyPlayer(pl) and pl.Character then
                consider(pl.Character, false)
            end
        end
    end

    if CFG.targetBots then
        local rigs = Workspace:FindFirstChild("BotRigs")
        if rigs then
            for _, m in ipairs(rigs:GetChildren()) do
                if isEnemyBot(m) then consider(m, true) end
            end
        end
    end

    return best
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
    fovCircle.Transparency = 0.35
    fovCircle.Visible = false
end)

RunService.RenderStepped:Connect(function()
    if not fovCircle then return end
    local show = CFG.aimShowFov and (CFG.aimbot or CFG.silent)
    fovCircle.Visible = show
    if show then
        fovCircle.Radius = (CFG.aimbot and CFG.aimFov or CFG.silentFov)
        fovCircle.Position = Cam.ViewportSize / 2
    end
end)

----------------------------------------------------------------
-- Aimbot (camera soft lock)
----------------------------------------------------------------
local aimHolding = false
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.aimbotKey then
        aimHolding = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CFG.aimbotKey then
        aimHolding = false
    end
end)

RunService.RenderStepped:Connect(function()
    if not CFG.aimbot then return end
    if CFG.aimbotHold and not aimHolding then return end
    local target = pickTarget(CFG.aimFov)
    if not target then return end
    local part = getPart(target, CFG.aimPart)
    if not part then return end
    local goal = CFrame.lookAt(Cam.CFrame.Position, part.Position)
    Cam.CFrame = Cam.CFrame:Lerp(goal, math.clamp(CFG.aimSmooth, 0.05, 1))
end)

----------------------------------------------------------------
-- Silent aim (rewrite Fire* args)
----------------------------------------------------------------
local function rewrite(name, a)
    if not CFG.silent then return end
    local muzzle = a[1]
    if typeof(muzzle) ~= "Vector3" or typeof(a[2]) ~= "Vector3" then return end
    if math.random(100) > CFG.hitChance then return end

    local model = pickTarget(CFG.silentFov)
    if not model then return end

    local wantHead = math.random(100) <= CFG.headChance
    local part = model:FindFirstChild(wantHead and "Head" or "UpperTorso")
        or getPart(model)
    if not part then return end

    local speed, arc = (Ballistics and Ballistics.SPEED) or 1700, nil
    if name == "FireSniper" and Ballistics then
        local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
        speed = (Ballistics.RIFLE_SPEED or speed) * ((tool and tonumber(tool:GetAttribute("GsVelocity"))) or 1)
        arc = Ballistics.RIFLE_ARC
    end

    local point = part.Position
        + Vector3.new(math.random(-10, 10), math.random(-8, 8), math.random(-10, 10)) / 100

    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root.AssemblyLinearVelocity.Magnitude > 0.5 then
        local dist = (point - muzzle).Magnitude
        local t = dist / speed
        if Ballistics and Ballistics.flightTime then
            local ok2, ft = pcall(Ballistics.flightTime, dist, speed, arc)
            if ok2 and type(ft) == "number" then t = ft end
        end
        point = point + root.AssemblyLinearVelocity * t
    end

    local plain = (point - muzzle).Unit
    local aim = plain
    if name == "FireSniper" and Ballistics and Ballistics.launch then
        local ok2, v = pcall(Ballistics.launch, muzzle, point, speed, arc)
        if ok2 and typeof(v) == "Vector3" and v.Magnitude > 0.5 then
            aim = v.Unit
        end
    end

    if name == "FireShotgun" then
        for i = 3, #a do
            if typeof(a[i]) == "Vector3" then a[i] = plain end
        end
    else
        a[2] = aim
        if typeof(a[4]) == "Vector3" then a[4] = plain end
        -- no spread / no recoil-ish: zero extra noise fields when requested
        if CFG.noSpread and typeof(a[5]) == "number" then a[5] = 0 end
        if CFG.noRecoil and typeof(a[6]) == "number" then a[6] = 0 end
    end
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local name = method == "FireServer" and FIRE[self]
    if name then
        local a, n = { ... }, select("#", ...)
        pcall(rewrite, name, a)
        setnamecallmethod(method)
        return oldNamecall(self, table.unpack(a, 1, n))
    end
    return oldNamecall(self, ...)
end))

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------
local espFolder = Instance.new("Folder")
espFolder.Name = "VoxelESP"
espFolder.Parent = LP:WaitForChild("PlayerGui")

local drawings = {} -- [model] = { box, name, health, tracer, chams }

local function clearEsp(model)
    local d = drawings[model]
    if not d then return end
    for _, x in pairs(d) do
        pcall(function()
            if typeof(x) == "Instance" then x:Destroy()
            elseif x.Remove then x:Remove() end
        end)
    end
    drawings[model] = nil
end

local function ensureEsp(model, color)
    if drawings[model] then return drawings[model] end
    local d = {}

    if Drawing then
        d.box = Drawing.new("Square")
        d.box.Thickness = 1
        d.box.Filled = false
        d.box.Color = color
        d.box.Visible = false

        d.name = Drawing.new("Text")
        d.name.Size = 13
        d.name.Center = true
        d.name.Outline = true
        d.name.Color = color
        d.name.Visible = false

        d.health = Drawing.new("Line")
        d.health.Thickness = 2
        d.health.Color = Color3.fromRGB(80, 255, 80)
        d.health.Visible = false

        d.tracer = Drawing.new("Line")
        d.tracer.Thickness = 1
        d.tracer.Color = color
        d.tracer.Visible = false
    end

    local chams = Instance.new("Highlight")
    chams.Name = "VoxelChams"
    chams.Adornee = model
    chams.FillColor = color
    chams.OutlineColor = color
    chams.FillTransparency = 0.55
    chams.OutlineTransparency = 0.2
    chams.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    chams.Enabled = false
    chams.Parent = model
    d.chams = chams

    drawings[model] = d
    return d
end

local function worldBox(model)
    local parts = {}
    for _, p in ipairs(model:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            table.insert(parts, p)
        end
    end
    if #parts == 0 then
        local r = model:FindFirstChild("HumanoidRootPart")
        if r then return r.Position, Vector2.new(40, 60) end
        return nil
    end
    local minV, maxV = Vector3.new(1e9,1e9,1e9), Vector3.new(-1e9,-1e9,-1e9)
    for _, p in ipairs(parts) do
        local cf, sz = p.CFrame, p.Size / 2
        for _, sx in ipairs({-1,1}) do
            for _, sy in ipairs({-1,1}) do
                for _, szz in ipairs({-1,1}) do
                    local w = cf * Vector3.new(sx * sz.X, sy * sz.Y, szz * sz.Z)
                    minV = Vector3.new(math.min(minV.X,w.X), math.min(minV.Y,w.Y), math.min(minV.Z,w.Z))
                    maxV = Vector3.new(math.max(maxV.X,w.X), math.max(maxV.Y,w.Y), math.max(maxV.Z,w.Z))
                end
            end
        end
    end
    local corners = {
        Vector3.new(minV.X,minV.Y,minV.Z), Vector3.new(maxV.X,minV.Y,minV.Z),
        Vector3.new(minV.X,maxV.Y,minV.Z), Vector3.new(maxV.X,maxV.Y,minV.Z),
        Vector3.new(minV.X,minV.Y,maxV.Z), Vector3.new(maxV.X,minV.Y,maxV.Z),
        Vector3.new(minV.X,maxV.Y,maxV.Z), Vector3.new(maxV.X,maxV.Y,maxV.Z),
    }
    local min2, max2 = Vector2.new(1e9,1e9), Vector2.new(-1e9,-1e9)
    local any = false
    for _, c in ipairs(corners) do
        local sp, on = Cam:WorldToViewportPoint(c)
        if on and sp.Z > 0 then
            any = true
            min2 = Vector2.new(math.min(min2.X,sp.X), math.min(min2.Y,sp.Y))
            max2 = Vector2.new(math.max(max2.X,sp.X), math.max(max2.Y,sp.Y))
        end
    end
    if not any then return nil end
    local center3 = (minV + maxV) / 2
    return center3, max2 - min2, min2
end

local function updateEsp()
    if not CFG.espEnabled then
        for m in pairs(drawings) do clearEsp(m) end
        return
    end

    local keep = {}
    local origin = Cam.CFrame.Position
    local screenBottom = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y)

    local function drawOne(model, label, color)
        if not alive(model) then return end
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso")
        if not root then return end
        local dist = (root.Position - origin).Magnitude
        if dist > CFG.maxEspDist then return end

        keep[model] = true
        local d = ensureEsp(model, color)
        local center, size, topLeft = worldBox(model)
        if not center then
            if d.box then d.box.Visible = false end
            if d.name then d.name.Visible = false end
            if d.health then d.health.Visible = false end
            if d.tracer then d.tracer.Visible = false end
            if d.chams then d.chams.Enabled = CFG.espChams end
            return
        end

        if d.chams then
            d.chams.Enabled = CFG.espChams
            d.chams.FillColor = color
            d.chams.OutlineColor = color
        end

        if d.box then
            d.box.Visible = CFG.espBoxes
            d.box.Color = color
            if topLeft and size then
                d.box.Position = topLeft
                d.box.Size = size
            end
        end

        local hum = model:FindFirstChildOfClass("Humanoid")
        local hp = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 1

        if d.name then
            d.name.Visible = CFG.espNames or CFG.espDistance
            d.name.Color = color
            local bits = {}
            if CFG.espNames then table.insert(bits, label) end
            if CFG.espDistance then table.insert(bits, string.format("[%dm]", math.floor(dist))) end
            if CFG.espHealth and hum then table.insert(bits, string.format("%dHP", math.floor(hum.Health))) end
            d.name.Text = table.concat(bits, " ")
            if topLeft and size then
                d.name.Position = Vector2.new(topLeft.X + size.X / 2, topLeft.Y - 14)
            end
        end

        if d.health and topLeft and size then
            d.health.Visible = CFG.espHealth
            local h = size.Y * hp
            d.health.From = Vector2.new(topLeft.X - 4, topLeft.Y + size.Y)
            d.health.To   = Vector2.new(topLeft.X - 4, topLeft.Y + size.Y - h)
            d.health.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 40)
        end

        if d.tracer and topLeft and size then
            d.tracer.Visible = CFG.espTracers
            d.tracer.Color = color
            d.tracer.From = screenBottom
            d.tracer.To = Vector2.new(topLeft.X + size.X / 2, topLeft.Y + size.Y)
        end
    end

    if CFG.espPlayers then
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LP and pl.Character then
                local enemy = isEnemyPlayer(pl)
                if enemy or CFG.espAllies then
                    drawOne(pl.Character, pl.Name, enemy and CFG.colEnemy or CFG.colAlly)
                end
            end
        end
    end

    if CFG.espBots then
        local rigs = Workspace:FindFirstChild("BotRigs")
        if rigs then
            for _, m in ipairs(rigs:GetChildren()) do
                if isEnemyBot(m) or CFG.espAllies then
                    drawOne(m, m.Name, CFG.colBot)
                end
            end
        end
    end

    for m in pairs(drawings) do
        if not keep[m] then clearEsp(m) end
    end
end

RunService.RenderStepped:Connect(function()
    pcall(updateEsp)
end)

----------------------------------------------------------------
-- Movement
----------------------------------------------------------------
local flyBV, flyBG
local noclipConn

local function setSpeed(on)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if on then
        hum.WalkSpeed = CFG.speedVal
    else
        hum.WalkSpeed = 16
    end
end

LP.CharacterAdded:Connect(function(char)
    task.wait(0.4)
    if CFG.speedOn then setSpeed(true) end
end)

RunService.Heartbeat:Connect(function()
    if CFG.speedOn then setSpeed(true) end
end)

local function setFly(on)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    if not on or not hrp then return end

    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = hrp

    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyBG.P = 1e4
    flyBG.CFrame = hrp.CFrame
    flyBG.Parent = hrp
end

RunService.RenderStepped:Connect(function()
    if not CFG.flyOn or not flyBV then return end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    hum.PlatformStand = true

    local dir = Vector3.zero
    local cf = Cam.CFrame
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end

    if dir.Magnitude > 0 then dir = dir.Unit * CFG.flySpeed end
    flyBV.Velocity = dir
    flyBG.CFrame = CFrame.new(hrp.Position, hrp.Position + cf.LookVector)
end)

local function setNoclip(on)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if not on then
        local char = LP.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
        return
    end
    noclipConn = RunService.Stepped:Connect(function()
        local char = LP.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end

----------------------------------------------------------------
-- LiteUI
----------------------------------------------------------------
Lite.Themes.war = {
    bg     = Color3.fromRGB(14, 16, 20),
    line   = Color3.fromRGB(40, 48, 58),
    text   = Color3.fromRGB(235, 240, 245),
    sub    = Color3.fromRGB(140, 150, 165),
    accent = Color3.fromRGB(255, 90, 70),
    warn   = Color3.fromRGB(255, 190, 60),
    danger = Color3.fromRGB(255, 70, 70),
    track  = Color3.fromRGB(28, 32, 40),
}

local ui = Lite.new({
    Title = "Voxel Wars",
    Subtitle = "Combat · Visuals · Movement",
    Width = 360,
    Theme = "war",
})

local tab = ui:Tabs({ "Combat", "Visuals", "Move", "Settings" }, { MaxHeight = 320 })

----------------------------------------------------------------
-- Combat tab
----------------------------------------------------------------
local combat = tab.Combat
combat:Section("Aimbot")
combat:Toggle({
    Name = "Enable Aimbot",
    Flag = "aimbot",
    Default = CFG.aimbot,
    Callback = function(v) CFG.aimbot = v end,
})
combat:Toggle({
    Name = "Hold key (E)",
    Flag = "aimHold",
    Default = CFG.aimbotHold,
    Callback = function(v) CFG.aimbotHold = v end,
})
combat:Slider({
    Name = "Smoothness",
    Flag = "aimSmooth",
    Min = 0.05, Max = 1, Default = CFG.aimSmooth, Step = 0.01,
    Callback = function(v) CFG.aimSmooth = v end,
})
combat:Slider({
    Name = "Aim FOV",
    Flag = "aimFov",
    Min = 40, Max = 400, Default = CFG.aimFov, Step = 5,
    Callback = function(v) CFG.aimFov = v end,
})
combat:Dropdown({
    Name = "Aim point",
    Flag = "aimPart",
    Options = { "Head", "UpperTorso" },
    Default = CFG.aimPart,
    Callback = function(v) CFG.aimPart = v end,
})
combat:Toggle({
    Name = "Show FOV ring",
    Flag = "aimShowFov",
    Default = CFG.aimShowFov,
    Callback = function(v) CFG.aimShowFov = v end,
})

combat:Section("Silent Aim")
combat:Toggle({
    Name = "Enable Silent",
    Flag = "silent",
    Default = CFG.silent,
    Callback = function(v) CFG.silent = v end,
})
combat:Slider({
    Name = "Silent FOV",
    Flag = "silentFov",
    Min = 40, Max = 500, Default = CFG.silentFov, Step = 5,
    Callback = function(v) CFG.silentFov = v end,
})
combat:Slider({
    Name = "Hit chance %",
    Flag = "hitChance",
    Min = 1, Max = 100, Default = CFG.hitChance, Step = 1,
    Callback = function(v) CFG.hitChance = v end,
})
combat:Slider({
    Name = "Head chance %",
    Flag = "headChance",
    Min = 0, Max = 100, Default = CFG.headChance, Step = 1,
    Callback = function(v) CFG.headChance = v end,
})
combat:Toggle({
    Name = "Wall check",
    Flag = "wallcheck",
    Default = CFG.wallcheck,
    Callback = function(v) CFG.wallcheck = v end,
})
combat:Toggle({
    Name = "Wallbang (through walls)",
    Flag = "wallbang",
    Default = CFG.wallbang,
    Callback = function(v)
        CFG.wallbang = v
        if v then CFG.wallcheck = false end
    end,
})
combat:Toggle({
    Name = "Target players",
    Flag = "targetPlayers",
    Default = CFG.targetPlayers,
    Callback = function(v) CFG.targetPlayers = v end,
})
combat:Toggle({
    Name = "Target bots",
    Flag = "targetBots",
    Default = CFG.targetBots,
    Callback = function(v) CFG.targetBots = v end,
})
combat:Toggle({
    Name = "Team check",
    Flag = "teamCheck",
    Default = CFG.teamCheck,
    Callback = function(v) CFG.teamCheck = v end,
})

combat:Section("Weapon")
combat:Toggle({
    Name = "No recoil",
    Flag = "noRecoil",
    Default = CFG.noRecoil,
    Callback = function(v) CFG.noRecoil = v end,
})
combat:Toggle({
    Name = "No spread",
    Flag = "noSpread",
    Default = CFG.noSpread,
    Callback = function(v) CFG.noSpread = v end,
})

----------------------------------------------------------------
-- Visuals tab
----------------------------------------------------------------
local vis = tab.Visuals
vis:Section("ESP")
vis:Toggle({
    Name = "Enable ESP",
    Flag = "espEnabled",
    Default = CFG.espEnabled,
    Callback = function(v)
        CFG.espEnabled = v
        if not v then for m in pairs(drawings) do clearEsp(m) end end
    end,
})
vis:Toggle({
    Name = "Boxes",
    Flag = "espBoxes",
    Default = CFG.espBoxes,
    Callback = function(v) CFG.espBoxes = v end,
})
vis:Toggle({
    Name = "Names",
    Flag = "espNames",
    Default = CFG.espNames,
    Callback = function(v) CFG.espNames = v end,
})
vis:Toggle({
    Name = "Health",
    Flag = "espHealth",
    Default = CFG.espHealth,
    Callback = function(v) CFG.espHealth = v end,
})
vis:Toggle({
    Name = "Distance",
    Flag = "espDistance",
    Default = CFG.espDistance,
    Callback = function(v) CFG.espDistance = v end,
})
vis:Toggle({
    Name = "Tracers",
    Flag = "espTracers",
    Default = CFG.espTracers,
    Callback = function(v) CFG.espTracers = v end,
})
vis:Toggle({
    Name = "Chams",
    Flag = "espChams",
    Default = CFG.espChams,
    Callback = function(v) CFG.espChams = v end,
})
vis:Slider({
    Name = "Max distance",
    Flag = "maxEspDist",
    Min = 100, Max = 3000, Default = CFG.maxEspDist, Step = 50,
    Callback = function(v) CFG.maxEspDist = v end,
})

vis:Section("Targets")
vis:Toggle({
    Name = "Players",
    Flag = "espPlayers",
    Default = CFG.espPlayers,
    Callback = function(v) CFG.espPlayers = v end,
})
vis:Toggle({
    Name = "Bots",
    Flag = "espBots",
    Default = CFG.espBots,
    Callback = function(v) CFG.espBots = v end,
})
vis:Toggle({
    Name = "Show allies",
    Flag = "espAllies",
    Default = CFG.espAllies,
    Callback = function(v) CFG.espAllies = v end,
})

vis:Section("Colours")
local COLOR_PRESETS = {
    ["Red"]    = Color3.fromRGB(255, 70, 70),
    ["Orange"] = Color3.fromRGB(255, 160, 40),
    ["Yellow"] = Color3.fromRGB(255, 220, 60),
    ["Green"]  = Color3.fromRGB(70, 220, 100),
    ["Cyan"]   = Color3.fromRGB(60, 200, 255),
    ["Blue"]   = Color3.fromRGB(70, 120, 255),
    ["Purple"] = Color3.fromRGB(180, 80, 255),
    ["White"]  = Color3.fromRGB(240, 240, 240),
}
local colorNames = { "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "White" }
vis:Dropdown({
    Name = "Enemy colour",
    Flag = "colEnemy",
    Options = colorNames,
    Default = "Red",
    Callback = function(v) CFG.colEnemy = COLOR_PRESETS[v] or CFG.colEnemy end,
})
vis:Dropdown({
    Name = "Ally colour",
    Flag = "colAlly",
    Options = colorNames,
    Default = "Cyan",
    Callback = function(v) CFG.colAlly = COLOR_PRESETS[v] or CFG.colAlly end,
})
vis:Dropdown({
    Name = "Bot colour",
    Flag = "colBot",
    Options = colorNames,
    Default = "Orange",
    Callback = function(v) CFG.colBot = COLOR_PRESETS[v] or CFG.colBot end,
})

----------------------------------------------------------------
-- Movement tab
----------------------------------------------------------------
local move = tab.Move
move:Section("Speed")
move:Toggle({
    Name = "Speed hack",
    Flag = "speedOn",
    Default = CFG.speedOn,
    Callback = function(v)
        CFG.speedOn = v
        setSpeed(v)
    end,
})
move:Slider({
    Name = "Walk speed",
    Flag = "speedVal",
    Min = 16, Max = 80, Default = CFG.speedVal, Step = 1,
    Callback = function(v)
        CFG.speedVal = v
        if CFG.speedOn then setSpeed(true) end
    end,
})

move:Section("Fly")
move:Toggle({
    Name = "Fly",
    Flag = "flyOn",
    Default = CFG.flyOn,
    Callback = function(v)
        CFG.flyOn = v
        setFly(v)
        if not v then
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
    end,
})
move:Slider({
    Name = "Fly speed",
    Flag = "flySpeed",
    Min = 20, Max = 150, Default = CFG.flySpeed, Step = 5,
    Callback = function(v) CFG.flySpeed = v end,
})
move:Label({ Text = "WASD + Space / Ctrl while flying" })

move:Section("Collision")
move:Toggle({
    Name = "Noclip",
    Flag = "noclipOn",
    Default = CFG.noclipOn,
    Callback = function(v)
        CFG.noclipOn = v
        setNoclip(v)
    end,
})

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
        CFG.espEnabled = false
        CFG.aimbot = false
        CFG.silent = false
        CFG.flyOn = false
        CFG.noclipOn = false
        CFG.speedOn = false
        setFly(false)
        setNoclip(false)
        setSpeed(false)
        for m in pairs(drawings) do clearEsp(m) end
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
        Title = "Voxel Wars",
        Text = "Hub loaded — RightShift to toggle",
        Duration = 4,
    })
end)

print("[VoxelWars] LiteUI hub loaded")
