# Make Plan: Maintenance Task Status Reader

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:120-143`.

Target unified system: local maintenance-task status.

Single entry point: `Get-WsusMaintenanceTask` in `Modules/WsusScheduledTask.psm1:417-455`.

## Phase 0 — Documentation and API discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:77-89`
- `PATHFINDER-2026-06-18/02-duplication-report.md:59-69`
- `PATHFINDER-2026-06-18/01-flowcharts/dashboard-auto-detection-health.md`
- `PATHFINDER-2026-06-18/01-flowcharts/scheduled-maintenance-automation.md`
- `Modules/WsusScheduledTask.psm1:417-455,493-523`
- `Modules/WsusAutoDetection.psm1:89-117,737-816`
- `Modules/WsusDashboardViewModel.psm1:18-50`
- `Scripts/WsusManagementGui.ps1:240-260,1202-1224`
- `Tests/WsusScheduledTask.Tests.ps1:56-80`
- `Tests/WsusAutoDetection.Tests.ps1:402-416`
- `wiki/Module-Reference.md:912-927,980-984,1105-1112`

### Allowed APIs and patterns
- Use `Get-WsusMaintenanceTask` as the only local maintenance-task reader.
- Map the scheduler DTO at the dashboard edge if the view-model still wants a narrow string.
- Keep DomainController remote `schtasks.exe` gpupdate fanout out of scope.

### Disallowed assumptions
- Do not keep a dashboard-only local task reader.
- Do not change the scheduler module’s task-creation/removal/start responsibilities.
- Do not force the view-model to consume the entire scheduler DTO if only a string/status projection is needed.

## Phase 1 — Add a dashboard mapping seam

### What to implement
- Introduce one mapping layer from `Get-WsusMaintenanceTask` output to the dashboard’s expected string/status shape.
- Prefer placing the mapping inside `WsusAutoDetection` or the dashboard view-model edge, not inside `WsusScheduledTask`.
- Decide whether the dashboard wants only state text or also missed runs/next run time in future. For this plan, keep parity with today’s `TaskStatus` string unless a broader card redesign is explicitly in scope.

### Verification checklist
- The mapping handles both found and not-found task results.
- The mapping preserves current dashboard semantics for `Ready` / `Running` / `Not Set`.

### Anti-pattern guards
- No second reader.
- No scheduler DTO mutation for dashboard-only convenience.

## Phase 2 — Cut AutoDetection duplicate readers

### What to implement
- Replace/remove `Get-WsusScheduledTaskStatus` at `Modules/WsusAutoDetection.psm1:89-117`.
- Replace/remove `Get-WsusDashboardTaskStatus` at `Modules/WsusAutoDetection.psm1:737-760`.
- Update `Get-WsusDashboardData` at `Modules/WsusAutoDetection.psm1:763-816` to use the scheduler module plus the new mapping seam.
- Ensure the GUI/module import boundary can actually resolve `WsusScheduledTask`; current GUI imports omit it.

### Verification checklist
- Search `Modules/WsusAutoDetection.psm1` for direct `Get-ScheduledTask` task-reader duplicates after the cutover.
- Confirm `Get-WsusDashboardSnapshot` still returns the expected task field for the GUI.

### Anti-pattern guards
- Do not leave dead duplicate functions exported or documented.
- Do not widen this change into remote-task orchestration.

## Phase 3 — Wire the dashboard consumer and tests

### What to implement
- Keep `Scripts/WsusManagementGui.ps1:1202-1224` and `Modules/WsusDashboardViewModel.psm1:18-50` behavior stable unless the mapping seam requires a tiny import/wiring change.
- Update tests so the scheduler module becomes the truth source and AutoDetection tests assert mapped behavior, not duplicate local readers.

### Tests to add/update
- `Tests/WsusScheduledTask.Tests.ps1`: keep current DTO-shape checks.
- `Tests/WsusAutoDetection.Tests.ps1`: replace duplicate-reader assertions with scheduler-backed mapping assertions.
- Add one architecture/static assertion that local dashboard task status comes from `Get-WsusMaintenanceTask`.

### Docs to update
- Remove or demote duplicate AutoDetection task-reader docs from `wiki/Module-Reference.md`.
- Keep scheduler module docs as the source of truth.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusScheduledTask.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\WsusAutoDetection.Tests.ps1 -Output Detailed
```

Run static searches:
- Search `Modules/WsusAutoDetection.psm1` for local duplicate task readers and direct `Get-ScheduledTask` dashboard status code.
- Search repo for `Get-WsusMaintenanceTask`; expected hits are scheduler, dashboard path, tests, and docs.
