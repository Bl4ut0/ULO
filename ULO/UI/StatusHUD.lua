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
ULO.UI.ActionsHUD = ULO.UI.ActionsHUD or {}
local StatusHUD = ULO.UI.StatusHUD
local ActionsHUD = ULO.UI.ActionsHUD

local Detection = ULO.Detection
local Monitor = ULO.Monitor
local Coordination = ULO.Coordination
local Compat = ULO.Compat
local C = ULO.Constants

-- Constants (width strictly <= 300 per HUD layout tests)
local HUD_WIDTH = 296
local HUD_HEIGHT = 264
local ACTIONS_WIDTH = 340
local ACTIONS_HEIGHT = 264
local ACTIONS_MAX_LOGS = 50
local ACTIONS_VISIBLE_LINES = 10
local DEFAULT_POS_X = 380
local DEFAULT_POS_Y = 360

-- Category Color Mapping Table for Action Telemetry
local ACTION_COLORS = {
    Hop                = "|cff00e5ff",
    AutoLayer          = "|cff66ccff",
    ["ULO Chan"]       = "|cff33ff99",
    OverlordLJ         = "|cffffb84d",
    Overlord           = "|cffffb84d",
    ["Direct Whisper"] = "|cffff88ff",
    Invite             = "|cff88ff88",
    Group              = "|cff44ff66",
    Scan               = "|cffeedd66",
    Monitor            = "|cffffaa44",
    Channel            = "|cff99bbff",
    Mode               = "|cff00ffff",
    Blocked            = "|cffff6666",
    Core               = "|cffcccccc",
}

-- Runtime State
local isMinimized = false
local lastActionText = "Drag header to move | Click [Actions] for feed"
ULO.actionLog = ULO.actionLog or {}

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
local actionsButton = nil
local optionsButton = nil
local closeButton = nil
local layerHopButtons = {}
local hudBgTex = nil
local hudHeaderBgTex = nil
local hudHeaderLineTex = nil
local hudTitleFS = nil

-- Actions HUD Elements
local actionsFrame = nil
local actionsModeButton = nil
local actionsThemeButton = nil
local telemetryStateFS = nil
local telemetryNetFS = nil
local telemetryPeersFS = nil
local actionsBgTex = nil
local actionsHeaderBgTex = nil
local actionsHeaderLineTex = nil
local actionsTeleBgTex = nil
local actionsTitleFS = nil
local logLineFS = {}
local themedButtons = {}

-- Color Themes (Alliance Blue, Horde Red, Obsidian Black, Neutral Grey)
local THEMES = {
    blue = {
        label  = "Blue",
        title  = "|cff33b5ffULO|r",
        bg     = { 0.05, 0.08, 0.16, 0.94 },
        hdr    = { 0.08, 0.15, 0.30, 0.98 },
        line   = { 0.10, 0.65, 1.00, 0.85 },
        teleBg = { 0.07, 0.11, 0.21, 0.80 },
        btnBg  = { 0.10, 0.18, 0.32, 0.95 },
        btnHl  = { 0.15, 0.72, 1.00, 0.25 },
        border = { 0.25, 0.62, 0.95, 0.92 },
        btnBdr = { 0.28, 0.56, 0.88, 0.90 },
    },
    red = {
        label  = "Red",
        title  = "|cffff4433ULO|r",
        bg     = { 0.14, 0.04, 0.05, 0.94 },
        hdr    = { 0.28, 0.06, 0.07, 0.98 },
        line   = { 0.95, 0.22, 0.18, 0.88 },
        teleBg = { 0.20, 0.06, 0.07, 0.80 },
        btnBg  = { 0.30, 0.08, 0.09, 0.95 },
        btnHl  = { 1.00, 0.28, 0.22, 0.25 },
        border = { 0.88, 0.25, 0.20, 0.92 },
        btnBdr = { 0.78, 0.24, 0.18, 0.90 },
    },
    black = {
        label  = "Black",
        title  = "|cffd4af37ULO|r",
        bg     = { 0.02, 0.02, 0.03, 0.96 },
        hdr    = { 0.06, 0.06, 0.08, 0.98 },
        line   = { 0.75, 0.60, 0.24, 0.85 },
        teleBg = { 0.05, 0.05, 0.07, 0.82 },
        btnBg  = { 0.09, 0.09, 0.12, 0.95 },
        btnHl  = { 0.85, 0.70, 0.30, 0.22 },
        border = { 0.42, 0.38, 0.28, 0.92 },
        btnBdr = { 0.38, 0.34, 0.25, 0.90 },
    },
    grey = {
        label  = "Grey",
        title  = "|cffd8dde6ULO|r",
        bg     = { 0.14, 0.15, 0.17, 0.94 },
        hdr    = { 0.22, 0.24, 0.27, 0.98 },
        line   = { 0.68, 0.72, 0.78, 0.85 },
        teleBg = { 0.18, 0.19, 0.22, 0.80 },
        btnBg  = { 0.24, 0.26, 0.30, 0.95 },
        btnHl  = { 0.82, 0.85, 0.90, 0.24 },
        border = { 0.56, 0.59, 0.64, 0.92 },
        btnBdr = { 0.48, 0.51, 0.56, 0.90 },
    },
}
local THEME_ORDER = { "blue", "red", "black", "grey" }
local THEME_ALIASES = {
    alliance = "blue",
    horde    = "red",
    gray     = "grey",
    neutral  = "grey",
    obsidian = "black",
    dark     = "black",
}

