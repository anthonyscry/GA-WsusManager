using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Collects system state data for the dashboard: service statuses,
/// database size, disk space, scheduled task status, and connectivity.
/// All queries are async and non-blocking.
/// Update metadata is lazy-loaded on-demand for optimal performance.
/// </summary>
public interface IDashboardService
{
    /// <summary>
    /// Collects all dashboard data asynchronously.
    /// Returns summary counts (approved/declined/total) without loading
    /// full update details - use GetUpdatesAsync for complete metadata.
    /// </summary>
    /// <param name="settings">Current application settings (content path, SQL instance).</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>Populated DashboardData with current system state.</returns>
    Task<DashboardData> CollectAsync(AppSettings settings, CancellationToken ct);

    /// <summary>
    /// Fetches update metadata on-demand with pagination support.
    /// Uses a 5-minute cache for the first page to avoid redundant queries.
    /// Call this method only when displaying the full update list.
    /// </summary>
    /// <param name="settings">Current application settings (SQL instance).</param>
    /// <param name="pageNumber">Page number to fetch (1-based).</param>
    /// <param name="pageSize">Number of items per page (default: 100).</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>Read-only list of update metadata for the requested page.</returns>
    Task<IReadOnlyList<UpdateInfo>> GetUpdatesAsync(
        AppSettings settings,
        int pageNumber = 1,
        int pageSize = 100,
        CancellationToken ct = default);

    /// <summary>
    /// Invalidates the update metadata cache, forcing the next GetUpdatesAsync call
    /// to fetch fresh data from the database. Call this after operations that
    /// modify update metadata (e.g., approval changes, cleanup operations).
    /// </summary>
    void InvalidateUpdateCache();
}
