--[[
    SHUFFLED! Utility Hub  ·  LiteUI
    PlaceId 97895487991697

    Features:
      - Auto Collect Income
      - Pack opener helper (Artist / Limited / named packs)
      - Collection rarity stats (from ClientData)
      - Quick Sell filter (by rarity)
      - Auto Fuse
      - Claim Daily / Quests
      - Trade / Unique pull notifier
]]

local LIB_URL = "https://raw.githubusercontent.com/ALuaUser/UIs/refs/heads/main/Grokware/v0.0.7/Source.lua"

local ok, Lite = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not ok or type(Lite) ~= "table" then
    warn("[Shuffled] LiteUI failed:", Lite)
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)

local function rf(name)
    local r = RemotesFolder and RemotesFolder:FindFirstChild(name)
    return r
end

local function invoke(name, ...)
    local r = rf(name)
    if not r then
        return false, "missing remote " .. name
    end
    local args = table.pack(...)
    local ok2, res = pcall(function()
        return r:InvokeServer(table.unpack(args, 1, args.n))
    end)
    return ok2, res
end

local function fire(name, ...)
    local r = rf(name)
    if not r then
        return false, "missing remote " .. name
    end
    local args = table.pack(...)
    local ok2, err = pcall(function()
        r:FireServer(table.unpack(args, 1, args.n))
    end)
    return ok2, err
end

----------------------------------------------------------------
-- CLIENT DATA / CONFIG (optional)
----------------------------------------------------------------
local ClientData, Config

pcall(function()
    local ps = LP:WaitForChild("PlayerScripts", 5)
    if not ps then
        return
    end
    local controllers = ps:FindFirstChild("Controllers")
    if controllers then
        local mod = controllers:FindFirstChild("ClientData")
        if mod then
            ClientData = require(mod)
        end
    end
end)

pcall(function()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared and shared:FindFirstChild("Config") then
        Config = require(shared.Config)
    end
end)

local function cd(key)
    if ClientData and type(ClientData.get) == "function" then
        local ok2, v = pcall(ClientData.get, key)
        if ok2 then
            return v
        end
    end
    return nil
end

local RARITIES = { "Demo", "Single", "Hit", "Platinum", "Diamond", "Unique" }

