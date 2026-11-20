-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Detection/LayerScanner.lua
-- Description: Multi-unit scanning (targets, nameplates, vignettes, combat log),
--              2-GUID consensus voting algorithm, context invalidation debounce,
--              instance suppression, and NovaWorldBuffs interoperability.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Detection = ULO.Detection or {}
local Detection = ULO.Detection
local Compat = ULO.Compat
local C = ULO.Constants

-- Runtime State Variables
local currentServerId = nil
local currentZoneId = nil
local currentLayer = nil
local layerConfidence = (C and C.CONFIDENCE and C.CONFIDENCE.UNDETERMINED) or "UNDETERMINED"

-- Voting Pools & Memoization Cache
local votePool = {} -- [serverId] = { count = n, guids = { [guid] = true } }
local memoCache = {} -- [guid] = true
local memoKeys = {}
local memoHitCount = 0
local scheduledScanCount = 0
local debounceEpoch = 0
local debounceTimer = nil
local isSyncingNWB = false

-- Authoritative mapping table: hardware shard IDs -> layer index
local KNOWN_SERVER_LAYERS = {
    [4469] = 1,
    [4470] = 2,
    [4471] = 1,
    [4472] = 2,
    [4473] = 3,
    [4474] = 4,
    [5120] = 1,
    [5122] = 3,
    [5123] = 3,
    [5124] = 3,
}

--- Maps a physical server shard ID to human layer number.
-- @param serverId number: Hardware shard ID
-- @return number: Layer number (1 to 30)
local function MapServerToLayer(serverId)
    if not serverId then return nil end
    if KNOWN_SERVER_LAYERS[serverId] then
        return KNOWN_SERVER_LAYERS[serverId]
    end
    local mod = serverId % 10
    return (mod == 0) and 10 or mod
end

--- Verifies whether open-world layering is active.
-- Returns false inside party dungeons, raids, battlegrounds, or arenas.
-- @return boolean: true if in open world
function Detection.IsLayeringEnabled()
    if type(_G.GetInstanceInfo) == "function" then
        local ok, name, instType = pcall(_G.GetInstanceInfo)
        if ok and instType and (instType == "party" or instType == "raid" or instType == "pvp" or instType == "arena" or (instType ~= "none" and instType ~= "")) then
            return false
        end
    end
    if type(_G.IsInInstance) == "function" then
        local ok, inInst = pcall(_G.IsInInstance)
        if ok and inInst then return false end
    end
    return true
end

--- Records a vote for a serverId from a specific creature GUID.
-- Enforces 2-GUID consensus before confirming layer.
-- @param serverId number: Hardware shard ID
-- @param guid string: Unique creature GUID
-- @return boolean confirmed: true if layer is confirmed
-- @return number leaderId: Current leading serverId
function Detection.VoteLayer(serverId, guid)
    if not serverId or not guid then
        return (layerConfidence == "CONFIRMED"), currentServerId
    end

    votePool[serverId] = votePool[serverId] or { count = 0, guids = {} }
    if not votePool[serverId].guids[guid] then
        votePool[serverId].guids[guid] = true
        votePool[serverId].count = votePool[serverId].count + 1
    end

    local threshold = (C and C.DETECTION and C.DETECTION.CONSENSUS_THRESHOLD) or 2
    if votePool[serverId].count >= threshold then
        local oldLayer = currentLayer
        local changed = (currentServerId ~= serverId)
        currentServerId = serverId
        currentLayer = MapServerToLayer(serverId)
        layerConfidence = "CONFIRMED"

        -- Synchronize with NovaWorldBuffs if present
        if (not ULO.IsTrackEnabled or ULO.IsTrackEnabled("nwb")) and not isSyncingNWB
           and (_G.NWB_CurrentLayer ~= currentLayer or _G.NWB_CurrentLayerZoneID ~= currentZoneId) then
            isSyncingNWB = true
            _G.NWB_CurrentLayer = currentLayer
            _G.NWB_CurrentLayerZoneID = currentZoneId
            if type(_G.NWB_LayerUpdated) == "function" then
                pcall(_G.NWB_LayerUpdated)
            end
            isSyncingNWB = false
        end

        if changed or oldLayer ~= currentLayer then
            local trigger = ULO.TriggerCallback or ULO.FireCallback
            if type(trigger) == "function" then
                trigger("OnLayerChanged", currentLayer, currentServerId, currentZoneId, oldLayer)
            end
        end

        return true, currentServerId
    else
        if layerConfidence == "UNDETERMINED" then
            layerConfidence = "ESTIMATED"
        end
        return false, serverId
    end
end

