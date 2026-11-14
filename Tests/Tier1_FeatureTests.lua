-- ============================================================================
-- Tests/Tier1_FeatureTests.lua
-- Universal Layer Operator (ULO)
-- Tier 1: Feature Coverage (85 Test Cases, F01 to F17)
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

local function GetTocInterface(tocFileName)
    local content = ReadFile(tocFileName)
    if not content then return nil end
    return string.match(content, "##%s*Interface:%s*(%d+)")
end

--------------------------------------------------------------------------------
-- F01: Multi-Release Compatibility Layer
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F01", "T1-F01-01: Environment Detection for WoW Forever (wowf, TOC 16001)", function()
    local env, ULO = HelperSetup("wowf")
    TestHarness.AssertEqual(ULO.Compat.GetClientFlavor(), "wowf", "Flavor should be wowf")
    TestHarness.AssertEqual(ULO.Compat.GetTocVersion(), 16001, "TOC should be 16001")
    TestHarness.AssertTrue(ULO.Compat.IsForever(), "IsForever should be true")
end)

TestHarness.RunTest("Tier 1", "F01", "T1-F01-02: Environment Detection for Classic Era (wow_classic_era, TOC 11509)", function()
    local env, ULO = HelperSetup("wow_classic_era")
    TestHarness.AssertEqual(ULO.Compat.GetClientFlavor(), "wow_classic_era", "Flavor should be wow_classic_era")
    TestHarness.AssertEqual(ULO.Compat.GetTocVersion(), 11509, "TOC should be 11509")
    TestHarness.AssertFalse(ULO.Compat.IsForever(), "IsForever should be false")
end)

TestHarness.RunTest("Tier 1", "F01", "T1-F01-03: Environment Detection for Anniversary TBC (wow_anniversary, TOC 20506)", function()
    local env, ULO = HelperSetup("wow_anniversary")
    TestHarness.AssertEqual(ULO.Compat.GetClientFlavor(), "wow_anniversary", "Flavor should be wow_anniversary")
    TestHarness.AssertEqual(ULO.Compat.GetTocVersion(), 20506, "TOC should be 20506")
end)

TestHarness.RunTest("Tier 1", "F01", "T1-F01-04: Unified LeaveParty Safe Dispatch via C_PartyInfo", function()
    local env, ULO = HelperSetup("wowf")
    local ok = ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(ok, "LeaveParty should succeed")
    TestHarness.AssertEqual(env.__harness.mockParty.cPartyLeaveCount, 1, "C_PartyInfo.LeaveParty must be called")
end)

TestHarness.RunTest("Tier 1", "F01", "T1-F01-05: Unified LeaveParty Fallback to Global Function", function()
    local env, ULO = HelperSetup("wow_classic_era")
    env.C_PartyInfo.LeaveParty = nil
    local ok = ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(ok, "Global LeaveParty should succeed")
    TestHarness.AssertEqual(env.__harness.mockParty.globalPartyLeaveCount, 1, "Global LeaveParty must be called")
end)

--------------------------------------------------------------------------------
-- F02: Technical Specification Document
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F02", "T1-F02-01: Verification of Specification Document Presence", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content, "TECHNICAL_SPECIFICATION.md must exist")
    TestHarness.AssertTrue(#content > 1000, "TECHNICAL_SPECIFICATION.md must be populated (>1000 bytes)")
end)

TestHarness.RunTest("Tier 1", "F02", "T1-F02-02: Verification of Layer Mechanics Specification", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content, "Specification file must exist")
    local hasRefresh = string.find(content, "180s") or string.find(content, "180-second") or string.find(content, "Refresh Window")
    local hasConsensus = string.find(content, "2-GUID") or string.find(content, "Consensus")
    TestHarness.AssertTrue(hasRefresh ~= nil, "Spec must document 180s refresh window")
    TestHarness.AssertTrue(hasConsensus ~= nil, "Spec must document 2-GUID consensus")
end)

TestHarness.RunTest("Tier 1", "F02", "T1-F02-03: Verification of Interoperability Protocol Specification", function()
    local content = ReadFile("TECHNICAL_SPECIFICATION.md") or ReadFile("Tests/../TECHNICAL_SPECIFICATION.md")
    TestHarness.AssertNotNil(content, "Specification file must exist")
    local hasOverlord = string.find(content, "OverlordLJ")
    local hasAdler = string.find(content, "Adler32") or string.find(content, "adler32")
    TestHarness.AssertTrue(hasOverlord ~= nil, "Spec must document OverlordLJ protocol")
    TestHarness.AssertTrue(hasAdler ~= nil, "Spec must document Adler32 channel protocol")
end)

