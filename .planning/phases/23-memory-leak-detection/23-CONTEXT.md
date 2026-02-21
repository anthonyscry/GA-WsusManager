# Phase 23: Memory Leak Detection - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

## Phase Boundary

Detect and fix memory leaks in the WPF application to ensure long-running stability. Profile memory usage during repeated operations (dashboard refresh, window open/close), verify event handlers are properly unsubscribed, confirm data-bound collections use ObservableCollection, and ensure IDisposable objects are properly disposed.

## Implementation Decisions

### Profiling Tool
- **JetBrains dotMemory** — Industry standard for .NET memory profiling
- **Alternative:** PerfView (free Microsoft tool) if dotMemory unavailable
- **Manual execution only** — Not automated in CI (profiling is interactive)
- **Output:** Memory snapshots showing object counts, heap usage, retention paths

**Rationale:** Research identifies dotMemory as the recommended tool for WPF memory leak detection with automatic leak detection and retention path analysis.

### Test Scenarios
- **Dashboard refresh cycle:** Run 100x dashboard refresh operations, capture memory before/after
- **Window open/close:** Open/close MainWindow 50x times, check for leaked window objects
- **Long-running operation:** Simulate 1 hour of continuous dashboard refresh (30s interval)
- **Service operations:** Repeated Health Check, Cleanup, and Export operations (10x each)

**Rationale:** Research identifies these patterns as common leak sources. 100 iterations provides statistically significant data.

### Leak Patterns to Check
- **Event handlers:** Verify event subscription (`+=`) has matching unsubscription (`-=`) in dispose/cleanup
- **Data binding:** Confirm data-bound collections use `ObservableCollection<T>` (not `List<T>`)
- **IDisposable:** Verify `IDisposable` services are disposed (DatabaseBackupService, SqlService)
- **Weak events:** Check for long-lived publishers using `WeakEventManager` pattern
- **Named elements:** Verify XAML `x:Name` elements don't create unintended references

**Rationale:** Research documents these as WPF-specific leak patterns. Phase 21 async audit reduced risk, but verification still needed.

### Acceptance Threshold
- **Memory growth:** <5% increase after 100 operations of same type
- **Object counts:** No unbounded growth in specific object types (e.g., DashboardCard keeps growing)
- **Baseline:** Measure initial memory after startup, compare after stress test
- **Pass criteria:** Memory returns to baseline +/- 5% after garbage collection

**Rationale:** Small memory growth is acceptable (caches, buffers). Unbounded growth indicates leaks. 5% threshold allows for measurement variance.

### Claude's Discretion
- Specific iteration counts (100 is reasonable starting point)
- Which operations to prioritize (dashboard refresh is highest frequency)
- Whether to automate test scenarios or run manually
- Whether to include memory snapshots in verification report

## Specific Ideas

- Focus on MainViewModel and DashboardViewModel (primary UI state holders)
- Check ObservableCollection usage in all ViewModels
- Verify async operations properly clean up CancellationTokenSource
- Check for static collections that grow unbounded
- Use dotMemory "Object retention" view to find leaked objects

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 23-memory-leak-detection*
*Context gathered: 2026-02-21*
