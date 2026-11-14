-- ============================================================================
-- Tests/Tier5_AdversarialHarden.lua
-- Universal Layer Operator (ULO)
-- Tier 5: Adversarial Coverage Hardening & Edge-Case Stress Suite
-- Consolidated Suite: Part A (17 tests) + Part B (18 tests) = 35 Tests Total
-- Subsystems: Core, Compatibility, Detection, Monitor, Coordination, Interop, UI
-- Authored by: Empirical Challenger 1 & Challenger 2 (Phase 2)
-- Consolidated & Integrated by: Worker Phase 2
-- ============================================================================

local TestHarness = ...
if not TestHarness or type(TestHarness) ~= "table" or not TestHarness.RunTest then
    local scriptPath = (arg and arg[0]) or ""
    local scriptDir = string.match(scriptPath, "^(.*)[/\\]") or "."
    package.path = scriptDir .. "/?.lua;" .. scriptDir .. "/../?.lua;" .. "./?.lua;./Tests/?.lua;" .. package.path
    TestHarness = require("TestHarness")
end

-- Ensure Tier 5 tally exists in TestHarness
TestHarness.results = TestHarness.results or {}
TestHarness.results.tierTally = TestHarness.results.tierTally or {}
TestHarness.results.tierTally["Tier 5"] = TestHarness.results.tierTally["Tier 5"] or { total = 0, passed = 0, failed = 0 }

if arg then
    for _, a in ipairs(arg) do
        if a == "-v" or a == "--verbose" then
            TestHarness.config.verbose = true
        end
    end
end

local function HelperSetup(flavor)
    local env = TestHarness.NewEnvironment(flavor or "wowf")
    TestHarness.LoadAddonIntoEnv(env)
    return env, env.ULO
end

-- Ensure RegisterTest is defined on TestHarness
if type(TestHarness.RegisterTest) ~= "function" then
    TestHarness.RegisterTest = function(tier, arg2, arg3, arg4)
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
end

-- ============================================================================
-- PART A: CORE, DETECTION, MONITOR, INTEROP (17 ADVERSARIAL TESTS)
-- ============================================================================

-- ============================================================================
-- SECTION 1: DETECTION SUBSYSTEM & LAYER CONSENSUS (F03, F04, F05)
-- ============================================================================

-- T5-AdvA-01: GUID Flapping & Interleaved Shard Stream Consensus Resistance
TestHarness.RegisterTest("Tier 5", "AdvA-01", "T5-AdvA-01: GUID Flapping & Interleaved Shard Stream Consensus Resistance", function()
    local env, ULO = HelperSetup("wowf")
    ULO.Detection.ResetContext(false)

    local layerChanges = {}
    ULO.RegisterCallback("OnLayerChanged", function(layer, serverId, zoneId, oldLayer)
        table.insert(layerChanges, { layer = layer, serverId = serverId, zoneId = zoneId, oldLayer = oldLayer })
    end)

    -- Alternating GUID streams: Shard 4469 (Layer 1) vs Shard 4470 (Layer 2)
    -- Stream 1: Shard 4469 Vote 1
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 1, "Shard 4469 should have 1 vote")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer must not be confirmed with only 1 vote")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "ESTIMATED", "Confidence should be ESTIMATED after 1 vote")

    -- Stream 2: Shard 4470 Vote 1
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-2-1")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4470), 1, "Shard 4470 should have 1 vote")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer must not be confirmed with conflicting 1-vote shards")

    -- Stream 3: Shard 4469 Vote 2 -> Hits consensus threshold (2)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 2, "Shard 4469 reached 2 votes")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4469, "ServerID 4469 should be confirmed")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1, "Layer 1 confirmed")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED", "Confidence should be CONFIRMED")
    TestHarness.AssertEqual(#layerChanges, 1, "One OnLayerChanged event fired")
    TestHarness.AssertEqual(layerChanges[1].layer, 1, "Event layer should be 1")
    TestHarness.AssertNil(layerChanges[1].oldLayer, "Previous layer was nil")

    -- Stream 4: Shard 4470 Vote 2 -> Shard 4470 reaches 2 votes, flapping layer to 2
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-2-2")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4470), 2, "Shard 4470 reached 2 votes")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4470, "ServerID should switch to 4470")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Layer 2 confirmed")
    TestHarness.AssertEqual(#layerChanges, 2, "Second OnLayerChanged event fired")
    TestHarness.AssertEqual(layerChanges[2].layer, 2, "New layer is 2")
    TestHarness.AssertEqual(layerChanges[2].oldLayer, 1, "Old layer was 1")

    -- Stream 5: Duplicate GUID replay for 4469 -> Must NOT flip layer back
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 2, "Duplicate GUID must not increment vote count")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4470, "ServerID remains 4470")
    TestHarness.AssertEqual(#layerChanges, 2, "No spurious event fired on duplicate replay")

    -- Stream 6: Fresh 3rd GUID for 4469 -> Shard 4469 takes lead with 3 votes
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-3")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4469), 3, "Shard 4469 now has 3 votes")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4469, "ServerID flips back to 4469")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1, "Layer 1 re-confirmed")
    TestHarness.AssertEqual(#layerChanges, 3, "Third OnLayerChanged event fired")
    TestHarness.AssertEqual(layerChanges[3].layer, 1, "Switched back to layer 1")
    TestHarness.AssertEqual(layerChanges[3].oldLayer, 2, "Old layer was 2")
end)

-- T5-AdvA-02: High-Volume LRU Cache Eviction and GUID Replay Immunity
TestHarness.RegisterTest("Tier 5", "AdvA-02", "T5-AdvA-02: High-Volume LRU Cache Eviction and GUID Replay Immunity", function()
    local env, ULO = HelperSetup("wowf")
    ULO.Detection.ResetContext(false)

    -- Inject 120 distinct GUIDs for Shard 4471 to exceed MAX_CACHE_ENTRIES (100)
    for i = 1, 120 do
        local guid = string.format("Creature-0-4471-0-14-1-%d", i)
        local ok = ULO.Detection.ScanGuid(guid)
        TestHarness.AssertTrue(ok, "GUID should scan successfully")
    end

    TestHarness.AssertEqual(ULO.Detection.GetMemoCacheSize(), 100, "Memo cache size must be capped at 100")
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4471), 120, "Total votes for 4471 should be 120")

    -- Re-scan the first 20 GUIDs that were FIFO evicted from memoCache
    local initialHits = ULO.Detection.GetMemoHitCount()
    for i = 1, 20 do
        local evictedGuid = string.format("Creature-0-4471-0-14-1-%d", i)
        local ok = ULO.Detection.ScanGuid(evictedGuid)
        TestHarness.AssertTrue(ok, "Evicted GUID re-scan should succeed")
    end

    -- Invariant: Replay of evicted GUIDs must NOT inflate the vote count
    TestHarness.AssertEqual(ULO.Detection.GetVoteCount(4471), 120, "Vote count must remain strictly 120 despite cache eviction replay")
    TestHarness.AssertEqual(ULO.Detection.GetMemoHitCount(), initialHits + 20, "Evicted replay must be detected as memo hit via votePool")
    TestHarness.AssertEqual(ULO.Detection.GetMemoCacheSize(), 100, "Memo cache remains clamped at 100")
end)

-- T5-AdvA-03: Rapid-Fire Zone Invalidation Race and Re-entrant Debounce Cancellation
TestHarness.RegisterTest("Tier 5", "AdvA-03", "T5-AdvA-03: Rapid-Fire Zone Invalidation Race and Re-entrant Debounce Cancellation", function()
    local env, ULO = HelperSetup("wowf")
    ULO.Detection.ResetContext(false)

    -- Confirm initial layer
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1)

    -- Simulate rapid zone switching across area boundaries (25 events in rapid succession)
    for i = 1, 25 do
        env.FireEvent("ZONE_CHANGED_NEW_AREA")
        TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Layer must be invalidated immediately")
        TestHarness.AssertNil(ULO.Detection.GetCurrentServerId(), "ServerId must be nil")
        TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "UNDETERMINED", "Confidence must reset to UNDETERMINED")
        env.AdvanceTime(0.01) -- 10ms step between events
    end

    TestHarness.AssertTrue(ULO.Detection.GetScheduledScanCount() >= 25, "All 25 invalidations tracked")

    -- Set up target units in the new zone for when the debounced scan fires
    env.SetUnit("target", { guid = "Creature-0-4472-0-14-1-1" })
    env.SetUnit("mouseover", { guid = "Creature-0-4472-0-14-1-2" })

    -- Advance time by 0.3s (less than 0.5s debounce delay from last event)
    env.AdvanceTime(0.3)
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer(), "Debounce timer must not fire before 0.5s")

    -- Advance time by another 0.3s (total 0.6s since last zone event -> debounce timer fires)
    env.AdvanceTime(0.3)

    -- Invariant: Only the final debounced scan executes, cleanly acquiring the new layer
    TestHarness.AssertEqual(ULO.Detection.GetCurrentServerId(), 4472, "ServerID 4472 acquired from debounced scan")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Layer 2 confirmed from debounced scan")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED", "Confidence confirmed after debounced scan")
end)

