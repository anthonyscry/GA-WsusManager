# Domain Pitfalls

**Domain:** C#/.NET 8 WPF Application Quality & Polish
**Researched:** 2026-02-21
**Confidence:** MEDIUM

## Critical Pitfalls

Mistakes that cause rewrites or major issues when adding quality improvements to an existing C# WPF codebase.

### Pitfall 1: Brittle Integration Tests Due to Environment Dependencies

**What goes wrong:**
Integration tests that pass locally but fail intermittently in CI/CD due to timing variations, display settings, DPI scaling, or system performance differences. Tests become unreliable and teams lose trust in the test suite.

**Why it happens:**
WPF applications require STA thread model, have UI rendering delays, and depend on external services (SQL, WinRM, file system). Tests interact with actual UI elements and are sensitive to environmental factors. Developers write tests assuming consistent timing and environment state.

**Consequences:**
- Flaky tests mask real bugs
- CI/CD pipelines fail unpredictably
- Teams disable tests entirely, reducing code quality
- Increased development time debugging test infrastructure instead of features

**Prevention:**
- Use modern frameworks like FlaUI specifically designed for WPF
- Implement robust wait strategies with explicit timeouts for UI operations
- Use test data factories and builders for consistent state
- Configure tests to run with proper permissions in isolated environments
- Implement proper test isolation and cleanup between runs
- Use stable automation properties instead of visual characteristics or coordinates
- Mock external dependencies (SQL, WinRM, file system) when possible

**Detection:**
- Tests fail in CI but pass locally on retry
- Tests fail only when run in parallel
- Tests fail when run on different hardware configurations
- "Strange" failures suggesting timing issues (element not found, timeout)

**Phase to address:**
Phase 18-01 (Integration Tests) - Focus on test stability and reliability from the start

---

### Pitfall 2: Misleading Code Coverage Creating False Security

**What goes wrong:**
Achieving high code coverage percentages (80%+) while missing critical edge cases, error handling paths, and exception scenarios. The code is "covered" but not actually tested for real-world failure conditions.

**Why it happens:**
Code coverage tools measure line execution, not test quality. Developers write "happy path" tests that pass through code lines without testing boundaries, null cases, invalid inputs, or exception handling. Coverage reports show green but production bugs still occur.

**Consequences:**
- False confidence in code quality
- Edge case bugs in production despite "good" coverage
- Refactoring becomes risky - tests don't catch regressions
- Technical debt accumulates in untested error paths

**Prevention:**
- Focus on branch coverage rather than line coverage
- Use parameterized testing (xUnit `Theory`) for edge cases
- Test exception paths explicitly with `Assert.Throws`
- Cover null/empty/invalid input scenarios
- Test boundary conditions (0, -1, int.MaxValue)
- Verify all async cancellation paths
- Check that catch blocks are actually executed
- Use mutation testing to verify test effectiveness

**Detection:**
- Code coverage >80% but production bugs in error handling
- Tests never exercise `catch` blocks
- No tests for `ArgumentNullException` or `InvalidOperationException`
- All tests use the same "happy path" data

**Phase to address:**
Phase 18-02 (Unit Test Coverage) - Implement quality-focused testing, not just coverage numbers

---

### Pitfall 3: Memory Leaks from Event Handlers and Data Binding

**What goes wrong:**
Application memory usage grows over time, UI controls aren't garbage collected, and performance degrades. The application may crash after extended use or leak resources like database connections.

**Why it happens:**
WPF's strong reference patterns create leaks: event handlers not unsubscribed, data-bound collections without `INotifyCollectionChanged`, `DependencyProperty` subscriptions using `AddValueChanged` without matching `RemoveValueChanged`, named elements (`x:Name`) creating global references even after removal.

**Consequences:**
- Memory usage grows continuously during operation
- UI controls remain in memory after closing
- Application crashes after extended use
- Poor performance on lower-spec systems

**Prevention:**
- Always unsubscribe event handlers in `Unloaded` events
- Use `ObservableCollection` for data-bound collections
- Use weak event patterns for long-lived publishers
- Call `RemoveValueChanged` for every `AddValueChanged`
- Use `UnregisterName()` when removing named elements
- Implement `IDisposable` and `IAsyncDisposable` properly
- Run memory profiling with tools like dotMemory or PerfView
- Test with memory snapshot comparison after operations

**Detection:**
- Memory usage increases with each operation
- dotMemory shows growing instance counts for UI types
- PerfView shows LOH (Large Object Heap) fragmentation
- Application becomes slower over time

**Phase to address:**
Phase 18-05 (Performance & Memory) - Conduct memory leak detection before performance optimization

