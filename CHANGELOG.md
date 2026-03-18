# Changelog

All notable changes to WSUS Manager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.1] - 2026-03-18

### Added
- **Tests/GuiFullTest.ps1** — Full GUI automation test (49 tests, 10 categories) using COM
  UI Automation via scheduled tasks; covers dashboard, panels, dialogs, buttons, log panel
- **docs/GUI-TESTING-LESSONS.md** — 16-section lessons learned document from GUI testing
  on headless Windows Server VMs via SSH tunnels and RDP sessions
- **Tests/FlaUI.Tests.ps1** — 71 FlaUI-based unit tests for AutomationId coverage

### Changed
- Install script synced with Pro version: flexible installer detection, `UPDATEENABLED="0"`
- GUI-tests CI workflow replaces old build.yml (self-hosted runner on triton-ajt)
- `.planning/` C#-era plans archived to `.planning-archive-reverted-c#-era/`

## [4.0.0] - 2026-03-15

### Added
- **WsusDialogs.psm1** — Dialog factory module (`New-WsusDialog`, `New-WsusFolderBrowser`,
  `New-WsusDialogLabel`, `New-WsusDialogButton`, `New-WsusDialogTextBox`); eliminates 6
  copy-pasted dialog boilerplate patterns across the GUI
- **WsusOperationRunner.psm1** — Unified operation lifecycle (`Start-WsusOperation`,
  `Stop-WsusOperation`, `Complete-WsusOperation`, `Find-WsusScript`); timeout watchdog
  per-operation type; replaces ~200 lines of duplicated Terminal/Embedded execution logic
- **WsusHistory.psm1** — Operation history to JSON at `%APPDATA%\WsusManager\history.json`
  (`Write/Get/Clear-WsusOperationHistory`); 100-entry trim; file-lock retry; 23 tests
- **WsusNotification.psm1** — Completion notifications (`Show-WsusNotification`) with
  Windows 10 toast → balloon tip → log-only fallback
- **WsusTrending.psm1** — DB size trending with linear regression over 30 days;
  days-until-full estimate; Critical alert <90 days / Warning <180 days to 10 GB limit
- `Get-WsusHealthScore` in `WsusHealth.psm1` — 0–100 weighted composite health score
  (Services 30, DB size 20, Sync recency 20, Disk space 20, Last operation 10);
  Grade: Green ≥80 / Yellow 50–79 / Red <50 / Unknown if all sources fail
- `Get-WsusHealthWeights` and `Get-WsusOperationTimeout` in `WsusConfig.psm1`
- 9 async dashboard data functions in `WsusAutoDetection.psm1` with 30-second TTL cache
  and consecutive-failure guard (shows "Data unavailable" after 10 failures)
- GUI: Startup splash screen with 4-stage progress bar (`Show-SplashScreen`)
- GUI: History view (📜 History nav button) showing last 50 operations
- GUI: Health Score band on dashboard with color-coded bar and grade label
- GUI: Last Successful Sync timestamp on dashboard (green <7 days / yellow 7–30 / red >30)
- GUI: DB size trend indicator with days-until-full estimate
- GUI: Air-Gap "💾 Create USB Package" button — differential export + SHA-256 manifest
- GUI: Keyboard shortcuts (Ctrl+D=Diagnostics, Ctrl+S=Sync, Ctrl+H=History, Ctrl+R/F5=Refresh)
- GUI: Right-click context menu on log panel ("Copy All" / "Save to File...")
- GUI: System tray minimize — `NotifyIcon` with health-score tooltip, double-click restore,
  right-click context menu (Restore / Exit), dispose on window close
- GUI: Settings dialog expanded with notification, beep, and tray-minimize checkboxes
- New Pester tests: `WsusDialogs.Tests.ps1` (58 tests), `WsusHistory.Tests.ps1` (23 tests),
  `WsusOperationRunner.Tests.ps1` (27 tests); 16 new tests in `WsusConfig.Tests.ps1`;
  18 new tests in `WsusHealth.Tests.ps1`; 25 new tests in `WsusAutoDetection.Tests.ps1`

### Changed
- `WsusAutoDetection.psm1`: dashboard data functions extracted from GUI and made runspace-safe
- `WsusConfig.psm1`: new `Get-WsusHealthWeights` and `Get-WsusOperationTimeout` functions
- `WsusHealth.psm1`: new `Get-WsusHealthScore` function with weighted composite scoring
- GUI operations now record to history and fire completion notifications
- Settings dialog height increased to 430px to accommodate new options
- `CLAUDE.md` updated for v4.0 module architecture and new GUI features

### Fixed
- `WsusDialogs.psm1`: `FolderBrowserDialog` now disposed in `try/finally` (resource leak)
- `WsusOperationRunner.psm1`: watchdog timer closure now captures `Timer` via `$wdData`
  hashtable instead of outer-scope variable (incorrect closure capture)
- `WsusManagementGui.ps1`: `ContextMenuStrip` disposed before `NotifyIcon` on window close

## [3.9.0] - 2026-03-15

### Added
- Monthly maintenance policy now auto-declines ARM64 and 25H2 updates and excludes them from auto-approval

### Changed
- Restored PowerShell-only distribution by removing C# source/workflow/documentation tracks

## [3.8.12] - 2026-02-14

### Fixed
- Corrected TrustServerCertificate compatibility for older SqlServer module versions
- Updated SQL execution wrapper usage in maintenance/management scripts to avoid unsupported parameter errors

## [3.8.11] - 2026-02-14

### Fixed
- TrustServerCertificate compatibility fix for SqlServer module v21.1+ differences

## [3.8.10] - 2026-02-12

### Changed
- Deep Cleanup now performs full 6-step WSUS database maintenance workflow
- Consolidated health check + repair into a single Diagnostics operation

### Fixed
- GitHub Actions artifact/release packaging alignment improvements

## [3.8.9] - 2026-02-10

### Added
- Monthly Maintenance renamed to Online Sync in GUI and workflow text
- Differential export path and export age options
- Definition Updates auto-approval support
- Reset Content action for air-gap recovery workflows

### Changed
- Increased max auto-approve threshold to 200
- Moved GUI/retry magic numbers into `WsusConfig.psm1`

## [3.8.8] - 2026-01-14

### Fixed
- Declined update purge parameter parsing issue
- Shrink retry behavior while backups are active
- Reduced expected noisy purge output errors

[4.0.1]: https://github.com/anthonyscry/GA-WsusManager/compare/v4.0.0...v4.0.1
[4.0.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.9.0...v4.0.0
[3.9.0]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.12...v3.9.0
[3.8.13]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.12...v3.8.13
[3.8.12]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.11...v3.8.12
[3.8.11]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.10...v3.8.11
[3.8.10]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.9...v3.8.10
[3.8.9]: https://github.com/anthonyscry/GA-WsusManager/compare/v3.8.8...v3.8.9
[3.8.8]: https://github.com/anthonyscry/GA-WsusManager/releases/tag/v3.8.8
