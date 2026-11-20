-- Fresh, client-scoped zone intelligence. Zone claims are not transfer proof.
local _, addonTable = ...
local ULO = _G.ULO or addonTable or {}
ULO.Intelligence = {}
local I = ULO.Intelligence
local Compat = ULO.Compat
local peers = {}
I.PEER_TTL = 90

local function Now() return type(_G.GetTime) == "function" and _G.GetTime() or 0 end
local function Number(value)
    if Compat.IsSecretValue(value) then return nil end
    local n = tonumber(value)
    return n and n == n and n > 0 and n < 1000000 and n % 1 == 0 and n or nil
end

function I.RequiresZone()
    return Compat.IsForever() or Compat.IsTBC()
end

function I.ResolveZone(mapID)
    local seen = {}
    for _ = 1, 32 do
        mapID = Number(mapID)
        if not mapID or seen[mapID] or type(_G.C_Map) ~= "table" or type(_G.C_Map.GetMapInfo) ~= "function" then return nil end
        seen[mapID] = true
        local ok, info = pcall(_G.C_Map.GetMapInfo, mapID)
        if not ok or type(info) ~= "table" or Compat.IsSecretValue(info) then return nil end
        local mapType = Number(info.mapType)
        if not mapType or mapType < 3 then return nil end
        if mapType == 3 then return mapID end
        mapID = info.parentMapID
    end
end

function I.GetZone(unit)
    if type(_G.C_Map) ~= "table" or type(_G.C_Map.GetBestMapForUnit) ~= "function" then return nil end
    local ok, mapID = pcall(_G.C_Map.GetBestMapForUnit, unit or "player")
    return ok and I.ResolveZone(mapID) or nil
end

function I.PeerKey(name)
    local character, realm = Compat.NormalizeTargetName(name)
    if not character then return nil end
    if not realm and type(_G.GetRealmName) == "function" then
        local ok, ownRealm = pcall(_G.GetRealmName)
        if ok then realm = Compat.SafeString(ownRealm) end
    end
    return string.lower(character) .. "-" .. string.lower(string.gsub(realm or "", "[%s%-]", ""))
end

function I.RecordPeer(name, layer, serverId, helper, zone, version, source)
    local key = I.PeerKey(name)
    if not key or Compat.IsSelfName(name) then return end
    local row = peers[key] or { name = name }
    row.layer, row.serverId, row.helper = Number(layer), Number(serverId), helper == true
    row.source, row.updatedAt = source or "ULO", Now()
    if zone ~= nil then
        row.zone = I.ResolveZone(zone)
        row.zoneAt, row.version = Now(), tonumber(version)
    end
    peers[key] = row
    return row
end

function I.GetPeer(name) return peers[I.PeerKey(name) or ""] end

function I.PeerZoneStatus(name)
    if not I.RequiresZone() then return "not_required" end
    local ownZone = I.GetZone()
    if not ownZone then return "zone_unknown" end
    local row = I.GetPeer(name)
    if not row or not row.zone or not row.zoneAt or Now() - row.zoneAt > I.PEER_TTL
       or Now() - row.updatedAt > I.PEER_TTL then return "unverified" end
    return row.zone == ownZone and "same_zone" or "zone_mismatch"
end

-- Legacy peers without zone metadata remain explicitly unverified. The requester
-- must validate the actual group leader before treating the hop as successful.
function I.RequestZoneAllowed(sender, requestZone, strict)
    if not I.RequiresZone() then return true end
    local ownZone = I.GetZone()
    if not ownZone then return false, "zone_unknown" end
    if requestZone ~= nil then
        local zone = I.ResolveZone(requestZone)
        if not zone then return false, "zone_unknown" end
        return zone == ownZone, zone == ownZone and "same_zone" or "zone_mismatch"
    end
    local status = I.PeerZoneStatus(sender)
    if strict and status ~= "same_zone" then return false, status end
    return status ~= "zone_mismatch", status
end

function I.GetLayerRows()
    local out = {}
    local current = ULO.Detection.GetCurrentLayer()
    for layer = 1, ULO.Constants.KEYWORDS.MAX_LAYER do
        local verified, unverified = 0, 0
        for _, row in pairs(peers) do
            if row.layer == layer and row.helper and Now() - row.updatedAt <= I.PEER_TTL
               and (not ULO.IsTrackEnabled or ULO.IsTrackEnabled(({ ULO = "ulo", NWB = "nwb", TresLayerSwap = "tresLayerSwap", LayerHopper = "layerHopper" })[row.source] or "ulo")) then
                local status = I.PeerZoneStatus(row.name)
                if status == "same_zone" or status == "not_required" then verified = verified + 1
                elseif status == "unverified" then unverified = unverified + 1 end
            end
        end
        out[#out + 1] = { layer = layer, current = layer == current, helpers = verified, unverified = unverified }
    end
    return out
end

function I.ValidateHopGroup(expectedHelper)
    if not I.RequiresZone() then return true end
    local ownZone = I.GetZone()
    if not ownZone then return nil, "zone_unknown" end
    local count = type(_G.GetNumGroupMembers) == "function" and _G.GetNumGroupMembers() or 0
    if count > 2 then return false, "foreign_group" end
    if count ~= 2 or type(_G.UnitName) ~= "function" then return nil, "group_unverified" end
    local expected = I.PeerKey(expectedHelper)
    local readable = false
    for n = 1, math.max(1, count - 1) do
        local unit = "party" .. n
        local ok, name, realm = pcall(_G.UnitName, unit)
        name = ok and Compat.SafeString(name) or nil
        realm = Compat.SafeString(realm)
        if name then
            readable = true
            if realm and realm ~= "" and not string.find(name, "-", 1, true) then name = name .. "-" .. realm end
            if I.PeerKey(name) == expected then
                if type(_G.UnitIsGroupLeader) == "function" and not _G.UnitIsGroupLeader(unit) then return nil, "leader_unverified" end
                local helperZone = I.GetZone(unit)
                if not helperZone then return nil, "zone_unverified" end
                return helperZone == ownZone, helperZone == ownZone and "same_zone" or "zone_mismatch"
            end
        end
    end
    if readable then return false, "foreign_group" end
    return nil, "group_unverified"
end

-- Advertise a heartbeat as well as zone changes: old claims must not stay fresh
-- merely because the UI repeatedly reads them.
if type(_G.CreateFrame) == "function" then
    local frame = _G.CreateFrame("Frame", "ULO_ZoneIntelligenceFrame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do frame:RegisterEvent(event) end
    local lastZone, lastAdvert = nil, -1000
    local function Update()
        local zone = I.GetZone()
        if zone ~= lastZone then
            local old = lastZone
            lastZone = zone
            ULO.TriggerCallback("OnZoneChanged", zone, old)
            lastAdvert = -1000
        end
        local guild = ULO.Interop and ULO.Interop.Guild
        if guild and guild.BroadcastLayer and Now() - lastAdvert >= 30 then
            lastAdvert = Now()
            guild.BroadcastLayer()
        end
    end
    frame:SetScript("OnEvent", Update)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + (tonumber(delta) or 0)
        if elapsed >= 1 then elapsed = 0; Update() end
    end)
end
