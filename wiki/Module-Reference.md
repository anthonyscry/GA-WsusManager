# Module Reference

High-level map of the PowerShell modules in WSUS Manager v4.1.0.

## Core runtime

| Module | Purpose |
|---|---|
| `WsusConfig.psm1` | Defaults, timeouts, health weights, version helper. |
| `WsusUtilities.psm1` | Logging, admin checks, SQL helpers, process helpers. |
| `WsusHostEnvironment.psm1` | Host adapters used by diagnostics/tests. |
| `WsusOperationPlan.psm1` | Builds child-process operation plans and secret env handoff. |
| `WsusOperationRunner.psm1` | Starts and tracks long-running operations. |
| `WsusOperationCompletion.psm1` | Normalizes completion/result handling. |
| `WsusGuiShell.psm1` | GUI shell/status helper functions. |
| `WsusDashboardViewModel.psm1` | Shapes dashboard data for display. |

## WSUS operations

| Module | Purpose |
|---|---|
| `WsusDatabase.psm1` | SUSDB size, backup, SQL access, cleanup helpers. |
| `WsusExport.psm1` | Robocopy content transfer helpers. |
| `WsusScheduledTask.psm1` | Scheduled Online Sync task registration. |
| `WsusProvisioning.psm1` | Install/restore path and backup discovery helpers. |
| `WsusServices.psm1` | SQL/WSUS/IIS service start/stop/status helpers. |
| `WsusFirewall.psm1` | Firewall rule checks and repair. |
| `WsusPermissions.psm1` | `C:\WSUS` ACL checks and repair. |

## Health, repair, and diagnostics

| Module | Purpose |
|---|---|
| `WsusHealth.psm1` | Health checks, Health Score, diagnostics, repair orchestration. |
| `WsusDiagnosticResult.psm1` | Diagnostic result object helpers. |
| `WsusRepairPlan.psm1` | Repair plan composition. |
| `WsusRepairHarness.psm1` | Compatibility wrapper for repair execution. |
| `WsusAutoDetection.psm1` | Dashboard detection/cache helpers. |
| `WsusStartupProbe.psm1` | GUI startup probe support for tests. |

## UX support

| Module | Purpose |
|---|---|
| `WsusDialogs.psm1` | WPF dialog helpers. |
| `WsusHistory.psm1` | Operation history at `%APPDATA%\WsusManager\history.json`. |
| `WsusNotification.psm1` | Toast/balloon/log notification fallback. |
| `WsusTrending.psm1` | SUSDB size trend storage and projection. |
| `AsyncHelpers.psm1` | Runspace/dispatcher async helpers retained for shared support. |

## Test/support wrappers

| Module | Purpose |
|---|---|
| `WsusProcessHost.psm1` | Compatibility wrapper; process hosting lives in operation modules. |
| `WsusTestHarness.psm1` | Shared Pester/GUI test helpers. |

## Public scripts

| Script | Purpose |
|---|---|
| `Scripts\WsusManagementGui.ps1` | Main WPF GUI source compiled into `GA-WsusManager.exe`. |
| `Scripts\Invoke-WsusManagement.ps1` | CLI/router for restore, Robocopy, cleanup, diagnostics, repair, and reset. |
| `Scripts\Invoke-WsusMonthlyMaintenance.ps1` | Online sync, cleanup, backup, and approved package staging. |
| `Scripts\Install-WsusWithSqlExpress.ps1` | SQL Express + WSUS installer. |
| `Scripts\Set-WsusHttps.ps1` | Optional HTTPS setup. |
| `Scripts\Invoke-WsusClientCheckIn.ps1` | Client check-in helper. |
| `DomainController\Set-WsusGroupPolicy.ps1` | GPO import/link/OU setup for air-gapped domains. |

## Related pages

- [[Developer Guide]]
- [[Configuration Guide]]
- [[Troubleshooting]]
