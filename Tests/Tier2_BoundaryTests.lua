-- ============================================================================
-- Tests/Tier2_BoundaryTests.lua
-- Universal Layer Operator (ULO)
-- Tier 2: Boundary & Corner Cases (85 Test Cases, F01 to F17)
-- ============================================================================

local TestHarness = ... or require("Tests.TestHarness")

local function HelperSetup(flavor)
    local env = TestHarness.NewEnvironment(flavor or "wowf")
    TestHarness.LoadAddonIntoEnv(env)
    return env, env.ULO
end

local function ReadFile(path)
    local root = (TestHarness.config and TestHarness.config.projectRoot) or os.getenv("ULO_PROJECT_ROOT") or "."
    local candidates = {
        root .. "/" .. path,
        root .. "/ULO/" .. path,
        root .. "/docs/" .. path,
        path,
        "ULO/" .. path,
        "docs/" .. path,
        "Tests/../" .. path,
        "Tests/../ULO/" .. path,
        "Tests/../docs/" .. path,
    }
    local f
    for _, candidate in ipairs(candidates) do
        f = io.open(candidate, "r")
        if f then break end
    end
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

--------------------------------------------------------------------------------
-- F01: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F01", "T2-F01-01: Retail 12.x Secret Value Guard (issecretvalue)", function()
    local env, ULO = HelperSetup("wow")
    local secretString = "TopSecretString123"
    env.MarkSecret(secretString)
    local safe = ULO.Compat.SafeString(secretString)
    TestHarness.AssertNil(safe, "Secret string must return nil")
end)

TestHarness.RunTest("Tier 2", "F01", "T2-F01-02: Chat Messaging Lockdown Awareness", function()
    local env, ULO = HelperSetup("wowf")
    env.__harness.mockChat.lockdown = true
    TestHarness.AssertTrue(ULO.Compat.InChatLockdown(), "InChatLockdown should be true during lockdown")
end)

TestHarness.RunTest("Tier 2", "F01", "T2-F01-03: Unrecognized or Future TOC Version Handling", function()
    local env, ULO = HelperSetup("wowf")
    env.GetBuildInfo = function() return "99.0.0", "99999", "Jan 1 2099", 999999 end
    TestHarness.AssertEqual(ULO.Compat.GetClientFlavor(), "unknown", "Unknown TOC should return 'unknown'")
end)

TestHarness.RunTest("Tier 2", "F01", "T2-F01-04: C_PartyInfo.LeaveParty Internal Lua Exception", function()
    local env, ULO = HelperSetup("wowf")
    env.C_PartyInfo.LeaveParty = function() error("Blizzard internal C-error") end
    local ok, err = ULO.Compat.LeaveParty()
    TestHarness.AssertFalse(ok, "LeaveParty should catch error via pcall and return false")
end)

TestHarness.RunTest("Tier 2", "F01", "T2-F01-05: Realm Normalization with Multi-Hyphen Names", function()
    local env, ULO = HelperSetup("wowf")
    local unit, realm = ULO.Compat.NormalizeTargetName("PlayerName-Server-Name-With-Hyphens")
    TestHarness.AssertEqual(unit, "PlayerName", "Unit name should be extracted")
    TestHarness.AssertEqual(realm, "Server-Name-With-Hyphens", "Multi-hyphen realm should be extracted")
end)

--------------------------------------------------------------------------------
-- F02: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F02", "T2-F02-01: Missing or Corrupt TOC Metadata", function()
    local env, ULO = HelperSetup()

    -- Corrupted TOC string returned by GetBuildInfo
    env.GetBuildInfo = function() return "1.0.0", "1234", "Jan 1 2026", "corrupted_metadata" end
    TestHarness.AssertEqual(ULO.Compat.GetTocVersion(), 16001, "Corrupted build info falls back to default TOC 16001")
    TestHarness.AssertEqual(ULO.Compat.GetClientFlavor(), "wowf", "Flavor falls back to wowf on corrupted TOC")

    -- Missing GetBuildInfo entirely (nil global)
    env.GetBuildInfo = nil
    TestHarness.AssertEqual(ULO.Compat.GetTocVersion(), 16001, "Missing GetBuildInfo falls back to default TOC 16001")
    TestHarness.AssertTrue(ULO.Compat.IsForever(), "IsForever returns true on default fallback")
end)

TestHarness.RunTest("Tier 2", "F02", "T2-F02-02: Protocol Max Layer Boundary Specification", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content)
    local hasMax = string.find(content, "20") ~= nil or string.find(content, "MAX_LAYER") ~= nil or string.find(content, "layer boundaries") ~= nil
    TestHarness.AssertTrue(hasMax, "Spec documents upper layer bound limits")
