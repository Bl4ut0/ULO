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
local C = ULO.Constants

local isSyncing = false

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
    if type(_G.NWBdatabase) == "table" and type(_G.NWBdatabase.layers) == "table" then
        return _G.NWBdatabase.layers
    end
    return nil
end

-- Layer change listener: sync layer and zone ID to NWB globals
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
    end)
end

-- Initial seed check on load
if _G.NWB_CurrentLayer ~= nil then
    NWB.SyncWithNWB()
end

-- Interop Subsystem Lifecycle
function Interop:Initialize()
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
