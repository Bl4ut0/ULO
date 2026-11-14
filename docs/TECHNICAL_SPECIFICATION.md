# Universal Layer Operator (ULO) — Technical Specification

**Document Version**: 1.0.0  
**Status**: Authoritative Architectural Reference  
**Target Client Releases**:
- WoW Forever / Camelot (`wowf`, TOC `16001`, Build `1.60.1.70938`)
- WoW Classic Era / Season of Discovery / Hardcore (`wow_classic_era`, TOC `11509`, Build `1.15.9.70576`)
- WoW Classic Anniversary / Burning Crusade (`wow_anniversary`, TOC `20506`, Build `2.5.6.70577`)
- WoW Classic Progression / Mists of Pandaria (`wow_classic`, TOC `50504`, Build `5.5.4.70631`)
- WoW Retail / Mainline (`wow`, TOC `120105`, Build `12.1.5.70783`)

---

## 1. System Overview & Vision

### 1.1 Mission & System Objective
Universal Layer Operator (ULO) is a multi-release World of Warcraft addon and runtime engine designed to provide:
1. **Autonomous Layer Detection**: Instantaneous, verified identification of the active layer shard through multi-unit entity scanning and 2-GUID consensus voting.
2. **Layer Refresh Monitoring**: Real-time lifecycle tracking of WoW Forever's native 180-second world refresh warning window, supporting manual "Refresh Now" triggers, combat deferrals (`PLAYER_REGEN_ENABLED`), and chat chevron minimization.
3. **Cross-Addon Layer Swapping Interoperability**: Seamless bi-directional bridging across established layering protocols, including Overlord's hidden whisper wire protocol (`OverlordLJ`), AutoLayer/NetherAutoLayer's public and Adler32 date-salted channels (`<AZ>`, `<OL>`, `<ZI>`, `<DI>`, `<AL2V...>`), and NovaWorldBuffs global state (`_G.NWB_CurrentLayer`).
4. **Universal Client Compatibility**: Zero-dependency runtime execution spanning five major client branches from Vanilla Era to Retail Midnight, guarded by robust security shims (`issecretvalue`, `InChatMessagingLockdown`).

### 1.2 Core Architectural Tenets
- **Phasing Safety First**: Phase transitions mid-combat, on flight paths, or while dead can cause fatal player deaths or desynchronization. ULO treats phasing as an asynchronous transaction with strict pre-conditions, combat deferrals, and post-transfer cooldowns.
- **Broadband Interoperability**: Rather than creating a fragmented, isolated user base, ULO natively speaks the wire protocols of existing addons (*Overlord*, *AutoLayer*, *NetherAutoLayer*, *NovaWorldBuffs*), allowing users to request and fulfill layer hops across all networks simultaneously.
- **Bulletproof Consensus Voting**: Dynamic open-world boundaries, wandering border patrols, and player-controlled pets introduce noisy or misleading GUIDs. ULO guarantees layer accuracy through a 2-GUID voting algorithm ($n \ge 2$) with strict entity filtering.
- **Defensive API Architecture**: The Blizzard Lua environment across releases features divergent namespaces and strict engine security sandboxes. ULO encapsulates all party, chat, and string operations within protected shims and validation barriers.

---

## 2. WoW Forever Layer Refresh Architecture

### 2.1 The Native Layer Refresh Mechanism
In WoW Forever (Camelot, build `1.60.1.70938`), Blizzard introduced an automated world refresh system to manage server load, rebalance dynamic population shards, and consolidate collapsing layers. Unlike legacy Classic clients where joining a group across mismatched layers triggers an immediate, unannounced phase shift, WoW Forever decouples group joining from phasing and institutes a warning window.

### 2.2 180-Second Warning Window Lifecycle
When a player joins a group on a different layer, or when the server schedules a layer rebalance:
1. **Initiation**: The server issues a world refresh alert.
2. **Warning Window**: An internal countdown timer of exactly **180.0 seconds (3:00)** begins.
3. **User Presentation**:
   - A high-visibility center banner and modal dialog appear:
     > *"In 3:00, we will refresh the world around you; get somewhere safe"*
   - The dialog contains an interactive action button: **[Refresh Now]**.
4. **Minimization Chevron**:
   - If the player dismisses the modal dialog to clear their screen, the notification collapses into a compact circular chevron icon docked adjacent to the primary chat frame.
   - The chevron displays a subtle countdown indicator.
   - Clicking the chevron immediately restores the full modal dialog.
   - **Auto-Expansion**: When the remaining time reaches $\le 10$ seconds, the minimized chevron automatically re-expands into the center banner to ensure the player is alerted before the world refreshes.