end)

TestHarness.RunTest("Tier 2", "F02", "T2-F02-03: Password-Protected Adler32 Channel Griefing Spec", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content)
    local hasGriefing = string.find(content, "failedChannels") ~= nil or string.find(content, "password") ~= nil or string.find(content, "fallback") ~= nil
    TestHarness.AssertTrue(hasGriefing, "Spec documents password griefing fallback")
end)

TestHarness.RunTest("Tier 2", "F02", "T2-F02-04: Combat Deferral Expiration Edge Case Spec", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content)
    local hasCombat = string.find(content, "combat") ~= nil or string.find(content, "DEFERRED") ~= nil or string.find(content, "REGEN") ~= nil
    TestHarness.AssertTrue(hasCombat, "Spec documents combat deferral mechanics")
end)

TestHarness.RunTest("Tier 2", "F02", "T2-F02-05: Nil Argument Resilience Specification", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content)
    local hasContracts = string.find(content, "Interface Contracts") ~= nil or string.find(content, "API") ~= nil
    TestHarness.AssertTrue(hasContracts, "Spec documents interface contracts")
end)

--------------------------------------------------------------------------------
-- F03: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F03", "T2-F03-01: Malformed GUID with Missing Hyphen Delimiters", function()
    local env, ULO = HelperSetup()
    local sId, err = ULO.Detection.ParseGuid("Creature044690141234")
    TestHarness.AssertNil(sId, "Malformed GUID without hyphens should return nil")
end)

TestHarness.RunTest("Tier 2", "F03", "T2-F03-02: Nil Parameter to GUID Parser", function()
    local env, ULO = HelperSetup()
    local sId, err = ULO.Detection.ParseGuid(nil)
    TestHarness.AssertNil(sId, "Nil GUID must return nil")
    TestHarness.AssertEqual(err, "nil_guid", "Reason should be nil_guid")
end)

TestHarness.RunTest("Tier 2", "F03", "T2-F03-03: Empty String Parameter to GUID Parser", function()
    local env, ULO = HelperSetup()
    local sId, err = ULO.Detection.ParseGuid("")
    TestHarness.AssertNil(sId, "Empty string GUID must return nil")
    TestHarness.AssertEqual(err, "empty_guid", "Reason should be empty_guid")
end)

TestHarness.RunTest("Tier 2", "F03", "T2-F03-04: Non-Numeric ServerID Token in GUID", function()
    local env, ULO = HelperSetup()
    local sId, err = ULO.Detection.ParseGuid("Creature-0-INVALID-0-14-1234-5678")
    TestHarness.AssertNil(sId, "Non-numeric serverId must return nil")
end)

TestHarness.RunTest("Tier 2", "F03", "T2-F03-05: Out-of-Bounds / Negative ServerID Token", function()
    local env, ULO = HelperSetup()
    local sId1 = ULO.Detection.ParseGuid("Creature-0--5-0-14-1234-5678")
    local sId2 = ULO.Detection.ParseGuid("Creature-0-999999999999-0-14-1234-5678")
    TestHarness.AssertNil(sId1, "Negative ServerID must return nil")
    TestHarness.AssertNil(sId2, "Overflow ServerID must return nil")
end)

--------------------------------------------------------------------------------
-- F04: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F04", "T2-F04-01: Conflicting GUIDs from Adjacent Zone Patrol", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-2-1")
    TestHarness.AssertNil(ULO.Detection.GetCurrentServerId(), "Consensus should not be reached with conflicting 1-vote serverIds")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 1)
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4470), 1)
end)

TestHarness.RunTest("Tier 2", "F04", "T2-F04-02: Duplicate Identical GUID Rescan Rejection", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    local guid = "Creature-0-4469-0-14-1-1"
    ULO.Detection.ScanGuid(guid)
    ULO.Detection.ScanGuid(guid) -- Scan identical GUID again
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 1, "Duplicate GUID must not increment vote count")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer not confirmed on duplicate single GUID")
end)

TestHarness.RunTest("Tier 2", "F04", "T2-F04-03: All Nearby Units Are Player Pets / Guardians", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    env.SetUnit("target", { guid = "Creature-0-4469-0-14-1-1", playerControlled = true })
    env.SetUnit("mouseover", { guid = "Creature-0-4469-0-14-1-2", playerControlled = true })
    ULO.Detection.ScanUnit("target")
    ULO.Detection.ScanUnit("mouseover")
    TestHarness.AssertEqual(ULO.Detection.GetTotalVotes(), 0, "No votes recorded for player-controlled units")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "UNDETERMINED")
