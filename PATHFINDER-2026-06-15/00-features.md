# Feature Inventory

Reviewed from `agent://FeatureDiscovery` and current repo sources on 2026-06-15.

## Boundary decisions

I kept 10 features.

Why:
- The GUI shell/router is a distinct orchestration layer over the runtime features.
- Dashboard/status presentation has a separate cache/view-model seam from diagnostics and maintenance.
- Install/provisioning, online maintenance, air-gap transfer, diagnostics/repair, scheduling, and GPO/client deployment each have separate entry points and module clusters.
- Database utilities are reused by both diagnostics and maintenance but are still a coherent subsystem with their own exported API.
- Config/utilities/history/notifications/build/lab are support systems, not a user-facing operator workflow, but they are a meaningful boundary for duplication analysis because many features depend on them.

## Feature list

### 1. GUI shell & operation orchestration
- Entry points:
  - `Scripts/WsusManagementGui.ps1:15`
  - `Scripts/WsusManagementGui.ps1:241-265`
  - `Scripts/WsusManagementGui.ps1:2996-3258`
  - `Scripts/WsusManagementGui.ps1:3273-3424`
- Core files:
  - `Scripts/WsusManagementGui.ps1`
  - `Modules/WsusOperationPlan.psm1`
  - `Modules/WsusOperationRunner.psm1`
  - `Modules/WsusGuiShell.psm1`
  - `Modules/WsusOperationCompletion.psm1`
  - `Modules/WsusDialogs.psm1`
  - `Modules/AsyncHelpers.psm1`
- Purpose:
  - WPF shell, navigation, dialogs, bottom log/status UI, keyboard shortcuts, and child-process operation lifecycle.

### 2. Dashboard, auto-detection & health presentation
- Entry points:
  - `Scripts/WsusManagementGui.ps1:1137-1152`
  - `Scripts/WsusManagementGui.ps1:1215-1223`
- Core files:
  - `Modules/WsusAutoDetection.psm1`
  - `Modules/WsusDashboardViewModel.psm1`
  - `Modules/WsusHealth.psm1`
  - `Modules/WsusTrending.psm1`
- Purpose:
  - Service/disk/database/task/internet status, cached dashboard snapshots, health score, and DB trend presentation.

### 3. Install & provisioning
- Entry points:
  - `Scripts/WsusManagementGui.ps1:3075-3117`
  - `Scripts/Install-WsusWithSqlExpress.ps1:25-48`
  - `Scripts/Invoke-WsusManagement.ps1:2006-2006`
- Core files:
  - `Scripts/Install-WsusWithSqlExpress.ps1`
  - `Modules/WsusProvisioning.psm1`
  - `Modules/WsusConfig.psm1`
  - `Modules/WsusFirewall.psm1`
  - `Modules/WsusPermissions.psm1`
- Purpose:
  - SQL Express/WSUS role install, installer-path resolution, post-installation configuration, firewall, registry, service, and IIS content-path setup.

### 4. Online sync, product policy, maintenance, backup & export
- Entry points:
  - `Scripts/WsusManagementGui.ps1:3151-3157`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:75-110`
  - `Scripts/Invoke-WsusManagement.ps1:2010-2010`
- Core files:
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
  - `Modules/WsusDatabase.psm1`
  - `Modules/WsusServices.psm1`
  - `Modules/WsusConfig.psm1`
- Purpose:
  - Microsoft Update sync, selected-product subscription, decline/approval policy, cleanup, backup, and optional full export.

### 5. Air-gap transfer, import/export & database restore
- Entry points:
  - `Scripts/WsusManagementGui.ps1:3119-3149`
  - `Scripts/Invoke-WsusManagement.ps1:77-124`
  - `Scripts/Invoke-WsusManagement.ps1:2027-2048`
- Core files:
  - `Scripts/Invoke-WsusManagement.ps1`
  - `Modules/WsusExport.psm1`
  - `Modules/WsusProvisioning.psm1`
  - `Modules/WsusOperationPlan.psm1`
- Purpose:
  - Move backups/content to and from external media or shares, normalize robocopy transfer plans, restore SUSDB safely, and re-verify content.

### 6. Diagnostics, health checks & repair actions
- Entry points:
  - `Scripts/WsusManagementGui.ps1:3171-3176`
  - `Scripts/Invoke-WsusManagement.ps1:1546-1579`
  - `Scripts/Invoke-WsusManagement.ps1:1610-1699`
- Core files:
  - `Modules/WsusHealth.psm1`
  - `Modules/WsusDiagnosticResult.psm1`
  - `Modules/WsusHostEnvironment.psm1`
  - `Modules/WsusRepairPlan.psm1`
  - `Modules/WsusRepairHarness.psm1`
- Purpose:
  - Standard/deep diagnostics, health score, report merging, evidence shaping, and safe auto-fix via named repair actions.

### 7. Database maintenance utilities
- Entry points:
  - `Scripts/WsusManagementGui.ps1:3166-3169`
  - `Scripts/Invoke-WsusManagement.ps1:1710-1916`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1405-1454`
