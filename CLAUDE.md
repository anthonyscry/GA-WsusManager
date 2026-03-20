# CLAUDE.md - WSUS Manager

This file provides guidance for AI assistants working with this codebase.

## Project Overview

WSUS Manager is a PowerShell WPF automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. It provides a modern GUI application for managing WSUS servers, including support for air-gapped networks.

**Author:** Tony Tran, ISSO, GA-ASI
**Current Version:** 4.0.0 (PowerShell)

## Repository Structure

```
GA-WsusManager/
├── build.ps1                    # Build script using PS2EXE
├── dist/                        # Build output folder (gitignored)
│   ├── WsusManager.exe          # Compiled executable
│   └── WsusManager-vX.X.X.zip   # Distribution package
├── Scripts/
│   ├── WsusManagementGui.ps1    # Main GUI source (WPF/XAML)
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusClientCheckIn.ps1
│   └── Set-WsusHttps.ps1
├── Modules/                     # Reusable PowerShell modules (16 modules)
│   ├── WsusUtilities.psm1       # Logging, colors, helpers
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusHealth.psm1          # Health checks, repair, + health score (0-100)
│   ├── WsusServices.psm1        # Service management
│   ├── WsusFirewall.psm1        # Firewall rules
│   ├── WsusPermissions.psm1     # Directory permissions
│   ├── WsusConfig.psm1          # Configuration, timeouts, health weights
│   ├── WsusExport.psm1          # Export/import
│   ├── WsusScheduledTask.psm1   # Scheduled tasks
│   ├── WsusAutoDetection.psm1   # Server detection, auto-recovery, dashboard data
│   ├── AsyncHelpers.psm1        # Async/background operation helpers for WPF
│   ├── WsusDialogs.psm1         # [v4.0] Dialog factory — New-WsusDialog, New-WsusFolderBrowser
│   ├── WsusOperationRunner.psm1 # [v4.0] Unified operation lifecycle — Start/Stop/Complete-WsusOperation
│   ├── WsusHistory.psm1         # [v4.0] Operation history — Write/Get/Clear-WsusOperationHistory
│   ├── WsusNotification.psm1    # [v4.0] Toast/balloon notifications — Show-WsusNotification
│   └── WsusTrending.psm1        # [v4.0] DB size trending — Add/Get/Clear trend snapshots
├── Tests/                       # Pester unit tests (one file per module)
└── DomainController/            # GPO deployment scripts
```

## Build Process

The project uses PS2EXE to compile PowerShell scripts into standalone executables.

```powershell
# Full build with tests and code review (recommended)
.\build.ps1

# Build without tests
.\build.ps1 -SkipTests

# Build without code review
.\build.ps1 -SkipCodeReview

# Run tests only
.\build.ps1 -TestOnly

# Build with custom output name
.\build.ps1 -OutputName "CustomName.exe"
```

The build process:
1. Runs Pester unit tests (323 tests across 10 files)
2. Runs PSScriptAnalyzer on `Scripts\WsusManagementGui.ps1` and `Scripts\Invoke-WsusManagement.ps1`
3. Blocks build if errors are found
4. Warns but continues if only warnings exist
5. Compiles `WsusManagementGui.ps1` to `WsusManager.exe` using PS2EXE
6. Creates distribution zip with Scripts/, Modules/, DomainController/, and branding assets

**Version:** Update in `build.ps1` and `Scripts\WsusManagementGui.ps1` (`$script:AppVersion`)

### Distribution Package Structure

The build creates a complete distribution zip (`WsusManager-vX.X.X.zip`) containing:
```
WsusManager.exe           # Main GUI application
Scripts/                  # Required - operation scripts
├── Invoke-WsusManagement.ps1
├── Invoke-WsusMonthlyMaintenance.ps1
├── Install-WsusWithSqlExpress.ps1
└── ...
Modules/                  # Required - PowerShell modules
├── WsusUtilities.psm1
├── WsusHealth.psm1
└── ...
DomainController/         # Optional - GPO scripts
general_atomics_logo_big.ico
general_atomics_logo_small.ico
QUICK-START.txt
README.md
```

**IMPORTANT:** The EXE requires the Scripts/ and Modules/ folders to be in the same directory. Do not deploy the EXE alone.

## Key Technical Details

### PowerShell Modules
- All modules are in the `Modules/` directory
- Scripts import modules at runtime using relative paths
- Modules export functions explicitly via `Export-ModuleMember`
- `WsusHealth.psm1` automatically imports dependent modules (Services, Firewall, Permissions)
- `WsusAutoDetection.psm1` provides auto-recovery, dashboard data functions, and 30s TTL cache
- **v4.0 additions:** `WsusDialogs.psm1`, `WsusOperationRunner.psm1`, `WsusHistory.psm1`, `WsusNotification.psm1`, `WsusTrending.psm1`

### v4.0 Module Architecture

