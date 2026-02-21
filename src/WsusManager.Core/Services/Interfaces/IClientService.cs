using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Provides client machine management operations for WSUS-managed endpoints.
/// All remote operations use WinRM (Invoke-Command) to execute PowerShell on the target host.
/// If WinRM is unavailable, callers should direct users to the Script Generator in Phase 15.
/// </summary>
public interface IClientService
{
    /// <summary>
    /// Cancels stuck Windows Update background jobs on the remote host by stopping
    /// wuauserv, clearing the job queue, and restarting the service.
    /// </summary>
    /// <param name="hostname">Target computer name or IP address.</param>
    /// <param name="progress">Progress reporter for real-time output lines.</param>
    /// <param name="ct">Cancellation token — stops the operation on cancellation.</param>
    /// <returns>Operation result indicating success or failure with detail.</returns>
    Task<OperationResult> CancelStuckJobsAsync(
        string hostname,
        IProgress<string> progress,
        CancellationToken ct = default);

    /// <summary>
    /// Forces the Windows Update client on the remote host to check in with the
    /// configured WSUS server immediately (wuauclt /detectnow + usoclient StartScan).
    /// </summary>
    /// <param name="hostname">Target computer name or IP address.</param>
    /// <param name="progress">Progress reporter for real-time output lines.</param>
    /// <param name="ct">Cancellation token — stops the operation on cancellation.</param>
    /// <returns>Operation result indicating success or failure with detail.</returns>
    Task<OperationResult> ForceCheckInAsync(
        string hostname,
        IProgress<string> progress,
        CancellationToken ct = default);

    /// <summary>
    /// Tests whether the remote host can reach the WSUS server on ports 8530 and 8531,
    /// measuring round-trip latency.
    /// </summary>
    /// <param name="hostname">Target computer name or IP address.</param>
    /// <param name="wsusServerUrl">WSUS server URL (e.g., http://wsus-server:8530).</param>
    /// <param name="progress">Progress reporter for real-time output lines.</param>
    /// <param name="ct">Cancellation token — stops the operation on cancellation.</param>
    /// <returns>Operation result with connectivity details (port reachability, latency).</returns>
    Task<OperationResult<ConnectivityTestResult>> TestConnectivityAsync(
        string hostname,
        string wsusServerUrl,
        IProgress<string> progress,
        CancellationToken ct = default);

    /// <summary>
    /// Runs a comprehensive diagnostics pass on the remote host: reads WSUS registry
    /// settings, checks service states, last check-in time, pending reboot flag,
    /// and Windows Update Agent version.
    /// </summary>
    /// <param name="hostname">Target computer name or IP address.</param>
    /// <param name="progress">Progress reporter for real-time output lines.</param>
    /// <param name="ct">Cancellation token — stops the operation on cancellation.</param>
    /// <returns>Operation result with full diagnostic snapshot from the remote host.</returns>
    Task<OperationResult<ClientDiagnosticResult>> RunDiagnosticsAsync(
        string hostname,
        IProgress<string> progress,
        CancellationToken ct = default);

    /// <summary>
    /// Looks up a WSUS/Windows Update error code and returns a human-readable
    /// description with a recommended fix. This is a local dictionary lookup —
    /// no remote call is made.
    /// </summary>
    /// <param name="errorCode">Hex code (e.g., "0x80244010") or decimal string.</param>
    /// <returns>Operation result with error info, or a failed result if unknown.</returns>
    OperationResult<WsusErrorInfo> LookupErrorCode(string errorCode);

    /// <summary>
    /// Runs ForceCheckInAsync sequentially across multiple hosts, reporting per-host
    /// pass/fail results. Processes are run one at a time (not parallel) to avoid
    /// overloading WinRM connections.
    /// </summary>
    /// <param name="hostnames">List of target hostnames or IP addresses.</param>
    /// <param name="progress">Progress reporter for real-time per-host output lines.</param>
    /// <param name="ct">Cancellation token — stops processing remaining hosts on cancellation.</param>
    /// <returns>
    /// Ok if all hosts succeeded; Fail if any host failed (but all reachable hosts are still processed).
    /// The message includes a summary: "{passed}/{total} hosts succeeded, {failed} failed."
    /// </returns>
    Task<OperationResult> MassForceCheckInAsync(
        IReadOnlyList<string> hostnames,
        IProgress<string> progress,
        CancellationToken ct = default);
}