---

### Pitfall 4: Async/Await Deadlocks in UI Thread

**What goes wrong:**
UI freezes completely, application hangs waiting for operations to complete, or deadlocks occur when mixing async and synchronous code. Users must force-quit the application.

**Why it happens:**
Using `Task.Result` or `.Wait()` on UI thread blocks the dispatcher from processing queued work. WPF's STA model means all UI operations must marshal to the UI thread, and blocking the dispatcher prevents async completions from being processed, creating deadlock.

**Consequences:**
- Application completely frozen
- Lost user work due to force-quit
- Negative user perception of stability
- Difficult to debug - deadlocks don't always reproduce

**Prevention:**
- Never use `Task.Result` or `.Wait()` on UI thread
- Always use `async/await` consistently throughout the call stack
- Use `ConfigureAwait(false)` in library code (non-UI layers)
- Use `Dispatcher.InvokeAsync` for cross-thread UI updates
- Pass `CancellationToken` to all async operations
- Handle `OperationCanceledException` properly
- Avoid `async void` except for event handlers
- Use `ValueTask` for disposable patterns

**Detection:**
- UI becomes unresponsive during certain operations
- Deadlock in debugger shows UI thread waiting
- Stack trace shows `Wait()` or `Result` on UI thread
- Application only hangs in production, not debugging

**Phase to address:**
Phase 18-05 (Performance & Memory) - Audit async patterns before optimization work

---

### Pitfall 5: Static Analyzer Noise and Warning Fatigue

**What goes wrong:**
Developers disable Roslyn analyzers or ignore warnings due to excessive false positives and low-value warnings. Real issues get missed in the noise. Code quality degrades as team learns to ignore warnings entirely.

**Why it happens:**
Enabling all analyzers without configuration produces hundreds of warnings. Not all warnings are relevant for the project context. Teams see valueless warnings (like naming style disputes) and disable entire analyzers instead of tuning rules.

**Consequences:**
- Real bugs hidden among 500+ style warnings
- Analyzers disabled project-wide
- Technical debt accumulates
- Code reviews become tedious

**Prevention:**
- Start with `MinimumRecommendedRules` for incremental adoption
- Use .editorconfig for fine-grained rule control
- Set `CodeAnalysisTreatWarningsAsErrors` to `false` initially
- Address warnings incrementally, not all at once
- Customize severity levels (error/warning/info/silent)
- Exclude specific rules that don't match project style
- Focus on CA (code analysis) rules over IDE (style) rules
- Review warnings regularly and update configuration

**Detection:**
- Build output shows 500+ warnings
- Team ignores all warnings as "noise"
- `<NoWarn>` contains analyzer categories instead of specific rules
- Pull requests show warning count increasing over time

**Phase to address:**
Phase 18-03 (Static Analysis) - Configure analyzer severity before fixing warnings

---

## Technical Debt Patterns

Shortcuts that seem reasonable when adding quality features but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Suppress CS1591 warnings project-wide | Eliminates 100+ documentation warnings immediately | No XML docs for API, no IntelliSense tooltips | Never - add docs or suppress per-file for internal helpers |
| Use `Thread.Sleep()` for test timing | Tests pass consistently | Brittle tests, slow execution, fails on faster machines | Never - use proper async/await and wait conditions |
| Mock everything in integration tests | Fast tests, no external dependencies | Tests don't catch real integration bugs | Rarely - only for truly external services (Azure AD, etc.) |
| Ignore analyzer warnings via `<NoWarn>` | Clean build output | Missed bugs, security issues, performance problems | Only for well-documented, project-specific exclusions |
| Test only happy path | High coverage quickly | Production bugs in error handling, unsafe refactoring | Never - error paths are where bugs hide |
| Skip XML docs for internal classes | Faster development | Poor discoverability for future developers | For truly internal implementation details only |
| Use `Task.Result` to avoid async propagation | Works in simple cases | Deadlock risk, blocks thread pool | Never - use async all the way |
| Disable flaky tests | CI passes consistently | Hidden bugs, regression detection lost | Only temporarily with bug tracking |

## Integration Gotchas

