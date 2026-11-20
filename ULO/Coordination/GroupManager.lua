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
local hopFallbackTimer = nil
local hopGeneration = 0
local hopOriginLayer = nil
local hopChatUntil = 0
local hopOriginZone = nil
local hopHelper = nil
local hopZoneValidated = false
local hopLayerProof = nil
local hopSession = 0
local externalOwner = nil

function Coordination.DelegateHop(owner)
    externalOwner = owner
    if hopTimeoutTimer and hopTimeoutTimer.Cancel then hopTimeoutTimer:Cancel() end
    if hopFallbackTimer and hopFallbackTimer.Cancel then hopFallbackTimer:Cancel() end
    hopTimeoutTimer, hopFallbackTimer = nil, nil
end

function Coordination.CompleteExternalHop(verified, reason)
    externalOwner = nil
    if ULO.LogAction then ULO.LogAction("Group", verified and "Verified native Overlord layer transfer" or (reason or "Native Overlord hop ended without a verified transfer")) end
    Coordination.ResetHopState()
end

local function Now()
    return (type(_G.GetTime) == "function" and _G.GetTime()) or 0
end

local function StopHopRequests()
    hopGeneration = hopGeneration + 1
    if hopFallbackTimer and hopFallbackTimer.Cancel then hopFallbackTimer:Cancel() end
    hopFallbackTimer = nil
    local ov = ULO.Interop and ULO.Interop.Overlord
    if ov and ov.CancelHopRequest then ov.CancelHopRequest() end
end

-- This filter only covers invitation notices during our own bounded hop window.
-- It does not hide arbitrary system errors, loot changes, or social invites later.
local function HopSystemFilter(_, _, msg)
    if Now() >= hopChatUntil then return false end
    local safe = Compat and Compat.SafeString and Compat.SafeString(msg)
    if not safe then return false end
    local templates = {
        _G.ERR_INVITED_TO_GROUP_S or "",
        _G.ERR_INVITED_TO_GROUP_SS or "",
        -- Exact English variants supplied in the owner report; some clients use
        -- different native global names for these messages.
        "%s has invited you to join a group.",
        "%s invited you to a group, but you could not accept because you are already in a group.",
    }
    for _, template in ipairs(templates) do
        template = Compat.SafeString(template)
        if template then
            local pattern = template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", ".+")
            if string.match(safe, "^" .. pattern .. "$") then return true end
        end
    end
    return false
end

local filterInstalled = false
local function InstallHopSystemFilter()
    if filterInstalled then return end
    local addFilter = _G.ChatFrame_AddMessageEventFilter
        or (type(_G.ChatFrameUtil) == "table" and _G.ChatFrameUtil.AddMessageEventFilter)
    if type(addFilter) == "function" then
        filterInstalled = pcall(addFilter, "CHAT_MSG_SYSTEM", HopSystemFilter)
    end
end
InstallHopSystemFilter()