**WsusDialogs.psm1** — Dialog Factory
- `New-WsusDialog` → `{Window, ContentPanel}`: window shell with ESC-close, owner, dark theme
- `New-WsusFolderBrowser` → `{Panel, TextBox, Label}`: DockPanel with Browse button
- `New-WsusDialogLabel`, `New-WsusDialogButton`, `New-WsusDialogTextBox`: styled UI helpers
- Eliminates the 6 copy-pasted dialog boilerplate patterns (anti-patterns #1, #3 resolved)

**WsusOperationRunner.psm1** — Unified Operation Lifecycle
- `Start-WsusOperation -Command -Title -Context -Mode [Embedded|Terminal] -TimeoutMinutes`
- `Stop-WsusOperation`, `Complete-WsusOperation`, `Find-WsusScript`
- Context hashtable carries GUI state (Window, Controls, buttons, inputs)
- Uses `[System.Text.StringBuilder]` for log accumulation (not string concat)
- Timeout watchdog kills hung processes (configurable per-type in WsusConfig)
- Eliminates ~200 lines of duplicated operation logic (anti-patterns #4, #7, #8, #11, #12 resolved)

**WsusHistory.psm1** — Operation History
- `Write-WsusOperationHistory -OperationType -Duration -Result -Summary`
- `Get-WsusOperationHistory -Count -OperationType -ResultFilter`
- JSON storage: `%APPDATA%\WsusManager\history.json`, trimmed to 100 entries
- File-lock retry, corrupt JSON recovery

**WsusNotification.psm1** — Completion Notifications
- `Show-WsusNotification -Title -Message -Result -EnableBeep`
- 3-tier fallback: Windows 10 toast → balloon tip → log-only
- Called by operation exit handlers; configurable in Settings

**WsusTrending.psm1** — DB Size Trending
- `Add-WsusTrendSnapshot`, `Get-WsusTrendSummary`, `Clear-WsusTrendData`
- Linear regression over last 30 days → days-until-full estimate
- Alert when <90 days to 10GB SQL Express limit

**WsusAutoDetection.psm1 additions (v4.0)**
- `Get-WsusDashboardServiceStatus`, `Get-WsusDashboardDiskFreeGB`, `Get-WsusDashboardDatabaseSizeGB`
- `Get-WsusDashboardTaskStatus`, `Test-WsusDashboardInternetConnection`
- `Get-WsusDashboardData` — aggregate function, runspace-safe
- `Get-WsusDashboardCachedData`, `Set-WsusDashboardCache`, `Test-WsusDashboardDataUnavailable`
- 30s TTL cache, "Data unavailable" after 10 consecutive failures

**WsusHealth.psm1 additions (v4.0)**
- `Get-WsusHealthScore` → `{Score, Components, Grade, AllFailed}`
- Weighted: Services 30, DB 20, Sync 20, Disk 20, LastOp 10
- Grade: "Green" ≥80, "Yellow" 50-79, "Red" <50, "Unknown" if all fail

**WsusConfig.psm1 additions (v4.0)**
- `Get-WsusHealthWeights` — canonical health score weights
- `Get-WsusOperationTimeout -OperationType` — per-operation timeout (minutes)

### GUI Application
- Built with WPF (`PresentationFramework`) and XAML
- Dark theme matching GA-AppLocker style; Light theme toggle in Settings (reserved)
- Auto-refresh dashboard (30-second interval) with refresh guard and operation skip
- Startup splash screen with progress bar (4 stages)
- History view (📜 History nav button) showing last 50 operations
- Keyboard shortcuts: Ctrl+D=Diagnostics, Ctrl+S=Sync, Ctrl+H=History, Ctrl+R/F5=Refresh
- Right-click context menu on log panel: Copy All / Save to File
- Notifications on operation completion (toast/balloon, configurable in Settings)
- Health Score card on dashboard (0-100, color-coded)
- DB size trend indicator with days-until-full estimate
- Last successful sync timestamp on dashboard
- Air-Gap "Create USB Package" workflow with transfer manifest
- Server Mode toggle (Online vs Air-Gap) with context-aware menu
- Custom icon: `wsus-icon.ico` (if present)
- Requires admin privileges
- Settings stored in `%APPDATA%\WsusManager\settings.json`
- DPI-aware rendering (Windows 8.1+ per-monitor, Vista+ system fallback)
- Global error handling with user-friendly error dialogs

### Standard Paths
- WSUS Content: `C:\WSUS\`
- SQL/SSMS Installers: `C:\WSUS\SQLDB\` (installer script prompts if missing)
- Logs: `C:\WSUS\Logs\`
- SQL Instance: `localhost\SQLEXPRESS`
- WSUS Ports: 8530 (HTTP), 8531 (HTTPS)

### SQL Express Considerations
- 10GB database size limit
- Dashboard monitors and alerts near limit
- Database name: `SUSDB`

## Common Development Tasks

### Adding a New Module Function
1. Add function to appropriate module in `Modules/`
2. Add to `Export-ModuleMember -Function` list at end of module
3. Document with PowerShell comment-based help
4. Add Pester tests in `Tests/`

### Modifying the GUI
1. Edit `Scripts\WsusManagementGui.ps1`
2. Run `.\build.ps1` to compile and test
3. Test the executable

### Running Tests
```powershell
# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run specific module tests
Invoke-Pester -Path .\Tests\WsusAutoDetection.Tests.ps1

# Run tests with code coverage
Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1
```

### Testing Changes
```powershell
# Test GUI script directly (without compiling)
powershell -ExecutionPolicy Bypass -File .\Scripts\WsusManagementGui.ps1

# Test CLI
powershell -ExecutionPolicy Bypass -File .\Scripts\Invoke-WsusManagement.ps1

# Run code analysis only
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
```

## Code Style Guidelines

- Use PowerShell approved verbs (Get-, Set-, New-, Remove-, Test-, Invoke-, etc.)
- Prefix WSUS-specific functions with `Wsus` (e.g., `Get-WsusDatabaseSize`)
- Use comment-based help for all public functions
- Color output functions: `Write-Success`, `Write-Failure`, `Write-Info`, `Write-WsusWarning` (from WsusUtilities)
- Logging via `Write-Log`, `Start-WsusLogging`, `Stop-WsusLogging`

## Security Considerations

- **Path Validation:** Use `Test-ValidPath` and `Test-SafePath` to prevent command injection
- **Path Escaping:** Use `Get-EscapedPath` for safe command string construction
- **SQL Injection:** Input validation in database operations
- **Service Status:** Re-query services instead of using Refresh() method (PSCustomObject compatibility)

## Important Considerations

- **Admin Required:** All scripts require elevated privileges
- **SQL Express:** Uses `localhost\SQLEXPRESS` - scripts auto-detect
- **Air-Gap Support:** Export/import operations designed for offline networks
- **Service Dependencies:** SQL Server must be running before WSUS operations
- **Content Path:** Must be `C:\WSUS\` (not `C:\WSUS\wsuscontent\`)

## Git Workflow

- Main branch: `main`
- Build artifacts (exe, zip) are NOT committed - they go to `dist/` folder (gitignored)
- Use conventional commit messages
- Run tests before committing: `.\build.ps1 -TestOnly`
- GitHub Actions builds the EXE on push/PR and creates releases

## Recent Changes (v4.0.0)

### Phase 1 — Foundations
- **WsusDialogs.psm1** — Dialog factory eliminating 6 copy-paste dialog patterns
- **WsusOperationRunner.psm1** — Unified operation lifecycle (start/stop/complete); timeout watchdog; Terminal + Embedded mode support
- **Async Dashboard** — Dashboard data functions moved to `WsusAutoDetection.psm1`; 30s TTL cache; `Get-WsusDashboardData` is runspace-safe; `Test-WsusDashboardDataUnavailable` after 10 failures
- **CLAUDE.md update** — Documented v4.0 architecture, new modules, and additional GUI patterns

### Phase 2 — Features
- **WsusHistory.psm1** — `Write/Get/Clear-WsusOperationHistory`; JSON at `%APPDATA%\WsusManager\history.json`; 100-entry trim; file-lock retry
- **WsusNotification.psm1** — `Show-WsusNotification`; toast → balloon → log fallback; configurable in Settings
- **DB Size Trending** — `WsusTrending.psm1` with linear regression; days-until-full estimate; Critical/Warning alerts near 10GB limit
- **Health Score** — `Get-WsusHealthScore` in `WsusHealth.psm1`; 0-100 weighted composite (Services=30, DB=20, Sync=20, Disk=20, LastOp=10); Grade Green/Yellow/Red/Unknown
- **Operation Timeouts** — `Get-WsusOperationTimeout` in `WsusConfig.psm1`; per-type values (Cleanup=60min, Sync=120min, Default=30min)
- **Air-Gap USB Package** — "Create USB Package" button in GUI; generates transfer manifest with checksums
- **History View** — 📜 History nav button; lists last 50 operations from history.json

### Phase 3 — Polish
- **Startup Splash Screen** — `Show-SplashScreen` / `Update-SplashProgress`; 4-stage progress; non-modal, non-fatal
- **Keyboard Shortcuts** — Ctrl+D=Diagnostics, Ctrl+S=Sync, Ctrl+H=History, Ctrl+R/F5=Refresh Dashboard
- **Log Context Menu** — Right-click on log panel: Copy All / Save to File
- **Last Sync Display** — Last successful sync timestamp on dashboard card
- **Theme Toggle** — Dark/Light theme toggle in Settings (reserved)

### Previous (v3.8.11)

- **TrustServerCertificate Compatibility Fix:**
  - Fixed "A parameter cannot be found that matches parameter name 'TrustServerCertificate'" error
  - The `-TrustServerCertificate` parameter was added in SqlServer module v21.1
  - Older versions don't support this parameter, causing declined update purge to fail
  - Updated `Invoke-WsusMonthlyMaintenance.ps1` and `Invoke-WsusManagement.ps1` to use `Invoke-WsusSqlcmd` wrapper
  - The wrapper function automatically detects SqlServer module version and only includes the parameter when supported

### Previous (v3.8.10)

- **Deep Cleanup Fix - Now performs full database maintenance:**
  - Previously only called `Invoke-WsusServerCleanup` (basic WSUS cleanup)
  - Now performs complete 6-step database maintenance:
    1. WSUS built-in cleanup (decline superseded, remove obsolete)
    2. Remove supersession records for declined updates
    3. Remove supersession records for superseded updates (batched, 10k/batch)
    4. Delete declined updates from database via `spDeleteUpdate` (100/batch)
    5. Rebuild/reorganize fragmented indexes + update statistics
    6. Shrink database to reclaim disk space
  - Shows progress and timing for each step
  - Reports database size before/after shrink

- **Unified Diagnostics:**
  - Consolidated Health Check + Repair into single "Diagnostics" operation
  - Single button in GUI performs comprehensive scan with automatic fixes
  - Clear pass/fail reporting for all checks

- **GitHub Actions Workflow Fixes:**
  - Fixed artifact naming mismatch (release job was missing "v" prefix)
  - Split artifacts: one for direct download (extracted), one for releases (zip)
  - Release now auto-publishes (not draft) with detailed release notes
  - Release notes include all v3.8.10 features

- **Documentation Updates:**
  - Updated README.md with Deep Cleanup fix details
  - Updated GitHub Wiki (User Guide, Changelog)
  - Updated Confluence SOP with all recent features
  - Documented Security Definitions auto-approval feature
  - Documented Reset Content button for air-gap import fix

### Previous (v3.8.9)

- **Renamed Monthly Maintenance to Online Sync:**
  - Nav button: "📅 Monthly" → "🔄 Online Sync"
  - Quick action button: "Maintenance" → "Online Sync"
  - Dialog title and options updated (Full/Quick Sync, Sync Only)
  - Schedule dialog title updated
  - CLI script header updated
  - Windows Task Scheduler task name unchanged for backward compatibility

- **Online Sync dialog with export path options:**
  - Added Full Export Path field with browse button (for complete backup + content mirror)
  - Added Differential Export Path field with browse button (for USB/air-gap transfer)
  - Added Export Days field (default: 30 days) for differential age filter
  - All export fields are optional - if not specified, export is skipped
  - Dialog height increased to 580px to accommodate new fields

- **CLI export path improvements (Invoke-WsusMonthlyMaintenance.ps1):**
  - Added `-DifferentialExportPath` parameter for separate differential destination
  - Removed hardcoded default export path (was `\\lab-hyperv\d\WSUS-Exports`)
  - If DifferentialExportPath not specified, defaults to `{ExportPath}\Year\Month`
  - Pre-flight checks validate access to both export paths
  - Operation summary displays both paths

- **Definition Updates now auto-approved:**
  - Added "Definition Updates" to approved classifications (security definitions, antivirus signatures)
  - Previously excluded as "too frequent" but superseded cleanup handles this
  - Approved classifications: Critical, Security, Update Rollups, Service Packs, Updates, Definition Updates
  - Still excluded: Upgrades (require manual review)

- **Updated MaxAutoApproveCount to 200:**
  - Increased from 100 to provide buffer for Definition Updates
  - Superseded updates are declined before approval runs, so accumulation is minimal
  - Safety check skips auto-approval if count exceeds 200

- **Extracted magic numbers to WsusConfig.psm1:**
  - GUI configuration: dialog sizes, timer intervals, panel heights, console window settings
  - Retry configuration: attempt counts and delay values for DB, service, and sync operations
  - New helper functions: `Get-WsusGuiSetting`, `Get-WsusRetrySetting`, `Get-WsusDialogSize`, `Get-WsusTimerInterval`
  - Dialog size presets: Small (480x280), Medium (480x360), Large (480x460), ExtraLarge (520x580), Schedule (480x560)
  - Timer presets: DashboardRefresh (30s), UiUpdate (250ms), OpCheck (500ms), KeystrokeFlush (2s)

- **Added CLI integration tests (`Tests/CliIntegration.Tests.ps1`):**
  - Parameter validation for all CLI scripts (Maintenance, Management, Install)
  - Verifies MaintenanceProfile, Operations, ExportPath, DifferentialExportPath parameters
  - Tests switch parameters (SkipExport, Unattended, NonInteractive, etc.)
  - Config module integration tests for GUI/Retry settings
  - Update classifications verification (Definition Updates approved, Upgrades excluded)
  - Export path handling tests (DifferentialExportPath, year/month fallback)
  - Help documentation presence tests (SYNOPSIS, DESCRIPTION, PARAMETER)

- **Reset Content button (Air-Gap):**
  - New "Reset Content" button in GUI Diagnostics section
  - Runs `wsusutil reset` to re-verify content files against database
  - Fixes "content is still downloading" status after database import on air-gapped servers
  - Added to OperationButtons and WsusRequiredButtons arrays
  - Uses existing `-Reset` parameter in `Invoke-WsusManagement.ps1`

### Previous (v3.8.8)

- **Bug Fixes (2026-01-14):**
  - Fixed `UpdateIdParam` error in declined update purge: Changed here-string from `@"..."@` to `@'...'@` to prevent PowerShell from evaluating `$(UpdateIdParam)` as a subexpression
  - Fixed database shrink failing when backup is running: Added retry logic (3 attempts, 30s delay) when shrink is blocked by ongoing backup operations
  - Fixed artifact download creating zip-within-zip: GitHub Actions now extracts contents before uploading artifact
  - Suppressed noisy `spDeleteUpdate` errors during declined update purge: Expected errors for updates with revision dependencies are now silently handled
  - Increased window height by 8 pixels (720 → 728) for better layout

### Previous (v3.8.7)

- **Live Terminal Mode:**
  - New toggle button in log panel header to open operations in external PowerShell window
  - Console window sized to 100x20 chars, positioned near log panel area
  - Keystroke timer sends Enter key every 2 seconds to flush output buffer
  - Settings persist to `settings.json`
- **Import dialog with source and destination selection:**
  - Transfer dialog now shows two folder browsers for Import operations
  - Source folder: external media location (USB drive)
  - Destination folder: WSUS server path (default: C:\WSUS)
  - Both paths passed to CLI, eliminating all interactive prompts
- **Create GPO button:**
  - New button in Setup menu copies GPO files to `C:\WSUS\WSUS GPO`
  - Shows detailed instructions for DC admin
  - Includes commands to force client check-in and verify GPO application
- **WSUS installation detection:**
  - Operations greyed out if WSUS service not installed on server
  - Dashboard cards show "Not Installed" / "N/A" status
  - Log panel displays installation instructions on startup
  - Only Install WSUS button remains enabled
- **Non-blocking network check:**
  - Changed `Test-InternetConnection` from `Test-Connection` to .NET Ping with 500ms timeout
  - Prevents UI freezing during dashboard refresh on slow/offline networks
- **Improved sync progress output:**
  - Only logs when phase changes or 10% progress made
  - Shows percentage in output (e.g., "Syncing: DownloadUpdates (45.2%)")
  - Logs near completion (95%+) to avoid gaps before "completed" message
- **Bug fixes from code review:**
  - Fixed Schedule Task crash: `-Profile` parameter renamed to `-MaintenanceProfile`
  - Fixed UNC path validation: `Test-SafePath` now accepts `\\server\share` paths
  - Added null checks to `Update-Dashboard` to prevent crashes during initialization
  - Fixed timer cleanup in `Stop-CurrentOperation` for `KeystrokeTimer` and `StdinFlushTimer`
  - Added bounds checking for console window positioning (min 400px width, max screen bounds)
  - Expanded scheduled task day validation from 1-28 to 1-31
  - Fixed Import CLI parameter set: `SourcePath`/`DestinationPath` now work for Import operations
  - Fixed button state after operation completes: calls `Update-WsusButtonState` to respect WSUS installation
  - Fixed Create GPO handler: disables buttons during operation, re-enables on completion
- **Live Terminal improvements:**
  - Console window now uses try/finally so "Press Enter" prompt always shows even on error
  - Changed from ReadKey to Read-Host for better compatibility
  - Error messages displayed with red text in catch block
- **Schedule Task dialog rewrite:**
  - Complete rewrite to fix null reference exceptions during ShowDialog()
  - Uses script-scope variables for event handlers to avoid closure capture issues
  - Added PowerShell comment-based help documentation
  - Null safety check for owner window before assignment
  - Increased dialog height to 540px to show all fields including credentials
- **SQL sysadmin permission checking:**
  - Added `Test-SqlSysadmin` and `Assert-SqlSysadmin` functions
  - Database operations (Restore, Deep Cleanup) check sysadmin permission before running
  - Monthly Maintenance includes sysadmin check in pre-flight checks
  - Clear error message if user lacks permissions

### Previous (v3.8.6)

- **Input fields now disabled during operations:**
  - Password boxes and path textbox greyed out during install
  - Added `OperationInputs` array for tracking input fields
  - Fields re-enabled when operation completes or is cancelled
- **Code cleanup:**
  - Removed duplicate `Start-Heartbeat`/`Stop-Heartbeat` functions (3 copies → 1)
  - Streamlined GitHub workflows with concurrency settings
  - Removed Codacy and release-drafter workflows

### Previous (v3.8.5)

- **Fixed output log window not refreshing until Cancel clicked:**
  - Changed from `Dispatcher.Invoke` to `Dispatcher.BeginInvoke` with Normal priority
  - Timer now uses proper WPF dispatcher pump instead of Windows Forms `DoEvents()`
  - Timer interval reduced to 250ms for more responsive UI updates
- **Fixed Install operation hanging when clicked:**
  - Added `-NonInteractive` parameter to `Install-WsusWithSqlExpress.ps1`
  - In non-interactive mode, script fails with error message instead of showing dialogs
  - GUI now passes `-NonInteractive` when calling the install script
  - Cleaned up duplicate code in GUI install case
- **Updated scheduled task to use domain credentials:**
  - Scheduled task dialog now prompts for username (default: `.\dod_admin`)
  - Password required for unattended task execution
  - Tasks run whether user is logged on or not
  - Removed hardcoded SYSTEM account for scheduled tasks

### Previous (v3.8.4)

- **Fixed Export hanging for input when called from GUI:**
  - Added non-interactive mode to `Invoke-ExportToMedia` function
  - New CLI parameters: `-SourcePath`, `-DestinationPath`, `-CopyMode`, `-DaysOld`
  - When `DestinationPath` is provided, skips all interactive prompts
  - Backward compatibility: `ExportRoot` parameter can be used as destination
- **Added Export Mode options to Transfer dialog:**
  - Full copy (all files)
  - Differential copy (files from last N days)
  - Custom days option for differential exports
- **Fixed GitHub Actions workflow:**
  - Distribution package now includes Scripts/ and Modules/ folders (required for EXE)
  - Build artifacts saved to `dist/` folder
  - ExeValidation tests run AFTER build step (not before)
  - ExeValidation tests excluded from pre-build test job
- **Fixed Pester tests:**
  - ExeValidation tests properly skip when exe doesn't exist
  - Uses `-Skip` on Context blocks for reliable Pester 5 behavior
  - Uses `BeforeDiscovery` for discovery-time variable evaluation
- **Cleaned up repository:**
  - Build artifacts (exe, zip) excluded from git via `.gitignore`
  - All build output goes to `dist/` folder

### Previous (v3.8.3)

- **Fixed script not found error:** Added proper validation before running operations
  - GUI now checks if Scripts exist before attempting to run them
  - Shows clear error dialog with search paths if scripts are missing
- **Fixed buttons staying enabled during operations:** Added `Disable-OperationButtons` / `Enable-OperationButtons`
  - All operation buttons (nav + quick action) are disabled while an operation runs
  - Buttons show 50% opacity when disabled for visual feedback
  - Buttons re-enable when operation completes, errors, or is cancelled
- **Fixed OperationRunning flag not resetting:** Flag now resets in all code paths
- **Fixed Export using invalid CLI parameters:** Removed `-Differential` and `-DaysOld` (not supported by CLI)
- **Fixed distribution package:** Zip now includes Scripts/ and Modules/ folders (was missing before)
- **Updated QUICK-START.txt:** Documents folder structure requirement

### Previous (v3.8.1)

- Added `AsyncHelpers.psm1` module for background operations in WPF apps
- Added DPI awareness (per-monitor on Win 8.1+, system DPI on Vista+)
- Added global error handling wrapper with user-friendly error dialogs
- Added startup time logging (`$script:StartupTime`, `$script:StartupDuration`)
- Added EXE validation Pester tests (`Tests\ExeValidation.Tests.ps1`)
- Added startup benchmark to CI pipeline (parse time, module import, EXE size)
- CI now validates PE header, version info, and 64-bit architecture

### Previous (v3.8.0)
- All dialogs now close with ESC key (Settings, Export/Import, Restore, Maintenance, Install, About)
- Fixed PSScriptAnalyzer warnings (unused parameter, verb naming, empty catch blocks)
- Build script now supports OneDrive module paths for PSScriptAnalyzer and ps2exe
- Code quality improvements for better maintainability

### Previous (v3.7.0)
- Output log panel now 250px tall and open by default
- All operations output to bottom log panel (removed separate Operation panel)
- Unified Export/Import into single Transfer dialog with direction selector
- Restore dialog auto-detects backup files in C:\WSUS
- Monthly Maintenance shows profile selection dialog
- Added Cancel button to stop running operations
- Operations block concurrent execution to prevent conflicts
- Fixed Install WSUS showing blank window before folder selection
- Fixed Health Check curly braces output by suppressing return value
- Fixed dashboard log path showing folder instead of specific file

## Common GUI Issues and Solutions

This section documents bugs encountered during development and how to avoid them in future changes.

### 1. Blank/Empty Operation Windows

**Problem:** Operations show blank windows or no output before dialogs appear.

**Cause:** The GUI switches to an empty operation panel before showing a dialog, giving users a blank screen.

**Solution:** Show dialogs BEFORE switching panels. Only switch to operation view after user confirms dialog:
```powershell
# WRONG - shows blank panel, then dialog
Show-Panel "Operation" "Install WSUS" "BtnInstall"
$fbd = New-Object System.Windows.Forms.FolderBrowserDialog
if ($fbd.ShowDialog() -eq "OK") { ... }

# CORRECT - show dialog first, only switch if user proceeds
$fbd = New-Object System.Windows.Forms.FolderBrowserDialog
if ($fbd.ShowDialog() -eq "OK") {
    # Now show operation panel and run
}
```

### 2. Curly Braces `{}` in Output

**Problem:** Operations like Health Check show `@{...}` or curly braces in log output.

**Cause:** PowerShell functions return hashtables/objects that get stringified to console.

**Solution:** Suppress return values with `$null =` or `| Out-Null`:
```powershell
# WRONG - outputs object representation
& '$mgmtSafe' -Health -ContentPath '$cp'

# CORRECT - suppress return value
$null = & '$mgmtSafe' -Health -ContentPath '$cp'
```

### 3. Event Handler Scope Issues

**Problem:** Event handlers can't access script-scope variables or controls.

**Cause:** `Register-ObjectEvent` handlers run in a different scope and can't access `$script:*` variables.

**Solution:** Pass data via `-MessageData` parameter:
```powershell
# WRONG - $script:controls not accessible in handler
$outputHandler = {
    $script:controls.LogOutput.AppendText($Event.SourceEventArgs.Data)
}
Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outputHandler

# CORRECT - pass controls via MessageData
$eventData = @{ Window = $window; Controls = $controls }
$outputHandler = {
    $data = $Event.MessageData
    $data.Window.Dispatcher.Invoke([Action]{
        $data.Controls.LogOutput.AppendText($Event.SourceEventArgs.Data)
    })
}
Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outputHandler -MessageData $eventData
```

### 4. UI Updates from Background Threads

**Problem:** UI controls don't update or throw threading errors.

**Cause:** WPF controls can only be modified from the UI thread.

**Solution:** Use `Dispatcher.Invoke()` for all UI updates from event handlers:
```powershell
# WRONG - direct access from background thread
$controls.LogOutput.AppendText($line)

# CORRECT - dispatch to UI thread
$controls.LogOutput.Dispatcher.Invoke([Action]{
    $controls.LogOutput.AppendText($line)
})
```

### 5. Closure Variable Capture

**Problem:** Click handlers reference stale variable values.

**Cause:** PowerShell closures capture variables by reference, not value.

**Solution:** Use `.GetNewClosure()` to capture current values:
```powershell
# WRONG - may use wrong value if $i changes
$btn.Add_Click({ Write-Host $i })

# CORRECT - captures current value
$btn.Add_Click({ Write-Host $i }.GetNewClosure())
```

### 6. Missing CLI Parameters

**Problem:** GUI passes parameters that CLI script doesn't accept.

**Cause:** New GUI features added without updating CLI script parameters.

**Solution:** Always update both files together:
1. Add parameter to CLI script (`Invoke-WsusManagement.ps1`)
2. Add parameter handling in CLI script
3. Update GUI to pass the parameter

Example: Adding `-BackupPath` for restore operation required changes to both scripts.

### 7. Process Output Not Appearing

**Problem:** External process output doesn't show in log panel.

**Cause:** Not calling `BeginOutputReadLine()` / `BeginErrorReadLine()` after starting process.

**Solution:** Always start async reading:
```powershell
$proc.Start() | Out-Null
$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()
```

### 8. Operations Running Concurrently

**Problem:** Users can start multiple operations, causing conflicts.

**Solution:** Use a flag to block concurrent operations:
```powershell
if ($script:OperationRunning) {
    [System.Windows.MessageBox]::Show("An operation is already running.", "Warning")
    return
}
$script:OperationRunning = $true
# ... run operation ...
$script:OperationRunning = $false
```

### 9. Dialogs Not Closing with ESC Key

**Problem:** Modal dialogs don't respond to ESC key to close.

**Cause:** WPF dialogs don't have default ESC key handling.

**Solution:** Add `KeyDown` event handler to each dialog:
```powershell
$dlg.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() }
})
```

Add this immediately after setting `ResizeMode` on each dialog window.

### 10. Script Not Found Errors

**Problem:** Operations fail with "script is not recognized" error.

**Cause:** GUI builds script path without validating it exists first.

**Solution:** Always validate script paths before using them:
```powershell
# WRONG - uses path even if it doesn't exist
$mgmt = Join-Path $sr "Invoke-WsusManagement.ps1"
if (-not (Test-Path $mgmt)) { $mgmt = Join-Path $sr "Scripts\Invoke-WsusManagement.ps1" }
# Still uses $mgmt even if second path doesn't exist either!