local RARITY_COLOR = {
    Demo = Color3.fromRGB(160, 160, 170),
    Single = Color3.fromRGB(120, 180, 255),
    Hit = Color3.fromRGB(100, 220, 140),
    Platinum = Color3.fromRGB(200, 210, 230),
    Diamond = Color3.fromRGB(120, 220, 255),
    Unique = Color3.fromRGB(255, 180, 60),
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local S = {
    autoIncome = false,
    incomeDelay = 30,
    autoFuse = false,
    fuseDelay = 20,
    autoDaily = false,
    packType = "Artist", -- Artist | Limited | custom
    packId = "",
    packCount = 1,
    skipAnim = true,
    sellRarities = {
        Demo = true,
        Single = true,
        Hit = false,
        Platinum = false,
        Diamond = false,
        Unique = false,
    },
    keepOne = true,
    skipFavorites = true,
    notifyUnique = true,
    notifyDiamond = true,
    notifyTrade = true,
    log = {},
}

local function pushLog(msg)
    table.insert(S.log, 1, os.date("%H:%M:%S") .. "  " .. msg)
    while #S.log > 40 do
        table.remove(S.log)
    end
end

----------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------
local notifyUi

local function toast(title, text, tone)
    if notifyUi then
        notifyUi(title, text, tone or "accent")
    end
    pushLog(title .. ": " .. text)
end

local function collectIncome()
    local ok2, res = invoke("CollectIncome")
    if ok2 and type(res) == "table" then
        if res.ok or res.amount or res.coins then
            local amt = res.amount or res.coins or res.gained
            toast("Income", amt and ("Collected " .. tostring(amt)) or "Collected", "accent")
            return true
        end
        if res.reason then
            toast("Income", tostring(res.reason), "warn")
            return false
        end
    end
    if ok2 then
        toast("Income", "Called CollectIncome", "accent")
        return true
    end
    toast("Income", tostring(res), "danger")
    return false
end

local function claimDaily()
    local ok2, res = invoke("ClaimDaily")
    if ok2 and type(res) == "table" and res.ok then
        toast("Daily", "Claimed", "accent")
        return true
    end
    toast("Daily", (type(res) == "table" and res.reason) or tostring(res), "warn")
    return false
end

local function claimQuest(id)
    local ok2, res = invoke("ClaimQuest", id)
    if ok2 and type(res) == "table" and res.ok then
        toast("Quest", "Claimed " .. tostring(id), "accent")
        return true
    end
    return false
end

local function tryClaimAllQuests()
    local quests = cd("Quests")
    local n = 0
    if type(quests) == "table" then
        for id, q in pairs(quests) do
            if type(q) == "table" and (q.ready or q.claimable or q.done == true) then
                if claimQuest(id) then
                    n += 1
                end
            elseif type(id) == "string" or type(id) == "number" then
                -- try claim by id opportunistically
            end
        end
    end
    -- also try RefreshQuests
    pcall(function()
        invoke("RefreshQuests")
    end)
    toast("Quests", n > 0 and ("Claimed " .. n) or "No ready quests found", n > 0 and "accent" or "warn")
end

local function autoFuseNow()
    local ok2, res = invoke("AutoFuseNow")
    if ok2 and type(res) == "table" and res.ok then
        toast("Fuse", "AutoFuse ran", "accent")
        return true
    end
    -- fallback Fuse if needed
    if not ok2 then
        ok2, res = invoke("Fuse")
    end
    if ok2 and type(res) == "table" and res.ok then
        toast("Fuse", "Fuse ok", "accent")
        return true
    end
    toast("Fuse", (type(res) == "table" and res.reason) or tostring(res), "warn")
    return false
end

local function openPack()
    local ptype = S.packType
    local pid = S.packId ~= "" and S.packId or nil
    local count = math.clamp(tonumber(S.packCount) or 1, 1, 50)
    local skip = S.skipAnim == true

    -- dump patterns:
    -- OpenPack("Artist", artistId, 1, false)
    -- OpenPack("Limited", limitedId, n, false)
    -- OpenPack(packName, nil, 1, true)
    local ok2, res
    if ptype == "Artist" or ptype == "Limited" then
        if not pid then
            toast("Pack", "Set Pack ID (artist/limited id)", "danger")
            return false
        end
        ok2, res = invoke("OpenPack", ptype, pid, count, skip)
    else
        -- treat packType as pack key name
        ok2, res = invoke("OpenPack", ptype, pid, count, skip)
    end

    if not ok2 then
        toast("Pack", tostring(res), "danger")
        return false
    end

    -- log cards if table result
    if type(res) == "table" then
        local cards = res.cards or res.pulls or res.result or res
        if type(cards) == "table" then
            local best = nil
            for _, c in pairs(cards) do
                if type(c) == "table" then
                    local r = c.rarity or (c.info and c.info.rarity)
                    if r == "Unique" and S.notifyUnique then
                        toast("UNIQUE!", tostring(c.name or c.song or c.title or "card"), "warn")
                    elseif r == "Diamond" and S.notifyDiamond then
                        toast("Diamond", tostring(c.name or c.song or c.title or "card"), "accent")
                    end
                    if r == "Unique" then
                        best = "Unique"
                    elseif r == "Diamond" and best ~= "Unique" then
                        best = "Diamond"
                    end
                end
            end
            toast("Pack", best and ("Opened · best " .. best) or "Opened", "accent")
        else
            if res.ok == false then
                toast("Pack", tostring(res.reason or "failed"), "warn")
                return false
            end
            toast("Pack", "Opened", "accent")
        end
    else
        toast("Pack", "Opened", "accent")
    end
    return true
end

local function quickSell()
    local rarities = {}
    for r, on in pairs(S.sellRarities) do
        if on then
            table.insert(rarities, r)
        end
    end
    if #rarities == 0 then
        toast("Sell", "Pick at least one rarity", "warn")
        return false
    end
    local ok2, res = invoke("QuickSell", {
        rarities = rarities,
        keepOne = S.keepOne,
        skipFavorites = S.skipFavorites,
    })
    if ok2 and type(res) == "table" and res.ok then
        local sold = res.sold or res.count or res.amount
        toast("Sell", sold and ("Sold " .. tostring(sold)) or "Done", "accent")
        return true
    end
    -- fallback SellCards
    if not ok2 then
        ok2, res = invoke("SellCards", rarities)
    end
    if ok2 and type(res) == "table" and (res.ok or res.sold) then
        toast("Sell", "Sold", "accent")
        return true
    end
    toast("Sell", (type(res) == "table" and res.reason) or tostring(res), "warn")
    return false
end

local function collectionStats()
    local cards = cd("Cards")
    local counts = {}
    for _, r in ipairs(RARITIES) do
        counts[r] = 0
    end
    local total = 0

    local function countCard(c)
        if type(c) ~= "table" then
            return
        end
        local r = c.rarity or (c.info and c.info.rarity)
        if r and counts[r] ~= nil then
            local n = tonumber(c.count or c.qty or c.amount) or 1
            counts[r] = counts[r] + n
            total += n
        end
    end

    if type(cards) == "table" then
        if type(cards.Stacks) == "table" then
            for _, stack in pairs(cards.Stacks) do
                countCard(stack)
                if type(stack) == "table" and stack.info then
                    countCard(stack.info)
                end
            end
        end
        if type(cards.List) == "table" then
            for _, c in pairs(cards.List) do
                countCard(c)
            end
        end
        -- flat map of uid -> card
        for k, v in pairs(cards) do
            if k ~= "Stacks" and k ~= "List" then
                countCard(v)
            end
        end
    end

    return counts, total
end

----------------------------------------------------------------
-- NOTIFY HOOKS
----------------------------------------------------------------
task.spawn(function()
    local notify = rf("Notify")
    if notify and notify:IsA("RemoteEvent") then
        notify.OnClientEvent:Connect(function(...)
            local args = { ... }
            local msg = ""
            for i, a in ipairs(args) do
                if type(a) == "string" then
                    msg = msg .. (msg ~= "" and " " or "") .. a
                elseif type(a) == "table" then
                    local r = a.rarity or (a.info and a.info.rarity)
                    local name = a.name or a.song or a.title
                    if r == "Unique" and S.notifyUnique then
                        toast("UNIQUE PULL", tostring(name or "card"), "warn")
                    elseif r == "Diamond" and S.notifyDiamond then
                        toast("Diamond pull", tostring(name or "card"), "accent")
                    end
                    if r then
                        msg = msg .. (msg ~= "" and " " or "") .. tostring(r)
                    end
                    if name then
                        msg = msg .. " " .. tostring(name)
                    end
                end
            end
            if msg ~= "" then
                pushLog("Notify: " .. msg)
            end
        end)
    end

    local tradeEv = rf("TradeEvent")
    if tradeEv and tradeEv:IsA("RemoteEvent") then
        tradeEv.OnClientEvent:Connect(function(...)
            if not S.notifyTrade then
                return
            end
            toast("Trade", "Trade event received", "warn")
        end)
    end

    local dataSync = rf("DataSync")
    if dataSync and dataSync:IsA("RemoteEvent") then
        dataSync.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then
                return
            end
            -- watch for card updates with Unique
            local cards = payload.Cards or payload.cards
            if type(cards) == "table" and S.notifyUnique then
                -- light touch — log only
            end
        end)
    end
end)

