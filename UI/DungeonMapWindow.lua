--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/DungeonMapWindow.lua : Interactive Dungeon Map Canvas, Flow Lines & 3D Boss Cards
--===========================================================================
local _, ns = ...

local DungeonRouteWindow = ns.DungeonRouteWindow or {}
ns.DungeonRouteWindow = DungeonRouteWindow
local L, translationHelper = ns.L, ns.GetLocalizedText
local unitState = ns.state

local HEADER, PAD, LISTW = 28, 6, 240
local LIST_CONTENT_W = LISTW - PAD - 24
local LEGEND_H, FOOT_H = 16, 14
local MAP_PATH = "Interface\\AddOns\\EzWoW-DungeonRouteGuide\\Maps\\"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local CAT = {
    entrance = { 0.30, 0.85, 0.45 },
    boss     = { 0.78, 0.14, 0.10 },
    rare     = { 0.66, 0.30, 0.90 },
    npc      = { 0.20, 0.50, 0.95 },
    quest    = { 0.95, 0.76, 0.10 },
    done     = { 0.38, 0.38, 0.38 },
    link     = { 0.70, 0.70, 0.70 },
}
function DungeonRouteWindow.resolveCategory(step)
    if step.kind == "object" or step.kind == "task" then return "quest" end
    return CAT[step.kind] and step.kind or "boss"
end

local containerFrame, canvasFrame, overlay, mapTex, noMapText, titleStr, footerRegion, legend, itemList, menu, picker
local markers, alts, links, rowWidgets, qrows, masks, tiles = {}, {}, {}, {}, {}, {}, {}
local floorBtn, floorNext, floorList, floorRows = nil, nil, nil, {}
local dropdown, currentBtn
local cardLayout, anchorCard, buildCard, plotCard, buildFloorPicker
local CARD_W = 232
local lootBar, lootLabel, lootBtns = nil, nil, {}
local trashBtns = {}
local TRASH_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local entranceMark, tabRoute, tabQuest, tabNotes, progressText, tipText, questNote
local orientationBadge
local listScroll, listContent, listScrollKey, listRestoreOffset
local listOffsets = {}
local zoomReset
local navigation, baseView, nav = {}, AVIEW, nil

-----------------------------------------------------------------------------
-- Apply Panel Backdrop
-----------------------------------------------------------------------------
function DungeonRouteWindow.applyPanelBackdrop(f, a)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.071, 0.094, 0.122, a or 0.94)
    f:SetBackdropBorderColor(0.918, 0.514, 0.494, 0.90)
end

function DungeonRouteWindow.createStyledButton(parent, text, w, tip, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(w, 20)
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
    buttonWidget:SetScript("OnClick", onClick)
    buttonWidget:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.18, 0.23, 0.29, 1.00)
            self:SetBackdropBorderColor(0.918, 0.514, 0.494, 1.00)
        end
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    buttonWidget:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.114, 0.157, 0.192, 0.96)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
        if tip then GameTooltip_Hide() end
    end)
    buttonWidget:SetScript("OnMouseDown", function() labelRegion:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() labelRegion:SetPoint("CENTER", 0, 0) end)
    return buttonWidget
end

function DungeonRouteWindow.getSafeFrameWidth(f, def) return ns.CoerceSafeNumber(ns.UnwrapSafeValue(f and f.GetWidth, f)) or def or 0 end
function DungeonRouteWindow.getSafeFrameHeight(f, def) return ns.CoerceSafeNumber(ns.UnwrapSafeValue(f and f.GetHeight, f)) or def or 0 end
function DungeonRouteWindow.getSafeStringWidth(labelRegion, def) return ns.CoerceSafeNumber(ns.UnwrapSafeValue(labelRegion and labelRegion.GetStringWidth, labelRegion)) or def or 0 end
function DungeonRouteWindow.getSafeStringHeight(labelRegion, def) return ns.CoerceSafeNumber(ns.UnwrapSafeValue(labelRegion and labelRegion.GetStringHeight, labelRegion)) or def or 0 end

local fitBtns = {}
function DungeonRouteWindow.fitButtonWidthToLabel(buttonWidget)
    local labelRegion = buttonWidget:GetFontString()
    local swVal = DungeonRouteWindow.getSafeStringWidth(labelRegion, 0)
    buttonWidget:SetWidth(math.max(buttonWidget.minW or 20, math.floor(swVal + 14)))
