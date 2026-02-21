# Phase 10: Core Operations — Context

**Goal:** Every core WSUS management operation executes to completion against a real WSUS server.
**Requirements:** OPS-01 through OPS-06 (health check, auto-repair, online sync, deep cleanup, backup, restore)

---

## Service-by-Service Analysis

### 1. HealthService (`src/WsusManager.Core/Services/HealthService.cs`)

**What it does:** Orchestrates a 12-check diagnostics pipeline matching the PowerShell `Invoke-WsusDiagnostics` checklist. Auto-repair is always enabled. Checks stream results as they complete.

**Check coverage:**
| # | Check | Auto-Repair |
|---|-------|-------------|
| 1 | SQL Server Express (MSSQL$SQLEXPRESS) service | Yes — StartServiceAsync |
| 2 | SQL Browser service | Yes |
| 3 | SQL firewall (informational pass — deferred to check 12) | No |
| 4 | WSUS service (WsusService) | Yes |
| 5 | IIS (W3SVC) | Yes |
| 6 | WSUS Application Pool via appcmd | Yes — appcmd start apppool |
| 7 | WSUS firewall rules 8530/8531 | Yes — netsh creates rules |
| 8 | SUSDB database existence | No |
| 9 | NETWORK SERVICE SQL login | No |
| 10 | Content directory permissions | Yes — icacls |
| 11 | SQL sysadmin permission | No (informational Warning) |
| 12 | SQL connectivity to SUSDB | No |

**Status: Correct and complete.** All 12 checks correspond to the PowerShell implementation. Auto-repair logic is appropriate and error handling is solid. The `RunCheckAsync` helper prevents any single check from aborting the pipeline.

**Bugs/Issues found:**

**BUG-01: appcmd path not fully qualified.**
`CheckWsusAppPoolAsync` calls `appcmd` without a full path. On a real server, appcmd lives at `C:\Windows\System32\inetsrv\appcmd.exe` and is NOT on the system PATH by default. This will cause the process launch to fail with FileNotFoundException, which is caught and reported as "IIS may not be installed" — a misleading error on a system where IIS is installed but appcmd is not on PATH.
- **Fix:** Use `@"C:\Windows\System32\inetsrv\appcmd.exe"` as the executable.

**BUG-02: appcmd argument quoting.**
The appcmd arguments `list apppool "WsusPool" /state:Started` and `start apppool /apppool.name:"WsusPool"` use double quotes inside a C# string. When passed to `ProcessStartInfo`, these quotes are treated as part of the argument string. On the command line appcmd expects them, but the ProcessRunner does not shell-expand arguments. This needs to be verified: the quotes should be fine since `ProcessStartInfo` passes arguments directly to the OS (no shell expansion), but the double quotes must be escaped correctly in the C# source (they appear correct as written).

**MINOR-01: SQLBrowser service.**
SQL Browser (`SQLBrowser`) is often set to Manual or Disabled on a minimal SQL Express install targeting localhost-only. The check will fail and attempt a restart — but SQL Browser may not be configured to start. This is not a bug, but it may produce a misleading repair failure. Should document this as expected on some setups.

---

### 2. SyncService (`src/WsusManager.Core/Services/SyncService.cs`)

**What it does:** Orchestrates the Online Sync workflow by composing `IWsusServerService` operations according to the selected profile (FullSync, QuickSync, SyncOnly).

**Workflow:**
1. Connect to WSUS server via WsusServerService
2. Get last sync info (informational)
3. Start synchronization and poll to completion
4. Decline expired/superseded/old updates (Full Sync only)
5. Auto-approve updates (Full + Quick Sync)
6. Print summary

**Status: Correct orchestration.** The profile-based conditional logic is correct. Non-fatal step failures (decline, approve) report warnings and continue rather than aborting.

**No bugs found in SyncService itself.** Issues are in WsusServerService (see below).

---

### 3. WsusServerService (`src/WsusManager.Core/Services/WsusServerService.cs`)

