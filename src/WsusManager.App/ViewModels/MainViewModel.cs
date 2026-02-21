using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using WsusManager.App.Services;
using WsusManager.App.Views;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.App.ViewModels;

/// <summary>
/// Primary ViewModel for the main application window.
/// Manages dashboard state, navigation, operation execution, log output,
/// server mode detection, WSUS installation detection, and settings persistence.
/// All long-running operations must go through RunOperationAsync.
/// </summary>
public partial class MainViewModel : ObservableObject, IDisposable
{
    private readonly ILogService _logService;
    private readonly ISettingsService _settingsService;
    private readonly IDashboardService _dashboardService;
    private readonly IHealthService _healthService;
    private readonly IWindowsServiceManager _serviceManager;
    private readonly IContentResetService _contentResetService;
    private readonly IDeepCleanupService _deepCleanupService;
    private readonly IDatabaseBackupService _backupService;
    private readonly ISyncService _syncService;
    private readonly IExportService _exportService;
    private readonly IImportService _importService;
    private readonly IInstallationService _installationService;
    private readonly IScheduledTaskService _scheduledTaskService;
    private readonly IGpoDeploymentService _gpoDeploymentService;
    private readonly IClientService _clientService;
    private readonly IScriptGeneratorService _scriptGeneratorService;
    private readonly IThemeService _themeService;
    private readonly IBenchmarkTimingService _benchmarkTimingService;
    private readonly ISettingsValidationService _validationService;
    private readonly ICsvExportService _csvExportService;
    private readonly StringBuilder _logBuilder = new();
    private readonly Queue<string> _logBatchQueue = new();
    private DispatcherTimer? _logBatchTimer;
    private const int LogBatchSize = 50;  // Lines per batch
    private const int LogBatchIntervalMs = 100;  // Flush interval
    private CancellationTokenSource? _operationCts;
    private DispatcherTimer? _refreshTimer;
    private EventHandler? _refreshTimerHandler;
    private AppSettings _settings = new();
    private bool _isInitialized;
    private bool _disposed;

    /// <summary>
    /// Maximum number of updates to auto-approve per sync run (safety threshold).
    /// </summary>
    private const int MaxAutoApproveCount = 200;

    /// <summary>
    /// Resolves a theme brush by key from the application's merged resource dictionaries.
    /// Falls back to the provided default color if the resource is not found
    /// (e.g., during unit tests where no WPF Application is running).
    /// </summary>
    private static SolidColorBrush GetThemeBrush(string resourceKey, Color fallback)
    {
        if (Application.Current?.TryFindResource(resourceKey) is SolidColorBrush brush)
            return brush;
        return new SolidColorBrush(fallback);
    }

    /// <summary>
    /// Formats a TimeSpan into a human-readable string for time estimates.
    /// Returns "2m 15s" format for durations >= 1 minute.
    /// Returns "45s" format for durations less than 1 minute.
    /// Returns "10s" format for durations less than 10 seconds.
    /// </summary>
    private static string FormatTimeSpan(TimeSpan ts)
    {
        if (ts.TotalMinutes >= 1)
        {
            var minutes = (int)ts.TotalMinutes;
            var seconds = ts.Seconds;
            return seconds > 0 ? $"{minutes}m {seconds}s" : $"{minutes}m";
        }
        return $"{(int)ts.TotalSeconds}s";
    }

    public MainViewModel(
        ILogService logService,
        ISettingsService settingsService,
        IDashboardService dashboardService,
        IHealthService healthService,
        IWindowsServiceManager serviceManager,
        IContentResetService contentResetService,
        IDeepCleanupService deepCleanupService,
        IDatabaseBackupService backupService,
        ISyncService syncService,
        IExportService exportService,
        IImportService importService,
        IInstallationService installationService,
        IScheduledTaskService scheduledTaskService,
        IGpoDeploymentService gpoDeploymentService,
        IClientService clientService,
        IScriptGeneratorService scriptGeneratorService,
        IThemeService themeService,
        IBenchmarkTimingService benchmarkTimingService,
        ISettingsValidationService validationService,
        ICsvExportService csvExportService)
    {
        _logService = logService;
        _settingsService = settingsService;
        _dashboardService = dashboardService;
        _healthService = healthService;
        _serviceManager = serviceManager;
        _contentResetService = contentResetService;
        _deepCleanupService = deepCleanupService;
        _backupService = backupService;
        _syncService = syncService;
        _exportService = exportService;
        _importService = importService;
        _installationService = installationService;
        _scheduledTaskService = scheduledTaskService;
        _gpoDeploymentService = gpoDeploymentService;
        _clientService = clientService;
        _scriptGeneratorService = scriptGeneratorService;
        _themeService = themeService;
        _benchmarkTimingService = benchmarkTimingService;
        _validationService = validationService;
        _csvExportService = csvExportService;
    }

    // ═══════════════════════════════════════════════════════════════
    // VERSION & BRANDING
    // ═══════════════════════════════════════════════════════════════

    public string VersionText => $"v{Program.AppVersion}";

