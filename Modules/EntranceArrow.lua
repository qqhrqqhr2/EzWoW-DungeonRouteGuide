--===========================================================================
-- EzWoW - Dungeon Route Guide
-- Modules/EntranceArrow.lua : Directional Overworld Dungeon Entrance HUD Arrow
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local EntranceArrowNavigator = ns.EntranceArrowNavigator or {}
ns.EntranceArrowNavigator = EntranceArrowNavigator
local L, translationHelper = ns.L, ns.GetLocalizedText
local unitState = ns.state

local ARROW = "Interface\\Minimap\\MinimapArrow"
local windowFrame, targetKey, elapsedAcc = nil, nil, 0

function EntranceArrowNavigator.resolveDungeonEntrancePoint(d)
    return (ns.db.entrances and ns.db.entrances[d.key]) or d.entrance
end

function EntranceArrowNavigator.resolvePlayerMapPos()
    local map = ns.CoerceSafeNumber(ns.UnwrapSafeValue(C_Map.GetBestMapForUnit, "player"))
    if not map then return end
    local coordPos = ns.UnwrapSafeValue(C_Map.GetPlayerMapPosition, map, "player")
    if not coordPos then return end
    local coordX, coordY = ns.UnwrapSafeValue(coordPos.GetXY, coordPos)
    coordX, coordY = ns.CoerceSafeNumber(coordX), ns.CoerceSafeNumber(coordY)
    if not coordX or not coordY or (coordX == 0 and coordY == 0) then return end
    return map, coordX, coordY
end

function EntranceArrowNavigator.resolveWorldPos(map, coordX, coordY)
    if not CreateVector2D then return end
    local cont, windowPos = ns.UnwrapSafeValue(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(coordX, coordY))
    if not windowPos then return end
    return ns.CoerceSafeNumber(cont), windowPos
end

function EntranceArrowNavigator.resolveTargetOnMap(map, e)
    if e.map == map then return e.x / 100, e.y / 100 end
    local cont, windowPos = EntranceArrowNavigator.resolveWorldPos(e.map, e.x / 100, e.y / 100)
    if not windowPos then return end
    local _, mpVal = ns.UnwrapSafeValue(C_Map.GetMapPosFromWorldPos, cont, windowPos, map)
    if not mpVal then return end
    local coordX, coordY = ns.UnwrapSafeValue(mpVal.GetXY, mpVal)
    return ns.CoerceSafeNumber(coordX), ns.CoerceSafeNumber(coordY), cont
end

function EntranceArrowNavigator.resolveZoneName(map)
    local apiInfo = ns.UnwrapSafeValue(C_Map.GetMapInfo, map)
    return apiInfo and ns.CoerceSafeString(apiInfo.name) or tostring(map)
end

function EntranceArrowNavigator.updateFrameOnTick()
    local d = targetKey
    if not d then return end
    local _, itype = ns.InstanceInfo()
    if itype and itype ~= "none" then
        windowFrame.arrow:Hide()
        windowFrame.text:SetText(L.ENTRANCE_INSIDE)
        return
    end
    local e = EntranceArrowNavigator.resolveDungeonEntrancePoint(d)
    local map, pxVal, pyVal = EntranceArrowNavigator.resolvePlayerMapPos()
    if not map then
        windowFrame.arrow:Hide()
        windowFrame.text:SetText(translationHelper(e.zone) .. ("\n%.1f, %.1f"):format(e.x, e.y))
        return
    end
    local txVal, tyVal = EntranceArrowNavigator.resolveTargetOnMap(map, e)
    local pcont = EntranceArrowNavigator.resolveWorldPos(map, pxVal, pyVal)
    local tcont = EntranceArrowNavigator.resolveWorldPos(e.map, e.x / 100, e.y / 100)
    if not txVal or (pcont and tcont and pcont ~= tcont) then
        windowFrame.arrow:Hide()
        windowFrame.text:SetText(L.ENTRANCE_OTHER:format(translationHelper(e.zone)))
        return
    end
    local boxWidth, headerBar = ns.UnwrapSafeValue(C_Map.GetMapWorldSize, map)
    boxWidth, headerBar = ns.CoerceSafeNumber(boxWidth), ns.CoerceSafeNumber(headerBar)
    if not boxWidth or not headerBar or boxWidth == 0 or headerBar == 0 then boxWidth, headerBar = 1500, 1000 end
    local east, south = (txVal - pxVal) * boxWidth, (tyVal - pyVal) * headerBar
    local dist = math.sqrt(east * east + south * south)
    if dist < 12 then
        windowFrame.arrow:Hide()
        windowFrame.text:SetText("|cff55ff55" .. L.ENTRANCE_ARRIVE .. "|r")
        return
    end
    
    local angle = math.atan2(-east, -south)
    local facing = ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetPlayerFacing))
    if facing then
        windowFrame.arrow:SetRotation(angle - facing)
        windowFrame.arrow:Show()
    else
        windowFrame.arrow:Hide()
    end
    local entryIndex = math.floor((angle % (2 * math.pi)) / (2 * math.pi) * 8 + 0.5) % 8
    windowFrame.text:SetText(L.DIST:format(L["DIR_" .. entryIndex], math.floor(dist + 0.5)))
