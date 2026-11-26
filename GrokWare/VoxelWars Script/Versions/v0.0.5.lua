--[[
    Voxel Wars  ·  Full Utility Hub
    PlaceId: 78884249003161
    UI: LiteUI (Grokware v0.0.7)

    Combat   — aimbot, silent, wallbang, triggerbot, sticky, priority, vehicle silent, melee
    Visuals  — boxes, names, HP, dist, tracers, chams, skeleton, weapon, arrows, radar, vehicles, fullbright
    Movement — speed, fly, noclip, inf jump, auto redeploy/revive, crouch/lean
    Progress — claim quests, shop, killstreaks
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
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")

local LP  = Players.LocalPlayer
local Cam = Workspace.CurrentCamera
local Mouse = LP:GetMouse()

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    -- Aimbot
    aimbot          = false,
    aimbotKey       = Enum.KeyCode.E,
    aimbotHold      = true,
    aimSmooth       = 0.22,
    aimPart         = "Head",
    aimFov          = 140,
    aimShowFov      = true,

    -- Silent
    silent          = true,
    silentFov       = 160,
    hitChance       = 90,
    headChance      = 60,
    wallcheck       = true,
    wallbang        = false,
    targetPlayers   = true,
    targetBots      = true,
    teamCheck       = true,
    stickyMs        = 350,
    priority        = "Closest", -- Closest | LowHP | BotsFirst

    -- Extra combat
    triggerbot      = false,
    triggerDelay   = 0.05,
    rapidFire       = false,
    vehicleSilent   = true,
    meleeAssist     = true,

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
    espSkeleton     = false,
    espWeapon       = true,
    espArrows       = true,
    espRadar        = true,
    espVehicles     = true,
    espPlayers      = true,
    espBots         = true,
    espAllies       = false,
    maxEspDist      = 1500,
    colEnemy        = Color3.fromRGB(255, 70, 70),
    colAlly         = Color3.fromRGB(70, 180, 255),
    colBot          = Color3.fromRGB(255, 180, 40),
    colVehicle      = Color3.fromRGB(180, 100, 255),
    fullbright      = false,

    -- Movement
    speedOn         = false,
    speedVal        = 28,
    flyOn           = false,
    flySpeed        = 60,
    noclipOn        = false,
    infJump         = false,
    autoRedeploy    = false,
    autoRevive      = false,
    crouchHelper    = false,
    leanHelper      = false,
}

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local VoxelRemotes = ReplicatedStorage:FindFirstChild("Voxel")
    and ReplicatedStorage.Voxel:FindFirstChild("Remotes")
local GameRemotes = ReplicatedStorage:FindFirstChild("Game")
    and ReplicatedStorage.Game:FindFirstChild("Remotes")
local VehicleRemotes = ReplicatedStorage:FindFirstChild("Vehicles")
    and ReplicatedStorage.Vehicles:FindFirstChild("Remotes")

local FIRE = {}
if VoxelRemotes then
    for _, n in ipairs({
        "FireRifle", "FireSMG", "FireLMG", "FirePistol", "FireDMR",
        "FireSniper", "FireShotgun", "FireHandCannon", "FireMinigun",
        "FireAA", "FireRocket", "FireFlame",
    }) do
        local r = VoxelRemotes:FindFirstChild(n)
        if r then FIRE[r] = n end
    end
end

local VEHICLE_FIRE = {}
if VehicleRemotes then
    for _, n in ipairs({ "TankFire", "HeliFire", "HeliDoorFire" }) do
        local r = VehicleRemotes:FindFirstChild(n)
        if r then VEHICLE_FIRE[r] = n end
    end
end

local MELEE = {}
if VoxelRemotes then
    for _, n in ipairs({ "KnifeHit", "MeleeSwing", "Punch", "HammerHit" }) do
        local r = VoxelRemotes:FindFirstChild(n)
        if r then MELEE[r] = n end
    end
end

local function remote(folder, name)
    return folder and folder:FindFirstChild(name)
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

local function getToolName(model)
    local tool = model:FindFirstChildOfClass("Tool")
    return tool and tool.Name or nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function visible(from, to, model)
    if CFG.wallbang or not CFG.wallcheck then return true end
    rayParams.FilterDescendantsInstances = { LP.Character, model }
    local hit = Workspace:Raycast(from, to - from, rayParams)
    return hit == nil or (hit.Instance and hit.Instance:IsDescendantOf(model))
end

----------------------------------------------------------------
-- Sticky + priority target pick
----------------------------------------------------------------
local stickyTarget, stickyUntil = nil, 0

local function scoreTarget(model, dist, isBot)
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hp = hum and (hum.Health / math.max(hum.MaxHealth, 1)) or 1
    if CFG.priority == "LowHP" then
        return hp * 1000 + dist
    elseif CFG.priority == "BotsFirst" then
        return (isBot and 0 or 500) + dist
    end
    return dist -- Closest
end

local function pickTarget(fov)
    fov = fov or CFG.silentFov
    local now = os.clock() * 1000
    if stickyTarget and now < stickyUntil and alive(stickyTarget) then
        local part = getPart(stickyTarget)
        if part then
            local sp, on = Cam:WorldToViewportPoint(part.Position)
            if on and sp.Z > 0 then
                local d = (Vector2.new(sp.X, sp.Y) - Cam.ViewportSize / 2).Magnitude
                if d < fov * 1.25 then
                    return stickyTarget
                end
            end
        end
    end

    local center = Cam.ViewportSize / 2
    local best, bestScore = nil, math.huge
    local origin = Cam.CFrame.Position

    local function consider(model, isBot)
        if not alive(model) then return end
        local part = getPart(model)
        if not part then return end
        local sp, onScreen = Cam:WorldToViewportPoint(part.Position)
        if not onScreen or sp.Z < 0 then return end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d >= fov then return end
        if not visible(origin, part.Position, model) then return end
        local sc = scoreTarget(model, d, isBot)
        if sc < bestScore then
            best, bestScore = model, sc
        end
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

    if best then
        stickyTarget = best
        stickyUntil = now + (CFG.stickyMs or 0)
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
-- Aimbot
----------------------------------------------------------------
local aimHolding = false
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.aimbotKey then aimHolding = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CFG.aimbotKey then aimHolding = false end
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
-- Triggerbot (auto click when on target)
----------------------------------------------------------------
local lastTrig = 0
RunService.RenderStepped:Connect(function()
    if not CFG.triggerbot then return end
    if os.clock() - lastTrig < CFG.triggerDelay then return end
    local target = pickTarget(math.min(CFG.silentFov, 80))
    if not target then return end
    local part = getPart(target)
    if not part then return end
    local sp, on = Cam:WorldToViewportPoint(part.Position)
    if not on then return end
    local center = Cam.ViewportSize / 2
    if (Vector2.new(sp.X, sp.Y) - center).Magnitude > 28 then return end
    lastTrig = os.clock()
    pcall(function()
        mouse1press()
        task.wait(0.02)
        mouse1release()
    end)
end)

----------------------------------------------------------------
-- Silent / vehicle / melee rewrite
----------------------------------------------------------------
local function aimPointOn(model, name)
    local wantHead = math.random(100) <= CFG.headChance
    local part = model:FindFirstChild(wantHead and "Head" or "UpperTorso") or getPart(model)
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
    local muzzleGuess = Cam.CFrame.Position
    if root and root.AssemblyLinearVelocity.Magnitude > 0.5 then
        local dist = (point - muzzleGuess).Magnitude
        local t = dist / speed
        if Ballistics and Ballistics.flightTime then
            local ok2, ft = pcall(Ballistics.flightTime, dist, speed, arc)
            if ok2 and type(ft) == "number" then t = ft end
        end
        point = point + root.AssemblyLinearVelocity * t
    end
    return point, part, speed, arc
end

local function rewriteGun(name, a)
    if not CFG.silent then return end
    local muzzle = a[1]
    if typeof(muzzle) ~= "Vector3" or typeof(a[2]) ~= "Vector3" then return end
    if math.random(100) > CFG.hitChance then return end

    local model = pickTarget(CFG.silentFov)
    if not model then return end
    local point = aimPointOn(model, name)
    if not point then return end

    local plain = (point - muzzle).Unit
    local aim = plain
    if name == "FireSniper" and Ballistics and Ballistics.launch then
        local speed = (Ballistics.RIFLE_SPEED or 1700)
        local ok2, v = pcall(Ballistics.launch, muzzle, point, speed, Ballistics.RIFLE_ARC)
        if ok2 and typeof(v) == "Vector3" and v.Magnitude > 0.5 then aim = v.Unit end
    end

    if name == "FireShotgun" then
        for i = 3, #a do
            if typeof(a[i]) == "Vector3" then a[i] = plain end
        end
    else
        a[2] = aim
        if typeof(a[4]) == "Vector3" then a[4] = plain end
        if CFG.noSpread and typeof(a[5]) == "number" then a[5] = 0 end
        if CFG.noRecoil and typeof(a[6]) == "number" then a[6] = 0 end
    end
end

local function rewriteVehicle(name, a)
    if not CFG.vehicleSilent then return end
    local model = pickTarget(CFG.silentFov * 1.5)
    if not model then return end
    local part = getPart(model)
    if not part then return end
    -- best-effort: replace any aim Vector3 with direction to target
    local origin = Cam.CFrame.Position
    for i = 1, #a do
        if typeof(a[i]) == "Vector3" and a[i].Magnitude > 0.1 and a[i].Magnitude < 1.5 then
            a[i] = (part.Position - origin).Unit
        end
    end
end

local function rewriteMelee(name, a)
    if not CFG.meleeAssist then return end
    local model = pickTarget(90)
    if not model then return end
    local part = getPart(model)
    if not part then return end
    for i = 1, #a do
        if typeof(a[i]) == "Vector3" then
            -- if it looks like a position near us, snap toward target
            a[i] = part.Position
            break
        end
    end
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" then
        local n = FIRE[self]
        if n then
            local a, c = { ... }, select("#", ...)
            pcall(rewriteGun, n, a)
            setnamecallmethod(method)
            return oldNamecall(self, table.unpack(a, 1, c))
        end
        n = VEHICLE_FIRE[self]
        if n then
            local a, c = { ... }, select("#", ...)
            pcall(rewriteVehicle, n, a)
            setnamecallmethod(method)
            return oldNamecall(self, table.unpack(a, 1, c))
        end
        n = MELEE[self]
        if n then
            local a, c = { ... }, select("#", ...)
            pcall(rewriteMelee, n, a)
            setnamecallmethod(method)
            return oldNamecall(self, table.unpack(a, 1, c))
        end
    end
    return oldNamecall(self, ...)
end))

