<p align="center">
  <img src="Images/Banner.png" alt="Universal Layer Operator Banner" width="840">
</p>

# Universal Layer Operator (ULO)

**Universal Layer Operator (`ULO`)** is a multi-release World of Warcraft layer and shard operator built for **WoW Forever**, **Classic Era / SoD / Hardcore**, **TBC Anniversary**, **Mists Classic**, and **Retail**.

<p align="center">
  <img src="Images/Logo.png" alt="ULO Emblem" width="160">
</p>

## Key Features
- **Cross-Release Compatibility**: Single addon package with both universal (`ULO.toc`) and client-specific manifests (`ULO_Camelot.toc`, `ULO_Vanilla.toc`, `ULO_TBC.toc`, `ULO_Mists.toc`, `ULO_Mainline.toc`) and safe Retail secret-value (`issecretvalue`) / combat lockdown guards.
- **Layer & Shard Detection**: Inspects creature/NPC GUIDs and UnitTokens with a 10-sample consensus window to determine active layer IDs and confidence.
- **Layer Refresh Monitor**: Tracks 180s layer-refresh countdowns with out-of-combat safe `/reload` deferral and post-transfer cooldown tracking.
- **Automated Hopping & Interop**:
  - Keyword-driven automated whisper invites with blacklists, range/exclusion matching, 300s player throttling, LFG queue protection, and audio chime suppression.
  - Safe hop acceptance that leaves normal social party invites untouched.
  - Full interoperability with **AutoLayer** (`layer` and daily Adler32 salted channels with slots 1–5 protection), **Overlord**, and **NovaWorldBuffs**.
- **In-Game UI**:
  - Circular bronze orbital Minimap Medallion showing the active layer (left-click toggles HUD, right-click opens Settings).
  - Draggable Status HUD (`Refresh` and `Hop` action buttons, countdown readout, SavedVariables position persistence).
  - Blizzard Settings / Interface Options integration and `/ulo` slash command control.

## Repository Structure
- `ULO/` — Installable World of Warcraft addon folder (`Interface\AddOns\ULO`).
- `Tests/` — Headless Lua test harness and 5-tier verification suite (231 tests).
- `.tools/` — Validation, PNG/TGA asset pipeline, multi-client local deployment, and release scripts.
- `.github/workflows/` — Automated GitHub Release & CurseForge publishing workflow.
- `docs/` — Technical specification and test documentation.

## Development & Verification
Install dev dependencies once and run the full check suite (Lua 5.1 syntax, TOC/asset structure, and 231 Lua tests):
```powershell
npm install --ignore-scripts --no-audit --no-fund
npm test
```

## Local Multi-Client Deployment
Deploy `ULO` to all local World of Warcraft installations (`_anniversary_`, `_classic_`, `_classic_beta_`, `_classic_era_`, `_classic_era_ptr_`, `_forever_`, `_retail_`) with SHA-256 verification:
```powershell
npm run install:local
```

## Branches
- `main` — Stable tagged releases (`vX.Y.Z`).
- `dev` — Active development (`## Version: Dev`).