end

function EntranceArrowNavigator.createPrimaryWidget()
    windowFrame = CreateFrame("Frame", "EzWoW_DungeonRouteGuideArrow", UIParent, "BackdropTemplate")
    windowFrame:SetSize(170, 112)
    if windowFrame.SetBackdrop then
        windowFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        windowFrame:SetBackdropColor(0.071, 0.094, 0.122, 0.90)
        windowFrame:SetBackdropBorderColor(0.918, 0.514, 0.494, 0.85)
    end
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:EnableMouse(true)
    windowFrame:RegisterForDrag("LeftButton")
    windowFrame:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    windowFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local anchorTarget, _, relativePoint, coordX, coordY = self:GetPoint(1)
        ns.db.frames.arrow = { anchorTarget, relativePoint, coordX, coordY }
    end)
    local coordPos = ns.db.frames.arrow
    if coordPos then windowFrame:SetPoint(coordPos[1], UIParent, coordPos[2], coordPos[3], coordPos[4]) else windowFrame:SetPoint("TOP", 0, -190) end
    windowFrame.title = windowFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    windowFrame.title:SetPoint("TOP", 0, -5)
    windowFrame.arrow = windowFrame:CreateTexture(nil, "ARTWORK")
    windowFrame.arrow:SetTexture(ARROW)
    windowFrame.arrow:SetSize(48, 48)
    windowFrame.arrow:SetPoint("TOP", 0, -20)
    windowFrame.text = windowFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    windowFrame.text:SetPoint("TOP", windowFrame.arrow, "BOTTOM", 0, -2)
    windowFrame.text:SetWidth(160)
    local stop = CreateFrame("Button", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    stop:SetSize(20, 16)
    if stop.SetBackdrop then
        stop:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        stop:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
        stop:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
    end
    local stopLabel = stop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stopLabel:SetPoint("CENTER")
    stopLabel:SetTextColor(0.929, 0.957, 0.969, 1.00)
    stopLabel:SetText("X")
    stop:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.18, 0.23, 0.29, 1.00)
            self:SetBackdropBorderColor(0.918, 0.514, 0.494, 1.00)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TIP_ARROW_STOP, 1, 1, 1)
        GameTooltip:AddDoubleLine(" ", "EzWoW - Dungeon Route Guide", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    stop:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
        GameTooltip:Hide()
    end)
    stop:SetPoint("TOPRIGHT", -2, -2)
    stop:SetScript("OnClick", function() ns.StopEntrance() end)
    windowFrame:SetScript("OnUpdate", function(_, elapsed)
        elapsedAcc = elapsedAcc + elapsed
        if elapsedAcc < 0.1 then return end
        elapsedAcc = 0
        local isCallOk, errorObj = pcall(EntranceArrowNavigator.updateFrameOnTick)
        if not isCallOk and ns.db.debug then ns.Print(errorObj) end
    end)
end