**What it does:** Connects to the local WSUS server using the `Microsoft.UpdateServices.Administration` managed API, loaded at runtime via `Assembly.LoadFrom`. All WSUS API calls are blocking and wrapped in `Task.Run`. Implements: Connect, StartSynchronization (with polling), GetLastSyncInfo, DeclineUpdates, ApproveUpdates.

**Status: Correct design pattern.** Loading the API at runtime avoids compile-time dependency on machines without WSUS. Reflection-based method invocation is the right approach for .NET 8 compatibility.

**Bugs/Issues found:**

**BUG-03: `DeclineUpdatesAsync` — old update declination logic is wrong.**
The method declines any update where `CreationDate < sixMonthsAgo`. This is not the same as the PowerShell behavior in `Invoke-WsusMonthlyMaintenance.ps1`, which declines updates where the update itself is superseded or expired — it does NOT arbitrarily decline by age. Declining updates older than 6 months will remove valid historical updates that may still be needed by clients. This needs to match the PowerShell logic: decline only if `IsSuperseded || PublicationState == "Expired"`.

**BUG-04: `ApproveUpdatesAsync` — `UpdateClassificationTitle` property name.**
The WSUS API property for classification is `UpdateClassificationTitle` on an `IUpdate` object. However, the actual WSUS API type `Microsoft.UpdateServices.Administration.IUpdate` does not have a direct `UpdateClassificationTitle` string property. The real property is on the update's `UpdateClassification` property, accessed as `update.UpdateClassification.Title`. This will return null via reflection, causing all updates to appear as having no classification, which then fails the approved-classification check — resulting in zero approvals.
- **Fix:** Use `update.GetType().GetProperty("UpdateClassification")?.GetValue(update)` then get `.GetType().GetProperty("Title")?.GetValue(classification)`.

**BUG-05: `StartSynchronizationAsync` — sync progress `TotalItems` cast.**
```csharp
var processed = (int)(processedProperty?.GetValue(syncProgress) ?? 0);
var total = (int)(totalProperty?.GetValue(syncProgress) ?? 0);
```
If `processedProperty?.GetValue(syncProgress)` returns a boxed `long` or `uint` (WSUS API uses `long` for item counts), the direct `(int)` cast will throw `InvalidCastException`. This is caught by the outer `catch { }` but will silently suppress progress reporting for the entire sync.
- **Fix:** Use `Convert.ToInt32(processedProperty?.GetValue(syncProgress) ?? 0)`.

**BUG-06: `GetLastSyncInfoAsync` — property name mismatch.**
The WSUS API `ISynchronizationInfo` interface uses `Result` as a property of type `SyncStatus` (an enum), not a string. The code calls `resultProp?.GetValue(syncInfo)?.ToString()` which will work for the string representation, but the `StartTime` property on `ISynchronizationInfo` is a `DateTime` (not `DateTime?`). The code casts to `DateTime?` which will work via boxing but the value will always be present (non-nullable in the API). This is minor and should work, but if the property returns `default(DateTime)` (year 0001), it will display a confusing timestamp.

**MINOR-02: `ConnectAsync` — Assembly.LoadFrom and AppDomain.**
`Assembly.LoadFrom` loads the assembly into the default `AssemblyLoadContext`. On .NET 8, this could cause type identity issues if the WSUS API assembly loads its own dependencies (e.g., if it tries to load `Microsoft.UpdateServices.Internal`). This is an inherent limitation of runtime loading of a .NET Framework-era DLL in a .NET 8 host. If the WSUS API was compiled for .NET Framework, it runs under the Windows Compatibility Shim, which generally works for admin-only tools like WSUS. However, if it throws `FileLoadException` or type exceptions, they are caught and reported as failures.

---

### 4. DeepCleanupService (`src/WsusManager.Core/Services/DeepCleanupService.cs`)

**What it does:** Implements the 6-step WSUS deep cleanup pipeline matching the PowerShell `WsusDatabase.psm1` implementation. Steps: WSUS built-in cleanup via PowerShell subprocess, remove declined supersession records, remove superseded supersession records in 10k batches, delete declined updates via `spDeleteUpdate` in 100-item batches, rebuild/reorganize fragmented indexes, shrink database with retry.