end
function DungeonRouteWindow.shrinkFontStringToFit(buttonWidget, minW)
    buttonWidget.minW = minW
    fitBtns[#fitBtns + 1] = buttonWidget
    DungeonRouteWindow.fitButtonWidthToLabel(buttonWidget)
    return buttonWidget
end

function DungeonRouteWindow.applyCircularMask(parent, layer, size, sub)
    local resolvedValue = parent:CreateTexture(nil, layer, nil, sub)
    resolvedValue:SetSize(size, size)
    resolvedValue:SetPoint("CENTER")
    resolvedValue:SetColorTexture(1, 1, 1, 1)
    if parent.CreateMaskTexture then
        local matchRef = parent:CreateMaskTexture()
        matchRef:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        matchRef:SetAllPoints(resolvedValue)
        resolvedValue:AddMaskTexture(matchRef)
    end
    return resolvedValue
end

local AVIEW = { 0, 0, 512, 512 }
local blizFailed = {}

function DungeonRouteWindow.useBliz(d)
    return (d and d.bliz and not blizFailed[d.key]) and true or false
end

function DungeonRouteWindow.resolveFlowGeo(d)
    if d.flowGeo then return d.flowGeo end
    local order = {}
    for index, stateFlag in ipairs(d.steps) do
        if stateFlag.kind ~= "fork" then order[#order + 1] = index end
    end
    local nodeEntry = #order
    local cols = (nodeEntry <= 3) and math.max(1, nodeEntry) or 3
    local rowWidgets = math.max(1, math.ceil(nodeEntry / cols))
    local steps = {}
    for entryKey, index in ipairs(order) do
        local rowEntry, themeColor = math.floor((entryKey - 1) / cols), (entryKey - 1) % cols
        if rowEntry % 2 == 1 then themeColor = cols - 1 - themeColor end            
        steps[d.steps[index].id] = { page = "flow", pos = { math.floor(512 * (themeColor + 1) / (cols + 1)), math.floor(60 + 400 * (rowEntry + 0.5) / rowWidgets) } }
    end
    d.flowGeo = { pages = { { key = "flow", flow = true, colW = 512 / (cols + 1) } }, steps = steps, order = order }
    return d.flowGeo
end

function DungeonRouteWindow.resolveDungeonFloorGeometry(d)
    if DungeonRouteWindow.useBliz(d) then return d.bliz end
    return DungeonRouteWindow.resolveFlowGeo(d) 
end
function DungeonRouteWindow.containsMap(d) local greenVal = DungeonRouteWindow.resolveDungeonFloorGeometry(d); return greenVal.pages and #greenVal.pages > 0 end
function DungeonRouteWindow.viewOf(page)
    if page and page.view then return page.view end
    return AVIEW
end

function DungeonRouteWindow.stepGeo(d, index)
    local step = d.steps[index]
    local recordEntry = ns.GetDungeonManualRouteEdits(d, step)
    local g0Val = DungeonRouteWindow.resolveDungeonFloorGeometry(d)
    if g0Val ~= d then
        local greenVal = g0Val.steps and g0Val.steps[step.id]
        if not greenVal then return nil end
        return greenVal.page, (g0Val == d.bliz and recordEntry and recordEntry.bpos) or greenVal.pos, greenVal.alt
    end
    if not step.pos then return nil end
    return step.page, (recordEntry and recordEntry.pos) or step.pos, step.alt
end
ns.ProjectStepToCanvasGeometry = DungeonRouteWindow.stepGeo

local view = AVIEW
function DungeonRouteWindow.calculateCanvasScale() return (ns.db.mapSize or 380) / view[4] end
function DungeonRouteWindow.clampCenter(nodeEntry, buttonWidget)
    local w, headerBar = buttonWidget[3] / nodeEntry.zoom, buttonWidget[4] / nodeEntry.zoom
    nodeEntry.x = math.max(buttonWidget[1] + w / 2, math.min(buttonWidget[1] + buttonWidget[3] - w / 2, nodeEntry.x))
    nodeEntry.y = math.max(buttonWidget[2] + headerBar / 2, math.min(buttonWidget[2] + buttonWidget[4] - headerBar / 2, nodeEntry.y))
end
function DungeonRouteWindow.resolveNavigationView(d, page)
    baseView = DungeonRouteWindow.viewOf(page)
    if not page or page.flow or page.unavailable then nav = nil; return baseView end
    local lookupKey = d.key .. "/" .. page.key
    nav = navigation[lookupKey]
    if not nav then
        nav = { zoom = 1, x = baseView[1] + baseView[3]/2, y = baseView[2] + baseView[4]/2 }
        navigation[lookupKey] = nav
    end
    DungeonRouteWindow.clampCenter(nav, baseView)
    return {nav.x-baseView[3]/nav.zoom/2, nav.y-baseView[4]/nav.zoom/2, baseView[3]/nav.zoom, baseView[4]/nav.zoom}
end
function DungeonRouteWindow.zoomMap(delta)
    if not nav or unitState.edit then return end
    local previousVal = nav.zoom
    local cxVal, cyVal = ns.UnwrapSafeValue(GetCursorPosition)
    cxVal, cyVal = ns.CoerceSafeNumber(cxVal), ns.CoerceSafeNumber(cyVal)
    local esVal = ns.CoerceSafeNumber(ns.UnwrapSafeValue(canvasFrame.GetEffectiveScale, canvasFrame)) or 1
    local left = ns.CoerceSafeNumber(ns.UnwrapSafeValue(canvasFrame.GetLeft, canvasFrame)) or 0
    local top = ns.CoerceSafeNumber(ns.UnwrapSafeValue(canvasFrame.GetTop, canvasFrame)) or 0
    local cwVal, chVal = DungeonRouteWindow.getSafeFrameWidth(canvasFrame, 380), DungeonRouteWindow.getSafeFrameHeight(canvasFrame, 380)
    if not cxVal or not cyVal or cwVal <= 0 or chVal <= 0 then return end
    local fxVal = math.max(0, math.min(1, (cxVal/esVal-left)/cwVal))
    local fyVal = math.max(0, math.min(1, (top-cyVal/esVal)/chVal))
    local pxVal, pyVal = view[1]+fxVal*view[3], view[2]+fyVal*view[4]
    nav.zoom = math.max(1, math.min(5, previousVal * (delta>0 and 1.25 or 0.8)))
    nav.x = pxVal + (0.5-fxVal)*baseView[3]/nav.zoom
    nav.y = pyVal + (0.5-fyVal)*baseView[4]/nav.zoom
    ns.RefreshMap(true)
end

function DungeonRouteWindow.stepTooltip(owner, d, index)
    local step = d.steps[index]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.ResolveRouteStepDisplayTitle(d, index), 1, 0.82, 0)
    local kind = L["KIND_" .. step.kind] or step.kind
    if step.optional then kind = kind .. " · " .. L.OPTIONAL end
    if step.unconfirmed then kind = kind .. " · " .. L.UNCONFIRMED end
    if step.outside then kind = kind .. " · " .. translationHelper(step.outside) end
    GameTooltip:AddLine(kind, 0.7, 0.7, 0.7)
    if step.quest then GameTooltip:AddLine("! " .. L.QUEST_MARK, 1, 0.82, 0) end
    local position = d.bliz and d.bliz.steps and d.bliz.steps[step.id]
    if position and position.candidates then GameTooltip:AddLine(L.PIN_CANDIDATES, 1, 0.75, 0.3, true) end
    GameTooltip:AddLine(translationHelper(step.tip), 1, 1, 1, true)
    if step.loot and #step.loot > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.LOOT, 1, 0.82, 0)
        for entryKey, entityID in ipairs(step.loot) do
            if entryKey > 12 then GameTooltip:AddLine(("+%d"):format(#step.loot - 12), 0.7, 0.7, 0.7); break end
            local displayName, _, priorityQueue, iconTex = ns.ItemInfo(entityID)
            local textureRegion = iconTex and ("|T" .. iconTex .. ":14:14|t ") or ""
            GameTooltip:AddLine(textureRegion .. (displayName and (ns.QualityHex(priorityQueue) .. displayName .. "|r") or ("|cff888888#" .. entityID .. " " .. L.LOADING .. "|r")))
        end
    end
    GameTooltip:AddLine(L.CLICK_HINT, 0.5, 0.8, 1, true)
    GameTooltip:Show()
end

function DungeonRouteWindow.stepClick(d, index, button)
    if button == "RightButton" then
        ns.SetRouteStepCompleted(d, index, not ns.IsRouteStepCompleted(d, index))
    else
        unitState.selected = (unitState.selected == index) and nil or index
        unitState.cardTrash = nil
        local pgVal, coordPos = DungeonRouteWindow.stepGeo(d, index)
        if pgVal then unitState.page, unitState.pageManual = pgVal, true end
        local nodeEntry = pgVal and navigation[d.key .. "/" .. pgVal]
        if nodeEntry and coordPos and unitState.selected then nodeEntry.x, nodeEntry.y = coordPos[1], coordPos[2] end
        ns.RefreshMap()
    end
end

function DungeonRouteWindow.resolvePageHasArea(p, area)
    if not area or not p.areas then return false end
    if not p.areaSet then
        p.areaSet = {}
        for _, a in ipairs(p.areas) do
            local nodeEntry = ns.Normalize(a)
            if nodeEntry then p.areaSet[nodeEntry] = true end
        end
    end
    return p.areaSet[area] == true
end

function DungeonRouteWindow.resolvePageByKey(greenVal, lookupKey)
    if not lookupKey then return nil end
    for _, p in ipairs(greenVal.pages) do if p.key == lookupKey then return p end end
end

function DungeonRouteWindow.learnedSet(d, greenVal)
    local all = ns.db.floorAreas
    return all and all[d.key .. (d.editSpace or "") .. (greenVal == d.bliz and ":b" or ":a")]
end
function DungeonRouteWindow.learnedPage(d, greenVal, area)
    if not area or (ns.IsMainDungeonZone and ns.IsMainDungeonZone(d, area)) then return nil end
    local resolvedValue = DungeonRouteWindow.learnedSet(d, greenVal)
    return resolvedValue and resolvedValue[area] and DungeonRouteWindow.resolvePageByKey(greenVal, resolvedValue[area]) or nil
end
function ns.LearnFloor(d, index)
    local area = unitState.area
    if not area or area == "" or (ns.IsMainDungeonZone and ns.IsMainDungeonZone(d, area)) then return end
    local greenVal = DungeonRouteWindow.resolveDungeonFloorGeometry(d)
    if not (greenVal.pages and #greenVal.pages > 1) then return end
    local pgVal = DungeonRouteWindow.stepGeo(d, index)
    if not pgVal then return end
    ns.db.floorAreas = ns.db.floorAreas or {}
    local lookupKey = d.key .. (d.editSpace or "") .. (greenVal == d.bliz and ":b" or ":a")
    local resolvedValue = ns.db.floorAreas[lookupKey] or {}
    ns.db.floorAreas[lookupKey] = resolvedValue
    if resolvedValue[area] == nil then resolvedValue[area] = pgVal elseif resolvedValue[area] ~= pgVal then resolvedValue[area] = false end
end

function DungeonRouteWindow.resolveFirstStepOnPage(d, pageKey)
    if not d or not pageKey then return nil end
    local firstVisible, firstUndone
    for index, step in ipairs(d.steps) do
        if ns.IsRouteStepVisibleOnFloor(step) and DungeonRouteWindow.stepGeo(d, index) == pageKey then
            if not firstVisible then firstVisible = index end
            if not firstUndone and not ns.IsRouteStepCompleted(d, index) then firstUndone = index end
            if ns.IsPrimaryRouteStep(step) and not ns.IsRouteStepCompleted(d, index) then return index end
        end
    end
    return firstUndone or firstVisible
end

function DungeonRouteWindow.selectFloor(d, pageKey)
    if not pageKey then return end
    unitState.page, unitState.pageManual = pageKey, true
    unitState.cardTrash = nil
    if d and (not unitState.selected or DungeonRouteWindow.stepGeo(d, unitState.selected) ~= pageKey) then
        unitState.selected = DungeonRouteWindow.resolveFirstStepOnPage(d, pageKey)
    end
end

function DungeonRouteWindow.resolveCurrentPage(d)
    if not DungeonRouteWindow.containsMap(d) then return nil end
    local greenVal = DungeonRouteWindow.resolveDungeonFloorGeometry(d)
    if unitState.pageDungeon ~= d or unitState.pageGeo ~= greenVal then
        unitState.pageDungeon, unitState.pageGeo, unitState.page, unitState.pageManual = d, greenVal, nil, false
    end
    local here = (d == unitState.current) and #greenVal.pages > 1
    
    if here and unitState.areaChanged then
        unitState.areaChanged = nil
        for _, p in ipairs(greenVal.pages) do
            if DungeonRouteWindow.resolvePageHasArea(p, unitState.area) then unitState.pageManual = false; break end
        end
        if DungeonRouteWindow.learnedPage(d, greenVal, unitState.area) then unitState.pageManual = false end
    end
    if unitState.pageManual and unitState.page then
        local p = DungeonRouteWindow.resolvePageByKey(greenVal, unitState.page)
        if p then return p end
    end
    if here then
        
        local p = unitState.targetStep and DungeonRouteWindow.resolvePageByKey(greenVal, (DungeonRouteWindow.stepGeo(d, unitState.targetStep)))
        if p then return p end

        local fits = {}
        for _, priorityQueue in ipairs(greenVal.pages) do
            if DungeonRouteWindow.resolvePageHasArea(priorityQueue, unitState.area) then fits[#fits + 1] = priorityQueue end
        end
        if #fits > 0 then
            local niVal = ns.ResolveNextIncompleteStep(d)
            local want = niVal and DungeonRouteWindow.stepGeo(d, niVal)
            for _, priorityQueue in ipairs(fits) do if priorityQueue.key == want then return priorityQueue end end
            for _, priorityQueue in ipairs(fits) do if priorityQueue.key == unitState.shownPage then return priorityQueue end end
            return fits[1]
        end
        local lpVal = DungeonRouteWindow.learnedPage(d, greenVal, unitState.area)
        if lpVal then return lpVal end
    end
    local index = ns.ResolveNextIncompleteStep(d)
    local want = index and DungeonRouteWindow.stepGeo(d, index)
    for _, p in ipairs(greenVal.pages) do if p.key == want then return p end end
    return greenVal.pages[1]
end

-----------------------------------------------------------------------------
-- Sync Menu
-----------------------------------------------------------------------------
function DungeonRouteWindow.syncMenu()
    local cfVal = ns.GetConfigFrame and ns.GetConfigFrame()
        if cfVal and cfVal:IsShown() and cfVal.RefreshCfg then
            cfVal.RefreshCfg()
    end
end

-----------------------------------------------------------------------------
-- Build Picker
-----------------------------------------------------------------------------
function DungeonRouteWindow.buildPicker()
    picker = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
    DungeonRouteWindow.applyPanelBackdrop(picker, 0.97)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(containerFrame:GetFrameLevel() + 40)
    picker:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    local nodeEntry = #ns.Dungeons
    picker:SetSize(250, nodeEntry * 20 + 8)
    picker.buttons = {}
    for entryKey, d in ipairs(ns.Dungeons) do
        local buttonWidget = CreateFrame("Button", nil, picker)
        buttonWidget:SetSize(238, 20)
        buttonWidget:SetPoint("TOPLEFT", 6, -4 - (entryKey - 1) * 20)
        local hlVal = buttonWidget:CreateTexture(nil, "HIGHLIGHT"); hlVal:SetAllPoints(); hlVal:SetColorTexture(1, 1, 1, 0.1)
        buttonWidget.text = buttonWidget:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        buttonWidget.text:SetPoint("LEFT", 4, 0)
        buttonWidget.lv = buttonWidget:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        buttonWidget.lv:SetPoint("RIGHT", -4, 0)
        buttonWidget:SetScript("OnClick", function()
            picker:Hide(); if floorList then floorList:Hide() end
            ns.SelectDungeon(d)
        end)
        picker.buttons[entryKey] = buttonWidget
    end
    picker:SetScript("OnShow", function()
        for entryKey, d in ipairs(ns.Dungeons) do
            local buttonWidget = picker.buttons[entryKey]
            buttonWidget.text:SetText((d == unitState.current and "|cff55ff55> |r" or "") .. translationHelper(d.name))
            buttonWidget.lv:SetText(d.levels or "")
            if d == unitState.viewed then buttonWidget.text:SetTextColor(1, 0.82, 0) else buttonWidget.text:SetTextColor(1, 1, 1) end
        end
    end)
    picker:Hide()
end

-----------------------------------------------------------------------------
-- Resolve Marker
-----------------------------------------------------------------------------
function DungeonRouteWindow.resolveMarker(entryKey)
    local matchRef = markers[entryKey]
    if matchRef then return matchRef end
    matchRef = CreateFrame("Button", nil, overlay)
    matchRef:SetSize(16, 16)
    matchRef:SetFrameLevel(overlay:GetFrameLevel() + 4)
    matchRef.leader = overlay:CreateLine(nil, "ARTWORK")
    matchRef.leader:SetThickness(1)
    matchRef.leader:SetColorTexture(1, 1, 1, 0.65)
    matchRef.leader:Hide()
    matchRef.glow = DungeonRouteWindow.applyCircularMask(matchRef, "BACKGROUND", 26)
    matchRef.glow:SetVertexColor(1, 0.82, 0, 0.55)
    matchRef.glow:SetBlendMode("ADD")
    if matchRef.glow.CreateAnimationGroup then
        local agVal = matchRef.glow:CreateAnimationGroup()
        local a = agVal:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.7)
        agVal:SetLooping("BOUNCE")
        matchRef.pulse = agVal
    end
    matchRef.ring = DungeonRouteWindow.applyCircularMask(matchRef, "BORDER", 17)
    matchRef.circle = DungeonRouteWindow.applyCircularMask(matchRef, "ARTWORK", 14)
    matchRef.text = matchRef:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    matchRef.text:SetPoint("CENTER", 0, 0)
    matchRef.icon = matchRef:CreateTexture(nil, "OVERLAY")
    matchRef.icon:SetSize(11, 11); matchRef.icon:SetPoint("CENTER", 0, 0)
    matchRef.label = matchRef:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    matchRef.label:SetPoint("TOP", matchRef, "BOTTOM", 0, -3)
    matchRef.label:Hide()
    matchRef.badge = DungeonRouteWindow.applyCircularMask(matchRef, "OVERLAY", 8, 1)
    matchRef.badge:ClearAllPoints(); matchRef.badge:SetPoint("TOPRIGHT", 3, 3)
    matchRef.badge:SetVertexColor(1, 0.82, 0, 1)
    matchRef.badgeText = matchRef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    matchRef.badgeText:SetPoint("CENTER", matchRef.badge, "CENTER", 0, 0)
    matchRef.badgeText:SetText("!"); matchRef.badgeText:SetTextColor(0, 0, 0)
    matchRef.check = matchRef:CreateTexture(nil, "OVERLAY", nil, 3)
    matchRef.check:SetTexture(CHECK)
    matchRef.check:SetSize(12, 12)
    matchRef.check:SetPoint("BOTTOMRIGHT", 5, -4)
    matchRef:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    matchRef:SetScript("OnEnter", function(self) DungeonRouteWindow.stepTooltip(self, unitState.viewed, self.index) end)
    matchRef:SetScript("OnLeave", GameTooltip_Hide)
    matchRef:SetScript("OnClick", function(self, button) DungeonRouteWindow.stepClick(unitState.viewed, self.index, button) end)
    markers[entryKey] = matchRef
    return matchRef
end

function DungeonRouteWindow.resolveAlt(entryKey)
    local a = alts[entryKey]
    if a then return a end
    a = CreateFrame("Button", nil, overlay)
    a:SetSize(11, 11)
    a:SetFrameLevel(overlay:GetFrameLevel() + 2)
    a.ring = DungeonRouteWindow.applyCircularMask(a, "BORDER", 11)
    a.inner = DungeonRouteWindow.applyCircularMask(a, "ARTWORK", 8)
    a.inner:SetVertexColor(0, 0, 0, 0.3)
    a.text = a:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a.text:SetPoint("CENTER", 0, 0)
    a.icon = a:CreateTexture(nil, "OVERLAY")
    a.icon:SetSize(8, 8); a.icon:SetPoint("CENTER", 0, 0)
    a:SetAlpha(0.6)
    a:SetScript("OnEnter", function(self)
        DungeonRouteWindow.stepTooltip(self, unitState.viewed, self.index)
        GameTooltip:AddLine(L.LEG_ALT, 0.8, 0.8, 0.8); GameTooltip:Show()
    end)
    a:SetScript("OnLeave", GameTooltip_Hide)
    alts[entryKey] = a
    return a
end

local LINK_ICON = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
function DungeonRouteWindow.resolveLink(entryKey)
    local leftPos = links[entryKey]
    if leftPos then return leftPos end
    leftPos = CreateFrame("Button", nil, overlay)
    leftPos:SetSize(18, 18)
    leftPos:SetFrameLevel(overlay:GetFrameLevel() + 3)
    leftPos.leader = overlay:CreateLine(nil, "ARTWORK")
    leftPos.leader:SetThickness(1); leftPos.leader:SetColorTexture(0.45,0.8,1,0.65); leftPos.leader:Hide()
    leftPos.bg = DungeonRouteWindow.applyCircularMask(leftPos, "BACKGROUND", 18)
    leftPos.bg:SetVertexColor(0.05, 0.05, 0.08, 0.75)
    leftPos.tex = leftPos:CreateTexture(nil, "ARTWORK")
    leftPos.tex:SetSize(11, 11); leftPos.tex:SetPoint("BOTTOMRIGHT",4,-2)
    leftPos.tex:SetTexture(LINK_ICON)
    leftPos.number=leftPos:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    leftPos.number:SetPoint("CENTER");leftPos.number:SetTextColor(0.55,0.85,1)
    leftPos.name = leftPos:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    leftPos.name:SetPoint("TOP", leftPos, "BOTTOM", 0, -1)
    leftPos.name:SetTextColor(0.55, 0.85, 1)
    leftPos.nameBg = leftPos:CreateTexture(nil, "BORDER")
    leftPos.nameBg:SetColorTexture(0, 0, 0, 0.6)
    leftPos.nameBg:SetPoint("TOPLEFT", leftPos.name, "TOPLEFT", -3, 1)
    leftPos.nameBg:SetPoint("BOTTOMRIGHT", leftPos.name, "BOTTOMRIGHT", 3, -1)
    leftPos:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.label or "", 1, 1, 1, 1, true)
        if not self.name:IsShown() and (self.name:GetText() or "") ~= "" then GameTooltip:AddLine(self.name:GetText(), 0.55, 0.85, 1) end
        if self.approx then GameTooltip:AddLine(L.APPROX, 1, 0.75, 0.3, true) end
        if self.toPage then GameTooltip:AddLine(L.LINK_CLICK, 0.5, 0.8, 1) end
        GameTooltip:Show()
    end)
    leftPos:SetScript("OnLeave", GameTooltip_Hide)
    leftPos:SetScript("OnClick", function(self)
        if not self.toPage then return end
        DungeonRouteWindow.selectFloor(unitState.viewed, self.toPage)
        GameTooltip_Hide(); ns.RefreshMap()
    end)
    links[entryKey] = leftPos
    return leftPos
end

-----------------------------------------------------------------------------
-- List Scroll Bar
-----------------------------------------------------------------------------
function DungeonRouteWindow.listScrollBar()
    return listScroll and (listScroll.ScrollBar or _G.EzWoW_DungeonRouteGuideListScrollScrollBar)
end

function DungeonRouteWindow.assignListOffset(offset)
    local maximum = listScroll.maxOffset or 0
    offset = math.max(0, math.min(maximum, offset or 0))
    listScroll:SetVerticalScroll(offset)
    local statusBar = DungeonRouteWindow.listScrollBar()
    if statusBar and statusBar.SetValue then statusBar:SetValue(offset) end
    if listScrollKey then listOffsets[listScrollKey] = offset end
end

function DungeonRouteWindow.listWheel(_, delta)
    DungeonRouteWindow.assignListOffset((listOffsets[listScrollKey] or 0) - delta * 36)
end

function DungeonRouteWindow.beginList(d, tab)
    listScrollKey = d.key .. ":" .. tab
    listRestoreOffset = listOffsets[listScrollKey] or 0
end

function DungeonRouteWindow.finishList(height)
    local viewport = DungeonRouteWindow.getSafeFrameHeight(listScroll, 300)
    listContent:SetHeight(math.max(viewport, height))
    listScroll.maxOffset = math.max(0, height - viewport)
    if listScroll.UpdateScrollChildRect then listScroll:UpdateScrollChildRect() end
    local statusBar = DungeonRouteWindow.listScrollBar()
    if statusBar then
        if statusBar.SetMinMaxValues then statusBar:SetMinMaxValues(0, listScroll.maxOffset) end
        statusBar:SetShown(listScroll.maxOffset > 0)
    end
    DungeonRouteWindow.assignListOffset(listRestoreOffset or 0)
end

function DungeonRouteWindow.resolveTextHeight(labelRegion, text, width)
    labelRegion:SetWidth(width)
    labelRegion:SetHeight(0)
    labelRegion:SetText(text)
    local height = math.max(12, math.ceil(DungeonRouteWindow.getSafeStringHeight(labelRegion, 12)))
    labelRegion:SetHeight(height)
    return height
end

function DungeonRouteWindow.resolveRow(entryKey)
    local rowEntry = rowWidgets[entryKey]
    if rowEntry then return rowEntry end
    rowEntry = CreateFrame("Button", nil, listContent)
    rowEntry:SetSize(LIST_CONTENT_W, 17)
    rowEntry:EnableMouseWheel(true)
    rowEntry:SetScript("OnMouseWheel", DungeonRouteWindow.listWheel)
    rowEntry.hl = rowEntry:CreateTexture(nil, "HIGHLIGHT"); rowEntry.hl:SetAllPoints(); rowEntry.hl:SetColorTexture(1, 1, 1, 0.08)
    rowEntry.bg = rowEntry:CreateTexture(nil, "BACKGROUND"); rowEntry.bg:SetAllPoints(); rowEntry.bg:SetColorTexture(1, 0.82, 0, 0.12)
    rowEntry.dot = DungeonRouteWindow.applyCircularMask(rowEntry, "ARTWORK", 8)
    
    rowEntry.dot:ClearAllPoints(); rowEntry.dot:SetPoint("TOPLEFT", 4, -4)
    rowEntry.check = rowEntry:CreateTexture(nil, "OVERLAY")
    rowEntry.check:SetTexture(CHECK); rowEntry.check:SetSize(14, 14); rowEntry.check:SetPoint("TOPLEFT", 1, -1)
    rowEntry.num = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rowEntry.num:SetPoint("TOPLEFT", 14, -2); rowEntry.num:SetSize(18, 12); rowEntry.num:SetJustifyH("RIGHT")
    rowEntry.kicon = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.kicon:SetSize(13, 13); rowEntry.kicon:SetPoint("TOPLEFT", 20, -1.5)
    rowEntry.tag = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rowEntry.tag:SetPoint("TOPRIGHT", -2, -2)
    rowEntry.tag:SetHeight(12)
    rowEntry.name = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rowEntry.name:SetPoint("TOPLEFT", 37, -2)
    rowEntry.name:SetJustifyH("LEFT")
    if rowEntry.name.SetWordWrap then rowEntry.name:SetWordWrap(true) end
    rowEntry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rowEntry:SetScript("OnEnter", function(self)
        if self.group then
            local greenVal = unitState.viewed.trashGroups[self.group]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(translationHelper(greenVal.name), 1, 0.82, 0)
            GameTooltip:AddLine(L.TRASH_ROW_TIP, 1, 1, 1, true)
            GameTooltip:Show()
        else
            DungeonRouteWindow.stepTooltip(self, unitState.viewed, self.index)
        end
    end)
    rowEntry:SetScript("OnLeave", GameTooltip_Hide)
    rowEntry:SetScript("OnClick", function(self, button)
        if self.group then
            
            unitState.selected = nil
            unitState.cardTrash = (unitState.cardTrash == self.group) and nil or self.group
            ns.RefreshMap()
        else
            DungeonRouteWindow.stepClick(unitState.viewed, self.index, button)
        end
    end)
    rowWidgets[entryKey] = rowEntry
    return rowEntry
end

function DungeonRouteWindow.locateQuestSteps(d, qid)
    if not d or not qid then return nil, nil end
    local firstIdx, names = nil, {}
    for index, step in ipairs(d.steps or {}) do
        for _, entityID in ipairs(step.quests or {}) do
            if entityID == qid then
                if not firstIdx then firstIdx = index end
                names[#names + 1] = ns.ResolveRouteStepDisplayTitle(d, index)
                break
            end
        end
    end
    return firstIdx, (#names > 0 and table.concat(names, ", ") or nil)
end

function DungeonRouteWindow.launchQuestInMapFinder(priorityQueue)
    if not priorityQueue then return end
    local qName = (priorityQueue.name and (translationHelper(priorityQueue.name) or priorityQueue.name.ko or priorityQueue.name.en)) or ns.QuestTitle(priorityQueue)
    if not qName or qName == "" then return end
    if WorldMapFrame and not WorldMapFrame:IsShown() then
        if ToggleWorldMap then
            pcall(ToggleWorldMap)
        else
            pcall(ShowUIPanel, WorldMapFrame)
        end
    end
    if _G.SlashCmdList and type(_G.SlashCmdList.EZWOWMAPFINDER) == "function" then
        pcall(_G.SlashCmdList.EZWOWMAPFINDER, "Q " .. qName)
    end
end

function DungeonRouteWindow.resolveQuestRow(entryKey)
    local rowEntry = qrows[entryKey]
    if rowEntry then return rowEntry end
    rowEntry = CreateFrame("Button", nil, listContent)
    rowEntry:SetSize(LIST_CONTENT_W, 30)
    rowEntry:EnableMouse(true)
    rowEntry:EnableMouseWheel(true)
    rowEntry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rowEntry:SetScript("OnMouseWheel", DungeonRouteWindow.listWheel)
    rowEntry.hl = rowEntry:CreateTexture(nil, "HIGHLIGHT")
    rowEntry.hl:SetAllPoints()
    rowEntry.hl:SetColorTexture(1, 1, 1, 0.08)
    rowEntry.name = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rowEntry.name:SetPoint("TOPLEFT", 2, 0)
    rowEntry.name:SetJustifyH("LEFT")
    if rowEntry.name.SetWordWrap then rowEntry.name:SetWordWrap(true) end
    rowEntry.status = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rowEntry.status:SetPoint("TOPRIGHT", -2, 0)
    rowEntry.giver = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rowEntry.giver:SetPoint("TOPLEFT", rowEntry.name, "BOTTOMLEFT", 6, -2)
    rowEntry.giver:SetJustifyH("LEFT")
    if rowEntry.giver.SetWordWrap then rowEntry.giver:SetWordWrap(true) end
    rowEntry:SetScript("OnEnter", function(self)
        if not self.q then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.QuestTitle(self.q), 1, 0.82, 0)
        if self.q.level then GameTooltip:AddLine(("Lv %d"):format(self.q.level), 0.7, 0.7, 0.7) end
        if self.q.minLevel then
            local low = (ns.CoerceSafeNumber(ns.UnwrapSafeValue(UnitLevel, "player")) or 0) < self.q.minLevel
            GameTooltip:AddLine(L.Q_MINLEVEL_TIP:format(self.q.minLevel), low and 1 or 0.7, low and 0.4 or 0.7, low and 0.4 or 0.7)
        end
        GameTooltip:AddLine(translationHelper(self.q.giver), 1, 1, 1, true)
        local stepIdx, stepNames = DungeonRouteWindow.locateQuestSteps(unitState.viewed, self.q.id)
        if stepNames then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.Q_TARGET_STEPS:format(stepNames), 0.95, 0.78, 0.35, true)
        end
        if self.q.rewards and #self.q.rewards > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L.Q_REWARDS, 1, 0.82, 0)
            for _, reward in ipairs(self.q.rewards) do
                local displayName, _, quality, iconTex = ns.ItemInfo(reward.id)
                displayName = displayName or translationHelper(reward.name)
                local textureRegion = iconTex and ("|T" .. iconTex .. ":14:14|t ") or ""
                GameTooltip:AddLine(textureRegion .. ns.QualityHex(quality) .. displayName .. "|r")
            end
        end
        local containsStep = stepIdx ~= nil
        local containsEMF = _G.SlashCmdList and type(_G.SlashCmdList.EZWOWMAPFINDER) == "function"
        if containsStep or containsEMF then
            GameTooltip:AddLine(" ")
            if containsStep then
                GameTooltip:AddLine(L.Q_CLICK_STEP, 0.5, 0.8, 1, true)
            end
            if containsEMF then
                GameTooltip:AddLine(L.Q_CLICK_MAP, 0.294, 0.784, 0.910, true)
            end
        end
        GameTooltip:Show()
    end)
    rowEntry:SetScript("OnLeave", GameTooltip_Hide)
    rowEntry:SetScript("OnClick", function(self, button)
        if not self.q then return end
        if button == "RightButton" then
            DungeonRouteWindow.launchQuestInMapFinder(self.q)
            return
        end
        local stepIdx = DungeonRouteWindow.locateQuestSteps(unitState.viewed, self.q.id)
        if stepIdx then
            unitState.selected = stepIdx
            unitState.cardTrash = nil
            local pgVal, coordPos = DungeonRouteWindow.stepGeo(unitState.viewed, stepIdx)
            if pgVal then unitState.page, unitState.pageManual = pgVal, true end
            local nodeEntry = pgVal and navigation[unitState.viewed.key .. "/" .. pgVal]
            if nodeEntry and coordPos then nodeEntry.x, nodeEntry.y = coordPos[1], coordPos[2] end
            ns.RefreshMap()
        else
            DungeonRouteWindow.launchQuestInMapFinder(self.q)
        end
    end)
    qrows[entryKey] = rowEntry
    return rowEntry
end

function DungeonRouteWindow.resolveQuestStatus(entityID)
    if ns.IsTruthySafeValue(ns.UnwrapSafeValue(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, entityID))
        or ns.IsTruthySafeValue(ns.UnwrapSafeValue(IsQuestFlaggedCompleted, entityID)) then return "done" end
    if ns.IsTruthySafeValue(ns.UnwrapSafeValue(C_QuestLog and C_QuestLog.IsOnQuest, entityID)) then return "active" end
    return "missing"
end
ns.QuestStatus = DungeonRouteWindow.resolveQuestStatus

function DungeonRouteWindow.assignTab(tab) ns.db.listTab = tab; ns.RefreshMap() end

-----------------------------------------------------------------------------
-- Persist Position
-----------------------------------------------------------------------------
function DungeonRouteWindow.persistPosition()
    local p, _, relativePoint, coordX, coordY = containerFrame:GetPoint(1)
    ns.db.frames.map = { p, relativePoint, coordX, coordY }
    if cardLayout and cardLayout:IsShown() then anchorCard() end
end

function DungeonRouteWindow.layoutWindowRegions()
    local StyleService = ns.db.mapSize
    local d = unitState.viewed
    local entryValue = DungeonRouteWindow.viewOf(d and DungeonRouteWindow.resolveCurrentPage(d))
    local CW = math.floor(StyleService * entryValue[3] / entryValue[4] + 0.5)
    local w = math.max(360, PAD + CW + PAD + (ns.db.showList and LISTW or 0))
    local headerBar = HEADER + StyleService + LEGEND_H + FOOT_H + 8
    containerFrame:SetSize(w, headerBar)
    canvasFrame:SetSize(CW, StyleService)
    legend:ClearAllPoints()
    legend:SetPoint("TOPLEFT", canvasFrame, "BOTTOMLEFT", 0, -3)
    itemList:SetShown(ns.db.showList)
    itemList:SetHeight(StyleService + LEGEND_H)
    listScroll:SetHeight(StyleService + LEGEND_H - 26)
end

local legendItems = {}
function DungeonRouteWindow.layoutLegend()
    local coordX = 0
    for _, itVal in ipairs(legendItems) do
        itVal.dot:ClearAllPoints(); itVal.dot:SetPoint("LEFT", coordX, 0)
        itVal.fs:ClearAllPoints(); itVal.fs:SetPoint("LEFT", coordX + 12, 0)
        itVal.fs:SetText(L["LEG_" .. itVal.key:upper()])
        coordX = coordX + 16 + DungeonRouteWindow.getSafeStringWidth(itVal.fs, 40) + 10
    end
end

function DungeonRouteWindow.buildLegend()
    legend = CreateFrame("Frame", nil, containerFrame)
    legend:SetSize(400, LEGEND_H)
    for _, lookupKey in ipairs({ "entrance", "boss", "rare", "npc", "quest" }) do
        local dot = DungeonRouteWindow.applyCircularMask(legend, "ARTWORK", 9)
        dot:SetVertexColor(CAT[lookupKey][1], CAT[lookupKey][2], CAT[lookupKey][3], 1)
        local labelRegion = legend:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        legendItems[#legendItems + 1] = { key = lookupKey, dot = dot, fs = labelRegion }
    end
    DungeonRouteWindow.layoutLegend()
end

function ns.OnLanguageChanged()
    for _, buttonWidget in ipairs(fitBtns) do DungeonRouteWindow.fitButtonWidthToLabel(buttonWidget) end
    if legend then DungeonRouteWindow.layoutLegend() end
    if ns.RefreshAll then ns.RefreshAll() end
end

-----------------------------------------------------------------------------
-- Resolve Page Name
-----------------------------------------------------------------------------
function DungeonRouteWindow.resolvePageName(p, entryKey) return p.name and translationHelper(p.name) or L.PAGE:format(entryKey) end

function DungeonRouteWindow.resolveDarkBackdrop(f, a)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.114, 0.157, 0.192, a or 0.92)
    f:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.90)
end

local plotFloors

function buildFloorPicker()
    floorBtn = CreateFrame("Button", nil, overlay, "BackdropTemplate")
    floorBtn:SetFrameLevel(overlay:GetFrameLevel() + 15)
    floorBtn:SetPoint("TOPLEFT", canvasFrame, "TOPLEFT", 4, -4)
    floorBtn:SetSize(160, 20)
    floorBtn:EnableMouse(true)
    floorBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    DungeonRouteWindow.resolveDarkBackdrop(floorBtn, 0.88)
    local arrow = floorBtn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetSize(14, 14); arrow:SetPoint("RIGHT", -4, -2)
    floorBtn.text = floorBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    floorBtn.text:SetPoint("LEFT", 6, 0)
    if floorBtn.text.SetWordWrap then floorBtn.text:SetWordWrap(false) end
    local hlVal = floorBtn:CreateTexture(nil, "HIGHLIGHT"); hlVal:SetAllPoints(); hlVal:SetColorTexture(1, 1, 1, 0.08)
    floorBtn:SetScript("OnClick", function()
        if menu then menu:Hide() end
        picker:Hide()
        floorList:SetShown(not floorList:IsShown())
    end)
    floorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.AREA_TIP:format(self.count or 0), 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    floorBtn:SetScript("OnLeave", GameTooltip_Hide)

    floorNext = CreateFrame("Button", nil, overlay, "BackdropTemplate")
    floorNext:SetFrameLevel(overlay:GetFrameLevel() + 15)
    floorNext:SetPoint("TOPLEFT", floorBtn, "BOTTOMLEFT", 0, -2)
    floorNext:SetSize(160, 16)
    floorNext:EnableMouse(true)
    floorNext:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    DungeonRouteWindow.resolveDarkBackdrop(floorNext, 0.85)
    if floorNext.SetBackdropBorderColor then floorNext:SetBackdropBorderColor(0.918, 0.514, 0.494, 0.85) end
    floorNext.text = floorNext:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    floorNext.text:SetPoint("LEFT", 5, 0)
    if floorNext.text.SetWordWrap then floorNext.text:SetWordWrap(false) end
    local nhl = floorNext:CreateTexture(nil, "HIGHLIGHT"); nhl:SetAllPoints(); nhl:SetColorTexture(0.918, 0.514, 0.494, 0.14)
    floorNext:SetScript("OnClick", function(self)
        DungeonRouteWindow.selectFloor(unitState.viewed, self.key)
        floorList:Hide(); ns.RefreshMap()
    end)

    floorList = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
    DungeonRouteWindow.applyPanelBackdrop(floorList, 0.97)
    floorList:SetFrameStrata("FULLSCREEN_DIALOG")
    floorList:SetFrameLevel(containerFrame:GetFrameLevel() + 40)
    floorList:SetPoint("TOPLEFT", floorBtn, "BOTTOMLEFT", 0, -2)
    floorList:SetSize(220, 6 * 20 + 8)
    for entryKey = 1, 6 do
        local rowEntry = CreateFrame("Button", nil, floorList)
        rowEntry:SetSize(208, 20)
        rowEntry:SetPoint("TOPLEFT", 6, -4 - (entryKey - 1) * 20)
        local rhl = rowEntry:CreateTexture(nil, "HIGHLIGHT"); rhl:SetAllPoints(); rhl:SetColorTexture(1, 1, 1, 0.1)
        rowEntry.text = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rowEntry.text:SetPoint("LEFT", 4, 0)
        rowEntry.text:SetJustifyH("LEFT")
        if rowEntry.text.SetWordWrap then rowEntry.text:SetWordWrap(false) end
        rowEntry.tag = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        rowEntry.tag:SetPoint("RIGHT", -4, 0)
        rowEntry:SetScript("OnClick", function(self)
            DungeonRouteWindow.selectFloor(unitState.viewed, self.key)
            floorList:Hide(); ns.RefreshMap()
        end)
        floorRows[entryKey] = rowEntry
    end
    floorList:SetScript("OnShow", function()
        floorNext:Hide()
        if unitState.viewed then plotFloors(unitState.viewed, DungeonRouteWindow.resolveCurrentPage(unitState.viewed)) end
    end)
    floorList:SetScript("OnHide", function()
        if floorNext.hasNext then floorNext:Show() end
    end)
    floorList:Hide()
    floorBtn:Hide(); floorNext:Hide()
end

function DungeonRouteWindow.resolveFloorRow(entryKey)
    return floorRows[entryKey]
end

function DungeonRouteWindow.resolveFloorInfo(d)
    local left, nextPage = {}, nil
    local niVal = ns.ResolveNextIncompleteStep(d)
    for index, step in ipairs(d.steps) do
        local pgVal = DungeonRouteWindow.stepGeo(d, index)
        if pgVal and ns.IsPrimaryRouteStep(step) and not ns.IsRouteStepCompleted(d, index) then left[pgVal] = (left[pgVal] or 0) + 1 end
        if index == niVal then nextPage = pgVal end
    end
    return left, nextPage
end

plotFloors = function(d, page)
    local pages = DungeonRouteWindow.resolveDungeonFloorGeometry(d).pages or {}
    if #pages < 2 or not page then
        floorNext.hasNext = false
        floorBtn:Hide(); floorNext:Hide(); floorList:Hide()
        return
    end
    if floorList.d ~= d then floorList:Hide(); floorList.d = d end
    local left, nextPage = DungeonRouteWindow.resolveFloorInfo(d)
    local entryIndex, nextName = 1, nil
    for entryKey, p in ipairs(pages) do
        if p == page then entryIndex = entryKey end
        if p.key == nextPage then nextName = DungeonRouteWindow.resolvePageName(p, entryKey) end
    end
    local cwVal = math.floor(ns.db.mapSize * view[3] / view[4] + 0.5)
    floorBtn.count = #pages
    floorBtn.text:SetText(("|cffea837e%s|r  %s"):format(L.AREA:format(entryIndex, #pages), DungeonRouteWindow.resolvePageName(page, entryIndex)))
    local btnW = math.max(130, math.min(cwVal - 8, math.floor(DungeonRouteWindow.getSafeStringWidth(floorBtn.text, 110) + 30)))
    floorBtn:SetWidth(btnW)
    floorBtn:SetFrameLevel(overlay:GetFrameLevel() + 15)
    floorBtn:Show()
    if nextName and nextPage ~= page.key then
        floorNext.hasNext = true
        floorNext.key = nextPage
        floorNext.text:SetText(L.NEXT_AREA:format(nextName))
        floorNext:SetWidth(math.max(110, math.min(cwVal - 8, math.floor(DungeonRouteWindow.getSafeStringWidth(floorNext.text, 100) + 12))))
        floorNext:SetFrameLevel(overlay:GetFrameLevel() + 15)
        floorNext:SetShown(not floorList:IsShown())
    else
        floorNext.hasNext = false
        floorNext:Hide()
    end
    local w = math.max(220, btnW)
    floorList:SetSize(w, #pages * 20 + 8)
    for entryKey, p in ipairs(pages) do
        local rowEntry = DungeonRouteWindow.resolveFloorRow(entryKey)
        if rowEntry then
            rowEntry.key = p.key
            rowEntry:SetWidth(w - 12)
            rowEntry.text:SetText((p == page and "|cff55ff55> |r" or "") .. entryKey .. ". " .. DungeonRouteWindow.resolvePageName(p, entryKey))
            if p == page then rowEntry.text:SetTextColor(1, 0.82, 0) else rowEntry.text:SetTextColor(1, 1, 1) end
            local tag = {}
            if p.key == nextPage then tag[#tag + 1] = "|cffea837e" .. L.AREA_NEXT .. "|r" end
            if left[p.key] then tag[#tag + 1] = L.AREA_LEFT:format(left[p.key]) end
            rowEntry.tag:SetText(table.concat(tag, " · "))
            rowEntry:Show()
        end
    end
    for subIndex = #pages + 1, #floorRows do floorRows[subIndex]:Hide() end
end

function ns.ResolveFloorEncounterWidgets() return floorBtn, floorNext, floorList, floorRows end

function DungeonRouteWindow.createPrimaryWidget()
    containerFrame = CreateFrame("Frame", "EzWoW_DungeonRouteGuideFrame", UIParent, "BackdropTemplate")
    DungeonRouteWindow.applyPanelBackdrop(containerFrame)
    containerFrame:SetFrameStrata("MEDIUM")
    containerFrame:SetClampedToScreen(true)
    containerFrame:SetMovable(true)
    containerFrame:EnableMouse(true)
    containerFrame:RegisterForDrag("LeftButton")
    containerFrame:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    containerFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); DungeonRouteWindow.persistPosition() end)
    local coordPos = ns.db.frames.map
    if coordPos then containerFrame:SetPoint(coordPos[1], UIParent, coordPos[2], coordPos[3], coordPos[4]) else containerFrame:SetPoint("CENTER", 200, 40) end

    local close = DungeonRouteWindow.createStyledButton(containerFrame, "X", 22, nil, function() containerFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -PAD, -4)
    local menuBtn = DungeonRouteWindow.createStyledButton(containerFrame, L.BTN_MENU, 44, function() return L.BTN_MENU .. " (/ezdg config)" end, function()
        if picker then picker:Hide() end
        if floorList then floorList:Hide() end
        ns.ToggleConfig()
    end)
    menuBtn:SetPoint("RIGHT", close, "LEFT", -2, 0)
    local listBtn = DungeonRouteWindow.createStyledButton(containerFrame, L.BTN_LIST, 40, nil, function() ns.db.showList = not ns.db.showList; DungeonRouteWindow.layoutWindowRegions(); ns.RefreshMap() end)
    listBtn:SetPoint("RIGHT", menuBtn, "LEFT", -2, 0)
    
    currentBtn = DungeonRouteWindow.createStyledButton(containerFrame, L.BTN_CURRENT, 64, function() return L.TIP_CURRENT end, function()
        if unitState.current then
            unitState.viewed, unitState.selected, unitState.pageManual = unitState.current, nil, false
            picker:Hide(); ns.RefreshMap()
        end
    end)
    currentBtn:SetPoint("RIGHT", listBtn, "LEFT", -6, 0)
    ns.GetLocalizedEntryField(menuBtn, "BTN_MENU"); ns.GetLocalizedEntryField(listBtn, "BTN_LIST"); ns.GetLocalizedEntryField(currentBtn, "BTN_CURRENT")
    DungeonRouteWindow.shrinkFontStringToFit(menuBtn, 40); DungeonRouteWindow.shrinkFontStringToFit(listBtn, 36); DungeonRouteWindow.shrinkFontStringToFit(currentBtn, 52)
    
    local titleBtn = CreateFrame("Button", nil, containerFrame, "BackdropTemplate")
    dropdown = titleBtn
    titleBtn:SetPoint("TOPLEFT", PAD, -4)
    titleBtn:SetPoint("RIGHT", currentBtn, "LEFT", -6, 0)
    titleBtn:SetHeight(20)
    if titleBtn.SetBackdrop then
        titleBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        titleBtn:SetBackdropColor(0.114, 0.157, 0.192, 0.94)
        titleBtn:SetBackdropBorderColor(0.918, 0.514, 0.494, 0.90)
    end
    local arrow = titleBtn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetSize(14, 14)
    arrow:SetPoint("RIGHT", -4, -2)
    local thl = titleBtn:CreateTexture(nil, "HIGHLIGHT"); thl:SetAllPoints(); thl:SetColorTexture(1, 1, 1, 0.08)
    titleStr = titleBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleStr:SetPoint("LEFT", 6, 0)
    titleStr:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    titleStr:SetJustifyH("LEFT")
    if titleStr.SetWordWrap then titleStr:SetWordWrap(false) end
    titleBtn:SetScript("OnClick", function() if menu then menu:Hide() end; floorList:Hide(); picker:SetShown(not picker:IsShown()) end)
    titleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.PICK_DUNGEON, 1, 1, 1); GameTooltip:Show()
    end)
    titleBtn:SetScript("OnLeave", GameTooltip_Hide)

    canvasFrame = CreateFrame("Frame", nil, containerFrame)
    canvasFrame:SetPoint("TOPLEFT", PAD, -HEADER)
    local backdropTex = canvasFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdropTex:SetAllPoints(); backdropTex:SetColorTexture(0, 0, 0, 0.5)
    mapTex = canvasFrame:CreateTexture(nil, "BACKGROUND")
    mapTex:SetAllPoints()
    for entryKey = 1, 12 do tiles[entryKey] = canvasFrame:CreateTexture(nil, "BACKGROUND") end
    noMapText = canvasFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    noMapText:SetPoint("CENTER"); ns.GetLocalizedEntryField(noMapText, "NO_MAP")
    overlay = CreateFrame("Frame", nil, canvasFrame)
    overlay:SetAllPoints()
    if overlay.SetClipsChildren then overlay:SetClipsChildren(true) end
    overlay:SetFrameLevel(canvasFrame:GetFrameLevel() + 2)
    orientationBadge = CreateFrame("Button", nil, overlay)
    orientationBadge:SetSize(120, 36)
    orientationBadge:SetPoint("TOPRIGHT", -6, -27)
    orientationBadge.text = orientationBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    orientationBadge.text:SetPoint("TOPRIGHT")
    orientationBadge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.northUp and L.MAP_NORTH_TIP or L.MAP_GUIDE_TIP, 1, 1, 1, 1, true)
        if self.partial then GameTooltip:AddLine(L.PARTIAL_MINIMAP, 1, 0.7, 0.3, true) end
        if self.supplementalNative then GameTooltip:AddLine(L.MAP_CLASSIC_SUPPLEMENT, 1, 0.8, 0.4, true) end
        GameTooltip:Show()
    end)
    orientationBadge:SetScript("OnLeave", GameTooltip_Hide)

    canvasFrame:EnableMouse(true)
    canvasFrame:EnableMouseWheel(true)
    canvasFrame:SetScript("OnMouseWheel", function(_, delta) DungeonRouteWindow.zoomMap(delta) end)
    canvasFrame:RegisterForDrag("LeftButton")
    canvasFrame:SetScript("OnDragStart", function(self)
        if nav and nav.zoom > 1 and not unitState.edit then
            local coordX, coordY = GetCursorPosition()
            self.pan = {coordX, coordY, nav.x, nav.y, DungeonRouteWindow.calculateCanvasScale(), self:GetEffectiveScale()}
            self:SetScript("OnUpdate", function(themeColor)
                local cxVal, cyVal = GetCursorPosition(); local p = themeColor.pan
                if not p or not nav then return end
                if cxVal == p[7] and cyVal == p[8] then return end     
                p[7], p[8] = cxVal, cyVal
                nav.x = p[3] - (cxVal-p[1])/p[6]/p[5]
                nav.y = p[4] + (cyVal-p[2])/p[6]/p[5]
                ns.RefreshMap(true)
            end)
        elseif not ns.db.locked then containerFrame:StartMoving() end
        self.dragged = true
    end)
    canvasFrame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil); self.pan = nil
        containerFrame:StopMovingOrSizing(); DungeonRouteWindow.persistPosition()
    end)
    canvasFrame:SetScript("OnMouseDown", function(self) self.dragged = false end)
    canvasFrame:SetScript("OnMouseUp", function(self, button) if not self.dragged then ns.HandleRouteCanvasEditClick(button) end end)
    canvasFrame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil); self.pan=nil end)
    zoomReset = DungeonRouteWindow.createStyledButton(overlay, L.MAP_FIT, 46, L.MAP_ZOOM_TIP, function()
        if nav then nav.zoom=1; ns.RefreshMap(true) end
    end)
    zoomReset:SetPoint("BOTTOMRIGHT", -4, 4)
    zoomReset:SetFrameLevel(overlay:GetFrameLevel()+8)

    entranceMark = CreateFrame("Frame", nil, overlay)
    entranceMark:SetSize(15, 15)
    entranceMark:SetFrameLevel(overlay:GetFrameLevel() + 3)
    local ering = DungeonRouteWindow.applyCircularMask(entranceMark, "BORDER", 15)
    ering:SetVertexColor(CAT.entrance[1], CAT.entrance[2], CAT.entrance[3], 1)
    local einner = DungeonRouteWindow.applyCircularMask(entranceMark, "ARTWORK", 9)
    einner:SetVertexColor(0.05, 0.15, 0.05, 0.5)
    entranceMark.text = entranceMark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    entranceMark.text:SetPoint("TOP", entranceMark, "BOTTOM", 0, -1)
    ns.GetLocalizedEntryField(entranceMark.text, "LEG_ENTRANCE")
    entranceMark.text:SetTextColor(CAT.entrance[1], CAT.entrance[2], CAT.entrance[3])

    buildFloorPicker()

    DungeonRouteWindow.buildLegend()
    footerRegion = containerFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footerRegion:SetPoint("BOTTOMLEFT", PAD, 4)
    footerRegion:SetPoint("BOTTOMRIGHT", -PAD, 4)
    footerRegion:SetJustifyH("LEFT")
    if footerRegion.SetWordWrap then footerRegion:SetWordWrap(false) end

    itemList = CreateFrame("Frame", nil, containerFrame)
    itemList:SetPoint("TOPLEFT", canvasFrame, "TOPRIGHT", PAD, 0)
    itemList:SetWidth(LISTW - PAD)
    tabRoute = DungeonRouteWindow.createStyledButton(itemList, L.TAB_ROUTE, 54, nil, function() DungeonRouteWindow.assignTab("route") end)
    tabRoute:SetPoint("TOPLEFT", 0, 0)
    tabQuest = DungeonRouteWindow.createStyledButton(itemList, L.TAB_QUEST, 58, nil, function() DungeonRouteWindow.assignTab("quest") end)
    tabQuest:SetPoint("LEFT", tabRoute, "RIGHT", 2, 0)
    tabNotes = DungeonRouteWindow.createStyledButton(itemList, L.TAB_NOTES, 50, nil, function() DungeonRouteWindow.assignTab("notes") end)
    tabNotes:SetPoint("LEFT", tabQuest, "RIGHT", 2, 0)
    ns.GetLocalizedEntryField(tabRoute, "TAB_ROUTE"); ns.GetLocalizedEntryField(tabQuest, "TAB_QUEST"); ns.GetLocalizedEntryField(tabNotes, "TAB_NOTES")
    DungeonRouteWindow.shrinkFontStringToFit(tabRoute, 40); DungeonRouteWindow.shrinkFontStringToFit(tabQuest, 40); DungeonRouteWindow.shrinkFontStringToFit(tabNotes, 36)
    progressText = itemList:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    progressText:SetPoint("TOPRIGHT", -4, -4)
    listScroll = CreateFrame("ScrollFrame", "EzWoW_DungeonRouteGuideListScroll", itemList, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 0, -26)
    listScroll:SetWidth(LIST_CONTENT_W)
    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(LIST_CONTENT_W, 1)
    listScroll:SetScrollChild(listContent)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", DungeonRouteWindow.listWheel)
    listScroll:HookScript("OnVerticalScroll", function(_, offset)
        if listScrollKey then listOffsets[listScrollKey] = offset end
    end)
    tipText = listContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tipText:SetJustifyH("LEFT"); tipText:SetJustifyV("TOP")
    tipText:SetWidth(LIST_CONTENT_W - 8)
    if tipText.SetWordWrap then tipText:SetWordWrap(true) end
    
    lootBar = CreateFrame("Frame", nil, listContent)
    lootBar:SetSize(LIST_CONTENT_W, 62)
    lootLabel = lootBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    lootLabel:SetPoint("TOPLEFT", 4, 0)
    lootBar:EnableMouseWheel(true)
    lootBar:SetScript("OnMouseWheel", DungeonRouteWindow.listWheel)
    questNote = listContent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    questNote:SetJustifyH("LEFT"); questNote:SetJustifyV("TOP")
    questNote:SetWidth(LIST_CONTENT_W - 8)
    if questNote.SetWordWrap then questNote:SetWordWrap(true) end

    DungeonRouteWindow.buildPicker()
    buildCard()
    containerFrame:SetScript("OnHide", function()
        if picker then picker:Hide() end
        if floorList then floorList:Hide() end
    end)
    DungeonRouteWindow.layoutWindowRegions()
    ns.ApplyAlpha()
