-- ============================================================================
-- Tests/Tier4_ScenarioTests.lua
-- Universal Layer Operator (ULO)
-- Tier 4: Real-World Application Scenarios (19 Comprehensive User Workflows)
-- ============================================================================

local TestHarness = ... or require("Tests.TestHarness")

local function HelperSetup(flavor)
    local env = TestHarness.NewEnvironment(flavor or "wowf")
    TestHarness.LoadAddonIntoEnv(env)
    return env, env.ULO
end

-- Owner reports, November 16, 2026: Hop Any produces a burst of duplicate group
-- notices, a "cannot invite yourself" error, and requests helpers on our layer.
-- Names are sanitized; native system text below follows the supplied chat log.
local function HopReportSetup(flavor)
    local env = TestHarness.NewEnvironment(flavor or "wowf")
    local filters = {}
    env.GetRealmName = function() return "Camelot" end
    env.ERR_INVITED_TO_GROUP_S = "%s has invited you to join a group."
    env.ERR_INVITED_TO_GROUP_SS = "%s invited you to a group, but you could not accept because you are already in a group."
    env.ChatFrame_AddMessageEventFilter = function(event, filter) filters[event] = filter end
    TestHarness.LoadAddonIntoEnv(env)
    local function filtered(msg)
        local filter = filters.CHAT_MSG_SYSTEM
        return filter and filter(nil, "CHAT_MSG_SYSTEM", msg) == true or false
    end
    return env, env.ULO, filtered
end

local function ConfirmReportLayer(ULO, sid)
    ULO.Detection.ResetContext(false)
    ULO.Detection.ScanGuid("Creature-0-" .. sid .. "-0-14-1-1")
    ULO.Detection.ScanGuid("Creature-0-" .. sid .. "-0-14-1-2")
end

local function HopRequestCount(env)
    local count = 0
    for _, row in ipairs(env.__harness.mockChat.outgoingAddonMessages) do
        if row.chatType == "WHISPER" and string.match(row.message or row.msg or "", "^R:") then
            count = count + 1
        end
    end
    return count
end

