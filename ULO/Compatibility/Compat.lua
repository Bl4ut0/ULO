-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Compatibility/Compat.lua
-- Description: Cross-release client detection, safe party API shims,
--              secret value protection, and headless testability mocks.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO
ULO.Compat = ULO.Compat or {}
local Compat = ULO.Compat

-- ============================================================================
-- Section 1: Headless & Standalone Mock Fallbacks
-- ============================================================================

--- Pure-Lua fallback for strsplit when running outside the WoW client environment
-- Uses literal string search (plain=true) to emulate Blizzard's C-engine strsplit.
-- @param delim string: Delimiter character or string
-- @param text string: Text to split
-- @param maxPieces number|nil: Optional limit on number of returned pieces
-- @return unpacked strings
local function PureLuaStrSplit(delim, text, maxPieces)
    if not text then return nil end
    if delim == nil then
        error("bad argument #1 to 'strsplit' (string expected, got nil)", 2)
    end
    local delimStr = tostring(delim)
    if delimStr == "" then return text end

    local maxP = tonumber(maxPieces)
    if maxP and maxP <= 1 then return text end

    local results = {}
    local startPos = 1

    while true do
        if maxP and (#results + 1) >= maxP then
            table.insert(results, string.sub(text, startPos))
            break
        end

        local s, e = string.find(text, delimStr, startPos, true)
        if not s then
            table.insert(results, string.sub(text, startPos))
            break
        end

        table.insert(results, string.sub(text, startPos, s - 1))
        startPos = e + 1
    end

    local unpackFunc = unpack or table.unpack
    return unpackFunc(results)
end

if type(_G.strsplit) ~= "function" then
    _G.strsplit = PureLuaStrSplit
end
Compat.FallbackStrSplit = PureLuaStrSplit

-- Standalone mock state for unit test isolation
local mockToc = nil
local mockFlavor = nil
local mockChatLockdown = nil
local mockSeasonal = nil

function Compat._SetMockToc(toc)
    mockToc = tonumber(toc)
end

function Compat._SetMockFlavor(flavor)
    mockFlavor = flavor
end

function Compat._SetMockChatLockdown(locked)
    mockChatLockdown = (locked == true)
end

function Compat._SetMockSeasonal(seasonal)
    mockSeasonal = (seasonal == true)
end

function Compat._ResetMocks()
    mockToc = nil
    mockFlavor = nil
    mockChatLockdown = nil
    mockSeasonal = nil
end

-- ============================================================================
-- Section 2: Environment & Client Flavor Detection
-- ============================================================================

--- Retrieves the current client TOC version as an integer.
-- @return number: TOC interface version (e.g. 16001, 11509, 20506, 50504, 120105)
function Compat.GetTocVersion()
    if mockToc ~= nil then return mockToc end

    if type(_G.GetBuildInfo) == "function" then
        local ok, _, _, _, toc = pcall(_G.GetBuildInfo)
        if ok and toc then
            return tonumber(toc) or 16001
        end
    end

    if _G.TOC_VERSION then
        return tonumber(_G.TOC_VERSION) or 16001
    end

    return 16001 -- Default fallback: WoW Forever TOC
end

--- Returns true if the client is WoW Forever (Camelot).
function Compat.IsForever()
    local toc = Compat.GetTocVersion()
    return toc >= 16000 and toc < 20000
end

--- Returns true if the client is WoW Retail (Mainline).
function Compat.IsRetail()
    local toc = Compat.GetTocVersion()
    return toc >= 100000 and toc < 900000
end

--- Returns true if the client is WoW Classic Era (Vanilla / SoD / Hardcore).
function Compat.IsClassicEra()
    local toc = Compat.GetTocVersion()
    return toc >= 11500 and toc < 12000
end

--- Returns true if the client is WoW Classic Anniversary (TBC).
function Compat.IsTBC()
    local toc = Compat.GetTocVersion()
    return toc >= 20000 and toc < 30000
end

--- Returns true if the client is WoW Classic Progression (Mists of Pandaria).
function Compat.IsProgression()
    local toc = Compat.GetTocVersion()
    return toc >= 30000 and toc < 100000
end

--- Returns true if the realm is an active seasonal realm (e.g., Season of Discovery).
function Compat.IsSeasonal()
    if mockSeasonal ~= nil then return mockSeasonal end

    if type(_G.C_Seasons) == "table" and type(_G.C_Seasons.HasActiveSeason) == "function" then
        local ok, hasSeason = pcall(_G.C_Seasons.HasActiveSeason)
        return ok and (hasSeason == true)
    end
    return false
end

--- Returns the canonical product flavor string.
-- @return string: "wowf", "wow_anniversary", "wow_classic_era", "wow_classic", or "wow"
function Compat.GetClientFlavor()
    if mockFlavor ~= nil then return mockFlavor end

    if Compat.IsForever() then
        return "wowf"
    elseif Compat.IsTBC() then
        return "wow_anniversary"
    elseif Compat.IsClassicEra() then
        return "wow_classic_era"
    elseif Compat.IsProgression() then
        return "wow_classic"
    elseif Compat.IsRetail() then
        return "wow"
    end

    return "unknown"
end

-- ============================================================================
-- Section 3: Security, Secret Value & Chat Lockdown Guards
-- ============================================================================

--- Checks whether chat messaging API restrictions are in effect.
-- @return boolean: true if chat messaging is currently locked down
function Compat.InChatLockdown()
    if mockChatLockdown ~= nil then return mockChatLockdown end

    if type(_G.InCombatLockdown) == "function" then
        local inCombat = false
        local ok, res = pcall(_G.InCombatLockdown)
        if ok and res then inCombat = true end
        if inCombat then return true end
    end

    if type(_G.C_ChatInfo) == "table" and type(_G.C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(_G.C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then
            return true
        end
    end

    return false
end

--- Tests whether a Lua value is marked as secret by the client engine.
-- @param val any: Value to check
-- @return boolean: true if secret or unreadable
function Compat.IsSecretValue(val)
    if type(val) == "nil" then return false end
    local issecret = _G.issecretvalue
    if type(issecret) == "function" then
        local ok, secret = pcall(issecret, val)
        if not ok then return true end
        return secret == true
    end
    return false
end

--- Tests whether the calling function has permissions to access a value.
-- @param val any: Value to check
-- @return boolean: true if accessible
function Compat.CanAccess(val)
    if Compat.IsSecretValue(val) then
        local canaccess = _G.canaccessvalue
        if type(canaccess) == "function" then
            local ok, accessible = pcall(canaccess, val)
            return ok and (accessible == true)
        end
        return false
    end
    return true
end

--- Validates and sanitizes a string against engine secret value constraints.
-- @param str any: Candidate string
-- @return string|nil: Safe string, or nil if secret/invalid
function Compat.SafeString(str)
    if type(str) == "nil" then return nil end
    if Compat.IsSecretValue(str) then return nil end
    if not Compat.CanAccess(str) then return nil end

    local strType = type(str)
    if strType == "string" then
        return str
    elseif strType == "number" then
        return tostring(str)
    end
    return nil
end

--- Safely converts a string to lowercase with secret guards.
-- @param str any: Candidate string
-- @return string|nil
function Compat.SafeLower(str)
    local safe = Compat.SafeString(str)
    if not safe then return nil end
    local ok, res = pcall(string.lower, safe)
    return ok and res or nil
end

--- Safely trims whitespace from both ends of a string.
-- @param str any: Candidate string
-- @return string|nil
function Compat.SafeTrim(str)
    local safe = Compat.SafeString(str)
    if not safe then return nil end
    local ok, res = pcall(string.match, safe, "^%s*(.-)%s*$")
    return ok and res or nil
end

--- Internal helper to unpack pcall return values without table allocation or arity distortion.
-- @param ok boolean: pcall success status
-- @param ... any: Return values from protected call
-- @return forwarded values on success, or nil on failure
local function SafeCallHelper(ok, ...)
    if ok then
        return ...
    end
    return nil
end

--- Safely executes string.match on a guarded string.
-- Preserves native return arity without fixed-tuple truncation or trailing nil inflation.
-- @param str any: Source string
-- @param pattern string: Lua pattern
-- @param init number|nil: Optional start index
-- @return captured substrings or nil
function Compat.SafeMatch(str, pattern, init)
    local safe = Compat.SafeString(str)
    if not safe then return nil end
    return SafeCallHelper(pcall(string.match, safe, pattern, init))
end

--- Safely executes string.find on a guarded string.
-- @param str any: Source string
-- @param pattern string: Pattern to search for
-- @param init number|nil: Start index
-- @param plain boolean|nil: Plain text search flag
-- @return startPos, endPos or nil
function Compat.SafeFind(str, pattern, init, plain)
    local safe = Compat.SafeString(str)
    if not safe then return nil end
    local ok, s, e = pcall(string.find, safe, pattern, init, plain)
    if ok then
        return s, e
    end
    return nil
end

--- Safely splits a guarded string using strsplit or pure-Lua fallback.
-- Preserves native return arity without intermediate table allocation.
-- @param delim string: Delimiter
-- @param str any: Source string
-- @param maxPieces number|nil: Maximum pieces to split
-- @return unpacked strings or nil
function Compat.SafeSplit(delim, str, maxPieces)
    local safe = Compat.SafeString(str)
    if not safe then return nil end
    local splitFunc = _G.strsplit or PureLuaStrSplit
    return SafeCallHelper(pcall(splitFunc, delim, safe, maxPieces))
end

-- ============================================================================
-- Section 4: Safe Party & Group API Shims
-- ============================================================================

--- Normalizes and splits a player target name into unit name and realm name.
-- Preserves multi-hyphen realms (e.g. "PlayerName-Server-Name-With-Hyphens" -> "PlayerName", "Server-Name-With-Hyphens").
-- @param target string: Player name or Name-Realm
-- @return string|nil: Unit name, or nil if invalid
-- @return string|nil: Realm name, or nil if single-realm
function Compat.NormalizeTargetName(target)
    local s = Compat.SafeString(target)
    if not s or s == "" then return nil, nil end
    s = Compat.SafeTrim(s)
    if not s or s == "" then return nil, nil end

    -- Unit name cannot begin with hyphen
    if string.sub(s, 1, 1) == "-" then
        return nil, nil
    end

    -- Strip trailing hyphens
    s = string.gsub(s, "%-+$", "")
    if s == "" then return nil, nil end

    local unit, realm = string.match(s, "^([^-]+)%-(.+)$")
    if unit and realm then
        return unit, realm
    end
    return s, nil
end

--- Normalizes a player name according to realm architecture.
-- Seasonal realms (SoD) strip the realm portion to prevent ERR_BAD_PLAYER_NAME_S.
-- WoW Forever, Retail, and connected realms preserve character-realm format.
-- @param name string: Raw player name
-- @return string|nil: Normalized name
function Compat.NormalizeInviteTarget(name)
    local safe = Compat.SafeString(name)
    if not safe or safe == "" then return nil end
    safe = Compat.SafeTrim(safe)
    if not safe or safe == "" then return nil end

    if Compat.IsSeasonal() then
        -- On Seasonal realms, cross-realm invites error out. Strip realm suffix:
        local baseName = safe:match("^([^-]+)")
        return baseName or safe
    else
        -- WoW Forever, Retail, and connected realms require full name-realm:
        return safe
    end
end

--- Safely dispatches a group invite to the specified player.
-- Prioritizes C_PartyInfo.InviteUnit, then C_PartyInfo.ConfirmInviteUnit, then global InviteUnit.
-- @param targetName string: Player name or Name-Realm
-- @return boolean: true on success
-- @return string|nil: Error identifier on failure
--- Identifies the current character without confusing another realm's namesake.
function Compat.IsSelfName(targetName)
    local target, targetRealm = Compat.NormalizeTargetName(targetName)
    if not target then return false end
    local player, playerRealm
    if type(_G.UnitFullName) == "function" then
        local ok, name, realm = pcall(_G.UnitFullName, "player")
        if ok then player, playerRealm = name, realm end
    end
    if not player and type(_G.UnitName) == "function" then
        local ok, name, realm = pcall(_G.UnitName, "player")
        if ok then player, playerRealm = name, realm end
    end
    local shortPlayer, embeddedRealm = Compat.NormalizeTargetName(player)
    if not shortPlayer or string.lower(target) ~= string.lower(shortPlayer) then return false end
    if not targetRealm then return true end
    playerRealm = Compat.SafeString(playerRealm) or embeddedRealm
    if (not playerRealm or playerRealm == "") and type(_G.GetRealmName) == "function" then
        local ok, realm = pcall(_G.GetRealmName)
        if ok then playerRealm = Compat.SafeString(realm) end
    end
    if not playerRealm then return false end
    local function realmKey(realm)
        return string.lower(string.gsub(realm, "[%s%-]", ""))
    end
    return realmKey(targetRealm) == realmKey(playerRealm)
end

function Compat.InviteUnit(targetName)
    local normalized = Compat.NormalizeInviteTarget(targetName)
    if not normalized or normalized == "" then
        return false, "invalid_target"
    end
    if Compat.IsSelfName(targetName) or Compat.IsSelfName(normalized) then
        return false, "self_invite"
    end

    if type(_G.C_PartyInfo) == "table" and (type(_G.C_PartyInfo.InviteUnit) == "function" or type(_G.C_PartyInfo.InviteUnit) == "userdata") then
        local ok, err = pcall(_G.C_PartyInfo.InviteUnit, normalized)
        if ok then return true, nil end
        if type(_G.C_PartyInfo.ConfirmInviteUnit) == "function" or type(_G.C_PartyInfo.ConfirmInviteUnit) == "userdata" then
            local cOk, cErr = pcall(_G.C_PartyInfo.ConfirmInviteUnit, normalized)
            if cOk then return true, nil end
        end
    end

    if type(_G.InviteUnit) == "function" or type(_G.InviteUnit) == "userdata" then
        local ok, err = pcall(_G.InviteUnit, normalized)
        if ok then return true, nil end
        return false, tostring(err)
    end

    return false, "no_invite_api"
end

--- Safely uninvites or kicks a player from the party/raid.
-- @param targetName string: Player name to remove
-- @param reason string|nil: Optional kick reason
-- @return boolean: true on success
-- @return string|nil: Error identifier on failure
function Compat.UninviteUnit(targetName, reason)
    local safe = Compat.SafeString(targetName)
    if not safe or safe == "" then return false, "invalid_target" end

    if type(_G.C_PartyInfo) == "table" and (type(_G.C_PartyInfo.UninviteUnit) == "function" or type(_G.C_PartyInfo.UninviteUnit) == "userdata") then
        local ok, err = pcall(_G.C_PartyInfo.UninviteUnit, safe, reason)
        if ok then return true, nil end
    end

    if type(_G.UninviteUnit) == "function" or type(_G.UninviteUnit) == "userdata" then
        local ok, err = pcall(_G.UninviteUnit, safe, reason)
        if ok then return true, nil end
        return false, tostring(err)
    end

    return false, "no_uninvite_api"
end

--- Safely leaves the current group, preventing nil dereference crashes on WoW Forever.
-- @param category number|nil: Optional party category
-- @return boolean: true on success
-- @return string|nil: Error identifier on failure
function Compat.LeaveParty(category)
    local success = false
    local lastErr = nil

    if type(_G.C_PartyInfo) == "table" and (type(_G.C_PartyInfo.LeaveParty) == "function" or type(_G.C_PartyInfo.LeaveParty) == "userdata") then
        local ok, err = pcall(_G.C_PartyInfo.LeaveParty, category)
        if ok then
            success = true
        else
            lastErr = tostring(err)
            if type(_G.C_PartyInfo.ConfirmLeaveParty) == "function" or type(_G.C_PartyInfo.ConfirmLeaveParty) == "userdata" then
                local cOk, cErr = pcall(_G.C_PartyInfo.ConfirmLeaveParty, category)
                if cOk then success = true; lastErr = nil end
            end
        end
    end

    if not success and (type(_G.LeaveParty) == "function" or type(_G.LeaveParty) == "userdata") then
        local ok, err = pcall(_G.LeaveParty, category)
        if ok then
            success = true
            lastErr = nil
        else
            lastErr = tostring(err)
        end
    end

    return success, lastErr
end

--- Safely accepts an inbound party invitation and suppresses the Blizzard popup.
-- Sets dialog.inviteAccepted = 1 before hiding to prevent Blizzard OnHide from calling DeclineGroup.
-- @return boolean: true on success
-- @return string|nil: Error identifier on failure
function Compat.AcceptGroup()
    local accepted = false
    local lastErr = nil

    if type(_G.C_PartyInfo) == "table" and (type(_G.C_PartyInfo.ConfirmAcceptInvite) == "function" or type(_G.C_PartyInfo.ConfirmAcceptInvite) == "userdata") then
        local ok, err = pcall(_G.C_PartyInfo.ConfirmAcceptInvite)
        if ok then accepted = true else lastErr = tostring(err) end
    end

    if not accepted and (type(_G.AcceptGroup) == "function" or type(_G.AcceptGroup) == "userdata") then
        local ok, err = pcall(_G.AcceptGroup)
        if ok then accepted = true else lastErr = tostring(err) end
    end

    -- Suppress and cleanly close static popup dialogs to prevent auto-decline on hide
    if type(_G.StaticPopup_FindVisible) == "function" or type(_G.StaticPopup_FindVisible) == "userdata" then
        local ok, dialog = pcall(_G.StaticPopup_FindVisible, "PARTY_INVITE")
        if ok and dialog then dialog.inviteAccepted = 1 end
        local xOk, xDialog = pcall(_G.StaticPopup_FindVisible, "PARTY_INVITE_XREALM")
        if xOk and xDialog then xDialog.inviteAccepted = 1 end
    end

    if type(_G.StaticPopup_Hide) == "function" or type(_G.StaticPopup_Hide) == "userdata" then
        pcall(_G.StaticPopup_Hide, "PARTY_INVITE")
        pcall(_G.StaticPopup_Hide, "PARTY_INVITE_XREALM")
    end

    return accepted, lastErr
end
