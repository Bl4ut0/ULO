-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Core/Init.lua
-- Description: Namespace bootstrapping, subsystem registration, central event bus,
--              SavedVariables lifecycle management, and logging infrastructure.
-- ============================================================================

local addonName, addonTable = ...
_G.ULO = _G.ULO or addonTable or {}
local ULO = _G.ULO

local C = ULO.Constants or {}

-- ----------------------------------------------------------------------------
-- Root Namespace Properties
-- ----------------------------------------------------------------------------
ULO.name        = addonName or "ULO"
ULO.title       = C.ADDON_TITLE or "Universal Layer Operator"
ULO.version     = C.VERSION or "1.0.0"
ULO.state       = C.STATES and C.STATES.UNINITIALIZED or "UNINITIALIZED"
ULO.subsystems  = {}
ULO.callbacks   = {}
ULO.isLoaded    = false
ULO.isLoggedIn  = false
ULO.db          = nil
ULO.config      = nil
ULO.charDB      = nil

-- ----------------------------------------------------------------------------
-- Deep Copy & Recursive Configuration Merge
-- ----------------------------------------------------------------------------
local function DeepMergeTable(target, source)
    if type(target) ~= "table" then target = {} end
    if type(source) ~= "table" then return target end

    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = DeepMergeTable(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end
ULO.DeepMergeTable = DeepMergeTable

-- ----------------------------------------------------------------------------
-- Subsystem Registration Pattern
-- ----------------------------------------------------------------------------
--- Registers a subsystem module into ULO.
-- @param name string: Unique identifier (e.g. "Detection", "Monitor", "Compat")
-- @param moduleTable table: Module table containing subsystem methods
-- @return table: The registered module table
function ULO.RegisterSubsystem(name, moduleTable)
    if type(name) ~= "string" or name == "" then
        error("ULO.RegisterSubsystem: name must be a non-empty string", 2)
    end
    if type(moduleTable) ~= "table" then
        error("ULO.RegisterSubsystem: moduleTable must be a table", 2)
    end

    ULO.subsystems[name] = moduleTable
    ULO[name] = moduleTable

    -- If the addon is already loaded, immediately initialize the subsystem
    local initFunc = moduleTable.Initialize
    if ULO.isLoaded and (type(initFunc) == "function" or type(initFunc) == "userdata") then
        local success, err = pcall(initFunc, moduleTable)
        if not success then
            ULO.Debug(string.format("Failed to initialize subsystem %s: %s", name, tostring(err)))
        end
    end

    return moduleTable
end

-- ----------------------------------------------------------------------------
-- Event Bus Callback System
-- ----------------------------------------------------------------------------
--- Registers a callback handler for an internal ULO event.
-- @param eventName string: Callback event identifier
-- @param handler function: Function to invoke when event triggers
-- @return function: Unsubscribe closure to remove this handler
function ULO.RegisterCallback(eventName, handler)
    if type(eventName) ~= "string" or eventName == "" then
        error("ULO.RegisterCallback: eventName must be a non-empty string", 2)
    end
    local hType = type(handler)
    local isCallable = (hType == "function") or (hType == "userdata")
    if not isCallable and hType == "table" then
        local mt = getmetatable(handler)
        if mt and mt.__call then isCallable = true end
    end
    if not isCallable then
        error("ULO.RegisterCallback: handler must be a function or callable", 2)
    end

    ULO.callbacks[eventName] = ULO.callbacks[eventName] or {}
    table.insert(ULO.callbacks[eventName], handler)

    -- Return unsubscribe function
    return function()
        ULO.UnregisterCallback(eventName, handler)
    end
end

-- Independent request sources. Existing flat settings remain authoritative so
-- the Actions menu and Settings checkboxes always read the same preferences.
ULO.RequestTracks = {
    { id = "ulo", label = "ULO", flag = "uloEnabled" },
    { id = "autoLayer", label = "AutoLayer", flag = "autoLayerEnabled" },
    { id = "overlord", label = "Overlord", flag = "overlordEnabled" },
    { id = "nwb", label = "NovaWorldBuffs sync", flag = "nwbSync" },
    { id = "guild", label = "Guild chat", flag = "guildInviteEnabled" },
    { id = "tresLayerSwap", label = "TresLayerSwap", flag = "tresLayerSwapEnabled" },
    { id = "layerHopper", label = "LayerHopper", flag = "layerHopperEnabled" },
    { id = "directWhisper", label = "Direct whispers", flag = "directWhisperEnabled" },
}

local function FindRequestTrack(id)
    for _, track in ipairs(ULO.RequestTracks) do
        if track.id == id then return track end
    end
end

function ULO.IsTrackEnabled(id)
    local track = FindRequestTrack(id)
    if not track then return false end
    local db = type(_G.ULODB) == "table" and _G.ULODB or {}
    local cfg = type(_G.ULO_CONFIG) == "table" and _G.ULO_CONFIG.interop or {}
    cfg = type(cfg) == "table" and cfg or {}
    if db.uloOnlyMode and (id == "autoLayer" or id == "overlord" or id == "tresLayerSwap" or id == "layerHopper") then
        return false
    end
    if db[track.flag] == false or cfg[track.flag] == false then return false end
    if id == "autoLayer" and cfg.autolayerEnabled == false then return false end
    if id == "nwb" and (db.nwbEnabled == false or cfg.nwbEnabled == false) then return false end
    return true
end

function ULO.SetTrackEnabled(id, enabled)
    local track = FindRequestTrack(id)
    if not track then return false end
    _G.ULODB = _G.ULODB or {}
    _G.ULO_CONFIG = _G.ULO_CONFIG or {}
    _G.ULO_CONFIG.interop = _G.ULO_CONFIG.interop or {}
    -- Preserve the effective choices when upgrading an old ULO-only profile.
    if _G.ULODB.uloOnlyMode then
        for _, legacy in ipairs({ "autoLayer", "overlord", "tresLayerSwap", "layerHopper" }) do
            local oldTrack = FindRequestTrack(legacy)
            _G.ULODB[oldTrack.flag] = false
            _G.ULO_CONFIG.interop[oldTrack.flag] = false
        end
        _G.ULODB.uloOnlyMode = false
    end
    local flag = enabled == true
    _G.ULODB[track.flag] = flag
    _G.ULO_CONFIG.interop[track.flag] = flag
    if id == "autoLayer" then _G.ULO_CONFIG.interop.autolayerEnabled = flag end
    if id == "nwb" then
        _G.ULODB.nwbEnabled = flag
        _G.ULO_CONFIG.interop.nwbEnabled = flag
    end
    if ULO.config then ULO.config.interop = _G.ULO_CONFIG.interop end
    if id == "guild" and ULO.Coordination and ULO.Coordination.SetGuildInviteEnabled then
        ULO.Coordination.SetGuildInviteEnabled(flag)
    end
    if ULO.Interop and ULO.Interop.Overlord and ULO.Interop.Overlord.SyncHelpMode then
        ULO.Interop.Overlord.SyncHelpMode()
    end
    if ULO.Coordination and ULO.Coordination.SyncLeatrixPlusGuard then ULO.Coordination.SyncLeatrixPlusGuard() end
    if ULO.LogAction then ULO.LogAction("Mode", track.label .. (flag and " enabled" or " disabled")) end
    if ULO.TriggerCallback then ULO.TriggerCallback("OnConfigChanged", "requestTrack", id, flag) end
    if ULO.UI and ULO.UI.StatusHUD then ULO.UI.StatusHUD.Update() end
    if ULO.UI and ULO.UI.SettingsPanel and ULO.UI.SettingsPanel.RefreshControls then ULO.UI.SettingsPanel.RefreshControls() end
    return flag
end

--- Unregisters a previously registered callback handler.
-- @param eventName string: Callback event identifier
-- @param handler function: Function to remove
function ULO.UnregisterCallback(eventName, handler)
    local handlers = ULO.callbacks[eventName]
    if not handlers then return end

    for index, registeredHandler in ipairs(handlers) do
        if registeredHandler == handler then
            table.remove(handlers, index)
            break
        end
    end
end

--- Triggers an internal ULO event, invoking all registered handlers safely.
-- @param eventName string: Callback event identifier
-- @param ... any: Variable arguments passed to handlers
function ULO.TriggerCallback(eventName, ...)
    local handlers = ULO.callbacks[eventName]
    if not handlers or #handlers == 0 then return end

    -- Snapshot handler list prior to dispatch to prevent in-flight mutation reentrancy hazards
    local snapshot = {}
    for i, h in ipairs(handlers) do
        snapshot[i] = h
    end

    for _, handler in ipairs(snapshot) do
        local success, err = pcall(handler, ...)
        if not success then
            ULO.Debug(string.format("Error in callback handler for '%s': %s", eventName, tostring(err)))
        end
    end
end
ULO.FireCallback = ULO.TriggerCallback

-- ----------------------------------------------------------------------------
-- Output & Logging Infrastructure
-- ----------------------------------------------------------------------------
--- Prints a formatted, colored message to the user chat frame.
-- @param msg any: Message to print
function ULO.Print(msg)
    local safeMsg = tostring(msg or "")
    local formatted = "|cff00ccff[ULO]|r " .. safeMsg

    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, formatted)
    elseif type(print) == "function" then
        pcall(print, formatted)
    end