### 2.3 "Refresh Now" Interactive Action
The player may choose to trigger the world refresh immediately rather than waiting for the 180s timer to elapse:
- **Out of Combat**: Invoking "Refresh Now" initiates the world reload and phase transfer immediately.
- **In Combat**: If `UnitAffectingCombat("player") == true`, the action is blocked. The UI presents an error notification:
  > *"Cannot refresh the world while in combat"*
  The 180s countdown continues ticking without interruption.

### 2.4 Combat Deferral Protocol (`PLAYER_REGEN_ENABLED`)
To eliminate the risk of players phasing into hostile mobs while actively engaged in combat:
1. If the 180-second countdown reaches `0:00` while the player is in combat (`UnitAffectingCombat("player") == true` or `InCombatLockdown() == true`), the transfer does **NOT** execute.
2. The addon enters the `IN_COMBAT_LOCKED` state.
3. The transfer is deferred until combat drops (`PLAYER_REGEN_ENABLED` event fires).
4. Upon receiving `PLAYER_REGEN_ENABLED`, ULO enforces a **2.0-second post-combat grace period** (`COMBAT_DEFERRAL_GRACE`) to ensure combat status has cleanly cleared before triggering the phase reload.

### 2.5 Native Minimap Bronze Layer Badge
WoW Forever features a native circular medallion badge docked directly beneath the minimap clock:
- **Visual Styling**: Embossed bronze/gold medallion frame displaying the active layer number (`1`, `2`, `3`, `4`, `5`).
- **Context Suppression**: The badge is automatically suppressed and hidden when the player enters an instanced dungeon, raid, battleground, or arena (`IsInInstance() == true`), or when the player is in an unlayered micro-zone.

### 2.6 Post-Refresh Layer Hopping Cooldown
Following any successful layer transfer (manual refresh or timer expiration), the server and ULO enforce an internal hopping cooldown:
- **Duration**: Configurable from 300 to 900 seconds (default: **300.0 seconds / 5 minutes**).
- **Behavior**: Subsequent layer hop requests are throttled and queued, preventing players from exploiting rapid layer hops to farm rare spawns or gather nodes.
- **UI Feedback**: The Status HUD and minimap badge display a cooldown indicator with remaining seconds.

---

## 3. Existing Addon Wire Protocols & Interoperability

ULO implements native protocol adapters for all major layering addons in the World of Warcraft ecosystem.

### 3.1 Overlord Hidden Wire Protocol (`OverlordLJ`)
*Overlord* (developed by Troma for WoW Forever) utilizes a binary-style opcode protocol over hidden addon whisper messages.

#### Transport & Addressing
- **Addon Message Prefix**: `"OverlordLJ"` (registered via `C_ChatInfo.RegisterAddonMessagePrefix`).
- **Transport Type**: `"WHISPER"` dispatched via `C_ChatInfo.SendAddonMessage`.

#### Wire Formats
1. **Layer Hop Request (`R`)**:
   ```
   R:2:<requestId>:<originLayer>
   ```
   - `R`: Request opcode.
   - `2`: Protocol version integer (`OVERLORD_PROTOCOL_VERSION`).
   - `<requestId>`: Alphanumeric session token (1 to 12 chars, e.g. `K9X2A7L1`).
   - `<originLayer>`: Current layer integer of requester, or `"-"` if undetermined.
2. **Layer Hop Decline / Negative Response (`N`)**:
   ```
   N:<requestId>:<reason>
   ```
   - `N`: Decline opcode.
   - `<requestId>`: Matching session token.
   - `<reason>`: Single-token failure identifier:
     - `off`: Auto-invites disabled.
     - `instance`: Host is inside a dungeon or raid instance.
     - `combat`: Host is actively engaged in combat.
     - `queue`: Host has a full invite queue.
     - `full`: Host's party/raid is full ($\ge 4$ members in party, $\ge 39$ in raid).
     - `busy`: Host is in the middle of a hop transaction.
     - `same`: Requester is already on the identical layer.
     - `silent`: Host configured for silent rejection.
     - `lost`: Requester disconnected or failed verification.

#### Timing & Flood Protection
- `HELPER_PER_SENDER_GAP`: 5.0 seconds (minimum interval between requests from same player).
- `HELPER_SAME_REQUESTER_GAP`: 30.0 seconds (lockout after successful request).
- `HELPER_INVITE_GAP`: 15.0 seconds (minimum delay between sending party invites).
- `HELPER_INVITES_PER_HOUR`: 20 invites maximum.
- `INVITE_WAIT`: 12.0 seconds (wait time for invite to register).
- `JOIN_WAIT`: 10.0 seconds (wait time for guest to accept group).
- `VERIFY_TIMEOUT`: 40.0 seconds (timeout to confirm layer switch).
- `GUEST_KICK_AFTER`: 120.0 seconds (safety kick if guest fails to leave).

