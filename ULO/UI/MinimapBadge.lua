-- ============================================================================
-- ULO: Universal Layer Operator
-- File: UI/MinimapBadge.lua
-- Description: Minimap circular bronze layer medallion badge. Renders active
--              layer number, supports 360-degree orbital dragging with position
--              persistence, tooltip diagnostic readout, and instance suppression.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.UI = ULO.UI or {}
ULO.UI.MinimapBadge = ULO.UI.MinimapBadge or {}
local Badge = ULO.UI.MinimapBadge

local Detection = ULO.Detection
local Monitor = ULO.Monitor
local Compat = ULO.Compat
local C = ULO.Constants

-- Constants
local DEFAULT_ANGLE = 225
local MINIMAP_RADIUS = 80
local MINIMAP_OFFSET = 5
local BADGE_SIZE = 32

-- Runtime State
local badgeText = "-"
local badgeShown = true
local isDragging = false

-- Reference or create Badge Frame
local badgeFrame = _G.ULOMinimapBadge
if not badgeFrame and type(_G.CreateFrame) == "function" then
    badgeFrame = _G.CreateFrame("Button", "ULOMinimapBadge", _G.Minimap or _G.UIParent)
end

-- Child Visual Elements
local badgeBg = nil
local badgeIcon = nil
local badgeBorder = nil
local badgeTextFS = nil

if badgeFrame then
    badgeFrame:SetSize(BADGE_SIZE, BADGE_SIZE)
    if type(badgeFrame.SetFrameStrata) == "function" then
        badgeFrame:SetFrameStrata("MEDIUM")
    end
    if type(badgeFrame.SetFrameLevel) == "function" then
        badgeFrame:SetFrameLevel(8)
    end
    if type(badgeFrame.SetMovable) == "function" then
        badgeFrame:SetMovable(true)
    end
    if type(badgeFrame.EnableMouse) == "function" then
        badgeFrame:EnableMouse(true)
    end
    if type(badgeFrame.RegisterForClicks) == "function" then
        badgeFrame:RegisterForClicks("anyUp")
    end
    if type(badgeFrame.RegisterForDrag) == "function" then
        badgeFrame:RegisterForDrag("LeftButton")
    end
    if type(badgeFrame.SetHighlightTexture) == "function" then
        badgeFrame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    end

    -- Overlord / Classic MiniMap-TrackingBorder minimap button geometry
    if type(badgeFrame.CreateTexture) == "function" then
        badgeBg = badgeFrame:CreateTexture(nil, "BACKGROUND")
        if badgeBg then
            if type(badgeBg.SetTexture) == "function" then
                badgeBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
            end
            if type(badgeBg.SetSize) == "function" then badgeBg:SetSize(20, 20) end
            if type(badgeBg.SetPoint) == "function" then badgeBg:SetPoint("TOPLEFT", badgeFrame, "TOPLEFT", 7, -5) end
        end

        badgeIcon = badgeFrame:CreateTexture(nil, "ARTWORK")
        if badgeIcon then
            if type(badgeIcon.SetTexture) == "function" then
                badgeIcon:SetTexture("Interface\\AddOns\\ULO\\Media\\ULOMinimap")
            end
            if type(badgeIcon.SetTexCoord) == "function" then
                badgeIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
            end
            if type(badgeIcon.SetSize) == "function" then badgeIcon:SetSize(20, 20) end
            if type(badgeIcon.SetPoint) == "function" then badgeIcon:SetPoint("TOPLEFT", badgeFrame, "TOPLEFT", 7, -5) end
        end

        -- Border overlay texture
        badgeBorder = badgeFrame:CreateTexture(nil, "OVERLAY")
        if badgeBorder then
            if type(badgeBorder.SetTexture) == "function" then
                badgeBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            end
            if type(badgeBorder.SetSize) == "function" then badgeBorder:SetSize(53, 53) end
            if type(badgeBorder.SetPoint) == "function" then
                badgeBorder:SetPoint("TOPLEFT", badgeFrame, "TOPLEFT", 0, 0)
            end
        end
    end

    -- Layer text font string
    if type(badgeFrame.CreateFontString) == "function" then
        badgeTextFS = badgeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if badgeTextFS then
            if type(badgeTextFS.GetFont) == "function" and type(badgeTextFS.SetFont) == "function" then
                local fontPath, fontSize = badgeTextFS:GetFont()
                if fontPath and fontSize then
                    badgeTextFS:SetFont(fontPath, fontSize, "OUTLINE")
                end
            end
            if type(badgeTextFS.SetPoint) == "function" then
                badgeTextFS:SetPoint("CENTER", badgeIcon or badgeFrame, "CENTER", 0, 0)
            end
            if type(badgeTextFS.SetText) == "function" then
                badgeTextFS:SetText("-")
            end
        end
    end
