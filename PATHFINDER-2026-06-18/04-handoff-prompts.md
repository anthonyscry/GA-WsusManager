# /make-plan handoff prompts

## 1. SQL access adapter

```text
/make-plan
Unify GA-WsusManager SQL execution around `Invoke-WsusSqlcmd`.

Target unified component and single entry point:
- `Invoke-WsusSqlcmd`
- `Modules/WsusUtilities.psm1:408`

Exact call sites to rewrite:
- `Scripts/WsusManagementGui.ps1:3008-3016`
- `Scripts/WsusManagementGui.ps1:3481-3483`
- `Scripts/Invoke-WsusManagement.ps1:279-288`
- `Scripts/Invoke-WsusManagement.ps1:390-408`
- `Scripts/Invoke-WsusManagement.ps1:570`
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:420-426`
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1247-1251`
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1429-1433`
- `Modules/WsusHostEnvironment.psm1:84-97`
- `Modules/WsusAutoDetection.psm1:155-167`
- `Modules/WsusAutoDetection.psm1:726-729`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-18/01-flowcharts/dashboard-auto-detection-health.md`
- `PATHFINDER-2026-06-18/01-flowcharts/online-sync-maintenance.md`
- `PATHFINDER-2026-06-18/01-flowcharts/database-maintenance-utilities.md`
- `PATHFINDER-2026-06-18/01-flowcharts/diagnostics-repair.md`

Anti-pattern guards:
- Do not add a second wrapper beside `Invoke-WsusSqlcmd`.
- Do not keep raw `sqlcmd.exe` helpers for non-bootstrap paths.
- Do not preserve parallel `Invoke-Sqlcmd` branches “just in case”.
- Keep the one legitimate install-bootstrap exception explicit and minimal if still required.
```

## 2. Backup verification entry

```text
/make-plan
Unify WSUS backup verification around `Test-WsusBackupIntegrity`.

Target unified component and single entry point:
- `Test-WsusBackupIntegrity`
- `Modules/WsusDatabase.psm1:527`

Exact call sites to rewrite:
- `Scripts/Invoke-WsusManagement.ps1:520-573`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/air-gap-transfer-restore.md`
- `PATHFINDER-2026-06-18/01-flowcharts/database-maintenance-utilities.md`

Anti-pattern guards:
- Do not keep both the raw restore verifier and the module helper.
- Do not weaken verification from `HEADERONLY` + `VERIFYONLY WITH CHECKSUM`.
- If restore needs stricter messaging, extend the shared helper instead of reintroducing an inline verifier.
```

## 3. WSUS transfer package

```text
/make-plan
Make `Invoke-WsusTransferPackage` the sole WSUS package transfer path, including monthly `.bak` staging.

Target unified component and single entry point:
- `Invoke-WsusTransferPackage`
- `Modules/WsusExport.psm1:430`

Exact call sites to rewrite:
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1514-1531`
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1547`
- Review but likely keep as-is: `Scripts/Invoke-WsusManagement.ps1:694`, `Scripts/Invoke-WsusManagement.ps1:1512`
- Review but likely keep Generic mode: `Modules/WsusOperationPlan.psm1:173`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/air-gap-transfer-restore.md`
- `PATHFINDER-2026-06-18/01-flowcharts/online-sync-maintenance.md`

Anti-pattern guards:
- Do not keep manual `Copy-Item` `.bak` staging in monthly export.
- Do not collapse GUI Generic copy into WSUS package transfer unless the UX explicitly grows export/import modes.
- Do not create a second transfer coordinator beside `Invoke-WsusTransferPackage`.
```

## 4. Server baseline applicator

```text
/make-plan
Create one thin server-baseline coordinator for standard WSUS/SQL firewall, ACL, and routine service startup work.

Target unified component and single entry point:
- `Invoke-WsusHostBaseline` [new]
- target file/anchor: `Modules/WsusProvisioning.psm1:53`

Exact call sites to rewrite:
- `Scripts/Install-WsusWithSqlExpress.ps1:793-823`
- `Scripts/Install-WsusWithSqlExpress.ps1:952-965`
- `Scripts/Install-WsusWithSqlExpress.ps1:627-647`
- `Scripts/Install-WsusWithSqlExpress.ps1:1053`
- `Scripts/Install-WsusWithSqlExpress.ps1:981-1012`
- `Modules/WsusHostEnvironment.psm1:185-194`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/install-provisioning.md`
- `PATHFINDER-2026-06-18/01-flowcharts/diagnostics-repair.md`
- `PATHFINDER-2026-06-18/01-flowcharts/configuration-shared-support.md`