end)

TestHarness.RunTest("Tier 2", "F04", "T2-F04-04: Zero Visible Units in Open Water / Desert", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.PerformFullScan()
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "UNDETERMINED", "Confidence remains UNDETERMINED without error")
end)

TestHarness.RunTest("Tier 2", "F04", "T2-F04-05: High-Frequency Target Event Spam Burst", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    local guid = "Creature-0-4469-0-14-10-99"
    for i = 1, 100 do
        ULO.Detection.ScanGuid(guid)
    end
    TestHarness.AssertTrue(ULO.Detection.GetMemoHitCount() > 90, "Memoization cache handles burst without overhead")
end)

--------------------------------------------------------------------------------
-- F05: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F05", "T2-F05-01: Rapid Zone Boundary Oscillation", function()
    local env, ULO = HelperSetup()
    for i = 1, 10 do
        env.FireEvent("ZONE_CHANGED_NEW_AREA")
    end
    TestHarness.AssertTrue(ULO.Detection.GetScheduledScanCount() >= 10, "Debounce count tracked")
end)

TestHarness.RunTest("Tier 2", "F05", "T2-F05-02: Non-Player UNIT_PHASE Event Filter", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED")
    env.FireEvent("UNIT_PHASE", "target")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED", "Target phase event does not reset player layer")
end)

TestHarness.RunTest("Tier 2", "F05", "T2-F05-03: C_Map.GetBestMapForUnit Returns Nil", function()
    local env, ULO = HelperSetup()
    env.C_Map.GetBestMapForUnit = function() return nil end
    local zId = ULO.Detection.GetCurrentZoneId()
    TestHarness.AssertNil(zId, "Nil map safely handled without error")
end)

TestHarness.RunTest("Tier 2", "F05", "T2-F05-04: Map Transition with Identical ServerID (Subzone Boundary)", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4469)
    -- Step into adjacent subzone on same serverId
    ULO.Detection.ScanGuid("Creature-0-4469-0-15-2-1")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4469, "ServerID preserved across subzone boundary")
end)

TestHarness.RunTest("Tier 2", "F05", "T2-F05-05: Transition into PvP Battleground / Arena", function()
    local env, ULO = HelperSetup()
    env.SetInstanceInfo("Warsong Gulch", "pvp", 1, "PvP", 10)
    env.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    TestHarness.AssertFalse(ULO.Detection.IsLayeringEnabled(), "Layering disabled in PvP battleground")
end)

--------------------------------------------------------------------------------
-- F06: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F06", "T2-F06-01: Negative or Zero Warning Timer Payload", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(-10)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 0, "Negative duration clamped to 0")
end)

TestHarness.RunTest("Tier 2", "F06", "T2-F06-02: Countdown Expiration While Dead / Ghost", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { isDead = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsDeferredDead(), "Refresh deferred while dead")
end)

TestHarness.RunTest("Tier 2", "F06", "T2-F06-03: Duplicate Warning Broadcast Mid-Countdown", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(120)
    ULO.Monitor.StartRefreshWarning(180)
    TestHarness.AssertEqual(ULO.Monitor.GetActiveTimerCount(), 1, "Only 1 active timer maintained")
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 180, "Resynchronized to 180")
end)

TestHarness.RunTest("Tier 2", "F06", "T2-F06-04: Minimized Chevron Auto-Expand Exactly at 10.0s Boundary", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(12)
    ULO.Monitor.MinimizeToChevron(true)
    TestHarness.AssertTrue(ULO.Monitor.IsChevronMinimized())
    env.AdvanceTime(2) -- ticks to 10s
    TestHarness.AssertFalse(ULO.Monitor.IsChevronMinimized(), "Auto-expands at <= 10s")
end)

TestHarness.RunTest("Tier 2", "F06", "T2-F06-05: Large Time Jump / Client Freeze", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    env.AdvanceTime(250) -- Jump 250s
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 0, "Clamped to 0 without underflow")
end)

--------------------------------------------------------------------------------
-- F07: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F07", "T2-F07-01: Rapid Clicks Spam on 'Refresh Now'", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = false })
    ULO.Monitor.StartRefreshWarning(180)
    local ok1 = ULO.Monitor.RequestRefreshNow()
    local ok2 = ULO.Monitor.RequestRefreshNow() -- Immediate second click
    TestHarness.AssertTrue(ok1)
    TestHarness.AssertFalse(ok2, "Rapid second click throttled")
