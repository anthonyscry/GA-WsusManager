# GA-WsusManager v4 — C# Rewrite

## What This Is

A production-ready C#/.NET 8 WPF application for managing WSUS servers with SQL Server Express on Windows Server 2019+. Delivers full feature parity with the PowerShell v3.8.12 in a single-file EXE with zero threading bugs, sub-second startup, and native async operations. Includes a complete client troubleshooting toolkit with WinRM remote operations, mass host management, and PowerShell script generation for air-gapped environments. Built for GA-ASI IT administrators managing critical WSUS infrastructure.

## Core Value

Rock-solid stability — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure on production servers.

## Requirements

### Validated

- ✓ Single-file EXE distribution (no Scripts/Modules folders) — v4.0
- ✓ Sub-second application startup — v4.0
- ✓ Native async operations (no threading hacks) — v4.0
- ✓ Modernized dark theme UI — v4.0
- ✓ Type-safe compiled code — v4.0
- ✓ All PowerShell module functionality ported — v4.0
- ✓ 257 xUnit tests covering all services and ViewModel logic — v4.0
- ✓ 62 v1 requirements implemented and verified — v4.0

- ✓ .NET 8 SDK compatibility (retarget from .NET 9) — v4.1
- ✓ App launches and UI renders correctly with active nav highlighting — v4.1
- ✓ 5 critical operation bugs fixed (sync, cleanup, health check) — v4.1
- ✓ Button CanExecute refresh for proper visual disabling — v4.1
- ✓ 263 xUnit tests passing — v4.1

- ✓ Editable settings dialog with JSON persistence and immediate effect — v4.2
- ✓ Dashboard mode toggle with manual Online/Air-Gap override — v4.2
- ✓ Operation progress bar, step tracking, success/failure banners — v4.2
- ✓ Real-time dialog validation (Install, Transfer, Schedule) — v4.2
- ✓ WinRM client management: cancel stuck jobs, force check-in, test connectivity, diagnostics — v4.2
- ✓ Error code lookup (20 common WSUS/WU codes) — v4.2
- ✓ Mass GPUpdate across multiple hosts — v4.2
- ✓ Script Generator producing self-contained PowerShell fallback scripts — v4.2
- ✓ 336 xUnit tests passing — v4.2

- ✓ Theme infrastructure with runtime color-scheme swapping — v4.3
- ✓ 6 built-in dark-family themes (Default Dark, Just Black, Slate, Serenity, Rose, Classic Blue) — v4.3
- ✓ Theme picker UI in Settings with live preview swatches — v4.3
- ✓ Cancel-to-revert behavior and JSON persistence for theme selection — v4.3
- ✓ WCAG 2.1 AA compliant color contrast across all themes — v4.3
- ✓ 336 xUnit tests passing — v4.3

- ✓ Coverlet coverage infrastructure with branch analysis — v4.4
- ✓ 70% branch coverage quality gate with CI enforcement — v4.4
- ✓ ReportGenerator HTML coverage artifacts in CI/CD — v4.4
- ✓ 46+ edge case tests for null inputs, empty collections, boundaries — v4.4
- ✓ 31+ exception path tests for SQL, Windows services, WinRM — v4.4
- ✓ 455 xUnit tests passing (+119 from v4.3) — v4.4

- ✓ Zero compiler warnings with Roslyn analyzers — v4.4
- ✓ .editorconfig for consistent code style across IDEs — v4.4
- ✓ Coverlet coverage infrastructure (84% line / 62% branch) — v4.4
- ✓ ReportGenerator HTML coverage artifacts in CI/CD — v4.4
- ✓ XML documentation for public APIs with DocFX — v4.4
- ✓ Code refactoring: consolidated database size query to ISqlService — v4.4
- ✓ Async/await patterns audited (already optimal) — v4.4
- ✓ BenchmarkDotNet infrastructure with operation baselines — v4.4
- ✓ Memory leak detection (StringBuilder, timer cleanup, IDisposable) — v4.4
- ✓ Comprehensive documentation: README, CONTRIBUTING, CI/CD, releases, architecture — v4.4

