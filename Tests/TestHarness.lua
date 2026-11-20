-- ============================================================================
-- Tests/TestHarness.lua
-- Universal Layer Operator (ULO)
-- Standalone WoW Lua Mock Environment, Test Runner & Assertion Engine
-- ============================================================================

local TestHarness = {}
TestHarness.__index = TestHarness

-- Ensure package.path includes script directory and project root
local scriptPath = (arg and arg[0]) or ""
local scriptDir = string.match(scriptPath, "^(.*)[/\\]") or "."
package.path = scriptDir .. "/?.lua;" .. scriptDir .. "/../?.lua;" .. "./?.lua;./Tests/?.lua;" .. package.path

-- Global test execution metrics
TestHarness.results = {
    total = 0,
    passed = 0,
    failed = 0,
    skipped = 0,
    errors = {},
    tierTally = {
        ["Tier 1"] = { total = 0, passed = 0, failed = 0 },
        ["Tier 2"] = { total = 0, passed = 0, failed = 0 },
        ["Tier 3"] = { total = 0, passed = 0, failed = 0 },
        ["Tier 4"] = { total = 0, passed = 0, failed = 0 },
        ["Tier 5"] = { total = 0, passed = 0, failed = 0 }
    },
    featureTally = {}
}

-- CLI Filter configuration
TestHarness.config = {
    filterTier = nil,
    filterFeature = nil,
    verbose = false,
    projectRoot = nil
}

--------------------------------------------------------------------------------
-- 1. ASSERTION LIBRARY
--------------------------------------------------------------------------------

