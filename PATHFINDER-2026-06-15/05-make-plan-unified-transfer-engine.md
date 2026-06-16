# Make Plan: Unified Transfer Engine

## Source prompt

From `PATHFINDER-2026-06-15/04-handoff-prompts.md:3-25`.

Target unified system: transfer/copy execution.

Single entry point: `Invoke-WsusTransferPackage` in `Modules/WsusExport.psm1` near the existing transfer-plan seam at `Modules/WsusExport.psm1:378-428`.

Rewrite call sites:
- `Modules/WsusOperationPlan.psm1:161-172` — GUI transfer currently builds raw robocopy command text.
- `Scripts/Invoke-WsusManagement.ps1:664-730` — import copy path.
- `Scripts/Invoke-WsusManagement.ps1:1347-1540` — export copy path.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1503-1590` — monthly export path.

## Phase 0 — Documentation and API discovery

### Sources to read first

- `PATHFINDER-2026-06-15/03-unified-proposal.md:23-42` — target shape and required call-site cutover.
- `PATHFINDER-2026-06-15/01-flowcharts/air-gap-transfer-restore.md:29-40,52-69` — import/export/GUI current flow.
- `PATHFINDER-2026-06-15/01-flowcharts/online-sync-maintenance.md:20-32` — monthly export current flow.
- `Modules/WsusExport.psm1:26-147,378-428,434-440` — existing low-level robocopy and transfer-plan APIs.
- `Modules/WsusOperationPlan.psm1:8-12,130-172` — command-literal helper, child module import pattern, current GUI transfer raw command.
- `Scripts/Invoke-WsusManagement.ps1:664-730,764-844,1347-1540,2027-2048` — CLI import/export behavior and legacy dispatch mapping.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:119-160,1503-1590` — imports and monthly export behavior.
- `Tests/WsusExport.Tests.ps1:28-56,112-188` — existing module export and robocopy tests.
- `Tests/WsusArchitectureInterfaces.Tests.ps1:100-105,170-176` — transfer contract tests to update.
- `README.md:117-148`, `docs/WSUS-Manager-SOP.md:451-453`, `wiki/Module-Reference.md:846-870` — operator-facing expected behavior.

### Allowed APIs and patterns

- Use `Invoke-WsusRobocopy` as the single robocopy process executor. It already centralizes source validation, args, log path, success mapping for exit codes under 8, and message text (`Modules/WsusExport.psm1:26-147`).
- Reuse `New-WsusTransferPlan` for WSUS-content-aware source/destination normalization (`Modules/WsusExport.psm1:378-413`).
- Reuse `Invoke-WsusTransferPlan` only if its signature remains useful; it currently forwards `Plan.ContentSource`, `Plan.ContentDestination`, `Plan.MaxAgeDays`, and `LogPath` to `Invoke-WsusRobocopy` (`Modules/WsusExport.psm1:416-428`).
- Use `ConvertTo-WsusCommandLiteral` for child-process command string arguments (`Modules/WsusOperationPlan.psm1:8-12`).
- Use the existing operation-plan child module import shape from `New-WsusScheduleOperationPlan` (`Modules/WsusOperationPlan.psm1:130-158`).
- Preserve operator semantics: transfer is non-destructive and must land imported content at `C:\WSUS\WsusContent` (`README.md:117-128`, `docs/WSUS-Manager-SOP.md:451-453`).

### Disallowed assumptions

- `Invoke-WsusTransferPackage` does not exist yet; implement it rather than pretending it is available.
- Do not keep raw robocopy fallback builders after the shared helper is wired.
- Do not introduce a strategy registry/provider abstraction.
- Do not use `/MIR` or any destructive synchronization option.
- Do not move GUI/CLI wording into the shared helper; return structured data and let each caller format.

## Phase 1 — Add the single package transfer API

### What to implement

In `Modules/WsusExport.psm1`, add `Invoke-WsusTransferPackage` near `New-WsusTransferPlan` / `Invoke-WsusTransferPlan`.

Proposed public signature:

```powershell
function Invoke-WsusTransferPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Import','Export','Generic')][string]$Direction,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [switch]$IncludeDatabase,
        [switch]$IncludeContent,
        [ValidateSet('Full','Differential')][string]$Mode = 'Full',
        [int]$MaxAgeDays = 0,
        [string]$LogPath,
        [int]$ThreadCount = 16,
        [string[]]$ExcludeExtensions = @('*.bak', '*.log'),
        [string[]]$ExcludeDirs = @('Logs', 'SQLDB', 'Backup')
    )
}
```

