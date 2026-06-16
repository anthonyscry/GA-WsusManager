# /make-plan handoff prompts

## 1. Unified transfer engine

```text
/make-plan
Target unified system: transfer/copy execution.
Single entry point: `Invoke-WsusTransferPackage` in `Modules/WsusExport.psm1` near the existing transfer-plan seam at `Modules/WsusExport.psm1:378-428`.

Rewrite these exact call sites:
- `Modules/WsusOperationPlan.psm1:161-172` — GUI transfer currently builds raw robocopy command text.
- `Scripts/Invoke-WsusManagement.ps1:664-730` — import copy path.
- `Scripts/Invoke-WsusManagement.ps1:1347-1540` — export copy path.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1503-1590` — monthly export path.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/air-gap-transfer-restore.md`
- `PATHFINDER-2026-06-15/01-flowcharts/online-sync-maintenance.md`

Anti-pattern guards:
- Do not keep both raw robocopy builders and the shared helper.
- Do not add a generic strategy registry; use one function with a small parameter set.
- Do not split generic GUI transfer and WSUS-content transfer into separate low-level copy engines.
- Keep one robocopy exit-code mapping and one place for exclusions/logging defaults.
```

## 2. Unified SQL access gate

```text
/make-plan
Target unified system: SQL readiness/sysadmin/tool discovery.
Single entry point: `Test-WsusSqlAccess` in `Modules/WsusUtilities.psm1` alongside `Invoke-WsusSqlcmd` (`Modules/WsusUtilities.psm1:408-555`).

Rewrite these exact call sites:
- `Scripts/WsusManagementGui.ps1:3004-3033` — GUI preflight for DB operations.
- `Scripts/Invoke-WsusManagement.ps1:358-473` — `Test-SqlSysadmin` / `Assert-SqlSysadmin` internals.
- `Scripts/Invoke-WsusManagement.ps1:1717-1720` — cleanup gate.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:349-447` — maintenance preflight SQL checks.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-15/01-flowcharts/online-sync-maintenance.md`
- `PATHFINDER-2026-06-15/01-flowcharts/database-maintenance-utilities.md`
- `PATHFINDER-2026-06-15/01-flowcharts/configuration-shared-support.md`

Anti-pattern guards:
- Do not duplicate sqlcmd path probing in each caller.
- Do not move popup/console wording into the shared function; return structured results and let callers format.
- Do not add a provider abstraction; one structured helper is enough.
- Preserve the current no-password-on-command-line rule from `Invoke-WsusSqlcmd`.
```

## 3. Unified install-time remediation primitives

```text
/make-plan
Target unified system: install-time ACL/firewall/IIS content setup.
Single entry points:
- `Initialize-WsusDirectories` in `Modules/WsusPermissions.psm1:226-277`
- `Initialize-WsusFirewallRules` in `Modules/WsusFirewall.psm1:198-253`
- `Initialize-SqlFirewallRules` in `Modules/WsusFirewall.psm1` export surface near `373`
- one shared IIS content-path helper added near provisioning/permissions helpers

Rewrite these exact call sites:
- `Scripts/Install-WsusWithSqlExpress.ps1:621-649` — directory + ACL setup.
- `Scripts/Install-WsusWithSqlExpress.ps1:792-829` — WSUS firewall rules.
- `Scripts/Install-WsusWithSqlExpress.ps1:951-971` — SQL firewall rules.
- `Scripts/Install-WsusWithSqlExpress.ps1:1032-1053` — IIS content-path verification + final WsusPool ACL.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/install-provisioning.md`
- `PATHFINDER-2026-06-15/01-flowcharts/diagnostics-repair.md`

Anti-pattern guards:
- Do not keep inline installer firewall/ACL rule definitions after helper migration.
- Do not introduce a provisioning framework; call the existing modules directly.
- Preserve the legitimate two-phase WsusPool timing by parameterizing it, not by keeping duplicate implementations.
- Keep existing installer side effects/order boring and explicit.
```

## 4. Unified runtime-config merge contract

```text
/make-plan
Target unified system: effective runtime configuration.
Single entry point: `Get-WsusEffectiveRuntimeConfig` in `Modules/WsusConfig.psm1` near `Get-WsusRuntimeConfig` (`Modules/WsusConfig.psm1:658-694`).

