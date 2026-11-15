-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Interop/AutoLayerProtocol.lua
-- Description: AutoLayer & NetherAutoLayer public and Adler32-salted channel
--              management, slot index protection, and segmented message parsing.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Interop = ULO.Interop or {}
local Interop = ULO.Interop

Interop.AutoLayer = Interop.AutoLayer or {}
local AutoLayer = Interop.AutoLayer
local C = ULO.Constants
local Compat = ULO.Compat

-- Internal State
local failedChannels = {}

--- Calculates an Adler32 checksum string formatted as an 8-character hex string.
-- @param str string: Input string to hash
-- @return string: 8-character lowercase hexadecimal hash
local function Adler32(str)
    if not str or str == "" then return "00000001" end
    local s1 = 1
    local s2 = 0
    for i = 1, #str do
        local b = string.byte(str, i)
        s1 = (s1 + b) % 65521
        s2 = (s2 + s1) % 65521
    end
    return string.format("%08x", (s2 * 65536) + s1)
end
AutoLayer.Adler32 = Adler32

--- Generates the date-salted AutoLayer channel name.
-- @param realm string|nil: Target realm name (defaults to current realm or "Camelot")
-- @param dateStr string|nil: Target date string (defaults to "14-11-2026")
-- @return string: Channel name matching "layer<8-hex>"
function AutoLayer.GenerateChannelName(realm, dateStr)
    if not realm or realm == "" then
        realm = (type(_G.GetRealmName) == "function" and _G.GetRealmName()) or "Camelot"
    end
    if not dateStr or dateStr == "" then
        dateStr = (type(_G.date) == "function" and _G.date("%d-%m-%Y")) or "14-11-2026"
    end

    local seed = realm .. "-" .. dateStr
    local hash = Adler32(seed)
    return "layer" .. hash
end

--- Joins today's dynamic date-salted AutoLayer channel (falling back to static 'layer' only if failed/headless).
-- @return string: Today's dynamic channel name
function AutoLayer.JoinChannels()
    local todayChannel = AutoLayer.GenerateChannelName()
    local useStaticFallback = AutoLayer.IsChannelFailed(todayChannel) or (type(_G.GetChannelName) ~= "function")
    if type(_G.JoinChannelByName) == "function" then
        pcall(_G.JoinChannelByName, todayChannel)
        if useStaticFallback then
            pcall(_G.JoinChannelByName, "layer")
        end
    end
    if not useStaticFallback and type(_G.GetChannelName) == "function" and type(_G.LeaveChannelByName) == "function" then
        local ok, slot = pcall(_G.GetChannelName, "layer")
        if ok and type(slot) == "number" and slot > 0 then
            pcall(_G.LeaveChannelByName, "layer")
        end
    end
    if type(ULO.LogAction) == "function" then
        if useStaticFallback then
            ULO.LogAction("Channel", "Joined /layer and /" .. tostring(todayChannel))
        else
            ULO.LogAction("Channel", "Joined /" .. tostring(todayChannel))
        end
    end
    return todayChannel
end

--- Marks a channel as failed (e.g. password-protected or unavailable).
-- @param ch string: Channel name
function AutoLayer.MarkChannelFailed(ch)
    if ch and ch ~= "" then
        failedChannels[ch] = true
    end
end

--- Checks if a channel has been marked as failed.
-- @param ch string: Channel name
-- @return boolean
function AutoLayer.IsChannelFailed(ch)
    return (ch ~= nil) and (failedChannels[ch] == true)
end

--- Retrieves the list of channels managed by AutoLayer interop.
-- @return table: Array of channel names {"layer", todayChannel}
function AutoLayer.GetManagedChannels()
    local list = { "layer" }
    local today = AutoLayer.GenerateChannelName()
    if today ~= "layer" then
        table.insert(list, today)
    end
    return list
end

--- Checks if a channel slot index is protected (reserved for Blizzard default channels 1-5).
-- @param slot number|any: Slot index
-- @return boolean: true if slot is between 1 and 5 inclusive
function AutoLayer.IsSlotProtected(slot)
    local n = tonumber(slot)
    return (n ~= nil) and (n > 0) and (n <= 5)
end

--- Leaves any managed layer channels that have displaced standard chat channels on slots <= 5.
-- Guaranteed idempotent under repeated invocations.
-- @param slotChecker function|nil: Optional custom slot resolver
-- @return table: Array of departed channel names
function AutoLayer.LeaveExcessChannels(slotChecker)
    local departed = {}
    local managed = AutoLayer.GetManagedChannels()

    for _, ch in ipairs(managed) do
        local slot = nil
        if type(slotChecker) == "function" then
            slot = slotChecker(ch)
        elseif type(_G.GetChannelName) == "function" then
            local ok, s = pcall(_G.GetChannelName, ch)
            if ok then slot = s end
        end

        if slot and AutoLayer.IsSlotProtected(slot) then
            if type(_G.LeaveChannelByName) == "function" then
                pcall(_G.LeaveChannelByName, ch)
                table.insert(departed, ch)
            end
        elseif not slotChecker and slot == nil and not _G.GetChannelName then
            -- Fallback when GetChannelName is not present in environment
            if type(_G.LeaveChannelByName) == "function" then
                pcall(_G.LeaveChannelByName, ch)
                table.insert(departed, ch)
            end
        end
    end

    return departed
