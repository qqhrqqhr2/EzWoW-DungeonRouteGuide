--===========================================================================
-- EzWoW - Dungeon Route Guide
-- Core/Init.lua : Safe Value Guards, GUID Parsers & Item Query Helpers
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CoreUtilities = ns.CoreUtilities or {}
ns.CoreUtilities = CoreUtilities

function CoreUtilities.pass(ok, ...)
    if ok then return ... end
end

function ns.UnwrapSafeValue(fn, ...)
    if type(fn) ~= "function" then return end
    return CoreUtilities.pass(pcall(fn, ...))
end

function ns.IsReadableValue(v)
    if v == nil then return false end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return false end
    end
    if canaccessvalue then
        local ok, can = pcall(canaccessvalue, v)
        if not ok or not can then return false end
    end
    return true
end

function ns.CoerceSafeString(v)
    if ns.IsReadableValue(v) and type(v) == "string" then return v end
end

function ns.CoerceSafeNumber(v)
    if ns.IsReadableValue(v) and type(v) == "number" and v == v then return v end
end

function ns.IsTruthySafeValue(v)
    return ns.IsReadableValue(v) and v == true
end

function ns.NpcIDFromGUID(guid)
    guid = ns.CoerceSafeString(guid)
    if not guid then return end
    local kind, entityID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(entityID) end
end

function ns.InstanceUIDFromGUID(guid)
    guid = ns.CoerceSafeString(guid)
    if not guid then return end
    local kind, zone = guid:match("^(%a+)%-%d+%-%d+%-%d+%-(%d+)%-%d+")
    if kind == "Creature" or kind == "Vehicle" then return zone end
end

function ns.UnitNpcID(unit)
    return ns.NpcIDFromGUID(ns.UnwrapSafeValue(UnitGUID, unit))
end

function ns.Normalize(s)
    s = ns.CoerceSafeString(s)
    if not s then return end
    return (s:lower():gsub("[%s%p]", ""))
end

-- Printing to chat in combat can taint the chat history, so lines written in
-- combat are held (up to MAX_HELD) and printed when combat ends.
local heldLines, MAX_HELD = {}, 20

