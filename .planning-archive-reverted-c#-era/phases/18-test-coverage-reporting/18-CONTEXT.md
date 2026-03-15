# Phase 18: Test Coverage & Reporting - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

## Phase Boundary

Establish code coverage measurement and reporting infrastructure for the C# WPF application. Configure Coverlet to collect branch coverage data during test execution, generate HTML reports via ReportGenerator, set quality gates that fail builds below threshold, and integrate coverage artifacts into CI/CD pipeline.

## Implementation Decisions

### Coverage Metric
- **Branch coverage** (not just line coverage) - more accurate for quality assessment
- Line coverage alone can miss critical decision paths
- Branch coverage captures all conditional branches and switch cases

### Coverage Thresholds
- **70% minimum branch coverage** (from v4.4 PITFALLS.md research)
- Build fails if coverage drops below threshold
- Thresholds configured per project (Core, App, Tests)
- Higher threshold (80%) for critical Core services

### Reporting Format
- **HTML reports** via ReportGenerator for human-readable visualization
- **XML output** for CI parsing and trend analysis
- Reports show:
  - Class-level coverage breakdown
  - Uncovered lines highlighted
  - Historical trend (if tracked)
  - Coverage by namespace/assembly

### Scope and Exclusions
- Cover all production code in `src/WsusManager.Core/` and `src/WsusManager.App/`
- Exclude test projects (WsusManager.Tests, WsusManager.E2E, etc.)
- Exclude generated code (XAML.g.cs, AssemblyInfo.cs, *.Designer.cs)
- Exclude third-party dependencies

### CI Integration
- Coverage runs on every test execution via `dotnet test --collect:"XPlat Code Coverage"`
- ReportGenerator creates HTML artifacts in CI output
- Build fails if below threshold (quality gate)
- HTML reports published as CI artifacts for review
- Coverage percentage displayed in build summary

### Claude's Discretion
- Exact ReportGenerator configuration (report types, history depth)
- Whether to track coverage trends over time (coverage history files)
- Whether to add badge to README (skip if not desired)
- Granularity of exclusions (can use attributes or glob patterns)

## Specific Ideas

- Follow Coverlet documentation for .NET 8 WPF projects
- Use Directory.Build.props for centralized coverage configuration
- HTML reports should be viewable directly from CI artifacts (no external hosting)
- Reports should help identify which specific classes/modules need more tests

## Deferred Ideas

None - discussion stayed within phase scope.

---

*Phase: 18-test-coverage-reporting*
*Context gathered: 2026-02-21*