-- Rapid fire: lower tool activation cooldown when possible
RunService.Heartbeat:Connect(function()
    if not CFG.rapidFire then return end
    local char = LP.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end
    pcall(function()
        if tool:GetAttribute("FireRate") then tool:SetAttribute("FireRate", 0.02) end
        if tool:GetAttribute("Cooldown") then tool:SetAttribute("Cooldown", 0) end
        local cd = tool:FindFirstChild("Cooldown") or tool:FindFirstChild("FireDelay")
        if cd and cd:IsA("NumberValue") then cd.Value = 0 end
    end)
end)

----------------------------------------------------------------
-- ESP + skeleton + weapon + arrows + vehicles
----------------------------------------------------------------
local drawings = {}
local arrowPool = {}
local vehicleDraw = {}

local function clearEsp(model)
    local d = drawings[model]
    if not d then return end
    for k, x in pairs(d) do
        if k == "bones" then
            for _, b in ipairs(x) do pcall(function() b:Remove() end) end
        else
            pcall(function()
                if typeof(x) == "Instance" then x:Destroy()
                elseif x.Remove then x:Remove() end
            end)
        end
    end
    drawings[model] = nil
end

local BONE_PAIRS = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
}

local function ensureEsp(model, color)
    if drawings[model] then return drawings[model] end
    local d = { bones = {} }
    if Drawing then
        d.box = Drawing.new("Square"); d.box.Thickness = 1; d.box.Filled = false; d.box.Visible = false
        d.name = Drawing.new("Text"); d.name.Size = 13; d.name.Center = true; d.name.Outline = true; d.name.Visible = false
        d.health = Drawing.new("Line"); d.health.Thickness = 2; d.health.Visible = false
        d.tracer = Drawing.new("Line"); d.tracer.Thickness = 1; d.tracer.Visible = false
        for _ = 1, #BONE_PAIRS do
            local ln = Drawing.new("Line"); ln.Thickness = 1.2; ln.Visible = false
            table.insert(d.bones, ln)
        end
    end
    local chams = Instance.new("Highlight")
    chams.Name = "VoxelChams"
    chams.Adornee = model
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
        if r then return r.Position, Vector2.new(40, 60), nil end
        return nil
    end
    local minV, maxV = Vector3.new(1e9,1e9,1e9), Vector3.new(-1e9,-1e9,-1e9)
    for _, p in ipairs(parts) do
        local cf, sz = p.CFrame, p.Size / 2
        for _, sx in ipairs({-1,1}) do
            for _, sy in ipairs({-1,1}) do
                for _, szz in ipairs({-1,1}) do
                    local w = cf * Vector3.new(sx*sz.X, sy*sz.Y, szz*sz.Z)
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
    return (minV+maxV)/2, max2-min2, min2