local function FormatValue(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then return "{...}" end
    return string.format("<%s>", t)
end

function TestHarness.AssertEqual(actual, expected, msg)
    if actual ~= expected then
        local detail = string.format("AssertEqual failed: expected %s, got %s. %s",
            FormatValue(expected), FormatValue(actual), msg or "")
        error(detail, 2)
    end
end

function TestHarness.AssertTrue(cond, msg)
    if not cond then
        local detail = string.format("AssertTrue failed: condition was %s. %s",
            FormatValue(cond), msg or "")
        error(detail, 2)
    end
end

function TestHarness.AssertFalse(cond, msg)
    if cond then
        local detail = string.format("AssertFalse failed: condition was %s. %s",
            FormatValue(cond), msg or "")
        error(detail, 2)
    end
end

function TestHarness.AssertNil(val, msg)
    if val ~= nil then
        local detail = string.format("AssertNil failed: value was not nil (%s). %s",
            FormatValue(val), msg or "")
        error(detail, 2)
    end
end

function TestHarness.AssertNotNil(val, msg)
    if val == nil then
        local detail = string.format("AssertNotNil failed: value was nil. %s", msg or "")
        error(detail, 2)
    end
end

function TestHarness.AssertMatch(str, pattern, msg)
    if type(str) ~= "string" or not string.find(str, pattern) then
        local detail = string.format("AssertMatch failed: string %s did not match pattern %q. %s",
            FormatValue(str), pattern, msg or "")
        error(detail, 2)
    end
end

function TestHarness.AssertTableEqual(actual, expected, msg, path)
    path = path or "root"
    if type(actual) ~= "table" or type(expected) ~= "table" then
        if actual ~= expected then
            error(string.format("AssertTableEqual mismatch at %s: expected %s, got %s. %s",
                path, FormatValue(expected), FormatValue(actual), msg or ""), 2)
        end
        return
    end
    for k, v in pairs(expected) do
        TestHarness.AssertTableEqual(actual[k], v, msg, path .. "." .. tostring(k))
    end
    for k, _ in pairs(actual) do
        if expected[k] == nil then
            error(string.format("AssertTableEqual unexpected key at %s: key %s found in actual. %s",
                path, tostring(k), msg or ""), 2)
        end
    end
end

function TestHarness.AssertThrows(func, expectedErrPattern, msg)
    local ok, err = pcall(func)
    if ok then
        error(string.format("AssertThrows failed: function did not throw an error. %s", msg or ""), 2)
    end
    if expectedErrPattern and not string.find(tostring(err), expectedErrPattern) then
        error(string.format("AssertThrows failed: error %q did not match expected pattern %q. %s",
            tostring(err), expectedErrPattern, msg or ""), 2)
    end
end

--------------------------------------------------------------------------------
-- 2. ENVIRONMENT FACTORY & WOW ENGINE MOCK
--------------------------------------------------------------------------------

local FLAVOR_PROFILES = {
    ["wowf"] = {
        version = "1.60.1",
        internalVersion = "70938",
        date = "Nov 14 2026",
        tocVersion = 16001,
        hasGlobalLeaveParty = false
    },
    ["wow_anniversary"] = {
        version = "2.5.6",
        internalVersion = "70577",
        date = "Nov 14 2026",
        tocVersion = 20506,
        hasGlobalLeaveParty = true
    },
    ["wow_classic_era"] = {
        version = "1.15.9",
        internalVersion = "70576",
        date = "Nov 14 2026",
        tocVersion = 11509,
        hasGlobalLeaveParty = true
    },
    ["wow_classic"] = {
        version = "5.5.4",
        internalVersion = "70631",
        date = "Nov 14 2026",
        tocVersion = 50504,
        hasGlobalLeaveParty = true
    },
    ["wow"] = {
        version = "12.1.5",
        internalVersion = "70783",
        date = "Nov 14 2026",
        tocVersion = 120105,
        hasGlobalLeaveParty = true
    }
}

-- Polyfill bit library if not natively present
local function EnsureBitLib()
    if _G.bit then return _G.bit end
    local bit = {}
    function bit.band(a, b)
        local result = 0
        local bitval = 1
        a = a or 0
        b = b or 0
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return result
    end
    function bit.bor(a, b)
        local result = 0
        local bitval = 1
        a = a or 0
        b = b or 0
        while a > 0 or b > 0 do
            if a % 2 == 1 or b % 2 == 1 then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return result
    end
    function bit.bxor(a, b)
        local result = 0
        local bitval = 1
        a = a or 0
        b = b or 0
        while a > 0 or b > 0 do
            local ra = a % 2
            local rb = b % 2
            if (ra == 1 and rb == 0) or (ra == 0 and rb == 1) then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return result
    end
    function bit.rshift(a, n)
        return math.floor((a or 0) / (2 ^ (n or 0)))
    end
    function bit.lshift(a, n)
        return ((a or 0) * (2 ^ (n or 0))) % 4294967296
    end
    function bit.bnot(a)
        return 4294967295 - (a or 0)
    end
    function bit.mod(a, b)
        return (a or 0) % (b or 1)
    end
    return bit
end

function TestHarness.NewEnvironment(flavor, options)
    flavor = flavor or "wowf"
    local profile = FLAVOR_PROFILES[flavor]
    if not profile then
        error("Invalid WoW client flavor: " .. tostring(flavor), 2)
    end

    local env = {}
    env._G = env

    -- Standard library references
    env.pairs = pairs
    env.ipairs = ipairs
    env.next = next
    env.type = type
    env.tostring = tostring
    env.tonumber = tonumber
    env.pcall = pcall
    env.xpcall = xpcall
    env.error = error
    env.assert = assert
    env.select = select
    env.unpack = unpack or table.unpack
    -- Isolate standard library tables per environment (Flaw 5 remediation)
    local function ShallowCopy(src)
        local dest = {}
        if type(src) == "table" then
            for k, v in pairs(src) do
                dest[k] = v
            end
        end
        return dest
    end

    env.string = ShallowCopy(string)
    env.table = ShallowCopy(table)
    env.math = ShallowCopy(math)
    env.bit = ShallowCopy(EnsureBitLib())

    -- Blizzard table / string utility polyfills
    env.wipe = function(t)
        if type(t) == "table" then
            for k in pairs(t) do t[k] = nil end
        end
        return t
    end
    env.tinsert = table.insert
    env.tremove = table.remove

    -- Robust WoW strsplit implementation preserving empty tokens, limits, and special delimiter characters (Flaws 6, 7, 8 remediation)
    env.strsplit = function(delim, str, limit)
        if str == nil then return nil end
        str = tostring(str)
        delim = tostring(delim)
        if delim == "" or #str == 0 then
            return str
        end

        local result = {}
        local startPos = 1

        while true do
            if limit and #result + 1 >= limit then
                table.insert(result, string.sub(str, startPos))
                break
            end

            local findStart, findEnd = string.find(str, delim, startPos, true)
            if not findStart then
                table.insert(result, string.sub(str, startPos))
                break
            end

            table.insert(result, string.sub(str, startPos, findStart - 1))
            startPos = findEnd + 1
        end

        return env.unpack(result)
    end

    env.strtrim = function(str)
        if not str then return "" end
        return string.match(str, "^%s*(.-)%s*$") or ""
    end

    env.strlower = string.lower
    env.strupper = string.upper
    env.format = string.format
    env.gsub = string.gsub
    env.strmatch = string.match
    env.strfind = string.find
    env.strsub = string.sub
    env.strlen = string.len

    -- Harness internal state
    local harnessState = {
        flavor = flavor,
        profile = profile,
        currentTime = 1000.000,
        currentEpoch = 1763105463,
        epochBase = 1763105463 - 1000,
        timerIdCounter = 0,
        timers = {},
        eventListeners = {},
        eventLog = {},
        allFrames = {},
        mockUnits = {
            ["player"] = {
                guid = "Player-4469-01234567",
                name = "Blauto-Camelot",
                isPlayer = true,
                playerControlled = true,
                inCombat = false,
                isDead = false,
                onTaxi = false,
                mapID = 1411
            }
        },
        mockParty = {
            members = { "player" },
            leader = "player",
            pendingInvites = {},
            declined = false,
            leftCount = 0,
            cPartyLeaveCount = 0,
            globalPartyLeaveCount = 0,
            acceptCallCount = 0,
            lastInvited = nil,
            inviteCallCount = 0
        },
        mockChat = {
            registeredPrefixes = {},
            outgoingAddonMessages = {},
            chatFrameMessages = {},
            outgoingChatMessages = {},
            joinedChannels = {},
            leftChannels = {},
            failedChannels = {},
            lockdown = false,
            lastBroadcast = nil
        },
        mockMap = {
            maps = {
                [1411] = { mapID = 1411, name = "Durotar", mapType = 3, parentMapID = 1414 },
                [1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
                [1434] = { mapID = 1434, name = "Stranglethorn Vale", mapType = 3, parentMapID = 1415 },
                [947]  = { mapID = 947,  name = "Azeroth", mapType = 1, parentMapID = 0 },
                [1945] = { mapID = 1945, name = "Outland", mapType = 1, parentMapID = 0 }
            }
        },
        mockInstance = {
            name = "",
            instanceType = "none",
            difficultyID = 0,
            difficultyName = "",
            maxPlayers = 0
        },
        mockNameplates = {},
        mockVignettes = {},
        mockSecrets = {},
        mockUI = {
            hiddenPopups = {},
            soundMuted = false,
            mutedSoundIds = {},
            menuInstanceCount = 0
        },
        reloadExecutionCount = 0,
        lfgQueued = false
    }
    env.__harness = harnessState

    ----------------------------------------------------------------------------
    -- CLOCK & TIMERS
    ----------------------------------------------------------------------------
    env.GetTime = function()
        return harnessState.currentTime
    end

    env.time = function()
        return harnessState.currentEpoch
    end

    env.C_Timer = {}

    -- Stable tie-breaking comparator for deterministic FIFO timer order (Flaw 2 remediation)
    local function TimerComparator(a, b)
        if a.fireTime ~= b.fireTime then
            return a.fireTime < b.fireTime
        end
        return a.id < b.id
    end

    env.C_Timer.After = function(delay, callback)
        if type(callback) ~= "function" then
            error("Usage: C_Timer.After(seconds, callback)", 2)
        end
        harnessState.timerIdCounter = harnessState.timerIdCounter + 1
        local timer = {
            id = harnessState.timerIdCounter,
            fireTime = harnessState.currentTime + math.max(0, delay or 0),
            callback = callback,
            isTicker = false,
            cancelled = false
        }
        table.insert(harnessState.timers, timer)
        table.sort(harnessState.timers, TimerComparator)
    end

    env.C_Timer.NewTicker = function(interval, callback, iterations)
        if type(callback) ~= "function" then
            error("Usage: C_Timer.NewTicker(seconds, callback[, iterations])", 2)
        end
        if not interval or interval <= 0 then
            error("C_Timer.NewTicker interval must be > 0", 2)
        end
        harnessState.timerIdCounter = harnessState.timerIdCounter + 1
        local tickerObj = {
            id = harnessState.timerIdCounter,
            interval = interval,
            fireTime = harnessState.currentTime + interval,
            callback = callback,
            iterations = iterations,
            remaining = iterations,
            isTicker = true,
            cancelled = false
        }
        function tickerObj:Cancel()
            self.cancelled = true
        end
        function tickerObj:IsCancelled()
            return self.cancelled
        end

        -- Ticker with iterations <= 0 cancelled immediately per WoW FrameXML semantics (Flaw 3 remediation)
        if iterations and iterations <= 0 then
            tickerObj.cancelled = true
            return tickerObj
        end

        table.insert(harnessState.timers, tickerObj)
        table.sort(harnessState.timers, TimerComparator)
        return tickerObj
    end

    function env.AdvanceTime(delta)
        delta = delta or 0
        local targetTime = harnessState.currentTime + delta
        local executedCount = 0

        while #harnessState.timers > 0 do
            local nextTimer = harnessState.timers[1]
            if nextTimer.fireTime > targetTime then
                break
            end

            table.remove(harnessState.timers, 1)
            harnessState.currentTime = nextTimer.fireTime

            if not nextTimer.cancelled then
                executedCount = executedCount + 1
                if nextTimer.isTicker then
                    nextTimer.callback(nextTimer)
                    if not nextTimer.cancelled then
                        if nextTimer.remaining then
                            nextTimer.remaining = nextTimer.remaining - 1
                        end
                        if not nextTimer.remaining or nextTimer.remaining > 0 then
                            nextTimer.fireTime = nextTimer.fireTime + nextTimer.interval
                            table.insert(harnessState.timers, nextTimer)
                            table.sort(harnessState.timers, TimerComparator)
                        end
                    end
                else
                    nextTimer.callback()
                end
            end
        end

        -- Re-entrant AdvanceTime protection: monotonically advance virtual clock and epoch (Flaw 4 remediation)
        harnessState.currentTime = math.max(harnessState.currentTime, targetTime)
        harnessState.currentEpoch = harnessState.epochBase + math.floor(harnessState.currentTime)

        -- Execute OnUpdate frame scripts
        for _, frame in ipairs(harnessState.allFrames) do
            if frame:IsShown() and frame.__scripts["OnUpdate"] then
                frame.__scripts["OnUpdate"](frame, delta)
            end
        end

        return executedCount
    end

    ----------------------------------------------------------------------------
    -- EVENT BUS & UI FRAMES
    ----------------------------------------------------------------------------
    local FrameMeta = {}
    FrameMeta.__index = FrameMeta

    function FrameMeta:RegisterEvent(event)
        event = string.upper(event)
        self.__registeredEvents = self.__registeredEvents or {}
        if self.__registeredEvents[event] then return end
        self.__registeredEvents[event] = true
        harnessState.eventListeners[event] = harnessState.eventListeners[event] or {}
        table.insert(harnessState.eventListeners[event], self)
    end

    function FrameMeta:UnregisterEvent(event)
        event = string.upper(event)
        if self.__registeredEvents then
            self.__registeredEvents[event] = nil
        end
        local list = harnessState.eventListeners[event]
        if list then
            for i, f in ipairs(list) do
                if f == self then
                    table.remove(list, i)
                    break
                end
            end
        end
    end

    function FrameMeta:UnregisterAllEvents()
        self.__registeredEvents = {}
        for _, list in pairs(harnessState.eventListeners) do
            for i = #list, 1, -1 do
                if list[i] == self then
                    table.remove(list, i)
                end
            end
        end
    end

    function FrameMeta:IsEventRegistered(event)
        event = string.upper(event)
        return (self.__registeredEvents and self.__registeredEvents[event] == true) or false
    end

    function FrameMeta:SetScript(scriptType, fn)
        self.__scripts[scriptType] = fn
    end

    function FrameMeta:GetScript(scriptType)
        return self.__scripts[scriptType]
    end

    function FrameMeta:HookScript(scriptType, hookFn)
        local orig = self.__scripts[scriptType]
        if orig then
            self.__scripts[scriptType] = function(...)
                orig(...)
                hookFn(...)
            end
        else
            self.__scripts[scriptType] = hookFn
        end
    end

    function FrameMeta:Show()
        if not self.__shown then
            self.__shown = true
            if self.__scripts["OnShow"] then self.__scripts["OnShow"](self) end
        end
    end

    function FrameMeta:Hide()
        if self.__shown then
            self.__shown = false
            if self.__scripts["OnHide"] then self.__scripts["OnHide"](self) end
        end
    end

    function FrameMeta:IsShown()
        return self.__shown
    end

    function FrameMeta:IsVisible()
        return self.__shown
    end

    function FrameMeta:GetParent()
        return self.__parent
    end

    function FrameMeta:SetParent(p)
        self.__parent = p
    end

    function FrameMeta:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
        self.__points = self.__points or {}
        table.insert(self.__points, { point = point, rel = relativeTo, relPoint = relativePoint, x = xOfs, y = yOfs })
        return self
    end

    function FrameMeta:ClearAllPoints()
        self.__points = {}
        return self
    end

    function FrameMeta:SetSize(w, h)
        self.__width = w
        self.__height = h
        return self
    end

    function FrameMeta:SetWidth(w)
        self.__width = w
        return self
    end

    function FrameMeta:GetWidth()
        return self.__width or 100
    end

    function FrameMeta:SetHeight(h)
        self.__height = h
        return self
    end

    function FrameMeta:GetHeight()
        return self.__height or 100
    end

    function FrameMeta:SetClampedToScreen(clamped)
        self.__clamped = clamped
        return self
    end

    function FrameMeta:IsClampedToScreen()
        return self.__clamped == true
    end

    function FrameMeta:SetMovable(m)
        self.__movable = m
        return self
    end

    function FrameMeta:EnableMouse(m)
        self.__mouse = m
        return self
    end

    function FrameMeta:RegisterForDrag(...)
        self.__dragButtons = { ... }
        return self
    end

    function FrameMeta:StartMoving()
        self.__isMoving = true
    end

    function FrameMeta:StopMovingOrSizing()
        self.__isMoving = false
    end

    function FrameMeta:CreateTexture(name, layer)
        local tex = {
            __name = name,
            __layer = layer,
            __shown = true,
            SetTexture = function(self, t) self.__tex = t end,
            GetTexture = function(self) return self.__tex end,
            SetAllPoints = function() end,
            SetPoint = function() end,
            SetSize = function(self, w, h) self.__w = w; self.__h = h end,
            SetVertexColor = function() end,
            Show = function(self) self.__shown = true end,
            Hide = function(self) self.__shown = false end,
            IsShown = function(self) return self.__shown end
        }
        return tex
    end

    function FrameMeta:CreateFontString(name, layer, inherit)
        local fs = {
            __name = name,
            __text = "",
            SetFont = function(self, font, size) self.__font = font; self.__size = size end,
            SetText = function(self, txt) self.__text = tostring(txt or "") end,
            GetText = function(self) return self.__text end,
            SetPoint = function() end,
            SetTextColor = function() end,
            Show = function() end,
            Hide = function() end,
            SetWidth = function() end,
            SetJustifyH = function() end,
            SetWordWrap = function() end
        }
        return fs
    end

    function FrameMeta:Click()
        if self.__enabled == false then return end
        if self.__type == "CheckButton" then self:SetChecked(not self:GetChecked()) end
        if self.__scripts["OnClick"] then
            self.__scripts["OnClick"](self, "LeftButton")
        end
    end

    function FrameMeta:SetChecked(checked)
        self.__checked = checked == true
    end

    function FrameMeta:SetEnabled(enabled) self.__enabled = enabled == true end
    function FrameMeta:IsEnabled() return self.__enabled ~= false end
    function FrameMeta:Enable() self.__enabled = true end
    function FrameMeta:Disable() self.__enabled = false end
    function FrameMeta:EnableMouseWheel(enabled) self.__mouseWheel = enabled == true end

    function FrameMeta:SetFrameStrata(strata)
        self.__strata = strata
    end

    function FrameMeta:GetFrameStrata()
        return self.__strata or "MEDIUM"
    end

    function FrameMeta:GetChecked()
        return self.__checked == true
    end

    env.CreateFrame = function(frameType, name, parent, template)
        local frame = setmetatable({
            __type = frameType or "Frame",
            __name = name,
            __parent = parent or env.UIParent,
            __template = template,
            __scripts = {},
            __registeredEvents = {},
            __shown = true,
            __width = 100,
            __height = 100
        }, FrameMeta)

        if name then
            env[name] = frame
        end
        table.insert(harnessState.allFrames, frame)
        return frame
    end

    env.UIParent = env.CreateFrame("Frame", "UIParent")
    env.Minimap = env.CreateFrame("Frame", "Minimap", env.UIParent)

    function env.FireEvent(event, ...)
        event = string.upper(event)
        if event == "PARTY_INVITE_REQUEST" then harnessState.incomingInviter = ... end
        local listeners = harnessState.eventListeners[event] or {}
        local count = 0

        -- Copy listener slice to withstand unregistrations during dispatch
        local targets = {}
        for _, f in ipairs(listeners) do
            table.insert(targets, f)
        end

        for _, f in ipairs(targets) do
            -- Cross-frame unregistration check: verify frame is still registered before invoking (Flaw 1 remediation)
            if f:IsEventRegistered(event) and f.__scripts["OnEvent"] then
                count = count + 1
                f.__scripts["OnEvent"](f, event, ...)
            end
        end

        table.insert(harnessState.eventLog, {
            event = event,
            args = { ... },
            time = harnessState.currentTime,
            frameCount = count
        })
        return count
    end

    ----------------------------------------------------------------------------
    -- UNIT APIS
    ----------------------------------------------------------------------------
    env.SetUnit = function(unit, data)
        harnessState.mockUnits[unit] = data
    end

    env.UnitGUID = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.guid or nil
    end

    env.UnitName = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.name or nil
    end

    env.UnitIsPlayer = function(unit)
        local u = harnessState.mockUnits[unit]
        if u and u.isPlayer ~= nil then return u.isPlayer end
        local guid = env.UnitGUID(unit)
        return guid and string.sub(guid, 1, 7) == "Player-" or false
    end

    env.UnitPlayerControlled = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.playerControlled or false
    end

    env.UnitAffectingCombat = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.inCombat or false
    end

    env.InCombatLockdown = function()
        local u = harnessState.mockUnits["player"]
        return u and u.inCombat or false
    end

    env.UnitIsDeadOrGhost = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.isDead or false
    end

    env.UnitIsDead = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.isDead or false
    end

    env.UnitOnTaxi = function(unit)
        local u = harnessState.mockUnits[unit]
        return u and u.onTaxi or false
    end

    ----------------------------------------------------------------------------
    -- C_PartyInfo & GROUP APIS
    ----------------------------------------------------------------------------
    local function ModelAcceptInvite()
        local helper = harnessState.incomingInviter or "Helper-Realm"
        local existing = harnessState.mockUnits[helper]
        harnessState.mockUnits.party1 = existing or {
            name = helper, guid = "Player-4469-99999999", isPlayer = true,
            mapID = harnessState.mockUnits.player.mapID,
        }
        harnessState.mockParty.members = { "player", helper }
        harnessState.mockParty.leader = "party1"
    end
    env.C_PartyInfo = {
        InviteUnit = function(name)
            harnessState.mockParty.inviteCallCount = harnessState.mockParty.inviteCallCount + 1
            if #harnessState.mockParty.members >= 5 then
                return false
            end
            harnessState.mockParty.pendingInvites[name] = harnessState.currentTime
            harnessState.mockParty.lastInvited = name
            return true
        end,
        LeaveParty = function()
            harnessState.mockParty.leftCount = harnessState.mockParty.leftCount + 1
            harnessState.mockParty.cPartyLeaveCount = harnessState.mockParty.cPartyLeaveCount + 1
            harnessState.mockParty.members = { "player" }
            env.FireEvent("GROUP_LEFT", 1, "")
            env.FireEvent("GROUP_ROSTER_UPDATE")
            return true
        end,
        IsPartyFull = function()
            return #harnessState.mockParty.members >= 5
        end,
        ConfirmLeaveParty = function()
            return env.C_PartyInfo.LeaveParty()
        end,
        ConfirmAcceptInvite = function()
            harnessState.mockParty.acceptCallCount = harnessState.mockParty.acceptCallCount + 1
            ModelAcceptInvite()
            env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
            env.FireEvent("GROUP_ROSTER_UPDATE")
            return true
        end,
        UninviteUnit = function(name)
            return true
        end
    }

    env.GetNumGroupMembers = function()
        local count = #harnessState.mockParty.members
        return count > 1 and count or 0
    end

    env.IsInGroup = function()
        return #harnessState.mockParty.members > 1
    end

    env.IsInRaid = function()
        return false
    end

    env.UnitIsGroupLeader = function(unit)
        return harnessState.mockParty.leader == unit
    end

    if profile.hasGlobalLeaveParty then
        env.LeaveParty = function()
            harnessState.mockParty.leftCount = harnessState.mockParty.leftCount + 1
            harnessState.mockParty.globalPartyLeaveCount = harnessState.mockParty.globalPartyLeaveCount + 1
            harnessState.mockParty.members = { "player" }
            env.FireEvent("GROUP_LEFT", 1, "")
            env.FireEvent("GROUP_ROSTER_UPDATE")
            return true
        end
    else
        env.LeaveParty = nil
    end

    env.InviteUnit = function(name)
        return env.C_PartyInfo.InviteUnit(name)
    end

    env.AcceptGroup = function()
        harnessState.mockParty.acceptCallCount = harnessState.mockParty.acceptCallCount + 1
        ModelAcceptInvite()
        env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
        env.FireEvent("GROUP_ROSTER_UPDATE")
        return true
    end

    env.DeclineGroup = function()
        harnessState.mockParty.declined = true
    end

    env.IsInLFGQueue = function()
        return harnessState.lfgQueued == true
    end

    ----------------------------------------------------------------------------
    -- C_ChatInfo & CHAT GLOBALS
    ----------------------------------------------------------------------------
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            if not prefix or #prefix > 16 then return false end
            harnessState.mockChat.registeredPrefixes[prefix] = true
            return true
        end,
        IsAddonMessagePrefixRegistered = function(prefix)
            return harnessState.mockChat.registeredPrefixes[prefix] == true
        end,
        GetRegisteredAddonMessagePrefixes = function()
            local list = {}
            for k in pairs(harnessState.mockChat.registeredPrefixes) do
                table.insert(list, k)
            end
            return list
        end,
        SendAddonMessage = function(prefix, message, chatType, target)
            if harnessState.mockChat.lockdown then
                return 3 -- Throttle / restricted
            end
            if not harnessState.mockChat.registeredPrefixes[prefix] then
                return 1 -- InvalidPrefix
            end
            local record = {
                prefix = prefix,
                message = message,
                chatType = chatType,
                target = target,
                time = harnessState.currentTime
            }
            table.insert(harnessState.mockChat.outgoingAddonMessages, record)
            return 0 -- Success
        end,
        InChatMessagingLockdown = function()
            return harnessState.mockChat.lockdown
        end
    }

    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(self, msg)
            table.insert(harnessState.mockChat.chatFrameMessages, msg)
        end,
        GetID = function() return 1 end
    }

    for i = 1, 10 do
        env["ChatFrame" .. i] = {
            AddMessage = function(self, msg) end,
            RemoveChannel = function(self, ch)
                harnessState.mockChat.leftChannels[ch] = true
            end,
            GetID = function() return i end
        }
    end

    env.SendChatMessage = function(msg, chatType, lang, target)
        local record = {
            msg = msg,
            chatType = chatType,
            target = target,
            time = harnessState.currentTime
        }
        table.insert(harnessState.mockChat.outgoingChatMessages, record)
        harnessState.mockChat.lastBroadcast = msg
    end

    -- A pre-existing layer subscription models the player's chat cache. Custom
    -- channels allocate after the five reserved slots, never a synthetic /1.
    harnessState.mockChat.channelSlots = { layer = 6 }
    env.GetChannelName = function(channel)
        if type(channel) == "number" then
            for name, slot in pairs(harnessState.mockChat.channelSlots) do
                if slot == channel then return slot, name end
            end
            return 0, nil
        end
        return harnessState.mockChat.channelSlots[channel] or 0, channel
    end
    env.C_DateAndTime = { GetCurrentCalendarTime = function() return { monthDay = 14, month = 11, year = 2026 } end }
    env.GetRealmName = function() return "Camelot" end
    env.JoinChannelByName = function(ch)
        table.insert(harnessState.mockChat.joinedChannels, ch)
        local slots = harnessState.mockChat.channelSlots
        if not slots[ch] then
            local slot, used = 6, {}
            for _, value in pairs(slots) do used[value] = true end
            while used[slot] do slot = slot + 1 end
            slots[ch] = slot
        end
        return slots[ch]
    end

    env.LeaveChannelByName = function(ch)
        harnessState.mockChat.leftChannels[ch] = true
        harnessState.mockChat.channelSlots[ch] = nil
    end

    env.StaticPopupDialogs = {
        ["PARTY_INVITE"] = {},
        ["PARTY_INVITE_XREALM"] = {}
    }

    env.StaticPopup_FindVisible = function(which)
        if not harnessState.mockUI.hiddenPopups[which] then
            return env.StaticPopupDialogs[which]
        end
        return nil
    end

    env.StaticPopup_Hide = function(which)
        harnessState.mockUI.hiddenPopups[which] = true
    end

    ----------------------------------------------------------------------------
    -- C_Map & WORLD
    ----------------------------------------------------------------------------
    env.C_Map = {
        GetBestMapForUnit = function(unit)
            local u = harnessState.mockUnits[unit]
            return u and u.mapID or nil
        end,
        GetMapInfo = function(uiMapID)
            return harnessState.mockMap.maps[uiMapID]
        end
    }

    env.GetInstanceInfo = function()
        local inst = harnessState.mockInstance
        return inst.name, inst.instanceType, inst.difficultyID, inst.difficultyName, inst.maxPlayers
    end

    env.SetInstanceInfo = function(name, instType, diffID, diffName, maxPlayers)
        harnessState.mockInstance = {
            name = name or "",
            instanceType = instType or "none",
            difficultyID = diffID or 0,
            difficultyName = diffName or "",
            maxPlayers = maxPlayers or 0
        }
    end

    ----------------------------------------------------------------------------
    -- C_NamePlate & C_VignetteInfo
    ----------------------------------------------------------------------------
    env.C_NamePlate = {
        GetNamePlates = function()
            local plates = {}
            for _, p in pairs(harnessState.mockNameplates) do
                table.insert(plates, p)
            end
            return plates
        end,
        GetNamePlateForUnit = function(unit)
            return harnessState.mockNameplates[unit]
        end
    }

    env.C_VignetteInfo = {
        GetVignettes = function()
            local list = {}
            for guid in pairs(harnessState.mockVignettes) do
                table.insert(list, guid)
            end
            return list
        end,
        GetVignetteInfo = function(vignetteGUID)
            return harnessState.mockVignettes[vignetteGUID]
        end
    }

    ----------------------------------------------------------------------------
    -- SOUND & SECURITY
    ----------------------------------------------------------------------------
    env.MuteSoundFile = function(id)
        harnessState.mockUI.soundMuted = true
        harnessState.mockUI.mutedSoundIds[id] = true
        env.soundMuted = true
    end

    env.UnmuteSoundFile = function(id)
        harnessState.mockUI.mutedSoundIds[id] = nil
        local any = false
        for _ in pairs(harnessState.mockUI.mutedSoundIds) do any = true; break end
        harnessState.mockUI.soundMuted = any
    end

    env.GetBuildInfo = function()
        return profile.version, profile.internalVersion, profile.date, profile.tocVersion
    end

    env.issecretvalue = function(val)
        return harnessState.mockSecrets[val] == true
    end

    env.canaccessvalue = function(val)
        return harnessState.mockSecrets[val] ~= true
    end

    env.MarkSecret = function(val)
        harnessState.mockSecrets[val] = true
    end

    env.ReloadUI = function()
        harnessState.reloadExecutionCount = harnessState.reloadExecutionCount + 1
    end

    -- GameTooltip stub
    local tooltipLines = {}
    env.GameTooltip = {
        SetOwner = function() tooltipLines = {} end,
        ClearLines = function() tooltipLines = {} end,
        AddLine = function(self, txt) table.insert(tooltipLines, tostring(txt)) end,
        Show = function() end,
        Hide = function() tooltipLines = {} end,
        GetLines = function() return tooltipLines end
    }

    return env
