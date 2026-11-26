--[[
    Zero Line [FPV DRONE KAMIKAZE]
    PlaceId: 132631375778013
    LiteUI hub — ESP · Silent · Aim · Utility
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[ZeroLine] LiteUI failed:", Lite)
    return
end

----------------------------------------------------------------
-- Services
----------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")

local LP  = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

local function cam()
    return Workspace.CurrentCamera
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    -- ESP
    espPlayers   = true,
    espBots      = true,
    espDrones    = true,
    espCrates    = true,
    espVehicles  = true,
    boxes        = true,
    names        = true,
    distance     = true,
    tracers      = false,
    chams        = true,
    maxDist      = 1200,
    colEnemy     = Color3.fromRGB(255, 70, 70),
    colBot       = Color3.fromRGB(255, 180, 40),
    colDrone     = Color3.fromRGB(255, 90, 200),
    colCrate     = Color3.fromRGB(100, 255, 140),
    colVehicle   = Color3.fromRGB(140, 120, 255),

    -- Combat
    silent       = true,
    silentFov    = 180,
    hitChance    = 95,
    aimbot       = false,
    aimKey       = Enum.KeyCode.E,
    aimHold      = true,
    aimSmooth    = 0.2,
    aimFov       = 140,
    showFov      = true,
    teamCheck    = true,
    targetPlayers= true,
    targetBots   = true,
    targetDrones = true,

    -- Utility
    autoCrate    = false,
    crateRange   = 25,
    autoBoost    = false,
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function alive(model)
    if not model then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health > 0 end
    -- drones may not have humanoid
    return model.Parent ~= nil
end

local function isEnemy(pl)
    if not pl or pl == LP then return false end
    if not CFG.teamCheck then return true end
    if pl.Team == nil or LP.Team == nil then return true end
    return pl.Team ~= LP.Team
end

local function getRoot(model)
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Hull")
        or model:FindFirstChild("PrimaryPart")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function dnew(kind)
    if not Drawing then return nil end
    local s, o = pcall(Drawing.new, kind)
    return s and o or nil
end

----------------------------------------------------------------
-- Target pick
----------------------------------------------------------------
local function pickTarget(fov)
    local C = cam()
    local center = C.ViewportSize / 2
    local best, bestDist = nil, fov
    local origin = C.CFrame.Position

    local function consider(model, prefer)
        local part = model:FindFirstChild(prefer)
            or model:FindFirstChild("Head")
            or getRoot(model)
        if not part then return end
        local sp, on = C:WorldToViewportPoint(part.Position)
        if not on or sp.Z < 0 then return end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d < bestDist then
            best, bestDist = part, d
        end
    end

    if CFG.targetPlayers then
        for _, pl in ipairs(Players:GetPlayers()) do
            if isEnemy(pl) and pl.Character and alive(pl.Character) then
                consider(pl.Character, "Head")
            end
        end
    end

    if CFG.targetBots then
        local bots = Workspace:FindFirstChild("Bots")
        if bots then
            for _, m in ipairs(bots:GetChildren()) do
                if alive(m) then consider(m, "Head") end
            end
        end
    end

    if CFG.targetDrones then
        local drones = Workspace:FindFirstChild("Drones")
        if drones then
            for _, m in ipairs(drones:GetDescendants()) do
                if m:IsA("Model") and (m.Name:find("Drone") or m.Name:find("Enemy")) then
                    consider(m, "Hull")
                end
            end
            -- also direct children
            for _, m in ipairs(drones:GetChildren()) do
                if m:IsA("Model") then consider(m, "Hull") end
            end
        end
    end

    return best
end

----------------------------------------------------------------
-- FOV ring
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
    local show = CFG.showFov and (CFG.aimbot or CFG.silent)
    fovCircle.Visible = show
    if show then
        fovCircle.Radius = CFG.aimbot and CFG.aimFov or CFG.silentFov
        fovCircle.Position = cam().ViewportSize / 2
    end
end)

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
    local part = pickTarget(CFG.aimFov)
    if not part then return end
    local C = cam()
    local goal = CFrame.lookAt(C.CFrame.Position, part.Position)
    C.CFrame = C.CFrame:Lerp(goal, math.clamp(CFG.aimSmooth, 0.05, 1))
end)

