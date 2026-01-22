using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WsusManager.Core.Health;
using WsusManager.Core.Services;
using WsusManager.Core.Database;
using WsusManager.Core.Operations;
using System.IO;
using System.Windows;
using Microsoft.Win32;
using Ookii.Dialogs.Wpf;

namespace WsusManager.Gui.ViewModels;

/// <summary>
/// Main view model - complete port matching PowerShell v3.8.3
/// </summary>
public partial class MainViewModel : ObservableObject
{
    private readonly HealthChecker _healthChecker;
    private readonly DatabaseOperations _database;
    private CancellationTokenSource? _operationCancellation;

    // Dashboard Properties
    [ObservableProperty] private string _currentPage = "Dashboard";
    [ObservableProperty] private bool _isDashboardVisible = true;
    [ObservableProperty] private string _statusMessage = "Ready";
    [ObservableProperty] private bool _isOperationRunning;
    [ObservableProperty] private string _logOutput = string.Empty;

    // Service Status
    [ObservableProperty] private string _servicesStatus = "...";
    [ObservableProperty] private bool _allServicesRunning;
    [ObservableProperty] private string _databaseSize = "Unknown";
    [ObservableProperty] private string _serverMode = "Online";
    [ObservableProperty] private string _overallHealth = "Unknown";

    // Log Panel
    [ObservableProperty] private GridLength _logPanelHeight = new GridLength(250);
    [ObservableProperty] private bool _isLogPanelExpanded = true;
    [ObservableProperty] private string _logPanelButtonText = "Hide";

    // Settings (loaded from file or defaults)
    private string _sqlInstance = @".\SQLEXPRESS";
    private string _contentPath = @"C:\WSUS";

    public MainViewModel()
    {
        _healthChecker = new HealthChecker(_sqlInstance);
        _database = new DatabaseOperations(_sqlInstance);

        // Load settings and start auto-refresh
        LoadSettings();
        StartAutoRefresh();
        _ = RefreshDashboardAsync();
    }

    #region Navigation Commands

    [RelayCommand]
    private void ShowDashboard()
    {
        CurrentPage = "Dashboard";
        IsDashboardVisible = true;
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task InstallWsusAsync()
    {
        var dialog = new VistaFolderBrowserDialog
        {
            Description = "Select folder containing SQL Server installers",
            UseDescriptionForTitle = true
        };

        if (dialog.ShowDialog() == true)
        {
            await RunOperationAsync("Install WSUS", async () =>
            {
                AppendLog($"=== Installing WSUS ===");
                AppendLog($"Installer path: {dialog.SelectedPath}");
                AppendLog("Installation functionality will call PowerShell script...");
                await Task.Delay(1000); // Placeholder
                return true;
            });
        }
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task RestoreDbAsync()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select SUSDB Backup File",
            Filter = "Backup Files (*.bak)|*.bak|All Files (*.*)|*.*",
            InitialDirectory = _contentPath
        };

        if (dialog.ShowDialog() == true)
        {
            await RunOperationAsync("Restore Database", async () =>
            {
                AppendLog($"=== Restoring Database ===");
                AppendLog($"Backup file: {dialog.FileName}");
                AppendLog("Restore functionality will call PowerShell script...");
                await Task.Delay(1000); // Placeholder
                return true;
            });
        }
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task ExportImportAsync()
    {
        // Show direction dialog
        var directionDialog = new Window
        {
            Title = "Export or Import?",
            Width = 400,
            Height = 200,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = Application.Current.MainWindow
        };

        bool isExport = true;
        var panel = new System.Windows.Controls.StackPanel { Margin = new Thickness(20) };

        var exportBtn = new System.Windows.Controls.Button
        {
            Content = "Export (Online → Media)",
            Padding = new Thickness(15, 10),
            Margin = new Thickness(0, 10)
        };
        exportBtn.Click += (s, e) => { isExport = true; directionDialog.DialogResult = true; };

        var importBtn = new System.Windows.Controls.Button
        {
            Content = "Import (Media → Air-Gap)",
            Padding = new Thickness(15, 10),
            Margin = new Thickness(0, 10)
        };
        importBtn.Click += (s, e) => { isExport = false; directionDialog.DialogResult = true; };

        panel.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "Select transfer direction:",
            FontSize = 14,
            Margin = new Thickness(0, 0, 0, 10)
        });
        panel.Children.Add(exportBtn);
        panel.Children.Add(importBtn);
        directionDialog.Content = panel;

        if (directionDialog.ShowDialog() != true)
            return;

        var folderDialog = new VistaFolderBrowserDialog
        {
            Description = isExport ? "Select destination folder for export" : "Select source folder for import",
            UseDescriptionForTitle = true
        };

