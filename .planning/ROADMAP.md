# Roadmap: GA-WsusManager

## Milestones

- ✅ **v4.0 C# Rewrite** — Phases 1-7 (shipped 2026-02-20)
- ✅ **v4.1 Bug Fixes & Polish** — Phases 8-11 (shipped 2026-02-20)
- ✅ **v4.2 UX & Client Management** — Phases 12-15 (shipped 2026-02-21)
- ✅ **v4.3 Themes** — Phases 16-17 (shipped 2026-02-21)
- 🔄 **v4.4 Quality & Polish** — Phases 18-24 (in progress)

## Phases

<details>
<summary>✅ v4.0 C# Rewrite (Phases 1-7) — SHIPPED 2026-02-20</summary>

- [x] Phase 1: Foundation — Compilable solution with DI, async pattern, single-file publish, UAC, logging (2026-02-19)
- [x] Phase 2: Application Shell and Dashboard — Dark theme, live dashboard, server mode, log panel, settings (2026-02-19)
- [x] Phase 3: Diagnostics and Service Management — Health check with auto-repair, service management, firewall, permissions (2026-02-20)
- [x] Phase 4: Database Operations — 6-step deep cleanup, backup/restore, sysadmin enforcement (2026-02-20)
- [x] Phase 5: WSUS Operations — Online sync with profiles, air-gap export/import, content reset (2026-02-19)
- [x] Phase 6: Installation and Scheduling — Install wizard, scheduled tasks, GPO deployment (2026-02-20)
- [x] Phase 7: Polish and Distribution — 257 tests, CI/CD pipeline, EXE validation, release automation (2026-02-20)

Full details: `.planning/milestones/v4.0-ROADMAP.md`

</details>

<details>
<summary>✅ v4.1 Bug Fixes & Polish (Phases 8-11) — SHIPPED 2026-02-20</summary>

- [x] Phase 8: Build Compatibility — Retarget to .NET 8, fix CI/CD and test paths (2026-02-20)
- [x] Phase 9: Launch and UI Verification — Fix duplicate startup message, add active nav highlighting (2026-02-20)
- [x] Phase 10: Core Operations — Fix 5 bugs in health check, sync, and cleanup services (2026-02-20)
- [x] Phase 11: Stability Hardening — Add CanExecute refresh for proper button disabling (2026-02-20)

Full details: `.planning/milestones/v4.1-ROADMAP.md`

</details>

<details>
<summary>✅ v4.2 UX & Client Management (Phases 12-15) — SHIPPED 2026-02-21</summary>

- [x] Phase 12: Settings & Mode Override — Editable settings dialog, dashboard mode toggle with override (2026-02-21)
- [x] Phase 13: Operation Feedback & Dialog Polish — Progress bar, step tracking, banners, dialog validation (2026-02-21)
- [x] Phase 14: Client Management Core — WinRM remote operations, error code lookup, Client Tools panel (2026-02-21)
- [x] Phase 15: Client Management Advanced — Mass GPUpdate, Script Generator fallback (2026-02-21)

Full details: `.planning/milestones/v4.2-ROADMAP.md`

</details>

<details>
<summary>✅ v4.3 Themes (Phases 16-17) — SHIPPED 2026-02-21</summary>

- [x] Phase 16: Theme Infrastructure — Split styles/tokens, migrate StaticResource to DynamicResource, implement ThemeService (2026-02-21)
- [x] Phase 17: Theme Content and Picker — 5 additional theme files, Settings Appearance section with live-preview swatch picker (2026-02-21)

Full details: `.planning/milestones/v4.3-ROADMAP.md`

</details>

<details>
<summary>🔄 v4.4 Quality & Polish (Phases 18-24) — IN PROGRESS</summary>

- [x] Phase 18: Test Coverage & Reporting — Measure and report test coverage with HTML artifacts (completed 2026-02-21)
- [x] Phase 19: Static Analysis & Code Quality — Zero compiler warnings with Roslyn analyzers (completed 2026-02-21)
- [ ] Phase 20: XML Documentation & API Reference — Complete XML docs for all public APIs
- [ ] Phase 21: Code Refactoring & Async Audit — Reduce complexity and fix async patterns
- [x] Phase 22: Performance Benchmarking — Baseline and benchmark critical operations (completed 2026-02-21)
- [ ] Phase 23: Memory Leak Detection — Detect and fix memory leaks before release
- [ ] Phase 24: Documentation Generation — User and developer documentation

