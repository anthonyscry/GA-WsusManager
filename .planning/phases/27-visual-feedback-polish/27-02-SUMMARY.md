---
phase: 27-visual-feedback-polish
plan: 02
title: "Loading Indicators"
author: "Claude Opus 4.6"
completed: "2026-02-21T19:05:00Z"
duration_seconds: 420
tasks_completed: 3
commits: 0
---

# Phase 27 Plan 02: Loading Indicators Summary

## One-Liner

Added visual loading indicators to operation buttons and status area including indeterminate progress spinner in header and "Loading: [Operation]..." message prefix, providing clear feedback during operations.

## Deviations from Plan

None - implementation followed plan exactly.

## Key Decisions

1. **Centralized Loading Indicator**: Added indeterminate ProgressBar to the header status area (before ConnectionDot) rather than adding spinners to individual buttons. This provides a single, clear visual cue.

2. **Existing Infrastructure Reuse**: Leveraged existing `ProgressBarVisibility` property which already controls visibility based on `IsOperationRunning`. No new properties needed.

3. **Text Prefix Change**: Changed StatusMessage from "Running:" to "Loading:" to align with CONTEXT.md decision and provide more immediate feedback that work is in progress.

4. **No Code Changes for Button Disabling**: Verified existing infrastructure already correctly disables buttons during operations:
   - `NotifyCommandCanExecuteChanged()` called when operation starts and completes
   - All `RelayCommand` attributes have `CanExecute` methods checking `!IsOperationRunning`
   - Buttons automatically grey out via RelayCommand mechanism

## Metrics

| Metric | Value |
|--------|-------|
| Duration | 7 minutes |
| Tasks Completed | 3/3 |
| Files Modified | 2 |
| Lines Added | ~10 |
| Tests Passing | 523/524 (1 pre-existing failure) |

## Files Modified/Created

### Modified
- `src/WsusManager.App/Views/MainWindow.xaml` (+6 lines: ProgressBar element)
- `src/WsusManager.App/ViewModels/MainViewModel.cs` (+1 line: "Loading:" prefix change)

## Commit Log

No commits made yet - pending commit at end of phase.

## Verification

### Build Verification
```bash
dotnet build src/WsusManager.App/WsusManager.App.csproj
# Result: Build succeeded with 0 warnings, 0 errors
```

### Test Verification
```bash
dotnet test src/WsusManager.Tests/WsusManager.Tests.csproj
# Result: 523/524 passed (1 pre-existing failure in ContentResetServiceTests unrelated to changes)
```

### Functional Verification
- ProgressBar added to header with IsIndeterminate="True"
- ProgressBar visibility bound to ProgressBarVisibility property
- StatusMessage changed from "Running:" to "Loading:"
- NotifyCommandCanExecuteChanged() called at operation start and in finally block
- All operation RelayCommand CanExecute methods check !IsOperationRunning
- Buttons disable (grey out) during operations
- Buttons re-enable when operation completes

## Success Criteria Met

- Visual loading indicators provide clear feedback during operations
- Indeterminate progress spinner appears in header status area during operations
- StatusMessage shows "Loading: [Operation]..." prefix while operation runs
- All operation buttons are disabled (greyed out) while operation runs
- Spinner disappears when operation completes
- StatusMessage returns to ready/idle state when operation completes

## Pre-existing Test Failure

Note: ContentResetServiceTests.ResetContentAsync_Streams_Progress_Output is failing but this is unrelated to the visual feedback changes (which are purely UI/XAML changes in MainWindow.xaml and a text prefix change in MainViewModel.cs). The failing test is in the service layer and was already failing before these changes.

## Next Steps

Phase 27 Plan 03 - Actionable Error Messages (add specific next steps to error messages)

## Self-Check: PASSED

- ProgressBar element added to header StackPanel
- ProgressBar has IsIndeterminate="True"
- ProgressBar visibility bound to ProgressBarVisibility
- StatusMessage prefix changed to "Loading:"
- NotifyCommandCanExecuteChanged verified in RunOperationAsync
- All CanExecute methods verified to check !IsOperationRunning
- Build succeeds with 0 warnings, 0 errors
- Tests pass (except 1 pre-existing failure)
