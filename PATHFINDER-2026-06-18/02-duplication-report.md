# Duplication Report

Reviewed from `agent://WithinFeatureDup`, `agent://CrossFeatureDup`, `PATHFINDER-2026-06-18/00-features.md`, and the current `01-flowcharts/` artifacts.

## Summary

Most of the codebase already has good subsystem seams. The duplication that still matters clusters around a few patterns:
- top-level scripts bypassing existing shared modules;
- partial unification, where one path uses the shared engine and another keeps an older inline copy;
- read-model drift, where dashboard/health/task status each probe the same host state differently;
- secret/path/JSON persistence helpers repeated near the UI.

## Consolidation-worthy duplication

### 1. SQL access, sqlcmd discovery, and backup verification fork across features
- Evidence:
  - Shared adapter path: `Modules/WsusUtilities.psm1:408`, `Modules/WsusUtilities.psm1:500`, `Modules/WsusUtilities.psm1:521`, `Modules/WsusUtilities.psm1:527`
  - Shared DB callers: `Modules/WsusDatabase.psm1:68`, `Modules/WsusDatabase.psm1:578`, `Modules/WsusDatabase.psm1:588`, `Modules/WsusDatabase.psm1:823`
  - GUI preflight/raw sqlcmd: `Scripts/WsusManagementGui.ps1:3008`, `Scripts/WsusManagementGui.ps1:3016`, `Scripts/WsusManagementGui.ps1:3481`
  - Management script raw sqlcmd / direct verification: `Scripts/Invoke-WsusManagement.ps1:279`, `Scripts/Invoke-WsusManagement.ps1:390`, `Scripts/Invoke-WsusManagement.ps1:570`
  - Monthly maintenance direct `Invoke-Sqlcmd` checks: `Scripts/Invoke-WsusMonthlyMaintenance.ps1:420`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1247`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1429`
  - Dashboard/auto-detection separate SQL probing: `Modules/WsusAutoDetection.psm1:163`, `Modules/WsusAutoDetection.psm1:726`
- Why they diverged:
  - `Invoke-WsusSqlcmd` arrived after older script-local probes existed.
  - Bootstrap/install-time code wanted a path that still works before the whole module stack is healthy.
  - Restore verification kept a fail-fast wrapper instead of calling `Test-WsusBackupIntegrity`.
- Verdict:
  - Mostly accidental duplication.
  - Narrow legitimate exception: early install/bootstrap can keep a minimal raw-`sqlcmd.exe` path if the shared adapter cannot be trusted that early.

### 2. Install/provisioning keeps inline copies of the firewall, ACL, and service baselines already modeled in modules
- Evidence:
  - Inline firewall setup: `Scripts/Install-WsusWithSqlExpress.ps1:793`, `Scripts/Install-WsusWithSqlExpress.ps1:797`, `Scripts/Install-WsusWithSqlExpress.ps1:805`, `Scripts/Install-WsusWithSqlExpress.ps1:956`, `Scripts/Install-WsusWithSqlExpress.ps1:965`
  - Canonical firewall helpers: `Modules/WsusFirewall.psm1:122`, `Modules/WsusFirewall.psm1:126`, `Modules/WsusFirewall.psm1:198`, `Modules/WsusFirewall.psm1:232`, `Modules/WsusFirewall.psm1:318`
  - Inline ACL setup: `Scripts/Install-WsusWithSqlExpress.ps1:627`, `Scripts/Install-WsusWithSqlExpress.ps1:631`, `Scripts/Install-WsusWithSqlExpress.ps1:637`, `Scripts/Install-WsusWithSqlExpress.ps1:647`, `Scripts/Install-WsusWithSqlExpress.ps1:1053`
  - Canonical ACL helpers: `Modules/WsusPermissions.psm1:54`, `Modules/WsusPermissions.psm1:58`, `Modules/WsusPermissions.psm1:64`, `Modules/WsusPermissions.psm1:77`, `Modules/WsusPermissions.psm1:226`
  - Inline service verification/startup: `Scripts/Install-WsusWithSqlExpress.ps1:981`, `Scripts/Install-WsusWithSqlExpress.ps1:984`, `Scripts/Install-WsusWithSqlExpress.ps1:990`, `Scripts/Install-WsusWithSqlExpress.ps1:1001`, `Scripts/Install-WsusWithSqlExpress.ps1:1009`
  - Canonical service helpers: `Modules/WsusServices.psm1:53`, `Modules/WsusServices.psm1:62`, `Modules/WsusServices.psm1:119`, `Modules/WsusServices.psm1:146`, `Modules/WsusServices.psm1:148`
- Why they diverged:
  - The installer stayed self-contained while the modules later became the canonical baseline for repair/maintenance.
- Verdict:
  - Accidental duplication for standard WSUS/SQL rules, standard content ACLs, and routine service start/status logic.
  - Legitimate specialization remains around installer-only sequencing such as WID removal, SQL media setup, and WSUS postinstall ordering.