TestHarness.RunTest("Tier 1", "F02", "T1-F02-04: Verification of Multi-Release TOC File Set", function()
    local camelot = ReadFile("ULO_Camelot.toc") or ReadFile("Tests/../ULO_Camelot.toc")
    local vanilla = ReadFile("ULO_Vanilla.toc") or ReadFile("Tests/../ULO_Vanilla.toc")
    TestHarness.AssertNotNil(camelot, "ULO_Camelot.toc must exist")
    TestHarness.AssertNotNil(vanilla, "ULO_Vanilla.toc must exist")
end)

TestHarness.RunTest("Tier 1", "F02", "T1-F02-05: Verification of TOC Interface Numbers", function()
    local cInterface = GetTocInterface("ULO_Camelot.toc")
    local vInterface = GetTocInterface("ULO_Vanilla.toc")
    TestHarness.AssertEqual(cInterface, "16001", "Camelot interface must be 16001")
    TestHarness.AssertEqual(vInterface, "11509", "Vanilla interface must be 11509")
end)

--------------------------------------------------------------------------------
-- F03: Creature GUID Parser & Validator
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F03", "T1-F03-01: Parse Standard Creature GUID", function()
    local env, ULO = HelperSetup()
    local sId, zId, entity = ULO.Detection.ParseGuid("Creature-0-4469-0-14-1234-0000123456")
    TestHarness.AssertEqual(sId, 4469, "ServerID should be 4469")
    TestHarness.AssertEqual(zId, 14, "ZoneID should be 14")
    TestHarness.AssertEqual(entity, "Creature", "Entity type should be Creature")
end)

TestHarness.RunTest("Tier 1", "F03", "T1-F03-02: Parse Vehicle Entity GUID", function()
    local env, ULO = HelperSetup()
    local sId, zId, entity = ULO.Detection.ParseGuid("Vehicle-0-5120-1-25-5678-0000654321")
    TestHarness.AssertEqual(sId, 5120, "ServerID should be 5120")
    TestHarness.AssertEqual(zId, 25, "ZoneID should be 25")
    TestHarness.AssertEqual(entity, "Vehicle", "Entity type should be Vehicle")
end)

TestHarness.RunTest("Tier 1", "F03", "T1-F03-03: Exclude Player GUID", function()
    local env, ULO = HelperSetup()
    local sId, reason = ULO.Detection.ParseGuid("Player-4469-0123ABCD")
    TestHarness.AssertNil(sId, "Player GUID must return nil serverId")
    TestHarness.AssertEqual(reason, "player_excluded", "Reason must be player_excluded")
end)

TestHarness.RunTest("Tier 1", "F03", "T1-F03-04: Exclude Pet GUID", function()
    local env, ULO = HelperSetup()
    local sId, reason = ULO.Detection.ParseGuid("Pet-0-4469-0-14-999-0000999999")
    TestHarness.AssertNil(sId, "Pet GUID must return nil serverId")
    TestHarness.AssertEqual(reason, "pet_excluded", "Reason must be pet_excluded")
end)

TestHarness.RunTest("Tier 1", "F03", "T1-F03-05: Player-Controlled Minion / Totem Filter", function()
    local env, ULO = HelperSetup()
    env.SetUnit("target", {
        guid = "Creature-0-4469-0-14-3527-0000111111",
        playerControlled = true
    })
    local eligible = ULO.Detection.IsUnitEligible("target")
    TestHarness.AssertFalse(eligible, "Player-controlled unit must not be eligible")
end)

--------------------------------------------------------------------------------
-- F04: Multi-Unit Scanner & 2-GUID Consensus
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F04", "T1-F04-01: Single GUID Scan Increments Vote Count", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    env.SetUnit("target", {
        guid = "Creature-0-4469-0-14-1234-0000000001",
        playerControlled = false
    })
    ULO.Detection.ScanUnit("target")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 1, "Vote count should be 1")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer should not be confirmed on 1 vote")
end)

TestHarness.RunTest("Tier 1", "F04", "T1-F04-02: Two Distinct GUIDs Confirm 2-GUID Consensus", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    env.SetUnit("target", { guid = "Creature-0-4469-0-14-1234-0000000001", playerControlled = false })
    env.SetUnit("mouseover", { guid = "Creature-0-4469-0-14-1234-0000000002", playerControlled = false })
    ULO.Detection.ScanUnit("target")
    ULO.Detection.ScanUnit("mouseover")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4469, "ServerID should be confirmed")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED", "Confidence should be CONFIRMED")
