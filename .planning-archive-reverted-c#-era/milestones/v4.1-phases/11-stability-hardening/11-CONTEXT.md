# Phase 11: Stability Hardening — Context

**Goal:** The application handles edge cases and error conditions without crashing or leaving the UI in a broken state.

**Requirements:**
- STAB-01: No unhandled exceptions reach the user as raw crash dialogs
- STAB-02: Cancel reliably stops running processes
- STAB-03: Concurrent operation attempts are blocked and clearly communicated

---

## Files Reviewed

| File | Purpose |
|------|---------|
| `src/WsusManager.App/ViewModels/MainViewModel.cs` | Central operation runner, cancel, concurrent blocking |
| `src/WsusManager.App/App.xaml.cs` | Global unhandled exception handlers |
| `src/WsusManager.Core/Infrastructure/ProcessRunner.cs` | External process execution and cancellation |
| `src/WsusManager.App/Program.cs` | Entry point, DI setup |
| `src/WsusManager.App/Views/MainWindow.xaml.cs` | Window initialization |
| `src/WsusManager.Core/Services/DatabaseBackupService.cs` | Representative complex service |
| `src/WsusManager.Core/Services/SyncService.cs` | Representative orchestration service |
| `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs` | Existing stability test coverage |

---

## STAB-01: Unhandled Exception Coverage

### Global Exception Handlers — PASS

`App.xaml.cs` registers all three standard .NET exception interception points in `OnStartup`:

```csharp
DispatcherUnhandledException += OnDispatcherUnhandledException;        // WPF UI thread
TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;    // async void / fire-and-forget
AppDomain.CurrentDomain.UnhandledException += OnAppDomainUnhandledException; // last resort
```

All three handlers:
1. Log the exception via `ILogger`
2. Show a user-friendly `MessageBox` (fatal errors include "must close" language)
3. Mark the exception as handled (`e.Handled = true`, `e.SetObserved()`)

The AppDomain handler correctly wraps its `ShowErrorDialog` call in a try/catch because showing a dialog during process termination may itself fail.

### RunOperationAsync — PASS

`MainViewModel.RunOperationAsync` is the sole gateway for all long-running work. Its structure is:

```csharp
try
{
    var success = await operation(progress, _operationCts.Token);
    // ... set status message
    return success;
}
catch (OperationCanceledException) { /* log, return false */ }
catch (Exception ex)               { /* log, append to UI log, return false */ }
finally
{
    IsOperationRunning = false;
    CurrentOperationName = string.Empty;
    _operationCts?.Dispose();
    _operationCts = null;
}
```

Key findings:
- The `finally` block always executes regardless of exception type — `IsOperationRunning` is guaranteed to reset.
- The `CancellationTokenSource` is always disposed in `finally`, preventing resource leaks.
- Both exception branches append error information to `LogOutput` so the user sees what happened.
- The `OperationCanceledException` is caught separately so cancellation is never mis-reported as an error.

### Individual Commands — PASS

All `[RelayCommand]` methods are `async Task` (not `async void`). This means exceptions propagate back to `RunOperationAsync`'s catch block rather than becoming unobserved. The one exception is:

- `MainWindow_Loaded` is `async void` (required by WPF event signature). If `InitializeAsync()` throws, the exception escapes to the `DispatcherUnhandledException` handler — this is the correct fallback path and is covered.

### Service-Level Exception Handling — PASS

Services such as `DatabaseBackupService` and `SyncService` follow a consistent pattern:
- `OperationCanceledException` is re-thrown (so cancellation propagates correctly to `RunOperationAsync`).
- All other exceptions are caught, logged, and returned as `OperationResult.Fail(...)` — they do not bubble up unhandled.
- The restore workflow uses `CancellationToken.None` for cleanup steps after a cancellation, ensuring services are restarted even when the user cancels mid-restore.

### Minor Issue: RefreshDashboard Called Inside Operation Lambdas

Several commands call `await RefreshDashboard()` inside the operation lambda after the main work completes:

```csharp
await RunOperationAsync("Install WSUS", async (progress, ct) =>
{
    ...
    if (result.Success)
        await RefreshDashboard();   // This uses CancellationToken.None internally
    return result.Success;
});
```

`RefreshDashboard` itself has a try/catch that swallows exceptions from the dashboard service. If the dashboard throws, it logs but returns normally — so this cannot cause `RunOperationAsync` to catch an unexpected exception. This is safe.

### Minor Issue: SaveLog Uses Try/Catch But Not AppendLog on All Paths

