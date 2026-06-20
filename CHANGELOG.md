# Changelog

All notable changes to WSUS Manager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.1.0] - 2026-06-20

### Added
- Add one-click **Fix SQL Login** to grant the current operator SQL sysadmin access.
- Add SQL sysadmin grants during install so first maintenance runs do not fail preflight.
- Add deeper diagnostics with SQL, IIS, service, firewall, content ACL, and download checks.
- Add repair plans and auto-fixes for content permissions, SQL login, services, and WSUS reset.
- Add Online Sync product picker with additive product sync and safer default selections.
- Add .NET Framework, Visual Studio 2022, Exchange 2019, and Defender product defaults.
- Add split server/workstation WSUS GPO backups plus inbound and outbound firewall GPOs.
- Add OU creation for Member Servers, WSUS Server, Workstations, and Domain Controllers links.
- Add Live Terminal streaming for Robocopy and long-running operations.
- Add themed WPF popups with scrollable readable content and native dialog fallback.
- Add build/package metadata copying so deployed apps can read `metadata.json`.
- Add CI, syntax-check, and ship-readiness validation helpers for release verification.

### Changed
- Restore the app to the v4.0.5 PowerShell/WPF baseline while keeping v4.1 operational fixes.
- Reorganize navigation into Setup, Maintenance, collapsible Online Operations, and Diagnostics.
- Move Restore DB, Robocopy, and Deep Cleanup to the Maintenance section in operator order.
- Move Online Sync and Schedule Task under collapsed Online Operations.
- Move Fix SQL Login under collapsed Diagnostics.
- Recalculate Health Score from services, SUSDB size, and content-drive free space only.
- Preserve existing WSUS subscriptions when adding selected sync products before sync starts.
- Keep Robocopy progress visible in Live Terminal and embedded logs for post-run review.
- Recommend at least 200 GB for the WSUS server/content drive across app help and docs.
- Rewrite air-gap restore guidance around approved USB media, Restore DB, Robocopy, and Reset Content.
- Document that the whole `DomainController/` folder must be copied to the DC before GPO import.
- Align GUI Help, About, README, Quick Start, SOP, wiki, and Confluence docs to v4.1.0.
- Keep PowerShell 5.1-safe UTF-8/BMP UI symbols for compiled GUI reliability.
- Use `metadata.json` as the release version source for build output and runtime helpers.
- Rename the release package to `GA-WsusManager-v4.1.0.zip` and publish only the zip asset.
- Move icon/logo assets into an `icons/` folder in source, `dist/`, and packaged zips.

### Fixed
- Fix GPO import when Member Servers, Member_Servers, WSUS Server, or Workstations OUs are missing.
- Fix WSUS server computer moves so inbound firewall policy applies after GPO import.
- Fix GPO targeting for Domain Controllers, member servers, workstations, and WSUS server OUs.
- Fix SQL sysadmin preflight false failures when SQL tooling is unavailable.
- Fix Fix SQL Login popup readability and duplicate native/custom dialog behavior.
- Fix WSUS content ACL auto-repair for IIS_IUSRS and Authenticated Users list/read/execute rights.
- Fix tray minimize behavior so the app remains recoverable from the taskbar/tray.
- Fix Robocopy output not appearing in the live terminal.
- Fix product sync so selected products are added without replacing existing subscriptions.
- Fix smart decline/approval filtering for Office, Visual Studio, Edge, WSL, ARM64, and preview builds.
- Fix dashboard health scores capped below 100 by non-core task/sync history components.
- Fix default package/version references that still pointed at v4.0.5 or the old zip name.
- Fix hardcoded dev paths and stale operator language in release docs.
- Fix PowerShell 5.1 scheduled-task monthly trigger registration by using XML registration.

### Removed
- Remove the GUI **Create GPO** menu option; the packaged Domain Controller script is authoritative.
- Remove current-score impact from scheduled task state, last sync, and last operation history.
- Remove standalone EXE upload from GitHub release assets; the EXE remains inside the zip.
- Remove stale Pathfinder planning artifacts from the repository root.