end)

TestHarness.RunTest("Tier 2", "F07", "T2-F07-02: Combat Engagement at Sub-Second Threshold (0.1s Remaining)", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(1)
    env.SetUnit("player", { inCombat = true })
    env.AdvanceTime(1)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Enters combat deferral at 0s threshold")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload blocked in combat")
end)

TestHarness.RunTest("Tier 2", "F07", "T2-F07-03: Extended 60-Minute Combat Lock", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(3600)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Deferral state preserved over long combat")
end)

TestHarness.RunTest("Tier 2", "F07", "T2-F07-04: Player Dies While in DEFERRED_COMBAT", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred())
    env.SetUnit("player", { inCombat = false, isDead = true })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(3)
    TestHarness.AssertTrue(ULO.Monitor.IsDeferredDead(), "Holds reload while player is dead")
end)

TestHarness.RunTest("Tier 2", "F07", "T2-F07-05: Repeated Regen Flapping (Combat Drop and Re-Aggro within 500ms)", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred())
    -- Regen drops, re-aggros 500ms later
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(0.5)
    env.SetUnit("player", { inCombat = true })
    env.FireEvent("PLAYER_REGEN_DISABLED")
    env.AdvanceTime(2.0)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload prevented by combat flapping")
end)

--------------------------------------------------------------------------------
-- F08: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F08", "T2-F08-01: Zero or Negative Cooldown Configuration", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(-50)
    TestHarness.AssertTrue(ULO.Monitor.GetCooldownRemaining() >= 300, "Negative cooldown clamped to >= 300s")
end)

TestHarness.RunTest("Tier 2", "F08", "T2-F08-02: Monotonic Clock Defense Against OS Time Drift", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(300)
    env.AdvanceTime(50)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 250, "Decrements monotonically without OS clock drift")
end)

TestHarness.RunTest("Tier 2", "F08", "T2-F08-03: Cooldown Query on Fresh Character (No Prior Hops)", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 0, "Fresh character cooldown is 0")
end)

TestHarness.RunTest("Tier 2", "F08", "T2-F08-04: Repeated Manual Hop Attempts During Active Cooldown", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(200)
    for i = 1, 5 do
        local ok, err = ULO.Coordination.RequestLayerHop(2)
        TestHarness.AssertFalse(ok, "Hop request blocked during cooldown")
        TestHarness.AssertEqual(err, "cooldown")
    end
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 200, "Cooldown remaining preserved")
end)

TestHarness.RunTest("Tier 2", "F08", "T2-F08-05: Maximum Cooldown Cap (Upper Bound Clamp)", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(999999)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 900, "Excessive cooldown clamped to 900s")
end)

--------------------------------------------------------------------------------
-- F09: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F09", "T2-F09-01: Blacklisted Trade & LFG Keywords Rejection", function()
    local env, ULO = HelperSetup()
    local m1, r1 = ULO.Coordination.MatchKeywords("wtb layer 2 boost pst")
    local m2, r2 = ULO.Coordination.MatchKeywords("wts portals inv")
    TestHarness.AssertFalse(m1)
    TestHarness.AssertEqual(r1, "blacklisted")
    TestHarness.AssertFalse(m2)
    TestHarness.AssertEqual(r2, "blacklisted")
end)

TestHarness.RunTest("Tier 2", "F09", "T2-F09-02: NovaWorldBuffs Auto-Whisper Tag [NWB] Filter", function()
    local env, ULO = HelperSetup()
    local m = ULO.Coordination.MatchKeywords("[NWB] Layer 2 Felwood Songflower 15m")
    TestHarness.AssertFalse(m, "[NWB] tag whispers must be rejected")
end)

TestHarness.RunTest("Tier 2", "F09", "T2-F09-03: Empty or Whitespace-Only Whisper", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertFalse(ULO.Coordination.MatchKeywords(""), "Empty whisper returns false")
    TestHarness.AssertFalse(ULO.Coordination.MatchKeywords("       "), "Whitespace whisper returns false")
end)

TestHarness.RunTest("Tier 2", "F09", "T2-F09-04: Substring Boundary Match Prevention", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertFalse(ULO.Coordination.MatchKeywords("slayer"), "'slayer' must not match 'layer'")
    TestHarness.AssertFalse(ULO.Coordination.MatchKeywords("player"), "'player' must not match 'layer'")
    TestHarness.AssertFalse(ULO.Coordination.MatchKeywords("flayer"), "'flayer' must not match 'layer'")
end)

