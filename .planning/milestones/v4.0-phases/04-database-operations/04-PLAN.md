# Phase 4: Database Operations — Plan

**Created:** 2026-02-19
**Requirements:** DB-01, DB-02, DB-03, DB-04, DB-05, DB-06
**Goal:** Administrators can run the full 6-step deep cleanup pipeline, backup the SUSDB database to a selected path, and restore from a backup file. Sysadmin permissions are enforced before any database operation.

---

## Plans

### Plan 1: SQL helper service and connection management

**What:** Create `ISqlService` and its implementation for executing SQL queries against SUSDB. This centralizes all SQL connection string construction, timeout management, and TrustServerCertificate handling into a single service — eliminating inline `SqlConnection` construction scattered across services. Provides methods for scalar queries, non-queries, and reader-based batch operations. All methods accept `CancellationToken` and configurable `CommandTimeout` (default: unlimited for maintenance queries).

**Requirements covered:** Foundation for DB-01 through DB-06

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/ISqlService.cs` — Interface with:
  - `Task<T?> ExecuteScalarAsync<T>(string sqlInstance, string database, string query, int commandTimeoutSeconds = 0, CancellationToken ct = default)`
  - `Task<int> ExecuteNonQueryAsync(string sqlInstance, string database, string query, int commandTimeoutSeconds = 0, CancellationToken ct = default)`
  - `Task<OperationResult<T>> ExecuteReaderFirstAsync<T>(string sqlInstance, string database, string query, Func<System.Data.IDataReader, T> mapper, int commandTimeoutSeconds = 0, CancellationToken ct = default)`
  - `string BuildConnectionString(string sqlInstance, string database, int connectTimeoutSeconds = 5)`
- `src/WsusManager.Core/Services/SqlService.cs` — Implementation using `Microsoft.Data.SqlClient`. Connection string always includes `Integrated Security=True;TrustServerCertificate=True`. Wraps all operations in try/catch returning `OperationResult` where appropriate. Logs query execution via `ILogService`.

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `ISqlService` in DI

**Verification:**
1. Unit test: `ExecuteScalarAsync` returns value from mock connection
2. Unit test: `BuildConnectionString` includes `TrustServerCertificate=True` and `Integrated Security=True`
3. Unit test: `ExecuteNonQueryAsync` passes through command timeout correctly
4. `dotnet build` succeeds with zero warnings

---

### Plan 2: Deep cleanup service — decline superseded and remove supersession records (steps 1–3)

**What:** Create `IDeepCleanupService` and begin its implementation with the first 3 of 6 deep cleanup steps. Step 1 runs WSUS built-in cleanup by calling `Invoke-WsusServerCleanup` via `IProcessRunner` (PowerShell command, since the WSUS managed API is incompatible with .NET 9). Step 2 removes supersession records for declined updates (single SQL batch via `ISqlService`). Step 3 removes supersession records for superseded updates in batches of 10,000 (matching `Remove-SupersededSupersessionRecords` from `WsusDatabase.psm1`). Each step reports progress with step number, name, and elapsed time via `IProgress<string>`.

**Requirements covered:** DB-01 (steps 1–3), DB-02 (progress/timing), DB-03 (10k batch for supersession)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IDeepCleanupService.cs` — Interface with:
  - `Task<OperationResult> RunAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)`
- `src/WsusManager.Core/Services/DeepCleanupService.cs` — Implementation. Constructor injects `ISqlService`, `IProcessRunner`, `IWindowsServiceManager`, `ILogService`. `RunAsync` orchestrates all 6 steps (steps 4–6 implemented in Plan 3). Steps 1–3:
  - **Step 1 — WSUS built-in cleanup:** Run PowerShell command `Get-WsusServer -Name localhost -PortNumber 8530 | Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -CompressUpdates -DeclineSupersededUpdates` via `IProcessRunner`. Report output lines to progress.
  - **Step 2 — Remove declined supersession records:** Execute SQL matching `Remove-DeclinedSupersessionRecords` from `WsusDatabase.psm1` (DELETE from `tbRevisionSupersedesUpdate` WHERE revision state = 2). Report count deleted.
  - **Step 3 — Remove superseded supersession records (batched):** Execute SQL matching `Remove-SupersededSupersessionRecords` with `DELETE TOP (10000)` loop (revision state = 3, 1-second delay between batches, unlimited timeout). Report total count deleted.
  - Format: `[Step N/6] Step Name... done (Xs)` matching PowerShell output format.