Behavior:
- Return a stable `[pscustomobject]` with `PSTypeName = 'Wsus.TransferResult'` and fields: `Success`, `Direction`, `SourcePath`, `DestinationPath`, `ContentSource`, `ContentDestination`, `DatabaseFiles`, `ContentResult`, `Errors`, `Warnings`, `Message`.
- Create destination root when missing, matching `Copy-ToDestination` and `Invoke-ExportToMedia` behavior (`Scripts/Invoke-WsusManagement.ps1:672-675`, `1456-1473`).
- If `IncludeDatabase`, copy database backups before content:
  - For import/package-copy source folders, copy all root `*.bak` files to destination. This preserves `Copy-ToDestination` behavior (`Scripts/Invoke-WsusManagement.ps1:681-690`).
  - For source-server export/monthly cases, callers may pass a narrowed source folder or a specific backup file only if the implementation adds a `DatabaseBackupPath` parameter. If not adding that parameter, preserve caller-side `Copy-Item` for the backup and only centralize content copy. Prefer adding `DatabaseBackupPath` to eliminate scattered backup copy logic in Phase 3.
- If `IncludeContent`, use `New-WsusTransferPlan` for `Import` and `Export`; use direct `SourcePath` and `DestinationPath` for `Generic` GUI transfer when the operator selected exact folders.
- Use `Invoke-WsusRobocopy` for all content copies. Pass through log path, thread count, max age, exclusions.
- Treat content copy failure as `Success = $false`; do not rely on caller-side warning-only handling.
- Export `Invoke-WsusTransferPackage` in `Export-ModuleMember`.

### Tests to add/update

Update `Tests/WsusExport.Tests.ps1`:
- Assert `Invoke-WsusTransferPackage` is exported.
- Mock `Invoke-WsusRobocopy`, `Test-Path`, `New-Item`, `Copy-Item`, `Get-ChildItem` inside module scope.
- Assert `Import` with `IncludeContent` maps source root `E:\Drop` to `E:\Drop\WsusContent` and destination `C:\WSUS` to `C:\WSUS\WsusContent`.
- Assert `Export` with `IncludeContent` maps source root `C:\WSUS` to `C:\WSUS\WsusContent` and destination root `E:\Export` to `E:\Export\WsusContent`.
- Assert `Generic` copies exactly the source and destination paths passed by the GUI path.
- Assert robocopy exit code 8+ produces `Success = $false` through the shared result.

### Verification checklist

- `Get-Command Invoke-WsusTransferPackage -Module WsusExport` succeeds.
- Existing `New-WsusTransferPlan` tests still pass (`Tests/WsusArchitectureInterfaces.Tests.ps1:170-176`).
- `Invoke-WsusRobocopy` remains the only `Start-Process -FilePath "robocopy.exe"` path in transfer code.

### Anti-pattern guards

- Do not duplicate the robocopy exit-code switch in `Invoke-WsusTransferPackage`; consume `Invoke-WsusRobocopy` result.
- Do not widen `Invoke-WsusRobocopy` into backup-copy behavior; keep DB file copy at package level.
- Do not change public `Export-WsusContent` unless required by tests; it can remain as a wrapper-style legacy helper.

## Phase 2 — Cut GUI transfer operation plan to the shared API

### What to implement

In `Modules/WsusOperationPlan.psm1:161-172`, replace raw robocopy command construction with a child command that imports `WsusExport.psm1` and calls `Invoke-WsusTransferPackage`.

Add a mandatory `ExportModulePath` or `ModulePath` parameter to `New-WsusTransferOperationPlan`, or derive the module path from an existing modules directory already available at the GUI call site. Prefer explicit `ExportModulePath` because `New-WsusScheduleOperationPlan` already accepts explicit module path (`Modules/WsusOperationPlan.psm1:130-158`).

Target command shape:

```powershell
& {
    Import-Module '<path>\WsusExport.psm1' -Force -DisableNameChecking
    $result = Invoke-WsusTransferPackage -Direction Generic -SourcePath '<source>' -DestinationPath '<destination>' -IncludeContent
    if (-not $result.Success) { Write-Error $result.Message; exit 1 }
}
```

Update the GUI call at `Scripts/WsusManagementGui.ps1:3135-3155` to pass the `WsusExport.psm1` path into `New-WsusTransferOperationPlan`.

Keep GUI transfer mode forced to embedded unless a later plan changes terminal behavior.

