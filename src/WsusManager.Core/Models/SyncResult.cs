namespace WsusManager.Core.Models;

/// <summary>
/// Result of a WSUS synchronization operation.
/// </summary>
public record SyncResult(
    string Result,
    int NewUpdates,
    int RevisedUpdates,
    DateTime? StartTime);
