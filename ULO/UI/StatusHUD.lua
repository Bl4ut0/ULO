-- ============================================================================
-- ULO: Universal Layer Operator
-- File: UI/StatusHUD.lua
-- Description: Movable Layer Operator HUD. Displays active layer number, 180s
--              countdown with <=10s visual urgency alert, post-transfer cooldown,
--              L1-L8 direct hop grid, [Hop Any], [Refresh], [Scan NPCs], and
--              [Auto-Inv] controls.
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

-- Constants (width strictly <= 300 per HUD layout tests)
local HUD_WIDTH = 296
local HUD_HEIGHT = 264
local DEFAULT_POS_X = 380
local DEFAULT_POS_Y = 360

-- Runtime State
local isMinimized = false
local lastActionText = "Drag header to move | Click L1-L8 to hop"

-- Reference or create Primary HUD Frame
local hudFrame = _G.ULOStatusHUD
if not hudFrame and type(_G.CreateFrame) == "function" then
    hudFrame = _G.CreateFrame("Frame", "ULOStatusHUD", _G.UIParent)
end

-- Child Visual Elements
local statusTextFS = nil
local detailTextFS = nil
local countdownTextFS = nil
local cooldownTextFS = nil
local actionStatusFS = nil
local refreshButton = nil
local hopButton = nil
local scanButton = nil
local autoInvButton = nil
local optionsButton = nil
local closeButton = nil
local layerHopButtons = {}

local function PrintToChat(msg)
    if _G.DEFAULT_CHAT_FRAME and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffULO:|r " .. tostring(msg))
    end
end

local function SetSolidColor(tex, r, g, b, a)
    if not tex then return end
    if type(tex.SetColorTexture) == "function" then
        tex:SetColorTexture(r, g, b, a or 1)
    elseif type(tex.SetTexture) == "function" then
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        if type(tex.SetVertexColor) == "function" then
            tex:SetVertexColor(r, g, b, a or 1)
        end
    end
end

local function AddBorder(frame, r, g, b, a, thickness)
    if not frame or type(frame.CreateTexture) ~= "function" then return end
    local t = thickness or 1

    local top = frame:CreateTexture(nil, "BORDER")
    if top then
        SetSolidColor(top, r, g, b, a)
        if type(top.SetPoint) == "function" and type(top.SetHeight) == "function" then
            top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            top:SetHeight(t)
        end
    end

    local bottom = frame:CreateTexture(nil, "BORDER")
    if bottom then
        SetSolidColor(bottom, r, g, b, a)
        if type(bottom.SetPoint) == "function" and type(bottom.SetHeight) == "function" then
            bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(t)
        end
    end

    local left = frame:CreateTexture(nil, "BORDER")
    if left then
        SetSolidColor(left, r, g, b, a)
        if type(left.SetPoint) == "function" and type(left.SetWidth) == "function" then
            left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            left:SetWidth(t)
        end
    end

    local right = frame:CreateTexture(nil, "BORDER")
    if right then
        SetSolidColor(right, r, g, b, a)
        if type(right.SetPoint) == "function" and type(right.SetWidth) == "function" then
            right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            right:SetWidth(t)
        end
    end
end

local function SetActionFeedback(msg)
    lastActionText = tostring(msg or "")
    if actionStatusFS and type(actionStatusFS.SetText) == "function" then
        actionStatusFS:SetText(lastActionText)
    end
end

local function CreateStyledButton(globalName, parent, width, height, labelText, onClick)
    if type(_G.CreateFrame) ~= "function" then return nil end
    local btn = _G.CreateFrame("Button", globalName, parent)
    if not btn then return nil end

    if type(btn.SetSize) == "function" then
        btn:SetSize(width, height)
    end
    if type(btn.CreateTexture) == "function" then
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        if bg then
            if type(bg.SetAllPoints) == "function" then
                bg:SetAllPoints(btn)
            end
            SetSolidColor(bg, 0.12, 0.16, 0.24, 0.95)
        end
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        if hl then
            if type(hl.SetAllPoints) == "function" then
                hl:SetAllPoints(btn)
            end
            SetSolidColor(hl, 0.0, 0.72, 0.92, 0.22)
        end
    end
    AddBorder(btn, 0.62, 0.48, 0.18, 0.9, 1)

    if type(btn.CreateFontString) == "function" then
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if fs then
            if type(fs.SetAllPoints) == "function" then
                fs:SetAllPoints(btn)
            end
            if type(fs.SetText) == "function" then
                fs:SetText(labelText)
            end
            btn.textFS = fs
        end
    elseif type(btn.SetText) == "function" then
        btn:SetText(labelText)
    end

    if type(btn.SetScript) == "function" and type(onClick) == "function" then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

