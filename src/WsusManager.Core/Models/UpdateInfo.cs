namespace WsusManager.Core.Models;

/// <summary>
/// Paged result set containing a subset of items along with pagination metadata.
/// </summary>
/// <typeparam name="T">Type of items in the result set.</typeparam>
/// <param name="Items">The subset of items for the current page.</param>
/// <param name="TotalCount">Total number of items across all pages.</param>
/// <param name="PageNumber">Current page number (1-based).</param>
/// <param name="PageSize">Number of items per page.</param>
public record PagedResult<T>(IReadOnlyList<T> Items, int TotalCount, int PageNumber, int PageSize)
{
    /// <summary>
    /// Total number of pages available.
    /// </summary>
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);

    /// <summary>
    /// Whether there is a previous page available.
    /// </summary>
    public bool HasPreviousPage => PageNumber > 1;

    /// <summary>
    /// Whether there is a next page available.
    /// </summary>
    public bool HasNextPage => PageNumber < TotalPages;
}

/// <summary>
/// Update metadata information from the WSUS database.
/// Used for lazy-loading update lists with pagination support.
/// </summary>
/// <param name="UpdateId">Unique identifier for the update.</param>
/// <param name="Title">Display title of the update.</param>
/// <param name="KbArticle">KB article number if available.</param>
/// <param name="Classification">Update classification (e.g., "Critical", "Security").</param>
/// <param name="CreatedDate">When the update was created/published.</param>
/// <param name="IsApproved">Whether the update is approved for installation.</param>
/// <param name="IsDeclined">Whether the update has been declined.</param>
public record UpdateInfo(
    Guid UpdateId,
    string Title,
    string? KbArticle,
    string? Classification,
    DateTime CreatedDate,
    bool IsApproved,
    bool IsDeclined);
