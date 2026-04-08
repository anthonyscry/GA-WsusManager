# Developer Guide

This guide covers building WSUS Manager from source, contributing to the project, and understanding the codebase architecture.

**Current Version:** 4.0.4

---

## Table of Contents

1. [Development Environment](#development-environment)
2. [Project Structure](#project-structure)
3. [Building from Source](#building-from-source)
4. [Testing](#testing)
5. [Code Style](#code-style)
6. [Architecture Overview](#architecture-overview)
7. [Adding Features](#adding-features)
8. [Contributing](#contributing)

---

## Development Environment

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| PowerShell | 5.1+ | Runtime and development |
| VS Code | Latest | Recommended IDE |
| Git | Latest | Version control |
| Pester | 5.0+ | Unit testing |
| PSScriptAnalyzer | Latest | Code analysis |
| PS2EXE | 1.0+ | Compile to EXE |

### VS Code Extensions

Recommended extensions for PowerShell development:

```json
{
    "recommendations": [
        "ms-vscode.powershell",
        "streetsidesoftware.code-spell-checker",
        "eamodio.gitlens"
    ]
}
```

### Installing Dependencies

```powershell
# Install required modules
Install-Module -Name Pester -Force -SkipPublisherCheck
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name ps2exe -Force

# Verify installation
Get-Module -ListAvailable Pester, PSScriptAnalyzer, ps2exe
```

---

## Project Structure

```
GA-WsusManager/
├── build.ps1                    # Build script (PS2EXE)
├── CHANGELOG.md                 # Version history
├── CLAUDE.md                    # AI assistant guide
├── README.md                    # User documentation
├── Assets/
│   └── Branding/                # Source icon and logo assets
├── dist/                        # Build output (gitignored)
│   ├── GA-WsusManager.exe       # Compiled executable
│   └── WsusManager-vX.X.X.zip  # Distribution package
│
├── Scripts/                     # Main PowerShell scripts
│   ├── WsusManagementGui.ps1    # WPF GUI application
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusClientCheckIn.ps1
│   └── Set-WsusHttps.ps1
│
├── Modules/                     # Reusable modules (16 modules)
│   ├── WsusUtilities.psm1       # Logging, colors, helpers
│   ├── WsusConfig.psm1          # Configuration, timeouts, health weights
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusServices.psm1        # Service management
│   ├── WsusFirewall.psm1        # Firewall rules
│   ├── WsusPermissions.psm1     # Directory permissions
│   ├── WsusExport.psm1          # Export/import
│   ├── WsusScheduledTask.psm1   # Scheduled tasks
│   ├── WsusAutoDetection.psm1   # Server detection, dashboard data, 30s TTL cache
│   ├── WsusHealth.psm1          # Health checks, repair, health score (0-100)
│   ├── WsusDialogs.psm1         # [v4.0] Dialog factory -- New-WsusDialog, New-WsusFolderBrowser
│   ├── WsusOperationRunner.psm1 # [v4.0] Unified operation lifecycle -- Start/Stop/Complete
│   ├── WsusHistory.psm1         # [v4.0] Operation history -- JSON at %APPDATA%
│   ├── WsusNotification.psm1    # [v4.0] Toast/balloon notifications
│   ├── WsusTrending.psm1        # [v4.0] DB size trending with linear regression
│   └── AsyncHelpers.psm1        # Async/background operation helpers for WPF
│
├── Tests/                       # Pester test files (19 test files)
│   ├── WsusUtilities.Tests.ps1
│   ├── WsusConfig.Tests.ps1
│   ├── WsusDatabase.Tests.ps1
│   ├── WsusServices.Tests.ps1
│   ├── WsusFirewall.Tests.ps1
│   ├── WsusPermissions.Tests.ps1
│   ├── WsusExport.Tests.ps1
│   ├── WsusScheduledTask.Tests.ps1
│   ├── WsusAutoDetection.Tests.ps1
│   ├── WsusHealth.Tests.ps1
│   ├── WsusDialogs.Tests.ps1
│   ├── WsusOperationRunner.Tests.ps1
│   ├── WsusHistory.Tests.ps1
│   ├── ProductFilter.Tests.ps1
│   ├── CliIntegration.Tests.ps1
│   ├── ExeValidation.Tests.ps1
│   ├── Integration.Tests.ps1
│   ├── FlaUI.Tests.ps1
│   └── StartupE2E.Tests.ps1
│
├── DomainController/            # Air-gap GPO deployment scripts
│   └── Set-WsusGroupPolicy.ps1
│
├── docs/                        # Project documentation
│   ├── ci-cd.md
│   ├── releases.md
│   ├── WSUS-Manager-SOP.md
│   └── ...
│
└── wiki/                        # GitHub wiki pages
    ├── Home.md
    ├── Developer-Guide.md
    ├── Module-Reference.md
    └── ...
```

### Key Files

| File | Purpose |
|------|---------|
| `build.ps1` | Compiles GUI to EXE, runs tests and code review |
| `CHANGELOG.md` | Version history and release notes |
| `Scripts/WsusManagementGui.ps1` | Main GUI source (WPF/XAML) |
| `Scripts/Invoke-WsusManagement.ps1` | CLI operations engine |
| `Scripts/Invoke-WsusMonthlyMaintenance.ps1` | Online sync and maintenance |
| `Scripts/Install-WsusWithSqlExpress.ps1` | WSUS + SQL Express installer |
| `Modules/WsusUtilities.psm1` | Base module -- logging, colors, path validation |
| `Modules/WsusConfig.psm1` | Configuration, dialog sizes, timeouts, health weights |
| `Modules/WsusDatabase.psm1` | SQL queries, database maintenance |
| `Modules/WsusHealth.psm1` | Health checks, repair, weighted health score (0-100) |
| `Modules/WsusAutoDetection.psm1` | Server detection, dashboard data, 30s TTL cache |
| `Modules/WsusDialogs.psm1` | [v4.0] Dialog factory -- eliminates boilerplate |
| `Modules/WsusOperationRunner.psm1` | [v4.0] Unified operation lifecycle with timeout watchdog |
| `Modules/WsusHistory.psm1` | [v4.0] Operation history -- JSON storage, 100-entry trim |
| `Modules/WsusNotification.psm1` | [v4.0] Toast/balloon/log completion notifications |
| `Modules/WsusTrending.psm1` | [v4.0] DB size trending, linear regression, days-until-full |
| `Modules/AsyncHelpers.psm1` | WPF runspace pool management and async execution |
| `Tests/*.Tests.ps1` | Pester unit and integration tests |

---

## Building from Source

### Quick Build

```powershell
# Navigate to project root
cd C:\Projects\GA-WsusManager

# Full build with tests and code review
.\build.ps1 -NoPush

# Quick build (skip tests)
.\build.ps1 -SkipTests -NoPush

# Skip code review only
.\build.ps1 -SkipCodeReview -NoPush

# Skip both
.\build.ps1 -SkipTests -SkipCodeReview -NoPush
```

Use `-NoPush` for normal local builds so `build.ps1` does not auto-commit and push `dist/`.

### Build Options

| Parameter | Description |
|-----------|-------------|
| `-SkipTests` | Skip Pester unit tests |
| `-SkipCodeReview` | Skip PSScriptAnalyzer |
| `-TestOnly` | Run tests without building |
| `-NoPush` | Prevent `build.ps1` from auto-committing and pushing `dist/` |
| `-OutputName` | Custom output filename |

### Build Process

The build script performs:

1. **Test Phase** (unless skipped)
   - Runs all Pester tests
   - Fails build if tests fail

2. **Code Review** (unless skipped)
   - Runs PSScriptAnalyzer on main scripts
   - Blocks on errors
   - Warns on warnings

3. **Compile Phase**
   - Uses PS2EXE to create executable
   - Sets admin requirement
   - Embeds icon
   - Creates 64-bit executable

### Build Output

```
dist/
├── GA-WsusManager.exe           # Compiled executable
└── WsusManager-vX.X.X.zip       # Full distribution package
```

The distribution zip contains everything needed for deployment:

```
GA-WsusManager.exe
Scripts/                         # Required -- operation scripts
Modules/                         # Required -- PowerShell modules
DomainController/                # Optional -- air-gap GPO scripts
general_atomics_logo_big.ico
general_atomics_logo_small.ico
QUICK-START.txt
README.txt
CHANGELOG.txt
```

**Important:** The EXE requires the `Scripts/` and `Modules/` folders in the same directory. Do not deploy the EXE alone.

---

## Testing

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path .\Tests -Output Detailed

# Run specific module tests
Invoke-Pester -Path .\Tests\WsusDatabase.Tests.ps1

# Run with code coverage
Invoke-Pester -Path .\Tests -CodeCoverage .\Modules\*.psm1

# Run via build script
.\build.ps1 -TestOnly
```

### Test Structure

Each module has a corresponding test file:

```
Modules/WsusDatabase.psm1       -->  Tests/WsusDatabase.Tests.ps1
Modules/WsusHealth.psm1         -->  Tests/WsusHealth.Tests.ps1
Modules/WsusDialogs.psm1        -->  Tests/WsusDialogs.Tests.ps1
Modules/WsusOperationRunner.psm1 --> Tests/WsusOperationRunner.Tests.ps1
Modules/WsusHistory.psm1        -->  Tests/WsusHistory.Tests.ps1
```

Additional test files cover cross-cutting concerns:

```
Tests/CliIntegration.Tests.ps1   # CLI parameter validation and config integration
Tests/ProductFilter.Tests.ps1    # Update product/classification filtering rules
Tests/ExeValidation.Tests.ps1    # PE header, architecture, version info (runs post-build)
Tests/Integration.Tests.ps1      # Cross-module integration tests
Tests/FlaUI.Tests.ps1            # GUI automation tests
Tests/StartupE2E.Tests.ps1       # End-to-end startup tests
```

### Writing Tests

Example test structure:

```powershell
BeforeAll {
    # Import module
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusDatabase.psm1"
    Import-Module $ModulePath -Force
}

Describe "Get-WsusDatabaseSize" {
    Context "With mocked SQL query" {
        BeforeAll {
            Mock Invoke-SqlScalar { return 5.5 }
        }

        It "Should return database size in GB" {
            $result = Get-WsusDatabaseSize
            $result | Should -BeOfType [decimal]
        }
    }
}

AfterAll {
    Remove-Module WsusDatabase -Force -ErrorAction SilentlyContinue
}
```

### Test Statistics

Current coverage:
- **490+ tests** across 19 test files
- All tests passing
- Covers all exported module functions
- Includes unit, integration, CLI, and GUI tests

Key test file contributions:
- WsusDialogs.Tests.ps1 -- 58 tests (dialog factory, folder browser, styled helpers)
- WsusOperationRunner.Tests.ps1 -- 27 tests (operation lifecycle, timeout, script finder)
- WsusHistory.Tests.ps1 -- 23 tests (JSON storage, trim, file-lock, corrupt recovery)
- ProductFilter.Tests.ps1 -- 31 tests (decline rules, approval exclusions, product matching)

---

## Code Style

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Functions | Verb-NounNoun | `Get-WsusDatabaseSize` |
| Variables | camelCase | `$databaseSize` |
| Parameters | PascalCase | `-SqlInstance` |
| Private Functions | _PrefixedName | `_ValidatePath` |
| Constants | UPPER_CASE | `$MAX_RETRIES` |

### Approved Verbs

Use PowerShell approved verbs:
- `Get-`, `Set-`, `New-`, `Remove-`
- `Test-`, `Invoke-`, `Start-`, `Stop-`
- `Import-`, `Export-`, `Initialize-`

Check with: `Get-Verb`

### Function Documentation

All public functions should have comment-based help:

```powershell
function Get-WsusDatabaseSize {
    <#
    .SYNOPSIS
        Gets the current size of the SUSDB database.

    .DESCRIPTION
        Queries SQL Server to get the SUSDB database size in GB.

    .PARAMETER SqlInstance
        The SQL Server instance name. Defaults to .\SQLEXPRESS.

    .OUTPUTS
        [decimal] Database size in GB

    .EXAMPLE
        Get-WsusDatabaseSize
        Returns: 5.5

    .EXAMPLE
        Get-WsusDatabaseSize -SqlInstance "server\instance"
    #>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS"
    )
    # Implementation
}
```

### Module Exports

Explicitly export functions:

```powershell
Export-ModuleMember -Function @(
    'Get-WsusDatabaseSize',
    'Get-WsusDatabaseStats',
    'Remove-DeclinedSupersessionRecords'
)
```

### Color Output

Use standard color functions from WsusUtilities:

```powershell
Write-Success "Operation completed"      # Green
Write-Failure "Operation failed"         # Red
Write-WsusWarning "Warning message"      # Yellow
Write-Info "Information"                 # Cyan
```

---

## Architecture Overview

### Module Dependencies

```
WsusUtilities (base)
    |
    +-- WsusConfig (configuration, dialog sizes, timeouts, health weights)
    +-- WsusDatabase (SQL queries, maintenance)
    +-- WsusServices (service management)
    +-- WsusFirewall (firewall rules)
    +-- WsusPermissions (directory permissions)
    +-- WsusExport (export/import operations)
    +-- WsusScheduledTask (scheduled tasks)
    +-- WsusAutoDetection (server detection, dashboard data, 30s TTL cache)
    |       |
    +-- WsusHealth (imports Services, Firewall, Permissions; weighted health score)
    +-- WsusDialogs (v4.0 - standalone, WPF dialog factory)
    +-- WsusOperationRunner (v4.0 - uses WsusConfig for timeouts)
    +-- WsusHistory (v4.0 - standalone JSON storage)
    +-- WsusNotification (v4.0 - standalone, toast/balloon/log)
    +-- WsusTrending (v4.0 - standalone, linear regression)
    +-- AsyncHelpers (standalone, WPF runspace management)
```

### GUI Architecture

The GUI (`WsusManagementGui.ps1`) uses:

- **WPF** - Windows Presentation Foundation
- **XAML** - UI definition (embedded in script)
- **Event Handlers** - Button clicks, toggles
- **Process Spawning** - Long operations run in child PowerShell process
- **Dispatcher** - UI updates from background threads

#### v4.0 GUI Patterns

- **Dialog Factory** (`WsusDialogs.psm1`) - All modal dialogs use `New-WsusDialog` instead of 40+ lines of repeated WPF boilerplate. Provides dark-themed window shell with ESC-close, styled labels, buttons, text boxes, and folder browser panels.

- **Unified Operation Lifecycle** (`WsusOperationRunner.psm1`) - `Start-WsusOperation` handles the full lifecycle: disable buttons, start process, pipe output to log panel, timeout watchdog, re-enable buttons, and send completion notification. Supports both Terminal and Embedded modes.

- **Operation History Tracking** (`WsusHistory.psm1`) - Every operation writes to `%APPDATA%\WsusManager\history.json` with type, duration, result, and summary. The **☰ History** button in the bottom bar shows the last 100 operations.

- **Health Score Dashboard** (`WsusHealth.psm1`) - `Get-WsusHealthScore` returns a weighted composite (0-100): Services=30, DB=20, Sync=20, Disk=20, LastOp=10. Displayed as a color-coded card (Green >=80, Yellow 50-79, Red <50).

- **Completion Notifications** (`WsusNotification.psm1`) - 3-tier fallback: Windows 10 toast, balloon tip, or log-only. Called automatically by operation exit handlers.

- **Dashboard Data Caching** (`WsusAutoDetection.psm1`) - Dashboard helper functions use a 30-second TTL cache. `Get-WsusDashboardCachedData` serves stale data while refresh runs in background. `Test-WsusDashboardDataUnavailable` triggers after 10 consecutive failures.

- **DB Size Trending** (`WsusTrending.psm1`) - Linear regression over last 30 days estimates days until the 10GB SQL Express limit. Shows Critical/Warning alerts on the dashboard.

### Key Design Patterns

1. **Modular Functions**
   - Each module handles one concern
   - Functions are stateless where possible

2. **Configuration Management**
   - Settings in `%APPDATA%\WsusManager\settings.json`
   - Defaults in WsusConfig module
   - Per-operation timeouts via `Get-WsusOperationTimeout`

3. **Error Handling**
   - Try/catch with specific messages
   - Warnings for non-fatal issues
   - Logging via Write-Log

4. **Security**
   - Path validation (Test-SafePath, Test-ValidPath)
   - Path escaping (Get-EscapedPath)
   - SQL injection prevention
   - Admin privilege enforcement

5. **Dialog Factory** (v4.0)
   - `New-WsusDialog` eliminates 6 copy-pasted dialog boilerplate patterns
   - Consistent dark theme, ESC-close, and owner window binding
   - Helper functions for labels, buttons, text boxes, and folder browsers

6. **Unified Operation Lifecycle** (v4.0)
   - `Start-WsusOperation` replaces ~200 lines of duplicated operation logic
   - Timeout watchdog kills hung processes (configurable per-type in WsusConfig)
   - Automatic button disable/re-enable, history write, and notification

7. **Dashboard Data Caching** (v4.0)
   - 30-second TTL cache prevents redundant queries during auto-refresh
   - Graceful degradation after 10 consecutive failures
   - Runspace-safe functions for background data collection

---

## Adding Features

### Adding a New Module Function

1. **Add function to module**
   ```powershell
   # In Modules/WsusDatabase.psm1
   function New-WsusFeature {
       param([string]$Parameter)
       # Implementation
   }
   ```

2. **Export the function**
   ```powershell
   Export-ModuleMember -Function @(
       # existing functions...
       'New-WsusFeature'
   )
   ```

3. **Add tests**
   ```powershell
   # In Tests/WsusDatabase.Tests.ps1
   Describe "New-WsusFeature" {
       It "Should do something" {
           # Test code
       }
   }
   ```

4. **Run tests**
   ```powershell
   Invoke-Pester -Path .\Tests\WsusDatabase.Tests.ps1
   ```

### Adding a GUI Feature

1. **Add XAML element**
   ```xml
   <Button x:Name="BtnNewFeature" Content="New Feature" />
   ```

2. **Add to controls hashtable**
   ```powershell
   $controls = @{
       BtnNewFeature = $window.FindName("BtnNewFeature")
   }
   ```

3. **Add event handler** (v4.0 pattern using operation runner)
   ```powershell
   $controls.BtnNewFeature.Add_Click({
       if ($script:OperationRunning) { return }
       $ctx = @{
           Window           = $window
           Controls         = $controls
           OperationButtons = $script:OperationButtons
           OperationInputs  = $script:OperationInputs
       }
       $scriptPath = Find-WsusScript "Invoke-WsusManagement.ps1"
       Start-WsusOperation -Command "& '$scriptPath' -NewFeature" `
                           -Title "New Feature" -Context $ctx
   })
   ```

4. **Add CLI parameter** (update both GUI and CLI scripts together)
   ```powershell
   # In Invoke-WsusManagement.ps1
   param(
       [switch]$NewFeature
   )
   if ($NewFeature) { Invoke-NewFeature }
   ```

### Adding a Dialog (v4.0 pattern)

Use the dialog factory instead of manual WPF boilerplate:

```powershell
$d = New-WsusDialog -Title "My Dialog" -Width 480 -Height 360 -Owner $window
$d.ContentPanel.Children.Add((New-WsusDialogLabel "Choose folder:"))
$fb = New-WsusFolderBrowser -Label "Path"
$d.ContentPanel.Children.Add($fb.Panel)
$d.ContentPanel.Children.Add((New-WsusDialogButton "OK" {
    $selectedPath = $fb.TextBox.Text
    $d.Window.Close()
}))
$d.Window.ShowDialog()
```

### Adding a CLI Option

1. **Add parameter to script**
   ```powershell
   param(
       [switch]$NewFeature
   )
   ```

2. **Add parameter set logic**
   ```powershell
   if ($NewFeature) {
       Invoke-NewFeature
   }
   ```

3. **Implement function**
   ```powershell
   function Invoke-NewFeature {
       # Implementation
   }
   ```

---

## Contributing

### Workflow

1. **Fork** the repository
2. **Clone** your fork
3. **Create branch** for your feature
4. **Make changes** following code style
5. **Add tests** for new functionality
6. **Run tests** to verify
7. **Commit** with descriptive message
8. **Push** to your fork
9. **Open Pull Request**

### Commit Messages

Use conventional commit format:

```
type: short description

Longer description if needed.

Fixes #123
```

Types:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `test:` - Tests
- `refactor:` - Code refactoring
- `style:` - Formatting
- `chore:` - Version bumps, dependency updates

### Pull Request Guidelines

- One feature/fix per PR
- Include tests for new features
- Update documentation if needed
- All tests must pass
- Code review required

### Versioning

Version format: `MAJOR.MINOR.PATCH`

Update version in:
1. `build.ps1` - `$script:Version`
2. `Scripts/WsusManagementGui.ps1` - `$script:AppVersion`
3. `CHANGELOG.md` - Add new version entry with changes
4. `CLAUDE.md` - Current Version (in Project Overview section)

---

## Debugging

### Debug GUI

```powershell
# Run GUI script directly (not compiled)
powershell -ExecutionPolicy Bypass -File .\Scripts\WsusManagementGui.ps1
```

### Debug Modules

```powershell
# Import module in console
Import-Module .\Modules\WsusDatabase.psm1 -Force

# Test functions
Get-WsusDatabaseSize -Verbose
```

### VS Code Debugging

Create `.vscode/launch.json`:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug GUI",
            "type": "PowerShell",
            "request": "launch",
            "script": "${workspaceFolder}/Scripts/WsusManagementGui.ps1"
        }
    ]
}
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Module not loading | Check Import-Module path |
| Function not found | Check Export-ModuleMember |
| GUI freezes | Check for blocking operations; use Dispatcher |
| Tests fail | Check mock definitions |
| Dialog boilerplate | Use New-WsusDialog from WsusDialogs.psm1 |
| Operation duplication | Use Start-WsusOperation from WsusOperationRunner.psm1 |
| Unicode in PS 5.1 | Never use em dashes or smart quotes -- PS 5.1 breaks |

---

## Next Steps

- [[Module Reference]] - Detailed function documentation
- [[Troubleshooting]] - Common issues
- [[Home]] - Back to main page
