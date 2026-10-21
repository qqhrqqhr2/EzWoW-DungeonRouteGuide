--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/WorldMapDockSearch.lua : WorldMap Dock Button & Dungeon Quick-Search Popover
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WorldMapDungeonSearch = ns.WorldMapDungeonSearch or {}
ns.WorldMapDungeonSearch = WorldMapDungeonSearch
local L, translationHelper = ns.L, ns.GetLocalizedText
local controls
ns.worldMapQuery = ""

-----------------------------------------------------------------------------
-- Has Auto Align
-----------------------------------------------------------------------------
function WorldMapDungeonSearch.hasAutoAlign()
    return not ns.db or ns.db.worldMapAutoAlign ~= false
end

function WorldMapDungeonSearch.positionButton(c, x, y, save)
    local dock = _G.EzWoWWorldMapDock
    local container = (dock and dock:GetCanvas()) or c.container
    c.container = container
    if dock and dock.NormalizeButtonParent then
        dock:NormalizeButtonParent(c.button, container)
    end
    local boxWidth = ns.CoerceSafeNumber(ns.UnwrapSafeValue(container.GetWidth, container))
    local headerBar = ns.CoerceSafeNumber(ns.UnwrapSafeValue(container.GetHeight, container))
    if not boxWidth or not headerBar or boxWidth <= 0 or headerBar <= 0 then return end
    if WorldMapDungeonSearch.hasAutoAlign() and not save and not x and not y and dock then
        dock:Layout()
        return
    end
    local coordPos = ns.db.frames.worldMapTools or {}
    x = x or (ns.CoerceSafeNumber(coordPos.x) or 0.04) * boxWidth
    y = y or (ns.CoerceSafeNumber(coordPos.y) or 0.22) * headerBar
    local mxVal, myVal = math.min(18, boxWidth / 2), math.min(18, headerBar / 2)
    x, y = math.max(mxVal, math.min(boxWidth - mxVal, x)), math.max(myVal, math.min(headerBar - myVal, y))
    c.button:SetSize(28, 28)
    c.button:ClearAllPoints(); c.button:SetPoint("CENTER", container, "BOTTOMLEFT", x, y)
    c.buttonX, c.buttonY = x, y
    if save then ns.db.frames.worldMapTools = {x = x / boxWidth, y = y / headerBar} end
end

function WorldMapDungeonSearch.resolveCursor(c)
    local dock = _G.EzWoWWorldMapDock
    if dock and dock.GetCursorCanvasXY then
        local rx, ry = dock:GetCursorCanvasXY(c.button)
        if rx and ry then return rx, ry end
    end
    local x, y = ns.UnwrapSafeValue(GetCursorPosition)
    x, y = ns.CoerceSafeNumber(x), ns.CoerceSafeNumber(y)
    local calculateCanvasScale = ns.CoerceSafeNumber(ns.UnwrapSafeValue(c.button.GetEffectiveScale, c.button))
        or ns.CoerceSafeNumber(ns.UnwrapSafeValue(c.container.GetEffectiveScale, c.container))
    local left = ns.CoerceSafeNumber(ns.UnwrapSafeValue(c.container.GetLeft, c.container))
    local bottom = ns.CoerceSafeNumber(ns.UnwrapSafeValue(c.container.GetBottom, c.container))
    if x and y and calculateCanvasScale and calculateCanvasScale > 0 and left and bottom then
        return x / calculateCanvasScale - left, y / calculateCanvasScale - bottom
    end
end

