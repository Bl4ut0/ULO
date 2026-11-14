# Release Workflow (Beta & Stable)

ULO uses a two-branch release model matching ItemRack:
- `dev`: Active development branch where all TOC `## Version:` headers stay `Dev`.
- `main`: Release branch mirroring tagged builds (`vX.Y.Z` / `vX.Y.Z-beta.N`).

## 1. Prepare Release on `dev` (or release branch)
1. Ensure clean working tree and passing checks:
   ```powershell
   npm.cmd test
   ```
2. Bump all 6 TOC versions and update `CHANGELOG.md` + `ULO/Changelog.txt`:
   ```powershell
   node .tools/create_release.js prepare <beta|stable> <version> --notes "- Summary of changes"
   ```
3. Review diff and commit release preparation.

## 2. Land on `main`, Build, & Tag
1. Switch to `main`, merge/cherry-pick the release commit, and run verification:
   ```powershell
   npm.cmd test
   node .tools/create_release.js build <beta|stable> <version> --ref HEAD
   ```
2. Tag `v<version>` on `main` and push `main` + tag to `origin`.
3. Create the GitHub release via `gh release create v<version> ".versions/<version>/ULO-v<version>.zip" ".versions/<version>/ULO-v<version>.zip.sha256" --notes-file ".versions/<version>/GITHUB_RELEASE.md"`.

## 3. Reset `dev` Back to `Dev`
1. Switch back to `dev`, merge `main` if needed, and reset TOC versions back to `Dev`:
   ```powershell
   node .tools/create_release.js reset
   npm.cmd test
   ```
2. Commit `Reset development version to Dev` and push `dev`.