**Status: Correct and detailed.** SQL logic matches the PowerShell source. Batch sizes, RevisionState values (2=Declined, 3=Superseded), and retry logic are all correct. Index optimization SQL (fragmentation > 30% = rebuild, > 10% = reorganize, page_count > 1000 only) matches PowerShell.

**Bugs/Issues found:**

**BUG-07: Step 1 PowerShell command — escaping issue.**
```csharp
var psCommand =
    "Get-WsusServer -Name localhost -PortNumber 8530 | " +
    "Invoke-WsusServerCleanup " +
    "-CleanupObsoleteUpdates " +
    "-CleanupUnneededContentFiles " +
    "-CompressUpdates " +
    "-DeclineSupersededUpdates";

var result = await _processRunner.RunAsync(
    "powershell.exe",
    $"-NonInteractive -NoProfile -Command \"{psCommand}\"",
    progress, ct);
```
The `psCommand` string is embedded inside double quotes in the `-Command` argument. `ProcessStartInfo` with `UseShellExecute = false` passes the arguments string directly without shell expansion, so the embedded double quotes in the arguments string work on Win32. However, if `ProcessRunner.RunAsync` constructs the `ProcessStartInfo` with `Arguments = $"-NonInteractive -NoProfile -Command \"{psCommand}\""`, the quotes around `{psCommand}` are literal characters in the argument string, which is correct for Windows process creation.

The real issue: `powershell.exe -Command "<pipeline>"` requires the pipeline to be on one line. The `\n` characters from string continuation will cause PowerShell to treat lines after `|` as separate statements. However, in this case the strings are C# string concatenation with no newlines — the multi-line C# syntax just adds to the same string. This is fine.

**However:** The `-Command` argument passes the entire pipeline as a single quoted string argument. On some systems, PowerShell's handling of embedded double quotes in the `-Command` argument can fail if the pipeline itself contains double quotes (it does not here, so this is OK). But the proper way to pass complex scripts to PowerShell is via `-EncodedCommand` (base64). This is not a blocker but a fragility.

**BUG-08: Step 4 — `spDeleteUpdate` parameter mismatch.**
```csharp
cmd.CommandText = "EXEC spDeleteUpdate @localUpdateID";
cmd.Parameters.AddWithValue("@localUpdateID", updateId);
```
The `spDeleteUpdate` stored procedure in SUSDB takes `@localUpdateID` as an `INT` (the `LocalUpdateID` identity column), not a `GUID` (the `UpdateID` column). The SELECT query retrieves `u.UpdateID` (the GUID), but the stored procedure expects `LocalUpdateID` (an int). This is a **critical data mismatch** that will cause `SqlException: Implicit conversion from data type uniqueidentifier to int is not allowed` for every single update, causing Step 4 to silently skip all updates (errors are suppressed).
- **Fix:** The SELECT query must retrieve `u.LocalUpdateID` (the int), or join to get it from `tbRevision.LocalUpdateID`, and pass that int to `spDeleteUpdate`.

**Correct SQL:**
```sql
SELECT DISTINCT r.LocalUpdateID
FROM tbUpdate u
INNER JOIN tbRevision r ON u.LocalUpdateID = r.LocalUpdateID
WHERE r.RevisionState = 2
```
Then pass `reader.GetInt32(0)` to the parameter.

**BUG-09: Step 5 — Cursor SQL executed with `ExecuteReaderAsync` but returns two SELECT columns.**
The index optimization SQL uses a CURSOR and ends with `SELECT @Rebuilt AS Rebuilt, @Reorganized AS Reorganized`. The code calls `cmd.ExecuteReaderAsync` and reads the first row's columns 0 and 1. This is correct. However, if SQL Server Express returns any informational messages (SET NOCOUNT is not set), the `ExecuteReaderAsync` might return additional result sets from intermediate EXEC statements inside the cursor. This depends on `MultipleActiveResultSets` (not set in connection string) and whether the EXEC statements inside the cursor return rows. `ALTER INDEX ... REBUILD` and `REORGANIZE` are DDL statements that don't return rows, so this should be safe.

