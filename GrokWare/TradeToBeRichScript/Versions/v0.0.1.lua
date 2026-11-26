--[[
    Trade To Be Rich — Full Helper
    PlaceId: 77588808128300

    All remotes under:
      ReplicatedStorage.Shared.Packages._Index.littensy_remo@1.5.2.remo.container
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local CONTAINER = RS:WaitForChild("Shared", 10)
    and RS.Shared:FindFirstChild("Packages")
local function findContainer()
    if not CONTAINER then
        CONTAINER = RS:FindFirstChild("Shared")
        if CONTAINER then
            CONTAINER = CONTAINER:FindFirstChild("Packages")
        end
    end
    if not CONTAINER then
        return nil
    end
    -- walk to remo.container
    local idx = CONTAINER:FindFirstChild("_Index")
    if not idx then
        return nil
    end
    for _, child in ipairs(idx:GetChildren()) do
        if child.Name:find("littensy_remo") then
            local remo = child:FindFirstChild("remo")
            if remo then
                return remo:FindFirstChild("container")
            end
        end
    end
    return nil
end

local container = findContainer()
if not container then
    -- fallback: search any RemoteFunction named like our list
    warn("[TradeHelper] remo.container not found, scanning…")
end

local function remote(name)
    if container then
        local r = container:FindFirstChild(name)
        if r then
            return r
        end
    end
    -- deep search
    for _, d in ipairs(RS:GetDescendants()) do
        if (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) and d.Name == name then
            if d.Parent and d.Parent.Name == "container" then
                return d
            end
        end
    end
    for _, d in ipairs(RS:GetDescendants()) do
        if (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) and d.Name == name then
            return d
        end
    end
    return nil
end

local R = {
    SellAll = remote("SellAll"),
    Stand = remote("Stand"),
    Sell = remote("Sell"),
    ClaimOffline = remote("ClaimOffline"),
    Trade = remote("Trade"),
    HousePlace = remote("HousePlace"),
    ClaimGift = remote("ClaimGift"),
    UpgradeHouse = remote("UpgradeHouse"),
    AfkHop = remote("AfkHop"),
    Rebirth = remote("Rebirth"),
    PlayerTrade = remote("PlayerTrade"),
    Device = remote("Device"),
    BuySlot = remote("BuySlot"),
    AdminHouse = remote("AdminHouse"),
    Conveyor = remote("Conveyor"),
    UpgradeLuck = remote("UpgradeLuck"),
    BuyProduct = remote("BuyProduct"),
    BeltRobux = remote("BeltRobux"),
    GetPlot = remote("GetPlot"),
    Setting = remote("Setting"),
    CollectorGive = remote("CollectorGive"),
    AutoBuy = remote("AutoBuy"),
    Effect = remote("Effect"),
    AdminSetMoney = remote("AdminSetMoney"),
    LockItem = remote("LockItem"),
    AdminWipeData = remote("AdminWipeData"),
    EquipBest = remote("EquipBest"),
}

local CFG = {
    autoConveyor = false,
    autoBuy = false,
    autoTrade = false,
    autoStand = false,
    autoSell = false,
    autoSellAll = false,
    autoClaimGift = true,
    autoClaimOffline = true,
    autoCollector = true,
    autoEquipBest = false,
    autoLuck = false,
    autoHouse = false,
    interval = 0.6,
}

local stats = {
    last = "ready",
    hits = 0,
}

local function log(...)
    print("[TradeHelper]", ...)
end

local function inv(rf, ...)
    if not rf then
        return false, "missing remote"
    end
    local pack = table.pack(pcall(function(...)
        if rf:IsA("RemoteFunction") then
            return rf:InvokeServer(...)
        else
            rf:FireServer(...)
            return true
        end
    end, ...))
    if not pack[1] then
        return false, tostring(pack[2])
    end
    return table.unpack(pack, 2, pack.n)
end

-- dump which remotes resolved
do
    local ok, miss = {}, {}
    for k, v in pairs(R) do
        if v then
            table.insert(ok, k)
        else
            table.insert(miss, k)
        end
    end
    table.sort(ok)
    table.sort(miss)
    log("found:", table.concat(ok, ", "))
    if #miss > 0 then
        log("missing:", table.concat(miss, ", "))
    end
end

----------------------------------------------------------------
-- Actions
----------------------------------------------------------------
local function doConveyor(...)
    local a, b = inv(R.Conveyor, ...)
    stats.last = "Conveyor " .. tostring(a) .. " " .. tostring(b)
    stats.hits += 1
    return a, b
end

local function doAutoBuy(state)
    -- try true/false toggle
    local a, b = inv(R.AutoBuy, state == nil and true or state)
    stats.last = "AutoBuy " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doTrade(...)
    local a, b = inv(R.Trade, ...)
    stats.last = "Trade " .. tostring(a) .. " " .. tostring(b)
    stats.hits += 1
    return a, b
end

local function doStand(...)
    local a, b = inv(R.Stand, ...)
    stats.last = "Stand " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doSell(...)
    local a, b = inv(R.Sell, ...)
    stats.last = "Sell " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doSellAll()
    local a, b = inv(R.SellAll)
    stats.last = "SellAll " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doHousePlace(...)
    local a, b = inv(R.HousePlace, ...)
    stats.last = "HousePlace " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doUpgradeHouse(...)
    local a, b = inv(R.UpgradeHouse, ...)
    stats.last = "UpgradeHouse " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doUpgradeLuck(...)
    local a, b = inv(R.UpgradeLuck, ...)
    stats.last = "UpgradeLuck " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doBuySlot(...)
    local a, b = inv(R.BuySlot, ...)
    stats.last = "BuySlot " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doClaimGift()
    local a, b = inv(R.ClaimGift)
    stats.last = "ClaimGift " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doClaimOffline()
    local a, b = inv(R.ClaimOffline)
    stats.last = "ClaimOffline " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doCollector()
    local a, b = inv(R.CollectorGive)
    stats.last = "Collector " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doEquipBest()
    local a, b = inv(R.EquipBest)
    stats.last = "EquipBest " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doRebirth()
    local a, b = inv(R.Rebirth)
    stats.last = "Rebirth " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doLockItem(...)
    local a, b = inv(R.LockItem, ...)
    stats.last = "LockItem " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

local function doGetPlot()
    local a, b = inv(R.GetPlot)
    stats.last = "GetPlot " .. tostring(a)
    log("GetPlot →", a, b)
    return a, b
end

local function doPlayerTrade(...)
    local a, b = inv(R.PlayerTrade, ...)
    stats.last = "PlayerTrade " .. tostring(a) .. " " .. tostring(b)
    return a, b
end

-- Admin
local function doAdminMoney(amount)
    amount = amount or 1000000
    local a, b = inv(R.AdminSetMoney, amount)
    stats.last = "AdminSetMoney " .. tostring(a) .. " " .. tostring(b)
    log(stats.last)
    return a, b
end

local function doAdminWipe()
    local a, b = inv(R.AdminWipeData)
    stats.last = "AdminWipeData " .. tostring(a) .. " " .. tostring(b)
    log(stats.last)
    return a, b
end

local function doAdminHouse(...)
    local a, b = inv(R.AdminHouse, ...)
    stats.last = "AdminHouse " .. tostring(a) .. " " .. tostring(b)
    log(stats.last)
    return a, b
end

local function doAfkHop()
    inv(R.AfkHop)
    stats.last = "AfkHop fired"
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "TradeToBeRichHelper"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(320, 520)
frame.Position = UDim2.fromOffset(12, 80)
frame.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -12, 0, 26)
title.Position = UDim2.fromOffset(8, 6)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(120, 220, 160)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Trade To Be Rich"
title.Parent = frame

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -12, 0, 48)
status.Position = UDim2.fromOffset(8, 32)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(160, 175, 190)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "…"
status.Parent = frame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -8, 1, -90)
scroll.Position = UDim2.fromOffset(4, 84)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.fromOffset(0, 900)
scroll.Parent = frame

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local order = 0
local function addBtn(text, cb, color)
    order += 1
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -12, 0, 28)
    b.BackgroundColor3 = color or Color3.fromRGB(45, 90, 70)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.Text = text
    b.LayoutOrder = order
    b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        task.spawn(cb)
    end)
    return b