local function RegisterSpecialFrame(frameName)
    if type(frameName) ~= "string" or frameName == "" then return end
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    for _, existing in ipairs(_G.UISpecialFrames) do
        if existing == frameName then return end
    end
    table.insert(_G.UISpecialFrames, frameName)
end

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

local function ApplyBorderColor(frame, rgba)
    if not frame or type(frame._borderTextures) ~= "table" or type(rgba) ~= "table" then return end
    for _, tex in ipairs(frame._borderTextures) do
        SetSolidColor(tex, rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    end
end

local function AddBorder(frame, r, g, b, a, thickness)
    if not frame or type(frame.CreateTexture) ~= "function" then return end
    local t = thickness or 1
    frame._borderTextures = frame._borderTextures or {}

    local function MakeEdge()
        local tex = frame:CreateTexture(nil, "BORDER")
        if tex then
            SetSolidColor(tex, r, g, b, a)
            table.insert(frame._borderTextures, tex)
        end
        return tex
    end

    local top = MakeEdge()
    if top and type(top.SetPoint) == "function" and type(top.SetHeight) == "function" then
        top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        top:SetHeight(t)
    end

    local bottom = MakeEdge()
    if bottom and type(bottom.SetPoint) == "function" and type(bottom.SetHeight) == "function" then
        bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(t)
    end

    local left = MakeEdge()
    if left and type(left.SetPoint) == "function" and type(left.SetWidth) == "function" then
        left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        left:SetWidth(t)
    end

    local right = MakeEdge()
    if right and type(right.SetPoint) == "function" and type(right.SetWidth) == "function" then
        right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(t)
    end
end

local function SetActionFeedback(msg)
    lastActionText = tostring(msg or "")
    if actionStatusFS and type(actionStatusFS.SetText) == "function" then
        actionStatusFS:SetText(lastActionText)
    end
end

--- Returns the rolling action telemetry log array.
-- @return table
function ULO.GetActionLog()
    ULO.actionLog = ULO.actionLog or {}
    return ULO.actionLog
end

--- Appends a timestamped telemetry entry to the Actions HUD without polluting chat.
-- @param category string: Originating system or action category
-- @param msg string: Event description
function ULO.LogAction(category, msg)
    local cat = tostring(category or "Core")
    local text = tostring(msg or "")
    local ts = "00:00:00"
    if type(_G.date) == "function" then
        local ok, d = pcall(_G.date, "%H:%M:%S")
        if ok and d then
            ts = d
        end
    elseif type(_G.GetTime) == "function" then
        ts = string.format("%.0fs", _G.GetTime() or 0)
    end

    local color = ACTION_COLORS[cat] or "|cffcccccc"
    local formatted = string.format("|cff888888[%s]|r %s[%s]|r %s", ts, color, cat, text)

    ULO.actionLog = ULO.actionLog or {}
    table.insert(ULO.actionLog, {
        time = ts,
        category = cat,
        text = text,
        line = formatted,
    })
    while #ULO.actionLog > ACTIONS_MAX_LOGS do
        table.remove(ULO.actionLog, 1)
    end

    SetActionFeedback(string.format("[%s] %s", cat, text))
    if ULO.UI and ULO.UI.ActionsHUD and type(ULO.UI.ActionsHUD.Update) == "function" then
        ULO.UI.ActionsHUD.Update()
    end
end

--- Returns whether ULO-Only Invite Mode is enabled (blocks external addon invites).
-- @return boolean
function ULO.IsULOOnlyMode()
    return (type(_G.ULODB) == "table" and _G.ULODB.uloOnlyMode == true)
end

--- Enables or disables ULO-Only Invite Mode (disables AutoLayer & Overlord addon invites).
-- @param enabled boolean
function ULO.SetULOOnlyMode(enabled)
    local flag = (enabled == true)
    _G.ULODB = _G.ULODB or {}
    _G.ULODB.uloOnlyMode = flag
    _G.ULODB.autoLayerEnabled = not flag
    _G.ULODB.overlordEnabled = not flag

    _G.ULO_CONFIG = _G.ULO_CONFIG or {}
    _G.ULO_CONFIG.interop = _G.ULO_CONFIG.interop or {}
    _G.ULO_CONFIG.interop.autoLayerEnabled = not flag
    _G.ULO_CONFIG.interop.autolayerEnabled = not flag
    _G.ULO_CONFIG.interop.overlordEnabled = not flag

    if ULO.config then
        ULO.config.interop = ULO.config.interop or {}
        ULO.config.interop.autoLayerEnabled = not flag
        ULO.config.interop.autolayerEnabled = not flag
        ULO.config.interop.overlordEnabled = not flag
    end

    if ULO.Interop and ULO.Interop.Overlord and type(ULO.Interop.Overlord.SyncHelpMode) == "function" then
        ULO.Interop.Overlord.SyncHelpMode()
    elseif flag and _G.Overlord and _G.Overlord.LayerJumper and type(_G.Overlord.LayerJumper.SetHelpMode) == "function" then
        pcall(_G.Overlord.LayerJumper.SetHelpMode, _G.Overlord.LayerJumper, "off")
    end
    if ULO.Coordination and type(ULO.Coordination.SyncLeatrixPlusGuard) == "function" then
        ULO.Coordination.SyncLeatrixPlusGuard()
    end

    ULO.LogAction("Mode", flag
        and "ULO ONLY mode ON (ignoring AutoLayer & Overlord invites)"
        or "ALL ADDONS mode ON (AutoLayer & Overlord enabled)")

    if ULO.TriggerCallback then
        ULO.TriggerCallback("OnConfigChanged", "uloOnlyMode", flag)
    end
    StatusHUD.Update()
    if ULO.UI and ULO.UI.ActionsHUD and type(ULO.UI.ActionsHUD.Update) == "function" then
        ULO.UI.ActionsHUD.Update()
    end
    if ULO.UI and ULO.UI.SettingsPanel and type(ULO.UI.SettingsPanel.RefreshControls) == "function" then
        ULO.UI.SettingsPanel.RefreshControls()
    end
end

--- Normalizes and returns the active UI color theme key ("blue", "red", "black", "grey").
-- @return string
function ULO.GetTheme()
    local raw = (_G.ULODB and _G.ULODB.theme)
                or (_G.ULO_CONFIG and _G.ULO_CONFIG.ui and _G.ULO_CONFIG.ui.theme)
                or (ULO.config and ULO.config.ui and ULO.config.ui.theme)
                or "blue"
    local key = string.lower(tostring(raw))
    key = THEME_ALIASES[key] or key
    if not THEMES[key] then
        key = "blue"
    end
    return key
end

--- Applies the current theme palette to all ULO HUD frames, borders, headers, and buttons.
function StatusHUD.ApplyTheme()
    local key = ULO.GetTheme()
    local t = THEMES[key]
    if not t then return end

    local function SetTex(tex, rgba)
        if tex and type(rgba) == "table" then
            SetSolidColor(tex, rgba[1], rgba[2], rgba[3], rgba[4] or 1)
        end
    end

    SetTex(hudBgTex, t.bg)
    SetTex(hudHeaderBgTex, t.hdr)
    SetTex(hudHeaderLineTex, t.line)
    ApplyBorderColor(hudFrame, t.border)
    if hudTitleFS and type(hudTitleFS.SetText) == "function" then
        hudTitleFS:SetText(t.title .. " Layer Op")
    end

    SetTex(actionsBgTex, t.bg)
    SetTex(actionsHeaderBgTex, t.hdr)
    SetTex(actionsHeaderLineTex, t.line)
    SetTex(actionsTeleBgTex, t.teleBg)
    ApplyBorderColor(actionsFrame, t.border)
    if actionsTitleFS and type(actionsTitleFS.SetText) == "function" then
        actionsTitleFS:SetText(t.title .. " Actions")
    end

    for _, btn in ipairs(themedButtons) do
        SetTex(btn._bgTex, t.btnBg)
        SetTex(btn._hlTex, t.btnHl)
        ApplyBorderColor(btn, t.btnBdr)
    end

    if actionsThemeButton and actionsThemeButton.textFS and type(actionsThemeButton.textFS.SetText) == "function" then
        actionsThemeButton.textFS:SetText(t.label)
    end

    local diagBox = _G.ULODiagnosticsBox
    if diagBox and diagBox._bgTex then
        SetTex(diagBox._bgTex, t.teleBg)
    end
end

--- Sets and persists the UI color theme ("blue" / "alliance", "red" / "horde", "black", "grey").
-- @param themeName string
-- @return boolean, string|nil
function ULO.SetTheme(themeName)
    if type(themeName) ~= "string" then return false, nil end
    local key = string.lower(string.match(themeName, "^%s*(.-)%s*$") or "")
    key = THEME_ALIASES[key] or key
    if not THEMES[key] then
        return false, nil
    end

    _G.ULODB = _G.ULODB or {}
    _G.ULODB.theme = key
    _G.ULO_CONFIG = _G.ULO_CONFIG or {}
    _G.ULO_CONFIG.ui = _G.ULO_CONFIG.ui or {}
    _G.ULO_CONFIG.ui.theme = key
    if ULO.config then
        ULO.config.ui = ULO.config.ui or {}
        ULO.config.ui.theme = key
    end

    StatusHUD.ApplyTheme()
    ULO.LogAction("Core", "Theme set to " .. THEMES[key].label)

    if ULO.TriggerCallback then
        ULO.TriggerCallback("OnConfigChanged", "theme", key)
    end
    if ULO.UI and ULO.UI.SettingsPanel and type(ULO.UI.SettingsPanel.RefreshControls) == "function" then
        ULO.UI.SettingsPanel.RefreshControls()
    end
    return true, key
end

--- Cycles through the available UI color themes (Blue -> Red -> Black -> Grey).
-- @return string: Newly activated theme key
function ULO.CycleTheme()
    local cur = ULO.GetTheme()
    local nextIdx = 1
    for i, k in ipairs(THEME_ORDER) do
        if k == cur then
            nextIdx = (i % #THEME_ORDER) + 1
            break
        end
    end
    local _, applied = ULO.SetTheme(THEME_ORDER[nextIdx])
    return applied or THEME_ORDER[nextIdx]
end

local function CreateStyledButton(globalName, parent, width, height, labelText, onClick, fontObj)
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
            SetSolidColor(bg, 0.10, 0.18, 0.32, 0.95)
            btn._bgTex = bg
        end
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        if hl then
            if type(hl.SetAllPoints) == "function" then
                hl:SetAllPoints(btn)
            end
            SetSolidColor(hl, 0.15, 0.72, 1.00, 0.25)
            btn._hlTex = hl
        end
    end
    AddBorder(btn, 0.28, 0.56, 0.88, 0.90, 1)
    table.insert(themedButtons, btn)

    if type(btn.CreateFontString) == "function" then
        local fs = btn:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
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
    local ok, reason = true, nil
    if ULO.Coordination and type(ULO.Coordination.RequestLayerHop) == "function" then
        ok, reason = ULO.Coordination.RequestLayerHop(targetLayer)
    end

    if ok == false and reason == "cooldown" then
        local msg = "Hop blocked: cooldown active (" .. StatusHUD.GetCooldownText() .. ")"
        SetActionFeedback(msg)
        PrintToChat(msg)
    elseif targetLayer then
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
    RegisterSpecialFrame("ULOStatusHUD")
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

    -- Solid Obsidian backdrop + theme borders so frame is always visible regardless of asset indexing
    if type(hudFrame.CreateTexture) == "function" then
        local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
        if bg then
            if type(bg.SetAllPoints) == "function" then
                bg:SetAllPoints(hudFrame)
            end
            SetSolidColor(bg, 0.05, 0.08, 0.16, 0.94)
            hudBgTex = bg
        end

        local headerBg = hudFrame:CreateTexture(nil, "ARTWORK")
        if headerBg then
            SetSolidColor(headerBg, 0.08, 0.15, 0.30, 0.98)
            if type(headerBg.SetPoint) == "function" and type(headerBg.SetHeight) == "function" then
                headerBg:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 1, -1)
                headerBg:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -1, -1)
                headerBg:SetHeight(26)
            end
            hudHeaderBgTex = headerBg
        end

        local headerLine = hudFrame:CreateTexture(nil, "OVERLAY")
        if headerLine then
            SetSolidColor(headerLine, 0.10, 0.65, 1.00, 0.85)
            if type(headerLine.SetPoint) == "function" and type(headerLine.SetHeight) == "function" then
                headerLine:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 1, -27)
                headerLine:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -1, -27)
                headerLine:SetHeight(1)
            end
            hudHeaderLineTex = headerLine
        end
    end
    AddBorder(hudFrame, 0.25, 0.62, 0.95, 0.92, 1)

    -- Header, Status, Countdown, Cooldown, and Feedback FontStrings
    if type(hudFrame.CreateFontString) == "function" then
        local titleFS = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if titleFS and type(titleFS.SetPoint) == "function" then
            titleFS:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 10, -7)
            if type(titleFS.SetText) == "function" then
                titleFS:SetText("|cff33b5ffULO|r Layer Op")
            end
        end
        hudTitleFS = titleFS

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
    end, "GameFontNormalSmall")
    if closeButton and type(closeButton.SetPoint) == "function" then
        closeButton:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -4, -4)
    end

    optionsButton = CreateStyledButton("ULOStatusHUDOptionsButton", hudFrame, 54, 18, "Options", function()
        if ULO.UI and ULO.UI.SettingsPanel and ULO.UI.SettingsPanel.Open then
            ULO.UI.SettingsPanel.Open()
        end
    end, "GameFontNormalSmall")
    if optionsButton and type(optionsButton.SetPoint) == "function" then
        optionsButton:SetPoint("RIGHT", closeButton or hudFrame, "LEFT", -3, 0)
    end

    actionsButton = CreateStyledButton("ULOStatusHUDActionsButton", hudFrame, 56, 18, "Actions", function()
        if ULO.UI and ULO.UI.ActionsHUD and type(ULO.UI.ActionsHUD.Toggle) == "function" then
            ULO.UI.ActionsHUD.Toggle()
        end
    end, "GameFontNormalSmall")
    if actionsButton and type(actionsButton.SetPoint) == "function" then
        actionsButton:SetPoint("RIGHT", optionsButton or hudFrame, "LEFT", -3, 0)
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
            ULO.LogAction("Monitor", "Requested layer refresh / reload")
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
        local serverId = ULO.Detection and ULO.Detection.GetCurrentServerId and ULO.Detection.GetCurrentServerId()
        local conf = (ULO.Detection and ULO.Detection.GetLayerConfidence and ULO.Detection.GetLayerConfidence()) or "UNDETERMINED"
        if layer then
            ULO.LogAction("Scan", string.format("Layer %s (Server %s, %s)", tostring(layer), tostring(serverId or "?"), tostring(conf)))
        else
            ULO.LogAction("Scan", "No NPC GUID found nearby (target an NPC)")
        end
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
        ULO.LogAction("Invite", "Auto-Invite " .. (enabled and "Enabled" or "Disabled"))
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
    if actionsFrame and type(actionsFrame.IsShown) == "function" and actionsFrame:IsShown() then
        ActionsHUD.Update()
    end
