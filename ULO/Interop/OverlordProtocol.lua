-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Interop/OverlordProtocol.lua
-- Description: Overlord hidden addon whisper wire protocol (OverlordLJ prefix),
--              request handling, decline responses, and peer-to-peer hopping.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Interop = ULO.Interop or {}
local Interop = ULO.Interop

Interop.Overlord = Interop.Overlord or {}
local Overlord = Interop.Overlord
local C = ULO.Constants
local Compat = ULO.Compat

local PREFIX = (C and C.OVERLORD and C.OVERLORD.PREFIX) or "OverlordLJ"
local failedRequests = {}
local activeHopQueue = nil
local HOP_CANDIDATE_TIMEOUT = 4.0
Overlord.lastWhisperedPeers = Overlord.lastWhisperedPeers or {}

--- Synchronizes Overlord LayerJumper HelpMode with ULO's configuration and wraps LJ:OnRequest
-- so Overlord does not reply "off" or double-invite when ULO is managing invites.
function Overlord.SyncHelpMode()
    local uloOnly = (_G.ULODB and _G.ULODB.uloOnlyMode == true)
    local disabled = (_G.ULODB and _G.ULODB.overlordEnabled == false)
                     or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.overlordEnabled == false)
    local autoInv = not ULO.Coordination
                    or type(ULO.Coordination.IsAutoInviteEnabled) ~= "function"
                    or ULO.Coordination.IsAutoInviteEnabled()
    local active = (not uloOnly) and (not disabled) and (autoInv == true)

    local lj = _G.Overlord and _G.Overlord.LayerJumper
    if lj then
        if type(lj.SetHelpMode) == "function" then
            pcall(lj.SetHelpMode, lj, active and "auto" or "off")
        end
        if type(lj.OnRequest) == "function" and not lj._uloHookedOnRequest then
            lj._uloOrigOnRequest = lj.OnRequest
            lj._uloHookedOnRequest = true
            lj.OnRequest = function(...)
                -- Handled centrally by ULO_OverlordEventFrame -> Overlord.ProcessMessage
                return
            end
        end
    end
end

--- Initializes and registers the OverlordLJ addon message prefix.
function Overlord.Init()
    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif type(_G.RegisterAddonMessagePrefix) == "function" then
        pcall(_G.RegisterAddonMessagePrefix, PREFIX)
    end
    Overlord.SyncHelpMode()
end
Overlord.Init()

if type(ULO.RegisterCallback) == "function" then
    ULO.RegisterCallback("OnLayerChanged", function(_, serverId)
        local sid = tonumber(serverId)
        if sid and sid > 0 and _G.Overlord and type(_G.Overlord.Shard) == "table" then
            _G.Overlord.Shard.currentShardID = sid
            _G.Overlord.Shard.lastUpdateAt = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
            local blocked = (_G.ULODB and (_G.ULODB.uloOnlyMode == true or _G.ULODB.overlordEnabled == false))
                            or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.overlordEnabled == false)
            if not blocked and _G.Overlord.Sync and type(_G.Overlord.Sync.SendToChannel) == "function" then
                pcall(_G.Overlord.Sync.SendToChannel, _G.Overlord.Sync, "SH", tostring(sid))
            end
        end
    end)
end

