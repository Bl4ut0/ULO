-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Monitor/RefreshMonitor.lua
-- Description: 180s refresh window countdown, "Refresh Now" trigger,
--              combat/death deferral, chat chevron minimization, and callbacks.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Monitor = ULO.Monitor or {}
local Monitor = ULO.Monitor
local C = ULO.Constants

-- Runtime State
local refreshPending = false
local refreshRemaining = 0
local refreshTicker = nil
local isChevronMinimized = false
local isCombatDeferred = false
local isDeferredDead = false
local isDeferredTaxi = false
local taxiWatchTimer = nil
local lastRefreshRequestTime = 0
local activeTimersCount = 0
local graceCounter = 0

--- Executes refresh transfer if not deferred by combat, death, or taxi flight.
function Monitor.CheckAndExecuteRefresh()
    local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                     or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
    local isDead = (type(_G.UnitIsDeadOrGhost) == "function" and _G.UnitIsDeadOrGhost("player"))
                   or (type(_G.UnitIsDead) == "function" and _G.UnitIsDead("player"))
    local onTaxi = (type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player"))

    if inCombat then
        isCombatDeferred = true
        return
    end

    if isDead then
        isDeferredDead = true
        return
    end

    if onTaxi then
        isDeferredTaxi = true
        -- Fallback polling if PLAYER_CONTROL_GAINED event is delayed
        if not taxiWatchTimer and type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
            local function CheckTaxiLanded()
                taxiWatchTimer = nil
                if not isDeferredTaxi then return end
                local stillOnTaxi = (type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player"))
                if not stillOnTaxi then
                    isDeferredTaxi = false
                    Monitor.CheckAndExecuteRefresh()
                else
                    taxiWatchTimer = true
                    _G.C_Timer.After(1.0, CheckTaxiLanded)
                end
            end
            taxiWatchTimer = true
            _G.C_Timer.After(1.0, CheckTaxiLanded)
        end
        return
    end

    -- Out of combat, alive, and not on taxi: execute refresh
    refreshPending = false
    isCombatDeferred = false
    isDeferredDead = false
    isDeferredTaxi = false
    taxiWatchTimer = nil
    refreshRemaining = 0
    if refreshTicker then
        refreshTicker:Cancel()
        refreshTicker = nil
        activeTimersCount = 0
    end

    local trigger = ULO.TriggerCallback or ULO.FireCallback
    if type(trigger) == "function" then
        trigger("OnRefreshTriggered")
    end

    if type(_G.ReloadUI) == "function" then
        pcall(_G.ReloadUI)
    end
end

--- Initiates a layer refresh countdown warning window.
-- @param duration number: Duration in seconds (defaults to 180)
function Monitor.StartRefreshWarning(duration)
    duration = tonumber(duration) or ((C and C.TIMERS and C.TIMERS.REFRESH_WINDOW) or 180)
    if duration < 0 then duration = 0 end

    refreshPending = true
    refreshRemaining = duration
    isCombatDeferred = false
    isDeferredDead = false
    isDeferredTaxi = false
    taxiWatchTimer = nil
    activeTimersCount = 1

    if duration == 0 then
        Monitor.CheckAndExecuteRefresh()
        return
    end

    if refreshTicker then
        refreshTicker:Cancel()
        refreshTicker = nil
    end

    if type(_G.C_Timer) == "table" and type(_G.C_Timer.NewTicker) == "function" then
        refreshTicker = _G.C_Timer.NewTicker(1, function(ticker)
            if not refreshPending then
                ticker:Cancel()
                refreshTicker = nil
                activeTimersCount = 0
                return
            end

            refreshRemaining = refreshRemaining - 1
            if refreshRemaining < 0 then refreshRemaining = 0 end

            -- Auto-expand chevron at <= 10s
            if refreshRemaining <= 10 and isChevronMinimized then
                isChevronMinimized = false
            end

            local trigger = ULO.TriggerCallback or ULO.FireCallback
            if type(trigger) == "function" then
                trigger("OnRefreshWarning", refreshRemaining, isCombatDeferred)
            end

            if refreshRemaining <= 0 then
                ticker:Cancel()
                refreshTicker = nil
                activeTimersCount = 0
                Monitor.CheckAndExecuteRefresh()
            end
        end)
    end
end

Monitor.StartRefreshCountdown = Monitor.StartRefreshWarning

--- Cancels any active refresh countdown.
-- @param reason string|nil: Reason for cancellation
function Monitor.CancelRefreshCountdown(reason)
    refreshPending = false
    refreshRemaining = 0
    isCombatDeferred = false
    isDeferredDead = false
    isDeferredTaxi = false
    taxiWatchTimer = nil
    graceCounter = graceCounter + 1
    if refreshTicker then
        refreshTicker:Cancel()
        refreshTicker = nil
        activeTimersCount = 0
    end
end

--- Attempts immediate refresh reload.
-- Rate limited to 1 click per second. Blocked in combat.
-- @return boolean: true if executed
-- @return string: "ok", "throttled", "combat", "dead", or "taxi"
function Monitor.RequestRefreshNow()
    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    if (now - lastRefreshRequestTime) < 0 then
        lastRefreshRequestTime = now
        return false, "throttled"
    end
    if (now - lastRefreshRequestTime) < 1.0 then
        return false, "throttled"
    end
    lastRefreshRequestTime = now

    local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                     or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
    if inCombat then
        return false, "combat"
    end

    local isDead = (type(_G.UnitIsDeadOrGhost) == "function" and _G.UnitIsDeadOrGhost("player"))
                   or (type(_G.UnitIsDead) == "function" and _G.UnitIsDead("player"))
    if isDead then
        return false, "dead"
    end

    local onTaxi = (type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player"))
    if onTaxi then
        return false, "taxi"
    end

    refreshPending = false
    isCombatDeferred = false
    isDeferredDead = false
    isDeferredTaxi = false
    taxiWatchTimer = nil
    refreshRemaining = 0
    if refreshTicker then
        refreshTicker:Cancel()
        refreshTicker = nil
        activeTimersCount = 0
    end

    local trigger = ULO.TriggerCallback or ULO.FireCallback
    if type(trigger) == "function" then
        trigger("OnRefreshTriggered")
    end

    if type(_G.ReloadUI) == "function" then
        pcall(_G.ReloadUI)
    end
    return true, "ok"
end

function Monitor.MinimizeToChevron(minimized)
    isChevronMinimized = (minimized == true)
end

function Monitor.IsChevronMinimized()
    return isChevronMinimized
end

function Monitor.IsRefreshPending()
    return refreshPending
end

function Monitor.GetRefreshRemaining()
    return refreshRemaining
end

function Monitor.IsCombatDeferred()
    return isCombatDeferred
end

function Monitor.IsDeferredDead()
    return isDeferredDead
end

function Monitor.IsDeferredTaxi()
    return isDeferredTaxi
end
Monitor.IsTaxiDeferred = Monitor.IsDeferredTaxi

if ULO.Detection then
    ULO.Detection.IsDeferredTaxi = Monitor.IsDeferredTaxi
end

function Monitor.GetActiveTimerCount()
    return activeTimersCount
end

-- ============================================================================
-- Event Frame & Subsystem Callbacks
-- ============================================================================
local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if Monitor.IsCombatDeferred() then
            graceCounter = graceCounter + 1
            local curGrace = graceCounter
            local graceDuration = (C and C.TIMERS and C.TIMERS.COMBAT_DEFERRAL_GRACE) or 2.0
            if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
                _G.C_Timer.After(graceDuration, function()
                    if curGrace ~= graceCounter then return end
                    local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                                     or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
                    if inCombat then
                        isCombatDeferred = true
                        return
                    end
                    local isDead = (type(_G.UnitIsDeadOrGhost) == "function" and _G.UnitIsDeadOrGhost("player"))
                                   or (type(_G.UnitIsDead) == "function" and _G.UnitIsDead("player"))
                    if isDead then
                        isDeferredDead = true
                        return
                    end
                    local onTaxi = (type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player"))
                    if onTaxi then
                        isDeferredTaxi = true
                        return
                    end
                    if Monitor.IsCombatDeferred() then
                        Monitor.CheckAndExecuteRefresh()
                    end
                end)
            else
                Monitor.CheckAndExecuteRefresh()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        graceCounter = graceCounter + 1
        if refreshPending or isCombatDeferred then
            isCombatDeferred = true
        end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if isDeferredDead then
            isDeferredDead = false
            local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
            local onTaxi = (type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player"))
            if inCombat then
                isCombatDeferred = true
            elseif onTaxi then
                isDeferredTaxi = true
            else
                Monitor.CheckAndExecuteRefresh()
            end
        end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if isDeferredTaxi then
            local onTaxi = (type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player"))
            if not onTaxi then
                isDeferredTaxi = false
                taxiWatchTimer = nil
                Monitor.CheckAndExecuteRefresh()
            end
        end
    end
end

if type(_G.CreateFrame) == "function" then
    local f = _G.CreateFrame("Frame", "ULO_RefreshMonitorFrame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_ALIVE")
    f:RegisterEvent("PLAYER_UNGHOST")
    f:RegisterEvent("PLAYER_CONTROL_GAINED")
    f:SetScript("OnEvent", OnEvent)
    Monitor.eventFrame = f
end

-- Automatic cancellation of refresh warning on confirmed layer change
if ULO.RegisterCallback then
    ULO.RegisterCallback("OnLayerChanged", function()
        if refreshPending then
            Monitor.CancelRefreshCountdown("layer_changed")
        end
    end)
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