        if (folderDialog.ShowDialog() == true)
        {
            await RunOperationAsync(isExport ? "Export" : "Import", async () =>
            {
                AppendLog($"=== Starting {(isExport ? "Export" : "Import")} ===");
                AppendLog($"Path: {folderDialog.SelectedPath}");

                var exportImport = new ExportImportOperations();
                var progress = new Progress<string>(msg => AppendLog(msg));

                return isExport
                    ? await exportImport.ExportAsync(folderDialog.SelectedPath, progress)
                    : await exportImport.ImportAsync(folderDialog.SelectedPath, progress);
            });
        }
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task MonthlyMaintenanceAsync()
    {
        // Show profile selection dialog
        var profileDialog = new Window
        {
            Title = "Select Maintenance Profile",
            Width = 400,
            Height = 250,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = Application.Current.MainWindow
        };

        string? selectedProfile = null;
        var panel = new System.Windows.Controls.StackPanel { Margin = new Thickness(20) };

        foreach (var profile in new[] { "Quick", "Standard", "Full" })
        {
            var btn = new System.Windows.Controls.Button
            {
                Content = $"{profile} Maintenance",
                Padding = new Thickness(15, 10),
                Margin = new Thickness(0, 10)
            };
            var profileCopy = profile;
            btn.Click += (s, e) => { selectedProfile = profileCopy; profileDialog.DialogResult = true; };
            panel.Children.Add(btn);
        }

        panel.Children.Insert(0, new System.Windows.Controls.TextBlock
        {
            Text = "Select maintenance profile:",
            FontSize = 14,
            Margin = new Thickness(0, 0, 0, 10)
        });
        profileDialog.Content = panel;

        if (profileDialog.ShowDialog() == true && selectedProfile != null)
        {
            await RunOperationAsync($"Monthly Maintenance ({selectedProfile})", async () =>
            {
                AppendLog($"=== Running {selectedProfile} Maintenance ===");
                AppendLog("Maintenance will call PowerShell script...");
                await Task.Delay(2000); // Placeholder
                return true;
            });
        }
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task DeepCleanupAsync()
    {
        var result = MessageBox.Show(
            "Deep cleanup will remove obsolete updates and compact the database. Continue?",
            "Confirm Deep Cleanup",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result == MessageBoxResult.Yes)
        {
            await RunOperationAsync("Deep Cleanup", async () =>
            {
                AppendLog("=== Starting Deep Cleanup ===");

                AppendLog("Removing declined supersession records...");
                var declined = await _database.RemoveDeclinedSupersessionRecordsAsync();
                AppendLog($"Removed {declined} declined records");

                AppendLog("Removing superseded supersession records...");
                var superseded = await _database.RemoveSupersededSupersessionRecordsAsync();
                AppendLog($"Removed {superseded} superseded records");

                AppendLog("Optimizing indexes...");
                await _database.OptimizeIndexesAsync();
                AppendLog("Index optimization complete");

                return true;
            });
        }
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task RunHealthCheckAsync()
    {
        await RunOperationAsync("Health Check", async () =>
        {
            AppendLog("=== Starting Health Check ===");

            var originalOut = Console.Out;
            using var writer = new StringWriter();
            Console.SetOut(writer);

            try
            {
                var result = await _healthChecker.PerformHealthCheckAsync(includeDatabase: true);
                var output = writer.ToString();
                AppendLog(output);

                UpdateDashboardFromHealthCheck(result);
                AppendLog($"\nHealth check complete. Status: {result.Overall}");
                return true;
            }
            finally
            {
                Console.SetOut(originalOut);
            }
        });
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task RepairHealthAsync()
    {
        await RunOperationAsync("Repair Health", async () =>
        {
            AppendLog("=== Starting Health Repair ===");

            var originalOut = Console.Out;
            using var writer = new StringWriter();
            Console.SetOut(writer);

            try
            {
                var result = await _healthChecker.RepairHealthAsync(_contentPath);
                var output = writer.ToString();
                AppendLog(output);

                AppendLog($"\nServices started: {result.ServicesStarted.Count}");
                await RefreshDashboardAsync();
                return result.Success;
            }
            finally
            {
                Console.SetOut(originalOut);
            }
        });
    }

    #endregion

    #region Quick Actions

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task StartServicesAsync()
    {
        await RunOperationAsync("Start Services", async () =>
        {
            AppendLog("=== Starting Services ===");

            var services = new[]
            {
                ("MSSQL$SQLEXPRESS", "SQL Server Express"),
                ("W3SVC", "IIS"),
                ("WSUSService", "WSUS Service")
            };

            foreach (var (name, display) in services)
            {
                try
                {
                    AppendLog($"Starting {display}...");
                    ServiceManager.StartService(name);
                    AppendLog($"✓ {display} started");
                }
                catch (Exception ex)
                {
                    AppendLog($"✗ Failed to start {display}: {ex.Message}");
                }
            }

            await RefreshDashboardAsync();
            return true;
        });
    }

    #endregion

    #region Dialogs

    [RelayCommand]
    private void ShowHelp()
    {
        MessageBox.Show(
            "WSUS Manager v4.0 - C# Edition\n\n" +
            "Operations:\n" +
            "• Install WSUS - Install WSUS with SQL Express\n" +
            "• Restore DB - Restore SUSDB from backup\n" +
            "• Export/Import - Transfer data for air-gap\n" +
            "• Monthly Maintenance - Scheduled cleanup\n" +
            "• Deep Cleanup - Remove obsolete updates\n" +
            "• Health Check - Diagnose issues\n" +
            "• Repair - Auto-fix common problems",
            "Help",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    [RelayCommand]
    private void ShowSettings()
    {
        MessageBox.Show(
            $"SQL Instance: {_sqlInstance}\n" +
            $"Content Path: {_contentPath}\n" +
            $"Server Mode: {ServerMode}\n\n" +
            "Settings dialog coming soon...",
            "Settings",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    [RelayCommand]
    private void ShowAbout()
    {
        MessageBox.Show(
            "WSUS Manager v4.0\n" +
            "C# Edition\n\n" +
            "Author: Tony Tran, ISSO, GA-ASI\n" +
            "Ported from PowerShell v3.8.3\n\n" +
            "© 2026 General Atomics",
            "About WSUS Manager",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    #endregion

    #region Log Panel

    [RelayCommand]
    private void ToggleLogPanel()
    {
        IsLogPanelExpanded = !IsLogPanelExpanded;
        LogPanelHeight = IsLogPanelExpanded ? new GridLength(250) : new GridLength(0);
        LogPanelButtonText = IsLogPanelExpanded ? "Hide" : "Show";
    }

    [RelayCommand]
    private void ClearLog()
    {
        LogOutput = string.Empty;
    }

    [RelayCommand]
    private void CancelOperation()
    {
        _operationCancellation?.Cancel();
        AppendLog("\n[Operation cancelled by user]");
        StatusMessage = "Operation cancelled";
        IsOperationRunning = false;
    }

    #endregion

    #region Helper Methods

    private async Task RunOperationAsync(string operationName, Func<Task<bool>> operation)
    {
        IsOperationRunning = true;
        _operationCancellation = new CancellationTokenSource();
        StatusMessage = $"Running {operationName}...";
        LogOutput = string.Empty;

        // Expand log panel if collapsed
        if (!IsLogPanelExpanded)
        {
            ToggleLogPanel();
        }

        try
        {
            var success = await operation();
            StatusMessage = success
                ? $"{operationName} completed successfully"
                : $"{operationName} completed with errors";

            if (success)
                AppendLog($"\n✓ {operationName} completed successfully");
        }
        catch (OperationCanceledException)
        {
            AppendLog($"\n[{operationName} was cancelled]");
            StatusMessage = "Operation cancelled";
        }
        catch (Exception ex)
        {
            AppendLog($"\n✗ ERROR: {ex.Message}");
            StatusMessage = $"{operationName} failed";
            MessageBox.Show(
                $"Operation failed: {ex.Message}",
                operationName,
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            IsOperationRunning = false;
            _operationCancellation?.Dispose();
            _operationCancellation = null;
        }
    }

    [RelayCommand]
    private async Task RefreshDashboardAsync()
    {
        try
        {
            var services = ServiceManager.GetWsusServiceStatus();

            int running = services.Count(s => s.Value.Running);
            int total = services.Count;
            ServicesStatus = $"{running}/{total} Running";
            AllServicesRunning = running == total;

            try
            {
                var dbSize = await _database.GetDatabaseSizeAsync();
                DatabaseSize = $"{dbSize:F2} GB";
            }
            catch
            {
                DatabaseSize = "Unknown";
            }

            StatusMessage = "Dashboard refreshed";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Refresh failed: {ex.Message}";
        }
    }

    private void UpdateDashboardFromHealthCheck(HealthCheckResult result)
    {
        OverallHealth = result.Overall;

        var running = result.Services.Count(s => s.Value.Running);
        var total = result.Services.Count;
        ServicesStatus = $"{running}/{total} Running";
        AllServicesRunning = running == total;
    }

    private void AppendLog(string message)
    {
        LogOutput += message + Environment.NewLine;
    }

    private bool CanExecuteOperation() => !IsOperationRunning;

    private void LoadSettings()
    {
        // TODO: Load from %APPDATA%\WsusManager\settings.json
        // For now use defaults
    }

    private async void StartAutoRefresh()
    {
        while (true)
        {
            await Task.Delay(TimeSpan.FromSeconds(30));

            if (!IsOperationRunning && IsDashboardVisible)
            {
                await RefreshDashboardAsync();
            }
        }
    }

    #endregion
}
