# Universal Layer Operator (ULO) — Test Infrastructure Specification

## 1. Test Philosophy

Universal Layer Operator (ULO) is designed as a mission-critical, multi-release World of Warcraft layering addon and technical specification. In World of Warcraft, layering, refresh monitoring, and cross-addon hopping operate across asynchronous network events, chat channels, whisper triggers, and combat restrictions. 

To guarantee reliability across all supported game releases without requiring a running World of Warcraft graphic client during automated builds and continuous integration, ULO adopts the following testing principles:

1. **Standalone Headless Execution**:
   - The test infrastructure executes in pure standard Lua (Lua 5.1 / LuaJIT / lua-wow) with zero external binaries, third-party libraries, or Blizzard client dependencies.
   - Modeled FrameXML, party, map and chat APIs run inside an isolated Lua sandbox table (`_G` self-referencing). These models do not replace native-client acceptance.
2. **Deterministic Virtual Clock & Event Engine**:
   - Time-dependent mechanics—such as the 180-second layer refresh warning window and the 300-second layer hopping cooldown—are controlled by an accelerated, monotonic virtual clock (`GetTime()` and `C_Timer`).
   - Tests advance virtual time deterministically via `env.AdvanceTime(deltaSeconds)`, executing all scheduled callbacks and frame updates instantaneously without wall-clock sleeps.
3. **Multi-Release Environment Sandboxing**:
   - Each test can instantiate an isolated WoW environment conditioned to specific client releases:
     - `wowf`: Camelot (WoW Forever, TOC 16001)
     - `wow_anniversary`: Classic Anniversary TBC (TOC 20506)
     - `wow_classic_era`: Vanilla / SoD / Hardcore (TOC 11509)
     - `wow_classic`: Classic Progression Mists (TOC 50504)
     - `wow`: Retail Midnight (TOC 120105)
   - Release-specific behaviors—such as the absence of global `LeaveParty` on WoW Forever or `issecretvalue()` guards on Retail—are explicitly validated.
4. **Opaque-Box Requirement-Driven Verification**:
   - Tests exercise public interface contracts, event listeners, and wire protocols rather than testing internal private variables.
   - Assertions verify authentic state transitions, output strings, network wire packets, and UI element text.
5. **Fail-Fast Integrity**:
   - All 247 standard-gate cases execute production behavior through modeled client APIs. Assertions cover parsing, consensus voting, timers, messages and UI controls.
   - The test runner returns OS exit code `0` if and only if 100% of executed tests pass, and non-zero on any failure.

---

## 2. 17-Feature Inventory (F01–F17)

Every feature in ULO is indexed with a unique identifier and mapped across project milestones and functional requirements:

| Feature ID | Feature Name | Description | Milestone | Source Requirement |
|------------|--------------|-------------|-----------|--------------------|
| **F01** | Multi-Release Compatibility Layer | Environment detection (`wowf`, `wow_classic_era`, etc.), TOC versions, safe party API shims (`LeaveParty`, `InviteUnit`), and `issecretvalue` / lockdown guards. | M1 | Survey, PROJECT.md §1 |
| **F02** | Technical Specification Document | Verification of `TECHNICAL_SPECIFICATION.md` presence, layer mechanics specification, wire protocol docs, and multi-release TOC files. | M1 | ORIGINAL_REQUEST §R1 |
| **F03** | Creature GUID Parser & Validator | Hyphen-delimited GUID parsing extracting ServerID (token 3) and ZoneID (token 5); filters player and pet entities (`UnitPlayerControlled`). | M2 | Survey, PROJECT.md §2 |
| **F04** | Multi-Unit Scanner & 2-GUID Consensus | Scans targets, mouseovers, nameplates, and vignettes with a 2-GUID consensus voting algorithm ($n \ge 2$) to eliminate phasing flapping. | M2 | Survey, PROJECT.md §2 |
| **F05** | Context Invalidation & Zone Management | Flushes vote cache on `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, `UNIT_PHASE`; disables detection inside dungeon/raid instances. | M2 | Survey, PROJECT.md §2 |
| **F06** | Layer Refresh Countdown Monitor | Tracks 180s (3:00) refresh warning window, periodic countdown callbacks, chat chevron minimization, and auto-expand at $\le 10$s. | M2 | ORIGINAL_REQUEST §R2 |
| **F07** | "Refresh Now" Action & Combat Deferral | Interactive refresh button, combat check blocking (`UnitAffectingCombat`), and deferral until `PLAYER_REGEN_ENABLED` + 2s safety buffer. | M2 | ORIGINAL_REQUEST §R2 |
| **F08** | Layer Hopping Cooldown Tracker | Post-refresh hop cooldown alert and monotonic throttle (300s to 900s) preventing hop spam abuse. | M2 | ORIGINAL_REQUEST §R2 |
| **F09** | Whisper Keyword Engine & Anti-Spam | Whole-word regex parsing (`%f[%w]layer%f[%W]`), inverted keywords (`not layer 1`), range parsing (`1-3`), and trade/LFG blacklist filter. | M3 | ORIGINAL_REQUEST §R3 |
| **F10** | Automated Party Invite Coordination | `C_PartyInfo.InviteUnit`, 300s player throttle cache, 180s pending invite expiration, group size caps ($\le 4$), and sound muting. | M3 | ORIGINAL_REQUEST §R3 |
| **F11** | Auto-Accept & Group Departure Lifecycle | Auto-accept hop invites, suppress `PARTY_INVITE` popup, verify layer shift, and auto-leave group after transfer or 40s timeout. | M3 | ORIGINAL_REQUEST §R3 |
| **F12** | AutoLayer & NetherAutoLayer Interop | Public `'layer'` channel, dynamic date-salted Adler32 channels, segment headers (`<AZ>`, `<OL>`, `<ZI>`, `<DI>`, `<AL2V...>`). | M3 | ORIGINAL_REQUEST §R3 |
| **F13** | Overlord Hidden Addon Channel Interop | Hidden addon channel `"OverlordLJ"` over WHISPER, wire requests `R:2:<req>:<layer>`, and decline wire responses `N:<req>:<reason>`. | M3 | Survey, PROJECT.md §5 |
| **F14** | NovaWorldBuffs Interop Hooks | Bi-directional layer synchronization with `_G.NWB_CurrentLayer`, `_G.NWB_CurrentLayerZoneID`, and `_G.NWB_LayerUpdated()`. | M3 | ORIGINAL_REQUEST §R3 |
| **F15** | Minimap Layer Indicator Badge | Bronze circular layer badge for minimap header displaying active layer number, instance hiding, tooltip data, and drag persistence. | M4 | ORIGINAL_REQUEST §R2 |
| **F16** | Movable Status HUD & Visual Alerts | Status frame displaying current layer, refresh countdown timer, urgent alert flashing at $\le 10$s, cooldown display, and refresh action button. | M4 | ORIGINAL_REQUEST §R2 |
| **F17** | Slash Command System & Options UI | `/ulo` and `/layer` slash commands, toggling auto-invite, status reports, direct layer hops, and options panel synchronization. | M4 | ORIGINAL_REQUEST §R2, R3, R4 |

---

## 3. Five-Tier Test Architecture & Coverage Thresholds

The test suite is structured across five verification tiers:

```
Tests/
├── TestHarness.lua          # Standalone WoW mock engine & test runner
├── ReferenceModel.lua       # Genuine functional reference model implementation
├── Tier1_FeatureTests.lua   # Tier 1: Feature Coverage (91 tests, F01-F17)
├── Tier2_BoundaryTests.lua  # Tier 2: Boundary & Corner Cases (85 tests, F01-F17)
├── Tier3_PairwiseTests.lua  # Tier 3: Cross-Feature Pairwise Interactions (17 tests)
├── Tier4_ScenarioTests.lua  # Tier 4: Real-World Application Workflows (19 tests)
└── Tier5_AdversarialHarden.lua # Tier 5: Adversarial cases (35 tests)
```

### Coverage Threshold Matrix

| Tier | Focus | Required Count | Implemented Count | Threshold Met |
|------|-------|----------------|-------------------|---------------|
| **Tier 1: Feature Coverage** | Feature cases and permanent regressions (F01–F17) | $\ge 85$ | **91** | 100% |
| **Tier 2: Boundary & Corner Cases** | 5 boundary, edge, and error condition tests per feature (F01–F17) | $\ge 85$ | **85** | 100% |
| **Tier 3: Cross-Feature Interactions** | Pairwise interactions between major subsystems (Detection, Monitor, Coordination, Interop, UI, Compat) | $\ge 17$ | **17** | 100% |
| **Tier 4: Real-World Scenarios** | Player workflows through modeled events | $\ge 9$ | **19** | 100% |
| **Tier 5: Adversarial Hardening** | Failure and malformed-input cases | $\ge 35$ | **35** | 100% |
| **TOTAL** | **Consolidated Test Verification Suite** | **$\ge 231$** | **247** | **100%** |

---

## 4. Subsystem Components

### 4.1 Standalone Test Harness (`Tests/TestHarness.lua`)
- **Sandbox Environment Factory**: `TestHarness.NewEnvironment(flavor)` generates an isolated global table `env` where `env._G = env`.
- **Event Bus Engine**: Emulates WoW `CreateFrame`, `RegisterEvent`, `UnregisterEvent`, `SetScript`, `HookScript`, and `FireEvent`. Safely clones listener lists during dispatch to prevent corruption when handlers modify registrations.
- **Virtual Clock & Timer Wheel**: `GetTime()`, `time()`, `C_Timer.After`, and `C_Timer.NewTicker` integrated into a priority-queue time wheel advanced via `env.AdvanceTime(delta)`.
- **Mock WoW Namespaces**:
  - `C_PartyInfo`: Roster state, group invitation queue, departure handling, party cap enforcement.
  - `C_ChatInfo`: Addon message prefix registration (16-char limit), outbound message logging, chat lockdown state.
  - `C_Map`: Best map resolution, map hierarchy lookup.
  - `C_NamePlate` & `C_VignetteInfo`: Scene object enumeration.
  - Unit APIs: `UnitGUID`, `UnitName`, `UnitPlayerControlled`, `UnitAffectingCombat`, `UnitIsDeadOrGhost`.
  - UI Globals: `DEFAULT_CHAT_FRAME`, `SendChatMessage`, `JoinChannelByName`, `StaticPopupDialogs`.
- **Assertion Suite**:
  - `AssertEqual(actual, expected, [msg])`
  - `AssertTrue(cond, [msg])`
  - `AssertFalse(cond, [msg])`
  - `AssertNil(val, [msg])`
  - `AssertNotNil(val, [msg])`
  - `AssertMatch(str, pattern, [msg])`
  - `AssertTableEqual(actual, expected, [msg])`
  - `AssertThrows(func, [expectedPattern], [msg])`
- **Module Loader**: Loads the 18 production Lua files in TOC order. The historical reference-model fallback is not production verification; the standard gate requires the addon structure and exercises production-specific behavior.

### 4.2 Specification Reference Model (`Tests/ReferenceModel.lua`)
`ReferenceModel.lua` provides a genuine, fully functional implementation of the ULO specification:
- Real hyphen-delimited GUID parsing and validation (ServerID token 3, ZoneID token 5).
- Real 2-GUID voting algorithm ($n \ge 2$) with entity exclusion.
- Real 180s countdown monitor with combat deferral to `PLAYER_REGEN_ENABLED` + 2s buffer.
- Real 300s post-hop cooldown tracker using monotonic clock.
- Real whole-word regex keyword matcher, range parser, and blacklist filter.
- Real party invite manager with 300s player cache and 180s expiration.
- Real Adler32 checksum calculation and segment header formatting (`<AZ>`, `<OL>`, `<AL2V...>`).
- Real OverlordLJ wire protocol (`R:2:<req>:<layer>` and `N:<req>:<reason>`).
- Real NovaWorldBuffs synchronization hooks (`_G.NWB_CurrentLayer`, `_G.NWB_LayerUpdated`).
- Real Status HUD and Minimap Badge UI states and `/ulo`, `/layer` slash command dispatcher.

---

## 5. Execution Instructions

The test suite can be executed from PowerShell or Windows Command Prompt (CMD) from either the project root or the `Tests/` directory.

### 5.1 PowerShell Execution
```powershell
# Run the complete test suite (all 247 tests across all 5 tiers)
.\RunTests.ps1

