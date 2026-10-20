--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/LauncherIcon.lua : Draggable Floating Dungeon Guide Launcher Icon
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local FloatingLauncherButton = ns.FloatingLauncherButton or {}
ns.FloatingLauncherButton = FloatingLauncherButton
local L, translationHelper = ns.L, ns.GetLocalizedText
local unitState = ns.state

local iconTex = "Interface\\AddOns\\EzWoW-DungeonRouteGuide\\Media\\icon"

local actionBtn

function ns.SuggestDungeon()
    local level = ns.CoerceSafeNumber(ns.UnwrapSafeValue(UnitLevel, "player")) or 1
    local inRange, inDist, upcoming, upLo, last
    for _, dataEntry in ipairs(ns.Dungeons) do
        local loVal, hiVal = (dataEntry.levels or ""):match("(%d+)%D+(%d+)")
        loVal, hiVal = tonumber(loVal), tonumber(hiVal)
        if loVal and hiVal then
            last = dataEntry
            if level >= loVal and level <= hiVal then
                local dist = math.abs(level - (loVal + hiVal) / 2)
                if not inDist or dist < inDist then inRange, inDist = dataEntry, dist end
            elseif level < loVal and (not upLo or loVal < upLo) then
                upcoming, upLo = dataEntry, loVal
            end
        end
    end
    return inRange or upcoming or last or ns.Dungeons[1]
end

function FloatingLauncherButton.tooltip(self)
    if self.dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("EzWoW - Dungeon Route Guide", 0.918, 0.514, 0.494)
    GameTooltip:AddLine(L.ICON_LEFT, 0.929, 0.957, 0.969)
    GameTooltip:AddLine(L.ICON_RIGHT, 0.655, 0.725, 0.773)
    GameTooltip:AddLine(L.ICON_DRAG, 0.655, 0.725, 0.773)
    GameTooltip:Show()
end

function FloatingLauncherButton.handleWidgetMouseClick(self, button)
    if self and self.dragging then return end
    if button == "RightButton" then
        if ns.EntranceActive() then
            ns.StopEntrance()
        else
            ns.StartEntrance(unitState.viewed or ns.SuggestDungeon())
        end
    else
        if not unitState.current and not unitState.viewed then unitState.viewed = ns.SuggestDungeon() end
        ns.ToggleMap()
    end
end

function ns.CreateIcon()
    if actionBtn then return actionBtn end
    actionBtn = CreateFrame("Button", "EzWoW_DungeonRouteGuideIcon", UIParent)
    actionBtn:SetSize(36, 36)
    actionBtn:SetScale(1)
    actionBtn:SetFrameStrata("MEDIUM")
    actionBtn:SetClampedToScreen(true)
    actionBtn:SetMovable(true)
    actionBtn:EnableMouse(true)
    actionBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    actionBtn:RegisterForDrag("LeftButton")

    local iconTex2 = actionBtn:CreateTexture(nil, "ARTWORK")
    iconTex2:SetTexture(iconTex)
    iconTex2:SetAllPoints()
    local hlVal = actionBtn:CreateTexture(nil, "HIGHLIGHT")
    hlVal:SetTexture(iconTex)
    hlVal:SetAllPoints()
    hlVal:SetBlendMode("ADD")
    hlVal:SetAlpha(0.35)
    actionBtn.icon = iconTex2

    local coordPos = ns.db.frames.icon
    if coordPos then
        actionBtn:SetPoint(coordPos[1], UIParent, coordPos[2], coordPos[3], coordPos[4])
    else
        actionBtn:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
    end

    local grabDX, grabDY = 0, 0
    actionBtn:SetScript("OnDragStart", function(self)
        self:SetScale(1)
        self.dragging = true
        GameTooltip:Hide()
        local effScale = self:GetEffectiveScale() or 1
        local curX, curY = GetCursorPosition()
        curX, curY = curX / effScale, curY / effScale
        local bx, by = self:GetCenter()
        if bx and by then
            grabDX = bx - curX
            grabDY = by - curY
        else
            grabDX, grabDY = 0, 0
        end
        self:SetScript("OnUpdate", function(btn)
            local es = btn:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es + grabDX, cy / es + grabDY
            local uiW = (UIParent and UIParent:GetWidth()) or 1920
            local uiH = (UIParent and UIParent:GetHeight()) or 1080
            local half = 18
            if cx < half then cx = half elseif cx > uiW - half then cx = uiW - half end
            if cy < half then cy = half elseif cy > uiH - half then cy = uiH - half end
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        end)
    end)
    actionBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        if cx and cy then
            ns.db.frames.icon = { "CENTER", "BOTTOMLEFT", math.floor(cx + 0.5), math.floor(cy + 0.5) }
        else
            local anchorTarget, _, relativePoint, coordX, coordY = self:GetPoint(1)
            ns.db.frames.icon = { anchorTarget, relativePoint, coordX, coordY }
        end
        self.dragging = false
    end)
    actionBtn:SetScript("OnClick", FloatingLauncherButton.handleWidgetMouseClick)
    actionBtn:SetScript("OnEnter", FloatingLauncherButton.tooltip)
    actionBtn:SetScript("OnLeave", GameTooltip_Hide)
    actionBtn:SetShown(ns.db.showIcon)
    return actionBtn
end

function ns.SetIconShown(show)
    ns.db.showIcon = show and true or false
    ns.CreateIcon():SetShown(ns.db.showIcon)
end
