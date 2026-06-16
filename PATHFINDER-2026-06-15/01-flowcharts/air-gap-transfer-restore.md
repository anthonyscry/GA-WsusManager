# Feature 5 — Air-gap transfer, import/export & database restore

## Sources consulted
- `PATHFINDER-2026-06-15/00-features.md:74-85`
- `Scripts/WsusManagementGui.ps1:332-338`
- `Scripts/WsusManagementGui.ps1:2064-2176`
- `Scripts/WsusManagementGui.ps1:2804-2868`
- `Scripts/WsusManagementGui.ps1:3119-3149`
- `Scripts/WsusManagementGui.ps1:3185-3258`
- `Scripts/Invoke-WsusManagement.ps1:77-124`
- `Scripts/Invoke-WsusManagement.ps1:179-223`
- `Scripts/Invoke-WsusManagement.ps1:294-355`
- `Scripts/Invoke-WsusManagement.ps1:500-642`
- `Scripts/Invoke-WsusManagement.ps1:664-730`
- `Scripts/Invoke-WsusManagement.ps1:764-844`
- `Scripts/Invoke-WsusManagement.ps1:1061-1178`
- `Scripts/Invoke-WsusManagement.ps1:1347-1540`
- `Scripts/Invoke-WsusManagement.ps1:2027-2048`
- `Modules/WsusProvisioning.psm1:73-124`
- `Modules/WsusOperationPlan.psm1:54-84`
- `Modules/WsusOperationPlan.psm1:161-172`
- `Modules/WsusExport.psm1:26-147`
- `Modules/WsusExport.psm1:378-428`
- `Modules/WsusOperationRunner.psm1:129-214`
- `Modules/WsusOperationRunner.psm1:250-562`
- `Modules/WsusGuiShell.psm1:151-210`
- `Modules/WsusOperationCompletion.psm1:10-68`

## Concrete findings
- GUI restore path uses `Show-RestoreDialog`, validates the selected `.bak` path with `Test-SafePath`, resolves it with `Resolve-WsusRestoreBackup`, then creates a `restore` management operation plan with `ContentPath`, `SqlInstance`, and `BackupFile` (`Scripts/WsusManagementGui.ps1:2064-2176`, `3119-3137`; `Modules/WsusProvisioning.psm1:73-124`).
- GUI transfer path uses `Show-TransferDialog`, validates source/destination with `Test-SafePath`, then creates `New-WsusTransferOperationPlan` in forced Embedded mode (`Scripts/WsusManagementGui.ps1:2804-2868`, `3139-3149`).
- `New-WsusTransferOperationPlan` emits direct `robocopy` source→destination with `/E /ZB /COPY:DAT /DCOPY:T /R:1 /W:1 /NDL /NP` and maps robocopy exit codes `0..7` to process exit 0 (`Modules/WsusOperationPlan.psm1:161-172`).
- GUI execution and terminal status are owned by `Start-WsusOperation` / `Complete-WsusOperation` plus `Invoke-WsusGuiOperationCompletion` (`Scripts/WsusManagementGui.ps1:3185-3258`; `Modules/WsusOperationRunner.psm1:129-214`, `250-562`; `Modules/WsusGuiShell.psm1:151-210`; `Modules/WsusOperationCompletion.psm1:10-68`).
- CLI exposes `-Restore`, `-Import`, `-Export`, `-BackupPath`, `-SourcePath`, `-DestinationPath`, `-NonInteractive`, `-ExportRoot`, `-ContentPath`, and `-SqlInstance` (`Scripts/Invoke-WsusManagement.ps1:77-130`). Main dispatch routes `-Restore` to `Invoke-WsusRestore`, `-Import` to `Invoke-CopyForAirGap`, and `-Export` to `Invoke-ExportToMedia` (`Scripts/Invoke-WsusManagement.ps1:2027-2048`).
- `Invoke-CopyForAirGap` validates the source, then `Invoke-FullCopy` locates the newest `.bak` and `WsusContent`, and `Copy-ToDestination` copies the `.bak` plus uses `New-WsusTransferPlan -Direction Import` and `Invoke-WsusTransferPlan` for content (`Scripts/Invoke-WsusManagement.ps1:1061-1178`, `764-844`, `664-730`; `Modules/WsusExport.psm1:378-428`).
- `Invoke-ExportToMedia` validates source/destination, copies the newest backup with `Copy-Item`, and uses `New-WsusTransferPlan -Direction Export` plus `Invoke-WsusTransferPlan` to send `WsusContent` to `destination\WsusContent` (`Scripts/Invoke-WsusManagement.ps1:1347-1540`; `Modules/WsusExport.psm1:378-428`).
- `New-WsusTransferPlan` normalizes `ContentSource` and `ContentDestination` by appending `WsusContent` unless the provided path already ends in `WsusContent` (`Modules/WsusExport.psm1:378-413`).
- `Invoke-WsusRobocopy` validates source existence, runs `robocopy.exe` with `/E /XO /MT:16 /R:2 /W:5 /NP /NDL` plus optional `/MAXAGE`, `/XF`, `/XD`, `/LOG`, and treats `0..7` as success (`Modules/WsusExport.psm1:26-147`).
- `Invoke-WsusRestore` requires SQL sysadmin, locates `sqlcmd.exe`, verifies backup with `RESTORE VERIFYONLY WITH CHECKSUM`, stops `WSUSService` and `W3SVC`, switches SUSDB to `SINGLE_USER`, runs `RESTORE DATABASE SUSDB WITH REPLACE`, switches back to `MULTI_USER`, restarts services, runs `wsusutil postinstall`, then `wsusutil reset`, and prints `RESTORE COMPLETE` (`Scripts/Invoke-WsusManagement.ps1:500-642`).
- Current-state caveat: `ErrorActionPreference` in `Invoke-WsusManagement.ps1` is `Continue`, so some failures can log/return without a nonzero exit; GUI status is based on child process exit code.