function ns.StartEntrance(d)
    d = d or unitState.viewed or unitState.current or ns.Dungeons[1]
    if not d then return end
    if not windowFrame then EntranceArrowNavigator.createPrimaryWidget() end
    targetKey = d
    windowFrame.title:SetText(translationHelper(d.name))
    windowFrame:Show()
    local e = EntranceArrowNavigator.resolveDungeonEntrancePoint(d)
    ns.Print(L.ENTRANCE_START:format(translationHelper(d.name)) .. " " .. translationHelper(e.zone) .. (" %.1f, %.1f"):format(e.x, e.y))
    if e.note then ns.Print(translationHelper(e.note)) end
end

function ns.StopEntrance(quiet)
    targetKey = nil
    if windowFrame then windowFrame:Hide() end
    if not quiet then ns.Print(L.ENTRANCE_STOP) end
end

function ns.EntranceActive()
    return targetKey ~= nil
end

function ns.StopEntranceIfInside()
    if targetKey then ns.StopEntrance(true) end
end

function ns.SaveEntranceHere(d)
    d = d or targetKey or unitState.viewed
    if not d then return end
    local _, itype = ns.InstanceInfo()
    local map, coordX, coordY = EntranceArrowNavigator.resolvePlayerMapPos()
    if (itype and itype ~= "none") or not map then ns.Print(L.ENTRANCE_NOPOS); return end
    ns.db.entrances[d.key] = { map = map, x = coordX * 100, y = coordY * 100, zone = { ko = EntranceArrowNavigator.resolveZoneName(map), en = EntranceArrowNavigator.resolveZoneName(map) } }
    if ns.RefreshWorldMap then ns.RefreshWorldMap() end
    ns.Print(L.ENTRANCE_SET:format(translationHelper(d.name), coordX * 100, coordY * 100))
end

--===========================================================================
-- Boss / rare areas: the sub-zone a boss or rare monster of a dungeon lies in,
-- taken when its corpse is looted. The game gives no position inside dungeons,
-- but the sub-zone name tells the floor (Data/FloorAreas.lua).
-- Shared between players with the same client language (EzWoW shared data,
-- kind "B"): "npcID,instanceID,count,area".
-- Kept in the shared store: store[npcID] = { i = instanceID, own = { [area] = count }, peers = { [sender] = { [area] = true } } }.
-- Only areas this character looted in are sent; received ones are never sent on.
-- They are gathered into the dungeon data of the next release (boss floors, missing bosses).
--===========================================================================
local BossAreas = {}
ns.BossAreas = BossAreas
local BOSS_CLASSES = { worldboss = true, rare = true, rareelite = true }
local MAX_PEERS = 20
local MAX_AREAS = 4

-- counts changes of the store, so the areas picked from it are read again
BossAreas.version = 0
function BossAreas.touch()
    BossAreas.version = BossAreas.version + 1
end

function BossAreas.store()
    if ns.Share and ns.Share.Store then
        local ok, s = pcall(ns.Share.Store, "B")
        if ok and type(s) == "table" then return s end
    end
    local db = ns.db
    if type(db) ~= "table" then return nil end
    db.bossAreas = type(db.bossAreas) == "table" and db.bossAreas or {}
    return db.bossAreas
end

function BossAreas.isStepNpc(npcID)
    local d = unitState.current
    if not d then return false end
    for _, step in ipairs(d.steps or {}) do
        if (step.kind == "boss" or step.kind == "rare") and step.npc then
            for _, id in ipairs(step.npc) do
                if id == npcID then return true end
            end
        end
    end
    return false
end

-- a boss / rare by its unit, when the corpse is the target or under the mouse
function BossAreas.isBossUnit(npcID)
    for _, unit in ipairs({ "target", "mouseover" }) do
        if ns.UnitNpcID(unit) == npcID then
            local class = ns.CoerceSafeString(ns.UnwrapSafeValue(UnitClassification, unit))
            local level = ns.CoerceSafeNumber(ns.UnwrapSafeValue(UnitLevel, unit))
            if (class and BOSS_CLASSES[class]) or level == -1 then return true end
        end
    end
    return false
end

function BossAreas.currentArea()
    for _, api in ipairs({ "GetSubZoneText", "GetMinimapZoneText" }) do
        local text = ns.CoerceSafeString(ns.UnwrapSafeValue(_G[api]))
        if text and text ~= "" and not text:find("[,;|]") and #text < 120 then return text end
    end
