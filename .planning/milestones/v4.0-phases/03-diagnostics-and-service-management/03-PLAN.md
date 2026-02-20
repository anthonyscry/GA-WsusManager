# Phase 3: Diagnostics and Service Management — Plan

**Created:** 2026-02-19
**Requirements:** DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05, SVC-01, SVC-02, SVC-03, FW-01, FW-02, PERM-01, PERM-02
**Goal:** Administrators can run a comprehensive health check that detects and auto-repairs service failures, firewall rule problems, content directory permission issues, and SQL connectivity failures — and can start/stop individual services directly from the UI. Also includes sysadmin permission enforcement and content reset (wsusutil reset).

---

## Plans

### Plan 1: Health check models and diagnostic result types

**What:** Create the data models that represent individual health check results and the overall diagnostics report. These types are consumed by the health service (Plan 2) and displayed in the UI (Plan 5). Each check has a name, status (Pass/Fail/Warning/Skipped), a detail message, and whether auto-repair was attempted and its outcome.

**Requirements covered:** DIAG-03 (clear pass/fail reporting for each check)

**Files to create:**
- `src/WsusManager.Core/Models/DiagnosticCheckResult.cs` — Single check result: `CheckName` (string), `Status` (enum: Pass, Fail, Warning, Skipped), `Message` (string), `RepairAttempted` (bool), `RepairSucceeded` (bool?), `RepairMessage` (string?)
- `src/WsusManager.Core/Models/DiagnosticReport.cs` — Aggregate report: `Checks` (IReadOnlyList<DiagnosticCheckResult>), `TotalChecks` (int), `PassedCount` (int), `FailedCount` (int), `RepairedCount` (int), `StartedAt` (DateTime), `CompletedAt` (DateTime), computed `Duration`, `IsHealthy` (bool)

**Verification:**
1. Models compile with no warnings
2. `DiagnosticReport.IsHealthy` returns true only when all checks pass or were repaired
3. `DiagnosticReport.RepairedCount` correctly counts checks where `RepairAttempted && RepairSucceeded`

---

### Plan 2: Windows service management service

**What:** Create `IWindowsServiceManager` and its implementation for starting, stopping, and querying the status of Windows services. Handles service dependency ordering (SQL Server first, then IIS, then WSUS for start; reverse for stop). Includes retry logic (3 attempts, 5-second delay) for service start failures. Uses `System.ServiceProcess.ServiceController` for all service operations.

**Requirements covered:** SVC-01 (start/stop SQL, WSUS, IIS), SVC-02 (real-time status), SVC-03 (dependency ordering)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IWindowsServiceManager.cs` — Interface with: `Task<ServiceStatusInfo> GetStatusAsync(string serviceName, CancellationToken ct)`, `Task<ServiceStatusInfo[]> GetAllStatusAsync(CancellationToken ct)`, `Task<OperationResult> StartServiceAsync(string serviceName, CancellationToken ct)`, `Task<OperationResult> StopServiceAsync(string serviceName, CancellationToken ct)`, `Task<OperationResult> StartAllServicesAsync(IProgress<string> progress, CancellationToken ct)`, `Task<OperationResult> StopAllServicesAsync(IProgress<string> progress, CancellationToken ct)`
- `src/WsusManager.Core/Models/ServiceStatusInfo.cs` — Model: `ServiceName` (string), `DisplayName` (string), `Status` (ServiceControllerStatus), `IsRunning` (bool)
- `src/WsusManager.Core/Services/WindowsServiceManager.cs` — Implementation using ServiceController. Service definitions: `MSSQL$SQLEXPRESS` (order 1), `W3SVC` (order 2), `WsusService` (order 3). Start follows ascending order, stop follows descending order. Retry logic: 3 attempts with 5-second delays on service start failure. Uses `WaitForStatus` with 30-second timeout.

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IWindowsServiceManager` in DI

**Verification:**
1. Unit test: `StartAllServicesAsync` starts services in correct order (SQL first, then IIS, then WSUS)
2. Unit test: `StopAllServicesAsync` stops in reverse order (WSUS first, then IIS, then SQL)
3. Unit test: `GetAllStatusAsync` returns status for all 3 monitored services
4. Unit test: Service start retries up to 3 times on failure before reporting error
5. `dotnet build` succeeds with zero warnings

---

### Plan 3: Firewall rule management service

**What:** Create `IFirewallService` and its implementation for checking and creating WSUS firewall rules. Uses `netsh advfirewall firewall` commands via `IProcessRunner` (not a managed API). Checks for inbound rules on ports 8530 (HTTP) and 8531 (HTTPS). Creates rules when missing during auto-repair.

