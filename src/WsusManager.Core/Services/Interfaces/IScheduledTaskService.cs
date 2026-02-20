using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Service for managing Windows scheduled tasks for WSUS maintenance.
/// Uses schtasks.exe via IProcessRunner for task creation, querying, and deletion.
/// </summary>
public interface IScheduledTaskService
{
    /// <summary>
    /// Creates (or replaces) a Windows scheduled task for WSUS maintenance.
    /// The task runs powershell.exe calling Invoke-WsusMonthlyMaintenance.ps1
    /// with the specified profile and credentials.
    /// </summary>
    Task<OperationResult> CreateTaskAsync(ScheduledTaskOptions options, IProgress<string>? progress = null, CancellationToken ct = default);

    /// <summary>
    /// Queries the status of a scheduled task by name.
    /// Returns the task status string (Ready, Running, Disabled, or Not Found).
    /// </summary>
    Task<OperationResult<string>> QueryTaskAsync(string taskName, CancellationToken ct = default);

    /// <summary>
    /// Deletes an existing scheduled task by name.
    /// </summary>
    Task<OperationResult> DeleteTaskAsync(string taskName, IProgress<string>? progress = null, CancellationToken ct = default);
}