-- T5-AdvA-04: Non-Player Unit Infiltration and Vehicle/Creature Metamorphic GUID Fuzzing
TestHarness.RegisterTest("Tier 5", "AdvA-04", "T5-AdvA-04: Non-Player Unit Infiltration and Vehicle/Creature Metamorphic GUID Fuzzing", function()
    local env, ULO = HelperSetup("wowf")
    local P = ULO.Detection.ParseGuid

    -- 1. Invalid / Out-of-bounds ServerIDs
    local s0, err0 = P("Creature-0-0-0-14-1-1")
    TestHarness.AssertNil(s0, "ServerID 0 must be rejected")
    TestHarness.AssertEqual(err0, "out_of_bounds")

    local sNeg, errNeg = P("Creature-0--4469-0-14-1-1")
    TestHarness.AssertNil(sNeg, "Negative ServerID must be rejected")
    TestHarness.AssertEqual(errNeg, "out_of_bounds")

    local sBig, errBig = P("Creature-0-1000000000-0-14-1-1")
    TestHarness.AssertNil(sBig, "Overflow ServerID (>999999999) must be rejected")
    TestHarness.AssertEqual(errBig, "out_of_bounds")

    -- 2. Player and Pet entity exclusions
    local sPlayer, errPlayer = P("Player-4469-01234567")
    TestHarness.AssertNil(sPlayer, "Player entity must be rejected")
    TestHarness.AssertEqual(errPlayer, "player_excluded")

    local sPet, errPet = P("Pet-0-4469-0-14-1-1")
    TestHarness.AssertNil(sPet, "Pet entity must be rejected")
    TestHarness.AssertEqual(errPet, "pet_excluded")

    -- 3. Malformed token formats
    local sBadToken, errBad = P("Creature-0-4469-0-14-1")
    TestHarness.AssertNil(sBadToken, "Incomplete tokens must be rejected")
    TestHarness.AssertEqual(errBad, "malformed_guid")

    local sInvalidType, errType = P("Item-0-4469-0-14-1-1")
    TestHarness.AssertNil(sInvalidType, "Item entity type must be rejected")
    TestHarness.AssertEqual(errType, "invalid_type")

    -- 4. Valid non-creature world entities (Vehicle, GameObject, Vignette)
    local sVeh, zVeh, tVeh, okVeh = P("Vehicle-0-4473-0-14-50-999")
    TestHarness.AssertTrue(okVeh, "Vehicle must be valid for layering")
    TestHarness.AssertEqual(sVeh, 4473)
    TestHarness.AssertEqual(zVeh, 14)
    TestHarness.AssertEqual(tVeh, "Vehicle")

    local sVig, zVig, tVig, okVig = P("Vignette-0-4474-0-14-10-1")
    TestHarness.AssertTrue(okVig, "Vignette must be valid for layering")
    TestHarness.AssertEqual(sVig, 4474)

    -- 5. Unit eligibility with player-controlled flag
    env.SetUnit("target", { guid = "Creature-0-4469-0-14-1-1", playerControlled = true })
    TestHarness.AssertFalse(ULO.Detection.IsUnitEligible("target"), "Player-controlled unit must not be eligible")

    env.SetUnit("target", { guid = "Creature-0-4469-0-14-1-1", playerControlled = false, isPlayer = false, exists = true })
    TestHarness.AssertTrue(ULO.Detection.IsUnitEligible("target"), "Wild creature must be eligible")
end)

-- ============================================================================
-- SECTION 2: MONITOR SUBSYSTEM (REFRESH MONITOR & COOLDOWN TRACKER) (F06, F07, F08)
-- ============================================================================

-- T5-AdvA-05: Re-entrant Refresh Warning and Countdown Preemption Race
TestHarness.RegisterTest("Tier 5", "AdvA-05", "T5-AdvA-05: Re-entrant Refresh Warning and Countdown Preemption Race", function()
    local env, ULO = HelperSetup("wowf")
    env.SetUnit("player", { inCombat = false })

    -- Start initial 180s warning
    ULO.Monitor.StartRefreshWarning(180)
    TestHarness.AssertTrue(ULO.Monitor.IsRefreshPending())
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 180)
    TestHarness.AssertEqual(ULO.Monitor.GetActiveTimerCount(), 1)

    -- Advance virtual time by 60s -> remaining = 120s
    env.AdvanceTime(60)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 120)

    -- Re-entrant preemption: New warning received specifying 90s
    ULO.Monitor.StartRefreshWarning(90)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 90, "Remaining resynchronized to 90s")
    TestHarness.AssertEqual(ULO.Monitor.GetActiveTimerCount(), 1, "Strictly 1 active timer maintained")

    -- Advance time by 80s -> remaining = 10s
    env.AdvanceTime(80)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 10)

    -- Minimize chevron
    ULO.Monitor.MinimizeToChevron(true)
    TestHarness.AssertTrue(ULO.Monitor.IsChevronMinimized())

    -- Advance virtual time by 1s -> remaining = 9s (< 10s boundary)
    env.AdvanceTime(1)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 9)
    TestHarness.AssertFalse(ULO.Monitor.IsChevronMinimized(), "Chevron auto-expands at <= 10s")

    -- Emergency 0s trigger while ticker is active
    local reloadFired = false
    ULO.RegisterCallback("OnRefreshTriggered", function()
        reloadFired = true
    end)

    ULO.Monitor.StartRefreshWarning(0)
    TestHarness.AssertTrue(reloadFired, "Immediate 0s warning triggers refresh execution")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1, "ReloadUI invoked")
    TestHarness.AssertFalse(ULO.Monitor.IsRefreshPending(), "Refresh no longer pending after execution")
    TestHarness.AssertEqual(ULO.Monitor.GetActiveTimerCount(), 0, "All tickers cleanly cancelled")
end)

-- T5-AdvA-06: Combat-Death-Taxi Cascading Deferral State Machine Flip-Flop
TestHarness.RegisterTest("Tier 5", "AdvA-06", "T5-AdvA-06: Combat-Death-Taxi Cascading Deferral State Machine Flip-Flop", function()
    local env, ULO = HelperSetup("wowf")
    env.SetUnit("player", { inCombat = true, isDead = false, onTaxi = false })

    -- Start 2s refresh countdown while player is in combat
    ULO.Monitor.StartRefreshWarning(2)
    env.AdvanceTime(3) -- Countdown reaches 0

    -- Invariant 1: Blocked by combat
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Must be combat-deferred")
    TestHarness.AssertTrue(ULO.Monitor.IsRefreshPending(), "Refresh remains pending while deferred")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "ReloadUI blocked while in combat")

    -- Player exits combat -> PLAYER_REGEN_ENABLED initiates 2.0s grace period
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")

    -- Advance time 1.0s (midway through the 2.0s grace window)
    env.AdvanceTime(1.0)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "ReloadUI withheld during grace period")

    -- Player is struck by lethal damage midway through grace! (Dies)
    env.SetUnit("player", { isDead = true })

    -- Advance time past the original 2.0s grace deadline (1.5s more -> total 2.5s)
    env.AdvanceTime(1.5)

    -- Invariant 2: Switched from combat deferral to death deferral; reload still blocked
    TestHarness.AssertTrue(ULO.Monitor.IsDeferredDead(), "Must switch to death deferral")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "ReloadUI blocked while player is dead")

    -- Player resurrects at spirit healer, but immediately takes a flight taxi
    env.SetUnit("player", { isDead = false, onTaxi = true })
    env.FireEvent("PLAYER_ALIVE")

    -- Invariant 3: Resurrected but on taxi -> deferred by taxi flight
    TestHarness.AssertFalse(ULO.Monitor.IsDeferredDead(), "Death deferral cleared")
    TestHarness.AssertTrue(ULO.Monitor.IsDeferredTaxi(), "Taxi deferral active")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "ReloadUI blocked while on taxi flight")

    -- Flight taxi lands at destination
    env.SetUnit("player", { onTaxi = false })
    env.FireEvent("PLAYER_CONTROL_GAINED")

    -- Invariant 4: Clear of combat, alive, and dismounted -> reload executes cleanly!
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1, "ReloadUI executed after all hazards cleared")
    TestHarness.AssertFalse(ULO.Monitor.IsCombatDeferred(), "Combat deferral cleared")
    TestHarness.AssertFalse(ULO.Monitor.IsDeferredDead(), "Death deferral cleared")
    TestHarness.AssertFalse(ULO.Monitor.IsDeferredTaxi(), "Taxi deferral cleared")
    TestHarness.AssertFalse(ULO.Monitor.IsRefreshPending(), "Refresh completed")
end)

-- T5-AdvA-07: Rapid Combat Regen Flapping (Combat Drops and Re-Aggro within 200ms)
TestHarness.RegisterTest("Tier 5", "AdvA-07", "T5-AdvA-07: Rapid Combat Regen Flapping (Combat Drops and Re-Aggro within 200ms)", function()
    local env, ULO = HelperSetup("wowf")
    env.SetUnit("player", { inCombat = true })

    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Initial combat deferral active")

    -- Flap Cycle 1: Regen enabled, but re-aggros 200ms later
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(0.2)
    env.SetUnit("player", { inCombat = true })
    env.FireEvent("PLAYER_REGEN_DISABLED")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload prevented by Flap 1")

    -- Advance 2.5s while still in combat to confirm grace timer was invalidated
    env.AdvanceTime(2.5)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Prior grace timer invalidated by re-aggro")
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred())

    -- Flap Cycle 2: Regen enabled, re-aggros 400ms later
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(0.4)
    env.SetUnit("player", { inCombat = true })
    env.FireEvent("PLAYER_REGEN_DISABLED")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload prevented by Flap 2")

    -- Final Cycle: Combat drops and remains clear
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")

    -- At 1.9s (just before 2.0s grace window expires), reload must still be pending
    env.AdvanceTime(1.9)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload strictly withheld until full 2.0s buffer")

    -- At 2.1s (grace expired with zero combat re-entry) -> reload executes!
    env.AdvanceTime(0.2)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1, "Reload executed after unbroken 2.0s grace period")
