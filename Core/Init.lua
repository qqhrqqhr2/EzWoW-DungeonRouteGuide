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

function ns.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffea837e[EzWoW - Dungeon Route Guide]|r " .. tostring(msg))
    end
end

function ns.FormatEnabledStateLabel(v)
    return v and ("|cff55ff55" .. ns.L.ON .. "|r") or ("|cffff5555" .. ns.L.OFF .. "|r")
end

function ns.InCombat()
    return ns.IsTruthySafeValue(ns.UnwrapSafeValue(InCombatLockdown))
end

ns.itemMissing, ns.itemAsked = {}, {}
local ITEM_WAIT = 12   

function ns.ItemState(entityID)
    local displayName = ns.ItemInfo(entityID)
    if displayName then ns.itemMissing[entityID] = nil; return "ok" end   
    if ns.itemMissing[entityID] then return "missing" end
    
    local exists = ns.UnwrapSafeValue(C_Item and C_Item.DoesItemExistByID, entityID)
    if ns.IsReadableValue(exists) and exists == false then ns.itemMissing[entityID] = true; return "missing" end
    local currentTime = ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetTime)) or 0
    local asked = ns.itemAsked[entityID]
    if not asked then ns.itemAsked[entityID] = currentTime
    elseif currentTime - asked > ITEM_WAIT then ns.itemMissing[entityID] = true; return "missing" end
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
    return ns.CoerceSafeString(displayName), ns.CoerceSafeString(link), ns.CoerceSafeNumber(quality), iconTex
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
