--===========================================================================
-- EzWoW - Dungeon Route Guide
-- UI/WorldMapPins.lua : WorldMap Dungeon Entrance Pin Mixin & Canvas Data Provider
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

-- With the gamepad UI on, the pins are made outside the map's pin pools: the map runs the
-- mouse code of the pins near its gamepad cursor itself, and addon code there taints its
-- gamepad steps (Libs/EzWoWGamePad: AcquireMapPin / RemoveMapPins)
local function acquirePin(map, template, ...)
    local pad = ns.GamePad
    if pad and pad.AcquireMapPin then return pad.AcquireMapPin(map, template, ...) end
    return map:AcquirePin(template, ...)
end
local function removePins(map, template)
    local pad = ns.GamePad
    if pad and pad.RemoveMapPins then return pad.RemoveMapPins(map, template) end
    map:RemoveAllPinsByTemplate(template)
end

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
    -- name tag: a small see-through plate with a thin gold rim, the name and the
    -- level range on one line (no thick outline on the letters)
    local tag = CreateFrame("Frame", nil, self, "BackdropTemplate")
    if tag.SetBackdrop then
        tag:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        tag:SetBackdropColor(0.04, 0.05, 0.07, 0.72)
        tag:SetBackdropBorderColor(0.80, 0.64, 0.30, 0.50)
    end
    tag:SetHeight(WorldMapPinProvider.TAG_H)
    -- the tag answers the mouse like its pin: hover raises both and shows the
    -- tooltip, a click does what a click on the pin does
    local pin = self
    if tag.EnableMouse then tag:EnableMouse(true) end
    tag:SetScript("OnEnter", function() pin:OnMouseEnter() end)
    tag:SetScript("OnLeave", function() pin:OnMouseLeave() end)
    tag:SetScript("OnMouseUp", function(_, button) pin:OnMouseClickAction(button) end)
    tag:Hide()
    self.tag = tag
    -- the gamepad cursor on the map finds the tag as well (Libs/EzWoWGamePad)
    if ns.GamePad and ns.GamePad.MapMark then ns.GamePad.MapMark(tag) end
    self.label = tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local font = self.label:GetFont()
    self.label:SetFont(font, 11, "")
    self.label:SetTextColor(1.0, 0.86, 0.45)
    self.label:SetShadowColor(0, 0, 0, 1); self.label:SetShadowOffset(1, -1)
    self.label:SetJustifyH("LEFT")
    self.label:SetPoint("LEFT", tag, "LEFT", WorldMapPinProvider.TAG_PAD, 0)
    self.level = tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.level:SetFont(font, 10, "")
    self.level:SetShadowColor(0, 0, 0, 1); self.level:SetShadowOffset(1, -1)
    self.level:SetPoint("LEFT", self.label, "RIGHT", 4, 0)
end

WorldMapPinProvider.TAG_H = 17
WorldMapPinProvider.TAG_PAD = 5

-- level range colour against the player's level: red too high, orange soon,
-- green right, grey done
function WorldMapPinProvider.levelColor(levels)
    local low, high = tostring(levels or ""):match("(%d+)%D+(%d+)")
    low, high = tonumber(low), tonumber(high)
    if not low then
        low = tonumber(tostring(levels or ""):match("(%d+)"))
        high = low
    end
    local level = ns.CoerceSafeNumber(ns.UnwrapSafeValue(UnitLevel, "player"))
    if not (low and level) then return 0.85, 0.85, 0.85 end
    if level < low - 3 then return 1.00, 0.38, 0.30 end
    if level < low then return 1.00, 0.62, 0.25 end
    if level <= high then return 0.45, 0.90, 0.45 end
    return 0.62, 0.62, 0.62
end

