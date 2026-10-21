--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/OptionsWindow.lua : EzWoW Style Settings Dialog, Route Export & Blizzard Panel
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog
local L, translationHelper = ns.L, ns.GetLocalizedText
local state = ns.state
local applyPanelBackdrop = ns.ApplyFrameBackdrop
local createStyledButtonEntry = ns.CreateStyledButton
local persistPosition = ns.SavePosition
local layoutWindowRegions = ns.Layout

local exportFrame
function ns.ShowExport()
    local outputList = { "-- EzWoW_DungeonRouteGuide native-70338-v1; manual edits are reference positions" }
    for _, dataEntry in ipairs(ns.Dungeons) do
        local rowEntry = ns.db.routes[dataEntry.key .. (dataEntry.editSpace or "")]
        if rowEntry then
            for _, step in ipairs(dataEntry.steps) do
                local recordEntry = rowEntry[step.id]
                if recordEntry then
                    local parts = {}
                    if recordEntry.pos then parts[#parts + 1] = ("pos = { %d, %d }"):format(recordEntry.pos[1], recordEntry.pos[2]) end
                    if recordEntry.bpos then parts[#parts + 1] = ("bliz = { %d, %d }"):format(recordEntry.bpos[1], recordEntry.bpos[2]) end
                    if recordEntry.path then
                        local pts = {}
                        for _, anchorTarget in ipairs(recordEntry.path) do pts[#pts + 1] = ("{ %d, %d }"):format(anchorTarget[1], anchorTarget[2]) end
                        parts[#parts + 1] = "path = { " .. table.concat(pts, ", ") .. " }"
                    end
                    outputList[#outputList + 1] = ("-- %s / %s\n%s"):format(dataEntry.key, step.id, table.concat(parts, ",\n"))
                end
            end
        end
    end
    local extractSafeTooltipText = #outputList > 0 and table.concat(outputList, "\n\n") or "-- no edits"
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "EzWoW_DungeonRouteGuideExport", UIParent, "BackdropTemplate")
        applyPanelBackdrop(exportFrame, 0.95)
        exportFrame:SetSize(440, 280)
        exportFrame:SetPoint("CENTER")
        ns.UIKit:ElevateModal(exportFrame, 260)
        exportFrame:EnableMouse(true)
        exportFrame:SetMovable(true)
        exportFrame:RegisterForDrag("LeftButton")
        exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
        exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
        local hint = exportFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 8, -8)
        ns.GetLocalizedEntryField(hint, "EXPORT_HINT")
        local close = createStyledButtonEntry(exportFrame, "X", 22, nil, function() exportFrame:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -4)
        local scrollFrame = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 8, -28)
        scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)
        local edit = CreateFrame("EditBox", nil, scrollFrame)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(390)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
        scrollFrame:SetScrollChild(edit)
        exportFrame.edit = edit
        if UISpecialFrames then tinsert(UISpecialFrames, "EzWoW_DungeonRouteGuideExport") end
    end
    ns.UIKit:ElevateModal(exportFrame, 260)
    exportFrame.edit:SetText(extractSafeTooltipText)
    exportFrame:Show()
    if exportFrame.Raise then exportFrame:Raise() end
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

local donateFrame
function ns.ShowDonate()
    if ns.DONATE_URL == "" then return end
    if not donateFrame then
        donateFrame = CreateFrame("Frame", "EzWoW_DungeonRouteGuideDonate", UIParent, "BackdropTemplate")
        applyPanelBackdrop(donateFrame, 0.96)
        donateFrame:SetSize(390, 132)
        donateFrame:SetPoint("CENTER", 0, 120)
        ns.UIKit:ElevateModal(donateFrame, 260)
        donateFrame:EnableMouse(true)
        donateFrame:SetMovable(true)
        donateFrame:RegisterForDrag("LeftButton")
        donateFrame:SetScript("OnDragStart", donateFrame.StartMoving)
        donateFrame:SetScript("OnDragStop", donateFrame.StopMovingOrSizing)
        local logo = donateFrame:CreateTexture(nil, "ARTWORK")
        logo:SetTexture("Interface\\AddOns\\EzWoW-DungeonRouteGuide\\Media\\icon")
        logo:SetSize(32, 32); logo:SetPoint("TOPLEFT", 14, -14)
        local extractSafeTooltipText = donateFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        extractSafeTooltipText:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 0); extractSafeTooltipText:SetPoint("RIGHT", -34, 0)
        extractSafeTooltipText:SetJustifyH("LEFT")
        ns.GetLocalizedEntryField(extractSafeTooltipText, "DONATE_TEXT")
        local close = createStyledButtonEntry(donateFrame, "X", 22, nil, function() donateFrame:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetFrameLevel(donateFrame:GetFrameLevel() + 5)
        local editBox = CreateFrame("EditBox", nil, donateFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        editBox:SetSize(356, 24)
        editBox:SetPoint("BOTTOM", 0, 14)
        editBox:SetFrameLevel(donateFrame:GetFrameLevel() + 5)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetTextInsets(6, 6, 0, 0)
        if editBox.SetBackdrop then
            editBox:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets   = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            editBox:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
            editBox:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
        end
        
        editBox:SetScript("OnTextChanged", function(self, user) if user then self:SetText(ns.DONATE_URL); self:HighlightText() end end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.918, 0.514, 0.494, 1.00)
            end
        end)
        editBox:SetScript("OnEditFocusLost", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(0.204, 0.298, 0.357, 1.00)
            end
        end)
        editBox:SetScript("OnEscapePressed", function() donateFrame:Hide() end)
        donateFrame.box = editBox
        if UISpecialFrames then tinsert(UISpecialFrames, "EzWoW_DungeonRouteGuideDonate") end
    end
    ns.UIKit:ElevateModal(donateFrame, 260)
    donateFrame.box:SetText(ns.DONATE_URL)
    donateFrame:Show()
    if donateFrame.Raise then donateFrame:Raise() end
    donateFrame.box:SetFocus()
    donateFrame.box:HighlightText()
end

local configFrame, BlizzardOptionsCanvas
local ROUTE_THEME = {
    bg     = { 0.071, 0.094, 0.122, 0.97 },
    bgSub  = { 0.114, 0.157, 0.192, 0.96 },
    border = { 0.204, 0.298, 0.357, 1.00 },
    accent = { 0.918, 0.514, 0.494, 1.00 }, 
    text   = { 0.929, 0.957, 0.969, 1.00 },
    muted  = { 0.655, 0.725, 0.773, 1.00 },
}
local ROUTE_GUIDE_ICON = "Interface\\AddOns\\EzWoW-DungeonRouteGuide\\Media\\icon"

function SettingsDialog.cleanColonVal(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("%s*:.*$", ""):gsub("%s*%%.*$", ""))
end

function SettingsDialog.buildConfigWindow()
    if configFrame then return configFrame end
    local windowFrame = CreateFrame("Frame", "EzWoW_DungeonRouteGuideConfig", UIParent, "BackdropTemplate")
    windowFrame:SetSize(460, 470)
    windowFrame:SetPoint("CENTER")
    windowFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    windowFrame:SetToplevel(true)
    windowFrame:SetClampedToScreen(true)
    windowFrame:SetMovable(true)
    windowFrame:EnableMouse(true)
    windowFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    windowFrame:SetBackdropColor(unpack(ROUTE_THEME.bg))
    windowFrame:SetBackdropBorderColor(unpack(ROUTE_THEME.border))
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoW_DungeonRouteGuideConfig") end

    local top = CreateFrame("Frame", nil, windowFrame, "BackdropTemplate")
    top:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -1, -1)
    top:SetHeight(56)
    top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    top:SetBackdropColor(unpack(ROUTE_THEME.bgSub))
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() windowFrame:StartMoving() end)
    top:SetScript("OnDragStop", function() windowFrame:StopMovingOrSizing() end)

    local accentLine = top:CreateTexture(nil, "ARTWORK")
    accentLine:SetColorTexture(unpack(ROUTE_THEME.accent))
    accentLine:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(2)

    local titleIcon = top:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(28, 28)
    titleIcon:SetPoint("TOPLEFT", 14, -14)
    titleIcon:SetTexture(ROUTE_GUIDE_ICON)

    local headingRegion = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headingRegion:SetPoint("TOPLEFT", 48, -11)
    headingRegion:SetText("EzWoW - Dungeon Route Guide")
    headingRegion:SetTextColor(unpack(ROUTE_THEME.accent))

    local subtitleRegion = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleRegion:SetPoint("TOPLEFT", headingRegion, "BOTTOMLEFT", 0, -3)
    subtitleRegion:SetWidth(365)
    subtitleRegion:SetJustifyH("LEFT")
    subtitleRegion:SetTextColor(unpack(ROUTE_THEME.muted))

    local syncCfg

    local function createSectionDivider(y)
        local resolvedValue = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resolvedValue:SetPoint("TOPLEFT", 20, y)
        resolvedValue:SetTextColor(unpack(ROUTE_THEME.accent))
        local line = windowFrame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.204, 0.298, 0.357, 0.85)
        line:SetPoint("TOPLEFT", windowFrame, "TOPLEFT", 20, y - 18)
        line:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -20, y - 18)
        line:SetHeight(1)
        return resolvedValue
    end

    local function createStyledButton(x, y, w, h, isAccent, onClick)
        local buttonWidget = CreateFrame("Button", nil, windowFrame, "BackdropTemplate")
        buttonWidget:SetSize(w, h)
        buttonWidget:SetPoint("TOPLEFT", x, y)
        buttonWidget:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        local function applyNormalButtonLook()
            if isAccent then
                buttonWidget:SetBackdropColor(0.24, 0.14, 0.15, 0.96)
                buttonWidget:SetBackdropBorderColor(unpack(ROUTE_THEME.accent))
            else
                buttonWidget:SetBackdropColor(unpack(ROUTE_THEME.bgSub))
                buttonWidget:SetBackdropBorderColor(unpack(ROUTE_THEME.border))
            end
        end
        applyNormalButtonLook()
        local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        formatLocalizedLabel:SetPoint("CENTER")
        formatLocalizedLabel:SetTextColor(unpack(isAccent and ROUTE_THEME.accent or ROUTE_THEME.text))
        buttonWidget.label = formatLocalizedLabel
        buttonWidget.fitWidth = w - 8
        buttonWidget:SetScript("OnEnter", function()
            buttonWidget:SetBackdropColor(0.20, 0.24, 0.30, 1)
            buttonWidget:SetBackdropBorderColor(unpack(ROUTE_THEME.accent))
        end)
        buttonWidget:SetScript("OnLeave", applyNormalButtonLook)
        buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
        buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
        buttonWidget:SetScript("OnClick", onClick)
        return buttonWidget
    end

    local close = createStyledButton(428, -14, 22, 22, false, function() windowFrame:Hide() end)
    close.label:SetText("X")
    close:SetFrameLevel(top:GetFrameLevel() + 3)

    local cfgChecks = {}
    local function createStyledCheckbox(x, y, w, resolveLabel, readOptionValue, writeOptionValue, attachHoverTooltip)
        local themeColor = CreateFrame("CheckButton", nil, windowFrame, "UICheckButtonTemplate")
        themeColor:SetSize(24, 24)
        themeColor:SetPoint("TOPLEFT", x, y)
        local displayText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        displayText:SetPoint("LEFT", themeColor, "RIGHT", 4, 0)
        displayText:SetWidth(w or 180)
        displayText:SetJustifyH("LEFT")
        displayText:SetTextColor(unpack(ROUTE_THEME.text))
        themeColor.txt = displayText
        themeColor.txtWidth = w or 180
        themeColor.resolveLabel = resolveLabel
        themeColor.readValue = readOptionValue
        themeColor:SetScript("OnClick", function(self)
            writeOptionValue(self:GetChecked() and true or false)
            ns.RefreshAll()
            syncCfg()
        end)
        if attachHoverTooltip then
            themeColor:SetScript("OnEnter", function(self)
                local resolvedValue = attachHoverTooltip()
                if not resolvedValue or resolvedValue == "" then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(resolveLabel(), unpack(ROUTE_THEME.accent))
                GameTooltip:AddLine(resolvedValue, 0.85, 0.90, 0.95, true)
                GameTooltip:Show()
            end)
            themeColor:SetScript("OnLeave", GameTooltip_Hide)
        end
        cfgChecks[#cfgChecks + 1] = themeColor
        return themeColor
    end

    local sec1 = createSectionDivider(-70)
    local langBtn = createStyledButton(240, -66, 200, 20, false, nil)
    -- click the box, then pick a language from the list
    local langItems = {}
    for index, code in ipairs({ "auto", "ko", "en", "de", "fr", "es", "ru", "zhCN", "zhTW" }) do
        langItems[index] = { value = code, text = function() return L["LANG_" .. code] end }
    end
    ns.LanguageDropdown.Attach(langBtn, {
        items = langItems,
        colors = { bg = ROUTE_THEME.bg, border = ROUTE_THEME.border, accent = ROUTE_THEME.accent, text = ROUTE_THEME.text },
        get = function() return ns.db.lang or "auto" end,
        set = function(code)
            ns.ChangeLanguage(code)
            syncCfg()
        end,
    })

    createStyledCheckbox(18, -94, 180, function() return SettingsDialog.cleanColonVal(L.OPT_AUTO) end,
        function() return ns.db.autoOpen end, function(v) ns.db.autoOpen = v end,
        function() return L.TIP_OPT_AUTO end)
    createStyledCheckbox(232, -94, 180, function() return SettingsDialog.cleanColonVal(L.OPT_HUD) end,
        function() return ns.db.hud end, function(v) ns.db.hud = v; ns.RefreshHUD() end,
        function() return L.TIP_OPT_HUD end)
    createStyledCheckbox(18, -120, 180, function() return SettingsDialog.cleanColonVal(L.OPT_RARE) end,
        function() return ns.db.rareAlert end, function(v) ns.db.rareAlert = v end,
        function() return L.TIP_OPT_RARE end)
    createStyledCheckbox(232, -120, 180, function() return SettingsDialog.cleanColonVal(L.OPT_FADE) end,
        function() return ns.db.combatFade end, function(v) ns.db.combatFade = v; ns.ApplyAlpha() end,
        function() return L.TIP_OPT_FADE end)
    createStyledCheckbox(18, -146, 180, function() return SettingsDialog.cleanColonVal(L.OPT_LOCK) end,
        function() return ns.db.locked end, function(v) ns.db.locked = v end,
        function() return L.TIP_OPT_LOCK end)
    createStyledCheckbox(232, -146, 180, function() return SettingsDialog.cleanColonVal(L.OPT_ICON) end,
        function() return ns.db.showIcon end, function(v) ns.SetIconShown(v) end,
        function() return L.TIP_OPT_ICON end)
    createStyledCheckbox(18, -172, 180, function() return L.WORLD_SHOW or SettingsDialog.cleanColonVal(L.OPT_WORLD_PINS) end,
        function() return ns.db.worldMapPins end, function(v) ns.db.worldMapPins = v end,
        function() return L.TIP_WORLD_SHOW end)
    createStyledCheckbox(232, -172, 180, function() return L.WORLD_LABELS end,
        function() return ns.db.worldMapLabels end, function(v) ns.db.worldMapLabels = v end,
        function() return L.TIP_WORLD_LABELS end)
    createStyledCheckbox(18, -198, 180, function() return L.WORLD_LEVELS end,
        function() return ns.db.worldMapLevels end, function(v) ns.db.worldMapLevels = v end,
        function() return L.TIP_WORLD_LEVELS end)
    createStyledCheckbox(232, -198, 180, function() return L.WORLD_AUTO_ALIGN end,
        function() return ns.db.worldMapAutoAlign ~= false end, function(v)
            ns.db.worldMapAutoAlign = v
            if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
        end,
        function() return L.TIP_WORLD_AUTO_ALIGN end)
    createStyledCheckbox(18, -224, 180, function() return SettingsDialog.cleanColonVal(L.OPT_EDIT) end,
        function() return state.edit end, function(v) ns.SetEditMode(v) end,
        function() return L.TIP_OPT_EDIT end)

    local alphaLbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alphaLbl:SetPoint("TOPLEFT", 20, -262)
    alphaLbl:SetTextColor(unpack(ROUTE_THEME.muted))
    local alphaMinus = createStyledButton(125, -258, 22, 20, false, function()
        ns.db.alpha = math.max(0.3, math.floor((ns.db.alpha - 0.1) * 20 + 0.5) / 20)
        ns.ApplyAlpha()
        syncCfg()
    end)
    alphaMinus.label:SetText("-")
    local alphaVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alphaVal:SetPoint("LEFT", alphaMinus, "RIGHT", 2, 0)
    alphaVal:SetWidth(42)
    alphaVal:SetJustifyH("CENTER")
    alphaVal:SetTextColor(unpack(ROUTE_THEME.text))
    local alphaPlus = createStyledButton(191, -258, 22, 20, false, function()
        ns.db.alpha = math.min(1.0, math.floor((ns.db.alpha + 0.1) * 20 + 0.5) / 20)
        ns.ApplyAlpha()
        syncCfg()
    end)
    alphaPlus.label:SetText("+")

    local sizeLbl = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLbl:SetPoint("TOPLEFT", 236, -262)
    sizeLbl:SetTextColor(unpack(ROUTE_THEME.muted))
    local sizeMinus = createStyledButton(340, -258, 22, 20, false, function()
        ns.db.mapSize = math.max(260, (ns.db.mapSize or 380) - 40)
        ns.RebuildMap()
        syncCfg()
    end)
    sizeMinus.label:SetText("-")
    local sizeVal = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeVal:SetPoint("LEFT", sizeMinus, "RIGHT", 2, 0)
    sizeVal:SetWidth(48)
    sizeVal:SetJustifyH("CENTER")
    sizeVal:SetTextColor(unpack(ROUTE_THEME.text))
    local sizePlus = createStyledButton(412, -258, 22, 20, false, function()
        ns.db.mapSize = math.min(620, (ns.db.mapSize or 380) + 40)
        ns.RebuildMap()
        syncCfg()
    end)
    sizePlus.label:SetText("+")

    local sec2 = createSectionDivider(-298)
    local launchMapBtn = createStyledButton(20, -324, 204, 26, false, function()
        ns.ToggleMap()
    end)
    local goBtn = createStyledButton(236, -324, 204, 26, false, function()
        ns.StartEntrance(state.viewed or state.current or ns.Dungeons[1])
    end)
    local resetProgBtn = createStyledButton(20, -358, 204, 26, false, function()
        ns.ResetProgress(state.viewed)
    end)
    local exportBtn = createStyledButton(236, -358, 204, 26, false, function()
        ns.ShowExport()
    end)

    local bottomResetBtn = createStyledButton(20, -406, 204, 28, false, function()
        ns.db.frames = {}
        ns.db.worldMapTools = nil
        ns.db.worldMapAutoAlign = true
        ns.db.showIcon = true
        if ns.SetIconShown then ns.SetIconShown(true) end
        if ns.GetMapFrame() then
            ns.GetMapFrame():ClearAllPoints()
            ns.GetMapFrame():SetPoint("CENTER", 200, 40)
        end
        if _G.EzWoW_DungeonRouteGuideIcon then
            _G.EzWoW_DungeonRouteGuideIcon:SetScale(1)
            _G.EzWoW_DungeonRouteGuideIcon:ClearAllPoints()
            _G.EzWoW_DungeonRouteGuideIcon:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
            _G.EzWoW_DungeonRouteGuideIcon:Show()
        end
        if _G.EzWoW_DungeonRouteGuideHUD then
            _G.EzWoW_DungeonRouteGuideHUD:ClearAllPoints()
            _G.EzWoW_DungeonRouteGuideHUD:SetPoint("TOP", 0, -110)
        end
        if _G.EzWoW_DungeonRouteGuideArrow then
            _G.EzWoW_DungeonRouteGuideArrow:ClearAllPoints()
            _G.EzWoW_DungeonRouteGuideArrow:SetPoint("TOP", 0, -190)
        end
        if _G.EzWoWWorldMapDock then _G.EzWoWWorldMapDock:Layout() end
        syncCfg()
    end)
    local donateBtn = createStyledButton(236, -406, 204, 28, true, function()
        ns.ShowDonate()
    end)

    local footerRegion = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerRegion:SetPoint("BOTTOMRIGHT", -20, 10)
    footerRegion:SetText("EzWoW - Dungeon Route Guide · /ezdg")
    footerRegion:SetTextColor(unpack(ROUTE_THEME.muted))

    -- Long translations (German, French, ...) shrink to fit their button
    local function setButtonLabel(buttonWidget, displayText)
        buttonWidget.label:SetText(displayText)
        ns.UIKit:FitFontString(buttonWidget.label, buttonWidget.fitWidth, 1)
    end

    syncCfg = function()
        if not ns.db then return end
        subtitleRegion:SetText(L.TAB_ROUTE .. " · " .. L.TAB_QUEST .. " · " .. L.TAB_NOTES)
        sec1:SetText(L.BTN_MENU)
        sec2:SetText(L.SEC_TOOLS or L.TAB_ROUTE)
        setButtonLabel(langBtn, L.OPT_LANG:format(L["LANG_" .. (ns.db.lang or "auto")]) .. " ▼")
        for _, themeColor in ipairs(cfgChecks) do
            themeColor.txt:SetText(themeColor.resolveLabel())
            ns.UIKit:FitFontString(themeColor.txt, themeColor.txtWidth, 2)
            themeColor:SetChecked(themeColor.readValue() and true or false)
        end
        alphaLbl:SetText(SettingsDialog.cleanColonVal(L.OPT_ALPHA))
        ns.UIKit:FitFontString(alphaLbl, 100, 1)
        alphaVal:SetText(math.floor(ns.db.alpha * 100 + 0.5) .. "%")
        sizeLbl:SetText(SettingsDialog.cleanColonVal(L.OPT_SIZE))
        ns.UIKit:FitFontString(sizeLbl, 100, 1)
        sizeVal:SetText((ns.db.mapSize or 380) .. "px")
        setButtonLabel(launchMapBtn, "EzWoW - Dungeon Route Guide (/ezdg)")
        setButtonLabel(goBtn, L.OPT_GO)
        setButtonLabel(resetProgBtn, L.OPT_RESET)
        setButtonLabel(exportBtn, L.OPT_EXPORT)
        setButtonLabel(bottomResetBtn, L.OPT_RESET_POS or RESET or "Reset")
        setButtonLabel(donateBtn, L.OPT_DONATE)
        if BlizzardOptionsCanvas and BlizzardOptionsCanvas.RefreshTexts then
            BlizzardOptionsCanvas:RefreshTexts()
        end
    end

    windowFrame.RefreshCfg = syncCfg
    windowFrame:SetScript("OnShow", syncCfg)
    syncCfg()
    windowFrame:Hide()
    configFrame = windowFrame
    return windowFrame
end

function ns.ToggleConfig()
    if not ns.db then ns.InitDB() end
    local windowFrame = SettingsDialog.buildConfigWindow()
    windowFrame:SetShown(not windowFrame:IsShown())
    if windowFrame:IsShown() then windowFrame:Raise() end
end

function ns.RegisterOptionsPanel()
    if BlizzardOptionsCanvas then return end
    local panelFrameEntry = CreateFrame("Frame", "EzWoW_DungeonRouteGuideOptionsPanel", UIParent)
    panelFrameEntry.name = "EzWoW - Dungeon Route Guide"
    BlizzardOptionsCanvas = panelFrameEntry

    local iconTex = panelFrameEntry:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(32, 32)
    iconTex:SetPoint("TOPLEFT", 18, -18)
    iconTex:SetTexture(ROUTE_GUIDE_ICON)

    local headingRegion = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    headingRegion:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
    headingRegion:SetText("EzWoW - Dungeon Route Guide")
    headingRegion:SetTextColor(unpack(ROUTE_THEME.accent))

    local desc = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", iconTex, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")

    local launchBtn = CreateFrame("Button", nil, panelFrameEntry, BackdropTemplateMixin and "BackdropTemplate" or nil)
    launchBtn:SetSize(220, 28)
    launchBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    if launchBtn.SetBackdrop then
        launchBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        launchBtn:SetBackdropColor(0.24, 0.14, 0.15, 0.96)
        launchBtn:SetBackdropBorderColor(unpack(ROUTE_THEME.accent))
    end
    local launchLabel = launchBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    launchLabel:SetPoint("CENTER")
    launchLabel:SetTextColor(unpack(ROUTE_THEME.accent))
    function launchBtn:SetText(displayText)
        launchLabel:SetText(displayText or "")
        ns.UIKit:FitFontString(launchLabel, 212, 1)
    end
    launchBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.20, 0.24, 0.30, 1)
            self:SetBackdropBorderColor(unpack(ROUTE_THEME.accent))
        end
    end)
    launchBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(0.24, 0.14, 0.15, 0.96)
            self:SetBackdropBorderColor(unpack(ROUTE_THEME.accent))
        end
    end)
    launchBtn:SetScript("OnMouseDown", function() launchLabel:SetPoint("CENTER", 1, -1) end)
    launchBtn:SetScript("OnMouseUp", function() launchLabel:SetPoint("CENTER", 0, 0) end)
    launchBtn:SetScript("OnClick", function()
        ns.ToggleConfig()
    end)

    local hint = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", launchBtn, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(unpack(ROUTE_THEME.muted))

    function panelFrameEntry:RefreshTexts()
        local hasKo = (ns.locale == "ko")
        desc:SetText(hasKo and "던전 공략 경로, 우두머리·희귀 몹 위치, 던전 퀘스트 및 세계지도 던전 입구를 안내합니다." or "Displays dungeon routes, boss & rare locations, dungeon quests, and world map dungeon entrances.")
        launchBtn:SetText((hasKo and "설정" or (L.BTN_MENU or "Settings")) .. " (/ezdg)")
        hint:SetText(hasKo and "채팅창에 /ezdg 또는 /ezdg config를 입력해도 열립니다." or "Type /ezdg or /ezdg config in chat to open settings.")
    end
    panelFrameEntry:SetScript("OnShow", function(self) self:RefreshTexts() end)
    panelFrameEntry:RefreshTexts()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local isCallOk, categoryKey = pcall(Settings.RegisterCanvasLayoutCategory, panelFrameEntry, panelFrameEntry.name)
        if isCallOk and categoryKey then pcall(Settings.RegisterAddOnCategory, categoryKey) end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panelFrameEntry)
    end
end

ns.GetConfigFrame = function() return configFrame end
