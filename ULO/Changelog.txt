# Changelog

## [Unreleased]

## [v1.0.1-beta.1] - 2026-11-20
### Added
- CurseForge publishing from GitHub releases, with full validation, verified artwork in release ZIPs, explicit game-version metadata and saved upload receipts.
- Replaced the eight layer buttons with a scrollable layer list and per-row Request controls. The current layer is disabled; fresh eligible helper counts are shown where available. The list covers the supported 1–20 range without claiming that every layer is populated.
- Added same-zone intelligence for Forever and TBC: normalize subzones, expire peer metadata after 90 seconds, advertise versioned ULO status/requests, and use TBC's zone-aware AutoLayer format. Legacy Forever requests retain their existing format and use bounded helper-zone checks after joining.
- Mode now opens a checkbox dropdown for ULO, AutoLayer, Overlord, NovaWorldBuffs, guild chat, TresLayerSwap, LayerHopper, and direct whispers. Each track can be enabled independently and selections are saved.
- Added a Linked / Free button to the Actions window. Linked Actions follows the main window and closes with it; Free Actions can be moved and kept open independently. The link preference and separate free position are saved.
### Fixed
- Guard secret chat text and sender names before comparisons, parsing or logging. This fixes the reported AutoLayer channel error and applies the same boundary checks to guild chat, whispers and ULO addon messages; readable requests remain supported.
- Overlord hops now enter its native LayerJumper lifecycle, preserving volunteer preferences, request handlers, shard IDs, and native invitation timing. Same-zone volunteers take priority; legacy volunteers remain unverified until their actual group leader can be checked. PvP contacts are not used as helper consent.
- AutoLayer subscriptions now match the upstream static channel and three server-calendar daily hashes. A hop sends once on an available channel, skips failed/protected slots, and refreshes owned subscriptions on date rollover.
- NWB observations no longer imply invitation consent or replace fresh explicit ULO helper preferences. Known incompatible helpers are rejected before acceptance; a formed party alone cannot verify a hop.
- Hop Any excludes the current known layer, tries directed helpers before a single public fallback, and stops sending requests after accepting the first invite. Repeated clicks, requests for the current layer, and same-layer confirmations cannot restart or complete a hop.
- Blocked self-invites at the shared invite API and request handlers. Automated AutoLayer replies no longer trigger invitations back to helpers. Hop-related group invitation notices are filtered only during the player's own bounded request window.
- Actions now starts closed at every login or reload, including profiles that previously saved it as open. Changing zones preserves a window opened during the current session.

## [v1.0.0] - 2026-11-14
### Added
- Initial public release of Universal Layer Operator (`ULO`) with multi-release support for WoW Forever (`16001`), Classic Era (`11509`), TBC Anniversary (`20506`), Mists Classic (`50504`), and Retail (`120001` / `120105`).
- Unified compatibility layer (`Compatibility/Compat.lua`) with Retail secret-value (`issecretvalue`) and combat lockdown guards.
- Real-time GUID and UnitToken layer detection (`Detection/GuidParser.lua`, `Detection/LayerScanner.lua`) with 10-observation sliding window stabilization.
- Forever-style 180s layer refresh monitoring (`Monitor/RefreshMonitor.lua`), safe out-of-combat `/reload` handling, and post-transfer cooldown tracking (`Monitor/CooldownTracker.lua`).
- Automated invite coordination (`Coordination/KeywordMatcher.lua`, `Coordination/InviteManager.lua`, `Coordination/GroupManager.lua`) with whisper & dynamic AutoLayer `CHAT_MSG_CHANNEL` dispatch, 300s player throttling, and non-hop social invite preservation.
- Interoperability protocols for AutoLayer (`Interop/AutoLayerProtocol.lua`), Overlord (`Interop/OverlordProtocol.lua`), and NovaWorldBuffs (`Interop/NWBInterop.lua`).
- Custom bronze/arcane emblem artwork and TGA textures (`Media/ULOIcon.tga`, `Media/ULOMinimap.tga`, `Media/ULOHudBg.tga`), draggable status HUD, minimap medallion badge, and Blizzard Settings panel.
- Full CI/CD, CurseForge packaging, local multi-client PowerShell deployment (`install_local.ps1`), and 231 headless Lua tests.