end

local function addToggle(name, key)
    local b
    b = addBtn(name .. ": OFF", function()
        CFG[key] = not CFG[key]
        b.Text = name .. ": " .. (CFG[key] and "ON" or "OFF")
        b.BackgroundColor3 = CFG[key] and Color3.fromRGB(40, 140, 90) or Color3.fromRGB(50, 55, 62)
    end, Color3.fromRGB(50, 55, 62))
    return b
end

local function addLabel(text)
    order += 1
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -12, 0, 20)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    l.TextColor3 = Color3.fromRGB(100, 180, 140)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.LayoutOrder = order
    l.Parent = scroll
end

-- Farm
addLabel("— Auto Farm —")
addToggle("Auto Conveyor", "autoConveyor")
addToggle("AutoBuy remote", "autoBuy")
addToggle("Auto Trade NPC", "autoTrade")
addToggle("Auto Stand", "autoStand")
addToggle("Auto Sell", "autoSell")
addToggle("Auto SellAll", "autoSellAll")
addToggle("Auto Claim Gift", "autoClaimGift")
addToggle("Auto Claim Offline", "autoClaimOffline")
addToggle("Auto Collector", "autoCollector")
addToggle("Auto EquipBest", "autoEquipBest")
addToggle("Auto UpgradeLuck", "autoLuck")
addToggle("Auto UpgradeHouse", "autoHouse")