end

function BossAreas.record(npcID, instanceID)
    local area = BossAreas.currentArea()
    if not area then return end
    local s = BossAreas.store()
    if not s then return end
    local key = tostring(npcID)
    local row = type(s[key]) == "table" and s[key] or {}
    s[key] = row
    row.i = instanceID
    row.own = type(row.own) == "table" and row.own or {}
    if not row.own[area] then
        local n = 0
        for _ in pairs(row.own) do n = n + 1 end
        if n >= MAX_AREAS then return end
    end
    row.own[area] = math.min((row.own[area] or 0) + 1, 99)
    BossAreas.touch()
end

function BossAreas.onLoot()
    local _, itype, instanceID = ns.InstanceInfo()
    if not itype or itype == "none" or not instanceID then return end
    local slots = ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetNumLootItems))
    if not slots or slots < 1 or slots > 100 then return end
    local seen = {}
    for slot = 1, slots do
        local sources = { ns.UnwrapSafeValue(GetLootSourceInfo, slot) }
        for k = 1, #sources, 2 do
            local npcID = ns.NpcIDFromGUID(sources[k])
            if npcID and not seen[npcID] then
                seen[npcID] = true
                if BossAreas.isStepNpc(npcID) or BossAreas.isBossUnit(npcID) then BossAreas.record(npcID, instanceID) end
            end
        end
    end
end

-----------------------------------------------------------------------------
-- Reading: the sub-zone of a route step's boss, as this character and other
-- players looted it. Each player counts once per area (this character too);
-- the area most players reported wins, a tie goes to this character's own,
-- then to the name. The dungeon's own name (what the game shows outside any
-- sub-zone) tells nothing and is left out. An area only other players sent
-- needs MIN_PLAYERS of them. Shown in the step's tooltip and route card, and
-- the map follows it to the boss's floor (see learnedPage in DungeonMapWindow.lua).
-----------------------------------------------------------------------------
local MIN_PLAYERS = 2
local OWN = {}   -- this character among the senders
local picked, pickedVersion, pickedAt = {}, -1, 0

-- true for a name that is the dungeon's own: its zone, instance or wing name
function BossAreas.isMainName(d, area)
    local z = ns.Normalize(area)
    if not z or z == "" then return true end
    if ns.IsMainDungeonZone and ns.IsMainDungeonZone(d, z) then return true end
    for _, name in ipairs(d.resetNames or {}) do
        if ns.Normalize(name) == z then return true end
    end
    for _, id in ipairs(d.instanceIDs or {}) do
        -- the zone name of an instance map (outside the dungeon too)
        if ns.Normalize(ns.CoerceSafeString(ns.UnwrapSafeValue(GetRealZoneText, id))) == z then return true end
    end
    return false
end