end

-----------------------------------------------------------------------------
-- Resolve Loot On Enter
-----------------------------------------------------------------------------
function DungeonRouteWindow.resolveLootOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.id) then
        GameTooltip:SetHyperlink("item:" .. self.id)
    end
    if self.from == "world" then
        GameTooltip:AddLine(L.SRC_WORLD, 0.75, 0.75, 0.75, true)
    elseif type(self.from) == "table" then
        GameTooltip:AddLine(L.SRC_FROM, 1, 0.82, 0)
        for _, stateFlag in ipairs(self.from) do
            GameTooltip:AddDoubleLine(translationHelper(stateFlag.n), ("%.1f%%"):format(stateFlag.r), 1, 1, 1, 0.75, 0.75, 0.75)
        end
    end
    GameTooltip:AddLine(L.LOOT_HINT, 0.5, 0.8, 1)
    GameTooltip:Show()
end

function DungeonRouteWindow.resolveSourceText(from)
    if from == "world" then return L.SRC_WORLD end
    if type(from) ~= "table" or not from[1] then return nil end
    local stateFlag = ("%s %.1f%%"):format(translationHelper(from[1].n), from[1].r)
    if #from > 1 then stateFlag = stateFlag .. " " .. L.SRC_MORE:format(#from - 1) end
    return stateFlag