----------------------------------------------------------------
-- Silent aim — rewrite Fire "fire" look vector
-- Signature: Fire:FireServer("fire", weaponName, camPos, lookVector, extra)
----------------------------------------------------------------
local FireRemote = Remotes and Remotes:FindFirstChild("Fire")

if FireRemote then
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self == FireRemote then
            local a = { ... }
            local n = select("#", ...)
            if CFG.silent and a[1] == "fire" and typeof(a[4]) == "Vector3" then
                if math.random(100) <= CFG.hitChance then
                    local part = pickTarget(CFG.silentFov)
                    if part then
                        local origin = typeof(a[3]) == "Vector3" and a[3] or cam().CFrame.Position
                        a[4] = (part.Position - origin).Unit
                    end
                end
            end
            setnamecallmethod(method)
            return old(self, table.unpack(a, 1, n))
        end
        return old(self, ...)
    end))
end

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------
local drawings = {}

local function clearKey(key)
    local d = drawings[key]
    if not d then return end
    for _, x in pairs(d) do
        pcall(function()
            if typeof(x) == "Instance" then x:Destroy()
            elseif x.Remove then x:Remove() end
        end)
    end
    drawings[key] = nil
end

local function ensure(key)
    if drawings[key] then return drawings[key] end
    local d = {}
    d.box = dnew("Square")
    if d.box then d.box.Thickness = 1; d.box.Filled = false; d.box.Visible = false end
    d.name = dnew("Text")
    if d.name then d.name.Size = 13; d.name.Center = true; d.name.Outline = true; d.name.Visible = false end
    d.tracer = dnew("Line")
    if d.tracer then d.tracer.Thickness = 1; d.tracer.Visible = false end
    drawings[key] = d
    return d
end

local function drawEntity(key, model, label, color)
    local root = getRoot(model)
    if not root then return false end
    local C = cam()
    local origin = C.CFrame.Position
    local dist = (root.Position - origin).Magnitude
    if dist > CFG.maxDist then return false end

    local sp, on = C:WorldToViewportPoint(root.Position)
    if not on or sp.Z <= 0 then return false end

    local d = ensure(key)
    local size = Vector2.new(math.clamp(4000 / dist, 12, 50), math.clamp(6000 / dist, 18, 70))
    local topLeft = Vector2.new(sp.X - size.X / 2, sp.Y - size.Y / 2)

    if CFG.boxes and d.box then
        d.box.Position = topLeft
        d.box.Size = size
        d.box.Color = color
        d.box.Visible = true
    elseif d.box then
        d.box.Visible = false
    end

    if (CFG.names or CFG.distance) and d.name then
        local bits = {}
        if CFG.names then table.insert(bits, label) end
        if CFG.distance then table.insert(bits, string.format("%dm", math.floor(dist))) end
        d.name.Text = table.concat(bits, " · ")
        d.name.Color = color
        d.name.Position = Vector2.new(sp.X, topLeft.Y - 14)
        d.name.Visible = true
    elseif d.name then
        d.name.Visible = false
    end

    if CFG.tracers and d.tracer then
        d.tracer.From = Vector2.new(C.ViewportSize.X / 2, C.ViewportSize.Y)
        d.tracer.To = Vector2.new(sp.X, sp.Y)
        d.tracer.Color = color
        d.tracer.Visible = true
    elseif d.tracer then
        d.tracer.Visible = false
    end

    if CFG.chams then
        if not d.chams or not d.chams.Parent then
            local hl = Instance.new("Highlight")
            hl.Name = "ZL_ESP"
            hl.FillTransparency = 0.6
            hl.OutlineTransparency = 0.25
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = model
            d.chams = hl
        end
        d.chams.FillColor = color
        d.chams.OutlineColor = color
        d.chams.Enabled = true
    elseif d.chams then
        d.chams.Enabled = false
    end

    return true
