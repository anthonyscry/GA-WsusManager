using Moq;
using WsusManager.App.ViewModels;
using WsusManager.Core.Logging;

namespace WsusManager.Tests.ViewModels;

/// <summary>
/// Tests for the MainViewModel async operation pattern.
/// Verifies that RunOperationAsync correctly manages state, cancellation,
/// error handling, and progress reporting.
/// </summary>
public class MainViewModelTests
{
    private readonly Mock<ILogService> _mockLog = new();
    private readonly MainViewModel _vm;

    public MainViewModelTests()
    {
        _vm = new MainViewModel(_mockLog.Object);
    }

    [Fact]
    public async Task RunOperationAsync_Sets_IsOperationRunning_During_Execution()
    {
        bool wasRunningDuringOp = false;

        await _vm.RunOperationAsync("Test", async (progress, ct) =>
        {
            wasRunningDuringOp = _vm.IsOperationRunning;
            await Task.CompletedTask;
            return true;
        });

        Assert.True(wasRunningDuringOp, "IsOperationRunning should be true during operation");
        Assert.False(_vm.IsOperationRunning, "IsOperationRunning should be false after operation");
    }

    [Fact]
    public async Task RunOperationAsync_Resets_State_After_Success()
    {
        var result = await _vm.RunOperationAsync("Test", async (progress, ct) =>
        {
            await Task.CompletedTask;
            return true;
        });

        Assert.True(result);
        Assert.False(_vm.IsOperationRunning);
        Assert.Equal(string.Empty, _vm.CurrentOperationName);
        Assert.Contains("completed", _vm.StatusMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task RunOperationAsync_Resets_State_After_Failure()
    {
        var result = await _vm.RunOperationAsync("Test", async (progress, ct) =>
        {
            await Task.CompletedTask;
            return false;
        });

        Assert.False(result);
        Assert.False(_vm.IsOperationRunning);
        Assert.Contains("failed", _vm.StatusMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task RunOperationAsync_Catches_OperationCanceledException()
    {
        var result = await _vm.RunOperationAsync("Test", async (progress, ct) =>
        {
            await Task.CompletedTask;
            throw new OperationCanceledException();
        });

        Assert.False(result);
        Assert.False(_vm.IsOperationRunning);
        Assert.Contains("CANCELLED", _vm.LogOutput);
    }

    [Fact]
    public async Task RunOperationAsync_Catches_Unhandled_Exception()
    {
        var result = await _vm.RunOperationAsync("Test", async (progress, ct) =>
        {
            await Task.CompletedTask;
            throw new InvalidOperationException("Something broke");
        });

        Assert.False(result);
        Assert.False(_vm.IsOperationRunning);
        Assert.Contains("Something broke", _vm.LogOutput);
        Assert.Contains("FAILED", _vm.LogOutput);
    }

    [Fact]
    public async Task RunOperationAsync_Blocks_Concurrent_Operations()
    {
        var tcs = new TaskCompletionSource<bool>();

        // Start a long-running operation
        var firstOp = _vm.RunOperationAsync("First", async (progress, ct) =>
        {
            return await tcs.Task;
        });

        // Try to start a second operation while first is running
        var secondResult = await _vm.RunOperationAsync("Second", async (progress, ct) =>
        {
            await Task.CompletedTask;
            return true;
        });

        Assert.False(secondResult, "Second operation should be rejected");
        Assert.Contains("already running", _vm.LogOutput, StringComparison.OrdinalIgnoreCase);

        // Complete the first operation
        tcs.SetResult(true);
        await firstOp;
    }

    [Fact]
    public async Task CancelCommand_Triggers_Cancellation()
    {
        var operationStarted = new TaskCompletionSource();

        var opTask = _vm.RunOperationAsync("CancelTest", async (progress, ct) =>
        {
            operationStarted.SetResult();
            // Wait until cancelled
            await Task.Delay(TimeSpan.FromSeconds(30), ct);
            return true;
        });

        await operationStarted.Task;
        Assert.True(_vm.IsOperationRunning);

        // Cancel
        _vm.CancelOperationCommand.Execute(null);

        var result = await opTask;
        Assert.False(result);
        Assert.Contains("CANCELLED", _vm.LogOutput);
    }

    [Fact]
    public void ClearLog_Clears_LogOutput()
    {
        _vm.AppendLog("Some output");
        Assert.NotEmpty(_vm.LogOutput);

        _vm.ClearLogCommand.Execute(null);
        Assert.Empty(_vm.LogOutput);
    }

    [Fact]
    public async Task RunOperationAsync_Reports_Progress()
    {
        await _vm.RunOperationAsync("ProgressTest", async (progress, ct) =>
        {
            progress.Report("Step 1 done");
            progress.Report("Step 2 done");
            await Task.CompletedTask;
            return true;
        });

        Assert.Contains("Step 1 done", _vm.LogOutput);
        Assert.Contains("Step 2 done", _vm.LogOutput);
    }
}
