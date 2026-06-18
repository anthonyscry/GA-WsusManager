# Make Plan: WSUS Transfer Package

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:64-88`.

Target unified system: WSUS package transfer.

Single entry point: `Invoke-WsusTransferPackage` in `Modules/WsusExport.psm1:430-539`.

Current-state correction:
- GUI Generic transfer is already on the package helper.
- CLI import/export are already on the package helper.
- Remaining work is monthly export: it still copies the backup file manually, then calls the helper for content only.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:45-59`
- `PATHFINDER-2026-06-18/02-duplication-report.md:45-58`
- `PATHFINDER-2026-06-18/01-flowcharts/air-gap-transfer-restore.md`
- `PATHFINDER-2026-06-18/01-flowcharts/online-sync-maintenance.md`
- `Modules/WsusExport.psm1:26-147,378-428,430-539,548-555`
- `Modules/WsusOperationPlan.psm1:161-184`
- `Scripts/Invoke-WsusManagement.ps1:690-735,1507-1548,2044-2065`
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1504-1586`
- `Tests/WsusExport.Tests.ps1:194-262`
- `Tests/CliIntegration.Tests.ps1:113-120,219-231`
- `Tests/WsusArchitectureInterfaces.Tests.ps1:100-111`
- `wiki/Module-Reference.md:865-892`

### Allowed APIs and patterns
- Keep `Invoke-WsusTransferPackage` as the only WSUS package coordinator.
- Keep `Invoke-WsusRobocopy` as the only direct robocopy executor.
- Keep GUI transfer on `-Direction Generic` via `New-WsusTransferOperationPlan`.
- Reuse the existing `-DatabaseBackupPath` parameter for monthly export; it already exists.

### Disallowed assumptions
- Do not re-plan GUI and CLI cutovers that are already done.
- Do not add a second transfer coordinator.
- Do not collapse Generic folder copy into WSUS Import/Export semantics.
- Do not move robocopy process spawning back into scripts.

## Phase 1 — Cut monthly export to the package helper fully

### What to implement
- In `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1518-1548`, remove manual `Copy-Item -Path $backupFile -Destination $ExportPath` staging.
- Replace the split flow with one package call that passes:
  - `-Direction Export`
  - `-SourcePath $script:ContentPath`
  - `-DestinationPath $ExportPath`
  - `-IncludeDatabase:$includeDatabase`
  - `-DatabaseBackupPath $backupFile` when a backup exists
  - `-IncludeContent` when `WsusContent` exists
  - `-LogPath $robocopyLog`
- Preserve `Test-ExportPathAccess` and backup selection logic.
- Preserve current operator-visible phase semantics unless the change intentionally upgrades a package failure from warning to hard failure.

### Verification checklist
- Search monthly export block for manual backup `Copy-Item` afterward.
- Confirm monthly still passes through the robocopy log path.
- Confirm CLI import/export and GUI Generic call sites remain unchanged unless a tiny signature update is required.

### Anti-pattern guards
- No manual monthly `.bak` copy left behind.
- No second package wrapper.
- No direct robocopy from monthly code.

## Phase 2 — Extend/confirm package tests

### What to implement
- Strengthen `Tests/WsusExport.Tests.ps1` to explicitly cover database staging with `-DatabaseBackupPath`.
- Strengthen `Tests/CliIntegration.Tests.ps1` monthly assertions to require:
  - `Invoke-WsusTransferPackage -Direction Export`
  - `-IncludeDatabase`
  - `-DatabaseBackupPath $backupFile`
  - absence of manual backup-file `Copy-Item`
- Keep existing GUI architecture assertions in `Tests/WsusArchitectureInterfaces.Tests.ps1:100-111` unchanged.

### Verification checklist
- Existing import/export path-mapping tests still pass.
- Generic transfer tests still assert exact paths.
- Monthly integration test now distinguishes content-only package use from full package use.

### Anti-pattern guards
- Do not weaken existing CLI export coverage.
- Do not overfit tests to log wording; assert behavior and call shape.

## Phase 3 — Docs and stale-reference cleanup

### What to update
- Update any docs that still describe monthly export as a manual backup copy plus content mirror.
- Keep GUI documentation honest: it remains a Generic non-destructive folder copy, not a WSUS package export UI.
- Ensure `wiki/Module-Reference.md:865-892` still matches the real package signature and return object.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusExport.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\CliIntegration.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusArchitectureInterfaces.Tests.ps1 -Output Detailed
```

Run static searches:
- Search `Scripts/Invoke-WsusMonthlyMaintenance.ps1` for backup-file `Copy-Item` in export flow.
- Search repo for direct `Start-Process -FilePath "robocopy.exe"`; only `Modules/WsusExport.psm1` should own it.
