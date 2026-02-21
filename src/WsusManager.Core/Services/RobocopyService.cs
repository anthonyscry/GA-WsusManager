using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Runs robocopy.exe with standardized WSUS options for content transfer.
/// Mirrors the PowerShell Invoke-WsusRobocopy function exactly.
/// </summary>
public class RobocopyService : IRobocopyService
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    /// <summary>
    /// File extensions to exclude from robocopy.
    /// </summary>
    private static readonly string[] ExcludedFilePatterns = ["*.bak", "*.log"];

    /// <summary>
    /// Directory names to exclude from robocopy.
    /// </summary>
    private static readonly string[] ExcludedDirectories = ["Logs", "SQLDB", "Backup"];

    public RobocopyService(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner;
        _logService = logService;
    }

    public async Task<OperationResult> CopyAsync(
        string source,
        string destination,
        int maxAgeDays = 0,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        var arguments = BuildArguments(source, destination, maxAgeDays);

        _logService.Info("Running robocopy: {Source} -> {Destination} (maxAge={MaxAge})",
            source, destination, maxAgeDays);
        progress?.Report($"Robocopy: {source} -> {destination}");

        var result = await _processRunner.RunAsync("robocopy.exe", arguments, progress, ct).ConfigureAwait(false);

        // Robocopy exit codes 0-7 are success, 8+ are errors
        if (result.ExitCode < 8)
        {
            var msg = MapExitCode(result.ExitCode);
            _logService.Info("Robocopy completed: exit code {ExitCode} ({Message})", result.ExitCode, msg);
            progress?.Report($"Robocopy completed: {msg}");
            return OperationResult.Ok(msg);
        }
        else
        {
            var msg = MapExitCode(result.ExitCode);
            _logService.Warning("Robocopy failed: exit code {ExitCode} ({Message})", result.ExitCode, msg);
            progress?.Report($"[ERROR] Robocopy failed: {msg}");
            return OperationResult.Fail(msg);
        }
    }

    /// <summary>
    /// Builds the robocopy argument string with standard WSUS options.
    /// </summary>
    public static string BuildArguments(string source, string destination, int maxAgeDays)
    {
        // Core options matching PowerShell Invoke-WsusRobocopy:
        // /E = copy subdirectories including empty
        // /XO = exclude older files
        // /MT:16 = 16 multi-threaded copy threads
        // /R:2 = 2 retries on failed copies
        // /W:5 = 5-second wait between retries
        // /NP = no progress percentage (cleaner log output)
        // /NDL = no directory listing
        var args = $"\"{source}\" \"{destination}\" /E /XO /MT:16 /R:2 /W:5 /NP /NDL";

        // File exclusions
        args += $" /XF {string.Join(" ", ExcludedFilePatterns)}";

        // Directory exclusions
        args += $" /XD {string.Join(" ", ExcludedDirectories)}";

        // Differential: only copy files modified within N days
        if (maxAgeDays > 0)
            args += $" /MAXAGE:{maxAgeDays}";

        return args;
    }

    /// <summary>
    /// Maps robocopy exit codes to human-readable messages.
    /// </summary>
    private static string MapExitCode(int exitCode) => exitCode switch
    {
        0 => "No files were copied. Source and destination are in sync.",
        1 => "All files were copied successfully.",
        2 => "Extra files or directories were detected. No files were copied.",
        3 => "Some files were copied. Additional files were present.",
        4 => "Mismatched files or directories were detected.",
        5 => "Some files were copied. Some files were mismatched.",
        6 => "Additional files and mismatched files exist.",
        7 => "Files were copied, mismatched, and additional files present.",
        8 => "Some files or directories could not be copied (copy errors).",
        16 => "Serious error. No files were copied.",
        _ => $"Robocopy error: exit code {exitCode}."
    };
}
