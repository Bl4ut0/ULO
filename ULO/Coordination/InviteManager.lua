-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Coordination/InviteManager.lua
-- Description: Automated party invite coordination, 300s player throttle cache,
--              180s pending invite expiration, LFG protection, party cap guards,
--              and audio chime suppression.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Coordination = ULO.Coordination or {}
local Coordination = ULO.Coordination
local C = ULO.Constants
local Compat = ULO.Compat

local autoInviteEnabled = true
local playerInviteCache = {}  -- [sender] = expireTimestamp (300s throttle)
local pendingInviteSlots = {} -- [sender] = expireTimestamp (180s expiration)

--- Toggles or sets automated party invite processing.
-- @param enable boolean|nil: Explicit enable state or nil to toggle
-- @return boolean: Updated auto-invite state
function Coordination.ToggleAutoInvite(enable)
    if enable == nil then
        autoInviteEnabled = not autoInviteEnabled
    else
        autoInviteEnabled = (enable == true)
    end
    if type(_G.ULODB) == "table" then
        _G.ULODB.autoInvite = autoInviteEnabled
    end
    return autoInviteEnabled
end

--- Returns whether automated party invites are currently active.
-- @return boolean
function Coordination.IsAutoInviteEnabled()
    return autoInviteEnabled
end

--- Enrolls a player in the invite throttle and pending slot caches.
-- @param sender string: Player name or Name-Realm
-- @param duration number|nil: Custom throttle duration in seconds (defaults to 300)
function Coordination.EnrollPlayerInCache(sender, duration)
    if not sender or sender == "" then return end
    local key = type(sender) == "string" and string.lower(sender) or tostring(sender)
    if Compat and Compat.SafeTrim then
        key = Compat.SafeTrim(key) or key
    end
    duration = tonumber(duration) or (C and C.TIMERS and C.TIMERS.INVITE_THROTTLE) or 300
    local pendingDuration = (C and C.TIMERS and C.TIMERS.INVITE_TIMEOUT) or 180
    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    playerInviteCache[key] = now + duration
    pendingInviteSlots[key] = now + pendingDuration
end

--- Checks whether a player is currently in the 300s invite throttle cache.
-- @param sender string: Player name or Name-Realm
-- @return boolean: true if cached and unexpired
function Coordination.IsPlayerInInviteCache(sender)
    if not sender or sender == "" then return false end
    local key = type(sender) == "string" and string.lower(sender) or tostring(sender)
    if Compat and Compat.SafeTrim then
        key = Compat.SafeTrim(key) or key
    end
    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    local exp = playerInviteCache[key]
    return (exp ~= nil) and (exp > now)
end

--- Returns the number of active, unexpired pending invite slots (180s window).
-- @return number: Active pending invite count
function Coordination.GetPendingInviteCount()
    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    local count = 0
    for sender, exp in pairs(pendingInviteSlots) do
        if exp > now then
            count = count + 1
        else
            pendingInviteSlots[sender] = nil
        end
    end
    return count
end

--- Clears all cached players and pending invite slots.
function Coordination.ClearInviteCache()
    playerInviteCache = {}
    pendingInviteSlots = {}
end