**Requirements:** 29 total (6 Test Coverage, 8 Code Quality, 7 Performance, 6 Documentation)

</details>

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Foundation | v4.0 | 6/6 | Complete | 2026-02-19 |
| 2. Application Shell and Dashboard | v4.0 | 8/8 | Complete | 2026-02-19 |
| 3. Diagnostics and Service Management | v4.0 | 1/1 | Complete | 2026-02-20 |
| 4. Database Operations | v4.0 | 1/1 | Complete | 2026-02-20 |
| 5. WSUS Operations | v4.0 | 8/8 | Complete | 2026-02-19 |
| 6. Installation and Scheduling | v4.0 | 1/1 | Complete | 2026-02-20 |
| 7. Polish and Distribution | v4.0 | 7/7 | Complete | 2026-02-20 |
| 8. Build Compatibility | v4.1 | 1/1 | Complete | 2026-02-20 |
| 9. Launch and UI Verification | v4.1 | 1/1 | Complete | 2026-02-20 |
| 10. Core Operations | v4.1 | 1/1 | Complete | 2026-02-20 |
| 11. Stability Hardening | v4.1 | 1/1 | Complete | 2026-02-20 |
| 12. Settings & Mode Override | v4.2 | 2/2 | Complete | 2026-02-21 |
| 13. Operation Feedback & Dialog Polish | v4.2 | 2/2 | Complete | 2026-02-21 |
| 14. Client Management Core | v4.2 | 3/3 | Complete | 2026-02-21 |
| 15. Client Management Advanced | v4.2 | 2/2 | Complete | 2026-02-21 |
| 16. Theme Infrastructure | v4.3 | 1/1 | Complete | 2026-02-21 |
| 17. Theme Content and Picker | v4.3 | 1/1 | Complete | 2026-02-21 |
| 18. Test Coverage & Reporting | v4.4 | 3/3 | Complete    | 2026-02-21 |
| 19. Static Analysis & Code Quality | v4.4 | 5/5 | Complete   | 2026-02-21 |
| 20. XML Documentation & API Reference | v4.4 | 0/2 | Not started | - |
| 21. Code Refactoring & Async Audit | v4.4 | 0/2 | Not started | - |
| 22. Performance Benchmarking | v4.4 | 3/3 | Complete | 2026-02-21 |
| 23. Memory Leak Detection | v4.4 | 1/1 | Ready for implementation | - |
| 24. Documentation Generation | v4.4 | 0/4 | Not started | - |

---

## v4.4 Phase Details

### Phase 18: Test Coverage & Reporting

**Goal:** Measure and visualize test coverage across the codebase with transparent reporting

**Depends on:** Nothing

**Requirements:** TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06

**Success Criteria** (what must be TRUE):
1. Developer can run `dotnet test` and generate HTML coverage report showing line/branch coverage
2. CI/CD pipeline produces coverage HTML artifact accessible from GitHub Actions run
3. Coverage report includes both line coverage percentage and branch coverage analysis
4. Edge cases (null inputs, empty collections, boundary values) are explicitly tested
5. All exception handling paths have corresponding test coverage

**Plans:** 3/3 plans complete

**Plan List:**
- [x] 18-01-PLAN.md — Coverage infrastructure (Coverlet config, ReportGenerator, CI integration)
- [x] 18-02-PLAN.md — Edge case testing (null inputs, empty collections, boundary values)
- [x] 18-03-PLAN.md — Exception path testing (SqlException, IOException, WinRM exceptions)

---

### Phase 19: Static Analysis & Code Quality

**Goal:** Establish compiler-level quality gates with zero warnings and consistent code style

**Depends on:** Nothing

**Requirements:** QUAL-01, QUAL-02, QUAL-03, QUAL-06

**Success Criteria** (what must be TRUE):
1. `dotnet build --configuration Release` completes with zero warnings
2. All developers see consistent code style formatting regardless of editor
3. Roslyn analyzers catch code quality issues at compile time
4. CI/CD pipeline fails if static analysis warnings are present
5. New code automatically follows configured style rules

**Plans:** 5/5 plans complete

**Plan List:**
- [x] 19-01-PLAN.md — Roslyn analyzer infrastructure (SDK analyzers, Roslynator, Meziantou, StyleCop, Directory.Build.props, incremental adoption)
- [x] 19-02-PLAN.md — .editorconfig for consistent code style (naming conventions, indentation, using directive ordering, IDE-agnostic enforcement)
- [x] 19-03-PLAN.md — Zero compiler warnings (baseline assessment, systematic resolution, TreatWarningsAsErrors, CI/CD gate)