local function writeLine(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffea837e[EzWoW - Dungeon Route Guide]|r " .. text)
    end
end

function ns.Print(msg)
    local text = ns.IsReadableValue(msg) and tostring(msg) or "?"
    if ns.IsTruthySafeValue(ns.UnwrapSafeValue(InCombatLockdown)) then
        if #heldLines < MAX_HELD then heldLines[#heldLines + 1] = text end
        return
    end
    writeLine(text)
end

local printFlush = CreateFrame("Frame")
pcall(printFlush.RegisterEvent, printFlush, "PLAYER_REGEN_ENABLED")
printFlush:SetScript("OnEvent", function()
    if #heldLines == 0 then return end
    local lines = heldLines
    heldLines = {}
    for _, text in ipairs(lines) do writeLine(text) end
end)

function ns.FormatEnabledStateLabel(v)
    return v and ("|cff55ff55" .. ns.L.ON .. "|r") or ("|cffff5555" .. ns.L.OFF .. "|r")
end

function ns.InCombat()
    return ns.IsTruthySafeValue(ns.UnwrapSafeValue(InCombatLockdown))
end

ns.itemMissing, ns.itemAsked, ns.itemFallback = {}, {}, {}
local ITEM_WAIT = 12   

-----------------------------------------------------------------------------
-- Shared data (EzWoW-Data, optional)
-- When EzWoW-Data is installed and its table format matches, the dungeon rows (bosses, kill
-- order, loot, quests) and the loot names (name, quality, icon) come from its Dungeons
-- module; until it is loaded (never during combat; EzWoW_Data.Load waits for the combat to
-- end) and whenever it is missing, the bundled Data/DungeonData.lua rows and
-- Data/LootNames.lua are used. The shared rows are merged into this addon's own dungeon
-- tables, which keep their identity and the parts that stay here (step tips and sources,
-- dungeon notes, map geometry). Shared values are used as they are; a step's name table is
-- copied only when a name learned in game is written into it (ns.OwnStepName). The shared
-- tables are only read, never changed.
-----------------------------------------------------------------------------
local SHARED_FORMAT = 2
-- data fields a shared row may leave out (cleared here too when it does)
local DUNGEON_OPTIONAL = { "quests", "trash", "trashGroups", "subzones", "resetNames" }
local STEP_FIELDS = { "id", "n", "kind", "npc", "model", "name", "loot", "quest", "quests", "optional",
    "unconfirmed", "outside", "aliases", "group", "faction" }

local function sharedAPI()
    local D = _G.EzWoW_Data
    if type(D) == "table" and D.formatVersion == SHARED_FORMAT and type(D.Load) == "function"
        and type(D.Peek) == "function" then
        return D
    end
    return nil
end

-- step name tables that still belong to the shared rows (weak keys)
local sharedStepNames = setmetatable({}, { __mode = "k" })

-- Before a learned name is written into a step's name table: copy it if it is a shared one.
function ns.OwnStepName(step)
    local t = step and step.name
    if type(t) ~= "table" or not sharedStepNames[t] then return end
    local o = {}
    for lang, text in pairs(t) do o[lang] = text end
    step.name = o
end

-- Builds everything first and only then writes into d, so a bad row leaves d as it was.
local function mergeDungeon(d, sd)
    local fields = {}
    for k, v in pairs(sd) do
        if k ~= "steps" and k ~= "notes" and k ~= "key" then fields[k] = v end
    end
    local own = {}
    for _, s in ipairs(d.steps or {}) do
        if s.id then own[s.id] = s end
    end
    local steps = {}
    for i, ss in ipairs(sd.steps) do
        if type(ss) ~= "table" or ss.id == nil then return false end
        local row = {}
        for k, v in pairs(ss) do
            if k ~= "tip" and k ~= "from" then row[k] = v end
        end
        steps[i] = { own[ss.id] or {}, row }
    end
    if #steps == 0 then return false end
    -- write
    for k, v in pairs(fields) do d[k] = v end
    for _, k in ipairs(DUNGEON_OPTIONAL) do
        if fields[k] == nil then d[k] = nil end
    end
    d.steps = d.steps or {}
    for i = #d.steps, 1, -1 do d.steps[i] = nil end
    for i, pair in ipairs(steps) do
        local s, row = pair[1], pair[2]
        for _, k in ipairs(STEP_FIELDS) do s[k] = nil end
        for k, v in pairs(row) do s[k] = v end
        if type(s.name) == "table" then sharedStepNames[s.name] = true end
        -- same rule as Data/MinimapData.lua: a step without a map spot is unconfirmed
        if d.bliz and s.kind ~= "fork" and not s.outside then
            local p = d.bliz.steps and d.bliz.steps[s.id]
            s.unconfirmed = not (p and p.pos) or nil
        end
        d.steps[i] = s
    end
    d._npcStepIndex, d._nameStepIndex, d.flowGeo = nil, nil, nil
    return true
end

local function useSharedDungeons(D)
    local m = D.Peek("Dungeons")
    if type(m) ~= "table" or m.formatVersion ~= SHARED_FORMAT then return end
    local list, loot = m.list, m.loot
    if type(list) ~= "table" or not ns.Dungeons then return end
    -- loot names, quality and icons (same shape as Data/LootNames.lua)
    if type(loot) == "table" and next(loot) ~= nil then ns.LootNames = loot end
    local byKey = {}
    for _, sd in ipairs(list) do
        if type(sd) == "table" and sd.key and type(sd.steps) == "table" then byKey[sd.key] = sd end
    end
    -- only dungeons this addon has a map for; the others keep their bundled rows
    local changed = false
    for _, d in ipairs(ns.Dungeons) do
        local sd = byKey[d.key]
        if sd then
            local ok, merged = pcall(mergeDungeon, d, sd)
            changed = changed or (ok and merged)
        end
    end
    if not changed then return end
    ns.usingSharedDungeons = true
    -- names learned in game are kept over the data (same as at login)
    local tracker = ns.DungeonProgressTracker
    if ns.db and tracker and tracker.commitLearnedNames then pcall(tracker.commitLearnedNames) end
    if ns.ready and ns.RefreshAll then pcall(ns.RefreshAll) end
end

-- called once the addon is loaded (out of combat, or the load waits for the combat to end)
function ns.LoadSharedData()
    local D = sharedAPI()
    if not D then return end
    pcall(D.Load, "Dungeons", function(_, ok) if ok then useSharedDungeons(D) end end)
end

-- { koKR name, enUS name, quality, icon } of a route guide drop, or nil (shape of Data/LootNames.lua)
function ns.GetLootFallback(entityID)
    if entityID == nil then return nil end
    return ns.LootNames and ns.LootNames[entityID]
end

-- The server sends an item's data only after someone has found it, so a real drop can stay unknown to the client.
-- Such items fall back to the names shipped in Data/LootNames.lua (or EzWoW-Data) instead of showing as missing.
local function useFallback(entityID)
    if ns.GetLootFallback(entityID) then ns.itemFallback[entityID] = true; ns.itemMissing[entityID] = nil; return true end
    return false
end

function ns.ItemState(entityID)
    local displayName = ns.ItemInfo(entityID)
    if displayName then ns.itemMissing[entityID] = nil; return "ok" end   
    if ns.itemMissing[entityID] then return useFallback(entityID) and "ok" or "missing" end
    
    local exists = ns.UnwrapSafeValue(C_Item and C_Item.DoesItemExistByID, entityID)
    if ns.IsReadableValue(exists) and exists == false then
        if useFallback(entityID) then return "ok" end
        ns.itemMissing[entityID] = true; return "missing"
    end
    local currentTime = ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetTime)) or 0
    local asked = ns.itemAsked[entityID]
    if not asked then ns.itemAsked[entityID] = currentTime
    elseif currentTime - asked > ITEM_WAIT then
        if useFallback(entityID) then return "ok" end
        ns.itemMissing[entityID] = true; return "missing"
    end
    return "loading"