end)

-- T5-AdvA-08: Cooldown Clock Jumps, Timer Warps, and Throttle Bypass Attempts
TestHarness.RegisterTest("Tier 5", "AdvA-08", "T5-AdvA-08: Cooldown Clock Jumps, Timer Warps, and Throttle Bypass Attempts", function()
    local env, ULO = HelperSetup("wowf")

    -- 1. Adversarial duration inputs to StartCooldown
    ULO.Monitor.StartCooldown(-500)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300, "Negative cooldown defaults to configured 300s")

    ULO.Monitor.StartCooldown(0/0) -- NaN
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300, "NaN cooldown defaults to configured 300s")

    ULO.Monitor.StartCooldown(math.huge) -- +Infinity
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300, "Infinity cooldown defaults to configured 300s")

    ULO.Monitor.StartCooldown(1500) -- Exceeds max 900
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 900, "Overflow cooldown clamped to max 900s")

    ULO.Monitor.StartCooldown(50) -- Below min 300 and < 180
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300, "Underflow cooldown clamped to min 300s")

    -- 2. Monotonic clock jump stress
    local expiredCount = 0
    ULO.RegisterCallback("OnCooldownExpired", function()
        expiredCount = expiredCount + 1
    end)

    ULO.Monitor.StartCooldown(300)
    TestHarness.AssertTrue(ULO.Monitor.IsOnCooldown())
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300)

    -- Advance virtual time by 10,000s in a single step
    env.AdvanceTime(10000)

    -- Invariant: Must clamp cleanly to 0 without underflow/negative time
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 0, "Cooldown cleanly clamped to 0")
    TestHarness.AssertFalse(ULO.Monitor.IsOnCooldown(), "IsOnCooldown must be false")
    TestHarness.AssertEqual(expiredCount, 1, "OnCooldownExpired must fire exactly once")

    -- Further time progression produces no ghost events
    env.AdvanceTime(1000)
    TestHarness.AssertEqual(expiredCount, 1, "No additional expiration events after cancellation")
end)

-- T5-AdvA-09: RequestRefreshNow Monotonic Rate Limiting and Backward Clock Warp Resilience
TestHarness.RegisterTest("Tier 5", "AdvA-09", "T5-AdvA-09: RequestRefreshNow Monotonic Rate Limiting and Backward Clock Warp Resilience", function()
    local env, ULO = HelperSetup("wowf")
    env.SetUnit("player", { inCombat = false, isDead = false, onTaxi = false })

    -- Virtual clock at t = 100
    env.__harness.currentTime = 100

    -- First request succeeds
    local ok1, code1 = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertTrue(ok1, "First refresh request should succeed")
    TestHarness.AssertEqual(code1, "ok")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1)

    -- Rapid burst request at t = 100.4 (less than 1.0s gap)
    env.__harness.currentTime = 100.4
    local ok2, code2 = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertFalse(ok2, "Rapid second request within 1.0s must be throttled")
    TestHarness.AssertEqual(code2, "throttled")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1, "No reload on throttled click")

    -- Request at t = 101.5 (> 1.0s gap) succeeds
    env.__harness.currentTime = 101.5
    local ok3, code3 = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertTrue(ok3, "Request after 1.1s gap should succeed")
    TestHarness.AssertEqual(code3, "ok")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 2)

    -- Backward clock warp (simulate client NTP clock rollback to t = 50)
    env.__harness.currentTime = 50
    local okWarp, codeWarp = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertFalse(okWarp, "Backward clock warp must be safely handled without throwing")
    TestHarness.AssertEqual(codeWarp, "throttled", "Clock warp is safely absorbed by rate limiter")
end)

-- ============================================================================
-- SECTION 3: INTEROP SUBSYSTEM (AUTOLAYER, OVERLORD, NWB) (F12, F13, F14)
-- ============================================================================

