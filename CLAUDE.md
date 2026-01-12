# CLAUDE.md - WSUS Manager

This file provides guidance for AI assistants working with this codebase.

## Project Overview

WSUS Manager is a PowerShell-based automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. It provides both a GUI application and CLI scripts for managing WSUS servers, including support for air-gapped networks.

**Author:** Tony Tran, ISSO, GA-ASI
**Current Version:** 3.8.3

## Repository Structure

```
GA-WsusManager/
├── WsusManager.exe              # Compiled GUI executable
├── build.ps1                    # Build script using PS2EXE
├── Scripts/
│   ├── WsusManagementGui.ps1    # Main GUI source (WPF/XAML)
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusClientCheckIn.ps1
│   └── Set-WsusHttps.ps1
├── Modules/                     # Reusable PowerShell modules (11 modules)
│   ├── WsusUtilities.psm1       # Logging, colors, helpers
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusHealth.psm1          # Health checks and repair
│   ├── WsusServices.psm1        # Service management
│   ├── WsusFirewall.psm1        # Firewall rules
│   ├── WsusPermissions.psm1     # Directory permissions
│   ├── WsusConfig.psm1          # Configuration
│   ├── WsusExport.psm1          # Export/import
│   ├── WsusScheduledTask.psm1   # Scheduled tasks
│   ├── WsusAutoDetection.psm1   # Server detection and auto-recovery
│   └── AsyncHelpers.psm1        # Async/background operation helpers for WPF
├── Tests/                       # Pester unit tests
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
6. Creates distribution zip with Scripts/, Modules/, and DomainController/ folders

**Version:** Update in `build.ps1` and `Scripts\WsusManagementGui.ps1` (`$script:AppVersion`)

### Distribution Package Structure

The build creates a complete distribution zip (`WsusManager-vX.X.X.zip`) containing:
```
WsusManager-vX.X.X/
├── WsusManager.exe           # Main GUI application
├── Scripts/                  # Required - operation scripts
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   └── ...
├── Modules/                  # Required - PowerShell modules
│   ├── WsusUtilities.psm1
│   ├── WsusHealth.psm1
│   └── ...
├── DomainController/         # Optional - GPO scripts
├── QUICK-START.txt
└── README.md
```

**IMPORTANT:** The EXE requires the Scripts/ and Modules/ folders to be in the same directory. Do not deploy the EXE alone.

## Key Technical Details

### PowerShell Modules
- All modules are in the `Modules/` directory
- Scripts import modules at runtime using relative paths
- Modules export functions explicitly via `Export-ModuleMember`
- `WsusHealth.psm1` automatically imports dependent modules (Services, Firewall, Permissions)
- `WsusAutoDetection.psm1` provides auto-recovery with re-queried service status (not Refresh())

### GUI Application
- Built with WPF (`PresentationFramework`) and XAML
- Dark theme matching GA-AppLocker style
- Auto-refresh dashboard (30-second interval) with refresh guard
- Server Mode toggle (Online vs Air-Gap) with context-aware menu
- Custom icon: `wsus-icon.ico` (if present)
- Requires admin privileges
- Settings stored in `%APPDATA%\WsusManager\settings.json`
- DPI-aware rendering (Windows 8.1+ per-monitor, Vista+ system fallback)
- Global error handling with user-friendly error dialogs
- Startup time logging for performance monitoring

### Standard Paths
- WSUS Content: `C:\WSUS\`
- SQL/SSMS Installers: `C:\WSUS\SQLDB\`
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
- Only the generic `WsusManager.exe` is committed (version is in About dialog)
- Use conventional commit messages
- Run tests before committing: `.\build.ps1 -TestOnly`

## Recent Changes (v3.8.3)

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
- **Pester Tests:** Unit tests with NUnit XML output
- **Build:** PS2EXE compilation with version embedding
- **Startup Benchmark:** Parse time, module import time, EXE size validation
- **EXE Validation:** PE header, 64-bit architecture, version info checks
- **Release Automation:** GitHub release with artifacts

### 6. EXE Validation Tests (`Tests\ExeValidation.Tests.ps1`)
- PE header validation (MZ signature, PE signature)
- 64-bit architecture verification
- Version info embedding (product name, company, version)
- Startup benchmark (script parse time < 5s)
- Distribution package validation