end

-- Off-screen arrows
local function ensureArrow()
    local a = Drawing.new("Triangle")
    a.Filled = true
    a.Thickness = 1
    a.Visible = false
    return a
end

local function drawArrow(idx, worldPos, color)
    while #arrowPool < idx do table.insert(arrowPool, ensureArrow()) end
    local tri = arrowPool[idx]
    local sp, on = Cam:WorldToViewportPoint(worldPos)
    local vs = Cam.ViewportSize
    if on and sp.Z > 0 and sp.X > 0 and sp.X < vs.X and sp.Y > 0 and sp.Y < vs.Y then
        tri.Visible = false
        return
    end
    local dir = Vector2.new(sp.X - vs.X/2, sp.Y - vs.Y/2)
    if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
    dir = dir.Unit
    local edge = Vector2.new(vs.X/2, vs.Y/2) + dir * (math.min(vs.X, vs.Y) * 0.42)
    local perp = Vector2.new(-dir.Y, dir.X)
    tri.PointA = edge + dir * 10
    tri.PointB = edge - dir * 6 + perp * 7
    tri.PointC = edge - dir * 6 - perp * 7
    tri.Color = color
    tri.Visible = CFG.espArrows
end

-- Radar
local radarGui
local radarDots = {}
local function ensureRadar()
    if radarGui then return end
    radarGui = Instance.new("ScreenGui")
    radarGui.Name = "VoxelRadar"
    radarGui.ResetOnSpawn = false
    radarGui.Parent = LP:WaitForChild("PlayerGui")
    local frame = Instance.new("Frame")
    frame.Name = "Pad"
    frame.Size = UDim2.fromOffset(130, 130)
    frame.Position = UDim2.new(1, -150, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = radarGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 70, 80)
    stroke.Parent = frame
    local cross1 = Instance.new("Frame")
    cross1.Size = UDim2.new(1, 0, 0, 1)
    cross1.Position = UDim2.fromScale(0, 0.5)
    cross1.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
    cross1.BorderSizePixel = 0
    cross1.Parent = frame
    local cross2 = Instance.new("Frame")
    cross2.Size = UDim2.new(0, 1, 1, 0)
    cross2.Position = UDim2.fromScale(0.5, 0)
    cross2.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
    cross2.BorderSizePixel = 0
    cross2.Parent = frame
    local me = Instance.new("Frame")
    me.Size = UDim2.fromOffset(6, 6)
    me.AnchorPoint = Vector2.new(0.5, 0.5)
    me.Position = UDim2.fromScale(0.5, 0.5)
    me.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    me.BorderSizePixel = 0
    me.Parent = frame
    Instance.new("UICorner", me).CornerRadius = UDim.new(1, 0)
