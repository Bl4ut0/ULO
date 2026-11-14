-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Coordination/GroupManager.lua
-- Description: Auto-accept hop invites, StaticPopupDialogs suppression,
--              post-hop group departure, 40s verification timeout, combat
--              deferral lifecycle, and Coordination subsystem registration.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Coordination = ULO.Coordination or {}
local Coordination = ULO.Coordination
local C = ULO.Constants
local Compat = ULO.Compat

-- Internal State
local isAwaitingHop = false
local awaitingHopTarget = nil
local awaitingLayerVerification = false
local isDepartureDeferred = false
local hopRequestTime = 0
local HOP_VERIFY_TIMEOUT = (C and C.OVERLORD and C.OVERLORD.VERIFY_TIMEOUT) or 40.0
local hopTimeoutTimer = nil

--- Initiates an active layer hop request for a target layer.
-- @param targetLayer number: Destination layer index
-- @param preferredProtocol string|nil: Preferred protocol ("AutoLayer" or "Overlord")
-- @return boolean: true if hop request armed successfully
-- @return string|nil: Status code ("ok" or error code like "cooldown")
function Coordination.RequestLayerHop(targetLayer, preferredProtocol)
    -- Guard: Active hop cooldown lockout
    if ULO.Monitor and type(ULO.Monitor.GetCooldownRemaining) == "function" and ULO.Monitor.GetCooldownRemaining() > 0 then
        if type(ULO.LogAction) == "function" then
            ULO.LogAction("Hop", "Blocked by cooldown (" .. tostring(ULO.Monitor.GetCooldownRemaining()) .. "s)")
        end
        return false, "cooldown"
    end

    if type(ULO.LogAction) == "function" then
        ULO.LogAction("Hop", targetLayer and ("Requesting hop to Layer " .. tostring(targetLayer)) or "Requesting hop to ANY available layer")
    end

    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    isAwaitingHop = true
    awaitingHopTarget = tonumber(targetLayer)
    awaitingLayerVerification = false
    isDepartureDeferred = false
    hopRequestTime = now

    if hopTimeoutTimer and type(hopTimeoutTimer.Cancel) == "function" then
        pcall(hopTimeoutTimer.Cancel, hopTimeoutTimer)
        hopTimeoutTimer = nil
    end

    -- Arm 40.0s verification safety timeout
    if type(_G.C_Timer) == "table" and type(_G.C_Timer.NewTimer) == "function" then
        hopTimeoutTimer = _G.C_Timer.NewTimer(HOP_VERIFY_TIMEOUT, function()
            Coordination.CancelHopRequest("timeout")
        end)
    elseif type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(HOP_VERIFY_TIMEOUT, function()
            local curNow = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
            if (isAwaitingHop or awaitingLayerVerification) and (curNow - hopRequestTime >= HOP_VERIFY_TIMEOUT) then
                Coordination.CancelHopRequest("timeout")
            end
        end)
    end

    -- Broadcast request over AutoLayer public channels if available
    if ULO.Interop and ULO.Interop.AutoLayer and type(ULO.Interop.AutoLayer.FormatBroadcastMessage) == "function" then
        ULO.Interop.AutoLayer.FormatBroadcastMessage(targetLayer)
    end

    -- Whisper up to 4 known Overlord LayerJumper peer candidates if available
    if ULO.Interop and ULO.Interop.Overlord and type(ULO.Interop.Overlord.BroadcastHopRequest) == "function" then
        pcall(ULO.Interop.Overlord.BroadcastHopRequest, targetLayer)
    end

    return true, "ok"
end

--- Cancels an active hop request, resets hop flags, and fires timeout callbacks.
-- @param reason string|nil: Cancellation reason code
function Coordination.CancelHopRequest(reason)
    local wasAwaitingVerification = awaitingLayerVerification
    isAwaitingHop = false
    awaitingHopTarget = nil
    awaitingLayerVerification = false
    if hopTimeoutTimer and type(hopTimeoutTimer.Cancel) == "function" then
        pcall(hopTimeoutTimer.Cancel, hopTimeoutTimer)
        hopTimeoutTimer = nil
    end

    -- Auto-depart helper group upon verification timeout expiration when in helper group
    if wasAwaitingVerification then
        Coordination.DepartGroup()
    end

    local trigger = ULO.TriggerCallback or ULO.FireCallback
    if type(trigger) == "function" then
        trigger("OnHopTimedOut", reason)
    end
end

--- Returns whether the client is currently awaiting an inbound layer hop invite.
-- Evaluates the 40s timeout window dynamically.
-- @return boolean
function Coordination.IsAwaitingHop()
    if not isAwaitingHop then return false end
    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    if (now - hopRequestTime) > HOP_VERIFY_TIMEOUT then
        Coordination.CancelHopRequest("timeout")
        return false
    end
    return true
end

--- Returns the active destination layer index for the pending hop, or nil.
-- @return number|nil
function Coordination.GetActiveHopTarget()
    return awaitingHopTarget
end

--- Returns whether player has joined the hop helper group and is awaiting layer verification.
-- @return boolean
function Coordination.IsAwaitingLayerVerification()
    return awaitingLayerVerification
end

--- Completely resets hop coordination lifecycle state.
function Coordination.ResetHopState()
    isAwaitingHop = false
    awaitingHopTarget = nil
    awaitingLayerVerification = false
    local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                     or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
    if not (inCombat and isDepartureDeferred) then
        isDepartureDeferred = false
    end
    if hopTimeoutTimer and type(hopTimeoutTimer.Cancel) == "function" then
        pcall(hopTimeoutTimer.Cancel, hopTimeoutTimer)
        hopTimeoutTimer = nil
    end
