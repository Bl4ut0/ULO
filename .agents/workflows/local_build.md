# Local Build & Deployment Workflow

Use this workflow to validate ULO locally and deploy to every local World of Warcraft client under `C:\Program Files (x86)\World of Warcraft`.

1. Run syntax, structure, and unit/scenario verification:
   ```powershell
   npm.cmd test
   ```
2. If source artwork changed, regenerate PNGs and WoW TGA textures:
   ```powershell
   & .\.tools\build_assets.ps1
   ```
3. Deploy the working tree directly to all installed local WoW clients with SHA-256 verification:
   ```powershell
   & .\.tools\install_local.ps1 -SourceRoot . -Confirm:$false
   ```
4. To deploy a clean git ref instead of the working tree:
   ```powershell
   & .\.tools\install_local.ps1 -SourceRoot . -Ref dev -Confirm:$false
   ```
