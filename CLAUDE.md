# CLAUDE.md - WSUS Manager

This file provides guidance for AI assistants working with this codebase.

## Project Overview

WSUS Manager is a PowerShell-based automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. It provides both a GUI application and CLI scripts for managing WSUS servers, including support for air-gapped networks.

**Author:** Tony Tran, ISSO, GA-ASI
**Current Version:** 3.5.2

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
├── Modules/                     # Reusable PowerShell modules
│   ├── WsusUtilities.psm1       # Logging, colors, helpers
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusHealth.psm1          # Health checks and repair
│   ├── WsusServices.psm1        # Service management
│   ├── WsusFirewall.psm1        # Firewall rules
│   ├── WsusPermissions.psm1     # Directory permissions
│   ├── WsusConfig.psm1          # Configuration
│   ├── WsusExport.psm1          # Export/import
│   ├── WsusScheduledTask.psm1   # Scheduled tasks
│   └── WsusAutoDetection.psm1   # Server detection
├── Tests/                       # Pester unit tests
└── DomainController/            # GPO deployment scripts
```

## Build Process

The project uses PS2EXE to compile PowerShell scripts into standalone executables.

```powershell
# Build with code review (recommended)
.\build.ps1

# Build without code review
.\build.ps1 -SkipCodeReview

# Build with custom output name
.\build.ps1 -OutputName "CustomName.exe"
```

The build process:
1. Runs PSScriptAnalyzer on `Scripts\WsusManagementGui.ps1` and `Scripts\Invoke-WsusManagement.ps1`
2. Blocks build if errors are found
3. Warns but continues if only warnings exist
4. Compiles `WsusManagementGui.ps1` to `WsusManager.exe` using PS2EXE

**Version:** Update in `build.ps1` and `Scripts\WsusManagementGui.ps1` (`$script:AppVersion`)

## Key Technical Details

### PowerShell Modules
- All modules are in the `Modules/` directory
- Scripts import modules at runtime using relative paths
- Modules export functions explicitly via `Export-ModuleMember`
- `WsusHealth.psm1` automatically imports dependent modules (Services, Firewall, Permissions)

### GUI Application
- Built with WPF (`PresentationFramework`) and XAML
- Dark theme matching GA-AppLocker style
- Auto-refresh dashboard (30-second interval)
- Server Mode toggle (Online vs Air-Gap) with context-aware menu
- Custom icon: `wsus-icon.ico` (if present)
- Requires admin privileges
- Settings stored in `%APPDATA%\WsusManager\settings.json`

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

### Modifying the GUI
1. Edit `Scripts\WsusManagementGui.ps1`
2. Run `.\build.ps1` to compile
3. Test the executable

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