--- Processes an inbound Overlord wire message received over WHISPER.
-- @param msg any: Wire message content
-- @param sender string: Sender name or Name-Realm
-- @return boolean: true if message was recognized and handled
function Overlord.ProcessMessage(msg, sender)
    if msg == nil or type(msg) ~= "string" or msg == "" then
        return false
    end
    if Compat and Compat.SafeString and not Compat.SafeString(msg) then
        return false
    end

    -- Inbound Hop Request: R:2:<requestId>:<originLayer>
    local reqId, tLayer = string.match(msg, "^R:2:([%w_]+):([%d%-]+)%s*$")
    if reqId and tLayer then
        local layerNum = tonumber(tLayer)
        if tLayer ~= "-" and (not layerNum or layerNum <= 0) then
            return false
        end

        local function Decline(reason)
            if type(ULO.LogAction) == "function" then
                ULO.LogAction("Overlord", string.format("Declined %s (%s)", tostring(sender), tostring(reason)))
            end
            Overlord.SendDecline(sender, reqId, reason)
            return true
        end

        -- 1. Check if auto-invites are enabled
        local Coordination = ULO.Coordination
        if Coordination and type(Coordination.IsAutoInviteEnabled) == "function" then
            if not Coordination.IsAutoInviteEnabled() then
                return Decline("off")
            end
        end

        -- 2. Check if host is inside a dungeon or raid instance
        if type(_G.IsInInstance) == "function" then
            local inInstance = _G.IsInInstance()
            if inInstance then
                return Decline("instance")
            end
        end

        -- 3. Check if player is in combat
        local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                         or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
        if inCombat then
            return Decline("combat")
        end

        -- 4. Check if party/raid is full (capacity >= 5 for party, >= 40 for raid)
        local numMembers = (type(_G.GetNumGroupMembers) == "function" and _G.GetNumGroupMembers())
                           or (type(_G.GetNumPartyMembers) == "function" and _G.GetNumPartyMembers())
                           or 0
        local inRaid = (type(_G.IsInRaid) == "function" and _G.IsInRaid())
        local maxMembers = inRaid and 40 or 5
        if numMembers >= maxMembers then
            return Decline("full")
        end

        -- 5. Check if requester is already on the host's layer/shard
        if layerNum then
            local Detection = ULO.Detection
            local myLayer = (Detection and type(Detection.GetCurrentLayer) == "function" and Detection.GetCurrentLayer())
            local myServerId = (Detection and type(Detection.GetCurrentServerId) == "function" and Detection.GetCurrentServerId())
            if (myLayer and myLayer == layerNum) or (myServerId and myServerId == layerNum) then
                return Decline("same")
            end
        end

        -- 6. Eligible: Dispatch party invitation
        local inviteOk = false
        if Compat and type(Compat.InviteUnit) == "function" then
            inviteOk = Compat.InviteUnit(sender)
        elseif type(_G.InviteUnit) == "function" then
            inviteOk = pcall(_G.InviteUnit, sender)
        end

        if inviteOk and Coordination and type(Coordination.EnrollPlayerInCache) == "function" then
            Coordination.EnrollPlayerInCache(sender, 300)
        end
        if type(ULO.LogAction) == "function" then
            ULO.LogAction("Overlord", string.format("Rx OverlordLJ req from %s -> %s", tostring(sender), inviteOk and "Invited" or "Invite failed"))
        end

        return true
    end

    -- Inbound Decline: N:<requestId>:<reason>
    local dReqId, reason = string.match(msg, "^N:([%w_]+):([%w_]+)%s*$")
    if dReqId and reason then
        failedRequests[dReqId] = reason
        local numId = tonumber(dReqId)
        if numId then
            failedRequests[numId] = reason
        end
        if type(ULO.LogAction) == "function" then
            ULO.LogAction("Overlord", string.format("Peer %s declined (%s): %s", tostring(sender), tostring(dReqId), tostring(reason)))
        end
        if activeHopQueue and activeHopQueue.activeReqId == tostring(dReqId) then
            Overlord.AdvanceHopCandidate(reason)
        end
        return true
    end

    return false
end

