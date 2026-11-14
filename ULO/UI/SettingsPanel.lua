-- ============================================================================
-- ULO: Universal Layer Operator
-- File: UI/SettingsPanel.lua
-- Description: Blizzard Settings configuration panel. Integrates modern Dragonflight+
--              Settings.RegisterAddOnCategory with Classic InterfaceOptions fallback.
--              Configures auto-invites, cooldown duration, sound muting, and interop.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.UI = ULO.UI or {}
ULO.UI.SettingsPanel = ULO.UI.SettingsPanel or {}
local SettingsPanel = ULO.UI.SettingsPanel

local Monitor = ULO.Monitor
local Coordination = ULO.Coordination
local Compat = ULO.Compat
local C = ULO.Constants

-- Constants
local MIN_COOLDOWN = 300
local MAX_COOLDOWN = 900
local DEFAULT_COOLDOWN = 300
local DEFAULT_TRIGGERS = "layer, inv, invite"
local DEFAULT_INVERTED = "not, off, except, but, out"
local DEFAULT_BLACKLIST = "wts, wtb, lfm, lfg, ashen, autoinv"

-- Frame & Category References
local panelFrame = nil
local categoryID = nil

--------------------------------------------------------------------------------
-- String & Table Utility Helpers
--------------------------------------------------------------------------------

local function TableToCSV(tbl, defaultStr)
    if type(tbl) == "string" then return tbl end
    if type(tbl) ~= "table" or #tbl == 0 then return defaultStr or "" end
    return table.concat(tbl, ", ")
end

local function CSVToTable(str)
    local list = {}
    if type(str) ~= "string" then return list end
    for token in string.gmatch(str, "([^,]+)") do
        local trimmed = string.match(token, "^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(list, string.lower(trimmed))
        end
    end
    return list
end

--------------------------------------------------------------------------------
-- Cooldown Accessor Methods
--------------------------------------------------------------------------------

--- Clamps and sets the layer hop post-transfer cooldown duration.
-- Strictly enforces minimum 300s and maximum 900s.
-- Synchronizes persistence to both ULODB and ULO_CONFIG, and calls Monitor.SetCooldownDuration.
-- @param val number: Target cooldown in seconds
-- @return number: Clamped cooldown value
function SettingsPanel.SetCooldown(val)
    if val == nil or type(val) ~= "number" or val ~= val or val == math.huge or val == -math.huge then
        val = DEFAULT_COOLDOWN
    end

    if val < MIN_COOLDOWN then
        val = MIN_COOLDOWN
    elseif val > MAX_COOLDOWN then
        val = MAX_COOLDOWN
    end

    _G.ULODB = _G.ULODB or {}
    _G.ULODB.cooldownDuration = val

    if _G.ULO_CONFIG and _G.ULO_CONFIG.cooldown then
        _G.ULO_CONFIG.cooldown.duration = val
    end
    if ULO.config and ULO.config.cooldown then
        ULO.config.cooldown.duration = val
    end

    if ULO.Monitor and type(ULO.Monitor.SetCooldownDuration) == "function" then
        ULO.Monitor.SetCooldownDuration(val)
    end

    return val
end

--- Returns current cooldown duration.
-- @return number: Cooldown duration in seconds
function SettingsPanel.GetCooldown()
    if ULO.Monitor and type(ULO.Monitor.GetCooldownDuration) == "function" then
        return ULO.Monitor.GetCooldownDuration()
    end
    _G.ULODB = _G.ULODB or {}
    return _G.ULODB.cooldownDuration or DEFAULT_COOLDOWN
end

--------------------------------------------------------------------------------
-- Widget Construction Helpers (Headless Test Resilient)
--------------------------------------------------------------------------------

local function CreateCheckbox(parent, name, labelText, tooltipText, initialValue, onToggle)
    local cb = _G.CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")

    -- Ensure CheckButton methods exist for headless mocks lacking XML templates
    if not cb.SetChecked then
        cb.SetChecked = function(self, val)
            self._checked = (val == true)
        end
    end
    if not cb.GetChecked then
        cb.GetChecked = function(self)
            return self._checked == true
        end
    end
    if not cb.GetText then
        cb.GetText = function(self)
            return self.labelText or ""
        end
    end

    -- FontString label: In live WoW, InterfaceOptionsCheckButtonTemplate provides _G[name .. "Text"]
    local fontString = _G[name .. "Text"]
    if not fontString and type(parent.CreateFontString) == "function" then
        fontString = parent:CreateFontString(name .. "Text", "ARTWORK", "GameFontHighlight")
        if fontString and type(fontString.SetPoint) == "function" then
            fontString:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        end
    end
    if fontString and type(fontString.SetText) == "function" then
        fontString:SetText(labelText)
    end
    cb.text = fontString
    cb.labelText = labelText
    cb.tooltipText = tooltipText

    -- Set initial state
    cb:SetChecked(initialValue == true)

    -- Scripts
    cb:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if type(onToggle) == "function" then
            onToggle(isChecked)
        end
    end)
    cb:SetScript("OnEnter", function(self)
        if _G.GameTooltip and type(_G.GameTooltip.SetOwner) == "function" and self.tooltipText then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(self.labelText or "", 1, 1, 1)
            _G.GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
            _G.GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function(self)
        if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
            _G.GameTooltip:Hide()
        end
    end)

    parent.__children = parent.__children or {}
    table.insert(parent.__children, cb)

    return cb