**MINOR-03: Step 6 — Shrink error detection.**
```csharp
private static bool IsBackupBlockingError(string message) =>
    message.Contains("serialized", StringComparison.OrdinalIgnoreCase) ||
    message.Contains("backup", StringComparison.OrdinalIgnoreCase) && message.Contains("operation", StringComparison.OrdinalIgnoreCase) ||
    message.Contains("file manipulation", StringComparison.OrdinalIgnoreCase);
```
Operator precedence: `&&` binds tighter than `||`, so this is evaluated as:
`Contains("serialized") || (Contains("backup") && Contains("operation")) || Contains("file manipulation")`.
This is the intended logic and correct as written. Not a bug.

---

### 5. DatabaseBackupService (`src/WsusManager.Core/Services/DatabaseBackupService.cs`)

**What it does:** Implements database backup (SQL BACKUP DATABASE with COMPRESSION) and restore (full workflow: verify, stop services, single-user mode, RESTORE DATABASE WITH REPLACE, multi-user mode, wsusutil postinstall, restart services). Includes sysadmin check, disk space estimation, and file integrity verification.

**Status: Correct and complete.** The restore workflow matches the PowerShell implementation exactly, including single-user mode, retry-safe service handling, and wsusutil postinstall.

**Bugs/Issues found:**

**BUG-10: `VerifyBackupAsync` — `RESTORE VERIFYONLY WITH CHECKSUM` behavior.**
```csharp
var verifySql = $"RESTORE VERIFYONLY FROM DISK = N'{safePath}' WITH CHECKSUM";
```
`RESTORE VERIFYONLY` does NOT return rows — it succeeds silently and throws a `SqlException` on failure. The code calls `ExecuteNonQueryAsync` which is correct. However, backup files created without `WITH CHECKSUM` in the original backup command will return a warning (not an error) when verified with `WITH CHECKSUM`. This warning will not throw a `SqlException` and `VerifyBackupAsync` will return success even for checksum warnings. This is acceptable behavior (no false failures), but means the verification is not as strict as it could be.

**BUG-11: `RestoreAsync` — `wsusutil.exe` path is hardcoded.**
```csharp
var wsusutilPath = @"C:\Program Files\Update Services\Tools\wsusutil.exe";
```
This is the standard install path and matches the PowerShell implementation. However, if WSUS is installed to a non-default location, this will fail silently (ProcessRunner will throw `FileNotFoundException` caught and reported as warning). This matches PowerShell behavior and is acceptable for Phase 10.

**BUG-12: `BackupAsync` — `GetDiskFreeGb` with UNC paths.**
```csharp
private static double GetDiskFreeGb(string path)
{
    try
    {
        var drive = new DriveInfo(path);
        return drive.AvailableFreeSpace / 1024.0 / 1024.0 / 1024.0;
    }
    catch
    {
        return -1; // Can't determine disk space
    }
}
```
`DriveInfo` constructor throws `ArgumentException` for UNC paths (`\\server\share\...`). The catch returns -1, which causes the disk space check to be silently skipped (`diskFreeGb < 0` branch). This is safe (no false block) but means UNC backup paths don't get disk space validation. Acceptable limitation.

---

### 6. SqlService (`src/WsusManager.Core/Services/SqlService.cs`)

**What it does:** Centralized SQL execution service. All connection strings use Integrated Security and TrustServerCertificate=True. Provides `ExecuteScalarAsync<T>`, `ExecuteNonQueryAsync`, and `ExecuteReaderFirstAsync<T>`. CommandTimeout=0 means unlimited, required for long-running maintenance queries.

**Status: Correct and complete.** The pattern of opening a new connection per query is correct for SQLEXPRESS (no connection pool contention for admin workloads). The `TrustServerCertificate=True` matches the PowerShell workaround from v3.8.11.

**Bugs/Issues found:**

**BUG-13: `ExecuteScalarAsync<T>` — invalid cast for `double` when result is `decimal`.**
```csharp
return (T)Convert.ChangeType(result, typeof(T));
```
SQL Server `SUM(size * 8.0 / 1024 / 1024)` returns `decimal`, not `double`. `Convert.ChangeType(decimal_value, typeof(double))` works correctly (decimal is convertible to double). This is safe.

