using System.Text.RegularExpressions;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Implements remote WSUS client management operations via WinRM.
/// All remote operations check WinRM availability before executing and
/// return clear failure messages when the target is unreachable.
/// </summary>
public class ClientService : IClientService
{
    private readonly WinRmExecutor _executor;
    private readonly ILogService _log;

    /// <summary>
    /// Regex to extract the hostname portion from a URL like http://wsus-server:8530.
    /// Captures everything between the scheme and an optional port/path.
    /// </summary>
    private static readonly Regex _urlHostRegex =
        new(@"^(?:https?://)?([A-Za-z0-9.\-]+)(?::\d+)?(?:/.*)?$",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>
    /// Initialises a new <see cref="ClientService"/>.
    /// </summary>
    /// <param name="executor">WinRM executor for remote PowerShell commands.</param>
    /// <param name="logService">Application log service.</param>
    public ClientService(WinRmExecutor executor, ILogService logService)
    {
        _executor = executor ?? throw new ArgumentNullException(nameof(executor));
        _log = logService ?? throw new ArgumentNullException(nameof(logService));
    }

    // -------------------------------------------------------------------------
    // IClientService implementation
    // -------------------------------------------------------------------------

    /// <inheritdoc />
    public async Task<OperationResult> CancelStuckJobsAsync(
        string hostname,
        IProgress<string> progress,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(hostname))
            return OperationResult.Fail("Hostname must not be empty.");

        _log.Info("ClientService.CancelStuckJobsAsync: starting on {Hostname}", hostname);
        progress.Report($"Cancelling stuck Windows Update jobs on {hostname}...");

        // Check WinRM availability first
        progress.Report("[Step 1/3] Checking WinRM connectivity...");
        if (!await _executor.TestWinRmAsync(hostname, ct).ConfigureAwait(false))
        {
            var msg = BuildWinRmUnavailableMessage(hostname);
            progress.Report(msg);
            _log.Warning("ClientService.CancelStuckJobsAsync: WinRM unavailable on {Hostname}", hostname);
            return OperationResult.Fail(msg);
        }
        progress.Report("[OK] WinRM is available.");

        // Single round-trip script block: stop, clear, restart
        const string scriptBlock = @"
$ErrorActionPreference = 'SilentlyContinue'
Write-Output 'STEP=StopServices'
Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
Write-Output 'STEP=ClearCache'
Remove-Item 'C:\Windows\SoftwareDistribution\*' -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'STEP=RestartServices'
$ErrorActionPreference = 'Stop'
Start-Service bits, wuauserv -ErrorAction Stop
Write-Output 'STEP=Done'
";

        progress.Report("[Step 2/3] Stopping services and clearing SoftwareDistribution cache...");
        var result = await _executor.ExecuteRemoteAsync(hostname, scriptBlock, progress, ct)
            .ConfigureAwait(false);

        if (!result.Success)
        {
            var msg = $"Operation failed on {hostname}: {result.Output}";
            _log.Warning("ClientService.CancelStuckJobsAsync: failed on {Hostname}: {Output}",
                hostname, result.Output);
            return OperationResult.Fail(msg);
        }

        progress.Report("[Step 3/3] Verifying services restarted...");
        // Parse step markers from output for informative progress
        foreach (var line in result.OutputLines)
        {
            if (line.Contains("STEP=StopServices"))
                progress.Report("  Stopped wuauserv and bits services.");
            else if (line.Contains("STEP=ClearCache"))
                progress.Report("  Cleared SoftwareDistribution cache.");
            else if (line.Contains("STEP=RestartServices"))
                progress.Report("  Restarted bits and wuauserv services.");
        }

        progress.Report($"[OK] Stuck jobs cancelled successfully on {hostname}.");
        _log.Info("ClientService.CancelStuckJobsAsync: completed on {Hostname}", hostname);
        return OperationResult.Ok($"Stuck Windows Update jobs cancelled on {hostname}.");
    }

    /// <inheritdoc />
    public async Task<OperationResult> ForceCheckInAsync(
        string hostname,
        IProgress<string> progress,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(hostname))
            return OperationResult.Fail("Hostname must not be empty.");

        _log.Info("ClientService.ForceCheckInAsync: starting on {Hostname}", hostname);
        progress.Report($"Forcing WSUS check-in on {hostname}...");