end

local function CreateCooldownSlider(parent, name, labelFormat, minVal, maxVal, step, initialVal, onValChanged)
    local slider = _G.CreateFrame("Slider", name, parent, "OptionsSliderTemplate")

    -- Ensure Slider methods exist for headless mocks
    if not slider.SetMinMaxValues then
        slider.SetMinMaxValues = function(self, mi, ma)
            self._min = mi
            self._max = ma
        end
    end
    if not slider.GetMinMaxValues then
        slider.GetMinMaxValues = function(self)
            return self._min or minVal, self._max or maxVal
        end
    end
    if not slider.SetValue then
        slider.SetValue = function(self, val)
            self._val = val
        end
    end
    if not slider.GetValue then
        slider.GetValue = function(self)
            return self._val or initialVal
        end
    end
    if not slider.SetValueStep then
        slider.SetValueStep = function(self, s)
            self._step = s
        end
    end
    if not slider.SetObeyStepOnDrag then
        slider.SetObeyStepOnDrag = function(self, obey)
            self._obey = obey
        end
    end

    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step or 10)
    if type(slider.SetObeyStepOnDrag) == "function" then
        slider:SetObeyStepOnDrag(true)
    end
    slider:SetValue(initialVal)

    -- Slider title, min, max font strings
    local textLabel = _G[name .. "Text"]
    if not textLabel and type(parent.CreateFontString) == "function" then
        textLabel = parent:CreateFontString(name .. "Text", "ARTWORK", "GameFontNormal")
        if textLabel and type(textLabel.SetPoint) == "function" then
            textLabel:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
        end
    end
    if textLabel and type(textLabel.SetText) == "function" then
        textLabel:SetText(string.format(labelFormat, initialVal))
    end
    slider.text = textLabel
    slider.labelFormat = labelFormat

    local lowLabel = _G[name .. "Low"]
    if not lowLabel and type(parent.CreateFontString) == "function" then
        lowLabel = parent:CreateFontString(name .. "Low", "ARTWORK", "GameFontHighlightSmall")
        if lowLabel and type(lowLabel.SetPoint) == "function" then
            lowLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -3)
        end
    end
    if lowLabel and type(lowLabel.SetText) == "function" then
        lowLabel:SetText(tostring(minVal) .. "s")
    end
    slider.low = lowLabel

    local highLabel = _G[name .. "High"]
    if not highLabel and type(parent.CreateFontString) == "function" then
        highLabel = parent:CreateFontString(name .. "High", "ARTWORK", "GameFontHighlightSmall")
        if highLabel and type(highLabel.SetPoint) == "function" then
            highLabel:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, -3)
        end
    end
    if highLabel and type(highLabel.SetText) == "function" then
        highLabel:SetText(tostring(maxVal) .. "s")
    end
    slider.high = highLabel

    slider:SetScript("OnValueChanged", function(self, value)
        if type(onValChanged) == "function" then
            local adjusted = onValChanged(value)
            if adjusted and textLabel and type(textLabel.SetText) == "function" then
                textLabel:SetText(string.format(labelFormat, adjusted))
            end
        end
    end)

    parent.__children = parent.__children or {}
    table.insert(parent.__children, slider)

    return slider
end