### Tests
- Add/update Pester coverage for GPO OU creation and WSUS computer moves.
- Add/update Pester coverage for product filtering, SQL login safety, and ACL repair.
- Add/update Pester coverage proving the new health score can reach 100.
- Add/update GUI/startup checks for navigation, Help text, popups, tray recovery, and live output.

## [4.0.5] - 2026-05-11

### Added
- Exchange Server 2019 added to default sync products

### Changed
- Product subscription changed from REPLACE to ADDITIVE — selected products are now added to existing WSUS subscriptions instead of replacing them
- Removed the "non-selected products decline" block; sub-product updates (Office LTSC 2024, SSMS v20) no longer get declined due to title mismatch with parent product names

### Fixed
- Office LTSC 2024 updates no longer missing after sync
- SQL Server Management Studio v20 updates no longer missing after sync

## [4.0.4] - 2026-03-22

### Added
- Invoke-WsusSqlcmd falls back to sqlcmd.exe when SqlServer module is not installed
- Updates older than 6 months auto-declined (skips already-approved updates)
- Declined purge progress shown on every batch (was every 5th)

### Changed
- Sysadmin verification uses sys.server_role_members (IS_SRVROLEMEMBER caches per-connection)
- Sysadmin preflight uses sqlcmd.exe fallback when Invoke-Sqlcmd unavailable
- SQLPS/SqlServer module explicitly imported before use (auto-load fails in child processes)

### Fixed
- All database operations (index rebuild, shrink, backup, purge) now work without SqlServer module
- Age decline preserves already-approved updates (was declining them on subsequent syncs)

## [4.0.3] - 2026-03-22

### Added
- Auto-decline rules for Edge non-stable (Dev/Beta/Extended Stable), Office 365/2019/LTSC 2021, WSL, Preview/Beta updates
- Microsoft Defender Antivirus and Microsoft Defender for Endpoint added to default products
- Microsoft Edge added to default products
- Updates and Update Rollups classifications enabled by default
- DNS preflight check before starting WSUS sync
- SQL connection retry after stopping WSUS in deep cleanup
- Install script configures classifications via WSUS API on fresh install
- Full WSUS configuration wizard suppression (registry + per-user + API)

### Changed
- Sync timeout increased from 60 to 180 minutes for first-sync scenarios
- Products set before sync starts (was racing with running sync)
- Exact product name matching (prevents driver sub-product bloat)
- x86/32-bit and 25H2 updates excluded from auto-approval (kept but not approved)
- 25H2 no longer auto-declined (kept for manual review); 23H2 and older still declined
- Export silently skips when path is inaccessible (was logging error)
- Robocopy transfer uses embedded log panel with visible file names
- Transfer creates destination subfolder (was dumping files loose)
- Schedule dialog defaults to current user, Tuesday 23:00
- Window size increased to 800x1000
- Dashboard skips all queries when WSUS not installed

### Fixed
- WID-to-SQL Express migration: uninstall WID role, reinstall with UpdateServices-DB
- Leftover WID data files cleaned up to prevent postinstall conflicts
- Language set via correct API (was using non-existent SetUpdateLanguages method)
- Age-based decline fixed (was declining entire catalog including approved updates on fresh sync)
- Process.Start() failure handling prevents stuck disabled buttons
- Get-WsusServer guarded by service running check (prevents UI freeze)

## [4.0.2] - 2026-03-20

### Changed
- **GPO deployment (v1.6.0):** Replaced `Invoke-GPUpdate` (WinRM) with `schtasks.exe` RPC-based push — works without WinRM, includes per-computer tracking and ping pre-check
- **GPO import strategy:** Delete-and-reimport instead of merge — permanently fixes stale registry values that caused "Extra Registry Settings" warnings in GPMC
- **GPO backups:** Removed `ScheduledInstallEveryWeek`, `ConfigureDeadlineNoAutoReboot`, `EnableFirewall`, and `PolicyVersion` from .pol binary files
- Removed differential export feature (Full/Differential copy mode, ExportDays, DifferentialExportPath) — simplified to full export only
- Removed `.GetNewClosure()` from all WPF click handlers — replaced with proper scope patterns
- Install script: dynamic SQL instance registry key detection, `UpdateServices` role (not `UpdateServices-DB`) for external SQL, `SyncFromMicrosoftUpdate=1`, TrustServerCertificate (`-C`), update language set to English
- `WsusOperationRunner.psm1` — Wrapped process command so Warning/Verbose/Debug/Info streams flow to stdout
- `WsusTrending.psm1` — Timestamped corrupt backup filenames to prevent silent overwrite