Common mistakes when connecting to external services during quality improvements.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| xUnit Test Discovery | Tests don't appear - missing `[Fact]` or `[Theory]` attributes | Ensure every test method has proper attribute, use `[Theory]` with `[InlineData]` for parameters |
| Coverlet Coverage | Coverage shows 0% - missing `<GenerateInstrumentationEnabled>true</GenerateInstrumentationEnabled>` | Add instrumentation flag to test project, use Debug configuration |
| FlaUI UI Automation | Tests fail with "element not found" - using UI automation before window loaded | Add explicit wait for window to load, use retry logic for element location |
| XML Documentation | CS1591 warnings not shown - `<GenerateDocumentationFile>` missing | Enable documentation generation in .csproj, add `<NoWarn>$(NoWarn);1591</NoWarn>` selectively |
| Roslyn Analyzers | Analyzers not running - `<EnableNETAnalyzers>` missing or set to false | Set to `true`, use `<AnalysisMode>AllEnabledByDefault</AnalysisMode>` |
| GitHub Actions | Flaky tests fail CI - no retry mechanism | Use `nick-fields/retry@v3` action with `max_attempts: 3` for test steps |
| PerfView Profiling | No data collected - missing `clr` event provider | Enable CLR events, use appropriate session settings for memory allocation |
| DocFX Generation | Missing API docs - XML doc file not in DocFX config | Include `<DocumentationFile>` path in DocFX `docfx.json` |

## Performance Traps

Patterns that work during development but cause issues in production or at scale.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Loading all data at startup | Fast on dev machine, 10+ seconds in production | Lazy load data, initialize after window renders, minimize assembly references | Cold start on production server |
| Synchronous file/database I/O | UI freezes during operations | Use async/await for all I/O, show progress indicators | Operations on large files or slow networks |
| No UI virtualization | Scrolling stutters with large lists | Enable `VirtualizingStackPanel.IsVirtualizing="True"` on ListViews/DataGrids | 100+ items in list |
| Forcing layout updates | Resize causes flicker and lag | Batch UI updates, use `SuspendLayout`/`ResumeLayout` equivalents | Complex layouts with many controls |
| Memory-mapped file not disposed | File handle leaks, eventually can't open files | Use `using` statements, implement `IDisposable`, verify with Process Explorer | Repeated file operations over time |
| Dispatcher.Invoke from background thread | UI thread blocked, unresponsive UI | Use `await Dispatcher.InvokeAsync()` with `ConfigureAwait(false)` in background | Frequent UI updates from background |
| String concatenation in loops | Memory usage spikes, GC pressure | Use `StringBuilder` for loop concatenation | Large loops (1000+ iterations) |
| Not pooling large objects | LOH fragmentation, out of memory | Pool large buffers, reuse objects, split large allocations | Long-running operations |

## Security Mistakes

Domain-specific security issues beyond general OWASP basics.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Password in connection string logged | Credentials exposed in logs/files | Use `SecureString`, redact passwords from logs, never log connection strings |
| SQL injection via string concatenation | Database compromise, data theft | Always parameterize queries, use Dapper/Entity Framework parameterization |
| Command injection in Process.Start | Code execution vulnerability | Validate all input, use argument arrays, escape user input |
| Not validating file paths | Directory traversal attacks | Use `Path.GetFullPath`, validate paths are within allowed directories |
| Hardcoded admin credentials | Application compromised if decompiled | Use Windows integrated security, prompt for credentials, store securely |
| Not escaping PowerShell script content | Injection via script generator | Use verbatim strings, validate input, escape carefully |
| Skipping certificate validation | Man-in-the-middle attacks | Validate SSL certificates, don't use `TrustServerCertificate` in production |

## UX Pitfalls

Common user experience mistakes in quality-focused development.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Test progress not visible | User thinks app crashed | Show progress bars, step tracking, current operation name |
| No cancellation option | User must force-quit | Implement `CancellationToken`, show Cancel button, handle gracefully |
| Errors shown in console only | User doesn't know what went wrong | Show user-friendly error dialogs, log technical details separately |
| Operations block UI thread | Application appears frozen | Use async/await, show loading indicators, keep UI responsive |
| No feedback for long operations | User uncertainty, repeated clicks | Disable buttons during operation, show progress, enable on completion |
| Settings take effect on restart only | Confusion about why changes didn't work | Apply settings immediately or explain restart requirement clearly |
| Memory usage grows | Application gets slower over time | Profile memory leaks, fix event handler issues, release resources |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces for quality improvements.

