# Phase 25: Performance Optimization - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Optimize application performance to improve perceived responsiveness: reduce startup time by 30%, virtualize large dashboard lists, lazy-load update metadata, batch log panel output, and accelerate theme switching.

</domain>

<decisions>
## Implementation Decisions

### Startup Optimization Approach
- Parallelize independent service initialization using Task.WhenAll
- Defer non-critical data loading (update lists, computer details) until after UI renders
- Prioritize: UI shell → dashboard summary → background data fetch
- Target: < 1.5s cold startup (30% improvement over v4.4 baseline ~2s)

### Data Virtualization Strategy
- Use WPF's built-in VirtualizingStackPanel for Lists/ListBoxes (no third-party dependencies)
- Enable VirtualizingPanel.IsVirtualizing="True" and VirtualizingPanel.VirtualizationMode="Recycling"
- Apply to Computers panel and Updates panel (handles 2000+ items)
- Keep item templates simple to avoid layout thrashing

### Lazy Loading Granularity
- Load summary counts immediately (computers online/offline, updates approved/declined)
- Fetch full update metadata on-demand when user expands or filters
- Use pagination for large datasets (100 items per page)
- Cache loaded data to avoid redundant queries

### Log Batching Parameters
- Batch log output into 50-line chunks
- Flush to UI every 100ms using DispatcherTimer
- Use Dispatcher.BeginInvoke with Normal priority (Background priority can cause delays)
- Preserve log order with concurrent queue

### Theme Switching Optimization
- Use existing ThemeService with DynamicResource bindings (already implemented)
- Ensure all resources use DynamicResource instead of StaticResource
- Pre-load theme resources on startup to avoid first-swap delay
- Target: < 100ms for instant visual feedback

### Claude's Discretion
- Exact Task parallelization strategy for startup
- VirtualizationPanel fine-tuning (scroll bar visibility, container recycling)
- Lazy loading cache size and eviction policy
- DispatcherTimer priority adjustments based on performance testing

</decisions>

<specifics>
## Specific Ideas

- "Startup should feel snappy — show the UI immediately, then populate data"
- "Large lists should scroll smoothly without loading all items into memory"
- "Theme switching should be instant — no reloading windows"
- Follow existing WPF and .NET 8 patterns from the codebase
- BenchmarkDotNet infrastructure already exists — use it to verify improvements

</specifics>

<deferred>
## Deferred Ideas

- Database query optimization (indexes, query rewriting) — defer to later if needed
- Background thread processing for non-critical operations — Phase 27 (Visual Feedback)
- Progress estimation for long-running operations — Phase 27 (Visual Feedback)

</deferred>

---

*Phase: 25-performance-optimization*
*Context gathered: 2026-02-21*
