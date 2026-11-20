-- Overlord LayerJumper interoperability. Never commandeer PvP recruitment,
-- volunteer preferences, request handlers, or native shard state.
local _, addonTable = ...
local ULO = _G.ULO or addonTable or {}
ULO.Interop = ULO.Interop or {}
local O = {}
ULO.Interop.Overlord = O
local Compat = ULO.Compat
local PREFIX = "OverlordLJ"
local failedRequests = {}
local nativeSession
O.lastWhisperedPeers = {}

local function Now() return type(_G.GetTime) == "function" and _G.GetTime() or 0 end
local function Native() return type(_G.Overlord) == "table" and _G.Overlord.LayerJumper or nil end
local function Enabled() return not ULO.IsTrackEnabled or ULO.IsTrackEnabled("overlord") end
local function SafeCall(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then return nil end
    local ok, value = pcall(obj[method], obj, ...)
    return ok and value or nil
end

-- Kept for Settings callers; the user's Overlord helper preference is untouched.
function O.SyncHelpMode() return Native() ~= nil end
function O.Init()
    if _G.C_ChatInfo and _G.C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif _G.RegisterAddonMessagePrefix then pcall(_G.RegisterAddonMessagePrefix, PREFIX) end
end
O.Init()

local function Whisper(target, payload)
    if not Enabled() or Compat.IsSelfName(target) then return false end
    if _G.C_ChatInfo and _G.C_ChatInfo.SendAddonMessage then
        return pcall(_G.C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", target)
    elseif _G.SendAddonMessage then return pcall(_G.SendAddonMessage, PREFIX, payload, "WHISPER", target) end
    return false
end

function O.SendHopRequest(target, origin, reqId)
    if Compat.IsSelfName(target) or not Enabled() then return nil end
    reqId = reqId or 100
    if not Whisper(target, string.format("R:2:%s:%s", tostring(reqId), tostring(origin or "-"))) then return nil end
    O.lastWhisperedPeers[string.lower(string.match(target, "^[^-]+") or target)] = true
    return reqId
end
function O.SendDecline(target, reqId, reason) return Whisper(target, "N:" .. tostring(reqId) .. ":" .. reason) end
function O.GetRequestFailureReason(reqId)
    if reqId == nil then return nil end
    return failedRequests[tostring(reqId)]
end

function O.ProcessMessage(msg, sender)
    if not Enabled() or Compat.IsSelfName(sender) or not Compat.SafeString(msg) then return false end
    -- The installed native addon owns its incoming requests and bookkeeping.
    if Native() and type(Native().OnRequest) == "function" then return false end
    local declineId, decline = string.match(msg, "^N:([%w_]+):([%w_]+)%s*$")
    if declineId then failedRequests[declineId] = decline; return true end
    local reqId, originText = string.match(msg, "^R:2:([%w_]+):([%d%-]+)%s*$")
    if not reqId then return false end
    local origin = tonumber(originText)
    if originText ~= "-" and (not origin or origin <= 0) then return false end
    local coord = ULO.Coordination
    local reason
    if not coord.IsAutoInviteEnabled() then reason = "off"
    elseif _G.IsInInstance and _G.IsInInstance() then reason = "instance"
    elseif (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) or (_G.InCombatLockdown and _G.InCombatLockdown()) then reason = "combat"
    elseif (_G.GetNumGroupMembers and _G.GetNumGroupMembers() or 0) >= ((_G.IsInRaid and _G.IsInRaid()) and 40 or 5) then reason = "full"
    elseif not ULO.Intelligence.RequestZoneAllowed(sender) then reason = "zone"
    elseif origin and (origin == ULO.Detection.GetCurrentLayer() or origin == ULO.Detection.GetCurrentServerId()) then reason = "same"
    elseif coord.IsPlayerInInviteCache(sender) then reason = "busy" end
    if reason then O.SendDecline(sender, reqId, reason); return true end
    local invited = Compat.InviteUnit(sender)
    if invited then coord.EnrollPlayerInCache(sender, 300) end
    return true
end

local function Candidates(targetLayer)
    local lj = Native()
    local rows = SafeCall(lj, "KnownPlayers") or {}
    if type(rows) ~= "table" then rows = {} end
    local mine = tonumber(SafeCall(lj, "MyLayer"))
    local ownIndex = ULO.Detection.GetCurrentLayer()
    local out, helpers = {}, 0
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.name) == "string" and row.helper and not Compat.IsSelfName(row.name) then
            helpers = helpers + 1
            local meta = ULO.Intelligence.GetPeer(row.name)
            if meta and Now() - meta.updatedAt > ULO.Intelligence.PEER_TTL then meta = nil end
            local zoneStatus = ULO.Intelligence.PeerZoneStatus(row.name)
            -- Native volunteers predate zone metadata. Prefer verified scope;
            -- legacy unknown scope requires the bounded post-join leader check.
            local zoneOK = zoneStatus ~= "zone_mismatch" and zoneStatus ~= "zone_unknown"
            local nativeLayer = tonumber(row.layer)
            local different = mine and nativeLayer and nativeLayer ~= mine
            if not mine then different = meta and meta.layer and ownIndex and meta.layer ~= ownIndex end
            local matches = not targetLayer or (meta and meta.layer == tonumber(targetLayer))
            if meta and meta.layer == ownIndex then different = false end
            if nativeLayer and nativeLayer > 0 and zoneOK and different and matches and not SafeCall(lj, "IsEnemy", row.name) then
                out[#out + 1] = { native = row, zoneStatus = zoneStatus }
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.zoneStatus == "same_zone") ~= (b.zoneStatus == "same_zone") then return a.zoneStatus == "same_zone" end
        return a.native.name < b.native.name
    end)
    return out, #rows, helpers