**Requirements covered:** FW-01 (manage WSUS firewall rules for 8530/8531), FW-02 (check and auto-repair during diagnostics)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IFirewallService.cs` — Interface with: `Task<OperationResult<bool>> CheckWsusRulesExistAsync(CancellationToken ct)`, `Task<OperationResult> CreateWsusRulesAsync(IProgress<string>? progress, CancellationToken ct)`
- `src/WsusManager.Core/Services/FirewallService.cs` — Implementation using `IProcessRunner` to run `netsh advfirewall firewall show rule name="WSUS HTTP"` (and HTTPS variant) for checking, and `netsh advfirewall firewall add rule name="WSUS HTTP" dir=in action=allow protocol=TCP localport=8530` (and 8531 for HTTPS) for creation. Returns success/failure from process exit codes.

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IFirewallService` in DI

**Verification:**
1. Unit test: `CheckWsusRulesExistAsync` returns true when both rules found (mock process returns exit code 0)
2. Unit test: `CheckWsusRulesExistAsync` returns false when a rule is missing (mock process returns non-zero)
3. Unit test: `CreateWsusRulesAsync` runs correct netsh commands via ProcessRunner
4. `dotnet build` succeeds

---

### Plan 4: Permissions and SQL sysadmin check services

**What:** Create `IPermissionsService` for checking and repairing WSUS content directory permissions (NETWORK SERVICE and IIS_IUSRS ACLs), and checking SQL sysadmin membership. Directory permission checks use `System.Security.AccessControl`. Sysadmin check queries `SELECT IS_SRVROLEMEMBER('sysadmin')` via SQL. Permission repair uses `icacls` via `IProcessRunner`.

**Requirements covered:** PERM-01 (check/repair directory permissions), PERM-02 (SQL login permissions), DIAG-04 (sysadmin verification)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IPermissionsService.cs` — Interface with: `Task<OperationResult<bool>> CheckContentPermissionsAsync(string contentPath, CancellationToken ct)`, `Task<OperationResult> RepairContentPermissionsAsync(string contentPath, IProgress<string>? progress, CancellationToken ct)`, `Task<OperationResult<bool>> CheckSqlSysadminAsync(string sqlInstance, CancellationToken ct)`, `Task<OperationResult<bool>> CheckNetworkServiceLoginAsync(string sqlInstance, CancellationToken ct)`
- `src/WsusManager.Core/Services/PermissionsService.cs` — Implementation:
  - Content permissions: Check for NETWORK SERVICE and IIS_IUSRS ACL entries on content path using `DirectoryInfo.GetAccessControl()`. Repair via `icacls "{path}" /grant "NETWORK SERVICE:(OI)(CI)F" /T` and similar for IIS_IUSRS.
  - Sysadmin: `SELECT IS_SRVROLEMEMBER('sysadmin')` returns 1 if current user is sysadmin.
  - NETWORK SERVICE login: `SELECT name FROM sys.server_principals WHERE name='NT AUTHORITY\NETWORK SERVICE'`.

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IPermissionsService` in DI

**Verification:**
1. Unit test: `CheckSqlSysadminAsync` returns true when query returns 1
2. Unit test: `CheckSqlSysadminAsync` returns false when query returns 0 or connection fails
3. Unit test: `CheckNetworkServiceLoginAsync` returns true when login exists
4. Unit test: `RepairContentPermissionsAsync` runs correct icacls commands via ProcessRunner
5. `dotnet build` succeeds

---

### Plan 5: Health check service with auto-repair pipeline

**What:** Create `IHealthService` and its implementation that orchestrates the full diagnostics pipeline. Runs 12 checks sequentially (matching the PowerShell `Invoke-WsusDiagnostics` check list), streams each result to the progress reporter in real time, and automatically attempts repairs for fixable issues. Returns a `DiagnosticReport` with all results.

**Requirements covered:** DIAG-01 (comprehensive health check), DIAG-02 (auto-repair), DIAG-03 (pass/fail reporting)

