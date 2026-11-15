-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Interop/NWBInterop.lua
-- Description: NovaWorldBuffs runtime integration, bi-directional layer
--              synchronization, global hook detection, and safe callback handling.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Interop = ULO.Interop or {}
local Interop = ULO.Interop

Interop.NWB = Interop.NWB or {}
local NWB = Interop.NWB
Interop.Guild = Interop.Guild or {}
local Guild = Interop.Guild
local C = ULO.Constants
local Compat = ULO.Compat

local isSyncing = false
local guildPeers = {}
local ADDON_PREFIXES = { "ULO", "TresLayerSwap", "LayerHopper" }

local function ShortKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    local short = string.match(name, "^([^%-]+)") or name
    short = string.match(short, "^%s*(.-)%s*$") or short
    if short == "" then return nil end
    return string.lower(short)
end

local function RegisterExtraPrefixes()
    for _, prefix in ipairs(ADDON_PREFIXES) do
        if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
            pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, prefix)
        elseif type(_G.RegisterAddonMessagePrefix) == "function" then
            pcall(_G.RegisterAddonMessagePrefix, prefix)
        end
    end
end
RegisterExtraPrefixes()

--- Synchronizes internal layer detection state from NovaWorldBuffs globals.
-- Employs reentrancy guard to prevent recursive update loops.
function NWB.SyncWithNWB()
    if isSyncing then return end
    isSyncing = true

    if _G.NWB_CurrentLayer ~= nil then
        local raw = _G.NWB_CurrentLayer
        local layer = tonumber(raw)
        if not layer and type(raw) == "string" then
            local match = string.match(raw, "(%d+)")
            if match then layer = tonumber(match) end
        end

        local Detection = ULO.Detection
        if layer and Detection and type(Detection.GetCurrentLayer) == "function" then
            if layer ~= Detection.GetCurrentLayer() then
                if type(Detection.ResetContext) == "function" then
                    Detection.ResetContext(false)
                end
                if type(Detection.ScanGuid) == "function" then
                    -- 2-GUID voting consensus injection (5000 + layer maps modulo 10 to layer without KNOWN_SERVER_LAYERS collisions)
                    local sid = 5000 + layer
                    Detection.ScanGuid(string.format("Creature-0-%d-0-14-1-1", sid))
                    Detection.ScanGuid(string.format("Creature-0-%d-0-14-1-2", sid))
                end
            end
        end
    end

    isSyncing = false
end

--- Dynamically checks whether NovaWorldBuffs runtime globals or hooks are present.
-- Must NOT cache state to properly support late/on-demand addon loading.
-- @return boolean: true if NWB is hooked
function NWB.IsHooked()
    return (type(_G.NWB_LayerUpdated) == "function") or (_G.NWB_CurrentLayer ~= nil)
end

--- Safely accesses NovaWorldBuffs layer database table.
-- @return table|nil: Layers database or nil if absent/corrupted
function NWB.GetNWBLayerData()
    if type(_G.NWB_GetLayerData) == "function" then
        local ok, data = pcall(_G.NWB_GetLayerData)
        if ok and type(data) == "table" then
            return data
        end
    end
    if type(_G.NWBdatabase) == "table" and type(_G.NWBdatabase.layers) == "table" then
        return _G.NWBdatabase.layers
    end
    return nil
end