end

local function radarDot(i)
    ensureRadar()
    local pad = radarGui.Pad
    local d = radarDots[i]
    if d then return d end
    d = Instance.new("Frame")
    d.Size = UDim2.fromOffset(5, 5)
    d.AnchorPoint = Vector2.new(0.5, 0.5)
    d.BorderSizePixel = 0
    d.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
    d.Parent = pad
    radarDots[i] = d
    return d
end

local function updateRadar(entries)
    if not CFG.espRadar then
        if radarGui then radarGui.Enabled = false end
        return
    end
    ensureRadar()
    radarGui.Enabled = true
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local yaw = math.atan2(-Cam.CFrame.LookVector.X, -Cam.CFrame.LookVector.Z)
    local range = 300
    local used = 0
    for _, e in ipairs(entries) do
        local offset = e.pos - hrp.Position
        local rx = offset.X * math.cos(yaw) - offset.Z * math.sin(yaw)
        local rz = offset.X * math.sin(yaw) + offset.Z * math.cos(yaw)
        local sx = 0.5 + (rx / range) * 0.5
        local sy = 0.5 + (rz / range) * 0.5
        if sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1 then
            used += 1
            local d = radarDot(used)
            d.Visible = true
            d.BackgroundColor3 = e.color
            d.Position = UDim2.fromScale(sx, sy)
        end
    end
    for i = used + 1, #radarDots do
        radarDots[i].Visible = false
    end
end

