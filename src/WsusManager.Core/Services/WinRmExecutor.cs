using System.Text.RegularExpressions;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;

namespace WsusManager.Core.Services;

/// <summary>
/// Executes PowerShell commands on remote hosts using WinRM (Invoke-Command).
/// Delegates to <see cref="IProcessRunner"/> to invoke powershell.exe.
///
/// <para><b>WinRM availability note:</b> WinRM is not guaranteed to be enabled on target
/// hosts, especially in locked-down environments. Every method returns a graceful error
/// result if the connection fails rather than throwing. Callers should direct users to
/// the Script Generator (Phase 15) when WinRM is unavailable.</para>
/// </summary>
public class WinRmExecutor
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _log;

    /// <summary>
    /// Regex that validates a hostname: letters, digits, hyphens, and dots only.
    /// Prevents command-injection via maliciously crafted hostnames.
    /// </summary>
    private static readonly Regex _hostnameRegex =
        new(@"^[A-Za-z0-9.\-]+$", RegexOptions.Compiled);

    /// <summary>
    /// Initialises a new <see cref="WinRmExecutor"/>.
    /// </summary>
    /// <param name="processRunner">Process runner used to invoke powershell.exe.</param>
    /// <param name="logService">Application log service.</param>
    public WinRmExecutor(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner ?? throw new ArgumentNullException(nameof(processRunner));
        _log = logService ?? throw new ArgumentNullException(nameof(logService));
    }

    /// <summary>
    /// Executes a PowerShell script block on a remote host via WinRM (Invoke-Command).
    /// </summary>
    /// <param name="hostname">Target computer name or IP address.</param>
    /// <param name="scriptBlock">
    /// PowerShell code to run inside the remote script block.
    /// Must not contain single-quote characters that would break the outer argument string.
    /// Use double-quoted strings or escape as needed.
    /// </param>
    /// <param name="progress">Optional progress reporter for real-time output lines.</param>
    /// <param name="ct">Cancellation token — kills the process on cancellation.</param>
    /// <returns>
    /// <see cref="ProcessResult"/> from the powershell.exe process. If hostname validation
    /// fails, returns a failed result (ExitCode -1) without launching a process.
    /// </returns>
    public async Task<ProcessResult> ExecuteRemoteAsync(
        string hostname,
        string scriptBlock,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        var validationError = ValidateHostname(hostname);
        if (validationError != null)
        {
            _log.Warning("WinRmExecutor: invalid hostname rejected: {Hostname}", hostname);
            progress?.Report($"[FAIL] {validationError}");
            return new ProcessResult(-1, new[] { validationError });
        }

        // Log the intent without the full script block to keep logs concise
        _log.Debug(
            "WinRmExecutor: executing remote command on {Hostname} (script: {ScriptSummary})",
            hostname,
            SummarizeScript(scriptBlock));

        var arguments = $"-NoProfile -NonInteractive -Command " +
                        $"\"Invoke-Command -ComputerName '{hostname}' " +
                        $"-ScriptBlock {{ {scriptBlock} }} -ErrorAction Stop\"";

        var result = await _processRunner.RunAsync("powershell.exe", arguments, progress, ct)
            .ConfigureAwait(false);

        if (!result.Success)
        {
            var isWinRmError = IsWinRmConnectivityError(result.Output);
            if (isWinRmError)
            {
                _log.Warning(
                    "WinRmExecutor: WinRM not available on {Hostname} (exit code {ExitCode})",
                    hostname, result.ExitCode);

                var winRmMessage =
                    $"[FAIL] Cannot connect to {hostname} via WinRM. " +
                    $"Ensure WinRM is enabled on the target (run 'winrm quickconfig' on {hostname}) " +
                    $"or use the Script Generator in Phase 15 to create a deployment package " +
                    $"that does not require WinRM.";

                progress?.Report(winRmMessage);

                return new ProcessResult(result.ExitCode,
                    result.OutputLines.Concat(new[] { winRmMessage }).ToList());
            }

            _log.Warning(
                "WinRmExecutor: remote command failed on {Hostname} (exit code {ExitCode})",
                hostname, result.ExitCode);
        }

        return result;
    }

    /// <summary>
    /// Tests whether WinRM is available and responding on the target host.
    /// </summary>
    /// <param name="hostname">Target computer name or IP address.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns><c>true</c> if the host responds to Test-WSMan; otherwise <c>false</c>.</returns>
    public async Task<bool> TestWinRmAsync(string hostname, CancellationToken ct = default)
    {
        var validationError = ValidateHostname(hostname);
        if (validationError != null)
        {
            _log.Warning("WinRmExecutor: TestWinRmAsync — invalid hostname: {Hostname}", hostname);
            return false;
        }

        _log.Debug("WinRmExecutor: testing WinRM connectivity to {Hostname}", hostname);

        var arguments =
            $"-NoProfile -NonInteractive -Command " +
            $"\"Test-WSMan -ComputerName '{hostname}' -ErrorAction Stop\"";

        var result = await _processRunner.RunAsync("powershell.exe", arguments, null, ct)
            .ConfigureAwait(false);

        var available = result.Success;
        _log.Debug(
            "WinRmExecutor: WinRM on {Hostname} is {Status}",
            hostname,
            available ? "available" : "unavailable");

        return available;
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /// <summary>
    /// Validates the hostname to prevent command injection.
    /// Returns null if valid; an error message string if invalid.
    /// </summary>
    private static string? ValidateHostname(string? hostname)
    {
        if (string.IsNullOrWhiteSpace(hostname))
            return "Hostname must not be empty.";

        if (!_hostnameRegex.IsMatch(hostname))
            return $"Invalid hostname '{hostname}': only letters, digits, hyphens, and dots are allowed.";

        if (hostname.Length > 253)
            return $"Hostname '{hostname}' exceeds the maximum length of 253 characters.";

        return null;
    }

    /// <summary>
    /// Returns a brief summary of the script block for log entries (first 80 chars).
    /// </summary>
    private static string SummarizeScript(string scriptBlock)
    {
        if (string.IsNullOrWhiteSpace(scriptBlock))
            return "(empty)";

        var singleLine = scriptBlock.Replace(Environment.NewLine, " ").Trim();
        return singleLine.Length <= 80 ? singleLine : singleLine[..80] + "...";
    }

    /// <summary>
    /// Checks whether the process output indicates a WinRM connectivity failure
    /// as opposed to a remote script execution error.
    /// </summary>
    private static bool IsWinRmConnectivityError(string output)
    {
        if (string.IsNullOrEmpty(output))
            return false;

        // Common WinRM connection-refused / unreachable patterns
        return output.Contains("WinRM", StringComparison.OrdinalIgnoreCase)
            || output.Contains("WSManFault", StringComparison.OrdinalIgnoreCase)
            || output.Contains("cannot connect to the destination specified", StringComparison.OrdinalIgnoreCase)
            || output.Contains("The WinRM client cannot complete the operation", StringComparison.OrdinalIgnoreCase)
            || output.Contains("Access is denied", StringComparison.OrdinalIgnoreCase)
            || output.Contains("No connection could be made", StringComparison.OrdinalIgnoreCase)
            || output.Contains("0x803380E4", StringComparison.OrdinalIgnoreCase)
            || output.Contains("Connecting to remote server", StringComparison.OrdinalIgnoreCase);
    }
}
