# Make Plan: Server Baseline Applicator

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:90-118`.

Target unified system: standard server baseline application.

Single entry point: new `Invoke-WsusHostBaseline` in `Modules/WsusProvisioning.psm1`, anchored near `Modules/WsusProvisioning.psm1:53`.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:61-75`
- `PATHFINDER-2026-06-18/02-duplication-report.md:31-44,108-120`
- `PATHFINDER-2026-06-18/01-flowcharts/install-provisioning.md`
- `PATHFINDER-2026-06-18/01-flowcharts/diagnostics-repair.md`
- `PATHFINDER-2026-06-18/01-flowcharts/configuration-shared-support.md`
- `Modules/WsusProvisioning.psm1:1-145`
- `Modules/WsusFirewall.psm1:21-60,67-140,198-270,318-365`
- `Modules/WsusPermissions.psm1:21-92,181-224,226-290`
- `Modules/WsusServices.psm1:21-180`
- `Modules/WsusHostEnvironment.psm1:33-50,185-198`
- `Scripts/Install-WsusWithSqlExpress.ps1:52-60,620-651,792-838,951-976,974-1015,1047-1059`
- `Tests/WsusFirewall.Tests.ps1`, `Tests/WsusPermissions.Tests.ps1`, `Tests/WsusServices.Tests.ps1`, `Tests/WsusProvisioning.Tests.ps1`

### Allowed APIs and patterns
- Use canonical helpers only:
  - `Initialize-WsusFirewallRules`, `Initialize-SqlFirewallRules`
  - `Initialize-WsusDirectories`, `Set-WsusContentPermissions`, `Repair-WsusContentPermissions`
  - `Get-WsusServiceDefinitions`, `Start-WsusService`, `Get-WsusServiceStatus`
- Keep the coordinator thin and procedural inside `WsusProvisioning.psm1`.
- Preserve `WsusHostEnvironment` return shapes when delegating its service actions to canonical helpers.

### Disallowed assumptions
- Do not assume installer-only API remoting firewall rules are represented in `WsusFirewall` today.
- Do not assume `Install-WsusWithSqlExpress.ps1` already imports the helper modules required by the new coordinator.
- Do not use private per-service wrappers from `WsusServices` as new external dependencies.
- Do not move WID removal, SQL media setup, or WSUS postinstall orchestration into the new helper.

## Phase 1 — Add the thin coordinator

### What to implement
- Add `Invoke-WsusHostBaseline` to `Modules/WsusProvisioning.psm1` and export it.
- Give it a narrow contract that coordinates:
  - standard firewall rules
  - standard WSUS directory creation/ACLs
  - routine service startup/status verification
- Decide the minimum parameter set from current callers. Prefer explicit parameters for content root and service inclusion rather than a generic options hashtable.
- If `WsusProvisioning` needs to import `WsusFirewall`, `WsusPermissions`, and `WsusServices`, copy the repo’s explicit module-path import pattern instead of assuming ambient imports.

### Verification checklist
- `Get-Command Invoke-WsusHostBaseline -Module WsusProvisioning` succeeds.
- The coordinator delegates to exported helper modules rather than copying their internals.

### Anti-pattern guards
- No registry/provider/factory layer.
- No reimplementation of firewall/ACL/service mechanics inside the coordinator.
- No compatibility shim that keeps both the inline installer blocks and the coordinator path.

## Phase 2 — Cut installer duplicate blocks to the coordinator

### What to implement
- Replace inline ACL setup at `Scripts/Install-WsusWithSqlExpress.ps1:620-651` and `1047-1059` with the coordinator plus any explicit post-IIS WsusPool follow-up that still proves necessary.
- Replace inline WSUS/SQL firewall setup at `Scripts/Install-WsusWithSqlExpress.ps1:792-838` and `951-976` with the coordinator.
- Replace inline service startup/status block at `Scripts/Install-WsusWithSqlExpress.ps1:974-1015` with coordinator-backed canonical service helpers.
- Audit the installer-only API remoting firewall rules. Either:
  - model them as data beside canonical firewall definitions if still required, or
  - drop them explicitly with evidence.

### Verification checklist
- Search installer script for the duplicated `New-NetFirewallRule`, `icacls`, `Start-Service`, and `Get-Service` baseline blocks after the cutover.
- Confirm installer still preserves script-local sequencing around SQL install, IIS, WSUS postinstall, and WsusPool existence.

### Anti-pattern guards
- Do not hide real installer sequencing inside the coordinator.
- Do not change operator-facing install flow while cutting the baseline mechanics.

## Phase 3 — Delegate host-environment service actions

### What to implement
- Update `Start-WsusHostService` and `Restart-WsusHostService` in `Modules/WsusHostEnvironment.psm1:185-198` to call canonical `WsusServices` helpers, then return the same `Get-WsusHostServiceState` projection.
- Keep `Get-WsusHostServiceState` as the diagnostic DTO seam.

### Verification checklist
- Existing host-environment tests still see the same returned fields.
- No raw `Start-Service` / `Restart-Service` remains in those two adapter functions.

### Anti-pattern guards
- Do not collapse the host-environment DTO seam into the services module.
- Delegate plumbing only; preserve the diagnostic boundary.

## Phase 4 — Tests and docs

### Tests to add/update
- Add provisioning tests for the new exported coordinator.
- Update firewall/permissions/services mock-based tests only where call graph changes.
- Add one static integration assertion that installer no longer owns the standard baseline blocks inline.

### Docs to update
- `wiki/Module-Reference.md` for the new provisioning export.
- `Modules/README.md` and any install docs that describe the baseline ownership split.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusProvisioning.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusFirewall.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusPermissions.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusServices.Tests.ps1 -Output Detailed
```

Run static searches:
- Search `Scripts/Install-WsusWithSqlExpress.ps1` for duplicated baseline `New-NetFirewallRule`, `icacls`, and service startup blocks.
- Search repo for `Invoke-WsusHostBaseline`; expected hits are provisioning, installer/host callers, tests, and docs.