-- T5-AdvA-10: AutoLayer Adler32 Hash Collision Resistance & Non-Standard Realm Salt
TestHarness.RegisterTest("Tier 5", "AdvA-10", "T5-AdvA-10: AutoLayer Adler32 Hash Collision Resistance & Non-Standard Realm Salt", function()
    local env, ULO = HelperSetup("wowf")
    local Adler32 = ULO.Interop.AutoLayer.Adler32
    local Gen = ULO.Interop.AutoLayer.GenerateChannelName

    -- 1. Boundary strings
    TestHarness.AssertEqual(Adler32(""), "00000001", "Empty string returns 00000001")
    TestHarness.AssertEqual(Adler32(nil), "00000001", "Nil returns 00000001")

    -- 2. Known Adler32 test vectors
    -- 'a' (97): s1 = 1 + 97 = 98, s2 = 98 -> (98 * 65536) + 98 = 6422626 = 0x00620062
    TestHarness.AssertEqual(Adler32("a"), "00620062", "Adler32 of 'a'")

    -- 3. Non-standard realm salts (apostrophes, dashes, UTF-8 sequences, spaces)
    local channel1 = Gen("Kel'Thuzad", "14-11-2026")
    TestHarness.AssertTrue(string.find(channel1, "^layer%x%x%x%x%x%x%x%x$") ~= nil, "Channel name format layer<8-hex>")
    TestHarness.AssertEqual(#channel1, 13, "Channel name length strictly 13 chars")

    local channel2 = Gen("Server-With-Many-Hyphens", "14-11-2026")
    TestHarness.AssertTrue(string.find(channel2, "^layer%x%x%x%x%x%x%x%x$") ~= nil)

    local channel3 = Gen("Ragn\195\169ros", "14-11-2026")
    TestHarness.AssertTrue(string.find(channel3, "^layer%x%x%x%x%x%x%x%x$") ~= nil)

    -- 4. Channel failure tracking
    TestHarness.AssertFalse(ULO.Interop.AutoLayer.IsChannelFailed(channel1))
    ULO.Interop.AutoLayer.MarkChannelFailed(channel1)
    TestHarness.AssertTrue(ULO.Interop.AutoLayer.IsChannelFailed(channel1), "Failed channel recorded")
    TestHarness.AssertFalse(ULO.Interop.AutoLayer.IsChannelFailed(channel2), "Unrelated channel not failed")
    TestHarness.AssertFalse(ULO.Interop.AutoLayer.IsChannelFailed(nil), "Nil channel returns false")
end)

-- T5-AdvA-11: AutoLayer Message Parser Fuzzing & Malformed Packet Injection
TestHarness.RegisterTest("Tier 5", "AdvA-11", "T5-AdvA-11: AutoLayer Message Parser Fuzzing & Malformed Packet Injection", function()
    local env, ULO = HelperSetup("wowf")
    local P = ULO.Interop.AutoLayer.ParseMessage

    -- 1. Valid protocol packets
    local segV2, lV2, verV2, mapV2 = P("<AL2V1_9_15Z1945> inv layer 2")
    TestHarness.AssertEqual(segV2, "AL2", "Protocol v2 segment is AL2")
    TestHarness.AssertEqual(lV2, 2, "Target layer is 2")
    TestHarness.AssertEqual(verV2, "1.9.15", "Version parsed with dots")
    TestHarness.AssertEqual(mapV2, 1945, "Scope map is 1945")

    local segAZ, lAZ = P("<AZ> inv layer 3")
    TestHarness.AssertEqual(segAZ, "AZ")
    TestHarness.AssertEqual(lAZ, 3)

    local segOL, lOL = P("<OL> inv layer 1")
    TestHarness.AssertEqual(segOL, "OL")
    TestHarness.AssertEqual(lOL, 1)

    -- 2. Adversarial / Malformed packet injections -> Must return nil without exceptions
    TestHarness.AssertNil(P(""), "Empty message returns nil")
    TestHarness.AssertNil(P(nil), "Nil message returns nil")
    TestHarness.AssertNil(P(12345), "Number message returns nil")
    TestHarness.AssertNil(P({}), "Table message returns nil")
    TestHarness.AssertNil(P("<AZ inv layer 2"), "Missing closing bracket returns nil")
    TestHarness.AssertNil(P("AZ> inv layer 2"), "Missing opening bracket returns nil")
    TestHarness.AssertNil(P("<123> inv layer 2"), "Non-alpha segment returns nil")
    TestHarness.AssertNil(P("<AZ> inv layer abc"), "Non-numeric layer returns nil")
    TestHarness.AssertNil(P("<AZ> inv layer -1"), "Negative layer returns nil")
    TestHarness.AssertNil(P("<AL2Z1945V1_9_15> inv layer 1"), "Out-of-order v2 header returns nil")
    TestHarness.AssertNil(P("<AL2V1_9_15ZOUTLAND> inv layer 1"), "Non-numeric v2 map returns nil")
    TestHarness.AssertNil(P("<AZ> inv layer 1; DROP TABLE users;"), "SQL injection suffix returns nil")
    TestHarness.AssertNil(P("<AZ> inv layer 1\n<OL> inv layer 2"), "Multi-packet injection returns nil")
    TestHarness.AssertNil(P(string.rep("A", 10000)), "10,000-char buffer overflow returns nil")
end)

-- T5-AdvA-12: AutoLayer Reserved Slot Eviction Idempotence & Boundary Protection
TestHarness.RegisterTest("Tier 5", "AdvA-12", "T5-AdvA-12: AutoLayer Reserved Slot Eviction Idempotence & Boundary Protection", function()
    local env, ULO = HelperSetup("wowf")
    local AL = ULO.Interop.AutoLayer

    -- 1. IsSlotProtected boundary conditions
    TestHarness.AssertTrue(AL.IsSlotProtected(1), "Slot 1 protected")
    TestHarness.AssertTrue(AL.IsSlotProtected(5), "Slot 5 protected")
    TestHarness.AssertFalse(AL.IsSlotProtected(0), "Slot 0 not protected")
    TestHarness.AssertFalse(AL.IsSlotProtected(-1), "Negative slot not protected")
    TestHarness.AssertFalse(AL.IsSlotProtected(6), "Slot 6 not protected")
    TestHarness.AssertFalse(AL.IsSlotProtected(10), "Slot 10 not protected")
    TestHarness.AssertFalse(AL.IsSlotProtected("invalid"), "String slot returns false")
    TestHarness.AssertFalse(AL.IsSlotProtected(nil), "Nil slot returns false")

    -- 2. LeaveExcessChannels slot protection & idempotence
    local todayChannel = AL.GenerateChannelName()
    local slotMap = {
        ["layer"] = 3,          -- Displacing slot 3 (General/Trade/LocalDefense) -> MUST LEAVE
        [todayChannel] = 7       -- Slot 7 (> 5) -> ALLOWED TO STAY
    }

    local departedPass1 = AL.LeaveExcessChannels(function(ch) return slotMap[ch] end)
    TestHarness.AssertEqual(#departedPass1, 1, "Exactly 1 channel departed on Pass 1")
    TestHarness.AssertEqual(departedPass1[1], "layer", "Departed channel is 'layer'")
    TestHarness.AssertTrue(env.__harness.mockChat.leftChannels["layer"], "'layer' channel left")
    TestHarness.AssertNil(env.__harness.mockChat.leftChannels[todayChannel], "Today channel remained joined")

    -- Invariant: Second consecutive pass is strictly idempotent
    slotMap["layer"] = nil -- Channel already departed
    local departedPass2 = AL.LeaveExcessChannels(function(ch) return slotMap[ch] end)
    TestHarness.AssertEqual(#departedPass2, 0, "Zero channels departed on Pass 2 (Idempotent)")

    -- 3. CheckAndEnforceSlotPolicy
    local ok1, reason1 = AL.CheckAndEnforceSlotPolicy("test_channel", 2)
    TestHarness.AssertFalse(ok1)
    TestHarness.AssertEqual(reason1, "slot_displaced")

    local ok2, reason2 = AL.CheckAndEnforceSlotPolicy("test_channel", 8)
    TestHarness.AssertTrue(ok2)
    TestHarness.AssertEqual(reason2, "slot_ok")
end)

-- T5-AdvA-13: Overlord Protocol Wire Spoofing & Malformed Inbound Attack Vectors
TestHarness.RegisterTest("Tier 5", "AdvA-13", "T5-AdvA-13: Overlord Protocol Wire Spoofing & Malformed Inbound Attack Vectors", function()
    local env, ULO = HelperSetup("wowf")
    local Overlord = ULO.Interop.Overlord

    -- Ensure host is in nominal state
    ULO.Coordination.ToggleAutoInvite(true)
    env.SetUnit("player", { inCombat = false })
    env.SetInstanceInfo("Durotar", "none", 0)

    -- 1. Protocol version mismatches
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:1:req1:2", "Attacker"), "Version 1 rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:3:req1:2", "Attacker"), "Version 3 rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:99:req1:2", "Attacker"), "Version 99 rejected")

    -- 2. Malformed request payloads
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:2::2", "Attacker"), "Empty reqId rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:2:req1:", "Attacker"), "Missing layer rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:2:req1:abc", "Attacker"), "Non-numeric layer rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:2:req1:0", "Attacker"), "Layer 0 rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:2:req1:-5", "Attacker"), "Negative layer rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("R:2:req;injection:2", "Attacker"), "Special chars in reqId rejected")

    -- 3. Decline spoofing & invalid decline formats
    TestHarness.AssertFalse(Overlord.ProcessMessage("N::combat", "Attacker"), "Empty reqId decline rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("N:req1:", "Attacker"), "Empty reason decline rejected")
    TestHarness.AssertFalse(Overlord.ProcessMessage("N:req1:special;char", "Attacker"), "Special chars in reason rejected")

    -- 4. Valid decline tracking
    TestHarness.AssertNil(Overlord.GetRequestFailureReason(777))
    local handledDecline = Overlord.ProcessMessage("N:777:busy", "Host")
    TestHarness.AssertTrue(handledDecline, "Valid decline should be processed")
    TestHarness.AssertEqual(Overlord.GetRequestFailureReason(777), "busy", "Failure reason recorded for req 777")

    -- 5. Fuzz non-string inputs
    TestHarness.AssertFalse(Overlord.ProcessMessage(nil, "Attacker"))
    TestHarness.AssertFalse(Overlord.ProcessMessage("", "Attacker"))
    TestHarness.AssertFalse(Overlord.ProcessMessage(12345, "Attacker"))
    TestHarness.AssertFalse(Overlord.ProcessMessage({}, "Attacker"))
    TestHarness.AssertFalse(Overlord.ProcessMessage(true, "Attacker"))
end)

-- T5-AdvA-14: Overlord State Gate Matrix & Mutual Exclusion Invariants
TestHarness.RegisterTest("Tier 5", "AdvA-14", "T5-AdvA-14: Overlord State Gate Matrix & Mutual Exclusion Invariants", function()
    local env, ULO = HelperSetup("wowf")
    local Overlord = ULO.Interop.Overlord

    local function GetLastDecline()
        local msgs = env.__harness.mockChat.outgoingAddonMessages
        for i = #msgs, 1, -1 do
            if msgs[i].prefix == "OverlordLJ" then
                return msgs[i]
            end
        end
        return nil
    end

    -- Gate 1: Auto-invite disabled -> "off"
    ULO.Coordination.ToggleAutoInvite(false)
    Overlord.ProcessMessage("R:2:req101:2", "Requester1")
    local d1 = GetLastDecline()
    TestHarness.AssertNotNil(d1)
    TestHarness.AssertEqual(d1.message, "N:req101:off", "Decline reason must be 'off'")

    -- Gate 2: In dungeon/raid instance -> "instance"
    ULO.Coordination.ToggleAutoInvite(true)
    env.IsInInstance = function() return true end
    Overlord.ProcessMessage("R:2:req102:2", "Requester2")
    local d2 = GetLastDecline()
    TestHarness.AssertNotNil(d2)
    TestHarness.AssertEqual(d2.message, "N:req102:instance", "Decline reason must be 'instance'")

    -- Gate 3: In combat -> "combat"
    env.IsInInstance = function() return false end
    env.SetInstanceInfo("Durotar", "none", 0)
    env.SetUnit("player", { inCombat = true })
    Overlord.ProcessMessage("R:2:req103:2", "Requester3")
    local d3 = GetLastDecline()
    TestHarness.AssertNotNil(d3)
    TestHarness.AssertEqual(d3.message, "N:req103:combat", "Decline reason must be 'combat'")

    -- Gate 4: Party full (5/5 players) -> "full"
    env.SetUnit("player", { inCombat = false })
    env.__harness.mockParty.members = { "player", "p1", "p2", "p3", "p4" }
    Overlord.ProcessMessage("R:2:req104:2", "Requester4")
    local d4 = GetLastDecline()
    TestHarness.AssertNotNil(d4)
    TestHarness.AssertEqual(d4.message, "N:req104:full", "Decline reason must be 'full'")

    -- Gate 5: Requester already on same layer -> "same"
    env.__harness.mockParty.members = { "player" }
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Confirmed layer 2")

    Overlord.ProcessMessage("R:2:req105:2", "Requester5")
    local d5 = GetLastDecline()
    TestHarness.AssertNotNil(d5)
    TestHarness.AssertEqual(d5.message, "N:req105:same", "Decline reason must be 'same'")

    -- Gate 6: All gates pass -> Dispatch party invite!
    local initialInvites = env.__harness.mockParty.inviteCallCount or 0
    local okPass = Overlord.ProcessMessage("R:2:req106:1", "EligibleJumper")
    TestHarness.AssertTrue(okPass, "Eligible wire request processed")
    TestHarness.AssertTrue((env.__harness.mockParty.inviteCallCount or 0) > initialInvites, "Party invite dispatched")
    TestHarness.AssertEqual(env.__harness.mockParty.lastInvited, "EligibleJumper", "Invited player matches sender")
    TestHarness.AssertTrue(ULO.Coordination.IsPlayerInInviteCache("EligibleJumper"), "Enrolled in throttle cache")
end)

-- T5-AdvA-15: NovaWorldBuffs Reentrant Callback Loops & Hook Tampering Resistance
TestHarness.RegisterTest("Tier 5", "AdvA-15", "T5-AdvA-15: NovaWorldBuffs Reentrant Callback Loops & Hook Tampering Resistance", function()
    local env, ULO = HelperSetup("wowf")
    local NWB = ULO.Interop.NWB

    -- 1. Infinite recursion reentrancy loop attack:
    -- Foreign NWB_LayerUpdated callback calls SyncWithNWB, which triggers OnLayerChanged, which calls NWB_LayerUpdated
    local loopCalls = 0
    env._G.NWB_LayerUpdated = function()
        loopCalls = loopCalls + 1
        NWB.SyncWithNWB() -- Attempt recursive call
    end

    -- Trigger layer consensus update
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-2")

    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2)
    -- Invariant: Recursion guard prevents stack overflow; loopCalls is strictly 1
    TestHarness.AssertEqual(loopCalls, 1, "isSyncing guard must prevent re-entrant recursion loop")

    -- 2. Foreign hook throwing runtime error
    env._G.NWB_LayerUpdated = function()
        error("Foreign Addon Runtime Crash in NWB_LayerUpdated!")
    end

    -- Changing layer again should not crash ULO
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1, "Layer updated despite foreign hook error")

    -- 3. Corrupted globals and database table
    env._G.NWB_CurrentLayer = "Unknown String Without Digits"
    NWB.SyncWithNWB()
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1, "Corrupted string does not alter layer")

    env._G.NWBdatabase = "corrupted string instead of table"
    TestHarness.AssertNil(NWB.GetNWBLayerData(), "Corrupted NWBdatabase safely returns nil")
end)