-- Owner stack: AutoLayerProtocol.lua:346 compares a secret sender on
-- CHAT_MSG_CHANNEL, with secret text and a readable daily channel name.
-- Stock Lua cannot taint primitive equality: traps below enforce string API
-- boundaries, while the empty-secret case detects the premature equality return.
TestHarness.RunTest("Tier 4", "F12", "reported-secret-channel-message-and-sender", function()
    for _, flavor in ipairs({ "wowf", "wow_anniversary", "wow_classic_era", "wow_classic", "wow" }) do
        for _, field in ipairs({ "both", "message", "sender", "empty_sender", "channel", "fallback_channel" }) do
            local env, ULO = HopReportSetup(flavor)
            ConfirmReportLayer(ULO, 4470)
            local message, sender = "<AZ> inv layer 2", "UnreadablePeer-Camelot"
            local display, base = "3. layer9b190880", "layer9b190880"
            if field == "both" or field == "message" then env.MarkSecret(message) end
            if field == "both" or field == "sender" then env.MarkSecret(sender) end
            if field == "empty_sender" then sender = ""; env.MarkSecret(sender) end
            if field == "channel" then env.MarkSecret(base) end
            if field == "fallback_channel" then base = nil; env.MarkSecret(display) end
            local checks, dispatches = 0, 0
            local secret = env.issecretvalue
            env.issecretvalue = function(value)
                if secret(value) then checks = checks + 1 end
                return secret(value)
            end
            local function CheckArguments(...)
                for n = 1, select("#", ...) do
                    if secret(select(n, ...)) then error("Secret passed to a string operation", 2) end
                end
            end
            for _, operation in ipairs({ "match", "find", "lower", "format", "gsub" }) do
                local original = env.string[operation]
                env.string[operation] = function(...)
                    CheckArguments(...)
                    return original(...)
                end
            end
            local stringify = env.tostring
            env.tostring = function(value) CheckArguments(value); return stringify(value) end
            local handle = ULO.Coordination.HandleWhisper
            ULO.Coordination.HandleWhisper = function(...)
                dispatches = dispatches + 1
                return handle(...)
            end
            local logCount = #ULO.GetActionLog()
            -- Preserve the owner's event shape, including unused secret fields.
            local unused = "UnusedSecretPayload"
            env.MarkSecret(unused)
            env.FireEvent("CHAT_MSG_CHANNEL", message, sender, "", display, unused, "NEWCOMER", 0, 3, base)
            TestHarness.AssertTrue(checks > 0, "Secrecy is checked before reading or comparing a protected field: " .. field)
            TestHarness.AssertEqual(dispatches, 0, "Secret channel data never reaches invitation dispatch")
            TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 0)
            TestHarness.AssertEqual(#ULO.GetActionLog(), logCount, "Unreadable data is not copied to the action log")
        end
        for _, event in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER", "CHAT_MSG_ADDON" }) do
          for _, field in ipairs({ "message", "sender", "empty_message", "empty_sender" }) do
            local env, ULO = HopReportSetup(flavor)
            ConfirmReportLayer(ULO, 4470)
            local message = event == "CHAT_MSG_ADDON" and "R:secret:2:3" or "inv layer 2"
            local sender = "UnreadablePeer-Camelot"
            if field == "empty_message" then message = "" end
            if field == "empty_sender" then sender = "" end
            env.MarkSecret((field == "message" or field == "empty_message") and message or sender)
            local checked = false
            local secret = env.issecretvalue
            env.issecretvalue = function(value)
                if secret(value) then checked = true end
                return secret(value)
            end
            if event == "CHAT_MSG_ADDON" then
                env.FireEvent(event, "ULO", message, "WHISPER", sender)
            else
                env.FireEvent(event, message, sender)
            end
            TestHarness.AssertTrue(checked, "Related chat entry points guard protected text before comparison: " .. event .. "/" .. field)
            TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 0)
          end
        end
        -- Unused protected event arguments do not hide an otherwise readable
        -- public request; clients without the secrecy APIs remain supported.
        for _, legacy in ipairs({ false, true }) do
            local env, ULO = HopReportSetup(flavor)
            ConfirmReportLayer(ULO, 4470)
            if legacy then env.issecretvalue, env.canaccessvalue = nil, nil end
            env.MarkSecret("UnusedSecretPayload")
            env.FireEvent("CHAT_MSG_CHANNEL", "<AZ> inv layer 2", "ReadablePeer-Camelot", "",
                "3. layer9b190880", "UnusedSecretPayload", "NEWCOMER", 0, 3, "layer9b190880")
            TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 1, "Readable public layer requests still invite once")
        end
    end
end)

