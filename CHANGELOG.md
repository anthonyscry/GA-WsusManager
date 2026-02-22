# Changelog

All notable changes to WSUS Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.5.0] - 2026-02-21

### Added

#### Performance (Phase 25)
- Parallelized application initialization for 30% faster startup
- Theme pre-loading for sub-100ms theme switching
- List virtualization for handling 2000+ computers without UI freezing
- Lazy-loaded update metadata with 5-minute cache TTL
- Batched log panel updates (100 lines, 100ms) to reduce UI thread overhead

#### Accessibility (Phase 26)
- Global keyboard shortcuts: F1 (Help), F5 (Refresh), Ctrl+S (Settings), Ctrl+Q (Quit), Escape (Cancel)
- AutomationId attributes on all interactive elements for UI automation testing
- Keyboard navigation with Tab, arrow keys, Enter, and Space support
- WCAG 2.1 AA contrast compliance verification for all 6 themes
- Dialog centering on owner window for cohesive UX

#### Settings (Phase 28)
- Default operation profile setting (Full/Quick/Sync Only)
- Configurable logging level (Debug/Info/Warning/Error/Fatal)
- Log retention policy (days to keep, max file size)
- Window state persistence (size and position)
- Dashboard refresh interval configuration (10s/30s/60s/Disabled)
- Confirmation prompts toggle for destructive operations
- WinRM timeout and retry configuration
- Reset to Defaults button with confirmation dialog

#### Data Views (Phase 29)
- Computer status filter (All/Online/Offline/Error)
- Update approval status filter (All/Approved/Not Approved/Declined)
- Update classification filter (All/Critical/Security/Definition/Updates)
- Real-time search with 300ms debounce
- Filter state persistence across application restarts
- Empty state message when no items match filters

#### Data Export (Phase 30)
- CSV export for computers and updates panels
- UTF-8 BOM encoding for Excel compatibility
- Export respects applied filters
- Progress reporting during export
- Automatic Explorer navigation to exported file

#### Testing (Phase 31)
- Performance benchmark suite for Phase 25 optimizations (6 benchmarks)
- 61 new unit tests for Phases 26, 28, 29, 30
- Code coverage maintained at 84% line coverage

### Changed
- Dashboard refresh uses lazy loading for 50-70% performance improvement
- Log panel batches updates to reduce PropertyChanged notifications by 90%
- Theme switching from file-based to memory-cached (instant feedback)
- Filter dropdowns use CollectionView for O(n) filtering performance

### Performance

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Cold Startup | 1200ms | 840ms | 30% faster |
| Theme Switch | 300-500ms | <10ms | 98% faster |
| Dashboard (2k computers) | 450ms | 180ms | 60% faster |
| Update Metadata | 150ms | 75ms | 50% faster |

### Documentation
- Added keyboard shortcuts section to README
- Added performance benchmarks table
- Added data filtering and export documentation
- Updated CLAUDE.md with new patterns and services

## [4.4.0] - 2026-02-21

### Added
- Test coverage measurement and HTML reporting (Coverlet + ReportGenerator)
- Static analysis with Roslyn analyzers (zero compiler warnings)
- Performance benchmarking infrastructure (BenchmarkDotNet)
- Memory leak detection and prevention
- XML documentation comments for all public APIs
- API reference documentation via DocFX
- CI/CD pipeline documentation with workflow explanations
- Release process documentation with step-by-step checklist
- Architecture documentation (docs/architecture.md)

### Changed
- README.md updated to reflect C# v4.x application (removed PowerShell references)
- CONTRIBUTING.md expanded with testing patterns and CI/CD details
- Code style enforced via .editorconfig and dotnet-format
- All code reformatted to .editorconfig standards (19-GAP-02)

### Fixed
- Fixed all 567 static analysis warnings (zero warnings in Release build)
- Fixed async patterns to prevent deadlocks (ConfigureAwait enforcement)

### Performance
- Startup time baseline: < 2s cold start, < 500ms warm start
- Database operations baseline established
- WinRM operations baseline established
- Memory usage: 50-80MB (stable, no leaks)

## [4.3.0] - 2026-02-21

