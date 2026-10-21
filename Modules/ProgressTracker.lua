--===========================================================================
-- EzWoW - Dungeon Route Guide
-- Modules/ProgressTracker.lua : Live Boss/Step Progress Tracker & Combat Event Engine
--===========================================================================
local ADDON, ns = ...

local DungeonProgressTracker = ns.DungeonProgressTracker or {}
ns.DungeonProgressTracker = DungeonProgressTracker
local L, translationHelper = ns.L, ns.GetLocalizedText

ns.state = {
    current = nil,    
    viewed = nil,     
    selected = nil,   
    targetStep = nil, 
    rareSeen = {},
    edit = false,
    inCombat = false,
}
local unitState = ns.state
local usePreview 

ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

local DEFAULTS = {
    alpha = 0.9, combatFade = true, combatAlpha = 0.35,
    mapSize = 380, showList = true, listTab = "route",
    locked = false, autoOpen = true, hud = true, rareAlert = true, showIcon = true, lang = "auto",
    worldMapPins = true,
    worldMapLabels = true, worldMapLevels = true, worldMapAutoAlign = true,
    mapStyle = "blizzard",
    routes = {}, entrances = {}, frames = {}, names = {}, floorAreas = {},
}

function DungeonProgressTracker.commitDefaults(db, defaults)
    for entryKey, entryValue in pairs(defaults) do
        if db[entryKey] == nil then
            if type(entryValue) == "table" then db[entryKey] = {}; DungeonProgressTracker.commitDefaults(db[entryKey], entryValue) else db[entryKey] = entryValue end
        elseif type(entryValue) == "table" and type(db[entryKey]) == "table" then
            DungeonProgressTracker.commitDefaults(db[entryKey], entryValue)
        end
    end
end

-----------------------------------------------------------------------------
-- Resolve Client Lang
-----------------------------------------------------------------------------
function DungeonProgressTracker.resolveClientLang()
    local leftPos = ns.CoerceSafeString(ns.UnwrapSafeValue(GetLocale))
    if leftPos == "koKR" then return "ko" end
    if leftPos and leftPos:find("^en") then return "en" end
    if leftPos == "deDE" then return "de" end
    if leftPos == "frFR" then return "fr" end
    if leftPos == "esES" or leftPos == "esMX" then return "es" end
    if leftPos == "ruRU" then return "ru" end
    if leftPos == "zhCN" then return "zhCN" end
    if leftPos == "zhTW" then return "zhTW" end
end

function DungeonProgressTracker.commitName(npc, lang, name)
    for _, dataEntry in ipairs(ns.Dungeons) do
        for _, stateFlag in ipairs(dataEntry.steps) do
            if stateFlag.npc and stateFlag.npc[1] == npc and not stateFlag.group then stateFlag.name[lang] = name end
        end
    end
end

function ns.LearnName(unit)
    local npc = ns.UnitNpcID(unit)
    local name = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitName, unit))
    local lang = DungeonProgressTracker.resolveClientLang()
    if not npc or not name or name == "" or not lang then return end
    local lookupKey = lang .. ":" .. npc
    if ns.db.names[lookupKey] == name then return end
    local known = false
    for _, dataEntry in ipairs(ns.Dungeons) do
        for _, stateFlag in ipairs(dataEntry.steps) do if stateFlag.npc and stateFlag.npc[1] == npc and not stateFlag.group then known = true end end
    end
    if not known then return end
    ns.db.names[lookupKey] = name
    DungeonProgressTracker.commitName(npc, lang, name)
end

function DungeonProgressTracker.commitLearnedNames()
    for lookupKey, name in pairs(ns.db.names) do
        local lang, npc = lookupKey:match("^(%a+):(%d+)$")
        if lang and type(name) == "string" then DungeonProgressTracker.commitName(tonumber(npc), lang, name) end
    end
end

function ns.InitDB()
    if type(EzWoW_DungeonRouteGuideDB) ~= "table" then
        if type(EzWoW_DungeonRouteGuideDB) == "table" then
            EzWoW_DungeonRouteGuideDB = EzWoW_DungeonRouteGuideDB
        else
            EzWoW_DungeonRouteGuideDB = {}
        end
    end
    EzWoW_DungeonRouteGuideDB = EzWoW_DungeonRouteGuideDB
    DungeonProgressTracker.commitDefaults(EzWoW_DungeonRouteGuideDB, DEFAULTS)

    if type(EzWoW_DungeonRouteGuideCharDB) ~= "table" then
        if type(EzWoW_DungeonRouteGuideCharDB) == "table" then
            EzWoW_DungeonRouteGuideCharDB = EzWoW_DungeonRouteGuideCharDB
        else
            EzWoW_DungeonRouteGuideCharDB = {}
        end
    end
    EzWoW_DungeonRouteGuideCharDB = EzWoW_DungeonRouteGuideCharDB
    EzWoW_DungeonRouteGuideCharDB.progress = EzWoW_DungeonRouteGuideCharDB.progress or { done = {}, lastSeen = 0 }
    ns.db = EzWoW_DungeonRouteGuideDB
    ns.db.worldMapHidden = nil 
    ns.db.mapStyle = "blizzard" 
    ns.char = EzWoW_DungeonRouteGuideCharDB
    ns.SetLanguage(ns.db.lang)
    DungeonProgressTracker.commitLearnedNames()
    for _, recordItem in ipairs(ns.db.mapscan or {}) do usePreview(recordItem) end
end

-----------------------------------------------------------------------------
-- Get Active Route Edits
-----------------------------------------------------------------------------
function DungeonProgressTracker.getActiveRouteEdits(dataEntry, step, create)
    local routeKey = dataEntry.key .. (dataEntry.editSpace or "")
    local rowEntry = ns.db.routes[routeKey]
    if not rowEntry and create then rowEntry = {}; ns.db.routes[routeKey] = rowEntry end
    if not rowEntry then return end
    local recordEntry = rowEntry[step.id]
    if not recordEntry and create then recordEntry = {}; rowEntry[step.id] = recordEntry end
    return recordEntry
end
ns.GetDungeonManualRouteEdits = DungeonProgressTracker.getActiveRouteEdits

function ns.ResolveRouteStepCoordinates(dataEntry, i)
    local step = dataEntry.steps[i]
    local recordEntry = DungeonProgressTracker.getActiveRouteEdits(dataEntry, step)
    return (recordEntry and recordEntry.pos) or step.pos
end

function ns.IsPrimaryRouteStep(step)
    return not step.optional and step.kind ~= "fork" and ns.IsRouteStepVisibleOnFloor(step)