end

--------------------------------------------------------------------------------
-- 3. MODULE LOADER & PRODUCTION CODE INTEGRATION
--------------------------------------------------------------------------------

local function ResolvePath(path)
    -- Normalize backslashes to forward slashes for Lua io
    return string.gsub(path, "\\", "/")
end

function TestHarness.LoadFileInEnv(filePath, env)
    local f, err = io.open(filePath, "r")
    if not f then
        return nil, string.format("Cannot open file %s: %s", filePath, tostring(err))
    end
    local content = f:read("*a")
    f:close()

    local chunk, loadErr
    if setfenv then
        chunk, loadErr = loadstring(content, "@" .. filePath)
        if chunk then
            setfenv(chunk, env)
        end
    else
        chunk, loadErr = load(content, "@" .. filePath, "t", env)
    end

    if not chunk then
        return nil, string.format("Syntax error loading %s: %s", filePath, tostring(loadErr))
    end

    local ok, runErr = pcall(chunk, "ULO", env.ULO)
    if not ok then
        return nil, string.format("Runtime error executing %s: %s", filePath, tostring(runErr))
    end

    return true
end

function TestHarness.LoadAddonIntoEnv(env, projectRoot)
    projectRoot = projectRoot or TestHarness.config.projectRoot or "."
    local root = ResolvePath(projectRoot)
    local addonRoot = root
    local probe = io.open(root .. "/ULO/Core/Constants.lua", "r")
    if probe then
        probe:close()
        addonRoot = root .. "/ULO"
    end

    -- Production addon files in canonical TOC load order across all subsystems
    local prodFiles = {
        addonRoot .. "/Core/Constants.lua",
        addonRoot .. "/Compatibility/Compat.lua",
        addonRoot .. "/Core/Init.lua",
        addonRoot .. "/Detection/GuidParser.lua",
        addonRoot .. "/Detection/LayerScanner.lua",
        addonRoot .. "/Monitor/RefreshMonitor.lua",
        addonRoot .. "/Monitor/CooldownTracker.lua",
        addonRoot .. "/Coordination/KeywordMatcher.lua",
        addonRoot .. "/Coordination/LayerIntelligence.lua",
        addonRoot .. "/Coordination/InviteManager.lua",
        addonRoot .. "/Coordination/GroupManager.lua",
        addonRoot .. "/Interop/AutoLayerProtocol.lua",
        addonRoot .. "/Interop/OverlordProtocol.lua",
        addonRoot .. "/Interop/NWBInterop.lua",
        addonRoot .. "/UI/MinimapBadge.lua",
        addonRoot .. "/UI/StatusHUD.lua",
        addonRoot .. "/UI/SettingsPanel.lua",
        addonRoot .. "/Core/SlashCommands.lua"
    }

    local hasAllProd = true
    for _, pf in ipairs(prodFiles) do
        local testOpen = io.open(pf, "r")
        if testOpen then
            testOpen:close()
        else
            hasAllProd = false
            break
        end
    end

    if hasAllProd then
        -- Load pure production codebase across all subsystems; zero mock stubs
        for _, pf in ipairs(prodFiles) do
            local ok, err = TestHarness.LoadFileInEnv(pf, env)
            if not ok then
                error(string.format("Failed to load production file %s: %s", pf, tostring(err)), 2)
            end
        end
    else
        -- Fallback to ReferenceModel for headless testing only when production files are absent
        local refPath = root .. "/Tests/ReferenceModel.lua"
        local refOk, refErr = TestHarness.LoadFileInEnv(refPath, env)
        if not refOk then
            error(string.format("Failed to load ReferenceModel.lua: %s", tostring(refErr)), 2)
        end
    end

    return env.ULO