--- Resolves an authoritative server layer index from a creature GUID zoneID using NWB's layerMap tables.
-- @param zoneId number|string: Creature GUID token 5 (zone instance ID)
-- @return number|nil: Resolved layer number (1..N) or nil
function NWB.ResolveLayerFromZoneID(zoneId)
    local zNum = tonumber(zoneId)
    if not zNum or zNum <= 0 then return nil end
    local zStr = tostring(zNum)

    local layersTable = NWB.GetNWBLayerData()
    if type(layersTable) ~= "table" then return nil end

    local function CheckLayerEntry(layerKey, layerData)
        local lNum = tonumber(layerKey)
        if not lNum or type(layerData) ~= "table" then return nil end
        local lMap = layerData.layerMap
        if type(lMap) == "table" then
            if lMap[zNum] ~= nil or lMap[zStr] ~= nil then
                return lNum
            end
        end
        if tonumber(layerData.zoneID) == zNum then
            return lNum
        end
        return nil
    end

    for k, v in pairs(layersTable) do
        local direct = CheckLayerEntry(k, v)
        if direct then return direct end
        if type(v) == "table" then
            for subKey, subVal in pairs(v) do
                local nested = CheckLayerEntry(subKey, subVal)
                if nested then return nested end
            end
        end
    end

    return nil
end

--- Records or updates a known guild/addon peer's layer state.
-- @param name string: Peer character name
-- @param layer number|nil: Peer layer number
-- @param serverId number|nil: Peer server/shard ID
-- @param isHelper boolean|nil: Whether peer has auto-invite active
-- @param source string|nil: Originating prefix ("ULO", "NWB", "TresLayerSwap", "LayerHopper")
function Guild.RecordPeer(name, layer, serverId, isHelper, source)
    local k = ShortKey(name)
    if not k then return end
    local now = (type(_G.GetTime) == "function" and _G.GetTime()) or 0
    guildPeers[k] = {
        name = name,
        layer = tonumber(layer),
        serverId = tonumber(serverId),
        helper = (isHelper ~= false),
        source = source or "ULO",
        updatedAt = now,
    }
end

--- Returns known guild and NWB peers filtered by target layer (or any different layer when nil).
-- @param targetLayer number|nil: Desired destination layer, or nil for any different layer
-- @return table: Array of peer candidate tables { name, layer, serverId, helper, source }
function NWB.GetKnownLayerPeers(targetLayer)
    local desired = tonumber(targetLayer)
    local Detection = ULO.Detection
    local myLayer = Detection and type(Detection.GetCurrentLayer) == "function" and Detection.GetCurrentLayer() or tonumber(_G.NWB_CurrentLayer)
    local mySid = Detection and type(Detection.GetCurrentServerId) == "function" and Detection.GetCurrentServerId() or nil
    local selfKey = ShortKey(type(_G.UnitName) == "function" and _G.UnitName("player") or nil)
    local uloOnly = (_G.ULODB and _G.ULODB.uloOnlyMode == true)

    -- Harvest any live player layer entries exposed by NWB database tables
    if type(_G.NWBdatabase) == "table" then
        for _, tblKey in ipairs({ "guildLayers", "playerLayers" }) do
            local tbl = _G.NWBdatabase[tblKey]
            if type(tbl) == "table" then
                for pName, info in pairs(tbl) do
                    local pLayer = (type(info) == "table" and tonumber(info.layer)) or tonumber(info)
                    if type(pName) == "string" and pLayer and pLayer > 0 then
                        Guild.RecordPeer(pName, pLayer, nil, true, "NWB")
                    end
                end
            end
        end
    end

    local out = {}
    for k, row in pairs(guildPeers) do
        if k ~= selfKey and (not uloOnly or row.source == "ULO") then
            local pLayer = tonumber(row.layer)
            local pSid = tonumber(row.serverId)
            local okLayer = false
            if desired then
                okLayer = (pLayer == desired)
            else
                local sameLayer = (myLayer and pLayer and pLayer == myLayer)
                    or (mySid and pSid and pSid == mySid and pSid > 0)
                okLayer = not sameLayer and ((pLayer ~= nil and pLayer > 0) or (pSid ~= nil and pSid > 0))
            end
            if okLayer then
                table.insert(out, row)
            end
        end
    end

    table.sort(out, function(a, b)
        if (a.helper and 1 or 0) ~= (b.helper and 1 or 0) then
            return a.helper == true
        end
        if (a.source == "ULO") ~= (b.source == "ULO") then
            return a.source == "ULO"
        end
        return tostring(a.name) < tostring(b.name)
    end)

    return out
