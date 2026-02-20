namespace WsusManager.Core.Models;

/// <summary>
/// Options for creating a Windows scheduled task for WSUS maintenance.
/// All fields are collected via the ScheduleTaskDialog before task creation.
/// </summary>
public record ScheduledTaskOptions
{
    /// <summary>Name of the scheduled task in Windows Task Scheduler.</summary>
    public string TaskName { get; init; } = "WSUS Monthly Maintenance";

    /// <summary>Schedule frequency: Monthly, Weekly, or Daily.</summary>
    public ScheduleType Schedule { get; init; } = ScheduleType.Monthly;

    /// <summary>Day of month (1-31). Used when Schedule is Monthly.</summary>
    public int DayOfMonth { get; init; } = 15;

    /// <summary>Day of week. Used when Schedule is Weekly.</summary>
    public DayOfWeek DayOfWeek { get; init; } = DayOfWeek.Saturday;

    /// <summary>Start time in HH:mm format (24-hour).</summary>
    public string Time { get; init; } = "02:00";

    /// <summary>Maintenance profile: Full, Quick, or SyncOnly.</summary>
    public string MaintenanceProfile { get; init; } = "Full";

    /// <summary>Windows username to run the task as (domain\user or .\user).</summary>
    public string Username { get; init; } = @".\dod_admin";

    /// <summary>Password for the Windows user account.</summary>
    public string Password { get; init; } = string.Empty;

    /// <summary>Maximum execution time in hours before the task is terminated.</summary>
    public int ExecutionTimeLimitHours { get; init; } = 4;
}
