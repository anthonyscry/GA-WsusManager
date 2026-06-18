# Feature Inventory

Reviewed on 2026-06-18 from `agent://FeatureDiscovery` plus current repo source reads.

## Boundary decisions

I kept 10 features.

Why:
- The GUI shell/router is a distinct orchestration layer over the runtime workflows.
- Dashboard/status presentation has a separate cache/view-model seam from diagnostics and maintenance.
- Install/provisioning, online maintenance, transfer/restore, diagnostics/repair, scheduling, and client deployment each have separate entry points and module clusters.
- Database utilities are reused by diagnostics and maintenance, but still expose a coherent subsystem with their own exported API.
- HTTPS remains a top-level operator workflow, but its code surface is small and tightly coupled to provisioning. I kept it inside install & provisioning rather than spending a standalone feature slot on a one-script utility.
- Config/utilities/history/notifications/services/firewall/permissions are support systems, not standalone operator journeys, but they are a meaningful boundary for duplication analysis because most workflows depend on them.

## Feature list

### 1. GUI shell & operation orchestration
- Entry points:
  - `Scripts/WsusManagementGui.ps1:15`
  - `Scripts/WsusManagementGui.ps1:525-541`
  - `Scripts/WsusManagementGui.ps1:2996-3060`
  - `Scripts/WsusManagementGui.ps1:3307-3411`
  - `Modules/WsusOperationRunner.psm1:250`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `Modules/WsusOperationPlan.psm1`
  - `Modules/WsusOperationRunner.psm1`
  - `Modules/WsusGuiShell.psm1`
  - `Modules/WsusDialogs.psm1`
  - `Modules/WsusOperationCompletion.psm1`
  - `Modules/WsusStartupProbe.psm1`
  - `Modules/AsyncHelpers.psm1`
- Purpose:
  - WPF shell, navigation, popups/dialogs, keyboard shortcuts, child-process command planning, embedded/live-terminal execution, timeout handling, cancellation, and completion routing.

### 2. Dashboard, auto-detection & health presentation
- Entry points:
  - `Scripts/WsusManagementGui.ps1:1202-1224`
  - `Modules/WsusAutoDetection.psm1:48`
  - `Modules/WsusAutoDetection.psm1:89`
  - `Modules/WsusAutoDetection.psm1:123`
  - `Modules/WsusAutoDetection.psm1:198`
  - `Modules/WsusAutoDetection.psm1:268`
  - `Modules/WsusDashboardViewModel.psm1:18`
  - `Modules/WsusHealth.psm1:223`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `Modules/WsusAutoDetection.psm1`
  - `Modules/WsusDashboardViewModel.psm1`
  - `Modules/WsusHealth.psm1`
  - `Modules/WsusTrending.psm1`
  - `Modules/WsusScheduledTask.psm1`
- Purpose:
  - Service/disk/database/task/certificate/server-mode telemetry, cached dashboard snapshots, health score calculation, and dashboard card/view-model presentation.

### 3. Install & provisioning
- Entry points:
  - `Scripts/WsusManagementGui.ps1:528`
  - `Scripts/WsusManagementGui.ps1:3463`
  - `Scripts/Install-WsusWithSqlExpress.ps1:25-47`
  - `Scripts/Install-WsusWithSqlExpress.ps1:307-342`
  - `Scripts/Set-WsusHttps.ps1:40`
  - `Scripts/Set-WsusHttps.ps1:171-243`
  - `Modules/WsusProvisioning.psm1:53`
  - `Modules/WsusOperationPlan.psm1:86`
- Core files:
  - `Scripts/Install-WsusWithSqlExpress.ps1`
  - `Scripts/Set-WsusHttps.ps1`
  - `Modules/WsusProvisioning.psm1`
  - `Modules/WsusOperationPlan.psm1`
  - `Modules/WsusFirewall.psm1`
  - `Modules/WsusPermissions.psm1`
  - `Modules/WsusServices.psm1`
  - `Modules/WsusDatabase.psm1`
- Purpose:
  - SQL Express media discovery, SA password handling via environment secret, WSUS role/post-install configuration, firewall/permission/service initialization, optional downstream configuration, and HTTPS enablement.