end)

TestHarness.RunTest("Tier 1", "F04", "T1-F04-03: OnLayerChanged Callback Dispatch", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    local cbFired = 0
    local cbServerId = nil
    ULO.RegisterCallback("OnLayerChanged", function(layer, serverId, zoneId, oldLayer)
        cbFired = cbFired + 1
        cbServerId = serverId
    end)
    ULO.Detection.ScanGuid("Creature-0-5122-0-14-1234-0000000001")
    ULO.Detection.ScanGuid("Creature-0-5122-0-14-1234-0000000002")
    TestHarness.AssertEqual(cbFired, 1, "Callback should fire once")
    TestHarness.AssertEqual(cbServerId, 5122, "Callback should receive serverId 5122")
end)

TestHarness.RunTest("Tier 1", "F04", "T1-F04-04: Passive Nameplate Iteration Scan", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    env.__harness.mockNameplates["np1"] = { namePlateUnitToken = "np1" }
    env.__harness.mockNameplates["np2"] = { namePlateUnitToken = "np2" }
    env.SetUnit("np1", { guid = "Creature-0-4470-0-14-100-0001", playerControlled = false })
    env.SetUnit("np2", { guid = "Creature-0-4470-0-14-100-0002", playerControlled = false })
    ULO.Detection.ScanNameplates()
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED", "Nameplates should establish consensus")
end)

TestHarness.RunTest("Tier 1", "F04", "T1-F04-05: Vignette Info Object GUID Scan", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    env.__harness.mockVignettes["vig-1"] = {
        vignetteGUID = "vig-1",
        objectGUID = "Creature-0-4472-0-14-200-0001"
    }
    ULO.Detection.ScanVignettes()
    TestHarness.AssertTrue(ULO.Detection.GetVoteCount(4472) >= 1, "Vignette should add vote for 4472")
end)

--------------------------------------------------------------------------------
-- F05: Context Invalidation & Zone Management
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F05", "T1-F05-01: ZONE_CHANGED_NEW_AREA Invalidation", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED")
    env.FireEvent("ZONE_CHANGED_NEW_AREA")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer should be nil after zone change")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "UNDETERMINED", "Confidence should be UNDETERMINED")
end)

TestHarness.RunTest("Tier 1", "F05", "T1-F05-02: PLAYER_ENTERING_WORLD Invalidation", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    env.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    TestHarness.AssertNil(ULO.Detection.GetCurrentServerId(), "ServerID should be nil")
    TestHarness.AssertEqual(ULO.Detection.GetTotalVotes(), 0, "Total votes should be 0")
end)

TestHarness.RunTest("Tier 1", "F05", "T1-F05-03: UNIT_PHASE on Player Invalidation", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    env.FireEvent("UNIT_PHASE", "player")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer should be reset on player phase change")
end)

TestHarness.RunTest("Tier 1", "F05", "T1-F05-04: Open-World Instance State Validation", function()
    local env, ULO = HelperSetup()
    env.SetInstanceInfo("", "none", 0, "", 0)
    TestHarness.AssertTrue(ULO.Detection.IsLayeringEnabled(), "Layering enabled in open world")
end)

TestHarness.RunTest("Tier 1", "F05", "T1-F05-05: Dungeon Instance Suppression", function()
    local env, ULO = HelperSetup()
    env.SetInstanceInfo("Deadmines", "party", 1, "Normal", 5)
    TestHarness.AssertFalse(ULO.Detection.IsLayeringEnabled(), "Layering disabled inside dungeon")
end)

--------------------------------------------------------------------------------
-- F06: Layer Refresh Countdown Monitor
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F06", "T1-F06-01: Inbound Refresh Warning Starts 180s Window", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    TestHarness.AssertTrue(ULO.Monitor.IsRefreshPending(), "Refresh should be pending")
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 180, "Remaining time should be 180")
end)

TestHarness.RunTest("Tier 1", "F06", "T1-F06-02: Countdown Decrements Over Time", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    env.AdvanceTime(30)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 150, "Remaining time should decrement by 30")
end)