`SaveLog` catches exceptions from `File.WriteAllText` and calls `AppendLog` to report them — good. The `SaveFileDialog` itself is not wrapped, but WPF dialog failures from broken file system state would propagate to `DispatcherUnhandledException` which is the correct handler for UI-thread exceptions.

---

## STAB-02: Cancellation

### CancelOperation Command — PASS

```csharp
[RelayCommand(CanExecute = nameof(CanCancelOperation))]
private void CancelOperation()
{
    if (_operationCts is { IsCancellationRequested: false })
    {
        _logService.Info("User cancelled operation: {Operation}", CurrentOperationName);
        _operationCts.Cancel();
    }
}

private bool CanCancelOperation() => IsOperationRunning;
```

The cancel button is only enabled while `IsOperationRunning` is true (bound via `CancelButtonVisibility`). Calling `Cancel()` on an already-cancelled token is guarded by the `IsCancellationRequested` check.

### ProcessRunner Cancellation — PASS

```csharp
catch (OperationCanceledException)
{
    _logService.Info("Killing process tree: {Executable} (cancelled)", executable);
    try
    {
        proc.Kill(entireProcessTree: true);
    }
    catch (Exception ex)
    {
        _logService.Warning("Failed to kill process: {Error}", ex.Message);
    }
    throw;  // re-throws so RunOperationAsync catches OperationCanceledException
}
```

Key points:
- `proc.Kill(entireProcessTree: true)` kills child processes (e.g. PowerShell spawning sub-processes), preventing orphans.
- The `Kill` call is wrapped in try/catch because the process may have already exited by the time cancel is processed.
- The `OperationCanceledException` is re-thrown so it propagates back through the service call stack to `RunOperationAsync`.

### Cancellation Token Propagation — PASS

All service methods accept and forward `CancellationToken ct` through to SQL operations, process runner calls, and async awaits. The token is not ignored at any layer reviewed.

### Edge Case: CancellationToken.None for Cleanup

`DatabaseBackupService.RestoreAsync` deliberately uses `CancellationToken.None` for service-restart cleanup steps after a failure or mid-restore cancellation:

```csharp
await RestartServicesAsync(sqlInstance, progress, CancellationToken.None);
```

This is intentional and correct — the restore operation should always attempt to restart services regardless of whether the user cancelled. This prevents leaving the WSUS server with stopped services.

---

## STAB-03: Concurrent Operation Blocking

### IsOperationRunning Guard — PASS

```csharp
public async Task<bool> RunOperationAsync(...)
{
    if (IsOperationRunning)
    {
        AppendLog("[WARNING] An operation is already running.");
        return false;
    }
    ...
}
```

All operations go through `RunOperationAsync`, so the single guard point is sufficient. The guard message is appended to the log panel so the user has visible feedback.

### CanExecute Guards — PASS

Commands use `CanExecute` predicates that check `IsOperationRunning`:

```csharp
private bool CanExecuteWsusOperation() => IsWsusInstalled && !IsOperationRunning;
private bool CanExecuteOnlineOperation() => IsWsusInstalled && !IsOperationRunning && IsOnline;
private bool CanExecuteInstall() => !IsOperationRunning;
```

`IsOperationRunning` is decorated with `[NotifyCanExecuteChangedFor(nameof(CancelOperationCommand))]` which triggers the cancel button. However, `NotifyCommandCanExecuteChanged()` is only called from `UpdateDashboardCards` — it is not called from within `RunOperationAsync` itself when `IsOperationRunning` changes.

**Issue STAB-03-A (Minor): CanExecute Not Notified on IsOperationRunning Change**

When `IsOperationRunning` is set to `true` at the start of `RunOperationAsync`, and then back to `false` in the `finally` block, the operation commands (`RunDiagnosticsCommand`, `RunDeepCleanupCommand`, etc.) do not have their `CanExecute` state refreshed. In practice, this means buttons may remain visually enabled in the UI while an operation is running, because CommunityToolkit's `[NotifyCanExecuteChangedFor]` is only applied to `CancelOperationCommand` on the `IsOperationRunning` property, not to all operation commands.

`NotifyCommandCanExecuteChanged()` is only called from `UpdateDashboardCards`, which is called from `RefreshDashboard`. Some operations do call `RefreshDashboard` after completing (e.g. DeepCleanup does not; Diagnostics does). This means after an operation that doesn't call `RefreshDashboard`, all operation buttons remain correctly-enabled but their visual disabled state during the operation is not enforced via WPF binding.

