using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Creates, queries, and deletes Windows scheduled tasks using schtasks.exe via IProcessRunner.
/// Uses schtasks.exe instead of COM TaskScheduler API -- simpler, no NuGet dependency,
/// and works reliably on Server 2019.
/// </summary>
public class ScheduledTaskService : IScheduledTaskService
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    /// <summary>PowerShell maintenance script filename.</summary>
    public const string MaintenanceScriptName = "Invoke-WsusMonthlyMaintenance.ps1";

    public ScheduledTaskService(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner;
        _logService = logService;
    }

    /// <inheritdoc/>
    public async Task<OperationResult> CreateTaskAsync(
        ScheduledTaskOptions options,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            // Locate the maintenance script
            var scriptPath = LocateScript();
            if (scriptPath is null)
            {
                var msg = $"Maintenance script not found. Searched for '{MaintenanceScriptName}' in:\n" +
                          $"  {GetSearchPaths()[0]}\n  {GetSearchPaths()[1]}";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            _logService.Info("Creating scheduled task: {TaskName}", options.TaskName);
            progress?.Report($"Creating scheduled task: {options.TaskName}");

            // Step 1: Delete existing task (ignore failure = task doesn't exist)
            progress?.Report("Removing existing task (if any)...");
            await _processRunner.RunAsync(
                "schtasks.exe",
                $"/Delete /TN \"{options.TaskName}\" /F",
                progress: null,
                ct: ct).ConfigureAwait(false);

            // Step 2: Build the task action command
            var taskAction = $"powershell.exe -ExecutionPolicy Bypass " +
                             $"-File \\\"{scriptPath}\\\" " +
                             $"-Unattended -MaintenanceProfile {options.MaintenanceProfile}";

            // Step 3: Build schtasks /Create arguments
            var args = BuildCreateArguments(options, taskAction);

            progress?.Report($"Schedule: {options.Schedule}");
            progress?.Report($"Time: {options.Time}");
            progress?.Report($"Profile: {options.MaintenanceProfile}");
            progress?.Report($"Username: {options.Username}");
            progress?.Report("Running schtasks /Create...");

            var result = await _processRunner.RunAsync("schtasks.exe", args, progress, ct).ConfigureAwait(false);

            if (result.Success)
            {
                _logService.Info("Scheduled task created successfully: {TaskName}", options.TaskName);
                progress?.Report($"[OK] Task '{options.TaskName}' created successfully.");
                return OperationResult.Ok($"Scheduled task '{options.TaskName}' created successfully.");
            }
            else
            {
                var msg = $"schtasks /Create failed with exit code {result.ExitCode}.";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }
        }
        catch (OperationCanceledException)
        {
            _logService.Info("Scheduled task creation cancelled by user");
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Scheduled task creation failed with unexpected error");
            return OperationResult.Fail($"Failed to create scheduled task: {ex.Message}", ex);
        }
    }

    /// <inheritdoc/>
    public async Task<OperationResult<string>> QueryTaskAsync(string taskName, CancellationToken ct = default)
    {
        try
        {
            var result = await _processRunner.RunAsync(
                "schtasks.exe",
                $"/Query /TN \"{taskName}\" /FO CSV /NH",
                progress: null,
                ct: ct).ConfigureAwait(false);

            if (!result.Success)
            {
                return OperationResult<string>.Ok("Not Found");
            }

            // Parse CSV output: "TaskName","Next Run Time","Status"
            var output = result.Output;
            if (output.Contains("Ready", StringComparison.OrdinalIgnoreCase))
                return OperationResult<string>.Ok("Ready");
            if (output.Contains("Running", StringComparison.OrdinalIgnoreCase))
                return OperationResult<string>.Ok("Running");
            if (output.Contains("Disabled", StringComparison.OrdinalIgnoreCase))
                return OperationResult<string>.Ok("Disabled");

            return OperationResult<string>.Ok("Unknown");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to query scheduled task: {TaskName}", taskName);
            return OperationResult<string>.Fail($"Failed to query task: {ex.Message}", ex);
        }
    }

    /// <inheritdoc/>
    public async Task<OperationResult> DeleteTaskAsync(
        string taskName,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Info("Deleting scheduled task: {TaskName}", taskName);
            progress?.Report($"Deleting scheduled task: {taskName}");

            var result = await _processRunner.RunAsync(
                "schtasks.exe",
                $"/Delete /TN \"{taskName}\" /F",
                progress,
                ct).ConfigureAwait(false);

            if (result.Success)
            {
                _logService.Info("Scheduled task deleted: {TaskName}", taskName);
                return OperationResult.Ok($"Task '{taskName}' deleted.");
            }
            else
            {
                var msg = $"schtasks /Delete failed with exit code {result.ExitCode}.";
                _logService.Warning(msg);
                return OperationResult.Fail(msg);
            }
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to delete scheduled task: {TaskName}", taskName);
            return OperationResult.Fail($"Failed to delete task: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Builds the schtasks /Create argument string based on schedule type.
    /// </summary>
    internal static string BuildCreateArguments(ScheduledTaskOptions options, string taskAction)
    {
        var args = $"/Create /TN \"{options.TaskName}\" " +
                   $"/TR \"{taskAction}\" " +
                   $"/ST {options.Time} " +
                   $"/RU \"{options.Username}\" " +
                   $"/RP \"{options.Password}\" " +
                   $"/RL HIGHEST /F";

        switch (options.Schedule)
        {
            case ScheduleType.Monthly:
                args += $" /SC MONTHLY /D {options.DayOfMonth}";
                break;
            case ScheduleType.Weekly:
                args += $" /SC WEEKLY /D {DayOfWeekToSchtasks(options.DayOfWeek)}";
                break;
            case ScheduleType.Daily:
                args += " /SC DAILY";
                break;
        }

        return args;
    }

    /// <summary>
    /// Converts DayOfWeek to the schtasks /D parameter value (MON, TUE, WED, etc.).
    /// </summary>
    internal static string DayOfWeekToSchtasks(DayOfWeek day) => day switch
    {
        DayOfWeek.Sunday => "SUN",
        DayOfWeek.Monday => "MON",
        DayOfWeek.Tuesday => "TUE",
        DayOfWeek.Wednesday => "WED",
        DayOfWeek.Thursday => "THU",
        DayOfWeek.Friday => "FRI",
        DayOfWeek.Saturday => "SAT",
        _ => "SAT"
    };

    /// <summary>
    /// Locates the maintenance script relative to the current executable directory.
    /// </summary>
    internal string? LocateScript()
    {
        foreach (var path in GetSearchPaths())
        {
            if (File.Exists(path))
                return path;
        }
        return null;
    }

    internal string[] GetSearchPaths()
    {
        var appDir = AppContext.BaseDirectory;
        return
        [
            Path.Combine(appDir, "Scripts", MaintenanceScriptName),
            Path.Combine(appDir, MaintenanceScriptName)
        ];
    }
}