**Verification:**
1. Unit test: Step 1 calls ProcessRunner with correct PowerShell command
2. Unit test: Step 2 executes correct SQL DELETE query on `tbRevisionSupersedesUpdate` with state = 2
3. Unit test: Step 3 uses batched SQL (10k batch size) with unlimited command timeout
4. Unit test: Each step reports progress with `[Step N/6]` format and elapsed time
5. `dotnet build` succeeds

---

### Plan 3: Deep cleanup service — delete declined, rebuild indexes, shrink DB (steps 4–6)

**What:** Complete the deep cleanup pipeline with steps 4–6. Step 4 deletes declined updates from the database using `spDeleteUpdate` stored procedure in batches of 100 (matching PowerShell). Step 5 rebuilds/reorganizes fragmented indexes and updates statistics (matching `Optimize-WsusIndexes` and `Update-WsusStatistics`). Step 6 shrinks the database with retry logic (3 attempts, 30-second delays when blocked by backup operations, matching `Invoke-WsusDatabaseShrink`). DB size is captured before step 1 and after step 6 for the before/after size report.

**Requirements covered:** DB-01 (steps 4–6), DB-02 (progress/timing), DB-03 (100/batch for declined), DB-04 (shrink retry)

**Files to modify:**
- `src/WsusManager.Core/Services/DeepCleanupService.cs` — Add steps 4–6:
  - **Step 4 — Delete declined updates:** Query declined update IDs via SQL (SELECT from `tbUpdate`/`tbRevision` WHERE state = 2). For each update in batches of 100, call `spDeleteUpdate` via parameterized SQL. Silently suppress errors for updates with revision dependencies (matching PS v3.8.11 fix). Report batch progress: `Deleted X/Y declined updates...`
  - **Step 5 — Rebuild indexes + update statistics:** Execute cursor-based SQL matching `Optimize-WsusIndexes` (fragmentation > 30% = rebuild, > 10% = reorganize, page_count > 1000). Then execute `sp_updatestats`. Report counts: `Rebuilt: X, Reorganized: Y`.
  - **Step 6 — Shrink database:** Get DB size before shrink. Execute `DBCC SHRINKDATABASE(SUSDB, 10) WITH NO_INFOMSGS`. Retry up to 3 times with 30-second delays when error message matches `serialized|backup.*operation|file manipulation`. Get DB size after. Report: `Database size: X.XX GB -> Y.YY GB (saved Z.ZZ GB)`.
  - Also: capture DB size before step 1 and display at start. Display final size after step 6 with before/after comparison.

**Verification:**
1. Unit test: Step 4 uses `spDeleteUpdate` with batches of 100
2. Unit test: Step 4 silently suppresses `SqlException` for dependency errors
3. Unit test: Step 5 executes index optimization SQL and `sp_updatestats`
4. Unit test: Step 6 retries 3 times with 30s delay on backup-blocked error
5. Unit test: Step 6 reports before/after DB size
6. Unit test: Full pipeline runs all 6 steps in sequence with timing
7. `dotnet build` succeeds

---

### Plan 4: Database backup service

**What:** Create `IDatabaseBackupService` with backup functionality. User provides a destination file path. Pre-flight checks verify disk space (estimate backup at 80% of DB size). Backup uses `BACKUP DATABASE SUSDB TO DISK = N'{path}' WITH COMPRESSION, INIT` via `ISqlService` with unlimited timeout. Reports backup duration and file size on completion. Sysadmin check gates the operation.

**Requirements covered:** DB-05 (backup SUSDB)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IDatabaseBackupService.cs` — Interface with:
  - `Task<OperationResult> BackupAsync(string sqlInstance, string backupPath, IProgress<string> progress, CancellationToken ct)`
  - `Task<OperationResult> RestoreAsync(string sqlInstance, string backupPath, string contentPath, IProgress<string> progress, CancellationToken ct)`
  - `Task<OperationResult<bool>> VerifyBackupAsync(string sqlInstance, string backupPath, CancellationToken ct)`
- `src/WsusManager.Core/Services/DatabaseBackupService.cs` — Implementation. Constructor injects `ISqlService`, `IPermissionsService`, `IWindowsServiceManager`, `IProcessRunner`, `ILogService`. `BackupAsync`:
  1. Check sysadmin permission via `IPermissionsService.CheckSqlSysadminAsync` — hard block if not sysadmin
  2. Get current DB size for disk space estimate
  3. Check disk free space on backup destination drive (backup estimated at 80% of DB size)
  4. Execute `BACKUP DATABASE SUSDB TO DISK = N'{safePath}' WITH COMPRESSION, INIT` (path single-quotes escaped)
  5. Report success with backup file size and duration

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IDatabaseBackupService` and `IDeepCleanupService` in DI