## Mermaid flowchart
```mermaid
flowchart TD
  B["Boundary: Feature 5 air-gap import/export/restore<br/>PATHFINDER-2026-06-15/00-features.md:74"] --> G0["GUI operation switch chooses restore or transfer<br/>Scripts/WsusManagementGui.ps1:3119"]
  B --> C0["CLI switches Restore/Import/Export declared<br/>Scripts/Invoke-WsusManagement.ps1:77"]
  G0 --> GR1["Restore dialog returns confirmed BackupPath<br/>Scripts/WsusManagementGui.ps1:2064"]
  GR1 --> GR2["GUI validates BackupPath with Test-SafePath<br/>Scripts/WsusManagementGui.ps1:3122"]
  GR2 --> GR3["Resolve-WsusRestoreBackup checks .bak path<br/>Modules/WsusProvisioning.psm1:73"]
  GR3 --> GR4["New-WsusManagementOperationPlan builds -Restore command<br/>Modules/WsusOperationPlan.psm1:78"]
  GR4 --> RUN["Start-WsusOperation launches powershell.exe child<br/>Modules/WsusOperationRunner.psm1:250"]
  G0 --> GT1["Transfer dialog returns SourcePath and DestinationPath<br/>Scripts/WsusManagementGui.ps1:2804"]
  GT1 --> GT2["GUI validates both paths with Test-SafePath<br/>Scripts/WsusManagementGui.ps1:3142"]
  GT2 --> GT3["New-WsusTransferOperationPlan builds direct robocopy command<br/>Modules/WsusOperationPlan.psm1:161"]
  GT3 --> RUN
  C0 --> CE1["-Export normalizes actual source and destination<br/>Scripts/Invoke-WsusManagement.ps1:2033"]
  CE1 --> CE2["Invoke-ExportToMedia validates source and scans .bak/WsusContent<br/>Scripts/Invoke-WsusManagement.ps1:1347"]
  CE2 --> CE3["Destination path validated and created if missing<br/>Scripts/Invoke-WsusManagement.ps1:1456"]
  CE3 --> CE4["Copy-Item copies newest database backup<br/>Scripts/Invoke-WsusManagement.ps1:1489"]
  CE4 --> TP1["New-WsusTransferPlan maps source\\WsusContent to destination\\WsusContent<br/>Modules/WsusExport.psm1:378"]
  TP1 --> RC1["Invoke-WsusRobocopy runs robocopy.exe for content<br/>Modules/WsusExport.psm1:26"]
  RC1 --> CE5["Export terminal status COPY COMPLETE and next steps<br/>Scripts/Invoke-WsusManagement.ps1:1532"]
  C0 --> CI1["-Import chooses SourcePath or ExportRoot and calls Invoke-CopyForAirGap<br/>Scripts/Invoke-WsusManagement.ps1:2029"]
  CI1 --> CI2["Invoke-CopyForAirGap validates source container<br/>Scripts/Invoke-WsusManagement.ps1:1061"]
  CI2 --> CI3["Invoke-FullCopy locates root or archive .bak/WsusContent<br/>Scripts/Invoke-WsusManagement.ps1:764"]
  CI3 --> CI4["Copy-ToDestination creates destination and copies .bak<br/>Scripts/Invoke-WsusManagement.ps1:664"]
  CI4 --> TP2["New-WsusTransferPlan maps import content destination<br/>Modules/WsusExport.psm1:397"]
  TP2 --> RC1
  RC1 --> CI5["Import terminal status COPY COMPLETE; next step restore<br/>Scripts/Invoke-WsusManagement.ps1:840"]
  RUN --> SR1["Management script imports config/export/provisioning modules<br/>Scripts/Invoke-WsusManagement.ps1:199"]
  SR1 --> SR2["Invoke-WsusRestore checks sysadmin and sqlcmd<br/>Scripts/Invoke-WsusManagement.ps1:500"]
  SR2 --> SR3["RESTORE VERIFYONLY WITH CHECKSUM<br/>Scripts/Invoke-WsusManagement.ps1:564"]
  SR3 --> SR4["Stop WSUSService and W3SVC<br/>Scripts/Invoke-WsusManagement.ps1:577"]
  SR4 --> SR5["ALTER SINGLE_USER, RESTORE DATABASE SUSDB, ALTER MULTI_USER<br/>Scripts/Invoke-WsusManagement.ps1:584"]
  SR5 --> SR6["Start services, wsusutil postinstall, wsusutil reset<br/>Scripts/Invoke-WsusManagement.ps1:610"]
  SR6 --> SR7["Restore terminal status RESTORE COMPLETE and OK lines<br/>Scripts/Invoke-WsusManagement.ps1:639"]
  SR7 --> DONE["Complete-WsusOperation sets Completed/Failed status<br/>Modules/WsusOperationRunner.psm1:129"]
  GT3 --> DONE
  DONE --> UI["Set-WsusGuiOperationUiState writes final StatusLabel<br/>Modules/WsusGuiShell.psm1:151"]
```

## External dependencies
- `powershell.exe` child process.
- `robocopy.exe` for direct GUI transfer and CLI import/export content movement.
- `sqlcmd.exe` for backup verification and SUSDB restore.
- SQL Server instance containing `SUSDB`, with current user sysadmin rights.
- Windows services `WSUSService` and `W3SVC` during restore.
- `wsusutil.exe` for postinstall and reset/content re-verification.
- Filesystem/external media or UNC paths.
- Optional GUI notification/history/secret cleanup modules on completion.

## Confidence
- High for current-state happy path through GUI restore/transfer, CLI import/export, robocopy placement, SUSDB restore, and GUI terminal status.
- Gap: no runtime execution; non-happy-path exit-code behavior is a current-state caveat only.