# Run tests from the Tests directory
cd Tests
.\RunTests.ps1

# Filter by tier (1, 2, 3, 4, or 5)
.\RunTests.ps1 --tier=1
.\RunTests.ps1 -t 3

# Filter by feature (F01 through F17)
.\RunTests.ps1 --feature=F04
.\RunTests.ps1 -f F13

# Verbose output (displays individual passing assertions)
.\RunTests.ps1 -v
```

### 5.2 Windows Batch / CMD Execution
```cmd
:: Run the complete test suite
RunTests.bat

:: Filter by tier
RunTests.bat --tier=2

:: Filter by feature
RunTests.bat --feature=F09
```

### 5.3 Direct Lua CLI Execution
```cmd
"C:\Dev Projects\Addon Studio\Extensions\Tools\Lua\lua.exe" Tests\TestHarness.lua
```

---

## 6. Pass / Fail Semantics & Exit Code Protocol

1. **Test Verdict Criteria**:
   - A test passes if and only if all assertions evaluate successfully without raising an error.
   - If any assertion fails or an unexpected Lua runtime exception occurs, the test is recorded as `FAIL` with its file, line number, and stack trace captured.
2. **Consolidated Summary Output**:
   At the conclusion of execution, the test harness prints a formatted summary table:
   ```
   ========================================================================
    Universal Layer Operator (ULO) - Test Suite Execution Summary
   ========================================================================
    Tier 1 (Feature Coverage)        :  85 /  85 passed (100.0%)
    Tier 2 (Boundary & Corner Cases) :  85 /  85 passed (100.0%)
    Tier 3 (Cross-Feature Pairwise)  :  17 /  17 passed (100.0%)
    Tier 4 (Real-World Scenarios)    :   9 /   9 passed (100.0%)
   ------------------------------------------------------------------------
    TOTAL: 196 Tests | Passed: 196 | Failed: 0 | Skipped: 0
    VERDICT: ALL TESTS PASSED
   ========================================================================
   ```
3. **Exit Code Transmission**:
   - **Exit Code 0**: Returned when all tests pass with zero failures.
   - **Exit Code 1**: Returned if any test fails, terminating automated CI/CD pipelines immediately.

## User-report regression: Actions startup and window linking

November 16, 2026 owner report: Actions should start closed at every login or
reload, even if it was open before. During play it can remain open independently
of the main window. The owner also requested a Linked / Free control.
The exact installed addon version and client build were not supplied.

`reported-actions-startup-hidden` extends the existing F16 tests in
`Tests/Tier1_FeatureTests.lua`, already included in `npm test`. It executes
production frame creation, login/world events, and the real window buttons with
unset/true/false saved Actions visibility, enabled/disabled main-window settings,
and all five client flavors. Against the unchanged implementation it fails
because the Actions frame is initially visible. With the correction it also
checks startup visibility reset, independent screen anchoring, main/Actions
close behavior, and visibility across later zone entries.

`actions-linked-and-free-window-lifecycle` covers the new button, linked anchors,
drag locking, close-button and native main-frame hides, on-demand reopening,
restoring the saved free position, scale-aware drag persistence, and reloads
that retain link mode while keeping both windows closed when main is disabled.
Both named cases run in the standard gate, which contained 233 tests after this change.

Client acceptance remains required: open both windows and reload/relog with main
enabled and disabled; Actions must start closed. In Free mode, drag Actions and
close main; Actions must remain open, including after changing zones. In Linked
mode, move main and verify Actions follows and cannot be dragged separately;
close main with X and Escape and check Actions closes. Reopen main and explicitly
open Actions again, then switch back to Free and check its former position.
Verify the mode survives reload while Actions stays closed. Check header labels,
screen edges, and multiple UI scales/themes in the native client; the headless
harness does not reproduce rendered geometry or native SavedVariables writing.

## User-report regression: Hop Any, self invites, and request tracks

November 16 owner report: pressing Hop Any at 11:44:20 was followed one second
later by one normal invitation and eighteen "already in a group" invitation
notices. The owner also saw "you cannot invite yourself" and required exclusion
of the current layer and a checkbox Mode dropdown. Names in fixtures are
sanitized. The precise client/build, installed ULO version, current-layer value,
enabled integrations, and sender/event that caused the self-invite were not
supplied. The transcript establishes the symptoms, not the self-invite path.

Permanent cases extend existing standard-gate suites:

- `reported-hop-any-excludes-current-layer` (Tier 4): the actual Hop Any button
  sends an exclusion for its known origin in both mixed and ULO-native modes,
  rejects an explicit same-layer target and repeated active clicks, and cannot
  treat an origin-layer callback as successful transfer. Unknown origins do not
  send an unrestricted Hop Any request.
- `reported-hop-group-invite-burst` (Tier 4): the registered system-chat filter
  receives the supplied English invitation text and a modeled first native
  invite. It suppresses only invitation notices within the player's own bounded
  hop window; loot changes, self-invite errors, and later social invites remain
  visible. A neighboring late invite event cannot cause a second acceptance.
- `reported-hop-self-invite-guard` (Tier 4): production invitation APIs and chat,
  guild, AutoLayer, Overlord, ULO, TresLayerSwap, and LayerHopper handlers reject
  self-name aliases across all five modeled clients. Automated AutoLayer status
  replies cannot invite helpers back. Another realm's namesake and genuine
  friend requests remain eligible. This verifies missing guards, not which
  event caused the owner's original error.
- `hop-directed-helpers-before-public-fallback` (Tier 4): known different-layer
  ULO helpers get a 12-second directed window before trying native Overlord or
  one public fallback; acceptance cancels remaining traffic. Once native
  Overlord starts, its controller owns the operation rather than a ULO retry.
- `mode-dropdown-independent-request-tracks` (Tier 1/F17): actual menu checkbox
  clicks preserve unrelated choices, reflect reloads and legacy profiles, and
  gate incoming and outgoing request paths. Existing Settings controls share the
  same values. The generic harness now models native CheckButton click state.

All five cases failed against their previous owning behavior and pass with the
corrections. The existing social-party invariant now verifies immediate request
rejection without a timeout or party departure. No separate suite or release
tag is added; the complete gate contains 238 tests.

Client acceptance: scan nearby NPCs and note the current layer, then press Hop
Any once. Check that the request excludes that layer, only one invite is accepted,
and an unchanged layer does not report success. Test native helper discovery,
directed timeouts/public fallback, real group notices, genuine social invites
afterward, and each self-name form on the affected client. Open Mode, mix enabled
and disabled tracks, reload, and check the chosen integrations and checkmarks
persist while Actions starts closed. Verify popup placement, Escape, labels,
and native checkboxes at screen edges and UI scales. Remote addons can still
answer a public request simultaneously; the addon controls its own dispatch and
chat filtering, not the server's incoming invitation delivery. Native timing,
localized message globals, real layer detection/transfer, and SavedVariables
writing remain in-client checks.

## November 16 development: zone intelligence and native Overlord

The owner's side-chat review identified an actual source defect: ULO forced
Overlord's volunteer setting and replaced its OnRequest handler. The permanent
`reported-overlord-preserves-native-helper-controls` case extends Tier 4/F13.
Running that same case with the unchanged owning adapter loaded over the test
environment failed (`expected 0, got 3` native preference writes); the corrected
adapter passes. Pre-fix adapter SHA-256:
`0467A34DFA82172ED4DB1D4C755AC01D36EF9BC4375C8DF26310FE06A0507632`.
The regression also covers handler/shard preservation, avoiding PvP directory
contacts, duplicate native helper handling and UI fallback settings paths.
It does not reproduce a real server-side failed transfer.

Additional permanent cases in the existing standard gate:

- `scrollable-layer-request-list` (Tier 1/F16): real wheel/buttons reach layers
  beyond eight, recycled rows request their displayed target, current/busy rows
  are disabled, limits clamp, and fresh helper counts expire while browsing.
- `zone-resolver-client-scope-and-freshness` (Tier 1/F12): subzone parents,
  unreadable/secret maps and cycles; Forever/TBC policy only; 90-second expiry.
- `autolayer-server-calendar-and-single-channel-fallback` (Tier 1/F12): static
  plus three daily names against independent Python zlib Adler32 fixtures,
  differing server/local dates, native calendar rollover, failed-channel
  fallback, no duplicate sends, no reserved or invented /1 destination.
  It failed against the pre-correction date/channel implementation; the older
  static-channel test also exposed its erroneous static-channel departure once
  the harness modeled the real GetChannelName API. Both pass after correction.
- `ulo-zone-aware-wire-and-legacy-compatibility` (Tier 4): actual registered S2
  and R2 handlers, same/wrong zones, stale peers, TBC AL2, unchanged Forever
  legacy headers, old R clients and NWB data without assumed helper consent.
- `zone-aware-owned-group-verification` (Tier 4): fresh layer observation plus
  actual modeled leader zone, wrong/unreadable leaders and owned departure;
  foreign social groups are preserved.
- `overlord-native-hop-lifecycle-owner` (Tier 4): Join receives the native raw
  shard ID rather than a ULO ordinal, one invitation acceptance/departure owner,
  no four-second retry, and native completion without ULO cancelling it.
- `overlord-legacy-zone-fallback-and-rejection` (Tier 4): verified volunteer
  priority, legacy unknown-zone fallback, same/wrong/unreadable leader checks
  on both clients, and native cancellation when requester scope changes.

Harness changes model disabled buttons, wheel/font APIs, a server calendar and
real named chat slots, and a two-person leader roster on accepting an invite.
The old combat-gate fixture now retains its map ID when replacing player data;
that avoids an unrelated unknown-zone rejection masking the intended gate.

Native source inspected: Overlord 2.5.3, commit
`2b5c711191c35b1f127f97e616b247e62eb20a5a`, installed LayerJumper SHA-256
`81B836D425A5206A681793259F29B84D0482E67FB2BFD0D9A346879EA5323702`.
Tests model its Join/Cancel/event boundary; they do not execute the complete
vendor addon or prove the live transport. AutoLayer 1.9.15 was reviewed at
`123ec2d650490711643e6864d431e9dcb8f545c3`; see
[research, compatibility limits and remaining tasks](IMPLEMENTATION_TASKS.md).

Client acceptance remains open: on Forever and TBC, compare same-zone,
cross-zone and unreadable leaders; move between a town/subzone and its parent;
observe an actual layer change after scanning NPCs. Confirm native Overlord
help preferences stay as saved, native retries/acceptance/leave occur once,
and PvP recruitment and unrelated parties remain unaffected. Exercise layer
rows above eight, wheel/arrow limits and UI scales; verify Actions startup,
Linked/Free behavior and Mode selections after reload/relog. Check real chat
subscriptions/date rollover and localized notices. Honor any native Refresh
Now prompt; modeled group membership and displayed layer numbers alone are
not proof of a real transfer.

Validation/deployment: the complete `npm.cmd test` gate passed in the prepared
tree and again in `C:\Dev Projects\ULO` (246/246; syntax 18 files; six Dev TOCs).
`git diff --check` passed. The project local installer then verified all 28 addon
files in each of the seven local clients by SHA-256 and missing/extra-file
comparison. Previous ULO folders were backed up; Overlord's LayerJumper hash was
unchanged. See [deployment record](IMPLEMENTATION_TASKS.md#local-installation-result--november-16-2026).
No native game acceptance result, commit, release, or tag is implied.

## User report: secret channel sender comparison

November 16 owner report: three errors at AutoLayerProtocol.lua:346, attempting
to compare secret `sender` on CHAT_MSG_CHANNEL. Both `msg` and `sender` are
secret strings; channel metadata remains readable (`3. layer9b190880`, slot 3,
NEWCOMER). The client/build and precise chat contents were not supplied.
The stack identifies an empty-string comparison before any secrecy guard, not
a changed layer channel. Pre-fix AutoLayerProtocol SHA-256:
`A5D7951D7D92D0E5BD7C0613258B32AB8064D0B0C4DF11788445F1B676C9D0AD`.

`reported-secret-channel-message-and-sender` extends Tier 4/F12 in the standard
gate. It invokes the registered event with the reported argument shape and
real Lua strings marked secret. String-operation traps expose forbidden reads;
secret empty strings verify that secrecy is checked before an early equality
return. The case failed on the old handler at a forbidden string operation,
then passed after the correction. It checks message/sender combinations,
defensive unreadable-channel handling, guild/whisper/addon entry points, no
invite or log dispatch for rejected channel payloads, and readable requests
with unused secret arguments or absent secrecy APIs across five modeled clients.

Stock Lua 5.1 cannot emulate native secret-string equality or WoW taint. The
owner's stack is the native comparison evidence; the regression establishes
guard ordering and no subsequent string/dispatch access, not a native-client
reproduction. Shared SafeString/IsSecretValue nil checks now use `type` so they
do not compare an unexamined value. Each affected chat boundary sanitizes text
and sender before empty-string checks, patterns, case conversion and logging.

Blizzard's generated [CHAT_MSG_CHANNEL API declaration](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua)
marks the event SecretInChatMessagingLockdown, while channel metadata is
NeverSecret. Defensive metadata tests do not claim those fields were secret in
the supplied report. No attempt is made to reveal or declassify chat contents.

Client acceptance: reload the addon, receive normal and protected messages on
the affected daily channel, and check no further sender-comparison/string-access
errors appear. Protected messages must not produce invitations or copied action
text; readable layer requests should still work. Live taint behavior remains
unverified until that in-game check.

Validation: `npm.cmd test` passed all 247 cases, Lua syntax for 18 files and
structure checks for six Dev TOCs; `git diff --check` passed. The tested tree
was installed with the repository workflow into all seven local clients;
each destination matched all 28 addon files by SHA-256 with no missing or extra
files. Previous ULO folders are backed up under
`%TEMP%\ulo-secret-chat-2026-11-16\client-backups-20261116-225643`.
Overlord's vendor file remained unchanged. The installation did not reload or
operate the running game, so native secret/taint acceptance is still pending.