#### Auto-Accept & Popup Suppression
When a hop invite arrives:
```lua
if AcceptGroup then pcall(AcceptGroup) end
local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
if dialog then dialog.inviteAccepted = 1 end
if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
```
*Note*: Setting `dialog.inviteAccepted = 1` is critical; without it, `StaticPopup_Hide` triggers Blizzard's `OnCancel` handler which invokes `DeclineGroup()`.

---

### 3.2 AutoLayer & NetherAutoLayer Protocol
*AutoLayer* (by iraizo) and *NetherAutoLayer* use public and hash-salted chat channels combined with structured text message headers.

#### Communication Channels
1. **Static Primary Channel**: `"layer"` (joined via `JoinChannelByName("layer")`).
2. **Dynamic Salted Channels**: `layer{hash}` where:
   $$\text{hash} = \text{Adler32}(\text{realmName} .. \text{"-"} .. \text{dateStr})$$
   Evaluated across three standard date patterns to account for timezone boundaries:
   - `dd-mm-yyyy`
   - `yyyy-mm-dd`
   - `mm-dd-yyyy`
3. **Channel Placement Safety**:
   - Channels 1 through 5 are reserved for Blizzard defaults (`General`, `Trade`, `LocalDefense`, etc.).
   - Layer channels are hidden from chat frames 1 through 10 to prevent message spam from polluting the user's chat window.

#### Segmented Wire Headers
AutoLayer segments messages by continent and geographic zone:
- `<AZ>`: Azeroth / Eastern Kingdoms & Kalimdor (`uiMapID 947`).
- `<OL>`: Outland (`uiMapID 1945` and subzones `1941, 1942, 1943, 1947, 1950, 1954, 1957`).
- `<ZI>`: Zephras Isle (WoW Forever starter island, `uiMapIDs 2521, 2665`).
- `<DI>`: Darkspear Islands (WoW Forever starter island, `uiMapID 2524`).

#### Message Formats
1. **Classic Segmented Request**:
   ```
   <{segment}> inv layer {target_layers}
   ```
   Example: `<AZ> inv layer 1,2` or `<ZI> inv layer 2`
2. **Protocol v2 Header**:
   ```
   <AL{protocolVersion}V{major}_{minor}_{patch}Z{scopeID}>{payload}
   ```
   Example: `<AL2V1_9_15Z1945> inv layer 1,3`
   Parsing Regex: `^<AL(%d+)V(%d+)_(%d+)_(%d+)Z(%d+)>(.*)$`

#### Whisper Triggers & Keyword Rules
- **Triggers**: Whole-word `%f[%w]layer%f[%W]`, `inv`, `invite`, `layer 1`, `layer 2`.
- **Inverted Keywords** (negative match): `not`, `off`, `except`, `but`, `out`, `other than`, `besides`, `apart from`.
- **Anti-Spam Blacklist**: `wts`, `wtb`, `lfm`, `lfg`, `ashen`, `auto inv`, `autoinv`, `pst for`, `guild`, `raid`, `enchant`, `player`, `what layer`, `which layer`, `worldbuffs`.
- **Throttles**: 300s player cache (`playersInvitedRecently`), 180s pending invite expiration (`pendingPlayerInvites`).
- **Group Caps**: Maximum 4 party members (ensuring space for 1 invitee); maximum 39 raid members.

---

### 3.3 NovaWorldBuffs (NWB) Integration
*NovaWorldBuffs* (by hippuli) maintains layer maps across realms. ULO interoperates directly with NWB's runtime globals:
1. **Global State Variables**:
   - `_G.NWB_CurrentLayer`: Current layer integer detected by NWB.
   - `_G.NWB_CurrentLayerZoneID`: Zone instance ID mapped by NWB.
2. **Callback Hook**:
   - `_G.NWB_LayerUpdated()`: Global hook invoked when NWB resolves a layer transition. ULO listens to this callback and dispatches `OnLayerChanged` to synchronize internal state.
3. **Database Integration**:
   - ULO reads continent layer mappings from `_G.NWBdatabase.global[realm][faction].layers`.
4. **WoW Forever Minimap Suppression**:
   - In `LayersUI.lua:880`, NWB suppresses its own minimap frame when running on WoW Forever (`if (isForever) then MinimapLayerFrame:Hide(); return; end`) because of the native bronze badge. ULO respects this design and coordinates with NWB without UI duplication.

---

## 4. Layer Detection Subsystem & GUID Specification

### 4.1 Creature GUID Schema
Blizzard entity GUIDs across modern and Classic engines follow a strict hyphen-delimited format:

$$\text{Creature-0-<ServerID>-<InstanceID>-<ZoneID>-<NpcID>-<SpawnUID>}$$