**MINOR-04: Connection string does not set `Application Name`.**
Not a bug, but setting `Application Name=WsusManager` would improve SQL Server diagnostics (shows which app is connecting in activity monitor). Not a blocker.

---

### 7. WindowsServiceManager (`src/WsusManager.Core/Services/WindowsServiceManager.cs`)

**What it does:** Manages Windows services using `System.ServiceProcess.ServiceController`. Start order: SQL -> IIS -> WSUS. Stop order: WSUS -> IIS -> SQL. Retry logic: 3 attempts, 5-second delays. 30-second wait timeout per service.

**Status: Correct and complete.** The start/stop ordering is correct. `ServiceController` is the right API. The 30-second `WaitForStatus` timeout is appropriate. `InvalidOperationException` is correctly caught for services that don't exist.

**Bugs/Issues found:**

**BUG-14: `StartAllServicesAsync` — stops on first failure.**
```csharp
if (result.Success)
    progress?.Report($"[OK] {displayName} running.");
else
{
    progress?.Report($"[FAIL] {displayName}: {result.Message}");
    return OperationResult.Fail($"Failed to start {displayName}: {result.Message}");
}
```
If SQL Server Express fails to start, IIS and WSUS will not be attempted. This is actually correct behavior for dependency ordering (WSUS requires SQL), so this is not a bug.

**MINOR-05: `StopServiceAsync` — does not handle `StartPending`/`StopPending` states.**
If a service is in `StopPending` state, calling `sc.Stop()` will throw an exception. The `catch (Exception ex)` will return `OperationResult.Fail`. This is acceptable error handling.

---

### 8. PermissionsService (`src/WsusManager.Core/Services/PermissionsService.cs`)

**What it does:** Checks and repairs WSUS content directory permissions (NETWORK SERVICE, IIS_IUSRS) and SQL login existence. Uses `System.Security.AccessControl` for checking and `icacls` for repair.

**Status: Correct.** The ACL check using `GetAccessRules` with inherited rules is correct. The `icacls` repair command uses `(OI)(CI)F` flags for recursive Full Control, which matches the PowerShell implementation.

**Bugs/Issues found:**

**BUG-15: Permission check accepts `Modify` as sufficient.**
```csharp
if ((rule.FileSystemRights & FileSystemRights.FullControl) == 0 &&
    (rule.FileSystemRights & FileSystemRights.Modify) == 0) continue;
```
The condition skips rules that have neither FullControl nor Modify. WSUS requires `FullControl` specifically for the content directory. Accepting `Modify` as sufficient is slightly less strict than the PowerShell implementation but is unlikely to cause issues in practice (WSUS also works with Modify).

---

### 9. FirewallService (`src/WsusManager.Core/Services/FirewallService.cs`)

**What it does:** Uses `netsh advfirewall` to check for and create inbound rules on ports 8530 and 8531.

**Status: Correct.** The netsh commands match the PowerShell implementation. Rule existence is checked by exact name match.

**Bugs/Issues found:**

**BUG-16: `CheckWsusRulesExistAsync` — netsh exit code interpretation.**
`netsh advfirewall firewall show rule name="WSUS HTTP"` returns exit code 0 if rules are found, exit code 1 if not found. The code checks `httpResult.Success` (exit code == 0). This is correct behavior.

**MINOR-06: Rule name case sensitivity.**
The rules are named "WSUS HTTP" and "WSUS HTTPS". If a previous installation created rules with different names (e.g., "WSUS-HTTP" or "WSUS (HTTP)"), the check will report missing and create duplicates. This is acceptable behavior that matches the PowerShell implementation.

---

### 10. ProcessRunner (`src/WsusManager.Core/Infrastructure/ProcessRunner.cs`)

**What it does:** Centralized external process execution with output capture, progress reporting, cancellation, and process tree kill on cancel.

**Status: Correct.** Using `proc.Kill(entireProcessTree: true)` is the right approach to clean up PowerShell child processes. `BeginOutputReadLine`/`BeginErrorReadLine` are called before `WaitForExitAsync`, which is the correct order to avoid deadlock.