    // ═══════════════════════════════════════════════════════════════
    // NAVIGATION
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty]
    private string _currentPanel = "Dashboard";

    [ObservableProperty]
    private string _pageTitle = "Dashboard";

    public Visibility IsDashboardVisible => string.Equals(CurrentPanel, "Dashboard", StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsDiagnosticsPanelVisible => string.Equals(CurrentPanel, "Diagnostics", StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsDatabasePanelVisible => string.Equals(CurrentPanel, "Database", StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsClientToolsPanelVisible => string.Equals(CurrentPanel, "ClientTools", StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsComputersPanelVisible => string.Equals(CurrentPanel, "Computers", StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsUpdatesPanelVisible => string.Equals(CurrentPanel, "Updates", StringComparison.Ordinal) ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsOperationPanelVisible => !string.Equals(CurrentPanel, "Dashboard", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "Diagnostics", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "Database", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "ClientTools"
, StringComparison.Ordinal) && !string.Equals(CurrentPanel, "Computers", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "Updates", StringComparison.Ordinal) ? Visibility.Visible
            : Visibility.Collapsed;

    [RelayCommand]
    private async Task Navigate(string panel)
    {
        // Settings opens a modal dialog, not a panel
        if (string.Equals(panel, "Settings", StringComparison.Ordinal))
        {
            _ = OpenSettings();
            return;
        }

        CurrentPanel = panel;
        PageTitle = panel switch
        {
            "Dashboard" => "Dashboard",
            "Install" => "Install WSUS",
            "Transfer" => "Export / Import",
            "Sync" => "Online Sync",
            "Schedule" => "Schedule Task",
            "Diagnostics" => "Diagnostics",
            "Database" => "Database Operations",
            "Cleanup" => "Deep Cleanup",
            "Restore" => "Restore Database",
            "Settings" => "Settings",
            "Help" => "Help",
            "About" => "About",
            "GPO" => "Create GPO",
            "ClientTools" => "Client Tools",
            "Computers" => "Computers",
            "Updates" => "Updates",
            _ => panel
        };

        // Load data when navigating to data panels (only load once)
        if (string.Equals(panel, "Computers", StringComparison.Ordinal) &&
            FilteredComputers.Count == 0)
        {
            await LoadComputersAsync().ConfigureAwait(false);
        }
        else if (string.Equals(panel, "Updates", StringComparison.Ordinal) &&
                 FilteredUpdates.Count == 0)
        {
            await LoadUpdatesAsync().ConfigureAwait(false);
        }

        OnPropertyChanged(nameof(IsDashboardVisible));
        OnPropertyChanged(nameof(IsDiagnosticsPanelVisible));
        OnPropertyChanged(nameof(IsDatabasePanelVisible));
        OnPropertyChanged(nameof(IsClientToolsPanelVisible));
        OnPropertyChanged(nameof(IsComputersPanelVisible));
        OnPropertyChanged(nameof(IsUpdatesPanelVisible));
        OnPropertyChanged(nameof(IsOperationPanelVisible));
    }

    // ═══════════════════════════════════════════════════════════════
    // KEYBOARD SHORTCUT COMMANDS (Phase 26)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// F1 - Opens Help dialog (same as Help button in sidebar).
    /// </summary>
    [RelayCommand]
    private void ShowHelp()
    {
        Navigate("Help");
    }

    /// <summary>
    /// F5 - Refreshes dashboard data immediately. Wrapper for RefreshDashboard command.
    /// Note: The existing RefreshDashboard method is already a RelayCommand (line 1239).
    /// This method provides the keyboard shortcut entry point with status message feedback.
    /// </summary>
    [RelayCommand]
    private async Task RefreshDashboardFromShortcut()
    {
        await RefreshDashboard().ConfigureAwait(false);
        StatusMessage = "Dashboard refreshed";
    }

    /// <summary>
    /// Ctrl+S - Opens Settings dialog.
    /// </summary>
    [RelayCommand]
    private async Task OpenSettingsFromShortcut()
    {
        await OpenSettings().ConfigureAwait(false);
    }

    /// <summary>
    /// Ctrl+Q - Prompts to quit application.
    /// Shows confirmation if no operation is running, otherwise blocks with message.
    /// </summary>
    [RelayCommand]
    private void Quit()
    {
        if (IsOperationRunning)
        {
            MessageBox.Show(
                "Cannot quit while an operation is running.",
                "Cannot Quit",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var result = MessageBox.Show(
            "Are you sure you want to quit?",
            "Confirm Quit",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result == MessageBoxResult.Yes)
        {
            Application.Current.Shutdown();
        }
    }

    /// <summary>
    /// Escape - Cancels current operation or does nothing if no operation running.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanCancelOperation))]
    private void CancelOperationFromShortcut()
    {
        if (IsOperationRunning && _operationCts is { IsCancellationRequested: false })
        {
            _logService.Info("User cancelled operation via Escape key: {Operation}", CurrentOperationName);
            _operationCts.Cancel();
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // STATUS & OPERATIONS
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CancelOperationCommand))]
    private string _statusMessage = "Ready";

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CancelOperationCommand))]
    [NotifyPropertyChangedFor(nameof(CancelButtonVisibility))]
    [NotifyPropertyChangedFor(nameof(ProgressBarVisibility))]
    [NotifyPropertyChangedFor(nameof(IsProgressBarVisible))]
    private bool _isOperationRunning;

    [ObservableProperty]
    private string _logOutput = string.Empty;

    [ObservableProperty]
    private string _currentOperationName = string.Empty;

    /// <summary>
    /// Tracks the current step of a multi-step operation (e.g. "[Step 3/6]: Rebuilding indexes").
    /// Updated automatically when progress lines matching "[Step N/M]" are reported.
    /// Cleared when an operation starts and when it completes.
    /// </summary>
    [ObservableProperty]
    private string _operationStepText = string.Empty;

    /// <summary>
    /// Estimated time remaining for the current operation. Displays format like "Est. 2m 15s remaining"
    /// or "Working..." when no benchmark data is available. Empty when no operation is running.
    /// Updated at operation start and after each progress step.
    /// </summary>
    [ObservableProperty]
    private string _estimatedTimeRemaining = string.Empty;

    /// <summary>
    /// Text shown in the colored result banner after an operation completes.
    /// Set to "{operationName} completed successfully.", "{operationName} failed.", or "{operationName} cancelled."
    /// Cleared when the next operation starts.
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(StatusBannerVisibility))]
    private string _statusBannerText = string.Empty;

    /// <summary>
    /// Background color for the status banner. Green (#3FB950) for success,
    /// Red (#F85149) for failure, Orange (#D29922) for cancel.
    /// </summary>
    [ObservableProperty]
    private SolidColorBrush _statusBannerColor = new(Colors.Transparent);

    /// <summary>
    /// True while an operation is running — drives the ProgressBar visibility binding.
    /// Computed from IsOperationRunning for clear semantic naming in XAML.
    /// </summary>
    public bool IsProgressBarVisible => IsOperationRunning;

    /// <summary>Controls whether the indeterminate ProgressBar is shown (during operations).</summary>
    public Visibility ProgressBarVisibility =>
        IsOperationRunning ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Controls whether the status banner is shown (after operation completes).</summary>
    public Visibility StatusBannerVisibility =>
        string.IsNullOrEmpty(StatusBannerText) ? Visibility.Collapsed : Visibility.Visible;

    public Visibility CancelButtonVisibility =>
        IsOperationRunning ? Visibility.Visible : Visibility.Collapsed;

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
    /// this method. It manages IsOperationRunning flag, CancellationTokenSource lifecycle,
    /// progress reporting, error handling, and state cleanup.
    /// </summary>
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
        StatusMessage = $"Loading: {operationName}...";

        // Clear previous banner and step text when new operation starts
        StatusBannerText = string.Empty;
        OperationStepText = string.Empty;
        EstimatedTimeRemaining = string.Empty;

        // Look up estimated time from benchmark data
        TimeSpan estimatedDuration;
        if (_benchmarkTimingService.TryGetAverageDuration(operationName, out estimatedDuration))
        {
            EstimatedTimeRemaining = $"Est. {FormatTimeSpan(estimatedDuration)} remaining";
        }
        else
        {
            EstimatedTimeRemaining = "Working...";
        }

        // Notify all operation commands to re-evaluate CanExecute (disables buttons during operation)
        NotifyCommandCanExecuteChanged();

        // Auto-expand log panel when operation starts
        IsLogPanelExpanded = true;

        _logService.Info("Starting operation: {Operation}", operationName);
        AppendLog($"=== {operationName} ===");

        var progress = new Progress<string>(line =>
        {
            AppendLog(line);

            // Parse "[Step N/M]" prefix to update step text in the log header
            if (line.StartsWith("[Step ", StringComparison.OrdinalIgnoreCase))
            {
                OperationStepText = line;

                // Recalculate remaining time based on progress
                var match = System.Text.RegularExpressions.Regex.Match(line, @"\[Step (\d+)/(\d+)\]");
                if (match.Success && _benchmarkTimingService.TryGetAverageDuration(operationName, out var estimatedDuration))
                {
                    if (int.TryParse(match.Groups[1].Value, out int currentStep) &&
                        int.TryParse(match.Groups[2].Value, out int totalSteps) &&
                        totalSteps > 0)
                    {
                        var remainingFraction = 1.0 - ((double)currentStep / totalSteps);
                        var remaining = estimatedDuration * remainingFraction;
                        EstimatedTimeRemaining = $"Est. {FormatTimeSpan(remaining)} remaining";
                    }
                }
            }
        });

        try
        {
            var success = await operation(progress, _operationCts.Token).ConfigureAwait(false);

            if (success)
            {
                StatusMessage = $"{operationName} completed successfully.";
                StatusBannerText = $"✓ {operationName} completed successfully.";
                StatusBannerColor = GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50));
                AppendLog($"=== ✓ {operationName} completed ===");
                _logService.Info("Operation completed: {Operation}", operationName);
            }
            else
            {
                StatusMessage = $"{operationName} failed.";
                StatusBannerText = $"✗ {operationName} failed.";
                StatusBannerColor = GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));
                AppendLog($"=== ✗ {operationName} FAILED ===");
                _logService.Warning("Operation failed: {Operation}", operationName);
            }

            return success;
        }
        catch (OperationCanceledException)
        {
            StatusMessage = $"{operationName} cancelled.";
            StatusBannerText = $"⚠ {operationName} cancelled.";
            StatusBannerColor = GetThemeBrush("StatusWarning", Color.FromRgb(0xD2, 0x99, 0x22));
            AppendLog($"=== ⚠ {operationName} CANCELLED ===");
            _logService.Info("Operation cancelled: {Operation}", operationName);
            return false;
        }
        catch (Exception ex)
        {
            StatusMessage = $"{operationName} failed with error.";
            StatusBannerText = $"✗ {operationName} failed.";
            StatusBannerColor = GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));
            AppendLog($"[ERROR] {ex.Message}");
            AppendLog($"=== ✗ {operationName} FAILED ===");
            _logService.Error(ex, "Operation error: {Operation}", operationName);
            return false;
        }
        finally
        {
            IsOperationRunning = false;
            CurrentOperationName = string.Empty;
            OperationStepText = string.Empty;
            EstimatedTimeRemaining = string.Empty;
            _operationCts?.Dispose();
            _operationCts = null;

            // Ensure final batch is displayed
            FlushLogBatch();

            // Notify all operation commands to re-evaluate CanExecute (re-enables buttons after operation)
            NotifyCommandCanExecuteChanged();
        }
    }

    /// <summary>
    /// Appends a line to the log output panel using StringBuilder to prevent
    /// unbounded string growth. Uses batching to reduce PropertyChanged notifications.
    /// Lines are queued and flushed in batches of 50 or every 100ms.
    /// </summary>
    public void AppendLog(string line)
    {
        // Add to batch queue
        lock (_logBatchQueue)
        {
            _logBatchQueue.Enqueue(line);

            // If batch size reached, flush immediately
            if (_logBatchQueue.Count >= LogBatchSize)
            {
                FlushLogBatch();
            }
            else if (_logBatchTimer == null)
            {
                // Start timer on first queued item
                StartLogBatchTimer();
            }
        }
    }

    /// <summary>
    /// Starts the batch timer that flushes queued log lines at a fixed interval.
    /// </summary>
    private void StartLogBatchTimer()
    {
        _logBatchTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(LogBatchIntervalMs)
        };
        _logBatchTimer.Tick += (s, e) =>
        {
            FlushLogBatch();
            _logBatchTimer?.Stop();
        };
        _logBatchTimer.Start();
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => { }));
    }

    /// <summary>
    /// Flushes queued log lines to the StringBuilder and updates the UI.
    /// Trims to last 1000 lines when exceeding 100KB to prevent unbounded growth.
    /// </summary>
    private void FlushLogBatch()
    {
        string[] batch;
        lock (_logBatchQueue)
        {
            if (_logBatchQueue.Count == 0) return;
            batch = _logBatchQueue.ToArray();
            _logBatchQueue.Clear();
        }

        // Add all lines to StringBuilder
        foreach (var line in batch)
        {
            _logBuilder.AppendLine(line);
        }

        // Trim to last 1000 lines to prevent unbounded growth (~100KB limit)
        if (_logBuilder.Length > 100_000)
        {
            var fullText = _logBuilder.ToString();
            var lines = fullText.Split('\n');
            if (lines.Length > 1000)
            {
                _logBuilder.Clear();
                var start = lines.Length - 1000;
                for (int i = start; i < lines.Length; i++)
                {
                    _logBuilder.AppendLine(lines[i]);
                }
            }
        }

        // Single UI update for entire batch
        LogOutput = _logBuilder.ToString();
    }

    [RelayCommand]
    private void ClearLog()
    {
        _logBuilder.Clear();
        LogOutput = string.Empty;
    }

    // ═══════════════════════════════════════════════════════════════
    // LOG PANEL
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(LogPanelHeight))]
    [NotifyPropertyChangedFor(nameof(LogTextVisibility))]
    [NotifyPropertyChangedFor(nameof(LogToggleText))]
    private bool _isLogPanelExpanded = true;

    public double LogPanelHeight => IsLogPanelExpanded ? 250 : 0;

    public Visibility LogTextVisibility => IsLogPanelExpanded ? Visibility.Visible : Visibility.Collapsed;

    public string LogToggleText => IsLogPanelExpanded ? "Hide" : "Show";

    [RelayCommand]
    private async Task ToggleLogPanel()
    {
        IsLogPanelExpanded = !IsLogPanelExpanded;
        _settings.LogPanelExpanded = IsLogPanelExpanded;
        await SaveSettingsAsync().ConfigureAwait(false);
    }

    [RelayCommand]
    private void SaveLog()
    {
        try
        {
            var dialog = new SaveFileDialog
            {
                Filter = "Log Files (*.log)|*.log|Text Files (*.txt)|*.txt|All Files (*.*)|*.*",
                DefaultExt = ".log",
                FileName = $"WsusManager-{DateTime.Now:yyyy-MM-dd-HHmm}.log"
            };

            if (dialog.ShowDialog() == true)
            {
                File.WriteAllText(dialog.FileName, LogOutput);
                AppendLog($"Log saved to: {dialog.FileName}");
            }
        }
        catch (Exception ex)
        {
            AppendLog($"[ERROR] Failed to save log: {ex.Message}");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // DATA LISTS (Phase 25: Virtualization Infrastructure)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Filtered list of computers for Phase 29 Data Filtering panel.
    /// Uses ObservableCollection for efficient UI updates with virtualization.
    /// </summary>
    [ObservableProperty]
    private ObservableCollection<ComputerInfo> _filteredComputers = new();

    /// <summary>
    /// Filtered list of updates for Phase 29 Data Filtering panel.
    /// Uses ObservableCollection for efficient UI updates with virtualization.
    /// </summary>
    [ObservableProperty]
    private ObservableCollection<UpdateInfo> _filteredUpdates = new();

    /// <summary>
    /// Loads computers into filtered collection. Called by Phase 29 Data Filtering.
    /// </summary>
    public async Task LoadComputersAsync(CancellationToken ct = default)
    {
        try
        {
            _logService?.Debug("Loading computers...");

            var computers = await _dashboardService.GetComputersAsync(ct).ConfigureAwait(false);

            FilteredComputers.Clear();
            foreach (var computer in computers)
            {
                FilteredComputers.Add(computer);
            }

            // Apply any active filters after loading
            ApplyComputerFilters();

            // Refresh export button state (Phase 30)
            ExportComputersCommand.NotifyCanExecuteChanged();

            _logService?.Info("Loaded {0} computers", FilteredComputers.Count);
        }
        catch (OperationCanceledException)
        {
            _logService?.Warning("Computer loading cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logService?.Error(ex, "Failed to load computers: {Message}", ex.Message);
            FilteredComputers.Clear();
        }
        finally
        {
            OnPropertyChanged(nameof(ComputerVisibleCount));
            OnPropertyChanged(nameof(ComputerFilterCountText));
        }
    }

    /// <summary>
    /// Loads updates into filtered collection. Called by Phase 29 Data Filtering.
    /// </summary>
    public async Task LoadUpdatesAsync(CancellationToken ct = default)
    {
        try
        {
            _logService?.Debug("Loading updates...");

            var updates = await _dashboardService.GetUpdatesAsync(ct).ConfigureAwait(false);

            FilteredUpdates.Clear();
            foreach (var update in updates)
            {
                FilteredUpdates.Add(update);
            }

            // Apply any active filters after loading
            ApplyUpdateFilters();

            // Refresh export button state (Phase 30)
            ExportUpdatesCommand.NotifyCanExecuteChanged();

            _logService?.Info("Loaded {0} updates", FilteredUpdates.Count);
        }
        catch (OperationCanceledException)
        {
            _logService?.Warning("Update loading cancelled");
            throw;
        }
        catch (Exception ex)
        {
            _logService?.Error(ex, "Failed to load updates: {Message}", ex.Message);
            FilteredUpdates.Clear();
        }
        finally
        {
            OnPropertyChanged(nameof(UpdateVisibleCount));
            OnPropertyChanged(nameof(UpdateFilterCountText));
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // DATA FILTERING - Computers Panel (Phase 29)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>Selected status filter for Computers panel.</summary>
    [ObservableProperty]
    private string _computerStatusFilter = "All";

    /// <summary>Search text for Computers panel (debounced).</summary>
    [ObservableProperty]
    private string _computerSearchText = string.Empty;

    /// <summary>Debounce timer for search input (300ms).</summary>
    private DispatcherTimer? _computerSearchDebounceTimer;

    /// <summary>Whether to show the Clear Filters button (any filter active).</summary>
    public bool ShowClearComputerFilters =>
        !string.Equals(ComputerStatusFilter, "All", StringComparison.Ordinal) ||
        !string.IsNullOrWhiteSpace(ComputerSearchText);

    /// <summary>Number of visible items after filtering.</summary>
    public int ComputerVisibleCount => FilteredComputers.Count;

    /// <summary>Text showing filter count (e.g., "15 of 200 computers visible").</summary>
    public string ComputerFilterCountText =>
        $"{FilteredComputers.Count} computers";

    // ═══════════════════════════════════════════════════════════════
    // DATA FILTERING - Updates Panel (Phase 29)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>Selected approval filter for Updates panel.</summary>
    [ObservableProperty]
    private string _updateApprovalFilter = "All";

    /// <summary>Selected classification filter for Updates panel.</summary>
    [ObservableProperty]
    private string _updateClassificationFilter = "All";

    /// <summary>Search text for Updates panel (debounced).</summary>
    [ObservableProperty]
    private string _updateSearchText = string.Empty;

    /// <summary>Debounce timer for update search input (300ms).</summary>
    private DispatcherTimer? _updateSearchDebounceTimer;

    /// <summary>Whether to show the Clear Filters button (any filter active).</summary>
    public bool ShowClearUpdateFilters =>
        !string.Equals(UpdateApprovalFilter, "All", StringComparison.Ordinal) ||
        !string.Equals(UpdateClassificationFilter, "All", StringComparison.Ordinal) ||
        !string.IsNullOrWhiteSpace(UpdateSearchText);

    /// <summary>Number of visible items after filtering.</summary>
    public int UpdateVisibleCount => FilteredUpdates.Count;

    /// <summary>Text showing filter count (e.g., "45 of 300 updates visible").</summary>
    public string UpdateFilterCountText =>
        $"{FilteredUpdates.Count} updates";

    // ═══════════════════════════════════════════════════════════════
    // DASHBOARD - Service Status Cards
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty] private string _servicesValue = "...";
    [ObservableProperty] private string _servicesSubtext = "Checking...";
    [ObservableProperty] private SolidColorBrush _servicesBarColor = new(Color.FromRgb(0x8B, 0x94, 0x9E));

    [ObservableProperty] private string _databaseValue = "...";
    [ObservableProperty] private string _databaseSubtext = "Checking...";
    [ObservableProperty] private SolidColorBrush _databaseBarColor = new(Color.FromRgb(0x8B, 0x94, 0x9E));

    [ObservableProperty] private string _diskValue = "...";
    [ObservableProperty] private string _diskSubtext = "Checking...";
    [ObservableProperty] private SolidColorBrush _diskBarColor = new(Color.FromRgb(0x8B, 0x94, 0x9E));

    [ObservableProperty] private string _taskValue = "...";
    [ObservableProperty] private string _taskSubtext = "";
    [ObservableProperty] private SolidColorBrush _taskBarColor = new(Color.FromRgb(0x8B, 0x94, 0x9E));

    // ═══════════════════════════════════════════════════════════════
    // DASHBOARD - Configuration Display
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty] private string _configContentPath = @"C:\WSUS";
    [ObservableProperty] private string _configSqlInstance = @"localhost\SQLEXPRESS";
    [ObservableProperty] private string _configLogPath = @"C:\WSUS\Logs";

    // ═══════════════════════════════════════════════════════════════
    // SERVER MODE & CONNECTIVITY
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// When true, dashboard auto-refresh does not update IsOnline from DashboardService.
    /// Activated when admin manually toggles the mode via ToggleModeCommand.
    /// </summary>
    private bool _modeOverrideActive;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ConnectionDotColor))]
    [NotifyPropertyChangedFor(nameof(ConnectionStatusText))]
    [NotifyPropertyChangedFor(nameof(ServerModeText))]
    [NotifyPropertyChangedFor(nameof(ToggleModeText))]
    [NotifyPropertyChangedFor(nameof(ModeOverrideIndicator))]
    private bool _isOnline = true;

    public SolidColorBrush ConnectionDotColor => IsOnline
        ? GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50))
        : GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));

    public string ConnectionStatusText => IsOnline ? "Online" : "Offline";

    public string ServerModeText => IsOnline ? "Online" : "Air-Gap";

    /// <summary>Dynamic button label for the mode toggle button.</summary>
    public string ToggleModeText => IsOnline ? "Switch to Air-Gap" : "Switch to Online";

    /// <summary>Indicator shown near toggle to signal whether mode is manually overridden.</summary>
    public string ModeOverrideIndicator => _modeOverrideActive ? "(manual)" : "(auto)";

    [RelayCommand]
    private async Task ToggleMode()
    {
        // Flip mode and activate manual override
        IsOnline = !IsOnline;
        _modeOverrideActive = true;

        // Persist the new mode to settings
        _settings.ServerMode = IsOnline ? "Online" : "AirGap";
        await SaveSettingsAsync().ConfigureAwait(false);

        // Notify CanExecute for online-dependent operations
        NotifyCommandCanExecuteChanged();

        var modeLabel = IsOnline ? "Online" : "Air-Gap";
        AppendLog($"Server mode manually set to {modeLabel}. Auto-detection bypassed until changed.");
    }

    // ═══════════════════════════════════════════════════════════════
    // WSUS INSTALLATION DETECTION
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty]
    private bool _isWsusInstalled;

    // ═══════════════════════════════════════════════════════════════
    // DIAGNOSTICS COMMANDS (Phase 3)
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RunDiagnostics()
    {
        Navigate("Diagnostics");

        await RunOperationAsync("Diagnostics", async (progress, ct) =>
        {
            var report = await _healthService.RunDiagnosticsAsync(
                _settings.ContentPath,
                _settings.SqlInstance,
                progress,
                ct).ConfigureAwait(false);

            // Trigger dashboard refresh to reflect any service state changes
            await RefreshDashboard().ConfigureAwait(false);

            return report.IsHealthy || report.FailedCount == 0;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task ResetContent()
    {
        // Confirm before running destructive operation
        if (!ConfirmDestructiveOperation("Content Reset"))
            return;

        Navigate("Diagnostics");

        await RunOperationAsync("Content Reset", async (progress, ct) =>
        {
            var result = await _contentResetService.ResetContentAsync(progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task StartService(string serviceName)
    {
        await RunOperationAsync($"Start {serviceName}", async (progress, ct) =>
        {
            progress.Report($"Starting {serviceName}...");
            var result = await _serviceManager.StartServiceAsync(serviceName, ct).ConfigureAwait(false);
            progress.Report(result.Success ? $"[OK] {result.Message}" : $"[FAIL] {result.Message}");

            // Refresh dashboard to reflect service state change
            await RefreshDashboard().ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task StopService(string serviceName)
    {
        await RunOperationAsync($"Stop {serviceName}", async (progress, ct) =>
        {
            progress.Report($"Stopping {serviceName}...");
            var result = await _serviceManager.StopServiceAsync(serviceName, ct).ConfigureAwait(false);
            progress.Report(result.Success ? $"[OK] {result.Message}" : $"[FAIL] {result.Message}");

            // Refresh dashboard to reflect service state change
            await RefreshDashboard().ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    // ═══════════════════════════════════════════════════════════════
    // DATABASE OPERATIONS COMMANDS (Phase 4)
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RunDeepCleanup()
    {
        // Confirm before running destructive operation
        if (!ConfirmDestructiveOperation("Deep Cleanup"))
            return;

        Navigate("Database");

        await RunOperationAsync("Deep Cleanup", async (progress, ct) =>
        {
            var result = await _deepCleanupService.RunAsync(
                _settings.SqlInstance,
                progress,
                ct).ConfigureAwait(false);

            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task BackupDatabase()
    {
        // Open SaveFileDialog before navigating (per CLAUDE.md pattern: dialog before panel switch)
        var dialog = new SaveFileDialog
        {
            Title = "Select Backup Destination",
            Filter = "SQL Backup Files (*.bak)|*.bak|All Files (*.*)|*.*",
            DefaultExt = ".bak",
            FileName = $"SUSDB_{DateTime.Now:yyyy-MM-dd}.bak",
            InitialDirectory = @"C:\WSUS"
        };

        if (dialog.ShowDialog() != true) return;

        var backupPath = dialog.FileName;
        Navigate("Database");

        await RunOperationAsync("Backup Database", async (progress, ct) =>
        {
            var result = await _backupService.BackupAsync(
                _settings.SqlInstance,
                backupPath,
                progress,
                ct).ConfigureAwait(false);

            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RestoreDatabase()
    {
        // Confirmation dialog first
        var confirm = MessageBox.Show(
            "Restoring the database will:\n\n" +
            "  1. Verify backup file integrity\n" +
            "  2. Stop WSUS and IIS services\n" +
            "  3. Replace the current SUSDB with the backup\n" +
            "  4. Run wsusutil postinstall\n" +
            "  5. Restart WSUS and IIS services\n\n" +
            "WARNING: This will replace ALL current WSUS data!\n\n" +
            "Continue?",
            "Confirm Database Restore",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes) return;

        // Open file picker
        var dialog = new OpenFileDialog
        {
            Title = "Select Backup File to Restore",
            Filter = "SQL Backup Files (*.bak)|*.bak|All Files (*.*)|*.*",
            DefaultExt = ".bak",
            InitialDirectory = @"C:\WSUS"
        };

        if (dialog.ShowDialog() != true) return;

        var backupPath = dialog.FileName;

        // Confirm before running destructive operation
        if (!ConfirmDestructiveOperation("Restore Database"))
            return;

        Navigate("Database");

        await RunOperationAsync("Restore Database", async (progress, ct) =>
        {
            var result = await _backupService.RestoreAsync(
                _settings.SqlInstance,
                backupPath,
                _settings.ContentPath,
                progress,
                ct).ConfigureAwait(false);

            // Refresh dashboard after restore to reflect new DB state
            if (result.Success)
                await RefreshDashboard().ConfigureAwait(false);

            return result.Success;
        }).ConfigureAwait(false);
    }

    // ═══════════════════════════════════════════════════════════════
    // QUICK ACTION COMMANDS
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task QuickDiagnostics()
    {
        await RunDiagnostics().ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task QuickCleanup()
    {
        await RunDeepCleanup().ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOnlineOperation))]
    private async Task QuickSync()
    {
        await RunOnlineSync().ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task QuickStartServices()
    {
        await RunOperationAsync("Start All Services", async (progress, ct) =>
        {
            var result = await _serviceManager.StartAllServicesAsync(progress, ct).ConfigureAwait(false);

            // Refresh dashboard to reflect service state changes
            await RefreshDashboard().ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    private bool CanExecuteWsusOperation() => IsWsusInstalled && !IsOperationRunning;

    private bool CanExecuteOnlineOperation() => IsWsusInstalled && !IsOperationRunning && IsOnline;

    private bool CanExecuteInstall() => !IsOperationRunning;

    // ═══════════════════════════════════════════════════════════════
    // WSUS OPERATIONS COMMANDS (Phase 5)
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand(CanExecute = nameof(CanExecuteOnlineOperation))]
    private async Task RunOnlineSync()
    {
        // Dialog before panel switch (per CLAUDE.md pattern)
        var dialog = new SyncProfileDialog();
        if (Application.Current.MainWindow is not null)
            dialog.Owner = Application.Current.MainWindow;

        if (dialog.ShowDialog() != true) return;

        var profile = dialog.SelectedProfile;
        Navigate("Sync");

        await RunOperationAsync("Online Sync", async (progress, ct) =>
        {
            var result = await _syncService.RunSyncAsync(
                profile, MaxAutoApproveCount, progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RunTransfer()
    {
        // Dialog before panel switch (per CLAUDE.md pattern)
        var dialog = new TransferDialog();
        if (Application.Current.MainWindow is not null)
            dialog.Owner = Application.Current.MainWindow;

        if (dialog.ShowDialog() != true) return;

        Navigate("Transfer");

        if (dialog.IsExportMode && dialog.ExportResult is not null)
        {
            await RunOperationAsync("Export", async (progress, ct) =>
            {
                var result = await _exportService.ExportAsync(
                    dialog.ExportResult, progress, ct).ConfigureAwait(false);
                return result.Success;
            }).ConfigureAwait(false);
        }
        else if (!dialog.IsExportMode && dialog.ImportResult is not null)
        {
            await RunOperationAsync("Import", async (progress, ct) =>
            {
                var result = await _importService.ImportAsync(
                    dialog.ImportResult, progress, ct).ConfigureAwait(false);
                return result.Success;
            }).ConfigureAwait(false);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // INSTALLATION & SCHEDULING COMMANDS (Phase 6)
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand(CanExecute = nameof(CanExecuteInstall))]
    private async Task RunInstallWsus()
    {
        // Dialog before panel switch (per CLAUDE.md pattern)
        var dialog = new InstallDialog();
        if (Application.Current.MainWindow is not null)
            dialog.Owner = Application.Current.MainWindow;

        if (dialog.ShowDialog() != true || dialog.Options is null) return;

        var options = dialog.Options;
        Navigate("Install");

        await RunOperationAsync("Install WSUS", async (progress, ct) =>
        {
            // Pre-flight validation
            progress.Report("Validating prerequisites...");
            var validation = await _installationService.ValidatePrerequisitesAsync(options, ct).ConfigureAwait(false);
            if (!validation.Success)
            {
                progress.Report($"[FAIL] {validation.Message}");
                return false;
            }
            progress.Report("[OK] All prerequisites met.");
            progress.Report("");

            // Run installation
            var result = await _installationService.InstallAsync(options, progress, ct).ConfigureAwait(false);

            // Refresh dashboard after install to detect WSUS role
            if (result.Success)
                await RefreshDashboard().ConfigureAwait(false);

            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RunScheduleTask()
    {
        // Dialog before panel switch (per CLAUDE.md pattern)
        var dialog = new ScheduleTaskDialog();
        if (Application.Current.MainWindow is not null)
            dialog.Owner = Application.Current.MainWindow;

        if (dialog.ShowDialog() != true || dialog.Options is null) return;

        var options = dialog.Options;
        Navigate("Schedule");

        await RunOperationAsync("Schedule Task", async (progress, ct) =>
        {
            var result = await _scheduledTaskService.CreateTaskAsync(options, progress, ct).ConfigureAwait(false);

            // Refresh dashboard to update Task card status
            if (result.Success)
                await RefreshDashboard().ConfigureAwait(false);

            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RunCreateGpo()
    {
        Navigate("Install");

        await RunOperationAsync("Create GPO", async (progress, ct) =>
        {
            var result = await _gpoDeploymentService.DeployGpoFilesAsync(progress, ct).ConfigureAwait(false);

            if (result.Success && result.Data is not null)
            {
                // Show instructions dialog on UI thread after operation completes
                Application.Current.Dispatcher.Invoke(() =>
                {
                    var instrDialog = new GpoInstructionsDialog(result.Data);
                    if (Application.Current.MainWindow is not null)
                        instrDialog.Owner = Application.Current.MainWindow;
                    instrDialog.ShowDialog();
                });
            }

            return result.Success;
        }).ConfigureAwait(false);
    }

    // ═══════════════════════════════════════════════════════════════
    // CLIENT MANAGEMENT (Phase 14)
    // ═══════════════════════════════════════════════════════════════

    [ObservableProperty]
    private string _clientHostname = string.Empty;

    [ObservableProperty]
    private string _errorCodeInput = string.Empty;

    [ObservableProperty]
    private string _errorCodeResult = string.Empty;

    /// <summary>
    /// Hostnames for mass GPUpdate. Can be comma, semicolon, or newline separated.
    /// Bound to the multi-line TextBox in the Mass Operations card.
    /// </summary>
    [ObservableProperty]
    private string _massHostnames = string.Empty;

    /// <summary>
    /// CanExecute helper for remote client operations — requires a hostname and no operation running.
    /// </summary>
    private bool CanExecuteClientOperation() =>
        !IsOperationRunning && !string.IsNullOrWhiteSpace(ClientHostname);

    /// <summary>
    /// CanExecute helper for mass operations — requires hostnames entered and no operation running.
    /// </summary>
    private bool CanExecuteMassOperation() =>
        !IsOperationRunning && !string.IsNullOrWhiteSpace(MassHostnames);

    /// <summary>
    /// Called automatically by CommunityToolkit.Mvvm when ClientHostname changes.
    /// Re-evaluates CanExecute for all client operation commands.
    /// </summary>
    partial void OnClientHostnameChanged(string value)
    {
        RunClientCancelStuckJobsCommand.NotifyCanExecuteChanged();
        RunClientForceCheckInCommand.NotifyCanExecuteChanged();
        RunClientTestConnectivityCommand.NotifyCanExecuteChanged();
        RunClientDiagnosticsCommand.NotifyCanExecuteChanged();
    }

    /// <summary>
    /// Called automatically by CommunityToolkit.Mvvm when MassHostnames changes.
    /// Re-evaluates CanExecute for RunMassGpUpdateCommand.
    /// </summary>
    partial void OnMassHostnamesChanged(string value)
    {
        RunMassGpUpdateCommand.NotifyCanExecuteChanged();
    }

    [RelayCommand(CanExecute = nameof(CanExecuteClientOperation))]
    private async Task RunClientCancelStuckJobs()
    {
        Navigate("ClientTools");

        await RunOperationAsync("Cancel Stuck Jobs", async (progress, ct) =>
        {
            var result = await _clientService.CancelStuckJobsAsync(
                ClientHostname.Trim(), progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteClientOperation))]
    private async Task RunClientForceCheckIn()
    {
        Navigate("ClientTools");

        await RunOperationAsync("Force Check-In", async (progress, ct) =>
        {
            var result = await _clientService.ForceCheckInAsync(
                ClientHostname.Trim(), progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteClientOperation))]
    private async Task RunClientTestConnectivity()
    {
        Navigate("ClientTools");

        await RunOperationAsync("Test Connectivity", async (progress, ct) =>
        {
            var wsusUrl = $"http://{_settings.SqlInstance.Split('\\')[0]}:8530";
            var result = await _clientService.TestConnectivityAsync(
                ClientHostname.Trim(), wsusUrl, progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    [RelayCommand(CanExecute = nameof(CanExecuteClientOperation))]
    private async Task RunClientDiagnostics()
    {
        Navigate("ClientTools");

        await RunOperationAsync("Client Diagnostics", async (progress, ct) =>
        {
            var result = await _clientService.RunDiagnosticsAsync(
                ClientHostname.Trim(), progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    /// <summary>
    /// Opens a file picker and loads hostnames from a text file (one per line) into
    /// the MassHostnames property. Always available — no CanExecute restriction.
    /// </summary>
    [RelayCommand]
    private void LoadHostFile()
    {
        try
        {
            var dialog = new OpenFileDialog
            {
                Title = "Load Hostnames from File",
                Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*",
                DefaultExt = ".txt"
            };

            if (dialog.ShowDialog() != true) return;

            var lines = File.ReadAllLines(dialog.FileName);
            MassHostnames = string.Join(Environment.NewLine, lines);

            var count = lines.Count(l => !string.IsNullOrWhiteSpace(l));
            var filename = System.IO.Path.GetFileName(dialog.FileName);
            AppendLog($"Loaded {count} hostname(s) from {filename}");
        }
        catch (Exception ex)
        {
            AppendLog($"[ERROR] Failed to load host file: {ex.Message}");
        }
    }

    /// <summary>
    /// Parses MassHostnames and runs ForceCheckIn on each host sequentially
    /// via MassForceCheckInAsync.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanExecuteMassOperation))]
    private async Task RunMassGpUpdate()
    {
        // Parse hostnames: split on commas, semicolons, and newlines
        var hostnames = MassHostnames
            .Split([',', ';', '\n', '\r'], StringSplitOptions.RemoveEmptyEntries)
            .Select(h => h.Trim())
            .Where(h => !string.IsNullOrWhiteSpace(h))
            .ToList();

        Navigate("ClientTools");

        await RunOperationAsync("Mass GPUpdate", async (progress, ct) =>
        {
            var result = await _clientService.MassForceCheckInAsync(hostnames, progress, ct).ConfigureAwait(false);
            return result.Success;
        }).ConfigureAwait(false);
    }

    // ═══════════════════════════════════════════════════════════════
    // SCRIPT GENERATOR (Phase 15)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Currently selected operation in the Script Generator dropdown.
    /// Bound to the ComboBox SelectedItem in the Script Generator card.
    /// </summary>
    [ObservableProperty]
    private string _selectedScriptOperation = string.Empty;

    /// <summary>
    /// List of available script operation display names for the ComboBox.
    /// Provided by IScriptGeneratorService.GetAvailableOperations().
    /// </summary>
    public IReadOnlyList<string> ScriptOperations => _scriptGeneratorService.GetAvailableOperations();

    /// <summary>
    /// Generates a self-contained PowerShell script for the selected operation
    /// and opens a SaveFileDialog so the admin can save it to disk.
    /// Script generation is synchronous and instant — does not go through RunOperationAsync.
    /// </summary>
    [RelayCommand]
    private void GenerateScript()
    {
        if (string.IsNullOrWhiteSpace(SelectedScriptOperation))
        {
            AppendLog("Select an operation type first.");
            return;
        }

        try
        {
            // Gather context parameters for operations that need them
            var wsusUrl = $"http://{_settings.SqlInstance.Split('\\')[0]}:8530";

            // For MassGpUpdate, pass the current MassHostnames list if populated
            IReadOnlyList<string>? hostnames = null;
            if (string.Equals(SelectedScriptOperation, "Mass GPUpdate", StringComparison.Ordinal) && !string.IsNullOrWhiteSpace(MassHostnames))
            {
                hostnames = MassHostnames
                    .Split([',', ';', '\n', '\r'], StringSplitOptions.RemoveEmptyEntries)
                    .Select(h => h.Trim())
                    .Where(h => !string.IsNullOrWhiteSpace(h))
                    .ToList();
            }

            var scriptContent = _scriptGeneratorService.GenerateScript(
                SelectedScriptOperation,
                wsusServerUrl: wsusUrl,
                hostnames: hostnames);

            // Default filename: WsusManager-{operation-slug}-{date}.ps1
            var slug = SelectedScriptOperation.Replace(" ", "-", StringComparison.Ordinal).Replace("/", "-", StringComparison.Ordinal);
            var defaultName = $"WsusManager-{slug}-{DateTime.Now:yyyy-MM-dd}.ps1";

            var dialog = new SaveFileDialog
            {
                Title = "Save PowerShell Script",
                Filter = "PowerShell Scripts (*.ps1)|*.ps1|All Files (*.*)|*.*",
                DefaultExt = ".ps1",
                FileName = defaultName
            };

            if (dialog.ShowDialog() == true)
            {
                File.WriteAllText(dialog.FileName, scriptContent, System.Text.Encoding.UTF8);
                AppendLog($"Script saved to: {dialog.FileName}");
                _logService.Info("Script saved: {Operation} → {Path}", SelectedScriptOperation, dialog.FileName);
            }
        }
        catch (Exception ex)
        {
            AppendLog($"[ERROR] Failed to generate script: {ex.Message}");
            _logService.Error(ex, "GenerateScript failed for operation: {Operation}", SelectedScriptOperation);
        }
    }

    /// <summary>
    /// Looks up a WSUS/Windows Update error code locally. Instant — no remote call.
    /// Does not go through RunOperationAsync because it is synchronous and near-instant.
    /// </summary>
    [RelayCommand]
    private void LookupErrorCode()
    {
        var input = ErrorCodeInput.Trim();
        if (string.IsNullOrWhiteSpace(input))
        {
            ErrorCodeResult = "Enter an error code to look up.";
            return;
        }

        var result = _clientService.LookupErrorCode(input);

        ErrorCodeResult = result.Success && result.Data is not null
            ? $"Code: {result.Data.Code}\nDescription: {result.Data.Description}\n\nRecommended Fix:\n{result.Data.RecommendedFix}"
            : "Error code not recognized. Check the Microsoft documentation or Windows Event Log for details.";
    }

    // ═══════════════════════════════════════════════════════════════
    // DASHBOARD REFRESH
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand]
    private async Task RefreshDashboard()
    {
        try
        {
            var data = await _dashboardService.CollectAsync(_settings, CancellationToken.None).ConfigureAwait(false);
            UpdateDashboardCards(data);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Dashboard refresh failed");
        }
    }

    /// <summary>
    /// Updates dashboard from pre-collected data. Used during initialization
    /// to avoid redundant data fetching when data is already available.
    /// </summary>
    private void UpdateDashboardFromData(DashboardData data)
    {
        UpdateDashboardCards(data);
    }

    /// <summary>
    /// Updates all dashboard card properties from collected data.
    /// Includes threshold-based color logic for each card.
    /// </summary>
    internal void UpdateDashboardCards(DashboardData data)
    {
        // WSUS Installation
        IsWsusInstalled = data.IsWsusInstalled;
        NotifyCommandCanExecuteChanged();

        // Server mode — only update from auto-detection when no manual override is active
        if (!_modeOverrideActive)
        {
            IsOnline = data.IsOnline;
        }
        // When override is active, IsOnline stays at the manually chosen value

        if (!data.IsWsusInstalled)
        {
            ServicesValue = "N/A";
            ServicesSubtext = "Not Installed";
            ServicesBarColor = GetThemeBrush("TextSecondary", Color.FromRgb(0x8B, 0x94, 0x9E));

            DatabaseValue = "N/A";
            DatabaseSubtext = "Not Installed";
            DatabaseBarColor = GetThemeBrush("TextSecondary", Color.FromRgb(0x8B, 0x94, 0x9E));

            DiskValue = "N/A";
            DiskSubtext = "Not Installed";
            DiskBarColor = GetThemeBrush("TextSecondary", Color.FromRgb(0x8B, 0x94, 0x9E));

            TaskValue = "N/A";
            TaskSubtext = "Not Installed";
            TaskBarColor = GetThemeBrush("TextSecondary", Color.FromRgb(0x8B, 0x94, 0x9E));
            return;
        }

        // Services Card
        ServicesValue = $"{data.ServiceRunningCount} / {data.ServiceNames.Length}";
        ServicesSubtext = string.Join(", ", data.ServiceNames);
        ServicesBarColor = data.ServiceRunningCount == data.ServiceNames.Length
            ? GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50))
            : data.ServiceRunningCount > 0
                ? GetThemeBrush("StatusWarning", Color.FromRgb(0xD2, 0x99, 0x22))
                : GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));

        // Database Card
        if (data.DatabaseSizeGB < 0)
        {
            DatabaseValue = "Offline";
            DatabaseSubtext = "SQL Server not running";
            DatabaseBarColor = GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));
        }
        else
        {
            DatabaseValue = $"{data.DatabaseSizeGB:F1} / 10 GB";
            DatabaseSubtext = data.DatabaseSizeGB >= 9
                ? "CRITICAL - Near 10 GB limit!"
                : data.DatabaseSizeGB >= 7
                    ? "Warning - Approaching limit"
                    : "Healthy";
            DatabaseBarColor = data.DatabaseSizeGB >= 9
                ? GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49))
                : data.DatabaseSizeGB >= 7
                    ? GetThemeBrush("StatusWarning", Color.FromRgb(0xD2, 0x99, 0x22))
                    : GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50));
        }

        // Disk Card
        DiskValue = $"{data.DiskFreeGB:F1} GB";
        DiskSubtext = data.DiskFreeGB < 10
            ? "Low disk space!"
            : $"Free on {(string.IsNullOrEmpty(_settings.ContentPath) ? "C:" : _settings.ContentPath[..2])} drive";
        DiskBarColor = data.DiskFreeGB < 10
            ? GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49))
            : data.DiskFreeGB < 50
                ? GetThemeBrush("StatusWarning", Color.FromRgb(0xD2, 0x99, 0x22))
                : GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50));

        // Task Card
        TaskValue = data.TaskStatus;
        TaskSubtext = string.Equals(data.TaskStatus, "Ready", StringComparison.Ordinal) ? "Scheduled" : "";
        TaskBarColor = string.Equals(data.TaskStatus, "Ready"
, StringComparison.Ordinal) ? GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50))
            : string.Equals(data.TaskStatus, "Not Found"
, StringComparison.Ordinal) ? GetThemeBrush("TextSecondary", Color.FromRgb(0x8B, 0x94, 0x9E))
                : GetThemeBrush("StatusWarning", Color.FromRgb(0xD2, 0x99, 0x22));
    }

    /// <summary>
    /// Notifies all commands that their CanExecute state may have changed.
    /// Called after dashboard refresh updates IsWsusInstalled or IsOperationRunning.
    /// </summary>
    private void NotifyCommandCanExecuteChanged()
    {
        QuickDiagnosticsCommand.NotifyCanExecuteChanged();
        QuickCleanupCommand.NotifyCanExecuteChanged();
        QuickSyncCommand.NotifyCanExecuteChanged();
        QuickStartServicesCommand.NotifyCanExecuteChanged();
        RunDiagnosticsCommand.NotifyCanExecuteChanged();
        ResetContentCommand.NotifyCanExecuteChanged();
        StartServiceCommand.NotifyCanExecuteChanged();
        StopServiceCommand.NotifyCanExecuteChanged();
        // Phase 4: Database Operations
        RunDeepCleanupCommand.NotifyCanExecuteChanged();
        BackupDatabaseCommand.NotifyCanExecuteChanged();
        RestoreDatabaseCommand.NotifyCanExecuteChanged();
        // Phase 5: WSUS Operations
        RunOnlineSyncCommand.NotifyCanExecuteChanged();
        RunTransferCommand.NotifyCanExecuteChanged();
        // Phase 6: Installation and Scheduling
        RunInstallWsusCommand.NotifyCanExecuteChanged();
        RunScheduleTaskCommand.NotifyCanExecuteChanged();
        RunCreateGpoCommand.NotifyCanExecuteChanged();
        // Phase 12: Mode Override + Settings
        ToggleModeCommand.NotifyCanExecuteChanged();
        OpenSettingsCommand.NotifyCanExecuteChanged();
        // Phase 14: Client Management
        RunClientCancelStuckJobsCommand.NotifyCanExecuteChanged();
        RunClientForceCheckInCommand.NotifyCanExecuteChanged();
        RunClientTestConnectivityCommand.NotifyCanExecuteChanged();
        RunClientDiagnosticsCommand.NotifyCanExecuteChanged();
        // Phase 15: Mass Operations + Script Generator
        RunMassGpUpdateCommand.NotifyCanExecuteChanged();
        GenerateScriptCommand.NotifyCanExecuteChanged();
    }

    // ═══════════════════════════════════════════════════════════════
    // INITIALIZATION & SETTINGS
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Called from MainWindow.Loaded. Loads settings, applies state,
    /// triggers the first dashboard refresh, and starts the auto-refresh timer.
    /// Uses parallel initialization for faster startup.
    /// </summary>
    public async Task InitializeAsync()
    {
        if (_isInitialized) return;
        _isInitialized = true;

        // Parallel initialization: load settings and fetch dashboard data concurrently
        var settingsTask = _settingsService.LoadAsync();
        var dashboardTask = _dashboardService.CollectAsync(_settingsService.Current, CancellationToken.None);

        // Await both operations in parallel
        await Task.WhenAll(settingsTask, dashboardTask).ConfigureAwait(false);

        // Apply settings and dashboard data from completed tasks
        _settings = settingsTask.Result;
        var dashboardData = dashboardTask.Result;

        ApplySettings(_settings);
        UpdateDashboardFromData(dashboardData);

        // Restore filter settings from saved state
        await InitializeFiltersAsync().ConfigureAwait(false);

        // Check WSUS installation and show message if needed
        if (!IsWsusInstalled)
        {
            AppendLog("WSUS is not installed on this server.");
            AppendLog("To get started, click 'Install WSUS' in the sidebar.");
            AppendLog("All other operations require WSUS to be installed first.");
            AppendLog("");
        }

        // Start auto-refresh timer
        StartRefreshTimer();

        _logService.Info("Application initialized, dashboard loaded");
    }

    /// <summary>
    /// Opens the Settings dialog. Always accessible — no CanExecute restriction.
    /// On OK, applies the new settings in-memory and persists to disk.
    /// If the refresh interval changed, restarts the auto-refresh timer.
    /// </summary>
    [RelayCommand]
    private async Task OpenSettings()
    {
        var dialog = new SettingsDialog(_settings, _themeService, _validationService);
        if (Application.Current.MainWindow is not null)
            dialog.Owner = Application.Current.MainWindow;

        if (dialog.ShowDialog() != true || dialog.Result is null) return;

        var updated = dialog.Result;

        // Preserve fields not shown in dialog
        updated.LogPanelExpanded = _settings.LogPanelExpanded;
        updated.LiveTerminalMode = _settings.LiveTerminalMode;

        // Check if refresh interval changed (need timer restart)
        var intervalChanged = updated.RefreshIntervalSeconds != _settings.RefreshIntervalSeconds ||
                             updated.DashboardRefreshInterval != _settings.DashboardRefreshInterval;

        // Check if theme changed (theme already applied by dialog for preview)
        var themeChanged = !string.Equals(updated.SelectedTheme, _settings.SelectedTheme, StringComparison.OrdinalIgnoreCase);

        // Apply in-memory
        _settings = updated;
        ApplySettings(_settings);

        // Restart timer if interval changed
        if (intervalChanged)
        {
            StopRefreshTimer();
            StartRefreshTimer();
        }

        // Persist to disk (includes theme selection)
        await SaveSettingsAsync().ConfigureAwait(false);

        // Refresh dashboard so new paths/mode take effect immediately
        await RefreshDashboard().ConfigureAwait(false);

        var themeLog = themeChanged ? $", Theme: {updated.SelectedTheme}" : "";
        AppendLog($"Settings saved. Server mode: {_settings.ServerMode}, Refresh: {_settings.RefreshIntervalSeconds}s{themeLog}");
    }

    /// <summary>
    /// Restores saved filter settings from AppSettings on application startup.
    /// Called during initialization to apply persisted filter values.
    /// </summary>
    private async Task InitializeFiltersAsync()
    {
        // Restore Computers filters
        ComputerStatusFilter = _settings.ComputerStatusFilter ?? "All";
        ComputerSearchText = _settings.ComputerSearchText ?? string.Empty;

        // Restore Updates filters
        UpdateApprovalFilter = _settings.UpdateApprovalFilter ?? "All";
        UpdateClassificationFilter = _settings.UpdateClassificationFilter ?? "All";
        UpdateSearchText = _settings.UpdateSearchText ?? string.Empty;

        await Task.CompletedTask.ConfigureAwait(false);
    }

    private void ApplySettings(AppSettings settings)
    {
        IsLogPanelExpanded = settings.LogPanelExpanded;
        IsOnline = string.Equals(settings.ServerMode, "Online", StringComparison.Ordinal);
        // Activate override on startup when saved mode is AirGap so auto-detection
        // doesn't flip it back to Online on the first ping check.
        _modeOverrideActive = string.Equals(settings.ServerMode, "AirGap", StringComparison.Ordinal);
        ConfigContentPath = settings.ContentPath;
        ConfigSqlInstance = settings.SqlInstance;
        ConfigLogPath = @"C:\WSUS\Logs";
    }

    /// <summary>
    /// Shows a confirmation dialog for destructive operations if the setting is enabled.
    /// Returns true if the user confirms or if prompts are disabled. Returns false if user cancels.
    /// </summary>
    /// <param name="operationName">The name of the destructive operation.</param>
    /// <returns>True to proceed with operation, false to cancel.</returns>
    private bool ConfirmDestructiveOperation(string operationName)
    {
        // If setting is disabled, auto-proceed
        if (!_settings.RequireConfirmationDestructive)
            return true;

        // Show confirmation dialog
        var result = MessageBox.Show(
            $"Are you sure you want to run {operationName}?\n\nThis action cannot be undone.",
            $"Confirm {operationName}",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning,
            MessageBoxResult.No);

        return result == MessageBoxResult.Yes;
    }

    private async Task SaveSettingsAsync()
    {
        try
        {
            await _settingsService.SaveAsync(_settings).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to save settings");
        }
    }

    private void StartRefreshTimer()
    {
        var intervalMs = GetRefreshIntervalMs();

        // If disabled, don't start timer
        if (intervalMs == 0)
        {
            _logService.Debug("Dashboard auto-refresh disabled");
            return;
        }

        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(intervalMs) };

        // Store handler reference for unsubscription (memory leak prevention)
        _refreshTimerHandler = async (_, _) =>
        {
            try
            {
                await RefreshDashboard().ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                _logService.Error(ex, "Dashboard refresh failed");
            }
        };

        _refreshTimer.Tick += _refreshTimerHandler;
        _refreshTimer.Start();

        _logService.Debug("Dashboard auto-refresh started ({Interval}s interval)", intervalMs / 1000.0);
    }

    /// <summary>
    /// Converts DashboardRefreshInterval enum to milliseconds.
    /// Returns 0 for Disabled (timer should not be started).
    /// </summary>
    private int GetRefreshIntervalMs()
    {
        return _settings.DashboardRefreshInterval switch
        {
            DashboardRefreshInterval.Sec10 => 10000,
            DashboardRefreshInterval.Sec30 => 30000,
            DashboardRefreshInterval.Sec60 => 60000,
            DashboardRefreshInterval.Disabled => 0,
            _ => 30000 // default to 30 seconds
        };
    }

    /// <summary>
    /// Stops the auto-refresh timer and removes event handler subscription.
    /// Called during cleanup/dispose and when refresh interval changes.
    /// </summary>
    public void StopRefreshTimer()
    {
        if (_refreshTimer != null)
        {
            _refreshTimer.Stop();
            // Important: Remove event handler to prevent memory leak
            if (_refreshTimerHandler != null)
            {
                _refreshTimer.Tick -= _refreshTimerHandler;
                _refreshTimerHandler = null;
            }
            _refreshTimer = null;
        }
    }

    /// <summary>
    /// Disposes of managed resources: stops refresh timer, cancels running operations,
    /// and clears the log builder. Called from MainWindow.Closed event.
    /// </summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        // Stop and cleanup log batch timer
        _logBatchTimer?.Stop();
        _logBatchTimer = null;

        // Stop and cleanup timer (includes handler unsubscription)
        StopRefreshTimer();

        // Cancel any running operation
        if (_operationCts is { IsCancellationRequested: false })
        {
            _operationCts.Cancel();
            _operationCts.Dispose();
        }

        // Clear log builder to release memory
        _logBuilder.Clear();

        GC.SuppressFinalize(this);
    }

    // ═══════════════════════════════════════════════════════════════
    // DATA FILTERING HANDLERS (Phase 29)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Called when ComputerStatusFilter changes. Applies filter and persists to settings.
    /// </summary>
    partial void OnComputerStatusFilterChanged(string value)
    {
        ApplyComputerFilters();
        SaveFilterSettings();
    }

    /// <summary>
    /// Called when ComputerSearchText changes. Debounces input before applying filter.
    /// </summary>
    partial void OnComputerSearchTextChanged(string value)
    {
        // Reset or start debounce timer
        _computerSearchDebounceTimer?.Stop();
        _computerSearchDebounceTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(300)
        };
        _computerSearchDebounceTimer.Tick += (s, e) =>
        {
            _computerSearchDebounceTimer?.Stop();
            ApplyComputerFilters();
            SaveFilterSettings();
        };
        _computerSearchDebounceTimer.Start();

        // Update status text to show "(filtering...)"
        if (!string.IsNullOrWhiteSpace(value))
        {
            _logService?.Debug("(filtering...)");
        }
    }

    /// <summary>
    /// Called when UpdateApprovalFilter changes. Applies filter and persists to settings.
    /// </summary>
    partial void OnUpdateApprovalFilterChanged(string value)
    {
        ApplyUpdateFilters();
        SaveUpdateFilterSettings();
    }

    /// <summary>
    /// Called when UpdateClassificationFilter changes. Applies filter and persists to settings.
    /// </summary>
    partial void OnUpdateClassificationFilterChanged(string value)
    {
        ApplyUpdateFilters();
        SaveUpdateFilterSettings();
    }

    /// <summary>
    /// Called when UpdateSearchText changes. Debounces input before applying filter.
    /// </summary>
    partial void OnUpdateSearchTextChanged(string value)
    {
        // Reset or start debounce timer
        _updateSearchDebounceTimer?.Stop();
        _updateSearchDebounceTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(300)
        };
        _updateSearchDebounceTimer.Tick += (s, e) =>
        {
            _updateSearchDebounceTimer?.Stop();
            ApplyUpdateFilters();
            SaveUpdateFilterSettings();
        };
        _updateSearchDebounceTimer.Start();

        // Update status text to show "(filtering...)"
        if (!string.IsNullOrWhiteSpace(value))
        {
            _logService?.Debug("(filtering...)");
        }
    }

    /// <summary>
    /// Applies computer status and search filters to the FilteredComputers collection.
    /// Uses CollectionView.Filter for efficient O(n) filtering.
    /// </summary>
    private void ApplyComputerFilters()
    {
        var view = System.Windows.Data.CollectionViewSource.GetDefaultView(FilteredComputers);
        view.Filter = (obj) =>
        {
            if (obj is not ComputerInfo computer) return false;

            // Status filter
            if (!string.Equals(ComputerStatusFilter, "All", StringComparison.Ordinal))
            {
                if (!string.Equals(computer.Status, ComputerStatusFilter, StringComparison.OrdinalIgnoreCase))
                    return false;
            }

            // Search filter (case-insensitive substring)
            if (!string.IsNullOrWhiteSpace(ComputerSearchText))
            {
                var search = ComputerSearchText.ToLowerInvariant();
                var match = computer.Hostname.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0 ||
                           computer.IpAddress.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0 ||
                           computer.Status.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0;
                if (!match) return false;
            }

            return true;
        };
        view.Refresh();

        // Notify UI updates
        OnPropertyChanged(nameof(ShowClearComputerFilters));
        OnPropertyChanged(nameof(ComputerVisibleCount));
        OnPropertyChanged(nameof(ComputerFilterCountText));

        // Refresh export button state (Phase 30)
        ExportComputersCommand.NotifyCanExecuteChanged();
    }

    /// <summary>
    /// Applies update approval, classification, and search filters to the FilteredUpdates collection.
    /// Uses CollectionView.Filter for efficient O(n) filtering.
    /// </summary>
    private void ApplyUpdateFilters()
    {
        var view = System.Windows.Data.CollectionViewSource.GetDefaultView(FilteredUpdates);
        view.Filter = (obj) =>
        {
            if (obj is not UpdateInfo update) return false;

            // Approval filter (combines IsApproved and IsDeclined)
            if (!string.Equals(UpdateApprovalFilter, "All", StringComparison.Ordinal))
            {
                bool matchesApproval = UpdateApprovalFilter switch
                {
                    "Approved" => update.IsApproved && !update.IsDeclined,
                    "Not Approved" => !update.IsApproved && !update.IsDeclined,
                    "Declined" => update.IsDeclined,
                    _ => true
                };
                if (!matchesApproval) return false;
            }

            // Classification filter
            if (!string.Equals(UpdateClassificationFilter, "All", StringComparison.Ordinal))
            {
                // Handle both classification string formats
                var classification = update.Classification?.ToLowerInvariant() ?? "";
                var filter = UpdateClassificationFilter.ToLowerInvariant();

                // Exact match or partial match (e.g., "Critical" matches "Critical Updates")
                if (!classification.Contains(filter))
                    return false;
            }

            // Search filter (case-insensitive substring across multiple fields)
            if (!string.IsNullOrWhiteSpace(UpdateSearchText))
            {
                var search = UpdateSearchText;
                var match = (update.Title?.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0) ||
                           (update.KbArticle?.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0) ||
                           (update.Classification?.IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0) ||
                           (update.IsApproved && "approved".IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0) ||
                           (update.IsDeclined && "declined".IndexOf(search, StringComparison.OrdinalIgnoreCase) >= 0);
                if (!match) return false;
            }

            return true;
        };
        view.Refresh();

        // Notify UI updates
        OnPropertyChanged(nameof(ShowClearUpdateFilters));
        OnPropertyChanged(nameof(UpdateVisibleCount));
        OnPropertyChanged(nameof(UpdateFilterCountText));

        // Refresh export button state (Phase 30)
        ExportUpdatesCommand.NotifyCanExecuteChanged();
    }

    /// <summary>
    /// Saves computer filter settings to persistent storage.
    /// </summary>
    private void SaveFilterSettings()
    {
        _settings.ComputerStatusFilter = ComputerStatusFilter;
        _settings.ComputerSearchText = ComputerSearchText;
        // Note: Settings are persisted on application shutdown or explicit save
        // For immediate persistence, call await SaveSettingsAsync()
    }

    /// <summary>
    /// Saves update filter settings to persistent storage.
    /// </summary>
    private void SaveUpdateFilterSettings()
    {
        _settings.UpdateApprovalFilter = UpdateApprovalFilter;
        _settings.UpdateClassificationFilter = UpdateClassificationFilter;
        _settings.UpdateSearchText = UpdateSearchText;
        // Note: Settings are persisted on application shutdown or explicit save
        // For immediate persistence, call await SaveSettingsAsync()
    }

    /// <summary>
    /// Clears all computer filters and resets to default state.
    /// </summary>
    [RelayCommand]
    private void ClearComputerFilters()
    {
        ComputerStatusFilter = "All";
        ComputerSearchText = string.Empty;
        _computerSearchDebounceTimer?.Stop();
        ApplyComputerFilters();
        SaveFilterSettings();
    }

    /// <summary>
    /// Clears all update filters and resets to default state.
    /// </summary>
    [RelayCommand]
    private void ClearUpdateFilters()
    {
        UpdateApprovalFilter = "All";
        UpdateClassificationFilter = "All";
        UpdateSearchText = string.Empty;
        _updateSearchDebounceTimer?.Stop();
        ApplyUpdateFilters();
        SaveUpdateFilterSettings();
    }

    // ═══════════════════════════════════════════════════════════════
    // PHASE 30: DATA EXPORT
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Exports the currently filtered computers list to CSV.
    /// Button enabled when FilteredComputers has items.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanExportComputers))]
    private async Task ExportComputersAsync()
    {
        if (FilteredComputers.Count == 0)
        {
            MessageBox.Show(
                "No computers to export. Apply filters or load data first.",
                "Cannot Export",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        await RunOperationAsync(
            "Export Computers",
            async (progress, ct) =>
            {
                var filePath = await _csvExportService.ExportComputersAsync(
                    FilteredComputers,
                    progress,
                    ct).ConfigureAwait(false);

                progress.Report($"Opening: {filePath}");

                // Open destination folder with file selected
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"/select,\"{filePath}\"",
                    UseShellExecute = true
                });

                return true;
            }).ConfigureAwait(false);
    }

    /// <summary>
    /// Determines if ExportComputers command can execute.
    /// Requires at least one visible computer in filtered list.
    /// </summary>
    private bool CanExportComputers() => FilteredComputers.Count > 0;

    /// <summary>
    /// Exports the currently filtered updates list to CSV.
    /// Button enabled when FilteredUpdates has items.
    /// </summary>
    [RelayCommand(CanExecute = nameof(CanExportUpdates))]
    private async Task ExportUpdatesAsync()
    {
        if (FilteredUpdates.Count == 0)
        {
            MessageBox.Show(
                "No updates to export. Apply filters or load data first.",
                "Cannot Export",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        await RunOperationAsync(
            "Export Updates",
            async (progress, ct) =>
            {
                var filePath = await _csvExportService.ExportUpdatesAsync(
                    FilteredUpdates,
                    progress,
                    ct).ConfigureAwait(false);

                progress.Report($"Opening: {filePath}");

                // Open destination folder with file selected
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"/select,\"{filePath}\"",
                    UseShellExecute = true
                });

                return true;
            }).ConfigureAwait(false);
    }

    /// <summary>
    /// Determines if ExportUpdates command can execute.
    /// Requires at least one visible update in filtered list.
    /// </summary>
    private bool CanExportUpdates() => FilteredUpdates.Count > 0;

    // ═══════════════════════════════════════════════════════════════
    // Note: Data list models (ComputerInfo, UpdateInfo) are now in
    // WsusManager.Core.Models namespace for proper layering
    // ═══════════════════════════════════════════════════════════════
}