This is a real gap: during a running operation, operation buttons appear enabled but clicking them logs "already running" and returns false. Users get no visual feedback that the buttons are locked.

**Recommendation:** Add `[NotifyCanExecuteChangedFor]` for all operation commands to `IsOperationRunning`, or call `NotifyCommandCanExecuteChanged()` inside `RunOperationAsync` when setting `IsOperationRunning`.

---

## Test Coverage Assessment

`MainViewModelTests.cs` already covers the core stability scenarios:

| Scenario | Test | Status |
|----------|------|--------|
| IsOperationRunning true during op | `RunOperationAsync_Sets_IsOperationRunning_During_Execution` | PASS |
| State resets after success | `RunOperationAsync_Resets_State_After_Success` | PASS |
| State resets after failure | `RunOperationAsync_Resets_State_After_Failure` | PASS |
| OperationCanceledException caught | `RunOperationAsync_Catches_OperationCanceledException` | PASS |
| General exception caught | `RunOperationAsync_Catches_Unhandled_Exception` | PASS |
| Concurrent op blocked | `RunOperationAsync_Blocks_Concurrent_Operations` | PASS |
| Cancel command triggers cancel | `CancelCommand_Triggers_Cancellation` | PASS |

---

## Summary of Findings

### What Is Working Well

1. **RunOperationAsync** is solid: try/catch/finally structure guarantees state reset in all paths.
2. **ProcessRunner cancellation** kills the entire process tree — no orphan processes.
3. **Global exception handlers** cover all three exception vectors (Dispatcher, TaskScheduler, AppDomain).
4. **Service-level error handling** consistently returns `OperationResult.Fail` rather than throwing.
5. **Concurrent blocking** is enforced at a single chokepoint with user-visible feedback.
6. **OperationCanceledException** is consistently re-thrown from services so cancellation semantics are preserved end-to-end.
7. **Test coverage** for the core stability patterns is comprehensive and passing.

### Issues to Fix

| ID | Severity | Description | File | Line |
|----|----------|-------------|------|------|
| STAB-03-A | Medium | `IsOperationRunning` changes do not trigger `NotifyCanExecuteChanged` on operation commands, so buttons are not visually disabled during operations | `MainViewModel.cs` | ~147-148, ~186-236 |

### Issues That Are Not Present (confirmed safe)

- No `async void` command handlers that could produce unobserved exceptions
- No raw `throw` in service code that bypasses `RunOperationAsync`'s catch
- No `CancellationToken` ignored in service chains
- No `_operationCts` leak (always disposed in `finally`)
- No missing null check on `_operationCts` before cancel (guarded by `IsCancellationRequested` check)

---

## Proposed Work Items for Phase 11

### STAB-01: No Unhandled Exceptions
Status: **Already implemented.** No work required. Global handlers cover all vectors. `RunOperationAsync` catches and logs all exceptions. Services return `OperationResult.Fail` rather than throwing.

### STAB-02: Cancel Works
Status: **Already implemented.** No work required. `CancelOperation` signals the CTS. `ProcessRunner` kills the process tree. `OperationCanceledException` propagates correctly from all service layers.

### STAB-03: Concurrent Blocking
Status: **Mostly implemented.** One gap to fix:

**STAB-03-A Fix:** Add `NotifyCanExecuteChanged` for all operation commands when `IsOperationRunning` changes.

Options:
1. Add `[NotifyCanExecuteChangedFor(nameof(RunDiagnosticsCommand))]` (and all other commands) to the `IsOperationRunning` property — clean but verbose with 15+ commands.
2. Call `NotifyCommandCanExecuteChanged()` at the start of `RunOperationAsync` (when setting `IsOperationRunning = true`) and again in the `finally` block (when setting `IsOperationRunning = false`) — minimal change, single location.

Option 2 is preferred: it keeps the change in one place and ensures buttons are visually disabled immediately when any operation starts and re-enabled as soon as it ends, regardless of whether the operation triggers a dashboard refresh.

### Additional Tests to Add

Even though the core patterns are sound, Phase 11 should add tests for:
1. **Verify `IsOperationRunning` blocks CanExecute** — test that `CanExecuteWsusOperation()` returns false when `IsOperationRunning` is true (current tests set `IsWsusInstalled` but not `IsOperationRunning` in mid-operation scenarios).
2. **Verify cancel button visibility** — `CancelButtonVisibility` returns `Visible` only when `IsOperationRunning`.
3. **Verify `_operationCts` is null after operation completes** — guards against double-cancel on stale token.