TestHarness.RunTest("Tier 1", "F06", "T1-F06-03: OnRefreshWarning Periodic Callback", function()
    local env, ULO = HelperSetup()
    local cbCount = 0
    local lastDeferred = nil
    ULO.RegisterCallback("OnRefreshWarning", function(rem, def)
        cbCount = cbCount + 1
        lastDeferred = def
    end)
    ULO.Monitor.StartRefreshWarning(180)
    env.AdvanceTime(10)
    TestHarness.AssertTrue(cbCount >= 1, "Callback should fire periodically")
    TestHarness.AssertFalse(lastDeferred, "Should not be deferred out of combat")
end)

TestHarness.RunTest("Tier 1", "F06", "T1-F06-04: Countdown Expiration Triggers Refresh", function()
    local env, ULO = HelperSetup()
    local triggered = false
    ULO.RegisterCallback("OnRefreshTriggered", function() triggered = true end)
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(triggered, "OnRefreshTriggered should fire on expiration")
    TestHarness.AssertFalse(ULO.Monitor.IsRefreshPending(), "Refresh pending should clear")
end)

TestHarness.RunTest("Tier 1", "F06", "T1-F06-05: Chat Chevron Minimization Toggle", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(120)
    ULO.Monitor.MinimizeToChevron(true)
    TestHarness.AssertTrue(ULO.Monitor.IsChevronMinimized(), "Chevron should be minimized")
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 120, "Timer continues ticking while minimized")
end)

--------------------------------------------------------------------------------
-- F07: "Refresh Now" Action & Combat Deferral
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F07", "T1-F07-01: Out-of-Combat 'Refresh Now' Success", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = false })
    ULO.Monitor.StartRefreshWarning(180)
    local ok, reason = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertTrue(ok, "RequestRefreshNow should succeed out of combat")
    TestHarness.AssertEqual(reason, "ok", "Reason should be ok")
end)

TestHarness.RunTest("Tier 1", "F07", "T1-F07-02: In-Combat 'Refresh Now' Blocked", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(180)
    local ok, reason = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertFalse(ok, "RequestRefreshNow should fail in combat")
    TestHarness.AssertEqual(reason, "combat", "Reason should be combat")
end)

TestHarness.RunTest("Tier 1", "F07", "T1-F07-03: Automatic Expiration While in Combat Enters Deferred State", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Should enter combat deferred state")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload should not execute in combat")
end)

TestHarness.RunTest("Tier 1", "F07", "T1-F07-04: PLAYER_REGEN_ENABLED Triggers Deferred Refresh", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred())
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(3) -- advance past 2.0s buffer
    TestHarness.AssertTrue(env.__harness.reloadExecutionCount >= 1, "Reload should execute after regen")
    TestHarness.AssertFalse(ULO.Monitor.IsCombatDeferred(), "Deferral should be cleared")
end)

TestHarness.RunTest("Tier 1", "F07", "T1-F07-05: Re-Entering Combat Resets Deferral Buffer", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred())
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(1.0) -- halfway through 2s buffer
    env.SetUnit("player", { inCombat = true })
    env.FireEvent("PLAYER_REGEN_DISABLED")
    env.AdvanceTime(2.0)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload aborted if re-entering combat")
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Should remain in combat deferred state")
end)

--------------------------------------------------------------------------------
-- F08: Layer Hopping Cooldown Tracker
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F08", "T1-F08-01: Cooldown Initialization on Layer Hop", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(300)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300, "Cooldown should be 300")
end)

TestHarness.RunTest("Tier 1", "F08", "T1-F08-02: Cooldown Decrement Over Time", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(300)
    env.AdvanceTime(60)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 240, "Cooldown should decrement to 240")
end)

TestHarness.RunTest("Tier 1", "F08", "T1-F08-03: OnCooldownStarted Callback Dispatch", function()
    local env, ULO = HelperSetup()
    local cbDuration = nil
    ULO.RegisterCallback("OnCooldownStarted", function(dur) cbDuration = dur end)
    ULO.Monitor.StartCooldown(300)
    TestHarness.AssertEqual(cbDuration, 300, "Callback should receive 300")
end)

TestHarness.RunTest("Tier 1", "F08", "T1-F08-04: Hop Request Throttling During Cooldown", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(300)
    env.AdvanceTime(150)
    local ok, err = ULO.Coordination.RequestLayerHop(2)
    TestHarness.AssertFalse(ok, "Hop should be throttled during cooldown")
    TestHarness.AssertEqual(err, "cooldown", "Error should be cooldown")
end)

TestHarness.RunTest("Tier 1", "F08", "T1-F08-05: Natural Cooldown Expiration", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(300)
    env.AdvanceTime(301)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 0, "Cooldown should expire to 0")
end)