| Token Position | Field Name | Description | Example Value |
|---|---|---|---|
| **Token 1** | `unitType` | Entity classification (`Creature`, `Vehicle`, `GameObject`, `Vignette`) | `Creature` |
| **Token 2** | `zero` | Engine zero padding | `0` |
| **Token 3** | `ServerID` | Physical server node / layer shard ID | `4469`, `4470`, `5122` |
| **Token 4** | `InstanceID`| World instance index (`0` for open world) | `0` |
| **Token 5** | `ZoneID` | Zone-level phase assignment / continent shard | `141`, `14` |
| **Token 6** | `NpcID` | Creature database entry ID | `10184` (Onyxia) |
| **Token 7** | `SpawnUID` | Unique hexadecimal spawn instance ID | `00002A4B8F` |

*Extraction Rule*: Token 3 (`ServerID`) is the authoritative hardware layer shard ID for open-world entities. Token 5 (`ZoneID`) represents the zone phase mapping utilized by NovaWorldBuffs.

### 4.2 Multi-Unit Scanning Strategy
To achieve rapid layer identification upon zone entry or phasing, ULO scans across four distinct data streams:
1. **Direct Unit Tokens**:
   - `"target"`, `"mouseover"`, `"focus"`, `"softenemy"`, `"softfriend"`, `"softinteract"`.
2. **Nameplates**:
   - Iterates over all active nameplate units returned by `C_NamePlate.GetNamePlates()`.
3. **Vignettes (Mini-map Rare & Chest Indicators)**:
   - Queries `C_VignetteInfo.GetVignettes()`, resolving each vignette's `objectGUID` via `C_VignetteInfo.GetVignetteInfo(vignetteGUID)`.
4. **Combat Log Stream**:
   - Listens to `COMBAT_LOG_EVENT_UNFILTERED`, inspecting `sourceGUID` and `destGUID` of open-world entities.

### 4.3 2-GUID Consensus Voting Algorithm (`VoteLayer`)
To eliminate false transitions caused by wandering border NPCs, transient pet spawns, or cross-zone pathing entities, ULO enforces a 2-GUID consensus voting algorithm:
1. When an entity is scanned, its GUID is verified. If the GUID was already evaluated in the current scan epoch, it is skipped.
2. The extracted `ServerID` receives a vote:
   $$\text{votes}[S] = \text{votes}[S] + 1$$
3. Only when a `ServerID` accumulates **$\ge 2$ distinct creature GUIDs** ($n \ge 2$) is the layer confirmed:
   $$\text{VoteLayer}(S) \ge 2 \implies \text{Confirmed Layer } = S$$
4. Until consensus is reached, the detection state remains in `LAYER_DETECTING` with confidence marked as `ESTIMATED`.

### 4.4 Player-Controlled Entity Filtering
Pets, guardians, totems, and charmed creatures inherit their controlling player's home server ID rather than the physical world layer ID.
- **Filter Rule**: Any unit for which `UnitIsPlayer(unit) == true` or `UnitPlayerControlled(unit) == true` is **immediately rejected** before GUID parsing.

### 4.5 Context Invalidation Events
Layer state and voting caches are automatically flushed upon:
- `ZONE_CHANGED_NEW_AREA`
- `PLAYER_ENTERING_WORLD`
- `UNIT_PHASE` (when `unit == "player"`)
- Map ID change detected via `C_Map.GetBestMapForUnit("player")`

Upon invalidation:
1. Layer cache and vote counters are cleared.
2. State transitions to `LAYER_DETECTING`.
3. A debounced scan is scheduled with a **0.5-second delay** (`DEBOUNCE_TIME`) to allow world entities to populate.

---

## 5. Multi-Release Compatibility Layer

### 5.1 Client Release Matrix

| Product Flavor | Client Directory | Product Name | TOC Version | Build Range | Special Constraints |
|---|---|---|---|---|---|
| `"wowf"` | `_forever_` | WoW Forever (Camelot) | `16001` | `1.60.x` | `LeaveParty` is nil; 180s refresh window; native bronze badge |
| `"wow_anniversary"` | `_anniversary_` | Classic Anniversary (TBC) | `20506` | `2.5.x` | Standard TBC API; Outland layer mapping |
| `"wow_classic_era"` | `_classic_era_` | Classic Era / SoD / Hardcore | `11509` | `1.15.x` | Seasonal realm name stripping; legacy party APIs |
| `"wow_classic"` | `_classic_` | Classic Progression (Mists) | `50504` | `5.5.x` | Mists FrameXML; hybrid C_PartyInfo APIs |
| `"wow"` | `_retail_` | Retail (Midnight) | `120105` | `12.x` | Strict `issecretvalue` enforcement; micro-sharding |

### 5.2 Safe Party & Group API Shims
To eliminate crashes caused by missing or deprecated global functions across client versions:

1. **`ULO.Compat.LeaveParty(category)`**:
   - In WoW Forever (`1.60.1`), calling `_G.LeaveParty()` throws a fatal error because `LeaveParty` is `nil`.
   - The shim prioritizes `C_PartyInfo.LeaveParty(category)`, falls back to `C_PartyInfo.ConfirmLeaveParty(category)`, and finally falls back to `_G.LeaveParty(category)`.
   - Every call is wrapped inside `pcall`.

2. **`ULO.Compat.InviteUnit(name)`**:
   - Normalizes target names via `NormalizeInviteTarget(name)`.
   - On Seasonal realms (Season of Discovery), realm names are stripped (`strsplit("-", name)`) to prevent `ERR_BAD_PLAYER_NAME_S`.
   - On WoW Forever and Retail connected realms, full `Name-Realm` format is preserved.
   - Dispatches via `C_PartyInfo.InviteUnit`, `C_PartyInfo.ConfirmInviteUnit`, or `_G.InviteUnit`.

3. **`ULO.Compat.AcceptGroup()`**:
   - Invokes `C_PartyInfo.ConfirmAcceptInvite()` or `AcceptGroup()`.
   - Finds visible `PARTY_INVITE` and `PARTY_INVITE_XREALM` dialogs, flags `dialog.inviteAccepted = 1`, and safely hides them via `StaticPopup_Hide`.

### 5.3 Security, Secret Value & Chat Lockdown Guards
In Retail 12.x and WoW Forever, the client engine introduces strict security sandboxing:
1. **`issecretvalue` and `canaccessvalue`**:
   - Strings originating from protected events or combat contexts may be tagged as secret values.
   - Performing standard operations (`string.lower`, `strsplit`, `strmatch`, concatenation) on secret values causes uncatchable engine exceptions.
   - `ULO.Compat.SafeString(str)` tests values against `issecretvalue()` and `canaccessvalue()`. If protected, it returns `nil` safely.
   - All string helpers (`SafeLower`, `SafeTrim`, `SafeSplit`, `SafeMatch`, `SafeFind`) pass through `SafeString`.
2. **`InChatMessagingLockdown()`**:
   - During encounters and restricted combat zones, `C_ChatInfo.InChatMessagingLockdown()` returns `true`.
   - `ULO.Compat.InChatLockdown()` checks both `InCombatLockdown()` and `C_ChatInfo.InChatMessagingLockdown()`.
   - Addon whisper and channel dispatches are blocked while lockdown is active.

---

## 6. 8-State Finite State Machine (FSM)

### 6.1 State Definitions
1. **`UNINITIALIZED` (State 1)**: Addon loaded, waiting for `PLAYER_ENTERING_WORLD` and valid zone/map context.
2. **`LAYER_DETECTING` (State 2)**: Actively scanning entities, accumulating votes toward 2-GUID consensus ($n < 2$).
3. **`LAYER_STABLE` (State 3)**: Layer verified by $\ge 2$ distinct GUIDs. Normal idle operation.
4. **`REFRESH_PENDING` (State 4)**: 180s refresh countdown active. Center banner/chevron displayed.
5. **`IN_COMBAT_LOCKED` (State 5)**: Timer expired or "Refresh Now" clicked while in combat. Phasing deferred.
6. **`REFRESH_IN_PROGRESS` (State 6)**: World reload executing. Addon awaits world re-entry.
7. **`REFRESH_COOLDOWN` (State 7)**: Post-refresh hopping cooldown active (300s-900s). Hop requests throttled.
8. **`INSTANCED_DISABLED` (State 8)**: Player inside dungeon, raid, battleground, or arena. Layering tracking suspended.

### 6.2 FSM Transition Matrix

```
                 +-------------------+
                 |   UNINITIALIZED   |
                 +-------------------+
                           |
            PLAYER_ENTERING_WORLD [NotInInstance]
                           v
        +-----------------------------------------+
        |             LAYER_DETECTING             |<--------------------+
        +-----------------------------------------+                     |
          |                      ^                                      |
  VoteLayer >= 2            Zone Change /                               |
          |                 Phase Invalidation                          |
          v                      |                                      |
+-------------------+            |                                      |
|   LAYER_STABLE    |------------+                                      |
+-------------------+                                                   |
   |             |                                                      |
   | Refresh     | "Refresh Now" (OutOfCombat)                          |
   | Warning     |                                                      |
   v             v                                                      |
+-------------------+                                                   |
|  REFRESH_PENDING  |                                                   |
+-------------------+                                                   |
   |             |                                                      |
   | Countdown=0 | Countdown=0 or Refresh Now                           |
   | (NoCombat)  | (InCombat)                                           |
   |             v                                                      |
   |   +-------------------+                                            |
   |   | IN_COMBAT_LOCKED  |                                            |
   |   +-------------------+                                            |
   |             |                                                      |
   |     PLAYER_REGEN_ENABLED                                           |
   |     (+ 2.0s Grace Period)                                          |
   |             |                                                      |
   v             v                                                      |
+-----------------------------------------+                             |
|           REFRESH_IN_PROGRESS           |                             |
+-----------------------------------------+                             |
                     |                                                  |
           World Reload Complete                                        |
                     v                                                  |
        +-------------------------+                                     |
        |    REFRESH_COOLDOWN     |-------------------------------------+
        +-------------------------+       Cooldown Expired (300s)
                     |
       (Inside Instance at any time -> INSTANCED_DISABLED)
```

