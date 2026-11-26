--[[
    Thrift&Flip: Resell Tycoon — Full Helper
    PlaceId: 94206080514907
    UI: LiteUI (Grokware)
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[ThriftHelper] LiteUI failed:", Lite)
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local Remotes = RS:WaitForChild("Remotes", 10)

local function RF(name)
    return Remotes and Remotes:FindFirstChild(name)
end

local R = {
    ThriftBuy = RF("ThriftBuy"),
    ThriftSnapshot = RF("ThriftSnapshot"),
    BasketAction = RF("BasketAction"),
    BasketSnapshot = RF("BasketSnapshot"),
    ComputerAction = RF("ComputerAction"),
    ComputerSnapshot = RF("ComputerSnapshot"),
    StaffAction = RF("StaffAction"),
    StaffSnapshot = RF("StaffSnapshot"),
    SupplierAction = RF("SupplierAction"),
    SupplierSnapshot = RF("SupplierSnapshot"),
    BagUpgradeRequest = RF("BagUpgradeRequest"),
    LogisticsAction = RF("LogisticsAction"),
    PhysicalRetailAction = RF("PhysicalRetailAction"),
    DailyRewardRequest = RF("DailyRewardRequest"),
    HourlyQuestRequest = RF("HourlyQuestRequest"),
    LevelRewardClaim = RF("LevelRewardClaim"),
    LevelRewardSnapshot = RF("LevelRewardSnapshot"),
    OfflineEarnings = RF("OfflineEarnings"),
    StayBonus = RF("StayBonus"),
    RebirthRequest = RF("RebirthRequest"),
    TraderBuy = RF("TraderBuy"),
    WheelOfFortuneSpin = RF("WheelOfFortuneSpin"),
    CardDropRequest = RF("CardDropRequest"),
    CardOpeningRequest = RF("CardOpeningRequest"),
    CardCollectionRequest = RF("CardCollectionRequest"),
    MapTravel = RF("MapTravel"),
    TeleportRequest = RF("TeleportRequest"),
    EngineeringAction = RF("EngineeringAction"),
    TrainingAction = RF("TrainingAction"),
    StreetwearDropRequest = RF("StreetwearDropRequest"),
    VipLoungeRequest = RF("VipLoungeRequest"),
    YouTuberPackRequest = RF("YouTuberPackRequest"),
    PerfumeAuctionRequest = RF("PerfumeAuctionRequest"),
    BloxyColaRequest = RF("BloxyColaRequest"),
    ArcadeRequest = RF("ArcadeRequest"),
    SalesTeam = RF("SalesTeam"),
    BusinessHub = RF("BusinessHub"),
    CompanyRequest = RF("CompanyRequest"),
    GlobalRequest = RF("GlobalRequest"),
    BillboardRequest = RF("BillboardRequest"),
    MoonRequest = RF("MoonRequest"),
    TrashBinRequest = RF("TrashBinRequest"),
    CommunityCodeRequest = RF("CommunityCodeRequest"),
}

local function inv(rf, ...)
    if not rf then return false, "missing remote" end
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

local function log(...)
    print("[ThriftHelper]", ...)
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local CFG = {
    -- ESP
    esp = true,
    showCommon = false,
    showUncommon = true,
    showRare = true,
    showEpic = true,
    showLegendary = true,
    showMythic = true,
    minTier = 2,
    maxDistance = 250,
    -- Auto
    autoBuy = false,
    autoBuyMinTier = 3, -- Rare+
    autoBuyAllOnRail = false, -- use BuyAll if any item meets min
    autoClaim = true,
    autoOffline = true,
    autoStay = false,
    interval = 1.2,
}

local stats = {
    last = "ready",
    buys = 0,
    claims = 0,
    shown = 0,
}

----------------------------------------------------------------
-- Rarity (Tier-only — game map)
----------------------------------------------------------------
local TIER_RARITY = {
    [1] = { "Common", Color3.fromRGB(200, 200, 200) },
    [2] = { "Uncommon", Color3.fromRGB(60, 200, 100) },
    [3] = { "Rare", Color3.fromRGB(70, 140, 255) },
    [4] = { "Epic", Color3.fromRGB(180, 70, 255) },
    [5] = { "Legendary", Color3.fromRGB(255, 180, 40) },
}

local function rarityFromTier(tier, name)
    tier = math.clamp(tonumber(tier) or 1, 1, 10)
    local n = string.lower(tostring(name or ""))
    if n:find("mythic", 1, true) or tier >= 6 then
        return "Mythic", Color3.fromRGB(255, 60, 200), tier
    end
    local row = TIER_RARITY[tier] or TIER_RARITY[1]
    return row[1], row[2], tier
end

local function rarityAllowed(rarity)
    if rarity == "Common" then return CFG.showCommon end
    if rarity == "Uncommon" then return CFG.showUncommon end
    if rarity == "Rare" then return CFG.showRare end
    if rarity == "Epic" then return CFG.showEpic end
    if rarity == "Legendary" then return CFG.showLegendary end
    if rarity == "Mythic" then return CFG.showMythic end
    return true
end

----------------------------------------------------------------
-- Stenders / Stock
----------------------------------------------------------------
local function getStenders()
    local map = workspace:FindFirstChild("Map")
    local ts = map and map:FindFirstChild("ThriftStore")
    return ts and ts:FindFirstChild("Stenders")
end

local function isStock(inst)
    return inst:IsA("Model") and inst.Name:sub(1, 6) == "Stock_"
end

local function readStock(inst)
    local tier = inst:GetAttribute("Tier") or 1
    local cat = inst:GetAttribute("Category") or ""
    local name = inst:GetAttribute("DisplayName")
        or inst:GetAttribute("BaseName")
        or inst:GetAttribute("DefinitionId")
        or inst.Name:gsub("^Stock_", ""):gsub("_Dirty$", ""):gsub("_Clean$", "")
    local rarity, color, tnum = rarityFromTier(tier, name)
    local stenderId = inst:GetAttribute("StenderId")
    local slotIndex = inst:GetAttribute("SlotIndex")
    return {
        tier = tnum,
        category = tostring(cat),
        name = tostring(name),
        rarity = rarity,
        color = color,
        stenderId = stenderId,
        slotIndex = tonumber(slotIndex),
        definitionId = inst:GetAttribute("DefinitionId"),
    }
end

local function eachStock(cb)
    local root = getStenders()
    if not root then return end
    for _, stender in ipairs(root:GetChildren()) do
        local sid = stender:GetAttribute("StenderId") or stender.Name
        for _, slot in ipairs(stender:GetChildren()) do
            if slot.Name:match("^Slot") then
                local slotNum = tonumber(slot.Name:match("%d+"))
                for _, ch in ipairs(slot:GetChildren()) do
                    if isStock(ch) then
                        local info = readStock(ch)
                        info.stenderId = info.stenderId or sid
                        info.slotIndex = info.slotIndex or slotNum
                        info.inst = ch
                        info.stender = stender
                        cb(info)
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
-- ESP
----------------------------------------------------------------
local tracked = {}

local function clearOne(inst)
    local t = tracked[inst]
    if not t then return end
    if t.hl then t.hl:Destroy() end
    if t.bill then t.bill:Destroy() end
    tracked[inst] = nil
end

local function clearESP()
    for inst in pairs(tracked) do clearOne(inst) end
end

local function ensureESP(info)
    local inst = info.inst
    if not CFG.esp or not rarityAllowed(info.rarity) or info.tier < CFG.minTier then
        clearOne(inst)
        return
    end
    local t = tracked[inst]
    if t then
        if t.hl then
            t.hl.FillColor = info.color
            t.hl.OutlineColor = info.color
        end
        if t.label then
            t.label.Text = string.format("%s\n%s · T%d\n%s", info.name, info.rarity, info.tier, info.category)
            t.label.TextColor3 = info.color
        end
        t.info = info
        return
    end

    local hl = Instance.new("Highlight")
    hl.Name = "ThriftRarityESP"
    hl.Adornee = inst
    hl.FillColor = info.color
    hl.OutlineColor = info.color
    hl.FillTransparency = 0.45
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = inst

    local bill = Instance.new("BillboardGui")
    bill.Name = "ThriftRarityTag"
    bill.Size = UDim2.fromOffset(150, 54)
    bill.StudsOffset = Vector3.new(0, 2.4, 0)
    bill.AlwaysOnTop = true
    bill.MaxDistance = CFG.maxDistance
    local anchor = inst:FindFirstChild("Root", true) or inst:FindFirstChildWhichIsA("BasePart", true) or inst
    bill.Adornee = anchor
    bill.Parent = inst

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = info.color
    label.TextStrokeTransparency = 0.35
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    label.Text = string.format("%s\n%s · T%d\n%s", info.name, info.rarity, info.tier, info.category)
    label.Parent = bill

    tracked[inst] = { hl = hl, bill = bill, label = label, info = info }
end

local function scanESP()
    local keep = {}
    eachStock(function(info)
        ensureESP(info)
        keep[info.inst] = true
    end)
    for inst in pairs(tracked) do
        if not keep[inst] or not inst.Parent then
            clearOne(inst)
        end
    end
    local n = 0
    for _ in pairs(tracked) do n += 1 end
    stats.shown = n
end

----------------------------------------------------------------
-- Thrift buy
-- Signature from client: ThriftBuy(StenderId, slotIndex, OfferId, action, activityKey?)
-- actions: "Buy", "BeginHold", "CommitHold", "CancelHold", "BuyAll"
----------------------------------------------------------------
local function snapshotStender(stenderId)
    return inv(R.ThriftSnapshot, stenderId)
end

-- Cobalt-verified:
-- ThriftBuy(StenderId, slotIndex, OfferId|nil, "Buy", ActivityKey)
-- ActivityKey = "StenderId|slot|ItemId|nil|<n>|timestamp"
local function makeActivityKey(stenderId, slotIndex, itemId, extra)
    extra = extra or "0"
    local ts = workspace:GetServerTimeNow()
    return string.format("%s|%s|%s|nil|%s|%s",
        tostring(stenderId),
        tostring(slotIndex),
        tostring(itemId or "unknown"),
        tostring(extra),
        tostring(ts)
    )
end

local function itemIdFromInfo(info)
    if not info then return "unknown" end
    local id = info.definitionId or info.name
    if type(id) == "string" then
        id = id:gsub("^Stock_", ""):gsub("_Dirty$", ""):gsub("_Clean$", "")
    end
    return id or "unknown"
end

local function buySlot(stenderId, slotIndex, offerId, action, itemId, extra)
    action = action or "Buy"
    slotIndex = tonumber(slotIndex) or 1
    local key = makeActivityKey(stenderId, slotIndex, itemId, extra or slotIndex)
    local a, b, c = inv(R.ThriftBuy, stenderId, slotIndex, offerId, action, key)
    stats.last = string.format("Buy %s#%s %s key=%s → %s %s",
        tostring(stenderId), tostring(slotIndex), action, key, tostring(a), tostring(b))
    log(stats.last)
    if a ~= false and a ~= nil then stats.buys += 1 end
    return a, b, c
end

local function buyAllOnStender(stenderId)
    local key = makeActivityKey(stenderId, 1, "BuyAll", "0")
    local a, b = inv(R.ThriftBuy, stenderId, 1, nil, "BuyAll", key)
    stats.last = string.format("BuyAll %s → %s %s", tostring(stenderId), tostring(a), tostring(b))
    log(stats.last)
    if a ~= false and a ~= nil then stats.buys += 1 end
    return a, b
end

local function tryAutoBuy()
    if not CFG.autoBuy then return end

    eachStock(function(info)
        if info.tier < CFG.autoBuyMinTier then return end
        local sid = info.stenderId
        local slot = info.slotIndex or 1
        if not sid then return end

        if CFG.autoBuyAllOnRail then
            -- handled per-stender below
            return
        end

        local iid = itemIdFromInfo(info)
        -- OfferId can be nil (confirmed via Cobalt)
        buySlot(sid, slot, nil, "Buy", iid, info.tier)
        task.wait(0.2)
    end)

    if CFG.autoBuyAllOnRail then
        local seen = {}
        eachStock(function(info)
            if info.tier < CFG.autoBuyMinTier then return end
            local sid = info.stenderId
            if not sid or seen[sid] then return end
            seen[sid] = true
            buyAllOnStender(sid)
            task.wait(0.35)
        end)
    end
end

----------------------------------------------------------------
-- Claims
----------------------------------------------------------------
local function claimDaily()
    local a, b = inv(R.DailyRewardRequest, "Get")
    -- try claim variants
    inv(R.DailyRewardRequest, "Claim")
    inv(R.DailyRewardRequest, "ClaimAll")
    stats.last = "Daily " .. tostring(a) .. " " .. tostring(b)
    stats.claims += 1
end

local function claimHourly()
    local snap = inv(R.HourlyQuestRequest, "Get")
    inv(R.HourlyQuestRequest, "Claim")
    if type(snap) == "table" then
        for i = 1, 8 do
            inv(R.HourlyQuestRequest, "Claim", snap.RoundId or snap.roundId, i)
        end
    end
    stats.last = "Hourly claimed"
    stats.claims += 1
end

local function claimLevel()
    inv(R.LevelRewardSnapshot)
    for i = 1, 20 do
        inv(R.LevelRewardClaim, i)
        inv(R.LevelRewardClaim, "Claim", i)
    end
    inv(R.LevelRewardClaim, "ClaimAll")
    stats.last = "Level rewards tried"
    stats.claims += 1
end

local function claimOffline()
    local a, b = inv(R.OfflineEarnings, "Read")
    inv(R.OfflineEarnings, "Claim")
    inv(R.OfflineEarnings, "Collect")
    stats.last = "Offline " .. tostring(a)
    stats.claims += 1
    return a, b
end

local function claimStay()
    local a, b = inv(R.StayBonus)
    inv(R.StayBonus, "Claim")
    stats.last = "StayBonus " .. tostring(a)
    stats.claims += 1
end

local function claimAll()
    claimDaily()
    claimHourly()
    claimLevel()
    claimOffline()
    claimStay()
    stats.last = "Claim-all done"
end

----------------------------------------------------------------
-- Other actions (best-effort)
----------------------------------------------------------------
local function bagUpgrade()
    local a, b = inv(R.BagUpgradeRequest)
    inv(R.BagUpgradeRequest, "Upgrade")
    inv(R.BagUpgradeRequest, "Buy")
    stats.last = "BagUpgrade " .. tostring(a)
end

local function computerListAll()
    inv(R.ComputerSnapshot)
    inv(R.ComputerAction, "ListAll")
    inv(R.ComputerAction, "List")
    inv(R.ComputerAction, "SellAll")
    stats.last = "Computer ListAll/Sell tried"
end

local function basketTake()
    inv(R.BasketSnapshot)
    inv(R.BasketAction, "Take")
    inv(R.BasketAction, "QuickSell")
    inv(R.BasketAction, "Open")
    stats.last = "Basket actions tried"
end

local function staffSnap()
    local a = inv(R.StaffSnapshot)
    stats.last = "StaffSnapshot " .. typeof(a)
    log("StaffSnapshot", a)
end

local function supplierSnap()
    local a = inv(R.SupplierSnapshot)
    stats.last = "SupplierSnapshot " .. typeof(a)
end

local function logisticsOpen()
    inv(R.LogisticsAction, "OpenComputer")
    inv(R.LogisticsAction, "Accept")
    inv(R.LogisticsAction, "Claim")
    stats.last = "Logistics tried"
end

local function retailCollect()
    inv(R.PhysicalRetailAction, "Collect")
    inv(R.PhysicalRetailAction, "Claim")
    inv(R.PhysicalRetailAction, "Open")
    stats.last = "Retail collect tried"
end

local function rebirth()
    local a, b = inv(R.RebirthRequest)
    inv(R.RebirthRequest, "Rebirth")
    stats.last = "Rebirth " .. tostring(a)
end

local function traderBuy()
    inv(R.TraderBuy)
    inv(R.TraderBuy, "Buy")
    stats.last = "TraderBuy tried"
end

local function wheelSpin()
    local a, b = inv(R.WheelOfFortuneSpin)
    stats.last = "Wheel " .. tostring(a)
end

local function cardDrop()
    inv(R.CardDropRequest)
    inv(R.CardOpeningRequest)
    inv(R.CardCollectionRequest)
    stats.last = "Cards tried"
end

local function sideClaims()
    inv(R.StreetwearDropRequest)
    inv(R.VipLoungeRequest)
    inv(R.YouTuberPackRequest)
    inv(R.PerfumeAuctionRequest)
    inv(R.BloxyColaRequest)
    inv(R.TrashBinRequest)
    stats.last = "Side systems tried"
end

----------------------------------------------------------------
-- LiteUI
----------------------------------------------------------------
if Lite.Themes then
    Lite.Themes.thrift = {
        bg = Color3.fromRGB(18, 22, 28),
        line = Color3.fromRGB(80, 160, 220),
        text = Color3.fromRGB(235, 240, 245),
        sub = Color3.fromRGB(140, 155, 170),
        accent = Color3.fromRGB(70, 170, 255),
        warn = Color3.fromRGB(255, 190, 80),
        danger = Color3.fromRGB(240, 90, 90),
        track = Color3.fromRGB(40, 48, 58),
    }
end

local ui = Lite.new({
    Title = "Thrift&Flip Helper",
    Subtitle = "ESP · Buy · Claims · Business",
    Width = 360,
    Theme = "thrift",
})

local tab = ui:Tabs({
    "ESP",
    "Buy",
    "Claims",
    "Business",
    "Extras",
    "Settings",
})

-- ESP tab
local espPanel = tab.ESP
espPanel:Section("Rarity ESP")
espPanel:Toggle({
    Name = "Enable ESP",
    Flag = "esp",
    Default = CFG.esp,
    Callback = function(v) CFG.esp = v; if not v then clearESP() else scanESP() end end,
})
espPanel:Toggle({
    Name = "Common (T1)",
    Flag = "showCommon",
    Default = CFG.showCommon,
    Callback = function(v) CFG.showCommon = v; scanESP() end,
})
espPanel:Toggle({
    Name = "Uncommon (T2)",
    Flag = "showUncommon",
    Default = CFG.showUncommon,
    Callback = function(v) CFG.showUncommon = v; scanESP() end,
})
espPanel:Toggle({
    Name = "Rare (T3)",
    Flag = "showRare",
    Default = CFG.showRare,
    Callback = function(v) CFG.showRare = v; scanESP() end,
})
espPanel:Toggle({
    Name = "Epic (T4)",
    Flag = "showEpic",
    Default = CFG.showEpic,
    Callback = function(v) CFG.showEpic = v; scanESP() end,
})
espPanel:Toggle({
    Name = "Legendary (T5)",
    Flag = "showLegendary",
    Default = CFG.showLegendary,
    Callback = function(v) CFG.showLegendary = v; scanESP() end,
})
espPanel:Toggle({
    Name = "Mythic",
    Flag = "showMythic",
    Default = CFG.showMythic,
    Callback = function(v) CFG.showMythic = v; scanESP() end,
})
espPanel:Slider({
    Name = "Min Tier",
    Flag = "minTier",
    Min = 1, Max = 5, Default = CFG.minTier,
    Callback = function(v) CFG.minTier = v; scanESP() end,
})
espPanel:Button({
    Name = "Rescan Rails",
    Callback = function() scanESP(); ui:Notify({ Title = "ESP", Text = "Shown: " .. stats.shown, Tone = "accent" }) end,
})

-- Buy tab
local buyPanel = tab.Buy
buyPanel:Section("Auto Buy")
buyPanel:Toggle({
    Name = "Auto Buy",
    Flag = "autoBuy",
    Default = CFG.autoBuy,
    Callback = function(v) CFG.autoBuy = v end,
})
buyPanel:Slider({
    Name = "Min Tier to Buy",
    Flag = "autoBuyMinTier",
    Min = 1, Max = 5, Default = CFG.autoBuyMinTier,
    Callback = function(v) CFG.autoBuyMinTier = v end,
})
buyPanel:Toggle({
    Name = "Use BuyAll on rail",
    Flag = "autoBuyAllOnRail",
    Default = CFG.autoBuyAllOnRail,
    Callback = function(v) CFG.autoBuyAllOnRail = v end,
})
buyPanel:Button({
    Name = "Buy matching now",
    Callback = function()
        tryAutoBuy()
        ui:Notify({ Title = "Buy", Text = stats.last, Tone = "accent" })
    end,
})
buyPanel:Separator()
buyPanel:Section("Manual")
buyPanel:Button({
    Name = "BuyAll on every rail (careful)",
    Callback = function()
        local root = getStenders()
        if not root then return end
        for _, st in ipairs(root:GetChildren()) do
            local sid = st:GetAttribute("StenderId") or st.Name
            buyAllOnStender(sid)
            task.wait(0.3)
        end
        ui:Notify({ Title = "BuyAll", Text = stats.last, Tone = "warn" })
    end,
})

-- Claims tab
local claimPanel = tab.Claims
claimPanel:Section("Auto Claims")
claimPanel:Toggle({
    Name = "Auto Claim loop",
    Flag = "autoClaim",
    Default = CFG.autoClaim,
    Callback = function(v) CFG.autoClaim = v end,
})
claimPanel:Toggle({
    Name = "Auto Offline",
    Flag = "autoOffline",
    Default = CFG.autoOffline,
    Callback = function(v) CFG.autoOffline = v end,
})
claimPanel:Toggle({
    Name = "Auto StayBonus",
    Flag = "autoStay",
    Default = CFG.autoStay,
    Callback = function(v) CFG.autoStay = v end,
})
claimPanel:Separator()
claimPanel:Button({ Name = "Claim All", Callback = function() claimAll(); ui:Notify({ Title = "Claims", Text = stats.last }) end })
claimPanel:Button({ Name = "Daily", Callback = function() claimDaily() end })
claimPanel:Button({ Name = "Hourly Quests", Callback = function() claimHourly() end })
claimPanel:Button({ Name = "Level Rewards", Callback = function() claimLevel() end })
claimPanel:Button({ Name = "Offline Earnings", Callback = function() claimOffline() end })
claimPanel:Button({ Name = "Stay Bonus", Callback = function() claimStay() end })

-- Business tab
local biz = tab.Business
biz:Section("Bag / Basket / Computer")
biz:Button({ Name = "Bag Upgrade", Callback = function() bagUpgrade() end })
biz:Button({ Name = "Basket Take / QuickSell", Callback = function() basketTake() end })
biz:Button({ Name = "Computer List / Sell", Callback = function() computerListAll() end })
biz:Separator()
biz:Section("Staff / Suppliers / Logistics")
biz:Button({ Name = "Staff Snapshot", Callback = function() staffSnap() end })
biz:Button({ Name = "Supplier Snapshot", Callback = function() supplierSnap() end })
biz:Button({ Name = "Logistics Open/Claim", Callback = function() logisticsOpen() end })
biz:Button({ Name = "Physical Retail Collect", Callback = function() retailCollect() end })
biz:Separator()
biz:Section("Progress")
biz:Button({ Name = "Rebirth", Callback = function() rebirth() end })
biz:Button({ Name = "Trader Buy", Callback = function() traderBuy() end })

-- Extras
local ex = tab.Extras
ex:Section("Side systems")
ex:Button({ Name = "Wheel of Fortune Spin", Callback = function() wheelSpin() end })
ex:Button({ Name = "Card Drop / Open", Callback = function() cardDrop() end })
ex:Button({ Name = "Streetwear / VIP / YT / Perfume / Cola / Trash", Callback = function() sideClaims() end })
ex:Button({
    Name = "MapTravel (no arg)",
    Callback = function()
        inv(R.MapTravel)
        inv(R.TeleportRequest)
        stats.last = "Travel fired"
    end,
})

-- Settings
local set = tab.Settings
set:Section("Loop")
set:Slider({
    Name = "Interval (sec)",
    Flag = "interval",
    Min = 0.5, Max = 5, Default = CFG.interval, Step = 0.1,
    Callback = function(v) CFG.interval = v end,
})
set:Slider({
    Name = "ESP Max Distance",
    Flag = "maxDistance",
    Min = 50, Max = 500, Default = CFG.maxDistance,
    Callback = function(v) CFG.maxDistance = v end,
})
set:Separator()
set:Label({ Text = "Player: " .. LP.Name })
set:Label({ Text = "LiteUI " .. tostring(Lite.Version or "?") })
local statusLabel = set:Label({ Text = "Status: ready" })
set:Button({
    Name = "Unload",
    Callback = function()
        CFG.esp = false
        CFG.autoBuy = false
        CFG.autoClaim = false
        clearESP()
        ui:Destroy()
    end,
})

if ui.Settings then
    ui:Settings({ Panel = set })
end
if ui.Profiles then
    set:Separator()
    set:Section("Profiles")
    ui:Profiles({ Panel = set })
end

ui:Show()
ui:Notify({ Title = "Thrift&Flip", Text = "Helper loaded — RightShift to toggle UI", Tone = "accent" })

----------------------------------------------------------------
-- Loops
----------------------------------------------------------------
task.spawn(function()
    while true do
        if CFG.esp then scanESP() end
        if CFG.autoBuy then
            pcall(tryAutoBuy)
        end
        if CFG.autoClaim then
            pcall(claimDaily)
            pcall(claimHourly)
            pcall(claimLevel)
        end
        if CFG.autoOffline then
            pcall(claimOffline)
        end
        if CFG.autoStay then
            pcall(claimStay)
        end
        if statusLabel and statusLabel.Set then
            statusLabel:Set(string.format("ESP %d · buys %d · claims %d · %s", stats.shown, stats.buys, stats.claims, stats.last))
        end
        task.wait(CFG.interval)
    end
end)

-- distance gate for highlights
RunService.RenderStepped:Connect(function()
    if not CFG.esp then return end
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local o = hrp.Position
    for inst, t in pairs(tracked) do
        local pos
        if inst.PrimaryPart then pos = inst.PrimaryPart.Position
        else
            local p = inst:FindFirstChild("Root", true) or inst:FindFirstChildWhichIsA("BasePart", true)
            pos = p and p.Position
        end
        if pos and t.hl then
            local on = (pos - o).Magnitude <= CFG.maxDistance
            t.hl.Enabled = on
            if t.bill then t.bill.Enabled = on end
        end
    end
end)

-- live stock
task.defer(function()
    local root = getStenders()
    if root then
        root.DescendantAdded:Connect(function(d)
            if isStock(d) then task.defer(scanESP) end
        end)
    end
end)

scanESP()
log("loaded")
