using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Runs robocopy.exe with standardized WSUS export/import options.
/// Mirrors the PowerShell Invoke-WsusRobocopy function: /E /XO /MT:16 /R:2 /W:5 /NP /NDL,
/// excludes *.bak *.log files and Logs SQLDB Backup directories.
/// Interprets robocopy exit codes correctly (0-7 = success, 8+ = error).
/// </summary>
public interface IRobocopyService
{
    /// <summary>
    /// Runs robocopy with standard WSUS options.
    /// </summary>
    /// <param name="source">Source directory path.</param>
    /// <param name="destination">Destination directory path.</param>
    /// <param name="maxAgeDays">If > 0, adds /MAXAGE:N to only copy files modified within N days.</param>
    /// <param name="progress">Progress reporter for robocopy output lines.</param>
    /// <param name="ct">Cancellation token.</param>
    Task<OperationResult> CopyAsync(
        string source,
        string destination,
        int maxAgeDays = 0,
        IProgress<string>? progress = null,
        CancellationToken ct = default);
}