----------------------------------------------------------------
-- LOOPS
----------------------------------------------------------------
task.spawn(function()
    while true do
        local d = math.max(5, S.incomeDelay)
        task.wait(d)
        if S.autoIncome then
            pcall(collectIncome)
        end
    end
end)

task.spawn(function()
    while true do
        local d = math.max(5, S.fuseDelay)
        task.wait(d)
        if S.autoFuse then
            pcall(autoFuseNow)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(120)
        if S.autoDaily then
            pcall(claimDaily)
        end
    end
end)

----------------------------------------------------------------
-- LITEUI
----------------------------------------------------------------
Lite.Themes.shuffled = {
    bg = Color3.fromRGB(18, 18, 24),
    line = Color3.fromRGB(220, 200, 255),
    text = Color3.fromRGB(245, 240, 255),
    sub = Color3.fromRGB(150, 140, 170),
    accent = Color3.fromRGB(160, 120, 255),
    warn = Color3.fromRGB(255, 190, 90),
    danger = Color3.fromRGB(240, 100, 120),
    track = Color3.fromRGB(40, 36, 52),
}

local ui = Lite.new({
    Name = "ShuffledHub",
    Key = Enum.KeyCode.RightShift,
})
ui:Watermark({ Text = "SHUFFLED Hub" })