end

--------------------------------------------------------------------------------
-- 4. TEST RUNNER ENGINE
--------------------------------------------------------------------------------

function TestHarness.RunTest(tier, featureId, name, testFunc)
    -- CLI Tier Filter
    if TestHarness.config.filterTier and TestHarness.config.filterTier ~= tier then
        return true
    end

    -- CLI Feature Filter
    if TestHarness.config.filterFeature and TestHarness.config.filterFeature ~= featureId then
        return true
    end

    TestHarness.results.total = TestHarness.results.total + 1

    local tierTally = TestHarness.results.tierTally[tier]
    if tierTally then
        tierTally.total = tierTally.total + 1
    end

    TestHarness.results.featureTally[featureId] = TestHarness.results.featureTally[featureId] or { total = 0, passed = 0, failed = 0 }
    TestHarness.results.featureTally[featureId].total = TestHarness.results.featureTally[featureId].total + 1

    local ok, err = xpcall(testFunc, debug.traceback)
    if ok then
        TestHarness.results.passed = TestHarness.results.passed + 1
        if tierTally then tierTally.passed = tierTally.passed + 1 end
        TestHarness.results.featureTally[featureId].passed = TestHarness.results.featureTally[featureId].passed + 1

        if TestHarness.config.verbose then
            print(string.format("  [PASS] [%s] [%s] %s", tier, featureId, name))
        end
        return true
    else
        TestHarness.results.failed = TestHarness.results.failed + 1
        if tierTally then tierTally.failed = tierTally.failed + 1 end
        TestHarness.results.featureTally[featureId].failed = TestHarness.results.featureTally[featureId].failed + 1

        local errRecord = {
            tier = tier,
            featureId = featureId,
            name = name,
            error = err
        }
        table.insert(TestHarness.results.errors, errRecord)
        print(string.format("  [FAIL] [%s] [%s] %s", tier, featureId, name))
        print(string.format("         Error: %s", tostring(err)))
        return false
    end
