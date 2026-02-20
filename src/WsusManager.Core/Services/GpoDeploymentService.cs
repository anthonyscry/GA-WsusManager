using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Copies GPO deployment files from the application's DomainController/ directory
/// to C:\WSUS\WSUS GPO\ and returns structured instruction text for the DC admin.
/// </summary>
public class GpoDeploymentService : IGpoDeploymentService
{
    private readonly ILogService _logService;

    /// <summary>Source directory name containing GPO files.</summary>
    public const string SourceDirectoryName = "DomainController";

    /// <summary>Default destination directory for GPO files.</summary>
    public const string DefaultDestination = @"C:\WSUS\WSUS GPO";

    public GpoDeploymentService(ILogService logService)
    {
        _logService = logService;
    }

    /// <inheritdoc/>
    public async Task<OperationResult<string>> DeployGpoFilesAsync(
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            // Locate source directory
            var sourceDir = LocateSourceDirectory();
            if (sourceDir is null)
            {
                var paths = GetSearchPaths();
                var msg = $"DomainController directory not found. Searched:\n" +
                          $"  {paths[0]}\n  {paths[1]}";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult<string>.Fail(msg);
            }

            _logService.Info("Deploying GPO files from {Source} to {Dest}", sourceDir, DefaultDestination);
            progress?.Report($"Source: {sourceDir}");
            progress?.Report($"Destination: {DefaultDestination}");

            // Create destination directory
            Directory.CreateDirectory(DefaultDestination);
            progress?.Report("Created destination directory.");

            // Copy all files recursively
            var fileCount = await Task.Run(() => CopyDirectory(sourceDir, DefaultDestination, progress), ct);

            _logService.Info("GPO deployment complete: {Count} files copied", fileCount);
            progress?.Report($"[OK] Copied {fileCount} files to {DefaultDestination}");

            var instructions = BuildInstructionText();
            return OperationResult<string>.Ok(instructions, $"GPO files deployed ({fileCount} files).");
        }
        catch (OperationCanceledException)
        {
            _logService.Info("GPO deployment cancelled by user");
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "GPO deployment failed with unexpected error");
            return OperationResult<string>.Fail($"GPO deployment failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Recursively copies all files from source to destination, preserving directory structure.
    /// Returns the number of files copied.
    /// </summary>
    internal static int CopyDirectory(string sourceDir, string destDir, IProgress<string>? progress)
    {
        var count = 0;
        var source = new DirectoryInfo(sourceDir);

        foreach (var file in source.GetFiles("*", SearchOption.AllDirectories))
        {
            var relativePath = Path.GetRelativePath(sourceDir, file.FullName);
            var destPath = Path.Combine(destDir, relativePath);
            var destDirectory = Path.GetDirectoryName(destPath)!;

            Directory.CreateDirectory(destDirectory);
            file.CopyTo(destPath, overwrite: true);
            count++;
        }

        return count;
    }

    /// <summary>
    /// Builds the step-by-step instruction text for the DC admin.
    /// </summary>
    internal static string BuildInstructionText()
    {
        return $"""
            GPO files have been copied to {DefaultDestination}

            Steps for the Domain Controller admin:

            1. Copy the "WSUS GPO" folder to the Domain Controller

            2. Run Set-WsusGroupPolicy.ps1 on the Domain Controller:
               powershell -ExecutionPolicy Bypass -File Set-WsusGroupPolicy.ps1

            3. Force client check-in on target machines:
               gpupdate /force
               wuauclt /detectnow
            """;
    }

    /// <summary>
    /// Locates the DomainController directory relative to the current executable directory.
    /// </summary>
    internal string? LocateSourceDirectory()
    {
        foreach (var path in GetSearchPaths())
        {
            if (Directory.Exists(path))
                return path;
        }
        return null;
    }

    internal string[] GetSearchPaths()
    {
        var appDir = AppContext.BaseDirectory;
        return
        [
            Path.Combine(appDir, SourceDirectoryName),
            Path.Combine(appDir, "..", SourceDirectoryName)
        ];
    }
}
