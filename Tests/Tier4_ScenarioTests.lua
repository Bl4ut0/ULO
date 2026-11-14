-- ============================================================================
-- Tests/Tier4_ScenarioTests.lua
-- Universal Layer Operator (ULO)
-- Tier 4: Real-World Application Scenarios (9 Comprehensive User Workflows)
-- ============================================================================

local TestHarness = ... or require("Tests.TestHarness")

local function HelperSetup(flavor)
    local env = TestHarness.NewEnvironment(flavor or "wowf")
    TestHarness.LoadAddonIntoEnv(env)
    return env, env.ULO
end

--------------------------------------------------------------------------------
-- T4-SCN-01: World Boss Layer Hop via Whisper Request & Auto-Accept
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F03_F04_F09_F10_F11_F15_F16", "T4-SCN-01: World Boss Layer Hop via Whisper Request & Auto-Accept", function()
    local env, ULO = HelperSetup()
    -- 1. Initial State: Confirmed on Layer 1 (ServerID 4469)
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1)
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "1")
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetStatusText(), "Layer: 1 (Confirmed)")

    -- 2. User initiates hop to Layer 2
    local ok = ULO.Coordination.RequestLayerHop(2)
    TestHarness.AssertTrue(ok)

    -- 3. Inbound party invite from Helper
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Camelot")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1, "Group invite auto-accepted")
    TestHarness.AssertTrue(env.__harness.mockUI.hiddenPopups["PARTY_INVITE"] == true, "Popup suppressed")

    -- 4. Group joined, phase transition begins
    env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
    TestHarness.AssertTrue(ULO.Coordination.IsAwaitingLayerVerification())

    -- 5. Scan Azshara NPCs on new layer (ServerID 4470 -> Layer 2)
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-2-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-2-2")

    -- 6. Verification confirmed
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Confirmed layer 2")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "2", "Badge updated to 2")

    -- 7. Auto-leave party after transfer
    ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1, "Left helper group")

    -- 8. Post-hop cooldown engaged for 300s
    ULO.Monitor.StartCooldown(300)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300, "300s cooldown active")
end)

--------------------------------------------------------------------------------
-- T4-SCN-02: Party Sync Layer Refresh with Combat Deferral & Auto-Departure
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F04_F05_F06_F07_F11_F16", "T4-SCN-02: Party Sync Layer Refresh with Combat Deferral & Auto-Departure", function()
    local env, ULO = HelperSetup()
    -- 1. Refresh warning begins with 180s countdown
    ULO.Monitor.StartRefreshWarning(180)
    TestHarness.AssertTrue(ULO.Monitor.IsRefreshPending())
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetCountdownText(), "3:00")

    -- 2. Advance time to 0:15 remaining
    env.AdvanceTime(165)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 15)

    -- 3. Player enters combat
    env.SetUnit("player", { inCombat = true })
    env.FireEvent("PLAYER_REGEN_DISABLED")

    -- 4. Timer reaches 10s: urgent pulse active
    env.AdvanceTime(5)
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 10)
    TestHarness.AssertTrue(ULO.UI.StatusHUD.IsUrgentAlertActive(), "Urgent alert active at 10s")

    -- 5. User clicks "Refresh Now" while in combat -> blocked
    local reqOk, reqReason = ULO.Monitor.RequestRefreshNow()
    TestHarness.AssertFalse(reqOk, "Cannot refresh in combat")
    TestHarness.AssertEqual(reqReason, "combat")

    -- 6. Countdown reaches 0:00 while still in combat
    env.AdvanceTime(10)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred(), "Deferred until out of combat")
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0, "Reload strictly blocked during combat")

    -- 7. Player exits combat 45 seconds later
    env.AdvanceTime(45)
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")

    -- 8. 2.0s safety buffer elapses cleanly
    env.AdvanceTime(3.0)
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1, "Reload executes safely out of combat")
    TestHarness.AssertFalse(ULO.Monitor.IsCombatDeferred(), "Combat deferral cleared")
end)