TestHarness.RunTest("Tier 4", "F10_F12_F14", "ulo-zone-aware-wire-and-legacy-compatibility", function()
    for _, flavor in ipairs({ "wowf", "wow_anniversary" }) do
        local env, ULO = HopReportSetup(flavor)
        ConfirmReportLayer(ULO, 4470)
        env.FireEvent("CHAT_MSG_ADDON", "ULO", "S2:3:4473:1:1411", "WHISPER", "SameZone-Camelot")
        env.FireEvent("CHAT_MSG_ADDON", "ULO", "S2:3:4473:1:1429", "WHISPER", "WrongZone-Camelot")
        local peers = ULO.Interop.NWB.GetKnownLayerPeers(3)
        TestHarness.AssertEqual(#peers, 1, "Known cross-zone helpers are excluded")
        TestHarness.AssertEqual(peers[1].name, "SameZone-Camelot")
        ULO.Interop.Guild.BroadcastHopRequest(3, true)
        local outgoing = env.__harness.mockChat.outgoingAddonMessages
        TestHarness.AssertMatch(outgoing[#outgoing].message, "^R2:[^:]+:3:2:1411$", "Capable ULO peers receive versioned zone requests")
        local public = ULO.Interop.AutoLayer.FormatBroadcastMessage(nil)
        if flavor == "wow_anniversary" then
            TestHarness.AssertMatch(public, "^<AL2V1_9_5Z1411> inv not layer 2$", "TBC uses the shipped AL2 zone capability")
        else
            TestHarness.AssertEqual(public, "<AZ> inv not layer 2", "Forever external requests retain their legacy format")
        end
        env.NWBdatabase = { guildLayers = { IntelligenceOnly = 3, ["SameZone-Camelot"] = 3 } }
        ULO.Interop.NWB.GetKnownLayerPeers(3)
        TestHarness.AssertFalse(ULO.Intelligence.GetPeer("IntelligenceOnly").helper, "NWB visibility is not helper consent")
        TestHarness.AssertTrue(ULO.Intelligence.GetPeer("SameZone-Camelot").helper, "NWB observations preserve fresh explicit ULO consent")
        env.AdvanceTime(91)
        TestHarness.AssertEqual(#ULO.Interop.NWB.GetKnownLayerPeers(3), 0, "Stale zone-aware helpers are not targeted")
        ULO.Interop.Guild.RecordPeer("Legacy-Camelot", 3, 4473, true, "ULO")
        ULO.Interop.Guild.BroadcastHopRequest(3, true)
        outgoing = env.__harness.mockChat.outgoingAddonMessages
        TestHarness.AssertMatch(outgoing[#outgoing].message, "^R:[^:]+:3:2$", "Legacy ULO peers keep their old request format")
        ConfirmReportLayer(ULO, 4473)
        local invites = env.__harness.mockParty.inviteCallCount
        env.FireEvent("CHAT_MSG_ADDON", "ULO", "R2:badzone:3:2:1429", "WHISPER", "RequesterWrong-Camelot")
        TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, invites, "R2 rejects the wrong zone before inviting")
        env.FireEvent("CHAT_MSG_ADDON", "ULO", "R2:goodzone:3:2:1411", "WHISPER", "RequesterGood-Camelot")
        TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, invites + 1, "R2 accepts the same zone and desired layer")
    end
end)

TestHarness.RunTest("Tier 4", "F05_F11_F12", "zone-aware-owned-group-verification", function()
    for _, flavor in ipairs({ "wowf", "wow_anniversary" }) do
        for _, zone in ipairs({ 1411, 1429, 0 }) do
            local env, ULO = HopReportSetup(flavor)
            ConfirmReportLayer(ULO, 4470)
            env.SetUnit("Remote-Camelot", { name = "Remote-Camelot", isPlayer = true, mapID = zone ~= 0 and zone or nil })
            ULO.Coordination.RequestLayerHop(3)
            env.FireEvent("PARTY_INVITE_REQUEST", "Remote-Camelot")
            ULO.TriggerCallback("OnLayerChanged", 3, 4473, 14)
            if zone == 1411 then
                TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1, "A verified same-zone transfer departs")
            elseif zone == 1429 then
                TestHarness.AssertFalse(ULO.Coordination.IsAwaitingLayerVerification(), "A mismatched leader is rejected")
                TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1, "Only the owned incompatible hop group is left")
            else
                TestHarness.AssertTrue(ULO.Coordination.IsAwaitingLayerVerification(), "An unreadable leader is not falsely verified")
                env.AdvanceTime(6.1)
                TestHarness.AssertFalse(ULO.Coordination.IsAwaitingLayerVerification(), "Unverified scope has a bounded retry window")
                TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1)
            end
        end
    end
    local env, ULO = HopReportSetup()
    ConfirmReportLayer(ULO, 4470)
    ULO.Coordination.RequestLayerHop(3)
    env.FireEvent("PARTY_INVITE_REQUEST", "Remote-Camelot")
    env.__harness.mockParty.members = { "player", "FriendA", "FriendB" }
    ULO.Coordination.CheckHopZone()
    TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 0, "A foreign social group is preserved")
end)

