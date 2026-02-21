using System.Text.Json.Serialization;

namespace WsusManager.Core.Models;

/// <summary>
/// Application settings model. Serialized to/from JSON at
/// %APPDATA%\WsusManager\settings.json. Survives close/reopen cycles.
/// </summary>
public class AppSettings
{
    // ═══════════════════════════════════════════════════════════════
    // EXISTING SETTINGS
    // ═══════════════════════════════════════════════════════════════

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

    /// <summary>Selected color theme name (e.g., "DefaultDark").</summary>
    [JsonPropertyName("selectedTheme")]
    public string SelectedTheme { get; set; } = "DefaultDark";

    // ═══════════════════════════════════════════════════════════════
    // OPERATIONS SETTINGS
    // ═══════════════════════════════════════════════════════════════

    /// <summary>Default sync profile for Online Sync dialog.</summary>
    [JsonPropertyName("defaultSyncProfile")]
    public DefaultSyncProfile DefaultSyncProfile { get; set; } = DefaultSyncProfile.Full;

    // ═══════════════════════════════════════════════════════════════
    // LOGGING SETTINGS
    // ═══════════════════════════════════════════════════════════════

    /// <summary>Minimum log level to output.</summary>
    [JsonPropertyName("logLevel")]
    public LogLevel LogLevel { get; set; } = LogLevel.Info;

    /// <summary>Number of days to retain log files (1-365).</summary>
    [JsonPropertyName("logRetentionDays")]
    public int LogRetentionDays { get; set; } = 30;

    /// <summary>Maximum log file size in MB before rotation (1-1000).</summary>
    [JsonPropertyName("logMaxFileSizeMb")]
    public int LogMaxFileSizeMb { get; set; } = 10;

    // ═══════════════════════════════════════════════════════════════
    // BEHAVIOR SETTINGS
    // ═══════════════════════════════════════════════════════════════

    /// <summary>Whether to save and restore window position and size.</summary>
    [JsonPropertyName("persistWindowState")]
    public bool PersistWindowState { get; set; } = true;

    /// <summary>Window bounds for persistence (if PersistWindowState is true).</summary>
    [JsonPropertyName("windowBounds")]
    public WindowBounds? WindowBounds { get; set; }

    /// <summary>Dashboard auto-refresh interval.</summary>
    [JsonPropertyName("dashboardRefreshInterval")]
    public DashboardRefreshInterval DashboardRefreshInterval { get; set; } = DashboardRefreshInterval.Sec30;

    /// <summary>Whether to show confirmation prompts for destructive operations.</summary>
    [JsonPropertyName("requireConfirmationDestructive")]
    public bool RequireConfirmationDestructive { get; set; } = true;

    // ═══════════════════════════════════════════════════════════════
    // ADVANCED SETTINGS
    // ═══════════════════════════════════════════════════════════════

    /// <summary>WinRM operation timeout in seconds (10-300).</summary>
    [JsonPropertyName("winRMTimeoutSeconds")]
    public int WinRMTimeoutSeconds { get; set; } = 60;

    /// <summary>WinRM operation retry count (1-10).</summary>
    [JsonPropertyName("winRMRetryCount")]
    public int WinRMRetryCount { get; set; } = 3;

    // ═══════════════════════════════════════════════════════════════
    // DATA FILTERING SETTINGS (Phase 29)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>Last selected status filter for Computers panel.</summary>
    [JsonPropertyName("computerStatusFilter")]
    public string ComputerStatusFilter { get; set; } = "All";

    /// <summary>Last search text for Computers panel.</summary>
    [JsonPropertyName("computerSearchText")]
    public string ComputerSearchText { get; set; } = string.Empty;

    /// <summary>Last selected approval filter for Updates panel.</summary>
    [JsonPropertyName("updateApprovalFilter")]
    public string UpdateApprovalFilter { get; set; } = "All";

    /// <summary>Last selected classification filter for Updates panel.</summary>
    [JsonPropertyName("updateClassificationFilter")]
    public string UpdateClassificationFilter { get; set; } = "All";

    /// <summary>Last search text for Updates panel.</summary>
    [JsonPropertyName("updateSearchText")]
    public string UpdateSearchText { get; set; } = string.Empty;
}
