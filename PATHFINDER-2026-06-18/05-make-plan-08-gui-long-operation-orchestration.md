# Make Plan: GUI Long-Operation Orchestration

## Source prompt

From `PATHFINDER-2026-06-18/04-handoff-prompts.md:200-223`.

Target unified system: GUI long-operation orchestration.

Single entry point: `Start-WsusOperation` in `Modules/WsusOperationRunner.psm1:250-560`.

## Phase 0 — Documentation and caller discovery

### Sources to read first
- `PATHFINDER-2026-06-18/03-unified-proposal.md:121-133`
- `PATHFINDER-2026-06-18/02-duplication-report.md:122-132`
- `PATHFINDER-2026-06-18/01-flowcharts/gui-shell-operation-orchestration.md`
- `Modules/WsusOperationRunner.psm1:250-624`
- `Scripts/WsusManagementGui.ps1:2996-3270,1564-1636`
- `Modules/AsyncHelpers.psm1:46-408`
- caller-audit search results showing no active Scripts/Modules callers for AsyncHelpers
- `Tests/WsusOperationRunner.Tests.ps1:1-45,240-285`
- `Tests/ExeValidation.Tests.ps1:172-212`
- `README.md:278-296`, `Modules/README.md:278-304`, `wiki/Module-Reference.md:1176-1274`

### Allowed APIs and patterns
- Keep `Start-WsusOperation` as the only active GUI orchestration path.
- Keep child-process isolation, stdout/stderr capture, timeout watchdog, and cleanup behavior.
- Use a caller audit before deleting `AsyncHelpers`.

### Disallowed assumptions
- Do not assume AsyncHelpers is safe to delete without checking tests/docs/import lists.
- Do not replatform GUI long operations onto runspaces.
- Do not keep a dormant second orchestration model with no live callers.

## Phase 1 — Prove the active caller set

### What to implement
- Perform a repo-wide caller audit for AsyncHelpers exports:
  - `Initialize-AsyncRunspacePool`
  - `Invoke-Async`
  - `Wait-Async`
  - `Test-AsyncComplete`
  - `Stop-Async`
  - `Start-BackgroundOperation`
- Record every live code caller, if any. Current discovery found none in `Scripts/` or non-AsyncHelper `Modules/`.
- If a hidden live caller appears, either migrate it to `Start-WsusOperation` or explicitly carve it out before deletion.

### Verification checklist
- Caller audit results are explicit and file-backed.
- GUI still uses `Start-WsusOperation` at `Scripts/WsusManagementGui.ps1:3259` and runner helpers around it.

### Anti-pattern guards
- No deletion before the caller audit is complete.
- No assumption that doc/test references equal live code callers.

## Phase 2 — Remove legacy AsyncHelpers surface if audit is clean

### What to implement
- Remove `AsyncHelpers` from active module/test/doc lists if Phase 1 confirms no live callers.
- Clean imports/usages from:
  - `Tests/ExeValidation.Tests.ps1:172-212`
  - `Tests/Integration.Tests.ps1:125-126`
  - `Tests/TestSetup.ps1:30-31`
  - docs that still advertise AsyncHelpers as an active subsystem
- Keep `Start-WsusOperation`, `Stop-WsusOperation`, `Complete-WsusOperation`, `Find-WsusScript`, and timeout helpers intact.

### Verification checklist
- No repo code imports or calls AsyncHelpers after cleanup.
- Operation runner exports remain unchanged.
- GUI cancel/shutdown path still uses the runner cleanup path.

### Anti-pattern guards
- Do not leave a compatibility shim module that re-exports dead async helpers.
- Do not touch runner behavior beyond removing stale parallel infrastructure.

## Phase 3 — Runner-focused cleanup and docs

### What to implement
- Update docs to present `WsusOperationRunner` as the GUI background-operation seam.
- Ensure any README/module-reference sections that previously described AsyncHelpers now either disappear or explain that the runner is the active path.
- If any tests or docs referred to runspace orchestration guarantees, rewrite them around the actual child-process guarantees already in `Start-WsusOperation`.

### Tests to add/update
- Keep `Tests/WsusOperationRunner.Tests.ps1` as the core verification surface.
- Remove or rewrite AsyncHelpers validation tests.
- Add one static integration assertion that the GUI imports/uses `WsusOperationRunner`, not AsyncHelpers.

## Final verification phase

Run targeted checks only:

```powershell
Invoke-Pester -Path .\Tests\WsusOperationRunner.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\Tests\Integration.Tests.ps1 -Output Detailed
```

Run static searches:
- Search repo for `Invoke-Async`, `Wait-Async`, `Start-BackgroundOperation`, and `Import-Module .*AsyncHelpers`.
- Search repo for `Start-WsusOperation`; expected hits are runner, GUI call sites, tests, and docs.
