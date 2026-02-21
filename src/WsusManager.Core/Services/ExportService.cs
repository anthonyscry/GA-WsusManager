using System.IO;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Exports WSUS content to external media using robocopy.
/// Supports full and differential export modes.
/// </summary>
public class ExportService : IExportService
{
    private readonly IRobocopyService _robocopyService;
    private readonly ILogService _logService;

    public ExportService(IRobocopyService robocopyService, ILogService logService)
    {
        _robocopyService = robocopyService;
        _logService = logService;
    }

    public async Task<OperationResult> ExportAsync(
        ExportOptions options,
        IProgress<string> progress,
        CancellationToken ct)
    {
        // Pre-flight: both paths blank means skip
        bool hasFullPath = !string.IsNullOrWhiteSpace(options.FullExportPath);
        bool hasDiffPath = !string.IsNullOrWhiteSpace(options.DifferentialExportPath);

        if (!hasFullPath && !hasDiffPath)
        {
            progress.Report("No export paths specified -- skipping export.");
            return OperationResult.Ok("No export paths specified -- skipping.");
        }

        // Pre-flight: validate source path
        if (!Directory.Exists(options.SourcePath))
        {
            var msg = $"Source path does not exist: {options.SourcePath}";
            progress.Report($"[FAIL] {msg}");
            return OperationResult.Fail(msg);
        }

        var contentSource = Path.Combine(options.SourcePath, "WsusContent");
        if (!Directory.Exists(contentSource))
        {
            // Fall back to source path directly if WsusContent subdirectory doesn't exist
            contentSource = options.SourcePath;
        }

        progress.Report("Starting WSUS export...");
        _logService.Info("Starting export from {Source}", options.SourcePath);

        bool anyFailure = false;

        // Full export
        if (hasFullPath)
        {
            progress.Report("[Full Export] Copying all content...");
            var fullDest = Path.Combine(options.FullExportPath!, "WsusContent");
            var result = await _robocopyService.CopyAsync(contentSource, fullDest, 0, progress, ct).ConfigureAwait(false);
            if (!result.Success)
            {
                progress.Report($"[WARNING] Full export had issues: {result.Message}");
                anyFailure = true;
            }
            else
            {
                progress.Report("[OK] Full export completed.");
            }
        }

        // Differential export
        if (hasDiffPath)
        {
            var now = DateTime.Now;
            var archivePath = Path.Combine(
                options.DifferentialExportPath!,
                now.Year.ToString(),
                now.ToString("MM"));
            var diffDest = Path.Combine(archivePath, "WsusContent");

            progress.Report($"[Differential Export] Copying files from last {options.ExportDays} days...");
            progress.Report($"  Archive path: {archivePath}");

            var result = await _robocopyService.CopyAsync(
                contentSource, diffDest, options.ExportDays, progress, ct).ConfigureAwait(false);
            if (!result.Success)
            {
                progress.Report($"[WARNING] Differential export had issues: {result.Message}");
                anyFailure = true;
            }
            else
            {
                progress.Report("[OK] Differential export completed.");
            }
        }

        // Optional database backup copy
        if (options.IncludeDatabaseBackup)
        {
            await CopyDatabaseBackupAsync(options, hasFullPath, hasDiffPath, progress, ct).ConfigureAwait(false);
        }

        var finalMsg = anyFailure
            ? "Export completed with warnings."
            : "Export completed successfully.";
        progress.Report(finalMsg);
        return anyFailure ? OperationResult.Ok(finalMsg) : OperationResult.Ok(finalMsg);
    }

    private async Task CopyDatabaseBackupAsync(
        ExportOptions options,
        bool hasFullPath,
        bool hasDiffPath,
        IProgress<string> progress,
        CancellationToken ct)
    {
        try
        {
            progress.Report("[DB Backup] Looking for newest .bak file...");

            var bakFiles = Directory.GetFiles(options.SourcePath, "*.bak", SearchOption.AllDirectories);
            if (bakFiles.Length == 0)
            {
                progress.Report("[DB Backup] No .bak files found in source path.");
                return;
            }

            var newestBak = bakFiles
                .Select(f => new FileInfo(f))
                .OrderByDescending(f => f.LastWriteTime)
                .First();

            progress.Report($"[DB Backup] Found: {newestBak.Name} ({newestBak.Length / (1024.0 * 1024):F1} MB)");

            // Copy to full export path
            if (hasFullPath)
            {
                var dest = Path.Combine(options.FullExportPath!, newestBak.Name);
                File.Copy(newestBak.FullName, dest, overwrite: true);
                progress.Report($"[DB Backup] Copied to: {dest}");
            }

            // Copy to differential export path
            if (hasDiffPath)
            {
                var dest = Path.Combine(options.DifferentialExportPath!, newestBak.Name);
                File.Copy(newestBak.FullName, dest, overwrite: true);
                progress.Report($"[DB Backup] Copied to: {dest}");
            }

            await Task.CompletedTask.ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            progress.Report($"[WARNING] Database backup copy failed: {ex.Message}");
            _logService.Warning("Database backup copy failed: {Error}", ex.Message);
        }
    }
}