notifyUi = function(title, text, tone)
    ui:Notify({ Title = title, Text = text, Tone = tone or "accent" })
end

local card = ui:Card({
    Title = "SHUFFLED!",
    Subtitle = "Packs · Income · Sell · Fuse",
    Value = "—",
    Tone = "accent",
})

local tab = ui:Tabs({ "Home", "Packs", "Sell", "Fuse", "Stats", "Alerts", "Settings" }, { MaxHeight = 300 })

----------------------------------------------------------------
-- HOME
----------------------------------------------------------------
local home = tab.Home
home:Section("Quick actions")
home:ButtonRow({
    {
        Name = "Collect Income",
        Callback = function()
            collectIncome()
        end,
    },
    {
        Name = "Claim Daily",
        Callback = function()
            claimDaily()
        end,
    },
})
home:Button({
    Name = "Try claim quests",
    Callback = function()
        tryClaimAllQuests()
    end,
})
home:Separator()
home:Section("Automation")
home:Toggle({
    Name = "Auto Collect Income",
    Flag = "auto_income",
    Default = false,
    Callback = function(v)
        S.autoIncome = v
        card:Set({ Value = v and "AUTO" or "—" })
    end,
})
home:Slider({
    Name = "Income interval",
    Min = 10,
    Max = 120,
    Step = 5,
    Default = 30,
    Suffix = "s",
    Flag = "income_delay",
    Callback = function(v)
        S.incomeDelay = v
    end,
})
home:Toggle({
    Name = "Auto Fuse",
    Flag = "auto_fuse",
    Default = false,
    Callback = function(v)
        S.autoFuse = v
    end,
})
home:Slider({
    Name = "Fuse interval",
    Min = 10,
    Max = 120,
    Step = 5,
    Default = 20,
    Suffix = "s",
    Flag = "fuse_delay",
    Callback = function(v)
        S.fuseDelay = v
    end,
})
home:Toggle({
    Name = "Auto Claim Daily (2m)",
    Flag = "auto_daily",
    Default = false,
    Callback = function(v)
        S.autoDaily = v
    end,
})

local coinsStat = home:Stat({ Name = "Coins", Value = "—" })
local levelStat = home:Stat({ Name = "Level", Value = "—" })

task.spawn(function()
    while true do
        task.wait(1)
        local coins = cd("Coins")
        local level = cd("Level")
        pcall(function()
            coinsStat:Set(coins and tostring(coins) or "—")
            levelStat:Set(level and tostring(level) or "—")
        end)
    end
end)

----------------------------------------------------------------
-- PACKS
----------------------------------------------------------------
local packs = tab.Packs
packs:Section("Open packs")
packs:Dropdown({
    Name = "Pack type",
    Options = { "Artist", "Limited", "Genre", "Standard", "Starter" },
    Default = "Artist",
    Flag = "pack_type",
    Callback = function(v)
        S.packType = v
    end,
})
packs:TextBox({
    Name = "Pack / Artist ID",
    Placeholder = "artist id or limited id…",
    Flag = "pack_id",
    Callback = function(t)
        S.packId = t
    end,
})
packs:Slider({
    Name = "Count",
    Min = 1,
    Max = 10,
    Step = 1,
    Default = 1,
    Flag = "pack_count",
    Callback = function(v)
        S.packCount = v
    end,
})
packs:Toggle({
    Name = "Skip open animation (server flag)",
    Flag = "skip_anim",
    Default = true,
    Callback = function(v)
        S.skipAnim = v
    end,
})
packs:Button({
    Name = "Open Pack",
    Callback = function()
        openPack()
    end,
})
packs:Paragraph("Artist/Limited need an ID from the in-game pack UI. Gift-style packs use type name + empty ID.")

----------------------------------------------------------------
-- SELL
----------------------------------------------------------------
local sell = tab.Sell
sell:Section("Quick Sell rarities")
for _, r in ipairs(RARITIES) do
    sell:Toggle({
        Name = "Sell " .. r,
        Flag = "sell_" .. r,
        Default = S.sellRarities[r] == true,
        Callback = function(v)
            S.sellRarities[r] = v
        end,
    })
