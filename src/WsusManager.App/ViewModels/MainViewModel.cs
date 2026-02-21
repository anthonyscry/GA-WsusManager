using System.IO;
using System.Windows;
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
public partial class MainViewModel : ObservableObject
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
    private CancellationTokenSource? _operationCts;
    private DispatcherTimer? _refreshTimer;
    private AppSettings _settings = new();
    private bool _isInitialized;

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
        IThemeService themeService)
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

    public Visibility IsOperationPanelVisible => !string.Equals(CurrentPanel, "Dashboard", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "Diagnostics", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "Database", StringComparison.Ordinal) && !string.Equals(CurrentPanel, "ClientTools"
, StringComparison.Ordinal) ? Visibility.Visible
            : Visibility.Collapsed;

    [RelayCommand]
    private void Navigate(string panel)
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
            _ => panel
        };

        OnPropertyChanged(nameof(IsDashboardVisible));
        OnPropertyChanged(nameof(IsDiagnosticsPanelVisible));
        OnPropertyChanged(nameof(IsDatabasePanelVisible));
        OnPropertyChanged(nameof(IsClientToolsPanelVisible));
        OnPropertyChanged(nameof(IsOperationPanelVisible));
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
        StatusMessage = $"Running: {operationName}...";

        // Clear previous banner and step text when new operation starts
        StatusBannerText = string.Empty;
        OperationStepText = string.Empty;

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
                OperationStepText = line;
        });

        try
        {
            var success = await operation(progress, _operationCts.Token).ConfigureAwait(false);

            if (success)
            {
                StatusMessage = $"{operationName} completed successfully.";
                StatusBannerText = $"{operationName} completed successfully.";
                StatusBannerColor = GetThemeBrush("StatusSuccess", Color.FromRgb(0x3F, 0xB9, 0x50));
                AppendLog($"=== {operationName} completed ===");
                _logService.Info("Operation completed: {Operation}", operationName);
            }
            else
            {
                StatusMessage = $"{operationName} failed.";
                StatusBannerText = $"{operationName} failed.";
                StatusBannerColor = GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));
                AppendLog($"=== {operationName} FAILED ===");
                _logService.Warning("Operation failed: {Operation}", operationName);
            }

            return success;
        }
        catch (OperationCanceledException)
        {
            StatusMessage = $"{operationName} cancelled.";
            StatusBannerText = $"{operationName} cancelled.";
            StatusBannerColor = GetThemeBrush("StatusWarning", Color.FromRgb(0xD2, 0x99, 0x22));
            AppendLog($"=== {operationName} CANCELLED ===");
            _logService.Info("Operation cancelled: {Operation}", operationName);
            return false;
        }
        catch (Exception ex)
        {
            StatusMessage = $"{operationName} failed with error.";
            StatusBannerText = $"{operationName} failed.";
            StatusBannerColor = GetThemeBrush("StatusError", Color.FromRgb(0xF8, 0x51, 0x49));
            AppendLog($"[ERROR] {ex.Message}");
            AppendLog($"=== {operationName} FAILED ===");
            _logService.Error(ex, "Operation error: {Operation}", operationName);
            return false;
        }
        finally
        {
            IsOperationRunning = false;
            CurrentOperationName = string.Empty;
            OperationStepText = string.Empty;
            _operationCts?.Dispose();
            _operationCts = null;

            // Notify all operation commands to re-evaluate CanExecute (re-enables buttons after operation)
            NotifyCommandCanExecuteChanged();
        }
    }

    /// <summary>
    /// Appends a line to the log output panel.
    /// </summary>
    public void AppendLog(string line)
    {
        LogOutput += line + Environment.NewLine;
    }

    [RelayCommand]
    private void ClearLog()
    {
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
        var confirm = MessageBox.Show(
            "This will run 'wsusutil reset' to re-verify all WSUS content files against the database.\n\n" +
            "This operation can take 10+ minutes on large content stores.\n\n" +
            "Continue?",
            "Confirm Content Reset",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (confirm != MessageBoxResult.Yes) return;

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
    /// </summary>
    public async Task InitializeAsync()
    {
        if (_isInitialized) return;
        _isInitialized = true;

        // Load settings
        _settings = await _settingsService.LoadAsync().ConfigureAwait(false);
        ApplySettings(_settings);

        // First dashboard refresh (sets IsWsusInstalled correctly before any checks)
        await RefreshDashboard().ConfigureAwait(false);

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
        var dialog = new SettingsDialog(_settings, _themeService);
        if (Application.Current.MainWindow is not null)
            dialog.Owner = Application.Current.MainWindow;

        if (dialog.ShowDialog() != true || dialog.Result is null) return;

        var updated = dialog.Result;

        // Preserve fields not shown in dialog
        updated.LogPanelExpanded = _settings.LogPanelExpanded;
        updated.LiveTerminalMode = _settings.LiveTerminalMode;

        // Check if refresh interval changed (need timer restart)
        var intervalChanged = updated.RefreshIntervalSeconds != _settings.RefreshIntervalSeconds;

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
        var interval = TimeSpan.FromSeconds(
            _settings.RefreshIntervalSeconds > 0 ? _settings.RefreshIntervalSeconds : 30);

        _refreshTimer = new DispatcherTimer { Interval = interval };
        _refreshTimer.Tick += async (_, _) => await RefreshDashboard().ConfigureAwait(false);
        _refreshTimer.Start();

        _logService.Debug("Dashboard auto-refresh started ({Interval}s interval)", interval.TotalSeconds);
    }

    /// <summary>
    /// Stops the auto-refresh timer. Called during cleanup/dispose.
    /// </summary>
    public void StopRefreshTimer()
    {
        _refreshTimer?.Stop();
        _refreshTimer = null;
    }
}