-- { area, n = players, got = players other than this character } of a boss or
-- rare step (all its NPCs together), or false
function BossAreas.pick(d, step)
    local s = BossAreas.store()
    if type(s) ~= "table" then return false end
    local inst, anyInst = {}, false
    for _, id in ipairs(d.instanceIDs or {}) do inst[id], anyInst = true, true end
    local tally, order = {}, {}
    local function add(area, who)
        if type(area) ~= "string" or area == "" then return end
        local t = tally[area]
        if not t then
            t = { area = area, n = 0, got = 0, seen = {} }
            tally[area] = t
            order[#order + 1] = t
        end
        if t.seen[who] then return end
        t.seen[who] = true
        t.n = t.n + 1
        if who == OWN then t.own = true else t.got = t.got + 1 end
    end
    for _, npc in ipairs(step.npc) do
        local row = s[tostring(npc)]
        local rowInst = type(row) == "table" and tonumber(row.i)
        if type(row) == "table" and not (anyInst and rowInst and not inst[rowInst]) then
            for area in pairs(type(row.own) == "table" and row.own or {}) do add(area, OWN) end
            for who, v in pairs(type(row.peers) == "table" and row.peers or {}) do
                if type(v) == "string" then
                    add(v, who)   -- one area, as older copies kept it
                elseif type(v) == "table" then
                    for area, on in pairs(v) do
                        if on then add(area, who) end
                    end
                end
            end
        end
    end
    local best
    for _, t in ipairs(order) do
        if (t.own or t.got >= MIN_PLAYERS) and not BossAreas.isMainName(d, t.area) then
            if not best or t.n > best.n
                or (t.n == best.n and ((t.own and not best.own) or (t.own == best.own and t.area < best.area))) then
                best = t
            end
        end
    end
    if not best then return false end
    return { area = best.area, n = best.n, got = best.got }
end

-- the sub-zone of a boss or rare step: area text, players, players other than
-- this character (nil when none is known)
function BossAreas.stepArea(d, step)
    if type(d) ~= "table" or type(step) ~= "table" or type(step.npc) ~= "table" then return nil end
    if step.kind ~= "boss" and step.kind ~= "rare" then return nil end
    -- read again after a change, and a while later (saved copies joined since)
    local now = ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetTime)) or 0
    if pickedVersion ~= BossAreas.version or now - pickedAt > 60 or now < pickedAt then
        picked, pickedVersion, pickedAt = {}, BossAreas.version, now
    end
    local hit = picked[step]
    if hit == nil then
        local ok, res = pcall(BossAreas.pick, d, step)
        hit = (ok and res) or false
        picked[step] = hit
    end
    if not hit then return nil end
    return hit.area, hit.n, hit.got
end

-- bosses whose shown area has reports from other players in it
function BossAreas.usedCount()
    local n = 0
    for _, d in ipairs(ns.Dungeons or {}) do
        for _, step in ipairs(d.steps or {}) do
            local area, _, got = BossAreas.stepArea(d, step)
            if area and got and got > 0 then n = n + 1 end
        end
    end
    return n
end

if ns.Share and ns.Share.RegisterKind then
    ns.Share.RegisterKind("B", {
        localized = true,
        own = function()
            local out = {}
            for npc, row in pairs(BossAreas.store() or {}) do
                if type(row) == "table" and type(row.own) == "table" and tonumber(npc) and tonumber(row.i) then
                    for area, count in pairs(row.own) do
                        if type(area) == "string" and type(count) == "number" then
                            -- (the count field is not read by anyone; kept at 1 so the record
                            -- does not change, and go out again, with every loot)
                            out[#out + 1] = string.format("%d,%d,%d,%s", tonumber(npc), tonumber(row.i), 1, area)
                        end
                    end
                end
            end
            return out
        end,
        receive = function(body, hash)
            local npc, inst, area = body:match("^(%d+),(%d+),%d+,([^,;|]+)$")
            npc, inst = tonumber(npc), tonumber(inst)
            if not (npc and inst and area) or npc < 1 or npc > 10000000 or inst < 1 or inst > 100000 or #area >= 120 then return false end
            local s = BossAreas.store()
            if not s then return false end
            local key = tostring(npc)
            local row = type(s[key]) == "table" and s[key] or {}
            s[key] = row
            row.i = row.i or inst
            row.peers = type(row.peers) == "table" and row.peers or {}
            local h = tostring(hash or "?")
            -- the areas each player sent (one player can loot a boss in up to MAX_AREAS sub-zones)
            local mine = row.peers[h]
            if type(mine) == "string" then mine = { [mine] = true } end   -- one area, as older copies kept it
            if type(mine) == "table" and mine[area] then return false end   -- had it already
            if type(mine) ~= "table" then
                local n = 0
                for _ in pairs(row.peers) do n = n + 1 end
                if n >= MAX_PEERS then return false end
                mine = {}
            else
                local n = 0
                for _ in pairs(mine) do n = n + 1 end
                if n >= MAX_AREAS then return false end
            end
            mine[area] = true
            row.peers[h] = mine
            BossAreas.touch()
            return true
        end,
        -- for the shared records window: bosses whose received areas are in use
        used = function()
            local ok, n = pcall(BossAreas.usedCount)
            return ok and n or 0
        end,
    })
end

do
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() pcall(BossAreas.onLoot) end)
    pcall(f.RegisterEvent, f, "LOOT_OPENED")
end
