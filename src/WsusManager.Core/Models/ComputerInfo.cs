namespace WsusManager.Core.Models;

/// <summary>
/// Represents a computer in the WSUS environment with filtering properties.
/// Used by Phase 29 Data Filtering panel with virtualized ListBox.
/// </summary>
public record ComputerInfo(
    string Hostname,
    string IpAddress,
    string Status,
    DateTime LastSync,
    int PendingUpdates,
    string OsVersion);