end

function DungeonRouteWindow.resolveLootOnClick(self)
    local _, link = ns.ItemInfo(self.id)
    if link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
    elseif link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

function DungeonRouteWindow.resolveQualityBorder(resolvedValue, priorityQueue)
    local themeColor = priorityQueue and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[priorityQueue]
    if themeColor then resolvedValue:SetColorTexture(themeColor.r, themeColor.g, themeColor.b, 0.9) else resolvedValue:SetColorTexture(0, 0, 0, 0) end
end

local cardRows = {}
local MODEL_H = 170

function DungeonRouteWindow.resolveCardRow(entryKey)
    local rowEntry = cardRows[entryKey]
    if rowEntry then return rowEntry end
    rowEntry = CreateFrame("Button", nil, cardLayout.content)
    rowEntry:SetSize(CARD_W - 40, 20)
    rowEntry.icon = rowEntry:CreateTexture(nil, "ARTWORK")
    rowEntry.icon:SetSize(18, 18); rowEntry.icon:SetPoint("LEFT", 1, 0)
    rowEntry.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    rowEntry.border = rowEntry:CreateTexture(nil, "BACKGROUND")
    rowEntry.border:SetPoint("TOPLEFT", rowEntry.icon, "TOPLEFT", -1, 1); rowEntry.border:SetPoint("BOTTOMRIGHT", rowEntry.icon, "BOTTOMRIGHT", 1, -1)
    rowEntry.name = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rowEntry.name:SetPoint("LEFT", rowEntry.icon, "RIGHT", 5, 0); rowEntry.name:SetPoint("RIGHT", -2, 0)
    rowEntry.name:SetJustifyH("LEFT")
    if rowEntry.name.SetWordWrap then rowEntry.name:SetWordWrap(false) end
    rowEntry.src = rowEntry:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rowEntry.src:SetPoint("TOPLEFT", rowEntry.name, "BOTTOMLEFT", 0, -1); rowEntry.src:SetPoint("RIGHT", -2, 0)
    rowEntry.src:SetJustifyH("LEFT")
    if rowEntry.src.SetWordWrap then rowEntry.src:SetWordWrap(false) end
    local hlVal = rowEntry:CreateTexture(nil, "HIGHLIGHT"); hlVal:SetAllPoints(); hlVal:SetColorTexture(1, 1, 1, 0.08)
    rowEntry:RegisterForClicks("LeftButtonUp")
    rowEntry:SetScript("OnEnter", DungeonRouteWindow.resolveLootOnEnter)
    rowEntry:SetScript("OnLeave", GameTooltip_Hide)
    rowEntry:SetScript("OnClick", DungeonRouteWindow.resolveLootOnClick)
    cardRows[entryKey] = rowEntry
    return rowEntry
