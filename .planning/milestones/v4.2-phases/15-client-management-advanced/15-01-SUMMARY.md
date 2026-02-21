---
phase: 15-client-management-advanced
plan: 01
subsystem: client-management
tags: [mass-operations, winrm, gp-update, xaml, mvvm]
dependency-graph:
  requires: [phase-14-client-management-core]
  provides: [MassForceCheckInAsync, MassOperationsCard, LoadHostFileCommand, RunMassGpUpdateCommand]
  affects: [IClientService, ClientService, MainViewModel, MainWindow.xaml]
tech-stack:
  added: []
  patterns: [sequential-batch-iteration, concurrent-bag-progress-capture]
key-files:
  created: []
  modified:
    - src/WsusManager.Core/Services/Interfaces/IClientService.cs
    - src/WsusManager.Core/Services/ClientService.cs
    - src/WsusManager.App/ViewModels/MainViewModel.cs
    - src/WsusManager.App/Views/MainWindow.xaml
    - src/WsusManager.Tests/Services/ClientServiceTests.cs
decisions:
  - "MassForceCheckInAsync iterates hosts sequentially (not parallel) — WinRM connections can saturate network on simultaneous large batches"
  - "MassForceCheckInAsync returns Fail if any host failed but still processes all hosts — partial-success pattern gives max feedback"
  - "Parse MassHostnames in ViewModel (not service) — service receives clean IReadOnlyList<string>; ViewModel handles user input formatting"
  - "LoadHostFile has no CanExecute restriction — file loading always available, consistent with single-host hostname field pattern"
  - "ConcurrentBag replaces List in CreateProgressCapture test helper — Progress<T> posts callbacks to threadpool in xUnit (no SyncCtx), causing collection-modified race"
metrics:
  duration: 4 minutes
  completed: 2026-02-21
  tasks-completed: 2
  files-modified: 5
---

# Phase 15 Plan 01: Mass GPUpdate Summary

Mass GPUpdate feature for batch WinRM operations across multiple WSUS client hosts, with service layer iteration, per-host progress reporting, and a Mass Operations UI card in the Client Tools panel.

## What Was Built

### Service Layer (Task 1)

**`IClientService.MassForceCheckInAsync`** — new interface method:
```csharp
Task<OperationResult> MassForceCheckInAsync(
    IReadOnlyList<string> hostnames,
    IProgress<string> progress,
    CancellationToken ct = default);
```

**`ClientService.MassForceCheckInAsync`** implementation:
- Filters whitespace-only entries before processing
- Validates empty list → returns `Fail` immediately
- Reports `"Processing {N} host(s)..."` at start
- Iterates hosts sequentially with `[Host {i}/{N}] {hostname}...` prefix per host
- Calls existing `ForceCheckInAsync` per host — no new remote logic
- Tracks pass/fail count
- Respects cancellation: `ct.ThrowIfCancellationRequested()` between hosts
- Final summary: `"[OK] Mass GPUpdate complete: {passed}/{total} hosts succeeded, {failed} failed."`
- Returns `Ok` only if all hosts succeeded; `Fail` if any failed (still processes all)

### Tests (Task 1)

5 new unit tests in `ClientServiceTests.cs`:
- `MassForceCheckIn_AllSucceed_Returns_True_And_Mentions_All_Hosts` — 3/3 success path
- `MassForceCheckIn_OneHostFails_Returns_False_Shows_PassFail_Count` — partial failure, 1/2 message
- `MassForceCheckIn_EmptyList_Returns_Failure_With_Descriptive_Message` — guard validation
- `MassForceCheckIn_WhitespaceOnlyEntries_TreatedAsEmpty` — whitespace-filter validation
- `MassForceCheckIn_Cancellation_StopsProcessingRemainingHosts` — cancellation via `Assert.ThrowsAsync<OperationCanceledException>`

**Total: 282 tests, 0 failures.**

### ViewModel (Task 2)

Added to `MainViewModel.cs` CLIENT MANAGEMENT section:
- `MassHostnames` observable property (bound to multi-line TextBox)
- `OnMassHostnamesChanged` partial method → notifies `RunMassGpUpdateCommand.NotifyCanExecuteChanged()`
- `CanExecuteMassOperation()` helper: `!IsOperationRunning && !IsNullOrWhiteSpace(MassHostnames)`
- `LoadHostFileCommand` (no CanExecute): opens `OpenFileDialog`, reads all lines, sets `MassHostnames`, logs count
- `RunMassGpUpdateCommand(CanExecute = CanExecuteMassOperation)`: parses on `,`, `;`, `\n`, `\r`; calls `RunOperationAsync` → `MassForceCheckInAsync`
- `RunMassGpUpdateCommand` added to `NotifyCommandCanExecuteChanged()` for disable-during-operation

### UI (Task 2)

New Mass Operations card in `MainWindow.xaml` Client Tools panel, inserted between Remote Operations and Error Code Lookup:

```
[ Mass Operations                                        ]
[ Enter hostnames (one per line, or comma-separated)... ]
[ ┌──────────────────────────────────────────────────┐  ]
[ │ host01                                           │  ]
[ │ host02                                           │  ]
[ └──────────────────────────────────────────────────┘  ]
[ [Load from File]   [Mass GPUpdate]                    ]
```

Uses same StaticResource keys as adjacent cards: `BgCard`, `BgInput`, `Text1`, `Text2`, `Border`, `BtnSec`, `BtnGreen`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed race condition in test progress capture helper**
- **Found during:** Task 1 test execution
- **Issue:** `CreateProgressCapture` used `List<string>` which caused `InvalidOperationException: Collection was modified; enumeration operation may not execute` in `ForceCheckIn_Reports_Step_Progress` when our new multi-host tests ran concurrently. `Progress<T>` posts callbacks to the thread pool in xUnit (no SynchronizationContext), so callbacks can fire while `LINQ.Any()` is enumerating.
- **Fix:** Changed `List<string>` to `ConcurrentBag<string>` in `CreateProgressCapture` — thread-safe for concurrent add+enumerate.
- **Files modified:** `src/WsusManager.Tests/Services/ClientServiceTests.cs`
- **Commit:** 0615ea9

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| IClientService.cs contains MassForceCheckInAsync | FOUND |
| ClientService.cs contains MassForceCheckInAsync | FOUND |
| MainViewModel.cs contains MassHostnames | FOUND |
| MainWindow.xaml contains Mass GPUpdate | FOUND |
| SUMMARY.md created | FOUND |
| Task 1 commit 0615ea9 | FOUND |
| Task 2 commit ee52ec4 | FOUND |
| All 282 tests pass | PASS |
