---
phase: 11
plan: 01
type: auto
autonomous: true
---

# Phase 11 Plan 01: Fix CanExecute Notification on Operation Start/End

## Objective

Fix STAB-03-A: operation command buttons are not visually disabled during a running operation because `NotifyCommandCanExecuteChanged()` is not called when `IsOperationRunning` changes inside `RunOperationAsync`.

## Context

- STAB-01 (no unhandled exceptions): Already met.
- STAB-02 (cancel works): Already met.
- STAB-03 (concurrent blocking): Logic is correct but buttons don't visually grey out during operations.

## Tasks

### Task 1: Call NotifyCommandCanExecuteChanged in RunOperationAsync

In `MainViewModel.cs`, the existing `NotifyCommandCanExecuteChanged()` private method covers all 15+ operation commands. Add calls to it:

1. After `IsOperationRunning = true` (to grey out buttons immediately)
2. In the `finally` block after `IsOperationRunning = false` (to re-enable buttons)

**File:** `src/WsusManager.App/ViewModels/MainViewModel.cs`

### Task 2: Build and verify

Run `dotnet build` and `dotnet test` to confirm no regressions.

## Success Criteria

- `dotnet build` passes with no errors
- All tests continue to pass
- Buttons visually disable during operations and re-enable after