| Current State | Trigger / Event | Guard Condition | Next State | Action Executed |
|---|---|---|---|---|
| `UNINITIALIZED` | `PLAYER_ENTERING_WORLD` | `IsInInstance() == false` | `LAYER_DETECTING` | Initialize map context, schedule initial entity scan |
| `UNINITIALIZED` | `PLAYER_ENTERING_WORLD` | `IsInInstance() == true` | `INSTANCED_DISABLED` | Suppress UI badge, suspend all layer scanning |
| `LAYER_DETECTING`| `VoteLayer(serverID) >= 2`| Open world context | `LAYER_STABLE` | Confirm layer, update minimap badge and Status HUD |
| `LAYER_STABLE` | Zone change / Phase change | `ZONE_CHANGED_NEW_AREA` or `UNIT_PHASE` | `LAYER_DETECTING` | Invalidate layer cache, clear voting counts |
| `LAYER_STABLE` | Layer refresh warning | Server refresh alert or cross-layer join | `REFRESH_PENDING` | Start 180s countdown timer, display banner |
| `REFRESH_PENDING`| "Refresh Now" clicked | `UnitAffectingCombat("player") == false` | `REFRESH_IN_PROGRESS` | Trigger immediate world reload |
| `REFRESH_PENDING`| "Refresh Now" clicked | `UnitAffectingCombat("player") == true` | `IN_COMBAT_LOCKED` | Block action, display combat error notification |
| `REFRESH_PENDING`| Countdown reaches 0:00 | `UnitAffectingCombat("player") == false` | `REFRESH_IN_PROGRESS` | Execute automatic layer transfer |
| `REFRESH_PENDING`| Countdown reaches 0:00 | `UnitAffectingCombat("player") == true` | `IN_COMBAT_LOCKED` | Defer transfer until player leaves combat |
| `IN_COMBAT_LOCKED`| `PLAYER_REGEN_ENABLED` | Out of combat for $\ge 2.0$s grace | `REFRESH_IN_PROGRESS` | Trigger deferred phase transfer |
| `REFRESH_IN_PROGRESS`| World reload complete | `PLAYER_ENTERING_WORLD` | `REFRESH_COOLDOWN` | Start 300s post-transfer cooldown timer |
| `REFRESH_COOLDOWN`| Cooldown reaches 0:00 | `remaining <= 0` | `LAYER_DETECTING` | Reset hop throttle, begin layer detection scan |
| Any State | Entered instance | `IsInInstance() == true` | `INSTANCED_DISABLED` | Abort pending hops, hide minimap badge |
| `INSTANCED_DISABLED`| Left instance | `IsInInstance() == false` | `LAYER_DETECTING` | Re-enable scanner and UI elements |

---

## 7. Party Coordination & Whisper Automation Engine

### 7.1 Keyword Engine & Pattern Matching
ULO parses incoming whispers and channel messages using whole-word boundary patterns:
- **Whole-Word Matching**: `%f[%w]` .. `string.lower(keyword)` .. `%f[%W]`.
- **Default Triggers**: `"layer"`, `"inv"`, `"invite"`, `"inv layer"`, `"layer inv"`.
- **Explicit Layer Requests**: Extracts layer numbers from expressions such as `"layer 2"`, `"inv 3"`, `"layer 1-3"`.
- **Inverted Keyword Filter**: Rejects messages containing negative qualifiers: `"not"`, `"off"`, `"except"`, `"but"`, `"out"`, `"other than"`, `"besides"`, `"apart from"`. (e.g., *"inv to anything but layer 2"* will not trigger layer 2 auto-invite).
- **Anti-Spam Blacklist**: Ignores messages containing trade/recruitment keywords (`"wts"`, `"wtb"`, `"lfg"`, `"lfm"`, `"ashen"`, `"autoinv"`).

### 7.2 Party Size Limits & Lifecycle Management
- **Party Member Cap**: Maximum 4 members (`GetNumGroupMembers() + #pendingInvites <= 4`). This reserves the 5th spot for the guest.
- **Raid Member Cap**: Maximum 39 members (`GetNumGroupMembers() <= 39`).
- **No Auto-Raid Conversion**: ULO will never automatically convert a 5-man party to a raid.
- **Offline Pruning**: If the party is full and a high-priority hop request arrives, ULO identifies the oldest offline party member (`SelectKickCandidate`) and uninvites them to make room.

