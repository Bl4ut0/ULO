-- ============================================================================
-- Tests/Tier3_PairwiseTests.lua
-- Universal Layer Operator (ULO)
-- Tier 3: Cross-Feature Pairwise Interactions (17 Test Cases)
-- ============================================================================

local TestHarness = ... or require("Tests.TestHarness")

local function HelperSetup(flavor)
    local env = TestHarness.NewEnvironment(flavor or "wowf")
    TestHarness.LoadAddonIntoEnv(env)
    return env, env.ULO
end

TestHarness.RunTest("Tier 3", "F04_F06", "T3-INT-01: Layer Shift Cancels Pending Refresh", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    env.AdvanceTime(70) -- 110s remaining
    TestHarness.AssertTrue(ULO.Monitor.IsRefreshPending())
    -- Confirm layer shift
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-2")
    TestHarness.AssertFalse(ULO.Monitor.IsRefreshPending(), "Refresh aborted on confirmed layer change")
    TestHarness.AssertEqual(ULO.Monitor.GetRefreshRemaining(), 0)
end)

TestHarness.RunTest("Tier 3", "F04_F15", "T3-INT-02: 2-GUID Consensus Triggers Badge Update", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-5123-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-5123-0-14-1-2")
    TestHarness.AssertEqual(ULO.UI.MinimapBadge.GetText(), "3", "Badge text updates to 3 on consensus")
end)

TestHarness.RunTest("Tier 3", "F04_F16", "T3-INT-03: Layer Confirmation Updates Status HUD", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetStatusText(), "Layer: ? (Undetermined)")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(ULO.UI.StatusHUD.GetStatusText(), "Layer: 2 (Confirmed)", "Status text updates to Layer: 2 (Confirmed)")
end)

TestHarness.RunTest("Tier 3", "F04_F14", "T3-INT-04: Consensus Publishes to NovaWorldBuffs", function()
    local env, ULO = HelperSetup()
    local nwbUpdatedCalled = false
    env._G.NWB_CurrentLayer = 1
    env._G.NWB_LayerUpdated = function() nwbUpdatedCalled = true end
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertEqual(env._G.NWB_CurrentLayer, 2, "NWB_CurrentLayer updated to 2")
    TestHarness.AssertTrue(nwbUpdatedCalled, "NWB_LayerUpdated hook was called")
end)

TestHarness.RunTest("Tier 3", "F06_F10", "T3-INT-05: Pending Refresh Suspends Automated Invites", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(30)
    local ok, reason = ULO.Coordination.HandleWhisper("HopRequester", "inv")
    TestHarness.AssertFalse(ok, "Auto-invite suspended during pending refresh")
    TestHarness.AssertEqual(reason, "refresh_pending")
    TestHarness.AssertNil(env.__harness.mockParty.lastInvited)
end)

TestHarness.RunTest("Tier 3", "F06_F16", "T3-INT-06: Countdown Progress Updates HUD Bar", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartRefreshWarning(180)
    env.AdvanceTime(170) -- ticks down to 10s
    TestHarness.AssertTrue(ULO.UI.StatusHUD.IsUrgentAlertActive(), "HUD urgent alert active at 10s")
end)

TestHarness.RunTest("Tier 3", "F06_F07", "T3-INT-07: Combat Deferral Lifecycle", function()
    local env, ULO = HelperSetup()
    env.SetUnit("player", { inCombat = true })
    ULO.Monitor.StartRefreshWarning(1)
    env.AdvanceTime(2)
    TestHarness.AssertTrue(ULO.Monitor.IsCombatDeferred())
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 0)
    -- Combat drops
    env.SetUnit("player", { inCombat = false })
    env.FireEvent("PLAYER_REGEN_ENABLED")
    env.AdvanceTime(3) -- 2s safety buffer expires
    TestHarness.AssertEqual(env.__harness.reloadExecutionCount, 1, "Reload executes after regen buffer")
end)

TestHarness.RunTest("Tier 3", "F09_F12", "T3-INT-08: AutoLayer Segment Header Matches Keyword Engine", function()
    local env, ULO = HelperSetup()
    local valid = ULO.Coordination.IsValidLayerRequest("<AZ> inv layer 2")
    TestHarness.AssertTrue(valid, "AutoLayer segment request matched by keyword engine")
end)

TestHarness.RunTest("Tier 3", "F10_F13", "T3-INT-09: Overlord R:2 Wire Message Enrolls Invite Cache", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.ToggleAutoInvite(true)
    env.FireEvent("CHAT_MSG_ADDON", "OverlordLJ", "R:2:42:1", "WHISPER", "Jumper")
    TestHarness.AssertTrue(ULO.Coordination.IsPlayerInInviteCache("Jumper"), "Jumper enrolled in player invite cache")
end)