local function CreateEditBox(parent, name, labelText, initialText, onCommit)
    local label = nil
    if type(parent.CreateFontString) == "function" then
        label = parent:CreateFontString(name .. "Label", "ARTWORK", "GameFontNormalSmall")
        if label and type(label.SetText) == "function" then
            label:SetText(labelText)
        end
    end

    local eb = _G.CreateFrame("EditBox", name, parent, "InputBoxTemplate")

    -- Ensure EditBox methods exist for headless mocks
    if not eb.SetText then
        eb.SetText = function(self, txt)
            self._text = tostring(txt or "")
        end
    end
    if not eb.GetText then
        eb.GetText = function(self)
            return self._text or ""
        end
    end
    if not eb.SetAutoFocus then
        eb.SetAutoFocus = function(self, autoFocus)
            self._autoFocus = autoFocus
        end
    end
    if not eb.ClearFocus then
        eb.ClearFocus = function(self) end
    end

    eb:SetAutoFocus(false)
    eb:SetText(initialText or "")

    local function Commit()
        local txt = eb:GetText()
        if type(onCommit) == "function" then
            onCommit(txt)
        end
        if type(eb.ClearFocus) == "function" then
            eb:ClearFocus()
        end
    end

    eb:SetScript("OnEnterPressed", Commit)
    eb:SetScript("OnEditFocusLost", Commit)
    eb:SetScript("OnEscapePressed", function(self)
        if type(self.ClearFocus) == "function" then
            self:ClearFocus()
        end
    end)

    eb.label = label
    parent.__children = parent.__children or {}
    table.insert(parent.__children, eb)

    return eb
end

--------------------------------------------------------------------------------
-- Control Synchronization & Panel Refresh
--------------------------------------------------------------------------------

--- Refreshes all controls to display the current SavedVariables state.
function SettingsPanel.RefreshControls()
    if not SettingsPanel.controls then return end
    local c = SettingsPanel.controls

    local cfg = _G.ULO_CONFIG or (ULO and ULO.config) or {}
    local db = _G.ULODB or (ULO and ULO.db) or {}

    -- Checkboxes
    if c.checkboxes then
        if c.checkboxes.autoInvite and c.checkboxes.autoInvite.SetChecked then
            local val = true
            if db.autoInvite ~= nil then
                val = db.autoInvite
            elseif cfg.autoInvite and cfg.autoInvite.enabled ~= nil then
                val = cfg.autoInvite.enabled
            end
            c.checkboxes.autoInvite:SetChecked(val == true)
        end
        if c.checkboxes.muteSounds and c.checkboxes.muteSounds.SetChecked then
            local val = true
            if cfg.autoInvite and cfg.autoInvite.muteSounds ~= nil then
                val = cfg.autoInvite.muteSounds
            elseif cfg.autoInvite and cfg.autoInvite.muteInviteSounds ~= nil then
                val = cfg.autoInvite.muteInviteSounds
            elseif db.muteSounds ~= nil then
                val = db.muteSounds
            end
            c.checkboxes.muteSounds:SetChecked(val == true)
        end
        if c.checkboxes.whisperConfirm and c.checkboxes.whisperConfirm.SetChecked then
            local val = false
            if cfg.autoInvite and cfg.autoInvite.whisperConfirm ~= nil then
                val = cfg.autoInvite.whisperConfirm
            elseif db.whisperConfirm ~= nil then
                val = db.whisperConfirm
            end
            c.checkboxes.whisperConfirm:SetChecked(val == true)
        end
        if c.checkboxes.showMinimap and c.checkboxes.showMinimap.SetChecked then
            local val = true
            if cfg.ui and cfg.ui.showMinimapBadge ~= nil then
                val = cfg.ui.showMinimapBadge
            elseif db.showMinimapBadge ~= nil then
                val = db.showMinimapBadge
            end
            c.checkboxes.showMinimap:SetChecked(val == true)
        end
        if c.checkboxes.showHUD and c.checkboxes.showHUD.SetChecked then
            local val = true
            if cfg.ui and cfg.ui.showStatusHUD ~= nil then
                val = cfg.ui.showStatusHUD
            elseif db.showStatusHUD ~= nil then
                val = db.showStatusHUD
            end
            c.checkboxes.showHUD:SetChecked(val == true)
        end
        if c.checkboxes.autoLayer and c.checkboxes.autoLayer.SetChecked then
            local val = true
            if cfg.interop and cfg.interop.autoLayerEnabled ~= nil then
                val = cfg.interop.autoLayerEnabled
            elseif cfg.interop and cfg.interop.autolayerEnabled ~= nil then
                val = cfg.interop.autolayerEnabled
            elseif db.autoLayerEnabled ~= nil then
                val = db.autoLayerEnabled
            end
            c.checkboxes.autoLayer:SetChecked(val == true)
        end
        if c.checkboxes.overlord and c.checkboxes.overlord.SetChecked then
            local val = true
            if cfg.interop and cfg.interop.overlordEnabled ~= nil then
                val = cfg.interop.overlordEnabled
            elseif db.overlordEnabled ~= nil then
                val = db.overlordEnabled
            end
            c.checkboxes.overlord:SetChecked(val == true)
        end
        if c.checkboxes.nwbSync and c.checkboxes.nwbSync.SetChecked then
            local val = true
            if cfg.interop and cfg.interop.nwbSync ~= nil then
                val = cfg.interop.nwbSync
            elseif cfg.interop and cfg.interop.nwbEnabled ~= nil then
                val = cfg.interop.nwbEnabled
            elseif db.nwbSync ~= nil then
                val = db.nwbSync
            end
            c.checkboxes.nwbSync:SetChecked(val == true)
        end
    end

    -- Cooldown Slider
    if c.slider and c.slider.SetValue then
        local cd = SettingsPanel.GetCooldown()
        c.slider:SetValue(cd)
        if c.slider.text and type(c.slider.text.SetText) == "function" and c.slider.labelFormat then
            c.slider.text:SetText(string.format(c.slider.labelFormat, cd))
        end
    end

    -- EditBoxes
    if c.editboxes then
        if c.editboxes.triggers and c.editboxes.triggers.SetText then
            local triggers = (cfg.autoInvite and (cfg.autoInvite.triggers or cfg.autoInvite.keywords)) or
                             (db.keywords)
            c.editboxes.triggers:SetText(TableToCSV(triggers, DEFAULT_TRIGGERS))
        end
        if c.editboxes.inverted and c.editboxes.inverted.SetText then
            local inverted = (cfg.autoInvite and (cfg.autoInvite.invertedKeywords or cfg.autoInvite.inverted)) or
                             (db.invertedKeywords)
            c.editboxes.inverted:SetText(TableToCSV(inverted, DEFAULT_INVERTED))
        end
        if c.editboxes.blacklist and c.editboxes.blacklist.SetText then
            local blacklist = (cfg.autoInvite and cfg.autoInvite.blacklist) or (db.blacklist)
            c.editboxes.blacklist:SetText(TableToCSV(blacklist, DEFAULT_BLACKLIST))
        end
    end