local function updateEsp()
    if not CFG.espEnabled then
        for m in pairs(drawings) do clearEsp(m) end
        for _, a in ipairs(arrowPool) do a.Visible = false end
        if radarGui then radarGui.Enabled = false end
        return
    end

    local keep = {}
    local origin = Cam.CFrame.Position
    local screenBottom = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y)
    local radarEntries = {}
    local arrowIdx = 0

    local function drawOne(model, label, color, isBot)
        if not alive(model) then return end
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso")
        if not root then return end
        local dist = (root.Position - origin).Magnitude
        if dist > CFG.maxEspDist then return end

        keep[model] = true
        local d = ensureEsp(model, color)
        table.insert(radarEntries, { pos = root.Position, color = color })

        arrowIdx += 1
        if CFG.espArrows then drawArrow(arrowIdx, root.Position, color) end

        local center, size, topLeft = worldBox(model)

        if d.chams then
            d.chams.Enabled = CFG.espChams
            d.chams.FillColor = color
            d.chams.OutlineColor = color
        end

        -- skeleton
        if d.bones then
            for i, pair in ipairs(BONE_PAIRS) do
                local ln = d.bones[i]
                if CFG.espSkeleton then
                    local a = model:FindFirstChild(pair[1])
                    local b = model:FindFirstChild(pair[2])
                    if a and b then
                        local sa, oa = Cam:WorldToViewportPoint(a.Position)
                        local sb, ob = Cam:WorldToViewportPoint(b.Position)
                        if oa and ob and sa.Z > 0 and sb.Z > 0 then
                            ln.From = Vector2.new(sa.X, sa.Y)
                            ln.To = Vector2.new(sb.X, sb.Y)
                            ln.Color = color
                            ln.Visible = true
                        else
                            ln.Visible = false
                        end
                    else
                        ln.Visible = false
                    end
                else
                    ln.Visible = false
                end
            end
        end

        if not center then
            if d.box then d.box.Visible = false end
            if d.name then d.name.Visible = false end
            if d.health then d.health.Visible = false end
            if d.tracer then d.tracer.Visible = false end
            return
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
        local weapon = CFG.espWeapon and getToolName(model) or nil

        if d.name then
            d.name.Visible = CFG.espNames or CFG.espDistance or CFG.espWeapon
            d.name.Color = color
            local bits = {}
            if CFG.espNames then table.insert(bits, label) end
            if CFG.espDistance then table.insert(bits, string.format("[%dm]", math.floor(dist))) end
            if CFG.espHealth and hum then table.insert(bits, string.format("%dHP", math.floor(hum.Health))) end
            if weapon then table.insert(bits, weapon) end
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
                    drawOne(pl.Character, pl.Name, enemy and CFG.colEnemy or CFG.colAlly, false)
                end
            end
        end
    end
    if CFG.espBots then
        local rigs = Workspace:FindFirstChild("BotRigs")
        if rigs then
            for _, m in ipairs(rigs:GetChildren()) do
                if isEnemyBot(m) or CFG.espAllies then
                    drawOne(m, m.Name, CFG.colBot, true)
                end
            end
        end
    end

    -- Vehicle ESP (simple highlight on models under workspace with Vehicle-like names)
    if CFG.espVehicles then
        for _, m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") and m:FindFirstChildWhichIsA("VehicleSeat", true) then
                local seat = m:FindFirstChildWhichIsA("VehicleSeat", true)
                local pos = seat and seat.Position
                if pos and (pos - origin).Magnitude < CFG.maxEspDist then
                    table.insert(radarEntries, { pos = pos, color = CFG.colVehicle })
                    if not vehicleDraw[m] then
                        local hl = Instance.new("Highlight")
                        hl.FillColor = CFG.colVehicle
                        hl.OutlineColor = CFG.colVehicle
                        hl.FillTransparency = 0.7
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Adornee = m
                        hl.Parent = m
                        vehicleDraw[m] = hl
                    end
                    vehicleDraw[m].Enabled = true
                end
            end
        end
    else
        for m, hl in pairs(vehicleDraw) do
            pcall(function() hl:Destroy() end)
            vehicleDraw[m] = nil
        end
    end

    for m in pairs(drawings) do
        if not keep[m] then clearEsp(m) end
    end
    for i = arrowIdx + 1, #arrowPool do
        arrowPool[i].Visible = false
    end
    updateRadar(radarEntries)
end

RunService.RenderStepped:Connect(function()
    pcall(updateEsp)
end)

----------------------------------------------------------------
-- Fullbright
----------------------------------------------------------------
local oldBrightness, oldAmbient, oldClock
local function setFullbright(on)
    if on then
        oldBrightness = Lighting.Brightness
        oldAmbient = Lighting.Ambient
        oldClock = Lighting.ClockTime
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1e6
        pcall(function()
            local atm = Lighting:FindFirstChildOfClass("Atmosphere")
            if atm then atm.Density = 0 end
        end)
    else
        if oldBrightness then Lighting.Brightness = oldBrightness end
        if oldAmbient then Lighting.Ambient = oldAmbient end
        if oldClock then Lighting.ClockTime = oldClock end
    end
end

----------------------------------------------------------------
-- Movement
----------------------------------------------------------------
local flyBV, flyBG, noclipConn

local function setSpeed(on)
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.WalkSpeed = on and CFG.speedVal or 16
end

LP.CharacterAdded:Connect(function()
    task.wait(0.4)
    if CFG.speedOn then setSpeed(true) end
end)
RunService.Heartbeat:Connect(function()
    if CFG.speedOn then setSpeed(true) end
end)

local function setFly(on)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
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

