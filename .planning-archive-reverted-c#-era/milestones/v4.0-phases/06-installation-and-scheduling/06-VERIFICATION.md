# Phase 6: Installation and Scheduling -- Verification

**Verified:** 2026-02-20

---

## Build Verification

```
dotnet build --configuration Debug   -> 0 warnings, 0 errors
dotnet build --configuration Release -> 0 warnings, 0 errors
dotnet test                          -> 214 passed, 0 failed
```

## Test Breakdown

| Test File | Tests | Category |
|-----------|-------|----------|
| InstallationServiceTests | 10 | Prerequisite validation, argument construction, script resolution |
| ScheduledTaskServiceTests | 15 | Monthly/Weekly/Daily args, credentials, DayOfWeek mapping, query parsing |
| GpoDeploymentServiceTests | 6 | Source validation, file copy, instruction text |
| MainViewModelTests (Phase 6) | 6 | CanExecute for Install (no WSUS req), Schedule, GPO |
| DiContainerTests (Phase 6) | 4 | Service resolution for all 3 new services |
| **Phase 6 Total** | **41** | |
| **All Tests Total** | **214** | |

## Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Installation wizard guides user -- no console prompts | PASS | InstallDialog collects all params; `-NonInteractive` flag; 10 validation tests |
| 2 | WSUS buttons disabled when not installed; Install button stays active | PASS | `CanExecuteInstall()` vs `CanExecuteWsusOperation()`; 6 CanExecute tests |
| 3 | Scheduled task with domain credentials, runs whether logged on or not | PASS | `/RU` + `/RP` + `/RL HIGHEST`; 15 schtasks argument tests |
| 4 | GPO files copied with step-by-step instructions shown | PASS | Recursive copy to `C:\WSUS\WSUS GPO\`; copyable instructions dialog; 6 tests |

---

*Phase: 06-installation-and-scheduling*
*Verified: 2026-02-20*