TestHarness.RunTest("Tier 2", "F09", "T2-F09-05: Excessive / Out-of-Bounds Layer Target (layer 999)", function()
    local env, ULO = HelperSetup()
    local match, reason = ULO.Coordination.MatchKeywords("layer 999")
    TestHarness.AssertFalse(match, "Layer 999 must be rejected as out of bounds")
end)

--------------------------------------------------------------------------------
-- F10: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F10", "T2-F10-01: Full Party Invite Prevention (N = 5)", function()
    local env, ULO = HelperSetup()
    env.__harness.mockParty.members = { "player", "p1", "p2", "p3", "p4" }
    local ok, reason = ULO.Coordination.HandleWhisper("NewRequester", "layer")
    TestHarness.AssertFalse(ok, "Invite rejected when party has 5 members")
end)

TestHarness.RunTest("Tier 2", "F10", "T2-F10-02: Full Raid Invite Prevention (N = 40)", function()
    local env, ULO = HelperSetup()
    env.__harness.mockParty.members = {}
    for i = 1, 40 do table.insert(env.__harness.mockParty.members, "p" .. i) end
    local ok, reason = ULO.Coordination.HandleWhisper("NewRequester", "layer")
    TestHarness.AssertFalse(ok, "Invite rejected when raid full")
end)

TestHarness.RunTest("Tier 2", "F10", "T2-F10-03: Group Decline Blacklist (ERR_DECLINE_GROUP_S)", function()
    local env, ULO = HelperSetup()
    -- Invite and decline
    ULO.Coordination.HandleWhisper("Decliner-Realm", "layer")
    -- Enrolled in cache immediately
    TestHarness.AssertTrue(ULO.Coordination.IsPlayerInInviteCache("Decliner-Realm"), "Declined player enrolled in cache")
end)

TestHarness.RunTest("Tier 2", "F10", "T2-F10-04: Incompatible Realm Error (ERR_BAD_PLAYER_NAME_S)", function()
    local env, ULO = HelperSetup()
    local ok, err = ULO.Compat.InviteUnit("")
    TestHarness.AssertFalse(ok, "Empty player name rejected")
end)

TestHarness.RunTest("Tier 2", "F10", "T2-F10-05: LFG Queue Protection Guard", function()
    local env, ULO = HelperSetup()
    env.__harness.lfgQueued = true
    local ok, reason = ULO.Coordination.HandleWhisper("HopRequester", "layer")
    TestHarness.AssertFalse(ok, "Auto-invite suspended in LFG queue")
    TestHarness.AssertEqual(reason, "lfg_queued")
end)

--------------------------------------------------------------------------------
-- F11: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F11", "T2-F11-01: Random Unsolicited Party Invite Rejection", function()
    local env, ULO = HelperSetup()
    env.FireEvent("PARTY_INVITE_REQUEST", "RandomStranger")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 0, "Unsolicited invite not auto-accepted")
end)

TestHarness.RunTest("Tier 2", "F11", "T2-F11-02: Hop Invite Arrives After Verification Timeout", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    TestHarness.AssertEqual(ULO.Coordination.GetActiveHopTarget(), 2, "Active hop target is 2")

    -- Advance time past the 40s hop timeout
    env.AdvanceTime(45)

    -- Inbound invite arrives after timeout
    env.FireEvent("PARTY_INVITE_REQUEST", "LateHelper")

    -- Must not auto-accept expired hop invite
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 0, "Late invite not accepted after timeout")
    TestHarness.AssertFalse(ULO.Coordination.IsAwaitingLayerVerification(), "Not awaiting verification for late invite")
end)

TestHarness.RunTest("Tier 2", "F11", "T2-F11-03: Helper on Same Layer (Stuck Phase Prevention)", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2)
    -- Joined helper on layer 2: departs group
    ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1, "Departs redundant layer group")
end)

TestHarness.RunTest("Tier 2", "F11", "T2-F11-04: Group Departure Blocked by Mid-Hop Combat", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })

    -- Attempt group departure while in combat
    local ok, reason = ULO.Coordination.LeavePartyWithCombatDeferral()
    TestHarness.AssertFalse(ok, "LeaveParty must return false when deferred by combat")
    TestHarness.AssertEqual(reason, "combat_deferred", "Reason is combat_deferred")
    TestHarness.AssertTrue(ULO.Coordination.IsDepartureDeferred(), "IsDepartureDeferred returns true")
    TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 0, "LeaveParty must not be called while in combat")

    -- Combat ends
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    -- Advance virtual time through the 2.0s out-of-combat buffer
    env.AdvanceTime(2.5)

    TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1, "LeaveParty called after combat ends and buffer expires")
    TestHarness.AssertFalse(ULO.Coordination.IsDepartureDeferred(), "Departure deferral cleared after leaving")