-- Infinite jump
UserInputService.JumpRequest:Connect(function()
    if not CFG.infJump then return end
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- Auto redeploy / revive
local function fireGame(name, ...)
    local r = remote(GameRemotes, name)
    if r then pcall(function() r:FireServer(...) end) end
end

local wasDead = false
RunService.Heartbeat:Connect(function()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    local dead = not hum or hum.Health <= 0
    if dead and not wasDead then
        if CFG.autoRevive then
            task.delay(0.5, function() fireGame("Revive") end)
        end
        if CFG.autoRedeploy then
            task.delay(1.2, function() fireGame("Redeploy") end)
        end
    end
    wasDead = dead
end)

-- Crouch / lean helpers (toggle spam while key held — soft assist)
local crouchR = VoxelRemotes and VoxelRemotes:FindFirstChild("Crouch")
local leanR = VoxelRemotes and VoxelRemotes:FindFirstChild("Lean")
local lastCrouch, lastLean = 0, 0
RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if CFG.crouchHelper and crouchR and UserInputService:IsKeyDown(Enum.KeyCode.C) and now - lastCrouch > 0.35 then
        lastCrouch = now
        pcall(function() crouchR:FireServer() end)
    end
    if CFG.leanHelper and leanR then
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) and now - lastLean > 0.35 then
            lastLean = now
            pcall(function() leanR:FireServer(-1) end)
        elseif UserInputService:IsKeyDown(Enum.KeyCode.E) and now - lastLean > 0.35 then
            lastLean = now
            pcall(function() leanR:FireServer(1) end)
        end
    end
end)

----------------------------------------------------------------
-- Progression helpers
----------------------------------------------------------------
local function claimQuests()
    fireGame("claimallquests")
    local qa = remote(GameRemotes, "QuestAction")
    if qa then pcall(function() qa:FireServer("ClaimAll") end) end
    local q = remote(GameRemotes, "Quest")
    if q then pcall(function() q:FireServer("Claim") end) end
end

local function callStreak(name)
    fireGame(name)
end

local function openShop()
    local shop = remote(GameRemotes, "Shop")
    if shop and shop:IsA("RemoteFunction") then
        pcall(function() shop:InvokeServer() end)
    end
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
    Subtitle = "Full utility hub",
    Width = 370,
    Theme = "war",
})

local tab = ui:Tabs(
    { "Combat", "Visuals", "Move", "Extras", "Settings" },
    { MaxHeight = 340 }
)

----------------------------------------------------------------
-- Combat
----------------------------------------------------------------
local combat = tab.Combat
combat:Section("Aimbot")
combat:Toggle({ Name = "Enable Aimbot", Flag = "aimbot", Default = CFG.aimbot, Callback = function(v) CFG.aimbot = v end })
combat:Toggle({ Name = "Hold key (E)", Flag = "aimHold", Default = CFG.aimbotHold, Callback = function(v) CFG.aimbotHold = v end })
combat:Slider({ Name = "Smoothness", Flag = "aimSmooth", Min = 0.05, Max = 1, Default = CFG.aimSmooth, Step = 0.01, Callback = function(v) CFG.aimSmooth = v end })
combat:Slider({ Name = "Aim FOV", Flag = "aimFov", Min = 40, Max = 400, Default = CFG.aimFov, Step = 5, Callback = function(v) CFG.aimFov = v end })
combat:Dropdown({ Name = "Aim point", Flag = "aimPart", Options = { "Head", "UpperTorso" }, Default = CFG.aimPart, Callback = function(v) CFG.aimPart = v end })
combat:Toggle({ Name = "Show FOV ring", Flag = "aimShowFov", Default = CFG.aimShowFov, Callback = function(v) CFG.aimShowFov = v end })

combat:Section("Silent Aim")
combat:Toggle({ Name = "Enable Silent", Flag = "silent", Default = CFG.silent, Callback = function(v) CFG.silent = v end })
combat:Slider({ Name = "Silent FOV", Flag = "silentFov", Min = 40, Max = 500, Default = CFG.silentFov, Step = 5, Callback = function(v) CFG.silentFov = v end })
combat:Slider({ Name = "Hit chance %", Flag = "hitChance", Min = 1, Max = 100, Default = CFG.hitChance, Step = 1, Callback = function(v) CFG.hitChance = v end })
combat:Slider({ Name = "Head chance %", Flag = "headChance", Min = 0, Max = 100, Default = CFG.headChance, Step = 1, Callback = function(v) CFG.headChance = v end })
combat:Slider({ Name = "Sticky ms", Flag = "stickyMs", Min = 0, Max = 1000, Default = CFG.stickyMs, Step = 25, Callback = function(v) CFG.stickyMs = v end })
combat:Dropdown({
    Name = "Priority",
    Flag = "priority",
    Options = { "Closest", "LowHP", "BotsFirst" },
    Default = CFG.priority,
    Callback = function(v) CFG.priority = v end,
})
combat:Toggle({ Name = "Wall check", Flag = "wallcheck", Default = CFG.wallcheck, Callback = function(v) CFG.wallcheck = v end })
combat:Toggle({
    Name = "Wallbang",
    Flag = "wallbang",
    Default = CFG.wallbang,
    Callback = function(v)
        CFG.wallbang = v
        if v then CFG.wallcheck = false end
    end,
})
combat:Toggle({ Name = "Target players", Flag = "targetPlayers", Default = CFG.targetPlayers, Callback = function(v) CFG.targetPlayers = v end })
combat:Toggle({ Name = "Target bots", Flag = "targetBots", Default = CFG.targetBots, Callback = function(v) CFG.targetBots = v end })
combat:Toggle({ Name = "Team check", Flag = "teamCheck", Default = CFG.teamCheck, Callback = function(v) CFG.teamCheck = v end })