end

--- Sanitizes an angle into [0, 360].
-- Defaults strictly to 225 on nil, non-number, NaN, infinity, or out-of-range values.
-- @param angle any: Input angle
-- @return number: Sanitized angle in [0, 360]
function Badge.SanitizeAngle(angle)
    if angle == nil or type(angle) ~= "number" or angle ~= angle or angle == math.huge or angle == -math.huge then
        return DEFAULT_ANGLE
    end
    if angle < 0 or angle > 360 then
        return DEFAULT_ANGLE
    end
    return angle
end

--- Returns the current persisted minimap angle.
-- @return number: Persisted angle in [0, 360]
function Badge.GetPosition()
    _G.ULODB = _G.ULODB or {}
    return Badge.SanitizeAngle(_G.ULODB.minimapPos)
end

--- Updates the badge frame position along the Minimap circular perimeter.
-- Persists sanitized angle to both ULODB and ULO_CONFIG.
-- @param angle number: Minimap orbit angle
-- @return number: Sanitized angle
function Badge.SetPosition(angle)
    local sanitized = Badge.SanitizeAngle(angle)
    _G.ULODB = _G.ULODB or {}
    _G.ULODB.minimapPos = sanitized

    if _G.ULO_CONFIG and _G.ULO_CONFIG.ui then
        _G.ULO_CONFIG.ui.minimapAngle = sanitized
        _G.ULO_CONFIG.ui.minimapPos = sanitized
    end
    if ULO.config and ULO.config.ui then
        ULO.config.ui.minimapAngle = sanitized
        ULO.config.ui.minimapPos = sanitized
    end

    if badgeFrame and type(badgeFrame.SetPoint) == "function" then
        local parent = (type(badgeFrame.GetParent) == "function" and badgeFrame:GetParent()) or _G.Minimap or _G.UIParent
        local radiusW = MINIMAP_RADIUS
        local radiusH = MINIMAP_RADIUS
        local mm = _G.Minimap or parent
        if mm and type(mm.GetWidth) == "function" and type(mm.GetHeight) == "function" then
            local okW, mw = pcall(mm.GetWidth, mm)
            local okH, mh = pcall(mm.GetHeight, mm)
            if okW and okH and type(mw) == "number" and type(mh) == "number" and mw > 0 and mh > 0 then
                radiusW = (mw / 2) + MINIMAP_OFFSET
                radiusH = (mh / 2) + MINIMAP_OFFSET
            end
        end
        local rad = math.rad(sanitized)
        local cx = math.cos(rad) * radiusW
        local cy = math.sin(rad) * radiusH
        if type(badgeFrame.ClearAllPoints) == "function" then
            badgeFrame:ClearAllPoints()
        end
        badgeFrame:SetPoint("CENTER", parent, "CENTER", cx, cy)
    end

    return sanitized
end

--- Persists angle and positions the badge.
-- @param angle number: Minimap orbit angle
-- @return number: Sanitized angle
function Badge.SavePosition(angle)
    return Badge.SetPosition(angle)