**Verification:**
1. Unit test: `BackupAsync` blocks when user is not sysadmin
2. Unit test: `BackupAsync` checks disk space before backup
3. Unit test: `BackupAsync` executes correct BACKUP DATABASE SQL
4. Unit test: Backup path is sanitized (single quotes escaped)
5. `dotnet build` succeeds

---

### Plan 5: Database restore service

**What:** Implement `RestoreAsync` and `VerifyBackupAsync` in `DatabaseBackupService`. Restore workflow: verify backup file with `RESTORE VERIFYONLY`, stop WSUS and IIS services (SQL stays running), set database to single-user mode, execute `RESTORE DATABASE SUSDB FROM DISK WITH REPLACE`, set database back to multi-user mode, run wsusutil postinstall, restart WSUS and IIS, optionally run wsusutil reset. Sysadmin check gates the operation.

**Requirements covered:** DB-06 (restore SUSDB from file picker)

**Files to modify:**
- `src/WsusManager.Core/Services/DatabaseBackupService.cs` — Implement:
  - `VerifyBackupAsync`: Execute `RESTORE VERIFYONLY FROM DISK = N'{path}' WITH CHECKSUM` — returns success/failure
  - `RestoreAsync`:
    1. Check sysadmin permission — hard block if not sysadmin
    2. Verify backup file exists on disk
    3. Verify backup integrity via `VerifyBackupAsync`
    4. Stop WSUS and IIS services via `IWindowsServiceManager` (SQL must stay running)
    5. Set SUSDB to single-user: `ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE`
    6. Execute `RESTORE DATABASE SUSDB FROM DISK = N'{path}' WITH REPLACE`
    7. Set SUSDB to multi-user: `ALTER DATABASE SUSDB SET MULTI_USER`
    8. Run `wsusutil.exe postinstall SQL_INSTANCE_NAME="{instance}" CONTENT_DIR="{contentPath}"` via `IProcessRunner`
    9. Restart WSUS and IIS services
    10. Report success with duration

**Verification:**
1. Unit test: `RestoreAsync` blocks when user is not sysadmin
2. Unit test: `RestoreAsync` verifies backup integrity before restoring
3. Unit test: `RestoreAsync` stops WSUS and IIS but not SQL before restore
4. Unit test: `RestoreAsync` sets database to single-user before restore and multi-user after
5. Unit test: `RestoreAsync` runs wsusutil postinstall after restore
6. Unit test: `RestoreAsync` restarts WSUS and IIS after restore
7. Unit test: `VerifyBackupAsync` executes RESTORE VERIFYONLY
8. `dotnet build` succeeds

---

### Plan 6: Database operations UI panel and ViewModel wiring

**What:** Add the Database operations panel to the main window and wire ViewModel commands. Database panel has three operations: Deep Cleanup, Backup Database, Restore Database. The panel shows current DB size at the top (from dashboard data). Deep Cleanup navigates to the Database panel and runs the full 6-step pipeline. Backup opens a SaveFileDialog (default: `C:\WSUS\SUSDB_YYYY-MM-DD.bak`). Restore shows a confirmation dialog, then opens an OpenFileDialog (default: `C:\WSUS`, filter: `*.bak`). All operations go through `RunOperationAsync`.

**Requirements covered:** DB-01, DB-02, DB-03, DB-04, DB-05, DB-06 (UI integration)

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameters for `IDeepCleanupService` and `IDatabaseBackupService`
  - `IsDatabasePanelVisible` — Visibility property for Database panel
  - `RunDeepCleanupCommand` — Sysadmin gate, navigate to "Database", run `IDeepCleanupService.RunAsync` through `RunOperationAsync`
  - `BackupDatabaseCommand` — SaveFileDialog, sysadmin gate, run `IDatabaseBackupService.BackupAsync` through `RunOperationAsync`
  - `RestoreDatabaseCommand` — Confirmation dialog, OpenFileDialog, sysadmin gate, run `IDatabaseBackupService.RestoreAsync` through `RunOperationAsync`, refresh dashboard after
  - Update `Navigate` to include "Database" panel
  - Update `NotifyCommandCanExecuteChanged` with new commands
  - Wire `QuickCleanup` to execute `RunDeepCleanupCommand` directly (replaces placeholder)