end
Guild.GetKnownPeers = NWB.GetKnownLayerPeers

--- Broadcasts the player's current layer state over the silent 'ULO' GUILD addon channel.
-- @return boolean: true if status packet dispatched
function Guild.BroadcastLayer()
    local Detection = ULO.Detection
    local myLayer = Detection and type(Detection.GetCurrentLayer) == "function" and Detection.GetCurrentLayer() or tonumber(_G.NWB_CurrentLayer) or 0
    local mySid = Detection and type(Detection.GetCurrentServerId) == "function" and Detection.GetCurrentServerId() or 0
    local autoInv = not ULO.Coordination or type(ULO.Coordination.IsAutoInviteEnabled) ~= "function" or ULO.Coordination.IsAutoInviteEnabled()
    local payload = string.format("S:%d:%d:%d", tonumber(myLayer) or 0, tonumber(mySid) or 0, autoInv and 1 or 0)

    if type(_G.IsInGuild) == "function" and not _G.IsInGuild() then
        return false
    end

    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendAddonMessage) == "function" then
        pcall(_G.C_ChatInfo.SendAddonMessage, "ULO", payload, "GUILD")
        return true
    elseif type(_G.SendAddonMessage) == "function" then
        pcall(_G.SendAddonMessage, "ULO", payload, "GUILD")
        return true
    end
    return false
end