combat:Section("Extra combat")
combat:Toggle({ Name = "Triggerbot", Flag = "triggerbot", Default = CFG.triggerbot, Callback = function(v) CFG.triggerbot = v end })
combat:Slider({ Name = "Trigger delay", Flag = "triggerDelay", Min = 0, Max = 0.3, Default = CFG.triggerDelay, Step = 0.01, Callback = function(v) CFG.triggerDelay = v end })
combat:Toggle({ Name = "Rapid fire", Flag = "rapidFire", Default = CFG.rapidFire, Callback = function(v) CFG.rapidFire = v end })
combat:Toggle({ Name = "Vehicle silent", Flag = "vehicleSilent", Default = CFG.vehicleSilent, Callback = function(v) CFG.vehicleSilent = v end })
combat:Toggle({ Name = "Melee assist", Flag = "meleeAssist", Default = CFG.meleeAssist, Callback = function(v) CFG.meleeAssist = v end })
combat:Toggle({ Name = "No recoil", Flag = "noRecoil", Default = CFG.noRecoil, Callback = function(v) CFG.noRecoil = v end })
combat:Toggle({ Name = "No spread", Flag = "noSpread", Default = CFG.noSpread, Callback = function(v) CFG.noSpread = v end })

----------------------------------------------------------------
-- Visuals
----------------------------------------------------------------
local vis = tab.Visuals
vis:Section("ESP")
vis:Toggle({ Name = "Enable ESP", Flag = "espEnabled", Default = CFG.espEnabled, Callback = function(v)
    CFG.espEnabled = v
    if not v then for m in pairs(drawings) do clearEsp(m) end end
end })
vis:Toggle({ Name = "Boxes", Flag = "espBoxes", Default = CFG.espBoxes, Callback = function(v) CFG.espBoxes = v end })
vis:Toggle({ Name = "Names", Flag = "espNames", Default = CFG.espNames, Callback = function(v) CFG.espNames = v end })
vis:Toggle({ Name = "Health", Flag = "espHealth", Default = CFG.espHealth, Callback = function(v) CFG.espHealth = v end })
vis:Toggle({ Name = "Distance", Flag = "espDistance", Default = CFG.espDistance, Callback = function(v) CFG.espDistance = v end })
vis:Toggle({ Name = "Tracers", Flag = "espTracers", Default = CFG.espTracers, Callback = function(v) CFG.espTracers = v end })
vis:Toggle({ Name = "Chams", Flag = "espChams", Default = CFG.espChams, Callback = function(v) CFG.espChams = v end })
vis:Toggle({ Name = "Skeleton", Flag = "espSkeleton", Default = CFG.espSkeleton, Callback = function(v) CFG.espSkeleton = v end })
vis:Toggle({ Name = "Weapon name", Flag = "espWeapon", Default = CFG.espWeapon, Callback = function(v) CFG.espWeapon = v end })
vis:Toggle({ Name = "Off-screen arrows", Flag = "espArrows", Default = CFG.espArrows, Callback = function(v) CFG.espArrows = v end })
vis:Toggle({ Name = "Radar", Flag = "espRadar", Default = CFG.espRadar, Callback = function(v) CFG.espRadar = v end })
vis:Toggle({ Name = "Vehicle ESP", Flag = "espVehicles", Default = CFG.espVehicles, Callback = function(v) CFG.espVehicles = v end })
vis:Slider({ Name = "Max distance", Flag = "maxEspDist", Min = 100, Max = 3000, Default = CFG.maxEspDist, Step = 50, Callback = function(v) CFG.maxEspDist = v end })

vis:Section("Targets")
vis:Toggle({ Name = "Players", Flag = "espPlayers", Default = CFG.espPlayers, Callback = function(v) CFG.espPlayers = v end })
vis:Toggle({ Name = "Bots", Flag = "espBots", Default = CFG.espBots, Callback = function(v) CFG.espBots = v end })
vis:Toggle({ Name = "Show allies", Flag = "espAllies", Default = CFG.espAllies, Callback = function(v) CFG.espAllies = v end })

