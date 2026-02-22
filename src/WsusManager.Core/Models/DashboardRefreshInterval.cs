namespace WsusManager.Core.Models;

/// <summary>
/// Dashboard auto-refresh interval. Controls how often the dashboard
/// data is refreshed from the WSUS server.
/// </summary>
public enum DashboardRefreshInterval
{
    /// <summary>Refresh every 10 seconds.</summary>
    Sec10,

    /// <summary>Refresh every 30 seconds (default).</summary>
    Sec30,

    /// <summary>Refresh every 60 seconds.</summary>
    Sec60,

    /// <summary>Disable auto-refresh (manual only).</summary>
    Disabled
}