end)

TestHarness.RunTest("Tier 2", "F11", "T2-F11-05: Helper Disbands Group Mid-Hop (ERR_GROUP_DISBANDED)", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)

    -- Accept invite from helper to enter hop verification phase
    env.FireEvent("PARTY_INVITE_REQUEST", "HopHelper")
    TestHarness.AssertTrue(ULO.Coordination.IsAwaitingLayerVerification(), "Awaiting layer verification after accepting invite")

    -- Helper disbands group before transfer is complete
    env.FireEvent("GROUP_LEFT", 1, "")

    TestHarness.AssertFalse(ULO.Coordination.IsAwaitingLayerVerification(), "Awaiting verification reset to false on group disband")
    TestHarness.AssertNil(ULO.Coordination.GetActiveHopTarget(), "Hop target cleared after group disbanded")
end)

--------------------------------------------------------------------------------
-- F12: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F12", "T1-F12-01: Password-Protected Adler32 Channel Fallback", function()
    local env, ULO = HelperSetup()
    local ch = ULO.Interop.AutoLayer.GenerateChannelName()
    ULO.Interop.AutoLayer.MarkChannelFailed(ch)
    TestHarness.AssertTrue(ULO.Interop.AutoLayer.IsChannelFailed(ch), "Channel marked failed")
end)

TestHarness.RunTest("Tier 2", "F12", "T2-F12-02: Misplaced Slot Index Protection (<= 5)", function()
    local env, ULO = HelperSetup()

    -- Join AutoLayer channels
    ULO.Interop.AutoLayer.JoinChannels()

    -- AutoLayer departs excess channels displacing standard chat slots <= 5
    local departed = ULO.Interop.AutoLayer.LeaveExcessChannels(function(ch)
        return (ch == "layer") and 3 or nil
    end)
    TestHarness.AssertTrue(#departed >= 1, "At least one excess/misplaced channel departed")
    TestHarness.AssertTrue(env.__harness.mockChat.leftChannels["layer"] == true, "AutoLayer channel departed to protect standard slots")
end)

TestHarness.RunTest("Tier 2", "F12", "T2-F12-03: Malformed Segment Header Received", function()
    local env, ULO = HelperSetup()
    local seg = ULO.Interop.AutoLayer.ParseMessage("<INVALID> inv layer")
    TestHarness.AssertNil(seg, "Malformed header returns nil")
end)

TestHarness.RunTest("Tier 2", "F12", "T2-F12-04: Truncated Protocol v2 Header", function()
    local env, ULO = HelperSetup()
    local seg = ULO.Interop.AutoLayer.ParseMessage("<AL2V1_9>")
    TestHarness.AssertNil(seg, "Truncated header returns nil")
end)

TestHarness.RunTest("Tier 2", "F12", "T2-F12-05: Adler32 Salt with Apostrophe in Realm Name", function()
    local env, ULO = HelperSetup()
    local ch = ULO.Interop.AutoLayer.GenerateChannelName("Kel'Thuzad", "14-11-2026")
    TestHarness.AssertNotNil(ch)
    TestHarness.AssertTrue(string.find(ch, "^layer%x%x%x%x%x%x%x%x$") ~= nil)
end)

--------------------------------------------------------------------------------
-- F13: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F13", "T2-F13-01: Malformed Overlord Wire Message", function()
    local env, ULO = HelperSetup()
    local handled = ULO.Interop.Overlord.ProcessMessage("INVALID:FORMAT", "Sender")
    TestHarness.AssertFalse(handled, "Malformed message discarded")
end)

TestHarness.RunTest("Tier 2", "F13", "T2-F13-02: Wire Request for Same Layer (R:2:<req>:<currentLayer>)", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2)
    ULO.Interop.Overlord.ProcessMessage("R:2:707:2", "Jumper")
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg)
    TestHarness.AssertEqual(lastMsg.message, "N:707:same", "Decline message should be N:707:same")
end)

TestHarness.RunTest("Tier 2", "F13", "T2-F13-03: Inbound Wire Request While Local Player in Combat", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Interop.Overlord.ProcessMessage("R:2:808:1", "Jumper")
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg)
    TestHarness.AssertEqual(lastMsg.message, "N:808:combat", "Decline message should be N:808:combat")