end

--------------------------------------------------------------------------------
-- Settings Panel Lifecycle & UI Construction
--------------------------------------------------------------------------------

--- Opens the configuration panel in Blizzard Settings or Interface Options.
function SettingsPanel.Open()
    if not panelFrame then
        SettingsPanel:Initialize()
    end
    SettingsPanel.RefreshControls()

    if _G.Settings and type(_G.Settings.OpenToCategory) == "function" and categoryID then
        pcall(_G.Settings.OpenToCategory, categoryID)
    elseif type(_G.InterfaceOptionsFrame_OpenToCategory) == "function" and panelFrame then
        pcall(_G.InterfaceOptionsFrame_OpenToCategory, panelFrame)
    end
end

--- Returns the configuration panel frame widget.
-- Lazily instantiates the panel if not already created.
-- @return table: Panel frame object
function SettingsPanel.GetPanel()
    if not panelFrame then
        SettingsPanel:Initialize()
    end
    return panelFrame
end

--- Builds the settings panel frame and interactive controls.
function SettingsPanel:Initialize()
    if panelFrame then return panelFrame end

    if type(_G.CreateFrame) ~= "function" then return end

    panelFrame = _G.CreateFrame("Frame", "ULOSettingsPanel", _G.UIParent)
    panelFrame.name = "Universal Layer Operator"
    panelFrame.__children = panelFrame.__children or {}

    -- Title & Subtitle font strings
    if type(panelFrame.CreateFontString) == "function" then
        local title = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        if title and type(title.SetPoint) == "function" then
            title:SetPoint("TOPLEFT", 16, -16)
            if type(title.SetText) == "function" then
                title:SetText("Universal Layer Operator (ULO)")
            end
        end

        local subtitle = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        if subtitle and type(subtitle.SetPoint) == "function" then
            subtitle:SetPoint("TOPLEFT", 16, -40)
            if type(subtitle.SetText) == "function" then
                subtitle:SetText("Multi-release layer detection, refresh monitoring, and coordination settings.")
            end
        end
    end

    local cfg = _G.ULO_CONFIG or (ULO and ULO.config) or {}
    local db = _G.ULODB or (ULO and ULO.db) or {}

    ----------------------------------------------------------------------------
    -- 1. Checkboxes (8 Specified Controls)
    ----------------------------------------------------------------------------

    -- Checkbox 1: Enable Auto-Invite
    local initAutoInvite = true
    if db.autoInvite ~= nil then
        initAutoInvite = db.autoInvite
    elseif cfg.autoInvite and cfg.autoInvite.enabled ~= nil then
        initAutoInvite = cfg.autoInvite.enabled
    end
    local cbAutoInvite = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_AutoInvite",
        "Enable Auto-Invite",
        "Automatically accept whisper keywords and dispatch party invitations to coordinate layer hops.",
        initAutoInvite,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.autoInvite = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.autoInvite = _G.ULO_CONFIG.autoInvite or {}
            _G.ULO_CONFIG.autoInvite.enabled = checked
            if ULO.config then
                ULO.config.autoInvite = ULO.config.autoInvite or {}
                ULO.config.autoInvite.enabled = checked
            end
            if ULO.Coordination and type(ULO.Coordination.ToggleAutoInvite) == "function" then
                ULO.Coordination.ToggleAutoInvite(checked)
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "autoInvite", checked) end
        end
    )
    if cbAutoInvite and type(cbAutoInvite.SetPoint) == "function" then
        cbAutoInvite:SetPoint("TOPLEFT", 16, -70)
    end

    -- Checkbox 2: Sound Muting on Invites
    local initMuteSounds = true
    if cfg.autoInvite and cfg.autoInvite.muteSounds ~= nil then
        initMuteSounds = cfg.autoInvite.muteSounds
    elseif cfg.autoInvite and cfg.autoInvite.muteInviteSounds ~= nil then
        initMuteSounds = cfg.autoInvite.muteInviteSounds
    elseif db.muteSounds ~= nil then
        initMuteSounds = db.muteSounds
    end
    local cbMuteSounds = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_MuteSounds",
        "Mute Invite Sounds",
        "Temporarily mute party invite audio chimes and group prompt sounds to prevent audio spam.",
        initMuteSounds,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.muteSounds = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.autoInvite = _G.ULO_CONFIG.autoInvite or {}
            _G.ULO_CONFIG.autoInvite.muteSounds = checked
            _G.ULO_CONFIG.autoInvite.muteInviteSounds = checked
            if ULO.config then
                ULO.config.autoInvite = ULO.config.autoInvite or {}
                ULO.config.autoInvite.muteSounds = checked
                ULO.config.autoInvite.muteInviteSounds = checked
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "muteSounds", checked) end
        end
    )
    if cbMuteSounds and type(cbMuteSounds.SetPoint) == "function" then
        cbMuteSounds:SetPoint("TOPLEFT", 16, -96)
    end

    -- Checkbox 3: Whisper Confirmation Alerts
    local initWhisperConfirm = false
    if cfg.autoInvite and cfg.autoInvite.whisperConfirm ~= nil then
        initWhisperConfirm = cfg.autoInvite.whisperConfirm
    elseif db.whisperConfirm ~= nil then
        initWhisperConfirm = db.whisperConfirm
    end
    local cbWhisperConfirm = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_WhisperConfirm",
        "Whisper Confirmation Alerts",
        "Send automatic confirmation whispers to requesting players when invitations are queued.",
        initWhisperConfirm,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.whisperConfirm = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.autoInvite = _G.ULO_CONFIG.autoInvite or {}
            _G.ULO_CONFIG.autoInvite.whisperConfirm = checked
            if ULO.config then
                ULO.config.autoInvite = ULO.config.autoInvite or {}
                ULO.config.autoInvite.whisperConfirm = checked
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "whisperConfirm", checked) end
        end
    )
    if cbWhisperConfirm and type(cbWhisperConfirm.SetPoint) == "function" then
        cbWhisperConfirm:SetPoint("TOPLEFT", 16, -122)
    end

    -- Checkbox 4: Show Minimap Button
    local initShowMinimap = true
    if cfg.ui and cfg.ui.showMinimapBadge ~= nil then
        initShowMinimap = cfg.ui.showMinimapBadge
    elseif db.showMinimapBadge ~= nil then
        initShowMinimap = db.showMinimapBadge
    end
    local cbShowMinimap = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_ShowMinimap",
        "Show Minimap Button",
        "Show the orbital ULO layer indicator badge anchored to the Minimap perimeter.",
        initShowMinimap,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.showMinimapBadge = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.ui = _G.ULO_CONFIG.ui or {}
            _G.ULO_CONFIG.ui.showMinimapBadge = checked
            if ULO.config then
                ULO.config.ui = ULO.config.ui or {}
                ULO.config.ui.showMinimapBadge = checked
            end
            if ULO.UI and ULO.UI.MinimapBadge then
                local bf = ULO.UI.MinimapBadge.GetFrame and ULO.UI.MinimapBadge.GetFrame()
                if bf and type(bf.SetShown) == "function" then
                    bf:SetShown(checked)
                elseif bf then
                    if checked and type(bf.Show) == "function" then bf:Show()
                    elseif not checked and type(bf.Hide) == "function" then bf:Hide() end
                end
                if type(ULO.UI.MinimapBadge.Update) == "function" then
                    ULO.UI.MinimapBadge.Update()
                end
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "showMinimapBadge", checked) end
        end
    )
    if cbShowMinimap and type(cbShowMinimap.SetPoint) == "function" then
        cbShowMinimap:SetPoint("TOPLEFT", 16, -148)
    end

    -- Checkbox 5: Show Status HUD
    local initShowHUD = true
    if cfg.ui and cfg.ui.showStatusHUD ~= nil then
        initShowHUD = cfg.ui.showStatusHUD
    elseif db.showStatusHUD ~= nil then
        initShowHUD = db.showStatusHUD
    end
    local cbShowHUD = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_ShowHUD",
        "Show Status HUD",
        "Display the on-screen movable Status HUD with active countdowns and quick-hop buttons.",
        initShowHUD,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.showStatusHUD = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.ui = _G.ULO_CONFIG.ui or {}
            _G.ULO_CONFIG.ui.showStatusHUD = checked
            if ULO.config then
                ULO.config.ui = ULO.config.ui or {}
                ULO.config.ui.showStatusHUD = checked
            end
            if ULO.UI and ULO.UI.StatusHUD then
                if checked and type(ULO.UI.StatusHUD.Show) == "function" then
                    ULO.UI.StatusHUD.Show()
                elseif not checked and type(ULO.UI.StatusHUD.Hide) == "function" then
                    ULO.UI.StatusHUD.Hide()
                end
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "showStatusHUD", checked) end
        end
    )
    if cbShowHUD and type(cbShowHUD.SetPoint) == "function" then
        cbShowHUD:SetPoint("TOPLEFT", 16, -174)
    end

    -- Checkbox 6: Enable AutoLayer Protocol
    local initAutoLayer = true
    if cfg.interop and cfg.interop.autoLayerEnabled ~= nil then
        initAutoLayer = cfg.interop.autoLayerEnabled
    elseif cfg.interop and cfg.interop.autolayerEnabled ~= nil then
        initAutoLayer = cfg.interop.autolayerEnabled
    elseif db.autoLayerEnabled ~= nil then
        initAutoLayer = db.autoLayerEnabled
    end
    local cbAutoLayer = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_AutoLayer",
        "Enable AutoLayer Protocol",
        "Participate in the shared AutoLayer / NetherAutoLayer cross-addon channel network.",
        initAutoLayer,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.autoLayerEnabled = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.interop = _G.ULO_CONFIG.interop or {}
            _G.ULO_CONFIG.interop.autoLayerEnabled = checked
            _G.ULO_CONFIG.interop.autolayerEnabled = checked
            if ULO.config then
                ULO.config.interop = ULO.config.interop or {}
                ULO.config.interop.autoLayerEnabled = checked
                ULO.config.interop.autolayerEnabled = checked
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "autoLayerEnabled", checked) end
        end
    )
    if cbAutoLayer and type(cbAutoLayer.SetPoint) == "function" then
        cbAutoLayer:SetPoint("TOPLEFT", 280, -70)
    end

    -- Checkbox 7: Enable Overlord Protocol
    local initOverlord = true
    if cfg.interop and cfg.interop.overlordEnabled ~= nil then
        initOverlord = cfg.interop.overlordEnabled
    elseif db.overlordEnabled ~= nil then
        initOverlord = db.overlordEnabled
    end
    local cbOverlord = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_Overlord",
        "Enable Overlord Protocol",
        "Respond to Overlord layer request tokens transmitted via hidden addon whispers.",
        initOverlord,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.overlordEnabled = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.interop = _G.ULO_CONFIG.interop or {}
            _G.ULO_CONFIG.interop.overlordEnabled = checked
            if ULO.config then
                ULO.config.interop = ULO.config.interop or {}
                ULO.config.interop.overlordEnabled = checked
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "overlordEnabled", checked) end
        end
    )
    if cbOverlord and type(cbOverlord.SetPoint) == "function" then
        cbOverlord:SetPoint("TOPLEFT", 280, -96)
    end

    -- Checkbox 8: Sync NovaWorldBuffs
    local initNWBSync = true
    if cfg.interop and cfg.interop.nwbSync ~= nil then
        initNWBSync = cfg.interop.nwbSync
    elseif cfg.interop and cfg.interop.nwbEnabled ~= nil then
        initNWBSync = cfg.interop.nwbEnabled
    elseif db.nwbSync ~= nil then
        initNWBSync = db.nwbSync
    end
    local cbNWBSync = CreateCheckbox(
        panelFrame,
        "ULOCheckbox_NWBSync",
        "Sync NovaWorldBuffs",
        "Publish current layer index to NovaWorldBuffs global variables and event handlers.",
        initNWBSync,
        function(checked)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.nwbSync = checked
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.interop = _G.ULO_CONFIG.interop or {}
            _G.ULO_CONFIG.interop.nwbSync = checked
            _G.ULO_CONFIG.interop.nwbEnabled = checked
            if ULO.config then
                ULO.config.interop = ULO.config.interop or {}
                ULO.config.interop.nwbSync = checked
                ULO.config.interop.nwbEnabled = checked
            end
            if checked and ULO.Interop and ULO.Interop.NWB and type(ULO.Interop.NWB.SyncWithNWB) == "function" then
                ULO.Interop.NWB.SyncWithNWB()
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "nwbSync", checked) end
        end
    )
    if cbNWBSync and type(cbNWBSync.SetPoint) == "function" then
        cbNWBSync:SetPoint("TOPLEFT", 280, -122)
    end

    ----------------------------------------------------------------------------
    -- 2. Cooldown Duration Slider [300, 900]
    ----------------------------------------------------------------------------
    local initCooldown = SettingsPanel.GetCooldown()
    local cooldownSlider = CreateCooldownSlider(
        panelFrame,
        "ULOSlider_Cooldown",
        "Hopping Cooldown: %d sec",
        MIN_COOLDOWN,
        MAX_COOLDOWN,
        10,
        initCooldown,
        function(val)
            return SettingsPanel.SetCooldown(val)
        end
    )
    if cooldownSlider and type(cooldownSlider.SetPoint) == "function" then
        cooldownSlider:SetPoint("TOPLEFT", 285, -170)
        if type(cooldownSlider.SetSize) == "function" then
            cooldownSlider:SetSize(180, 16)
        end
    end

    ----------------------------------------------------------------------------
    -- 3. Text EditBoxes (3 Specified Controls)
    ----------------------------------------------------------------------------

    -- EditBox 1: Trigger Keywords
    local initTriggers = TableToCSV(
        (cfg.autoInvite and (cfg.autoInvite.triggers or cfg.autoInvite.keywords)) or db.keywords,
        DEFAULT_TRIGGERS
    )
    local ebTriggers = CreateEditBox(
        panelFrame,
        "ULOEditBox_Triggers",
        "Trigger Keywords (comma-separated):",
        initTriggers,
        function(txt)
            local tbl = CSVToTable(txt)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.keywords = tbl
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.autoInvite = _G.ULO_CONFIG.autoInvite or {}
            _G.ULO_CONFIG.autoInvite.triggers = tbl
            _G.ULO_CONFIG.autoInvite.keywords = tbl
            if ULO.config then
                ULO.config.autoInvite = ULO.config.autoInvite or {}
                ULO.config.autoInvite.triggers = tbl
                ULO.config.autoInvite.keywords = tbl
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "keywords", tbl) end
        end
    )
    if ebTriggers then
        if ebTriggers.label and type(ebTriggers.label.SetPoint) == "function" then
            ebTriggers.label:SetPoint("TOPLEFT", 16, -225)
        end
        if type(ebTriggers.SetPoint) == "function" then
            ebTriggers:SetPoint("TOPLEFT", 20, -242)
        end
        if type(ebTriggers.SetSize) == "function" then
            ebTriggers:SetSize(460, 22)
        end
    end

    -- EditBox 2: Inverted Keywords
    local initInverted = TableToCSV(
        (cfg.autoInvite and (cfg.autoInvite.invertedKeywords or cfg.autoInvite.inverted)) or db.invertedKeywords,
        DEFAULT_INVERTED
    )
    local ebInverted = CreateEditBox(
        panelFrame,
        "ULOEditBox_Inverted",
        "Inverted Keywords (e.g. not, off, except):",
        initInverted,
        function(txt)
            local tbl = CSVToTable(txt)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.invertedKeywords = tbl
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.autoInvite = _G.ULO_CONFIG.autoInvite or {}
            _G.ULO_CONFIG.autoInvite.invertedKeywords = tbl
            _G.ULO_CONFIG.autoInvite.inverted = tbl
            if ULO.config then
                ULO.config.autoInvite = ULO.config.autoInvite or {}
                ULO.config.autoInvite.invertedKeywords = tbl
                ULO.config.autoInvite.inverted = tbl
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "invertedKeywords", tbl) end
        end
    )
    if ebInverted then
        if ebInverted.label and type(ebInverted.label.SetPoint) == "function" then
            ebInverted.label:SetPoint("TOPLEFT", 16, -275)
        end
        if type(ebInverted.SetPoint) == "function" then
            ebInverted:SetPoint("TOPLEFT", 20, -292)
        end
        if type(ebInverted.SetSize) == "function" then
            ebInverted:SetSize(460, 22)
        end
    end

    -- EditBox 3: Blacklist words
    local initBlacklist = TableToCSV(
        (cfg.autoInvite and cfg.autoInvite.blacklist) or db.blacklist,
        DEFAULT_BLACKLIST
    )
    local ebBlacklist = CreateEditBox(
        panelFrame,
        "ULOEditBox_Blacklist",
        "Blacklist Words (comma-separated):",
        initBlacklist,
        function(txt)
            local tbl = CSVToTable(txt)
            _G.ULODB = _G.ULODB or {}
            _G.ULODB.blacklist = tbl
            _G.ULO_CONFIG = _G.ULO_CONFIG or {}
            _G.ULO_CONFIG.autoInvite = _G.ULO_CONFIG.autoInvite or {}
            _G.ULO_CONFIG.autoInvite.blacklist = tbl
            if ULO.config then
                ULO.config.autoInvite = ULO.config.autoInvite or {}
                ULO.config.autoInvite.blacklist = tbl
            end
            if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "blacklist", tbl) end
        end
    )
    if ebBlacklist then
        if ebBlacklist.label and type(ebBlacklist.label.SetPoint) == "function" then
            ebBlacklist.label:SetPoint("TOPLEFT", 16, -325)
        end
        if type(ebBlacklist.SetPoint) == "function" then
            ebBlacklist:SetPoint("TOPLEFT", 20, -342)
        end
        if type(ebBlacklist.SetSize) == "function" then
            ebBlacklist:SetSize(460, 22)
        end
    end

    ----------------------------------------------------------------------------
    -- 4. Expose Controls Table for Verification & Inspection
    ----------------------------------------------------------------------------
    SettingsPanel.controls = {
        checkboxes = {
            autoInvite     = cbAutoInvite,
            muteSounds     = cbMuteSounds,
            whisperConfirm = cbWhisperConfirm,
            showMinimap    = cbShowMinimap,
            showHUD        = cbShowHUD,
            autoLayer      = cbAutoLayer,
            overlord       = cbOverlord,
            nwbSync        = cbNWBSync,
        },
        editboxes = {
            triggers       = ebTriggers,
            inverted       = ebInverted,
            blacklist      = ebBlacklist,
        },
        slider = cooldownSlider,

        -- Flat direct aliases
        autoInvite     = cbAutoInvite,
        muteSounds     = cbMuteSounds,
        whisperConfirm = cbWhisperConfirm,
        showMinimap    = cbShowMinimap,
        showHUD        = cbShowHUD,
        autoLayer      = cbAutoLayer,
        overlord       = cbOverlord,
        nwbSync        = cbNWBSync,
        triggers       = ebTriggers,
        inverted       = ebInverted,
        blacklist      = ebBlacklist,
        cooldownSlider = cooldownSlider,
    }
    panelFrame.controls = SettingsPanel.controls

    panelFrame:SetScript("OnShow", function(self)
        SettingsPanel.RefreshControls()
    end)

    ----------------------------------------------------------------------------
    -- 5. Multi-release Blizzard Settings Registration
    ----------------------------------------------------------------------------
    if _G.Settings and type(_G.Settings.RegisterCanvasLayoutCategory) == "function" and type(_G.Settings.RegisterAddOnCategory) == "function" then
        local ok, cat = pcall(_G.Settings.RegisterCanvasLayoutCategory, panelFrame, panelFrame.name)
        if ok and cat then
            pcall(_G.Settings.RegisterAddOnCategory, cat)
            if type(cat.GetID) == "function" then
                categoryID = cat:GetID()
            end
        end
    elseif type(_G.InterfaceOptions_AddCategory) == "function" then
        pcall(_G.InterfaceOptions_AddCategory, panelFrame)
    end

    return panelFrame