end

--- Returns the primary badge frame widget.
-- @return table: Frame object
function Badge.GetFrame()
    return badgeFrame or _G.Minimap or _G.UIParent
end

--- Refreshes badge text, visibility, and orbital position.
function Badge.Update()
    local isEnabled = true
    if ULO.Detection and type(ULO.Detection.IsLayeringEnabled) == "function" then
        isEnabled = ULO.Detection.IsLayeringEnabled()
    end

    local userHidden = (type(_G.ULODB) == "table" and _G.ULODB.showMinimapBadge == false)
        or (type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.ui) == "table" and _G.ULO_CONFIG.ui.showMinimapBadge == false)

    if not isEnabled or userHidden then
        badgeShown = false
        if badgeFrame and type(badgeFrame.Hide) == "function" then
            badgeFrame:Hide()
        end
        return
    end

    badgeShown = true
    if badgeFrame and type(badgeFrame.Show) == "function" then
        badgeFrame:Show()
    end

    local layer = nil
    if ULO.Detection and type(ULO.Detection.GetCurrentLayer) == "function" then
        layer = ULO.Detection.GetCurrentLayer()
    end

    if layer then
        badgeText = tostring(layer)
    else
        badgeText = "-"
    end

    if badgeTextFS and type(badgeTextFS.SetText) == "function" then
        badgeTextFS:SetText(badgeText)
    end

    Badge.SetPosition(Badge.GetPosition())
end

--- Returns current badge layer text string.
-- @return string: Layer number or "-"
function Badge.GetText()
    Badge.Update()
    return badgeText
end

--- Returns whether the badge is currently visible.
-- @return boolean: True if visible in open world, false if instanced/hidden
function Badge.IsShown()
    Badge.Update()
    return badgeShown
end

--- Tooltip mouseover handler.
-- Displays Layer number, hardware Server ID, confidence, and active timers.
-- Uses AddLine exclusively (AddDoubleLine is not implemented in headless test harness).
-- @param frame table: Badge frame or anchor
function Badge.OnEnter(frame)
    if not _G.GameTooltip then return end
    frame = frame or Badge.GetFrame()

    if type(_G.GameTooltip.SetOwner) == "function" then
        _G.GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
    end
    if type(_G.GameTooltip.ClearLines) == "function" then
        _G.GameTooltip:ClearLines()
    end

    local layer = ULO.Detection and ULO.Detection.GetCurrentLayer and ULO.Detection.GetCurrentLayer()
    local serverId = ULO.Detection and ULO.Detection.GetCurrentServerId and ULO.Detection.GetCurrentServerId()
    local conf = (ULO.Detection and ULO.Detection.GetLayerConfidence and ULO.Detection.GetLayerConfidence()) or "UNDETERMINED"

    _G.GameTooltip:AddLine("Universal Layer Operator")
    if layer then
        _G.GameTooltip:AddLine(string.format("Layer %d", layer))
    else
        _G.GameTooltip:AddLine("Layer: Undetermined")
    end

    if serverId then
        _G.GameTooltip:AddLine(string.format("Server: %d", serverId))
    else
        _G.GameTooltip:AddLine("Server: Unknown")
    end

    _G.GameTooltip:AddLine(string.format("Confidence: %s", tostring(conf or "UNDETERMINED")))

    if ULO.Monitor then
        if ULO.Monitor.IsRefreshPending and ULO.Monitor.IsRefreshPending() then
            local rem = (ULO.Monitor.GetRefreshRemaining and ULO.Monitor.GetRefreshRemaining()) or 0
            _G.GameTooltip:AddLine(string.format("Refresh in: %d:%02d", math.floor(rem / 60), rem % 60))
        end
        if ULO.Monitor.GetCooldownRemaining and ULO.Monitor.GetCooldownRemaining() > 0 then
            local cd = ULO.Monitor.GetCooldownRemaining()
            _G.GameTooltip:AddLine(string.format("Cooldown: %d:%02d", math.floor(cd / 60), cd % 60))
        end
    end

    _G.GameTooltip:AddLine(" ")
    _G.GameTooltip:AddLine("Left-Click: Toggle Layer Operator HUD")
    _G.GameTooltip:AddLine("Right-Click: Open Settings")
    _G.GameTooltip:AddLine("Shift-Left-Click: Scan Target / NPCs")
    _G.GameTooltip:AddLine("Drag: Move around Minimap")

    if type(_G.GameTooltip.Show) == "function" then
        _G.GameTooltip:Show()
    end