end

--------------------------------------------------------------------------------
-- Live Actions & Telemetry HUD (ULOActionsHUD)
--------------------------------------------------------------------------------

local function DockActionsToHUD()
    if not actionsFrame or type(actionsFrame.ClearAllPoints) ~= "function" or type(actionsFrame.SetPoint) ~= "function" then
        return
    end
    local saved = _G.ULODB and _G.ULODB.actionsPosition
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
        actionsFrame:ClearAllPoints()
        actionsFrame:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", saved.x, saved.y)
        return
    end
    if not hudFrame then return end

    local dockLeft = false
    if type(hudFrame.GetRight) == "function" and _G.UIParent and type(_G.UIParent.GetWidth) == "function" then
        local okR, right = pcall(hudFrame.GetRight, hudFrame)
        local okW, pw = pcall(_G.UIParent.GetWidth, _G.UIParent)
        if okR and okW and type(right) == "number" and type(pw) == "number"
           and pw > (HUD_WIDTH + ACTIONS_WIDTH) and (right + ACTIONS_WIDTH + 8) > pw then
            dockLeft = true
        end
    end

    actionsFrame:ClearAllPoints()
    if dockLeft then
        actionsFrame:SetPoint("TOPRIGHT", hudFrame, "TOPLEFT", -8, 0)
    else
        actionsFrame:SetPoint("TOPLEFT", hudFrame, "TOPRIGHT", 8, 0)
    end