--- Evaluates an incoming whisper and dispatches a party invitation if eligible.
-- @param sender string: Whispering player name
-- @param msg string: Whisper text
-- @param source string|nil: Originating system tag (defaults to "Direct Whisper")
-- @return boolean: true if invite successfully dispatched
-- @return string|nil: Error or rejection reason
function Coordination.HandleWhisper(sender, msg, source)
    source = source or "Direct Whisper"
    -- Guard 1: Auto-invite globally disabled
    if not autoInviteEnabled then
        return false, "disabled"
    end

    -- Guard 2: Layer refresh countdown active
    if ULO.Monitor and type(ULO.Monitor.IsRefreshPending) == "function" and ULO.Monitor.IsRefreshPending() then
        return false, "refresh_pending"
    end

    -- Guard 3: LFG / Dungeon Finder queue guard
    if type(_G.IsInLFGQueue) == "function" and _G.IsInLFGQueue() then
        return false, "lfg_queued"
    end

    -- Guard 4: Group capacity cap (Party max 5, Raid max 40)
    local numMembers = (type(_G.GetNumGroupMembers) == "function" and _G.GetNumGroupMembers())
                       or (type(_G.GetNumPartyMembers) == "function" and _G.GetNumPartyMembers())
                       or 0
    local inRaid = (type(_G.IsInRaid) == "function" and _G.IsInRaid())
    local maxMembers = inRaid and (((C and C.GROUP and C.GROUP.MAX_RAID_MEMBERS) or 39) + 1)
                              or (((C and C.GROUP and C.GROUP.MAX_PARTY_MEMBERS) or 4) + 1)
    if numMembers >= maxMembers then
        return false, "party_full"
    end

    -- Guard 5: Player throttle cache (300s window)
    if Coordination.IsPlayerInInviteCache(sender) then
        return false, "cached"
    end

    -- Guard 6: Keyword & target layer recognition
    local match, targetLayerOrReason, isInverted, r1, r2 = Coordination.MatchKeywords(msg)
    if not match then
        return false, targetLayerOrReason or "no_match"
    end

    if ULO.Detection and type(ULO.Detection.GetCurrentLayer) == "function" then
        local myLayer = ULO.Detection.GetCurrentLayer()
        if myLayer ~= nil then
            if type(targetLayerOrReason) == "number" and targetLayerOrReason ~= myLayer then
                return false, "layer_mismatch"
            end
            if isInverted and r1 == myLayer then
                return false, "layer_excluded"
            end
            if not isInverted and r1 and r2 and (myLayer < r1 or myLayer > r2) then
                return false, "layer_out_of_range"
            end
        end
    end

    -- Sound Muting: Suppress client invite audio chimes (567490, 567451)
    if type(_G.MuteSoundFile) == "function" then
        pcall(_G.MuteSoundFile, 567490)
        pcall(_G.MuteSoundFile, 567451)
    end

    -- Dispatch Party Invite via Compatibility Layer
    local ok, err = false, nil
    if Compat and type(Compat.InviteUnit) == "function" then
        ok, err = Compat.InviteUnit(sender)
    elseif type(_G.InviteUnit) == "function" then
        ok, err = pcall(_G.InviteUnit, sender)
    end

    -- Sound Unmuting: Restore client audio
    if type(_G.UnmuteSoundFile) == "function" then
        pcall(_G.UnmuteSoundFile, 567490)
        pcall(_G.UnmuteSoundFile, 567451)
    end

    if ok then
        Coordination.EnrollPlayerInCache(sender, 300)
        if type(ULO.LogAction) == "function" then
            ULO.LogAction(source, string.format("Auto-invited %s (%s)", tostring(sender), tostring(msg)))
        end
        return true
    end

    return false, err
end

-- Event Listener: Inbound whisper frame
if type(_G.CreateFrame) == "function" then
    local whisperFrame = _G.CreateFrame("Frame", "ULO_InviteManagerFrame")
    whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
    whisperFrame:SetScript("OnEvent", function(self, event, msg, sender)
        if event ~= "CHAT_MSG_WHISPER" then return end
        local src = "Direct Whisper"
        if type(msg) == "string" and (not Compat or not Compat.SafeString or Compat.SafeString(msg)) then
            local lowerMsg = string.lower(msg)
            if string.find(lowerMsg, "^%s*%[autolayer%]") or string.find(lowerMsg, "^%s*auto%s*layer") then
                src = "AutoLayer"
                if (_G.ULODB and (_G.ULODB.autoLayerEnabled == false or _G.ULODB.uloOnlyMode == true))
                   or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.autoLayerEnabled == false) then
                    if type(ULO.LogAction) == "function" then
                        ULO.LogAction("Blocked", "Ignored AutoLayer whisper from " .. tostring(sender))
                    end
                    return
                end
            end
        end
        Coordination.HandleWhisper(sender, msg, src)
    end)
end