- Core files:
  - `Modules/WsusDatabase.psm1`
  - `Modules/WsusUtilities.psm1`
- Purpose:
  - SUSDB sizing/stats, supersession cleanup, index maintenance, shrink, backup integrity/consistency helpers, and sqlcmd fallback.

### 8. Scheduled maintenance automation
- Entry points:
  - `Scripts/WsusManagementGui.ps1:2470-2798`
  - `Scripts/WsusManagementGui.ps1:3158-3165`
- Core files:
  - `Modules/WsusScheduledTask.psm1`
  - `Modules/WsusOperationPlan.psm1`
  - `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
- Purpose:
  - Create/update/remove/start Windows Scheduled Tasks that run maintenance profiles as a configured user.

### 9. Client deployment, GPO import & check-in
- Entry points:
  - `Scripts/WsusManagementGui.ps1:3307-3386`
  - `DomainController/Set-WsusGroupPolicy.ps1:56-60`
  - `DomainController/Set-WsusGroupPolicy.ps1:543-635`
  - `Scripts/Invoke-WsusClientCheckIn.ps1:24-26`
- Core files:
  - `DomainController/Set-WsusGroupPolicy.ps1`
  - `DomainController/WSUS GPOs/*`
  - `Scripts/Invoke-WsusClientCheckIn.ps1`
  - `Modules/WsusUtilities.psm1`
- Purpose:
  - Stage/import air-gap WSUS GPO backups, set WSUS URLs/deadlines, link GPOs, push gpupdate via schtasks/RPC, and force client re-registration/detection.

### 10. Configuration, shared utilities, history, notifications & support evidence
- Entry points:
  - `Modules/WsusConfig.psm1:153-180`
  - `Modules/WsusConfig.psm1:622-658`
  - `Modules/WsusUtilities.psm1:89-145`
  - `Modules/WsusUtilities.psm1:408-555`
  - `Modules/WsusUtilities.psm1:923-994`
  - `Modules/WsusHistory.psm1:134-185`
  - `Modules/WsusNotification.psm1:193-281`
  - `Tests/WsusArchitectureInterfaces.Tests.ps1:1-30`
  - `build/Invoke-ShipReadiness.ps1:1-12`
  - `lab/New-WsusLab.ps1:1-17`
- Core files:
  - `Modules/WsusConfig.psm1`
  - `Modules/WsusUtilities.psm1`
  - `Modules/WsusHistory.psm1`
  - `Modules/WsusNotification.psm1`
  - `Modules/WsusTestHarness.psm1`
  - `Tests/*.ps1`
  - `build/*.ps1`
  - `lab/*.ps1`
- Purpose:
  - Runtime constants/version/paths, logging, SQL wrappers, path/security helpers, secret environment handling, operation history, notifications, test harnesses, release validation scripts, and lab scaffolding.

## Current-state caveats
- `CLAUDE.md` still mentions `WsusOfficeUpdates.psm1` and `WsusProcessHost` as active support modules (`CLAUDE.md:45-48`, `CLAUDE.md:107-108`), but current source inventory no longer supports Office C2R and `Modules/WsusProcessHost.psm1:1-2` says it was inlined into `WsusOperationRunner`.
- These stale docs matter for duplication analysis because they show drift between runtime architecture and support documentation.