- ✓ 30% startup time reduction via parallelized initialization — v4.5
- ✓ Dashboard virtualization for 2000+ computers — v4.5
- ✓ Lazy-loaded update metadata (100-item pagination) — v4.5
- ✓ Batched log panel updates (90% UI overhead reduction) — v4.5
- ✓ Sub-100ms theme switching with pre-loaded themes — v4.5
- ✓ 5 global keyboard shortcuts (F1, F5, Ctrl+S, Ctrl+Q, Esc) — v4.5
- ✓ Full keyboard navigation (Tab, arrows, Enter/Space) — v4.5
- ✓ 45 AutomationId attributes for UI automation — v4.5
- ✓ WCAG 2.1 AA compliance (55 contrast tests passing) — v4.5
- ✓ Dialog centering on owner window — v4.5
- ✓ Estimated time remaining for long operations — v4.5
- ✓ Loading indicators on operation buttons — v4.5
- ✓ Actionable error messages with "To fix:" steps — v4.5
- ✓ Consistent success/failure banners (✓/✗/⚠) — v4.5
- ✓ Tooltip help text on all interactive buttons — v4.5
- ✓ 8 configurable settings across 4 categories — v4.5
- ✓ Settings validation with min/max ranges — v4.5
- ✓ Reset to defaults functionality — v4.5
- ✓ Window state persistence — v4.5
- ✓ Real-time filtering (300ms debounce) — v4.5
- ✓ Status/approval/classification filters — v4.5
- ✓ Case-insensitive search — v4.5
- ✓ CSV export (UTF-8 BOM for Excel) — v4.5
- ✓ Export respects filters — v4.5
- ✓ Progress dialog with cancellation — v4.5
- ✓ 53 new tests (593 total, 100% passing) — v4.5
- ✓ 6 performance benchmarks (Phase 25 verification) — v4.5
- ✓ Documentation updates (README, CHANGELOG, CLAUDE.md) — v4.5

### Active

**Current Milestone: Planning Next Enhancement**

**Completed:** v4.5 Enhancement Suite (shipped 2026-02-22)

**Goal for next milestone:** TBD — user feedback analysis from v4.5 deployment

**Potential areas:** Real-time dashboard monitoring, advanced reporting, multi-server management

### Out of Scope

- Mobile or web-based interface — desktop-only for server administration
- Linux/macOS support — Windows Server only (WSUS is Windows-only)
- Server 2016 support — targeting 2019+ only
- Real-time multi-server management — single server at a time
- PowerShell script backward compatibility — clean break from PS codebase
- Building on C# POC — started fresh per user preference
- Active Directory browser — use existing AD tools, just accept hostnames
- Client-side agent/service — admin tool only, not a client endpoint
- SCCM/Intune integration — different tooling ecosystem

## Context

### Current State
- **Version:** v4.5 Enhancement Suite (shipped 2026-02-22)
- **Phases:** 31 phases complete, 94 plans delivered
- **Codebase:** ~22,000 LOC C#/XAML across 110+ files
- **Tech stack:** C#/.NET 8, WPF, CommunityToolkit.Mvvm, Serilog, xUnit + Moq + Coverlet + BenchmarkDotNet
- **Tests:** 593 xUnit tests (84% line / 62% branch coverage maintained)
- **Quality:** Zero compiler warnings, .editorconfig enforced, Roslyn analyzers enabled
- **Docs:** README, CONTRIBUTING, CHANGELOG, CLAUDE.md, docs/api/
- **CI/CD:** GitHub Actions — build, test, coverage, benchmarks, publish, release automation
- **Distribution:** Single self-contained win-x64 EXE + DomainController/ folder
- **Themes:** 6 built-in dark-family themes with runtime switching
- **v4.5 Features:** Performance (30% faster startup), Keyboard shortcuts (5), Accessibility (WCAG AA), Settings (8), Data Filtering, CSV Export

