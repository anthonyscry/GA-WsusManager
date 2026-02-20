# Phase 5: WSUS Operations — Plan

**Created:** 2026-02-19
**Requirements:** SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05, XFER-01, XFER-02, XFER-03, XFER-04, XFER-05
**Goal:** Administrators can run Online Sync with profile selection, export WSUS data to media (full and differential), import from USB or network share, and reset content after an air-gap import — covering the full air-gap maintenance workflow end-to-end.

---

## Plans

### Plan 1: WSUS server connection service

**What:** Create `IWsusServerService` and its implementation for connecting to the local WSUS server via the `Microsoft.UpdateServices.Administration` managed API. The assembly ships with the WSUS role at `%ProgramFiles%\Update Services\Api\Microsoft.UpdateServices.Administration.dll` — it must be loaded at runtime via `Assembly.LoadFrom` since it is not a NuGet package. The service provides access to the `IUpdateServer` object, subscription status, sync progress, update retrieval, and update approval. All methods return `OperationResult` for consistent error handling. This service is the foundation for sync and approval operations.

**Requirements covered:** Foundation for SYNC-01 through SYNC-05

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IWsusServerService.cs` — Interface with:
  - `Task<OperationResult> ConnectAsync(CancellationToken ct = default)` — Load WSUS API assembly and connect to localhost:8530
  - `Task<OperationResult> StartSynchronizationAsync(IProgress<string>? progress, CancellationToken ct)` — Trigger sync and poll status/progress until complete or cancelled. Reports phase name and percentage.
  - `Task<OperationResult<SyncResult>> GetLastSyncInfoAsync(CancellationToken ct = default)` — Get last sync result, new/revised update counts
  - `Task<OperationResult<int>> DeclineUpdatesAsync(IProgress<string>? progress, CancellationToken ct)` — Decline expired, superseded, and old (>6 months) updates. Returns count declined.
  - `Task<OperationResult<int>> ApproveUpdatesAsync(int maxCount, IProgress<string>? progress, CancellationToken ct)` — Auto-approve pending updates matching approved classifications against "All Computers" target group. Safety threshold blocks if count exceeds `maxCount`. Returns count approved.
  - `bool IsConnected { get; }` — Whether a WSUS server connection is active
- `src/WsusManager.Core/Models/SyncResult.cs` — Record with: `string Result`, `int NewUpdates`, `int RevisedUpdates`, `DateTime? StartTime`

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IWsusServerService` in DI

**Implementation notes:**
- Use `Assembly.LoadFrom` to load the WSUS API DLL at runtime. If the DLL is not found, return `OperationResult.Fail("WSUS API not found")` — do not throw.
- Use reflection or dynamic to call `AdminProxy.GetUpdateServer("localhost", false, 8530)`. This avoids a compile-time reference to the WSUS assembly which would break on machines without WSUS.
- Sync progress polling: 5-second interval, max 120 iterations (60 minutes timeout). Report when phase changes, 10% progress jump, or near completion (95%+).
- Approved classifications (matching PowerShell exactly): Critical Updates, Security Updates, Update Rollups, Service Packs, Updates, Definition Updates. Exclude: Upgrades.
- Decline logic: decline expired, superseded, and updates with `CreationDate` older than 6 months. Exclude updates already declined. Exclude Preview and Beta titles from approval.
- All WSUS API calls are blocking — wrap in `Task.Run` to keep the UI responsive.

**Verification:**
1. Unit test: `ConnectAsync` returns failure when WSUS DLL not found (mock Assembly.LoadFrom)
2. Unit test: `StartSynchronizationAsync` polls with 5-second interval and reports phase/percentage
3. Unit test: `ApproveUpdatesAsync` blocks when count exceeds maxCount threshold
4. Unit test: `ApproveUpdatesAsync` excludes Upgrades classification
5. Unit test: `DeclineUpdatesAsync` declines expired, superseded, and old updates
6. `dotnet build` succeeds with zero warnings

---

### Plan 2: Online sync service with profile selection