**MINOR-07: `proc.Start()` return value not checked.**
```csharp
proc.Start();
proc.BeginOutputReadLine();
proc.BeginErrorReadLine();
```
`proc.Start()` returns `false` if the process was already running (shell-execute reuse) or throws `Win32Exception` if the executable is not found. The `Win32Exception` propagates up and is caught by callers' try/catch blocks. The `false` return is not checked, but for `UseShellExecute = false` (direct launch), `Start()` returns `true` on success or throws on failure. Not a practical issue.

---

### 11. DashboardService (`src/WsusManager.Core/Services/DashboardService.cs`)

**What it does:** Collects service status, DB size, disk space, scheduled task status, and internet connectivity in parallel.

**Bugs/Issues found:**

**BUG-17: `CheckDatabaseSize` uses wrong SQL.**
```csharp
cmd.CommandText = "SELECT SUM(size) * 8.0 / 1024 / 1024 FROM sys.database_files";
```
This query runs in the context of `SUSDB` (Initial Catalog=SUSDB in connection string), so `sys.database_files` shows files for SUSDB only — this is correct for size. However, multiplying `SUM(size)` by `8.0 / 1024 / 1024` gives size in **GB** only if `size` is in pages (8KB each), which gives: `pages * 8KB / 1024 / 1024 = GB`. The math is: `pages * 8 / 1024 / 1024 = GB`. This is actually `pages * 8.0 / 1024 / 1024` = GB. Correct.

However, compare to `DeepCleanupService` which uses:
```sql
SELECT SUM(size * 8.0 / 1024 / 1024) AS SizeGB
FROM sys.master_files
WHERE database_id = DB_ID('SUSDB')
AND type = 0
```
The `DashboardService` query runs against the SUSDB connection and queries `sys.database_files` (all files in current DB, both data and log), while `DeepCleanupService` queries `sys.master_files` in master with `type=0` (data files only). The dashboard includes log file size in its DB size calculation, while the cleanup service does not. This causes an inconsistency in reported sizes — the dashboard will show a slightly larger number. Not a functional bug, but a reporting inconsistency.

---

### 12. MainViewModel Command Handlers (`src/WsusManager.App/ViewModels/MainViewModel.cs`)

**What it does:** Central ViewModel managing all operations through `RunOperationAsync`. All operations disable the UI, report progress, handle cancellation, and re-enable UI on completion.

**Status: Correct pattern.** The `RunOperationAsync` pattern properly manages `IsOperationRunning`, `CancellationTokenSource` lifecycle, progress reporting, and state cleanup in `finally`. The dialog-before-panel-switch pattern from CLAUDE.md is followed for all operations.

**Bugs/Issues found:**

**BUG-18: `RunDiagnostics` — `report.IsHealthy || report.FailedCount == 0` is redundant.**
```csharp
return report.IsHealthy || report.FailedCount == 0;
```
If `DiagnosticReport.IsHealthy` is defined as `FailedCount == 0`, this is always true when `FailedCount == 0`. If `IsHealthy` is a different condition (e.g., also checks `RepairedCount`), this may not be a bug. This needs to be verified against `DiagnosticReport.IsHealthy`. Minor issue.

**BUG-19: `AppendLog` is not thread-safe.**
```csharp
public void AppendLog(string line)
{
    LogOutput += line + Environment.NewLine;
}
```
`Progress<string>` callbacks are dispatched on the thread that called `new Progress<string>()`. Since `RunOperationAsync` is called from the UI thread (via async command handlers), the `Progress<string>` callbacks run on the UI thread via `SynchronizationContext`. However, `WsusServerService` uses `Task.Run` internally and the progress callback passed from `SyncService` into the `Task.Run` lambda is the same `IProgress<string>` object. The `Progress<T>` class captures the `SynchronizationContext` at construction time and marshals callbacks to that context. So `AppendLog` will be called on the UI thread. **This is safe.** But it depends on `Progress<T>` being constructed on the UI thread — which it is, inside `RunOperationAsync`.

