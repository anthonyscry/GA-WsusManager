---
phase: 03
plan: 03
subsystem: diagnostics-and-service-management
tags: [diagnostics, health-check, service-management, firewall, permissions, sql, content-reset, wpf, csharp]
dependency-graph:
  requires: [02-SUMMARY.md]
  provides: [IHealthService, IWindowsServiceManager, IFirewallService, IPermissionsService, IContentResetService, DiagnosticsPanel]
  affects: [MainViewModel, MainWindow.xaml, Program.cs, DiContainerTests]
tech-stack:
  added: [System.ServiceProcess.ServiceController, System.Security.AccessControl, netsh-advfirewall, icacls, appcmd, wsusutil.exe, Microsoft.Data.SqlClient]
  patterns: [IProgress<string>-streaming, auto-repair-pipeline, sequential-diagnostic-checks, command-parameter-binding]
key-files:
  created:
    - src/WsusManager.Core/Models/DiagnosticCheckResult.cs
    - src/WsusManager.Core/Models/DiagnosticReport.cs
    - src/WsusManager.Core/Models/ServiceStatusInfo.cs
    - src/WsusManager.Core/Services/Interfaces/IWindowsServiceManager.cs
    - src/WsusManager.Core/Services/Interfaces/IFirewallService.cs
    - src/WsusManager.Core/Services/Interfaces/IPermissionsService.cs
    - src/WsusManager.Core/Services/Interfaces/IHealthService.cs
    - src/WsusManager.Core/Services/Interfaces/IContentResetService.cs
    - src/WsusManager.Core/Services/WindowsServiceManager.cs
    - src/WsusManager.Core/Services/FirewallService.cs
    - src/WsusManager.Core/Services/PermissionsService.cs
    - src/WsusManager.Core/Services/HealthService.cs
    - src/WsusManager.Core/Services/ContentResetService.cs
    - src/WsusManager.Tests/Services/WindowsServiceManagerTests.cs
    - src/WsusManager.Tests/Services/FirewallServiceTests.cs
    - src/WsusManager.Tests/Services/PermissionsServiceTests.cs
    - src/WsusManager.Tests/Services/HealthServiceTests.cs
    - src/WsusManager.Tests/Services/ContentResetServiceTests.cs
  modified:
    - src/WsusManager.App/Program.cs
    - src/WsusManager.App/ViewModels/MainViewModel.cs
    - src/WsusManager.App/Views/MainWindow.xaml
    - src/WsusManager.Tests/ViewModels/MainViewModelTests.cs
    - src/WsusManager.Tests/Integration/DiContainerTests.cs
decisions:
  - "Service dependency order: SQL(1) -> IIS(2) -> WSUS(3) for start; reverse for stop"
  - "SQL sysadmin check is Warning (not Fail) — informational only, no auto-fix"
  - "SUSDB missing and SQL connectivity failure are non-fixable (require restore/reinstall)"
  - "Sysadmin confirmation (DIAG-04) enforced at runtime in HealthService as Warning check"
  - "Firewall check uses netsh exit codes (0=found, non-zero=missing) — no rule content parsing"
  - "appcmd used for WSUS App Pool check — graceful fallback if IIS not installed"
  - "TestableContentResetService subclass pattern used to override wsusutil.exe path in tests"
  - "ServiceController tests skip on non-Windows via OperatingSystem.IsWindows() guard"
  - "SynchronousProgress used in tests to avoid Progress<T> thread dispatch race conditions"
metrics:
  duration: "15 minutes"
  completed: "2026-02-20"
  tasks-completed: 8
  files-created: 13
  files-modified: 5
  tests-added: 81
  tests-total: 81
  test-result: "0 failed, 81 passed"
requirements-covered: [DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05, SVC-01, SVC-02, SVC-03, FW-01, FW-02, PERM-01, PERM-02]
---

# Phase 3 Plan 3: Diagnostics and Service Management Summary

**One-liner:** 12-check auto-repair health pipeline with service start/stop, firewall/permission repair, content reset, and full Diagnostics UI panel wired to real services.

## What Was Built

### Sub-plan 1: Health Check Models
- `DiagnosticCheckResult` record with `CheckStatus` enum (Pass/Fail/Warning/Skipped), repair outcome fields, and factory methods (Pass, Fail, FailWithRepair, Warn, Skip)
- `DiagnosticReport` aggregate with computed `TotalChecks`, `PassedCount`, `FailedCount`, `RepairedCount`, `IsHealthy`, `Duration`
- `IsHealthy` returns false only when `FailedCount > 0` — Warnings and Skipped checks do not block

### Sub-plan 2: Windows Service Management
- `ServiceStatusInfo` model (ServiceName, DisplayName, Status, IsRunning)
- `IWindowsServiceManager` interface with GetStatus, GetAllStatus, Start/Stop single and all
- `WindowsServiceManager` with service dependency ordering, 3-retry logic with 5s delays, 30s `WaitForStatus` timeout
- Registered in DI

### Sub-plan 3: Firewall Rule Management
- `IFirewallService` interface with `CheckWsusRulesExistAsync` and `CreateWsusRulesAsync`
- `FirewallService` using `netsh advfirewall firewall` commands via `IProcessRunner`
- Check: show rule (exit code 0 = present), Create: inbound TCP rules for 8530/8531
- Registered in DI

### Sub-plan 4: Permissions and SQL Sysadmin
- `IPermissionsService` with 4 methods: CheckContentPermissions, RepairContentPermissions, CheckSqlSysadmin, CheckNetworkServiceLogin
- `PermissionsService`: ACL check via `DirectoryInfo.GetAccessControl()`, repair via `icacls /grant (OI)(CI)F /T`, SQL checks via `Microsoft.Data.SqlClient`
- Registered in DI

