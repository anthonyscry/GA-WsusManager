using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WsusManager.Core.Logging;

namespace WsusManager.App.ViewModels;

/// <summary>
/// Primary ViewModel for the main application window.
/// Manages dashboard state, operation execution, log output, and cancellation.
/// All long-running operations must go through RunOperationAsync — no raw async
/// void handlers are permitted anywhere in the application.
/// </summary>
public partial class MainViewModel : ObservableObject
{
    private readonly ILogService _logService;
    private CancellationTokenSource? _operationCts;

    public MainViewModel(ILogService logService)
    {
        _logService = logService;
    }

    /// <summary>
    /// Status bar message displayed at the bottom of the window.
    /// </summary>
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CancelOperationCommand))]
    private string _statusMessage = "Ready";

    /// <summary>
    /// Whether an operation is currently running. When true, all operation
    /// commands are disabled via CanExecute and the Cancel button is enabled.
    /// </summary>
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CancelOperationCommand))]
    private bool _isOperationRunning;

    /// <summary>
    /// Accumulated log output from the current and previous operations.
    /// Displayed in the expandable log panel.
    /// </summary>
    [ObservableProperty]
    private string _logOutput = string.Empty;

    /// <summary>
    /// The name of the currently running operation (shown in status bar).
    /// </summary>
    [ObservableProperty]
    private string _currentOperationName = string.Empty;

    /// <summary>
    /// Cancels the currently running operation.
    /// </summary>
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

    /// <summary>
    /// Central operation runner. Every operation in the application must go through
    /// this method. It manages:
    /// - IsOperationRunning flag (disables all operation buttons)
    /// - CancellationTokenSource lifecycle
    /// - Progress reporting to the log panel
    /// - Error handling with log output (no popup dialogs for operation errors)
    /// - State cleanup in the finally block
    /// </summary>
    /// <param name="operationName">Human-readable name for status display and logging.</param>
    /// <param name="operation">
    /// The async operation to run. Receives an IProgress&lt;string&gt; for log output
    /// and a CancellationToken for cooperative cancellation. Returns true on success.
    /// </param>
    /// <returns>True if the operation completed successfully, false otherwise.</returns>
    public async Task<bool> RunOperationAsync(
        string operationName,
        Func<IProgress<string>, CancellationToken, Task<bool>> operation)
    {
        if (IsOperationRunning)
        {
            AppendLog("[WARNING] An operation is already running.");
            return false;
        }

        _operationCts = new CancellationTokenSource();
        IsOperationRunning = true;
        CurrentOperationName = operationName;
        StatusMessage = $"Running: {operationName}...";

        _logService.Info("Starting operation: {Operation}", operationName);
        AppendLog($"=== {operationName} ===");

        var progress = new Progress<string>(line => AppendLog(line));

        try
        {
            var success = await operation(progress, _operationCts.Token);

            if (success)
            {
                StatusMessage = $"{operationName} completed successfully.";
                AppendLog($"=== {operationName} completed ===");
                _logService.Info("Operation completed: {Operation}", operationName);
            }
            else
            {
                StatusMessage = $"{operationName} failed.";
                AppendLog($"=== {operationName} FAILED ===");
                _logService.Warning("Operation failed: {Operation}", operationName);
            }

            return success;
        }
        catch (OperationCanceledException)
        {
            StatusMessage = $"{operationName} cancelled.";
            AppendLog($"=== {operationName} CANCELLED ===");
            _logService.Info("Operation cancelled: {Operation}", operationName);
            return false;
        }
        catch (Exception ex)
        {
            StatusMessage = $"{operationName} failed with error.";
            AppendLog($"[ERROR] {ex.Message}");
            AppendLog($"=== {operationName} FAILED ===");
            _logService.Error(ex, "Operation error: {Operation}", operationName);
            return false;
        }
        finally
        {
            IsOperationRunning = false;
            CurrentOperationName = string.Empty;
            _operationCts?.Dispose();
            _operationCts = null;
        }
    }

    /// <summary>
    /// Appends a line to the log output panel.
    /// </summary>
    public void AppendLog(string line)
    {
        LogOutput += line + Environment.NewLine;
    }

    /// <summary>
    /// Clears the log output panel.
    /// </summary>
    [RelayCommand]
    private void ClearLog()
    {
        LogOutput = string.Empty;
    }
}
