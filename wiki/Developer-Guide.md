# Developer Guide

This guide covers building WSUS Manager from source, contributing to the project, and understanding the codebase architecture.

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
├── WsusManager.exe              # Compiled executable
├── wsus-icon.ico                # Application icon
├── build.ps1                    # Build script
├── CLAUDE.md                    # AI assistant guide
├── README.md                    # User documentation
├── README-CONFLUENCE.md         # Confluence documentation
│
├── Scripts/                     # Main PowerShell scripts
│   ├── WsusManagementGui.ps1    # WPF GUI application
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusClientCheckIn.ps1
│   └── Set-WsusHttps.ps1
│
├── Modules/                     # Reusable modules
│   ├── WsusUtilities.psm1       # Logging, colors, helpers
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusHealth.psm1          # Health checks
│   ├── WsusServices.psm1        # Service management
│   ├── WsusFirewall.psm1        # Firewall rules
│   ├── WsusPermissions.psm1     # Permissions
│   ├── WsusConfig.psm1          # Configuration
│   ├── WsusExport.psm1          # Export/import
│   ├── WsusScheduledTask.psm1   # Scheduled tasks
│   └── WsusAutoDetection.psm1   # Auto-detection
│
├── Tests/                       # Pester test files
│   ├── WsusUtilities.Tests.ps1
│   ├── WsusDatabase.Tests.ps1
│   └── ... (10 test files)
│
├── DomainController/            # GPO scripts
│   └── Set-WsusGroupPolicy.ps1
│
└── wiki/                        # GitHub wiki pages
```

### Key Files

| File | Purpose |
|------|---------|
| `build.ps1` | Compiles GUI to EXE |
| `Scripts/WsusManagementGui.ps1` | Main GUI source |
| `Scripts/Invoke-WsusManagement.ps1` | CLI operations |
| `Modules/*.psm1` | Shared functionality |
| `Tests/*.Tests.ps1` | Unit tests |

---

## Building from Source

### Quick Build

```powershell
# Navigate to project root
cd C:\Projects\GA-WsusManager

# Full build with tests and code review
.\build.ps1

# Quick build (skip tests)
.\build.ps1 -SkipTests

# Skip code review only
.\build.ps1 -SkipCodeReview

# Skip both
.\build.ps1 -SkipTests -SkipCodeReview
```

### Build Options

| Parameter | Description |
|-----------|-------------|
| `-SkipTests` | Skip Pester unit tests |
| `-SkipCodeReview` | Skip PSScriptAnalyzer |
| `-TestOnly` | Run tests without building |
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
WsusManager.exe     # ~260 KB executable
dist\WsusManager-vX.X.X.zip  # Distribution package with Scripts/, Modules/, and branding assets
```

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
Modules/WsusDatabase.psm1    →    Tests/WsusDatabase.Tests.ps1
Modules/WsusHealth.psm1      →    Tests/WsusHealth.Tests.ps1
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
- **323 tests** across 10 test files
- All tests passing
- Covers all exported module functions

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
    ↑
    ├── WsusConfig
    ├── WsusDatabase
    ├── WsusServices
    ├── WsusFirewall
    ├── WsusPermissions
    ├── WsusExport
    ├── WsusScheduledTask
    └── WsusAutoDetection
            ↑
        WsusHealth (imports Services, Firewall, Permissions)
```

### GUI Architecture

The GUI (`WsusManagementGui.ps1`) uses:

- **WPF** - Windows Presentation Foundation
- **XAML** - UI definition (embedded in script)
- **Event Handlers** - Button clicks, toggles
- **Process Spawning** - Long operations run in child PowerShell process
- **Dispatcher** - UI updates from background threads

### Key Design Patterns

1. **Modular Functions**
   - Each module handles one concern
   - Functions are stateless where possible

2. **Configuration Management**
   - Settings in `%APPDATA%\WsusManager\settings.json`
   - Defaults in WsusConfig module

3. **Error Handling**
   - Try/catch with specific messages
   - Warnings for non-fatal issues
   - Logging via Write-Log

4. **Security**
   - Path validation (Test-SafePath)
   - SQL injection prevention
   - Admin privilege enforcement

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

3. **Add event handler**
   ```powershell
   $controls.BtnNewFeature.Add_Click({
       Run-Operation "newfeature" "New Feature"
   })
   ```

4. **Add operation handler**
   ```powershell
   # In Run-Operation switch
   "newfeature" { "& '$mgmtSafe' -NewFeature" }
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
3. `CLAUDE.md` - Current Version

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
| GUI freezes | Check for blocking operations |
| Tests fail | Check mock definitions |

---

## Next Steps

- [[Module Reference]] - Detailed function documentation
- [[Troubleshooting]] - Common issues
- [[Home]] - Back to main page