function ns.WorldMapMatches(d)
    local query = ns.worldMapQuery or ""
    if query == "" then return true end
    local values = ns.AllLocalizedTexts(d.name)
    values[#values + 1], values[#values + 2] = d.key, d.slug
    for _, value in ipairs(values) do
        local extractSafeTooltipText = ns.Normalize(value)
        if extractSafeTooltipText and extractSafeTooltipText:find(query, 1, true) then return true end
    end
    return false
end

function WorldMapDungeonSearch.launchDungeonOnWorldMap(d)
    if not d then return end
    local recordEntry = (ns.db.entrances and ns.db.entrances[d.key]) or d.entrance
    if not recordEntry then return end
    local entityID, x, y = ns.CoerceSafeNumber(recordEntry.map), ns.CoerceSafeNumber(recordEntry.x), ns.CoerceSafeNumber(recordEntry.y)
    if not entityID or entityID <= 0 or not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then return end
    local apiInfo = ns.UnwrapSafeValue(C_Map and C_Map.GetMapInfo, entityID)
    if not ns.IsReadableValue(apiInfo) or type(apiInfo) ~= "table" then return end
    ns.UnwrapSafeValue(WorldMapFrame.SetMapID, WorldMapFrame, entityID)
    ns.UnwrapSafeValue(WorldMapFrame.PanTo, WorldMapFrame, x / 100, y / 100)
end

function WorldMapDungeonSearch.locateDungeon()
    local query = ns.worldMapQuery or ""
    if query == "" then return end
    local first
    for _, d in ipairs(ns.Dungeons) do
        if ns.WorldMapMatches(d) then
            first = first or d
            local values = ns.AllLocalizedTexts(d.name)
            values[#values + 1], values[#values + 2] = d.key, d.slug
            for _, value in ipairs(values) do
                if ns.Normalize(value) == query then return d end
            end
        end
    end
    return first
end

function WorldMapDungeonSearch.launchSearchRegion()
    local d = WorldMapDungeonSearch.locateDungeon()
    if d then WorldMapDungeonSearch.launchDungeonOnWorldMap(d) end
end

function WorldMapDungeonSearch.createActionButton(parent, extractSafeTooltipText, width, action)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(width, 20)
    if buttonWidget.SetBackdrop then
        buttonWidget:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        buttonWidget:SetBackdropColor(0.071, 0.094, 0.122, 0.96)
        buttonWidget:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
    end
    local labelRegion = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelRegion:SetPoint("CENTER")
    labelRegion:SetTextColor(0.929, 0.957, 0.969, 1.00)
    labelRegion:SetText(extractSafeTooltipText or "")
    buttonWidget.label = labelRegion
    -- Grows with long translations up to maxW, then shrinks the text
    function buttonWidget:SetText(txt)
        labelRegion:SetText(txt or "")
        ns.UIKit:SizeButtonToText(buttonWidget, labelRegion, width, buttonWidget.maxW or width, 10)
    end
    function buttonWidget:GetText() return labelRegion:GetText() end
    buttonWidget:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.18, 0.23, 0.29, 1.00)
            self:SetBackdropBorderColor(0.918, 0.514, 0.494, 1.00)
        end
    end)
    buttonWidget:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.071, 0.094, 0.122, 0.96)
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
    end)
    buttonWidget:SetScript("OnMouseDown", function() labelRegion:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() labelRegion:SetPoint("CENTER", 0, 0) end)
    buttonWidget:SetScript("OnClick", action)
    return buttonWidget
end

local VISIBLE_DUNGEON_ROWS = 6