end

actionsFrame = _G.ULOActionsHUD
if not actionsFrame and type(_G.CreateFrame) == "function" then
    actionsFrame = _G.CreateFrame("Frame", "ULOActionsHUD", _G.UIParent)
end

if actionsFrame then
    RegisterSpecialFrame("ULOActionsHUD")
    actionsFrame:SetSize(ACTIONS_WIDTH, ACTIONS_HEIGHT)
    if type(actionsFrame.SetFrameStrata) == "function" then
        actionsFrame:SetFrameStrata("DIALOG")
    end
    if type(actionsFrame.SetClampedToScreen) == "function" then
        actionsFrame:SetClampedToScreen(true)
    end
    if type(actionsFrame.SetClampRectInsets) == "function" then
        actionsFrame:SetClampRectInsets(0, 0, 0, 0)
    end
    if type(actionsFrame.SetMovable) == "function" then
        actionsFrame:SetMovable(true)
    end
    if type(actionsFrame.EnableMouse) == "function" then
        actionsFrame:EnableMouse(true)
    end
    if type(actionsFrame.RegisterForDrag) == "function" then
        actionsFrame:RegisterForDrag("LeftButton")
    end

    if type(actionsFrame.CreateTexture) == "function" then
        local abg = actionsFrame:CreateTexture(nil, "BACKGROUND")
        if abg then
            if type(abg.SetAllPoints) == "function" then abg:SetAllPoints(actionsFrame) end
            SetSolidColor(abg, 0.05, 0.08, 0.16, 0.94)
            actionsBgTex = abg
        end

        local ahdr = actionsFrame:CreateTexture(nil, "ARTWORK")
        if ahdr then
            SetSolidColor(ahdr, 0.08, 0.15, 0.30, 0.98)
            if type(ahdr.SetPoint) == "function" and type(ahdr.SetHeight) == "function" then
                ahdr:SetPoint("TOPLEFT", actionsFrame, "TOPLEFT", 1, -1)
                ahdr:SetPoint("TOPRIGHT", actionsFrame, "TOPRIGHT", -1, -1)
                ahdr:SetHeight(26)
            end
            actionsHeaderBgTex = ahdr
        end

        local aline = actionsFrame:CreateTexture(nil, "OVERLAY")
        if aline then
            SetSolidColor(aline, 0.10, 0.65, 1.00, 0.85)
            if type(aline.SetPoint) == "function" and type(aline.SetHeight) == "function" then
                aline:SetPoint("TOPLEFT", actionsFrame, "TOPLEFT", 1, -27)
                aline:SetPoint("TOPRIGHT", actionsFrame, "TOPRIGHT", -1, -27)
                aline:SetHeight(1)
            end
            actionsHeaderLineTex = aline
        end

        local teleBg = actionsFrame:CreateTexture(nil, "ARTWORK")
        if teleBg then
            SetSolidColor(teleBg, 0.07, 0.11, 0.21, 0.80)
            if type(teleBg.SetPoint) == "function" and type(teleBg.SetSize) == "function" then
                teleBg:SetPoint("TOPLEFT", actionsFrame, "TOPLEFT", 10, -30)
                teleBg:SetSize(320, 52)
            end
            actionsTeleBgTex = teleBg
        end
    end
    AddBorder(actionsFrame, 0.25, 0.62, 0.95, 0.92, 1)

    if type(actionsFrame.CreateFontString) == "function" then
        local aTitle = actionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if aTitle and type(aTitle.SetPoint) == "function" then
            aTitle:SetPoint("TOPLEFT", actionsFrame, "TOPLEFT", 10, -7)
            if type(aTitle.SetText) == "function" then
                aTitle:SetText("|cff33b5ffULO|r Actions")
            end
        end
        actionsTitleFS = aTitle

        local function CreateTelemetryFS(yOfs, initText)
            local fs = actionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if fs then
                if type(fs.SetPoint) == "function" then fs:SetPoint("TOPLEFT", actionsFrame, "TOPLEFT", 14, yOfs) end
                if type(fs.SetWidth) == "function" then fs:SetWidth(312) end
                if type(fs.SetJustifyH) == "function" then fs:SetJustifyH("LEFT") end
                if type(fs.SetWordWrap) == "function" then fs:SetWordWrap(false) end
                if type(fs.SetText) == "function" then fs:SetText(initText) end
            end
            return fs
        end

        telemetryStateFS = CreateTelemetryFS(-34, "State: IDLE")
        telemetryNetFS   = CreateTelemetryFS(-49, "Mode: ALL ADDONS | Chan: -")
        telemetryPeersFS = CreateTelemetryFS(-64, "Overlord: 0 shard (0 help, 0 dir) | Pend: 0")

        for i = 1, ACTIONS_VISIBLE_LINES do
            local fs = actionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if fs then
                if type(fs.SetPoint) == "function" then
                    fs:SetPoint("TOPLEFT", actionsFrame, "TOPLEFT", 12, -88 - ((i - 1) * 16))
                end
                if type(fs.SetWidth) == "function" then fs:SetWidth(316) end
                if type(fs.SetJustifyH) == "function" then fs:SetJustifyH("LEFT") end
                if type(fs.SetWordWrap) == "function" then fs:SetWordWrap(false) end
                if type(fs.SetText) == "function" then fs:SetText("") end
            end
            logLineFS[i] = fs
        end
    end

    local aCloseBtn = CreateStyledButton("ULOActionsHUDCloseButton", actionsFrame, 18, 18, "X", function()
        _G.ULODB = _G.ULODB or {}
        _G.ULODB.showActionsHUD = false
        ActionsHUD.Hide()
    end, "GameFontNormalSmall")
    if aCloseBtn and type(aCloseBtn.SetPoint) == "function" then
        aCloseBtn:SetPoint("TOPRIGHT", actionsFrame, "TOPRIGHT", -4, -4)
    end

    local aClearBtn = CreateStyledButton("ULOActionsHUDClearButton", actionsFrame, 38, 18, "Clear", function()
        ActionsHUD.Clear()
    end, "GameFontNormalSmall")
    if aClearBtn and type(aClearBtn.SetPoint) == "function" then
        aClearBtn:SetPoint("RIGHT", aCloseBtn or actionsFrame, "LEFT", -3, 0)
    end

    actionsModeButton = CreateStyledButton("ULOActionsHUDModeButton", actionsFrame, 68, 18, "Mode: All", function()
        ULO.SetULOOnlyMode(not ULO.IsULOOnlyMode())
    end, "GameFontNormalSmall")
    if actionsModeButton and type(actionsModeButton.SetPoint) == "function" then
        actionsModeButton:SetPoint("RIGHT", aClearBtn or actionsFrame, "LEFT", -3, 0)
    end

    actionsThemeButton = CreateStyledButton("ULOActionsHUDThemeButton", actionsFrame, 48, 18, "Blue", function()
        ULO.CycleTheme()
    end, "GameFontNormalSmall")
    if actionsThemeButton and type(actionsThemeButton.SetPoint) == "function" then
        actionsThemeButton:SetPoint("RIGHT", actionsModeButton or actionsFrame, "LEFT", -3, 0)
    end

    actionsFrame:SetScript("OnDragStart", function(self)
        if type(self.StartMoving) == "function" then
            self:StartMoving()
        end
    end)

    actionsFrame:SetScript("OnDragStop", function(self)
        if type(self.StopMovingOrSizing) == "function" then
            self:StopMovingOrSizing()
        end
        if type(self.GetLeft) == "function" and type(self.GetBottom) == "function" then
            local okL, left = pcall(self.GetLeft, self)
            local okB, bottom = pcall(self.GetBottom, self)
            if okL and okB and type(left) == "number" and type(bottom) == "number" then
                _G.ULODB = _G.ULODB or {}
                _G.ULODB.actionsPosition = { x = math.floor(left + 0.5), y = math.floor(bottom + 0.5) }
            end
        end
    end)

    local tickAcc = 0
    actionsFrame:SetScript("OnUpdate", function(_, elapsed)
        tickAcc = tickAcc + (tonumber(elapsed) or 0)
        if tickAcc >= 1.0 then
            tickAcc = 0
            ActionsHUD.Update()
        end
    end)

    DockActionsToHUD()