local function TriggerHopToLayer(targetLayer)
    if ULO.Coordination and type(ULO.Coordination.RequestLayerHop) == "function" then
        ULO.Coordination.RequestLayerHop(targetLayer)
    end
    if targetLayer and ULO.Interop then
        if ULO.Interop.AutoLayer and type(ULO.Interop.AutoLayer.FormatBroadcastMessage) == "function" then
            pcall(ULO.Interop.AutoLayer.FormatBroadcastMessage, targetLayer)
        end
        if ULO.Interop.Overlord and type(ULO.Interop.Overlord.BroadcastHopRequest) == "function" then
            pcall(ULO.Interop.Overlord.BroadcastHopRequest, targetLayer)
        end
    end

    if targetLayer then
        local msg = string.format("Requested hop to Layer %d...", targetLayer)
        SetActionFeedback(msg)
        PrintToChat(msg)
    else
        local msg = "Requested hop to next available layer..."
        SetActionFeedback(msg)
        PrintToChat(msg)
    end
    StatusHUD.Update()
end

if hudFrame then
    hudFrame:SetSize(HUD_WIDTH, HUD_HEIGHT)
    if type(hudFrame.SetFrameStrata) == "function" then
        hudFrame:SetFrameStrata("DIALOG")
    end
    if type(hudFrame.SetClampedToScreen) == "function" then
        hudFrame:SetClampedToScreen(true)
    end
    if type(hudFrame.SetClampRectInsets) == "function" then
        hudFrame:SetClampRectInsets(0, 0, 0, 0)
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

    -- Solid Obsidian backdrop + gold borders so frame is always visible regardless of asset indexing
    if type(hudFrame.CreateTexture) == "function" then
        local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
        if bg then
            if type(bg.SetAllPoints) == "function" then
                bg:SetAllPoints(hudFrame)
            end
            SetSolidColor(bg, 0.05, 0.07, 0.12, 0.94)
        end

        local headerBg = hudFrame:CreateTexture(nil, "ARTWORK")
        if headerBg then
            SetSolidColor(headerBg, 0.09, 0.13, 0.22, 0.98)
            if type(headerBg.SetPoint) == "function" and type(headerBg.SetHeight) == "function" then
                headerBg:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 1, -1)
                headerBg:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -1, -1)
                headerBg:SetHeight(26)
            end
        end

        local headerLine = hudFrame:CreateTexture(nil, "OVERLAY")
        if headerLine then
            SetSolidColor(headerLine, 0.0, 0.78, 0.95, 0.85)
            if type(headerLine.SetPoint) == "function" and type(headerLine.SetHeight) == "function" then
                headerLine:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 1, -27)
                headerLine:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -1, -27)
                headerLine:SetHeight(1)
            end
        end
    end
    AddBorder(hudFrame, 0.78, 0.61, 0.24, 0.95, 1)

    -- Header, Status, Countdown, Cooldown, and Feedback FontStrings
    if type(hudFrame.CreateFontString) == "function" then
        local titleFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        if titleFS and type(titleFS.SetPoint) == "function" then
            titleFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -6)
            if type(titleFS.SetText) == "function" then
                titleFS:SetText("|cff00ccffULO|r Layer Operator")
            end
        end

        statusTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        if statusTextFS and type(statusTextFS.SetPoint) == "function" then
            statusTextFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -32)
            if type(statusTextFS.SetText) == "function" then
                statusTextFS:SetText("Layer: ? (Undetermined)")
            end
        end

        detailTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if detailTextFS and type(detailTextFS.SetPoint) == "function" then
            detailTextFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -54)
            if type(detailTextFS.SetText) == "function" then
                detailTextFS:SetText("Server: - | Auto-Inv: ON")
            end
        end

        local timerLabelFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if timerLabelFS and type(timerLabelFS.SetPoint) == "function" then
            timerLabelFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -74)
            if type(timerLabelFS.SetText) == "function" then
                timerLabelFS:SetText("Refresh:")
            end
        end

        countdownTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if countdownTextFS and type(countdownTextFS.SetPoint) == "function" then
            countdownTextFS:SetPoint("LEFT", timerLabelFS or hudFrame, "RIGHT", 4, 0)
            if type(countdownTextFS.SetText) == "function" then
                countdownTextFS:SetText("3:00")
            end
        end

        local cdLabelFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        if cdLabelFS and type(cdLabelFS.SetPoint) == "function" then
            cdLabelFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 152, -74)
            if type(cdLabelFS.SetText) == "function" then
                cdLabelFS:SetText("Hop CD:")
            end
        end

        cooldownTextFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        if cooldownTextFS and type(cooldownTextFS.SetPoint) == "function" then
            cooldownTextFS:SetPoint("LEFT", cdLabelFS or hudFrame, "RIGHT", 4, 0)
            if type(cooldownTextFS.SetText) == "function" then
                cooldownTextFS:SetText("0:00")
            end
        end

        local hopLabelFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if hopLabelFS and type(hopLabelFS.SetPoint) == "function" then
            hopLabelFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -96)
            if type(hopLabelFS.SetText) == "function" then
                hopLabelFS:SetText("Request Specific Layer:")
            end
        end

        actionStatusFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        if actionStatusFS and type(actionStatusFS.SetPoint) == "function" then
            actionStatusFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -178)
            if type(actionStatusFS.SetText) == "function" then
                actionStatusFS:SetText(lastActionText)
            end
        end
    end

    -- Header Buttons
    closeButton = CreateStyledButton("ULOStatusHUDCloseButton", hudFrame, 18, 18, "X", function()
        StatusHUD.Hide()
    end)
    if closeButton and type(closeButton.SetPoint) == "function" then
        closeButton:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -4, -4)
    end

    optionsButton = CreateStyledButton("ULOStatusHUDOptionsButton", hudFrame, 62, 18, "Options", function()
        if ULO.UI and ULO.UI.SettingsPanel and ULO.UI.SettingsPanel.Open then
            ULO.UI.SettingsPanel.Open()
        end
    end)
    if optionsButton and type(optionsButton.SetPoint) == "function" then
        optionsButton:SetPoint("RIGHT", closeButton or hudFrame, "LEFT", -4, 0)
    end

    -- 4x2 Direct Layer Hop Grid (L1 - L8)
    for i = 1, 8 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local lBtn = CreateStyledButton("ULOStatusHUDHopL" .. i, hudFrame, 65, 26, "L" .. i, function()
            TriggerHopToLayer(i)
        end)
        if lBtn and type(lBtn.SetPoint) == "function" then
            lBtn:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10 + (col * 70), -114 - (row * 30))
        end
        layerHopButtons[i] = lBtn
    end

    -- Primary Interactive Action Buttons
    hopButton = CreateStyledButton("ULOStatusHUDHopButton", hudFrame, 134, 26, "Hop Any", function()
        TriggerHopToLayer(nil)
    end)
    if hopButton and type(hopButton.SetPoint) == "function" then
        hopButton:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -196)
    end

    refreshButton = CreateStyledButton("ULOStatusHUDRefreshButton", hudFrame, 134, 26, "Refresh", function()
        if ULO.Monitor and type(ULO.Monitor.RequestRefreshNow) == "function" then
            ULO.Monitor.RequestRefreshNow()
            SetActionFeedback("Requested layer refresh / reload...")
        end
    end)
    if refreshButton and type(refreshButton.SetPoint) == "function" then
        refreshButton:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -10, -196)
    end

    scanButton = CreateStyledButton("ULOStatusHUDScanButton", hudFrame, 134, 26, "Scan NPCs", function()
        if ULO.Detection and type(ULO.Detection.ScanUnit) == "function" then
            ULO.Detection.ScanUnit("target")
            ULO.Detection.ScanUnit("mouseover")
            ULO.Detection.ScanUnit("npc")
            ULO.Detection.ScanUnit("focus")
            for idx = 1, 10 do
                ULO.Detection.ScanUnit("nameplate" .. idx)
            end
        end
        local layer = ULO.Detection and ULO.Detection.GetCurrentLayer and ULO.Detection.GetCurrentLayer()
        local conf = (ULO.Detection and ULO.Detection.GetLayerConfidence and ULO.Detection.GetLayerConfidence()) or "UNDETERMINED"
        SetActionFeedback(string.format("Scanned units -> Layer: %s (%s)", tostring(layer or "?"), tostring(conf)))
        StatusHUD.Update()
    end)
    if scanButton and type(scanButton.SetPoint) == "function" then
        scanButton:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -228)
    end

    autoInvButton = CreateStyledButton("ULOStatusHUDAutoInvButton", hudFrame, 134, 26, "Auto-Inv: ON", function()
        local enabled = true
        if ULO.Coordination and type(ULO.Coordination.ToggleAutoInvite) == "function" then
            enabled = ULO.Coordination.ToggleAutoInvite()
        end
        SetActionFeedback("Auto-Invite " .. (enabled and "Enabled" or "Disabled"))
        StatusHUD.Update()
        if ULO.UI and ULO.UI.SettingsPanel and type(ULO.UI.SettingsPanel.RefreshControls) == "function" then
            ULO.UI.SettingsPanel.RefreshControls()
        end
    end)
    if autoInvButton and type(autoInvButton.SetPoint) == "function" then
        autoInvButton:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -10, -228)
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

    if _G.UIParent and type(_G.UIParent.GetWidth) == "function" and type(_G.UIParent.GetHeight) == "function" then
        local okW, pw = pcall(_G.UIParent.GetWidth, _G.UIParent)
        local okH, ph = pcall(_G.UIParent.GetHeight, _G.UIParent)
        if okW and type(pw) == "number" and pw > HUD_WIDTH then
            finalX = math.min(finalX, math.max(0, math.floor(pw - HUD_WIDTH)))
        end
        if okH and type(ph) == "number" and ph > HUD_HEIGHT then
            finalY = math.min(finalY, math.max(0, math.floor(ph - HUD_HEIGHT)))
        end
    end

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