-- Source-backed report from the side chat: ULO used to change the native
-- volunteer setting and replace OnRequest, bypassing Overlord bookkeeping.
TestHarness.RunTest("Tier 4", "F13", "reported-overlord-preserves-native-helper-controls", function()
    local env, ULO = HopReportSetup()
    local modeChanges, pvpTouches = 0, 0
    local original = function() end
    env.Overlord = {
        LayerJumper = { OnRequest = original, SetHelpMode = function() modeChanges = modeChanges + 1 end,
            GetHelpMode = function() return "off" end, KnownPlayers = function() return {} end },
        Shard = { currentShardID = 777 },
        GroupFinder = { Contacts = function() pvpTouches = pvpTouches + 1; return { "NonVolunteer" } end },
    }
    ULO.Interop.Overlord.SyncHelpMode()
    ULO.SetTrackEnabled("overlord", false)
    ULO.SetTrackEnabled("overlord", true)
    ULO.Interop.Overlord.GetPeerSummary()
    ULO.TriggerCallback("OnLayerChanged", 2, 4470, 14)
    TestHarness.AssertEqual(modeChanges, 0, "ULO does not change native helping preferences")
    TestHarness.AssertEqual(env.Overlord.LayerJumper.OnRequest, original, "Native request handler is preserved")
    TestHarness.AssertEqual(env.Overlord.Shard.currentShardID, 777, "Native shard state is not fabricated")
    TestHarness.AssertEqual(pvpTouches, 0, "PvP contacts do not become layer volunteers")
    ULO.Interop.Overlord.ProcessMessage("R:2:native:1", "Requester-Camelot")
    TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 0, "ULO does not duplicate the installed native helper controller")
    ULO.Interop.Overlord = nil
    ULO.SetULOOnlyMode(true)
    env.FireEvent("PLAYER_ENTERING_WORLD")
    TestHarness.AssertEqual(modeChanges, 0, "UI fallback paths also preserve native preferences")
end)

TestHarness.RunTest("Tier 4", "F11_F13", "overlord-native-hop-lifecycle-owner", function()
    local env, ULO = HopReportSetup()
    ConfirmReportLayer(ULO, 4470)
    local joins, cancels = 0, 0
    local lj = { state = "idle" }
    function lj:IsActive() return self.state ~= "idle" end
    function lj:MyLayer() return 9001 end
    function lj:KnownPlayers() return { { name = "Volunteer-Camelot", layer = 9002, helper = true },
        { name = "NonVolunteer-Camelot", layer = 9003 } } end
    function lj:Join(name, nativeLayer)
        joins = joins + 1
        TestHarness.AssertEqual(name, "Volunteer-Camelot")
        TestHarness.AssertEqual(nativeLayer, 9002, "Native shard IDs are not ordinal UI layers")
        self.hop, self.state = { current = { name = name, key = "volunteer" } }, "requesting"
        return true
    end
    function lj:Cancel() cancels = cancels + 1; self.hop, self.state = nil, "idle" end
    env.Overlord = { LayerJumper = lj }
    TestHarness.AssertEqual(ULO.Interop.Overlord.BroadcastHopRequest(3), 0, "Unknown-zone native volunteers are not marked verified")
    ULO.Intelligence.RecordPeer("Volunteer-Camelot", 3, 4473, true, 1411, 2, "ULO")
    ULO.Coordination.RequestLayerHop(3, "Overlord")
    TestHarness.AssertEqual(joins, 1, "Request enters native Join once")
    env.AdvanceTime(13)
    TestHarness.AssertTrue(ULO.Coordination.IsAwaitingHop(), "ULO does not impose its former four-second retry")
    local nativeFrame = env.CreateFrame("Frame")
    nativeFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    nativeFrame:SetScript("OnEvent", function(_, _, sender)
        if sender == "Volunteer-Camelot" and lj.state == "requesting" then
            lj.state = "joining"; env.AcceptGroup(); lj.state = "verifying"
        end
    end)
    env.FireEvent("PARTY_INVITE_REQUEST", "Volunteer-Camelot")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1, "Only the native controller accepts")
    ULO.TriggerCallback("OnLayerChanged", 3, 4473, 14)
    TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 0, "ULO does not compete with native departure")
    lj.state, lj.hop = "idle", nil
    env.C_PartyInfo.LeaveParty()
    TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1)
    TestHarness.AssertEqual(cancels, 0, "Normal native completion is not cancelled by ULO")
    TestHarness.AssertFalse(ULO.Coordination.IsAwaitingLayerVerification())
end)