### 3. Transfer paths are only partially unified; monthly export still stages `.bak` outside the shared engine
- Evidence:
  - Shared transfer package supports DB copy: `Modules/WsusExport.psm1:430`, `Modules/WsusExport.psm1:497`, `Modules/WsusExport.psm1:511`
  - CLI export/import already uses it: `Scripts/Invoke-WsusManagement.ps1:694`, `Scripts/Invoke-WsusManagement.ps1:843`, `Scripts/Invoke-WsusManagement.ps1:1512`
  - Monthly export still does manual backup copy first: `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1514`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1531`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1547`
  - GUI generic transfer uses a different path entirely: `Scripts/WsusManagementGui.ps1:3147`, `Modules/WsusOperationPlan.psm1:173`
- Why they diverged:
  - CLI import/export was refactored onto `Invoke-WsusTransferPackage`.
  - Monthly maintenance kept its older “copy `.bak`, then copy content” split.
  - GUI “Robocopy” stayed as a generic folder copy, not a WSUS package transfer.
- Verdict:
  - Monthly `.bak` staging is accidental duplication.
  - GUI generic transfer vs WSUS package import/export is legitimate specialization.

### 4. Dashboard task status is duplicated instead of reusing the scheduler subsystem
- Evidence:
  - Dashboard task probes: `Modules/WsusAutoDetection.psm1:89`, `Modules/WsusAutoDetection.psm1:101`, `Modules/WsusAutoDetection.psm1:737`, `Modules/WsusAutoDetection.psm1:743`
  - Scheduler-owned task model: `Modules/WsusScheduledTask.psm1:417`, `Modules/WsusScheduledTask.psm1:433`, `Modules/WsusScheduledTask.psm1:478`, `Modules/WsusScheduledTask.psm1:515`
  - GUI scheduler entry depends on the scheduler module: `Modules/WsusOperationPlan.psm1:155`, `Scripts/WsusManagementGui.ps1:3391`
- Why they diverged:
  - Dashboard only wanted a cheap card status and reimplemented a narrow `Get-ScheduledTask` read.
  - Scheduler module owns the richer task DTO and lifecycle.
- Verdict:
  - Accidental duplication.
  - One local maintenance-task status source is enough.

### 5. Database cleanup and restore verification duplicate module logic inside script entry points
- Evidence:
  - Shared backup verification helper: `Modules/WsusDatabase.psm1:527`, `Modules/WsusDatabase.psm1:577`, `Modules/WsusDatabase.psm1:587`
  - Restore path does its own verify flow: `Scripts/Invoke-WsusManagement.ps1:479`, `Scripts/Invoke-WsusManagement.ps1:570`
  - Shared supersession/index/stat/shrink helpers: `Modules/WsusDatabase.psm1:114`, `Modules/WsusDatabase.psm1:226`, `Modules/WsusDatabase.psm1:382`, `Modules/WsusDatabase.psm1:411`
  - Cleanup scripts still own their own `spDeleteUpdate` purge loops: `Scripts/Invoke-WsusManagement.ps1:1833`, `Scripts/Invoke-WsusManagement.ps1:1860`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1334`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1355`
- Why they diverged:
  - The module centralized most DB work, but restore verification and the aggressive declined-update purge remained embedded in the top-level scripts.
- Verdict:
  - Accidental duplication.
  - The DB module already owns the right boundary.

### 6. Secret environment packaging is repeated between plan builders and GUI cleanup
- Evidence:
  - Install env packaging: `Modules/WsusOperationPlan.psm1:98`
  - Schedule env packaging: `Modules/WsusOperationPlan.psm1:153`
  - GUI cleanup paths: `Scripts/WsusManagementGui.ps1:3225`, `Scripts/WsusManagementGui.ps1:3253`, `Scripts/WsusManagementGui.ps1:3266`
  - Canonical secret-environment object exists already: `Modules/WsusUtilities.psm1:923`, `Modules/WsusUtilities.psm1:944`
- Why they diverged:
  - Operation plans grew per operation, and the cleanup flow later inferred cleanup keys separately in the GUI.
- Verdict:
  - Accidental duplication.
  - There should be one way to define environment keys and one way to clean them up.

### 7. AppData JSON persistence is parallelized across settings, history, and trends
- Evidence:
  - GUI settings file path and writes: `Scripts/WsusManagementGui.ps1:68`, `Scripts/WsusManagementGui.ps1:209`, `Scripts/WsusManagementGui.ps1:232`, `Scripts/WsusManagementGui.ps1:235`
  - Shared AppData helper exists: `Modules/WsusUtilities.psm1:619`, `Modules/WsusUtilities.psm1:633`, `Modules/WsusUtilities.psm1:901`
  - History store helpers: `Modules/WsusHistory.psm1:19`, `Modules/WsusHistory.psm1:35`, `Modules/WsusHistory.psm1:134`, `Modules/WsusHistory.psm1:166`
  - Trends store helpers: `Modules/WsusTrending.psm1:8`, `Modules/WsusTrending.psm1:26`, `Modules/WsusTrending.psm1:75`, `Modules/WsusTrending.psm1:165`