- [ ] **Integration tests pass consistently** - Often missing retry logic for flaky tests — verify tests pass 10+ times consecutively in CI
- [ ] **Code coverage increased** - Often missing edge case testing — verify branch coverage, exception paths, and boundary conditions
- [ ] **Memory profiling completed** - Often missing comparison snapshots — verify before/after snapshots for specific operations
- [ ] **XML documentation added** - Often missing cref validation — verify all `see` and `seealso` references resolve correctly
- [ ] **Static analysis warnings fixed** - Often missing root cause analysis — verify warnings weren't just suppressed without fixing underlying issues
- [ ] **Performance benchmarks run** - Often missing cold start measurement — verify startup timing after system reboot, not warm cache
- [ ] **UI automation tests created** - Often missing cleanup between tests — verify no state pollution between test runs
- [ ] **Async patterns audited** - Often missing cancellation token propagation — verify all async methods accept and respect `CancellationToken`

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Brittle integration tests | HIGH | Add wait strategies, mock external dependencies, use stable selectors, run tests in isolation, implement retry logic |
| Misleading code coverage | MEDIUM | Add edge case tests, test exception paths explicitly, use mutation testing, focus on critical business logic coverage |
| Memory leaks from events | HIGH | Audit all event subscriptions, add weak event patterns, implement proper cleanup, use memory profiling tools |
| Async/await deadlocks | MEDIUM | Audit for `.Result`/`.Wait()`, add `ConfigureAwait(false)`, verify proper async propagation |
| Analyzer warning fatigue | MEDIUM | Re-enable analyzers incrementally, configure severity, update .editorconfig, document exclusions |
| Slow cold startup | MEDIUM | Profile with PerfView, lazy-load modules, delay initialization, optimize assembly references |
| Flaky CI tests | LOW | Add retry action, categorize flaky tests, increase timeouts, improve cleanup |
| Missing XML docs | LOW | Generate doc skeleton, fill in high-priority APIs, suppress CS1591 selectively |

## Pitfall-to-Phase Mapping

How v4.4 quality phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Brittle integration tests | Phase 18-01 (Integration Tests) | Tests pass 10 consecutive runs in CI, no timing-dependent failures |
| Misleading code coverage | Phase 18-02 (Unit Test Coverage) | Branch coverage >70%, edge case tests documented |
| Memory leaks | Phase 18-05 (Performance & Memory) | Memory usage stable after 100 operations, no growth in dotMemory |
| Async deadlocks | Phase 18-05 (Performance & Memory) | No `.Result`/`.Wait()` in codebase, all methods propagate `CancellationToken` |
| Analyzer warning fatigue | Phase 18-03 (Static Analysis) | <50 warnings, analyzer config documented, no project-wide suppressions |
| Slow cold startup | Phase 18-05 (Performance & Memory) | Cold start <1 second on production hardware |
| Flaky CI tests | Phase 18-01 (Integration Tests) | Retry logic in place, flaky tests categorized |
| Missing XML docs | Phase 18-06 (Documentation) | Public APIs documented, XML generation enabled, IntelliSense works |
| Cyclomatic complexity | Phase 18-03 (Static Analysis) | No methods >10 complexity, refactoring documented |
| UI automation issues | Phase 18-04 (UI Automation) | Reliable element location, explicit waits, stable selectors |

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| 18-01 Integration Tests | Brittle tests due to timing, environment, STA issues | Use FlaUI, implement wait strategies, mock external services, configure STA |
| 18-02 Unit Test Coverage | High coverage but low quality, missing edge cases | Focus on branch coverage, test exceptions, use parameterized tests |
| 18-03 Static Analysis | Warning fatigue, analyzer noise, over-suppression | Incremental adoption, configure severity, document exclusions |
| 18-04 UI Automation | Element location issues, timing problems | Stable selectors, explicit waits, retry logic, proper cleanup |
| 18-05 Performance & Memory | Premature optimization, missing cold start tests | Profile before optimizing, test cold start, measure before/after |
| 18-06 Documentation | Incomplete docs, cref validation failures | Enable XML generation, validate crefs, document behavior not implementation |

## Sources

- WPF Integration Testing Challenges (FlaUI, Appium, testing patterns) - MEDIUM confidence
- C# .NET Memory Leak Detection (dotMemory, PerfView, WPF patterns) - MEDIUM confidence
- Async/Await Deadlock Patterns (Task.Result, ConfigureAwait, Dispatcher) - MEDIUM confidence
- Code Coverage Quality Issues (Coverlet, branch vs line coverage, mutation testing) - MEDIUM confidence
- WPF Cold Start Optimization (Splash screen, module loading, I/O optimization) - MEDIUM confidence
- C# XML Documentation Best Practices (CS1591 warnings, cref validation) - MEDIUM confidence
- GitHub Actions Flaky Test Retries (nick-fields/retry, xUnit patterns) - MEDIUM confidence
- Cyclomatic Complexity and Maintainability Index (thresholds, refactoring guidelines) - MEDIUM confidence

---

*Pitfalls research for: C#/.NET 8 WPF Quality & Polish Improvements*
*Researched: 2026-02-21*