- `src/WsusManager.App/Views/MainWindow.xaml` — Add Database panel:
  - Database panel (Visibility bound to `IsDatabasePanelVisible`)
  - Current DB size display at top of panel
  - "Deep Cleanup" button (BtnGreen style)
  - "Backup Database" button (BtnSec style)
  - "Restore Database" button (BtnSec style with warning text)
  - Add "Database" navigation item in sidebar
- Update navigation visibility to include Database panel exclusion in `IsOperationPanelVisible`

**Verification:**
1. Clicking "Deep Cleanup" runs the 6-step pipeline and outputs progress to log panel
2. "Backup Database" opens SaveFileDialog and runs backup
3. "Restore Database" shows confirmation, then OpenFileDialog, then runs restore
4. All operations disable buttons during execution (existing `RunOperationAsync` guard)
5. Dashboard refreshes after restore to reflect new DB state
6. Quick Cleanup button now runs the actual deep cleanup pipeline
7. `dotnet build` succeeds

---

### Plan 7: Tests and integration verification

**What:** Add comprehensive unit tests for all Phase 4 services and ViewModel commands. Verify all success criteria. Update DI container tests to verify new service registrations.

**Requirements covered:** All Phase 4 requirements (verification)

**Files to create:**
- `src/WsusManager.Tests/Services/SqlServiceTests.cs` — Tests: connection string construction, scalar execution, non-query execution, timeout handling
- `src/WsusManager.Tests/Services/DeepCleanupServiceTests.cs` — Tests: all 6 steps run in sequence, batched deletion (10k and 100), shrink retry logic, progress format matches `[Step N/6]`, DB size before/after, spDeleteUpdate error suppression, step timing reported
- `src/WsusManager.Tests/Services/DatabaseBackupServiceTests.cs` — Tests: sysadmin gate (backup and restore), disk space check before backup, backup SQL command, restore workflow (verify, stop services, single-user, restore, multi-user, postinstall, restart), backup path sanitization

**Files to modify:**
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` — Add tests: RunDeepCleanup command wired, BackupDatabase command wired, RestoreDatabase command wired, Database panel visibility, QuickCleanup runs deep cleanup
- `src/WsusManager.Tests/Integration/DiContainerTests.cs` — Add resolution tests for ISqlService, IDeepCleanupService, IDatabaseBackupService

**Verification:**
1. `dotnet build` — 0 warnings, 0 errors
2. `dotnet test` — All tests pass (existing + new)
3. All 4 Phase 4 success criteria verified in tests:
   - Deep Cleanup runs all 6 steps with progress and timing
   - DB size before/after shrink with retry logic
   - No SQL timeout errors (unlimited timeout on maintenance queries)
   - Backup and restore via file picker with sysadmin enforcement

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | SQL helper service and connection management | Foundation for DB-01–DB-06 |
| 2 | Deep cleanup steps 1–3 (WSUS cleanup, remove supersession records) | DB-01, DB-02, DB-03 |
| 3 | Deep cleanup steps 4–6 (delete declined, rebuild indexes, shrink) | DB-01, DB-02, DB-03, DB-04 |
| 4 | Database backup service | DB-05 |
| 5 | Database restore service | DB-06 |
| 6 | Database operations UI panel and ViewModel wiring | DB-01–DB-06 (UI) |
| 7 | Tests and integration verification | All Phase 4 (verification) |

## Execution Order

Plans 1 through 7 execute sequentially. Each plan builds on the previous:
- Plan 1 creates the SQL helper that Plans 2–5 use for all database queries
- Plans 2–3 build the deep cleanup pipeline (split into two plans for manageable scope)
- Plans 4–5 build the backup/restore services (backup first since restore depends on verify)
- Plan 6 wires everything into the UI
- Plan 7 adds tests and verifies all success criteria

## Success Criteria (from Roadmap)

All four Phase 4 success criteria must be TRUE after Plan 7 completes:

1. Deep Cleanup runs all 6 steps in sequence, reporting progress and elapsed time for each step in the log panel, with batched deletion (10k/batch for supersession records, 100/batch for declined updates)
2. DB size is displayed before and after the shrink step, and the shrink retries automatically (up to 3 times with 30-second delays) when blocked by an active backup operation
3. Deep Cleanup completes on a production SUSDB without SQL timeout errors — all maintenance queries run with unlimited command timeout
4. User can select a backup destination and successfully back up the SUSDB — and can restore it from a backup file selected via a file picker dialog

---

*Phase: 04-database-operations*
*Plan created: 2026-02-19*