### Fixed
- **Closure scope bugs** in WPF click handlers causing stale variable capture
- **Security:** `Install-WsusWithSqlExpress.ps1` — pass `$currentUser` via `sqlcmd -v` variable to prevent SQL injection
- **Security:** `Invoke-WsusMonthlyMaintenance.ps1` — word-boundary `\b` in product decline regex prevents false positives
- **Security:** SQL-escape apostrophes in `N'...'` contexts for Fix SQL Login and installer sysadmin grant
- **Security:** Sanitize WSUS product names before command string interpolation (reject unsafe characters)
- **Security:** Block double-quote and percent in `Test-SafePath` to prevent robocopy argument injection
- **Security:** Scrub SA password from `ConfigurationFile.ini` immediately after SQL setup completes
- **Security:** Wrap process start in `try/finally` for guaranteed password env var cleanup
- **Safety:** `WsusTrending.psm1` — add timestamp to corrupt backup filename to prevent silent overwrite
- **Robocopy exit codes:** Normalize exit codes 1–7 to 0 (success) in GUI transfer operations
- **GPO push:** Make ICMP ping advisory — hardened domains blocking ping can still receive GP updates via RPC
- **Restore:** Guard `wsusutil reset` behind `Test-Path` to prevent WSUS service stranding if wsusutil.exe is missing
- **Dashboard:** Skip refresh while operations are running (prevents log output stutter)
- Log message said 'any key' but only ESC/Q work
- Backtick-escape `$(CurrentUser)` in installer sqlcmd calls
- Fix `Integration.Tests.ps1` version check (4.0.1 → 4.0.2) and stale workflow assumptions

### Documentation
- Added **AIR-GAP ONLY** warnings across operator documentation
- Updated Create GPO instructions: removed `Invoke-GPUpdate` reference, added schtasks explanation
- Removed `ConfigureDeadlineNoAutoReboot` from SOP settings table
- Removed differential export references from all docs and wiki

## [4.0.1] - 2026-03-18

### Added
- **Tests/GuiFullTest.ps1** — Full GUI automation test (49 tests, 10 categories) using COM
  UI Automation via scheduled tasks; covers dashboard, panels, dialogs, buttons, log panel
- **docs/GUI-TESTING-LESSONS.md** — 16-section lessons learned document from GUI testing
  on headless Windows Server VMs via SSH tunnels and RDP sessions
- **Tests/FlaUI.Tests.ps1** — 71 FlaUI-based unit tests for AutomationId coverage
- **Tests/ProductFilter.Tests.ps1** — 31 Pester tests for product decline/approval logic,
  Office 365 LTSC exception handling, ARM64/25H2 exclusion, and SQL injection safety

### Changed
- Install script synced with Pro version: flexible installer detection, `UPDATEENABLED="0"`
- Removed stale GitHub workflow scaffolding from the cleaned v4.1.0 branch
- Removed archived planning folders from the cleaned v4.1.0 branch

### Fixed
- **Security:** `Install-WsusWithSqlExpress.ps1` — pass `$currentUser` via `sqlcmd -v`
  variable instead of string interpolation to prevent SQL injection in sysadmin creation
- **Security:** `Invoke-WsusMonthlyMaintenance.ps1` — add word-boundary `\b` to product
  decline regex to prevent false-positive substring matches (e.g., "Server 2019" matching
  "Windows Server 2019 22H2")
- **Safety:** `WsusTrending.psm1` — add timestamp to corrupt backup filename to prevent
  silent overwrite of diagnostic data

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
- Developer guidance moved into the wiki and operator docs

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
