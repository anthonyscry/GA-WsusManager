using System.Text;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Generates self-contained PowerShell scripts for WSUS client operations.
/// Each generated script:
/// - Requires administrator privileges (#Requires -RunAsAdministrator)
/// - Is fully self-contained with no module imports or external dependencies
/// - Uses Write-Host with colours for readable output
/// - Ends with a "Press Enter" pause so the admin can read results
/// </summary>
public class ScriptGeneratorService : IScriptGeneratorService
{
    // -------------------------------------------------------------------------
    // Operation display names (shown in UI) and their internal keys
    // -------------------------------------------------------------------------

    private static readonly string[] DisplayNames =
    [
        "Cancel Stuck Jobs",
        "Force Check-In",
        "Test Connectivity",
        "Run Diagnostics",
        "Mass GPUpdate",
    ];

    private static readonly Dictionary<string, string> DisplayToKey =
        new(StringComparer.OrdinalIgnoreCase)
        {
            { "Cancel Stuck Jobs",  "CancelStuckJobs"   },
            { "Force Check-In",     "ForceCheckIn"      },
            { "Test Connectivity",  "TestConnectivity"  },
            { "Run Diagnostics",    "RunDiagnostics"    },
            { "Mass GPUpdate",      "MassGpUpdate"      },
        };

    // Reverse map: internal key → display name (for header generation)
    private static readonly Dictionary<string, string> KeyToDisplay =
        new(StringComparer.OrdinalIgnoreCase)
        {
            { "CancelStuckJobs",   "Cancel Stuck Jobs"  },
            { "ForceCheckIn",      "Force Check-In"     },
            { "TestConnectivity",  "Test Connectivity"  },
            { "RunDiagnostics",    "Run Diagnostics"    },
            { "MassGpUpdate",      "Mass GPUpdate"      },
        };

    // -------------------------------------------------------------------------
    // IScriptGeneratorService
    // -------------------------------------------------------------------------

    /// <inheritdoc />
    public IReadOnlyList<string> GetAvailableOperations() => DisplayNames;

    /// <inheritdoc />
    public string GenerateScript(
        string operationType,
        string? wsusServerUrl = null,
        IReadOnlyList<string>? hostnames = null)
    {
        if (string.IsNullOrWhiteSpace(operationType))
            throw new ArgumentException("Operation type must not be empty.", nameof(operationType));

        // Normalise display name → internal key
        var key = NormaliseKey(operationType);

        return key switch
        {
            "CancelStuckJobs"  => BuildCancelStuckJobsScript(),
            "ForceCheckIn"     => BuildForceCheckInScript(),
            "TestConnectivity" => BuildTestConnectivityScript(wsusServerUrl),
            "RunDiagnostics"   => BuildRunDiagnosticsScript(),
            "MassGpUpdate"     => BuildMassGpUpdateScript(hostnames),
            _ => throw new ArgumentException(
                $"Unknown operation type '{operationType}'. " +
                "Valid values: CancelStuckJobs, ForceCheckIn, TestConnectivity, RunDiagnostics, MassGpUpdate " +
                "(or their display names).",
                nameof(operationType))
        };
    }

    // -------------------------------------------------------------------------
    // Script builders — use @"..." verbatim strings to avoid C# interpolation
    // clashing with PowerShell $() expressions.
    // -------------------------------------------------------------------------