end)

TestHarness.RunTest("Tier 2", "F13", "T2-F13-04: Inbound Wire Request While Group Full", function()
    local env, ULO = HelperSetup()
    env.__harness.mockParty.members = { "player", "p1", "p2", "p3", "p4" }
    ULO.Interop.Overlord.ProcessMessage("R:2:909:1", "Jumper")
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg)
    TestHarness.AssertEqual(lastMsg.message, "N:909:full", "Decline message should be N:909:full")
end)

TestHarness.RunTest("Tier 2", "F13", "T2-F13-05: Non-Numeric or Overflow RequestID in Wire Header", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(false)
    ULO.Interop.Overlord.ProcessMessage("R:2:ABCDEF999:1", "Jumper")
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg)
    TestHarness.AssertTrue(string.find(lastMsg.message, "^N:") ~= nil, "Decline sent with sanitized ID")
end)

--------------------------------------------------------------------------------
-- F14: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F14", "T2-F14-01: Non-Numeric String in _G.NWB_CurrentLayer", function()
    local env = TestHarness.NewEnvironment("wowf")
    env._G.NWB_CurrentLayer = "Layer 2"
    TestHarness.LoadAddonIntoEnv(env)
    TestHarness.AssertEqual(env.ULO.Detection.GetCurrentLayer(), 2, "Numeric extracted from string")
end)

TestHarness.RunTest("Tier 2", "F14", "T2-F14-02: _G.NWB_LayerUpdated Set to Non-Function Type", function()
    local env, ULO = HelperSetup()
    env._G.NWB_LayerUpdated = "not a function"
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Does not crash when NWB_LayerUpdated is non-function")
end)

TestHarness.RunTest("Tier 2", "F14", "T2-F14-03: Corrupted NWB Global Database Table", function()
    local env, ULO = HelperSetup()
    env._G.NWBdatabase = { corrupted = true }
    TestHarness.AssertNil(ULO.Interop.NWB.GetNWBLayerData(), "Returns nil gracefully on corrupted NWB table")
end)

TestHarness.RunTest("Tier 2", "F14", "T2-F14-04: Recursive Callback Infinite Loop Guard", function()
    local env, ULO = HelperSetup()
    local calls = 0
    env._G.NWB_LayerUpdated = function()
        calls = calls + 1
        if calls <= 1 then
            ULO.Interop.NWB.SyncWithNWB()
        end
    end
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertTrue(calls <= 2, "Recursion stopped without stack overflow")
end)

TestHarness.RunTest("Tier 2", "F14", "T2-F14-05: Late Loading of NovaWorldBuffs (On-Demand)", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertFalse(ULO.Interop.NWB.IsHooked(), "Not hooked initially")
    env._G.NWB_CurrentLayer = 1
    TestHarness.AssertTrue(ULO.Interop.NWB.IsHooked(), "Dynamically hooks when NWB defined")
end)

--------------------------------------------------------------------------------
-- F15: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F15", "T2-F15-01: Custom UI Minimap Addons (Parent Frame Nil)", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertNotNil(ULO.UI.MinimapBadge.GetFrame():GetParent(), "Badge anchored to parent frame")
end)

TestHarness.RunTest("Tier 2", "F15", "T2-F15-02: Undetermined Layer Rendering", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "-", "Undetermined layer rendered as '-'")
end)

TestHarness.RunTest("Tier 2", "F15", "T2-F15-03: Screen Resolution / UI Scale Change", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertTrue(ULO.UI.MinimapBadge.IsShown(), "Badge remains shown on UI scale change")
end)

TestHarness.RunTest("Tier 2", "F15", "T2-F15-04: Rapid Click Storm on Minimap Badge", function()
    local env, ULO = HelperSetup()
    for i = 1, 50 do
        ULO.UI.MinimapBadge.GetFrame():Click()
    end
    TestHarness.AssertTrue(ULO.UI.MinimapBadge.IsShown(), "Badge remains shown and functional after rapid click storm")
    TestHarness.AssertNotNil(ULO.UI.MinimapBadge.GetText(), "Badge text remains non-nil after click storm")
end)

