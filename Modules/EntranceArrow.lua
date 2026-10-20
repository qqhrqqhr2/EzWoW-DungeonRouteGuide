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
    end)
    stop:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
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
