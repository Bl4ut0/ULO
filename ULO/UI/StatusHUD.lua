-- ============================================================================
-- ULO: Universal Layer Operator
-- File: UI/StatusHUD.lua
-- Description: Movable status HUD. Displays active layer number, 180s countdown
--              with <=10s visual urgency alert, post-transfer cooldown banner,
--              interactive [Refresh Now] and [Hop Layer] buttons, and chevron mode.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.UI = ULO.UI or {}
ULO.UI.StatusHUD = ULO.UI.StatusHUD or {}
local StatusHUD = ULO.UI.StatusHUD

local Detection = ULO.Detection
local Monitor = ULO.Monitor
local Coordination = ULO.Coordination
local Compat = ULO.Compat
local C = ULO.Constants

-- Constants
local HUD_WIDTH = 220
local HUD_HEIGHT = 50
local DEFAULT_POS_X = 100
local DEFAULT_POS_Y = 100

-- Runtime State
local isMinimized = false

-- Reference or create Primary HUD Frame
local hudFrame = _G.ULOStatusHUD
if not hudFrame and type(_G.CreateFrame) == "function" then
    hudFrame = _G.CreateFrame("Frame", "ULOStatusHUD", _G.UIParent)
end

-- Child Visual Elements
local statusTextFS = nil
local countdownTextFS = nil
local cooldownTextFS = nil
local refreshButton = nil
local hopButton = nil

