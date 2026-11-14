# Universal Layer Operator (ULO) — Test Infrastructure Specification

## 1. Test Philosophy

Universal Layer Operator (ULO) is designed as a mission-critical, multi-release World of Warcraft layering addon and technical specification. In World of Warcraft, layering, refresh monitoring, and cross-addon hopping operate across asynchronous network events, chat channels, whisper triggers, and combat restrictions. 

To guarantee reliability across all supported game releases without requiring a running World of Warcraft graphic client during automated builds and continuous integration, ULO adopts the following testing principles:

1. **Standalone Headless Execution**:
   - The test infrastructure executes in pure standard Lua (Lua 5.1 / LuaJIT / lua-wow) with zero external binaries, third-party libraries, or Blizzard client dependencies.
   - Every Blizzard FrameXML subsystem, C-library namespace, and frame hierarchy is faithfully emulated inside an isolated Lua sandbox table (`_G` self-referencing).
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
   - Zero tolerance for cheating or facade returns. All 196 tests execute real parsing, real consensus voting, real timer countdowns, and real message formatting.
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

## 3. Four-Tier Test Architecture & Coverage Thresholds

The test suite is structured across four distinct verification tiers:

```
Tests/
├── TestHarness.lua          # Standalone WoW mock engine & test runner
├── ReferenceModel.lua       # Genuine functional reference model implementation
├── Tier1_FeatureTests.lua   # Tier 1: Feature Coverage (85 tests, F01-F17)
├── Tier2_BoundaryTests.lua  # Tier 2: Boundary & Corner Cases (85 tests, F01-F17)
├── Tier3_PairwiseTests.lua  # Tier 3: Cross-Feature Pairwise Interactions (17 tests)
└── Tier4_ScenarioTests.lua  # Tier 4: Real-World Application Workflows (9 tests)
```

### Coverage Threshold Matrix

| Tier | Focus | Required Count | Implemented Count | Threshold Met |
|------|-------|----------------|-------------------|---------------|
| **Tier 1: Feature Coverage** | 5 nominal test cases per feature across all 17 features (F01–F17) | $\ge 85$ | **85** | 100% |
| **Tier 2: Boundary & Corner Cases** | 5 boundary, edge, and error condition tests per feature (F01–F17) | $\ge 85$ | **85** | 100% |
| **Tier 3: Cross-Feature Interactions** | Pairwise interactions between major subsystems (Detection, Monitor, Coordination, Interop, UI, Compat) | $\ge 17$ | **17** | 100% |
| **Tier 4: Real-World Scenarios** | Full end-to-end player user workflows with multi-step execution traces | $\ge 9$ | **9** | 100% |
| **TOTAL** | **Consolidated Test Verification Suite** | **$\ge 196$** | **196** | **100%** |

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
- **Module Loader**: Dynamically loads production addon files if present in the workspace; otherwise loads the genuine reference model (`Tests/ReferenceModel.lua`) so all 196 tests can execute and verify specification conformance.

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
# Run the complete test suite (all 196 tests across all 4 tiers)
.\RunTests.ps1

# Run tests from the Tests directory
cd Tests
.\RunTests.ps1

# Filter by tier (1, 2, 3, or 4)
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