end

--- Registers and executes a test within the test harness.
-- Supports 4-argument signature: (tier, featureId, name, testFunc)
-- Supports 3-argument signature: (tier, name, testFunc)
function TestHarness.RegisterTest(tier, arg2, arg3, arg4)
    if type(arg4) == "function" then
        local featureId = arg2
        local name = arg3
        local testFn = arg4
        return TestHarness.RunTest(tier, featureId, name, function()
            local env = TestHarness.NewEnvironment("wowf")
            TestHarness.LoadAddonIntoEnv(env)
            return testFn(env)
        end)
    elseif type(arg3) == "function" then
        local name = arg2
        local testFn = arg3
        local featureId = string.match(name, "%[Adv([AB])%]") or string.match(name, "Adv([AB])")
        if featureId then
            featureId = "Adv" .. featureId
        else
            featureId = (tier == "Tier 5" and "ADV") or "GEN"
        end
        return TestHarness.RunTest(tier, featureId, name, function()
            local env = TestHarness.NewEnvironment("wowf")
            TestHarness.LoadAddonIntoEnv(env)
            return testFn(env)
        end)
    end
end

function TestHarness.Summary()
    print("")
    print("========================================================================")
    print(" Universal Layer Operator (ULO) - Test Suite Execution Summary")
    print("========================================================================")

    local function FormatLine(label, passed, total)
        local pct = total > 0 and (passed / total * 100.0) or 0.0
        return string.format(" %-32s : %3d / %3d passed (%5.1f%%)", label, passed, total, pct)
    end

    local t1 = TestHarness.results.tierTally["Tier 1"]
    local t2 = TestHarness.results.tierTally["Tier 2"]
    local t3 = TestHarness.results.tierTally["Tier 3"]
    local t4 = TestHarness.results.tierTally["Tier 4"]
    local t5 = TestHarness.results.tierTally["Tier 5"]

    print(FormatLine("Tier 1 (Feature Coverage)", t1.passed, t1.total))
    print(FormatLine("Tier 2 (Boundary & Corner Cases)", t2.passed, t2.total))
    print(FormatLine("Tier 3 (Cross-Feature Pairwise)", t3.passed, t3.total))
    print(FormatLine("Tier 4 (Real-World Scenarios)", t4.passed, t4.total))
    print(FormatLine("Tier 5 (Adversarial Hardening)", t5.passed, t5.total))
    print("------------------------------------------------------------------------")
    print(string.format(" TOTAL: %d Tests | Passed: %d | Failed: %d | Skipped: %d",
        TestHarness.results.total, TestHarness.results.passed, TestHarness.results.failed, TestHarness.results.skipped))

    if TestHarness.results.failed == 0 and TestHarness.results.total > 0 then
        print(" VERDICT: ALL TESTS PASSED (Exit Code: 0)")
        print("========================================================================")
        return 0
    elseif TestHarness.results.total == 0 then
        print(" VERDICT: NO TESTS EXECUTED (Filter matched 0 tests) (Exit Code: 1)")
        print("========================================================================")
        return 1
    else
        print(string.format(" VERDICT: %d TEST(S) FAILED (Exit Code: 1)", TestHarness.results.failed))
        print("========================================================================")
        return 1
    end
