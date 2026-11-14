-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Coordination/KeywordMatcher.lua
-- Description: Whisper keyword engine, whole-word pattern recognition,
--              range and inverted parsing, anti-spam blacklist filtering,
--              and [NWB] tag rejection.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

ULO.Coordination = ULO.Coordination or {}
local Coordination = ULO.Coordination
local C = ULO.Constants
local Compat = ULO.Compat

local MAX_LAYER = (C and C.KEYWORDS and C.KEYWORDS.MAX_LAYER) or 20

local DEFAULT_BLACKLIST = {
    "wtb", "wts", "boost", "portals", "portal", "gold", "gdkp",
    "lfm", "lfg", "ashen", "ashenvale", "autoinv", "auto inv",
    "pst for", "guild", "raid", "enchant", "player",
    "what layer", "which layer", "worldbuffs",
}

local function BuildBlacklist()
    local list = {}
    local seen = {}
    local function addWord(w)
        if type(w) == "string" and w ~= "" then
            local lower = string.lower(w)
            if not seen[lower] then
                seen[lower] = true
                table.insert(list, lower)
            end
        end
    end

    if C and C.KEYWORDS and type(C.KEYWORDS.BLACKLIST) == "table" then
        for _, w in ipairs(C.KEYWORDS.BLACKLIST) do
            addWord(w)
        end
    end
    for _, w in ipairs(DEFAULT_BLACKLIST) do
        addWord(w)
    end
    return list
end

local BLACKLIST_WORDS = BuildBlacklist()

--- Matches and parses layer request keywords in incoming whisper messages.
-- @param msg any: Candidate chat string
-- @return boolean: true if recognized as valid layer request
-- @return number|string|nil: target layer number, or rejection reason string
-- @return boolean|nil: isInverted (true if "not layer N")
-- @return number|nil: rangeStart or excludedLayer
-- @return number|nil: rangeEnd
function Coordination.MatchKeywords(msg)
    if msg == nil or type(msg) ~= "string" or msg == "" then
        return false
    end

    -- Guard against retail engine secret values
    if (Compat and Compat.IsSecretValue and Compat.IsSecretValue(msg)) or (_G.issecretvalue and _G.issecretvalue(msg)) then
        return false
    end

    -- Reject whitespace-only strings
    if string.match(msg, "^%s*$") then
        return false
    end

    -- Rejection 1: NovaWorldBuffs automated layer announcement tags
    if string.find(msg, "^%s*%[NWB%]") then
        return false, "nwb_tag"
    end

    local lower = string.lower(msg)

    -- Rejection 2: Anti-Spam Blacklist filter (wtb, wts, boost, portals, gdkp, etc.)
    for _, word in ipairs(BLACKLIST_WORDS) do
        local pat = "%f[%w]" .. string.gsub(word, "%s+", "%%s+") .. "%f[%W]"
        if string.find(lower, pat) then
            return false, "blacklisted"
        end
    end

    -- Match Pattern 1: Range syntax "layer 1-3"
    local r1, r2 = string.match(lower, "%f[%w]layer%s+(%d+)%s*%-%s*(%d+)%f[%D]")
    if r1 and r2 then
        local n1, n2 = tonumber(r1), tonumber(r2)
        if n1 < 1 or n1 > MAX_LAYER or n2 < 1 or n2 > MAX_LAYER or n1 > n2 then
            return false, "out_of_bounds"
        end
        return true, nil, false, n1, n2
    end

    -- Match Pattern 2: Inverted syntax "not layer 1", "off layer 1", "except layer 1", "but layer 1"
    local invPrefixes = (C and C.KEYWORDS and C.KEYWORDS.INVERTED) or {
        "not", "off", "except", "but", "out", "other than", "besides", "apart from"
    }
    local invLayer = nil
    for _, prefix in ipairs(invPrefixes) do
        local pat = "%f[%w]" .. string.gsub(prefix, "%s+", "%%s+") .. "%s+layer%s+(%-?%d+)%f[%D]"
        invLayer = string.match(lower, pat)
        if invLayer then break end
    end
    if invLayer then
        local lNum = tonumber(invLayer)
        if not lNum or lNum < 1 or lNum > MAX_LAYER then
            return false, "out_of_bounds"
        end
        return true, nil, true, lNum
    end

    -- Match Pattern 3: Specific layer number "layer 2" (including negative and invalid integer rejection)
    local anyLayerSpec = string.match(lower, "%f[%w]layer%s+([-%d]+)%f[%D]")
    if anyLayerSpec then
        local lNum = tonumber(anyLayerSpec)
        if not lNum or lNum < 1 or lNum > MAX_LAYER then
            return false, "out_of_bounds"
        end
        return true, lNum
    end

    -- Match Pattern 4: Standard whole-word triggers "layer", "inv", "invite"
    local hasLayer = string.find(lower, "%f[%w]layer%f[%W]")
    local hasInv = string.find(lower, "%f[%w]inv%f[%W]")
    local hasInvite = string.find(lower, "%f[%w]invite%f[%W]")
    if hasLayer or hasInv or hasInvite then
        return true, nil
    end

    return false
end

--- Validates whether a message is an acceptable layer invitation request.
-- @param msg any: Candidate message
-- @return boolean: true if valid request
function Coordination.IsValidLayerRequest(msg)
    local match = Coordination.MatchKeywords(msg)
    return match == true
end