### Technical Environment
- Windows Server 2019/2022 with WSUS role installed
- SQL Server Express 2022 (localhost\SQLEXPRESS) with 10GB limit
- SUSDB database for WSUS metadata
- Standard paths: C:\WSUS\ (content), C:\WSUS\Logs\ (logs)
- Ports: 8530 (HTTP), 8531 (HTTPS)
- Air-gapped networks require USB-based export/import workflow

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full C# rewrite (not incremental port) | PowerShell had fundamental threading/deployment limitations | ✓ Good — eliminated 12+ anti-patterns |
| Start fresh (ignore C# POC) | Clean architecture with modern patterns | ✓ Good — cleaner DI and MVVM |
| Single-file EXE distribution | Simplifies deployment on production servers | ✓ Good — no Scripts/Modules folders |
| .NET 8 self-contained | No runtime installation required, .NET 8 LTS available on dev machines | ✓ Good — works on clean Windows Server |
| Drop Server 2016 support | Allows targeting modern .NET runtime | ✓ Good — simplified targeting |
| CommunityToolkit.Mvvm for MVVM | Source generators, less boilerplate | ✓ Good — clean ViewModel pattern |
| Runtime-load WSUS API assembly | Ships with WSUS role, not NuGet | ✓ Good — no compile-time dependency |
| schtasks.exe for scheduled tasks | Simpler than COM TaskScheduler API | ✓ Good — no NuGet dep needed |
| Shell out to PS for WSUS install | Install script too complex to rewrite | ✓ Good — reuses proven logic |
| Separate CI workflow (build-csharp.yml) | Keeps PowerShell build.yml untouched | ✓ Good — no conflicts |
| Settings dialog as modal (not panel) | Configuration is transient, not persistent view | ✓ Good — always accessible |
| Sequential WinRM for mass operations | Prevent network saturation on large batches | ✓ Good — reliable for 50+ hosts |
| Verbatim strings for PS script templates | Avoids C# interpolation conflicts with PowerShell $() | ✓ Good — clean separation |
| WinRM pre-check before every remote op | Fail fast with clear message and Script Generator guidance | ✓ Good — better UX than timeout |
| 70% branch coverage quality gate (Phase 18) | Balances quality with practicality; line coverage alone misses critical paths | ✓ Good — revealed 7 NullReference bugs during test development |
| Task.WhenAll for parallel initialization (Phase 25) | 30% startup reduction by parallelizing independent operations | ✓ Good — settings load + dashboard fetch run concurrently |
| Lazy-loading with 5-min cache TTL (Phase 25) | Separates summary counts from detailed metadata | ✓ Good — dashboard refresh 50-70% faster |
| 100-item pagination for updates (Phase 25) | Balances SQL query performance with UI responsiveness | ✓ Good — handles 1000+ updates efficiently |
| Theme pre-loading at startup (Phase 25) | Load all 6 themes into memory cache | ✓ Good — <10ms theme switching (was 300-500ms) |
| F1/F5/Ctrl+S/Ctrl+Q/Esc shortcuts (Phase 26) | Standard Windows patterns admins expect | ✓ Good — familiar keyboard navigation |
| PascalCase AutomationId naming (Phase 26) | `[Purpose][ControlType]` pattern for UI automation | ✓ Good — predictable for WinAppDriver/FlaUI |
| Progress estimation using BenchmarkDotNet data (Phase 27) | Reuse Phase 22 baselines for time estimates | ✓ Good — accurate without manual timing |
| Three-part error format (Phase 27) | "What failed + Why it matters + Specific action to resolve" | ✓ Good — admins know exactly what to do |
| CollectionView filtering (Phase 29) | O(n) filtering with 300ms debounce for real-time search | ✓ Good — instant feedback without UI lag |
| UTF-8 BOM for CSV export (Phase 30) | Required for Excel to display UTF-8 correctly | ✓ Good — no mojibake in exported data |


## Constraints

- **Target OS**: Windows Server 2019+ (64-bit only)
- **Admin Required**: All operations require elevated privileges
- **SQL Express**: Must work with localhost\SQLEXPRESS and 10GB database limit
- **Air-Gap**: Export/import must work fully offline — no internet dependency
- **Single EXE**: Distribution must be a single executable file
- **WSUS APIs**: Must interact with Microsoft.UpdateServices.Administration and SUSDB directly

---
*Last updated: 2026-02-22 after v4.5 Enhancement Suite milestone*