end

--- Prints a debug message if debug logging is enabled in configuration.
-- @param msg any: Message to print
function ULO.Debug(msg)
    if type(ULO.config) ~= "table" or not ULO.config.debug then return end

    local safeMsg = tostring(msg or "")
    local formatted = "|cffff9900[ULO Debug]|r " .. safeMsg

    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, formatted)
    elseif type(print) == "function" then
        pcall(print, formatted)
    end
end

--- Prints an error message to the chat frame.
-- @param msg any: Error message
function ULO.Error(msg)
    local safeMsg = tostring(msg or "")
    local formatted = "|cffff3333[ULO Error]|r " .. safeMsg

    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, formatted)
    elseif type(print) == "function" then
        pcall(print, formatted)
    end
end

-- ----------------------------------------------------------------------------
-- SavedVariables & Addon Lifecycle Handling
-- ----------------------------------------------------------------------------
local function OnAddonLoaded(loadedName)
    if loadedName ~= ULO.name and loadedName ~= "ULO" then return end

    -- Initialize SavedVariables with strict table type validation
    if type(_G.ULO_DB) ~= "table" then
        _G.ULO_DB = {}
    end
    if type(_G.ULO_CONFIG) ~= "table" then
        _G.ULO_CONFIG = {}
    end
    if type(_G.ULO_CHAR_DB) ~= "table" then
        _G.ULO_CHAR_DB = {}
    end

    -- Deep merge default settings to populate missing keys from updates
    if C.DEFAULT_CONFIG then
        _G.ULO_CONFIG = DeepMergeTable(_G.ULO_CONFIG, C.DEFAULT_CONFIG)
    end

    ULO.db       = _G.ULO_DB
    ULO.config   = _G.ULO_CONFIG
    ULO.charDB   = _G.ULO_CHAR_DB
    ULO.isLoaded = true

    -- Initialize all registered subsystems
    for name, subsystem in pairs(ULO.subsystems) do
        local initFunc = subsystem.Initialize
        if type(initFunc) == "function" or type(initFunc) == "userdata" then
            local success, err = pcall(initFunc, subsystem)
            if not success then
                ULO.Debug(string.format("Failed to initialize subsystem %s: %s", name, tostring(err)))
            end
        end
    end