    private static string BuildCancelStuckJobsScript()
    {
        return ScriptHeader("CancelStuckJobs") + @"#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host ""=== Cancel Stuck Windows Update Jobs ==="" -ForegroundColor Cyan

try {
    Write-Host ""Stopping Windows Update service (wuauserv)..."" -ForegroundColor Yellow
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Write-Host ""[OK] wuauserv stopped."" -ForegroundColor Green

    Write-Host ""Stopping BITS service..."" -ForegroundColor Yellow
    Stop-Service bits -Force -ErrorAction SilentlyContinue
    Write-Host ""[OK] bits stopped."" -ForegroundColor Green

    Write-Host ""Clearing SoftwareDistribution cache..."" -ForegroundColor Yellow
    Remove-Item 'C:\Windows\SoftwareDistribution\*' -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ""[OK] SoftwareDistribution cache cleared."" -ForegroundColor Green

    Write-Host ""Starting BITS service..."" -ForegroundColor Yellow
    Start-Service bits -ErrorAction Stop
    Write-Host ""[OK] bits started."" -ForegroundColor Green

    Write-Host ""Starting Windows Update service..."" -ForegroundColor Yellow
    Start-Service wuauserv -ErrorAction Stop
    Write-Host ""[OK] wuauserv started."" -ForegroundColor Green

    Write-Host """"
    Write-Host ""--- Service Status ---"" -ForegroundColor Cyan
    $services = Get-Service wuauserv, bits -ErrorAction SilentlyContinue
    foreach ($svc in $services) {
        $color = if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' }
        Write-Host (""{0,-20} {1}"" -f $svc.Name, $svc.Status) -ForegroundColor $color
    }

    Write-Host """"
    Write-Host ""[SUCCESS] Stuck jobs cancelled. Windows Update services restarted."" -ForegroundColor Green
}
catch {
    Write-Host """"
    Write-Host ""[ERROR] $($_.Exception.Message)"" -ForegroundColor Red
    Write-Host ""Please investigate and retry."" -ForegroundColor Yellow
}

Write-Host """"
Write-Host ""Script complete. Press Enter to exit."" -ForegroundColor Cyan
Read-Host
";
    }

    private static string BuildForceCheckInScript()
    {
        return ScriptHeader("ForceCheckIn") + @"#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'

Write-Host """"
Write-Host ""=== Force WSUS Check-In ==="" -ForegroundColor Cyan

Write-Host ""Running gpupdate /force..."" -ForegroundColor Yellow
gpupdate /force | Out-Null
Write-Host ""[OK] Group Policy updated."" -ForegroundColor Green

Write-Host ""Running wuauclt /resetauthorization..."" -ForegroundColor Yellow
wuauclt /resetauthorization
Write-Host ""[OK] WSUS client authorisation reset."" -ForegroundColor Green

Write-Host ""Running wuauclt /detectnow..."" -ForegroundColor Yellow
wuauclt /detectnow
Write-Host ""[OK] Update detection triggered."" -ForegroundColor Green

Write-Host ""Running wuauclt /reportnow..."" -ForegroundColor Yellow
wuauclt /reportnow
Write-Host ""[OK] Status report triggered."" -ForegroundColor Green

# Try usoclient if available (Windows 10/Server 2016+)
$usoPath = ""$env:SystemRoot\System32\usoclient.exe""
if (Test-Path $usoPath) {
    Write-Host ""usoclient found — triggering StartScan..."" -ForegroundColor Yellow
    & $usoPath StartScan 2>$null
    Write-Host ""[OK] usoclient StartScan triggered."" -ForegroundColor Green
}
else {
    Write-Host ""usoclient not found (older OS) — skipping."" -ForegroundColor Yellow
}

Write-Host """"
Write-Host ""[SUCCESS] Force check-in commands sent."" -ForegroundColor Green
Write-Host ""Detection and reporting may take several minutes to complete."" -ForegroundColor Yellow
Write-Host ""Check the WSUS console in 5-10 minutes to confirm this host has checked in."" -ForegroundColor Yellow

Write-Host """"
Write-Host ""Script complete. Press Enter to exit."" -ForegroundColor Cyan
Read-Host
";
    }

    private static string BuildTestConnectivityScript(string? wsusServerUrl)
    {
        // Extract hostname from URL, or use placeholder if not provided
        var wsusServer = ExtractHostname(wsusServerUrl) ?? "WSUS-SERVER";

        // Build using string concatenation to safely inject the WSUS server name
        // without C# string interpolation clashing with PowerShell $() expressions.
        return ScriptHeader("TestConnectivity")
            + "#Requires -RunAsAdministrator" + Environment.NewLine
            + Environment.NewLine
            + "$WsusServer = \"" + wsusServer + "\"" + Environment.NewLine
            + Environment.NewLine
            + @"Write-Host """"
Write-Host ""=== WSUS Connectivity Test ==="" -ForegroundColor Cyan
Write-Host ""Target WSUS server: $WsusServer"" -ForegroundColor Yellow
Write-Host """"

# DNS resolution
Write-Host ""--- DNS Resolution ---"" -ForegroundColor Cyan
try {
    $resolved = [System.Net.Dns]::GetHostAddresses($WsusServer)
    Write-Host ""[PASS] DNS resolved '$WsusServer' to: $($resolved -join ', ')"" -ForegroundColor Green
}
catch {
    Write-Host ""[FAIL] DNS resolution failed for '$WsusServer': $($_.Exception.Message)"" -ForegroundColor Red
}

Write-Host """"
Write-Host ""--- TCP Port Tests ---"" -ForegroundColor Cyan

# Port 8530 (HTTP)
$r8530 = Test-NetConnection -ComputerName $WsusServer -Port 8530 -WarningAction SilentlyContinue
if ($r8530.TcpTestSucceeded) {
    $latency = if ($r8530.PingReplyDetails) { $r8530.PingReplyDetails.RoundtripTime } else { 'N/A' }
    Write-Host ""[PASS] Port 8530 (HTTP)  — reachable. Latency: $latency ms"" -ForegroundColor Green
}
else {
    Write-Host ""[FAIL] Port 8530 (HTTP)  — not reachable."" -ForegroundColor Red
}

# Port 8531 (HTTPS)
$r8531 = Test-NetConnection -ComputerName $WsusServer -Port 8531 -WarningAction SilentlyContinue
if ($r8531.TcpTestSucceeded) {
    Write-Host ""[PASS] Port 8531 (HTTPS) — reachable."" -ForegroundColor Green
}
else {
    Write-Host ""[WARN] Port 8531 (HTTPS) — not reachable (may be expected if HTTPS is not configured)."" -ForegroundColor Yellow
}

Write-Host """"
if ($r8530.TcpTestSucceeded -or $r8531.TcpTestSucceeded) {
    Write-Host ""[SUCCESS] At least one WSUS port is reachable."" -ForegroundColor Green
}
else {
    Write-Host ""[FAIL] Neither port 8530 nor 8531 is reachable from this machine."" -ForegroundColor Red
    Write-Host ""Possible causes:"" -ForegroundColor Yellow
    Write-Host ""  - Firewall blocking ports 8530/8531"" -ForegroundColor Yellow
    Write-Host ""  - WSUS server is offline or IIS is stopped"" -ForegroundColor Yellow
    Write-Host ""  - Incorrect WSUS server name in Group Policy"" -ForegroundColor Yellow
}

Write-Host """"
Write-Host ""Script complete. Press Enter to exit."" -ForegroundColor Cyan
Read-Host
";
    }

    private static string BuildRunDiagnosticsScript()
    {
        return ScriptHeader("RunDiagnostics") + @"#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'

Write-Host """"
Write-Host ""=== WSUS Client Diagnostics ==="" -ForegroundColor Cyan
Write-Host ""Computer: $env:COMPUTERNAME"" -ForegroundColor Yellow
Write-Host """"

# WSUS registry settings
Write-Host ""--- WSUS Registry Settings ---"" -ForegroundColor Cyan
$wuKey = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -EA SilentlyContinue
$auKey = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -EA SilentlyContinue

$wsusServer  = if ($wuKey.WUServer)       { $wuKey.WUServer }       else { ""(not configured)"" }
$wsusStatus  = if ($wuKey.WUStatusServer) { $wuKey.WUStatusServer } else { ""(not configured)"" }
$useWuServer = if ($auKey.UseWUServer -eq 1) { ""Yes (managed by WSUS)"" } else { ""No (using Windows Update)"" }

Write-Host (""{0,-25} {1}"" -f ""WUServer:"",       $wsusServer)  -ForegroundColor White
Write-Host (""{0,-25} {1}"" -f ""WUStatusServer:"", $wsusStatus)  -ForegroundColor White
Write-Host (""{0,-25} {1}"" -f ""UseWUServer:"",    $useWuServer) -ForegroundColor White

Write-Host """"
Write-Host ""--- Service Status ---"" -ForegroundColor Cyan
$serviceNames = @('wuauserv', 'bits', 'cryptsvc')
foreach ($name in $serviceNames) {
    $svc = Get-Service $name -EA SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' }
        Write-Host (""{0,-20} {1}"" -f $svc.Name, $svc.Status) -ForegroundColor $color
    }
    else {
        Write-Host (""{0,-20} Not found"" -f $name) -ForegroundColor Yellow
    }
}

Write-Host """"
Write-Host ""--- Pending Reboot ---"" -ForegroundColor Cyan
$rebootKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
if (Test-Path $rebootKey) {
    Write-Host ""  Pending reboot: YES — reboot required before updates will apply."" -ForegroundColor Red
}
else {
    Write-Host ""  Pending reboot: No"" -ForegroundColor Green
}

Write-Host """"
Write-Host ""--- Windows Update Agent Version ---"" -ForegroundColor Cyan
$agentKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -EA SilentlyContinue
$agentVer = if ($agentKey.AgentVersion) { $agentKey.AgentVersion } else { ""(unknown)"" }
Write-Host ""  WUA Version: $agentVer"" -ForegroundColor White

Write-Host """"
Write-Host ""--- Last Status Report Time ---"" -ForegroundColor Cyan
$lastReport = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name LastWUStatusReportTime -EA SilentlyContinue).LastWUStatusReportTime
if ($lastReport) {
    try {
        $dt = [DateTime]::FromFileTimeUtc($lastReport)
        Write-Host ""  Last check-in: $($dt.ToString('yyyy-MM-dd HH:mm:ss')) UTC"" -ForegroundColor White
    }
    catch {
        Write-Host ""  Last check-in: $lastReport (raw)"" -ForegroundColor White
    }
}
else {
    Write-Host ""  Last check-in: (never)"" -ForegroundColor Yellow
}

Write-Host """"
Write-Host ""[SUCCESS] Diagnostics complete."" -ForegroundColor Green

Write-Host """"
Write-Host ""Script complete. Press Enter to exit."" -ForegroundColor Cyan
Read-Host
";
    }