end
sell:Toggle({
    Name = "Keep one of each",
    Flag = "keep_one",
    Default = true,
    Callback = function(v)
        S.keepOne = v
    end,
})
sell:Toggle({
    Name = "Skip favorites",
    Flag = "skip_fav",
    Default = true,
    Callback = function(v)
        S.skipFavorites = v
    end,
})
sell:Button({
    Name = "Quick Sell now",
    Tone = "danger",
    Callback = function()
        ui:Prompt({
            Title = "Quick Sell?",
            Text = "Sells selected rarities on the server.",
            Yes = "Sell",
            Tone = "danger",
            Callback = function(yes)
                if yes then
                    quickSell()
                end
            end,
        })
    end,
})

----------------------------------------------------------------
-- FUSE
----------------------------------------------------------------
local fuse = tab.Fuse
fuse:Section("Fuse")
fuse:Button({
    Name = "AutoFuseNow",
    Callback = function()
        autoFuseNow()
    end,
})
fuse:Paragraph("Uses AutoFuseNow remote (same as game auto-fuse). Enable Auto Fuse on Home for a loop.")

----------------------------------------------------------------
-- STATS
----------------------------------------------------------------
local stats = tab.Stats
stats:Section("Collection")
local statsPara = stats:Paragraph("Press refresh to read ClientData cards.")
stats:Button({
    Name = "Refresh stats",
    Callback = function()
        local counts, total = collectionStats()
        local lines = { "Total: " .. tostring(total) }
        for _, r in ipairs(RARITIES) do
            lines[#lines + 1] = r .. ": " .. tostring(counts[r] or 0)
        end
        local coins = cd("Coins")
        local level = cd("Level")
        lines[#lines + 1] = "Coins: " .. tostring(coins or "?")
        lines[#lines + 1] = "Level: " .. tostring(level or "?")
        local text = table.concat(lines, "\n")
        pcall(function()
            statsPara:Set(text)
        end)
        pcall(function()
            if statsPara.SetText then
                statsPara:SetText(text)
            end
        end)
        toast("Stats", "Total cards ~" .. total, "accent")
    end,
})

local logPara = stats:Paragraph("Log empty")
stats:Button({
    Name = "Refresh log",
    Callback = function()
        local t = #S.log > 0 and table.concat(S.log, "\n") or "Log empty"
        pcall(function()
            logPara:Set(t)
        end)
        pcall(function()
            if logPara.SetText then
                logPara:SetText(t)
            end
        end)
    end,
})

----------------------------------------------------------------
-- ALERTS
----------------------------------------------------------------
local al = tab.Alerts
al:Section("Notifications")
al:Toggle({
    Name = "Alert Unique pulls",
    Flag = "alert_unique",
    Default = true,
    Callback = function(v)
        S.notifyUnique = v
    end,
})
al:Toggle({
    Name = "Alert Diamond pulls",
    Flag = "alert_diamond",
    Default = true,
    Callback = function(v)
        S.notifyDiamond = v
    end,
})
al:Toggle({
    Name = "Alert trade events",
    Flag = "alert_trade",
    Default = true,
    Callback = function(v)
        S.notifyTrade = v
    end,
})
al:Button({
    Name = "Test notify",
    Callback = function()
        toast("Test", "Notifications work", "accent")
    end,
})

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
ui:Settings({ Panel = tab.Settings })
tab.Settings:Separator()
tab.Settings:Section("Profiles")
ui:Profiles({ Panel = tab.Settings })
tab.Settings:Separator()
tab.Settings:Button({
    Name = "Unload",
    Tone = "danger",
    Callback = function()
        S.autoIncome = false
        S.autoFuse = false
        S.autoDaily = false
        ui:Destroy()
    end,
})

ui:OnDestroy(function()
    S.autoIncome = false
    S.autoFuse = false
    S.autoDaily = false
end)

ui:Show()
ui:Notify({
    Title = "SHUFFLED Hub",
    Text = "RightShift to hide · Collect / Packs / Sell / Fuse ready",
    Tone = "accent",
})
print("[Shuffled Hub] LiteUI loaded")