end

--- Returns the Actions HUD frame.
-- @return table
function ActionsHUD.GetFrame()
    return actionsFrame
end

--- Clears the rolling action log and refreshes the display.
function ActionsHUD.Clear()
    ULO.actionLog = {}
    ActionsHUD.Update()
end

--- Shows the Actions HUD and updates telemetry.
function ActionsHUD.Show()
    if actionsFrame and type(actionsFrame.Show) == "function" then
        DockActionsToHUD()
        actionsFrame:Show()
        ActionsHUD.Update()
    end
end

--- Hides the Actions HUD.
function ActionsHUD.Hide()
    if actionsFrame and type(actionsFrame.Hide) == "function" then
        actionsFrame:Hide()
    end
end

--- Toggles Actions HUD visibility and persists preference.
function ActionsHUD.Toggle()
    if not actionsFrame then return end
    _G.ULODB = _G.ULODB or {}
    if type(actionsFrame.IsShown) == "function" and actionsFrame:IsShown() then
        _G.ULODB.showActionsHUD = false
        ActionsHUD.Hide()
    else
        _G.ULODB.showActionsHUD = true
        ActionsHUD.Show()
    end
end

--- Updates live telemetry header lines and rolling 10-line action log.
function ActionsHUD.Update()
    if not actionsFrame then return end

    local cdRem = (ULO.Monitor and type(ULO.Monitor.GetCooldownRemaining) == "function" and ULO.Monitor.GetCooldownRemaining()) or 0
    local isVerifying = ULO.Coordination and type(ULO.Coordination.IsAwaitingLayerVerification) == "function" and ULO.Coordination.IsAwaitingLayerVerification()
    local isAwaiting = ULO.Coordination and type(ULO.Coordination.IsAwaitingHop) == "function" and ULO.Coordination.IsAwaitingHop()
    local targetL = ULO.Coordination and type(ULO.Coordination.GetActiveHopTarget) == "function" and ULO.Coordination.GetActiveHopTarget()

    local stateStr = "|cff44ff66IDLE|r"
    if cdRem > 0 then
        stateStr = string.format("|cffff6644COOLDOWN (%s)|r", StatusHUD.GetCooldownText())
    elseif isVerifying then
        stateStr = "|cffffd100VERIFYING LAYER TRANSFER|r"
    elseif isAwaiting then
        stateStr = string.format("|cff00e5ffAWAITING INVITE (%s)|r", targetL and ("L" .. tostring(targetL)) or "Any")
    end

    if telemetryStateFS and type(telemetryStateFS.SetText) == "function" then
        telemetryStateFS:SetText("State: " .. stateStr)
    end

    local uloOnly = ULO.IsULOOnlyMode()
    local alOn = not (_G.ULODB and _G.ULODB.autoLayerEnabled == false)
    local ovOn = not (_G.ULODB and _G.ULODB.overlordEnabled == false)
    if uloOnly then
        alOn, ovOn = false, false
    end

    local chStr = "None"
    if ULO.Interop and ULO.Interop.AutoLayer and type(ULO.Interop.AutoLayer.GetManagedChannels) == "function" then
        local chList = ULO.Interop.AutoLayer.GetManagedChannels()
        if type(chList) == "table" and #chList > 0 then
            local parts = {}
            for _, ch in ipairs(chList) do
                local slot = (type(_G.GetChannelName) == "function") and select(1, _G.GetChannelName(ch)) or nil
                if type(slot) == "number" and slot > 0 then
                    table.insert(parts, "/" .. tostring(slot))
                end
            end
            if #parts > 0 then
                chStr = table.concat(parts, ",")
            end
        end
    end

    local modeLabel = uloOnly and "|cff00ffffULO ONLY|r" or "|cff88ff88ALL ADDONS|r"
    if telemetryNetFS and type(telemetryNetFS.SetText) == "function" then
        telemetryNetFS:SetText(string.format("Mode: %s | AL:%s OV:%s | Chan:%s",
            modeLabel, alOn and "ON" or "OFF", ovOn and "ON" or "OFF", chStr))
    end

    if actionsModeButton and actionsModeButton.textFS and type(actionsModeButton.textFS.SetText) == "function" then
        actionsModeButton.textFS:SetText(uloOnly and "Mode: ULO" or "Mode: All")
    end

    local totalPeers, otherHelpers, dirPeers = 0, 0, 0
    if ULO.Interop and ULO.Interop.Overlord and type(ULO.Interop.Overlord.GetPeerSummary) == "function" then
        totalPeers, otherHelpers, dirPeers = ULO.Interop.Overlord.GetPeerSummary()
    end
    local pendingInv = (ULO.Coordination and type(ULO.Coordination.GetPendingInviteCount) == "function" and ULO.Coordination.GetPendingInviteCount()) or 0

    if telemetryPeersFS and type(telemetryPeersFS.SetText) == "function" then
        telemetryPeersFS:SetText(string.format("Overlord: %d shard (%d help, %d dir) | Pend: %d",
            totalPeers, otherHelpers, dirPeers, pendingInv))
    end

    local log = ULO.GetActionLog()
    local total = #log
    if total == 0 then
        if logLineFS[1] and type(logLineFS[1].SetText) == "function" then
            logLineFS[1]:SetText("|cff888888Waiting for scans, hops, or invites...|r")
        end
        for i = 2, ACTIONS_VISIBLE_LINES do
            if logLineFS[i] and type(logLineFS[i].SetText) == "function" then
                logLineFS[i]:SetText("")
            end
        end
    else
        local startIdx = math.max(1, total - ACTIONS_VISIBLE_LINES + 1)
        for i = 1, ACTIONS_VISIBLE_LINES do
            local entry = log[startIdx + i - 1]
            if logLineFS[i] and type(logLineFS[i].SetText) == "function" then
                logLineFS[i]:SetText(entry and entry.line or "")
            end
        end
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
                DockActionsToHUD()
                StatusHUD.ApplyTheme()
                if ULO.Interop and ULO.Interop.Overlord and type(ULO.Interop.Overlord.SyncHelpMode) == "function" then
                    ULO.Interop.Overlord.SyncHelpMode()
                elseif ULO.IsULOOnlyMode() and _G.Overlord and _G.Overlord.LayerJumper and type(_G.Overlord.LayerJumper.SetHelpMode) == "function" then
                    pcall(_G.Overlord.LayerJumper.SetHelpMode, _G.Overlord.LayerJumper, "off")
                end
                if ULO.Coordination and type(ULO.Coordination.SyncLeatrixPlusGuard) == "function" then
                    ULO.Coordination.SyncLeatrixPlusGuard()
                end
                if #ULO.GetActionLog() == 0 then
                    ULO.LogAction("Core", "Ready: click L1-L8, Hop Any, or Scan NPCs")
                end
                if (type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.ui) == "table" and _G.ULO_CONFIG.ui.showStatusHUD == false)
                   or _G.ULODB.showStatusHUD == false then
                    StatusHUD.Hide()
                    ActionsHUD.Hide()
                else
                    StatusHUD.Update()
                    if _G.ULODB.showActionsHUD == false then
                        ActionsHUD.Hide()
                    else
                        ActionsHUD.Show()
                    end
                end
            end
        end)
    end