--- Initiates an active layer hop request for a target layer.
-- @param targetLayer number: Destination layer index
-- @param preferredProtocol string|nil: Preferred protocol ("AutoLayer" or "Overlord")
-- @return boolean: true if hop request armed successfully
-- @return string|nil: Status code ("ok" or error code like "cooldown")
function Coordination.RequestLayerHop(targetLayer, preferredProtocol)
    local originZone = ULO.Intelligence.GetZone()
    if ULO.Intelligence.RequiresZone() and not originZone then return false, "zone_unknown" end
    local origin = ULO.Detection and ULO.Detection.GetCurrentLayer and tonumber(ULO.Detection.GetCurrentLayer())
    local target = tonumber(targetLayer)
    if target and target == origin then return false, "already_on_layer" end
    if targetLayer ~= nil and (not target or target < 1 or target % 1 ~= 0
       or target > ((C and C.DETECTION and C.DETECTION.MAX_LAYER_NUMBER) or 30)) then
        return false, "invalid_layer"
    end
    if not target and (not origin or origin <= 0) then return false, "layer_unknown" end
    if isAwaitingHop or awaitingLayerVerification or isDepartureDeferred then return false, "hop_pending" end
    if (type(_G.IsInGroup) == "function" and _G.IsInGroup()) or (type(_G.IsInRaid) == "function" and _G.IsInRaid()) then
        return false, "already_grouped"
    end
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
    hopOriginLayer = origin
    hopOriginZone, hopHelper, hopLayerProof = originZone, nil, nil
    hopZoneValidated = not ULO.Intelligence.RequiresZone()
    hopSession = hopSession + 1
    hopChatUntil = now + HOP_VERIFY_TIMEOUT
    StopHopRequests()
    local generation = hopGeneration

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

    local interop = ULO.Interop or {}
    local function StillRequesting()
        return generation == hopGeneration and Coordination.IsAwaitingHop()
            and not (type(_G.IsInGroup) == "function" and _G.IsInGroup())
    end
    local function PublicFallback()
        if not StillRequesting() then return false end
        if interop.AutoLayer and interop.AutoLayer.FormatBroadcastMessage then
            local ok, _, sent = pcall(interop.AutoLayer.FormatBroadcastMessage, target)
            if ok and tonumber(sent) and sent > 0 then return true end
        end
        if interop.Guild and interop.Guild.BroadcastHopRequest then
            local ok, sent = pcall(interop.Guild.BroadcastHopRequest, target, false)
            if ok and tonumber(sent) and sent > 0 then return true end
        end
        Coordination.CancelHopRequest("no_helpers")
        return false
    end
    local function TryOverlord()
        if not StillRequesting() then return false end
        if interop.Overlord and interop.Overlord.BroadcastHopRequest then
            local ok, sent = pcall(interop.Overlord.BroadcastHopRequest, target, PublicFallback)
            if ok and tonumber(sent) and sent > 0 then return true end
        end
        return PublicFallback()
    end
    local sentDirect = false
    if preferredProtocol == "AutoLayer" then
        PublicFallback()
    elseif preferredProtocol == "Overlord" then
        TryOverlord()
    else
        if interop.Guild and interop.Guild.BroadcastHopRequest then
            local ok, sent = pcall(interop.Guild.BroadcastHopRequest, target, true)
            sentDirect = ok and tonumber(sent) ~= nil and sent > 0
        end
        if sentDirect and type(_G.C_Timer) == "table" and type(_G.C_Timer.NewTimer) == "function" then
            hopFallbackTimer = _G.C_Timer.NewTimer(12, TryOverlord)
        elseif sentDirect and type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(12, TryOverlord)
        else
            TryOverlord()
        end
    end
    if not isAwaitingHop and not awaitingLayerVerification then return false, "no_helpers" end
    return true, "ok"
end

--- Cancels an active hop request, resets hop flags, and fires timeout callbacks.
-- @param reason string|nil: Cancellation reason code
function Coordination.CancelHopRequest(reason, keepGroup)
    local owner = externalOwner
    externalOwner = nil
    if owner and owner.Cancel then owner.Cancel(reason) end
    hopSession = hopSession + 1
    StopHopRequests()
    hopChatUntil = 0
    hopOriginLayer = nil
    local wasAwaitingVerification = awaitingLayerVerification
    isAwaitingHop = false
    awaitingHopTarget = nil
    awaitingLayerVerification = false
    if hopTimeoutTimer and type(hopTimeoutTimer.Cancel) == "function" then
        pcall(hopTimeoutTimer.Cancel, hopTimeoutTimer)
        hopTimeoutTimer = nil
    end

    -- Auto-depart helper group upon verification timeout expiration when in helper group
    if wasAwaitingVerification and not keepGroup then
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
    if externalOwner then return externalOwner.State() == "requesting" end
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
    if externalOwner then local state = externalOwner.State(); return state == "joining" or state == "verifying" end
    return awaitingLayerVerification
end

--- Completely resets hop coordination lifecycle state.
function Coordination.ResetHopState()
    externalOwner = nil
    hopSession = hopSession + 1
    hopHelper, hopLayerProof, hopOriginZone = nil, nil, nil
    hopZoneValidated = false
    StopHopRequests()
    if isAwaitingHop or awaitingLayerVerification then hopChatUntil = math.min(hopChatUntil, Now() + 2) end
    hopOriginLayer = nil
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

local function FinishVerifiedHop()
    if not awaitingLayerVerification or not hopZoneValidated or not hopLayerProof then return end
    local layer = hopLayerProof
    if (hopOriginLayer and layer == hopOriginLayer) or (awaitingHopTarget and layer ~= awaitingHopTarget) then return end
    local allowed = ULO.Intelligence.ValidateHopGroup(hopHelper)
    if not allowed then
        hopZoneValidated = false
        Coordination.CheckHopZone()
        return
    end
    if ULO.LogAction then ULO.LogAction("Group", "Verified Layer " .. layer .. " and helper zone; leaving helper party") end
    local ok = Coordination.DepartGroup()
    if ok then Coordination.ResetHopState()
    else
        isAwaitingHop, awaitingHopTarget, awaitingLayerVerification = false, nil, false
        if hopTimeoutTimer and hopTimeoutTimer.Cancel then hopTimeoutTimer:Cancel() end
        hopTimeoutTimer = nil
    end