end

--- Validates channel placement against slot protection policy.
-- @param channelName string: Channel name
-- @param slotIndex number: Assigned channel slot
-- @return boolean: true if slot placement is valid
-- @return string: "slot_ok" or "slot_displaced"
function AutoLayer.CheckAndEnforceSlotPolicy(channelName, slotIndex)
    if AutoLayer.IsSlotProtected(slotIndex) then
        if type(_G.LeaveChannelByName) == "function" then
            pcall(_G.LeaveChannelByName, channelName)
        end
        return false, "slot_displaced"
    end
    return true, "slot_ok"
end

--- Parses inbound AutoLayer protocol messages (Segmented and Protocol v2).
-- @param msg any: Candidate chat message
-- @return segment string|nil: "AL2", "AZ", "OL", "ZI", "DI", or nil
-- @return targetLayer number|nil: Parsed layer number
-- @return version string|nil: Protocol v2 addon version (e.g. "1.9.15")
-- @return scopeID number|nil: Protocol v2 scope map ID (e.g. 1945)
function AutoLayer.ParseMessage(msg)
    if msg == nil or type(msg) ~= "string" or msg == "" then
        return nil
    end

    if Compat and Compat.SafeString and not Compat.SafeString(msg) then
        return nil
    end

    local cleanMsg = msg
    if Compat and Compat.SafeTrim then
        cleanMsg = Compat.SafeTrim(cleanMsg) or cleanMsg
    else
        cleanMsg = string.match(cleanMsg, "^%s*(.-)%s*$") or cleanMsg
    end

    -- 1. Protocol v2: <AL2V1_9_15Z1945> inv layer 1
    local ver, scope, lNum = string.match(cleanMsg, "^%s*<AL2V([%d_]+)Z(%d+)>%s*inv%s*layer%s*(%d+)%s*$")
    if ver and scope and lNum then
        local cleanVer = string.gsub(ver, "_", ".")
        return "AL2", tonumber(lNum), cleanVer, tonumber(scope)
    end

    -- 2. Continental segment headers: <AZ> inv layer 2, <OL> inv layer 3, etc.
    local seg, tLayer = string.match(cleanMsg, "^%s*<([A-Z]+)>%s*inv%s*layer%s*(%d+)%s*$")
    if seg and tLayer then
        return seg, tonumber(tLayer)
    end

    return nil
end

--- Formats and broadcasts an outgoing hop request on active AutoLayer channels.
-- @param targetLayer number|nil: Requested layer number, or nil for any available layer
-- @param mapID number|nil: UiMapID of current zone
-- @return string: Formatted broadcast string (e.g. "<AZ> inv layer 3")
function AutoLayer.FormatBroadcastMessage(targetLayer, mapID)
    mapID = mapID or (type(_G.C_Map) == "table" and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetBestMapForUnit("player")) or 947
    local uloOnly = (_G.ULODB and _G.ULODB.uloOnlyMode == true)
    local seg = "AZ"
    if uloOnly then
        seg = "ULO"
    elseif mapID == 1945 then
        seg = "OL"
    end

    local formatted
    local lNum = tonumber(targetLayer)
    if lNum then
        formatted = string.format("<%s> inv layer %d", seg, lNum)
    elseif seg == "ULO" then
        local myLayer = ULO.Detection and type(ULO.Detection.GetCurrentLayer) == "function"
            and ULO.Detection.GetCurrentLayer() or nil
        if tonumber(myLayer) then
            formatted = string.format("<ULO> inv not layer %d", tonumber(myLayer))
        else
            formatted = "<ULO> inv layer"
        end
    else
        formatted = string.format("<%s> inv layer", seg)
    end

    local sentSlots = {}
    if type(_G.SendChatMessage) == "function" then
        if type(_G.GetChannelName) == "function" then
            local todayCh = AutoLayer.GenerateChannelName()
            local seenSlot = {}
            local fallbackSlot = nil
            for _, chName in ipairs({ todayCh, "layer" }) do
                local ok, id = pcall(_G.GetChannelName, chName)
                if ok and type(id) == "number" and id > 0 and not seenSlot[id] then
                    seenSlot[id] = true
                    if not AutoLayer.IsSlotProtected(id) then
                        table.insert(sentSlots, id)
                        if #sentSlots >= 1 then
                            break
                        end
                    elseif not fallbackSlot then
                        fallbackSlot = id
                    end
                end
            end
            if #sentSlots == 0 and fallbackSlot then
                table.insert(sentSlots, fallbackSlot)
            end
        else
            -- Headless test harness environments without GetChannelName default to channel 1
            table.insert(sentSlots, 1)
        end
        for _, slotId in ipairs(sentSlots) do
            pcall(_G.SendChatMessage, formatted, "CHANNEL", nil, slotId)
        end
    end

    if type(ULO.LogAction) == "function" then
        local tag = (seg == "ULO") and "ULO Chan" or "AutoLayer"
        if #sentSlots > 0 then
            local slotLabels = {}
            for _, slotId in ipairs(sentSlots) do
                table.insert(slotLabels, "/" .. tostring(slotId))
            end
            ULO.LogAction(tag, string.format("Sent %q on %s", formatted, table.concat(slotLabels, ", ")))
        else
            ULO.LogAction(tag, string.format("Prepared %q (no channel slot)", formatted))
        end
    end
    return formatted