        // Step 1/4: Check WinRM
        progress.Report($"[Step 1/4] Checking WinRM connectivity to {hostname}...");
        if (!await _executor.TestWinRmAsync(hostname, ct).ConfigureAwait(false))
        {
            var msg = BuildWinRmUnavailableMessage(hostname);
            progress.Report(msg);
            _log.Warning("ClientService.ForceCheckInAsync: WinRM unavailable on {Hostname}", hostname);
            return OperationResult.Fail(msg);
        }
        progress.Report("[OK] WinRM is available.");

        // Single round-trip script block: 4 steps
        const string scriptBlock = @"
Write-Output 'STEP=GpUpdate'
gpupdate /force | Out-Null
Write-Output 'STEP=ResetAuth'
wuauclt /resetauthorization
Write-Output 'STEP=DetectNow'
wuauclt /detectnow
Write-Output 'STEP=ReportNow'
wuauclt /reportnow
Write-Output 'STEP=Done'
";

        progress.Report($"[Step 2/4] Running gpupdate /force on {hostname}...");
        var result = await _executor.ExecuteRemoteAsync(hostname, scriptBlock, null, ct)
            .ConfigureAwait(false);

        if (!result.Success)
        {
            var msg = $"Force check-in failed on {hostname}: {result.Output}";
            _log.Warning("ClientService.ForceCheckInAsync: failed on {Hostname}: {Output}",
                hostname, result.Output);
            return OperationResult.Fail(msg);
        }

        // Report step completion based on output markers
        foreach (var line in result.OutputLines)
        {
            if (line.Contains("STEP=GpUpdate"))
                progress.Report("[Step 2/4] Group Policy updated.");
            else if (line.Contains("STEP=ResetAuth"))
                progress.Report("[Step 3/4] Running wuauclt /resetauthorization...");
            else if (line.Contains("STEP=DetectNow"))
                progress.Report("[Step 3/4] Reset WSUS client identity.");
            else if (line.Contains("STEP=ReportNow"))
                progress.Report("[Step 4/4] Running wuauclt /detectnow and /reportnow...");
            else if (line.Contains("STEP=Done"))
                progress.Report("[Step 4/4] Detection and reporting triggered.");
        }

        progress.Report($"[OK] Force check-in completed on {hostname}. Detection and reporting may take several minutes to complete.");
        _log.Info("ClientService.ForceCheckInAsync: completed on {Hostname}", hostname);
        return OperationResult.Ok($"Force check-in initiated on {hostname}.");
    }

    /// <inheritdoc />
    public async Task<OperationResult<ConnectivityTestResult>> TestConnectivityAsync(
        string hostname,
        string wsusServerUrl,
        IProgress<string> progress,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(hostname))
            return OperationResult<ConnectivityTestResult>.Fail("Hostname must not be empty.");

        var wsusServer = ExtractHostname(wsusServerUrl);
        if (string.IsNullOrWhiteSpace(wsusServer))
            return OperationResult<ConnectivityTestResult>.Fail(
                $"Cannot extract hostname from WSUS server URL: '{wsusServerUrl}'");

        _log.Info("ClientService.TestConnectivityAsync: testing from {Hostname} to {WsusServer}",
            hostname, wsusServer);
        progress.Report($"Testing connectivity from {hostname} to WSUS server {wsusServer}...");

        // Check WinRM first
        progress.Report($"[Step 1/2] Checking WinRM connectivity to {hostname}...");
        if (!await _executor.TestWinRmAsync(hostname, ct).ConfigureAwait(false))
        {
            var msg = BuildWinRmUnavailableMessage(hostname);
            progress.Report(msg);
            _log.Warning("ClientService.TestConnectivityAsync: WinRM unavailable on {Hostname}", hostname);
            return OperationResult<ConnectivityTestResult>.Fail(msg);
        }
        progress.Report("[OK] WinRM is available.");

        // Test TCP ports 8530 and 8531 from the remote host
        var scriptBlock = $@"