end

function Coordination.CheckHopZone(attempt, session)
    attempt, session = attempt or 1, session or hopSession
    if session ~= hopSession or not awaitingLayerVerification then return end
    local allowed, reason = ULO.Intelligence.ValidateHopGroup(hopHelper)
    if allowed then hopZoneValidated = true; FinishVerifiedHop(); return end
    if allowed == false or attempt >= 4 then
        if ULO.LogAction then ULO.LogAction("Group", "Hop rejected: " .. tostring(reason)) end
        Coordination.CancelHopRequest(reason, reason == "foreign_group")
    elseif type(_G.C_Timer) == "table" and _G.C_Timer.After then
        _G.C_Timer.After(2, function() Coordination.CheckHopZone(attempt + 1, session) end)
    end
end

-- Event Listener: Group lifecycle management frame
if type(_G.CreateFrame) == "function" then
    local groupFrame = _G.CreateFrame("Frame", "ULO_GroupManagerFrame")
    groupFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    groupFrame:RegisterEvent("GROUP_JOINED")
    groupFrame:RegisterEvent("GROUP_LEFT")
    groupFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    groupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    groupFrame:SetScript("OnEvent", function(self, event, ...)
        if externalOwner and event ~= "PLAYER_ENTERING_WORLD" then
            if event == "GROUP_JOINED" and externalOwner.OnGroupJoined then externalOwner.OnGroupJoined() end
            if event == "GROUP_LEFT" and externalOwner.OnGroupLeft then externalOwner.OnGroupLeft() end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            InstallHopSystemFilter()
        elseif event == "PARTY_INVITE_REQUEST" then
            local sender = ...
            if Compat and Compat.IsSelfName and Compat.IsSelfName(sender) then return end
            if Coordination.IsAwaitingHop() and not awaitingLayerVerification
               and not (type(_G.IsInGroup) == "function" and _G.IsInGroup()) then
                local peer = ULO.Intelligence.GetPeer(sender)
                local fresh = peer and Now() - peer.updatedAt <= ULO.Intelligence.PEER_TTL
                if ULO.Intelligence.PeerZoneStatus(sender) == "zone_mismatch"
                   or (fresh and peer.layer and ((hopOriginLayer and peer.layer == hopOriginLayer)
                       or (awaitingHopTarget and peer.layer ~= awaitingHopTarget))) then
                    if ULO.LogAction then ULO.LogAction("Group", "Ignored hop invite from known incompatible helper " .. tostring(sender)) end
                    return
                end
                -- Latch before calling native acceptance: GROUP_JOINED may be synchronous.
                isAwaitingHop = false
                awaitingLayerVerification = true
                hopHelper = sender
                StopHopRequests()
                local accepted = false
                if Compat and type(Compat.AcceptGroup) == "function" then
                    accepted = Compat.AcceptGroup()
                elseif type(_G.AcceptGroup) == "function" then
                    accepted = pcall(_G.AcceptGroup)
                end
                if not accepted then
                    awaitingLayerVerification = false
                    Coordination.CancelHopRequest("accept_failed")
                    return
                end
                Coordination.CheckHopZone()
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
                isAwaitingHop = false
                awaitingLayerVerification = true
                StopHopRequests()
            end
            if awaitingLayerVerification then Coordination.CheckHopZone() end
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
        newLayer = tonumber(newLayer)
        if externalOwner then if externalOwner.RecordLayerProof then externalOwner.RecordLayerProof(newLayer) end; return end
        if awaitingLayerVerification and newLayer then hopLayerProof = newLayer; FinishVerifiedHop() end
    end)
    ULO.RegisterCallback("OnConfigChanged", function(key)
        if key == "requestTrack" and isAwaitingHop then Coordination.CancelHopRequest("settings_changed") end
    end)
    ULO.RegisterCallback("OnZoneChanged", function(zone)
        if externalOwner then
            if externalOwner.OnZoneChanged then externalOwner.OnZoneChanged(zone) end
            return
        end
        if not externalOwner and (isAwaitingHop or awaitingLayerVerification) and hopOriginZone and zone ~= hopOriginZone then
            local _, reason = ULO.Intelligence.ValidateHopGroup(hopHelper)
            Coordination.CancelHopRequest("zone_changed", reason == "foreign_group")
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