function PinMixin:OnAcquired(group)
    self:SetMouseClickEnabled(true)
    self:SetMouseMotionEnabled(true)
    self.entries = group.entries
    self.count:SetText(#self.entries > 1 and tostring(#self.entries) or "")
    local nameText = translationHelper(self.entries[1].name)
    local levels = self.entries[1].levels
    if #self.entries > 1 then
        nameText = L.WORLD_PIN_GROUP:format(nameText, #self.entries - 1)
        levels = nil
    elseif not ns.db.worldMapLevels or type(levels) ~= "string" or levels == "" then
        levels = nil
    end
    self.label:SetWidth(0); self.label:SetText(nameText)
    self.level:SetText(levels or "")
    self.level:SetShown(levels ~= nil)
    if levels then self.level:SetTextColor(WorldMapPinProvider.levelColor(levels)) end
    local nameW = ns.CoerceSafeNumber(ns.UnwrapSafeValue(self.label.GetStringWidth, self.label)) or 80
    local levelW = levels and (ns.CoerceSafeNumber(ns.UnwrapSafeValue(self.level.GetStringWidth, self.level)) or 30) + 4 or 0
    self.tag:SetWidth(math.ceil(nameW + levelW + WorldMapPinProvider.TAG_PAD * 2))
    self.tag:Hide()
    self:SetPosition(group.x, group.y)
    self:ApplyCurrentScale()
end

-- left clicks belong to the pin; other buttons (right-click zoom out) go to the map
function PinMixin:ShouldMouseButtonBePassthrough(button) return button ~= "LeftButton" end

-- SetPassThroughButtons is blocked in combat; the map calls it when pins are acquired
function PinMixin:SetPassThroughButtons(...)
    if InCombatLockdown() then return end
    getmetatable(self).__index.SetPassThroughButtons(self, ...)
end

-- the mouse propagation setters are protected in combat the same way
function PinMixin:SetPropagateMouseClicks(...)
    if InCombatLockdown() then return end
    getmetatable(self).__index.SetPropagateMouseClicks(self, ...)
end

function PinMixin:SetPropagateMouseMotion(...)
    if InCombatLockdown() then return end
    getmetatable(self).__index.SetPropagateMouseMotion(self, ...)
end

-- One mark of all EzWoW map marks is in front: the last one the mouse was on
-- (above every other mark, its label too). It stays in front after the mouse
-- leaves, until another mark is hovered; the one before goes back to its place.
-- Kept in a table all EzWoW addons share (EzWoWMapPinFront).
local function mapPinFront()
    local f = _G.EzWoWMapPinFront
    if type(f) == "table" and (tonumber(f.v) or 0) >= 2 then return f end
    f = { v = 2 }
    local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
        FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    function f.Restore(pin)
        if not pin then return end
        if pin.ezBaseLevel ~= nil then
            if pin.ezBaseStrata then pcall(pin.SetFrameStrata, pin, pin.ezBaseStrata) end
            -- a level its addon gave it since (the marks were drawn again) stays
            if pin:GetFrameLevel() == pin.ezFrontLevel then pcall(pin.SetFrameLevel, pin, pin.ezBaseLevel) end
        end
        pin.ezBaseLevel, pin.ezBaseStrata, pin.ezFrontLevel = nil, nil, nil
        if f.pin == pin then f.pin = nil end
    end
    function f.Raise(pin)
        if not pin then return end
        if f.pin == pin then
            if pin:GetFrameLevel() == pin.ezFrontLevel then return end
            -- drawn again at its own level since it came to the front: raised from there
            pin.ezBaseLevel = pin:GetFrameLevel()
        else
            if f.pin then f.Restore(f.pin) end
            pin.ezBaseLevel, pin.ezBaseStrata = pin:GetFrameLevel(), pin:GetFrameStrata()
            f.pin = pin
        end
        -- the marks of the quest addons sit in HIGH: at least that layer
        if (STRATA[pin.ezBaseStrata] or 0) < STRATA.HIGH then pcall(pin.SetFrameStrata, pin, "HIGH") end
        local parent = pin:GetParent()
        pcall(pin.SetFrameLevel, pin, ((parent and parent:GetFrameLevel()) or 0) + 1200)
        pin.ezFrontLevel = pin:GetFrameLevel()
    end
    _G.EzWoWMapPinFront = f
    return f
end

-- the hovered mark (and its name tag) comes to the front of every map mark and stays there
function PinMixin:OnMouseEnter()
    mapPinFront().Raise(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("EzWoW - Dungeon Route Guide", 1, 0.82, 0)
    for _, d in ipairs(self.entries) do
        GameTooltip:AddLine(translationHelper(d.name) .. "  |cffffffff" .. (d.levels or "") .. "|r", 1, 0.82, 0, true)
        local e = WorldMapPinProvider.resolveDungeonEntrancePoint(d)
        local apiInfo = e and WorldMapPinProvider.resolveMapInfo(e.map)
        GameTooltip:AddLine((apiInfo and ns.CoerceSafeString(apiInfo.name) or (e and translationHelper(e.zone)) or "") .. ("  %.1f, %.1f"):format(e.x, e.y), 0.8, 0.8, 0.8, true)
        if e.note then GameTooltip:AddLine(translationHelper(e.note), 0.8, 0.8, 0.8, true) end
    end
    if L.WORLD_PIN_CLICK then GameTooltip:AddLine(L.WORLD_PIN_CLICK, 0.5, 0.8, 1, true) end
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    GameTooltip_Hide()
end

-- Map waypoint on the entrance (only where the client allows one)
function WorldMapPinProvider.setEntranceWaypoint(d)
    local e = WorldMapPinProvider.resolveDungeonEntrancePoint(d)
    local mapID, x, y = e and ns.CoerceSafeNumber(e.map), e and ns.CoerceSafeNumber(e.x), e and ns.CoerceSafeNumber(e.y)
    if not (mapID and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return end
    if C_Map.CanSetUserWaypointOnMap and not ns.IsTruthySafeValue(ns.UnwrapSafeValue(C_Map.CanSetUserWaypointOnMap, mapID)) then return end
    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x / 100, y / 100)
    if not (ok and point) then return end
    if pcall(C_Map.SetUserWaypoint, point) and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    -- the on-screen arrow (Libs/EzWoWWaypointArrow) names the dungeon; it stays
    -- hidden while this addon's own entrance arrow is up
    local arrow = _G.EzWoW_WaypointArrow
    if type(arrow) == "table" and type(arrow.SetLabel) == "function" then
        pcall(arrow.SetLabel, translationHelper(d.name), "EzWoW - Dungeon Route Guide")
    end
end

-- Click: that dungeon's route window. Shift+click: entrance arrow (+ map waypoint).
function WorldMapPinProvider.activateDungeon(d, guide)
    if not d then return end
    if guide then
        if ns.StartEntrance then ns.StartEntrance(d) end
        WorldMapPinProvider.setEntranceWaypoint(d)
    elseif ns.ShowMap then
        local state = ns.state
        if type(state) == "table" then
            state.viewed, state.selected, state.cardTrash = d, nil, nil
            state.page, state.pageManual = nil, false
        end
        ns.ShowMap(d)
    end
end

function PinMixin:OnMouseClickAction(button)
    if button and button ~= "LeftButton" then return end
    local entries = self.entries
    if not entries or #entries == 0 then return end
    local guide = IsShiftKeyDown and IsShiftKeyDown()
    if #entries == 1 or not (MenuUtil and MenuUtil.CreateContextMenu) then
        WorldMapPinProvider.activateDungeon(entries[1], guide)
        return
    end
    -- several dungeons share this pin: pick one
    local list = {}
    for index, d in ipairs(entries) do list[index] = d end
    MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        for _, d in ipairs(list) do
            rootDescription:CreateButton(translationHelper(d.name) .. "  |cffffffff" .. (d.levels or "") .. "|r", function()
                WorldMapPinProvider.activateDungeon(d, guide)
            end)
        end
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("|cff8c8c8cEzWoW - Dungeon Route Guide|r")
    end)
end

function PinMixin:OnReleased()
    self.entries = nil
    mapPinFront().Restore(self)
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
    removePins(self:GetMap(), TEMPLATE)
    self.pins = {}
end

function MapDataProvider:RefreshAllData()
    self:RemoveAllData()
    do
        local w, h = WorldMapPinProvider.canvasSize(self:GetMap())
        self.canvasKey = w and h and string.format("%.1f:%.1f", w, h) or nil
    end
    if not ns.db or not ns.db.worldMapPins then return end
    local map = self:GetMap()
    local id = ns.CoerceSafeNumber(ns.UnwrapSafeValue(map.GetMapID, map))
    local apiInfo = id and WorldMapPinProvider.resolveMapInfo(id)
    local kind = apiInfo and ns.CoerceSafeNumber(apiInfo.mapType)
    
    local mapTypes = Enum and Enum.UIMapType or {}
    local worldType, continentType, zoneType = mapTypes.World or 1, mapTypes.Continent or 2, mapTypes.Zone or 3
    if kind ~= worldType and kind ~= continentType and kind ~= zoneType then return end
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
    for _, group in ipairs(groups) do self.pins[#self.pins + 1] = acquirePin(map, TEMPLATE, group) end
    self:PlaceLabels()
end

function MapDataProvider:PlaceLabels()
    local boxWidth, headerBar = WorldMapPinProvider.canvasSize(self:GetMap())
    if not boxWidth then return end
    local used = {}
    local function canLabelFitWithoutOverlap(coordX, coordY, width, height)
        if coordX < 3 or coordY < 3 or coordX + width > boxWidth - 3 or coordY + height > headerBar - 3 then return false end
        -- the pin icons (20 px)
        for _, anchorTarget in ipairs(self.pins or {}) do
            local pxVal, pyVal = anchorTarget.normalizedX * boxWidth, anchorTarget.normalizedY * headerBar
            if coordX < pxVal + 10 and coordX + width > pxVal - 10 and coordY < pyVal + 10 and coordY + height > pyVal - 10 then return false end
        end
        for _, rowEntry in ipairs(used) do
            if coordX < rowEntry[3] and coordX + width > rowEntry[1] and coordY < rowEntry[4] and coordY + height > rowEntry[2] then return false end
        end
        return true
    end
    -- next to the pin, toward the nearer edge of the map first so the middle of
    -- the map (the land) stays clear: a pin in the left half gets its tag on
    -- the left, one in the upper half above rather than below. The inner side
    -- comes last. A tag that would cover another pin or tag is left out (the
    -- tooltip still names it).
    local GAP = 11
    for _, pinFrame in ipairs(self.pins or {}) do
        local tag = pinFrame.tag
        if not ns.db.worldMapLabels then
            tag:Hide()
        else
            local coordX, coordY = pinFrame.normalizedX * boxWidth, pinFrame.normalizedY * headerBar
            local width = ns.CoerceSafeNumber(ns.UnwrapSafeValue(tag.GetWidth, tag)) or 100
            local height = WorldMapPinProvider.TAG_H
            local leftOut = pinFrame.normalizedX < 0.5
            local upOut = pinFrame.normalizedY < 0.5
            local outX = leftOut and (-GAP - width) or GAP                  -- beside, on the outer side
            local inX = leftOut and GAP or (-GAP - width)
            local outCornerX = leftOut and (-GAP - width + 3) or (GAP - 3)
            local inCornerX = leftOut and (GAP - 3) or (-GAP - width + 3)
            local outY = upOut and (-GAP - height) or GAP                   -- above / below, outer side
            local inY = upOut and GAP or (-GAP - height)
            local outCornerY = upOut and (-GAP - height + 5) or (GAP - 5)
            local inCornerY = upOut and (GAP - 5) or (-GAP - height + 5)
            local candidates = {
                { outX, -height / 2 },            -- beside, outer side
                { outCornerX, outCornerY },       -- outer corner
                { outCornerX, inCornerY },
                { -width / 2, outY },             -- above / below, outer side
                { -width / 2, inY },
                { inX, -height / 2 },             -- inner side last
                { inCornerX, outCornerY },
                { inCornerX, inCornerY },
            }
            local placed
            for _, offset in ipairs(candidates) do
                if canLabelFitWithoutOverlap(coordX + offset[1], coordY + offset[2], width, height) then
                    used[#used + 1] = { coordX + offset[1], coordY + offset[2], coordX + offset[1] + width, coordY + offset[2] + height }
                    tag:ClearAllPoints()
                    tag:SetPoint("TOPLEFT", pinFrame, "CENTER", offset[1], -offset[2])
                    placed = true
                    break
                end
            end
            tag:SetShown(placed == true)
        end
    end
end

-- The map calls these on every frame in some states (the gamepad cursor on the map: 50 refreshes a
-- second were counted). Each refresh releases the pins, and with the gamepad UI the game then runs
-- every released pin's mouse-leave, which hid any tooltip on the map. Only a real change refreshes.
function MapDataProvider:RefreshIfCanvasChanged()
    local w, h = WorldMapPinProvider.canvasSize(self:GetMap())
    local key = w and h and string.format("%.1f:%.1f", w, h) or nil
    if key and key == self.canvasKey then return end
    self:RefreshAllData()
end
function MapDataProvider:OnCanvasScaleChanged() self:RefreshIfCanvasChanged() end
function MapDataProvider:OnCanvasSizeChanged() self:RefreshIfCanvasChanged() end
function MapDataProvider:OnHide()
    if ns.WorldMapControls then ns.WorldMapControls.panel:Hide() end
end

-- Our map layer runs from post-hooks on the map instead of being registered
-- as a map data provider: a provider runs inside the map's own update loop,
-- and the game's pins made after it in that loop are then blocked in combat
-- (SetPassThroughButtons). The layer keeps the provider method names.
local function attachMapLayer(map, layer)
    layer.owningMap = map
    layer.GetMap = function() return map end
    local function run(method, ...)
        local fn = layer[method]
        if type(fn) == "function" then fn(layer, ...) end
    end
    hooksecurefunc(map, "OnMapChanged", function() run("OnMapChanged") end)
    for _, method in ipairs({ "OnCanvasScaleChanged", "OnCanvasSizeChanged", "SetGlobalAlpha" }) do
        if type(map[method]) == "function" then
            local target = method == "SetGlobalAlpha" and "OnGlobalAlphaChanged" or method
            hooksecurefunc(map, method, function() run(target) end)
        end
    end
    map:HookScript("OnShow", function() run("OnShow"); run("RefreshAllData", true) end)
    map:HookScript("OnHide", function() run("OnHide") end)
end

function ns.InitWorldMap()
    if WorldMapDataProvider or not ns.db or not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin then return end
    for lookupKey, value in pairs(MapCanvasPinMixin) do if PinMixin[lookupKey] == nil then PinMixin[lookupKey] = value end end
    WorldMapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin, MapDataProvider)
    attachMapLayer(WorldMapFrame, WorldMapDataProvider)
    if ns.CreateWorldMapControls then ns.CreateWorldMapControls() end
    if ns.IsTruthySafeValue(ns.UnwrapSafeValue(WorldMapFrame.IsShown, WorldMapFrame)) then WorldMapDataProvider:RefreshAllData() end
end

function ns.RefreshWorldMap()
    ns.InitWorldMap()
    if ns.RefreshWorldMapControls then ns.RefreshWorldMapControls() end
    if WorldMapDataProvider and ns.IsTruthySafeValue(ns.UnwrapSafeValue(WorldMapFrame.IsShown, WorldMapFrame)) then WorldMapDataProvider:RefreshAllData() end
end

_G.EzWoWRouteGuideWorldPinMixin = EzWoWRouteGuideWorldPinMixin