# CORRECT - validate and show error if not found
$mgmt = $null
$locations = @(
    (Join-Path $sr "Invoke-WsusManagement.ps1"),
    (Join-Path $sr "Scripts\Invoke-WsusManagement.ps1")
)
foreach ($loc in $locations) {
    if (Test-Path $loc) { $mgmt = $loc; break }
}
if (-not $mgmt) {
    [System.Windows.MessageBox]::Show("Script not found!", "Error", "OK", "Error")
    return
}
```

### 11. Buttons Not Disabled During Operations

**Problem:** Users can click operation buttons while another operation is running.

**Cause:** Only showing a message box but buttons remain clickable.

**Solution:** Disable all operation buttons when an operation starts:
```powershell
$script:OperationButtons = @("BtnInstall","BtnHealth","QBtnHealth",...)

function Disable-OperationButtons {
    foreach ($b in $script:OperationButtons) {
        if ($controls[$b]) {
            $controls[$b].IsEnabled = $false
            $controls[$b].Opacity = 0.5
        }
    }
}

function Enable-OperationButtons {
    foreach ($b in $script:OperationButtons) {
        if ($controls[$b]) {
            $controls[$b].IsEnabled = $true
            $controls[$b].Opacity = 1.0
        }
    }
}

# Call Disable at start, Enable at end (including error/cancel paths)
```

### 12. Operation Status Flag Not Resetting After Completion

**Problem:** After an operation completes, clicking another operation shows "An operation is already running" even though no operation is running.

**Cause:** The `exitHandler` event handler only updates UI text but doesn't reset `$script:OperationRunning` or re-enable buttons. Event handlers run in a different scope so they can't directly call script functions.

**Solution:**
1. Pass the operation buttons list in the eventData
2. Reset `$script:OperationRunning = $false` outside the Dispatcher.Invoke (in event handler scope)
3. Re-enable buttons inside the Dispatcher.Invoke using the passed button list

```powershell
# Include buttons list in eventData
$eventData = @{
    Window = $window
    Controls = $controls
    Title = $Title
    OperationButtons = $script:OperationButtons  # Add this
}

