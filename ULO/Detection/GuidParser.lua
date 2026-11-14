-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Detection/GuidParser.lua
-- Description: Hyphen-delimited GUID parsing, token extraction (ServerID, ZoneID),
--              entity filtering (Player/Pet exclusion), and secret value guards.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Detection = ULO.Detection or {}
local Detection = ULO.Detection
local Compat = ULO.Compat
local C = ULO.Constants

-- Hyphen-delimited entity GUID format:
-- EntityType-0-ServerID-InstanceID-ZoneID-NpcID-SpawnUID
local GUID_PATTERN = "^([%a]+)%-0%-(%-?%d+)%-(%d+)%-(%d+)%-(%d+)%-([%x%d]+)$"

--- Parses an entity GUID into constituent layer tokens.
-- @param guid string: Raw entity GUID string
-- @return serverId number|nil: Hardware shard ID (Token 3)
-- @return zoneId number|nil: Zone instance ID (Token 5)
-- @return entityType string|nil: Entity classification (Token 1) or error string on failure
-- @return isValid boolean: true if valid entity GUID for layering
function Detection.ParseGuid(guid)
    if guid == nil then return nil, "nil_guid", nil, false end
    if type(guid) ~= "string" then return nil, "invalid_type", nil, false end
    if guid == "" then return nil, "empty_guid", nil, false end

    -- Guard against retail/engine secret values
    if (Compat and Compat.IsSecretValue and Compat.IsSecretValue(guid)) or (_G.issecretvalue and _G.issecretvalue(guid)) then
        return nil, "secret_guid", nil, false
    end

    -- Explicit exclusions for players and player pets
    if string.sub(guid, 1, 7) == "Player-" then
        return nil, "player_excluded", nil, false
    end
    if string.sub(guid, 1, 4) == "Pet-" then
        return nil, "pet_excluded", nil, false
    end

    local entityType, serverStr, instStr, zoneStr, npcStr, uidStr = string.match(guid, GUID_PATTERN)
    if not entityType then
        return nil, "malformed_guid", nil, false
    end

    local validTypes = (C and C.DETECTION and C.DETECTION.VALID_UNIT_TYPES) or {
        Creature   = true,
        Vehicle    = true,
        GameObject = true,
        Vignette   = true,
    }
    if not validTypes[entityType] then
        return nil, "invalid_type", nil, false
    end

    local serverId = tonumber(serverStr)
    if not serverId then
        return nil, "malformed_guid", nil, false
    end

    -- ServerID bounds: must be strictly positive and within valid integer bounds
    if serverId <= 0 or serverId > 999999999 then
        return nil, "out_of_bounds", nil, false
    end

    local zoneId = tonumber(zoneStr)
    return serverId, zoneId, entityType, true
end

-- SCOPE.md casing alias
Detection.ParseGUID = Detection.ParseGuid

--- Determines whether a unit token is eligible for layer detection.
-- Filters players, player-controlled units (pets, totems, charmed), and invalid units.
-- @param unit string: Unit token (e.g. "target", "mouseover")
-- @return boolean: true if unit is eligible
function Detection.IsUnitEligible(unit)
    if not unit then return false end

    if type(_G.UnitExists) == "function" then
        local ok, exists = pcall(_G.UnitExists, unit)
        if ok and not exists then return false end
    end

    if type(_G.UnitIsVisible) == "function" then
        local ok, visible = pcall(_G.UnitIsVisible, unit)
        if ok and not visible then return false end
    end

    if type(_G.UnitIsPlayer) == "function" then
        local ok, isPlayer = pcall(_G.UnitIsPlayer, unit)
        if ok and isPlayer then return false end
    end

    if type(_G.UnitPlayerControlled) == "function" then
        local ok, isControlled = pcall(_G.UnitPlayerControlled, unit)
        if ok and isControlled then return false end
    end

    if type(_G.UnitGUID) ~= "function" then return false end
    local ok, guid = pcall(_G.UnitGUID, unit)
    if not ok or not guid or type(guid) ~= "string" then return false end

    if (Compat and Compat.IsSecretValue and Compat.IsSecretValue(guid)) or (_G.issecretvalue and _G.issecretvalue(guid)) then
        return false
    end

    local sId = Detection.ParseGuid(guid)
    return sId ~= nil
end

--- Entity validity check adhering to SCOPE.md signature.
-- @param unitToken string|nil: Unit token
-- @param guid string|nil: GUID string
-- @return boolean: true if valid for layer detection
function Detection.IsEntityValidForLayer(unitToken, guid)
    if unitToken then
        if not Detection.IsUnitEligible(unitToken) then
            return false
        end
        if guid then
            local sId = Detection.ParseGuid(guid)
            return sId ~= nil
        end
        return true
    elseif guid then
        local sId = Detection.ParseGuid(guid)
        return sId ~= nil
    end
    return false
end