end

--- Enables options panel components upon player login.
function SettingsPanel:Enable()
    SettingsPanel:Initialize()
end

--- Clean teardown on player logout.
function SettingsPanel:OnLogout()
    -- Flush pending changes
end

-- Wire UI Subsystem Lifecycle
function ULO.UI:Initialize()
    if SettingsPanel.Initialize then
        SettingsPanel:Initialize()
    end
    if ULO.UI.MinimapBadge and ULO.UI.MinimapBadge.Update then
        ULO.UI.MinimapBadge.Update()
    end
    if ULO.UI.StatusHUD and ULO.UI.StatusHUD.Update then
        ULO.UI.StatusHUD.Update()
    end
end

function ULO.UI:Enable()
    if SettingsPanel.Enable then
        SettingsPanel:Enable()
    end
    if ULO.UI.MinimapBadge and ULO.UI.MinimapBadge.Update then
        ULO.UI.MinimapBadge.Update()
    end
    if ULO.UI.StatusHUD and ULO.UI.StatusHUD.Update then
        ULO.UI.StatusHUD.Update()
    end
end

function ULO.UI:OnLogout()
    if SettingsPanel.OnLogout then
        SettingsPanel:OnLogout()
    end
end

-- Register UI Subsystem into ULO Core
if ULO.RegisterSubsystem then
    ULO.RegisterSubsystem("UI", ULO.UI)
end

return SettingsPanel