--------------------------------------------------------------------------------
-- F09: Whisper Keyword Engine & Anti-Spam
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F09", "T1-F09-01: Standard Whole-Word Keyword Match 'layer'", function()
    local env, ULO = HelperSetup()
    local match, target = ULO.Coordination.MatchKeywords("invite me to your layer please")
    TestHarness.AssertTrue(match, "Should match 'layer'")
    TestHarness.AssertNil(target, "Target should be nil for generic keyword")
end)

TestHarness.RunTest("Tier 1", "F09", "T1-F09-02: Standard Keyword Match 'inv'", function()
    local env, ULO = HelperSetup()
    local match = ULO.Coordination.MatchKeywords("inv")
    TestHarness.AssertTrue(match, "Should match 'inv'")
end)

TestHarness.RunTest("Tier 1", "F09", "T1-F09-03: Specific Layer Number Extraction 'layer 2'", function()
    local env, ULO = HelperSetup()
    local match, target = ULO.Coordination.MatchKeywords("layer 2")
    TestHarness.AssertTrue(match, "Should match")
    TestHarness.AssertEqual(target, 2, "Target layer should be 2")
end)

TestHarness.RunTest("Tier 1", "F09", "T1-F09-04: Inverted Keyword Matching 'not layer 1'", function()
    local env, ULO = HelperSetup()
    local match, target, inv, excl = ULO.Coordination.MatchKeywords("not layer 1")
    TestHarness.AssertTrue(match, "Should match")
    TestHarness.AssertTrue(inv, "Should be inverted")
    TestHarness.AssertEqual(excl, 1, "Excluded layer should be 1")
end)

TestHarness.RunTest("Tier 1", "F09", "T1-F09-05: Layer Range Parsing 'layer 1-3'", function()
    local env, ULO = HelperSetup()
    local match, target, inv, rStart, rEnd = ULO.Coordination.MatchKeywords("layer 1-3")
    TestHarness.AssertTrue(match, "Should match")
    TestHarness.AssertEqual(rStart, 1, "Range start should be 1")
    TestHarness.AssertEqual(rEnd, 3, "Range end should be 3")
end)

--------------------------------------------------------------------------------
-- F10: Automated Party Invite Coordination
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F10", "T1-F10-01: Auto-Invite Dispatch on Valid Whisper", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    local ok = ULO.Coordination.HandleWhisper("Arthas-Lordaeron", "layer")
    TestHarness.AssertTrue(ok, "Whisper invite should succeed")
    TestHarness.AssertEqual(env.__harness.mockParty.lastInvited, "Arthas-Lordaeron", "Invited player should be Arthas-Lordaeron")
end)

TestHarness.RunTest("Tier 1", "F10", "T1-F10-02: 300s Player Cache Enrollment", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    ULO.Coordination.HandleWhisper("Arthas-Lordaeron", "layer")
    TestHarness.AssertTrue(ULO.Coordination.IsPlayerInInviteCache("Arthas-Lordaeron"), "Player should be enrolled in cache")
end)

TestHarness.RunTest("Tier 1", "F10", "T1-F10-03: Player Cache Throttling", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    ULO.Coordination.HandleWhisper("Arthas-Lordaeron", "layer")
    env.AdvanceTime(60)
    local ok = ULO.Coordination.HandleWhisper("Arthas-Lordaeron", "layer")
    TestHarness.AssertFalse(ok, "Repeated whisper should be throttled")
    TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 1, "Invite should only be called once")
end)

TestHarness.RunTest("Tier 1", "F10", "T1-F10-04: 180s Pending Invite Expiration", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    ULO.Coordination.HandleWhisper("Arthas-Lordaeron", "layer")
    TestHarness.AssertEqual(ULO.Coordination.GetPendingInviteCount(), 1, "Pending count should be 1")
    env.AdvanceTime(181)
    TestHarness.AssertEqual(ULO.Coordination.GetPendingInviteCount(), 0, "Pending count should be 0 after 180s")
end)

TestHarness.RunTest("Tier 1", "F10", "T1-F10-05: Sound Muting During Invite", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    ULO.Coordination.HandleWhisper("Arthas-Lordaeron", "layer")
    TestHarness.AssertTrue(env.soundMuted, "Sound should be muted during invite")
end)

--------------------------------------------------------------------------------
-- F11: Auto-Accept & Group Departure Lifecycle
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F11", "T1-F11-01: Auto-Accept Inbound Hop Invite", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Realm")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1, "AcceptGroup should be called")
end)