$exitHandler = {
    $data = $Event.MessageData
    $data.Window.Dispatcher.Invoke([Action]{
        # ... update UI ...
        # Re-enable buttons using passed list
        foreach ($btnName in $data.OperationButtons) {
            if ($data.Controls[$btnName]) {
                $data.Controls[$btnName].IsEnabled = $true
                $data.Controls[$btnName].Opacity = 1.0
            }
        }
    })
    # Reset flag OUTSIDE Dispatcher.Invoke (script scope accessible here)
    $script:OperationRunning = $false
}
```

**Also:** Don't use `.GetNewClosure()` on timer handlers - it captures stale variable values.

### 13. Pester Tests Not Skipping Properly

**Problem:** Using `-Skip:$condition` on a `Describe` block doesn't skip all child tests in Pester 5.

**Cause:** Pester 5 has inconsistent behavior with `-Skip` on `Describe` blocks - it may only mark the first test as skipped while running (and failing) subsequent tests.

**Solution:** Use `-Skip` on individual `Context` blocks instead of `Describe`:
```powershell
# WRONG - Skip on Describe doesn't propagate reliably
Describe "Tests requiring EXE" -Skip:(-not $script:ExeExists) {
    Context "File Tests" {
        It "Test 1" { ... }  # May still run and fail!
    }
}