**Check list (matching PowerShell exactly):**
1. SQL Server Express service status
2. SQL Browser service status
3. SQL Server firewall rules
4. WSUS service status
5. IIS service status
6. WSUS Application Pool (via `IProcessRunner` calling `appcmd list apppool "WsusPool"`)
7. WSUS firewall rules (ports 8530/8531)
8. SUSDB database existence (SQL query `SELECT DB_ID('SUSDB')`)
9. NETWORK SERVICE SQL login
10. WSUS content directory permissions
11. SQL sysadmin permission (informational — no auto-fix)
12. SQL connectivity test (connection + simple query)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IHealthService.cs` — Interface with: `Task<DiagnosticReport> RunDiagnosticsAsync(string contentPath, string sqlInstance, IProgress<string> progress, CancellationToken ct)`
- `src/WsusManager.Core/Services/HealthService.cs` — Implementation that injects `IWindowsServiceManager`, `IFirewallService`, `IPermissionsService`, `IProcessRunner`, `ILogService`. Each check runs sequentially. Auto-repair is always on (matches GUI behavior). Reports each check inline: `[PASS] SQL Server Express — Running`, `[FAIL] WSUS Service — Stopped -> Restarting... [FIXED]`, or `-> Repair failed: <reason>`. Summary line at end: `Diagnostics complete: X/Y checks passed, Z auto-repaired`.

**Verification:**
1. Unit test: All 12 checks run in sequence and results are collected in the report
2. Unit test: Auto-repair is attempted for fixable issues (service start, firewall create, permission repair)
3. Unit test: Non-fixable issues (service not installed, SUSDB missing) report Fail without repair attempt
4. Unit test: Sysadmin check is informational (Warning, not Fail) when user lacks sysadmin
5. Unit test: Progress reports each check result as it completes
6. Unit test: Report summary counts are correct
7. `dotnet build` and `dotnet test` pass

---

### Plan 6: Content reset service (wsusutil reset)

**What:** Create the content reset capability that runs `wsusutil.exe reset` via `IProcessRunner`. The wsusutil executable is located at `C:\Program Files\Update Services\Tools\wsusutil.exe`. Output is streamed to the progress reporter. No timeout is applied (can take 10+ minutes on large content stores).

**Requirements covered:** DIAG-05 (content reset for air-gap import fixes)

**Files to create:**
- `src/WsusManager.Core/Services/Interfaces/IContentResetService.cs` — Interface with: `Task<OperationResult> ResetContentAsync(IProgress<string> progress, CancellationToken ct)`
- `src/WsusManager.Core/Services/ContentResetService.cs` — Implementation: Validates `wsusutil.exe` exists at expected path. Runs `wsusutil.exe reset` via `IProcessRunner` with output streaming. Returns success/failure based on exit code.

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IContentResetService` in DI

**Verification:**
1. Unit test: `ResetContentAsync` calls ProcessRunner with correct executable path and "reset" argument
2. Unit test: Returns failure when wsusutil.exe is not found at expected path
3. Unit test: Progress output is streamed from process
4. `dotnet build` succeeds

---

### Plan 7: Diagnostics UI panel and ViewModel wiring

**What:** Wire the Diagnostics panel in the main window. When user clicks "Diagnostics" (sidebar or quick action), the operation panel shows a Diagnostics view with a "Run Diagnostics" button, a "Reset Content" button, and individual service start/stop buttons for SQL Server, WSUS, and IIS. The "Run Diagnostics" button invokes `IHealthService.RunDiagnosticsAsync` through `RunOperationAsync`. The "Reset Content" button shows a confirmation dialog before running `IContentResetService.ResetContentAsync`. Service buttons trigger immediate start/stop with dashboard refresh after state change.

**Requirements covered:** DIAG-01, DIAG-02, DIAG-03, DIAG-05, SVC-01, SVC-02, SVC-03

**Files to modify:**
- `src/WsusManager.App/ViewModels/MainViewModel.cs` — Add:
  - Constructor parameters for `IHealthService`, `IWindowsServiceManager`, `IContentResetService`
  - `RunDiagnosticsCommand` — Calls `RunOperationAsync("Diagnostics", ...)` with health service
  - `ResetContentCommand` — Shows confirmation dialog, then calls `RunOperationAsync("Content Reset", ...)` with content reset service
  - `StartServiceCommand` (RelayCommand<string>) — Starts named service, refreshes dashboard
  - `StopServiceCommand` (RelayCommand<string>) — Stops named service, refreshes dashboard
  - `StartAllServicesCommand` — Replaces placeholder `QuickStartServices`, uses `IWindowsServiceManager.StartAllServicesAsync`
  - Wire QuickDiagnostics to run diagnostics directly (instead of just navigating)
- `src/WsusManager.App/Views/MainWindow.xaml` — Replace operation panel placeholder with Diagnostics panel content:
  - "Run Diagnostics" button (BtnGreen style)
  - "Reset Content" button (BtnSec style)
  - Service control section: 3 rows (SQL Server, IIS, WSUS) each with service name, status dot, Start/Stop buttons
  - Status dots bound to service state from last dashboard refresh

**Files to modify:**
- `src/WsusManager.App/Program.cs` — Register `IHealthService`, `IContentResetService` in DI