**What:** Create `ISyncService` that orchestrates the full Online Sync workflow using `IWsusServerService`. Three profiles match the legacy PowerShell behavior:
- **Full Sync:** synchronize -> decline superseded/expired/old -> approve updates -> monitor downloads
- **Quick Sync:** synchronize -> approve updates (skip decline step)
- **Sync Only:** synchronize metadata only, no approval changes

The service takes a `SyncProfile` enum and runs the corresponding workflow, reporting progress for each phase.

**Requirements covered:** SYNC-01 (profile selection), SYNC-02 (progress), SYNC-03 (auto-approval with threshold), SYNC-04 (approved classifications), SYNC-05 (Upgrades excluded)

**Files to create:**
- `src/WsusManager.Core/Models/SyncProfile.cs` — Enum: `FullSync`, `QuickSync`, `SyncOnly`
- `src/WsusManager.Core/Services/Interfaces/ISyncService.cs` — Interface with:
  - `Task<OperationResult> RunSyncAsync(SyncProfile profile, int maxAutoApproveCount, IProgress<string> progress, CancellationToken ct)` — Full sync workflow based on profile
- `src/WsusManager.Core/Services/SyncService.cs` — Implementation. Constructor injects `IWsusServerService`, `ILogService`. `RunSyncAsync` orchestrates:
  1. Connect to WSUS server (all profiles)
  2. Get and report last sync info (all profiles)
  3. Start synchronization and monitor progress (all profiles)
  4. Decline expired/superseded/old updates (Full Sync only)
  5. Auto-approve updates with safety threshold (Full Sync and Quick Sync)
  6. Monitor content downloads (Full Sync and Quick Sync)
  7. Report summary: declined counts, approved count, sync duration

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `ISyncService` in DI

**Verification:**
1. Unit test: Full Sync runs all 6 steps in order
2. Unit test: Quick Sync skips decline step but runs approval
3. Unit test: Sync Only skips both decline and approval
4. Unit test: Safety threshold blocks approval when count exceeds max
5. Unit test: Progress reports include phase name and percentage
6. `dotnet build` succeeds

---

### Plan 3: Robocopy service for content transfer

**What:** Create `IRobocopyService` for running robocopy.exe via `IProcessRunner` with standardized WSUS export/import options. Mirrors the PowerShell `Invoke-WsusRobocopy` function exactly: `/E /XO /MT:16 /R:2 /W:5 /NP /NDL`, excludes `*.bak *.log` files and `Logs SQLDB Backup` directories, supports `/MAXAGE:N` for differential copies. Interprets robocopy exit codes correctly (0–7 = success, 8+ = error). Reports progress lines from robocopy stdout.