end

--- Tooltip mouse leave handler.
-- @param frame table: Badge frame
function Badge.OnLeave(frame)
    if _G.GameTooltip then
        if type(_G.GameTooltip.ClearLines) == "function" then
            _G.GameTooltip:ClearLines()
        end
        if type(_G.GameTooltip.Hide) == "function" then
            _G.GameTooltip:Hide()
        end
    end
end

--- Click interaction handler.
-- Left click toggles Status HUD; Shift-left click scans units; Right click opens Blizzard Settings.
-- @param frame table: Badge frame
-- @param button string: "LeftButton" or "RightButton"
function Badge.OnClick(frame, button)
    if button == "RightButton" then
        if ULO.UI and ULO.UI.SettingsPanel and ULO.UI.SettingsPanel.Open then
            ULO.UI.SettingsPanel.Open()
        end
    elseif type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() then
        if ULO.Detection and type(ULO.Detection.ScanUnit) == "function" then
            ULO.Detection.ScanUnit("target")
            ULO.Detection.ScanUnit("mouseover")
            ULO.Detection.ScanUnit("npc")
            for i = 1, 10 do
                ULO.Detection.ScanUnit("nameplate" .. i)
            end
        end
        Badge.Update()
        if ULO.UI and ULO.UI.StatusHUD and type(ULO.UI.StatusHUD.Update) == "function" then
            ULO.UI.StatusHUD.Update()
        end
        local layer = ULO.Detection and ULO.Detection.GetCurrentLayer and ULO.Detection.GetCurrentLayer()
        local conf = (ULO.Detection and ULO.Detection.GetLayerConfidence and ULO.Detection.GetLayerConfidence()) or "UNDETERMINED"
        local msg = string.format("|cff00ccffULO:|r Scanned nearby units -> Layer: %s (%s)", tostring(layer or "?"), tostring(conf))
        if _G.DEFAULT_CHAT_FRAME and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
            _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    else
        if ULO.UI and ULO.UI.StatusHUD and ULO.UI.StatusHUD.Toggle then
            ULO.UI.StatusHUD.Toggle()
        end
    end
end

--- Calculates the cursor angle relative to the center of Minimap.
-- Uses GetCursorPosition(), UIParent/Minimap effective scale, and Minimap:GetCenter().
-- Normalizes angle to [0, 360].
-- Returns nil if required APIs, coordinates, or frames are unavailable.
-- @return number|nil: Angle in [0, 360], or nil on fallback
function Badge.CalculateCursorAngle()
    if type(_G.GetCursorPosition) ~= "function" then
        return nil
    end

    local minimap = _G.Minimap
    if not minimap or type(minimap.GetCenter) ~= "function" then
        return nil
    end

    local okCenter, mx, my = pcall(minimap.GetCenter, minimap)
    if not okCenter or type(mx) ~= "number" or type(my) ~= "number" then
        return nil
    end

    local okCur, cursorX, cursorY = pcall(_G.GetCursorPosition)
    if not okCur or type(cursorX) ~= "number" or type(cursorY) ~= "number" then
        return nil
    end

    local scale = 1
    if _G.UIParent and type(_G.UIParent.GetEffectiveScale) == "function" then
        local okScale, s = pcall(_G.UIParent.GetEffectiveScale, _G.UIParent)
        if okScale and type(s) == "number" and s > 0 then
            scale = s
        end
    end
    if type(minimap.GetEffectiveScale) == "function" then
        local okScale, s = pcall(minimap.GetEffectiveScale, minimap)
        if okScale and type(s) == "number" and s > 0 then
            scale = s
        end
    end

    local cx = cursorX / scale
    local cy = cursorY / scale
    local dx = cx - mx
    local dy = cy - my

    if dx == 0 and dy == 0 then
        return nil
    end

    local atan2 = math.atan2 or math.atan
    local rad = atan2(dy, dx)
    local deg = math.deg(rad)
    deg = (deg % 360 + 360) % 360

    return Badge.SanitizeAngle(deg)
