# Changelog

All notable changes to WSUS Manager are documented here.

---

## [3.8.4] - January 2026

### Bug Fixes
- **Fixed**: Export operation hanging when called from GUI
  - Added non-interactive mode to `Invoke-ExportToMedia`
  - New CLI parameters: `-SourcePath`, `-DestinationPath`, `-CopyMode`, `-DaysOld`
  - Skips interactive prompts when DestinationPath is provided
- **Fixed**: GitHub Actions workflow EXE validation tests failing
  - ExeValidation tests now excluded from pre-build test job
  - EXE validation runs after build in build job
  - Uses `-Skip` on Context blocks for reliable Pester 5 behavior
- **Fixed**: Distribution package missing required folders
  - Scripts/ and Modules/ now always included in package

### Features
- **Added**: Export Mode options to Transfer dialog
  - Full copy (all files)
  - Differential copy (last N days)
  - Custom days selector

### Infrastructure
- **Changed**: Build artifacts go to `dist/` folder (gitignored)
- **Changed**: Repository no longer contains build artifacts (exe, zip)
- **Updated**: GitHub Actions workflow for cleaner artifact handling

### Documentation
- **Updated**: CLAUDE.md with Pester skip patterns
- **Updated**: CLAUDE.md with CLI non-interactive mode patterns
- **Updated**: Changelog.md with recent changes

---

## [3.8.3] - January 2026

### Bug Fixes
- **Fixed**: Script not found error when running operations
- **Fixed**: Buttons staying enabled during operations
- **Fixed**: OperationRunning flag not resetting
- **Fixed**: Export using invalid CLI parameters

### Improvements
- **Added**: Disable-OperationButtons / Enable-OperationButtons
- **Updated**: Distribution package includes Scripts/ and Modules/
- **Updated**: QUICK-START.txt with folder structure requirement

---

## [3.8.1] - January 2026

### Features
- **Added**: AsyncHelpers.psm1 module for background operations
- **Added**: DPI awareness (per-monitor on Win 8.1+)
- **Added**: Global error handling wrapper
- **Added**: Startup time logging

### CI/CD
- **Added**: EXE validation Pester tests
- **Added**: Startup benchmark in CI pipeline
- **Added**: PE header validation in CI

---

## [3.8.0] - January 2026

### Bug Fixes
- **Fixed**: All dialogs now close with ESC key
- **Fixed**: PSScriptAnalyzer warnings
- **Fixed**: Build script OneDrive module paths

---

## [3.7.0] - January 2026

### Features
- **Changed**: Output log panel now 250px tall and open by default
- **Changed**: Unified Export/Import into single Transfer dialog
- **Added**: Restore dialog auto-detects backup files
- **Added**: Monthly Maintenance profile selection dialog
- **Added**: Cancel button to stop running operations

### Bug Fixes
- **Fixed**: Install WSUS showing blank window
- **Fixed**: Health Check curly braces output
- **Fixed**: Dashboard log path display

---

## [3.5.2] - January 2026

### Bug Fixes
- **Fixed**: `Start-WsusAutoRecovery` error where `$svc.Refresh()` failed on PSCustomObject
  - Now re-queries service status using `Get-Service` instead of `Refresh()` method
  - Improves compatibility across different PowerShell environments

### Security
- **Added**: SQL injection prevention in `Test-WsusBackupIntegrity`
- **Added**: Path validation functions (`Test-ValidPath`, `Test-SafePath`)
- **Added**: Safe path escaping with `Get-EscapedPath`
- **Added**: DPAPI credential storage documentation

### Performance
- **Improved**: SQL module caching (version checked once at load time)
- **Improved**: Batch service queries (single query instead of 5 individual calls)
- **Added**: Dashboard refresh guard (prevents overlapping refresh operations)
- **Improved**: Test suite optimization with shared module pre-loading

### Code Quality
- **Added**: 323 Pester unit tests across 10 test files
- **Added**: PSScriptAnalyzer code review in build process
- **Fixed**: Renamed `Load-Settings` to `Import-WsusSettings` (approved verb)

### Documentation
- **Updated**: README.md with bug fix notes
- **Updated**: CLAUDE.md with security considerations
- **Updated**: README-CONFLUENCE.md with helpful links
- **Added**: GitHub wiki documentation

---

## [3.5.1] - January 2026

### Performance
- **Improved**: Batch service status queries
- **Added**: Module-level caching for configuration
- **Improved**: Dashboard responsiveness

### Bug Fixes
- **Fixed**: Various minor UI issues

---

## [3.5.0] - January 2026

### Features
- **Added**: Server Mode Toggle (Online/Air-Gap)
  - Toggle switch in sidebar
  - Persists across sessions
  - Shows/hides relevant menu items
- **Added**: Modern WPF GUI
  - Dark theme matching GA-AppLocker style
  - Color-coded status cards
  - Auto-refresh dashboard (30 seconds)
- **Added**: Database Size Indicator
  - Real-time size monitoring
  - Color coding: green (<7GB), yellow (7-9GB), red (>9GB)
  - 10GB SQL Express limit warning
- **Added**: Export/Import Dialogs
  - Folder picker for export destination
  - Full vs Differential export options
  - Days selector for differential exports

### Improvements
- **Improved**: Console output with color coding
- **Improved**: Error handling with descriptive messages
- **Improved**: Settings dialog UX

---

## [3.4.x] - December 2025

### Features
- **Added**: Database size indicator on dashboard
- **Added**: Export/import dialogs with folder pickers
- **Added**: Quick action buttons

### Improvements
- **Improved**: GUI layout and styling
- **Improved**: Error messaging

---

## [3.3.x] - December 2025

### Features
- **Added**: Health + Repair functionality
- **Added**: Firewall rule management
- **Added**: Permission verification

### Modules
- **Added**: WsusFirewall.psm1
- **Added**: WsusPermissions.psm1
- **Added**: WsusHealth.psm1

---

## [3.2.x] - November 2025

### Features
- **Added**: Monthly maintenance automation
- **Added**: Database optimization routines
- **Added**: Index management

### Modules
- **Added**: WsusDatabase.psm1
- **Added**: WsusServices.psm1

---

## [3.1.x] - November 2025

### Features
- **Added**: WPF GUI application
- **Added**: Dashboard with status cards
- **Added**: PS2EXE compilation

### Infrastructure
- **Added**: build.ps1 script
- **Added**: Module architecture

---

## [3.0.0] - October 2025

### Major Rewrite
- **Changed**: Modular architecture
- **Added**: PowerShell modules
- **Added**: Configuration management
- **Added**: Centralized logging

---

## [2.x] - 2025

### Features
- Air-gapped network support
- Export/import functionality
- Basic CLI operations

---

## [1.x] - 2024-2025

### Initial Release
- Basic WSUS management scripts
- SQL Express integration
- Installation automation

---

## Versioning

WSUS Manager uses semantic versioning:

```
MAJOR.MINOR.PATCH

MAJOR - Breaking changes
MINOR - New features (backwards compatible)
PATCH - Bug fixes (backwards compatible)
```

### Version Locations

Update version in:
1. `build.ps1` - `$script:Version`
2. `Scripts/WsusManagementGui.ps1` - `$script:AppVersion`
3. `CLAUDE.md` - Current Version

---

## Links

- [[Home]] - Documentation home
- [[Installation Guide]] - Setup instructions
- [[Developer Guide]] - Contributing guide
