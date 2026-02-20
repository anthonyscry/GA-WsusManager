namespace WsusManager.Core.Models;

/// <summary>
/// Sync profile selection for Online Sync operations.
/// Matches legacy PowerShell MaintenanceProfile parameter.
/// </summary>
public enum SyncProfile
{
    /// <summary>
    /// Full Sync: synchronize -> decline superseded/expired/old -> approve updates -> monitor downloads.
    /// </summary>
    FullSync,

    /// <summary>
    /// Quick Sync: synchronize -> approve updates (skip decline step).
    /// </summary>
    QuickSync,

    /// <summary>
    /// Sync Only: synchronize metadata only, no approval changes.
    /// </summary>
    SyncOnly
}