end

function DungeonRouteWindow.resolveModelCall(matchRef, method, ...)
    if not matchRef[method] then return false end
    return (pcall(matchRef[method], matchRef, ...))
end

function DungeonRouteWindow.resolveModelRotate(self)
    local coordX = GetCursorPosition()
    self.rot = (self.rot or 0) + (coordX - (self.dragX or coordX)) * 0.012
    self.dragX = coordX
    DungeonRouteWindow.resolveModelCall(self, "SetRotation", self.rot)
end

function buildCard()
    cardLayout = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
    DungeonRouteWindow.applyPanelBackdrop(cardLayout, 0.92)
    cardLayout:SetWidth(CARD_W)
    cardLayout:EnableMouse(true)
    local close = DungeonRouteWindow.createStyledButton(cardLayout, "X", 22, nil, function() unitState.selected, unitState.cardTrash = nil, nil; ns.RefreshMap() end)
    close:SetPoint("TOPRIGHT", -4, -4)
    cardLayout.title = cardLayout:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cardLayout.title:SetPoint("TOPLEFT", 8, -8); cardLayout.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
    cardLayout.title:SetJustifyH("LEFT")
    if cardLayout.title.SetWordWrap then cardLayout.title:SetWordWrap(false) end
    cardLayout.kind = cardLayout:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cardLayout.kind:SetPoint("TOPLEFT", cardLayout.title, "BOTTOMLEFT", 0, -3)
    local mbg = cardLayout:CreateTexture(nil, "BACKGROUND", nil, 1)
    mbg:SetPoint("TOPLEFT", 6, -44); mbg:SetPoint("TOPRIGHT", -6, -44); mbg:SetHeight(MODEL_H)
    mbg:SetColorTexture(0, 0, 0, 0.45)
    cardLayout.mbg = mbg
    local matchRef = CreateFrame("PlayerModel", nil, cardLayout)
    matchRef:SetAllPoints(mbg)
    matchRef:EnableMouse(true)
    if matchRef.EnableMouseWheel then matchRef:EnableMouseWheel(true) end
    matchRef:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            self.rot, self.zoom = 0.5, 1
            DungeonRouteWindow.resolveModelCall(self, "SetRotation", self.rot); DungeonRouteWindow.resolveModelCall(self, "SetCamDistanceScale", self.zoom)
        else
            self.dragX = GetCursorPosition()
            self:SetScript("OnUpdate", DungeonRouteWindow.resolveModelRotate)
        end
    end)
    matchRef:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    matchRef:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    matchRef:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0.4, math.min(2.5, (self.zoom or 1) - delta * 0.1))
        DungeonRouteWindow.resolveModelCall(self, "SetCamDistanceScale", self.zoom)
    end)
    matchRef:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.MODEL_HINT, 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    matchRef:SetScript("OnLeave", GameTooltip_Hide)
    cardLayout.model = matchRef
    cardLayout.noModel = cardLayout:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cardLayout.noModel:SetPoint("CENTER", mbg, "CENTER")
    ns.GetLocalizedEntryField(cardLayout.noModel, "NO_MODEL")
    cardLayout.lootLabel = cardLayout:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cardLayout.lootLabel:SetPoint("TOPLEFT", mbg, "BOTTOMLEFT", 2, -8)
    
    cardLayout.scroll = CreateFrame("ScrollFrame", nil, cardLayout, "UIPanelScrollFrameTemplate")
    cardLayout.content = CreateFrame("Frame", nil, cardLayout.scroll)
    cardLayout.content:SetSize(CARD_W - 40, 10)
    cardLayout.scroll:SetScrollChild(cardLayout.content)
    
    local lbVal = CreateFrame("StatusBar", nil, cardLayout)
    lbVal:SetPoint("BOTTOMLEFT", 8, 7); lbVal:SetPoint("BOTTOMRIGHT", -8, 7)
    lbVal:SetHeight(12)
    lbVal:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    lbVal:SetStatusBarColor(0.25, 0.6, 1)
    lbVal:SetMinMaxValues(0, 1)
    local lbg = lbVal:CreateTexture(nil, "BACKGROUND"); lbg:SetAllPoints(); lbg:SetColorTexture(0, 0, 0, 0.6)
    lbVal.text = lbVal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbVal.text:SetPoint("CENTER")
    lbVal:Hide()
    cardLayout.loadBar = lbVal
    cardLayout.more = cardLayout.content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cardLayout.more:SetJustifyH("LEFT")
    cardLayout:SetScript("OnShow", function() cardLayout.modelFor = nil end)
    cardLayout:Hide()
end

function anchorCard()
    cardLayout:ClearAllPoints()
    local right = ns.CoerceSafeNumber(ns.UnwrapSafeValue(containerFrame.GetRight, containerFrame)) or 0
    local screen = (UIParent and ns.CoerceSafeNumber(ns.UnwrapSafeValue(UIParent.GetRight, UIParent))) or (GetScreenWidth and ns.CoerceSafeNumber(ns.UnwrapSafeValue(GetScreenWidth))) or 1e6
    if right + CARD_W + 4 > screen then
        cardLayout:SetPoint("TOPRIGHT", containerFrame, "TOPLEFT", -2, 0)
    else
        cardLayout:SetPoint("TOPLEFT", containerFrame, "TOPRIGHT", 2, 0)
    end
    cardLayout:SetHeight(DungeonRouteWindow.getSafeFrameHeight(containerFrame, 480))
end

function DungeonRouteWindow.assignCardModel(step)
    local matchRef = cardLayout.model
    local entityID = step.model or (step.npc and step.npc[1])
    if cardLayout.modelFor == entityID then return end   
    cardLayout.modelFor = entityID
    matchRef.rot, matchRef.zoom = 0.5, 1
    matchRef:Show()   
    DungeonRouteWindow.resolveModelCall(matchRef, "ClearModel")
    local isCallOk = false
    if step.model then isCallOk = DungeonRouteWindow.resolveModelCall(matchRef, "SetDisplayInfo", step.model) end
    if not isCallOk and step.npc then isCallOk = DungeonRouteWindow.resolveModelCall(matchRef, "SetCreature", step.npc[1]) end
    if isCallOk then
        DungeonRouteWindow.resolveModelCall(matchRef, "SetPortraitZoom", 0)
        DungeonRouteWindow.resolveModelCall(matchRef, "SetCamDistanceScale", matchRef.zoom)
        DungeonRouteWindow.resolveModelCall(matchRef, "SetRotation", matchRef.rot)
    end
    matchRef:SetShown(isCallOk)
    cardLayout.noModel:SetShown(not isCallOk)
end