--- Ingests a GUID string into the layer voting pipeline.
-- @param guid string: Candidate GUID string
-- @return boolean: true if successfully evaluated or cached
function Detection.ScanGuid(guid)
    if not guid then return false end
    if not Detection.IsLayeringEnabled() then
        layerConfidence = "INSTANCED"
        return false
    end

    if memoCache[guid] then
        memoHitCount = memoHitCount + 1
        return true
    end

    local serverId, zoneId = Detection.ParseGuid(guid)
    if not serverId then return false end

    local maxEntries = (C and C.DETECTION and C.DETECTION.MAX_CACHE_ENTRIES) or 100

    if votePool[serverId] and votePool[serverId].guids[guid] then
        memoHitCount = memoHitCount + 1
        if #memoKeys >= maxEntries then
            local oldest = table.remove(memoKeys, 1)
            if oldest then
                memoCache[oldest] = nil
            end
        end
        memoCache[guid] = true
        table.insert(memoKeys, guid)
        return true
    end

    if #memoKeys >= maxEntries then
        local oldest = table.remove(memoKeys, 1)
        if oldest then
            memoCache[oldest] = nil
        end
    end
    memoCache[guid] = true
    table.insert(memoKeys, guid)

    if zoneId then
        currentZoneId = zoneId
    end

    Detection.VoteLayer(serverId, guid)
    return true
end

--- Scans a unit token safely.
-- @param unit string: Unit token
-- @return boolean: true if scanned
function Detection.ScanUnit(unit)
    if not unit then return false end
    if not Detection.IsUnitEligible(unit) then return false end
    local ok, guid = pcall(_G.UnitGUID, unit)
    if not ok or not guid then return false end
    return Detection.ScanGuid(guid)
end