end

local function isCrate(inst)
    if not inst then return false end
    local n = string.lower(inst.Name)
    return n:find("crate") or n:find("loot") or n:find("supply") or n:find("box")
end

RunService.RenderStepped:Connect(function()
    local keep = {}

    if CFG.espPlayers then
        for _, pl in ipairs(Players:GetPlayers()) do
            if isEnemy(pl) and pl.Character and alive(pl.Character) then
                if drawEntity(pl, pl.Character, pl.Name, CFG.colEnemy) then
                    keep[pl] = true
                end
            end
        end
    end

    if CFG.espBots then
        local bots = Workspace:FindFirstChild("Bots")
        if bots then
            for _, m in ipairs(bots:GetChildren()) do
                if alive(m) then
                    if drawEntity(m, m, m.Name, CFG.colBot) then
                        keep[m] = true
                    end
                end
            end
        end
    end

    if CFG.espDrones then
        local drones = Workspace:FindFirstChild("Drones")
        if drones then
            for _, m in ipairs(drones:GetChildren()) do
                if m:IsA("Model") then
                    if drawEntity(m, m, m.Name, CFG.colDrone) then
                        keep[m] = true
                    end
                end
            end
        end
    end

    if CFG.espCrates then
        -- scan map folders for crates (throttled via only checking known folders)
        local map = Workspace:FindFirstChild("Map")
        local folders = { Workspace, map }
        for _, folder in ipairs(folders) do
            if not folder then continue end
            for _, ch in ipairs(folder:GetChildren()) do
                if ch:IsA("Model") or ch:IsA("BasePart") then
                    if isCrate(ch) then
                        local model = ch:IsA("Model") and ch or ch.Parent
                        if model and drawEntity(ch, model:IsA("Model") and model or ch, ch.Name, CFG.colCrate) then
                            keep[ch] = true
                        end
                    end
                elseif ch:IsA("Folder") and (ch.Name:lower():find("crate") or ch.Name:lower():find("loot")) then
                    for _, c in ipairs(ch:GetChildren()) do
                        if drawEntity(c, c:IsA("Model") and c or c, c.Name, CFG.colCrate) then
                            keep[c] = true
                        end
                    end
                end
            end
        end
    end

    if CFG.espVehicles then
        for _, m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") and m:FindFirstChildWhichIsA("VehicleSeat", true) then
                if drawEntity(m, m, m.Name, CFG.colVehicle) then
                    keep[m] = true
                end
            end
        end
    end

    for k in pairs(drawings) do
        if not keep[k] then clearKey(k) end
    end
end)

----------------------------------------------------------------
-- Utility
----------------------------------------------------------------
local function fireRemote(name, ...)
    local r = Remotes and Remotes:FindFirstChild(name)
    if not r then return end
    local args = { ... }
    local n = select("#", ...)
    pcall(function()
        if r:IsA("RemoteFunction") then
            r:InvokeServer(table.unpack(args, 1, n))
        else
            r:FireServer(table.unpack(args, 1, n))
        end
    end)
end

local function launchDrone()
    local r = Remotes and Remotes:FindFirstChild("LaunchDrone")
    if not r then
        uiNotify("LaunchDrone missing")
        return
    end
    local ok2, res = pcall(function() return r:InvokeServer() end)
    if ok2 and res then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Zero Line",
                Text = "Drone launched",
                Duration = 2,
            })
        end)
    end
end

local function enterGame()
    fireRemote("EnterGame")
end

local function returnBase()
    fireRemote("ReturnToBase")
end

local function claimDaily()
    local r = Remotes and Remotes:FindFirstChild("Daily")
    if r then pcall(function() r:InvokeServer() end) end