end

-- Calendar rollover, initial join, and channel hop request listener frame
if type(_G.CreateFrame) == "function" then
    local autoLayerFrame = _G.CreateFrame("Frame", "ULO_AutoLayerEventFrame")
    if autoLayerFrame and type(autoLayerFrame.RegisterEvent) == "function" and type(autoLayerFrame.SetScript) == "function" then
        autoLayerFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
        autoLayerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        autoLayerFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        autoLayerFrame:SetScript("OnEvent", function(self, event, ...)
            if event == "CALENDAR_UPDATE_EVENT_LIST" then
                AutoLayer.JoinChannels()
                AutoLayer.LeaveExcessChannels()
            elseif event == "PLAYER_ENTERING_WORLD" then
                if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
                    _G.C_Timer.After(2, function()
                        AutoLayer.JoinChannels()
                        AutoLayer.LeaveExcessChannels()
                    end)
                else
                    AutoLayer.JoinChannels()
                    AutoLayer.LeaveExcessChannels()
                end
            elseif event == "CHAT_MSG_CHANNEL" then
                local msg, sender, _, channelName, _, _, _, _, channelBaseName = ...
                if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then
                    return
                end

                local playerName = type(_G.UnitName) == "function" and _G.UnitName("player")
                local shortSender = string.match(sender, "^([^%-]+)") or sender
                if playerName and (sender == playerName or shortSender == playerName) then
                    return
                end

                local base = string.lower(tostring(channelBaseName or channelName or ""))
                if base == "" or not (base == "layer" or string.match(base, "^layer%x%x%x%x%x%x%x%x$")) then
                    return
                end

                local isULOMsg = string.match(msg, "^%s*<ULO>%s*inv") ~= nil
                local sourceTag = isULOMsg and "ULO Chan" or "AutoLayer"
                if not isULOMsg and ((_G.ULODB and (_G.ULODB.autoLayerEnabled == false or _G.ULODB.uloOnlyMode == true))
                   or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.autoLayerEnabled == false)) then
                    if type(ULO.LogAction) == "function" then
                        ULO.LogAction("Blocked", "Ignored AutoLayer channel req from " .. tostring(sender))
                    end
                    return
                end

                local seg, targetLayer = AutoLayer.ParseMessage(msg)
                local coord = ULO.Coordination
                if seg and targetLayer then
                    if coord and type(coord.HandleWhisper) == "function" then
                        coord.HandleWhisper(sender, string.format("inv layer %d", targetLayer), sourceTag)
                    end
                else
                    local exLayer = string.match(msg, "^%s*<[A-Z0-9_.]+>%s*inv%s+not%s+layer%s+(%d+)%s*$")
                    local isAnyHeaderHop = (not exLayer) and (string.match(msg, "^%s*<[A-Z0-9_.]+>%s*inv%s+layer%s*$") ~= nil)
                    if exLayer then
                        if coord and type(coord.HandleWhisper) == "function" then
                            coord.HandleWhisper(sender, string.format("not layer %d", tonumber(exLayer)), sourceTag)
                        end
                    elseif isAnyHeaderHop then
                        if coord and type(coord.HandleWhisper) == "function" then
                            coord.HandleWhisper(sender, "inv layer", sourceTag)
                        end
                    elseif not string.match(msg, "^%s*<") and coord
                           and type(coord.MatchKeywords) == "function"
                           and type(coord.HandleWhisper) == "function"
                           and coord.MatchKeywords(msg) then
                        coord.HandleWhisper(sender, msg, sourceTag)
                    end
                end
            end
        end)
    end
end