---

### Phase 20: XML Documentation & API Reference

**Goal:** Complete XML documentation for all public APIs with exception documentation

**Depends on:** Nothing

**Requirements:** QUAL-04, QUAL-05

**Success Criteria** (what must be TRUE):
1. IntelliSense shows descriptive summaries for all public APIs
2. All public methods document thrown exceptions with `<exception>` tags
3. API reference documentation website can be generated from XML comments
4. Public API parameters are documented with `<param>` tags
5. Return values are documented with `<returns>` tags

**Plans:** TBD

---

### Phase 21: Code Refactoring & Async Audit

**Goal:** Reduce code complexity and eliminate async anti-patterns that cause deadlocks

**Depends on:** Phase 19 (static analysis identifies complex methods)

**Requirements:** QUAL-07, QUAL-08, PERF-07

**Success Criteria** (what must be TRUE):
1. No methods have cyclomatic complexity >10
2. Duplicated code patterns are extracted into reusable helpers
3. No async operations use `.Result` or `.Wait()` on UI thread
4. All async operations propagate `CancellationToken` properly
5. Application remains responsive during long-running operations

**Plans:** TBD

---

### Phase 22: Performance Benchmarking

**Goal:** Establish performance baselines and detect regressions in critical operations

**Depends on:** Nothing

**Requirements:** PERF-01, PERF-02, PERF-03, PERF-04, PERF-05

**Success Criteria** (what must be TRUE):
1. Startup time is measured and documented (cold start <2s, warm start <500ms)
2. CI/CD pipeline displays startup benchmark in build output
3. Database operations have baseline performance metrics
4. WinRM operations have baseline performance metrics
5. Performance regressions are detected before release

**Plans:** 3/3 plans complete

**Plan List:**
- [x] 22-01-PLAN.md — Benchmark infrastructure project (BenchmarkDotNet, startup benchmarks, baseline capture)
- [ ] 22-02-PLAN.md — Database operations benchmarking (queries, connections, mock benchmarks for CI)
- [ ] 22-03-PLAN.md — WinRM benchmarks and CI/CD integration (manual trigger, regression detection, 10% threshold)

---

### Phase 23: Memory Leak Detection

**Goal:** Detect and fix memory leaks to ensure long-running stability

**Depends on:** Phase 21 (async audit reduces leak risk)

**Requirements:** PERF-06

**Success Criteria** (what must be TRUE):
1. Application memory usage remains stable during extended operation
2. Event handlers are properly unsubscribed in `Unloaded` events
3. Data-bound collections use `ObservableCollection` to prevent leaks
4. Long-lived publishers use weak event patterns
5. Memory profiling shows no growing object counts over time

**Plans:** 1/1 plan complete

**Plan List:**
- [x] 23-01-PLAN.md — Memory leak detection and prevention (StringBuilder for logs, timer cleanup, IDisposable pattern, dialog event handler cleanup)

---

### Phase 24: Documentation Generation

**Goal:** Comprehensive user and developer documentation for onboarding and contribution

**Depends on:** Phase 20 (XML docs required for API documentation)

**Requirements:** DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06

**Success Criteria** (what must be TRUE):
1. New users can install and run application from README instructions
2. Contributors can build, test, and submit changes following CONTRIBUTING.md
3. API documentation website browsable with generated HTML
4. CI/CD pipeline is documented with workflow explanations
5. Release process is documented with versioning and publish steps
6. Architecture decisions are documented for maintainability

**Plans:** TBD

---

## Requirement Traceability (v4.4)

| Category | Requirements | Phase | Coverage |
|----------|--------------|-------|----------|
| Test Coverage | TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06 | 18 | 6/6 |
| Code Quality | QUAL-01, QUAL-02, QUAL-03, QUAL-06 | 19 | 4/4 |
| Code Quality | QUAL-04, QUAL-05 | 20 | 2/2 |
| Code Quality | QUAL-07, QUAL-08 | 21 | 2/2 |
| Performance | PERF-01, PERF-02, PERF-03, PERF-04, PERF-05 | 22 | 5/5 |
| Performance | PERF-06 | 23 | 1/1 |
| Performance | PERF-07 | 21 | 1/1 |
| Documentation | DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06 | 24 | 6/6 |
| **Total** | **29 requirements** | **7 phases** | **29/29 (100%)** |
