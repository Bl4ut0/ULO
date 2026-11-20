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
local ownedChannels = {}
local joinedDay

local function DateFormats()
    local t
    if type(_G.C_DateAndTime) == "table" and type(_G.C_DateAndTime.GetCurrentCalendarTime) == "function" then
        local ok, value = pcall(_G.C_DateAndTime.GetCurrentCalendarTime)
        if ok and type(value) == "table" and not Compat.IsSecretValue(value) then t = value end
    end
    local day, month, year
    if t and not Compat.IsSecretValue(t.monthDay) and not Compat.IsSecretValue(t.month) and not Compat.IsSecretValue(t.year) then
        day, month, year = tonumber(t.monthDay), tonumber(t.month), tonumber(t.year)
    end
    if not (day and month and year) and type(_G.date) == "function" then
        local ok, value = pcall(_G.date, "%d-%m-%Y")
        value = ok and Compat.SafeString(value)
        if value then day, month, year = string.match(value, "^(%d%d)%-(%d%d)%-(%d%d%d%d)$") end
        day, month, year = tonumber(day), tonumber(month), tonumber(year)
    end
    if not (day and month and year) or day < 1 or day > 31 or month < 1 or month > 12
       or year < 1970 or year > 3000 or day % 1 ~= 0 or month % 1 ~= 0 or year % 1 ~= 0 then return {} end
    return { string.format("%02d-%02d-%04d", day, month, year), string.format("%04d-%02d-%02d", year, month, day),
        string.format("%02d-%02d-%04d", month, day, year) }
end

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
-- @param dateStr string|nil: Target date string (defaults to server calendar day)
-- @return string: Channel name matching "layer<8-hex>"
function AutoLayer.GenerateChannelName(realm, dateStr)
    if not realm or realm == "" then
        if type(_G.GetRealmName) == "function" then
            local ok, value = pcall(_G.GetRealmName)
            realm = ok and value or nil
        end
    end
    realm = Compat.SafeString(realm)
    if not realm then return nil end
    if not dateStr or dateStr == "" then
        dateStr = DateFormats()[1]
    end
    dateStr = Compat.SafeString(dateStr)
    if not dateStr then return nil end

    local seed = realm .. "-" .. dateStr
    local hash = Adler32(seed)
    return "layer" .. hash
end

