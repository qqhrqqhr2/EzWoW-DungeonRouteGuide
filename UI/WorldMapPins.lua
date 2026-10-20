--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/WorldMapPins.lua : WorldMap Dungeon Entrance Pin Mixin & Canvas Data Provider
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WorldMapPinProvider = ns.WorldMapPinProvider or {}
ns.WorldMapPinProvider = WorldMapPinProvider
local L, translationHelper = ns.L, ns.GetLocalizedText
local TEMPLATE = "EzWoWRouteGuideWorldPinTemplate"
local WorldMapDataProvider
local PinMixin, MapDataProvider = {}, {}
EzWoWRouteGuideWorldPinMixin = PinMixin

function WorldMapPinProvider.resolveDungeonEntrancePoint(d)
    return (ns.db.entrances and ns.db.entrances[d.key]) or d.entrance
end

function WorldMapPinProvider.resolveMapInfo(id)
    local apiInfo = ns.UnwrapSafeValue(C_Map and C_Map.GetMapInfo, id)
    if ns.IsReadableValue(apiInfo) and type(apiInfo) == "table" then return apiInfo end
end

function WorldMapPinProvider.normalizePointCoordinates(pos)
    if not ns.IsReadableValue(pos) or not pos then return end
    local coordX, coordY = ns.UnwrapSafeValue(pos.GetXY, pos)
    return ns.CoerceSafeNumber(coordX), ns.CoerceSafeNumber(coordY)
end