### Tests to update

Update `Tests/WsusArchitectureInterfaces.Tests.ps1:100-105`:
- Stop asserting the GUI transfer plan command contains `robocopy` or `$LASTEXITCODE -le 7`.
- Assert it imports `WsusExport.psm1` and calls `Invoke-WsusTransferPackage`.
- Assert `-Direction Generic` is present for raw folder-to-folder GUI transfer.
- Assert `Mode` remains `Embedded` and timeout remains 180 minutes.

Update `Tests/Integration.Tests.ps1:179-198` only if its string expectation becomes stale. Preserve the assertion that GUI still calls `New-WsusTransferOperationPlan -SourcePath $opts.SourcePath -DestinationPath $opts.DestinationPath` or update it to include the module path while preserving source/destination semantics.

### Verification checklist

- No raw `robocopy` string remains in `New-WsusTransferOperationPlan`.
- GUI transfer plan still quotes paths with apostrophes correctly via `ConvertTo-WsusCommandLiteral`.
- Existing operation runner behavior remains unchanged; only `plan.Command` changes.

### Anti-pattern guards

- Do not let the GUI call `Invoke-WsusTransferPackage` in-process; it must still run through `Start-WsusOperation` to keep long transfer work off the UI thread.
- Do not pass user paths without `ConvertTo-WsusCommandLiteral`.

## Phase 3 — Cut CLI import/export to the shared API

### What to implement

In `Scripts/Invoke-WsusManagement.ps1`, remove the raw fallback robocopy builders from:
- `Copy-ToDestination` lines `664-730`.
- `Invoke-ExportToMedia` lines `1347-1540`.

Update `Copy-ToDestination`:
- Keep destination creation only if `Invoke-WsusTransferPackage` does not own it after Phase 1; otherwise delete local creation.
- Replace database and content copy branches with one `Invoke-WsusTransferPackage -Direction Import -SourcePath $SourceFolder -DestinationPath $Destination -IncludeDatabase:$IncludeDatabase -IncludeContent:$IncludeContent`.
- Use the returned `DatabaseFiles`, `ContentDestination`, and `ContentResult` for existing output lines.
- If the result is unsuccessful, log an error and return failure in a way the caller can observe. If current callers only print, add a boolean or result return from `Copy-ToDestination` and have `Invoke-FullCopy` stop before `COPY COMPLETE` on failure.

Update `Invoke-ExportToMedia`:
- Preserve source/destination validation and interactive prompting.
- Replace `Copy-Item` database copy plus content-copy block with `Invoke-WsusTransferPackage -Direction Export -SourcePath $source -DestinationPath $destination -IncludeDatabase:($null -ne $sourceBak) -IncludeContent:$hasContent`.
- If Phase 1 added `DatabaseBackupPath`, pass `$sourceBak.FullName` so export copies the same newest backup currently selected at `Scripts/Invoke-WsusManagement.ps1:1421-1424`.
- Remove `Get-Command New-WsusTransferPlan` / `Invoke-WsusTransferPlan` fallback checks. The script imports `WsusExport` during startup; absence should be a real failure, not a silent alternate engine.

### Tests to add/update

Add focused Pester coverage. Prefer AST/string-level tests if dot-sourcing the full CLI script triggers real WSUS behavior.

Assertions:
- `Scripts/Invoke-WsusManagement.ps1` no longer contains `Start-Process -FilePath "robocopy.exe"` in the import/export call-site ranges.
- CLI import path contains `Invoke-WsusTransferPackage -Direction Import`.
- CLI export path contains `Invoke-WsusTransferPackage -Direction Export`.
- `-Export` dispatch still preserves legacy `ExportRoot`-as-destination behavior (`Scripts/Invoke-WsusManagement.ps1:2033-2048`).

### Verification checklist

- Import with source root containing `WsusContent` still reports destination content under `C:\WSUS\WsusContent`.
- Export with source root `C:\WSUS` still reports exported content under `<destination>\WsusContent`.
- The CLI no longer has a raw robocopy fallback for this flow.

### Anti-pattern guards

- Do not keep the `Get-Command New-WsusTransferPlan` fallback branch.
- Do not change top-level `-Import` / `-Export` parameter semantics.
- Do not remove the legacy GUI `ExportRoot` destination mapping unless separately planned.

## Phase 4 — Cut monthly maintenance export to the shared API

### What to implement