if hudFrame then
    hudFrame:SetSize(HUD_WIDTH, HUD_HEIGHT)
    if type(hudFrame.SetClampedToScreen) == "function" then
        hudFrame:SetClampedToScreen(true)
    end
    if type(hudFrame.SetMovable) == "function" then
        hudFrame:SetMovable(true)
    end
    if type(hudFrame.EnableMouse) == "function" then
        hudFrame:EnableMouse(true)
    end
    if type(hudFrame.RegisterForDrag) == "function" then
        hudFrame:RegisterForDrag("LeftButton")
    end

    -- Background texture
    if type(hudFrame.CreateTexture) == "function" then
        local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
        if bg and type(bg.SetAllPoints) == "function" then
            bg:SetAllPoints(hudFrame)
            if type(bg.SetTexture) == "function" then
                bg:SetTexture("Interface\\AddOns\\ULO\\Media\\ULOHudBg")
            end
        end
    end

    -- Font strings for layer, countdown, and cooldown readouts
    if type(hudFrame.CreateFontString) == "function" then
        statusTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if statusTextFS and type(statusTextFS.SetPoint) == "function" then
            statusTextFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 8, -6)
            if type(statusTextFS.SetText) == "function" then
                statusTextFS:SetText("Layer: ? (Undetermined)")
            end
        end

        countdownTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if countdownTextFS and type(countdownTextFS.SetPoint) == "function" then
            countdownTextFS:SetPoint("BOTTOMLEFT", hudFrame, "BOTTOMLEFT", 8, 8)
            if type(countdownTextFS.SetText) == "function" then
                countdownTextFS:SetText("3:00")
            end
        end

        cooldownTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        if cooldownTextFS and type(cooldownTextFS.SetPoint) == "function" then
            cooldownTextFS:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -8, 8)
            if type(cooldownTextFS.SetText) == "function" then
                cooldownTextFS:SetText("")
            end
        end
    end

    -- Interactive Action Buttons
    if type(_G.CreateFrame) == "function" then
        refreshButton = _G.CreateFrame("Button", "ULOStatusHUDRefreshButton", hudFrame)
        if refreshButton then
            refreshButton:SetSize(60, 18)
            if type(refreshButton.SetPoint) == "function" then
                refreshButton:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -8, -6)
            end
            if type(refreshButton.CreateTexture) == "function" then
                local rBg = refreshButton:CreateTexture(nil, "BACKGROUND")
                if rBg and type(rBg.SetAllPoints) == "function" then
                    rBg:SetAllPoints(refreshButton)
                    if type(rBg.SetColorTexture) == "function" then
                        rBg:SetColorTexture(0.18, 0.22, 0.30, 0.90)
                    elseif type(rBg.SetTexture) == "function" then
                        rBg:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
                    end
                end
            end
            if type(refreshButton.CreateFontString) == "function" then
                local rText = refreshButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                if rText then
                    if type(rText.SetAllPoints) == "function" then
                        rText:SetAllPoints(refreshButton)
                    end
                    if type(rText.SetText) == "function" then
                        rText:SetText("Refresh")
                    end
                end
            elseif type(refreshButton.SetText) == "function" then
                refreshButton:SetText("Refresh")
            end
            refreshButton:SetScript("OnClick", function(self)
                if ULO.Monitor and type(ULO.Monitor.RequestRefreshNow) == "function" then
                    ULO.Monitor.RequestRefreshNow()
                end
            end)
        end

        hopButton = _G.CreateFrame("Button", "ULOStatusHUDHopButton", hudFrame)
        if hopButton then
            hopButton:SetSize(40, 18)
            if type(hopButton.SetPoint) == "function" then
                hopButton:SetPoint("RIGHT", refreshButton or hudFrame, "LEFT", -4, 0)
            end
            if type(hopButton.CreateTexture) == "function" then
                local hBg = hopButton:CreateTexture(nil, "BACKGROUND")
                if hBg and type(hBg.SetAllPoints) == "function" then
                    hBg:SetAllPoints(hopButton)
                    if type(hBg.SetColorTexture) == "function" then
                        hBg:SetColorTexture(0.18, 0.22, 0.30, 0.90)
                    elseif type(hBg.SetTexture) == "function" then
                        hBg:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
                    end
                end
            end
            if type(hopButton.CreateFontString) == "function" then
                local hText = hopButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                if hText then
                    if type(hText.SetAllPoints) == "function" then
                        hText:SetAllPoints(hopButton)
                    end
                    if type(hText.SetText) == "function" then
                        hText:SetText("Hop")
                    end
                end
            elseif type(hopButton.SetText) == "function" then
                hopButton:SetText("Hop")
            end
            hopButton:SetScript("OnClick", function(self)
                if ULO.Coordination and type(ULO.Coordination.RequestLayerHop) == "function" then
                    ULO.Coordination.RequestLayerHop()
                end
            end)
        end
    end

    -- Drag Scripts
    hudFrame:SetScript("OnDragStart", function(self)
        if type(self.StartMoving) == "function" then
            self:StartMoving()
        end
    end)

    hudFrame:SetScript("OnDragStop", function(self)
        if type(self.StopMovingOrSizing) == "function" then
            self:StopMovingOrSizing()
        end

        local posX, posY = nil, nil

        -- Method 1: Canonical Blizzard FrameXML Left/Bottom query
        if type(self.GetLeft) == "function" and type(self.GetBottom) == "function" then
            local okL, left = pcall(self.GetLeft, self)
            local okB, bottom = pcall(self.GetBottom, self)
            if okL and okB and type(left) == "number" and type(bottom) == "number" then
                local scale = (type(self.GetEffectiveScale) == "function" and self:GetEffectiveScale()) or 1
                local parentScale = (_G.UIParent and type(_G.UIParent.GetEffectiveScale) == "function" and _G.UIParent:GetEffectiveScale()) or 1
                if type(scale) == "number" and type(parentScale) == "number" and parentScale > 0 then
                    posX = left * scale / parentScale
                    posY = bottom * scale / parentScale
                else
                    posX = left
                    posY = bottom
                end
            end
        end

        -- Method 2: Secondary FrameXML GetPoint query
        if (not posX or not posY) and type(self.GetPoint) == "function" then
            local ok, point, relTo, relPoint, xOfs, yOfs = pcall(self.GetPoint, self, 1)
            if ok and type(xOfs) == "number" and type(yOfs) == "number" then
                posX = xOfs
                posY = yOfs
            end
        end

        -- Method 3: Headless test harness mock __points table inspection
        if (not posX or not posY) and self.__points and type(self.__points) == "table" and #self.__points > 0 then
            local pt = self.__points[#self.__points]
            if pt and type(pt.x) == "number" and type(pt.y) == "number" then
                posX = pt.x
                posY = pt.y
            end
        end

        -- Method 4: Existing saved position fallback or default constants
        if not posX or posX ~= posX or posX == math.huge or posX == -math.huge then
            posX = (_G.ULODB and _G.ULODB.hudPosition and _G.ULODB.hudPosition.x) or DEFAULT_POS_X
        end
        if not posY or posY ~= posY or posY == math.huge or posY == -math.huge then
            posY = (_G.ULODB and _G.ULODB.hudPosition and _G.ULODB.hudPosition.y) or DEFAULT_POS_Y
        end

        -- Rounding and boundary clamping: x >= 0, y >= 0
        local finalX = math.floor(math.max(0, tonumber(posX) or DEFAULT_POS_X) + 0.5)
        local finalY = math.floor(math.max(0, tonumber(posY) or DEFAULT_POS_Y) + 0.5)

        -- Persist into saved variables and re-anchor frame
        StatusHUD.SetPosition(finalX, finalY)
    end)
end

--- Returns the primary HUD frame.
-- @return table: Frame object
function StatusHUD.GetFrame()
    return hudFrame or _G.UIParent
end

--- Formats the primary status readout string.
-- Reflects open-world layering state, active layer index, and confidence.
-- @return string: Status text
function StatusHUD.GetStatusText()
    local isEnabled = true
    if ULO.Detection and type(ULO.Detection.IsLayeringEnabled) == "function" then
        isEnabled = ULO.Detection.IsLayeringEnabled()
    end

    if not isEnabled then
        return "Instanced (Layering Inactive)"
    end

    local layer = ULO.Detection and ULO.Detection.GetCurrentLayer and ULO.Detection.GetCurrentLayer()
    local conf = (ULO.Detection and ULO.Detection.GetLayerConfidence and ULO.Detection.GetLayerConfidence()) or "UNDETERMINED"

    if layer and conf == "CONFIRMED" then
        return string.format("Layer: %d (Confirmed)", layer)
    elseif layer then
        return string.format("Layer: %d (%s)", layer, tostring(conf))
    else
        return "Layer: ? (Undetermined)"
    end
end

--- Formats the 180s layer refresh countdown timer as m:ss.
-- Strictly zero-padded (%d:%02d).
-- @return string: Countdown string
function StatusHUD.GetCountdownText()
    local rem = 0
    if ULO.Monitor and type(ULO.Monitor.GetRefreshRemaining) == "function" then
        rem = ULO.Monitor.GetRefreshRemaining()
    end
    local mins = math.floor(rem / 60)
    local secs = rem % 60
    return string.format("%d:%02d", mins, secs)
end

--- Evaluates whether the <= 10s urgent visual alert is active.
-- Triggers at exactly 10.0s remaining when a refresh is pending.
-- @return boolean: True if urgent alert active
function StatusHUD.IsUrgentAlertActive()
    if not ULO.Monitor then return false end
    local isPending = ULO.Monitor.IsRefreshPending and ULO.Monitor.IsRefreshPending()
    local rem = (ULO.Monitor.GetRefreshRemaining and ULO.Monitor.GetRefreshRemaining()) or 0
    return (isPending == true) and (rem <= 10)
end

--- Formats the post-transfer hopping cooldown timer as m:ss.
-- @return string: Cooldown string
function StatusHUD.GetCooldownText()
    local rem = 0
    if ULO.Monitor and type(ULO.Monitor.GetCooldownRemaining) == "function" then
        rem = ULO.Monitor.GetCooldownRemaining()
    end
    local mins = math.floor(rem / 60)
    local secs = rem % 60
    return string.format("%d:%02d", mins, secs)
end

--- Returns the persisted HUD coordinates (x, y).
-- @return number, number: x, y coordinates
function StatusHUD.GetPosition()
    _G.ULODB = _G.ULODB or {}
    _G.ULODB.hudPosition = _G.ULODB.hudPosition or { x = DEFAULT_POS_X, y = DEFAULT_POS_Y }
    return _G.ULODB.hudPosition.x, _G.ULODB.hudPosition.y
end

--- Sets and persists the HUD position.
-- @param x number: Horizontal offset
-- @param y number: Vertical offset
function StatusHUD.SetPosition(x, y)
    local posX = tonumber(x)
    local posY = tonumber(y)
    if not posX or posX ~= posX or posX == math.huge or posX == -math.huge then
        posX = DEFAULT_POS_X
    end
    if not posY or posY ~= posY or posY == math.huge or posY == -math.huge then
        posY = DEFAULT_POS_Y
    end
    local finalX = math.max(0, math.floor(posX + 0.5))
    local finalY = math.max(0, math.floor(posY + 0.5))

    _G.ULODB = _G.ULODB or {}
    _G.ULODB.hudPosition = { x = finalX, y = finalY }
    if _G.ULO_CONFIG then
        _G.ULO_CONFIG.ui = _G.ULO_CONFIG.ui or {}
        _G.ULO_CONFIG.ui.hudPosition = _G.ULODB.hudPosition
    end
    if ULO and ULO.config then
        ULO.config.ui = ULO.config.ui or {}
        ULO.config.ui.hudPosition = _G.ULODB.hudPosition
    end

    if hudFrame and type(hudFrame.ClearAllPoints) == "function" and type(hudFrame.SetPoint) == "function" then
        hudFrame:ClearAllPoints()
        hudFrame:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", _G.ULODB.hudPosition.x, _G.ULODB.hudPosition.y)
    end
end

--- Toggles HUD frame visibility.
function StatusHUD.Toggle()
    if not hudFrame then return end
    if type(hudFrame.IsShown) == "function" and hudFrame:IsShown() then
        StatusHUD.Hide()
    else
        StatusHUD.Show()
    end
end

--- Shows the HUD frame.
function StatusHUD.Show()
    if hudFrame and type(hudFrame.Show) == "function" then
        hudFrame:Show()
        StatusHUD.Update()
    end
end

--- Hides the HUD frame.
function StatusHUD.Hide()
    if hudFrame and type(hudFrame.Hide) == "function" then
        hudFrame:Hide()
    end
end

--- Refreshes all HUD sub-elements (status, countdown, cooldown, buttons).
function StatusHUD.Update()
    if statusTextFS and type(statusTextFS.SetText) == "function" then
        statusTextFS:SetText(StatusHUD.GetStatusText())
    end
    if countdownTextFS and type(countdownTextFS.SetText) == "function" then
        countdownTextFS:SetText(StatusHUD.GetCountdownText())
    end
    if cooldownTextFS and type(cooldownTextFS.SetText) == "function" then
        cooldownTextFS:SetText(StatusHUD.GetCooldownText())
    end
end

-- Event registration for initial SavedVariables positioning and world reload sync
if type(_G.CreateFrame) == "function" then
    local evtFrame = _G.CreateFrame("Frame", "ULOStatusHUDEventFrame")
    if evtFrame and type(evtFrame.RegisterEvent) == "function" and type(evtFrame.SetScript) == "function" then
        evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        evtFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_ENTERING_WORLD" then
                StatusHUD.SetPosition(StatusHUD.GetPosition())
                if type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.ui) == "table" and _G.ULO_CONFIG.ui.showStatusHUD == false then
                    StatusHUD.Hide()
                else
                    StatusHUD.Update()
                end
            end
        end)
    end
end

-- Apply initial anchor
StatusHUD.SetPosition(StatusHUD.GetPosition())

-- Subscribe to ULO Callbacks for automatic HUD refreshing
if ULO.RegisterCallback then
    ULO.RegisterCallback("OnLayerChanged", function() StatusHUD.Update() end)
    ULO.RegisterCallback("OnRefreshWarning", function() StatusHUD.Update() end)
    ULO.RegisterCallback("OnRefreshTriggered", function() StatusHUD.Update() end)
    ULO.RegisterCallback("OnCooldownStarted", function() StatusHUD.Update() end)
    ULO.RegisterCallback("OnCooldownExpired", function() StatusHUD.Update() end)
end

return StatusHUD