- Why they diverged:
  - Settings predates the shared AppData helper.
  - History and trends each added their own JSON read/write, corruption handling, and path resolution rules.
- Verdict:
  - Separate stores are legitimate specialization.
  - Path resolution and JSON persistence mechanics are accidental duplication.

### 8. Diagnostics and support layers reimplement service/SQL adapter behavior
- Evidence:
  - Canonical service control: `Modules/WsusServices.psm1:21`, `Modules/WsusServices.psm1:53`, `Modules/WsusServices.psm1:93`, `Modules/WsusServices.psm1:119`
  - Host-environment service actions: `Modules/WsusHostEnvironment.psm1:33`, `Modules/WsusHostEnvironment.psm1:185`, `Modules/WsusHostEnvironment.psm1:194`
  - Canonical SQL adapter: `Modules/WsusUtilities.psm1:408`, `Modules/WsusUtilities.psm1:500`, `Modules/WsusUtilities.psm1:521`
  - Host-environment SQL adapter: `Modules/WsusHostEnvironment.psm1:84`, `Modules/WsusHostEnvironment.psm1:93`, `Modules/WsusHostEnvironment.psm1:97`
- Why they diverged:
  - `WsusHostEnvironment` wanted a diagnostic seam and avoided hard module coupling.
  - The service and SQL policies had already been centralized elsewhere.
- Verdict:
  - Mixed.
  - The DTO/read-model seam is legitimate specialization.
  - The actual start/restart/status and SQL execution plumbing is accidental duplication.

### 9. Async/orchestration infrastructure overlaps; only one path is active
- Evidence:
  - Active operation runner: `Modules/WsusOperationRunner.psm1:250`, `Modules/WsusOperationRunner.psm1:351`, `Modules/WsusOperationRunner.psm1:417`, `Modules/WsusOperationRunner.psm1:489`
  - Parallel async layer: `Modules/AsyncHelpers.psm1:46`, `Modules/AsyncHelpers.psm1:117`, `Modules/AsyncHelpers.psm1:130`, `Modules/AsyncHelpers.psm1:341`
  - GUI flowchart uses the runner, not the async helper path: `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md:55-75`
- Why they diverged:
  - The GUI settled on child `powershell.exe` plus event/timer lifecycle management.
  - `AsyncHelpers.psm1` remains as a separate runspace-pool abstraction.
- Verdict:
  - Likely accidental overlap unless there are out-of-band callers not present in the current feature flows.
  - Needs a callsite check before deletion.

## Legitimate specialization to keep

### A. Remote GPO gpupdate fanout is not the same problem as local maintenance scheduling
- Evidence:
  - Remote one-shot gpupdate via `schtasks.exe`: `DomainController/Set-WsusGroupPolicy.ps1:431`, `DomainController/Set-WsusGroupPolicy.ps1:464`, `DomainController/Set-WsusGroupPolicy.ps1:470`
  - Local persistent monthly maintenance task: `Modules/WsusScheduledTask.psm1:265`, `Modules/WsusScheduledTask.psm1:355`, `Modules/WsusScheduledTask.psm1:433`
- Why they diverged:
  - One targets many remote domain computers without WinRM.
  - The other registers one persistent local server task.
- Verdict:
  - Legitimate specialization.

### B. Client check-in service handling is not the same concern as WSUS server service orchestration
- Evidence:
  - Client services: `Scripts/Invoke-WsusClientCheckIn.ps1:91`, `Scripts/Invoke-WsusClientCheckIn.ps1:167`
  - Server services: `Modules/WsusServices.psm1:145`, `Modules/WsusServices.psm1:148`, `Scripts/Invoke-WsusManagement.ps1:580`, `Scripts/Invoke-WsusMonthlyMaintenance.ps1:694`
- Why they diverged:
  - Client remediation targets `wuauserv`, `bits`, `cryptsvc`, `msiserver`.
  - Server flows target SQL, WSUS, IIS, and WsusPool.
- Verdict:
  - Legitimate specialization.

### C. Separate machine/runtime config, per-user UI data, and DPAPI credentials should remain separate stores
- Evidence:
  - Runtime config: `Modules/WsusConfig.psm1:468`, `Modules/WsusConfig.psm1:658`
  - Per-user settings/history/trends: `Scripts/WsusManagementGui.ps1:68`, `Modules/WsusHistory.psm1:19`, `Modules/WsusTrending.psm1:8`
  - DPAPI SQL credentials: `Modules/WsusUtilities.psm1:739`, `Modules/WsusUtilities.psm1:792`
- Why they diverged:
  - They have different trust boundaries and lifetimes.
- Verdict:
  - Legitimate specialization.

## What this means for the unified proposal

The highest-value unifications are:
1. one SQL access/verification path;
2. one transfer/export path that also owns `.bak` staging;
3. one source of truth for server firewall/ACL/service operations;
4. one local maintenance-task status reader;
5. one shared AppData/JSON persistence helper;
6. one secret-environment packaging path.
