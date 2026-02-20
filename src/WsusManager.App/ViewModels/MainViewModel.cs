using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
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
    private CancellationTokenSource? _operationCts;
    private DispatcherTimer? _refreshTimer;
    private AppSettings _settings = new();
    private bool _isInitialized;

    /// <summary>
    /// Maximum number of updates to auto-approve per sync run (safety threshold).
    /// </summary>
    private const int MaxAutoApproveCount = 200;

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
        IGpoDeploymentService gpoDeploymentService)
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

    public Visibility IsDashboardVisible =>
        CurrentPanel == "Dashboard" ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsDiagnosticsPanelVisible =>
        CurrentPanel == "Diagnostics" ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsDatabasePanelVisible =>
        CurrentPanel == "Database" ? Visibility.Visible : Visibility.Collapsed;

    public Visibility IsOperationPanelVisible =>
        CurrentPanel != "Dashboard" && CurrentPanel != "Diagnostics" && CurrentPanel != "Database"
            ? Visibility.Visible
            : Visibility.Collapsed;

    [RelayCommand]
    private void Navigate(string panel)
    {
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
            _ => panel
        };

        OnPropertyChanged(nameof(IsDashboardVisible));
        OnPropertyChanged(nameof(IsDiagnosticsPanelVisible));
        OnPropertyChanged(nameof(IsDatabasePanelVisible));
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
    private bool _isOperationRunning;

    [ObservableProperty]
    private string _logOutput = string.Empty;

    [ObservableProperty]
    private string _currentOperationName = string.Empty;

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

        // Auto-expand log panel when operation starts
        IsLogPanelExpanded = true;

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
        await SaveSettingsAsync();
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

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ConnectionDotColor))]
    [NotifyPropertyChangedFor(nameof(ConnectionStatusText))]
    [NotifyPropertyChangedFor(nameof(ServerModeText))]
    private bool _isOnline = true;

    public SolidColorBrush ConnectionDotColor => IsOnline
        ? new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50))   // Green
        : new SolidColorBrush(Color.FromRgb(0xF8, 0x51, 0x49));  // Red

    public string ConnectionStatusText => IsOnline ? "Online" : "Offline";
    public string ServerModeText => IsOnline ? "Online" : "Air-Gap";

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
                ct);

            // Trigger dashboard refresh to reflect any service state changes
            await RefreshDashboard();

            return report.IsHealthy || report.FailedCount == 0;
        });
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
            var result = await _contentResetService.ResetContentAsync(progress, ct);
            return result.Success;
        });
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task StartService(string serviceName)
    {
        await RunOperationAsync($"Start {serviceName}", async (progress, ct) =>
        {
            progress.Report($"Starting {serviceName}...");
            var result = await _serviceManager.StartServiceAsync(serviceName, ct);
            progress.Report(result.Success ? $"[OK] {result.Message}" : $"[FAIL] {result.Message}");

            // Refresh dashboard to reflect service state change
            await RefreshDashboard();
            return result.Success;
        });
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task StopService(string serviceName)
    {
        await RunOperationAsync($"Stop {serviceName}", async (progress, ct) =>
        {
            progress.Report($"Stopping {serviceName}...");
            var result = await _serviceManager.StopServiceAsync(serviceName, ct);
            progress.Report(result.Success ? $"[OK] {result.Message}" : $"[FAIL] {result.Message}");

            // Refresh dashboard to reflect service state change
            await RefreshDashboard();
            return result.Success;
        });
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
                ct);

            return result.Success;
        });
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
                ct);

            return result.Success;
        });
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
                ct);

            // Refresh dashboard after restore to reflect new DB state
            if (result.Success)
                await RefreshDashboard();

            return result.Success;
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // QUICK ACTION COMMANDS
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task QuickDiagnostics()
    {
        await RunDiagnostics();
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task QuickCleanup()
    {
        await RunDeepCleanup();
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOnlineOperation))]
    private async Task QuickSync()
    {
        await RunOnlineSync();
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task QuickStartServices()
    {
        await RunOperationAsync("Start All Services", async (progress, ct) =>
        {
            var result = await _serviceManager.StartAllServicesAsync(progress, ct);

            // Refresh dashboard to reflect service state changes
            await RefreshDashboard();
            return result.Success;
        });
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
                profile, MaxAutoApproveCount, progress, ct);
            return result.Success;
        });
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
                    dialog.ExportResult, progress, ct);
                return result.Success;
            });
        }
        else if (!dialog.IsExportMode && dialog.ImportResult is not null)
        {
            await RunOperationAsync("Import", async (progress, ct) =>
            {
                var result = await _importService.ImportAsync(
                    dialog.ImportResult, progress, ct);
                return result.Success;
            });
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
            var validation = await _installationService.ValidatePrerequisitesAsync(options, ct);
            if (!validation.Success)
            {
                progress.Report($"[FAIL] {validation.Message}");
                return false;
            }
            progress.Report("[OK] All prerequisites met.");
            progress.Report("");

            // Run installation
            var result = await _installationService.InstallAsync(options, progress, ct);

            // Refresh dashboard after install to detect WSUS role
            if (result.Success)
                await RefreshDashboard();

            return result.Success;
        });
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
            var result = await _scheduledTaskService.CreateTaskAsync(options, progress, ct);

            // Refresh dashboard to update Task card status
            if (result.Success)
                await RefreshDashboard();

            return result.Success;
        });
    }

    [RelayCommand(CanExecute = nameof(CanExecuteWsusOperation))]
    private async Task RunCreateGpo()
    {
        Navigate("Install");

        await RunOperationAsync("Create GPO", async (progress, ct) =>
        {
            var result = await _gpoDeploymentService.DeployGpoFilesAsync(progress, ct);

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
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // DASHBOARD REFRESH
    // ═══════════════════════════════════════════════════════════════

    [RelayCommand]
    private async Task RefreshDashboard()
    {
        try
        {
            var data = await _dashboardService.CollectAsync(_settings, CancellationToken.None);
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

        // Server mode
        IsOnline = data.IsOnline;

        if (!data.IsWsusInstalled)
        {
            ServicesValue = "N/A";
            ServicesSubtext = "Not Installed";
            ServicesBarColor = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E)); // gray

            DatabaseValue = "N/A";
            DatabaseSubtext = "Not Installed";
            DatabaseBarColor = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E));

            DiskValue = "N/A";
            DiskSubtext = "Not Installed";
            DiskBarColor = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E));

            TaskValue = "N/A";
            TaskSubtext = "Not Installed";
            TaskBarColor = new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E));
            return;
        }

        // Services Card
        ServicesValue = $"{data.ServiceRunningCount} / {data.ServiceNames.Length}";
        ServicesSubtext = string.Join(", ", data.ServiceNames);
        ServicesBarColor = data.ServiceRunningCount == data.ServiceNames.Length
            ? new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50))   // all running = green
            : data.ServiceRunningCount > 0
                ? new SolidColorBrush(Color.FromRgb(0xD2, 0x99, 0x22))  // some running = orange
                : new SolidColorBrush(Color.FromRgb(0xF8, 0x51, 0x49)); // none running = red

        // Database Card
        if (data.DatabaseSizeGB < 0)
        {
            DatabaseValue = "Offline";
            DatabaseSubtext = "SQL Server not running";
            DatabaseBarColor = new SolidColorBrush(Color.FromRgb(0xF8, 0x51, 0x49)); // red
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
                ? new SolidColorBrush(Color.FromRgb(0xF8, 0x51, 0x49))   // red
                : data.DatabaseSizeGB >= 7
                    ? new SolidColorBrush(Color.FromRgb(0xD2, 0x99, 0x22))  // orange
                    : new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50)); // green
        }

        // Disk Card
        DiskValue = $"{data.DiskFreeGB:F1} GB";
        DiskSubtext = data.DiskFreeGB < 10
            ? "Low disk space!"
            : $"Free on {(string.IsNullOrEmpty(_settings.ContentPath) ? "C:" : _settings.ContentPath[..2])} drive";
        DiskBarColor = data.DiskFreeGB < 10
            ? new SolidColorBrush(Color.FromRgb(0xF8, 0x51, 0x49))   // red
            : data.DiskFreeGB < 50
                ? new SolidColorBrush(Color.FromRgb(0xD2, 0x99, 0x22))  // orange
                : new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50)); // green

        // Task Card
        TaskValue = data.TaskStatus;
        TaskSubtext = data.TaskStatus == "Ready" ? "Scheduled" : "";
        TaskBarColor = data.TaskStatus == "Ready"
            ? new SolidColorBrush(Color.FromRgb(0x3F, 0xB9, 0x50))   // green
            : data.TaskStatus == "Not Found"
                ? new SolidColorBrush(Color.FromRgb(0x8B, 0x94, 0x9E))  // gray
                : new SolidColorBrush(Color.FromRgb(0xD2, 0x99, 0x22)); // orange
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
        _settings = await _settingsService.LoadAsync();
        ApplySettings(_settings);

        // Show startup message
        if (!IsWsusInstalled)
        {
            AppendLog("WSUS is not installed on this server.");
            AppendLog("To get started, click 'Install WSUS' in the sidebar.");
            AppendLog("");
        }

        // First dashboard refresh
        await RefreshDashboard();

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

    private void ApplySettings(AppSettings settings)
    {
        IsLogPanelExpanded = settings.LogPanelExpanded;
        IsOnline = settings.ServerMode == "Online";
        ConfigContentPath = settings.ContentPath;
        ConfigSqlInstance = settings.SqlInstance;
        ConfigLogPath = @"C:\WSUS\Logs";
    }

    private async Task SaveSettingsAsync()
    {
        try
        {
            await _settingsService.SaveAsync(_settings);
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
        _refreshTimer.Tick += async (_, _) => await RefreshDashboard();
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