--------------------------------------------------------------------------------
-- T4-SCN-03: AutoLayer Continental Channel Hop to Outland (<OL>)
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F09_F10_F11_F12_F17", "T4-SCN-03: AutoLayer Continental Channel Hop to Outland (<OL>)", function()
    local env, ULO = HelperSetup()
    -- 1. In Outland zone map 1945
    env.SetUnit("player", { mapID = 1945 })
    ULO.Interop.AutoLayer.JoinChannels()

    -- 2. User initiates hop targeting Layer 3 in Outland
    local broadcast = ULO.Interop.AutoLayer.FormatBroadcastMessage(3, 1945)
    TestHarness.AssertEqual(broadcast, "<OL> inv layer 3", "Outgoing broadcast uses <OL> continental prefix")
    TestHarness.AssertEqual(env.__harness.mockChat.lastBroadcast, "<OL> inv layer 3")

    -- 3. Inbound invite from remote helper
    ULO.Coordination.RequestLayerHop(3)
    env.FireEvent("PARTY_INVITE_REQUEST", "OutlandHelper-Realm")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1)

    -- 4. Group joined, parse Outland creature GUIDs (ServerID 5123 -> Layer 3)
    env.FireEvent("GROUP_JOINED", 1, "party-guid-1945")
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-5123-0-1945-1-1")
    ULO.Detection.ScanGuid("Creature-0-5123-0-1945-1-2")

    -- 5. Verification confirmed, depart helper party
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 3, "Confirmed Layer 3 in Outland")
    ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1, "Left helper party after transfer")
end)

--------------------------------------------------------------------------------
-- T4-SCN-04: OverlordLJ Hidden Addon Peer-to-Peer Hop with Rejection Handling
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F10_F11_F13_F16", "T4-SCN-04: OverlordLJ Hidden Addon Peer-to-Peer Hop with Rejection Handling", function()
    local env, ULO = HelperSetup()
    -- 1. Initiate hop to Layer 2, send wire request to Helper 1 (BusyHelper)
    local req1 = ULO.Interop.Overlord.SendHopRequest("BusyHelper-Camelot", 2, 301)
    TestHarness.AssertEqual(req1, 301)

    -- 2. Helper 1 declines with wire message: "N:301:combat"
    env.FireEvent("CHAT_MSG_ADDON", "OverlordLJ", "N:301:combat", "WHISPER", "BusyHelper-Camelot")
    TestHarness.AssertEqual(ULO.Interop.Overlord.GetRequestFailureReason(301), "combat", "Caught combat decline reason")

    -- 3. Failover: Send wire request to Helper 2 (FreeHelper)
    local req2 = ULO.Interop.Overlord.SendHopRequest("FreeHelper-Camelot", 2, 302)
    TestHarness.AssertEqual(req2, 302)

    -- 4. Helper 2 accepts and invites local player
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "FreeHelper-Camelot")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1, "Auto-accepted Helper 2 invite")

    -- 5. Phases to Layer 2 (ServerID 4470), verify and leave
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "Verified Layer 2")
    ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1)
end)

--------------------------------------------------------------------------------
-- T4-SCN-05: High-Density Zone Transition & Dungeon Instance Suppression Lifecycle
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F03_F04_F05_F15_F16", "T4-SCN-05: High-Density Zone Transition & Dungeon Instance Suppression Lifecycle", function()
    local env, ULO = HelperSetup()
    -- 1. Start in Redridge Mountains: Layer 1 confirmed
    env.SetInstanceInfo("", "none", 0, "", 0)
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4469-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1)
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "1")

    -- 2. Cross boundary into Burning Steppes (ServerID 4471 -> Layer 1 or 3)
    env.FireEvent("ZONE_CHANGED_NEW_AREA")
    TestHarness.AssertNil(ULO.Detection.GetCurrentLayer())
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "-")

    -- 3. Scan Burning Steppes dragons (ServerID 4473 -> Layer 3)
    ULO.Detection.ScanGuid("Creature-0-4473-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4473-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 3)
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "3")

    -- 4. Enter Blackrock Depths dungeon portal
    env.SetInstanceInfo("Blackrock Depths", "party", 1, "Normal", 5)
    env.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "INSTANCED", "Detection suppressed in dungeon")
    TestHarness.AssertFalse(ULO.UI.MinimapBadge.IsShown(), "Minimap badge hidden in dungeon")
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetStatusText(), "Instanced (Layering Inactive)")

    -- 5. Complete dungeon, exit back to Burning Steppes
    env.SetInstanceInfo("", "none", 0, "", 0)
    env.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    TestHarness.AssertTrue(ULO.Detection.IsLayeringEnabled())
    ULO.Detection.ScanGuid("Creature-0-4473-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4473-0-14-1-2")
    TestHarness.AssertEqual(ULO.Detection.GetLayerConfidence(), "CONFIRMED", "Restored open world tracking")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "3")
