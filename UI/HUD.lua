--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/HUD.lua : Compact In-Dungeon Current Step & Boss Progress Overlay
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local StepTrackerHUD = ns.StepTrackerHUD or {}
ns.StepTrackerHUD = StepTrackerHUD
local L, translationHelper = ns.L, ns.GetLocalizedText
local unitState = ns.state

local hud

function StepTrackerHUD.createStepDeltaBtn(parent, text, w, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(w, 18)
    if buttonWidget.SetBackdrop then
        buttonWidget:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        buttonWidget:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
        buttonWidget:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
    end
    local labelRegion = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelRegion:SetPoint("CENTER")
    labelRegion:SetTextColor(0.929, 0.957, 0.969, 1.00)
    labelRegion:SetText(text or "")
    buttonWidget.label = labelRegion
    function buttonWidget:SetText(txt) labelRegion:SetText(txt or "") end
    function buttonWidget:GetText() return labelRegion:GetText() end
    function buttonWidget:GetFontString() return labelRegion end
    buttonWidget:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.18, 0.23, 0.29, 1.00)
            self:SetBackdropBorderColor(0.918, 0.514, 0.494, 1.00)
        end
    end)
    buttonWidget:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
    end)
    buttonWidget:SetScript("OnMouseDown", function() labelRegion:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() labelRegion:SetPoint("CENTER", 0, 0) end)
    buttonWidget:SetScript("OnClick", onClick)
    return buttonWidget
end

function StepTrackerHUD.createPrimaryWidget()
    hud = CreateFrame("Frame", "EzWoW_DungeonRouteGuideHUD", UIParent, "BackdropTemplate")
    hud:SetSize(340, 62)
    if hud.SetBackdrop then
        hud:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        hud:SetBackdropColor(0.071, 0.094, 0.122, 0.90)
        hud:SetBackdropBorderColor(0.918, 0.514, 0.494, 0.85)
    end
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local anchorTarget, _, relativePoint, coordX, coordY = self:GetPoint(1)
        ns.db.frames.hud = { anchorTarget, relativePoint, coordX, coordY }
    end)
    local coordPos = ns.db.frames.hud
    if coordPos then hud:SetPoint(coordPos[1], UIParent, coordPos[2], coordPos[3], coordPos[4]) else hud:SetPoint("TOP", 0, -110) end

    hud.mapBtn = StepTrackerHUD.createStepDeltaBtn(hud, L.BTN_MAP, 42, function() ns.ToggleMap() end)
    hud.mapBtn:SetPoint("TOPRIGHT", -4, -4)
    hud.tellBtn = StepTrackerHUD.createStepDeltaBtn(hud, L.BTN_ANNOUNCE, 62, function() ns.BroadcastCurrentStepToChat() end)
    hud.tellBtn:SetPoint("RIGHT", hud.mapBtn, "LEFT", -2, 0)
    ns.GetLocalizedEntryField(hud.mapBtn, "BTN_MAP"); ns.GetLocalizedEntryField(hud.tellBtn, "BTN_ANNOUNCE")

    hud.head = hud:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hud.head:SetPoint("TOPLEFT", 8, -7)
    hud.head:SetPoint("RIGHT", hud.tellBtn, "LEFT", -4, 0)
    hud.head:SetJustifyH("LEFT")
    if hud.head.SetWordWrap then hud.head:SetWordWrap(false) end

    hud.line = hud:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hud.line:SetPoint("TOPLEFT", 8, -24)
    hud.line:SetPoint("RIGHT", -8, 0)
    hud.line:SetJustifyH("LEFT")
    if hud.line.SetWordWrap then hud.line:SetWordWrap(false) end

    hud.tip = hud:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hud.tip:SetPoint("TOPLEFT", 8, -42)
    hud.tip:SetPoint("RIGHT", -8, 0)
    hud.tip:SetJustifyH("LEFT")
    hud.tip:SetTextColor(0.85, 0.85, 0.85)
    if hud.tip.SetWordWrap then hud.tip:SetWordWrap(false) end
end

function ns.RefreshHUD()
    local dataEntry = unitState.current
    local show = ns.db and ns.db.hud and dataEntry ~= nil
    if not show then
        if hud then hud:Hide() end
        return
    end
    if not hud then StepTrackerHUD.createPrimaryWidget() end
    local done, grandTotal = ns.ComputeDungeonProgressCounts(dataEntry)
    hud.head:SetText(("|cffffd100%s|r  %s"):format(translationHelper(dataEntry.name), L.PROGRESS:format(done, grandTotal)))
    local index, formatLocalizedLabel = unitState.targetStep, L.TARGET
    if not index or ns.IsRouteStepCompleted(dataEntry, index) then index, formatLocalizedLabel = ns.ResolveNextIncompleteStep(dataEntry), L.NEXT end
    if index then
        local step = dataEntry.steps[index]
        hud.line:SetText(("|cffffd100%s:|r %s"):format(formatLocalizedLabel, ns.ResolveRouteStepDisplayTitle(dataEntry, index)))
        hud.tip:SetText(ns.FirstSentence(translationHelper(step.tip)))
    else
        hud.line:SetText("|cff55ff55" .. L.DONE_ALL .. "|r")
        hud.tip:SetText("")
    end
    hud:Show()
end