    private static string BuildMassGpUpdateScript(IReadOnlyList<string>? hostnames)
    {
        var hostnamesBlock = BuildHostnamesBlock(hostnames);

        return ScriptHeader("MassGpUpdate")
            + "#Requires -RunAsAdministrator" + Environment.NewLine
            + Environment.NewLine
            + "# -----------------------------------------------------------------------" + Environment.NewLine
            + "# Hostname list — edit this array before running if needed." + Environment.NewLine
            + "# -----------------------------------------------------------------------" + Environment.NewLine
            + hostnamesBlock + Environment.NewLine
            + Environment.NewLine
            + @"$ErrorActionPreference = 'SilentlyContinue'
$passed = 0
$failed = 0
$results = @()

Write-Host """"
Write-Host ""=== Mass GPUpdate ==="" -ForegroundColor Cyan
Write-Host ""Processing $($Hostnames.Count) host(s)..."" -ForegroundColor Yellow
Write-Host """"

foreach ($hostname in $Hostnames) {
    $hostname = $hostname.Trim()
    if ([string]::IsNullOrWhiteSpace($hostname)) { continue }

    Write-Host ""--- $hostname ---"" -ForegroundColor Cyan

    # Check WinRM availability
    $winrmOk = $false
    try {
        $null = Test-WSMan -ComputerName $hostname -ErrorAction Stop
        $winrmOk = $true
    }
    catch {
        Write-Host ""  [SKIP] WinRM not available on $hostname — skipping."" -ForegroundColor Yellow
        $failed++
        $results += [PSCustomObject]@{ Host = $hostname; Result = 'SKIP (WinRM unavailable)' }
        continue
    }

    # Run gpupdate and WSUS check-in remotely
    try {
        Invoke-Command -ComputerName $hostname -ErrorAction Stop -ScriptBlock {
            $ErrorActionPreference = 'SilentlyContinue'
            gpupdate /force | Out-Null
            wuauclt /resetauthorization
            wuauclt /detectnow
            wuauclt /reportnow
        }
        Write-Host ""  [PASS] gpupdate and WSUS check-in commands sent to $hostname."" -ForegroundColor Green
        $passed++
        $results += [PSCustomObject]@{ Host = $hostname; Result = 'PASS' }
    }
    catch {
        Write-Host ""  [FAIL] Remote execution failed on $hostname: $($_.Exception.Message)"" -ForegroundColor Red
        $failed++
        $results += [PSCustomObject]@{ Host = $hostname; Result = ""FAIL: $($_.Exception.Message)"" }
    }
}

Write-Host """"
Write-Host ""=== Summary ==="" -ForegroundColor Cyan
$resultColor = if ($failed -eq 0) { 'Green' } else { 'Yellow' }
Write-Host ""Total: $($Hostnames.Count) | Passed: $passed | Failed/Skipped: $failed"" -ForegroundColor $resultColor
Write-Host """"
Write-Host ""Per-host results:"" -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host

Write-Host """"
Write-Host ""Script complete. Press Enter to exit."" -ForegroundColor Cyan
Read-Host
";
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// <summary>
    /// Builds the standard script header comment block.
    /// </summary>
    private static string ScriptHeader(string operationKey)
    {
        var displayName = KeyToDisplay.TryGetValue(operationKey, out var name) ? name : operationKey;
        var date = DateTime.Now.ToString("yyyy-MM-dd HH:mm");

        return $"# WSUS Manager - {displayName} Script{Environment.NewLine}"
             + $"# Generated: {date}{Environment.NewLine}"
             + $"# Run this script on the target host as Administrator.{Environment.NewLine}"
             + $"# No external modules or WSUS Manager installation required.{Environment.NewLine}"
             + Environment.NewLine;
    }

    /// <summary>
    /// Builds the $Hostnames PowerShell array block from the provided list.
    /// If the list is null or empty, a placeholder template is used instead.
    /// </summary>
    private static string BuildHostnamesBlock(IReadOnlyList<string>? hostnames)
    {
        var validHosts = hostnames?
            .Select(h => h.Trim())
            .Where(h => !string.IsNullOrWhiteSpace(h))
            .ToList();

        if (validHosts is null || validHosts.Count == 0)
        {
            return "$Hostnames = @(" + Environment.NewLine
                 + "    \"HOST1\"," + Environment.NewLine
                 + "    \"HOST2\"," + Environment.NewLine
                 + "    \"HOST3\"" + Environment.NewLine
                 + "    # Add more hostnames here, one per line." + Environment.NewLine
                 + ")";
        }

        var sb = new StringBuilder();
        sb.AppendLine("$Hostnames = @(");
        for (int i = 0; i < validHosts.Count; i++)
        {
            var comma = i < validHosts.Count - 1 ? "," : "";
            sb.AppendLine($"    \"{validHosts[i]}\"{comma}");
        }
        sb.Append(")");
        return sb.ToString();
    }

    /// <summary>
    /// Normalises an operation type string: tries display name → key,
    /// then falls back to treating the input as a key directly.
    /// </summary>
    private static string NormaliseKey(string operationType)
    {
        if (DisplayToKey.TryGetValue(operationType, out var key))
            return key;

        // Already an internal key (case-insensitive)
        foreach (var k in KeyToDisplay.Keys)
        {
            if (string.Equals(k, operationType, StringComparison.OrdinalIgnoreCase))
                return k;
        }

        // Return as-is to trigger the ArgumentException in the switch
        return operationType;
    }

    /// <summary>
    /// Extracts the hostname from a URL such as http://wsus-server:8530.
    /// Returns null if the URL is null or cannot be parsed.
    /// </summary>
    private static string? ExtractHostname(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
            return null;

        try
        {
            var uri = new Uri(url.Contains("://") ? url : "http://" + url);
            return uri.Host;
        }
        catch
        {
            return null;
        }
    }
}
