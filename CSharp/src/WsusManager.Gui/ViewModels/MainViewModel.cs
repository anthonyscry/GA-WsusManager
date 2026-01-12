using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WsusManager.Core.Health;
using WsusManager.Core.Services;
using WsusManager.Core.Utilities;
using System.Collections.ObjectModel;

namespace WsusManager.Gui.ViewModels;

/// <summary>
/// Main view model for WSUS Manager GUI.
/// Demonstrates clean async/await pattern - no more Dispatcher.Invoke complexity!
/// </summary>
public partial class MainViewModel : ObservableObject
{
    private readonly HealthChecker _healthChecker;

    [ObservableProperty]
    private string _statusMessage = "Ready";

    [ObservableProperty]
    private bool _isOperationRunning;

    [ObservableProperty]
    private string _logOutput = string.Empty;

    [ObservableProperty]
    private ServiceStatusViewModel? _sqlServerStatus;

    [ObservableProperty]
    private ServiceStatusViewModel? _wsusServiceStatus;

    [ObservableProperty]
    private ServiceStatusViewModel? _iisStatus;

    [ObservableProperty]
    private string _databaseSize = "Unknown";

    [ObservableProperty]
    private string _overallHealth = "Unknown";

    public MainViewModel()
    {
        _healthChecker = new HealthChecker();

        // Initialize service status view models
        SqlServerStatus = new ServiceStatusViewModel { ServiceName = "SQL Server Express" };
        WsusServiceStatus = new ServiceStatusViewModel { ServiceName = "WSUS Service" };
        IisStatus = new ServiceStatusViewModel { ServiceName = "IIS" };

        // Start auto-refresh timer (30 seconds)
        StartAutoRefresh();
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task RunHealthCheckAsync()
    {
        IsOperationRunning = true;
        StatusMessage = "Running health check...";
        LogOutput = string.Empty;

        try
        {
            AppendLog("=== Starting Health Check ===");

            // Capture console output
            var originalOut = Console.Out;
            using var writer = new StringWriter();
            Console.SetOut(writer);

            try
            {
                var result = await _healthChecker.PerformHealthCheckAsync(includeDatabase: true);

                // Get captured output
                var output = writer.ToString();
                AppendLog(output);

                // Update UI with results
                UpdateServiceStatus(result.Services);
                OverallHealth = result.Overall.ToString();
                DatabaseSize = result.Database.Connected
                    ? $"{result.Database.SizeGB:F2} GB"
                    : "Unavailable";

                AppendLog($"\nHealth check completed. Status: {result.Overall}");
                StatusMessage = $"Health check complete - Status: {result.Overall}";
            }
            finally
            {
                Console.SetOut(originalOut);
            }
        }
        catch (Exception ex)
        {
            AppendLog($"\nERROR: {ex.Message}");
            StatusMessage = "Health check failed";
        }
        finally
        {
            IsOperationRunning = false;
        }
    }

    [RelayCommand(CanExecute = nameof(CanExecuteOperation))]
    private async Task RepairHealthAsync()
    {
        IsOperationRunning = true;
        StatusMessage = "Repairing health issues...";
        LogOutput = string.Empty;

        try
        {
            AppendLog("=== Starting Health Repair ===");

            var originalOut = Console.Out;
            using var writer = new StringWriter();
            Console.SetOut(writer);

            try
            {
                var result = await Task.Run(() => _healthChecker.RepairHealth());

                var output = writer.ToString();
                AppendLog(output);

                AppendLog($"\nRepair completed. Services started: {result.ServicesStarted.Count}");
                StatusMessage = result.Success
                    ? "Repair completed successfully"
                    : "Repair completed with errors";

                // Refresh dashboard
                await RefreshDashboardAsync();
            }
            finally
            {
                Console.SetOut(originalOut);
            }
        }
        catch (Exception ex)
        {
            AppendLog($"\nERROR: {ex.Message}");
            StatusMessage = "Repair failed";
        }
        finally
        {
            IsOperationRunning = false;
        }
    }

    [RelayCommand]
    private async Task RefreshDashboardAsync()
    {
        try
        {
            var services = ServiceManager.GetWsusServiceStatus();
            UpdateServiceStatus(services);
            StatusMessage = "Dashboard refreshed";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Refresh failed: {ex.Message}";
        }
    }

    private void UpdateServiceStatus(Dictionary<string, ServiceStatus> services)
    {
        if (services.TryGetValue("SQL Server Express", out var sql))
        {
            if (SqlServerStatus != null)
            {
                SqlServerStatus.Status = sql.Status;
                SqlServerStatus.IsRunning = sql.Running;
            }
        }

        if (services.TryGetValue("WSUS Service", out var wsus))
        {
            if (WsusServiceStatus != null)
            {
                WsusServiceStatus.Status = wsus.Status;
                WsusServiceStatus.IsRunning = wsus.Running;
            }
        }

        if (services.TryGetValue("IIS", out var iis))
        {
            if (IisStatus != null)
            {
                IisStatus.Status = iis.Status;
                IisStatus.IsRunning = iis.Running;
            }
        }
    }

    private void AppendLog(string message)
    {
        LogOutput += message + Environment.NewLine;
    }

    private bool CanExecuteOperation() => !IsOperationRunning;

    private async void StartAutoRefresh()
    {
        while (true)
        {
            await Task.Delay(TimeSpan.FromSeconds(30));

            if (!IsOperationRunning)
            {
                await RefreshDashboardAsync();
            }
        }
    }
}

/// <summary>
/// Service status view model.
/// </summary>
public partial class ServiceStatusViewModel : ObservableObject
{
    [ObservableProperty]
    private string _serviceName = string.Empty;

    [ObservableProperty]
    private string _status = "Unknown";

    [ObservableProperty]
    private bool _isRunning;
}
