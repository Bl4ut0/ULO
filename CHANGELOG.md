# Changelog

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
