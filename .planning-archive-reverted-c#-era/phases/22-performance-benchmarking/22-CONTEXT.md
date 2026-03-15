# Phase 22: Performance Benchmarking - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

## Phase Boundary

Establish performance baselines for critical application operations using BenchmarkDotNet. Measure startup time (cold/warm), database operations (cleanup, restore, queries), and WinRM operations (client checks, GPUpdate). Configure CI/CD integration with manual trigger and set regression detection thresholds.

## Implementation Decisions

### Benchmarking Tool
- **BenchmarkDotNet** (v0.14.0) — Industry standard for .NET performance testing
- **Attributes:** `[MemoryDiagnoser]`, `[Benchmark]`, `[Arguments]` for parameterized tests
- **Output:** HTML report with statistical analysis (mean, stddev, percentiles)
- **Project:** Separate `WsusManager.Benchmarks` project (prevents accidental benchmark runs)

**Rationale:** Research recommends BenchmarkDotNet for consistent measurements with statistical rigor.

### Critical Operations to Benchmark
- **Startup:** Cold start (first launch), warm start (subsequent launches)
- **Database:** Cleanup (6-step process), restore (single-user mode, restore, multi-user), queries (server status, update counts)
- **WinRM:** Connectivity check, GPUpdate invocation, diagnostics execution
- **Memory:** Ensure no leaks across 100 iterations of critical operations

**Rationale:** These operations directly impact user experience. Startup latency affects first impressions; database/WinRM performance affects responsiveness.

### Baseline Targets (from STATE.md)
- **Cold startup:** <2 seconds
- **Warm startup:** <500ms
- **Database operations:** Queries <100ms, cleanup <30s total, restore <10s
- **WinRM operations:** Connectivity check <2s, GPUpdate <5s per host
- **Memory:** Stable after 100 iterations (no growth)

**Rationale:** Targets come from v4.4 STATE.md metrics. Baselines establish current performance; subsequent runs detect regressions.

### CI/CD Integration
- **Manual trigger only** — Benchmarks run via `workflow_dispatch` event, not on push
- **Reason:** Benchmarks take 5-10 minutes — too slow for every CI run
- **Artifact:** Benchmark HTML report uploaded as CI artifact for trend analysis
- **Regression alert:** Fail build if any operation regresses >10% from baseline

**Rationale:** Research warns against running benchmarks on every commit. Manual trigger before releases ensures performance isn't degrading.

### Benchmark Configuration
- **Iterations:** 100 warmup + 1000 measurement (statistical significance)
- **Platform:** AnyCPU, prefer 64-bit
- **Jit:** Default (JitOptimizes, RyuJit x64)
- **Memory:** Enable `MemoryDiagnoser` to detect allocations
- **Outliers:** Auto-remove to avoid noise from background processes

### Claude's Discretion
- Specific iteration counts (balance statistical significance vs. runtime)
- Whether to use `[DryRunJob]` for quick verification during development
- Exact baseline values will be discovered during first benchmark run
- Threshold for "regression" (10% is reasonable starting point)

## Specific Ideas

- Create `BenchmarkStartup.cs` for cold/warm startup measurements
- Create `BenchmarkDatabaseOperations.cs` for SQL operations
- Create `BenchmarkWinRMOperations.cs` for remote operations
- Store baseline results in repository as `baseline.txt` for regression comparison
- Use `[Arguments]` for parameterized benchmarks (e.g., different record counts)

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 22-performance-benchmarking*
*Context gathered: 2026-02-21*
