# Project Research Summary

**Project:** GA-WsusManager v4 (C# Rewrite)
**Domain:** Windows Server WSUS Administration GUI Tool
**Researched:** 2026-02-19
**Confidence:** HIGH

## Executive Summary

GA-WsusManager v4 is a production rewrite of a battle-tested PowerShell/WPF admin tool for managing Windows Server Update Services on Windows Server 2019+. The rewrite is motivated by the PowerShell version having reached practical complexity limits — 12 documented anti-patterns, recurring async/threading bugs, slow startup, and a fragile deployment model that requires Scripts/ and Modules/ folders alongside the EXE. The recommended approach is C# 13 with .NET 9 and WPF, using CommunityToolkit.Mvvm for MVVM source generation, Microsoft.Data.SqlClient for all SUSDB operations, and dotnet publish single-file self-contained EXE for deployment. This is not a close call — every alternative language (Rust, Go, Electron) has a blocking gap in either GUI maturity, Windows API access, or WSUS integration.

The critical architectural constraint is that `Microsoft.UpdateServices.Administration.dll` — the WSUS managed API — is incompatible with .NET 5+. This is confirmed via GitHub dotnet/core issue #5736 and means all WSUS operations must go through direct SQL against SUSDB (for database maintenance) or `wsusutil.exe` via `Process.Start()` (for export, import, reset, and health check). This constraint is actually an advantage: the existing PowerShell v3.8.x codebase already operates this way and the approach is proven across 3+ years of production use. The rewrite reproduces this pattern natively in C#, removing the PowerShell subprocess layer for most operations.

The primary risk is a rewrite that achieves feature parity on the happy path but silently drops the accumulated edge-case behaviors embedded in the PowerShell codebase: SQL command timeouts set to unlimited for maintenance operations, batched deletion of 100 updates per call to prevent transaction log overflow, retry logic on DB shrink when backup is running, two-step supersession record removal before update purge, and the `wsusutil reset` fix for post-import air-gap content states. Each feature phase must begin with a review of the corresponding PowerShell source before writing C#. Port the Pester test suite to xUnit test-first to surface these edge cases before they are missed.

---

## Key Findings

### Recommended Stack

C# (.NET 9) with WPF is the only stack that satisfies all hard constraints: native WPF GUI, full Windows API access, .NET COM interop path for future needs, and production-quality single-EXE deployment. All alternatives were evaluated and rejected. Use .NET 9 specifically (not .NET 8 LTS) because it ships the WPF Fluent dark theme natively — a core UI requirement of the rewrite. The Fluent `ThemeMode` API is experimental in .NET 9; implement dark theme via explicit ResourceDictionary entries instead.

**Core technologies:**
- **C# 13 / .NET 9**: Application language and runtime — only option with native WPF, COM interop, single-EXE deployment, and active Windows tooling ecosystem
- **WPF (net9.0-windows)**: GUI framework — Microsoft-maintained, battle-tested, DPI-aware, Fluent theme capable; only full-featured Windows desktop GUI in the .NET ecosystem
- **CommunityToolkit.Mvvm 8.4.0**: MVVM pattern with source generators — `[ObservableProperty]` and `[RelayCommand]` eliminate 80% of ViewModel boilerplate and prevent threading bugs via clean UI/logic separation
- **Microsoft.Data.SqlClient 6.1.4**: SQL Server Express (SUSDB) connectivity — replaces every `Invoke-Sqlcmd` call; requires .NET 8+ target
- **Serilog 4.x + Serilog.Sinks.File 6.x**: Structured file logging to `C:\WSUS\Logs\` with rolling files — replaces manual `Write-Log` pattern
- **Microsoft.Extensions.Hosting 9.0.x + DependencyInjection 9.0.x**: DI container and application lifecycle — prevents closure-capture and scope bugs from PowerShell event handlers
- **xUnit 2.9.x + Moq 4.20.x**: Unit testing and mocking — fast parallel execution with interface-based mocking for all services

**Critical version notes:**
- `PublishTrimmed=true` must NOT be used — WPF is not trim-compatible, breaks XAML bindings silently
- NativeAOT must NOT be used — WPF does not support it in .NET 9
- Use `AppContext.BaseDirectory` not `Assembly.CodeBase` — throws in single-file apps
- `System.Data.SqlClient` (old namespace) is deprecated; use `Microsoft.Data.SqlClient` exclusively
- Known .NET 9 regression (dotnet/sdk#43461): some WPF assemblies may be missing from self-contained publish; pin to .NET 8 as fallback if this manifests and upgrade to .NET 10 when available

### Expected Features

This is a rewrite of an existing production tool, not a greenfield product. "MVP" means feature parity with v3.8.12 so users can switch over. No net-new features are required for v4.0. WSUS was deprecated by Microsoft in September 2024, so the ecosystem is frozen — no new competitive tooling exists and the differentiation space for this tool's air-gap + single-server niche is uncontested.

**Must have (v4.0 — parity with v3.8.12):**
- Dashboard: service status (SQL/WSUS/IIS), DB size with 10GB limit warning, last sync time, auto-refresh (30s)
- Health check + auto-repair diagnostics: SQL connectivity, WSUS service, IIS app pool, firewall ports 8530/8531, content directory permissions
- Deep cleanup: 6-step pipeline (WSUS built-in cleanup, supersession record removal for declined, supersession removal for superseded in batches, spDeleteUpdate in batches of 100, index rebuild, DB shrink with retry)
- Service management quick actions: start/stop SQL Server, WSUS, IIS without UI freeze
- Online sync with profile selection (Full/Quick/Sync Only)
- Air-gap export/import workflow: full + differential (days-based filter)
- Database backup and restore
- Scheduled task creation for unattended maintenance
- WSUS + SQL Express installation wizard
- Settings persistence to `%APPDATA%\WsusManager\settings.json`
- Operation log panel with cancel button
- Server mode toggle (Online vs Air-Gap) with context-aware UI
- Admin privilege enforcement via UAC manifest at startup
- Single-file EXE distribution (no Scripts/Modules folders required)
- Dark theme, DPI-aware rendering

**Should have (v4.1 — post-parity improvements):**
- IIS app pool optimization (queue length 2000, ping disabled, no memory limit)
- Compliance summary: client count, % patched, last seen from SUSDB
- Export path pre-flight validation
- Live terminal mode toggle (external PowerShell window for raw output)

**Defer (v4.x+):**
- Update approval workflow UI (native WSUS console is adequate; enormous scope)
- Client force check-in trigger (requires WinRM/GPO; complex)
- HTTPS/SSL configuration helper (infrequent need; CLI is adequate)
- GPO deployment helper (low frequency; CLI is adequate)

**Anti-features — do not build:**
- Multi-server management (scope explosion; run one instance per server)
- Web-based/remote UI (wrong model for local admin tool)
- Third-party application patching (different API surface entirely)
- Real-time WSUS client monitoring (WSUS reporting is pull-based; "real-time" is misleading)
- Cloud/Azure integration (contradicts air-gap use case)

### Architecture Approach

The architecture follows strict three-layer MVVM: a WPF presentation layer (Views with zero code-behind logic), a service layer (all business logic behind interfaces, injected via DI), and an infrastructure layer (ProcessRunner for external processes, SqlHelper for SUSDB, FileSystemHelper). The main entry point uses `Microsoft.Extensions.Hosting` Generic Host for DI wiring and lifecycle management. All UI state lives in `MainViewModel` using CommunityToolkit.Mvvm observables; all long-running operations use `async Task` RelayCommands with `CancellationToken` threading, and a single `IsOperationRunning` flag that automatically disables all commands via `[NotifyCanExecuteChangedFor]`. The separation of `WsusManager.App` (WPF) from `WsusManager.Core` (no WPF dependency) is mandatory — it makes all service and ViewModel code unit-testable without a WPF runtime.

**Major components:**
1. `WsusManager.App` (WPF) — Presentation: MainWindow.xaml, MainViewModel, dialog ViewModels/Views, DI host wiring in Program.cs
2. `WsusManager.Core` — Business logic: IWsusService (operations, sync, cleanup), IDatabaseService (SQL maintenance), IHealthService (diagnostics, auto-repair), IWindowsServiceManager (service start/stop/status), IFirewallService (netsh rules), ISettingsService (JSON persistence), ILogService (Serilog wrapper)
3. Infrastructure — Low-level: ProcessRunner (async process execution with stdout/stderr capture), SqlHelper (connection factory, query helpers, sysadmin check), FileSystemHelper (path validation)
4. `WsusManager.Tests` (xUnit) — Unit tests for all Core services and ViewModels using mocked interfaces
5. `WsusManager.ApiShim` (optional, .NET Framework 4.8) — Only if WSUS COM API operations prove necessary; communicates via JSON stdin/stdout

**Build order dependency (non-negotiable):**
1. Infrastructure + Models (no dependencies)
2. SettingsService + LogService (needed by all services)
3. WindowsServiceManager + FirewallService + DatabaseService
4. WsusService + HealthService
5. MainViewModel + DI host
6. MainWindow XAML + dashboard views
7. Dialog ViewModels + Views

### Critical Pitfalls

1. **WSUS managed API incompatible with .NET 9** — Do not reference `Microsoft.UpdateServices.Administration.dll`. Use direct SQL against SUSDB for all database operations and `ProcessRunner` wrapping `wsusutil.exe` for export/import/reset/checkhealth. Add a CI check that the project has zero references to this assembly. Treat this as absolute — it works on some dev machines (GAC entries) but fails on every clean Server 2019 deployment.

2. **Single-file EXE extraction blocked by antivirus on air-gapped servers** — Use `IncludeAllContentForSelfExtract=true` in the publish profile. This embeds all content in the EXE rather than extracting to `%TEMP%\.net\`, which antivirus heuristics treat as a dropper. Validate the published EXE on a clean Windows Server 2019 VM with AV enabled before declaring the deployment model functional.

3. **Async void event handlers silently swallow exceptions** — Every `async void` WPF event handler must wrap its body in try/catch that routes to a centralized error handler. All actual operation logic lives in `async Task` methods, never in `async void` handlers directly. Use `RelayCommand` from CommunityToolkit.Mvvm — it enforces this pattern automatically.

4. **Rewrite silently drops accumulated edge-case behaviors** — Before writing any C# operation, read the corresponding PowerShell module function in full including catch blocks. Port the Pester tests to xUnit test-first. Critical behaviors that must be explicitly preserved: SQL `CommandTimeout = 0` for maintenance operations (default 30s will time out), batch size of 100 for `spDeleteUpdate`, two-step supersession removal, DB shrink retry (3 attempts, 30s delay when backup is running), and `BeginOutputReadLine()` called immediately after `Process.Start()`.

5. **UI thread blocking from "looks async" code** — Code after an `await` resumes on the UI thread. Any blocking call (ServiceController.WaitForStatus, file I/O, SQL connection establishment) after an `await` in a command handler freezes the UI. Keep all blocking work inside `Task.Run()`. Never use `Dispatcher.Invoke` — its presence in code signals an architectural mistake. Use `IProgress<T>` for log-line reporting from background threads.

---

## Implications for Roadmap

### Phase 1: Foundation and Build Infrastructure

**Rationale:** Every subsequent phase depends on this. The WSUS API incompatibility constraint, the UAC manifest, the single-file publish configuration, the dark theme approach, and the async operation pattern must all be established before any feature code is written. Getting these wrong late is expensive.

**Delivers:** Compilable solution structure with correct csproj configuration, DI host wiring, ProcessRunner with async output capture, SqlHelper with connection pooling, the `RunOperationAsync` wrapper pattern, UAC manifest, dark ResourceDictionary theme, single-file publish pipeline, and CI/CD that validates the EXE on a clean Windows Server environment.

**Addresses from FEATURES.md:** Single-file EXE deployment, admin privilege enforcement, dark theme, DPI awareness

**Avoids from PITFALLS.md:**
- Pitfall 1 (WSUS API incompatibility): CI check blocks any reference to `Microsoft.UpdateServices.Administration`
- Pitfall 2 (AV blocking single-file EXE): `IncludeAllContentForSelfExtract=true` in publish profile
- Pitfall 3 (async void exceptions): `RunOperationAsync` wrapper established before any operation code
- Pitfall 4 (UI thread blocking): pattern enforced in code review gate
- Pitfall 10 (Fluent theme crashes): explicit ResourceDictionary, no `Application.ThemeMode`
- Pitfall 11 (UAC manifest missing): manifest embedded from project creation

**Research flag:** Standard patterns — no additional research needed. WPF/DI bootstrapping is well-documented.

---

### Phase 2: Application Shell and Dashboard

**Rationale:** The dashboard is the daily-use surface. It requires all the service integrations that every subsequent operation phase also needs: WindowsServiceManager, DatabaseService for size queries, and the PeriodicTimer refresh pattern. Building this second validates that DI, data binding, and background refresh work correctly before adding operation complexity.

**Delivers:** MainWindow XAML with nav structure, MainViewModel with observable dashboard properties, 30-second PeriodicTimer refresh (no Dispatcher.Invoke), service status cards (SQL/WSUS/IIS), DB size with 10GB limit warning, last sync display, settings persistence, server mode toggle (Online/Air-Gap), operation log panel stub.

**Uses from STACK.md:** CommunityToolkit.Mvvm observables, `System.ServiceProcess.ServiceController` with `sc.Refresh()` pattern, `Microsoft.Data.SqlClient` for size query, `PeriodicTimer` for refresh

**Implements from ARCHITECTURE.md:** Pattern 5 (Dashboard State via Polling + Dispatcher-Free Updates), IWindowsServiceManager, IDatabaseService (size/sync queries only), ISettingsService

**Avoids from PITFALLS.md:**
- Pitfall 6 (ServiceController caching): `sc.Refresh()` or new instance per read established here
- Pitfall 8 (progress flooding): dashboard refresh throttled to 30s, never per-row

**Research flag:** Standard patterns. PeriodicTimer and ObservableProperty are well-documented.

---

### Phase 3: Core Operations — Diagnostics and Service Management

**Rationale:** Health check + auto-repair is the most commonly used operation and validates the full operation execution pattern (async command, cancellation, progress reporting, IProgress, log panel output). Service management (start/stop SQL/WSUS/IIS) is a prerequisite for the repair flow and for the installation wizard.

**Delivers:** Health check (SQL connectivity, WSUS service, IIS app pool, firewall 8530/8531, content directory permissions), auto-repair for detected failures, service start/stop quick actions, cancel button wired to CancellationTokenSource.

**Uses from STACK.md:** ProcessRunner (`netsh advfirewall`), ServiceController (Refresh pattern), `Microsoft.Data.SqlClient` (SQL connectivity test)

**Implements from ARCHITECTURE.md:** Pattern 2 (Async Command Pattern with CancellationToken), IHealthService, IFirewallService, Pattern 3 (OperationResult)

**Avoids from PITFALLS.md:**
- Pitfall 5 (rewrite drops edge cases): port Pester tests from `Tests/WsusAutoDetection.Tests.ps1` and `Tests/WsusHealth.Tests.ps1` to xUnit before implementing
- Pitfall 9 (process stdout deadlock): ProcessRunner uses `BeginOutputReadLine()` + `BeginErrorReadLine()` established in Phase 1

**Research flag:** Standard patterns for service management. Health check logic should be reviewed against PowerShell source before coding.

---

### Phase 4: Database Operations — Deep Cleanup and Backup/Restore

**Rationale:** Deep cleanup is the highest-complexity operation (6-step pipeline with batching, retry logic, and unlimited SQL timeouts). Building it as a dedicated phase allows full focus on the edge cases documented in PITFALLS.md. Database backup and restore are grouped here because they share SqlHelper and the same safety preconditions (sysadmin check).

**Delivers:** Full 6-step deep cleanup pipeline (WSUS built-in cleanup, supersession removal for declined, batched supersession removal for superseded, batched spDeleteUpdate at 100/batch, index rebuild, DB shrink with 3-attempt retry), database backup (SUSDB backup via SQL), database restore, sysadmin permission check before all DB operations, before/after size reporting.

**Uses from STACK.md:** `Microsoft.Data.SqlClient` with `CommandTimeout = 0` for maintenance, connection string `Data Source=localhost\SQLEXPRESS;Initial Catalog=SUSDB;Integrated Security=true;TrustServerCertificate=true`

**Implements from ARCHITECTURE.md:** IDatabaseService (full implementation), Pattern 3 (OperationResult for DB failures vs programming errors), operation flow diagram for deep cleanup

**Avoids from PITFALLS.md:**
- Pitfall 5 (rewrite drops edge cases): port `Tests/WsusDatabase.Tests.ps1`, review `WsusDatabase.psm1` in full before implementing
- Pitfall 7 (SQL command timeout): every `SqlCommand` in this phase has explicit `CommandTimeout`; code review gate enforced
- Pitfall 8 (progress flooding): throttle to per-batch reporting, not per-update

**Research flag:** Needs careful review of PowerShell source. The batching logic (100/call for spDeleteUpdate, 10k/call for supersession records), retry on shrink, and two-step supersession removal are not obvious from documentation and must be extracted from the existing codebase.

---

### Phase 5: WSUS Operations — Sync, Export, and Import

**Rationale:** Online sync (profile-based), air-gap export (full + differential), and import are grouped because they all flow through the same ProcessRunner + wsusutil.exe integration path. These are the operations most critical for GA-ASI's air-gap network use case.

**Delivers:** Online sync with Full/Quick/Sync-Only profiles, export full (complete WSUS content mirror), export differential (days-based filter), import from USB source, content reset (`wsusutil reset`) for post-import air-gap state, server mode toggle that hides/shows relevant operations.

**Uses from STACK.md:** ProcessRunner wrapping `wsusutil.exe` at `%ProgramFiles%\Update Services\Tools\wsusutil.exe`, `System.IO` for file copy operations with buffered streams

**Implements from ARCHITECTURE.md:** IWsusService (sync, export, import operations), WSUS Administration Shim pattern (process-based isolation for wsusutil)

**Avoids from PITFALLS.md:**
- Pitfall 5 (edge cases): review `WsusExport.psm1` and `Invoke-WsusMonthlyMaintenance.ps1` in full; port export path validation and pre-flight checks
- Pitfall 9 (process stdout deadlock): ProcessRunner pattern from Phase 1 handles this

**Research flag:** Needs review of PowerShell source for export/import. Differential export behavior, path handling, and the content directory root (`C:\WSUS\`, not `C:\WSUS\wsuscontent\`) are non-obvious requirements.

---

### Phase 6: WSUS Installation Wizard and Scheduled Tasks

**Rationale:** The installation wizard is high complexity (multi-step, downloads SQL Express, configures WSUS, firewall, GPO path) but is only used once per server. Deferred until core operations are solid. Scheduled tasks are grouped here because they depend on the operational workflows established in Phases 3-5.

**Delivers:** WSUS + SQL Express installation wizard (guided multi-step UI, path selection, SQL download check, WSUS role configuration, firewall setup), scheduled task creation for maintenance and sync operations, credential prompting for domain task execution.

**Uses from STACK.md:** `Microsoft.Win32.TaskScheduler` NuGet or `ProcessRunner` + `schtasks.exe`, ProcessRunner for wsusutil and installation process execution

**Implements from ARCHITECTURE.md:** Dialog ViewModel pattern per dialog (Install wizard dialog VM, Schedule dialog VM)

**Avoids from PITFALLS.md:**
- Pitfall 5 (edge cases): review `Install-WsusWithSqlExpress.ps1` in full before implementing; NonInteractive mode handling is critical to avoid dialog lockup

**Research flag:** Scheduled task library (`Microsoft.Win32.TaskScheduler`) needs verification on Windows Server 2019 with domain credentials. If it proves problematic, fall back to `schtasks.exe` via ProcessRunner.

---

### Phase 7: Polish, Testing, and Distribution

**Rationale:** Final phase locks in quality. EXE validation tests, startup benchmarking, AV-on-server deployment validation, CI/CD pipeline with clean Server 2019 runner.

**Delivers:** xUnit EXE validation tests (PE header, 64-bit, version info, startup benchmark), GitHub Actions workflow replacing PS2EXE step with `dotnet publish`, deployment validation on clean Windows Server 2019 VM with AV enabled, full test suite (service unit tests, ViewModel tests, integration tests), updated documentation.

**Avoids from PITFALLS.md:**
- Pitfall 2 (AV blocking): validated in this phase on real target environment
- Pitfall 12 (WSUS API "works on dev" false confidence): CI runs on clean Server 2019 agent

**Research flag:** Standard patterns. CI/CD pipeline changes are mechanical.

---

### Phase Ordering Rationale

- **Infrastructure first (Phase 1):** The WSUS API incompatibility constraint, UAC manifest, and async operation pattern must be enforced before any feature code is written. Wrong decisions here contaminate every subsequent phase.
- **Dashboard second (Phase 2):** Validates the DI wiring, data binding, and service integration before adding operation complexity. Provides the visible skeleton that all subsequent phases hang features onto.
- **Operations in dependency order (Phases 3-6):** Architecture research confirmed the build order: service management underlies health check underlies database operations. Each phase depends on the prior phase's infrastructure.
- **Installation wizard last (Phase 6):** High complexity, low frequency. Core operations must be solid before building the path that is used exactly once per server.
- **Polish last (Phase 7):** Cannot validate deployment until the product is complete.

---

### Research Flags

**Needs additional research or careful source review during planning:**
- Phase 4 (Deep Cleanup): SQL batching logic, supersession removal order, and DB shrink retry must be extracted from PowerShell source `WsusDatabase.psm1` before writing specs
- Phase 5 (Sync/Export/Import): Differential export behavior, wsusutil argument specifics, content directory root conventions
- Phase 6 (Installation Wizard): `Microsoft.Win32.TaskScheduler` NuGet library compatibility on Server 2019 with domain credentials needs validation

**Standard patterns — skip research-phase:**
- Phase 1 (Foundation): WPF DI bootstrapping and publish configuration are fully documented in official .NET docs
- Phase 2 (Dashboard): ObservableProperty, PeriodicTimer, ServiceController patterns are canonical .NET
- Phase 7 (Polish/CI): GitHub Actions dotnet publish pipeline is standard

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All recommendations sourced from official Microsoft docs and verified NuGet package listings. .NET 9 WPF Fluent theme confirmed on Windows Server 2019 (build 1809). One known .NET 9 regression (dotnet/sdk#43461) tracked. |
| Features | HIGH | Existing v3.8.12 codebase provides validated production feature set. Competitor landscape is MEDIUM (WSUS ecosystem thin/deprecated, few comparable tools). Feature priority matrix is judgment-based. |
| Architecture | HIGH | WPF/MVVM/DI patterns are well-established. WSUS API incompatibility confirmed via official GitHub issue. Single-EXE publication known regression tracked. ProcessRunner pattern proven in existing codebase. |
| Pitfalls | HIGH | Core pitfalls sourced from official .NET GitHub issues and Microsoft docs. Edge-case behaviors sourced from production PowerShell codebase (first-party). |

**Overall confidence: HIGH**

### Gaps to Address

- **.NET 9 self-contained publish regression (dotnet/sdk#43461):** WPF assemblies may be missing from publish output. Mitigation is to pin to .NET 8 for first production release if the regression manifests. Track .NET 10 (Nov 2025, already available) as the upgrade path. Validate the published EXE on a clean Server 2019 VM in Phase 7 before any release decision.

- **`Application.ThemeMode` experimental status:** The WPF Fluent dark theme API is experimental in .NET 9 with known threading crashes on system theme changes. Mitigated by using explicit ResourceDictionary dark palette instead. Re-evaluate for .NET 10 which stabilizes the API.

- **WsusApiShim necessity:** It is unclear from research whether auto-approval with granular classification control requires the WSUS COM API or whether direct SQL + wsusutil can achieve the same result. The v3.8.x codebase uses `MaxAutoApproveCount = 200` and `Definition Updates` auto-approval via PowerShell COM. If the C# implementation cannot replicate this via SQL alone, the optional WsusApiShim (.NET Framework 4.8 helper process) must be built. Assess in Phase 5.

- **Scheduled task credential handling:** The `Microsoft.Win32.TaskScheduler` NuGet library is recommended over `schtasks.exe` for type safety, but has not been validated on Windows Server 2019 with domain credentials in the context of this project. Validate early in Phase 6 with a fallback to `schtasks.exe` via ProcessRunner.

---

## Sources

### Primary (HIGH confidence)
- [What's New in WPF for .NET 9 — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/whats-new/net90) — Fluent theme, ThemeMode API, Server 2019 compatibility
- [Single-File Deployment Overview — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) — PublishSingleFile constraints, extraction behavior, NativeAOT limitations
- [NuGet: Microsoft.Data.SqlClient 6.1.4](https://www.nuget.org/packages/Microsoft.Data.SqlClient) — latest stable, .NET 8+ requirement
- [NuGet: CommunityToolkit.Mvvm 8.4.0](https://www.nuget.org/packages/CommunityToolkit.Mvvm) — .NET 9 compatibility
- [dotnet/core Issue #5736](https://github.com/dotnet/core/issues/5736) — WSUS managed API incompatibility with .NET Core/5+
- [dotnet/runtime#2300](https://github.com/dotnet/runtime/issues/2300) — Single-file EXE antivirus extraction blocking
- [dotnet/sdk#43461](https://github.com/dotnet/sdk/issues/43461) — .NET 9 self-contained publish WPF assembly regression
- [Process.StandardOutput docs — deadlock warning](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.standardoutput) — stdout deadlock
- [ServiceController docs — Refresh() requirement](https://learn.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicecontroller) — status caching
- [CommunityToolkit.Mvvm IoC documentation](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/ioc) — DI pattern
- [.NET Generic Host documentation](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host) — host setup
- [Microsoft Q&A — WSUS APIs with C#](https://learn.microsoft.com/en-us/answers/questions/1298593/how-to-use-the-wsus-apis-with-c-in-visual-studio) — API incompatibility confirmation
- [WPF .NET 9 ThemeMode experimental status](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/whats-new/net90) — experimental API warning
- [UAC manifest configuration](https://learn.microsoft.com/en-us/cpp/build/reference/manifestuac-embeds-uac-information-in-manifest) — requireAdministrator
- GA-WsusManager CLAUDE.md — 12 documented anti-patterns, v3.8.x production feature set, edge case behaviors (first-party)
- [WSUS Deprecation Announcement — Microsoft TechCommunity (September 2024)](https://techcommunity.microsoft.com/blog/windows-itpro-blog/windows-server-update-services-wsus-deprecation/4250436)

### Secondary (MEDIUM confidence)
- [Optimize-WsusServer — GitHub (awarre)](https://github.com/awarre/Optimize-WsusServer) — competitor feature analysis
- [WSUS Maintenance Guide — Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide) — maintenance best practices
- [Should You Use WPF with .NET in 2025? — Inedo Blog](https://blog.inedo.com/dotnet/wpf-on-dotnet) — WPF viability assessment
- [2025 Survey of Rust GUI Libraries — boringcactus](https://www.boringcactus.com/2025/04/13/2025-survey-of-rust-gui-libraries.html) — Rust alternative rejection
- [Brian Lagunas — Progress reporting WPF UI freeze](https://brianlagunas.com/does-reporting-progress-with-task-run-freeze-your-wpf-ui/) — progress throttling
- [Rick Strahl — Async void event handling in WPF](https://weblog.west-wind.com/posts/2022/Apr/22/Async-and-Async-Void-Event-Handling-in-WPF) — async void pitfall
- [Offline Windows Patching for Air-Gapped Networks — BatchPatch](https://batchpatch.com/offline-windows-patching-for-isolated-or-air-gapped-networks) — air-gap feature validation
- [Serilog .NET 9 Structured Logging — Medium](https://medium.com/@michaelmaurice410/how-structured-logging-with-serilog-in-net-9-980229322ebe) — Serilog compatibility

---

*Research completed: 2026-02-19*
*Ready for roadmap: yes*