### 7.3 Throttles and Auto-Departure
- **Player Invite Cache**: 300-second cache (`playersInvitedRecently`). A player cannot trigger another invite within 300 seconds.
- **Pending Invite Expiration**: 180 seconds.
- **Clean Group Departure**: When hopping to another player's layer:
  1. Auto-accept group invite via `Compat.AcceptGroup()`.
  2. Wait for 2-GUID consensus to confirm new layer.
  3. Wait 2.0 seconds (`DEPARTURE_DELAY`) for world stabilization.
  4. Automatically call `Compat.LeaveParty()`.
  5. If layer confirmation does not occur within 120 seconds (`GUEST_KICK_AFTER`), leave the party automatically to avoid occupying party slots.

---

## 8. User Interface Architecture

### 8.1 Minimap Bronze Layer Badge
- **Location**: Anchored below the minimap clock frame.
- **Appearance**: Circular bronze medallion with embossed layer number.
- **Tooltip**: Displays detailed diagnostic information:
  - Active Layer Number
  - Hardware Server ID (Token 3)
  - Zone Instance ID (Token 5)
  - Confidence Status (`CONFIRMED`, `ESTIMATED`, `UNDETERMINED`)
  - Active Refresh Countdown or Cooldown remaining
- **Suppression**: Automatically hidden when `IsInInstance() == true` or when layer is undetermined.

### 8.2 Movable Status HUD
- **Frame**: Movable, lockable status bar.
- **Displays**:
  - Current Layer Shard
  - Active 180s Refresh Countdown Bar
  - Post-Transfer Cooldown Alert
  - Quick-action buttons: **[Refresh Now]** and **[Hop Layer]**
- **States**: Fades to low opacity when idle; illuminates and pulses during `REFRESH_PENDING` and `IN_COMBAT_LOCKED`.

### 8.3 Slash Commands & Configuration Panel
- **Slash Commands**: `/ulo` and `/layer`
  - `/ulo`: Toggle Status HUD display.
  - `/ulo config`: Open Blizzard Settings panel.
  - `/ulo invite`: Toggle automated party invites on/off.
  - `/ulo hop <layer>`: Dispatch hop request for target layer.
- **Settings Panel**: Integrated into Blizzard Interface Options, configuring trigger keywords, auto-invite toggles, cooldown duration, and interop protocols.

---

## 9. Edge Cases, Failure Modes & Threat Matrix

| # | Scenario / Threat | Root Cause | Impact | Mitigation / Remediation |
|---|---|---|---|---|
| **1** | **Combat Lockout at Timer Expiry** | 180s timer reaches 0:00 while player is fighting | Phasing in combat causes mob reset, sudden death, or PvP desync | State transitions to `IN_COMBAT_LOCKED`. Transfer suspended until `PLAYER_REGEN_ENABLED` + 2.0s grace period. |
| **2** | **Griefed Daily Adler32 Channel** | Malicious user joins daily channel first and sets password | `JoinChannelByName` fails; addon cannot communicate | Catch channel join failure; blacklist hash in `failedChannels`; fall back immediately to static `"layer"` channel. |
| **3** | **PvP vs PvE Realm Mismatch (WoW Forever)** | Player attempts to invite character on incompatible rule set | Server returns `ERR_BAD_PLAYER_NAME_S` | Catch error event; blacklist target player for session; notify user via `ULO.Print`. |
| **4** | **Retail 12.x Secret String Crash** | Engine tags whisper text as secret in restricted encounter | Direct `string.match` or `strsplit` crashes client engine | All text operations routed through `Compat.SafeString` and `issecretvalue()` guards. |
| **5** | **Flight Path / Taxi Phasing** | World refresh fires while player is mid-flight on a taxi | Phasing drops player from flight path to fatal fall | Check `UnitOnTaxi("player")`. Defer transfer until taxi flight terminates. |
| **6** | **Dead / Ghost State Phasing** | Refresh fires while player is dead or in spirit form | Corpse location desynchronizes across layers | Check `UnitIsDeadOrGhost("player")`. Defer refresh until `PLAYER_ALIVE` / `PLAYER_UNGHOST`. |
| **7** | **Whisper Flood / Denial of Service** | Hostile player spams trigger whispers to exhaust party slots | Addon spams party invites, flooding chat and group | Enforce 5s per-sender throttle, 300s cache, and hard cap of 20 invites per hour. |
| **8** | **Zone Boundary Flapping** | Wandering border NPCs carry ServerID from neighboring zone | Layer indicator flips erratically between layers | 2-GUID consensus voting (`VoteLayer`) requires $\ge 2$ distinct creature GUIDs to switch layer. |
| **9** | **Instance Entrapment** | Player enters dungeon while hop request or refresh is pending | Hopping inside dungeon causes instance transfer errors | Listen for `ZONE_CHANGED_NEW_AREA`; if `IsInInstance()` is true, immediately enter `INSTANCED_DISABLED` and clear all pending hops. |
| **10**| **Muted Sound Leak** | High-volume invites cause repetitive chime sounds | Audio fatigue for user | Hook `PlaySound` / mute sound IDs (`567490`, `567451`, `567458`, `567478`) during automated invite transactions. |