Rewrite these exact call sites:
- `Scripts/WsusManagementGui.ps1:68-104` — GUI hardcoded defaults.
- `Scripts/WsusManagementGui.ps1:207-239` — GUI settings overlay.
- `Scripts/WsusManagementGui.ps1:267-279` — GUI runtime overwrite.
- `Scripts/Invoke-WsusManagement.ps1:199-241` — CLI fallback config.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:153-170` — maintenance runtime reset.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/configuration-shared-support.md`
- `PATHFINDER-2026-06-15/01-flowcharts/gui-shell-operation-orchestration.md`

Anti-pattern guards:
- Do not keep multiple sources mutating the same effective path fields after the new merge contract exists.
- Do not hide precedence in side effects; document and encode one order: defaults → wsus-config.json → GUI settings → explicit parameters.
- Do not add a config service class or registry; one function returning one effective object is enough.
- Fix version ownership in the same plan if it naturally falls out of the merge cleanup.
```

## 5. Unified diagnostics finalization

```text
/make-plan
Target unified system: diagnostics repair/finalization pipeline.
Single entry points:
- `Invoke-WsusDiagnosticRepairs`
- `Complete-WsusDiagnosticReport`
Both should live in `Modules/WsusDiagnosticResult.psm1` near the existing typed-report seam (`Modules/WsusDiagnosticResult.psm1:103-185`).

Rewrite these exact call sites:
- `Modules/WsusHealth.psm1:550-615` — standard diagnostics finalize path.
- `Modules/WsusHealth.psm1:841-875` — deep diagnostics finalize path.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/diagnostics-repair.md`

Anti-pattern guards:
- Do not merge the actual standard and deep collectors; only unify repair/report shaping.
- Do not create a generic plugin system.
- Preserve current evidence/check specialization while deleting duplicated repair loops and healthy/failure summary logic.
- Keep the typed report seam the only owner of final report assembly.
```

## 6. Unified schedule validation seam

```text
/make-plan
Target unified system: schedule-input validation and secure-string bridge.
Single entry points:
- `Test-WsusMaintenanceTaskInput` in `Modules/WsusScheduledTask.psm1` near `185-260`
- `ConvertFrom-WsusSecureString` helper in `Modules/WsusUtilities.psm1` near `955`

Rewrite these exact call sites:
- `Scripts/WsusManagementGui.ps1:2727-2791` — GUI dialog validation.
- `Modules/WsusOperationPlan.psm1:19-29`, `153-157` — secure-string to plaintext bridge.
- `Modules/WsusScheduledTask.psm1:60-77`, `255-257` — duplicate plaintext bridge.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/scheduled-maintenance-automation.md`

Anti-pattern guards:
- Do not keep weaker GUI-only validation rules after module validation is exposed.
- Do not create a validation registry or rules engine.
- Preserve the GUI’s early UX feedback, but make it call the same validator as the module.
- Keep one secret conversion helper with one cleanup contract.
```

## 7. Unified maintenance policy predicates

```text
/make-plan
Target unified system: decline/approval policy evaluation in monthly maintenance.
Single entry point: `Get-WsusMaintenancePolicyDecision` in `Scripts/Invoke-WsusMonthlyMaintenance.ps1` near the current decline/approval logic (`Scripts/Invoke-WsusMonthlyMaintenance.ps1:969-1177`).

Rewrite these exact call sites:
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:969-1094` — decline loops.
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1096-1177` — approval filtering.

Relevant flowcharts:
- `PATHFINDER-2026-06-15/01-flowcharts/online-sync-maintenance.md`

Anti-pattern guards:
- Do not split the policy into separate decline and approval rule tables that can drift again.
- Do not move this into a new module unless there is a second real consumer.
- Keep one predicate set for preview/ARM64/legacy-build/25H2/Office/Edge/WSL/x86 checks.
- Preserve the legitimate difference between “decline” and “do not auto-approve.”
```