end

function ns.ItemProgress(ids)
    local settled, missing = 0, 0
    for _, entityID in ipairs(ids or {}) do
        local stateEntry = ns.ItemState(entityID)
        if stateEntry ~= "loading" then settled = settled + 1 end
        if stateEntry == "missing" then missing = missing + 1 end
    end
    return settled, #(ids or {}), missing
end

function ns.ItemInfo(entityID)
    local resolveInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local displayName, link, quality, _, _, _, _, _, _, iconTex = ns.UnwrapSafeValue(resolveInfo, entityID)
    if not iconTex then iconTex = ns.UnwrapSafeValue((C_Item and C_Item.GetItemIconByID) or GetItemIcon, entityID) end
    if not ns.CoerceSafeString(displayName) then
        ns.UnwrapSafeValue(C_Item and C_Item.RequestLoadItemDataByID, entityID)

        displayName = ns.UnwrapSafeValue(C_Item and C_Item.GetItemNameByID, entityID)
        quality = quality or ns.UnwrapSafeValue(C_Item and C_Item.GetItemQualityByID, entityID)
    end
    if not ns.IsReadableValue(iconTex) or (type(iconTex) ~= "number" and type(iconTex) ~= "string") then iconTex = nil end
    displayName = ns.CoerceSafeString(displayName)
    if displayName then
        ns.itemFallback[entityID] = nil
    elseif ns.itemFallback[entityID] then
        local f = ns.GetLootFallback(entityID)     -- { ko, en, quality, icon }
        local loc = GetLocale and GetLocale()
        return (loc == "koKR" and f[1] ~= "" and f[1]) or f[2], nil, f[3], iconTex or f[4]
    end
    return displayName, ns.CoerceSafeString(link), ns.CoerceSafeNumber(quality), iconTex
end

function ns.QualityHex(q)
    local themeColor = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if themeColor and themeColor.hex then return themeColor.hex end
    return "|cffffffff"
end

function ns.FirstSentence(s)
    if type(s) ~= "string" then return "" end
    local first = s:match("^(.-[%.!?])%s") or s
    return first
end

function ns.QuestTitle(q)
    if ns.locale == "ko" then
        local titleStr = ns.CoerceSafeString(ns.UnwrapSafeValue(C_QuestLog and C_QuestLog.GetTitleForQuestID, q.id))
        if titleStr and titleStr:find("[\234-\237][\128-\191][\128-\191]") then return titleStr end
    end
    return ns.GetLocalizedText(q.name)
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreUtilities.CoerceSafeNumber = ns.CoerceSafeNumber
CoreUtilities.FormatEnabledStateLabel = ns.FormatEnabledStateLabel
CoreUtilities.IsReadableValue = ns.IsReadableValue
CoreUtilities.UnwrapSafeValue = ns.UnwrapSafeValue
CoreUtilities.CoerceSafeString = ns.CoerceSafeString
CoreUtilities.IsTruthySafeValue = ns.IsTruthySafeValue