-- ============================================================================
-- SECTION 4: CORE SUBSYSTEM (INIT, CALLBACKS, SLASH COMMANDS) (F01, F17)
-- ============================================================================

-- T5-AdvA-16: Core Callback Bus Reentrancy, Self-Unsubscription & Error Isolation
TestHarness.RegisterTest("Tier 5", "AdvA-16", "T5-AdvA-16: Core Callback Bus Reentrancy, Self-Unsubscription & Error Isolation", function()
    local env, ULO = HelperSetup("wowf")

    local h1Calls = 0
    local h2Calls = 0
    local h3Calls = 0
    local h4Calls = 0
    local h5Calls = 0

    local unreg1 = nil
    local unreg2 = nil

    -- Handler 1: Dynamically registers Handler 3 during active dispatch
    unreg1 = ULO.RegisterCallback("AdversarialEvent", function(arg)
        h1Calls = h1Calls + 1
        ULO.RegisterCallback("AdversarialEvent", function(innerArg)
            h3Calls = h3Calls + 1
        end)
    end)

    -- Handler 2: Self-unregisters and unregisters Handler 1 during active dispatch
    unreg2 = ULO.RegisterCallback("AdversarialEvent", function(arg)
        h2Calls = h2Calls + 1
        unreg1()
        unreg2()
    end)

    -- Handler 4: Throws an intentional runtime exception
    ULO.RegisterCallback("AdversarialEvent", function(arg)
        h4Calls = h4Calls + 1
        error("Simulated catastrophic failure in callback handler")
    end)

    -- Handler 5: Normal handler following throwing handler
    ULO.RegisterCallback("AdversarialEvent", function(arg)
        h5Calls = h5Calls + 1
    end)

    -- Trigger callback dispatch 1
    ULO.TriggerCallback("AdversarialEvent", "payload1")

    -- Invariant: Snapshot isolation executes Handlers 1, 2, 4, 5. Handler 3 was registered mid-dispatch, so not in snapshot 1
    TestHarness.AssertEqual(h1Calls, 1, "Handler 1 called")
    TestHarness.AssertEqual(h2Calls, 1, "Handler 2 called")
    TestHarness.AssertEqual(h4Calls, 1, "Handler 4 called")
    TestHarness.AssertEqual(h5Calls, 1, "Handler 5 called (error in Handler 4 was isolated!)")
    TestHarness.AssertEqual(h3Calls, 0, "Handler 3 not called in initial dispatch snapshot")

    -- Trigger callback dispatch 2
    ULO.TriggerCallback("AdversarialEvent", "payload2")

    -- Invariant: Handlers 1 and 2 were unregistered; Handler 3 is now active; Handlers 4 and 5 run again
    TestHarness.AssertEqual(h1Calls, 1, "Handler 1 was unregistered, not called again")
    TestHarness.AssertEqual(h2Calls, 1, "Handler 2 was unregistered, not called again")
    TestHarness.AssertEqual(h3Calls, 1, "Handler 3 now active and called")
    TestHarness.AssertEqual(h4Calls, 2, "Handler 4 called again")
    TestHarness.AssertEqual(h5Calls, 2, "Handler 5 called again")
end)

