namespace WsusManager.Core.Models;

/// <summary>
/// Holds all data collected during a dashboard refresh cycle.
/// Populated by IDashboardService.CollectAsync().
/// </summary>
public class DashboardData
{
    /// <summary>Number of monitored services currently running.</summary>
    public int ServiceRunningCount { get; set; }

    /// <summary>Names of the monitored services (SQL, WSUS, IIS).</summary>
    public string[] ServiceNames { get; set; } = Array.Empty<string>();

    /// <summary>
    /// SUSDB database size in GB. Returns -1 if SQL Server is not running
    /// or the database cannot be queried.
    /// </summary>
    public double DatabaseSizeGB { get; set; } = -1;

    /// <summary>Free disk space in GB on the WSUS content drive.</summary>
    public double DiskFreeGB { get; set; }

    /// <summary>
    /// Scheduled task status: "Ready", "Running", "Disabled", "Not Found", etc.
    /// </summary>
    public string TaskStatus { get; set; } = "Not Found";

    /// <summary>Whether the WSUS service (WsusService) is installed on this server.</summary>
    public bool IsWsusInstalled { get; set; }

    /// <summary>Whether the server has internet connectivity.</summary>
    public bool IsOnline { get; set; }
}
