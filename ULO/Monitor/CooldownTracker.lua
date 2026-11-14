-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Monitor/CooldownTracker.lua
-- Description: Post-transfer layer hopping cooldown tracking, hop throttling,
--              and cooldown alert dispatches.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Monitor = ULO.Monitor or {}
local Monitor = ULO.Monitor
local C = ULO.Constants

-- Runtime State
local cooldownRemaining = 0
local cooldownTicker = nil

local function GetSavedDB()
    if type(_G.ULO_DB) ~= "table" then
        _G.ULO_DB = (type(_G.ULODB) == "table" and _G.ULODB) or {}
    elseif type(_G.ULODB) == "table" and _G.ULO_DB.cooldownDuration == nil and _G.ULODB.cooldownDuration ~= nil then
        _G.ULO_DB.cooldownDuration = _G.ULODB.cooldownDuration
    end
    -- Keep _G.ULODB aliased to _G.ULO_DB for backwards compatibility and test assertions
    _G.ULODB = _G.ULO_DB
    return _G.ULO_DB
end

--- Sets the configurable cooldown duration (clamped [300, 900]).
-- @param val number: Target duration in seconds
-- @return number: Clamped duration
function Monitor.SetCooldownDuration(val)
    local minCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_MIN) or 300
    local maxCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_MAX) or 900
    local defCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_DEFAULT) or 300

    local n = tonumber(val)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        n = defCD
    elseif n < minCD then
        n = minCD
    elseif n > maxCD then
        n = maxCD
    else
        n = math.floor(n + 0.5)
    end

    local db = GetSavedDB()
    db.cooldownDuration = n
    _G.ULO_DB = _G.ULO_DB or _G.ULODB or {}
    _G.ULODB = _G.ULO_DB
    _G.ULO_DB.cooldownDuration = n
    _G.ULODB.cooldownDuration = n

    -- Synchronize ULO_CONFIG schema if present
    if type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.cooldown) == "table" then
        _G.ULO_CONFIG.cooldown.durationSeconds = n
    end

    return n
end

--- Gets the configured cooldown duration (default 300).
-- @return number: Cooldown duration in seconds
function Monitor.GetCooldownDuration()
    local minCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_MIN) or 300
    local maxCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_MAX) or 900
    local defCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_DEFAULT) or 300

    local db = GetSavedDB()
    local cd = tonumber(db.cooldownDuration)
    if not cd or cd < minCD or cd > maxCD then
        if type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.cooldown) == "table" then
            cd = tonumber(_G.ULO_CONFIG.cooldown.durationSeconds)
        end
        if not cd or cd < minCD or cd > maxCD then
            cd = defCD
        end
        db.cooldownDuration = cd
        _G.ULODB.cooldownDuration = cd
    end
    return cd
end

--- Initiates post-transfer hopping cooldown.
-- @param duration number|nil: Duration in seconds (clamped <= 900, defaults to configured duration)
function Monitor.StartCooldown(duration)
    local minCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_MIN) or 300
    local maxCD = (C and C.TIMERS and C.TIMERS.COOLDOWN_MAX) or 900
    local configured = Monitor.GetCooldownDuration()

    local d = tonumber(duration)
    if not d or d ~= d or d == math.huge or d == -math.huge or d <= 0 then
        duration = configured
    elseif d > maxCD then
        duration = maxCD
    elseif d < minCD and d < 180 then
        duration = minCD
    else
        duration = math.floor(d + 0.5)
    end

    cooldownRemaining = duration

    local trigger = ULO.TriggerCallback or ULO.FireCallback
    if type(trigger) == "function" then
        trigger("OnCooldownStarted", duration)
    end

    if cooldownTicker then
        cooldownTicker:Cancel()
        cooldownTicker = nil
    end

    if type(_G.C_Timer) == "table" and type(_G.C_Timer.NewTicker) == "function" then
        cooldownTicker = _G.C_Timer.NewTicker(1, function(ticker)
            cooldownRemaining = cooldownRemaining - 1
            if cooldownRemaining <= 0 then
                cooldownRemaining = 0
                ticker:Cancel()
                cooldownTicker = nil
                local trig = ULO.TriggerCallback or ULO.FireCallback
                if type(trig) == "function" then
                    trig("OnCooldownExpired")
                end
            end
        end)
    end
end

--- Cancels any active post-transfer cooldown.
function Monitor.CancelCooldown()
    if cooldownTicker then
        cooldownTicker:Cancel()
        cooldownTicker = nil
    end
    cooldownRemaining = 0
end

--- Returns the remaining seconds on hopping cooldown.
-- @return number: Seconds remaining
function Monitor.GetCooldownRemaining()
    return cooldownRemaining
end

--- Returns whether player is currently on hopping cooldown.
-- @return boolean: true if cooldown > 0
function Monitor.IsOnCooldown()
    return cooldownRemaining > 0
end

function Monitor:Initialize()
    -- Subsystem initialization
end

function Monitor:Enable()
    -- Subsystem enable
end

Monitor.OnPlayerLogin = Monitor.Enable

function Monitor:OnLogout()
    -- Subsystem clean teardown
end

-- Register Subsystem into ULO
if ULO.RegisterSubsystem then
    ULO.RegisterSubsystem("Monitor", ULO.Monitor)
end