end

--------------------------------------------------------------------------------
-- 5. CLI ENTRYPOINT & DISPATCH
--------------------------------------------------------------------------------

local function ParseCLIArgs(...)
    local args = { ... }
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--verbose" or a == "-v" then
            TestHarness.config.verbose = true
        elseif string.sub(a, 1, 7) == "--tier=" then
            local val = string.sub(a, 8)
            TestHarness.config.filterTier = "Tier " .. val
        elseif (a == "--tier" or a == "-t") and i < #args then
            i = i + 1
            local val = args[i]
            if string.sub(val, 1, 1) == "=" then
                val = string.sub(val, 2)
            end
            TestHarness.config.filterTier = "Tier " .. val
        elseif string.sub(a, 1, 10) == "--feature=" then
            TestHarness.config.filterFeature = string.upper(string.sub(a, 11))
        elseif (a == "--feature" or a == "-f") and i < #args then
            i = i + 1
            local val = args[i]
            if string.sub(val, 1, 1) == "=" then
                val = string.sub(val, 2)
            end
            TestHarness.config.filterFeature = string.upper(val)
        elseif a == "--help" or a == "-h" then
            print("Universal Layer Operator (ULO) Test Suite Runner")
            print("Usage: lua Tests/TestHarness.lua [OPTIONS]")
            print("Options:")
            print("  --tier=<1|2|3|4|5>, --tier <1|2|3|4|5>    Run only tests for the specified tier")
            print("  -t <1|2|3|4|5>                            Shorthand for --tier")
            print("  --feature=<F01-F17>, --feature <ID>   Run only tests for the specified feature")
            print("  -f <F01-F17>                          Shorthand for --feature")
            print("  --verbose, -v        Display all individual test passes")
            print("  --help, -h           Show this help text")
            os.exit(0)
        end
        i = i + 1
    end