--- Dispatches an outbound layer hop request over OverlordLJ WHISPER.
-- @param targetPlayer string: Target helper player name
-- @param targetLayer number|string|nil: Destination layer index, or '-'
-- @param reqId string|number|nil: Session request token
-- @return string|number: The dispatched requestId
function Overlord.SendHopRequest(targetPlayer, targetLayer, reqId)
    reqId = reqId or 100
    local layerStr = (targetLayer ~= nil and targetLayer ~= "") and tostring(targetLayer) or "-"
    local payload = string.format("R:2:%s:%s", tostring(reqId), layerStr)

    if type(targetPlayer) == "string" and targetPlayer ~= "" then
        local short = string.lower(string.match(targetPlayer, "^([^%-]+)") or targetPlayer)
        Overlord.lastWhisperedPeers[short] = true
    end

    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendAddonMessage) == "function" then
        pcall(_G.C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", targetPlayer)
    elseif type(_G.SendAddonMessage) == "function" then
        pcall(_G.SendAddonMessage, PREFIX, payload, "WHISPER", targetPlayer)
    end
    return reqId
end

local function ShortKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    if string.sub(name, 1, 5) == "BNet-" or string.sub(name, 1, 7) == "Bridge-" then
        return nil
    end
    local short = string.match(name, "^([^%-]+)") or name
    short = string.match(short, "^%s*(.-)%s*$") or short
    if short == "" then return nil end
    return string.lower(short)
end

local function IsSameLayerOrShard(peerLayer, myLayer, myServerId, ovLayer)
    if not peerLayer then return false end
    return (myLayer and peerLayer == myLayer)
        or (myServerId and peerLayer == myServerId)
        or (ovLayer and peerLayer == ovLayer)
end

local function IsPeerEnemy(lj, name, rowEnemy)
    if rowEnemy == true then return true end
    if lj and type(lj.IsEnemy) == "function" then
        local okE, res = pcall(lj.IsEnemy, lj, name)
        if okE and res then return true end
    end
    return false
end

--- Collects categorized Overlord peer candidates across KnownPlayers, knownHelpers, and directory contacts.
-- @param targetLayer number|nil: Desired destination layer, or nil for any different layer
-- @return table: Struct containing buckets and counts
local function CollectOverlordPeers(targetLayer)
    local result = {
        shardHelpers = {},
        knownHelpers = {},
        shardOthers = {},
        dirContacts = {},
        shardCount = 0,
        helperCount = 0,
        dirCount = 0,
        myLayer = ULO.Detection and type(ULO.Detection.GetCurrentLayer) == "function" and ULO.Detection.GetCurrentLayer() or nil,
        myServerId = ULO.Detection and type(ULO.Detection.GetCurrentServerId) == "function" and ULO.Detection.GetCurrentServerId() or nil,
        ovLayer = nil,
    }

    local ov = _G.Overlord
    if type(ov) ~= "table" then return result end

    local lj = ov.LayerJumper
    local shard = ov.Shard
    local gf = ov.GroupFinder
    local dir = ov.ChannelDirectory

    if lj and type(lj.MyLayer) == "function" then
        local okOv, ovId = pcall(lj.MyLayer, lj)
        if okOv then result.ovLayer = tonumber(ovId) end
    end

    local desiredLayer = tonumber(targetLayer)
    local selfKey = ShortKey(type(_G.UnitName) == "function" and _G.UnitName("player") or nil)
    local seen = {}
    if selfKey then seen[selfKey] = true end

    local function TryEligibility(peerLayer)
        if desiredLayer then
            return peerLayer == desiredLayer
        end
        return not IsSameLayerOrShard(peerLayer, result.myLayer, result.myServerId, result.ovLayer)
    end

    -- 1. Overlord.LayerJumper:KnownPlayers() (shard cache)
    if lj and type(lj.KnownPlayers) == "function" then
        local ok, peers = pcall(lj.KnownPlayers, lj)
        if ok and type(peers) == "table" then
            result.shardCount = #peers
            for _, row in ipairs(peers) do
                if type(row) == "table" and type(row.name) == "string" then
                    local k = ShortKey(row.name)
                    if k and not seen[k] then
                        seen[k] = true
                        if not IsPeerEnemy(lj, row.name, row.enemy) then
                            local peerLayer = tonumber(row.layer)
                            if TryEligibility(peerLayer) then
                                if row.helper then
                                    result.helperCount = result.helperCount + 1
                                    table.insert(result.shardHelpers, row)
                                else
                                    table.insert(result.shardOthers, row)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0

    -- 2. Overlord.Shard.knownHelpers (~h presence flag without requiring front-zone shard)
    if type(shard) == "table" and type(shard.knownHelpers) == "table" then
        for name, untilAt in pairs(shard.knownHelpers) do
            if type(name) == "string" and (tonumber(untilAt) or 0) > now then
                local k = ShortKey(name)
                if k and not seen[k] then
                    seen[k] = true
                    if not IsPeerEnemy(lj, name, false) then
                        local peerLayer = type(shard.knownShards) == "table" and tonumber(shard.knownShards[name]) or nil
                        local okLayer = desiredLayer and (peerLayer == desiredLayer)
                                     or (not desiredLayer and not IsSameLayerOrShard(peerLayer, result.myLayer, result.myServerId, result.ovLayer))
                        if okLayer then
                            result.helperCount = result.helperCount + 1
                            table.insert(result.knownHelpers, { name = name, layer = peerLayer, helper = true })
                        end
                    end
                end
            end
        end
    end

    -- 3. GroupFinder:Contacts(), ChannelDirectory.partners, ChannelDirectory.names
    local function AddDirCandidate(name)
        if type(name) ~= "string" then return end
        local k = ShortKey(name)
        if not k or seen[k] then return end
        seen[k] = true
        if IsPeerEnemy(lj, name, false) then return end
        local peerLayer = (type(shard) == "table" and type(shard.knownShards) == "table") and tonumber(shard.knownShards[name]) or nil
        if IsSameLayerOrShard(peerLayer, result.myLayer, result.myServerId, result.ovLayer) then
            return
        end
        result.dirCount = result.dirCount + 1
        if not desiredLayer then
            table.insert(result.dirContacts, { name = name, layer = peerLayer })
        end
    end

    if gf and type(gf.Contacts) == "function" then
        local okC, contacts = pcall(gf.Contacts, gf)
        if okC and type(contacts) == "table" then
            for _, name in ipairs(contacts) do
                AddDirCandidate(name)
            end
        end
    end
    if type(dir) == "table" then
        if type(dir.partners) == "table" then
            for k, row in pairs(dir.partners) do
                local name = (type(row) == "table" and row.name) or (type(row) == "string" and row) or k
                AddDirCandidate(name)
            end
        end
        if type(dir.names) == "table" then
            for _, name in ipairs(dir.names) do
                AddDirCandidate(name)
                if result.dirCount >= 50 then break end
            end
        end
    end

    return result
end

--- Returns live Overlord peer counts across shard cache, helpers, and channel directory.
-- @return number, number, number: shardPeersCount, helperCount, dirContactsCount
function Overlord.GetPeerSummary()
    local data = CollectOverlordPeers(nil)
    return data.shardCount, data.helperCount, data.dirCount
end

--- Advances sequential OverlordLJ hop whispers one peer at a time.
-- @param reason string|nil: Trigger reason ("start", decline code, or "timeout")
-- @return boolean: true if another candidate whisper was dispatched
function Overlord.AdvanceHopCandidate(reason)
    local queue = activeHopQueue
    if not queue then
        return false
    end

    if queue.enforceAwaiting and ULO.Coordination and type(ULO.Coordination.IsAwaitingHop) == "function" then
        if not ULO.Coordination.IsAwaitingHop() then
            activeHopQueue = nil
            return false
        end
    end

    if (type(_G.IsInGroup) == "function" and _G.IsInGroup()) or (type(_G.IsInRaid) == "function" and _G.IsInRaid()) then
        activeHopQueue = nil
        return false
    end

    queue.index = queue.index + 1
    local row = queue.candidates[queue.index]
    if not row then
        activeHopQueue = nil
        return false
    end

    local reqId = string.format("%x%d", queue.baseTime % 65535, queue.index)
    local reqKey = tostring(reqId)
    queue.activeReqId = reqKey
    Overlord.SendHopRequest(row.name, queue.originTag, reqId)

    if type(ULO.LogAction) == "function" then
        local progress = string.format("(%d/%d)", queue.index, #queue.candidates)
        if row.layer then
            ULO.LogAction("OverlordLJ", string.format("Whispered %s (Shard #%s) %s", tostring(row.name), tostring(row.layer), progress))
        else
            ULO.LogAction("OverlordLJ", string.format("Whispered %s (Overlord peer) %s", tostring(row.name), progress))
        end
    end

    if queue.index < #queue.candidates and type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(HOP_CANDIDATE_TIMEOUT, function()
            if activeHopQueue == queue and activeHopQueue.activeReqId == reqKey then
                Overlord.AdvanceHopCandidate("timeout")
            end
        end)
    end

    return true
end

--- Broadcasts OverlordLJ hop whispers sequentially (1 peer at a time, up to 4 candidates max).
-- @param targetLayer number|nil: Desired destination layer, or nil for any different layer
-- @return number: Count of immediate peer whisper requests dispatched (1 or 0)
function Overlord.BroadcastHopRequest(targetLayer)
    if (_G.ULODB and (_G.ULODB.overlordEnabled == false or _G.ULODB.uloOnlyMode == true))
       or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.overlordEnabled == false) then
        return 0
    end

    if type(_G.Overlord) ~= "table" then
        return 0
    end

    local data = CollectOverlordPeers(targetLayer)
    local candidates = {}
    local function AppendFrom(bucket)
        for _, row in ipairs(bucket) do
            if #candidates >= 4 then break end
            table.insert(candidates, row)
        end
    end

    AppendFrom(data.shardHelpers)
    AppendFrom(data.knownHelpers)
    AppendFrom(data.shardOthers)
    AppendFrom(data.dirContacts)

    if #candidates == 0 then
        activeHopQueue = nil
        if type(ULO.LogAction) == "function" then
            ULO.LogAction("OverlordLJ", "0 known Overlord peers found")
        end
        return 0
    end

    local baseTime = (type(_G.time) == "function" and _G.time()) or math.floor(((type(_G.GetTime) == "function" and _G.GetTime()) or 0) * 1000)
    local originTag = data.myServerId or data.ovLayer or data.myLayer or "-"
    local isAwaiting = ULO.Coordination and type(ULO.Coordination.IsAwaitingHop) == "function" and ULO.Coordination.IsAwaitingHop()

    activeHopQueue = {
        candidates = candidates,
        index = 0,
        originTag = originTag,
        baseTime = baseTime,
        activeReqId = nil,
        enforceAwaiting = (isAwaiting == true),
    }

    return Overlord.AdvanceHopCandidate("start") and 1 or 0