end

--- Returns whether the badge is currently being dragged.
-- @return boolean: True if dragging
function Badge.IsDragging()
    return isDragging == true
end

--- Handler for drag start event.
-- Uses pure orbital positioning so the badge remains anchored to Minimap.
-- @param frame table: Badge frame
function Badge.OnDragStart(frame)
    isDragging = true
    local angle = Badge.CalculateCursorAngle()
    if angle then
        Badge.SetPosition(angle)
    end
end

--- Handler for OnUpdate event during drag.
-- @param frame table: Badge frame
-- @param elapsed number: Elapsed time
function Badge.OnUpdate(frame, elapsed)
    if not isDragging then return end
    local angle = Badge.CalculateCursorAngle()
    if angle then
        Badge.SetPosition(angle)
    end
end

--- Handler for drag stop event.
-- Saves final orbital position to saved variables.
-- @param frame table: Badge frame
function Badge.OnDragStop(frame)
    isDragging = false
    local angle = Badge.CalculateCursorAngle()
    if angle then
        Badge.SavePosition(angle)
    else
        Badge.SavePosition(Badge.GetPosition())
    end
end

-- Wire Frame Scripts
if badgeFrame then
    badgeFrame:SetScript("OnEnter", function(self) Badge.OnEnter(self) end)
    badgeFrame:SetScript("OnLeave", function(self) Badge.OnLeave(self) end)
    badgeFrame:SetScript("OnClick", function(self, button) Badge.OnClick(self, button) end)
    badgeFrame:SetScript("OnDragStart", function(self) Badge.OnDragStart(self) end)
    badgeFrame:SetScript("OnUpdate", function(self, elapsed) Badge.OnUpdate(self, elapsed) end)
    badgeFrame:SetScript("OnDragStop", function(self) Badge.OnDragStop(self) end)
end

-- Event registration for world and instance transitions
if type(_G.CreateFrame) == "function" then
    local evtFrame = _G.CreateFrame("Frame", "ULOMinimapBadgeEventFrame")
    if evtFrame and type(evtFrame.RegisterEvent) == "function" then
        evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        evtFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        evtFrame:RegisterEvent("ZONE_CHANGED")
        evtFrame:SetScript("OnEvent", function(self, event, ...)
            Badge.Update()
        end)
    end
end

-- Subscribe to ULO Internal Event Callbacks
if ULO.RegisterCallback then
    ULO.RegisterCallback("OnLayerChanged", function(layer, serverId, zoneId)
        Badge.Update()
    end)
end

-- Reposition once Minimap finishes initial layout/resizing
if _G.Minimap and type(_G.Minimap.HookScript) == "function" then
    pcall(_G.Minimap.HookScript, _G.Minimap, "OnSizeChanged", function()
        Badge.SetPosition(Badge.GetPosition())
    end)
    pcall(_G.Minimap.HookScript, _G.Minimap, "OnShow", function()
        Badge.SetPosition(Badge.GetPosition())
    end)
end
if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
    _G.C_Timer.After(0, function()
        Badge.SetPosition(Badge.GetPosition())
    end)
end

-- Initialize position
Badge.SetPosition(Badge.GetPosition())

return Badge
