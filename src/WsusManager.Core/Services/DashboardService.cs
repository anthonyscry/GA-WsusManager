using System.Net.NetworkInformation;
using System.ServiceProcess;
using Microsoft.Data.SqlClient;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Collects dashboard data from the local system: Windows services,
/// SQL database size, disk space, scheduled task status, and internet connectivity.
/// All queries use async patterns and timeouts to avoid blocking the UI.
/// </summary>
public class DashboardService : IDashboardService
{
    private static readonly string[] MonitoredServices = { "MSSQL$SQLEXPRESS", "WsusService", "W3SVC" };
    private const int ConnectivityTimeoutMs = 500;

    private readonly ILogService _logService;

    public DashboardService(ILogService logService)
    {
        _logService = logService;
    }

    public async Task<DashboardData> CollectAsync(AppSettings settings, CancellationToken ct)
    {
        var data = new DashboardData();

        // Run all checks in parallel for responsiveness
        var serviceTask = Task.Run(() => CheckServices(data), ct);
        var dbTask = Task.Run(() => CheckDatabaseSize(data, settings.SqlInstance), ct);
        var diskTask = Task.Run(() => CheckDiskSpace(data, settings.ContentPath), ct);
        var taskTask = Task.Run(() => CheckScheduledTask(data), ct);
        var connectTask = CheckConnectivity(data);

        try
        {
            await Task.WhenAll(serviceTask, dbTask, diskTask, taskTask, connectTask).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logService.Warning("One or more dashboard checks failed: {Error}", ex.Message);
        }

        return data;
    }

    /// <summary>
    /// Checks the status of monitored Windows services.
    /// </summary>
    private void CheckServices(DashboardData data)
    {
        try
        {
            var running = 0;
            var wsusFound = false;

            foreach (var name in MonitoredServices)
            {
                try
                {
                    using var sc = new ServiceController(name);
                    _ = sc.Status; // Force query to verify service exists

                    if (string.Equals(name, "WsusService", StringComparison.Ordinal))
                        wsusFound = true;

                    if (sc.Status == ServiceControllerStatus.Running)
                        running++;
                }
                catch (InvalidOperationException)
                {
                    // Service not installed
                    if (string.Equals(name, "WsusService", StringComparison.Ordinal))
                        wsusFound = false;
                }
            }

            data.ServiceNames = MonitoredServices;
            data.ServiceRunningCount = running;
            data.IsWsusInstalled = wsusFound;
        }
        catch (Exception ex)
        {
            _logService.Warning("Service check failed: {Error}", ex.Message);
            data.ServiceNames = MonitoredServices;
            data.ServiceRunningCount = 0;
            data.IsWsusInstalled = false;
        }
    }

    /// <summary>
    /// Queries SUSDB size from SQL Server Express.
    /// Returns -1 if SQL is not running or query fails.
    /// </summary>
    private void CheckDatabaseSize(DashboardData data, string sqlInstance)
    {
        try
        {
            var connStr = $"Data Source={sqlInstance};Initial Catalog=SUSDB;" +
                          "Integrated Security=True;TrustServerCertificate=True;" +
                          "Connect Timeout=5";

            using var conn = new SqlConnection(connStr);
            conn.Open();

            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT SUM(size) * 8.0 / 1024 / 1024 FROM sys.database_files";
            cmd.CommandTimeout = 5;

            var result = cmd.ExecuteScalar();
            if (result != null && result != DBNull.Value)
            {
                data.DatabaseSizeGB = Convert.ToDouble(result);
            }
        }
        catch (Exception ex)
        {
            _logService.Debug("Database size check failed (SQL may be offline): {Error}", ex.Message);
            data.DatabaseSizeGB = -1;
        }
    }

    /// <summary>
    /// Checks free disk space on the drive containing the WSUS content path.
    /// </summary>
    private void CheckDiskSpace(DashboardData data, string contentPath)
    {
        try
        {
            var driveLetter = string.IsNullOrEmpty(contentPath) ? "C" : contentPath[..1];
            var driveInfo = new DriveInfo(driveLetter);

            if (driveInfo.IsReady)
            {
                data.DiskFreeGB = driveInfo.AvailableFreeSpace / (1024.0 * 1024 * 1024);
            }
        }
        catch (Exception ex)
        {
            _logService.Debug("Disk space check failed: {Error}", ex.Message);
            data.DiskFreeGB = 0;
        }
    }

    /// <summary>
    /// Checks the status of the WSUS maintenance scheduled task.
    /// Uses schtasks.exe to query task state.
    /// </summary>
    private void CheckScheduledTask(DashboardData data)
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = "/Query /TN \"WSUS Monthly Maintenance\" /FO CSV /NH",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var proc = System.Diagnostics.Process.Start(psi);
            if (proc != null)
            {
                var output = proc.StandardOutput.ReadToEnd();
                proc.WaitForExit(3000);

                if (proc.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
                {
                    // CSV output: "TaskName","NextRunTime","Status"
                    if (output.Contains("Ready", StringComparison.OrdinalIgnoreCase))
                        data.TaskStatus = "Ready";
                    else if (output.Contains("Running", StringComparison.OrdinalIgnoreCase))
                        data.TaskStatus = "Running";
                    else if (output.Contains("Disabled", StringComparison.OrdinalIgnoreCase))
                        data.TaskStatus = "Disabled";
                    else
                        data.TaskStatus = "Unknown";
                }
                else
                {
                    data.TaskStatus = "Not Found";
                }
            }
        }
        catch (Exception ex)
        {
            _logService.Debug("Scheduled task check failed: {Error}", ex.Message);
            data.TaskStatus = "Not Found";
        }
    }

    /// <summary>
    /// Checks internet connectivity using a .NET Ping with 500ms timeout.
    /// Non-blocking to prevent UI freezing on slow/offline networks.
    /// </summary>
    private async Task CheckConnectivity(DashboardData data)
    {
        try
        {
            using var ping = new Ping();
            var reply = await ping.SendPingAsync("8.8.8.8", ConnectivityTimeoutMs).ConfigureAwait(false);
            data.IsOnline = reply.Status == IPStatus.Success;
        }
        catch
        {
            data.IsOnline = false;
        }
    }
}