end

--- Attempts to leave the party, deferring departure if player is engaged in combat.
-- @return boolean: true if party departure executed immediately
-- @return string|nil: "combat_deferred" or error
function Coordination.LeavePartyWithCombatDeferral()
    local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                     or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
    if inCombat then
        isDepartureDeferred = true
        return false, "combat_deferred"
    end

    isDepartureDeferred = false
    local ok, err = false, nil
    if Compat and type(Compat.LeaveParty) == "function" then
        ok, err = Compat.LeaveParty()
    elseif type(_G.LeaveParty) == "function" then
        ok, err = pcall(_G.LeaveParty)
    end
    return ok, err
end

--- Departs helper group; delegates to combat-deferred departure.
-- @return boolean
function Coordination.DepartGroup()
    return Coordination.LeavePartyWithCombatDeferral()
end

--- Evaluates deferred departure upon combat drop.
-- @return boolean: true if group departure was executed
function Coordination.ProcessCombatRegen()
    if isDepartureDeferred then
        local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                         or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
        if not inCombat then
            return Coordination.DepartGroup()
        end
    end
    return false
end

--- Returns whether group departure is currently deferred pending combat end.
-- @return boolean
function Coordination.IsDepartureDeferred()
    return isDepartureDeferred
end

-- Event Listener: Group lifecycle management frame
if type(_G.CreateFrame) == "function" then
    local groupFrame = _G.CreateFrame("Frame", "ULO_GroupManagerFrame")
    groupFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    groupFrame:RegisterEvent("GROUP_JOINED")
    groupFrame:RegisterEvent("GROUP_LEFT")
    groupFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    groupFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "PARTY_INVITE_REQUEST" then
            local sender = ...
            if Coordination.IsAwaitingHop() then
                if Compat and type(Compat.AcceptGroup) == "function" then
                    Compat.AcceptGroup()
                elseif type(_G.AcceptGroup) == "function" then
                    pcall(_G.AcceptGroup)
                end
                awaitingLayerVerification = true
                local shortSender = type(sender) == "string" and string.lower(string.match(sender, "^([^%-]+)") or sender) or ""
                local viaSystem = "AutoLayer / Channel"
                if ULO.Interop and ULO.Interop.Overlord and ULO.Interop.Overlord.lastWhisperedPeers and ULO.Interop.Overlord.lastWhisperedPeers[shortSender] then
                    viaSystem = "OverlordLJ Whisper"
                elseif _G.ULODB and _G.ULODB.uloOnlyMode == true then
                    viaSystem = "ULO Native"
                end
                if type(ULO.LogAction) == "function" then
                    ULO.LogAction("Group", string.format("Accepted hop invite from %s [via %s]", tostring(sender or "helper"), viaSystem))
                end
            else
                -- Non-hop invite: leave untouched so normal social invites behave naturally
            end
        elseif event == "GROUP_JOINED" then
            if isAwaitingHop then
                awaitingLayerVerification = true
            end
        elseif event == "GROUP_LEFT" then
            isDepartureDeferred = false
            Coordination.ResetHopState()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if Coordination.IsDepartureDeferred() then
                local buffer = (C and C.TIMERS and C.TIMERS.COMBAT_DEFERRAL_GRACE) or 2.0
                if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
                    _G.C_Timer.After(buffer, function()
                        local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                                         or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
                        if not inCombat and Coordination.IsDepartureDeferred() then
                            Coordination.DepartGroup()
                        end
                    end)
                else
                    Coordination.DepartGroup()
                end
            end
        end
    end)
end

-- Layer change listener: auto-depart group once target layer confirmed
if type(ULO.RegisterCallback) == "function" then
    ULO.RegisterCallback("OnLayerChanged", function(newLayer)
        if awaitingLayerVerification and (not awaitingHopTarget or newLayer == awaitingHopTarget) then
            if type(ULO.LogAction) == "function" then
                ULO.LogAction("Group", "Verified Layer " .. tostring(newLayer) .. " -> leaving helper party")
            end
            local ok, reason = Coordination.DepartGroup()
            if ok then
                Coordination.ResetHopState()
            else
                -- Combat deferral: cancel safety timeout and clear hop flags, but preserve deferral state
                isAwaitingHop = false
                awaitingHopTarget = nil
                awaitingLayerVerification = false
                if hopTimeoutTimer and type(hopTimeoutTimer.Cancel) == "function" then
                    pcall(hopTimeoutTimer.Cancel, hopTimeoutTimer)
                    hopTimeoutTimer = nil
                end
            end
        end
    end)
end

-- Coordination Subsystem Lifecycle
function Coordination:Initialize()
    if type(_G.ULODB) == "table" and _G.ULODB.autoInvite ~= nil then
        Coordination.ToggleAutoInvite(_G.ULODB.autoInvite == true)
    elseif type(_G.ULO_CONFIG) == "table" and type(_G.ULO_CONFIG.autoInvite) == "table" and _G.ULO_CONFIG.autoInvite.enabled ~= nil then
        Coordination.ToggleAutoInvite(_G.ULO_CONFIG.autoInvite.enabled == true)
    end
end

function Coordination:Enable()
end
Coordination.OnPlayerLogin = Coordination.Enable

function Coordination:OnLogout()
end

-- Subsystem Registration
if ULO.RegisterSubsystem then
    ULO.RegisterSubsystem("Coordination", ULO.Coordination)
end