vis:Section("Colours")
local COLOR_PRESETS = {
    Red = Color3.fromRGB(255, 70, 70), Orange = Color3.fromRGB(255, 160, 40),
    Yellow = Color3.fromRGB(255, 220, 60), Green = Color3.fromRGB(70, 220, 100),
    Cyan = Color3.fromRGB(60, 200, 255), Blue = Color3.fromRGB(70, 120, 255),
    Purple = Color3.fromRGB(180, 80, 255), White = Color3.fromRGB(240, 240, 240),
}
local colorNames = { "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "White" }
vis:Dropdown({ Name = "Enemy", Flag = "colEnemy", Options = colorNames, Default = "Red", Callback = function(v) CFG.colEnemy = COLOR_PRESETS[v] or CFG.colEnemy end })
vis:Dropdown({ Name = "Ally", Flag = "colAlly", Options = colorNames, Default = "Cyan", Callback = function(v) CFG.colAlly = COLOR_PRESETS[v] or CFG.colAlly end })
vis:Dropdown({ Name = "Bot", Flag = "colBot", Options = colorNames, Default = "Orange", Callback = function(v) CFG.colBot = COLOR_PRESETS[v] or CFG.colBot end })
vis:Dropdown({ Name = "Vehicle", Flag = "colVehicle", Options = colorNames, Default = "Purple", Callback = function(v) CFG.colVehicle = COLOR_PRESETS[v] or CFG.colVehicle end })

vis:Section("World")
vis:Toggle({
    Name = "Fullbright / no fog",
    Flag = "fullbright",
    Default = CFG.fullbright,
    Callback = function(v)
        CFG.fullbright = v
        setFullbright(v)
    end,
})

----------------------------------------------------------------
-- Move
----------------------------------------------------------------
local move = tab.Move
move:Section("Speed")
move:Toggle({ Name = "Speed hack", Flag = "speedOn", Default = CFG.speedOn, Callback = function(v) CFG.speedOn = v; setSpeed(v) end })
move:Slider({ Name = "Walk speed", Flag = "speedVal", Min = 16, Max = 80, Default = CFG.speedVal, Step = 1, Callback = function(v) CFG.speedVal = v; if CFG.speedOn then setSpeed(true) end end })

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
move:Slider({ Name = "Fly speed", Flag = "flySpeed", Min = 20, Max = 150, Default = CFG.flySpeed, Step = 5, Callback = function(v) CFG.flySpeed = v end })
move:Label({ Text = "WASD + Space / Ctrl while flying" })

move:Section("Other")
move:Toggle({ Name = "Noclip", Flag = "noclipOn", Default = CFG.noclipOn, Callback = function(v) CFG.noclipOn = v; setNoclip(v) end })
move:Toggle({ Name = "Infinite jump", Flag = "infJump", Default = CFG.infJump, Callback = function(v) CFG.infJump = v end })
move:Toggle({ Name = "Auto revive", Flag = "autoRevive", Default = CFG.autoRevive, Callback = function(v) CFG.autoRevive = v end })
move:Toggle({ Name = "Auto redeploy", Flag = "autoRedeploy", Default = CFG.autoRedeploy, Callback = function(v) CFG.autoRedeploy = v end })
move:Toggle({ Name = "Crouch helper (C)", Flag = "crouchHelper", Default = CFG.crouchHelper, Callback = function(v) CFG.crouchHelper = v end })
move:Toggle({ Name = "Lean helper (Q/E)", Flag = "leanHelper", Default = CFG.leanHelper, Callback = function(v) CFG.leanHelper = v end })

----------------------------------------------------------------
-- Extras (quests / streaks / shop)
----------------------------------------------------------------
local ex = tab.Extras
ex:Section("Progression")
ex:Button({ Name = "Claim all quests", Callback = claimQuests })
ex:Button({ Name = "Shop invoke", Callback = openShop })

ex:Section("Killstreaks (if unlocked)")
ex:Button({ Name = "Call Airstrike", Callback = function() callStreak("CallAirstrike") end })
ex:Button({ Name = "Triple Strike", Callback = function() callStreak("TripleStrike") end })
ex:Button({ Name = "Hellfire", Callback = function() callStreak("Hellfire") end })
ex:Button({ Name = "Gunship", Callback = function() callStreak("Gunship") end })

ex:Section("Note")
ex:Label({ Text = "Streaks only work when the game has granted them." })

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
        CFG.fullbright = false
        setFly(false); setNoclip(false); setSpeed(false); setFullbright(false)
        for m in pairs(drawings) do clearEsp(m) end
        if fovCircle then pcall(function() fovCircle:Remove() end) end
        if radarGui then radarGui:Destroy() end
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
        Text = "Full hub loaded",
        Duration = 4,
    })
end)
print("[VoxelWars] full hub loaded")