end

-- Auto crate
local lastCrate = 0
RunService.Heartbeat:Connect(function()
    if not CFG.autoCrate then return end
    if os.clock() - lastCrate < 0.4 then return end
    lastCrate = os.clock()

    local origin = cam().CFrame.Position
    local grab = Remotes and Remotes:FindFirstChild("GrabCrate")
    if not grab then return end

    local function try(inst)
        local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
        if not part then return end
        if (part.Position - origin).Magnitude > CFG.crateRange then return end
        pcall(function() grab:FireServer(inst) end)
    end

    local map = Workspace:FindFirstChild("Map")
    for _, folder in ipairs({ Workspace, map }) do
        if not folder then continue end
        for _, ch in ipairs(folder:GetChildren()) do
            if isCrate(ch) then try(ch) end
            if ch:IsA("Folder") then
                for _, c in ipairs(ch:GetChildren()) do
                    if isCrate(c) then try(c) end
                end
            end
        end
    end
end)

-- Auto boost while flying
local lastBoost = 0
RunService.Heartbeat:Connect(function()
    if not CFG.autoBoost then return end
    if os.clock() - lastBoost < 0.5 then return end
    if not LP:GetAttribute("FlyingLocal") then return end
    lastBoost = os.clock()
    fireRemote("DroneInput", "boost", true)
end)

----------------------------------------------------------------
-- LiteUI
----------------------------------------------------------------
Lite.Themes.zeroline = {
    bg     = Color3.fromRGB(12, 16, 14),
    line   = Color3.fromRGB(40, 55, 48),
    text   = Color3.fromRGB(230, 245, 235),
    sub    = Color3.fromRGB(130, 155, 140),
    accent = Color3.fromRGB(80, 220, 140),
    warn   = Color3.fromRGB(255, 190, 60),
    danger = Color3.fromRGB(255, 80, 80),
    track  = Color3.fromRGB(28, 36, 32),
}

local ui = Lite.new({
    Title = "Zero Line",
    Subtitle = "FPV · ESP · Silent",
    Width = 360,
    Theme = "zeroline",
})

local tab = ui:Tabs({ "Combat", "ESP", "Utility", "Settings" }, { MaxHeight = 320 })

----------------------------------------------------------------
-- Combat
----------------------------------------------------------------
local combat = tab.Combat
combat:Section("Silent Aim")
combat:Toggle({ Name = "Enable Silent", Flag = "silent", Default = CFG.silent, Callback = function(v) CFG.silent = v end })
combat:Slider({ Name = "Silent FOV", Flag = "silentFov", Min = 40, Max = 500, Default = CFG.silentFov, Step = 5, Callback = function(v) CFG.silentFov = v end })
combat:Slider({ Name = "Hit chance %", Flag = "hitChance", Min = 1, Max = 100, Default = CFG.hitChance, Step = 1, Callback = function(v) CFG.hitChance = v end })

combat:Section("Aimbot")
combat:Toggle({ Name = "Enable Aimbot", Flag = "aimbot", Default = CFG.aimbot, Callback = function(v) CFG.aimbot = v end })
combat:Toggle({ Name = "Hold key (E)", Flag = "aimHold", Default = CFG.aimHold, Callback = function(v) CFG.aimHold = v end })
combat:Slider({ Name = "Smoothness", Flag = "aimSmooth", Min = 0.05, Max = 1, Default = CFG.aimSmooth, Step = 0.01, Callback = function(v) CFG.aimSmooth = v end })
combat:Slider({ Name = "Aim FOV", Flag = "aimFov", Min = 40, Max = 400, Default = CFG.aimFov, Step = 5, Callback = function(v) CFG.aimFov = v end })
combat:Toggle({ Name = "Show FOV ring", Flag = "showFov", Default = CFG.showFov, Callback = function(v) CFG.showFov = v end })