**BUG-20: `RunCreateGpo` — `Dispatcher.Invoke` inside async operation.**
```csharp
Application.Current.Dispatcher.Invoke(() =>
{
    var instrDialog = new GpoInstructionsDialog(result.Data);
    ...
    instrDialog.ShowDialog();
});
```
`RunOperationAsync` is an `async Task` method. The lambda passed to it runs as an async continuation on the thread pool (via `await operation(progress, _operationCts.Token)`). `Dispatcher.Invoke` then marshals back to the UI thread to show the dialog. This is correct but redundant — since `RunOperationAsync` awaits the lambda, and the lambda itself is not `Task.Run`-wrapped (the `GpoDeploymentService` may use Task.Run internally), the actual execution context depends on `GpoDeploymentService`. If `DeployGpoFilesAsync` uses `Task.Run` internally (making the continuation run on a threadpool thread), then `Dispatcher.Invoke` is necessary. If not, it's redundant but harmless. **This is safe.**

**MINOR-08: `CanExecuteWsusOperation` not notified after `IsOperationRunning` changes.**
```csharp
[ObservableProperty]
[NotifyCanExecuteChangedFor(nameof(CancelOperationCommand))]
private bool _isOperationRunning;
```
`IsOperationRunning` only notifies `CancelOperationCommand` via the attribute. The `CanExecuteWsusOperation()` check also depends on `IsOperationRunning`. While `NotifyCommandCanExecuteChanged()` is called on dashboard refresh (which happens after operations), it is NOT called when `IsOperationRunning` changes in `RunOperationAsync`. This means buttons may temporarily appear enabled while an operation is running.
- **Fix:** Add `[NotifyCanExecuteChangedFor(...all operation commands...)]` to `_isOperationRunning`, or call `NotifyCommandCanExecuteChanged()` when `IsOperationRunning` changes.

---

## Summary of Bugs by Severity

### Critical (will cause silent failures or incorrect behavior on real hardware)

| ID | Location | Description |
|----|----------|-------------|
| BUG-03 | WsusServerService.DeclineUpdatesAsync | Declines updates older than 6 months — not matching PS behavior, removes valid updates |
| BUG-04 | WsusServerService.ApproveUpdatesAsync | `UpdateClassificationTitle` property doesn't exist on WSUS IUpdate — returns null, zero approvals |
| BUG-08 | DeepCleanupService Step 4 | `spDeleteUpdate` receives GUID (UpdateID) but expects INT (LocalUpdateID) — all Step 4 deletes silently fail |

### High (operation partially broken but recoverable)

| ID | Location | Description |
|----|----------|-------------|
| BUG-01 | HealthService.CheckWsusAppPoolAsync | `appcmd` not on PATH — check fails with misleading error, no app pool repair on real servers |
| BUG-05 | WsusServerService.StartSynchronizationAsync | Direct `(int)` cast on boxed `long` from WSUS API — sync progress silently suppressed |

### Medium (functional but non-ideal behavior)

| ID | Location | Description |
|----|----------|-------------|
| BUG-06 | WsusServerService.GetLastSyncInfoAsync | `StartTime` as `DateTime?` may show default(DateTime) for never-synced servers |
| BUG-17 | DashboardService.CheckDatabaseSize | Includes log file in DB size (vs. DeepCleanup which excludes log file) — minor reporting inconsistency |
| MINOR-08 | MainViewModel | `IsOperationRunning` doesn't notify all operation commands — brief button enable during operations |

### Low (acceptable limitations or minor issues)

| ID | Location | Description |
|----|----------|-------------|
| BUG-07 | DeepCleanupService Step 1 | PS `-Command` quoting fragile — should use `-EncodedCommand` for robustness |
| BUG-10 | DatabaseBackupService.VerifyBackupAsync | `WITH CHECKSUM` verify may pass for backups created without checksum — slightly loose validation |
| BUG-11 | DatabaseBackupService.RestoreAsync | wsusutil.exe hardcoded path — acceptable for standard installs |
| BUG-12 | DatabaseBackupService.BackupAsync | UNC paths skip disk space check — safe but no UNC validation |
| BUG-15 | PermissionsService | Accepts `Modify` as equivalent to `FullControl` — functionally acceptable |
| MINOR-01 | HealthService | SQLBrowser often disabled — repair failure is expected on minimal installs |