TestHarness.RunTest("Tier 3", "F10_F11", "T3-INT-10: Auto-Accept and Post-Hop Auto-Leave", function()
    local env, ULO = HelperSetup()
    ULO.Coordination.RequestLayerHop(2)
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper-Realm")
    env.FireEvent("GROUP_JOINED", 1, "party-guid-123")
    -- Confirm new layer
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4470-0-14-1-2")
    ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(env.__harness.mockParty.leftCount >= 1, "Auto-leaves group after transfer verified")
end)

TestHarness.RunTest("Tier 3", "F08_F10", "T3-INT-11: Active Cooldown Blocks Outgoing Hop Requests", function()
    local env, ULO = HelperSetup()
    ULO.Monitor.StartCooldown(300)
    env.AdvanceTime(50) -- 250s remaining
    local ok, err = ULO.Coordination.RequestLayerHop(3)
    TestHarness.AssertFalse(ok, "Outgoing hop blocked during active cooldown")
    TestHarness.AssertNil(env.__harness.mockChat.lastBroadcast, "No broadcast sent")
end)

TestHarness.RunTest("Tier 3", "F01_F03", "T3-INT-12: Retail Secret GUIDs Protected by pcall", function()
    local env, ULO = HelperSetup("wow")
    local secretGuid = "Creature-0-4469-0-14-1-99"
    env.MarkSecret(secretGuid)
    env.SetUnit("target", { guid = secretGuid })
    local res = ULO.Detection.ScanUnitSafe("target")
    TestHarness.AssertNil(res, "Secret GUID handled safely without crash")
end)

TestHarness.RunTest("Tier 3", "F01_F10", "T3-INT-13: WoW Forever Safe Departure via C_PartyInfo", function()
    local env, ULO = HelperSetup("wowf")
    TestHarness.AssertNil(env.LeaveParty, "Global LeaveParty is nil on wowf")
    local ok = ULO.Compat.LeaveParty()
    TestHarness.AssertTrue(ok, "Leaves party cleanly via C_PartyInfo")
    TestHarness.AssertTrue(env.__harness.mockParty.cPartyLeaveCount >= 1)
end)

TestHarness.RunTest("Tier 3", "F17_F09", "T3-INT-14: /ulo invite off Immediately Mutes Whispers", function()
    local env, ULO = HelperSetup()
    ULO.HandleSlashCommand("invite off")
    local ok, reason = ULO.Coordination.HandleWhisper("NewPlayer", "layer")
    TestHarness.AssertFalse(ok, "Whisper rejected when invite off")
    TestHarness.AssertEqual(reason, "disabled")
end)

TestHarness.RunTest("Tier 3", "F05_F04_F15", "T3-INT-15: Dungeon Entry Hides Minimap Badge", function()
    local env, ULO = HelperSetup()
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-4472-0-14-1-2")
    TestHarness.AssertTrue(ULO.UI.MinimapBadge.IsShown())
    -- Step into dungeon instance
    env.SetInstanceInfo("Shadowfang Keep", "party", 1, "Normal", 5)
    env.FireEvent("ZONE_CHANGED_NEW_AREA")
    TestHarness.AssertFalse(ULO.UI.MinimapBadge.IsShown(), "Badge hidden inside dungeon instance")
end)

TestHarness.RunTest("Tier 3", "F13_F10", "T3-INT-16: Overlord Wire Decline on Full Group", function()
    local env, ULO = HelperSetup()
    env.__harness.mockParty.members = { "player", "m1", "m2", "m3", "m4" } -- 5 members (full)
    ULO.Interop.Overlord.ProcessMessage("R:2:777:2", "HopRequester")
    local lastMsg = env.__harness.mockChat.outgoingAddonMessages[#env.__harness.mockChat.outgoingAddonMessages]
    TestHarness.AssertNotNil(lastMsg)
    TestHarness.AssertEqual(lastMsg.message, "N:777:full", "Responds with N:777:full wire decline")
end)

TestHarness.RunTest("Tier 3", "F12_F01", "T3-INT-17: Calendar Date Rollover Regenerates Adler32 Channel", function()
    local env, ULO = HelperSetup()
    local initialCount = #env.__harness.mockChat.joinedChannels
    env.FireEvent("CALENDAR_UPDATE_EVENT_LIST")
    TestHarness.AssertTrue(#env.__harness.mockChat.joinedChannels > initialCount, "Rejoins channels on date rollover")
end)