function ns.RefreshWorldMapControls()
    if not controls then return end
    if not controls.panel:IsShown() then return end
    local c = controls
    c.title:SetText("EzWoW - Dungeon Route Guide")
    if c.cfgBtn then c.cfgBtn:SetText(L.BTN_MENU) end
    if c.mapBtn then c.mapBtn:SetText(L.BTN_MAP) end
    if c.searchHint then
        local priorityQueue = c.search:GetText() or ""
        c.searchHint:SetText(L.BTN_PICK or "Search...")
        c.searchHint:SetShown(priorityQueue == "" and not c.search:HasFocus())
        if c.clear then c.clear:SetShown(priorityQueue ~= "") end
    end

    local matches = {}
    for _, d in ipairs(ns.Dungeons) do
        if ns.WorldMapMatches(d) then
            matches[#matches + 1] = d
        end
    end
    c.matches = matches
    c.matchCount = #matches

    local maxScroll = math.max(0, #matches - VISIBLE_DUNGEON_ROWS)
    c.scrollOffset = math.max(0, math.min(c.scrollOffset or 0, maxScroll))

    for index = 1, VISIBLE_DUNGEON_ROWS do
        local rowEntry = c.rows[index]
        local d = matches[c.scrollOffset + index]
        if d then
            rowEntry.dungeon = d
            rowEntry.name:SetText(translationHelper(d.name))
            rowEntry.lvl:SetText(d.levels or "")
            rowEntry:Show()
        else
            rowEntry.dungeon = nil
            rowEntry:Hide()
        end
    end

    if #matches == 0 then
        c.emptyText:SetText(L.WORLD_NO_RESULT)
        c.emptyText:Show()
    else
        c.emptyText:Hide()
    end

    local rowsCount = math.min(VISIBLE_DUNGEON_ROWS, math.max(1, #matches))
    c.panel:SetHeight(64 + rowsCount * 20 + 6)
end

function ns.CreateWorldMapControls()
    if controls then return end
    controls = { rows = {}, scrollOffset = 0 }
    ns.WorldMapControls = controls
    local c = controls
    local container = (_G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock:GetCanvas()) or WorldMapFrame.ScrollContainer or WorldMapFrame
    c.container = container
    local strata = ns.CoerceSafeString(ns.UnwrapSafeValue(WorldMapFrame.GetFrameStrata, WorldMapFrame)) or "HIGH"
    local level = ns.CoerceSafeNumber(ns.UnwrapSafeValue(WorldMapFrame.GetFrameLevel, WorldMapFrame)) or 0
    c.button = CreateFrame("Button", "EzWoW_DungeonRouteGuideWorldMapButton", container)
    c.button:SetSize(28, 28)
    local iconTex = "Interface\\AddOns\\EzWoW-DungeonRouteGuide\\Media\\icon"
    c.button.icon = c.button:CreateTexture(nil, "ARTWORK")
    c.button.icon:SetTexture(iconTex)
    c.button.icon:SetAllPoints()
    local highlight = c.button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(iconTex)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD"); highlight:SetAlpha(0.35)
    c.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.button:RegisterForDrag("LeftButton")
    c.button:SetScript("OnMouseDown", function() c.ignoreClick = nil end)
    c.button:SetScript("OnClick", function(_, button)
        if c.ignoreClick then c.ignoreClick = nil; return end
        if button == "RightButton" then
            ns.db.worldMapAutoAlign = true
            if ns.db.frames then ns.db.frames.worldMapTools = nil end
            if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
            ns.RefreshWorldMapControls()
            return
        end
        GameTooltip_Hide()
        if c.panel:IsShown() then
            c.panel:Hide()
        else
            if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.CloseOthers then
                _G.EzWoWWorldMapDock:CloseOthers("EzWoW_DungeonRouteGuide")
            end
            c.panel:Show()
        end
    end)
    c.button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("EzWoW - Dungeon Route Guide", 0.918, 0.514, 0.494)
        local lineList = {}
        for line in tostring(L.WORLD_RIGHT_CLICK or ""):gmatch("[^\n]+") do
            lineList[#lineList + 1] = line
        end
        if lineList[1] then GameTooltip:AddLine(lineList[1], 0.929, 0.957, 0.969) end
        for index = 2, #lineList do
            GameTooltip:AddLine(lineList[index], 0.655, 0.725, 0.773)
        end
        GameTooltip:Show()
    end)
    c.button:SetScript("OnLeave", GameTooltip_Hide)
    c.button:SetScript("OnDragStart", function(self)
        local dock = _G.EzWoWWorldMapDock
        local x, y = WorldMapDungeonSearch.resolveCursor(c)
        if not x then return end
        local btnCX, btnCY = c.buttonX, c.buttonY
        if dock and dock.GetButtonCanvasCenter then
            local cx, cy = dock:GetButtonCanvasCenter(self)
            if cx and cy then btnCX, btnCY = cx, cy end
        end
        btnCX = btnCX or x
        btnCY = btnCY or y
        c.dragX, c.dragY = btnCX - x, btnCY - y
        WorldMapDungeonSearch.positionButton(c, btnCX, btnCY, true)
        if WorldMapDungeonSearch.hasAutoAlign() then
            ns.db.worldMapAutoAlign = false
            if dock then dock:Layout() end
        end
        c.ignoreClick = true; c.panel:Hide(); GameTooltip_Hide()
        self:SetScript("OnUpdate", function()
            local cxVal, cyVal = WorldMapDungeonSearch.resolveCursor(c)
            if cxVal then WorldMapDungeonSearch.positionButton(c, cxVal + c.dragX, cyVal + c.dragY, true) end
        end)
    end)
    c.button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        WorldMapDungeonSearch.positionButton(c, c.buttonX, c.buttonY, true)
        if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
    end)
    c.button:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    c.button:SetScript("OnShow", function() WorldMapDungeonSearch.positionButton(c) end)
    container:HookScript("OnSizeChanged", function() WorldMapDungeonSearch.positionButton(c) end)
    c.button:SetFrameStrata(strata); c.button:SetFrameLevel(level + 500)

    if _G.EzWoWWorldMapDock then
        _G.EzWoWWorldMapDock:Register("EzWoW_DungeonRouteGuide", {
            order = 3,
            button = c.button,
            isAuto = WorldMapDungeonSearch.hasAutoAlign,
            closePanel = function()
                if c.panel then c.panel:Hide() end
            end,
            onDockedLayout = function(btn, canvas, idx, total, x, y)
                c.buttonX = x + 14
                c.buttonY = y + 14
            end,
            onFreeLayout = function()
                WorldMapDungeonSearch.positionButton(c)
            end,
        })
    else
        WorldMapDungeonSearch.positionButton(c)
    end

    c.panel = CreateFrame("Frame", nil, WorldMapFrame, "BackdropTemplate")
    c.panel:SetFrameStrata(strata); c.panel:SetFrameLevel(level + 510)
    c.panel:SetClampedToScreen(true); c.panel:EnableMouse(true)
    c.panel:SetPoint("BOTTOMLEFT", c.button, "BOTTOMRIGHT", 6, 0)
    c.panel:SetSize(272, 190)
    c.panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    c.panel:SetBackdropColor(0.071, 0.094, 0.122, 0.96)
    c.panel:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)

    local headerBg = c.panel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", -1, -1)
    headerBg:SetHeight(29)
    headerBg:SetColorTexture(0.114, 0.157, 0.192, 0.96)

    local headerLine = c.panel:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerBg, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(0.918, 0.514, 0.494, 1.00)

    c.closeBtn = WorldMapDungeonSearch.createActionButton(c.panel, "X", 20, function() c.panel:Hide() end)
    c.closeBtn:SetPoint("TOPRIGHT", -5, -5)

    c.cfgBtn = WorldMapDungeonSearch.createActionButton(c.panel, L.BTN_MENU, 40, function()
        if ns.ToggleConfig then ns.ToggleConfig() end
    end)
    c.cfgBtn:SetPoint("RIGHT", c.closeBtn, "LEFT", -3, 0)
    c.cfgBtn.maxW = 70

    c.mapBtn = WorldMapDungeonSearch.createActionButton(c.panel, L.BTN_MAP, 44, function()
        if ns.ToggleMap then ns.ToggleMap() end
    end)
    c.mapBtn:SetPoint("RIGHT", c.cfgBtn, "LEFT", -3, 0)
    c.mapBtn.maxW = 70

    c.title = c.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.title:SetPoint("TOPLEFT", 10, -9)
    c.title:SetPoint("RIGHT", c.mapBtn, "LEFT", -4, 0)
    c.title:SetJustifyH("LEFT")
    if c.title.SetWordWrap then c.title:SetWordWrap(false) end
    c.title:SetTextColor(0.918, 0.514, 0.494)

    c.search = CreateFrame("EditBox", nil, c.panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c.search:SetSize(256, 20); c.search:SetPoint("TOPLEFT", 8, -36)
    c.search:SetFontObject(ChatFontNormal)
    c.search:SetTextInsets(6, 22, 0, 0)
    c.search:SetAutoFocus(false); c.search:SetMaxLetters(64)
    if c.search.SetBackdrop then
        c.search:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        c.search:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        c.search:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
    end
    c.searchHint = c.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.searchHint:SetPoint("LEFT", c.search, "LEFT", 6, 0)
    c.searchHint:SetTextColor(0.655, 0.725, 0.773, 0.85)

    c.clear = WorldMapDungeonSearch.createActionButton(c.search, "X", 16, function() c.search:SetText(""); c.search:SetFocus() end)
    c.clear:SetSize(16, 16)
    c.clear:SetPoint("RIGHT", c.search, "RIGHT", -2, 0)
    c.clear:Hide()

    c.search:SetScript("OnEditFocusGained", function(self)
        c.searchHint:Hide()
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(0.918, 0.514, 0.494, 1.00)
        end
    end)
    c.search:SetScript("OnEditFocusLost", function(self)
        c.searchHint:SetShown((self:GetText() or "") == "")
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
    end)

    c.panel:EnableMouseWheel(true)
    c.panel:SetScript("OnMouseWheel", function(_, delta)
        c.scrollOffset = (c.scrollOffset or 0) - delta * 2
        ns.RefreshWorldMapControls()
    end)

    for index = 1, VISIBLE_DUNGEON_ROWS do
        local rowEntry = CreateFrame("Button", nil, c.panel)
        rowEntry:SetHeight(20)
        rowEntry:SetPoint("TOPLEFT", 6, -62 - (index - 1) * 20)
        rowEntry:SetPoint("RIGHT", -6, 0)
        rowEntry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rowEntry:EnableMouseWheel(true)
        rowEntry:SetScript("OnMouseWheel", function(_, delta)
            c.scrollOffset = (c.scrollOffset or 0) - delta * 2
            ns.RefreshWorldMapControls()
        end)

        rowEntry.hl = rowEntry:CreateTexture(nil, "HIGHLIGHT")
        rowEntry.hl:SetAllPoints()
        rowEntry.hl:SetColorTexture(0.918, 0.514, 0.494, 0.14)

        rowEntry.lvl = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        rowEntry.lvl:SetPoint("RIGHT", -6, 0)
        rowEntry.lvl:SetJustifyH("RIGHT")
        rowEntry.lvl:SetTextColor(0.655, 0.725, 0.773)

        rowEntry.name = rowEntry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rowEntry.name:SetPoint("LEFT", 6, 0)
        rowEntry.name:SetPoint("RIGHT", rowEntry.lvl, "LEFT", -6, 0)
        rowEntry.name:SetJustifyH("LEFT")
        if rowEntry.name.SetWordWrap then rowEntry.name:SetWordWrap(false) end
        rowEntry.name:SetTextColor(0.929, 0.957, 0.969)

        rowEntry:SetScript("OnEnter", function(self)
            if not self.dungeon then return end
            local d = self.dungeon
            local recordEntry = (ns.db.entrances and ns.db.entrances[d.key]) or d.entrance
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(translationHelper(d.name), 0.918, 0.514, 0.494)
            if d.levels then
                GameTooltip:AddLine("Lv " .. d.levels, 0.929, 0.957, 0.969)
            end
            if recordEntry and recordEntry.zone then
                GameTooltip:AddLine(translationHelper(recordEntry.zone) .. (" (%.1f, %.1f)"):format(recordEntry.x or 0, recordEntry.y or 0), 0.655, 0.725, 0.773)
            end
            local qTotal, qActive, qDone = 0, 0, 0
            for _, priorityQueue in ipairs(d.quests or {}) do
                if not ns.IsRouteStepVisibleOnFloor or ns.IsRouteStepVisibleOnFloor(priorityQueue) then
                    qTotal = qTotal + 1
                    local stateEntry = ns.QuestStatus and ns.QuestStatus(priorityQueue.id)
                    if stateEntry == "done" then qDone = qDone + 1
                    elseif stateEntry == "active" then qActive = qActive + 1 end
                end
            end
            if qTotal > 0 and L.WORLD_ROW_QUESTS then
                GameTooltip:AddLine(L.WORLD_ROW_QUESTS:format(qTotal, qActive, qDone), 0.95, 0.78, 0.35)
            end
            if L.WORLD_ROW_HINT then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L.WORLD_ROW_HINT, 0.5, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        rowEntry:SetScript("OnLeave", GameTooltip_Hide)
        rowEntry:SetScript("OnClick", function(self, btn)
            if not self.dungeon then return end
            if btn == "RightButton" then
                if ns.ShowMap then ns.ShowMap(self.dungeon) end
            else
                WorldMapDungeonSearch.launchDungeonOnWorldMap(self.dungeon)
            end
        end)
        c.rows[index] = rowEntry
    end

    c.emptyText = c.panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.emptyText:SetPoint("TOP", 0, -68)
    c.emptyText:SetTextColor(0.655, 0.725, 0.773)
    c.emptyText:Hide()

    c.search:SetScript("OnTextChanged", function(self)
        if c.suppress then return end
        c.scrollOffset = 0
        ns.worldMapQuery = ns.Normalize(ns.CoerceSafeString(ns.UnwrapSafeValue(self.GetText, self))) or ""
        ns.RefreshWorldMap()
    end)
    c.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        WorldMapDungeonSearch.launchSearchRegion()
    end)
    c.search:SetScript("OnEscapePressed", function(self)
        if (ns.worldMapQuery or "") ~= "" then self:SetText("") else c.panel:Hide() end
        self:ClearFocus()
    end)
    c.panel:SetScript("OnShow", function()
        ns.RefreshWorldMapControls()
    end)
    c.panel:SetScript("OnHide", function()
        c.suppress = true; c.search:SetText(""); c.search:ClearFocus(); c.suppress = false
        ns.worldMapQuery = ""; ns.RefreshWorldMap()
    end)
    c.panel:Hide()
    c.button:Show()
    if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
end