end
function O.GetPeerSummary()
    local _, total, helpers = Candidates(nil)
    return total, helpers, 0 -- GroupFinder/directory presence is not volunteer consent.
end

function O.CancelHopRequest()
    local session = nativeSession
    nativeSession = nil
    if session and session.lj.hop == session.hop then SafeCall(session.lj, "Cancel") end
end

function O.BroadcastHopRequest(targetLayer)
    if not Enabled() then return 0 end
    local lj = Native()
    if not lj or type(lj.Join) ~= "function" or type(lj.IsActive) ~= "function" or SafeCall(lj, "IsActive") then return 0 end
    local candidates = Candidates(targetLayer)
    local selected = candidates[1]
    if not selected then return 0 end
    local candidate = selected.native
    -- This is a native shard identifier; never substitute the UI's layer index.
    local ok, started = pcall(lj.Join, lj, candidate.name, tonumber(candidate.layer), false)
    if not ok or not started or not lj.hop then return 0 end
    local session = { lj = lj, hop = lj.hop, origin = ULO.Detection.GetCurrentLayer(), target = tonumber(targetLayer),
        originZone = ULO.Intelligence.GetZone(), startedAt = Now() }
    nativeSession = session
    local bridge = {}
    local function CurrentName()
        return session.hop.current and session.hop.current.name or candidate.name
    end
    local function Finish()
        if nativeSession ~= session then return end
        nativeSession = nil
        ULO.Coordination.CompleteExternalHop(session.proof ~= nil and session.proof ~= session.origin
            and (not session.target or session.proof == session.target) and session.zoneOK == true,
            "Native Overlord operation ended; transfer was not confirmed by ULO")
    end
    function bridge.State() return lj.state or "idle" end
    function bridge.Cancel()
        O.CancelHopRequest()
    end
    function bridge.RecordLayerProof(layer)
        if session.joined and tonumber(layer) then session.proof = tonumber(layer) end
    end
    function bridge.OnGroupJoined()
        session.joined = true
        session.joinedAt = session.joinedAt or Now()
        local allowed, reason = ULO.Intelligence.ValidateHopGroup(CurrentName())
        if allowed then session.zoneOK = true
        elseif allowed == false then
            session.zoneOK = false
            O.CancelHopRequest()
            ULO.Coordination.CompleteExternalHop(false, "Native hop rejected: " .. tostring(reason))
        end
    end
    function bridge.OnGroupLeft() Finish() end
    function bridge.OnZoneChanged(zone)
        if ULO.Intelligence.RequiresZone() and zone ~= session.originZone then
            O.CancelHopRequest()
            ULO.Coordination.CompleteExternalHop(false, "Native hop cancelled: requester zone changed")
        end
    end
    ULO.Coordination.DelegateHop(bridge)
    local function Poll()
        if nativeSession ~= session then return end
        if lj.hop ~= nil and lj.hop ~= session.hop then Finish(); return end
        if session.joined and SafeCall(lj, "IsActive") then
            local allowed, reason = ULO.Intelligence.ValidateHopGroup(CurrentName())
            if allowed then session.zoneOK = true
            else
                session.zoneOK = false
                if allowed == false or Now() - session.joinedAt >= 6 then
                    O.CancelHopRequest()
                    ULO.Coordination.CompleteExternalHop(false, "Native hop rejected: " .. tostring(reason))
                    return
                end
            end
        end
        if not SafeCall(lj, "IsActive") then Finish(); return end
        if Now() - session.startedAt >= 180 then
            O.CancelHopRequest()
            ULO.Coordination.CompleteExternalHop(false, "Native hop timed out")
            return
        end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.25, Poll) end
    end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.25, Poll) end
    if ULO.LogAction then ULO.LogAction("OverlordLJ", "Native LayerJumper requested " .. candidate.name
        .. (selected.zoneStatus == "unverified" and " (zone unverified; checking after join)" or "")) end
    return 1
end

if type(_G.CreateFrame) == "function" then
    local frame = _G.CreateFrame("Frame", "ULO_OverlordEventFrame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if prefix == PREFIX then O.ProcessMessage(msg, sender) end
    end)
end
