using System.Collections.Concurrent;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Provides historical timing data for WSUS operations. Pre-populated with
/// average durations from Phase 22 BenchmarkDotNet benchmarks and practical measurements.
/// Thread-safe for concurrent access.
/// </summary>
public class BenchmarkTimingService : IBenchmarkTimingService
{
    private readonly ConcurrentDictionary<string, TimeSpan> _operationTimings;

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, TimeSpan> OperationTimings => _operationTimings;

    /// <summary>
    /// Initializes a new instance of the <see cref="BenchmarkTimingService"/> class
    /// with pre-populated timing data from Phase 22 benchmarks and practical measurements.
    /// </summary>
    public BenchmarkTimingService()
    {
        _operationTimings = new ConcurrentDictionary<string, TimeSpan>(StringComparer.OrdinalIgnoreCase)
        {
            // Diagnostics operations (fast - typically < 30 seconds)
            ["Health Check"] = TimeSpan.FromSeconds(5),
            ["Repair Health"] = TimeSpan.FromSeconds(30),
            ["Diagnostics"] = TimeSpan.FromSeconds(25),

            // Service operations (instant - < 5 seconds)
            ["Start SQL"] = TimeSpan.FromSeconds(3),
            ["Start WSUS"] = TimeSpan.FromSeconds(2),
            ["Start IIS"] = TimeSpan.FromSeconds(2),
            ["Stop SQL"] = TimeSpan.FromSeconds(2),
            ["Stop WSUS"] = TimeSpan.FromSeconds(2),
            ["Stop IIS"] = TimeSpan.FromSeconds(2),
            ["Start All Services"] = TimeSpan.FromSeconds(5),

            // Content operations (medium - 30-120 seconds)
            ["Content Reset"] = TimeSpan.FromSeconds(45),

            // Database operations (long - varies by database size)
            ["Deep Cleanup"] = TimeSpan.FromMinutes(2),
            ["Backup Database"] = TimeSpan.FromMinutes(3),
            ["Restore Database"] = TimeSpan.FromMinutes(5),

            // WSUS operations (long - varies by update count)
            ["Online Sync"] = TimeSpan.FromMinutes(2),
            ["Export"] = TimeSpan.FromMinutes(1.5),
            ["Import"] = TimeSpan.FromMinutes(1),

            // Installation operations (very long - 10-30 minutes)
            ["Install WSUS"] = TimeSpan.FromMinutes(15),

            // Scheduling and GPO (instant)
            ["Schedule Task"] = TimeSpan.FromSeconds(2),
            ["Create GPO"] = TimeSpan.FromSeconds(3),

            // Client operations (medium - varies by client count)
            ["Cancel Stuck Jobs"] = TimeSpan.FromSeconds(10),
            ["Force Check-In"] = TimeSpan.FromSeconds(15),
            ["Test Connectivity"] = TimeSpan.FromSeconds(5),
            ["Client Diagnostics"] = TimeSpan.FromSeconds(30),
            ["Mass GPUpdate"] = TimeSpan.FromMinutes(2),
        };
    }

    /// <inheritdoc/>
    public bool TryGetAverageDuration(string operationName, out TimeSpan duration)
    {
        if (string.IsNullOrWhiteSpace(operationName))
        {
            duration = TimeSpan.Zero;
            return false;
        }

        // Try exact match first
        if (_operationTimings.TryGetValue(operationName, out duration))
        {
            return true;
        }

        // Try partial match for operations like "Start SQL Server" when we have "Start SQL"
        foreach (var kvp in _operationTimings)
        {
            if (operationName.Contains(kvp.Key, StringComparison.OrdinalIgnoreCase) ||
                kvp.Key.Contains(operationName, StringComparison.OrdinalIgnoreCase))
            {
                duration = kvp.Value;
                return true;
            }
        }

        duration = TimeSpan.Zero;
        return false;
    }

    /// <inheritdoc/>
    public void RecordTiming(string operationName, TimeSpan duration)
    {
        if (string.IsNullOrWhiteSpace(operationName))
        {
            return;
        }

        // Update or add the timing
        _operationTimings.AddOrUpdate(operationName, duration, (_, _) => duration);
    }
}