--- Processes inbound 'ULO', 'TresLayerSwap', and 'LayerHopper' addon messages.
-- @param prefix string: Addon message prefix
-- @param msg string: Payload string
-- @param channel string: Distribution channel ("GUILD", "WHISPER", etc.)
-- @param sender string: Sender character name
-- @return boolean: true if message was recognized and processed
function Guild.ProcessAddonMessage(prefix, msg, channel, sender)
    if type(prefix) ~= "string" or type(msg) ~= "string" or msg == "" or type(sender) ~= "string" or sender == "" then
        return false
    end
    if Compat and Compat.SafeString and not Compat.SafeString(msg) then
        return false
    end
    if prefix ~= "ULO" and prefix ~= "TresLayerSwap" and prefix ~= "LayerHopper" then
        return false
    end

    local selfKey = ShortKey(type(_G.UnitName) == "function" and _G.UnitName("player") or nil)
    local senderKey = ShortKey(sender)
    if selfKey and senderKey == selfKey then
        return false
    end

    local uloOnly = (_G.ULODB and _G.ULODB.uloOnlyMode == true)
    if uloOnly and prefix ~= "ULO" then
        if type(ULO.LogAction) == "function" then
            ULO.LogAction("Blocked", string.format("Ignored %s req from %s", tostring(prefix), tostring(sender)))
        end
        return false
    end

    -- 1. Status announcements: S:<layer>:<serverId>:<helper> or LAYER:<layer> / STATUS:<layer>
    local sLayer, sSid, sHelp = string.match(msg, "^S:(%d+):(%d+):([01])%s*$")
    if sLayer then
        Guild.RecordPeer(sender, tonumber(sLayer), tonumber(sSid), sHelp == "1", prefix)
        return true
    end

    local altLayer = string.match(msg, "^LAYER:(%d+)%s*$") or string.match(msg, "^STATUS:(%d+)%s*$")
    if altLayer then
        Guild.RecordPeer(sender, tonumber(altLayer), nil, true, prefix)
        return true
    end

    -- 2. Layer status queries: Q or PING
    if msg == "Q" or msg == "PING" then
        Guild.BroadcastLayer()
        return true
    end

    -- 3. Hop / Invite requests:
    --    ULO: R:<reqId>:<desiredLayerOrDash>:<originLayerOrDash>
    --    TresLayerSwap / LayerHopper: R:<reqId>:<layer>, REQ[:<layer>], HOP[:<layer>], INV[:<layer>], INVITE[:<layer>]
    local isHopReq = false
    local desiredLayer = nil
    local originLayer = nil

    local rId, dTok, oTok = string.match(msg, "^R:([%w_]+):([%d%-]+):([%d%-]+)%s*$")
    if rId then
        isHopReq = true
        desiredLayer = tonumber(dTok)
        originLayer = tonumber(oTok)
    else
        local rId2, dTok2 = string.match(msg, "^R:([%w_]+):([%d%-]+)%s*$")
        if rId2 then
            isHopReq = true
            desiredLayer = tonumber(dTok2)
        else
            local up = string.upper(msg)
            local cmd, arg = string.match(up, "^(REQUEST):?([%d%-]*)%s*$")
            if not cmd then
                cmd, arg = string.match(up, "^(REQ):?([%d%-]*)%s*$")
            end
            if not cmd then
                cmd, arg = string.match(up, "^(HOP):?([%d%-]*)%s*$")
            end
            if not cmd then
                cmd, arg = string.match(up, "^(INVITE):?([%d%-]*)%s*$")
            end
            if not cmd then
                cmd, arg = string.match(up, "^(INV):?([%d%-]*)%s*$")
            end
            if cmd then
                isHopReq = true
                desiredLayer = tonumber(arg)
            end
        end
    end

    if not isHopReq then
        return false
    end

    local Coordination = ULO.Coordination
    if Coordination and type(Coordination.IsAutoInviteEnabled) == "function" and not Coordination.IsAutoInviteEnabled() then
        return false
    end
    if ULO.Monitor and type(ULO.Monitor.IsRefreshPending) == "function" and ULO.Monitor.IsRefreshPending() then
        return false
    end
    if type(_G.IsInInstance) == "function" and _G.IsInInstance() then
        return false
    end
    local inCombat = (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player"))
                     or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown())
    if inCombat then
        return false
    end

    local numMembers = (type(_G.GetNumGroupMembers) == "function" and _G.GetNumGroupMembers())
                       or (type(_G.GetNumPartyMembers) == "function" and _G.GetNumPartyMembers())
                       or 0
    local inRaid = (type(_G.IsInRaid) == "function" and _G.IsInRaid())
    local maxMembers = inRaid and 40 or 5
    if numMembers >= maxMembers then
        return false
    end

    if Coordination and type(Coordination.IsPlayerInInviteCache) == "function" and Coordination.IsPlayerInInviteCache(sender) then
        return false
    end

    local Detection = ULO.Detection
    local myLayer = Detection and type(Detection.GetCurrentLayer) == "function" and Detection.GetCurrentLayer() or tonumber(_G.NWB_CurrentLayer)
    local mySid = Detection and type(Detection.GetCurrentServerId) == "function" and Detection.GetCurrentServerId() or nil

    if desiredLayer and myLayer and desiredLayer ~= myLayer then
        return false
    end
    if not desiredLayer and originLayer then
        if (myLayer and originLayer == myLayer) or (mySid and originLayer == mySid) then
            return false
        end
    end

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
        local tag = (prefix == "ULO") and "ULO Guild" or prefix
        ULO.LogAction(tag, string.format("Auto-invited %s (%s)", tostring(sender), inviteOk and "Invited" or "Invite failed"))
    end
    return inviteOk
end

