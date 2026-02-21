namespace WsusManager.Core.Models;

/// <summary>
/// Represents an update with filtering properties.
/// Used by Phase 29 Data Filtering panel with virtualized ListBox.
/// </summary>
public record UpdateInfo(
    Guid UpdateId,
    string Title,
    string? KbArticle,
    string Classification,
    DateTime ApprovalDate,
    bool IsApproved,
    bool IsDeclined);