--- Re-centers the HUD window to its visible default position and shows it.
function StatusHUD.ResetPosition()
    _G.ULODB = _G.ULODB or {}
    _G.ULODB.hudLayoutV2 = true
    StatusHUD.SetPosition(DEFAULT_POS_X, DEFAULT_POS_Y)
    StatusHUD.Show()
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

--- Refreshes all HUD sub-elements (status, telemetry, countdown, cooldown, buttons).
function StatusHUD.Update()
    if statusTextFS and type(statusTextFS.SetText) == "function" then
        statusTextFS:SetText(StatusHUD.GetStatusText())
    end

    local serverId = ULO.Detection and ULO.Detection.GetCurrentServerId and ULO.Detection.GetCurrentServerId()
    local zoneId = ULO.Detection and ULO.Detection.GetCurrentZoneId and ULO.Detection.GetCurrentZoneId()
    local autoInv = true
    if ULO.Coordination and type(ULO.Coordination.IsAutoInviteEnabled) == "function" then
        autoInv = ULO.Coordination.IsAutoInviteEnabled()
    end

    if detailTextFS and type(detailTextFS.SetText) == "function" then
        if serverId then
            detailTextFS:SetText(string.format("Server: %s | Zone: %s | Auto-Inv: %s",
                tostring(serverId), tostring(zoneId or "-"), autoInv and "ON" or "OFF"))
        else
            detailTextFS:SetText(string.format("Auto-Inv: %s | Target an NPC to detect layer",
                autoInv and "ON" or "OFF"))
        end
    end

    if countdownTextFS and type(countdownTextFS.SetText) == "function" then
        countdownTextFS:SetText(StatusHUD.GetCountdownText())
        if type(countdownTextFS.SetTextColor) == "function" then
            if StatusHUD.IsUrgentAlertActive() then
                countdownTextFS:SetTextColor(1, 0.25, 0.25)
            else
                countdownTextFS:SetTextColor(1, 1, 1)
            end
        end
    end

    if cooldownTextFS and type(cooldownTextFS.SetText) == "function" then
        cooldownTextFS:SetText(StatusHUD.GetCooldownText())
    end

    if autoInvButton and autoInvButton.textFS and type(autoInvButton.textFS.SetText) == "function" then
        autoInvButton.textFS:SetText(autoInv and "Auto-Inv: ON" or "Auto-Inv: OFF")
    end

    if actionStatusFS and type(actionStatusFS.SetText) == "function" then
        actionStatusFS:SetText(lastActionText)
    end
end

-- Event registration for initial SavedVariables positioning and world reload sync
if type(_G.CreateFrame) == "function" then
    local evtFrame = _G.CreateFrame("Frame", "ULOStatusHUDEventFrame")
    if evtFrame and type(evtFrame.RegisterEvent) == "function" and type(evtFrame.SetScript) == "function" then
        evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        evtFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_ENTERING_WORLD" then
                _G.ULODB = _G.ULODB or {}
                if not _G.ULODB.hudLayoutV2 then
                    _G.ULODB.hudPosition = { x = DEFAULT_POS_X, y = DEFAULT_POS_Y }
                    _G.ULODB.hudLayoutV2 = true
                end
                StatusHUD.SetPosition(StatusHUD.GetPosition())
                if (type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.ui) == "table" and _G.ULO_CONFIG.ui.showStatusHUD == false)
                   or _G.ULODB.showStatusHUD == false then
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