# CORRECT - Skip on each Context block
Describe "Tests requiring EXE" {
    Context "File Tests" -Skip:(-not $script:ExeExists) {
        It "Test 1" { ... }  # Properly skipped
    }
    Context "Other Tests" -Skip:(-not $script:ExeExists) {
        It "Test 2" { ... }  # Properly skipped
    }
}
```

**Also:** Use `BeforeDiscovery` for variables that `-Skip` depends on:
```powershell
# BeforeDiscovery runs BEFORE test discovery, so -Skip can use the variable
BeforeDiscovery {
    $script:ExeExists = Test-Path ".\WsusManager.exe"
}

# BeforeAll runs AFTER discovery, so variables set here aren't available for -Skip
BeforeAll {
    $script:ExePath = ".\WsusManager.exe"  # Available during tests, not for -Skip
}
```

### 14. CLI Export Hanging for User Input

**Problem:** Export operation hangs waiting for keyboard input when called from GUI.

**Cause:** The CLI script's `Invoke-ExportToMedia` function prompts interactively for source and destination, but GUI passes parameters expecting non-interactive mode.

**Solution:** Check if destination is provided and skip prompts:
```powershell
function Invoke-ExportToMedia {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    # Detect non-interactive mode when DestinationPath is provided
    $nonInteractive = -not [string]::IsNullOrWhiteSpace($DestinationPath)

    if (-not $nonInteractive) {
        # Interactive prompts for source and destination
        $source = Read-Host "Enter source"
        # ... etc
    } else {
        # Use provided parameters directly
        $source = $SourcePath
    }
}
```

**GUI side:** Always pass all required parameters:
```powershell
# Pass export parameters to avoid interactive prompts
"& '$mgmt' -Export -DestinationPath '$dest' -SourcePath '$src'"
```

### 15. Using v4.0 Dialog Factory (WsusDialogs.psm1)

**Problem:** Repeating ~40 lines of dark-theme WPF dialog boilerplate for every new dialog.

**Solution:** Use `New-WsusDialog` + helper functions from `WsusDialogs.psm1`:
```powershell
# OLD pattern (~40 lines):
$dlg = New-Object System.Windows.Window
$dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
$dlg.Title = "My Dialog"
$dlg.Width = 480; $dlg.Height = 360
# ... etc.
$dlg.Add_KeyDown({ if ($_.Key -eq 'Escape') { $this.Close() } })