---

## What Needs to Be Fixed for Operations to Work on Real Hardware

### Must Fix Before Phase 10 Completion

1. **BUG-08 (Critical):** `DeepCleanupService` Step 4 — change SELECT to retrieve `LocalUpdateID` (int) and pass that to `spDeleteUpdate`.

2. **BUG-04 (Critical):** `WsusServerService.ApproveUpdatesAsync` — fix `UpdateClassificationTitle` property access. The WSUS API property chain is: `IUpdate.UpdateClassification` (IUpdateClassification) -> `.Title` (string). Use two-level reflection.

3. **BUG-03 (Critical):** `WsusServerService.DeclineUpdatesAsync` — remove the "older than 6 months" decline criterion. Decline only `IsSuperseded == true` or `PublicationState == "Expired"`.

4. **BUG-01 (High):** `HealthService.CheckWsusAppPoolAsync` — use full path `C:\Windows\System32\inetsrv\appcmd.exe`.

5. **BUG-05 (High):** `WsusServerService.StartSynchronizationAsync` — use `Convert.ToInt32()` instead of direct `(int)` cast for sync progress counters.

### Fix Before Production Use (Recommended for Phase 10)

6. **MINOR-08:** `MainViewModel._isOperationRunning` — add `NotifyCanExecuteChanged` for all operation commands when `IsOperationRunning` changes, to prevent momentary button enable states.

### Acceptable for Phase 10 (Document as Known Limitations)

- BUG-07: PowerShell `-Command` quoting — works for this specific command, no nested quotes
- BUG-10: VERIFYONLY/CHECKSUM is best-effort verification
- BUG-11: wsusutil.exe hardcoded path — standard install location
- BUG-12: UNC paths skip disk space validation — safe fallback
- BUG-15: Modify vs FullControl — WSUS functions with either
- BUG-17: Dashboard DB size includes log file — cosmetic difference
- MINOR-01: SQLBrowser — documented expected behavior on minimal installs

---

## Operations Readiness Assessment

| Operation | OPS-ID | Status | Blocking Issues |
|-----------|--------|--------|-----------------|
| Health Check / Auto-Repair | OPS-01 | Near-Ready | BUG-01 (appcmd path) |
| Online Sync | OPS-02 | Broken | BUG-03, BUG-04, BUG-05 |
| Deep Cleanup | OPS-03 | Partially Broken | BUG-08 (Step 4 silent fail) |
| Database Backup | OPS-04 | Ready | None critical |
| Database Restore | OPS-05 | Ready | None critical |
| Start Services | OPS-06 | Ready | None |

---

## Architecture Notes (No Issues Found)

- **WPF Dispatcher safety:** `Progress<T>` is constructed on the UI thread inside `RunOperationAsync`. The `SynchronizationContext` capture ensures all progress callbacks run on the UI thread. No `Dispatcher.Invoke` is needed in services — they correctly accept `IProgress<string>` and call `progress.Report()` without thread concerns.

- **Cancellation propagation:** `CancellationToken` flows correctly from `RunOperationAsync` through all service layers and into `SqlConnection.OpenAsync`, `cmd.ExecuteNonQueryAsync`, `Task.Delay`, and `Process.WaitForExitAsync`. Cancellation in the middle of a DB operation will abort the SQL command cleanly.

- **No hardcoded SQL instance:** `_settings.SqlInstance` (default: `localhost\SQLEXPRESS`) is passed through from settings to all services. Users can override to `localhost\MSSQLSERVER` or other instances in settings.

- **No hardcoded content path:** `_settings.ContentPath` (default: `C:\WSUS`) is passed from settings. Used by HealthService, BackupService, and PermissionsService.

- **Connection string is consistent:** All services use `TrustServerCertificate=True;Integrated Security=True` matching the v3.8.11 PowerShell fix. There is a duplication between `HealthService` (which has its own `BuildConnectionString`) and `SqlService` (which also builds connection strings). This is a minor DRY violation but does not cause inconsistency since both use the same parameters.
