# Phase 4: Database Operations - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Administrators can run the full 6-step deep cleanup pipeline, backup the SUSDB database to a selected path, and restore from a backup file. Sysadmin permissions are enforced before any database operation. This phase does NOT cover sync, export/import, or installation — those are Phases 5 and 6.

</domain>

<decisions>
## Implementation Decisions

### Deep Cleanup Pipeline (6 Steps)
- All 6 steps run sequentially matching PowerShell v3.8 exactly:
  1. Decline superseded updates (WSUS API via `IUpdateServer.GetUpdates()` or direct SQL)
  2. Remove supersession records for declined updates (single SQL batch)
  3. Remove supersession records for superseded updates (batched: 10,000 records per batch)
  4. Delete declined updates via `spDeleteUpdate` stored proc (batched: 100 per batch)
  5. Rebuild/reorganize fragmented indexes + update statistics
  6. Shrink database (`DBCC SHRINKDATABASE(SUSDB, 10)`)
- Each step reports: step name, elapsed time, and result to log panel via `IProgress<string>`
- DB size displayed before step 1 and after step 6 so user sees space reclaimed
- All SQL queries use unlimited command timeout (0) — maintenance queries can run 30+ minutes on large SUSDB
- Shrink retry: 3 attempts with 30-second delays when blocked by backup/file operations (matching `Invoke-WsusDatabaseShrink` pattern)
- `spDeleteUpdate` errors for updates with revision dependencies are silently suppressed (expected behavior, matching PS v3.8.11 fix)

### Sysadmin Permission Enforcement
- Hard block (not just warning) before Deep Cleanup, Backup, and Restore operations
- Check `IPermissionsService.CheckSqlSysadminAsync()` (already built in Phase 3)
- Display clear error: "Current user does not have sysadmin permissions on SQL Server. Database operations require sysadmin access."
- Do not proceed — return early with failure result
- This upgrades Phase 3's informational Warning to an actual gate for DB operations

### Backup Workflow
- User clicks "Backup Database" → file save dialog opens (SaveFileDialog)
- Default directory: `C:\WSUS` (standard WSUS content path)
- Default filename: `SUSDB_YYYY-MM-DD.bak`
- Filter: `*.bak` files
- Pre-flight: Check disk space before backup (estimate backup at 80% of DB size, matching `Get-WsusDiskSpace`)
- Backup via: `BACKUP DATABASE SUSDB TO DISK = N'{path}' WITH COMPRESSION, INIT`
- Stream progress to log panel. Report backup duration and file size on completion.

### Restore Workflow
- User clicks "Restore Database" → confirmation dialog first: "This will replace the current SUSDB database. All current data will be lost. Continue?"
- If confirmed → file open dialog (OpenFileDialog) defaulting to `C:\WSUS`, filter `*.bak`
- Validate backup file using `RESTORE VERIFYONLY` before restoring (matching `Test-WsusBackupIntegrity`)
- Stop WSUS and IIS services before restore (SQL must stay running), restore via `RESTORE DATABASE SUSDB FROM DISK = N'{path}' WITH REPLACE`
- Restart WSUS and IIS after restore completes
- Report success/failure with duration in log panel

### Database Operations UI Integration
- Add "Database" navigation item in sidebar (separate from Diagnostics)
- Database panel contains: "Deep Cleanup" button (BtnGreen), "Backup Database" button (BtnSec), "Restore Database" button (BtnSec with warning styling)
- Current DB size displayed at top of panel (pulled from dashboard data)
- All operations use existing `RunOperationAsync` pattern — buttons disabled during operation, log panel auto-expands

### Claude's Discretion
- Whether to use WSUS managed API or direct SQL for declining superseded updates in step 1 (direct SQL preferred for .NET 9 compatibility)
- Exact SQL queries for index rebuild/reorganize — can use same pattern as PowerShell or optimize
- Whether to wrap backup/restore in a transaction or rely on SQL Server's built-in atomicity
- Internal service interface naming (e.g., `IDatabaseService`, `IDeepCleanupService`, or combined)

</decisions>

<specifics>
## Specific Ideas

- Match PowerShell v3.8.11 deep cleanup output format: each step shows "[Step N/6] Step Name... done (Xs)" with timing
- Batch deletion progress: "Deleted X supersession records..." and "Deleted X/Y declined updates..." inline
- Before/after DB size: "Database size: X.XX GB → Y.YY GB (saved Z.ZZ GB)"
- The `Invoke-WsusSqlcmd` wrapper in PowerShell auto-detects SqlServer module version for TrustServerCertificate — C# should use `TrustServerCertificate=true` in connection string (internal SQL Express, self-signed cert is expected)

</specifics>

<deferred>
## Deferred Ideas

- Database integrity check (`DBCC CHECKDB`) — could be Phase 7 polish item
- Automated backup scheduling — Phase 6 handles scheduling
- Database migration/upgrade tooling — out of scope for v4.0

</deferred>

---

*Phase: 04-database-operations*
*Context gathered: 2026-02-20*