function WorldMapPinProvider.isMapEligibleForPins(e, mapID)
    if not e then return end
    local sourceVal, coordX, coordY = ns.CoerceSafeNumber(e.map), ns.CoerceSafeNumber(e.x), ns.CoerceSafeNumber(e.y)
    if not sourceVal or not coordX or not coordY or coordX < 0 or coordX > 100 or coordY < 0 or coordY > 100 then return end
    coordX, coordY = coordX / 100, coordY / 100
    if sourceVal == mapID then return coordX, coordY end
    local current, visitedMap, ancestor = sourceVal, {}, false
    for _ = 1, 20 do
        if current == mapID then ancestor = true; break end
        if visitedMap[current] then break end
        visitedMap[current] = true
        local apiInfo = WorldMapPinProvider.resolveMapInfo(current)
        current = apiInfo and ns.CoerceSafeNumber(apiInfo.parentMapID)
        if not current or current == 0 then break end
    end
    if not ancestor then return end
    local minX, maxX, minY, maxY = ns.UnwrapSafeValue(C_Map.GetMapRectOnMap, sourceVal, mapID)
    minX, maxX, minY, maxY = ns.CoerceSafeNumber(minX), ns.CoerceSafeNumber(maxX), ns.CoerceSafeNumber(minY), ns.CoerceSafeNumber(maxY)
    if minX and maxX and minY and maxY and maxX > minX and maxY > minY then
        coordX, coordY = minX + coordX * (maxX - minX), minY + coordY * (maxY - minY)
    elseif CreateVector2D then
        local continent, world = ns.UnwrapSafeValue(C_Map.GetWorldPosFromMapPos, sourceVal, CreateVector2D(coordX, coordY))
        continent = ns.CoerceSafeNumber(continent)
        if not continent or not ns.IsReadableValue(world) or not world then return end
        local result, pos = ns.UnwrapSafeValue(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
        if ns.CoerceSafeNumber(result) ~= mapID then return end
        coordX, coordY = WorldMapPinProvider.normalizePointCoordinates(pos)
    else return end
    if coordX and coordY and coordX >= 0 and coordX <= 1 and coordY >= 0 and coordY <= 1 then return coordX, coordY end
end

function PinMixin:OnLoad()
    self:SetSize(16, 16)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")
    self:SetIgnoreGlobalPinScale(true)
    self:SetScalingLimits(1, 1, 1)
    self.icon = self:CreateTexture(nil, "ARTWORK")
    if self.icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Dungeon") then
        self.icon:SetAtlas("Dungeon", false)
        self.icon:SetSize(20, 20)
    else
        self.icon:SetTexture("Interface\\AddOns\\EzWoW-DungeonRouteGuide\\Media\\dungeon_pin")
        self.icon:SetSize(15, 15)
    end
    self.icon:SetPoint("CENTER")
    self.count = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.count:SetPoint("TOPRIGHT", 2, 2)
    self.count:SetTextColor(0.3, 0.9, 1)
    self.label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local font, size, flags = self.label:GetFont()
    self.label:SetFont(font, math.max(11, size or 11), "OUTLINE")
    self.label:SetJustifyH("LEFT")
    self.label:SetShadowColor(0, 0, 0, 1); self.label:SetShadowOffset(1, -1)
    self.labelBg = self:CreateTexture(nil, "BACKGROUND")
    self.labelBg:SetColorTexture(0.02, 0.02, 0.02, 0.85)
    self.labelBg:SetPoint("TOPLEFT", self.label, "TOPLEFT", -4, 3)
    self.labelBg:SetPoint("BOTTOMRIGHT", self.label, "BOTTOMRIGHT", 4, -3)
end

function PinMixin:OnAcquired(group)
    self:SetMouseClickEnabled(false)
    self:SetMouseMotionEnabled(true)
    self.entries = group.entries
    self.count:SetText(#self.entries > 1 and tostring(#self.entries) or "")
    local extractSafeTooltipText = translationHelper(self.entries[1].name)
    if #self.entries > 1 then extractSafeTooltipText = L.WORLD_PIN_GROUP:format(extractSafeTooltipText, #self.entries - 1)
    elseif ns.db.worldMapLevels then extractSafeTooltipText = extractSafeTooltipText .. "\n|cffffffff" .. L.WORLD_PIN_LEVEL:format(self.entries[1].levels or "") .. "|r" end
    self.label:SetWidth(0); self.label:SetText(extractSafeTooltipText)
    self:SetPosition(group.x, group.y)
    self:ApplyCurrentScale()
end

function PinMixin:ShouldMouseButtonBePassthrough() return true end

function PinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("EzWoW - Dungeon Route Guide", 1, 0.82, 0)
    for _, d in ipairs(self.entries) do
        GameTooltip:AddLine(translationHelper(d.name) .. "  |cffffffff" .. (d.levels or "") .. "|r", 1, 0.82, 0, true)
        local e = WorldMapPinProvider.resolveDungeonEntrancePoint(d)
        local apiInfo = e and WorldMapPinProvider.resolveMapInfo(e.map)
        GameTooltip:AddLine((apiInfo and ns.CoerceSafeString(apiInfo.name) or (e and translationHelper(e.zone)) or "") .. ("  %.1f, %.1f"):format(e.x, e.y), 0.8, 0.8, 0.8, true)
        if e.note then GameTooltip:AddLine(translationHelper(e.note), 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave() GameTooltip_Hide() end

function PinMixin:OnMouseClickAction() end

function PinMixin:OnReleased()
    self.entries = nil
    if ns.IsTruthySafeValue(ns.UnwrapSafeValue(GameTooltip.IsOwned, GameTooltip, self)) then GameTooltip_Hide() end
    MapCanvasPinMixin.OnReleased(self)
end

function WorldMapPinProvider.canvasSize(map)
    local canvasFrame = ns.UnwrapSafeValue(map.GetCanvas, map)
    local calculateCanvasScale = ns.CoerceSafeNumber(ns.UnwrapSafeValue(map.GetCanvasScale, map)) or 1
    if not canvasFrame or calculateCanvasScale <= 0 then return end
    local boxWidth, headerBar = ns.CoerceSafeNumber(ns.UnwrapSafeValue(canvasFrame.GetWidth, canvasFrame)), ns.CoerceSafeNumber(ns.UnwrapSafeValue(canvasFrame.GetHeight, canvasFrame))
    if boxWidth and headerBar and boxWidth > 0 and headerBar > 0 then return boxWidth * calculateCanvasScale, headerBar * calculateCanvasScale end
end

function MapDataProvider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    self.pins = {}
end

function MapDataProvider:RefreshAllData()
    self:RemoveAllData()
    if not ns.db or not ns.db.worldMapPins then return end
    local map = self:GetMap()
    local id = ns.CoerceSafeNumber(ns.UnwrapSafeValue(map.GetMapID, map))
    local apiInfo = id and WorldMapPinProvider.resolveMapInfo(id)
    local kind = apiInfo and ns.CoerceSafeNumber(apiInfo.mapType)
    
    if kind ~= 1 and kind ~= 2 then return end
    local boxWidth, headerBar = WorldMapPinProvider.canvasSize(map)
    if not boxWidth then return end
    local groups = {}
    for _, d in ipairs(ns.Dungeons) do
        local matches = not ns.WorldMapMatches or ns.WorldMapMatches(d)
        local coordX, coordY
        if matches then coordX, coordY = WorldMapPinProvider.isMapEligibleForPins(WorldMapPinProvider.resolveDungeonEntrancePoint(d), id) end
        if coordX then
            local group
            for _, greenVal in ipairs(groups) do
                if ((coordX - greenVal.x) * boxWidth)^2 + ((coordY - greenVal.y) * headerBar)^2 < 32^2 then group = greenVal; break end
            end
            if not group then group = { x = coordX, y = coordY, entries = {} }; groups[#groups + 1] = group end
            group.entries[#group.entries + 1] = d
        end
    end
    for _, group in ipairs(groups) do self.pins[#self.pins + 1] = map:AcquirePin(TEMPLATE, group) end
    self:PlaceLabels()
end

function MapDataProvider:PlaceLabels()
    local boxWidth, headerBar = WorldMapPinProvider.canvasSize(self:GetMap())
    if not boxWidth then return end
    local used = {}
    local function canLabelFitWithoutOverlap(coordX, coordY, width, height)
        if coordX < 3 or coordY < 3 or coordX + width > boxWidth - 3 or coordY + height > headerBar - 3 then return false end
        for _, anchorTarget in ipairs(self.pins or {}) do
            local pxVal, pyVal = anchorTarget.normalizedX * boxWidth, anchorTarget.normalizedY * headerBar
            if coordX < pxVal + 18 and coordX + width > pxVal - 18 and coordY < pyVal + 18 and coordY + height > pyVal - 18 then return false end
        end
        for _, rowEntry in ipairs(used) do
            if coordX < rowEntry[3] and coordX + width > rowEntry[1] and coordY < rowEntry[4] and coordY + height > rowEntry[2] then return false end
        end
        return true
    end
    for _, pinFrame in ipairs(self.pins or {}) do
        if not ns.db.worldMapLabels then
            pinFrame.label:Hide(); pinFrame.labelBg:Hide()
        else
        local coordX, coordY = pinFrame.normalizedX * boxWidth, pinFrame.normalizedY * headerBar
        local width = (ns.CoerceSafeNumber(ns.UnwrapSafeValue(pinFrame.label.GetStringWidth, pinFrame.label)) or 100) + 8
        local height = (ns.CoerceSafeNumber(ns.UnwrapSafeValue(pinFrame.label.GetStringHeight, pinFrame.label)) or 26) + 6
        local candidates = { {20, -height/2}, {-20-width, -height/2}, {-width/2, 20}, {-width/2, -20-height}, {20, 20}, {-20-width, 20}, {20, -20-height}, {-20-width, -20-height} }
        local placed
        for _, offset in ipairs(candidates) do
            if canLabelFitWithoutOverlap(coordX + offset[1], coordY + offset[2], width, height) then
                used[#used + 1] = { coordX + offset[1], coordY + offset[2], coordX + offset[1] + width, coordY + offset[2] + height }
                pinFrame.label:ClearAllPoints(); pinFrame.label:SetPoint("TOPLEFT", pinFrame, "CENTER", offset[1] + 4, -offset[2] - 3)
                placed = true; break
            end
        end
        pinFrame.label:SetShown(placed == true); pinFrame.labelBg:SetShown(placed == true)
        end
    end
end

function MapDataProvider:OnCanvasScaleChanged() self:RefreshAllData() end
function MapDataProvider:OnCanvasSizeChanged() self:RefreshAllData() end
function MapDataProvider:OnHide()
    if ns.WorldMapControls then ns.WorldMapControls.panel:Hide() end
end

-- While our entrance pins are on, drop the game's own entrance pins so each entrance shows once
function WorldMapPinProvider.shouldHideStockEntrances()
    return ns.db and ns.db.worldMapPins and ns.db.hideStockEntrances ~= false
end

function WorldMapPinProvider.bindStockEntranceProvider(_, provider)
    if not (DungeonEntranceDataProviderMixin and provider ~= WorldMapDataProvider
        and provider.RefreshAllData == DungeonEntranceDataProviderMixin.RefreshAllData)
        or provider.ezWoWRouteGuideHooked then return end
    provider.ezWoWRouteGuideHooked = true
    hooksecurefunc(provider, "RefreshAllData", function(p)
        if WorldMapPinProvider.shouldHideStockEntrances() and p:GetMap() == WorldMapFrame then
            WorldMapFrame:RemoveAllPinsByTemplate("DungeonEntrancePinTemplate")
        end
    end)
end

function ns.InitWorldMap()
    if WorldMapDataProvider or not ns.db or not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin then return end
    for lookupKey, value in pairs(MapCanvasPinMixin) do if PinMixin[lookupKey] == nil then PinMixin[lookupKey] = value end end
    WorldMapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin, MapDataProvider)
    WorldMapFrame:AddDataProvider(WorldMapDataProvider)
    for provider in pairs(WorldMapFrame.dataProviders or {}) do WorldMapPinProvider.bindStockEntranceProvider(WorldMapFrame, provider) end
    hooksecurefunc(WorldMapFrame, "AddDataProvider", WorldMapPinProvider.bindStockEntranceProvider)
    if ns.CreateWorldMapControls then ns.CreateWorldMapControls() end
    if ns.IsTruthySafeValue(ns.UnwrapSafeValue(WorldMapFrame.IsShown, WorldMapFrame)) then WorldMapDataProvider:RefreshAllData() end
end

function ns.RefreshWorldMap()
    ns.InitWorldMap()
    if ns.RefreshWorldMapControls then ns.RefreshWorldMapControls() end
    if WorldMapDataProvider and ns.IsTruthySafeValue(ns.UnwrapSafeValue(WorldMapFrame.IsShown, WorldMapFrame)) then
        -- Refresh every provider only when the stock-icon state flips, so the game's icons follow the option right away
        local hideStock = WorldMapPinProvider.shouldHideStockEntrances() and true or false
        if hideStock ~= WorldMapPinProvider.lastStockHidden and WorldMapFrame.RefreshAllDataProviders then
            WorldMapPinProvider.lastStockHidden = hideStock
            pcall(WorldMapFrame.RefreshAllDataProviders, WorldMapFrame)
        else
            WorldMapDataProvider:RefreshAllData()
        end
    end
end

_G.EzWoWRouteGuideWorldPinMixin = EzWoWRouteGuideWorldPinMixin
