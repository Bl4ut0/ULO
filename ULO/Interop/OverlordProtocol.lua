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

--- Initializes and registers the OverlordLJ addon message prefix.
function Overlord.Init()
    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif type(_G.RegisterAddonMessagePrefix) == "function" then
        pcall(_G.RegisterAddonMessagePrefix, PREFIX)
    end
end
Overlord.Init()

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

        -- 1. Check if auto-invites are enabled
        local Coordination = ULO.Coordination
        if Coordination and type(Coordination.IsAutoInviteEnabled) == "function" then
            if not Coordination.IsAutoInviteEnabled() then
                Overlord.SendDecline(sender, reqId, "off")
                return true
            end
        end

        -- 2. Check if host is inside a dungeon or raid instance
        if type(_G.IsInInstance) == "function" then
            local inInstance = _G.IsInInstance()
            if inInstance then
                Overlord.SendDecline(sender, reqId, "instance")
                return true
            end
        end

        -- 3. Check if player is in combat
        local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                         or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
        if inCombat then
            Overlord.SendDecline(sender, reqId, "combat")
            return true
        end

        -- 4. Check if party/raid is full (capacity >= 5 for party, >= 40 for raid)
        local numMembers = (type(_G.GetNumGroupMembers) == "function" and _G.GetNumGroupMembers())
                           or (type(_G.GetNumPartyMembers) == "function" and _G.GetNumPartyMembers())
                           or 0
        local inRaid = (type(_G.IsInRaid) == "function" and _G.IsInRaid())
        local maxMembers = inRaid and 40 or 5
        if numMembers >= maxMembers then
            Overlord.SendDecline(sender, reqId, "full")
            return true
        end

        -- 5. Check if requester is already on the host's layer
        if layerNum then
            local Detection = ULO.Detection
            local myLayer = (Detection and type(Detection.GetCurrentLayer) == "function" and Detection.GetCurrentLayer())
            if myLayer and myLayer == layerNum then
                Overlord.SendDecline(sender, reqId, "same")
                return true
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

    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendAddonMessage) == "function" then
        pcall(_G.C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", targetPlayer)
    elseif type(_G.SendAddonMessage) == "function" then
        pcall(_G.SendAddonMessage, PREFIX, payload, "WHISPER", targetPlayer)
    end
    return reqId
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
            Overlord.ProcessMessage(msg, sender)
        end
    end)
end
