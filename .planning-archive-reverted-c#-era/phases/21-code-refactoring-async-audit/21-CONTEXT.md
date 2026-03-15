# Phase 21: Code Refactoring & Async Audit - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

## Phase Boundary

Reduce code complexity by refactoring methods with high cyclomatic complexity (>10) and eliminate async/await anti-patterns that cause UI deadlocks. Extract duplicated code patterns into reusable helpers and ensure proper CancellationToken propagation throughout async call chains.

## Implementation Decisions

### Complexity Threshold
- **Target:** Cyclomatic complexity ≤10 per method
- **Source:** Phase 19 static analysis (Meziantou.Maintainability CA1502 analyzer)
- **Prioritization:** Focus on methods with complexity >15 first, then 11-15
- **Exemptions:** Auto-generated code (XAML.g.cs, AssemblyInfo.cs) exempt from complexity rules

**Rationale:** Research identifies complexity >10 as hard to maintain and error-prone. Methods >15 are urgent refactoring targets.

### Async Anti-Pattern Elimination
- **Library code:** Use `ConfigureAwait(false)` on all `await` calls in WsusManager.Core
- **UI code:** Use `ConfigureAwait(true)` (default) in WsusManager.App for thread affinity
- **Forbidden:** `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` on UI thread
- **Async all the way:** Once a method is async, all callers must be async (no sync-over-async)

**Rationale:** Phase 19 found CA2007 warnings that were fixed. This phase ensures remaining async code follows patterns.

### Duplicated Code Extraction
- **Identify:** Use Phase 19 Roslynator MA0056 "do not declare same type in multiple namespaces" warnings
- **Extract:** Common 3+ line patterns into private helper methods or extension methods
- **Naming:** Helpers named descriptively (e.g., `ExecuteSqlAsync`, `LogOperation`, `ParseWsusId`)
- **Location:** Private helpers in same class, or extension methods in dedicated static class

**Rationale:** Duplicated code increases maintenance burden and bug surface area. 3+ occurrences justify extraction.

### CancellationToken Propagation
- **Required:** All async methods accept optional `CancellationToken cancellationToken = default`
- **Pass through:** Forward token to all async method calls in call chain
- **Timeout:** Use `CancellationTokenSource` with timeout for long-running operations (WinRM, SQL)
- **Cancellation check:** Throw `OperationCanceledException` if `token.IsCancellationRequested` before expensive work

**Rationale:** Proper cancellation allows users to stop long operations and prevents resource leaks.

### Claude's Discretion
- Specific methods to refactor (based on analyzer results)
- Whether to extract helper methods inline or to separate utility class
- Exact timeout values for CancellationTokenSource (30s, 60s, 2m based on operation type)
- Whether to add `[MethodImpl(MethodImplOptions.AggressiveInlining)]` to small helpers

## Specific Ideas

- Use existing async patterns from ContentResetService and DatabaseBackupService as templates
- Follow Phase 19-01's ConfigureAwait fixes as the pattern for remaining async code
- Check WsusManager.App ViewModels for sync-over-async patterns (button click handlers)
- Prioritize high-complexity methods that also have async issues

## Deferred Ideas

None — discussion stayed within phase scope.

---

*Phase: 21-code-refactoring-async-audit*
*Context gathered: 2026-02-21*