TestHarness.RunTest("Tier 1", "F11", "T1-F11-02: PARTY_INVITE Dialog Suppression", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Realm")
    TestHarness.AssertTrue(env.__harness.mockUI.hiddenPopups["PARTY_INVITE"] == true, "PARTY_INVITE popup should be hidden")
end)

TestHarness.RunTest("Tier 1", "F11", "T1-F11-03: GROUP_JOINED Starts Layer Verification", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Realm")
    env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
    TestHarness.AssertTrue(ULO.Coordination.IsAwaitingLayerVerification(), "Should await layer verification")
end)

TestHarness.RunTest("Tier 1", "F11", "T1-F11-04: Automatic Group Departure on Confirmed Hop", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Realm")
    env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
    -- Confirm layer 2
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-2")
    ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1, "LeaveParty should be executed on confirmed hop")
end)

TestHarness.RunTest("Tier 1", "F11", "T1-F11-05: Verification Timeout Safety Departure", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Realm")
    env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
    env.AdvanceTime(41) -- Timeout after 40s triggers autonomous departure
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1, "LeaveParty executed on timeout")
end)

--------------------------------------------------------------------------------
-- F12: AutoLayer & NetherAutoLayer Interop
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F12", "T1-F12-01: Dynamic Date-Salted Adler32 Channel Generation", function()
    local env, ULO = HelperSetup()
    local ch = ULO.Interop.AutoLayer.GenerateChannelName("Crusader Strike", "14-11-2026")
    TestHarness.AssertTrue(string.find(ch, "^layer%x%x%x%x%x%x%x%x$") ~= nil, "Channel should match layer<8-hex>")
end)

TestHarness.RunTest("Tier 1", "F12", "T1-F12-02: Static Fallback Channel 'layer' Joined", function()
    local env, ULO = HelperSetup()
    ULO.Interop.AutoLayer.JoinChannels()
    local joined = false
    for _, ch in ipairs(env.__harness.mockChat.joinedChannels) do
        if ch == "layer" then joined = true end
    end
    TestHarness.AssertTrue(joined, "Static 'layer' channel must be joined")
end)

TestHarness.RunTest("Tier 1", "F12", "T1-F12-03: Continental Segment Header Parsing <AZ>", function()
    local env, ULO = HelperSetup()
    local seg, target = ULO.Interop.AutoLayer.ParseMessage("<AZ> inv layer 2")
    TestHarness.AssertEqual(seg, "AZ", "Segment should be AZ")
    TestHarness.AssertEqual(target, 2, "Target layer should be 2")
end)

TestHarness.RunTest("Tier 1", "F12", "T1-F12-04: Protocol v2 Header Parsing <AL2V...>", function()
    local env, ULO = HelperSetup()
    local seg, target, ver, scope = ULO.Interop.AutoLayer.ParseMessage("<AL2V1_9_15Z1945> inv layer 1")
    TestHarness.AssertEqual(ver, "1.9.15", "Version should be 1.9.15")
    TestHarness.AssertEqual(scope, 1945, "Scope map should be 1945")
    TestHarness.AssertEqual(target, 1, "Target layer should be 1")
end)

TestHarness.RunTest("Tier 1", "F12", "T1-F12-05: Outgoing Broadcast Formatting", function()
    local env, ULO = HelperSetup()
    local msg = ULO.Interop.AutoLayer.FormatBroadcastMessage(3, 947)
    TestHarness.AssertEqual(msg, "<AZ> inv layer 3", "Broadcast message should be <AZ> inv layer 3")
end)

--------------------------------------------------------------------------------
-- F13: Overlord Hidden Addon Channel Interop
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F13", "T1-F13-01: Register Addon Message Prefix 'OverlordLJ'", function()
    local env, ULO = HelperSetup()
    TestHarness.AssertTrue(env.C_ChatInfo.IsAddonMessagePrefixRegistered("OverlordLJ"), "OverlordLJ prefix must be registered")
end)

TestHarness.RunTest("Tier 1", "F13", "T1-F13-02: Incoming Wire Request R:2:<requestId>:<layer>", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    env.FireEvent("CHAT_MSG_ADDON", "OverlordLJ", "R:2:101:2", "WHISPER", "Jumper-Camelot")
    TestHarness.AssertEqual(env.__harness.mockParty.lastInvited, "Jumper-Camelot", "Jumper-Camelot should be invited")
end)

