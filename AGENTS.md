# Universal Layer Operator (ULO) - Repository Guidelines

## Layout
- `ULO/` contains the installable World of Warcraft addon folder (`ULO.toc`, flavor-specific `.toc` files, `Core/`, `Compatibility/`, `Detection/`, `Monitor/`, `Coordination/`, `Interop/`, `UI/`, `Media/`, `Changelog.txt`).
- `Tests/` contains the headless Lua test harness (`TestHarness.lua`) and the 5-tier verification suites (`Tier1` through `Tier5`, 231 tests total).
- `.tools/` contains validation, asset generation, local client deployment, and release automation scripts.
- `docs/` contains technical architecture and test infrastructure documentation.

## Required Checks
Always run the full validation suite before committing or deploying:
```powershell
npm.cmd test
```
This runs:
1. `node .tools/check_lua.js` (`luaparse` Lua 5.1 syntax validation over `ULO/**/*.lua`)
2. `node .tools/check_addon_structure.js` (verifies all 6 `.toc` manifests, version consistency, textures, and referenced Lua files)
3. `powershell -NoProfile -ExecutionPolicy Bypass -File ./RunTests.ps1` (executes all 231 headless Lua tests)

## Versioning & Branch Rules
- `main` tracks released builds (`X.Y.Z`) and tagged releases (`vX.Y.Z`).
- `dev` keeps `## Version: Dev` across all 6 `.toc` files between releases.
- Keep `## Interface:` values `16001` on `ULO/ULO_Camelot.toc` and `11509` on `ULO/ULO_Vanilla.toc`.
- Keep `CHANGELOG.md` and `ULO/Changelog.txt` synchronized for every release.
- See `.agents/workflows/local_build.md` and `.agents/workflows/release.md` for standard procedures.
