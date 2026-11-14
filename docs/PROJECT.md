# Project: Universal Layer Operator (ULO)

## Architecture
Universal Layer Operator (ULO) is a multi-release World of Warcraft layering addon and technical specification providing layer/shard detection, refresh monitoring, layer swapping, and automated party invite coordination, with interoperability hooks into established layering addons (*AutoLayer*, *NetherAutoLayer*, *Overlord*, *NovaWorldBuffs*).

### Module Architecture
1. **Compatibility Layer (`Compatibility/Compat.lua`)**:
   - Environment and client flavor detection (`wowf`, `wow_anniversary`, `wow_classic_era`, `wow_classic`, `wow`).
   - TOC compatibility (`16001`, `20506`, `11509`, `50504`, `120105`).
   - Safe API wrappers with `pcall` guards, `issecretvalue()` checks, and chat messaging lockdown awareness (`InChatMessagingLockdown()`).
   - Unified party functions (`LeaveParty`, `InviteUnit`, `AcceptGroup`).
2. **Detection Subsystem (`Detection/`)**:
   - `GuidParser.lua`: Extracts ServerID (token 3) and ZoneID (token 5) from `Creature-0-<ServerID>-<InstanceID>-<ZoneID>-<NpcID>-<SpawnUID>`.
   - `LayerScanner.lua`: Coordinates unit target scans (`target`, `mouseover`, `focus`, `soft` units), nameplates (`C_NamePlate`), vignettes (`C_VignetteInfo`), and combat logs.
   - Enforces 2-GUID voting consensus (`VoteLayer`, $n \ge 2$) and filters player-controlled entities (`UnitPlayerControlled`).
   - Context invalidation on `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, `UNIT_PHASE`.
3. **Monitor Subsystem (`Monitor/`)**:
   - `RefreshMonitor.lua`: Tracks 180s (3:00) layer refresh warning window, "Refresh Now" action, combat deferral (`PLAYER_REGEN_ENABLED`), and chat chevron minimization.
   - `CooldownTracker.lua`: Tracks post-refresh hopping cooldown (300s to 900s) and throttles hop requests.
4. **Coordination Subsystem (`Coordination/`)**:
   - `KeywordMatcher.lua`: Parses whole-word whisper triggers (`layer`, `inv`, `layer 1`), inverted keywords (`not`, `except`), ranges (`1-3`), and spam blacklist.
   - `InviteManager.lua`: Dispatches party invites (`C_PartyInfo.InviteUnit`), manages 300s player throttle cache, 180s invite timeouts, and sound muting.
   - `GroupManager.lua`: Manages group size caps ($\le 4$ party, $\le 39$ raid), auto-accepts hop invites, suppresses `StaticPopupDialogs["PARTY_INVITE"]`, and departs group after transfer confirmation.
5. **Addon Interoperability Subsystem (`Interop/`)**:
   - `AutoLayerProtocol.lua`: Dynamic date-salted Adler32 channels (`layer{hash}`), static `"layer"` channel, segment headers (`<AZ>`, `<OL>`, `<ZI>`, `<DI>`), Protocol v2 headers (`<AL2V...>`).
   - `OverlordProtocol.lua`: Hidden addon channel `"OverlordLJ"` over WHISPER (`R:2:<requestId>:<layer>` and `N:<requestId>:<reason>`).
   - `NWBInterop.lua`: Hooks `_G.NWB_CurrentLayer`, `_G.NWB_CurrentLayerZoneID`, and `_G.NWB_LayerUpdated()`.
6. **User Interface (`UI/`)**:
   - `MinimapBadge.lua`: Bronze/gold circular layer indicator badge for the minimap header.
   - `StatusHUD.lua`: Movable status frame displaying current layer, refresh countdown timer, cooldown alerts, and quick actions.
   - `SettingsPanel.lua` & `SlashCommands.lua`: Interface options and `/ulo`, `/layer` slash commands.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F01 | Multi-Release Compatibility Layer | Environment detection, API shims (C_PartyInfo, LeaveParty), secret value/lockdown guards | M1 | Survey (Explorer 1 & 2) |
| F02 | Technical Specification Document | Comprehensive technical specification detailing layer mechanics, interoperability, and architecture | M1 | ORIGINAL_REQUEST §R1 |
| F03 | Creature GUID Parser & Validator | Extract ServerID (token 3) and ZoneID (token 5) with player-controlled entity filter | M2 | Survey (Explorer 1 & Spec Miner 3) |
| F04 | Multi-Unit Scanner & 2-GUID Consensus | Scans targets, nameplates, vignettes, and combat logs with 2-GUID voting anti-flapping algorithm | M2 | Survey (Explorer 1 & Spec Miner 3) |
| F05 | Context Invalidation & Zone Management | Flushes cache on zone changes, map crossings, and phase changes; instance suppression | M2 | Survey (Explorer 1 & Spec Miner 3) |
| F06 | Layer Refresh Countdown Monitor | 180s countdown tracking, center banner/popup, minimized chevron, auto-expand at <=10s | M2 | ORIGINAL_REQUEST §R2, Spec Miner 3 |
| F07 | "Refresh Now" Action & Combat Deferral | Interactive refresh button, combat check blocking, and deferral until PLAYER_REGEN_ENABLED | M2 | Spec Miner 3, Survey |
| F08 | Layer Hopping Cooldown Tracker | Post-refresh cooldown alert and throttle (300s) preventing continuous hopping abuse | M2 | ORIGINAL_REQUEST §R2, Spec Miner 3 |
| F09 | Whisper Keyword Engine & Anti-Spam | Configurable triggers ('layer', 'inv', 'layer 1'), whole-word regex, ranges, blacklist filter | M3 | ORIGINAL_REQUEST §R3, Explorer 2 |
| F10 | Automated Party Invite Coordination | C_PartyInfo.InviteUnit, 300s invite cache, 180s timeout, party cap (<=4), sound muting | M3 | ORIGINAL_REQUEST §R3, Explorer 1 & 2 |
| F11 | Auto-Accept & Group Departure Lifecycle | Auto-accept hop invites, suppress PARTY_INVITE popup, leave party after transfer | M3 | ORIGINAL_REQUEST §R3, Explorer 1 & 2 |
| F12 | AutoLayer & NetherAutoLayer Interop | Public 'layer' channel, Adler32 salted channels, segment headers (<AZ>, <OL>, <ZI>, <DI>, <AL2V>) | M3 | ORIGINAL_REQUEST §R3, Explorer 2 |
| F13 | Overlord Hidden Addon Channel Interop | OverlordLJ WHISPER prefix, wire requests R:2:<req>:<layer> and decline responses N:<req>:<reason> | M3 | Survey (Explorer 1 & Spec Miner 3) |
| F14 | NovaWorldBuffs Interop Hooks | Bi-directional sync with NWB_CurrentLayer, NWB_CurrentLayerZoneID, and NWB_LayerUpdated | M3 | ORIGINAL_REQUEST §R3, Explorer 1 & 2 |
| F15 | Minimap Layer Indicator Badge | Bronze circular badge displaying active layer number, matching WoW Forever visual style | M4 | ORIGINAL_REQUEST §R2, Spec Miner 3 |
| F16 | Movable Status HUD & Visual Alerts | Layer status display, active refresh timer, cooldown alerts, quick hop buttons | M4 | ORIGINAL_REQUEST §R2 |
| F17 | Slash Command System & Options UI | /ulo and /layer slash commands, toggle auto-invites, trigger keywords, protocol config | M4 | ORIGINAL_REQUEST §R2, R3, R4 |
| F18 | E2E Test Verification Suite | 100% pass of Tiers 1-4 requirement-driven E2E tests across targeted client releases | M5 | Project Pattern Dual Track |
| F19 | Adversarial Coverage Hardening | White-box stress testing, edge-case coverage audit, and bug remediation (Tier 5) | M5 | Project Pattern Dual Track |

---

## Milestones
| # | Name | Scope | Dependencies | Status | Key Outputs |
|---|------|-------|-------------|--------|-------------|
| M1 | Technical Specification & Compatibility Foundation | F01, F02 (TECHNICAL_SPECIFICATION.md, TOC files, Core/Constants.lua, Core/Init.lua, Compatibility/Compat.lua) | none | DONE | TECHNICAL_SPECIFICATION.md, 6 TOC files, Core/Constants.lua, Core/Init.lua, Compatibility/Compat.lua (Gate 2 Passed 100%) |
| M2 | Core Layer Detection & Refresh Monitoring | F03, F04, F05, F06, F07, F08 (Detection/GuidParser.lua, Detection/LayerScanner.lua, Monitor/RefreshMonitor.lua, Monitor/CooldownTracker.lua) | M1 | DONE | Detection/GuidParser.lua, Detection/LayerScanner.lua, Monitor/RefreshMonitor.lua, Monitor/CooldownTracker.lua, 6 TOC files updated (Gate 2 Passed 100%, 350+ tests pass) |
| M3 | Layer Swapping, Auto-Invites & Addon Interoperability | F09, F10, F11, F12, F13, F14 (Coordination/InviteManager.lua, Coordination/KeywordMatcher.lua, Coordination/GroupManager.lua, Interop/AutoLayerProtocol.lua, Interop/OverlordProtocol.lua, Interop/NWBInterop.lua) | M1, M2 | DONE | Coordination/KeywordMatcher.lua, Coordination/InviteManager.lua, Coordination/GroupManager.lua, Interop/AutoLayerProtocol.lua, Interop/OverlordProtocol.lua, Interop/NWBInterop.lua, 6 TOC files updated (Gate 2 Passed 100%, 270 tests pass) |
| M4 | User Interface, Status HUD & Slash Commands | F15, F16, F17 (UI/MinimapBadge.lua, UI/StatusHUD.lua, UI/SettingsPanel.lua, Core/SlashCommands.lua) | M2, M3 | DONE | UI/MinimapBadge.lua, UI/StatusHUD.lua, UI/SettingsPanel.lua, Core/SlashCommands.lua, 6 TOC files updated, TestHarness.lua wired (Gate 2 Passed 100%, 378+ tests pass, Auditor CLEAN) |
| M5 | Final Milestone: 100% E2E Pass & Adversarial Hardening | F18, F19 (Pass 100% of E2E Test Suite, Tier 5 Adversarial Coverage Hardening) | M1, M2, M3, M4, TEST_READY.md | DONE | Phase 1 PASSED (196/196); Phase 2 PASSED (35 Tier 5 tests); 231/231 tests pass (100.0%, Exit Code 0); 2x Reviewers APPROVE; Forensic Auditor CLEAN |

---

## Interface Contracts

### Compatibility ↔ All Subsystems
- `ULO.Compat.GetClientFlavor()` -> returns string (`"wowf"`, `"wow_anniversary"`, `"wow_classic_era"`, `"wow_classic"`, `"wow"`)
- `ULO.Compat.GetTocVersion()` -> returns number (`16001`, `20506`, `11509`, `50504`, `120105`)
- `ULO.Compat.IsForever()` -> returns boolean
- `ULO.Compat.IsRetail()` -> returns boolean
- `ULO.Compat.LeaveParty()` -> safely invokes `C_PartyInfo.LeaveParty` or global `LeaveParty` with `pcall`
- `ULO.Compat.InviteUnit(name)` -> safely invokes `C_PartyInfo.InviteUnit` or `InviteUnit` with realm normalization
- `ULO.Compat.InChatLockdown()` -> boolean check for messaging restrictions
- `ULO.Compat.SafeString(str)` -> validates string against `issecretvalue()` and returns safe string or nil

### Detection ↔ Monitor & UI & Interop
- `ULO.Detection.GetCurrentLayer()` -> returns `layerNumber` (number or nil)
- `ULO.Detection.GetCurrentServerId()` -> returns `serverId` (number or nil)
- `ULO.Detection.GetCurrentZoneId()` -> returns `zoneId` (number or nil)
- `ULO.Detection.GetLayerConfidence()` -> returns string (`"CONFIRMED"`, `"ESTIMATED"`, `"UNDETERMINED"`, `"INSTANCED"`)
- Callback: `ULO.RegisterCallback("OnLayerChanged", function(layerNumber, serverId, zoneId, oldLayer) ... end)`

### Monitor ↔ UI & Coordination
- `ULO.Monitor.IsRefreshPending()` -> returns boolean
- `ULO.Monitor.GetRefreshRemaining()` -> returns number (seconds remaining in 180s window)
- `ULO.Monitor.IsCombatDeferred()` -> returns boolean
- `ULO.Monitor.RequestRefreshNow()` -> attempts immediate phase reload, returns success (bool), reason (string)
- `ULO.Monitor.GetCooldownRemaining()` -> returns number (seconds remaining on post-transfer cooldown)
- Callback: `ULO.RegisterCallback("OnRefreshWarning", function(remainingSeconds, isDeferred) ... end)`
- Callback: `ULO.RegisterCallback("OnRefreshTriggered", function() ... end)`
- Callback: `ULO.RegisterCallback("OnCooldownStarted", function(duration) ... end)`

### Coordination ↔ Interop & UI
- `ULO.Coordination.ToggleAutoInvite(enable)` -> sets auto-invite state
- `ULO.Coordination.IsAutoInviteEnabled()` -> returns boolean
- `ULO.Coordination.HandleWhisper(sender, message)` -> processes inbound whisper for keywords and schedules invite
- `ULO.Coordination.RequestLayerHop(targetLayer, preferredProtocol)` -> initiates hop request across available networks

### Interop ↔ Coordination & Detection
- `ULO.Interop.AutoLayer.BroadcastHopRequest(segment, layers)` -> sends hop request to layer chat channels
- `ULO.Interop.Overlord.SendHopRequest(targetPlayer, originLayer)` -> sends `R:2:<req>:<layer>` over OverlordLJ WHISPER
- `ULO.Interop.NWB.SyncWithNWB()` -> synchronizes state with `_G.NWB_CurrentLayer`

---

## Code Layout
```
C:\Dev Projects\ULO\
├── ULO.toc                           # Universal TOC (comma-delimited interfaces)
├── ULO_Camelot.toc                   # WoW Forever TOC (16001)
├── ULO_Vanilla.toc                   # WoW Classic Era / SoD / Hardcore TOC (11509)
├── ULO_TBC.toc                       # WoW Classic Anniversary TBC TOC (20506)
├── ULO_Mists.toc                     # WoW Classic Progression TOC (50504)
├── ULO_Mainline.toc                  # WoW Retail TOC (120105)
├── TECHNICAL_SPECIFICATION.md        # Comprehensive technical specification document
├── TEST_INFRA.md                     # E2E test infrastructure specification
├── TEST_READY.md                     # E2E test suite readiness attestation (196 tests)
├── Core/
│   ├── Init.lua                      # Addon initialization, namespace setup, lifecycle
│   ├── Constants.lua                 # Opcodes, events, default keywords, timer constants
│   └── SlashCommands.lua             # /ulo and /layer slash command handlers
├── Compatibility/
│   └── Compat.lua                    # Multi-release environment detection, API shims, pcall guards
├── Detection/
│   ├── GuidParser.lua                # Hyphen-delimited GUID parsing (ServerID, ZoneID, entity filter)
│   └── LayerScanner.lua              # Multi-unit scan, nameplates, vignettes, 2-GUID voting consensus
├── Monitor/
│   ├── RefreshMonitor.lua            # 180s countdown warning, "Refresh Now", combat deferral
│   └── CooldownTracker.lua           # Post-refresh hop cooldown tracking and throttle alerts
├── Coordination/
│   ├── KeywordMatcher.lua            # Whole-word regex parsing, ranges, blacklist filters
│   ├── InviteManager.lua             # C_PartyInfo.InviteUnit, 300s cache, 180s expiration, sound muting
│   └── GroupManager.lua              # Group size caps, auto-accept, popup suppression, auto-leave
├── Interop/
│   ├── AutoLayerProtocol.lua         # 'layer' channel, Adler32 salted hashes, segment headers (<AZ>)
│   ├── OverlordProtocol.lua          # OverlordLJ WHISPER prefix, R:2 and N wire protocol
│   └── NWBInterop.lua                # NovaWorldBuffs global state hooks and synchronization
├── UI/
│   ├── MinimapBadge.lua              # Bronze circular layer badge for minimap
│   ├── StatusHUD.lua                 # Movable status frame, countdown display, cooldown alerts
│   └── SettingsPanel.lua             # Blizzard Settings / Interface Options configuration panel
└── Tests/
    ├── TestHarness.lua               # Standalone WoW Lua mock environment & test runner
    ├── Tier1_FeatureTests.lua        # >=5 tests per inventoried feature
    ├── Tier2_BoundaryTests.lua       # Boundary, edge case, and error condition tests
    ├── Tier3_PairwiseTests.lua       # Cross-feature combination tests
    ├── Tier4_ScenarioTests.lua       # End-to-end real-world workflow scenarios
    └── RunTests.bat / RunTests.ps1   # Executable test runner script
```