**Verification:**
1. Clicking "Run Diagnostics" runs the health check pipeline and outputs all 12 check results to the log panel
2. "Reset Content" shows confirmation dialog; clicking Yes runs wsusutil reset
3. Individual service Start/Stop buttons work and dashboard refreshes immediately after
4. "Start Services" quick action button starts all 3 services in dependency order
5. All buttons disabled during operations (existing RunOperationAsync guard)
6. `dotnet build` succeeds

---

### Plan 8: Tests and integration verification

**What:** Add comprehensive unit tests for all Phase 3 services and ViewModel commands. Verify all success criteria. Update DI container tests to verify new service registrations.

**Requirements covered:** All Phase 3 requirements (verification)

**Files to create:**
- `src/WsusManager.Tests/Services/WindowsServiceManagerTests.cs` — Tests: start order, stop order, retry logic, status query, timeout handling
- `src/WsusManager.Tests/Services/FirewallServiceTests.cs` — Tests: rule existence check (found/missing), rule creation commands
- `src/WsusManager.Tests/Services/PermissionsServiceTests.cs` — Tests: sysadmin check (true/false/error), network service login, permission repair commands
- `src/WsusManager.Tests/Services/HealthServiceTests.cs` — Tests: all 12 checks run, auto-repair attempted, report summary correct, progress streaming, non-fixable issues
- `src/WsusManager.Tests/Services/ContentResetServiceTests.cs` — Tests: correct process invocation, missing executable, output streaming

**Files to modify:**
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` — Add tests: RunDiagnostics command, ResetContent command, StartService/StopService commands, StartAllServices wiring
- `src/WsusManager.Tests/Integration/DiContainerTests.cs` — Add resolution tests for IHealthService, IWindowsServiceManager, IFirewallService, IPermissionsService, IContentResetService

**Verification:**
1. `dotnet build` — 0 warnings, 0 errors
2. `dotnet test` — All tests pass (existing + new)
3. All 5 Phase 3 success criteria verified in tests:
   - Health check produces pass/fail for all checks
   - Auto-repair restarts stopped services, creates firewall rules, fixes permissions
   - Individual service start/stop works with dashboard refresh
   - Sysadmin check blocks with clear error message
   - Content reset completes without hanging

---

## Plan Summary

| Plan | Description | Requirements |
|------|-------------|--------------|
| 1 | Health check models and diagnostic result types | DIAG-03 |
| 2 | Windows service management service | SVC-01, SVC-02, SVC-03 |
| 3 | Firewall rule management service | FW-01, FW-02 |
| 4 | Permissions and SQL sysadmin check services | PERM-01, PERM-02, DIAG-04 |
| 5 | Health check service with auto-repair pipeline | DIAG-01, DIAG-02, DIAG-03 |
| 6 | Content reset service (wsusutil reset) | DIAG-05 |
| 7 | Diagnostics UI panel and ViewModel wiring | DIAG-01, DIAG-02, DIAG-03, DIAG-05, SVC-01, SVC-02, SVC-03 |
| 8 | Tests and integration verification | All Phase 3 (verification) |

## Execution Order

Plans 1 through 8 execute sequentially. Each plan builds on the previous:
- Plan 1 creates the data models that Plans 2-6 return and Plan 7 displays
- Plan 2 creates the service manager that Plans 5 and 7 use for service checks/repair
- Plan 3 creates the firewall service that Plan 5 uses for firewall checks/repair
- Plan 4 creates the permissions service that Plan 5 uses for permission checks/repair
- Plan 5 orchestrates Plans 2-4 into the unified diagnostics pipeline
- Plan 6 creates the content reset capability (independent of Plan 5, but needed by Plan 7)
- Plan 7 wires everything into the UI
- Plan 8 adds tests and verifies all success criteria

## Success Criteria (from Roadmap)

All five Phase 3 success criteria must be TRUE after Plan 8 completes:

1. Running Health Check produces a clear pass/fail report for each check: SQL Server connectivity, WSUS service state, IIS app pool, firewall ports 8530 and 8531, content directory permissions
2. Auto-repair during Health Check successfully restarts stopped services, re-creates missing firewall rules, and fixes content directory permissions without manual intervention
3. Users can start or stop SQL Server, WSUS, and IIS individually from the Service Management panel — and the dashboard reflects the new state without a manual refresh
4. Database operations are blocked with a clear error message when the current user lacks SQL sysadmin permissions
5. Running Content Reset (wsusutil reset) completes without hanging and reports success or failure in the log panel

---

*Phase: 03-diagnostics-and-service-management*
*Plan created: 2026-02-19*