--- Dispatches a hop request to known Guild / NWB / TresLayerSwap / LayerHopper peers.
-- @param targetLayer number|nil: Target layer number, or nil for any different layer
-- @return number: Count of outbound addon hop messages sent (0 or 1)
function Guild.BroadcastHopRequest(targetLayer)
    local Detection = ULO.Detection
    local myLayer = Detection and type(Detection.GetCurrentLayer) == "function" and Detection.GetCurrentLayer() or tonumber(_G.NWB_CurrentLayer)
    local tgtStr = tonumber(targetLayer) and tostring(tonumber(targetLayer)) or "-"
    local origStr = tonumber(myLayer) and tostring(tonumber(myLayer)) or "-"
    local baseTime = (type(_G.time) == "function" and _G.time()) or 1000
    local reqId = string.format("g%x", baseTime % 65535)

    local peers = NWB.GetKnownLayerPeers(targetLayer)
    if #peers > 0 then
        local best = peers[1]
        local usePrefix = (best.source == "TresLayerSwap" or best.source == "LayerHopper") and best.source or "ULO"
        local payload = (usePrefix == "ULO")
            and string.format("R:%s:%s:%s", reqId, tgtStr, origStr)
            or (tonumber(targetLayer) and ("REQ:" .. tostring(tonumber(targetLayer))) or "REQ")
        if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendAddonMessage) == "function" then
            pcall(_G.C_ChatInfo.SendAddonMessage, usePrefix, payload, "WHISPER", best.name)
            return 1
        elseif type(_G.SendAddonMessage) == "function" then
            pcall(_G.SendAddonMessage, usePrefix, payload, "WHISPER", best.name)
            return 1
        end
    end

    if type(_G.IsInGuild) == "function" and _G.IsInGuild() then
        local payload = string.format("R:%s:%s:%s", reqId, tgtStr, origStr)
        if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.SendAddonMessage) == "function" then
            pcall(_G.C_ChatInfo.SendAddonMessage, "ULO", payload, "GUILD")
            return 1
        elseif type(_G.SendAddonMessage) == "function" then
            pcall(_G.SendAddonMessage, "ULO", payload, "GUILD")
            return 1
        end
    end

    return 0
end

-- Layer change listener: sync layer and zone ID to NWB globals and broadcast to Guild ULO peers
if type(ULO.RegisterCallback) == "function" then
    ULO.RegisterCallback("OnLayerChanged", function(layer, serverId, zoneId)
        if not isSyncing then
            if _G.NWB_CurrentLayer ~= layer or _G.NWB_CurrentLayerZoneID ~= zoneId then
                _G.NWB_CurrentLayer = layer
                _G.NWB_CurrentLayerZoneID = zoneId
                if type(_G.NWB_LayerUpdated) == "function" then
                    pcall(_G.NWB_LayerUpdated)
                end
            end
        end
        Guild.BroadcastLayer()
    end)
end

-- Addon message listener frame for ULO Guild, TresLayerSwap, and LayerHopper
if type(_G.CreateFrame) == "function" then
    local guildInteropFrame = _G.CreateFrame("Frame", "ULO_GuildInteropEventFrame")
    if guildInteropFrame and type(guildInteropFrame.RegisterEvent) == "function" and type(guildInteropFrame.SetScript) == "function" then
        guildInteropFrame:RegisterEvent("CHAT_MSG_ADDON")
        guildInteropFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        guildInteropFrame:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
            if event == "PLAYER_ENTERING_WORLD" then
                RegisterExtraPrefixes()
                Guild.BroadcastLayer()
            elseif event == "CHAT_MSG_ADDON" then
                if prefix == "ULO" or prefix == "TresLayerSwap" or prefix == "LayerHopper" then
                    Guild.ProcessAddonMessage(prefix, msg, channel, sender)
                end
            end
        end)
    end
end

-- Initial seed check on load
if _G.NWB_CurrentLayer ~= nil then
    NWB.SyncWithNWB()
end

-- Interop Subsystem Lifecycle
function Interop:Initialize()
    RegisterExtraPrefixes()
    if Interop.Overlord and type(Interop.Overlord.Init) == "function" then
        Interop.Overlord.Init()
    end
    if Interop.NWB and type(Interop.NWB.SyncWithNWB) == "function" then
        Interop.NWB.SyncWithNWB()
    end
end

function Interop:Enable()
end
Interop.OnPlayerLogin = Interop.Enable

function Interop:OnLogout()
end

-- Subsystem Registration
if ULO.RegisterSubsystem then
    ULO.RegisterSubsystem("Interop", ULO.Interop)
end
