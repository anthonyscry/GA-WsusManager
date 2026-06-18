# Make Plan: SQL Access Adapter

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:3-38`.

Target unified system: SQL execution.

Single entry point: `Invoke-WsusSqlcmd` in `Modules/WsusUtilities.psm1:408-555`.

Note on current state:
- The PATHFINDER prompt is directionally right, but two monthly call sites named there are already migrated. Current source already uses `Invoke-WsusSqlcmd` at `Scripts/Invoke-WsusMonthlyMaintenance.ps1:1247-1253` and `1411-1435`.
- The remaining non-bootstrap drift is GUI raw preflight, management raw helpers, AutoDetection raw size probes, and fallback branches in host/dashboard readers.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:12-28`
- `PATHFINDER-2026-06-18/02-duplication-report.md:15-30`
- `PATHFINDER-2026-06-18/01-flowcharts/dashboard-auto-detection-health.md`
- `PATHFINDER-2026-06-18/01-flowcharts/diagnostics-repair.md`
- `PATHFINDER-2026-06-18/01-flowcharts/database-maintenance-utilities.md`
- `Modules/WsusUtilities.psm1:408-555,970-985`
- `Modules/WsusHostEnvironment.psm1:84-99`
- `Modules/WsusAutoDetection.psm1:123-190,708-746`
- `Scripts/WsusManagementGui.ps1:317-330,2996-3035,3479-3518`
- `Scripts/Invoke-WsusManagement.ps1:278-291,390-408,479-497,589-596`
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1:399-432,1247-1253,1352-1364,1429-1435`
- `Scripts/Install-WsusWithSqlExpress.ps1:664-717`
- `Tests/WsusUtilities.Tests.ps1:209-218`
- `Tests/WsusHostEnvironment.Tests.ps1:1-30,80-95`
- `Tests/Integration.Tests.ps1:145-160`

### Allowed APIs and patterns
- Use `Invoke-WsusSqlcmd` as the only normal SQL execution path. It already owns module import, TrustServerCertificate behavior, sqlcmd fallback, timeout, variable substitution, and the no-`-P` security rule (`Modules/WsusUtilities.psm1:408-555`).
- Reuse wrapper call patterns already present in monthly maintenance, especially optional `-Credential` and SQLCMD variable substitution (`Scripts/Invoke-WsusMonthlyMaintenance.ps1:1247-1253,1352-1364,1429-1435`).
- Preserve the install-bootstrap raw sqlcmd exception only where SQL itself is being provisioned and the wrapper cannot yet be trusted (`Scripts/Install-WsusWithSqlExpress.ps1:664-717`).

### Disallowed assumptions
- Do not keep `Invoke-SqlScalar` as a second adapter; it is a raw sqlcmd helper and not the target seam (`Modules/WsusUtilities.psm1:372-403`).
- Do not preserve direct `Invoke-Sqlcmd` fallback branches in non-bootstrap code once the cutover is complete.
- Do not add a new connectivity wrapper beside `Invoke-WsusSqlcmd`; if a tiny helper is needed, it should call the same adapter.
- Do not change install/bootstrap raw sqlcmd behavior as part of this plan unless the replacement is explicitly proven equivalent.

## Phase 1 — Lock the adapter contract and remove fallback branches

### What to implement
- Keep `Invoke-WsusSqlcmd` public and authoritative.
- Decide whether `Invoke-SqlScalar` becomes private, deprecated, or deleted. Prefer deletion if no live callers remain after a repo-wide caller check.
- Remove direct `Invoke-Sqlcmd` fallback from:
  - `Modules/WsusHostEnvironment.psm1:84-99`
  - `Modules/WsusAutoDetection.psm1:708-746`
- If GUI preflight needs a reusable `SELECT 1` probe, add a tiny helper in `WsusUtilities` that delegates to `Invoke-WsusSqlcmd`; do not create a second adapter.

### Verification checklist
- Search repo for raw non-bootstrap `Invoke-Sqlcmd` and raw `sqlcmd.exe` usage in GUI, management, auto-detection, and host-environment paths.
- Confirm `Invoke-WsusSqlcmd` remains exported.
- Confirm `Tests/WsusUtilities.Tests.ps1` still enforces no password-on-command-line behavior.

### Anti-pattern guards
- No second wrapper.
- No raw `Invoke-Sqlcmd` branch kept in non-bootstrap modules.
- No GUI-specific SQL adapter.

## Phase 2 — Cut caller sites to the adapter

### What to implement
- Replace GUI DB-operation preflight at `Scripts/WsusManagementGui.ps1:2996-3035` with wrapper-backed `SELECT 1` execution.
- Remove the raw `sqlcmd.exe` presence gate before Fix SQL Login at `Scripts/WsusManagementGui.ps1:3479-3483`; rely on `Test-WsusSqlLoginIsSysAdmin` / `Add-WsusSqlLogin` instead.
- Replace management-script raw helpers/callers at:
  - `Scripts/Invoke-WsusManagement.ps1:278-291`
  - `Scripts/Invoke-WsusManagement.ps1:390-408`
  - any remaining non-restore-execution branches still using `Invoke-CheckedSqlcmd`
- Replace AutoDetection raw DB size path at `Modules/WsusAutoDetection.psm1:123-190` with wrapper-backed query execution.
- Leave install bootstrap raw sqlcmd alone unless this plan explicitly proves the wrapper can cover it.

### Verification checklist
- Search the targeted files for `SELECT IS_SRVROLEMEMBER`, raw `sqlcmd`, and direct `Invoke-Sqlcmd` branches.
- Confirm Integration/host tests still load the module and see `Invoke-WsusSqlcmd`.

### Anti-pattern guards
- Do not widen scope into restore backup verification; that is Plan 02.
- Do not widen scope into monthly calls already on the wrapper.

## Phase 3 — Tests and docs

### Tests to add/update
- `Tests/WsusHostEnvironment.Tests.ps1`: update expected behavior if `Invoke-Sqlcmd` fallback is removed.
- `Tests/WsusUtilities.Tests.ps1`: keep the security test and add text/behavior assertions for the surviving adapter path.
- `Tests/Integration.Tests.ps1`: keep the availability check for `Invoke-WsusSqlcmd`.
- Add one focused static assertion that GUI preflight and AutoDetection no longer shell raw sqlcmd in their targeted sections.

### Docs to update
- `wiki/Module-Reference.md:108-125` if `Invoke-SqlScalar` is removed or demoted.
- `Modules/README.md:20-32` and `wiki/Developer-Guide.md:300-314` if they still present the scalar helper as first-class.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusUtilities.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusHostEnvironment.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\Integration.Tests.ps1 -Output Detailed
```

Run static searches:
- Search targeted GUI/management/auto-detection/host files for raw `sqlcmd` and direct `Invoke-Sqlcmd`.
- Search repo for `Invoke-WsusSqlcmd`; expected hits are utilities, legitimate callers, tests, and docs.
