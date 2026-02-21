namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Provides historical timing data for WSUS operations to enable time estimation
/// during long-running operations. Timing data comes from Phase 22 BenchmarkDotNet
/// benchmarks and runtime measurements.
/// </summary>
public interface IBenchmarkTimingService
{
    /// <summary>
    /// Gets the read-only dictionary of operation names to average durations.
    /// Keys are operation names (e.g., "Health Check", "Repair Health").
    /// Values are average durations based on historical measurements.
    /// </summary>
    IReadOnlyDictionary<string, TimeSpan> OperationTimings { get; }

    /// <summary>
    /// Attempts to retrieve the average duration for a specific operation.
    /// </summary>
    /// <param name="operationName">The name of the operation (e.g., "Health Check", "Deep Cleanup").</param>
    /// <param name="duration">When this method returns, contains the average duration if found; otherwise, TimeSpan.Zero.</param>
    /// <returns>True if the operation has timing data; otherwise, false.</returns>
    bool TryGetAverageDuration(string operationName, out TimeSpan duration);

    /// <summary>
    /// Records a new timing measurement for an operation.
    /// This can be used to update estimates based on actual runtime measurements.
    /// </summary>
    /// <param name="operationName">The name of the operation.</param>
    /// <param name="duration">The duration to record.</param>
    void RecordTiming(string operationName, TimeSpan duration);
}