---

## 10. Implementation Roadmap & Project Layout

### 10.1 Milestone Roadmap
- **Milestone 1 (Current)**: Architectural Specification, TOC Descriptors, Core Constants, Namespace Bootstrap, Compatibility Layer.
- **Milestone 2**: Core Layer Detection Subsystem (`GuidParser.lua`, `LayerScanner.lua`) and Refresh Monitoring Subsystem (`RefreshMonitor.lua`, `CooldownTracker.lua`).
- **Milestone 3**: Coordination Subsystem (`KeywordMatcher.lua`, `InviteManager.lua`, `GroupManager.lua`) and Addon Interoperability Subsystem (`AutoLayerProtocol.lua`, `OverlordProtocol.lua`, `NWBInterop.lua`).
- **Milestone 4**: User Interface Subsystem (`MinimapBadge.lua`, `StatusHUD.lua`, `SettingsPanel.lua`, `SlashCommands.lua`).
- **Milestone 5**: Full E2E Verification Suite (Tiers 1-4) and Adversarial Coverage Hardening (Tier 5).

### 10.2 File Layout
```
C:\Dev Projects\ULO\
├── ULO.toc                           # Universal TOC (11509, 16001, 20506, 50504, 120105)
├── ULO_Camelot.toc                   # WoW Forever TOC (16001)
├── ULO_Vanilla.toc                   # WoW Classic Era TOC (11509)
├── ULO_TBC.toc                       # WoW Classic Anniversary TBC TOC (20506)
├── ULO_Mists.toc                     # WoW Classic Progression TOC (50504)
├── ULO_Mainline.toc                  # WoW Retail TOC (120105)
├── TECHNICAL_SPECIFICATION.md        # Comprehensive technical specification document
├── Core/
│   ├── Constants.lua                 # Opcodes, events, default keywords, timer constants
│   ├── Init.lua                      # Addon initialization, namespace setup, lifecycle
│   └── SlashCommands.lua             # /ulo and /layer slash command handlers (M4)
├── Compatibility/
│   └── Compat.lua                    # Multi-release environment detection, API shims, security guards
├── Detection/
│   ├── GuidParser.lua                # Hyphen-delimited GUID parsing (M2)
│   └── LayerScanner.lua              # Multi-unit scan, nameplates, 2-GUID voting consensus (M2)
├── Monitor/
│   ├── RefreshMonitor.lua            # 180s countdown warning, "Refresh Now", combat deferral (M2)
│   └── CooldownTracker.lua           # Post-refresh hop cooldown tracking and throttle alerts (M2)
├── Coordination/
│   ├── KeywordMatcher.lua            # Whole-word regex parsing, ranges, blacklist filters (M3)
│   ├── InviteManager.lua             # C_PartyInfo.InviteUnit, 300s cache, 180s expiration (M3)
│   └── GroupManager.lua              # Group size caps, auto-accept, popup suppression (M3)
├── Interop/
│   ├── AutoLayerProtocol.lua         # 'layer' channel, Adler32 salted hashes, segment headers (M3)
│   ├── OverlordProtocol.lua          # OverlordLJ WHISPER prefix, R:2 and N wire protocol (M3)
│   └── NWBInterop.lua                # NovaWorldBuffs global state hooks and synchronization (M3)
├── UI/
│   ├── MinimapBadge.lua              # Bronze circular layer badge for minimap (M4)
│   ├── StatusHUD.lua                 # Movable status frame, countdown display, cooldown alerts (M4)
│   └── SettingsPanel.lua             # Blizzard Settings configuration panel (M4)
└── Tests/
    ├── TestHarness.lua               # Standalone WoW Lua mock environment & test runner (M5)
    ├── Tier1_FeatureTests.lua        # >=5 tests per inventoried feature (M5)
    ├── Tier2_BoundaryTests.lua       # Boundary, edge case, and error condition tests (M5)
    ├── Tier3_PairwiseTests.lua       # Cross-feature combination tests (M5)
    ├── Tier4_ScenarioTests.lua       # End-to-end real-world workflow scenarios (M5)
    └── RunTests.ps1                  # Executable test runner script (M5)
```