addLabel("— Manual —")
addBtn("Conveyor (no args)", function()
    doConveyor()
end)
addBtn("AutoBuy true", function()
    doAutoBuy(true)
end)
addBtn("Trade (no args)", function()
    doTrade()
end)
addBtn("Stand", function()
    doStand()
end)
addBtn("Sell", function()
    doSell()
end)
addBtn("SellAll", function()
    doSellAll()
end, Color3.fromRGB(160, 100, 40))
addBtn("HousePlace", function()
    doHousePlace()
end)
addBtn("UpgradeHouse", function()
    doUpgradeHouse()
end)
addBtn("UpgradeLuck", function()
    doUpgradeLuck()
end)
addBtn("BuySlot", function()
    doBuySlot()
end)
addBtn("ClaimGift", function()
    doClaimGift()
end)
addBtn("ClaimOffline", function()
    doClaimOffline()
end)
addBtn("CollectorGive", function()
    doCollector()
end)
addBtn("EquipBest", function()
    doEquipBest()
end)
addBtn("Rebirth", function()
    doRebirth()
end, Color3.fromRGB(120, 60, 140))
addBtn("GetPlot", function()
    doGetPlot()
end)
addBtn("AfkHop", function()
    doAfkHop()
end)

addLabel("— Admin (may fail if not admin) —")
addBtn("AdminSetMoney 1M", function()
    doAdminMoney(1000000)
end, Color3.fromRGB(160, 50, 50))
addBtn("AdminSetMoney 100M", function()
    doAdminMoney(100000000)
end, Color3.fromRGB(160, 50, 50))
addBtn("AdminHouse", function()
    doAdminHouse()
end, Color3.fromRGB(160, 50, 50))
addBtn("AdminWipeData", function()
    doAdminWipe()
end, Color3.fromRGB(100, 20, 20))

list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scroll.CanvasSize = UDim2.fromOffset(0, list.AbsoluteContentSize.Y + 12)
end)

----------------------------------------------------------------
-- Loop
----------------------------------------------------------------
task.spawn(function()
    while gui.Parent do
        status.Text = ("hits %d\n%s"):format(stats.hits, stats.last)

        if CFG.autoConveyor then
            doConveyor()
        end
        if CFG.autoBuy then
            doAutoBuy(true)
        end
        if CFG.autoTrade then
            doTrade()
        end
        if CFG.autoStand then
            doStand()
        end
        if CFG.autoSell then
            doSell()
        end
        if CFG.autoSellAll then
            doSellAll()
        end
        if CFG.autoClaimGift then
            doClaimGift()
        end
        if CFG.autoClaimOffline then
            doClaimOffline()
        end
        if CFG.autoCollector then
            doCollector()
        end
        if CFG.autoEquipBest then
            doEquipBest()
        end
        if CFG.autoLuck then
            doUpgradeLuck()
        end
        if CFG.autoHouse then
            doUpgradeHouse()
        end

        task.wait(CFG.interval)
    end
end)

log("loaded")
