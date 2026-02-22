namespace WsusManager.Core.Models;

/// <summary>
/// Default sync profile selection for Online Sync operations.
/// Used as the preset choice when opening the Online Sync dialog.
/// </summary>
public enum DefaultSyncProfile
{
    /// <summary>Full Sync: synchronize, decline superseded, approve, monitor.</summary>
    Full,

    /// <summary>Quick Sync: synchronize, approve (skip decline).</summary>
    Quick,

    /// <summary>Sync Only: synchronize metadata only, no approval changes.</summary>
    SyncOnly
}