end

function ns.IsBossEncounterStep(step)
    return step.kind == "boss" and not step.optional and ns.IsRouteStepVisibleOnFloor(step)
end

function ns.IsRouteStepVisibleOnFloor(step)
    if not step.faction then return true end
    local windowFrame = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitFactionGroup, "player"))
    return not windowFrame or windowFrame == step.faction
end

function ns.ResolveRouteStepFloorSegment(dataEntry, i)
    local step = dataEntry.steps[i]
    if not ns.IsPrimaryRouteStep(step) or not step.pos then return nil end
    local origin = step.from
    if not origin then
        for subIndex = i - 1, 1, -1 do
            local stateFlag = dataEntry.steps[subIndex]
            if ns.IsPrimaryRouteStep(stateFlag) and stateFlag.pos then
                if stateFlag.page == step.page then origin = ns.ResolveRouteStepCoordinates(dataEntry, subIndex) end
                break
            end
        end
    end
    if not origin and dataEntry.start and dataEntry.start.page == step.page then
        local first = true
        for subIndex = 1, i - 1 do
            local stateFlag = dataEntry.steps[subIndex]
            if ns.IsPrimaryRouteStep(stateFlag) and stateFlag.pos then first = false; break end
        end
        if first then origin = dataEntry.start.pos end
    end
    if not origin then return nil end
    local recordEntry = DungeonProgressTracker.getActiveRouteEdits(dataEntry, step)
    local path = (recordEntry and recordEntry.path) or step.path or {}
    local pts = { origin }
    for _, anchorTarget in ipairs(path) do pts[#pts + 1] = anchorTarget end
    pts[#pts + 1] = ns.ResolveRouteStepCoordinates(dataEntry, i)
    return pts
end

-----------------------------------------------------------------------------
-- Resolve Progress
-----------------------------------------------------------------------------
function DungeonProgressTracker.resolveProgress(dataEntry)
    local anchorTarget = ns.char.progress
    if anchorTarget.key ~= dataEntry.key then
        anchorTarget.key = dataEntry.key; anchorTarget.done = {}; anchorTarget.history = {}; anchorTarget.lastSeen = time()
    end
    return anchorTarget
end

function ns.IsRouteStepCompleted(dataEntry, i)
    local anchorTarget = ns.char.progress
    return anchorTarget.key == dataEntry.key and anchorTarget.done[dataEntry.steps[i].id] == true
end

function ns.ComputeDungeonProgressCounts(dataEntry)
    local grandTotal, done = 0, 0
    for i, step in ipairs(dataEntry.steps) do
        if ns.IsBossEncounterStep(step) then
            grandTotal = grandTotal + 1
            if ns.IsRouteStepCompleted(dataEntry, i) then done = done + 1 end
        end
    end
    return done, grandTotal
end

local KIND_ICON = {
    npc    = "Interface\\GossipFrame\\GossipGossipIcon",
    rare   = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    object = "Interface\\GossipFrame\\AvailableQuestIcon",
    task   = "Interface\\GossipFrame\\AvailableQuestIcon",
}
function ns.ResolveStepCategoryIcon(step) return KIND_ICON[step.kind] end

function ns.ResolveBossEncounterOrderIndex(dataEntry, i)
    if dataEntry.steps[i].kind ~= "boss" then return nil end
    local nodeEntry = 0
    for subIndex = 1, i do
        local stateFlag = dataEntry.steps[subIndex]
        if stateFlag.kind == "boss" and ns.IsRouteStepVisibleOnFloor(stateFlag) then nodeEntry = nodeEntry + 1 end
    end
    return nodeEntry
end

function ns.FormatRouteStepBadgeTag(dataEntry, i, size)
    local buttonWidget = ns.ResolveBossEncounterOrderIndex(dataEntry, i)
    if buttonWidget then return tostring(buttonWidget) end
    local icVal = KIND_ICON[dataEntry.steps[i].kind]
    size = size or 14
    return icVal and ("|T" .. icVal .. ":" .. size .. ":" .. size .. "|t") or "-"
end

function ns.ResolveRouteStepDisplayTitle(dataEntry, i)
    local buttonWidget = ns.ResolveBossEncounterOrderIndex(dataEntry, i)
    local name = ns.GetLocalizedText(dataEntry.steps[i].name)
    if buttonWidget then return buttonWidget .. ". " .. name end
    return ns.FormatRouteStepBadgeTag(dataEntry, i) .. " " .. name
end

function DungeonProgressTracker.resolveLastDoneMain(dataEntry)
    local last = 0
    for i, step in ipairs(dataEntry.steps) do
        if ns.IsPrimaryRouteStep(step) and ns.IsRouteStepCompleted(dataEntry, i) then last = i end
    end
    return last
end

function ns.IsRouteStepSkipped(dataEntry, i)
    local step = dataEntry.steps[i]
    return ns.IsPrimaryRouteStep(step) and not ns.IsRouteStepCompleted(dataEntry, i) and i < DungeonProgressTracker.resolveLastDoneMain(dataEntry)
end

function DungeonProgressTracker.resolveSpotOf(dataEntry, i)
    local step = dataEntry.steps[i]
    local greenVal = dataEntry.bliz and dataEntry.bliz.steps and dataEntry.bliz.steps[step.id]
    if greenVal then return greenVal.page, greenVal.pos end
    if step.pos then return step.page, step.pos end
end

function DungeonProgressTracker.resolveHereIndex(dataEntry)
    local anchorTarget = ns.char.progress
    if anchorTarget.key == dataEntry.key and anchorTarget.history then
        for entryKey = #anchorTarget.history, 1, -1 do
            local entityID = anchorTarget.history[entryKey]
            if anchorTarget.done[entityID] then
                for i, stateFlag in ipairs(dataEntry.steps) do
                    if stateFlag.id == entityID and DungeonProgressTracker.resolveSpotOf(dataEntry, i) then return i end
                end
            end
        end
    end
    local last = DungeonProgressTracker.resolveLastDoneMain(dataEntry)
    return last > 0 and last or nil
end

local SKIPPED_WEIGHT = 2.5   
local OTHER_AREA = 1e6       

function ns.ResolveNextIncompleteStep(dataEntry)
    if not dataEntry then return end
    local done, grandTotal = ns.ComputeDungeonProgressCounts(dataEntry)
    if grandTotal > 0 and done >= grandTotal then return end
    local here = DungeonProgressTracker.resolveHereIndex(dataEntry)
    local hpVal, hpos
    if here then hpVal, hpos = DungeonProgressTracker.resolveSpotOf(dataEntry, here) end
    if not hpos then
        for i, step in ipairs(dataEntry.steps) do
            if ns.IsPrimaryRouteStep(step) and not ns.IsRouteStepCompleted(dataEntry, i) then return i end
        end
        return
    end
    local furthest = DungeonProgressTracker.resolveLastDoneMain(dataEntry)
    local best, bestScore
    for i, step in ipairs(dataEntry.steps) do
        if ns.IsPrimaryRouteStep(step) and not ns.IsRouteStepCompleted(dataEntry, i) then
            local pgVal, coordPos = DungeonProgressTracker.resolveSpotOf(dataEntry, i)
            local score
            if coordPos and pgVal == hpVal then
                local dxVal, dyVal = coordPos[1] - hpos[1], coordPos[2] - hpos[2]
                score = math.sqrt(dxVal * dxVal + dyVal * dyVal)
            else
                score = OTHER_AREA + math.abs(i - here)
            end
            if i < furthest then score = score * SKIPPED_WEIGHT end
            if not bestScore or score < bestScore then best, bestScore = i, score end
        end
    end
    return best
end

function ns.SetRouteStepCompleted(dataEntry, i, value, auto)
    local anchorTarget = DungeonProgressTracker.resolveProgress(dataEntry)
    local step = dataEntry.steps[i]
    if (anchorTarget.done[step.id] == true) == (value and true or false) then return end
    anchorTarget.done[step.id] = value and true or nil
    anchorTarget.lastSeen = time()
    if value then
        anchorTarget.history = anchorTarget.history or {}
        anchorTarget.history[#anchorTarget.history + 1] = step.id
    end
    if value then

        
        if step.kind == "boss" then
            for subIndex = i - 1, 1, -1 do
                local stateFlag = dataEntry.steps[subIndex]
                if stateFlag.kind == "boss" then break end
                if stateFlag.kind ~= "rare" and not stateFlag.optional then anchorTarget.done[stateFlag.id] = true end
            end
        end
        if auto then
            if dataEntry == unitState.current and ns.LearnFloor then ns.LearnFloor(dataEntry, i) end
            local done, grandTotal = ns.ComputeDungeonProgressCounts(dataEntry)
            ns.Print(L.KILLED:format(translationHelper(step.name), done, grandTotal))
            if done >= grandTotal then ns.Print("|cff55ff55" .. L.DONE_ALL .. "|r") end
        end
    end
    ns.RefreshAll()
end

function ns.ResetProgress(dataEntry)
    dataEntry = dataEntry or unitState.current or unitState.viewed
    if not dataEntry then return end
    local anchorTarget = ns.char.progress
    anchorTarget.key = dataEntry.key; anchorTarget.done = {}; anchorTarget.history = {}; anchorTarget.zone = nil; anchorTarget.lastSeen = time()
    unitState.rareSeen = {}
    ns.Print(L.RESET_DONE)
    ns.RefreshAll()
end

function ns.CompleteNextRouteStep()
    local dataEntry = unitState.current or unitState.viewed
    local i = ns.ResolveNextIncompleteStep(dataEntry)
    if i then ns.SetRouteStepCompleted(dataEntry, i, true) end
end

function ns.UndoLastCompletedStep()
    local dataEntry = unitState.current or unitState.viewed
    if not dataEntry then return end
    local anchorTarget = ns.char.progress
    if anchorTarget.key == dataEntry.key and anchorTarget.history then
        while #anchorTarget.history > 0 do
            local entityID = table.remove(anchorTarget.history)
            for i, step in ipairs(dataEntry.steps) do
                if step.id == entityID and ns.IsRouteStepCompleted(dataEntry, i) then ns.SetRouteStepCompleted(dataEntry, i, false); return end
            end
        end
    end
    for i = #dataEntry.steps, 1, -1 do
        if ns.IsRouteStepCompleted(dataEntry, i) then ns.SetRouteStepCompleted(dataEntry, i, false); return end
    end
end

-----------------------------------------------------------------------------
-- List Has
-----------------------------------------------------------------------------
function DungeonProgressTracker.listHas(list, value)
    if not list or not value then return false end
    for _, entryValue in ipairs(list) do if entryValue == value then return true end end
    return false
end

function DungeonProgressTracker.nameMatches(dataEntry, name)
    if not name or not dataEntry.nameMatch then return false end
    for _, frag in ipairs(dataEntry.nameMatch) do
        if name:find(frag, 1, true) then return true end
    end
    return false
end

-----------------------------------------------------------------------------
-- Map Scan
-----------------------------------------------------------------------------
usePreview = function(recordItem)
    
end

function ns.MapScan()
    ns.Print(L.FLOW_ONLY)
end

function ns.InstanceInfo()
    local name, itype, _, _, _, _, _, itemIDVal = ns.UnwrapSafeValue(GetInstanceInfo)
    return ns.CoerceSafeString(name), ns.CoerceSafeString(itype), ns.CoerceSafeNumber(itemIDVal)
end

function ns.DungeonCandidates()
    local name, itype, itemIDVal = ns.InstanceInfo()
    if not itype or itype == "none" then return {}, name, nil end
    local byID, byName = {}, {}
    for _, dataEntry in ipairs(ns.Dungeons) do
        if DungeonProgressTracker.listHas(dataEntry.instanceIDs, itemIDVal) then byID[#byID + 1] = dataEntry end
        if DungeonProgressTracker.nameMatches(dataEntry, name) then byName[#byName + 1] = dataEntry end
    end
    return #byID > 0 and byID or byName, name, itemIDVal or name
end

function DungeonProgressTracker.resolveWingFromZone(list, zone)
    zone = ns.Normalize(zone)
    if not zone or zone == "" then return end
    local match
    for _, dataEntry in ipairs(list) do
        local found = false
        for _, text in ipairs(ns.AllLocalizedTexts(dataEntry.name)) do
            if ns.Normalize(text) == zone then found = true; break end
        end
        for _, alias in ipairs(dataEntry.subzones or {}) do
            if ns.Normalize(alias) == zone then found = true; break end
        end
        if found then
            if match then return end 
            match = dataEntry
        end
    end
    return match
end

function ns.DetectDungeon()
    local list, name, scope = ns.DungeonCandidates()
    if unitState.detectInstanceScope ~= scope then
        unitState.detectInstanceScope = scope
        unitState.detectedWing, unitState.wingOverride = nil, nil
    end
    unitState.detectionPending = nil
    if #list <= 1 then return list[1] end
    if unitState.wingOverride and DungeonProgressTracker.listHas(list, unitState.wingOverride) then return unitState.wingOverride end

    for _, api in ipairs({ "GetSubZoneText", "GetMinimapZoneText", "GetZoneText" }) do
        local dataEntry = DungeonProgressTracker.resolveWingFromZone(list, ns.CoerceSafeString(ns.UnwrapSafeValue(_G[api])))
        if dataEntry then unitState.detectedWing = dataEntry; return dataEntry end
    end
    local named
    for _, dataEntry in ipairs(list) do
        if DungeonProgressTracker.nameMatches(dataEntry, name) then
            if named then named = nil; break end
            named = dataEntry
        end
    end
    if named then unitState.detectedWing = named; return named end

    if unitState.detectedWing and DungeonProgressTracker.listHas(list, unitState.detectedWing) then return unitState.detectedWing end
    unitState.detectionPending = list
    return nil
end

function ns.SelectDungeon(dataEntry)
    local list, _, scope = ns.DungeonCandidates()
    unitState.page, unitState.pageManual = nil, false
    if #list > 1 and DungeonProgressTracker.listHas(list, dataEntry) then
        unitState.detectInstanceScope = scope
        unitState.wingOverride = dataEntry
        ns.UpdateLocation()
        unitState.viewed, unitState.selected, unitState.cardTrash = dataEntry, nil, nil
        if ns.ShowMap then ns.ShowMap(dataEntry) end
        ns.Print(L.WING_MANUAL:format(translationHelper(dataEntry.name)))
    else
        unitState.viewed, unitState.selected, unitState.cardTrash = dataEntry, nil, nil
        if ns.ShowMap then ns.ShowMap(dataEntry) end
    end
end

function DungeonProgressTracker.enterDungeon(dataEntry)
    local anchorTarget = ns.char.progress
    local stale = (time() - (anchorTarget.lastSeen or 0)) > 30 * 60
    local finished = false
    if anchorTarget.key == dataEntry.key then
        local done, grandTotal = ns.ComputeDungeonProgressCounts(dataEntry)
        finished = grandTotal > 0 and done >= grandTotal
    end
    if anchorTarget.key ~= dataEntry.key or stale or finished then
        anchorTarget.key = dataEntry.key; anchorTarget.done = {}; anchorTarget.history = {}; anchorTarget.zone = nil
        unitState.rareSeen = {}
        ns.Print(L.NEW_RUN:format(translationHelper(dataEntry.name)))
    end
    anchorTarget.lastSeen = time()
    unitState.current = dataEntry
    unitState.viewed = dataEntry
    unitState.selected = nil
    unitState.targetStep = nil
    unitState.page, unitState.pageManual = nil, false
    unitState.area = nil
    unitState.areaChanged = true
    if ns.StopEntranceIfInside then ns.StopEntranceIfInside() end
    if ns.db.autoOpen and ns.ShowMap then ns.ShowMap(dataEntry, true) end
end

function DungeonProgressTracker.leaveDungeon()
    ns.char.progress.lastSeen = time()
    unitState.current = nil
    unitState.targetStep = nil
    if ns.HideMapIfAuto then ns.HideMapIfAuto() end
end

function DungeonProgressTracker.hasMainDungeonZone(dataEntry, z)
    if not z or z == "" then return true end
    if z == ns.Normalize(ns.CoerceSafeString(ns.UnwrapSafeValue(GetRealZoneText))) then return true end
    if z == ns.Normalize(ns.CoerceSafeString(ns.UnwrapSafeValue(GetZoneText))) then return true end
    local instName = ns.InstanceInfo()
    if z == ns.Normalize(instName) then return true end
    if dataEntry then
        for _, text in ipairs(ns.AllLocalizedTexts(dataEntry.name)) do
            if z == ns.Normalize(text) then return true end
        end
        for _, nmVal in ipairs(dataEntry.nameMatch or {}) do
            if z == ns.Normalize(nmVal) then return true end
        end
    end
    return false
end
ns.IsMainDungeonZone = DungeonProgressTracker.hasMainDungeonZone

function DungeonProgressTracker.refreshArea()
    local z = ns.Normalize(ns.CoerceSafeString(ns.UnwrapSafeValue(GetSubZoneText)))
    if not z or z == "" then z = ns.Normalize(ns.CoerceSafeString(ns.UnwrapSafeValue(GetMinimapZoneText))) end
    if DungeonProgressTracker.hasMainDungeonZone(unitState.current, z) then z = nil end
    if z ~= unitState.area then
        unitState.area = z
        if z then unitState.areaChanged = true end   
    end
end

function ns.UpdateLocation()
    local previousPending = unitState.detectionPending
    local dataEntry = ns.DetectDungeon()
    if dataEntry ~= unitState.current then
        if unitState.current and not dataEntry then DungeonProgressTracker.leaveDungeon()
        elseif dataEntry then DungeonProgressTracker.enterDungeon(dataEntry) end
    end
    if unitState.detectionPending then
        unitState.warnedUnknown = nil
        if not previousPending then
            ns.Print(L.WING_PENDING)
            if ns.db.autoOpen and ns.ShowWingPicker then ns.ShowWingPicker(unitState.detectionPending) end
        end
    elseif not dataEntry then
        if ns.HideWingPicker then ns.HideWingPicker() end
        local _, itype = ns.InstanceInfo()
        if itype == "party" and not unitState.warnedUnknown then
            unitState.warnedUnknown = true
            ns.Print(L.NOT_SUPPORTED)
        end
    else
        if ns.HideWingPicker then ns.HideWingPicker() end
        unitState.warnedUnknown = nil
        DungeonProgressTracker.refreshArea()
    end
    ns.RefreshAll()
end

-----------------------------------------------------------------------------
-- Reset Pattern Entry
-----------------------------------------------------------------------------
local resetPattern
function DungeonProgressTracker.resetPatternEntry()
    if resetPattern ~= nil then return resetPattern end
    resetPattern = false
    local greenVal = ns.CoerceSafeString(INSTANCE_RESET_SUCCESS)
    if greenVal then
        greenVal = greenVal:gsub("|1[^;]*;[^;]*;", "\1")           
        greenVal = greenVal:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        greenVal = greenVal:gsub("%%%%s", "(.+)"):gsub("\1", ".-")
        resetPattern = "^" .. greenVal .. "$"
    end
    return resetPattern
end

function DungeonProgressTracker.resolveDungeonsInText(text)
    local found = {}
    for _, dataEntry in ipairs(ns.Dungeons) do
        local names = ns.AllLocalizedTexts(dataEntry.name)
        for _, nodeEntry in ipairs(dataEntry.resetNames or {}) do names[#names + 1] = nodeEntry end
        for _, nodeEntry in ipairs(names) do
            if nodeEntry and text:find(nodeEntry, 1, true) then found[#found + 1] = dataEntry; break end
        end
    end
    return found
end

function DungeonProgressTracker.onSystemMessage(msg)
    msg = ns.CoerceSafeString(msg)
    if not msg then return end
    local list
    local pat = DungeonProgressTracker.resetPatternEntry()
    if pat then
        local name = msg:match(pat)
        if name then list = DungeonProgressTracker.resolveDungeonsInText(name) end
    elseif msg:find("초기화되었습니다", 1, true) or msg:find("has been reset", 1, true) then
        list = DungeonProgressTracker.resolveDungeonsInText(msg)
    end
    if not list or #list == 0 then return end
    local anchorTarget = ns.char.progress
    for _, dataEntry in ipairs(list) do
        if anchorTarget.key == dataEntry.key then anchorTarget.done = {}; anchorTarget.history = {}; anchorTarget.zone = nil; anchorTarget.lastSeen = 0 end
    end
    ns.Print(L.RESET_SEEN:format(translationHelper(list[1].name)))
    ns.RefreshAll()
end

-----------------------------------------------------------------------------
-- Step By Npc
-----------------------------------------------------------------------------
function DungeonProgressTracker.stepByNpc(dataEntry, npc)
    if not dataEntry or not npc then return end
    local npcMap = dataEntry._npcStepIndex
    if not npcMap then
        npcMap = {}
        for i, step in ipairs(dataEntry.steps) do
            if step.npc then
                for _, entityID in ipairs(step.npc) do
                    if npcMap[entityID] == nil then npcMap[entityID] = i end
                end
            end
        end
        dataEntry._npcStepIndex = npcMap
    end
    local idx = npcMap[npc]
    if idx then return idx, dataEntry.steps[idx] end
end
ns.StepByNpc = DungeonProgressTracker.stepByNpc

function DungeonProgressTracker.stepByName(dataEntry, name)
    local nodeEntry = ns.Normalize(name)
    if not dataEntry or not nodeEntry then return end
    local nameMap = dataEntry._nameStepIndex
    if not nameMap then
        nameMap = {}
        for i, step in ipairs(dataEntry.steps) do
            for _, alias in ipairs(step.aliases or {}) do
                local na = ns.Normalize(alias)
                if na and nameMap[na] == nil then nameMap[na] = i end
            end
            for _, entryValue in pairs(step.name) do
                local nv = ns.Normalize(entryValue)
                if nv and nameMap[nv] == nil then nameMap[nv] = i end
            end
        end
        dataEntry._nameStepIndex = nameMap
    end
    local idx = nameMap[nodeEntry]
    if idx then return idx, dataEntry.steps[idx] end
end

function DungeonProgressTracker.recordBossKillStep(npc, name)
    local dataEntry = unitState.current
    local i, step = DungeonProgressTracker.stepByNpc(dataEntry, npc)
    if not i and name then i, step = DungeonProgressTracker.stepByName(dataEntry, name) end
    if i and (step.kind == "boss" or step.kind == "rare") and not ns.IsRouteStepCompleted(dataEntry, i) then ns.SetRouteStepCompleted(dataEntry, i, true, true) end
end

function DungeonProgressTracker.verifyUnitDeath(unit)
    if not unitState.current then return end
    if not ns.IsTruthySafeValue(ns.UnwrapSafeValue(UnitIsDead, unit)) then return end
    DungeonProgressTracker.recordBossKillStep(ns.UnitNpcID(unit), ns.CoerceSafeString(ns.UnwrapSafeValue(UnitName, unit)))
end

function DungeonProgressTracker.noteInstance(unit)
    local dataEntry = unitState.current
    if not dataEntry then return end
    
    if not ns.IsTruthySafeValue(ns.UnwrapSafeValue(UnitCanAttack, "player", unit)) then return end
    local guid = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitGUID, unit))
    local map = guid and tonumber(guid:match("^%a+%-%d+%-%d+%-(%d+)%-%d+%-"))
    local _, _, itemIDVal = ns.InstanceInfo()
    if not map or not itemIDVal or map ~= itemIDVal then return end
    local zone = ns.InstanceUIDFromGUID(guid)
    if not zone then return end
    local anchorTarget = ns.char.progress
    if anchorTarget.key ~= dataEntry.key then return end
    if anchorTarget.zone and anchorTarget.zone ~= zone then
        local any = false
        for _ in pairs(anchorTarget.done) do any = true; break end
        anchorTarget.done = {}
        anchorTarget.history = {}
        unitState.rareSeen = {}
        if any then ns.Print(L.NEW_INSTANCE) end
        anchorTarget.zone = zone
        ns.RefreshAll()
    else
        anchorTarget.zone = zone
    end
end
ns.NoteInstance = DungeonProgressTracker.noteInstance

local WATCH_UNITS = { target = true, focus = true, mouseover = true }
function DungeonProgressTracker.isNpcTrackedInDungeon(unit)
    unit = ns.CoerceSafeString(unit)
    if not unit then return false end
    return WATCH_UNITS[unit] or unit:find("^nameplate%d") or unit:find("^boss%d")
end

function DungeonProgressTracker.sweepDeaths()
    if not unitState.current then return end
    DungeonProgressTracker.verifyUnitDeath("target"); DungeonProgressTracker.verifyUnitDeath("focus"); DungeonProgressTracker.verifyUnitDeath("mouseover")
    for entryKey = 1, 4 do DungeonProgressTracker.verifyUnitDeath("party" .. entryKey .. "target") end
    for entryKey = 1, 5 do DungeonProgressTracker.verifyUnitDeath("boss" .. entryKey) end
    for entryKey = 1, 40 do DungeonProgressTracker.verifyUnitDeath("nameplate" .. entryKey) end
end
ns.SweepDeaths = DungeonProgressTracker.sweepDeaths

function DungeonProgressTracker.verifyLoot()
    if not unitState.current then return end
    local nodeEntry = ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetNumLootItems))
    if not nodeEntry or nodeEntry < 1 or nodeEntry > 100 then return end
    for slot = 1, nodeEntry do
        local sources = { ns.UnwrapSafeValue(GetLootSourceInfo, slot) }
        for entryKey = 1, #sources, 2 do DungeonProgressTracker.recordBossKillStep(ns.NpcIDFromGUID(sources[entryKey])) end
    end
end

function DungeonProgressTracker.onEncounter(name, success)
    if not unitState.current then return end
    if success ~= nil and ns.CoerceSafeNumber(success) ~= 1 then return end
    local i, step = DungeonProgressTracker.stepByName(unitState.current, name)
    if i and (step.kind == "boss" or step.kind == "rare") and not ns.IsRouteStepCompleted(unitState.current, i) then ns.SetRouteStepCompleted(unitState.current, i, true, true) end
end

-----------------------------------------------------------------------------
-- Resolve Rare Alert
-----------------------------------------------------------------------------
function DungeonProgressTracker.resolveRareAlert(unit)
    if not ns.db.rareAlert or not unitState.current then return end
    local npc = ns.UnitNpcID(unit)
    if not npc or unitState.rareSeen[npc] or ns.IsTruthySafeValue(ns.UnwrapSafeValue(UnitIsDead, unit)) then return end
    local _, step = DungeonProgressTracker.stepByNpc(unitState.current, npc)
    local hasRare = step and step.kind == "rare"
    if not hasRare then
        local themeColor = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitClassification, unit))
        hasRare = (themeColor == "rare" or themeColor == "rareelite") and not ns.IsTruthySafeValue(ns.UnwrapSafeValue(UnitIsDead, unit))
    end
    if not hasRare then return end
    unitState.rareSeen[npc] = true
    local name = step and translationHelper(step.name) or ns.CoerceSafeString(ns.UnwrapSafeValue(UnitName, unit)) or "?"
    local msg = L.RARE_ALERT:format(name)
    ns.Print("|cffff80ff" .. msg .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        ns.UnwrapSafeValue(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    ns.UnwrapSafeValue(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
end

function DungeonProgressTracker.refreshTarget()
    DungeonProgressTracker.noteInstance("target")
    ns.LearnName("target")
    local i = unitState.current and DungeonProgressTracker.stepByNpc(unitState.current, ns.UnitNpcID("target"))
    if not i and unitState.current then i = DungeonProgressTracker.stepByName(unitState.current, ns.CoerceSafeString(ns.UnwrapSafeValue(UnitName, "target"))) end
    local changed = unitState.targetStep ~= i
    unitState.targetStep = i
    DungeonProgressTracker.verifyUnitDeath("target")
    if ns.RefreshHUD then ns.RefreshHUD() end
    if changed and i and ns.RefreshMap then ns.RefreshMap() end   
end

-----------------------------------------------------------------------------
-- Broadcast Current Step To Chat
-----------------------------------------------------------------------------
function ns.BroadcastCurrentStepToChat()
    local dataEntry = unitState.current or unitState.viewed
    if not dataEntry then return end
    local i = unitState.targetStep
    if not i or unitState.current ~= dataEntry or ns.IsRouteStepCompleted(dataEntry, i) then i = ns.ResolveNextIncompleteStep(dataEntry) end
    if not i then return end
    local step = dataEntry.steps[i]
    local buttonWidget = ns.ResolveBossEncounterOrderIndex(dataEntry, i)
    local msg = ("[%s] %s%s: %s"):format(L.TITLE, buttonWidget and (buttonWidget .. " ") or "", translationHelper(step.name), ns.FirstSentence(translationHelper(step.tip)))
    if #msg > 250 then msg = msg:sub(1, 247) .. "..." end
    local inInstanceGroup = LE_PARTY_CATEGORY_INSTANCE and ns.IsTruthySafeValue(ns.UnwrapSafeValue(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
    local channel = inInstanceGroup and "INSTANCE_CHAT" or (ns.IsTruthySafeValue(ns.UnwrapSafeValue(IsInGroup)) and "PARTY") or nil
    if not channel then ns.Print(msg); return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local isCallOk = pcall(send, msg, channel)
    if not isCallOk then ns.Print(msg) end
end

-----------------------------------------------------------------------------
-- Change Language
-----------------------------------------------------------------------------

function ns.ChangeLanguage(want)
    if not want then
        local order = {
            auto = "ko", ko = "en", en = "de", de = "fr",
            fr = "es", es = "ru", ru = "zhCN", zhCN = "zhTW", zhTW = "auto",
        }
        want = order[ns.db.lang or "auto"] or "auto"
    end
    ns.db.lang = want
    ns.SetLanguage(want)
    ns.Print(L.OPT_LANG:format(L["LANG_" .. want]))
end

function ns.RefreshAll()
    if ns.RefreshMap then ns.RefreshMap() end
    if ns.RefreshHUD then ns.RefreshHUD() end
    if ns.RefreshWorldMap then ns.RefreshWorldMap() end
end

local eventFrame = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "PLAYER_TARGET_CHANGED", "UNIT_HEALTH", "NAME_PLATE_UNIT_ADDED",
    "LOOT_OPENED", "ENCOUNTER_END", "BOSS_KILL", "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET", "CHAT_MSG_SYSTEM", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
}
for _, recordEntry in ipairs(EVENTS) do pcall(eventFrame.RegisterEvent, eventFrame, recordEntry) end

local EVENT_DISPATCH_TABLE = {}
EVENT_DISPATCH_TABLE.ADDON_LOADED = function(name)
    if name == ADDON then ns.InitDB() end
    if name == "Blizzard_WorldMap" and ns.InitWorldMap then ns.InitWorldMap() end
end
EVENT_DISPATCH_TABLE.PLAYER_LOGIN = function()
    if not ns.db then ns.InitDB() end
    ns.ready = true
    
    if ns.CreateIcon then pcall(ns.CreateIcon) end
    if ns.InitWorldMap then pcall(ns.InitWorldMap) end
    if ns.RegisterOptionsPanel then pcall(ns.RegisterOptionsPanel) end
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(30, function()
            if unitState.current then ns.char.progress.lastSeen = time() end
        end)
    end
end
EVENT_DISPATCH_TABLE.PLAYER_LOGOUT = function()
    if unitState.current and ns.char then ns.char.progress.lastSeen = time() end
end
EVENT_DISPATCH_TABLE.PLAYER_ENTERING_WORLD = function()
    unitState.detectedWing, unitState.wingOverride, unitState.detectInstanceScope = nil, nil, nil
    ns.UpdateLocation()

    if C_Timer and C_Timer.After then
        for _, delay in ipairs({ 0.25, 1, 2 }) do C_Timer.After(delay, ns.UpdateLocation) end
    end
end
EVENT_DISPATCH_TABLE.ZONE_CHANGED_NEW_AREA = function() ns.UpdateLocation() end
EVENT_DISPATCH_TABLE.ZONE_CHANGED = function() ns.UpdateLocation() end
EVENT_DISPATCH_TABLE.ZONE_CHANGED_INDOORS = EVENT_DISPATCH_TABLE.ZONE_CHANGED
EVENT_DISPATCH_TABLE.PLAYER_TARGET_CHANGED = DungeonProgressTracker.refreshTarget
EVENT_DISPATCH_TABLE.UNIT_HEALTH = function(unit) if unitState.current and DungeonProgressTracker.isNpcTrackedInDungeon(unit) then DungeonProgressTracker.verifyUnitDeath(unit) end end
EVENT_DISPATCH_TABLE.NAME_PLATE_UNIT_ADDED = function(unit) DungeonProgressTracker.noteInstance(unit); DungeonProgressTracker.resolveRareAlert(unit); DungeonProgressTracker.verifyUnitDeath(unit) end
EVENT_DISPATCH_TABLE.LOOT_OPENED = DungeonProgressTracker.verifyLoot
local itemRefreshQueued = false
EVENT_DISPATCH_TABLE.GET_ITEM_INFO_RECEIVED = function(itemID, success)
    local entityID = ns.CoerceSafeNumber(itemID)
    if entityID and success == false then ns.itemMissing[entityID] = true end
    if itemRefreshQueued or not (C_Timer and C_Timer.After) then return end
    itemRefreshQueued = true
    C_Timer.After(0.3, function() itemRefreshQueued = false; if ns.RefreshMap then ns.RefreshMap() end end)
end
local questRefreshQueued = false
EVENT_DISPATCH_TABLE.QUEST_LOG_UPDATE = function()
    if questRefreshQueued then return end
    if C_Timer and C_Timer.After then
        questRefreshQueued = true
        C_Timer.After(0.2, function()
            questRefreshQueued = false
            if ns.RefreshMap then ns.RefreshMap() end
        end)
    elseif ns.RefreshMap then ns.RefreshMap() end
end
EVENT_DISPATCH_TABLE.QUEST_ACCEPTED = EVENT_DISPATCH_TABLE.QUEST_LOG_UPDATE
EVENT_DISPATCH_TABLE.QUEST_TURNED_IN = EVENT_DISPATCH_TABLE.QUEST_LOG_UPDATE
EVENT_DISPATCH_TABLE.QUEST_REMOVED = EVENT_DISPATCH_TABLE.QUEST_LOG_UPDATE
EVENT_DISPATCH_TABLE.CHAT_MSG_SYSTEM = DungeonProgressTracker.onSystemMessage
EVENT_DISPATCH_TABLE.UPDATE_MOUSEOVER_UNIT = function() DungeonProgressTracker.noteInstance("mouseover"); ns.LearnName("mouseover"); DungeonProgressTracker.verifyUnitDeath("mouseover") end
EVENT_DISPATCH_TABLE.UNIT_TARGET = function(unit)
    unit = ns.CoerceSafeString(unit)
    if unitState.current and unit and unit:find("^party%d$") then DungeonProgressTracker.verifyUnitDeath(unit .. "target") end
end
EVENT_DISPATCH_TABLE.ENCOUNTER_END = function(_, name, _, _, success) DungeonProgressTracker.onEncounter(name, success) end
EVENT_DISPATCH_TABLE.BOSS_KILL = function(_, name) DungeonProgressTracker.onEncounter(name, nil) end
EVENT_DISPATCH_TABLE.PLAYER_REGEN_DISABLED = function()
    unitState.inCombat = true
    if ns.ApplyAlpha then ns.ApplyAlpha() end
end
EVENT_DISPATCH_TABLE.PLAYER_REGEN_ENABLED = function()
    unitState.inCombat = false
    if ns.ApplyAlpha then ns.ApplyAlpha() end
    DungeonProgressTracker.sweepDeaths()
    if C_Timer and C_Timer.After then C_Timer.After(1.5, DungeonProgressTracker.sweepDeaths) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not ns.db and event ~= "ADDON_LOADED" then return end
    local headerBar = EVENT_DISPATCH_TABLE[event]
    if headerBar then
        local isCallOk, errorObj = pcall(headerBar, ...)
        if not isCallOk and ns.db and ns.db.debug then ns.Print("|cffff5555" .. event .. ": " .. tostring(errorObj) .. "|r") end
    end
end)

-----------------------------------------------------------------------------
-- Dungeon Route Guide Toggle
-----------------------------------------------------------------------------
function EzWoW_DungeonRouteGuide_Toggle() if ns.ToggleMap then ns.ToggleMap() end end
function EzWoW_DungeonRouteGuide_MarkNext() ns.CompleteNextRouteStep() end
function EzWoW_DungeonRouteGuide_Announce() ns.BroadcastCurrentStepToChat() end

function DungeonProgressTracker.printDebugMessage()
    local name, itype, itemIDVal = ns.InstanceInfo()
    ns.Print(("instance: %s / type: %s / id: %s"):format(tostring(name), tostring(itype), tostring(itemIDVal)))
    ns.Print(("zone: %s / sub: %s / minimap: %s"):format(tostring(ns.CoerceSafeString(ns.UnwrapSafeValue(GetZoneText))),
        tostring(ns.CoerceSafeString(ns.UnwrapSafeValue(GetSubZoneText))), tostring(ns.CoerceSafeString(ns.UnwrapSafeValue(GetMinimapZoneText)))))
    local dataEntry = ns.DetectDungeon()
    ns.Print("detected: " .. (dataEntry and translationHelper(dataEntry.name) or "-"))
    local npc = ns.UnitNpcID("target")
    if npc then ns.Print(("target npc: %d %s"):format(npc, tostring(ns.CoerceSafeString(ns.UnwrapSafeValue(UnitName, "target"))))) end
end

SLASH_EZWOWDUNGEONROUTEGUIDE1 = "/ezdg"
SLASH_EZWOWDUNGEONROUTEGUIDE2 = "/drg"
SLASH_EZWOWDUNGEONROUTEGUIDE3 = "/dungeonroute"
SLASH_EZWOWDUNGEONROUTEGUIDE4 = "/던전길잡이"
SlashCmdList.EZWOWDUNGEONROUTEGUIDE = function(msg)
    if not ns.db then ns.InitDB() end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" then ns.ToggleMap()
    elseif cmd == "config" or cmd == "opt" or cmd == "options" or cmd == "settings" or cmd == "설정" then
        if ns.ToggleConfig then ns.ToggleConfig() end
    elseif cmd == "hud" then ns.db.hud = not ns.db.hud; ns.RefreshHUD()
    elseif cmd == "next" or cmd == "skip" then ns.CompleteNextRouteStep()
    elseif cmd == "undo" then ns.UndoLastCompletedStep()
    elseif cmd == "reset" then ns.ResetProgress()
    elseif cmd == "lock" then ns.db.locked = not ns.db.locked; ns.RefreshAll()
    elseif cmd == "alpha" then
        local entryValue = tonumber(rest); if entryValue then ns.db.alpha = math.max(0.2, math.min(1, entryValue > 1 and entryValue / 100 or entryValue)); ns.ApplyAlpha() end
    elseif cmd == "size" then
        local entryValue = tonumber(rest); if entryValue then ns.db.mapSize = math.max(240, math.min(800, entryValue)); ns.RebuildMap() end
    elseif cmd == "auto" then ns.db.autoOpen = not ns.db.autoOpen; ns.Print(L.OPT_AUTO:format(ns.FormatEnabledStateLabel(ns.db.autoOpen)))
    elseif cmd == "lang" or cmd == "language" or cmd == "언어" then
        local want = ({
            auto = "auto", ["자동"] = "auto",
            ko = "ko", kr = "ko", kokr = "ko", ["한국어"] = "ko",
            en = "en", enus = "en", engb = "en", english = "en", ["영어"] = "en",
            de = "de", dede = "de", german = "de", ["독일어"] = "de",
            fr = "fr", frfr = "fr", french = "fr", ["프랑스어"] = "fr",
            es = "es", eses = "es", esmx = "es", spanish = "es", ["스페인어"] = "es",
            ru = "ru", ruru = "ru", russian = "ru", ["러시아어"] = "ru",
            zhcn = "zhCN", cn = "zhCN", ["중국어"] = "zhCN",
            zhtw = "zhTW", tw = "zhTW",
        })[rest]
        ns.ChangeLanguage(want)
    elseif cmd == "map" then
        ns.SetMapStyle("blizzard")
    elseif cmd == "wing" or cmd == "지역" or cmd == "구역" then
        if rest == "auto" or rest == "자동" then
            unitState.wingOverride, unitState.detectedWing = nil, nil
            ns.UpdateLocation()
        else
            local dataEntry = ns.DungeonByKey[rest]
            if not dataEntry then
                for _, candidate in ipairs(ns.Dungeons) do
                    for _, alias in ipairs(candidate.nameMatch or {}) do
                        if ns.Normalize(alias) == ns.Normalize(rest) then dataEntry = candidate; break end
                    end
                    if dataEntry then break end
                end
            end
            if dataEntry then ns.SelectDungeon(dataEntry) else ns.Print(L.WING_HELP) end
        end
    elseif cmd == "icon" then ns.SetIconShown(not ns.db.showIcon); ns.Print(L.OPT_ICON:format(ns.FormatEnabledStateLabel(ns.db.showIcon)))
    elseif cmd == "rare" then ns.db.rareAlert = not ns.db.rareAlert; ns.Print(L.OPT_RARE:format(ns.FormatEnabledStateLabel(ns.db.rareAlert)))
    elseif cmd == "go" then
        if rest == "stop" or rest == "off" then ns.StopEntrance() else ns.StartEntrance(ns.DungeonByKey[rest] or unitState.viewed) end
    elseif cmd == "entrance" and rest == "set" then ns.SaveEntranceHere()
    elseif cmd == "entrance" and rest == "clear" then
        if unitState.viewed then ns.db.entrances[unitState.viewed.key] = nil end
        if ns.RefreshWorldMap then ns.RefreshWorldMap() end
    elseif cmd == "edit" then ns.SetEditMode(not unitState.edit)
    elseif cmd == "export" then ns.ShowExport()
    elseif cmd == "donate" or cmd == "support" or cmd == "후원" then ns.ShowDonate()
    elseif cmd == "mapscan" then ns.MapScan()
    elseif cmd == "item" then
        
        local entityID = tonumber(rest)
        if entityID then
            local full = ns.CoerceSafeString(ns.UnwrapSafeValue((C_Item and C_Item.GetItemInfo) or GetItemInfo, entityID))
            local short = ns.CoerceSafeString(ns.UnwrapSafeValue(C_Item and C_Item.GetItemNameByID, entityID))
            local exists = ns.UnwrapSafeValue(C_Item and C_Item.DoesItemExistByID, entityID)
            ns.Print(("item %d: info=%s name=%s exists=%s state=%s"):format(entityID, tostring(full), tostring(short),
                tostring(ns.IsReadableValue(exists) and exists), ns.ItemState(entityID)))
        end
    elseif cmd == "debug" then DungeonProgressTracker.printDebugMessage()
    elseif cmd == "verbose" then ns.db.debug = not ns.db.debug; ns.Print("debug " .. ns.FormatEnabledStateLabel(ns.db.debug))
    else
        ns.Print(L.HELP)
    end
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
DungeonProgressTracker.BroadcastCurrentStepToChat = ns.BroadcastCurrentStepToChat
DungeonProgressTracker.ResolveBossEncounterOrderIndex = ns.ResolveBossEncounterOrderIndex
DungeonProgressTracker.ComputeDungeonProgressCounts = ns.ComputeDungeonProgressCounts
DungeonProgressTracker.IsBossEncounterStep = ns.IsBossEncounterStep
DungeonProgressTracker.GetDungeonManualRouteEdits = ns.GetDungeonManualRouteEdits
DungeonProgressTracker.IsRouteStepCompleted = ns.IsRouteStepCompleted
DungeonProgressTracker.IsPrimaryRouteStep = ns.IsPrimaryRouteStep
DungeonProgressTracker.IsRouteStepSkipped = ns.IsRouteStepSkipped
DungeonProgressTracker.ResolveStepCategoryIcon = ns.ResolveStepCategoryIcon
DungeonProgressTracker.CompleteNextRouteStep = ns.CompleteNextRouteStep
DungeonProgressTracker.ResolveNextIncompleteStep = ns.ResolveNextIncompleteStep
DungeonProgressTracker.SetRouteStepCompleted = ns.SetRouteStepCompleted
DungeonProgressTracker.ResolveRouteStepCoordinates = ns.ResolveRouteStepCoordinates
DungeonProgressTracker.ResolveRouteStepFloorSegment = ns.ResolveRouteStepFloorSegment
DungeonProgressTracker.FormatRouteStepBadgeTag = ns.FormatRouteStepBadgeTag
DungeonProgressTracker.ResolveRouteStepDisplayTitle = ns.ResolveRouteStepDisplayTitle
DungeonProgressTracker.IsRouteStepVisibleOnFloor = ns.IsRouteStepVisibleOnFloor
DungeonProgressTracker.UndoLastCompletedStep = ns.UndoLastCompletedStep