end

function TestHarness.RunAll()
    local root = TestHarness.config.projectRoot or os.getenv("ULO_PROJECT_ROOT") or "."
    root = ResolvePath(root)
    TestHarness.config.projectRoot = root

    print("========================================================================")
    print(" Executing Universal Layer Operator (ULO) Test Suite")
    print(string.format(" Project Root: %s", root))
    if TestHarness.config.filterTier then
        print(string.format(" Filter: Tier = %s", TestHarness.config.filterTier))
    end
    if TestHarness.config.filterFeature then
        print(string.format(" Filter: Feature = %s", TestHarness.config.filterFeature))
    end
    print("========================================================================")

    local tierFiles = {
        { tier = "Tier 1", path = root .. "/Tests/Tier1_FeatureTests.lua" },
        { tier = "Tier 2", path = root .. "/Tests/Tier2_BoundaryTests.lua" },
        { tier = "Tier 3", path = root .. "/Tests/Tier3_PairwiseTests.lua" },
        { tier = "Tier 4", path = root .. "/Tests/Tier4_ScenarioTests.lua" },
        { tier = "Tier 5", path = root .. "/Tests/Tier5_AdversarialHarden.lua" }
    }

    for _, tf in ipairs(tierFiles) do
        if not TestHarness.config.filterTier or TestHarness.config.filterTier == tf.tier then
            print(string.format("\n>> Loading %s (%s)...", tf.tier, tf.path))
            local f, err = io.open(tf.path, "r")
            if not f then
                print(string.format("  [WARNING] Cannot open %s: %s", tf.path, tostring(err)))
            else
                f:close()
                local chunk, loadErr = loadfile(tf.path)
                if not chunk then
                    print(string.format("  [ERROR] Syntax error in %s: %s", tf.path, tostring(loadErr)))
                    TestHarness.results.failed = TestHarness.results.failed + 1
                else
                    local ok, runErr = pcall(chunk, TestHarness)
                    if not ok then
                        print(string.format("  [ERROR] Execution error in %s: %s", tf.path, tostring(runErr)))
                        TestHarness.results.failed = TestHarness.results.failed + 1
                    end
                end
            end
        end
    end

    local exitCode = TestHarness.Summary()
    return exitCode
end

-- If executed directly from command line (arg[0] matches TestHarness.lua)
if arg and arg[0] and string.find(string.lower(arg[0]), "testharness.lua") then
    ParseCLIArgs(unpack(arg))
    local exitCode = TestHarness.RunAll()
    os.exit(exitCode)
end

return TestHarness
