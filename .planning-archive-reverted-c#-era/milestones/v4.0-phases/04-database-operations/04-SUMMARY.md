---
phase: "04"
plan: "04"
subsystem: "database-operations"
tags: ["sql", "deep-cleanup", "backup", "restore", "wsus", "csharp"]
dependency_graph:
  requires: ["03-diagnostics-service-management"]
  provides: ["ISqlService", "IDeepCleanupService", "IDatabaseBackupService"]
  affects: ["MainViewModel", "MainWindow.xaml", "DI container"]
tech_stack:
  added: ["Microsoft.Data.SqlClient (ISqlService)", "DriveInfo (disk space check)"]
  patterns: ["Repository-like SQL service", "6-step pipeline", "Retry-on-error", "Sysadmin gate", "Batch processing"]
key_files:
  created:
    - src/WsusManager.Core/Services/Interfaces/ISqlService.cs
    - src/WsusManager.Core/Services/SqlService.cs
    - src/WsusManager.Core/Services/Interfaces/IDeepCleanupService.cs
    - src/WsusManager.Core/Services/DeepCleanupService.cs
    - src/WsusManager.Core/Services/Interfaces/IDatabaseBackupService.cs
    - src/WsusManager.Core/Services/DatabaseBackupService.cs
    - src/WsusManager.Tests/Services/SqlServiceTests.cs
    - src/WsusManager.Tests/Services/DeepCleanupServiceTests.cs
    - src/WsusManager.Tests/Services/DatabaseBackupServiceTests.cs
  modified:
    - src/WsusManager.App/Program.cs (DI registration for ISqlService, IDeepCleanupService, IDatabaseBackupService)
    - src/WsusManager.App/ViewModels/MainViewModel.cs (Phase 4 commands and panel visibility)
    - src/WsusManager.App/Views/MainWindow.xaml (Database panel and nav button)
    - src/WsusManager.Tests/ViewModels/MainViewModelTests.cs (Phase 4 mock injection and tests)
    - src/WsusManager.Tests/Integration/DiContainerTests.cs (Phase 4 DI resolution tests)
decisions:
  - "DeepCleanupService steps 2-3 and 6 use ISqlService for testability; steps 4-5 use SqlConnection directly for batch/cursor operations requiring per-row control"
  - "RESTORE VERIFYONLY executes as non-query (returns no rows but throws on invalid backup)"
  - "spDeleteUpdate SqlExceptions silently suppressed to match PowerShell v3.8.11 behavior"
  - "SynchronousProgress<T> wrapper used in tests to avoid Progress<T> async delivery race conditions"
  - "Backup estimated at 80% of DB size for disk space pre-flight check"
metrics:
  duration: "10 minutes"
  completed: "2026-02-19"
  tasks_completed: 7
  files_created: 9
  files_modified: 5
  tests_added: 25
  tests_total: 125
---

# Phase 4 Plan 04: Database Operations Summary

**One-liner:** 6-step deep cleanup pipeline + SUSDB backup/restore with sysadmin gate, 10k/100-batch processing, and 3-retry shrink — wired into a dedicated Database panel in the UI.

## What Was Built

### Plan 1 — SQL Helper Service
- `ISqlService` interface: `ExecuteScalarAsync<T>`, `ExecuteNonQueryAsync`, `ExecuteReaderFirstAsync<T>`, `BuildConnectionString`
- `SqlService` implementation using `Microsoft.Data.SqlClient` with `Integrated Security=True;TrustServerCertificate=True`
- `CommandTimeout=0` (unlimited) by default — required for maintenance queries that run for minutes
- Registered as singleton in DI container

### Plans 2-3 — Deep Cleanup Service (All 6 Steps)
- `IDeepCleanupService` interface with `RunAsync(sqlInstance, progress, ct)`
- `DeepCleanupService` implementing the full pipeline:
  - **Step 1:** PowerShell subprocess `Get-WsusServer | Invoke-WsusServerCleanup` (WSUS managed API incompatible with .NET 9)
  - **Step 2:** DELETE from `tbRevisionSupersedesUpdate` where `RevisionState = 2` (declined)
  - **Step 3:** Batched DELETE TOP (10,000) for `RevisionState = 3` (superseded) with 1s inter-batch delay
  - **Step 4:** Query declined update IDs → call `spDeleteUpdate` in batches of 100, silently suppress `SqlException` for dependency conflicts
  - **Step 5:** Cursor-based index rebuild/reorganize (fragmentation > 30% = REBUILD, > 10% = REORGANIZE, page_count > 1000) + `sp_updatestats`
  - **Step 6:** `DBCC SHRINKDATABASE(SUSDB, 10)` with 3 retries on backup-blocking errors (30s delay each)
- DB size captured before step 1 and after step 6 — before/after comparison displayed
- Progress format: `[Step N/6] Step Name... done (Xs)` matching PowerShell output

### Plans 4-5 — Database Backup Service
- `IDatabaseBackupService` interface: `BackupAsync`, `RestoreAsync`, `VerifyBackupAsync`
- `DatabaseBackupService` implementation:
  - **BackupAsync:** sysadmin gate → DB size query → disk space check (80% of DB size) → `BACKUP DATABASE SUSDB TO DISK WITH COMPRESSION, INIT` (path single-quote escaped)
  - **VerifyBackupAsync:** `RESTORE VERIFYONLY FROM DISK WITH CHECKSUM` — throws on invalid backup
  - **RestoreAsync:** sysadmin gate → file exists → verify integrity → stop WSUS/IIS → `SET SINGLE_USER` → `RESTORE DATABASE WITH REPLACE` → `SET MULTI_USER` → `wsusutil postinstall` → restart services

