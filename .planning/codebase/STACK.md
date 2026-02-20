# Technology Stack

**Analysis Date:** 2026-02-19

## Languages

**Primary:**
- PowerShell 5.1+ - All scripts, modules, and build automation
- XAML - GUI layout (embedded in `Scripts/WsusManagementGui.ps1`)
- C# - DPI awareness, console window helpers (inline via `Add-Type -TypeDefinition`)
- SQL T-SQL - Database operations and queries via `Invoke-Sqlcmd`

**Build/Configuration:**
- JSON - Settings persistence (`%APPDATA%\WsusManager\settings.json`)
- PSD1 - PowerShell module manifests and analyzer configuration
- YAML - GitHub Actions workflow definitions (`.github/workflows/`)

## Runtime

**Environment:**
- Windows PowerShell 5.1 (core requirement per `#Requires -Version 5.1` in `Scripts/WsusManagementGui.ps1`)
- Windows Server 2016+ or Windows 10+

**Package Manager:**
- PowerShell Gallery (PSGallery)
- No `package.json` or `requirements.txt` - dependencies installed via `Install-Module`
- Modules are self-contained without external package manager

## Frameworks

**GUI:**
- Windows Presentation Foundation (WPF) - Primary GUI framework
  - Assembly: `PresentationFramework`, `PresentationCore`, `WindowsBase`
  - XAML-based UI (dark theme with GitHub-style colors)
  - DPI-aware rendering (per-monitor on Win 8.1+, system DPI fallback on Vista+)

**Build/Compilation:**
- PS2EXE - Converts `WsusManagementGui.ps1` to standalone `.exe`
  - Configuration: `build.ps1`
  - Output: `WsusManager.exe` or custom name via `-OutputName`

**Testing:**
- Pester 5.0+ - Unit test framework
  - Config: Auto-installed by `Tests/Invoke-Tests.ps1`
  - Requirement: Minimum v5.0.0 enforced in test runner
  - Test files: 16 `.Tests.ps1` files in `Tests/` folder
  - Coverage: 323 unit tests across 10 test modules

**Code Quality:**
- PSScriptAnalyzer 1.21.0+ - PowerShell linting and code review
  - Config: `.PSScriptAnalyzerSettings.psd1`
  - Severity levels: Error, Warning
  - Custom exclusions: `PSAvoidUsingWriteHost`, `PSUseShouldProcessForStateChangingFunctions`, `PSUseSingularNouns`
  - Enforced rules: Security, best practices, approved verbs

**Windows Modules (Built-in):**
- WebAdministration - IIS management for HTTPS configuration
  - Used in: `Install-WsusWithSqlExpress.ps1`, `Set-WsusHttps.ps1`, `WsusAutoDetection.psm1`, `WsusHealth.psm1`
- UpdateServices - WSUS API (optional, fallback to WSUS Admin API)
  - Used in: `Invoke-WsusManagement.ps1`, `Invoke-WsusMonthlyMaintenance.ps1`

## Key Dependencies

**Critical:**
- SqlServer PowerShell Module - SQL Server query execution
  - Provides: `Invoke-Sqlcmd` (wrapper in `WsusUtilities.psm1`)
  - Version detection: Auto-detects v21.1+ for `TrustServerCertificate` parameter support
  - Used by: All database operations (`WsusDatabase.psm1`, GUI health checks)
  - Not required to be pre-installed - gracefully handles missing module

- Microsoft.UpdateServices.Administration.dll - WSUS server control
  - Path: `$env:ProgramFiles\Update Services\Api\Microsoft.UpdateServices.Administration.dll`
  - Loaded via `Add-Type -Path` in `Invoke-WsusMonthlyMaintenance.ps1`
  - Provides: WSUS server cleanup, synchronization, configuration

- System.Windows.Forms - Windows Forms for dialogs
  - Assemblies: `System.Windows.Forms`, `System.Windows.Forms.MessageBox`
  - Used in: Folder browser dialogs, file dialogs, message boxes

**Infrastructure:**
- robocopy.exe - File copying for export operations
  - Location: Built-in to Windows (`C:\Windows\System32\robocopy.exe`)
  - Used by: `WsusExport.psm1` for WSUS content export
  - Options: Multi-threaded (MT), differential copy, logging