--- Scans a unit token with Retail 12.x secret value protection.
-- @param unit string: Unit token
-- @return boolean|nil
function Detection.ScanUnitSafe(unit)
    if not unit or type(_G.UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(_G.UnitGUID, unit)
    if not ok or not guid then return nil end
    if (Compat and Compat.IsSecretValue and Compat.IsSecretValue(guid)) or (_G.issecretvalue and _G.issecretvalue(guid)) then
        return nil
    end
    return Detection.ScanGuid(guid)
end

--- Scans all active visible nameplates.
function Detection.ScanNameplates()
    if not Detection.IsLayeringEnabled() then return end
    if type(_G.C_NamePlate) == "table" and type(_G.C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(_G.C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local unit = plate.namePlateUnitToken or plate.unitToken or "nameplate1"
                Detection.ScanUnit(unit)
            end
        end
    end
end

--- Scans mini-map rare and chest vignettes.
function Detection.ScanVignettes()
    if not Detection.IsLayeringEnabled() then return end
    if type(_G.C_VignetteInfo) == "table" and type(_G.C_VignetteInfo.GetVignettes) == "function" then
        local ok, vList = pcall(_G.C_VignetteInfo.GetVignettes)
        if ok and type(vList) == "table" then
            for _, vGuid in ipairs(vList) do
                local infoOk, info = pcall(_G.C_VignetteInfo.GetVignetteInfo, vGuid)
                if infoOk and info and info.objectGUID then
                    Detection.ScanGuid(info.objectGUID)
                end
            end
        end
    end
end

--- Performs a comprehensive multi-unit scan across all eligible data streams.
function Detection.ScanAll()
    if not Detection.IsLayeringEnabled() then
        Detection.ResetContext(true)
        return
    end

    local scanUnits = (C and C.DETECTION and C.DETECTION.SCAN_UNITS) or {
        "target", "mouseover", "focus", "softenemy", "softfriend", "softinteract"
    }
    for _, unit in ipairs(scanUnits) do
        Detection.ScanUnit(unit)
    end
    Detection.ScanNameplates()
    Detection.ScanVignettes()
end

Detection.PerformFullScan = Detection.ScanAll

--- Flushes voting cache, invalidates current layer, and schedules debounced scan.
-- @param instanced boolean|string|nil: true or "INSTANCED" if in instance
function Detection.ResetContext(instanced)
    votePool = {}
    memoCache = {}
    memoKeys = {}
    currentServerId = nil
    currentLayer = nil
    currentZoneId = nil

    local isInst = (instanced == true or instanced == "INSTANCED" or not Detection.IsLayeringEnabled())
    if isInst then
        layerConfidence = "INSTANCED"
    else
        layerConfidence = "UNDETERMINED"
    end

    scheduledScanCount = scheduledScanCount + 1
    debounceEpoch = debounceEpoch + 1
    debounceTimer = nil

    -- Schedule debounced entity scan (0.5s) if in open world
    if not isInst and type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        local thisEpoch = debounceEpoch
        local debounceDelay = (C and C.DETECTION and C.DETECTION.DEBOUNCE_TIME) or 0.5
        _G.C_Timer.After(debounceDelay, function()
            if thisEpoch == debounceEpoch and Detection.IsLayeringEnabled() then
                Detection.ScanAll()
            end
        end)
    end
end

Detection.ResetLayerContext = Detection.ResetContext

-- Context Accessors
function Detection.GetCurrentLayer() return currentLayer end
function Detection.GetCurrentServerId() return currentServerId end
function Detection.GetLayerConfidence() return layerConfidence end
function Detection.GetVoteCount(serverId) return (votePool[serverId] and votePool[serverId].count) or 0 end
function Detection.GetTotalVotes()
    local total = 0
    for _, v in pairs(votePool) do
        total = total + (v.count or 0)
    end
    return total
end
function Detection.GetMemoHitCount() return memoHitCount end
function Detection.GetScheduledScanCount() return scheduledScanCount end
function Detection.GetMemoCacheSize() return #memoKeys end

function Detection.GetCurrentZoneId()
    if not currentZoneId and type(_G.C_Map) == "table" and type(_G.C_Map.GetBestMapForUnit) == "function" then
        local ok, mapId = pcall(_G.C_Map.GetBestMapForUnit, "player")
        if ok and mapId then return mapId end
    end
    return currentZoneId
end

-- ============================================================================
-- Event Frame & Subsystem Lifecycle
-- ============================================================================
local function OnEvent(self, event, arg1, ...)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        local inInst = not Detection.IsLayeringEnabled()
        Detection.ResetContext(inInst)
    elseif event == "ZONE_CHANGED" then
        if not Detection.IsLayeringEnabled() then
            Detection.ResetContext(true)
        end
    elseif event == "UNIT_PHASE" then
        if arg1 == "player" then
            Detection.ResetContext(not Detection.IsLayeringEnabled())
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        Detection.ScanUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Detection.ScanUnit("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Detection.ScanUnit("focus")
    elseif event == "UNIT_TARGET" then
        if arg1 then Detection.ScanUnit(tostring(arg1) .. "target") end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if arg1 then Detection.ScanUnit(arg1) end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not Detection.IsLayeringEnabled() then return end
        local timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID
        if type(_G.CombatLogGetCurrentEventInfo) == "function" then
            timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID = _G.CombatLogGetCurrentEventInfo()
        else
            timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID = arg1, ...
        end
        if sourceGUID and type(sourceGUID) == "string" and (sourceGUID:find("^Creature%-") or sourceGUID:find("^Vehicle%-")) then
            Detection.ScanGuid(sourceGUID)
        end
        if destGUID and type(destGUID) == "string" and (destGUID:find("^Creature%-") or destGUID:find("^Vehicle%-")) then
            Detection.ScanGuid(destGUID)
        end
    end
end

-- Create event frame at file load time
if type(_G.CreateFrame) == "function" then
    local f = _G.CreateFrame("Frame", "ULO_DetectionEventFrame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ZONE_CHANGED")
    f:RegisterEvent("UNIT_PHASE")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    f:RegisterEvent("PLAYER_FOCUS_CHANGED")
    f:RegisterEvent("UNIT_TARGET")
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")

    local toc = (Compat and type(Compat.GetTocVersion) == "function" and Compat.GetTocVersion()) or 0
    local isRestrictedClient = not _G.__harness and (
        _G.C_Secrets ~= nil
        or _G.GetAddOnRestrictionState ~= nil
        or (toc >= 16000 and toc < 20000)
        or toc >= 120000
    )
    if not isRestrictedClient then
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end

    f:SetScript("OnEvent", OnEvent)
    Detection.eventFrame = f
end

-- Seed initial layer from NWB if available
if (not ULO.IsTrackEnabled or ULO.IsTrackEnabled("nwb")) and _G.NWB_CurrentLayer then
    local seed = tonumber(_G.NWB_CurrentLayer) or tonumber(string.match(tostring(_G.NWB_CurrentLayer), "(%d+)"))
    if seed then
        currentLayer = seed
        layerConfidence = "CONFIRMED"
    end
end

function Detection:Initialize()
    if (not ULO.IsTrackEnabled or ULO.IsTrackEnabled("nwb")) and _G.NWB_CurrentLayer then
        local seed = tonumber(_G.NWB_CurrentLayer) or tonumber(string.match(tostring(_G.NWB_CurrentLayer), "(%d+)"))
        if seed then
            currentLayer = seed
            layerConfidence = "CONFIRMED"
        end
    end
end

function Detection:Enable()
    Detection.ResetContext(not Detection.IsLayeringEnabled())
end

Detection.OnPlayerLogin = Detection.Enable

function Detection:OnLogout()
    -- Subsystem clean teardown
end

-- Register Subsystem into ULO
if ULO.RegisterSubsystem then
    ULO.RegisterSubsystem("Detection", Detection)
end
