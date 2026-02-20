using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Service for connecting to and operating on the local WSUS server via the
/// Microsoft.UpdateServices.Administration managed API. The API assembly ships
/// with the WSUS role and is loaded at runtime via Assembly.LoadFrom to avoid
/// compile-time dependencies on machines without WSUS installed.
/// </summary>
public interface IWsusServerService
{
    /// <summary>
    /// Whether a WSUS server connection is currently active.
    /// </summary>
    bool IsConnected { get; }

    /// <summary>
    /// Loads the WSUS API assembly and connects to the local WSUS server on port 8530.
    /// Returns failure if the WSUS API DLL is not found or the connection fails.
    /// </summary>
    Task<OperationResult> ConnectAsync(CancellationToken ct = default);

    /// <summary>
    /// Triggers a WSUS synchronization and polls status/progress until complete or cancelled.
    /// Reports phase name and percentage via the progress reporter.
    /// Polling interval: 5 seconds. Max iterations: 720 (60 minutes timeout).
    /// </summary>
    Task<OperationResult> StartSynchronizationAsync(IProgress<string>? progress, CancellationToken ct);

    /// <summary>
    /// Gets information about the last synchronization run.
    /// </summary>
    Task<OperationResult<SyncResult>> GetLastSyncInfoAsync(CancellationToken ct = default);

    /// <summary>
    /// Declines expired, superseded, and old (>6 months) updates.
    /// Returns the count of updates declined.
    /// </summary>
    Task<OperationResult<int>> DeclineUpdatesAsync(IProgress<string>? progress, CancellationToken ct);

    /// <summary>
    /// Auto-approves pending updates matching approved classifications against
    /// the "All Computers" target group. Approved classifications: Critical Updates,
    /// Security Updates, Update Rollups, Service Packs, Updates, Definition Updates.
    /// Upgrades are never auto-approved. Preview and Beta titles are excluded.
    /// Safety threshold blocks approval if count exceeds maxCount.
    /// Returns the count of updates approved.
    /// </summary>
    Task<OperationResult<int>> ApproveUpdatesAsync(int maxCount, IProgress<string>? progress, CancellationToken ct);
}
