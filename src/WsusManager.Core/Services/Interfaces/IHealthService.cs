using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Orchestrates the full diagnostics pipeline. Runs all health checks sequentially,
/// streams each result to the progress reporter in real time, and automatically
/// attempts repairs for fixable issues. Returns a complete DiagnosticReport.
/// </summary>
public interface IHealthService
{
    /// <summary>
    /// Runs all 12 health checks sequentially with auto-repair for fixable issues.
    /// Each check result is streamed to <paramref name="progress"/> as it completes.
    /// </summary>
    /// <param name="contentPath">WSUS content directory path (e.g., C:\WSUS).</param>
    /// <param name="sqlInstance">SQL Server instance name (e.g., localhost\SQLEXPRESS).</param>
    /// <param name="progress">Progress reporter for real-time output lines.</param>
    /// <param name="ct">Cancellation token — stops the pipeline on cancellation.</param>
    /// <returns>Complete diagnostic report with all check results and summary statistics.</returns>
    Task<DiagnosticReport> RunDiagnosticsAsync(
        string contentPath,
        string sqlInstance,
        IProgress<string> progress,
        CancellationToken ct = default);
}
