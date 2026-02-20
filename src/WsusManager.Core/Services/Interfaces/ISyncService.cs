using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Orchestrates the full Online Sync workflow using IWsusServerService.
/// Three profiles match legacy PowerShell behavior:
/// - Full Sync: synchronize -> decline -> approve -> monitor downloads
/// - Quick Sync: synchronize -> approve (skip decline)
/// - Sync Only: synchronize metadata only
/// </summary>
public interface ISyncService
{
    /// <summary>
    /// Runs the sync workflow based on the selected profile.
    /// </summary>
    /// <param name="profile">Sync profile determining which steps to run.</param>
    /// <param name="maxAutoApproveCount">Safety threshold for auto-approval (default 200).</param>
    /// <param name="progress">Progress reporter for log output.</param>
    /// <param name="ct">Cancellation token.</param>
    Task<OperationResult> RunSyncAsync(
        SyncProfile profile,
        int maxAutoApproveCount,
        IProgress<string> progress,
        CancellationToken ct);
}
