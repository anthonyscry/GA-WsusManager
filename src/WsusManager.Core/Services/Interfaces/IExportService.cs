using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Exports WSUS content to external media. Supports full export (all content)
/// and differential export (files modified within N days with Year/Month archive structure).
/// Both modes use IRobocopyService for content copy.
/// </summary>
public interface IExportService
{
    /// <summary>
    /// Exports WSUS content based on the provided options.
    /// If both export paths are blank, returns success with a skip message.
    /// </summary>
    Task<OperationResult> ExportAsync(
        ExportOptions options,
        IProgress<string> progress,
        CancellationToken ct);
}