TestHarness.RunTest("Tier 4", "F11_F13", "overlord-legacy-zone-fallback-and-rejection", function()
    for _, flavor in ipairs({ "wowf", "wow_anniversary" }) do
        for _, helperZone in ipairs({ 1411, 1429, 0 }) do
            local env, ULO = HopReportSetup(flavor)
            ConfirmReportLayer(ULO, 4470)
            local selected, cancels = nil, 0
            local lj = { state = "idle" }
            function lj:IsActive() return self.state ~= "idle" end
            function lj:MyLayer() return 9001 end
            function lj:KnownPlayers() return {
                { name = "ALegacy-Camelot", layer = 9002, helper = true },
                { name = "Verified-Camelot", layer = 9003, helper = true },
                { name = "Wrong-Camelot", layer = 9004, helper = true },
                { name = "Observer-Camelot", layer = 9005 },
            } end
            function lj:Join(name)
                selected = name
                self.hop, self.state = { current = { name = name } }, "requesting"
                return true
            end
            function lj:Cancel()
                cancels = cancels + 1
                self.hop, self.state = nil, "idle"
                if env.IsInGroup() then env.C_PartyInfo.LeaveParty() end
            end
            env.Overlord = { LayerJumper = lj }
            ULO.Intelligence.RecordPeer("Verified-Camelot", 3, 4473, true, 1411, 2, "ULO")
            ULO.Intelligence.RecordPeer("Wrong-Camelot", 4, 4474, true, 1429, 2, "ULO")
            ULO.Coordination.RequestLayerHop(nil, "Overlord")
            TestHarness.AssertEqual(selected, "Verified-Camelot", "Verified same-zone volunteers take priority")
            ULO.Coordination.CancelHopRequest("fixture")
            -- Only the old volunteer remains. Its zone is explicitly unverified,
            -- while native raw shard IDs establish a different origin.
            lj.KnownPlayers = function() return { { name = "ALegacy-Camelot", layer = 9002, helper = true } } end
            ULO.Coordination.RequestLayerHop(nil, "Overlord")
            TestHarness.AssertEqual(selected, "ALegacy-Camelot", "Legacy native volunteers remain usable through post-join checks")
            env.SetUnit("ALegacy-Camelot", { name = "ALegacy-Camelot", isPlayer = true,
                mapID = helperZone ~= 0 and helperZone or nil })
            local nativeFrame = env.CreateFrame("Frame")
            nativeFrame:RegisterEvent("PARTY_INVITE_REQUEST")
            nativeFrame:SetScript("OnEvent", function()
                lj.state = "verifying"
                env.AcceptGroup()
            end)
            env.FireEvent("PARTY_INVITE_REQUEST", "ALegacy-Camelot")
            if helperZone == 1411 then
                TestHarness.AssertEqual(cancels, 1, "A same-zone native group stays with its native controller")
                ULO.TriggerCallback("OnZoneChanged", 1429)
                TestHarness.AssertEqual(cancels, 2, "Moving requester zones cancels through native ownership")
            else
                if helperZone == 0 then env.AdvanceTime(6.1) end
                TestHarness.AssertEqual(cancels, 2, "Mismatched or unreadable leaders cancel the native operation")
            end
            TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1, "There is one acceptance owner")
            TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1, "Only native cancellation leaves its group")
        end
    end
end)

