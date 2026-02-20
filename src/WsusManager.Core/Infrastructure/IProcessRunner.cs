using WsusManager.Core.Models;

namespace WsusManager.Core.Infrastructure;

/// <summary>
/// Interface for external process execution. All shell commands (wsusutil,
/// netsh, sc, schtasks, etc.) go through this interface for testability.
/// </summary>
public interface IProcessRunner
{
    /// <summary>
    /// Runs an external process with captured stdout/stderr.
    /// </summary>
    /// <param name="executable">Path to the executable.</param>
    /// <param name="arguments">Command-line arguments.</param>
    /// <param name="progress">Optional progress reporter for real-time output.</param>
    /// <param name="ct">Cancellation token — kills the process on cancellation.</param>
    /// <returns>Process result with exit code and captured output.</returns>
    Task<ProcessResult> RunAsync(
        string executable,
        string arguments,
        IProgress<string>? progress = null,
        CancellationToken ct = default);
}