--- Subscribe to static layer plus all three upstream daily date formats.
-- Requests still use one active channel to avoid multiplying invitations.
function AutoLayer.JoinChannels()
    local valid = {}
    joinedDay = DateFormats()[1]
    local managed = AutoLayer.GetManagedChannels()
    for _, channel in ipairs(managed) do
        valid[channel] = true
        if not AutoLayer.IsChannelFailed(channel) and type(_G.JoinChannelByName) == "function" then
            local ok = pcall(_G.JoinChannelByName, channel)
            if ok then ownedChannels[channel] = true end
        end
    end
    for channel in pairs(ownedChannels) do
        if not valid[channel] and channel ~= "layer" and type(_G.LeaveChannelByName) == "function" then
            pcall(_G.LeaveChannelByName, channel)
            ownedChannels[channel], failedChannels[channel] = nil, nil
        end
    end
    if type(ULO.LogAction) == "function" then
        ULO.LogAction("Channel", "Subscribed to " .. #managed .. " compatible layer channels")
    end
    return AutoLayer.GenerateChannelName() or "layer"
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
-- @return table: Unique channel names in upstream preference order
function AutoLayer.GetManagedChannels()
    local list = { "layer" }
    local seen = { layer = true }
    for _, dateStr in ipairs(DateFormats()) do
        local channel = AutoLayer.GenerateChannelName(nil, dateStr)
        if channel and not seen[channel] then
            seen[channel] = true
            list[#list + 1] = channel
        end
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
        end
    end

    if #departed > 0 and type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(30, AutoLayer.JoinChannels)
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
        or (ULO.IsTrackEnabled and not ULO.IsTrackEnabled("autoLayer") and ULO.IsTrackEnabled("ulo"))
    local seg = "AZ"
    if uloOnly then
        seg = "ULO"
    elseif mapID == 1945 then
        seg = "OL"
    end

    local formatted
    local lNum = tonumber(targetLayer)
    local myLayer = ULO.Detection and type(ULO.Detection.GetCurrentLayer) == "function"
        and tonumber(ULO.Detection.GetCurrentLayer()) or nil
    if ULO.IsTrackEnabled and not ULO.IsTrackEnabled(uloOnly and "ulo" or "autoLayer") then
        return nil, 0, "disabled"
    end
    if not uloOnly and ((_G.ULODB and _G.ULODB.autoLayerEnabled == false)
       or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.autoLayerEnabled == false)) then
        return nil, 0, "disabled"
    end
    if lNum and myLayer == lNum then return nil, 0, "already_on_layer" end
    if lNum then
        formatted = string.format("<%s> inv layer %d", seg, lNum)
    elseif myLayer and myLayer > 0 then
        formatted = string.format("<%s> inv not layer %d", seg, myLayer)
    else
        return nil, 0, "layer_unknown"
    end
    if Compat.IsTBC() and not uloOnly then
        local zone = ULO.Intelligence.GetZone()
        if not zone then return nil, 0, "zone_unknown" end
        -- AL2's minimum zone-aware wire capability (1.9.5), not ULO's version.
        formatted = "<AL2V1_9_5Z" .. zone .. "> " .. (lNum and ("inv layer " .. lNum) or ("inv not layer " .. myLayer))
    end

    local sentSlots = {}
    if type(_G.SendChatMessage) == "function" then
        if type(_G.GetChannelName) == "function" then
            local seenSlot = {}
            for _, chName in ipairs(AutoLayer.GetManagedChannels()) do
                local ok, id = pcall(_G.GetChannelName, chName)
                if not AutoLayer.IsChannelFailed(chName) and ok and type(id) == "number" and id > 0 and not seenSlot[id] then
                    seenSlot[id] = true
                    if not AutoLayer.IsSlotProtected(id) then
                        table.insert(sentSlots, id)
                        if #sentSlots >= 1 then
                            break
                        end
                    end
                end
            end
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
    return formatted, #sentSlots
end

-- Calendar rollover, initial join, and channel hop request listener frame
if type(_G.CreateFrame) == "function" then
    local autoLayerFrame = _G.CreateFrame("Frame", "ULO_AutoLayerEventFrame")
    if autoLayerFrame and type(autoLayerFrame.RegisterEvent) == "function" and type(autoLayerFrame.SetScript) == "function" then
        autoLayerFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
        autoLayerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        autoLayerFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        local calendarElapsed = 0
        autoLayerFrame:SetScript("OnUpdate", function(_, elapsed)
            calendarElapsed = calendarElapsed + elapsed
            if calendarElapsed >= 30 then
                calendarElapsed = 0
                if DateFormats()[1] ~= joinedDay then
                    AutoLayer.JoinChannels()
                    AutoLayer.LeaveExcessChannels()
                end
            end
        end)
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
                if type(msg) ~= "string" or type(sender) ~= "string" then
                    return
                end
                -- Chat text and names may remain strings while being secret.
                -- Validate before equality, patterns, case conversion or logging.
                msg, sender = Compat.SafeString(msg), Compat.SafeString(sender)
                if not msg or not sender or sender == "" then
                    return
                end

                if Compat and Compat.IsSelfName and Compat.IsSelfName(sender) then return end

                local base
                if type(channelBaseName) == "nil" then
                    base = Compat.SafeLower(channelName)
                else
                    base = Compat.SafeLower(channelBaseName)
                end
                if not base or base == "" or not (base == "layer" or string.match(base, "^layer%x%x%x%x%x%x%x%x$")) then
                    return
                end

                local isULOMsg = string.match(msg, "^%s*<ULO>%s*inv") ~= nil
                if ULO.IsTrackEnabled and not ULO.IsTrackEnabled(isULOMsg and "ulo" or "autoLayer") then return end
                local sourceTag = isULOMsg and "ULO Chan" or "AutoLayer"
                if not isULOMsg and ((_G.ULODB and (_G.ULODB.autoLayerEnabled == false or _G.ULODB.uloOnlyMode == true))
                   or (_G.ULO_CONFIG and _G.ULO_CONFIG.interop and _G.ULO_CONFIG.interop.autoLayerEnabled == false)) then
                    if type(ULO.LogAction) == "function" then
                        ULO.LogAction("Blocked", "Ignored AutoLayer channel req from " .. tostring(sender))
                    end
                    return
                end

                local seg, targetLayer, _, scope = AutoLayer.ParseMessage(msg)
                scope = scope or tonumber(string.match(msg, "^%s*<AL2V[%d_]+Z(%d+)>"))
                if scope and not ULO.Intelligence.RequestZoneAllowed(sender, scope, true) then return end
                local coord = ULO.Coordination
                if seg and targetLayer then
                    if coord and type(coord.HandleWhisper) == "function" then
                        coord.HandleWhisper(sender, string.format("inv layer %d", targetLayer), sourceTag, false, scope)
                    end
                else
                    local exLayer = string.match(msg, "^%s*<[A-Z0-9_.]+>%s*inv%s+not%s+layer%s+(%d+)%s*$")
                    local isAnyHeaderHop = (not exLayer) and (string.match(msg, "^%s*<[A-Z0-9_.]+>%s*inv%s+layer%s*$") ~= nil)
                    if exLayer then
                        if coord and type(coord.HandleWhisper) == "function" then
                            coord.HandleWhisper(sender, string.format("not layer %d", tonumber(exLayer)), sourceTag, false, scope)
                        end
                    elseif isAnyHeaderHop then
                        if coord and type(coord.HandleWhisper) == "function" then
                            coord.HandleWhisper(sender, "inv layer", sourceTag, false, scope)
                        end
                    elseif not string.match(msg, "^%s*<") and coord
                           and type(coord.HandleWhisper) == "function" then
                        local chatMatcher = (type(coord.MatchChatRequest) == "function") and coord.MatchChatRequest or coord.MatchKeywords
                        if type(chatMatcher) == "function" and chatMatcher(msg) then
                            coord.HandleWhisper(sender, msg, sourceTag, true)
                        end
                    end
                end
            end
        end)
    end
end