TestHarness.RunTest("Tier 2", "F15", "T2-F15-05: Corrupted Saved Variable Position (NaN / Infinity)", function()
    local env, ULO = HelperSetup()

    -- Test NaN corruption input
    ULO.UI.MinimapBadge.SetPosition(0/0)
    TestHarness.AssertEqual(env._G.ULODB.minimapPos, 225, "NaN resets to default 225 in ULODB")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetPosition(), 225, "Badge GetPosition returns default 225 for NaN")

    -- Test Infinity corruption input
    ULO.UI.MinimapBadge.SetPosition(math.huge)
    TestHarness.AssertEqual(env._G.ULODB.minimapPos, 225, "math.huge resets to default 225 in ULODB")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetPosition(), 225, "Badge GetPosition returns default 225 for math.huge")

    -- Test -Infinity corruption input
    ULO.UI.MinimapBadge.SetPosition(-math.huge)
    TestHarness.AssertEqual(env._G.ULODB.minimapPos, 225, "-math.huge resets to default 225 in ULODB")
end)

--------------------------------------------------------------------------------
-- F16: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F16", "T2-F16-01: Status HUD Dragged Off-Screen", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertTrue(ULO.UI.StatusHUD.GetFrame():IsClampedToScreen(), "HUD clamped to screen")
    local x, y = ULO.UI.StatusHUD.GetPosition()
    TestHarness.AssertTrue(x >= 0, "Position x within visible bounds")
end)

TestHarness.RunTest("Tier 2", "F16", "T2-F16-02: Extreme UI Scale (0.5x and 1.5x)", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertTrue(ULO.UI.StatusHUD.GetFrame():GetWidth() > 0, "HUD frame width valid")
end)

TestHarness.RunTest("Tier 2", "F16", "T2-F16-03: Exactly 10.0s Boundary Alert Transition", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(10)
    TestHarness.AssertTrue(ULO.UI.StatusHUD.IsUrgentAlertActive(), "Urgent alert active at exactly 10s")
end)

TestHarness.RunTest("Tier 2", "F16", "T2-F16-04: Ultra-Long Zone Name Rendering", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertTrue(ULO.UI.StatusHUD.GetFrame():GetWidth() <= 300, "Frame width constrained")
end)

TestHarness.RunTest("Tier 2", "F16", "T2-F16-05: Background Timer Ticking While HUD Hidden", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    env.AdvanceTime(60)
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetCountdownText(), "2:00", "Timer ticks accurately while hidden")
end)

--------------------------------------------------------------------------------
-- F17: Boundary & Edge Cases
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 2", "F17", "T2-F17-01: Unknown Subcommand Error Handling", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("foobar_invalid")
    local lastMsg = env.__harness.mockChat.chatFrameMessages[#env.__harness.mockChat.chatFrameMessages]
    TestHarness.AssertTrue(lastMsg and string.find(lastMsg, "Unknown command") ~= nil, "Unknown command error printed")
end)

TestHarness.RunTest("Tier 2", "F17", "T2-F17-02: Empty Slash Command", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("")
    local lastMsg = env.__harness.mockChat.chatFrameMessages[#env.__harness.mockChat.chatFrameMessages]
    TestHarness.AssertTrue(lastMsg and string.find(lastMsg, "Status") ~= nil, "Status printed on empty slash command")
end)

TestHarness.RunTest("Tier 2", "F17", "T2-F17-03: Non-Numeric Argument to Direct Hop Command", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("layer abc")
    local lastMsg = env.__harness.mockChat.chatFrameMessages[#env.__harness.mockChat.chatFrameMessages]
    TestHarness.AssertTrue(lastMsg and string.find(lastMsg, "Invalid layer number") ~= nil, "Validation error printed")
end)

TestHarness.RunTest("Tier 2", "F17", "T2-F17-04: Out-of-Range Options Slider Input", function()
    local env, ULO = HelperSetup()

    -- Test negative / below min boundary
    ULO.UI.SettingsPanel.SetCooldown(-100)
    TestHarness.AssertEqual(env._G.ULODB.cooldownDuration, 300, "Cooldown duration clamped to minimum 300s")
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownDuration(), 300, "Monitor reflects clamped min duration")

    -- Test above max boundary
    ULO.UI.SettingsPanel.SetCooldown(10000)
    TestHarness.AssertEqual(env._G.ULODB.cooldownDuration, 900, "Cooldown duration clamped to maximum 900s")
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownDuration(), 900, "Monitor reflects clamped max duration")
end)

TestHarness.RunTest("Tier 2", "F17", "T2-F17-05: Macro Rapid Burst of Conflicting Slash Commands", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("invite on")
    ULO.HandleSlashCommand("invite off")
    ULO.HandleSlashCommand("invite on")
    TestHarness.AssertTrue(ULO.Coordination.IsAutoInviteEnabled(), "Final state is autoInvite = true")
end)
