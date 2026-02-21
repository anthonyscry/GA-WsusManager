using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Orchestrates the full 6-step WSUS deep cleanup pipeline.
/// Steps match the PowerShell WsusDatabase.psm1 implementation:
///   1. WSUS built-in cleanup (Invoke-WsusServerCleanup via PowerShell)
///   2. Remove supersession records for declined updates
///   3. Remove supersession records for superseded updates (10k batches)
///   4. Delete declined updates via spDeleteUpdate (100/batch)
///   5. Rebuild fragmented indexes + update statistics
///   6. Shrink database (3 retries on backup-block).
/// </summary>
public interface IDeepCleanupService
{
    /// <summary>
    /// Runs the full 6-step deep cleanup pipeline.
    /// Each step reports progress in format: [Step N/6] Step Name... done (Xs)
    /// DB size is captured before step 1 and after step 6 for before/after comparison.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance (e.g., "localhost\SQLEXPRESS").</param>
    /// <param name="progress">Progress reporter for real-time status lines.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>OperationResult indicating success or failure.</returns>
    Task<OperationResult> RunAsync(
        string sqlInstance,
        IProgress<string> progress,
        CancellationToken ct);
}