$server = '{wsusServer}'
$r8530 = Test-NetConnection -ComputerName $server -Port 8530 -WarningAction SilentlyContinue
$r8531 = Test-NetConnection -ComputerName $server -Port 8531 -WarningAction SilentlyContinue
""PORT8530=$($r8530.TcpTestSucceeded);PORT8531=$($r8531.TcpTestSucceeded);LATENCY=$($r8530.PingReplyDetails.RoundtripTime)""
";

        progress.Report($"[Step 2/2] Testing TCP ports 8530 and 8531 from {hostname} to {wsusServer}...");
        var result = await _executor.ExecuteRemoteAsync(hostname, scriptBlock, null, ct)
            .ConfigureAwait(false);

        if (!result.Success)
        {
            var msg = $"Connectivity test failed on {hostname}: {result.Output}";
            _log.Warning("ClientService.TestConnectivityAsync: failed on {Hostname}: {Output}",
                hostname, result.Output);
            return OperationResult<ConnectivityTestResult>.Fail(msg);
        }

        // Parse the KEY=VALUE output line
        var connectivityResult = ParseConnectivityOutput(result.OutputLines);

        // Report results with clear pass/fail formatting
        progress.Report($"  Port 8530 (HTTP):  {(connectivityResult.Port8530Reachable ? "[PASS]" : "[FAIL]")}");
        progress.Report($"  Port 8531 (HTTPS): {(connectivityResult.Port8531Reachable ? "[PASS]" : "[FAIL]")}");
        progress.Report($"  Latency: {(connectivityResult.LatencyMs >= 0 ? $"{connectivityResult.LatencyMs} ms" : "N/A")}");

        var summary = connectivityResult.Port8530Reachable || connectivityResult.Port8531Reachable
            ? $"[OK] Connectivity test passed — at least one WSUS port is reachable from {hostname}."
            : $"[WARN] Connectivity test completed — neither port 8530 nor 8531 is reachable from {hostname} to {wsusServer}.";
        progress.Report(summary);

        _log.Info(
            "ClientService.TestConnectivityAsync: {Hostname} → {WsusServer}: 8530={P8530}, 8531={P8531}, latency={Latency}ms",
            hostname, wsusServer,
            connectivityResult.Port8530Reachable,
            connectivityResult.Port8531Reachable,
            connectivityResult.LatencyMs);

        return OperationResult<ConnectivityTestResult>.Ok(connectivityResult, summary);
    }

    /// <inheritdoc />
    public async Task<OperationResult<ClientDiagnosticResult>> RunDiagnosticsAsync(
        string hostname,
        IProgress<string> progress,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(hostname))
            return OperationResult<ClientDiagnosticResult>.Fail("Hostname must not be empty.");

        _log.Info("ClientService.RunDiagnosticsAsync: starting on {Hostname}", hostname);
        progress.Report($"Running WSUS diagnostics on {hostname}...");

        // Check WinRM first
        progress.Report($"[Step 1/2] Checking WinRM connectivity to {hostname}...");
        if (!await _executor.TestWinRmAsync(hostname, ct).ConfigureAwait(false))
        {
            var msg = BuildWinRmUnavailableMessage(hostname);
            progress.Report(msg);
            _log.Warning("ClientService.RunDiagnosticsAsync: WinRM unavailable on {Hostname}", hostname);
            return OperationResult<ClientDiagnosticResult>.Fail(msg);
        }
        progress.Report("[OK] WinRM is available.");

        // Gather all diagnostics in a single round trip
        const string scriptBlock = @"