end

--- Dispatches a decline message over OverlordLJ WHISPER.
-- @param targetPlayer string: Target player name
-- @param reqId string|number: Session request token
-- @param reason string: Decline code (off, combat, full, same, etc.)
function Overlord.SendDecline(targetPlayer, reqId, reason)
    local payload = string.format("N:%s:%s", tostring(reqId), reason)

    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendAddonMessage) == "function" then
        pcall(_G.C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", targetPlayer)
    elseif type(_G.SendAddonMessage) == "function" then
        pcall(_G.SendAddonMessage, PREFIX, payload, "WHISPER", targetPlayer)
    end
end

--- Retrieves the rejection failure reason recorded for a session request ID.
-- @param reqId string|number: Request identifier
-- @return string|nil: Decline reason string
function Overlord.GetRequestFailureReason(reqId)
    if reqId == nil then return nil end
    return failedRequests[reqId] or failedRequests[tostring(reqId)] or failedRequests[tonumber(reqId)]
end

-- Addon message event listener
if type(_G.CreateFrame) == "function" then
    local overlordFrame = _G.CreateFrame("Frame", "ULO_OverlordEventFrame")
    overlordFrame:RegisterEvent("CHAT_MSG_ADDON")
    overlordFrame:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
        if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
            if (_G.ULODB and (_G.ULODB.overlordEnabled == false or _G.ULODB.uloOnlyMode == true))
               or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.overlordEnabled == false) then
                if type(ULO.LogAction) == "function" then
                    ULO.LogAction("Blocked", "Ignored OverlordLJ req from " .. tostring(sender))
                end
                return
            end
            Overlord.ProcessMessage(msg, sender)
        end
    end)
end