**Requirements covered:** Foundation for XFER-01 through XFER-05

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IRobocopyService.cs` — Interface with:
  - `Task<OperationResult> CopyAsync(string source, string destination, int maxAgeDays = 0, IProgress<string>? progress = null, CancellationToken ct = default)` — Run robocopy with standard WSUS options
- `src/WsusManager.Core/Services/RobocopyService.cs` — Implementation. Constructor injects `IProcessRunner`, `ILogService`. Builds robocopy argument string from parameters. Maps exit codes to success/failure messages. Streams stdout lines to progress reporter.

**Verification:**
1. Unit test: Builds correct robocopy arguments with all standard options
2. Unit test: Adds `/MAXAGE:N` when `maxAgeDays > 0`
3. Unit test: Exit codes 0–7 return success, exit codes 8+ return failure
4. Unit test: Excludes `*.bak`, `*.log`, `Logs`, `SQLDB`, `Backup` directories
5. Unit test: Streams stdout lines to progress reporter
6. `dotnet build` succeeds

---

### Plan 4: Export service — full and differential content export

**What:** Create `IExportService` for exporting WSUS content to external media. Supports two export modes: full (all content to a root path) and differential (files modified within N days to an archive path with Year/Month structure). Both modes use `IRobocopyService` for content copy. Optionally copies the newest `.bak` database backup file. Pre-flight validates source and destination paths. Matches the PowerShell `Export-WsusContent` function behavior.

**Requirements covered:** XFER-01 (full export), XFER-02 (differential), XFER-04 (optional paths), XFER-05 (pre-flight validation)

**Files to create:**
- `src/WsusManager.Core/Models/ExportOptions.cs` — Record with: `string SourcePath` (default `C:\WSUS`), `string? FullExportPath`, `string? DifferentialExportPath`, `int ExportDays` (default 30), `bool IncludeDatabaseBackup`
- `src/WsusManager.Core/Services/Interfaces/IExportService.cs` — Interface with:
  - `Task<OperationResult> ExportAsync(ExportOptions options, IProgress<string> progress, CancellationToken ct)`
- `src/WsusManager.Core/Services/ExportService.cs` — Implementation. Constructor injects `IRobocopyService`, `ILogService`. `ExportAsync`:
  1. Pre-flight: validate source path exists; if both export paths are blank, return `OperationResult.Ok("No export paths specified — skipping")`
  2. If `FullExportPath` specified: robocopy `{source}\WsusContent` to `{fullPath}\WsusContent` with `maxAgeDays=0`
  3. If `DifferentialExportPath` specified: create Year/Month archive structure, robocopy `{source}\WsusContent` to `{diffPath}\{Year}\{Month}\WsusContent` with `maxAgeDays=ExportDays`
  4. If `IncludeDatabaseBackup`: find newest `.bak` file in source, copy to export path(s)
  5. Report summary: files exported, size, duration

**Verification:**
1. Unit test: Returns skip message when both export paths are blank (XFER-04)
2. Unit test: Full export calls robocopy with `maxAgeDays=0`
3. Unit test: Differential export calls robocopy with `maxAgeDays=ExportDays` and Year/Month path
4. Unit test: Pre-flight fails when source path does not exist (XFER-05)
5. Unit test: Database backup file copied when `IncludeDatabaseBackup=true`
6. `dotnet build` succeeds

---

### Plan 5: Import service — content import from external media

**What:** Create `IImportService` for importing WSUS content from external media (USB drive, network share) to the local WSUS content directory. Uses `IRobocopyService` for the file copy. Pre-flight validates both source and destination paths before starting. After import completes, offers to run content reset via `IContentResetService` (already implemented in Phase 3).

**Requirements covered:** XFER-03 (import with source/destination), XFER-05 (pre-flight validation)

**Files to create:**
- `src/WsusManager.Core/Models/ImportOptions.cs` — Record with: `string SourcePath`, `string DestinationPath` (default `C:\WSUS`), `bool RunContentResetAfterImport`
- `src/WsusManager.Core/Services/Interfaces/IImportService.cs` — Interface with:
  - `Task<OperationResult> ImportAsync(ImportOptions options, IProgress<string> progress, CancellationToken ct)`
- `src/WsusManager.Core/Services/ImportService.cs` — Implementation. Constructor injects `IRobocopyService`, `IContentResetService`, `ILogService`. `ImportAsync`:
  1. Pre-flight: validate source path exists and has content, validate destination path is writable
  2. Robocopy from `{source}` to `{destination}` with `maxAgeDays=0` (copy everything)
  3. If `RunContentResetAfterImport`: run `IContentResetService.ResetContentAsync` and report result
  4. Report summary: files imported, duration

**Verification:**
1. Unit test: Pre-flight fails when source path does not exist
2. Unit test: Pre-flight fails when source path is empty (no files)
3. Unit test: Import calls robocopy with correct source and destination
4. Unit test: Content reset runs when `RunContentResetAfterImport=true`
5. Unit test: Content reset skipped when `RunContentResetAfterImport=false`
6. `dotnet build` succeeds

---

### Plan 6: WSUS operations UI — sync dialog and ViewModel commands

**What:** Add the Online Sync UI to the main window and wire ViewModel commands. A sync profile selection dialog (WPF Window) with radio buttons for Full Sync / Quick Sync / Sync Only appears before sync starts (dialog before panel switch, per CLAUDE.md patterns). The sync operation runs through `RunOperationAsync` with progress reporting. Wire the `QuickSync` quick-action command to open the sync dialog and run the selected profile. Add navigation for "Sync" panel.

**Requirements covered:** SYNC-01 (profile selection UI), SYNC-02 (progress in log panel), SYNC-03 through SYNC-05 (wired through ISyncService)

**Files to create:**
- `src/WsusManager.App/Views/SyncProfileDialog.xaml` — WPF dialog with:
  - Dark theme styling (matching existing dialogs)
  - Three radio buttons: Full Sync, Quick Sync, Sync Only
  - Description text for each profile
  - OK and Cancel buttons
  - ESC key closes dialog (GUI-04)
  - Returns selected `SyncProfile` via `DialogResult`
- `src/WsusManager.App/Views/SyncProfileDialog.xaml.cs` — Minimal code-behind for dialog result

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameter for `ISyncService`
  - `RunOnlineSyncCommand` — Show `SyncProfileDialog`, run `ISyncService.RunSyncAsync` with selected profile through `RunOperationAsync`
  - Replace `QuickSync` placeholder with actual sync dialog flow
  - Update `NotifyCommandCanExecuteChanged` with new sync commands
  - `QuickSync` uses `CanExecuteOnlineOperation` (existing — requires online mode)
- `src/WsusManager.App/Views/MainWindow.xaml` — Add Sync navigation button in sidebar (online-mode only visibility)

**Verification:**
1. Sync profile dialog shows three options and closes with ESC
2. Clicking OK with Full Sync selected runs the full sync workflow
3. Quick Sync button opens the sync profile dialog
4. Progress appears in log panel during sync
5. Sync button disabled in air-gap mode (CanExecuteOnlineOperation)
6. `dotnet build` succeeds

---

### Plan 7: WSUS operations UI — transfer dialog and ViewModel commands

**What:** Add the Transfer (Export/Import) dialog and wire ViewModel commands. A combined WPF dialog with a direction selector (Export / Import) mirrors the legacy PowerShell UX. Export mode shows: Full Export Path (browse), Differential Export Path (browse), Export Days (numeric, default 30). Import mode shows: Source Path (browse), Destination Path (browse, default `C:\WSUS`). Pre-flight validation runs before starting. All fields collected before operation begins — no interactive prompts during execution.

**Requirements covered:** XFER-01 (full export UI), XFER-02 (differential UI), XFER-03 (import UI), XFER-04 (optional paths), XFER-05 (pre-flight)

**Files to create:**
- `src/WsusManager.App/Views/TransferDialog.xaml` — WPF dialog with:
  - Dark theme styling
  - Direction selector: Export / Import radio buttons
  - Export fields: Full Export Path (TextBox + Browse button), Differential Export Path (TextBox + Browse button), Export Days (TextBox, default 30), Include DB Backup (CheckBox)
  - Import fields: Source Path (TextBox + Browse button), Destination Path (TextBox + Browse button, default `C:\WSUS`), Run Content Reset After Import (CheckBox)
  - Fields visibility toggles based on selected direction
  - OK and Cancel buttons
  - ESC key closes dialog (GUI-04)
- `src/WsusManager.App/Views/TransferDialog.xaml.cs` — Code-behind for browse buttons (FolderBrowserDialog) and direction toggle

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameters for `IExportService` and `IImportService`
  - `RunTransferCommand` — Show `TransferDialog`, build `ExportOptions` or `ImportOptions` from dialog, run appropriate service through `RunOperationAsync`
  - Navigate to "Transfer" panel on operation start
  - Update `NotifyCommandCanExecuteChanged` with transfer command
- `src/WsusManager.App/Views/MainWindow.xaml` — Add Transfer navigation button in sidebar

**Verification:**
1. Transfer dialog shows Export/Import direction selector
2. Selecting Export shows export fields; selecting Import shows import fields
3. Browse buttons open folder picker dialogs
4. Export runs with specified full and/or differential paths
5. Import runs with specified source and destination paths
6. Both operations report progress to log panel
7. `dotnet build` succeeds

---

### Plan 8: Tests and integration verification

**What:** Add comprehensive unit tests for all Phase 5 services and ViewModel commands. Verify all success criteria from the roadmap. Update DI container tests to verify new service registrations.

**Requirements covered:** All Phase 5 requirements (verification)

**Files to create:**
- `src/WsusManager.Tests/Services/WsusServerServiceTests.cs` — Tests: connect failure when DLL missing, sync progress polling, decline logic (expired/superseded/old), approval classification filtering (includes 6 types, excludes Upgrades), safety threshold blocks when count exceeds max, excludes Preview/Beta from approval
- `src/WsusManager.Tests/Services/SyncServiceTests.cs` — Tests: Full Sync runs all steps, Quick Sync skips decline, Sync Only skips decline and approval, progress format, safety threshold
- `src/WsusManager.Tests/Services/RobocopyServiceTests.cs` — Tests: argument construction, MAXAGE flag, exit code mapping, file/directory exclusions, progress streaming
- `src/WsusManager.Tests/Services/ExportServiceTests.cs` — Tests: skip when paths blank, full export robocopy args, differential with Year/Month, pre-flight validation, DB backup copy
- `src/WsusManager.Tests/Services/ImportServiceTests.cs` — Tests: pre-flight validation, robocopy args, content reset conditional execution

**Files to modify:**
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` — Add tests: RunOnlineSync command wired, RunTransfer command wired, QuickSync runs actual sync flow, sync disabled in air-gap mode
- `src/WsusManager.Tests/Integration/DiContainerTests.cs` — Add resolution tests for IWsusServerService, ISyncService, IRobocopyService, IExportService, IImportService