Anti-pattern guards:
- Do not add a generic registry/factory abstraction.
- Keep WID removal, SQL media setup, and WSUS postinstall sequencing script-local.
- Reuse `WsusFirewall`, `WsusPermissions`, and `WsusServices`; do not re-copy their internals into the new coordinator.
- Preserve installer-only extra API remoting rules only if they are still truly required.
```

## 5. Local maintenance-task status reader

```text
/make-plan
Unify local maintenance-task status reads around the scheduler module.

Target unified component and single entry point:
- `Get-WsusMaintenanceTask`
- `Modules/WsusScheduledTask.psm1:417`

Exact call sites to rewrite:
- `Modules/WsusAutoDetection.psm1:89-117`
- `Modules/WsusAutoDetection.psm1:737-760`
- Dashboard mapping path that consumes task state: `Scripts/WsusManagementGui.ps1:1215-1224`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/dashboard-auto-detection-health.md`
- `PATHFINDER-2026-06-18/01-flowcharts/scheduled-maintenance-automation.md`

Anti-pattern guards:
- Do not keep a parallel dashboard-only task reader.
- Do not change DomainController remote `schtasks.exe` gpupdate fanout; that is a different system.
- If the dashboard needs a narrow string, map the scheduler DTO at the edge instead of creating another reader.
```

## 6. Secret environment packaging

```text
/make-plan
Unify install/schedule secret environment handling around `New-WsusSecretEnvironment`.

Target unified component and single entry point:
- `New-WsusSecretEnvironment`
- `Modules/WsusUtilities.psm1:923`

Exact call sites to rewrite:
- `Modules/WsusOperationPlan.psm1:98-103`
- `Modules/WsusOperationPlan.psm1:153-157`
- `Scripts/WsusManagementGui.ps1:3225-3253`
- `Scripts/WsusManagementGui.ps1:3266-3267`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-18/01-flowcharts/scheduled-maintenance-automation.md`
- `PATHFINDER-2026-06-18/01-flowcharts/install-provisioning.md`

Anti-pattern guards:
- Do not keep ad-hoc environment hashtables for install and schedule.
- Do not make GUI cleanup infer secret keys independently.
- Preserve the existing no-command-line-secrets rule.
```

## 7. Per-user JSON store helper

```text
/make-plan
Add one small AppData-scoped JSON store helper and move settings/history/trends onto it.

Target unified component and single entry point:
- `Invoke-WsusJsonStore` [new]
- target file/anchor: `Modules/WsusUtilities.psm1:619`

Exact call sites to rewrite:
- `Scripts/WsusManagementGui.ps1:209-235`
- `Modules/WsusHistory.psm1:19-100`
- `Modules/WsusHistory.psm1:134-166`
- `Modules/WsusTrending.psm1:8-75`
- `Modules/WsusTrending.psm1:96-165`

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-18/01-flowcharts/dashboard-auto-detection-health.md`
- `PATHFINDER-2026-06-18/01-flowcharts/configuration-shared-support.md`

Anti-pattern guards:
- Do not merge settings, history, and trends into one file.
- Unify only the disk/path/JSON/corruption mechanics.
- Reuse `Get-WsusAppDataPath`; do not reintroduce literal `%APPDATA%\WsusManager` path building in feature files.
```

## 8. GUI long-operation orchestration

```text
/make-plan
Confirm current callers, then collapse GUI long-operation orchestration onto `Start-WsusOperation` alone.

Target unified component and single entry point:
- `Start-WsusOperation`
- `Modules/WsusOperationRunner.psm1:250`

Exact call sites to rewrite or remove:
- Active GUI call site already on the target path: `Scripts/WsusManagementGui.ps1:3259`
- Candidate legacy overlap to verify/remove: `Modules/AsyncHelpers.psm1:46-374`
- Remove any now-dead imports/usages discovered during the callsite audit

Relevant flowcharts:
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `PATHFINDER-2026-06-18/01-flowcharts/configuration-shared-support.md`

Anti-pattern guards:
- Do not keep both a child-process runner and a dormant parallel async abstraction without live callers.
- Do not replatform GUI operations onto runspaces unless the current child-process guarantees are explicitly preserved.
- Delete unused orchestration code cleanly; no compatibility shim layer.
```