$wu  = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -EA SilentlyContinue
$au  = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -EA SilentlyContinue
$svcs = Get-Service wuauserv, bits, cryptsvc -EA SilentlyContinue | ForEach-Object { ""$($_.Name)=$($_.Status)"" }
$reboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$lastReport = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name LastWUStatusReportTime -EA SilentlyContinue).LastWUStatusReportTime
$agent = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name AgentVersion -EA SilentlyContinue).AgentVersion
""WSUS=$($wu.WUServer);STATUS=$($wu.WUStatusServer);USE=$($au.UseWUServer);SVCS=$($svcs -join ',');REBOOT=$reboot;LASTCHECKIN=$lastReport;AGENT=$agent""
";

        progress.Report($"[Step 2/2] Gathering WSUS registry settings, service status, and agent info from {hostname}...");
        var result = await _executor.ExecuteRemoteAsync(hostname, scriptBlock, null, ct)
            .ConfigureAwait(false);

        if (!result.Success)
        {
            var msg = $"Diagnostics failed on {hostname}: {result.Output}";
            _log.Warning("ClientService.RunDiagnosticsAsync: failed on {Hostname}: {Output}",
                hostname, result.Output);
            return OperationResult<ClientDiagnosticResult>.Fail(msg);
        }

        // Parse output into ClientDiagnosticResult
        var diagnostics = ParseDiagnosticsOutput(result.OutputLines);

        // Report each field clearly
        progress.Report("");
        progress.Report($"--- WSUS Diagnostics: {hostname} ---");
        progress.Report($"  WSUS Server:       {diagnostics.WsusServerUrl ?? "(not configured)"}");
        progress.Report($"  Status Server:     {diagnostics.WsusStatusServerUrl ?? "(not configured)"}");
        progress.Report($"  UseWUServer:       {(diagnostics.UseWUServer ? "Yes" : "No")}");
        progress.Report($"  Pending Reboot:    {(diagnostics.PendingRebootRequired ? "YES (reboot required)" : "No")}");
        progress.Report($"  Last Check-in:     {(diagnostics.LastCheckInTime.HasValue ? diagnostics.LastCheckInTime.Value.ToString("yyyy-MM-dd HH:mm:ss") : "(never)")}");
        progress.Report($"  WUA Version:       {diagnostics.WindowsUpdateAgentVersion ?? "(unknown)"}");

        if (diagnostics.ServiceStatuses.Count > 0)
        {
            progress.Report("  Services:");
            foreach (var (svc, status) in diagnostics.ServiceStatuses)
                progress.Report($"    {svc,-12} {status}");
        }

        progress.Report($"--- End Diagnostics ---");

        _log.Info("ClientService.RunDiagnosticsAsync: completed on {Hostname}: WSUS={WsusUrl}, UseWUS={UseWus}, Reboot={Reboot}",
            hostname, diagnostics.WsusServerUrl ?? "(none)", diagnostics.UseWUServer, diagnostics.PendingRebootRequired);

        return OperationResult<ClientDiagnosticResult>.Ok(
            diagnostics,
            $"Diagnostics completed for {hostname}.");
    }

    /// <inheritdoc />
    public OperationResult<WsusErrorInfo> LookupErrorCode(string errorCode)
    {
        var info = WsusErrorCodes.Lookup(errorCode);

        if (info == null)
        {
            _log.Debug("ClientService.LookupErrorCode: unknown code '{ErrorCode}'", errorCode);
            return OperationResult<WsusErrorInfo>.Fail(
                $"Error code '{errorCode}' was not found in the WSUS error dictionary. " +
                "Check the Microsoft documentation or Windows Event Log for details.");
        }

        _log.Debug("ClientService.LookupErrorCode: found '{ErrorCode}' → {Description}",
            errorCode, info.Description);

        return OperationResult<WsusErrorInfo>.Ok(info, $"Found error code {info.Code}.");
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /// <summary>
    /// Extracts the hostname component from a URL string.
    /// Returns null if the URL is empty or cannot be parsed.
    /// </summary>
    internal static string? ExtractHostname(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
            return null;

        var match = _urlHostRegex.Match(url.Trim());
        return match.Success ? match.Groups[1].Value : null;
    }

    /// <summary>
    /// Builds the standard WinRM-unavailable error message for a host.
    /// </summary>
    private static string BuildWinRmUnavailableMessage(string hostname) =>
        $"[FAIL] Cannot connect to {hostname} via WinRM. " +
        $"Ensure WinRM is enabled on the target host (run 'winrm quickconfig' on {hostname}), " +
        "or use the Script Generator to create a deployment package that does not require WinRM.";

    /// <summary>
    /// Parses connectivity test output lines into a <see cref="ConnectivityTestResult"/>.
    /// Expects a line in the format: PORT8530=True;PORT8531=False;LATENCY=5
    /// </summary>
    private static ConnectivityTestResult ParseConnectivityOutput(IReadOnlyList<string> lines)
    {
        foreach (var line in lines)
        {
            if (!line.Contains("PORT8530="))
                continue;

            var kvp = ParseKeyValueLine(line);

            var port8530 = kvp.TryGetValue("PORT8530", out var p8530)
                && string.Equals(p8530, "True", StringComparison.OrdinalIgnoreCase);

            var port8531 = kvp.TryGetValue("PORT8531", out var p8531)
                && string.Equals(p8531, "True", StringComparison.OrdinalIgnoreCase);

            int latency = 0;
            if (kvp.TryGetValue("LATENCY", out var lat))
                int.TryParse(lat, out latency);

            return new ConnectivityTestResult
            {
                Port8530Reachable = port8530,
                Port8531Reachable = port8531,
                LatencyMs = latency
            };
        }

        // Return default (all false / zero) if parsing fails
        return new ConnectivityTestResult();
    }

    /// <summary>
    /// Parses diagnostics output lines into a <see cref="ClientDiagnosticResult"/>.
    /// Expects a line in the format: WSUS=http://...;STATUS=http://...;USE=1;SVCS=...;REBOOT=True;LASTCHECKIN=...;AGENT=...
    /// </summary>
    private static ClientDiagnosticResult ParseDiagnosticsOutput(IReadOnlyList<string> lines)
    {
        foreach (var line in lines)
        {
            if (!line.Contains("WSUS=") && !line.Contains("SVCS="))
                continue;

            var kvp = ParseKeyValueLine(line);

            // Parse service statuses: "wuauserv=Running,bits=Running,cryptsvc=Stopped"
            var serviceStatuses = new Dictionary<string, string>();
            if (kvp.TryGetValue("SVCS", out var svcsRaw) && !string.IsNullOrWhiteSpace(svcsRaw))
            {
                foreach (var svcPair in svcsRaw.Split(',', StringSplitOptions.RemoveEmptyEntries))
                {
                    var idx = svcPair.IndexOf('=');
                    if (idx > 0)
                        serviceStatuses[svcPair[..idx].Trim()] = svcPair[(idx + 1)..].Trim();
                }
            }

            // Parse UseWUServer (1 = true)
            bool useWuServer = kvp.TryGetValue("USE", out var useRaw)
                && (useRaw == "1"
                    || string.Equals(useRaw, "True", StringComparison.OrdinalIgnoreCase));

            // Parse pending reboot
            bool reboot = kvp.TryGetValue("REBOOT", out var rebootRaw)
                && string.Equals(rebootRaw, "True", StringComparison.OrdinalIgnoreCase);

            // Parse last check-in time (Windows registry stores as FileTime or FILETIME string)
            DateTime? lastCheckIn = null;
            if (kvp.TryGetValue("LASTCHECKIN", out var checkInRaw)
                && !string.IsNullOrWhiteSpace(checkInRaw)
                && checkInRaw != "$null")
            {
                // Try parsing as FileTime (long integer)
                if (long.TryParse(checkInRaw, out var fileTime) && fileTime > 0)
                {
                    try { lastCheckIn = DateTime.FromFileTimeUtc(fileTime); }
                    catch { /* ignore invalid file times */ }
                }
                // Try parsing as datetime string
                else if (DateTime.TryParse(checkInRaw, out var parsedDate))
                {
                    lastCheckIn = parsedDate.ToUniversalTime();
                }
            }

            return new ClientDiagnosticResult
            {
                WsusServerUrl = NullIfEmpty(kvp.TryGetValue("WSUS", out var wsus) ? wsus : null),
                WsusStatusServerUrl = NullIfEmpty(kvp.TryGetValue("STATUS", out var status) ? status : null),
                UseWUServer = useWuServer,
                ServiceStatuses = serviceStatuses,
                LastCheckInTime = lastCheckIn,
                PendingRebootRequired = reboot,
                WindowsUpdateAgentVersion = NullIfEmpty(kvp.TryGetValue("AGENT", out var agent) ? agent : null)
            };
        }

        // Return empty result if output could not be parsed
        return new ClientDiagnosticResult();
    }

    /// <summary>
    /// Parses a semicolon-delimited KEY=VALUE line into a dictionary.
    /// The first KEY= may be preceded by a quote (from PowerShell string output).
    /// </summary>
    private static Dictionary<string, string> ParseKeyValueLine(string line)
    {
        // Strip surrounding quotes that PowerShell may add
        line = line.Trim().Trim('"');

        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var segments = line.Split(';');

        foreach (var segment in segments)
        {
            var idx = segment.IndexOf('=');
            if (idx <= 0)
                continue;

            var key = segment[..idx].Trim();
            var value = segment[(idx + 1)..].Trim();
            result[key] = value;
        }

        return result;
    }

    /// <summary>Returns null if the string is null, empty, or the PowerShell "$null" literal.</summary>
    private static string? NullIfEmpty(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (value == "$null") return null;
        return value;
    }
}