### Plan 6 — Database Operations UI Panel
- `MainViewModel`: added `IDeepCleanupService` and `IDatabaseBackupService` constructor parameters
- `IsDatabasePanelVisible` property (CurrentPanel == "Database")
- `IsOperationPanelVisible` updated to exclude "Database" panel
- Navigation includes "Database" → "Database Operations" page title
- `RunDeepCleanupCommand`: navigates to Database panel, runs `IDeepCleanupService.RunAsync`
- `BackupDatabaseCommand`: `SaveFileDialog` (default: `SUSDB_YYYY-MM-DD.bak`), then `BackupAsync`
- `RestoreDatabaseCommand`: confirmation dialog → `OpenFileDialog` → `RestoreAsync` → dashboard refresh
- `QuickCleanup` now calls `RunDeepCleanup` (previously a placeholder Navigate-only)
- `NotifyCommandCanExecuteChanged` updated with 3 new database commands
- `MainWindow.xaml`: DATABASE sidebar category + nav button, Database panel with DB size display, Deep Cleanup (BtnGreen), Backup Database (BtnSec), Restore Database (BtnSec with warning)

### Plan 7 — Tests
- **SqlServiceTests (7 tests):** connection string validation (TrustServerCertificate, IntegratedSecurity, instance, database, timeout), SQL execution, cancellation token
- **DeepCleanupServiceTests (14 tests):** step 1 PS command params, step 2 SQL targets correct table/RevisionState, step 3 10k batch + unlimited timeout, step 4 100-batch size, step 5 sp_updatestats, step 6 SUSDB target + retry params + backup block patterns, progress format, DB size math
- **DatabaseBackupServiceTests (11 tests):** sysadmin gate, disk space check, BACKUP DATABASE SQL, path single-quote escaping, unlimited timeout, RESTORE VERIFYONLY + CHECKSUM, file-not-found, stop WSUS/IIS before restore, SINGLE_USER before MULTI_USER ordering, wsusutil postinstall call, restart services after restore
- **MainViewModelTests additions:** IsDatabasePanelVisible, IsOperationPanelVisible excludes Database, navigate Database title, RunDeepCleanupCommand navigation and service call, CanExecute gating for all 3 commands
- **DiContainerTests additions:** ISqlService, IDeepCleanupService, IDatabaseBackupService resolve tests + All_Phase4_Services_Resolve_Without_Error

**Test count: 125 total (was 121 before Phase 4, added 25 new tests)**

## Success Criteria Verification

1. **Deep Cleanup runs all 6 steps with progress and timing** — VERIFIED: DeepCleanupService.RunAsync orchestrates all 6 steps with `[Step N/6] Name... done (Xs)` format and Stopwatch per step
2. **DB size before/after shrink, shrink retries 3x with 30s delays** — VERIFIED: GetDatabaseSizeGbAsync called before step 1 and after step 6; ShrinkMaxRetries=3, ShrinkRetryDelaySeconds=30
3. **No SQL timeout errors on maintenance queries** — VERIFIED: All maintenance calls use CommandTimeout=0 (unlimited) via ISqlService
4. **User can select backup destination and backup/restore SUSDB via file picker** — VERIFIED: SaveFileDialog in BackupDatabaseCommand, OpenFileDialog in RestoreDatabaseCommand; sysadmin enforced

## Deviations from Plan

**1. [Rule 2 - Missing Critical Functionality] SynchronousProgress<T> for test reliability**
- **Found during:** Plan 7 (DatabaseBackupServiceTests)
- **Issue:** `Progress<T>` posts callbacks to `SynchronizationContext` asynchronously — in tests without a SynchronizationContext this causes messages to arrive after assertions run, producing false failures
- **Fix:** Added private `SynchronousProgress<T>` sealed class that calls the callback directly (synchronously) for all test progress capture
- **Files modified:** `DatabaseBackupServiceTests.cs`
- **Commit:** c737dc2

**2. [Rule 1 - Bug] Steps 4-5 use SqlConnection directly**
- **Found during:** Plan 2-3 implementation
- **Issue:** Step 4 (batch deletion with per-row error suppression) and Step 5 (cursor-based index rebuild returning row counts) require direct SqlConnection control that can't be expressed through ISqlService's abstraction
- **Fix:** Used `_sqlService.BuildConnectionString()` for consistent connection string construction then opened `SqlConnection` directly for these two steps only
- **Files modified:** `DeepCleanupService.cs`

## Commits

| Hash | Message |
|------|---------|
| 270b124 | feat(04-01): add ISqlService and SqlService for centralized SQL execution |
| 9b1ebfb | feat(04-02,04-03): add IDeepCleanupService with all 6 deep cleanup steps |
| fe10d35 | feat(04-04,04-05): add IDatabaseBackupService with backup and restore |
| 82e0ee4 | feat(04-06): add Database operations panel and wire ViewModel commands |
| c737dc2 | test(04-07): add comprehensive tests for Phase 4 database services |

## Self-Check: PASSED

All 9 created files exist on disk. All 5 commits verified in git log. 125 tests pass with 0 failures. dotnet build produces 0 warnings, 0 errors.