end

local function OnPlayerLogin()
    ULO.isLoggedIn = true

    -- Notify enabled subsystems
    for name, subsystem in pairs(ULO.subsystems) do
        local enableFunc = subsystem.Enable
        if type(enableFunc) == "function" or type(enableFunc) == "userdata" then
            local success, err = pcall(enableFunc, subsystem)
            if not success then
                ULO.Debug(string.format("Failed to enable subsystem %s: %s", name, tostring(err)))
            end
        end
    end

    if type(ULO.config) == "table" and ULO.config.debug then
        local flavorStr = "unknown"
        if ULO.Compat and type(ULO.Compat.GetClientFlavor) == "function" then
            flavorStr = ULO.Compat.GetClientFlavor()
        end
        ULO.Print(string.format("v%s initialized. Client flavor: %s", ULO.version, flavorStr))
    end
end

local function OnPlayerLogout()
    -- Allow subsystems to flush state prior to game exit
    for name, subsystem in pairs(ULO.subsystems) do
        local logoutFunc = subsystem.OnLogout
        if type(logoutFunc) == "function" or type(logoutFunc) == "userdata" then
            pcall(logoutFunc, subsystem)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Blizzard Event Dispatcher Frame (Guarded for headless tests)
-- ----------------------------------------------------------------------------
if type(CreateFrame) == "function" then
    local eventFrame = CreateFrame("Frame", "ULO_CoreEventFrame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")

    eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
        if event == "ADDON_LOADED" then
            OnAddonLoaded(arg1)
        elseif event == "PLAYER_LOGIN" then
            OnPlayerLogin()
        elseif event == "PLAYER_LOGOUT" then
            OnPlayerLogout()
        end
    end)
    ULO.eventFrame = eventFrame
else
    -- Headless test environment mock triggers
    ULO._TriggerAddonLoaded = OnAddonLoaded
    ULO._TriggerPlayerLogin = OnPlayerLogin
    ULO._TriggerPlayerLogout = OnPlayerLogout
end

-- Register the Compat module into the subsystem registry if it was loaded earlier
if ULO.Compat then
    ULO.RegisterSubsystem("Compat", ULO.Compat)
end