-- T5-AdvA-17: Slash Command Fuzzing, Boundary Values & Injection Resilience
TestHarness.RegisterTest("Tier 5", "AdvA-17", "T5-AdvA-17: Slash Command Fuzzing, Boundary Values & Injection Resilience", function()
    local env, ULO = HelperSetup("wowf")
    local Slash = ULO.HandleSlashCommand

    local printedMessages = {}
    env.DEFAULT_CHAT_FRAME.AddMessage = function(self, msg)
        table.insert(printedMessages, msg)
    end

    -- 1. Fuzz non-string and empty inputs
    Slash(nil)
    Slash("")
    Slash("   ")
    Slash(12345)
    Slash({ invalid = true })
    Slash(true)

    TestHarness.AssertTrue(#printedMessages >= 1, "Fuzz inputs handled without error")

    -- 2. Boundary layer numbers for /ulo layer and /layer
    printedMessages = {}
    Slash("layer 0")
    TestHarness.AssertEqual(printedMessages[#printedMessages], "Invalid layer number: 0", "Layer 0 rejected")

    Slash("layer -5")
    TestHarness.AssertEqual(printedMessages[#printedMessages], "Invalid layer number: -5", "Negative layer rejected")

    Slash("layer 25")
    TestHarness.AssertEqual(printedMessages[#printedMessages], "Invalid layer number: 25", "Layer > 20 rejected")

    -- 3. Auto-invite toggles
    printedMessages = {}
    Slash("toggle off")
    TestHarness.AssertEqual(printedMessages[#printedMessages], "Auto-Invite Disabled")
    TestHarness.AssertFalse(ULO.Coordination.IsAutoInviteEnabled())

    Slash("toggle on")
    TestHarness.AssertEqual(printedMessages[#printedMessages], "Auto-Invite Enabled")
    TestHarness.AssertTrue(ULO.Coordination.IsAutoInviteEnabled())

    -- 4. Status command
    printedMessages = {}
    Slash("status")
    TestHarness.AssertTrue(string.find(printedMessages[#printedMessages], "Current Layer:") ~= nil, "Status printed")

    -- 5. Command injection fuzzing
    printedMessages = {}
    Slash("; DROP TABLE users; --")
    TestHarness.AssertEqual(printedMessages[#printedMessages], "Unknown command. Type /ulo help for commands.")
end)

-- ============================================================================
-- PART B: COMPATIBILITY, COORDINATION, UI, INTEGRATION (18 ADVERSARIAL TESTS)
-- ============================================================================

-- ============================================================================
-- Category 1: Compatibility Layer Adversarial Stress (Tests 1–3)
-- ============================================================================

TestHarness.RegisterTest("Tier 5", "AdvB-01", "[AdvB] Compat: NormalizeTargetName Whitespace-Only and Non-String Edge Cases", function(env)
    local Compat = env.ULO.Compat

    -- 1. Empty string
    local u, r = Compat.NormalizeTargetName("")
    TestHarness.AssertNil(u, "Empty string target must return nil unit")
    TestHarness.AssertNil(r, "Empty string target must return nil realm")

    -- 2. Nil
    u, r = Compat.NormalizeTargetName(nil)
    TestHarness.AssertNil(u, "Nil target must return nil unit")
    TestHarness.AssertNil(r, "Nil target must return nil realm")

    -- 3. Non-string: number
    u, r = Compat.NormalizeTargetName(12345)
    TestHarness.AssertEqual(u, "12345", "Numeric target should convert to string")
    TestHarness.AssertNil(r, "Numeric target should have nil realm")

    -- 4. Non-string: boolean
    u, r = Compat.NormalizeTargetName(true)
    TestHarness.AssertNil(u, "Boolean target must return nil unit")
    TestHarness.AssertNil(r, "Boolean target must return nil realm")

    -- 5. Non-string: table
    u, r = Compat.NormalizeTargetName({})
    TestHarness.AssertNil(u, "Table target must return nil unit")
    TestHarness.AssertNil(r, "Table target must return nil realm")

    -- 6. Engine secret value guard
    env.issecretvalue = function(v) return v == "SecretPlayer-SecretRealm" end
    u, r = Compat.NormalizeTargetName("SecretPlayer-SecretRealm")
    TestHarness.AssertNil(u, "Secret value target must return nil unit")
    TestHarness.AssertNil(r, "Secret value target must return nil realm")
    env.issecretvalue = nil

    -- 7. Whitespace-only string
    u, r = Compat.NormalizeTargetName("   ")
    TestHarness.AssertNil(u, "Whitespace-only target must return nil unit, not empty string")
    TestHarness.AssertNil(r, "Whitespace-only target must return nil realm")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-02", "[AdvB] Compat: NormalizeTargetName Hyphen Boundary Invariants", function(env)
    local Compat = env.ULO.Compat

    -- Standard single realm
    local u, r = Compat.NormalizeTargetName("Arthas")
    TestHarness.AssertEqual(u, "Arthas")
    TestHarness.AssertNil(r)

    -- Standard Name-Realm
    u, r = Compat.NormalizeTargetName("Arthas-Frostmourne")
    TestHarness.AssertEqual(u, "Arthas")
    TestHarness.AssertEqual(r, "Frostmourne")

    -- Multi-hyphen realm (e.g. Twisting-Nether-US)
    u, r = Compat.NormalizeTargetName("Illidan-Twisting-Nether-US")
    TestHarness.AssertEqual(u, "Illidan")
    TestHarness.AssertEqual(r, "Twisting-Nether-US")

    -- Trimming whitespace around target
    u, r = Compat.NormalizeTargetName("  Jaina-Proudmoore  ")
    TestHarness.AssertEqual(u, "Jaina")
    TestHarness.AssertEqual(r, "Proudmoore")

    -- Malformed hyphen tests:
    -- Trailing hyphen: "Arthas-"
    u, r = Compat.NormalizeTargetName("Arthas-")
    TestHarness.AssertTrue(u == nil or u == "Arthas", "Trailing hyphen should not leave unit as 'Arthas-'")

    -- Leading hyphen: "-Frostmourne"
    u, r = Compat.NormalizeTargetName("-Frostmourne")
    TestHarness.AssertTrue(u == nil, "Leading hyphen should not produce unit '-Frostmourne'")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-03", "[AdvB] Compat: NormalizeTargetName Multi-Byte UTF-8 and International Realms", function(env)
    local Compat = env.ULO.Compat

    -- European accented characters (Umlauts, Accents)
    local u, r = Compat.NormalizeTargetName("München-Élune")
    TestHarness.AssertEqual(u, "München", "Multi-byte unit name preserved")
    TestHarness.AssertEqual(r, "Élune", "Multi-byte realm name preserved")

    -- Nordic characters
    u, r = Compat.NormalizeTargetName("Søren-Kazzåk")
    TestHarness.AssertEqual(u, "Søren")
    TestHarness.AssertEqual(r, "Kazzåk")

    -- Cyrillic characters
    u, r = Compat.NormalizeTargetName("Иван-Гордунни")
    TestHarness.AssertEqual(u, "Иван")
    TestHarness.AssertEqual(r, "Гордунни")

    -- Asian characters
    u, r = Compat.NormalizeTargetName("勇者-韓国")
    TestHarness.AssertEqual(u, "勇者")
    TestHarness.AssertEqual(r, "韓国")

    -- Multi-byte unit single name
    u, r = Compat.NormalizeTargetName("Éowyn")
    TestHarness.AssertEqual(u, "Éowyn")
    TestHarness.AssertNil(r)
end)

-- ============================================================================
-- Category 2: Whisper Keyword Engine Boundary Attacks (Tests 4–7)
-- ============================================================================

TestHarness.RegisterTest("Tier 5", "AdvB-04", "[AdvB] Coordination: Keyword Engine Partial Word and Substring Injection", function(env)
    local Coord = env.ULO.Coordination

    -- Legitimate keywords must match
    local ok, target = Coord.MatchKeywords("layer")
    TestHarness.AssertTrue(ok, "'layer' must match")

    ok, target = Coord.MatchKeywords("inv")
    TestHarness.AssertTrue(ok, "'inv' must match")

    ok, target = Coord.MatchKeywords("invite")
    TestHarness.AssertTrue(ok, "'invite' must match")

    -- Partial words containing 'layer', 'inv', 'invite' as substrings must NOT match
    local falseKeywords = {
        "slayer",
        "relayer",
        "layering",
        "layered",
        "bricklayer",
        "invisible",
        "reinv",
        "uninvited",
        "inviting",
        "invitation",
        "reinvent",
        "disinvite"
    }

    for _, kw in ipairs(falseKeywords) do
        local ok, reason = Coord.MatchKeywords(kw)
        TestHarness.AssertFalse(ok, string.format("Partial word %q must not match as layer keyword", kw))
    end
end)

TestHarness.RegisterTest("Tier 5", "AdvB-05", "[AdvB] Coordination: Keyword Engine Regex Metacharacter Injection", function(env)
    local Coord = env.ULO.Coordination

    local metacharMsgs = {
        "layer (1)",
        "layer [1]",
        "layer %d",
        "layer +1",
        "layer *1",
        "layer ?1",
        "layer ^1",
        "layer 1$",
        "layer %s+1",
        "layer %f[%w]",
        "layer [a-z]+",
        "layer (.*)"
    }

    for _, msg in ipairs(metacharMsgs) do
        local ok, err = pcall(function()
            return Coord.MatchKeywords(msg)
        end)
        TestHarness.AssertTrue(ok, string.format("KeywordMatcher must not crash on metacharacter input %q", msg))
    end
end)

TestHarness.RegisterTest("Tier 5", "AdvB-06", "[AdvB] Coordination: Keyword Engine Inverted and Conflicting Query Stress", function(env)
    local Coord = env.ULO.Coordination

    -- Inverted keywords
    local ok, target, inv, lNum = Coord.MatchKeywords("not layer 1")
    TestHarness.AssertTrue(ok)
    TestHarness.AssertTrue(inv)
    TestHarness.AssertEqual(lNum, 1)

    ok, target, inv, lNum = Coord.MatchKeywords("except layer 2")
    TestHarness.AssertTrue(ok)
    TestHarness.AssertTrue(inv)
    TestHarness.AssertEqual(lNum, 2)

    ok, target, inv, lNum = Coord.MatchKeywords("off layer 3")
    TestHarness.AssertTrue(ok)
    TestHarness.AssertTrue(inv)
    TestHarness.AssertEqual(lNum, 3)

    ok, target, inv, lNum = Coord.MatchKeywords("but layer 4")
    TestHarness.AssertTrue(ok)
    TestHarness.AssertTrue(inv)
    TestHarness.AssertEqual(lNum, 4)

    -- Inverted out of bounds
    ok, target = Coord.MatchKeywords("not layer 0")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    ok, target = Coord.MatchKeywords("not layer 25")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    -- Conflicting query: "layer 1 not layer 1"
    ok, target, inv, lNum = Coord.MatchKeywords("layer 1 not layer 1")
    TestHarness.AssertTrue(ok)
    TestHarness.AssertTrue(inv, "Inverted pattern should take precedence over positive layer")
    TestHarness.AssertEqual(lNum, 1)
end)

TestHarness.RegisterTest("Tier 5", "AdvB-07", "[AdvB] Coordination: Keyword Engine Extreme Range and Out-of-Bounds Parsing", function(env)
    local Coord = env.ULO.Coordination

    -- Valid range
    local ok, target, inv, r1, r2 = Coord.MatchKeywords("layer 1-3")
    TestHarness.AssertTrue(ok)
    TestHarness.AssertEqual(r1, 1)
    TestHarness.AssertEqual(r2, 3)

    -- Reverse range: 9999-1
    ok, target = Coord.MatchKeywords("layer 9999-1")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    -- Oversized range: 1-100000
    ok, target = Coord.MatchKeywords("layer 1-100000")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    -- Inverted range: 5-2
    ok, target = Coord.MatchKeywords("layer 5-2")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    -- Out of bounds single layers
    ok, target = Coord.MatchKeywords("layer 0")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    ok, target = Coord.MatchKeywords("layer 21")
    TestHarness.AssertFalse(ok)
    TestHarness.AssertEqual(target, "out_of_bounds")

    -- Negative layer: "layer -1"
    ok, target = Coord.MatchKeywords("layer -1")
    TestHarness.AssertFalse(ok, "Negative layer number must not be matched as valid request")
    TestHarness.AssertEqual(target, "out_of_bounds")
end)

-- ============================================================================
-- Category 3: Automated Party Invite Race Conditions & Throttle Stress (Tests 8–11)
-- ============================================================================

TestHarness.RegisterTest("Tier 5", "AdvB-08", "[AdvB] Coordination: Invite Throttle Window Expiry Monotonic Boundary (t = 299.9 vs 300.1)", function(env)
    local Coord = env.ULO.Coordination

    local t0 = env.GetTime()

    -- Enroll player "Alice" with 300s throttle (expires at t0 + 300.0)
    Coord.EnrollPlayerInCache("Alice", 300)

    -- At t = t0 + 299.9 (299.9s elapsed)
    env.AdvanceTime(299.9)
    TestHarness.AssertTrue(Coord.IsPlayerInInviteCache("Alice"), "Player must be in cache at t=299.9s")
    local ok, reason = Coord.HandleWhisper("Alice", "layer")
    TestHarness.AssertFalse(ok, "Invite must be throttled at t=299.9s")
    TestHarness.AssertEqual(reason, "cached")

    -- At t = t0 + 300.1 (300.1s elapsed) - expiry boundary
    env.AdvanceTime(0.2)
    TestHarness.AssertFalse(Coord.IsPlayerInInviteCache("Alice"), "Player must expire from cache at t=300.1s")
    ok, reason = Coord.HandleWhisper("Alice", "layer")
    TestHarness.AssertTrue(ok, "Invite must succeed after throttle window expiration at t=300.1s")

    -- Player is now re-enrolled (expires at t + 300.0)
    TestHarness.AssertTrue(Coord.IsPlayerInInviteCache("Alice"), "Player re-enrolled in cache")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-09", "[AdvB] Coordination: Invite Throttle Case-Insensitivity & Realm Bypass Probe", function(env)
    local Coord = env.ULO.Coordination
    Coord.ClearInviteCache()

    -- PlayerOne whispers "layer"
    local ok1, r1 = Coord.HandleWhisper("PlayerOne", "layer")
    TestHarness.AssertTrue(ok1, "First invite should succeed")

    -- Probe casing mutations 5 seconds later
    env.AdvanceTime(5)

    -- Casing mutation: "playerone"
    local ok2, r2 = Coord.HandleWhisper("playerone", "layer")
    TestHarness.AssertFalse(ok2, "Lowercase sender 'playerone' must be throttled by 'PlayerOne' cache entry")
    TestHarness.AssertEqual(r2, "cached")

    -- Casing mutation: "PLAYERONE"
    local ok3, r3 = Coord.HandleWhisper("PLAYERONE", "layer")
    TestHarness.AssertFalse(ok3, "Uppercase sender 'PLAYERONE' must be throttled by 'PlayerOne' cache entry")
    TestHarness.AssertEqual(r3, "cached")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-10", "[AdvB] Coordination: High-Frequency Whisper Burst From 50+ Concurrent Senders", function(env)
    local Coord = env.ULO.Coordination
    Coord.ClearInviteCache()

    local mutedCount = 0
    local unmutedCount = 0
    env._G.MuteSoundFile = function(id) mutedCount = mutedCount + 1 end
    env._G.UnmuteSoundFile = function(id) unmutedCount = unmutedCount + 1 end

    local currentGroupMembers = 1
    env._G.GetNumGroupMembers = function() return currentGroupMembers end
    env._G.IsInRaid = function() return false end

    local invitesDispatched = 0
    local invitesRejectedFull = 0

    -- 60 unique players whisper simultaneously
    for i = 1, 60 do
        local sender = string.format("BurstPlayer%02d", i)
        local ok, reason = Coord.HandleWhisper(sender, "inv")
        if ok then
            invitesDispatched = invitesDispatched + 1
            if currentGroupMembers < 5 then
                currentGroupMembers = currentGroupMembers + 1
            end
        elseif reason == "party_full" then
            invitesRejectedFull = invitesRejectedFull + 1
        end
    end

    -- Exactly 4 invites dispatched (leader + 4 members = 5), remaining 56 rejected as party_full
    TestHarness.AssertEqual(invitesDispatched, 4, "Only 4 party slots available for leader (max 5)")
    TestHarness.AssertEqual(invitesRejectedFull, 56, "All remaining 56 whispers must be rejected with party_full")

    -- Sound mute and unmute calls must match (2 sound files per invite * 4 invites = 8 calls)
    TestHarness.AssertEqual(mutedCount, 8, "MuteSoundFile should be called 8 times (2 per invite)")
    TestHarness.AssertEqual(unmutedCount, 8, "UnmuteSoundFile should be called 8 times (2 per invite)")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-11", "[AdvB] Coordination: Pending Invite 180s Expiration Monotonic Eviction", function(env)
    local Coord = env.ULO.Coordination
    Coord.ClearInviteCache()

    -- Enroll 5 players at t = 100 (pending expires at t = 280)
    env.AdvanceTime(100)
    for i = 1, 5 do
        Coord.EnrollPlayerInCache("PendingPlayer" .. i)
    end

    TestHarness.AssertEqual(Coord.GetPendingInviteCount(), 5, "Initial pending count must be 5")

    -- Advance to t = 279.9
    env.AdvanceTime(179.9)
    TestHarness.AssertEqual(Coord.GetPendingInviteCount(), 5, "Pending count must be 5 at t=279.9")

    -- Advance to t = 280.1
    env.AdvanceTime(0.2)
    TestHarness.AssertEqual(Coord.GetPendingInviteCount(), 0, "All pending invites must expire at t=280.1")

    -- Re-enroll 2 players and clear cache
    Coord.EnrollPlayerInCache("FreshPlayer1")
    Coord.EnrollPlayerInCache("FreshPlayer2")
    TestHarness.AssertEqual(Coord.GetPendingInviteCount(), 2)
    Coord.ClearInviteCache()
    TestHarness.AssertEqual(Coord.GetPendingInviteCount(), 0, "ClearInviteCache must instantly reset pending slots")
end)

-- ============================================================================
-- Category 4: Group Departure and Transfer Lifecycle Race Conditions (Tests 12–15)
-- ============================================================================

TestHarness.RegisterTest("Tier 5", "AdvB-12", "[AdvB] Coordination: Mid-Combat Hop Invite Acceptance & Deferral of Departure", function(env)
    local Coord = env.ULO.Coordination
    Coord.ResetHopState()

    local inCombat = false
    env._G.UnitAffectingCombat = function(unit)
        if unit == "player" then return inCombat end
        return false
    end
    env._G.InCombatLockdown = function() return inCombat end

    local leftPartyCalled = false
    env._G.C_PartyInfo.LeaveParty = function() leftPartyCalled = true; return true end
    env._G.LeaveParty = function() leftPartyCalled = true; return true end

    -- 1. Request hop to layer 4
    local reqOk = Coord.RequestLayerHop(4)
    TestHarness.AssertTrue(reqOk)
    TestHarness.AssertTrue(Coord.IsAwaitingHop())

    -- 2. Player enters combat
    inCombat = true

    -- 3. Hop invite arrives while in combat
    env.FireEvent("PARTY_INVITE_REQUEST", "HopHelper")
    TestHarness.AssertTrue(Coord.IsAwaitingLayerVerification(), "Should accept invite and await layer verification even in combat")

    -- 4. Target layer confirms
    env.FireEvent("GROUP_JOINED")
    env.ULO.TriggerCallback("OnLayerChanged", 4)

    -- Must detect combat and defer departure
    TestHarness.AssertFalse(leftPartyCalled, "Must NOT leave party during active combat")
    TestHarness.AssertTrue(Coord.IsDepartureDeferred(), "Departure must be marked as deferred")

    -- 5. Combat ends: PLAYER_REGEN_ENABLED fires
    inCombat = false
    env.FireEvent("PLAYER_REGEN_ENABLED")

    -- At t + 1.0s (within 2s grace buffer): still deferred
    env.AdvanceTime(1.0)
    TestHarness.AssertFalse(leftPartyCalled, "Must wait for 2.0s grace buffer before leaving party")
    TestHarness.AssertTrue(Coord.IsDepartureDeferred())

    -- At t + 2.1s: buffer expires, departure executes
    env.AdvanceTime(1.1)
    TestHarness.AssertTrue(leftPartyCalled, "LeaveParty must be called after 2.0s buffer expires")
    TestHarness.AssertFalse(Coord.IsDepartureDeferred(), "isDepartureDeferred must reset to false")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-13", "[AdvB] Coordination: Silent Group Disband During Combat Deferral", function(env)
    local Coord = env.ULO.Coordination
    Coord.ResetHopState()

    local inCombat = true
    env._G.UnitAffectingCombat = function(unit) return inCombat end
    env._G.InCombatLockdown = function() return inCombat end

    local leftPartyCount = 0
    env._G.C_PartyInfo.LeaveParty = function() leftPartyCount = leftPartyCount + 1; return true end
    env._G.LeaveParty = function() leftPartyCount = leftPartyCount + 1; return true end

    -- Setup deferred departure state
    Coord.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "LeaderA")
    env.ULO.TriggerCallback("OnLayerChanged", 2)
    TestHarness.AssertTrue(Coord.IsDepartureDeferred(), "Departure must be deferred")

    -- While in combat, party disbands silently: GROUP_LEFT fires
    env.FireEvent("GROUP_LEFT")
    TestHarness.AssertFalse(Coord.IsDepartureDeferred(), "GROUP_LEFT must clear departure deferral")
    TestHarness.AssertFalse(Coord.IsAwaitingHop(), "Hop state must be reset")

    -- Later combat ends
    inCombat = false
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(3.0)

    -- LeaveParty must NOT have been called
    TestHarness.AssertEqual(leftPartyCount, 0, "LeaveParty must NOT be called after group already disbanded")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-14", "[AdvB] Coordination: Hop Timeout Invariant When Already In Existing Group", function(env)
    local Coord = env.ULO.Coordination
    Coord.ResetHopState()

    -- Player is already in an authentic party with friends (3 members)
    env._G.IsInGroup = function() return true end
    env._G.GetNumGroupMembers = function() return 3 end

    local leavePartyCalled = false
    env._G.C_PartyInfo.LeaveParty = function() leavePartyCalled = true; return true end
    env._G.LeaveParty = function() leavePartyCalled = true; return true end

    -- Hop timed out callback tracking
    local timedOutReason = nil
    env.ULO.RegisterCallback("OnHopTimedOut", function(reason)
        timedOutReason = reason
    end)

    -- Request hop to layer 3
    Coord.RequestLayerHop(3)
    TestHarness.AssertTrue(Coord.IsAwaitingHop())

    -- Advance time past the 40.0s verification timeout
    env.AdvanceTime(41.0)

    -- Callback must fire
    TestHarness.AssertEqual(timedOutReason, "timeout", "OnHopTimedOut callback must fire with 'timeout'")

    -- Invariant: Player never joined a hop helper group (wasAwaitingVerification was false).
    -- ULO must NOT kick the player out of their existing party!
    TestHarness.AssertFalse(leavePartyCalled, "Hop timeout must NOT drop player from existing party when never joined helper group")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-15", "[AdvB] Coordination: LeaveParty Failure Recovery and State Invariant", function(env)
    local Coord = env.ULO.Coordination
    local Compat = env.ULO.Compat
    Coord.ResetHopState()

    -- Simulate C-API failure when LeaveParty is called
    env._G.C_PartyInfo.LeaveParty = function()
        error("BLIZZARD_INTERNAL_PARTY_ERROR")
    end
    env._G.LeaveParty = function()
        error("BLIZZARD_INTERNAL_PARTY_ERROR")
    end

    -- Compat.LeaveParty must handle error gracefully
    local ok, err = Compat.LeaveParty()
    TestHarness.AssertFalse(ok, "LeaveParty must report failure cleanly")
    TestHarness.AssertNotNil(err, "Error message must be returned")

    -- LeavePartyWithCombatDeferral must also handle failure without throwing
    local defOk, defErr = Coord.LeavePartyWithCombatDeferral()
    TestHarness.AssertFalse(defOk)
    TestHarness.AssertNotNil(defErr)

    -- Reset state must execute cleanly
    Coord.ResetHopState()
    TestHarness.AssertFalse(Coord.IsDepartureDeferred())
end)

-- ============================================================================
-- Category 5: UI Orbital Math, Coordinate Clamping, Settings & Slash Commands (Tests 16–18)
-- ============================================================================

TestHarness.RegisterTest("Tier 5", "AdvB-16", "[AdvB] UI: Minimap Badge Orbital Math Edge Cases (NaN, Infinity, Negative Angles)", function(env)
    local Badge = env.ULO.UI.MinimapBadge

    -- SanitizeAngle stress testing
    TestHarness.AssertEqual(Badge.SanitizeAngle(nil), 225, "nil -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(0/0), 225, "NaN -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(math.huge), 225, "+Inf -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(-math.huge), 225, "-Inf -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(-45), 225, "Negative angle -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(-360), 225, "-360 -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(360.1), 225, "> 360 -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(720), 225, "720 -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle("180"), 225, "String -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle({}), 225, "Table -> default 225")
    TestHarness.AssertEqual(Badge.SanitizeAngle(true), 225, "Boolean -> default 225")

    -- Valid angles preserved exactly
    TestHarness.AssertEqual(Badge.SanitizeAngle(0), 0)
    TestHarness.AssertEqual(Badge.SanitizeAngle(180), 180)
    TestHarness.AssertEqual(Badge.SanitizeAngle(225), 225)
    TestHarness.AssertEqual(Badge.SanitizeAngle(360), 360)

    -- SetPosition persistence
    local saved = Badge.SetPosition(90)
    TestHarness.AssertEqual(saved, 90)
    TestHarness.AssertEqual(Badge.GetPosition(), 90)

    saved = Badge.SetPosition(-999)
    TestHarness.AssertEqual(saved, 225)
    TestHarness.AssertEqual(Badge.GetPosition(), 225)

    -- CalculateCursorAngle edge cases
    env._G.Minimap = {
        GetCenter = function() return 500, 500 end,
        GetEffectiveScale = function() return 1 end
    }
    env._G.UIParent = {
        GetEffectiveScale = function() return 1 end
    }

    -- Cursor coincides with center (dx=0, dy=0) -> returns nil without divide-by-zero
    env._G.GetCursorPosition = function() return 500, 500 end
    TestHarness.AssertNil(Badge.CalculateCursorAngle(), "Center coincidence must return nil")

    -- Cursor East (dx=100, dy=0) -> 0 deg
    env._G.GetCursorPosition = function() return 600, 500 end
    local angle = Badge.CalculateCursorAngle()
    TestHarness.AssertNotNil(angle)
    TestHarness.AssertTrue(math.abs(angle - 0) < 0.01 or math.abs(angle - 360) < 0.01, "East = 0 deg")

    -- Cursor North (dx=0, dy=100) -> 90 deg
    env._G.GetCursorPosition = function() return 500, 600 end
    angle = Badge.CalculateCursorAngle()
    TestHarness.AssertNotNil(angle)
    TestHarness.AssertTrue(math.abs(angle - 90) < 0.01, "North = 90 deg")

    -- Cursor West (dx=-100, dy=0) -> 180 deg
    env._G.GetCursorPosition = function() return 400, 500 end
    angle = Badge.CalculateCursorAngle()
    TestHarness.AssertNotNil(angle)
    TestHarness.AssertTrue(math.abs(angle - 180) < 0.01, "West = 180 deg")

    -- Cursor South (dx=0, dy=-100) -> 270 deg
    env._G.GetCursorPosition = function() return 500, 400 end
    angle = Badge.CalculateCursorAngle()
    TestHarness.AssertNotNil(angle)
    TestHarness.AssertTrue(math.abs(angle - 270) < 0.01, "South = 270 deg")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-17", "[AdvB] UI: StatusHUD Coordinate Boundary Clamping and Off-Screen Prevention", function(env)
    local HUD = env.ULO.UI.StatusHUD

    -- Countdown formatting checks
    env.ULO.Monitor = env.ULO.Monitor or {}
    local remSeconds = 180
    env.ULO.Monitor.GetRefreshRemaining = function() return remSeconds end

    remSeconds = 180
    TestHarness.AssertEqual(HUD.GetCountdownText(), "3:00")

    remSeconds = 65
    TestHarness.AssertEqual(HUD.GetCountdownText(), "1:05")

    remSeconds = 9
    TestHarness.AssertEqual(HUD.GetCountdownText(), "0:09")

    remSeconds = 0
    TestHarness.AssertEqual(HUD.GetCountdownText(), "0:00")

    -- Urgent alert threshold (<= 10.0s when refresh is pending)
    local isPending = false
    env.ULO.Monitor.IsRefreshPending = function() return isPending end

    isPending = true
    remSeconds = 10.1
    TestHarness.AssertFalse(HUD.IsUrgentAlertActive(), "10.1s must NOT trigger urgent alert")

    remSeconds = 10.0
    TestHarness.AssertTrue(HUD.IsUrgentAlertActive(), "10.0s MUST trigger urgent alert")

    remSeconds = 5.0
    TestHarness.AssertTrue(HUD.IsUrgentAlertActive(), "5.0s MUST trigger urgent alert")

    isPending = false
    TestHarness.AssertFalse(HUD.IsUrgentAlertActive(), "No pending refresh must NOT trigger urgent alert even if rem <= 10")

    -- Coordinate boundary clamping
    HUD.SetPosition(-50, -100)
    local x, y = HUD.GetPosition()
    TestHarness.AssertTrue(x >= 0, "HUD X coordinate must be clamped >= 0 to prevent off-screen loss")
    TestHarness.AssertTrue(y >= 0, "HUD Y coordinate must be clamped >= 0 to prevent off-screen loss")
end)

TestHarness.RegisterTest("Tier 5", "AdvB-18", "[AdvB] UI: Settings Cooldown Clamping & Slash Command Corrupt Input Fuzzing", function(env)
    local SettingsPanel = env.ULO.UI.SettingsPanel

    -- Cooldown slider clamping to [300, 900]
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(-50), 300, "Negative cooldown clamped to 300")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(0), 300, "0 clamped to 300")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(299), 300, "299 clamped to 300")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(300), 300, "300 preserved")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(600), 600, "600 preserved")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(900), 900, "900 preserved")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(901), 900, "901 clamped to 900")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(1500), 900, "1500 clamped to 900")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(nil), 300, "nil defaults to 300")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(0/0), 300, "NaN defaults to 300")
    TestHarness.AssertEqual(SettingsPanel.SetCooldown(math.huge), 300, "Inf defaults to 300")

    -- Slash command fuzzing: must not raise unhandled Lua errors
    local fuzzInputs = {
        nil, "", "   ", 12345, true, {},
        string.rep("x", 5000),
        "layer 0", "layer 21", "layer -1", "layer abc",
        "invite off", "invite on", "invite toggle", "invite nonsense",
        "status", "config", "refresh", "unknowncommand12345",
        "'; DROP TABLE layers; --",
        "layer \0 injection",
        "layer 1\r\n\t"
    }

    for _, inp in ipairs(fuzzInputs) do
        local ok, err = pcall(function()
            env.ULO.HandleSlashCommand(inp)
        end)
        TestHarness.AssertTrue(ok, string.format("HandleSlashCommand must not crash on fuzz input %q", tostring(inp)))
    end
end)

-- ============================================================================
-- SUMMARY & CLI EXIT CODE PROTOCOL
-- ============================================================================
local t5 = TestHarness.results.tierTally["Tier 5"]

if arg and arg[0] and string.find(string.lower(arg[0]), "tier5_adversarialharden.lua") then
    print("")
    print("========================================================================")
    print(" Universal Layer Operator (ULO) - Tier 5 Adversarial Harden Suite")
    print("========================================================================")
    print(string.format(" Tier 5 Results: %d / %d passed (Failed: %d)", t5.passed, t5.total, t5.failed))
    if #TestHarness.results.errors > 0 then
        print("\n Documented Failures:")
        for idx, errRec in ipairs(TestHarness.results.errors) do
            print(string.format("  #%d: [%s] %s", idx, errRec.featureId, errRec.name))
            print(string.format("      Error: %s", tostring(errRec.error):match("([^\r\n]+)")))
        end
    end
    print("========================================================================")
    os.exit(t5.failed == 0 and 0 or 1)
end

return TestHarness
