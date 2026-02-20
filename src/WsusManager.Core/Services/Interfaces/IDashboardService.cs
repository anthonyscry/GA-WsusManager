using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Collects system state data for the dashboard: service statuses,
/// database size, disk space, scheduled task status, and connectivity.
/// All queries are async and non-blocking.
/// </summary>
public interface IDashboardService
{
    /// <summary>
    /// Collects all dashboard data asynchronously.
    /// </summary>
    /// <param name="settings">Current application settings (content path, SQL instance).</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>Populated DashboardData with current system state.</returns>
    Task<DashboardData> CollectAsync(AppSettings settings, CancellationToken ct);
}