# NEW pattern (4 lines):
$d = New-WsusDialog -Title "My Dialog" -Width 480 -Height 360 -Owner $window
$d.ContentPanel.Children.Add((New-WsusDialogLabel "Choose folder:"))
$d.ContentPanel.Children.Add((New-WsusFolderBrowser -Label "Path").Panel)
$d.Window.ShowDialog()
```

### 16. Using v4.0 Operation Runner (WsusOperationRunner.psm1)

**Problem:** Operation execution logic (~200 lines of duplicated code) spread across Terminal/Embedded branches.

**Solution:** Call `Start-WsusOperation` which handles the full lifecycle:
```powershell
$ctx = @{
    Window          = $window
    Controls        = $controls
    OperationButtons = $script:OperationButtons
    OperationInputs  = $script:OperationInputs
}

Start-WsusOperation -Command "& '$mgmt' -Health" -Title "Diagnostics" -Context $ctx
# Handles: disable buttons, start process, pipe output to log, timeout watchdog, re-enable, notification
```

Always use `Find-WsusScript` to locate CLI scripts instead of hardcoding paths.

## Testing Checklist for GUI Changes

Before committing GUI changes, verify:

1. [ ] All operations show dialog BEFORE switching panels (no blank windows)
2. [ ] All function return values are suppressed (`$null =` or `| Out-Null`)
3. [ ] Event handlers use `Dispatcher.Invoke()` for UI updates
4. [ ] Event handlers pass data via `-MessageData`, not script-scope variables
5. [ ] Click handlers use `.GetNewClosure()` when capturing variables
6. [ ] New CLI parameters are added to BOTH GUI and CLI scripts
7. [ ] Concurrent operation blocking is in place
8. [ ] Cancel button properly kills running processes
9. [ ] All dialogs close with ESC key
10. [ ] **Script paths are validated before use** (show error if not found)
11. [ ] **Buttons are disabled during operations** (and re-enabled on completion/error/cancel)
12. [ ] Build passes: `.\build.ps1`
13. [ ] Manual test each affected operation
14. [ ] **Test from extracted zip** (not just dev environment)

## PowerShell-to-EXE GUI Template Features

This project serves as a template for building portable PowerShell GUI applications. Key reusable components:

### 1. DPI Awareness (GUI Header)
```powershell
#region DPI Awareness - Enable crisp rendering on high-DPI displays
try {
    Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class DpiAwareness {
            [DllImport("shcore.dll")]
            public static extern int SetProcessDpiAwareness(int awareness);
            [DllImport("user32.dll")]
            public static extern bool SetProcessDPIAware();
            public static void Enable() {
                try { SetProcessDpiAwareness(2); }  // Per-monitor DPI (Win 8.1+)
                catch { try { SetProcessDPIAware(); } catch { } }  // System DPI (Vista+)
            }
        }
"@ -ErrorAction SilentlyContinue
    [DpiAwareness]::Enable()
} catch { }
#endregion
```

### 2. AsyncHelpers Module (`Modules\AsyncHelpers.psm1`)
Provides non-blocking background operations for WPF applications:
- `Initialize-AsyncRunspacePool` / `Close-AsyncRunspacePool` - Runspace pool management
- `Invoke-Async` / `Wait-Async` / `Test-AsyncComplete` / `Stop-Async` - Async execution
- `Invoke-UIThread` - Safe UI thread dispatch
- `Start-BackgroundOperation` - Complete async workflow with callbacks

### 3. Error Handling Wrapper (Main Entry Point)
```powershell
try {
    $window.ShowDialog() | Out-Null
}
catch {
    $errorMsg = "A fatal error occurred:`n`n$($_.Exception.Message)"
    Write-Log "FATAL: $($_.Exception.Message)"
    Write-Log "Stack: $($_.ScriptStackTrace)"
    [System.Windows.MessageBox]::Show($errorMsg, "App - Error", "OK", "Error") | Out-Null
    exit 1
}
finally {
    # Cleanup: stop timers, kill processes, dispose resources
}
```

### 4. Startup Benchmarking
```powershell
$script:StartupTime = Get-Date
# ... initialization ...
$script:StartupDuration = ((Get-Date) - $script:StartupTime).TotalMilliseconds
Write-Log "Startup completed in $([math]::Round($script:StartupDuration, 0))ms"
```

### 5. CI Pipeline Features (`.github\workflows\build.yml`)
- **Code Review:** PSScriptAnalyzer with custom settings
- **Security Scan:** Specific security-focused rules
- **Pester Tests:** Unit tests with NUnit XML output (excludes ExeValidation.Tests.ps1)
- **Build:** PS2EXE compilation with version embedding
- **EXE Validation:** Runs AFTER build - PE header, 64-bit architecture, version info checks
- **Startup Benchmark:** Parse time, module import time, EXE size validation
- **Distribution Package:** Creates `dist/` folder with exe, Scripts/, Modules/, zip
- **Release Automation:** GitHub release with artifacts from `dist/` folder

**Important:** EXE validation tests are excluded from the main test job and run separately in the build job after the exe is created. This prevents test failures when no exe exists.

### 6. EXE Validation Tests (`Tests\ExeValidation.Tests.ps1`)
- PE header validation (MZ signature, PE signature)
- 64-bit architecture verification
- Version info embedding (product name, company, version)
- Startup benchmark (script parse time < 5s)
- Distribution package validation