### 4. Online sync, product policy, maintenance, backup & export
- Entry points:
  - `Scripts/WsusManagementGui.ps1:534`
  - `Scripts/WsusManagementGui.ps1:3390`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:76-109`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:247-276`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:724`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1304`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1504`
  - `Modules/WsusOperationPlan.psm1:106`
- Core files:
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
  - `Modules/WsusDatabase.psm1`
  - `Modules/WsusExport.psm1`
  - `Modules/WsusServices.psm1`
  - `Modules/WsusConfig.psm1`
  - `Modules/WsusOperationPlan.psm1`
- Purpose:
  - Microsoft Update sync, selected-product/category policy, decline/approval policy, cleanup, backup, and optional export for the online/source WSUS server.

### 5. Air-gap transfer, import/export & restore
- Entry points:
  - `Scripts/WsusManagementGui.ps1:537`
  - `Scripts/WsusManagementGui.ps1:3389`
  - `Scripts/Invoke-WsusManagement.ps1:80-124`
  - `Scripts/Invoke-WsusManagement.ps1:500`
  - `Scripts/Invoke-WsusManagement.ps1:2022-2077`
  - `Modules/WsusExport.psm1:154`
  - `Modules/WsusExport.psm1:378`
  - `Modules/WsusExport.psm1:430`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `Scripts/Invoke-WsusManagement.ps1`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
  - `Modules/WsusExport.psm1`
  - `Modules/WsusOperationPlan.psm1`
  - `Modules/WsusProvisioning.psm1`
- Purpose:
  - Move `WsusContent` and optional SUSDB backups to and from removable media or shares, normalize robocopy transfer plans, and stage air-gap restore workflows.

### 6. Diagnostics, health checks & repair actions
- Entry points:
  - `Scripts/WsusManagementGui.ps1:540`
  - `Scripts/WsusManagementGui.ps1:3397-3401`
  - `Scripts/Invoke-WsusManagement.ps1:92-96`
  - `Scripts/Invoke-WsusManagement.ps1:1627`
  - `Modules/WsusHealth.psm1:391`
  - `Modules/WsusHealth.psm1:629`
  - `Modules/WsusRepairPlan.psm1:18`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `Scripts/Invoke-WsusManagement.ps1`
  - `Modules/WsusHealth.psm1`
  - `Modules/WsusDiagnosticResult.psm1`
  - `Modules/WsusRepairPlan.psm1`
  - `Modules/WsusRepairHarness.psm1`
  - `Modules/WsusHostEnvironment.psm1`
  - `Modules/WsusPermissions.psm1`
  - `Modules/WsusFirewall.psm1`
  - `Modules/WsusServices.psm1`
- Purpose:
  - Standard and deep diagnostics for services, SQL networking, firewall, IIS content path, permissions, event logs, stuck downloads/import issues, plus mapping repairable findings to host actions.

### 7. Database maintenance utilities
- Entry points:
  - `Scripts/WsusManagementGui.ps1:529-530`
  - `Scripts/WsusManagementGui.ps1:3392-3395`
  - `Scripts/Invoke-WsusManagement.ps1:1727`
  - `Scripts/Invoke-WsusManagement.ps1:1939`
  - `Modules/WsusDatabase.psm1:50`
  - `Modules/WsusDatabase.psm1:226`
  - `Modules/WsusDatabase.psm1:411`
  - `Modules/WsusDatabase.psm1:527`
  - `Modules/WsusDatabase.psm1:806`
- Core files:
  - `Modules/WsusDatabase.psm1`
  - `Scripts/Invoke-WsusManagement.ps1`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
  - `Modules/WsusUtilities.psm1`
- Purpose:
  - SUSDB sizing/stats, backup integrity/consistency, SQL login repair, deep cleanup helpers, index/stat maintenance, shrink, and sqlcmd fallback paths.

### 8. Scheduled maintenance automation
- Entry points:
  - `Scripts/WsusManagementGui.ps1:535`
  - `Scripts/WsusManagementGui.ps1:2470-2528`
  - `Scripts/WsusManagementGui.ps1:3391`
  - `Modules/WsusScheduledTask.psm1:93`
  - `Modules/WsusOperationPlan.psm1:125`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `Modules/WsusScheduledTask.psm1`
  - `Modules/WsusOperationPlan.psm1`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
- Purpose:
  - Create/update/remove/start Windows Scheduled Tasks that run monthly maintenance profiles with stored credentials and schedule metadata.

### 9. Client deployment, GPO import & client check-in
- Entry points:
  - `Scripts/WsusManagementGui.ps1:531`
  - `Scripts/WsusManagementGui.ps1:3308-3380`
  - `DomainController/Set-WsusGroupPolicy.ps1:57-60`
  - `DomainController/Set-WsusGroupPolicy.ps1:288`
  - `DomainController/Set-WsusGroupPolicy.ps1:543-636`
  - `Scripts/Invoke-WsusClientCheckIn.ps1:24`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `DomainController/Set-WsusGroupPolicy.ps1`
  - `DomainController/WSUS GPOs/`
  - `Scripts/Invoke-WsusClientCheckIn.ps1`
  - `Modules/WsusUtilities.psm1`
- Purpose:
  - Stage/import air-gap WSUS GPO backups, set WSUS URLs and firewall/update policies, link GPOs, push `gpupdate` via `schtasks`, and force client re-registration/detection.

### 10. Configuration, shared utilities & operator support
- Entry points:
  - `Modules/WsusConfig.psm1:153`
  - `Modules/WsusConfig.psm1:658`
  - `Modules/WsusUtilities.psm1:408`
  - `Modules/WsusUtilities.psm1:923`
  - `Modules/WsusServices.psm1:110`
  - `Modules/WsusFirewall.psm1:198`
  - `Modules/WsusPermissions.psm1:21`
  - `Modules/WsusHistory.psm1:134`
  - `Modules/WsusNotification.psm1:69`
  - `Modules/WsusOperationCompletion.psm1:1`
  - `Modules/WsusHostEnvironment.psm1:11`
- Core files:
  - `Modules/WsusConfig.psm1`
  - `Modules/WsusUtilities.psm1`
  - `Modules/WsusServices.psm1`
  - `Modules/WsusFirewall.psm1`
  - `Modules/WsusPermissions.psm1`
  - `Modules/WsusHistory.psm1`
  - `Modules/WsusNotification.psm1`
  - `Modules/WsusOperationCompletion.psm1`
  - `Modules/WsusHostEnvironment.psm1`
- Purpose:
  - Runtime constants/version/paths, logging, sqlcmd wrappers, secret environment handling, canonical service/firewall/ACL helpers, operation history, notifications, and host-state adapters reused across workflows.

## Current-state caveats
- `FeatureDiscovery` intentionally did not consult the older `PATHFINDER-2026-06-15/` outputs. Boundary decisions above are based on current source plus that fresh discovery pass.
- `Modules/WsusProcessHost.psm1` still exists in the tree, but the active process lifecycle sits in `Modules/WsusOperationRunner.psm1`; do not model `WsusProcessHost` as a live subsystem.
