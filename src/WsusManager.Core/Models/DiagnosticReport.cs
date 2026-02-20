namespace WsusManager.Core.Models;

/// <summary>
/// Aggregate result of a full diagnostics run. Contains all individual check results
/// and computed summary statistics. Immutable — created once after all checks complete.
/// </summary>
public record DiagnosticReport
{
    /// <summary>All individual check results in the order they were run.</summary>
    public required IReadOnlyList<DiagnosticCheckResult> Checks { get; init; }

    /// <summary>When the diagnostics run started.</summary>
    public required DateTime StartedAt { get; init; }

    /// <summary>When the diagnostics run completed.</summary>
    public required DateTime CompletedAt { get; init; }

    /// <summary>Total wall-clock duration of the diagnostics run.</summary>
    public TimeSpan Duration => CompletedAt - StartedAt;

    /// <summary>Total number of checks that were run (excluding Skipped).</summary>
    public int TotalChecks => Checks.Count(c => c.Status != CheckStatus.Skipped);

    /// <summary>Number of checks that passed (including those repaired to pass).</summary>
    public int PassedCount => Checks.Count(c => c.Status == CheckStatus.Pass);

    /// <summary>Number of checks that failed (after any repair attempts).</summary>
    public int FailedCount => Checks.Count(c => c.Status == CheckStatus.Fail);

    /// <summary>Number of checks that resulted in a warning.</summary>
    public int WarningCount => Checks.Count(c => c.Status == CheckStatus.Warning);

    /// <summary>
    /// Number of checks where auto-repair was attempted and succeeded.
    /// </summary>
    public int RepairedCount => Checks.Count(c => c.RepairAttempted && c.RepairSucceeded == true);

    /// <summary>
    /// True when all checks pass or were successfully repaired.
    /// Warnings and Skipped checks do not affect IsHealthy.
    /// </summary>
    public bool IsHealthy => FailedCount == 0;

    /// <summary>
    /// Creates an empty report for the case where no checks ran.
    /// </summary>
    public static DiagnosticReport Empty() => new()
    {
        Checks = [],
        StartedAt = DateTime.UtcNow,
        CompletedAt = DateTime.UtcNow
    };
}
