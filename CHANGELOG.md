# Changelog

All notable changes to WSUS Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (To be filled in next release)

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

[Unreleased]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.4.0...HEAD
[4.4.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.3.0...v4.4.0
[4.3.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.2.0...v4.3.0
[4.2.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.11...v4.0.0
[3.8.11]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.10...v3.8.11
[3.8.10]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.9...v3.8.10
[3.8.9]: https://github.com/anthonyscry/GA-WsusManager/releases/tag/v3.8.9