function plotCard(d)
    local index = unitState.selected
    local step = index and d.steps[index]
    local radioOptionGroup = unitState.cardTrash and d.trashGroups and d.trashGroups[unitState.cardTrash]
    if unitState.cardTrash and not radioOptionGroup then unitState.cardTrash = nil end
    if not radioOptionGroup and (not step or not (step.model or step.npc or (step.loot and #step.loot > 0))) then
        cardLayout:Hide(); cardLayout.modelFor = nil
        return
    end
    cardLayout:Show()
    anchorCard()
    local ids, top
    if radioOptionGroup then
        cardLayout.title:SetText(translationHelper(radioOptionGroup.name))
        cardLayout.kind:SetText(radioOptionGroup.trash and L.TRASH_ALL or L.TRASH_NAMED)
        cardLayout.mbg:Hide(); cardLayout.model:Hide(); cardLayout.noModel:Hide(); cardLayout.modelFor = nil
        cardLayout.lootLabel:ClearAllPoints(); cardLayout.lootLabel:SetPoint("TOPLEFT", 10, -44)
        cardLayout.lootLabel:SetText(L.LOOT .. (" (%d)"):format(#radioOptionGroup.loot))
        ids, top = radioOptionGroup.loot, 44
    else
        cardLayout.title:SetText(ns.ResolveRouteStepDisplayTitle(d, index))
        local kind = L["KIND_" .. step.kind] or step.kind
        if step.optional then kind = kind .. " · " .. L.OPTIONAL end
        cardLayout.kind:SetText(kind)
        cardLayout.mbg:Show()
        DungeonRouteWindow.assignCardModel(step)
        cardLayout.lootLabel:ClearAllPoints(); cardLayout.lootLabel:SetPoint("TOPLEFT", cardLayout.mbg, "BOTTOMLEFT", 2, -8)
        cardLayout.lootLabel:SetText(L.LOOT .. ((step.loot and #step.loot > 0) and (" (%d)"):format(#step.loot) or ""))
        ids, top = step.loot or {}, 44 + MODEL_H
    end
    local from = radioOptionGroup and radioOptionGroup.from
    local rowH = from and 30 or 21
    local settled, grandTotal, missing = ns.ItemProgress(ids)
    local loading = settled < grandTotal
    if loading then
        cardLayout.loadBar:SetMinMaxValues(0, grandTotal)
        cardLayout.loadBar:SetValue(settled)
        cardLayout.loadBar.text:SetText(L.ITEMS_LOADING:format(settled, grandTotal))
        cardLayout.loadBar:Show()
        
        if not cardLayout.ticking and C_Timer and C_Timer.After then
            cardLayout.ticking = true
            C_Timer.After(1, function() cardLayout.ticking = false; if cardLayout:IsShown() then ns.RefreshMap() end end)
        end
    else
        cardLayout.loadBar:Hide()
    end
    cardLayout.scroll:ClearAllPoints()
    cardLayout.scroll:SetPoint("TOPLEFT", cardLayout.lootLabel, "BOTTOMLEFT", -2, -4)
    cardLayout.scroll:SetPoint("BOTTOMRIGHT", cardLayout, "BOTTOMRIGHT", -28, loading and 24 or 8)
    
    local listKey = radioOptionGroup and ("g" .. tostring(radioOptionGroup)) or ("s" .. tostring(step))
    if cardLayout.listKey ~= listKey then
        cardLayout.listKey = listKey
        if cardLayout.scroll.SetVerticalScroll then cardLayout.scroll:SetVerticalScroll(0) end
    end
    local shown = 0
    for entryKey, entityID in ipairs(ids) do
        local rowEntry = DungeonRouteWindow.resolveCardRow(entryKey)
        rowEntry.id = entityID
        rowEntry.from = from and from[entityID]
        local stateEntry = DungeonRouteWindow.resolveSourceText(rowEntry.from)
        rowEntry:SetHeight(rowH)
        rowEntry.name:ClearAllPoints()
        rowEntry.name:SetPoint(stateEntry and "TOPLEFT" or "LEFT", rowEntry.icon, stateEntry and "TOPRIGHT" or "RIGHT", 5, stateEntry and 2 or 0)
        rowEntry.name:SetPoint("RIGHT", -2, 0)
        rowEntry.src:SetText(stateEntry or "")
        rowEntry.src:SetShown(stateEntry ~= nil)
        local displayName, _, priorityQueue, iconTex = ns.ItemInfo(entityID)
        rowEntry.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        DungeonRouteWindow.resolveQualityBorder(rowEntry.border, priorityQueue)
        local missingItem = not displayName and ns.ItemState(entityID) == "missing"
        rowEntry.name:SetText(displayName and (ns.QualityHex(priorityQueue) .. displayName .. "|r")
            or ("|cff888888#" .. entityID .. " " .. (missingItem and L.ITEM_MISSING or L.LOADING) .. "|r"))
        rowEntry:ClearAllPoints()
        rowEntry:SetPoint("TOPLEFT", cardLayout.content, "TOPLEFT", 0, -(entryKey - 1) * rowH)
        rowEntry:Show()
        shown = entryKey
    end
    for subIndex = shown + 1, #cardRows do cardRows[subIndex]:Hide() end
    cardLayout.more:ClearAllPoints()
    cardLayout.more:SetPoint("TOPLEFT", cardLayout.content, "TOPLEFT", 2, -2 - shown * rowH)
    cardLayout.more:SetText(#ids == 0 and L.NO_LOOT or (missing > 0 and L.ITEMS_MISSING:format(missing) or ""))
    cardLayout.content:SetHeight(math.max(10, shown * rowH + (missing > 0 and 18 or 4)))
end

-----------------------------------------------------------------------------
-- Update Widget Anchor Position
-----------------------------------------------------------------------------
function DungeonRouteWindow.updateWidgetAnchorPosition(f, sc, p, dx, dy)
    f:ClearAllPoints()
    f:SetPoint("CENTER", canvasFrame, "TOPLEFT", (p[1] - view[1]) * sc + (dx or 0), -(p[2] - view[2]) * sc + (dy or 0))
end
function DungeonRouteWindow.inView(p)
    return p and p[1]>=view[1] and p[1]<=view[1]+view[3] and p[2]>=view[2] and p[2]<=view[2]+view[4]
end
function DungeonRouteWindow.resolveMarkerSpot(p, sc, occupied)
    local axVal, ayVal = (p[1]-view[1])*sc, (p[2]-view[2])*sc
    local widgetHelper, headerFrameRef = DungeonRouteWindow.getSafeFrameWidth(canvasFrame, ns.db.mapSize), DungeonRouteWindow.getSafeFrameHeight(canvasFrame, ns.db.mapSize)
    local function free(coordX,coordY)
        for _,priorityQueue in ipairs(occupied)do if (priorityQueue[1]-coordX)^2+(priorityQueue[2]-coordY)^2 < 20^2 then return false end end
        return true
    end
    for _,radius in ipairs({0,22,32,44,60,80,104,132})do
        for angle=0,15 do
            local a=angle*math.pi/8
            local coordX=math.max(12,math.min(widgetHelper-12,axVal+radius*math.cos(a)))
            local coordY=math.max(12,math.min(headerFrameRef-12,ayVal+radius*math.sin(a)))
            if free(coordX,coordY)then occupied[#occupied+1]={coordX,coordY};return coordX-axVal, ayVal-coordY end
        end
    end
    occupied[#occupied+1]={axVal,ayVal};return 0,0
end

function DungeonRouteWindow.plotMarkers(d, page, nextIndex, sc)
    local entryKey, kaVal = 0, 0
    local greenVal = DungeonRouteWindow.resolveDungeonFloorGeometry(d)
    local occupied={}
    for _,lnVal in ipairs(greenVal.links or{})do
        if lnVal.page==page.key and DungeonRouteWindow.inView(lnVal.pos)then occupied[#occupied+1]={(lnVal.pos[1]-view[1])*sc,(lnVal.pos[2]-view[2])*sc}end
    end
    if greenVal.start and greenVal.start.page==page.key and DungeonRouteWindow.inView(greenVal.start.pos)then
        occupied[#occupied+1]={(greenVal.start.pos[1]-view[1])*sc,(greenVal.start.pos[2]-view[2])*sc}
    end
    local reservedCount=#occupied
    for index, step in ipairs(d.steps) do
        local spage, spos, salt = DungeonRouteWindow.stepGeo(d, index)
        if spos and spage == page.key and DungeonRouteWindow.inView(spos) and ns.IsRouteStepVisibleOnFloor(step) then
            local done = ns.IsRouteStepCompleted(d, index)
            local categoryKey = DungeonRouteWindow.resolveCategory(step)
            local themeColor = done and CAT.done or CAT[categoryKey]
            
            for _, apVal in ipairs((unitState.selected==index or unitState.targetStep==index) and (salt or {}) or {}) do
                if DungeonRouteWindow.inView(apVal) then
                kaVal = kaVal + 1
                local a = DungeonRouteWindow.resolveAlt(kaVal)
                a.index = index
                DungeonRouteWindow.updateWidgetAnchorPosition(a, sc, apVal)
                a.ring:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], 1)
                local abn, aic = ns.ResolveBossEncounterOrderIndex(d, index), ns.ResolveStepCategoryIcon(step)
                a.text:SetText(abn and tostring(abn) or "")
                if not abn and aic then a.icon:SetTexture(aic); a.icon:Show() else a.icon:Hide() end
                a:Show()
                end
            end
            entryKey = entryKey + 1
            local matchRef = DungeonRouteWindow.resolveMarker(entryKey)
            matchRef.index = index
            local dx,dy=0,0
            if not page.flow then dx,dy=DungeonRouteWindow.resolveMarkerSpot(spos,sc,occupied) end
            DungeonRouteWindow.updateWidgetAnchorPosition(matchRef, sc, spos,dx,dy)
            local displaced=dx*dx+dy*dy>1
            matchRef.leader:SetShown(displaced)
            if displaced then
                local axVal,ayVal=(spos[1]-view[1])*sc,-(spos[2]-view[2])*sc
                matchRef.leader:SetStartPoint("TOPLEFT",canvasFrame,axVal,ayVal)
                matchRef.leader:SetEndPoint("TOPLEFT",canvasFrame,axVal+dx,ayVal+dy)
            end
            if page.flow then
                
                matchRef.label:SetWidth(math.max(40, page.colW * sc - 8))
                if matchRef.label.SetWordWrap then matchRef.label:SetWordWrap(true) end
                matchRef.label:SetText(translationHelper(step.name)); matchRef.label:Show()
            else
                matchRef.label:Hide()
            end
            
            matchRef.circle:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], step.optional and 0.45 or 0.6)
            if unitState.selected == index then matchRef.ring:SetVertexColor(1, 1, 1, 0.9) else matchRef.ring:SetVertexColor(0, 0, 0, 0.5) end
            local bnVal, icVal = ns.ResolveBossEncounterOrderIndex(d, index), ns.ResolveStepCategoryIcon(step)
            matchRef.text:SetText(bnVal and tostring(bnVal) or "")
            if not bnVal and icVal then matchRef.icon:SetTexture(icVal); matchRef.icon:Show() else matchRef.icon:Hide() end
            matchRef.check:SetShown(done)
            local presentBadge = step.quest and not done and step.kind ~= "object" and step.kind ~= "task"
            matchRef.badge:SetShown(presentBadge); matchRef.badgeText:SetShown(presentBadge)
            local hasNext2 = (index == nextIndex) or (unitState.targetStep == index and unitState.current == d)
            matchRef.glow:SetShown(hasNext2)
            if matchRef.pulse then if hasNext2 then matchRef.pulse:Play() else matchRef.pulse:Stop() end end
            matchRef:Show()
        end
    end
    for subIndex = entryKey + 1, #markers do markers[subIndex]:Hide(); markers[subIndex].leader:Hide() end
    for subIndex = kaVal + 1, #alts do alts[subIndex]:Hide() end
    
    if greenVal.start and greenVal.start.page == page.key and DungeonRouteWindow.inView(greenVal.start.pos) then
        DungeonRouteWindow.updateWidgetAnchorPosition(entranceMark, sc, greenVal.start.pos)
        entranceMark.text:ClearAllPoints()
        if (greenVal.start.pos[2] - view[2]) / view[4] > 0.92 then
            entranceMark.text:SetPoint("BOTTOM", entranceMark, "TOP", 0, 1)
        else
            entranceMark.text:SetPoint("TOP", entranceMark, "BOTTOM", 0, -1)
        end
        entranceMark:Show()
    else
        entranceMark:Hide()
    end
    local klVal = 0
    local linkOccupied={}
    for subIndex=reservedCount+1,#occupied do linkOccupied[#linkOccupied+1]=occupied[subIndex]end
    if greenVal.start and greenVal.start.page==page.key and DungeonRouteWindow.inView(greenVal.start.pos)then linkOccupied[#linkOccupied+1]={(greenVal.start.pos[1]-view[1])*sc,(greenVal.start.pos[2]-view[2])*sc}end

    local labelRects, named = {}, {}
    local widgetHelper, headerFrameRef = DungeonRouteWindow.getSafeFrameWidth(canvasFrame, ns.db.mapSize), DungeonRouteWindow.getSafeFrameHeight(canvasFrame, ns.db.mapSize)
    local function resolveLabelFits(x0, y0, x1, y1)
        if x0 < 0 or y1 > headerFrameRef or (widgetHelper > 0 and x1 > widgetHelper) then return false end
        for _, rowEntry in ipairs(labelRects) do
            if x0 < rowEntry[3] and x1 > rowEntry[1] and y0 < rowEntry[4] and y1 > rowEntry[2] then return false end
        end
        for _, priorityQueue in ipairs(occupied) do
            if priorityQueue[1] > x0 - 9 and priorityQueue[1] < x1 + 9 and priorityQueue[2] > y0 - 9 and priorityQueue[2] < y1 + 9 then return false end
        end
        return true
    end
    for _, lnVal in ipairs(greenVal.links or {}) do
        if lnVal.page == page.key and DungeonRouteWindow.inView(lnVal.pos) then
            klVal = klVal + 1
            local leftPos = DungeonRouteWindow.resolveLink(klVal)
            leftPos.label = translationHelper(lnVal.text)
            leftPos.toPage = lnVal.toPage
            leftPos.approx = lnVal.approx
            local dest = DungeonRouteWindow.resolvePageByKey(greenVal, lnVal.toPage)
            local nameText = (dest and dest.name and translationHelper(dest.name)) or (lnVal.to and translationHelper(lnVal.to)) or ""
            leftPos.name:SetText(nameText)
            leftPos.number:SetText(lnVal.caption and translationHelper(lnVal.caption):match("^(%d+)") or "↗")
            local dx,dy=DungeonRouteWindow.resolveMarkerSpot(lnVal.pos,sc,linkOccupied)
            DungeonRouteWindow.updateWidgetAnchorPosition(leftPos, sc, lnVal.pos,dx,dy)
            local cxVal, cyVal = (lnVal.pos[1]-view[1])*sc + dx, (lnVal.pos[2]-view[2])*sc - dy
            local show = nameText ~= ""
            if show then
                for _, p in ipairs(named[nameText] or {}) do
                    if (p[1]-cxVal)^2 + (p[2]-cyVal)^2 < 90^2 then show = false; break end
                end
            end
            if show then
                
                local w = DungeonRouteWindow.getSafeStringWidth(leftPos.name, 40) / 2 + 3
                local shift = 0
                if widgetHelper > 0 then shift = math.max(0 - (cxVal - w), math.min(0, widgetHelper - (cxVal + w))) end
                local x0, x1 = cxVal - w + shift, cxVal + w + shift
                local placed
                if resolveLabelFits(x0, cyVal + 10, x1, cyVal + 24) then placed = "below"
                elseif resolveLabelFits(x0, cyVal - 24, x1, cyVal - 10) then placed = "above" end
                show = placed ~= nil
                if show then
                    labelRects[#labelRects + 1] = placed == "below" and { x0, cyVal + 10, x1, cyVal + 24 } or { x0, cyVal - 24, x1, cyVal - 10 }
                    named[nameText] = named[nameText] or {}
                    table.insert(named[nameText], { cxVal, cyVal })
                    leftPos.name:ClearAllPoints()
                    if placed == "below" then leftPos.name:SetPoint("TOP", leftPos, "BOTTOM", shift, -1)
                    else leftPos.name:SetPoint("BOTTOM", leftPos, "TOP", shift, 1) end
                end
            end
            leftPos.name:SetShown(show); leftPos.nameBg:SetShown(show)
            leftPos.leader:SetShown(dx*dx+dy*dy>1)
            if dx*dx+dy*dy>1 then
                local axVal,ayVal=(lnVal.pos[1]-view[1])*sc,-(lnVal.pos[2]-view[2])*sc
                leftPos.leader:SetStartPoint("TOPLEFT",canvasFrame,axVal,ayVal);leftPos.leader:SetEndPoint("TOPLEFT",canvasFrame,axVal+dx,ayVal+dy)
            end
            leftPos:Show()
        end
    end
    for subIndex = klVal + 1, #links do links[subIndex]:Hide();links[subIndex].leader:Hide() end
end

function DungeonRouteWindow.plotMasks(page, sc)
    local entryKey = 0
    for _, p in ipairs(page.mask or {}) do
        entryKey = entryKey + 1
        local matchRef = masks[entryKey]
        if not matchRef then
            matchRef = { outer = canvasFrame:CreateTexture(nil, "BACKGROUND", nil, 2), inner = canvasFrame:CreateTexture(nil, "BACKGROUND", nil, 3) }
            for _, resolvedValue in ipairs({ matchRef.outer, matchRef.inner }) do
                resolvedValue:SetColorTexture(1, 1, 1, 1)
                if canvasFrame.CreateMaskTexture then
                    local mkVal = canvasFrame:CreateMaskTexture()
                    mkVal:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    mkVal:SetAllPoints(resolvedValue)
                    resolvedValue:AddMaskTexture(mkVal)
                end
            end
            matchRef.outer:SetVertexColor(0.08, 0.07, 0.06, 0.45)
            matchRef.inner:SetVertexColor(0.08, 0.07, 0.06, 0.85)
            masks[entryKey] = matchRef
        end
        matchRef.outer:SetSize(24 * sc, 24 * sc); matchRef.inner:SetSize(17 * sc, 17 * sc)
        for _, resolvedValue in ipairs({ matchRef.outer, matchRef.inner }) do
            resolvedValue:ClearAllPoints()
            resolvedValue:SetPoint("CENTER", canvasFrame, "TOPLEFT", p[1] * sc, -p[2] * sc)
            resolvedValue:Show()
        end
    end
    for subIndex = entryKey + 1, #masks do masks[subIndex].outer:Hide(); masks[subIndex].inner:Hide() end
end

function DungeonRouteWindow.resolveTileSet(page)
    if page.set ~= nil then return page.set or nil end
    page.set = false
    if page.img then page.set = page.img; return page.set end      
    if page.grid then
        if #page.grid.tiles == 0 then return nil end
        for _, tile in ipairs(page.grid.tiles) do
            local isCallOk, loaded = pcall(tiles[1].SetTexture, tiles[1], tile[1])
            if not isCallOk or loaded == false then return nil end
        end
        page.set = page.grid
        return page.set
    end
    for _, set in ipairs(page.tiles) do
        local isCallOk, loaded = pcall(tiles[1].SetTexture, tiles[1], set[1])
        if isCallOk and loaded ~= false then page.set = set; break end
    end
    return page.set or nil
end

function DungeonRouteWindow.plotTiles(page, sc)
    local set = page and (page.tiles or page.grid or page.img) and DungeonRouteWindow.resolveTileSet(page)
    local nodeEntry = 0
    local function put(file, tx, ty, size, layer, th, border, fileSize)
        local twVal = size
        th = th or size
        local x0, x1 = math.max(tx, view[1]), math.min(tx + twVal, view[1] + view[3])
        local y0, y1 = math.max(ty, view[2]), math.min(ty + th, view[2] + view[4])
        if x1 <= x0 or y1 <= y0 then return end
        nodeEntry = nodeEntry + 1
        local resolvedValue = tiles[nodeEntry]
        if not resolvedValue then resolvedValue = canvasFrame:CreateTexture(nil, "BACKGROUND"); tiles[nodeEntry] = resolvedValue end
        resolvedValue:SetTexture(file)
        resolvedValue:SetDrawLayer("BACKGROUND", layer or 0)
        if border and fileSize then
            resolvedValue:SetTexCoord((border+x0-tx)/fileSize,(border+x1-tx)/fileSize,(border+y0-ty)/fileSize,(border+y1-ty)/fileSize)
        else
            resolvedValue:SetTexCoord((x0 - tx) / twVal, (x1 - tx) / twVal, (y0 - ty) / th, (y1 - ty) / th)
        end
        resolvedValue:ClearAllPoints()
        resolvedValue:SetPoint("TOPLEFT", canvasFrame, "TOPLEFT", (x0 - view[1]) * sc, -(y0 - view[2]) * sc)
        resolvedValue:SetSize((x1 - x0) * sc, (y1 - y0) * sc)
        resolvedValue:Show()
    end
    if set and page.img then
        put(MAP_PATH .. page.img[1], page.img[2], page.img[3], page.img[4])
    elseif set and page.grid then
        local size = page.grid.size or 512
        for _, greenVal in ipairs(page.grid.tiles) do
            if page.grid.px then

                put(greenVal[1], greenVal[2], greenVal[3], greenVal[4], math.min(1, (greenVal[6] or 0) - 7), greenVal[5], greenVal[7], greenVal[8])
            else
                put(greenVal[1], greenVal[2] * size, greenVal[3] * size, size)
            end
        end
    elseif set then
        for entryKey = 1, 12 do put(set[entryKey], ((entryKey - 1) % 4) * 256, math.floor((entryKey - 1) / 4) * 256, 256) end
    end
    for entryKey = nodeEntry + 1, #tiles do tiles[entryKey]:Hide() end
    return set ~= nil
end

local flowLines = {}
function DungeonRouteWindow.plotFlowLines(d, page, sc)
    local entryKey = 0
    if page and page.flow then
        local greenVal = DungeonRouteWindow.resolveDungeonFloorGeometry(d)
        local prev
        for _, index in ipairs(greenVal.order or {}) do
            local stateFlag = greenVal.steps[d.steps[index].id]
            if stateFlag and ns.IsRouteStepVisibleOnFloor(d.steps[index]) then
                if prev then
                    entryKey = entryKey + 1
                    local lnVal = flowLines[entryKey]
                    if not lnVal then lnVal = overlay:CreateLine(nil, "BACKGROUND"); flowLines[entryKey] = lnVal end
                    lnVal:SetThickness(2)
                    lnVal:SetColorTexture(0.7, 0.7, 0.7, 0.45)
                    lnVal:SetStartPoint("TOPLEFT", canvasFrame, prev[1] * sc, -prev[2] * sc)
                    lnVal:SetEndPoint("TOPLEFT", canvasFrame, stateFlag.pos[1] * sc, -stateFlag.pos[2] * sc)
                    lnVal:Show()
                end
                prev = stateFlag.pos
            end
        end
    end
    for subIndex = entryKey + 1, #flowLines do flowLines[subIndex]:Hide() end
end

function DungeonRouteWindow.dismissMapLayer()
    for _, resolvedValue in ipairs(markers) do resolvedValue:Hide(); resolvedValue.leader:Hide() end
    for _, resolvedValue in ipairs(alts) do resolvedValue:Hide() end
    for _, resolvedValue in ipairs(links) do resolvedValue:Hide();resolvedValue.leader:Hide() end
    for _, matchRef in ipairs(masks) do matchRef.outer:Hide(); matchRef.inner:Hide() end
    entranceMark:Hide()
end

function DungeonRouteWindow.resolvePageIndex(d, pageKey)
    if not d or not pageKey then return nil, 0 end
    local pages = DungeonRouteWindow.resolveDungeonFloorGeometry(d).pages or {}
    if #pages < 2 then return nil, #pages end
    for entryIndex, p in ipairs(pages) do
        if p.key == pageKey then return entryIndex, #pages end
    end
    return nil, #pages
end

function DungeonRouteWindow.resolveRowTag(step, d, index)
    local base = ""
    if step.outside then base = L.OUTSIDE
    elseif step.unconfirmed and step.kind ~= "fork" then base = L.UNCONFIRMED
    elseif step.kind == "rare" then base = L.KIND_rare
    elseif step.optional then base = L.OPTIONAL
    elseif step.kind ~= "boss" then base = L["KIND_" .. step.kind] or "" end
    local spage = d and index and DungeonRouteWindow.stepGeo(d, index)
    local fIdx = DungeonRouteWindow.resolvePageIndex(d, spage)
    if fIdx then
        local fLabel = (L.AREA_SHORT or "지역 %d"):format(fIdx)
        local fTag = (spage == unitState.shownPage) and ("|cffea837e" .. fLabel .. "|r") or ("|cff6e7f8d" .. fLabel .. "|r")
        if base ~= "" then return fTag .. " " .. base end
        return fTag
    end
    return base
end

function DungeonRouteWindow.resolveLootBtn(entryKey)
    local buttonWidget = lootBtns[entryKey]
    if buttonWidget then return buttonWidget end
    buttonWidget = CreateFrame("Button", nil, lootBar)
    buttonWidget:SetSize(22, 22)
    buttonWidget.icon = buttonWidget:CreateTexture(nil, "ARTWORK"); buttonWidget.icon:SetAllPoints()
    buttonWidget.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    
    buttonWidget.border = buttonWidget:CreateTexture(nil, "BACKGROUND")
    buttonWidget.border:SetPoint("TOPLEFT", -1, 1); buttonWidget.border:SetPoint("BOTTOMRIGHT", 1, -1)
    buttonWidget.border:SetColorTexture(1, 1, 1, 0)
    local hlVal = buttonWidget:CreateTexture(nil, "HIGHLIGHT"); hlVal:SetAllPoints(); hlVal:SetColorTexture(1, 1, 1, 0.25)
    buttonWidget:RegisterForClicks("LeftButtonUp")
    buttonWidget:SetScript("OnEnter", DungeonRouteWindow.resolveLootOnEnter)
    buttonWidget:SetScript("OnLeave", GameTooltip_Hide)
    buttonWidget:SetScript("OnClick", DungeonRouteWindow.resolveLootOnClick)
    lootBtns[entryKey] = buttonWidget
    return buttonWidget
end

local lootFrom   

function DungeonRouteWindow.plotLoot(ids, label, from)
    lootFrom = from
    if not ids or #ids == 0 then lootBar:Hide(); return 0 end
    lootBar:Show()
    local perRow = math.floor(LIST_CONTENT_W / 24)
    local settled, grandTotal = ns.ItemProgress(ids)
    if settled < grandTotal then label = label .. (" |cff66b3ff%s|r"):format(L.ITEMS_LOADING:format(settled, grandTotal)) end
    local labelHeight = DungeonRouteWindow.resolveTextHeight(lootLabel, label, LIST_CONTENT_W - 8)
    for entryKey, entityID in ipairs(ids) do
        local buttonWidget = DungeonRouteWindow.resolveLootBtn(entryKey)
        buttonWidget.id = entityID
        buttonWidget.from = lootFrom and lootFrom[entityID]
        local _, _, priorityQueue, iconTex = ns.ItemInfo(entityID)
        buttonWidget.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        DungeonRouteWindow.resolveQualityBorder(buttonWidget.border, priorityQueue)
        buttonWidget:ClearAllPoints()
        local rowWidget, columnIndex = math.floor((entryKey - 1) / perRow), (entryKey - 1) % perRow
        buttonWidget:SetPoint("TOPLEFT", lootBar, "TOPLEFT", 2 + columnIndex * 24, -labelHeight - 2 - rowWidget * 24)
        buttonWidget:EnableMouseWheel(true)
        buttonWidget:SetScript("OnMouseWheel", DungeonRouteWindow.listWheel)
        buttonWidget:Show()
    end
    for subIndex = #ids + 1, #lootBtns do lootBtns[subIndex]:Hide() end
    local height = labelHeight + 2 + math.ceil(#ids / perRow) * 24
    lootBar:SetHeight(height)
    return height + 4
end

function DungeonRouteWindow.dismissTrashBtns() for _, buttonWidget in ipairs(trashBtns) do buttonWidget:Hide() end end

function DungeonRouteWindow.plotRouteList(d, nextIndex)
    DungeonRouteWindow.beginList(d, "route")
    DungeonRouteWindow.dismissTrashBtns()
    local groups = d.trashGroups or {}
    local multiFloor = #(DungeonRouteWindow.resolveDungeonFloorGeometry(d).pages or {}) > 1
    local coordY, entryKey = 0, 0
    for index, step in ipairs(d.steps) do
        if ns.IsRouteStepVisibleOnFloor(step) then
            entryKey = entryKey + 1
            local rowEntry = DungeonRouteWindow.resolveRow(entryKey)
            rowEntry.index = index
            rowEntry:ClearAllPoints()
            rowEntry:SetPoint("TOPLEFT", 0, coordY)
            local done = ns.IsRouteStepCompleted(d, index)
            local spage = DungeonRouteWindow.stepGeo(d, index)
            local onShownFloor = (not multiFloor) or (not spage) or (spage == unitState.shownPage)
            rowEntry:SetAlpha((onShownFloor or unitState.selected == index) and 1 or 0.72)
            rowEntry.check:SetShown(done)
            local themeColor = CAT[DungeonRouteWindow.resolveCategory(step)]
            rowEntry.dot:SetVertexColor(themeColor[1], themeColor[2], themeColor[3], 1)
            rowEntry.dot:SetShown(not done and step.kind ~= "fork")
            local rbn, ric = ns.ResolveBossEncounterOrderIndex(d, index), ns.ResolveStepCategoryIcon(step)
            rowEntry.num:SetText(rbn and tostring(rbn) or "")
            if not rbn and ric then rowEntry.kicon:SetTexture(ric); rowEntry.kicon:Show() else rowEntry.kicon:Hide() end
            if done then rowEntry.name:SetTextColor(0.55, 0.55, 0.55)
            elseif index == nextIndex then rowEntry.name:SetTextColor(1, 0.82, 0)
            elseif step.kind == "fork" then rowEntry.name:SetTextColor(0.7, 0.7, 0.7)
            elseif step.optional then rowEntry.name:SetTextColor(0.82, 0.7, 1)
            else rowEntry.name:SetTextColor(1, 1, 1) end
            rowEntry.group = nil
            local tagText = DungeonRouteWindow.resolveRowTag(step, d, index)
            rowEntry.tag:SetWidth(0)
            rowEntry.tag:SetText(tagText)
            local tagWidth = tagText ~= "" and math.min(84, DungeonRouteWindow.getSafeStringWidth(rowEntry.tag, 36)) or 0
            rowEntry.tag:SetWidth(tagWidth)
            local rowH = math.max(17, DungeonRouteWindow.resolveTextHeight(rowEntry.name, translationHelper(step.name), LIST_CONTENT_W - 43 - tagWidth) + 4)
            rowEntry:SetHeight(rowH)
            coordY = coordY - rowH
            rowEntry.bg:SetShown(unitState.selected == index)
            rowEntry:Show()
        end
    end
    
    for gkVal, greenVal in ipairs(groups) do
        entryKey = entryKey + 1
        local rowEntry = DungeonRouteWindow.resolveRow(entryKey)
        rowEntry.index, rowEntry.group = nil, gkVal
        rowEntry:SetAlpha(1)
        rowEntry:ClearAllPoints()
        rowEntry:SetPoint("TOPLEFT", 0, coordY)
        rowEntry.check:Hide()
        rowEntry.dot:SetVertexColor(0.6, 0.6, 0.6, 1); rowEntry.dot:Show()
        rowEntry.num:SetText("")
        rowEntry.kicon:SetTexture(TRASH_ICON); rowEntry.kicon:Show()
        rowEntry.name:SetTextColor(0.8, 0.8, 0.8)
        rowEntry.tag:SetWidth(0)
        rowEntry.tag:SetText(L.LOOT .. " " .. #greenVal.loot)
        local tagWidth = math.min(64, DungeonRouteWindow.getSafeStringWidth(rowEntry.tag, 42))
        rowEntry.tag:SetWidth(tagWidth)
        local rowH = math.max(17, DungeonRouteWindow.resolveTextHeight(rowEntry.name, translationHelper(greenVal.name), LIST_CONTENT_W - 43 - tagWidth) + 4)
        rowEntry:SetHeight(rowH)
        coordY = coordY - rowH
        rowEntry.bg:SetShown(unitState.cardTrash == gkVal)
        rowEntry:Show()
    end
    for subIndex = entryKey + 1, #rowWidgets do rowWidgets[subIndex]:Hide() end
    local tgVal = unitState.cardTrash and groups[unitState.cardTrash]
    local floorStep = (multiFloor and unitState.shownPage) and DungeonRouteWindow.resolveFirstStepOnPage(d, unitState.shownPage) or nil
    local index = unitState.selected or floorStep or nextIndex
    local step = index and d.steps[index]
    tipText:ClearAllPoints()
    tipText:SetPoint("TOPLEFT", 4, coordY - 6)
    local text
    if tgVal then
        text = "|cffffd100" .. translationHelper(tgVal.name) .. "|r\n" .. L.TRASH_TIP:format(#tgVal.loot)
    elseif index then
        text = "|cffffd100" .. ns.ResolveRouteStepDisplayTitle(d, index) .. "|r\n" .. translationHelper(step.tip)
    else
        text = "|cff55ff55" .. L.DONE_ALL .. "|r"
    end
    coordY = coordY - 6 - DungeonRouteWindow.resolveTextHeight(tipText, text, LIST_CONTENT_W - 8) - 8
    lootBar:ClearAllPoints()
    lootBar:SetPoint("TOPLEFT", 0, coordY)
    local used
    if tgVal then used = DungeonRouteWindow.plotLoot(tgVal.loot, L.LOOT .. " · " .. translationHelper(tgVal.name), tgVal.from)
    else used = DungeonRouteWindow.plotLoot(step and step.loot, L.LOOT .. (step and (" · " .. translationHelper(step.name)) or "")) end
    DungeonRouteWindow.finishList(-coordY + used + 8)
    tipText:Show()
    for subIndex = 1, #qrows do qrows[subIndex]:Hide() end
    questNote:Hide()
end

function DungeonRouteWindow.plotQuestList(d)
    DungeonRouteWindow.beginList(d, "quest")
    DungeonRouteWindow.dismissTrashBtns()
    for subIndex = 1, #rowWidgets do rowWidgets[subIndex]:Hide() end
    tipText:Hide()
    DungeonRouteWindow.plotLoot(nil)
    local coordY, entryKey = 0, 0
    for _, priorityQueue in ipairs(d.quests or {}) do
        if ns.IsRouteStepVisibleOnFloor(priorityQueue) then
            entryKey = entryKey + 1
            local rowEntry = DungeonRouteWindow.resolveQuestRow(entryKey)
            rowEntry.q = priorityQueue
            rowEntry:ClearAllPoints()
            rowEntry:SetPoint("TOPLEFT", 0, coordY)
            local stateEntry = DungeonRouteWindow.resolveQuestStatus(priorityQueue.id)
            local nameHeight = DungeonRouteWindow.resolveTextHeight(rowEntry.name, ns.QuestTitle(priorityQueue), LIST_CONTENT_W - 54)
            if stateEntry == "done" then rowEntry.status:SetText("|cff55ff55" .. L.Q_DONE .. "|r")
            elseif stateEntry == "active" then rowEntry.status:SetText("|cffffd100" .. L.Q_ACTIVE .. "|r")
            elseif priorityQueue.minLevel and (ns.CoerceSafeNumber(ns.UnwrapSafeValue(UnitLevel, "player")) or 0) < priorityQueue.minLevel then
                rowEntry.status:SetText("|cffff6666" .. L.Q_MINLEVEL:format(priorityQueue.minLevel) .. "|r")
            else rowEntry.status:SetText("|cff999999" .. L.Q_MISSING .. "|r") end
            local giverHeight = DungeonRouteWindow.resolveTextHeight(rowEntry.giver, translationHelper(priorityQueue.giver), LIST_CONTENT_W - 10)
            local rowHeight = nameHeight + 2 + giverHeight + 6
            rowEntry:SetHeight(rowHeight)
            coordY = coordY - rowHeight
            rowEntry:Show()
        end
    end
    for subIndex = entryKey + 1, #qrows do qrows[subIndex]:Hide() end
    questNote:ClearAllPoints()
    questNote:SetPoint("TOPLEFT", 4, coordY - 6)
    local noteHeight = DungeonRouteWindow.resolveTextHeight(questNote, entryKey == 0 and L.NO_QUESTS or L.Q_NOTE, LIST_CONTENT_W - 8)
    DungeonRouteWindow.finishList(-coordY + 6 + noteHeight + 8)
    questNote:Show()
end

function DungeonRouteWindow.plotNotes(d)
    DungeonRouteWindow.beginList(d, "notes")
    for subIndex = 1, #rowWidgets do rowWidgets[subIndex]:Hide() end
    for subIndex = 1, #qrows do qrows[subIndex]:Hide() end
    questNote:Hide()
    local parts = {}
    for _, nodeEntry in ipairs(d.notes or {}) do parts[#parts + 1] = "• " .. translationHelper(nodeEntry) end
    for _,connection in ipairs(d.routeConnections or {}) do
        parts[#parts + 1] = translationHelper(connection.text)
    end
    if d.entrance then
        parts[#parts + 1] = ("|cff4fd96f%s|r %s (%.1f, %.1f)"):format(L.LEG_ENTRANCE, translationHelper(d.entrance.zone), d.entrance.x, d.entrance.y)
    end
    DungeonRouteWindow.plotLoot(nil)

    local groups = d.trashGroups or {}
    tipText:ClearAllPoints()
    tipText:SetPoint("TOPLEFT", 4, 0)
    local height = DungeonRouteWindow.resolveTextHeight(tipText, #parts > 0 and table.concat(parts, "\n\n") or L.NO_NOTES, LIST_CONTENT_W - 8)
    local coordY = -height - 10
    for entryKey, greenVal in ipairs(groups) do
        local buttonWidget = trashBtns[entryKey]
        if not buttonWidget then
            buttonWidget = DungeonRouteWindow.createStyledButton(listContent, "", LIST_CONTENT_W, nil, function(self)
                unitState.selected = nil
                unitState.cardTrash = (unitState.cardTrash == self.index) and nil or self.index
                ns.RefreshMap()
            end)
            trashBtns[entryKey] = buttonWidget
            buttonWidget:EnableMouseWheel(true)
            buttonWidget:SetScript("OnMouseWheel", DungeonRouteWindow.listWheel)
        end
        buttonWidget.index = entryKey
        buttonWidget:SetText(("%s · %s %d"):format(translationHelper(greenVal.name), L.LOOT, #greenVal.loot))
        buttonWidget:ClearAllPoints()
        buttonWidget:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, coordY)
        buttonWidget:SetAlpha(unitState.cardTrash == entryKey and 1 or 0.85)
        buttonWidget:Show()
        coordY = coordY - 22
    end
    for subIndex = #groups + 1, #trashBtns do trashBtns[subIndex]:Hide() end
    DungeonRouteWindow.finishList(-coordY + 8)
    tipText:Show()
end

function ns.RefreshMap(mapOnly)
    if not containerFrame or not containerFrame:IsShown() then return end
    local d = unitState.viewed
    if not d then return end
    local nextIndex = ns.ResolveNextIncompleteStep(d)
    local page = DungeonRouteWindow.resolveCurrentPage(d)
    
    if page and not page.unavailable and (page.tiles or page.grid) and not DungeonRouteWindow.resolveTileSet(page) then
        blizFailed[d.key] = true
        page = DungeonRouteWindow.resolveCurrentPage(d)
    end
    view = DungeonRouteWindow.resolveNavigationView(d, page)
    unitState.shownPage = page and page.key
    local sig = tostring(d) .. tostring(page) .. tostring(ns.db.mapSize) .. tostring(ns.db.showList)
    if containerFrame.layoutSig ~= sig then containerFrame.layoutSig = sig; DungeonRouteWindow.layoutWindowRegions() end
    local sc = DungeonRouteWindow.calculateCanvasScale()
    zoomReset:SetShown(nav ~= nil)
    if nav then zoomReset:SetText(nav.zoom > 1 and ("%.1f×"):format(nav.zoom) or L.MAP_FIT) end
    titleStr:SetText(("%s |cffaaaaaa%s|r"):format(translationHelper(d.name), d.levels or ""))
    local away = unitState.current ~= nil and unitState.current ~= d
    currentBtn:SetEnabled(away)
    currentBtn:SetAlpha(away and 1 or 0.45)
    if not mapOnly and ns.db.showList then
        local done, grandTotal = ns.ComputeDungeonProgressCounts(d)
        progressText:SetText(("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12|t %d/%d"):format(done, grandTotal))
        local tab = ns.db.listTab
        if tab == "quest" then DungeonRouteWindow.plotQuestList(d) elseif tab == "notes" then DungeonRouteWindow.plotNotes(d) else DungeonRouteWindow.plotRouteList(d, nextIndex) end
        tabRoute:SetAlpha((tab ~= "quest" and tab ~= "notes") and 1 or 0.55)
        tabQuest:SetAlpha(tab == "quest" and 1 or 0.55)
        tabNotes:SetAlpha(tab == "notes" and 1 or 0.55)
    end
    if page then
        if page.unavailable then
            mapTex:Hide()
            DungeonRouteWindow.plotTiles(nil)
            DungeonRouteWindow.dismissMapLayer()
            DungeonRouteWindow.plotFlowLines(d, nil, sc)
        elseif page.flow then
            mapTex:Hide()
            DungeonRouteWindow.plotTiles(nil)
        elseif page.tiles or page.grid or page.img then
            mapTex:Hide()
            DungeonRouteWindow.plotTiles(page, sc)
        else
            DungeonRouteWindow.plotTiles(nil)
            mapTex:SetTexture(MAP_PATH .. page.map)
            mapTex:Show()
        end
        noMapText:SetText(page.unavailable and L.UNAVAILABLE_MINIMAP or L.NO_MAP)
        noMapText:SetShown(page.unavailable or false)
        if not page.unavailable then
            DungeonRouteWindow.plotMasks(page, sc)
            DungeonRouteWindow.plotMarkers(d, page, nextIndex, sc)
            DungeonRouteWindow.plotFlowLines(d, page, sc)
        end
    else
        mapTex:Hide()
        DungeonRouteWindow.plotTiles(nil)
        noMapText:Show()
        DungeonRouteWindow.dismissMapLayer()
        DungeonRouteWindow.plotFlowLines(d, nil, sc)
    end
    plotFloors(d, page)
    if mapOnly then return end
    
    local orientation = page and not page.unavailable and page.orientation
    orientationBadge:SetShown(orientation and true or false)
    if orientation then
        orientationBadge.northUp = orientation.mode == "north-up"
        orientationBadge.partial = page.partial
        orientationBadge.supplementalNative = page.supplementalNative
        local directionText = orientationBadge.northUp and L.MAP_NORTH_UP or L.MAP_GUIDE_UP
        if page.partial then directionText = directionText .. "\n|cffffb347" .. L.PARTIAL_MINIMAP .. "|r" end
        orientationBadge.text:SetText(directionText)
    end
    local parts = {}
    if unitState.edit then parts[#parts + 1] = "|cffff5555EDIT|r" end
    if unitState.current ~= d then parts[#parts + 1] = L.BROWSE_ONLY end
    if page and page.schematic then parts[#parts + 1] = L.SCHEMATIC end
    if page and page.flow then parts[#parts + 1] = L.FLOW_ONLY end
    if page and page.partial then parts[#parts + 1] = L.PARTIAL_MINIMAP end
    if page and page.approx then parts[#parts + 1] = L.APPROX end
    if page and page.tiles and d.bliz and d.bliz.preview then parts[#parts + 1] = L.PREVIEW_MAP end
    footerRegion:SetText(table.concat(parts, " · "))
    plotCard(d)
    DungeonRouteWindow.syncMenu()
end

function ns.ApplyAlpha()
    if not containerFrame then return end
    local a = ns.db.alpha
    if unitState.inCombat and ns.db.combatFade then a = math.min(a, ns.db.combatAlpha) end
    containerFrame:SetAlpha(a)
end

function ns.RebuildMap()
    if not containerFrame then return end
    containerFrame.layoutSig = nil
    DungeonRouteWindow.layoutWindowRegions()
    ns.RefreshMap()
end

function ns.SetMapStyle(style)
    ns.db.mapStyle = "blizzard" 
    for entryKey in pairs(blizFailed) do blizFailed[entryKey] = nil end
    for _, d in ipairs(ns.Dungeons) do
        for _, p in ipairs(d.bliz and d.bliz.pages or {}) do p.set = nil end
    end
    ns.Print(L.MAP_BLIZ)
    ns.RebuildMap()
end

local wingPicker
function ns.ShowWingPicker(candidates)
    if containerFrame then containerFrame:Hide() end
    if not wingPicker then
        wingPicker = CreateFrame("Frame", "EzWoW_DungeonRouteGuideWingPicker", UIParent, "BackdropTemplate")
        DungeonRouteWindow.applyPanelBackdrop(wingPicker, 0.97)
        wingPicker:SetPoint("CENTER")
        ns.UIKit:ElevateModal(wingPicker, 240)
        wingPicker:SetSize(330, 90 + #candidates * 28)
        wingPicker.heading = wingPicker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        wingPicker.heading:SetPoint("TOP", 0, -14)
        wingPicker.note = wingPicker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wingPicker.note:SetPoint("BOTTOM", 0, 14)
        wingPicker.buttons = {}
        local close = DungeonRouteWindow.createStyledButton(wingPicker, "X", 20, nil, function() wingPicker:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    wingPicker.heading:SetText(L.WING_TITLE)
    wingPicker.note:SetText(L.WING_WAIT)
    wingPicker:SetHeight(90 + #candidates * 28)
    for index, d in ipairs(candidates) do
        local buttonWidget = wingPicker.buttons[index]
        if not buttonWidget then
            buttonWidget = DungeonRouteWindow.createStyledButton(wingPicker, "", 306)
            buttonWidget:SetPoint("TOPLEFT", 12, -44 - (index - 1) * 28)
            buttonWidget:SetScript("OnClick", function(self) ns.SelectDungeon(self.dungeon) end)
            wingPicker.buttons[index] = buttonWidget
        end
        buttonWidget.dungeon = d; buttonWidget:SetText(translationHelper(d.name)); buttonWidget:Show()
    end
    for index = #candidates + 1, #wingPicker.buttons do wingPicker.buttons[index]:Hide() end
    wingPicker:Show()
end

function ns.HideWingPicker()
    if wingPicker then wingPicker:Hide() end
end

function ns.ShowMap(d, auto)
    if unitState.detectionPending and not unitState.current then
        ns.ShowWingPicker(unitState.detectionPending)
        return
    end
    if not containerFrame then DungeonRouteWindow.createPrimaryWidget() end
    unitState.viewed = d or unitState.viewed or unitState.current or (ns.SuggestDungeon and ns.SuggestDungeon()) or ns.Dungeons[1]
    containerFrame.autoShown = auto and true or false
    containerFrame:Show()
    ns.RefreshMap()
end

function ns.HideMapIfAuto()
    if containerFrame and containerFrame:IsShown() and containerFrame.autoShown then containerFrame:Hide() end
end

function ns.ToggleMap()
    if containerFrame and containerFrame:IsShown() then containerFrame:Hide() else ns.ShowMap(unitState.current or unitState.viewed) end
end

function ns.CycleViewedDungeonRoute(dir)
    local all = ns.Dungeons
    local entryIndex = 1
    for entryKey, d in ipairs(all) do if d == unitState.viewed then entryIndex = entryKey end end
    entryIndex = (entryIndex - 1 + dir) % #all + 1
    unitState.viewed = all[entryIndex]
    unitState.selected, unitState.cardTrash = nil, nil
    unitState.page, unitState.pageManual = nil, false
    ns.RefreshMap()
end

-----------------------------------------------------------------------------
-- Set Edit Mode
-----------------------------------------------------------------------------
function ns.SetEditMode(on)
    unitState.edit = on and true or false
    if on and (not containerFrame or not containerFrame:IsShown()) then ns.ShowMap(unitState.viewed or unitState.current) end
    ns.Print(unitState.edit and L.EDIT_ON or L.EDIT_OFF)
    ns.RefreshMap()
end

function ns.HandleRouteCanvasEditClick(button)
    if not unitState.edit then return end
    local d = unitState.viewed
    local index = unitState.selected or ns.ResolveNextIncompleteStep(d)
    if not d or not index then return end
    local step = d.steps[index]
    local cxVal, cyVal = GetCursorPosition()
    local stateFlag = canvasFrame:GetEffectiveScale()
    local sc = DungeonRouteWindow.calculateCanvasScale()
    local coordX = math.floor((cxVal / stateFlag - canvasFrame:GetLeft()) / sc + view[1] + 0.5)
    local coordY = math.floor((canvasFrame:GetTop() - cyVal / stateFlag) / sc + view[2] + 0.5)
    if not (d.pages and #d.pages > 0) and not DungeonRouteWindow.useBliz(d) then return end   
    local field = DungeonRouteWindow.useBliz(d) and "bpos" or "pos"
    if button == "RightButton" then
        local recordEntry = ns.GetDungeonManualRouteEdits(d, step)
        if recordEntry then recordEntry[field] = nil end
        ns.Print(L.EDIT_CLEAR:format(translationHelper(step.name)))
    else
        ns.GetDungeonManualRouteEdits(d, step, true)[field] = { coordX, coordY }
        ns.Print(L.EDIT_MARK:format(translationHelper(step.name), coordX, coordY))
    end
    ns.RefreshMap()
end

ns.ApplyFrameBackdrop = DungeonRouteWindow.applyPanelBackdrop
ns.CreateStyledButton = DungeonRouteWindow.createStyledButton
ns.SavePosition = DungeonRouteWindow.persistPosition
ns.Layout = DungeonRouteWindow.layoutWindowRegions
ns.GetMapFrame = function() return containerFrame end
ns.GetEditBtn = function() return editBtn end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
DungeonRouteWindow.ResolveFloorEncounterWidgets = ns.ResolveFloorEncounterWidgets
DungeonRouteWindow.ApplyFrameBackdrop = ns.ApplyFrameBackdrop
DungeonRouteWindow.CreateStyledButton = ns.CreateStyledButton
DungeonRouteWindow.CycleViewedDungeonRoute = ns.CycleViewedDungeonRoute
DungeonRouteWindow.HandleRouteCanvasEditClick = ns.HandleRouteCanvasEditClick
DungeonRouteWindow.ProjectStepToCanvasGeometry = ns.ProjectStepToCanvasGeometry