In `Scripts/Invoke-WsusMonthlyMaintenance.ps1`:
- Import `Modules/WsusExport.psm1` with the same local module import pattern used for Utilities/Config/Database/Services (`Scripts/Invoke-WsusMonthlyMaintenance.ps1:119-160`).
- Replace raw robocopy block at `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1536-1566` with `Invoke-WsusTransferPackage -Direction Export -SourcePath $script:ContentPath -DestinationPath $ExportPath -IncludeContent -LogPath $robocopyLog`.
- Keep backup selection from `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1518-1534`, or pass `DatabaseBackupPath` to the package helper if Phase 1 added it.
- Preserve `Test-ExportPathAccess` behavior and export phase status/warning behavior (`Scripts/Invoke-WsusMonthlyMaintenance.ps1:1511-1517`, `1571-1581`).
- When the package result fails, add the shared result message to `$MaintenanceResults.Warnings` or `$MaintenanceResults.Errors` consistently with the existing export failure handling.

### Tests to add/update

Update `Tests/CliIntegration.Tests.ps1` or a new focused maintenance-export test:
- Assert the script imports `WsusExport.psm1`.
- Assert monthly export no longer contains `Start-Process -FilePath "robocopy.exe"` in the export phase.
- Assert monthly export calls `Invoke-WsusTransferPackage -Direction Export`.
- Keep existing `ExportPath` and `SkipExport` parameter assertions (`Tests/CliIntegration.Tests.ps1:64-82`).

### Verification checklist

- ExportPath blank still skips export.
- `-SkipExport` still skips export.
- Export path inaccessible still marks phase skipped, not failed.
- Content path missing still produces an operator-visible warning.

### Anti-pattern guards

- Do not move maintenance phase progress/timing into `WsusExport`; the helper owns copying, not maintenance orchestration.
- Do not hardcode monthly log file naming inside `Invoke-WsusTransferPackage`; pass `LogPath` from the caller.

## Phase 5 — Documentation and stale-reference cleanup

### What to update

- Update `wiki/Module-Reference.md:846-870` to document `Invoke-WsusTransferPackage`. Also correct stale fields if they remain wrong: current `Invoke-WsusRobocopy` returns `Success`, `ExitCode`, and `Message`, not documented `FilesCopied` (`Modules/WsusExport.psm1:73-147`, `wiki/Module-Reference.md:849-853`).
- If operator behavior changes in wording only, update `README.md:117-148` and `docs/WSUS-Manager-SOP.md:451-453` only enough to say GUI/CLI/monthly export use the same transfer engine.
- Do not alter the documented import destination expectation: `C:\WSUS\WsusContent`.

### Verification checklist

- Search docs for `Invoke-WsusTransferPackage`; module reference includes it.
- Search docs for stale `FilesCopied` on `Invoke-WsusRobocopy` and correct or remove it.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusExport.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusArchitectureInterfaces.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\Integration.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\CliIntegration.Tests.ps1 -Output Detailed
```

Run static searches:

- Search `Modules/WsusOperationPlan.psm1`, `Scripts/Invoke-WsusManagement.ps1`, and `Scripts/Invoke-WsusMonthlyMaintenance.ps1` for raw `robocopy` / `Start-Process -FilePath "robocopy.exe"`; only `Modules/WsusExport.psm1` should execute robocopy.
- Search all repo files for `Invoke-WsusTransferPackage`; expected locations are `Modules/WsusExport.psm1`, call sites, tests, and docs.
- Search for `$LASTEXITCODE -le 7` in transfer paths; remove duplicate exit-code normalization outside `Invoke-WsusRobocopy`.

Manual smoke checklist if a Windows WSUS lab is available:

1. GUI Robocopy from a small test source folder to a temp destination completes and creates expected destination contents.
2. CLI export with `-Export -SourcePath <temp-root> -DestinationPath <temp-dest>` copies `.bak` and `WsusContent`.
3. CLI import with `-Import -SourcePath <temp-export> -DestinationPath <temp-import>` lands content under `<temp-import>\WsusContent`.
4. Monthly maintenance with `-Operations Export -ExportPath <temp-dest> -SkipUltimateCleanup` uses the shared transfer path and logs the robocopy log path.

## Implementation order

1. Add `Invoke-WsusTransferPackage` and tests in `WsusExport`.
2. Cut GUI transfer plan and update architecture/integration tests.
3. Cut CLI import/export and add static assertions.
4. Cut monthly export and add static assertions.
5. Update docs.
6. Run targeted tests and static searches.