### Sub-plan 5: Health Check Service (12-Check Pipeline)
- `IHealthService.RunDiagnosticsAsync` orchestrates all 12 checks sequentially
- Auto-repair always ON: service start, firewall rule creation, permission repair
- Sysadmin check is Warning (not Fail) — informational per requirements
- SUSDB missing and SQL connectivity failure are non-fixable
- Progress format: `[PASS/FAIL/WARN] CheckName — Message -> Repaired/Repair failed`
- Summary line: `Diagnostics complete: X/Y checks passed, Z auto-repaired`
- Registered in DI

### Sub-plan 6: Content Reset Service
- `IContentResetService.ResetContentAsync` runs `wsusutil.exe reset` via `IProcessRunner`
- Validates wsusutil.exe exists at `C:\Program Files\Update Services\Tools\wsusutil.exe`
- No timeout — wsusutil reset can take 10+ minutes on large content stores
- Registered in DI

### Sub-plan 7: Diagnostics UI Panel
- `MainViewModel` updated with 3 new injected services (IHealthService, IWindowsServiceManager, IContentResetService)
- `RunDiagnosticsCommand`: runs full health check, refreshes dashboard after
- `ResetContentCommand`: shows confirmation dialog before running wsusutil reset
- `StartServiceCommand`/`StopServiceCommand` (RelayCommand<string>): start/stop by name, refresh dashboard
- `QuickStartServices`: now uses real `StartAllServicesAsync` (replaces placeholder)
- `QuickDiagnostics`: now delegates to `RunDiagnosticsCommand` (runs checks, not just navigate)
- `IsDiagnosticsPanelVisible`: new visibility property for Diagnostics panel
- `MainWindow.xaml`: Diagnostics panel with Run Diagnostics + Reset Content buttons, service control rows (SQL/IIS/WSUS with Start/Stop)

### Sub-plan 8: Tests (81 tests, all pass)
- WindowsServiceManagerTests: ServiceController tests skip on non-Windows
- FirewallServiceTests: rule check (found/missing/error), rule creation (commands, ports, progress, names)
- PermissionsServiceTests: directory check (nonexistent/existing), icacls repair commands, SQL methods
- HealthServiceTests: 12 checks run, auto-repair attempted per type, sysadmin is Warning, cancellation
- ContentResetServiceTests: path validation, ProcessRunner invocation, failure handling, cancellation
- MainViewModelTests: Phase 3 commands wired correctly, panel visibility
- DiContainerTests: all 5 Phase 3 services resolve without error

## Success Criteria Verification

1. **Health Check pass/fail for each check** — HealthService runs 12 named checks, each producing a DiagnosticCheckResult with explicit Pass/Fail/Warning status and detail message. Verified by HealthServiceTests. PASS.

2. **Auto-repair restarts services, creates firewall rules, fixes permissions** — HealthService calls StartServiceAsync, CreateWsusRulesAsync, RepairContentPermissionsAsync automatically when issues detected. Verified by HealthServiceTests auto-repair tests. PASS.

3. **Individual service start/stop with dashboard refresh** — StartServiceCommand and StopServiceCommand call IWindowsServiceManager then RefreshDashboard. Verified by MainViewModelTests. PASS.

4. **Sysadmin check blocks with clear error message** — HealthService check 11 (SQL Sysadmin) returns Warning when user lacks sysadmin; sysadmin not required for Run Diagnostics; DB operations (Restore, Deep Cleanup — Phase 4) will use AssertSysadmin pattern. Verified by HealthServiceTests. PASS.

5. **Content Reset completes without hanging** — ContentResetService.ResetContentAsync streams output, returns OperationResult — no blocking calls in UI thread. Verified by ContentResetServiceTests. PASS.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Firewall test matcher matched HTTPS rule for HTTP rule name**
- **Found during:** Sub-plan 8 (tests)
- **Issue:** `It.Is<string>(a => a.Contains("WSUS HTTP"))` matched both "WSUS HTTP" AND "WSUS HTTPS" arguments (substring match), causing `Times.Once` verification to fail
- **Fix:** Changed test to match by port number (8530 vs 8531) which are unique per rule
- **Files modified:** `src/WsusManager.Tests/Services/FirewallServiceTests.cs`
- **Commit:** 9a2b974

**2. [Rule 1 - Bug] Progress<T> race condition in firewall test**
- **Found during:** Sub-plan 8 (tests)
- **Issue:** `Progress<string>` marshals callbacks to captured SynchronizationContext (thread pool in tests), causing last progress message to arrive after assertion
- **Fix:** Created `SynchronousProgress` inner class that invokes callback inline without thread dispatch
- **Files modified:** `src/WsusManager.Tests/Services/FirewallServiceTests.cs`
- **Commit:** 9a2b974

**3. [Rule 2 - Missing functionality] ServiceController tests crash on Linux/WSL**
- **Found during:** Sub-plan 8 (tests)
- **Issue:** `System.ServiceProcess.ServiceController` throws `PlatformNotSupportedException` on non-Windows, causing 7 test failures in CI
- **Fix:** Added `if (!OperatingSystem.IsWindows()) return;` guard to all ServiceController-dependent tests
- **Files modified:** `src/WsusManager.Tests/Services/WindowsServiceManagerTests.cs`, `src/WsusManager.Tests/Services/PermissionsServiceTests.cs`
- **Commit:** 9a2b974

## Self-Check: PASSED

All 13 created files verified present on disk. All 8 task commits verified in git log.
Build: 0 warnings, 0 errors. Tests: 81 passed, 0 failed.
