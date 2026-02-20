using System.IO;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Imports WSUS content from external media to the local WSUS content directory.
/// </summary>
public class ImportService : IImportService
{
    private readonly IRobocopyService _robocopyService;
    private readonly IContentResetService _contentResetService;
    private readonly ILogService _logService;

    public ImportService(
        IRobocopyService robocopyService,
        IContentResetService contentResetService,
        ILogService logService)
    {
        _robocopyService = robocopyService;
        _contentResetService = contentResetService;
        _logService = logService;
    }

    public async Task<OperationResult> ImportAsync(
        ImportOptions options,
        IProgress<string> progress,
        CancellationToken ct)
    {
        // Pre-flight: validate source path exists
        if (!Directory.Exists(options.SourcePath))
        {
            var msg = $"Source path does not exist: {options.SourcePath}";
            progress.Report($"[FAIL] {msg}");
            return OperationResult.Fail(msg);
        }

        // Pre-flight: validate source has content
        var hasFiles = Directory.EnumerateFileSystemEntries(options.SourcePath).Any();
        if (!hasFiles)
        {
            var msg = $"Source path is empty: {options.SourcePath}";
            progress.Report($"[FAIL] {msg}");
            return OperationResult.Fail(msg);
        }

        // Pre-flight: validate destination path is writable
        try
        {
            Directory.CreateDirectory(options.DestinationPath);
        }
        catch (Exception ex)
        {
            var msg = $"Cannot write to destination path {options.DestinationPath}: {ex.Message}";
            progress.Report($"[FAIL] {msg}");
            return OperationResult.Fail(msg);
        }

        progress.Report("Starting WSUS import...");
        progress.Report($"  Source: {options.SourcePath}");
        progress.Report($"  Destination: {options.DestinationPath}");
        _logService.Info("Starting import: {Source} -> {Destination}",
            options.SourcePath, options.DestinationPath);

        // Copy content
        var copyResult = await _robocopyService.CopyAsync(
            options.SourcePath, options.DestinationPath, 0, progress, ct);

        if (!copyResult.Success)
        {
            progress.Report($"[FAIL] Import failed: {copyResult.Message}");
            return OperationResult.Fail($"Import failed: {copyResult.Message}");
        }

        progress.Report("[OK] Content import completed.");

        // Optional content reset
        if (options.RunContentResetAfterImport)
        {
            progress.Report("");
            progress.Report("Running content reset (wsusutil reset)...");
            var resetResult = await _contentResetService.ResetContentAsync(progress, ct);
            if (resetResult.Success)
            {
                progress.Report("[OK] Content reset completed.");
            }
            else
            {
                progress.Report($"[WARNING] Content reset failed: {resetResult.Message}");
                _logService.Warning("Content reset after import failed: {Error}", resetResult.Message);
            }
        }

        _logService.Info("Import completed: {Source} -> {Destination}",
            options.SourcePath, options.DestinationPath);
        return OperationResult.Ok("Import completed successfully.");
    }
}
