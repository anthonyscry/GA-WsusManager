namespace WsusManager.Core.Models;

/// <summary>
/// Snapshot of WSUS client configuration and state on a remote host, gathered
/// from the Windows Update registry hive, service control manager, and WMI.
/// </summary>
public record ClientDiagnosticResult
{
    /// <summary>
    /// Configured WSUS server URL from HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\WUServer.
    /// Null if the registry key is absent or WUServer is not set.
    /// </summary>
    public string? WsusServerUrl { get; init; }

    /// <summary>
    /// Configured WSUS status server URL from WUStatusServer registry value.
    /// Usually matches WsusServerUrl; may differ in some GPO deployments.
    /// </summary>
    public string? WsusStatusServerUrl { get; init; }

    /// <summary>
    /// Whether UseWUServer policy is enabled (1 = true). When false the client
    /// ignores WsusServerUrl and contacts Windows Update directly.
    /// </summary>
    public bool UseWUServer { get; init; }

    /// <summary>
    /// Current state of Windows Update-related services keyed by service name
    /// (e.g., "wuauserv", "bits", "cryptsvc", "msiserver"). Value is the
    /// service status string (Running, Stopped, etc.).
    /// </summary>
    public Dictionary<string, string> ServiceStatuses { get; init; } = new(StringComparer.Ordinal);

    /// <summary>
    /// UTC timestamp of the client's last successful check-in with the WSUS server.
    /// Null if the client has never checked in or if the value could not be read.
    /// </summary>
    public DateTime? LastCheckInTime { get; init; }

    /// <summary>
    /// True if the host has a pending reboot required to complete update installation.
    /// Detected via the RebootRequired registry key or CBS session state.
    /// </summary>
    public bool PendingRebootRequired { get; init; }

    /// <summary>
    /// Windows Update Agent version string from the wuaueng.dll file version.
    /// Example: "10.0.19041.1949".
    /// </summary>
    public string? WindowsUpdateAgentVersion { get; init; }
}

/// <summary>
/// Result of a network connectivity test from the client host to the WSUS server.
/// Ports are tested with a TCP connection attempt; latency is measured via ping.
/// </summary>
public record ConnectivityTestResult
{
    /// <summary>True if the client can reach the WSUS server on port 8530 (HTTP).</summary>
    public bool Port8530Reachable { get; init; }

    /// <summary>True if the client can reach the WSUS server on port 8531 (HTTPS).</summary>
    public bool Port8531Reachable { get; init; }

    /// <summary>Round-trip latency in milliseconds from the client to the WSUS server host.</summary>
    public int LatencyMs { get; init; }
}

/// <summary>
/// Decoded information for a WSUS or Windows Update error code.
/// Sourced from the WsusErrorCodes static dictionary.
/// </summary>
public record WsusErrorInfo
{
    /// <summary>Canonical hex representation, e.g., "0x80244010".</summary>
    public string Code { get; init; } = string.Empty;

    /// <summary>
    /// Short hex suffix used as the dictionary key, e.g., "80244010".
    /// Stored for convenience when building display strings.
    /// </summary>
    public string HexCode { get; init; } = string.Empty;

    /// <summary>Human-readable description of what this error code means.</summary>
    public string Description { get; init; } = string.Empty;

    /// <summary>Recommended remediation steps for the administrator.</summary>
    public string RecommendedFix { get; init; } = string.Empty;
}