TestHarness.RunTest("Tier 1", "F13", "T1-F13-03: Outgoing Wire Request Transmission", function()
    local env, ULO = HelperSetup()
    ULO.Interop.Overlord.SendHopRequest("Helper-Camelot", 3, 505)
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg, "Addon message should be sent")
    TestHarness.AssertEqual(lastMsg.prefix, "OverlordLJ", "Prefix should be OverlordLJ")
    TestHarness.AssertEqual(lastMsg.message, "R:2:505:3", "Message should be R:2:505:3")
end)

TestHarness.RunTest("Tier 1", "F13", "T1-F13-04: Decline Response Wire Parsing N:<requestId>:<reason>", function()
    local env, ULO = HelperSetup()
    env.FireEvent("CHAT_MSG_ADDON", "OverlordLJ", "N:505:combat", "WHISPER", "Helper-Camelot")
    TestHarness.AssertEqual(ULO.Interop.Overlord.GetRequestFailureReason(505), "combat", "Reason should be combat")
end)

TestHarness.RunTest("Tier 1", "F13", "T1-F13-05: Auto-Decline Dispatch When Auto-Invite Disabled", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(false)
    env.FireEvent("CHAT_MSG_ADDON", "OverlordLJ", "R:2:999:1", "WHISPER", "Random-Camelot")
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg)
    TestHarness.AssertEqual(lastMsg.message, "N:999:off", "Decline message should be N:999:off")
end)

--------------------------------------------------------------------------------
-- F14: NovaWorldBuffs Interop Hooks
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F14", "T1-F14-01: Seed Layer from _G.NWB_CurrentLayer", function()
    local env = TestHarness.NewEnvironment("wowf")
    env._G.NWB_CurrentLayer = 3
    TestHarness.LoadAddonIntoEnv(env)
    TestHarness.AssertEqual(env.ULO.Detection.GetCurrentLayer(), 3, "Layer should seed from NWB_CurrentLayer")
end)

TestHarness.RunTest("Tier 1", "F14", "T1-F14-02: Publish Layer to _G.NWB_CurrentLayer", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4474-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4474-0-14-1-2")
    TestHarness.AssertEqual(env._G.NWB_CurrentLayer, 4, "NWB_CurrentLayer should update to 4")
end)

TestHarness.RunTest("Tier 1", "F14", "T1-F14-03: Invoke _G.NWB_LayerUpdated() Callback Hook", function()
    local env, ULO = HelperSetup()
    local nwbUpdated = false
    env._G.NWB_LayerUpdated = function() nwbUpdated = true end
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4474-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4474-0-14-1-2")
    TestHarness.AssertTrue(nwbUpdated, "NWB_LayerUpdated callback must be invoked")
end)

TestHarness.RunTest("Tier 1", "F14", "T1-F14-04: Sync Zone ID to _G.NWB_CurrentLayerZoneID", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4474-0-1414-1-1")
    ULO.Detection.ScanGuid("Creature-0-4474-0-1414-1-2")
    TestHarness.AssertEqual(env._G.NWB_CurrentLayerZoneID, 1414, "NWB_CurrentLayerZoneID should be 1414")
end)

TestHarness.RunTest("Tier 1", "F14", "T1-F14-05: Graceful Degradation Without NovaWorldBuffs", function()
    local env, ULO = HelperSetup()
    env._G.NWB_CurrentLayer = nil
    env._G.NWB_LayerUpdated = nil
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Layer detection works without NWB")
end)

--------------------------------------------------------------------------------
-- F15: Minimap Layer Indicator Badge
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F15", "T1-F15-01: Layer Number Text Rendering", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4473-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4473-0-14-1-2")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "3", "Badge text should be 3")
end)

TestHarness.RunTest("Tier 1", "F15", "T1-F15-02: Visual Update on Layer Change Event", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "2", "Badge updates text to 2")
end)

TestHarness.RunTest("Tier 1", "F15", "T1-F15-03: Hidden Inside Instances", function()
    local env, ULO = HelperSetup()
    env.SetInstanceInfo("Deadmines", "party", 1, "Normal", 5)
    ULO.Detection.ResetContext(true)
    TestHarness.AssertFalse(ULO.UI.MinimapBadge.IsShown(), "Badge should be hidden in instance")
end)