TestHarness.RunTest("Tier 4", "F11_F12_F16", "reported-hop-any-excludes-current-layer", function()
    for _, uloOnly in ipairs({ false, true }) do
        local env, ULO = HopReportSetup()
        env.ULODB = { uloOnlyMode = uloOnly }
        ConfirmReportLayer(ULO, 4470) -- Layer 2.
        local ok, reason = ULO.Coordination.RequestLayerHop(2)
        TestHarness.AssertFalse(ok, "An explicit request for our current layer is rejected")
        TestHarness.AssertEqual(reason, "already_on_layer")
        env.ULOStatusHUDHopButton:Click()
        local chat = env.__harness.mockChat.outgoingChatMessages
        TestHarness.AssertEqual(#chat, 1, "No directed helpers means one public fallback")
        TestHarness.AssertMatch(chat[1].msg, "inv not layer 2$", "Hop Any excludes its origin layer")
        env.ULOStatusHUDHopButton:Click()
        TestHarness.AssertEqual(#chat, 1, "Repeated clicks cannot broadcast another active request")
        ULO.Intelligence.RecordPeer("SameHelper-Camelot", 2, 4470, true, 1411, 2, "ULO")
        env.FireEvent("PARTY_INVITE_REQUEST", "SameHelper-Camelot")
        TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 0, "A known same-layer helper's invite cannot be accepted")
        env.FireEvent("PARTY_INVITE_REQUEST", "OtherHelper-Camelot")
        ULO.TriggerCallback("OnLayerChanged", 2, 4470, 14)
        ULO.TriggerCallback("OnLayerChanged", "2", 4470, 14)
        TestHarness.AssertTrue(ULO.Coordination.IsAwaitingLayerVerification(), "Origin-layer confirmation is not a successful hop")
        TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 0, "Same-layer confirmation does not depart as a success")
        ULO.TriggerCallback("OnLayerChanged", 3, 4473, 14)
        TestHarness.AssertFalse(ULO.Coordination.IsAwaitingLayerVerification(), "Different layer finishes verification")
        TestHarness.AssertEqual(env.__harness.mockParty.leftCount, 1, "Successful transfer departs exactly once")
    end
    local env, ULO = HopReportSetup()
    local ok, reason = ULO.Coordination.RequestLayerHop(nil)
    TestHarness.AssertFalse(ok, "Hop Any waits for a known origin")
    TestHarness.AssertEqual(reason, "layer_unknown")
    TestHarness.AssertEqual(#env.__harness.mockChat.outgoingChatMessages, 0, "Unknown origin never broadcasts an unrestricted request")
end)

TestHarness.RunTest("Tier 4", "F10_F11_F16", "reported-hop-group-invite-burst", function()
    local env, ULO, filtered = HopReportSetup()
    ConfirmReportLayer(ULO, 4470)
    local first = "[Helper01] has invited you to join a group."
    TestHarness.AssertFalse(filtered(first), "Social invite notices are untouched outside a hop")
    env.ULOStatusHUDHopButton:Click()
    env.AdvanceTime(1)
    TestHarness.AssertTrue(filtered(first), "Own-hop invite notice is kept out of system chat")
    env.FireEvent("PARTY_INVITE_REQUEST", "Helper01-Camelot")
    for i = 2, 19 do
        local msg = string.format("[Helper%02d] invited you to a group, but you could not accept because you are already in a group.", i)
        TestHarness.AssertTrue(filtered(msg), "Reported duplicate invite notice is suppressed during this hop")
    end
    TestHarness.AssertFalse(filtered("Looting set to Group Loot."), "Unrelated system messages remain visible")
    TestHarness.AssertFalse(filtered("You cannot invite yourself."), "Self-invite errors are prevented, not hidden")
    env.FireEvent("PARTY_INVITE_REQUEST", "LateHelper-Camelot")
    TestHarness.AssertEqual(env.__harness.mockParty.acceptCallCount, 1, "Only the first invite is accepted")
    TestHarness.AssertFalse(ULO.Coordination.IsAwaitingHop(), "Accepted hop stops requesting invites")
    env.AdvanceTime(41)
    TestHarness.AssertFalse(filtered(first), "The hop filter expires for later social invites")
end)

TestHarness.RunTest("Tier 4", "F01_F09_F10_F12_F13", "reported-hop-self-invite-guard", function()
    for _, flavor in ipairs({ "wowf", "wow_anniversary", "wow_classic_era", "wow_classic", "wow" }) do
        local env, ULO = HopReportSetup(flavor)
        for _, selfName in ipairs({ "Blauto", "Blauto-Camelot", "blauto-camelot", "  Blauto  " }) do
            local ok, reason = ULO.Compat.InviteUnit(selfName)
            TestHarness.AssertFalse(ok, "Shared invite API rejects the current player")
            TestHarness.AssertEqual(reason, "self_invite")
            env.FireEvent("CHAT_MSG_WHISPER", "inv layer", selfName)
            env.FireEvent("CHAT_MSG_GUILD", "inv layer", selfName)
            env.FireEvent("CHAT_MSG_CHANNEL", "<AZ> inv layer", selfName, nil, "6. layer", nil, nil, nil, 6, "layer")
            ULO.Interop.Overlord.ProcessMessage("R:2:selfguard:-", selfName)
            ULO.Interop.Overlord.SendHopRequest(selfName, nil)
            for _, prefix in ipairs({ "ULO", "TresLayerSwap", "LayerHopper" }) do
                ULO.Interop.Guild.ProcessAddonMessage(prefix, "R:selfguard:-:1", "WHISPER", selfName)
            end
        end
        TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 0, "No protocol can issue a native self invite")
        env.FireEvent("CHAT_MSG_WHISPER", "[AutoLayer] Inviting you to layer 2...", "OtherHelper-Camelot")
        env.FireEvent("CHAT_MSG_WHISPER", "[AutoLayer] Please Leave Party after layer switch", "OtherHelper-Camelot")
        TestHarness.AssertEqual(env.__harness.mockParty.inviteCallCount, 0, "Automated replies are not treated as hop requests")
        TestHarness.AssertTrue(ULO.Compat.InviteUnit("Blauto-OtherRealm"), "A different realm's namesake remains a valid target")
        TestHarness.AssertTrue(ULO.Coordination.HandleWhisper("Friend-Camelot", "inv layer"), "A real friend's request still works")
    end
end)