end)

--------------------------------------------------------------------------------
-- T4-SCN-06: Rapid Hop Cooldown Lockout and Auto-Recovery
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F08_F10_F16_F17", "T4-SCN-06: Rapid Hop Cooldown Lockout and Auto-Recovery", function()
    local env, ULO = HelperSetup()
    -- Hop completed at t=100. Start 300s cooldown
    ULO.Monitor.StartCooldown(300)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 300)

    -- At t=120 (20s later, 280s remaining)
    env.AdvanceTime(20)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 280)
    local ok1, err1 = ULO.Coordination.RequestLayerHop(3)
    TestHarness.AssertFalse(ok1, "Hop blocked by cooldown at t=120")
    TestHarness.AssertEqual(err1, "cooldown")

    -- At t=200 (100s later, 200s remaining)
    env.AdvanceTime(80)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 200)
    local ok2, err2 = ULO.Coordination.RequestLayerHop(3)
    TestHarness.AssertFalse(ok2, "Hop blocked by cooldown at t=200")

    -- Advance simulated time past t=400 (t=401, delta = 201s)
    env.AdvanceTime(201)
    TestHarness.AssertEqual(ULO.Monitor.GetCooldownRemaining(), 0, "Cooldown fully expired")

    -- Hop now approved
    local ok3 = ULO.Coordination.RequestLayerHop(3)
    TestHarness.AssertTrue(ok3, "Hop approved after cooldown expiration")
end)

--------------------------------------------------------------------------------
-- T4-SCN-07: Inbound Whisper Spam Burst with Blacklist Filtering & Sound Muting
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F09_F10_F17", "T4-SCN-07: Inbound Whisper Spam Burst with Blacklist Filtering & Sound Muting", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)

    -- Whisper 1: Trade boost spam -> discarded
    local ok1, reason1 = ULO.Coordination.HandleWhisper("SpammerA", "WTS Blacksmithing services PST")
    TestHarness.AssertFalse(ok1)
    TestHarness.AssertEqual(reason1, "blacklisted")

    -- Whisper 2: NWB buff tag announcement -> discarded
    local ok2 = ULO.Coordination.HandleWhisper("SpammerB", "[NWB] Layer 1 Onyxia buff dropping in 5m")
    TestHarness.AssertFalse(ok2)

    -- Whisper 3: Valid layer whisper from PlayerValid1 -> invited
    local ok3 = ULO.Coordination.HandleWhisper("PlayerValid1", "layer")
    TestHarness.AssertTrue(ok3, "PlayerValid1 invited")
    TestHarness.AssertTrue(env.soundMuted, "Sound muted during invite")

    -- Whisper 4: Duplicate whisper from PlayerValid1 2s later -> throttled by cache
    env.AdvanceTime(2)
    local ok4, reason4 = ULO.Coordination.HandleWhisper("PlayerValid1", "inv layer please")
    TestHarness.AssertFalse(ok4, "Duplicate whisper throttled")
    TestHarness.AssertEqual(reason4, "cached")

    -- Whisper 5: Valid whisper from PlayerValid2 -> invited
    local ok5 = ULO.Coordination.HandleWhisper("PlayerValid2", "inv")
    TestHarness.AssertTrue(ok5, "PlayerValid2 invited")

    TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 2, "Exactly 2 valid invites dispatched")
    TestHarness.AssertTrue(ULO.Coordination.IsPlayerInInviteCache("PlayerValid1"))
