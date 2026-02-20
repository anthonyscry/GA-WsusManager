using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Imports WSUS content from external media (USB drive, network share) to the
/// local WSUS content directory. Uses IRobocopyService for file copy and
/// optionally runs content reset via IContentResetService after import.
/// </summary>
public interface IImportService
{
    /// <summary>
    /// Imports WSUS content from source to destination.
    /// Pre-flight validates both paths before starting.
    /// </summary>
    Task<OperationResult> ImportAsync(
        ImportOptions options,
        IProgress<string> progress,
        CancellationToken ct);
}
