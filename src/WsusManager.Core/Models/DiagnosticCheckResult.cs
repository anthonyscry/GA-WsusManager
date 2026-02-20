namespace WsusManager.Core.Models;

/// <summary>
/// Status of a single diagnostic check.
/// </summary>
public enum CheckStatus
{
    Pass,
    Fail,
    Warning,
    Skipped
}

/// <summary>
/// Result of a single health check. Each check has a name, status, detail message,
/// and optional repair outcome if auto-repair was attempted.
/// </summary>
public record DiagnosticCheckResult
{
    /// <summary>Human-readable name for this check (e.g., "SQL Server Express").</summary>
    public required string CheckName { get; init; }

    /// <summary>Pass, Fail, Warning, or Skipped.</summary>
    public required CheckStatus Status { get; init; }

    /// <summary>Detail message describing the check result (e.g., "Running", "Stopped").</summary>
    public required string Message { get; init; }

    /// <summary>True if an auto-repair was attempted for this check.</summary>
    public bool RepairAttempted { get; init; }

    /// <summary>True if repair succeeded, false if it failed, null if no repair was attempted.</summary>
    public bool? RepairSucceeded { get; init; }

    /// <summary>Detail message from the repair attempt (reason for success or failure).</summary>
    public string? RepairMessage { get; init; }

    /// <summary>
    /// Creates a passing result.
    /// </summary>
    public static DiagnosticCheckResult Pass(string checkName, string message) =>
        new() { CheckName = checkName, Status = CheckStatus.Pass, Message = message };

    /// <summary>
    /// Creates a failing result with no repair attempted.
    /// </summary>
    public static DiagnosticCheckResult Fail(string checkName, string message) =>
        new() { CheckName = checkName, Status = CheckStatus.Fail, Message = message };

    /// <summary>
    /// Creates a failing result where repair was attempted.
    /// </summary>
    public static DiagnosticCheckResult FailWithRepair(
        string checkName,
        string message,
        bool repairSucceeded,
        string repairMessage) =>
        new()
        {
            CheckName = checkName,
            Status = repairSucceeded ? CheckStatus.Pass : CheckStatus.Fail,
            Message = message,
            RepairAttempted = true,
            RepairSucceeded = repairSucceeded,
            RepairMessage = repairMessage
        };

    /// <summary>
    /// Creates a warning result (informational, non-critical).
    /// </summary>
    public static DiagnosticCheckResult Warn(string checkName, string message) =>
        new() { CheckName = checkName, Status = CheckStatus.Warning, Message = message };

    /// <summary>
    /// Creates a skipped result.
    /// </summary>
    public static DiagnosticCheckResult Skip(string checkName, string message) =>
        new() { CheckName = checkName, Status = CheckStatus.Skipped, Message = message };
}