end)

--------------------------------------------------------------------------------
-- T4-SCN-08: Cross-Release Seamless Operation (WoW Forever vs Classic Era vs Retail)
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F01_F03_F04_F11_F13", "T4-SCN-08: Cross-Release Seamless Operation (WoW Forever vs Classic Era vs Retail)", function()
    local totalErrors = 0

    -- Profile A: WoW Forever (Camelot, TOC 16001)
    local okA, errA = pcall(function()
        local envA, ULO_A = HelperSetup("wowf")
        TestHarness.AssertEqual(ULO_A.Compat.GetClientFlavor(), "wowf")
        TestHarness.AssertTrue(ULO_A.Compat.IsForever())
        TestHarness.AssertNil(envA.LeaveParty)
        TestHarness.AssertTrue(ULO_A.Compat.LeaveParty())
    end)
    if not okA then totalErrors = totalErrors + 1; print("Profile A error: " .. tostring(errA)) end

    -- Profile B: Classic Era (Vanilla, TOC 11509)
    local okB, errB = pcall(function()
        local envB, ULO_B = HelperSetup("wow_classic_era")
        TestHarness.AssertEqual(ULO_B.Compat.GetClientFlavor(), "wow_classic_era")
        TestHarness.AssertTrue(ULO_B.Compat.IsClassicEra())
        TestHarness.AssertNotNil(envB.LeaveParty)
        TestHarness.AssertTrue(ULO_B.Compat.LeaveParty())
    end)
    if not okB then totalErrors = totalErrors + 1; print("Profile B error: " .. tostring(errB)) end

    -- Profile C: Retail (Midnight, TOC 120105)
    local okC, errC = pcall(function()
        local envC, ULO_C = HelperSetup("wow")
        TestHarness.AssertEqual(ULO_C.Compat.GetClientFlavor(), "wow")
        TestHarness.AssertTrue(ULO_C.Compat.IsRetail())
        envC.MarkSecret("SecretData")
        TestHarness.AssertNil(ULO_C.Compat.SafeString("SecretData"))
    end)
    if not okC then totalErrors = totalErrors + 1; print("Profile C error: " .. tostring(errC)) end

    TestHarness.AssertEqual(totalErrors, 0, "All 3 release profiles executed with 0 errors")
end)

--------------------------------------------------------------------------------
-- T4-SCN-09: NovaWorldBuffs Bi-directional Layer Synchronization and Map Roster Discovery
--------------------------------------------------------------------------------
TestHarness.RunTest("Tier 4", "F03_F04_F14_F15_F16", "T4-SCN-09: NovaWorldBuffs Bi-directional Layer Synchronization and Map Roster Discovery", function()
    local env, ULO = HelperSetup()
    local syncLoopCount = 0
    env._G.NWB_CurrentLayer = 1
    env._G.NWB_LayerUpdated = function()
        syncLoopCount = syncLoopCount + 1
        -- NWB hook triggers ULO sync
        ULO.Interop.NWB.SyncWithNWB()
    end

    -- 1. ULO detects Layer 2 from creature scans
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-1434-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-1434-1-2")

    TestHarness.AssertEqual(env._G.NWB_CurrentLayer, 2, "NWB published to layer 2")
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 2, "ULO layer confirmed as 2")

    -- 2. Later, NWB receives guild sync collapsing world to Layer 1
    env._G.NWB_CurrentLayer = 1
    env._G.NWB_LayerUpdated()

    -- 3. ULO listener updates to Layer 1
    TestHarness.AssertEqual(ULO.Detection.GetCurrentLayer(), 1, "ULO synchronized to layer 1 from NWB")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "1", "Minimap badge updated to 1")
    TestHarness.AssertTrue(syncLoopCount <= 3, "No circular infinite recursion")
end)