end

-- Apply initial anchor and theme
StatusHUD.SetPosition(StatusHUD.GetPosition())
StatusHUD.ApplyTheme()

-- Subscribe to ULO Callbacks for automatic HUD & Action Log refreshing
if ULO.RegisterCallback then
    ULO.RegisterCallback("OnLayerChanged", function(newLayer, serverId)
        ULO.LogAction("Scan", string.format("Layer updated -> L%s (Server %s)", tostring(newLayer or "?"), tostring(serverId or "?")))
        StatusHUD.Update()
    end)
    ULO.RegisterCallback("OnHopTimedOut", function(reason)
        ULO.LogAction("Hop", "Hop timed out (" .. tostring(reason or "timeout") .. ")")
        StatusHUD.Update()
    end)
    ULO.RegisterCallback("OnRefreshWarning", function(rem)
        ULO.LogAction("Monitor", string.format("Refresh warning (%ds remaining)", tonumber(rem) or 180))
        StatusHUD.Update()
    end)
    ULO.RegisterCallback("OnRefreshTriggered", function()
        ULO.LogAction("Monitor", "Layer refresh triggered")
        StatusHUD.Update()
    end)
    ULO.RegisterCallback("OnCooldownStarted", function(dur)
        ULO.LogAction("Monitor", string.format("Hop cooldown started (%ds)", tonumber(dur) or 300))
        StatusHUD.Update()
    end)
    ULO.RegisterCallback("OnCooldownExpired", function()
        ULO.LogAction("Monitor", "Hop cooldown expired (ready to hop)")
        StatusHUD.Update()
    end)
end

return StatusHUD