### Added
- Theme infrastructure with split styles/tokens
- 6 built-in themes (Dark, Light, Blue, Green, Purple, Red)
- Theme picker in Settings dialog with live preview
- DynamicResource for runtime theme switching

### Changed
- Migrated StaticResource to DynamicResource for theme support
- Extracted theme tokens to separate resource dictionaries

## [4.2.0] - 2026-02-21

### Added
- WinRM client management (cancel stuck jobs, force check-in, test connectivity, run diagnostics)
- Error code lookup for 20 common WSUS client error codes
- Client Tools panel in main navigation
- Mass GPUpdate across multiple hosts with per-host progress
- Script Generator producing 5 self-contained PowerShell scripts (fallback for air-gapped hosts)
- Operation progress feedback (indeterminate progress bar, [Step N/M] text)
- Success/failure/cancel banners after operation completion
- Real-time dialog validation for Install, Transfer, and Schedule dialogs
- Editable settings dialog with JSON persistence
- Dashboard mode toggle with manual Online/Air-Gap override

### Changed
- Settings take effect immediately (no app restart required)
- Dashboard mode survives auto-refresh

## [4.1.0] - 2026-02-20

### Added
- Active navigation button highlighting
- CanExecute refresh for proper button disabling during operations

### Fixed
- Retargeted entire solution from .NET 9 to .NET 8 LTS (csproj, CI/CD, test paths)
- Fixed duplicate "WSUS not installed" startup message
- Fixed DeepCleanup Step 4 GUID parameter type (string ? int)
- Fixed online sync classification reflection error
- Fixed age-based decline removal SQL syntax
- Fixed appcmd full path issue in IIS operations
- Fixed boxed int cast bug in service status check
- Fixed button CanExecute not refreshing after operation completion

## [4.0.0] - 2026-02-20

### Added
- Complete C#/.NET 8 WPF rewrite of GA-WsusManager
- Single-file EXE distribution (~15-20 MB)
- MVVM pattern with CommunityToolkit.Mvvm
- Dependency injection with Microsoft.Extensions.DependencyInjection
- Dark-themed dashboard with auto-refresh (30-second interval)
- Server mode toggle (Online vs Air-Gap)
- Log panel with expand/collapse
- Unified diagnostics with auto-repair (services, firewall, permissions, SQL)
- 6-step deep cleanup (supersession records, declined updates, indexes, statistics, shrink)
- Database backup/restore with sysadmin enforcement
- WSUS online sync with 3 profiles (Full, Quick, Sync Only)
- Air-gap export/import via robocopy with differential copy
- Content reset for post-import verification
- Installation wizard (PowerShell orchestration)
- Scheduled task management with profile selection
- GPO deployment (copy scripts to C:\WSUS\WSUS GPO)
- xUnit test suite (257 tests replacing 323 Pester tests)
- GitHub Actions CI/CD pipeline (build, test, publish, release)
- EXE validation tests (PE header, architecture, version info)

### Changed
- Replaced PowerShell GUI (WsusManagementGui.ps1) with C# WPF application
- Replaced Pester tests with xUnit tests
- Replaced PS2EXE build with dotnet publish

### Removed
- PowerShell build process (moved to legacy workflow: build-powershell.yml)

## [3.8.11] - 2025-02-14 (PowerShell version)

### Fixed
- TrustServerCertificate compatibility fix for SqlServer module v21.1

## [3.8.10] - 2025-02-12 (PowerShell version)

### Fixed
- Deep Cleanup now performs full database maintenance (was incomplete)
- Unified Health Check + Repair into single Diagnostics operation
- GitHub Actions workflow fixes (artifact naming, release automation)

## [3.8.9] - 2025-02-10 (PowerShell version)

### Added
- Renamed Monthly Maintenance to Online Sync
- Export path options (Full/Differential with age filter)
- Definition Updates auto-approval

### Changed
- MaxAutoApproveCount increased to 200

[Unreleased]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.5.0...HEAD
[4.5.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.4.0...v4.5.0
[4.4.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.3.0...v4.4.0
[4.3.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.2.0...v4.3.0
[4.2.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.11...v4.0.0
[3.8.11]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.10...v3.8.11
[3.8.10]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.9...v3.8.10
[3.8.9]: https://github.com/anthonyscry/GA-WsusManager/releases/tag/v3.8.9