**Verification:**
1. `dotnet build` — 0 warnings, 0 errors
2. `dotnet test` — All tests pass (existing 125+ plus new)
3. All 5 Phase 5 success criteria verified in tests:
   - Online Sync runs with selected profile and reports progress
   - Definition Updates auto-approved with safety threshold, Upgrades excluded
   - Export supports full and differential paths (optional)
   - Import validates source and destination paths before starting
   - All operations run without interactive prompts from GUI

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | WSUS server connection service (API loading, sync, approval) | Foundation for SYNC-01–SYNC-05 |
| 2 | Online sync service with profile selection | SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05 |
| 3 | Robocopy service for content transfer | Foundation for XFER-01–XFER-05 |
| 4 | Export service — full and differential content export | XFER-01, XFER-02, XFER-04, XFER-05 |
| 5 | Import service — content import from external media | XFER-03, XFER-05 |
| 6 | WSUS operations UI — sync dialog and ViewModel commands | SYNC-01–SYNC-05 (UI) |
| 7 | WSUS operations UI — transfer dialog and ViewModel commands | XFER-01–XFER-05 (UI) |
| 8 | Tests and integration verification | All Phase 5 (verification) |

## Execution Order

Plans 1 through 8 execute sequentially. Each plan builds on the previous:
- Plan 1 creates the WSUS server connection service that Plan 2 uses for sync orchestration
- Plan 2 builds the sync workflow with profile selection
- Plan 3 creates the robocopy service that Plans 4–5 use for file transfers
- Plans 4–5 build the export and import services (export first since it is more complex)
- Plans 6–7 wire everything into the UI (sync dialog first, then transfer dialog)
- Plan 8 adds tests and verifies all success criteria

## Success Criteria (from Roadmap)

All five Phase 5 success criteria must be TRUE after Plan 8 completes:

1. Online Sync runs with the selected profile (Full Sync, Quick Sync, or Sync Only) and reports sync phase and percentage progress in the log panel without freezing the UI
2. Definition Updates are auto-approved after sync (up to 200), Critical/Security/Update Rollups/Service Packs/Updates/Definition Updates classifications are approved, and Upgrades are never auto-approved
3. User can export WSUS data to a full path and/or a differential path (files from the last N days) — if neither path is specified, the export step is skipped
4. User can import WSUS data from a source path (e.g., USB drive) to a destination path, with pre-flight validation that both paths are accessible before any data is moved
5. All export/import operations run without interactive prompts when launched from the GUI

---

*Phase: 05-wsus-operations*
*Plan created: 2026-02-19*