combat:Section("Targets")
combat:Toggle({ Name = "Players", Flag = "targetPlayers", Default = CFG.targetPlayers, Callback = function(v) CFG.targetPlayers = v end })
combat:Toggle({ Name = "Bots", Flag = "targetBots", Default = CFG.targetBots, Callback = function(v) CFG.targetBots = v end })
combat:Toggle({ Name = "Enemy drones", Flag = "targetDrones", Default = CFG.targetDrones, Callback = function(v) CFG.targetDrones = v end })
combat:Toggle({ Name = "Team check", Flag = "teamCheck", Default = CFG.teamCheck, Callback = function(v) CFG.teamCheck = v end })

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------
local esp = tab.ESP
esp:Section("Entities")
esp:Toggle({ Name = "Players", Flag = "espPlayers", Default = CFG.espPlayers, Callback = function(v) CFG.espPlayers = v end })
esp:Toggle({ Name = "Bots (Soldiers)", Flag = "espBots", Default = CFG.espBots, Callback = function(v) CFG.espBots = v end })
esp:Toggle({ Name = "Enemy drones", Flag = "espDrones", Default = CFG.espDrones, Callback = function(v) CFG.espDrones = v end })
esp:Toggle({ Name = "Crates", Flag = "espCrates", Default = CFG.espCrates, Callback = function(v) CFG.espCrates = v end })
esp:Toggle({ Name = "Vehicles", Flag = "espVehicles", Default = CFG.espVehicles, Callback = function(v) CFG.espVehicles = v end })

esp:Section("Style")
esp:Toggle({ Name = "Boxes", Flag = "boxes", Default = CFG.boxes, Callback = function(v) CFG.boxes = v end })
esp:Toggle({ Name = "Names", Flag = "names", Default = CFG.names, Callback = function(v) CFG.names = v end })
esp:Toggle({ Name = "Distance", Flag = "distance", Default = CFG.distance, Callback = function(v) CFG.distance = v end })
esp:Toggle({ Name = "Tracers", Flag = "tracers", Default = CFG.tracers, Callback = function(v) CFG.tracers = v end })
esp:Toggle({ Name = "Chams", Flag = "chams", Default = CFG.chams, Callback = function(v) CFG.chams = v end })
esp:Slider({ Name = "Max distance", Flag = "maxDist", Min = 100, Max = 3000, Default = CFG.maxDist, Step = 50, Callback = function(v) CFG.maxDist = v end })

----------------------------------------------------------------
-- Utility
----------------------------------------------------------------
local util = tab.Utility
util:Section("Drone")
util:Button({ Name = "Launch drone", Callback = launchDrone })
util:Toggle({ Name = "Auto boost (while flying)", Flag = "autoBoost", Default = CFG.autoBoost, Callback = function(v) CFG.autoBoost = v end })
util:Button({
    Name = "Detonate (impact pos)",
    Callback = function()
        fireRemote("DroneInput", "detonate", cam().CFrame.Position)
    end,
})

util:Section("Crates")
util:Toggle({ Name = "Auto grab crates", Flag = "autoCrate", Default = CFG.autoCrate, Callback = function(v) CFG.autoCrate = v end })
util:Slider({ Name = "Crate range", Flag = "crateRange", Min = 8, Max = 60, Default = CFG.crateRange, Step = 1, Callback = function(v) CFG.crateRange = v end })

util:Section("Session")
util:Button({ Name = "Enter game", Callback = enterGame })
util:Button({ Name = "Return to base", Callback = returnBase })
util:Button({ Name = "Claim daily", Callback = claimDaily })

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
        CFG.silent = false
        CFG.aimbot = false
        CFG.autoCrate = false
        for k in pairs(drawings) do clearKey(k) end
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
        Title = "Zero Line",
        Text = "Hub loaded · RightShift toggles UI",
        Duration = 4,
    })
end)
print("[ZeroLine] hub loaded | Fire remote:", FireRemote and "ok" or "missing")
