using System.Text.Json.Serialization;

namespace WsusManager.Core.Models;

/// <summary>
/// Application settings model. Serialized to/from JSON at
/// %APPDATA%\WsusManager\settings.json. Survives close/reopen cycles.
/// </summary>
public class AppSettings
{
    /// <summary>Server mode: "Online" or "AirGap".</summary>
    [JsonPropertyName("serverMode")]
    public string ServerMode { get; set; } = "Online";

    /// <summary>Whether the log panel is expanded on startup.</summary>
    [JsonPropertyName("logPanelExpanded")]
    public bool LogPanelExpanded { get; set; } = true;

    /// <summary>Whether to open operations in an external PowerShell window.</summary>
    [JsonPropertyName("liveTerminalMode")]
    public bool LiveTerminalMode { get; set; }

    /// <summary>WSUS content path (default C:\WSUS).</summary>
    [JsonPropertyName("contentPath")]
    public string ContentPath { get; set; } = @"C:\WSUS";

    /// <summary>SQL Server instance name.</summary>
    [JsonPropertyName("sqlInstance")]
    public string SqlInstance { get; set; } = @"localhost\SQLEXPRESS";

    /// <summary>Dashboard auto-refresh interval in seconds.</summary>
    [JsonPropertyName("refreshIntervalSeconds")]
    public int RefreshIntervalSeconds { get; set; } = 30;
}