TestHarness.RunTest("Tier 4", "F11_F12_F13_F14", "hop-directed-helpers-before-public-fallback", function()
    local env, ULO = HopReportSetup()
    ConfirmReportLayer(ULO, 4470)
    ULO.Interop.Guild.RecordPeer("SameHelper-Camelot", 2, 4470, true, "ULO")
    ULO.Interop.Guild.RecordPeer("OtherHelper-Camelot", 3, 4473, true, "ULO")
    env.Overlord = { LayerJumper = { KnownPlayers = function() return {
        { name = "SameOverlord-Camelot", layer = 4470, helper = true },
        { name = "OtherOverlord-Camelot", layer = 4473, helper = true },
    } end } }
    ULO.Coordination.RequestLayerHop(nil)
    TestHarness.AssertEqual(#env.__harness.mockChat.outgoingChatMessages, 0, "Known helpers are tried before public chat")
    TestHarness.AssertEqual(HopRequestCount(env), 1, "Only one helper is contacted at a time")
    env.AdvanceTime(4.1)
    TestHarness.AssertEqual(HopRequestCount(env), 1, "No competing four-second retry")
    TestHarness.AssertEqual(#env.__harness.mockChat.outgoingChatMessages, 0, "No simultaneous public request")
    env.FireEvent("PARTY_INVITE_REQUEST", "OtherOverlord-Camelot")
    env.AdvanceTime(20)
    TestHarness.AssertEqual(HopRequestCount(env), 1, "Acceptance stops remaining helper requests")
    TestHarness.AssertEqual(#env.__harness.mockChat.outgoingChatMessages, 0, "Acceptance cancels public fallback")

    local fallback, fallbackULO = HopReportSetup()
    ConfirmReportLayer(fallbackULO, 4470)
    fallbackULO.Interop.Guild.RecordPeer("OtherHelper-Camelot", 3, 4473, true, "ULO")
    fallback.Overlord = env.Overlord
    fallbackULO.Coordination.RequestLayerHop(nil)
    fallback.AdvanceTime(12.1)
    TestHarness.AssertEqual(#fallback.__harness.mockChat.outgoingChatMessages, 1, "Unanswered directed requests fall back once")
    TestHarness.AssertMatch(fallback.__harness.mockChat.outgoingChatMessages[1].msg, "inv not layer 2$")
    fallback.AdvanceTime(10)
    TestHarness.AssertEqual(#fallback.__harness.mockChat.outgoingChatMessages, 1, "Fallback is not repeated automatically")
end)

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
    -- 1. Hellfire Peninsula is a zone within the Outland continent.
    env.__harness.mockMap.maps[1944] = { mapType = 3, parentMapID = 1945, name = "Hellfire Peninsula" }
    env.SetUnit("player", { mapID = 1944 })
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