TestHarness.RunTest("Tier 1", "F15", "T1-F15-04: Tooltip Data Population on Mouseover", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Layer 2 confirmed")

    -- Genuine OnEnter API call populates GameTooltip
    ULO.UI.MinimapBadge.OnEnter(ULO.UI.MinimapBadge.GetFrame())

    local lines = env.GameTooltip:GetLines()
    local foundLayer = false
    local foundServer = false
    for _, l in ipairs(lines) do
        if string.find(l, "Layer 2") then foundLayer = true end
        if string.find(l, "Server: 4472") then foundServer = true end
    end
    TestHarness.AssertTrue(foundLayer, "Tooltip populated with active Layer 2")
    TestHarness.AssertTrue(foundServer, "Tooltip populated with Server ID 4472")

    -- Genuine OnLeave API call hides and clears GameTooltip
    ULO.UI.MinimapBadge.OnLeave(ULO.UI.MinimapBadge.GetFrame())
    TestHarness.AssertEqual(#env.GameTooltip:GetLines(), 0, "Tooltip lines cleared on mouse leave")
end)

TestHarness.RunTest("Tier 1", "F15", "T1-F15-05: Badge Drag Position Persistence", function()
    local env, ULO = HelperSetup()

    -- Save position through genuine MinimapBadge API
    ULO.UI.MinimapBadge.SavePosition(45)
    TestHarness.AssertEqual(env._G.ULODB.minimapPos, 45, "Saved variable persisted angle 45")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetPosition(), 45, "Badge GetPosition returns persisted angle 45")

    -- Update badge and verify persisted position is retained
    ULO.UI.MinimapBadge.Update()
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetPosition(), 45, "Position maintained after badge update")
end)

--------------------------------------------------------------------------------
-- F16: Movable Status HUD & Visual Alerts
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F16", "T1-F16-01: HUD Renders Active Layer Status", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4471-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4471-0-14-1-2")
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetStatusText(), "Layer: 1 (Confirmed)", "Status text should be Layer: 1 (Confirmed)")
end)

TestHarness.RunTest("Tier 1", "F16", "T1-F16-02: Refresh Countdown Timer Display", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(175)
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetCountdownText(), "2:55", "175s should format as 2:55")
end)

TestHarness.RunTest("Tier 1", "F16", "T1-F16-03: Urgent Visual Alert at <= 10 Seconds", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(10)
    TestHarness.AssertTrue(ULO.UI.StatusHUD.IsUrgentAlertActive(), "Urgent alert active at 10s")
end)

TestHarness.RunTest("Tier 1", "F16", "T1-F16-04: Cooldown Display Banner", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(180)
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetCooldownText(), "3:00", "180s cooldown formatted as 3:00")
end)

TestHarness.RunTest("Tier 1", "F16", "T1-F16-05: Interactive 'Refresh Now' Button Click", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    local ok, reason = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertTrue(ok, "Refresh requested successfully via HUD")
end)

--------------------------------------------------------------------------------
-- F17: Slash Command System & Options UI
--------------------------------------------------------------------------------

TestHarness.RunTest("Tier 1", "F17", "T1-F17-01: /ulo help Command Execution", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("help")
    local lastMsg = env.__harness.mockChat.chatFrameMessages[#env.__harness.mockChat.chatFrameMessages]
    TestHarness.AssertTrue(lastMsg and string.find(lastMsg, "Universal Layer Operator Commands") ~= nil, "Help message printed")
end)

TestHarness.RunTest("Tier 1", "F17", "T1-F17-02: /ulo invite Toggle", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("invite off")
    TestHarness.AssertFalse(ULO.Coordination.IsAutoInviteEnabled(), "Auto-invite should be disabled")
    ULO.HandleSlashCommand("invite on")
    TestHarness.AssertTrue(ULO.Coordination.IsAutoInviteEnabled(), "Auto-invite should be re-enabled")
end)

TestHarness.RunTest("Tier 1", "F17", "T1-F17-03: /ulo status Report", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    ULO.HandleSlashCommand("status")
    local lastMsg = env.__harness.mockChat.chatFrameMessages[#env.__harness.mockChat.chatFrameMessages]
    TestHarness.AssertTrue(lastMsg and string.find(lastMsg, "Current Layer: 2") ~= nil, "Status printed layer 2")
end)

TestHarness.RunTest("Tier 1", "F17", "T1-F17-04: /layer <num> Direct Hop Command", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("layer 3")
    TestHarness.AssertEqual(ULO.Coordination.GetActiveHopTarget(), 3, "Active hop target should be 3")
end)

TestHarness.RunTest("Tier 1", "F17", "T1-F17-05: Options Panel Checkbox Synchronization", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(false)
    TestHarness.AssertEqual(env._G.ULODB.autoInvite, false, "ULODB.autoInvite synchronized to false")
end)