- icacls.exe - File permission management
  - Location: Built-in to Windows
  - Used by: `WsusPermissions.psm1` for ACL management
  - Targets: WSUS content paths, WSUS system folders

- secedit.exe - Security policy configuration
  - Location: Built-in to Windows
  - Used by: `Install-WsusWithSqlExpress.ps1` for SA user permissions

- wuauclt.exe - Windows Update Agent client
  - Used by: `Invoke-WsusClientCheckIn.ps1` for forcing update detection/reporting

**System Assemblies:**
- System.Management - WMI/CIM operations
  - Used by: Service status checks (`Get-CimInstance` for service state monitoring)
- System.Net - Network connectivity testing
  - Used by: Internet connection validation (Ping with 500ms timeout)
- System.Diagnostics - Process management
  - Used by: Background operation execution, console window control

## Configuration

**Environment:**
- Settings file: `%APPDATA%\WsusManager\settings.json`
  - Persists: ContentPath, SqlInstance, ExportRoot, ServerMode, LiveTerminalMode
  - Auto-loaded on startup by `Import-WsusSettings` function
  - Auto-saved on change by `Save-Settings` function

**Standard Paths:**
- WSUS Content: `C:\WSUS\` (registry lookup fallback to `Get-WsusContentPath`)
- SQL/SSMS Installers: `C:\WSUS\SQLDB\`
- Logs: `C:\WSUS\Logs\` (daily log files: `WsusOperations_YYYY-MM-DD.log`)
- SQL Instance: `.\SQLEXPRESS` (named instance, dynamic port 1433)
- WSUS Database: `SUSDB` on SQL Express (10GB limit)

**Build Configuration:**
- Build script: `build.ps1` (line 52: `$Version = "3.8.12"`)
- Output: `dist/` folder (gitignored)
  - `WsusManager.exe` - Compiled executable
  - `WsusManager-vX.X.X.zip` - Distribution package with Scripts/, Modules/, DomainController/
- Code review: `PSScriptAnalyzer` on `Scripts\WsusManagementGui.ps1` and `Scripts\Invoke-WsusManagement.ps1`

**Database:**
- SQL Server Express 2022 (typical deployment)
- Authentication: sa account (SQL authentication)
- Database name: SUSDB
- Limitations: 10GB size limit (critical threshold monitored in GUI)

## Platform Requirements

**Development:**
- PowerShell 5.1+ (Windows 10/Server 2016+)
- Visual Studio Code (optional, for editing)
- Pester 5.0+ (auto-installed by build.ps1)
- PSScriptAnalyzer 1.21.0+ (auto-installed by build.ps1)
- Optional: PS2EXE (auto-resolved, supports OneDrive module paths per `build.ps1` line 68-71)

**Production:**
- Windows Server 2012 R2 or later (for WSUS support)
- Windows 10 1909+ or Windows 11 (for desktop deployments)
- SQL Server Express 2022 (or compatible version)
- Administrator privileges (required for all operations)
- IIS (Internet Information Services) with WSUS role installed

**Network:**
- WSUS HTTP port: 8530
- WSUS HTTPS port: 8531
- SQL Server port: 1433
- SQL Browser port: 1434 (UDP)
- All configurable via firewall rules in `WsusFirewall.psm1`

## Executable Build

**Process:**
1. Code review via PSScriptAnalyzer on 2 core scripts + all modules
2. Pester test execution (323 tests, ~10 test files)
3. PS2EXE compilation of `Scripts/WsusManagementGui.ps1` → `WsusManager.exe`
4. Distribution package creation (zip with Scripts/, Modules/, DomainController/)

**Output:**
- Single `.exe` file: ~280KB (after compilation, not self-contained)
- Requires adjacent `Scripts/` and `Modules/` folders to function
- Version embedded in exe via PS2EXE metadata

**CI/CD Pipeline:**
- Trigger: Push to main/master/develop or manual workflow_dispatch
- Runner: Windows Server (windows-latest)
- Concurrency: Single build per branch (cancel in-progress)
- Artifacts: Uploaded to GitHub Actions for download
- Release: Auto-published to GitHub Releases with version tag

---

*Stack analysis completed: 2026-02-19*
