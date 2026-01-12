# WSUS Manager

**Author:** Tony Tran, ISSO, GA-ASI | **Version:** 3.8.3

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports both online and air-gapped networks.

---

## What's New in v3.8.3

### Bug Fixes
- **Fixed script not found error** - GUI now validates scripts exist before running operations
- **Fixed buttons not disabling** - Operation buttons are now disabled (grayed out) while an operation is running
- **Fixed OperationRunning flag** - Flag now properly resets in all code paths (completion, error, cancel)
- **Fixed Export parameters** - Removed invalid CLI parameters that were causing errors
- **Fixed distribution package** - Zip now includes required Scripts/ and Modules/ folders
- **Installer prompt** - Install WSUS now prompts for SQL/SSMS installer location if files are missing
- **Air-gap import** - GUI/CLI import runs non-interactively using the selected media path
- **Maintenance UX** - Monthly maintenance logs note that some phases can be quiet for several minutes

### Previous (v3.8.1)
- DPI awareness for high-resolution displays
- Global error handling with user-friendly dialogs
- Startup time logging for performance monitoring

### Previous (v3.8.0)
- ESC key support for all dialogs
- PSScriptAnalyzer code quality improvements

### Previous (v3.7.0)
- Output log panel 250px tall and open by default
- Unified Export/Import into single Transfer dialog
- Restore dialog auto-detects backup files
- Cancel button to stop running operations
- Concurrent operation blocking

### Previous (v3.5.x)
- Server Mode Toggle (Online/Air-Gap)
- Modern WPF GUI with dark theme
- Database Size Indicator with 10GB limit warnings
- 323 Pester unit tests
- PSScriptAnalyzer integration in build

---

## Quick Start

### Option 1: Portable Executable (Recommended)

1. Download the latest `WsusManager-vX.X.X.zip`
2. **Extract the entire folder** to your WSUS server (e.g., `C:\WSUS\WsusManager`)
3. Run **`WsusManager.exe`** as Administrator

**Important:** Keep the folder structure intact:
```
WsusManager.exe      # Main application
Scripts/             # Required - do not delete!
Modules/             # Required - do not delete!
DomainController/    # Optional - GPO scripts
```

> ⚠️ **Do not move WsusManager.exe without its Scripts and Modules folders!**

Features:
- Modern dark-themed WPF interface
- Auto-refresh dashboard (30-second interval)
- Database size monitoring with 10GB limit warnings
- Buttons disabled during operations to prevent conflicts

### Option 2: PowerShell Scripts

```powershell
.\Scripts\Invoke-WsusManagement.ps1
```

---

## Requirements

| Requirement | Specification |
|-------------|---------------|
| OS | Windows Server 2019+ |
| CPU | 4+ cores |
| RAM | 16+ GB |
| Disk | 50+ GB for updates |
| PowerShell | 5.1+ |
| SQL Server | SQL Server Express 2022 |

### Required Installers (place in `C:\WSUS\SQLDB\` or select at prompt)

- `SQLEXPRADV_x64_ENU.exe` - SQL Server Express 2022
- `SSMS-Setup-ENU.exe` - SQL Server Management Studio

---

## Dashboard

The dashboard displays four status cards with auto-refresh:

| Card | Information | Color Coding |
|------|-------------|--------------|
| Services | SQL/WSUS/IIS status | Green=All running, Orange=Partial, Red=Stopped |
| Database | SUSDB size / 10GB limit | Green=<7GB, Yellow=7-9GB, Red=>9GB |
| Disk Space | Free space on C: | Green=>50GB, Yellow=10-50GB, Red=<10GB |
| Automation | Scheduled task status | Green=Ready, Orange=Not Set |

**Quick Actions:** Health Check, Deep Cleanup, Maintenance, Start Services

---

## Server Mode

Server Mode auto-detects **Online** vs **Air-Gap** based on internet connectivity and shows only the relevant menu options for your server type.

| Mode | Visible Operations | Hidden |
|------|-------------------|--------|
| **Online** | Export to Media, Monthly Maintenance | Import from Media |
| **Air-Gap** | Import from Media | Export to Media, Monthly Maintenance |

The mode is saved to your user settings and persists across restarts.

---

## Main Operations

| Menu Item | Mode | Description |
|-----------|------|-------------|
| Install WSUS | Both | Install WSUS + SQL Express from scratch |
| Restore Database | Both | Restore SUSDB from backup |
| Export to Media | Online | Export DB and content to USB (Full or Differential) |
| Import from Media | Air-Gap | Import from USB to air-gapped server |
| Monthly Maintenance | Online | Sync with Microsoft, cleanup, and backup |
| Schedule Task | Online | Create or update the scheduled maintenance task |
| Deep Cleanup | Both | Aggressive cleanup for space recovery |
| Health Check | Both | Verify WSUS configuration and connectivity |
| Health + Repair | Both | Health check with automatic fixes |

> **Note:** Monthly Maintenance and Schedule Task are intended for the **Online** WSUS server only.

---

## Air-Gapped Workflow

```
Online WSUS → Monthly Maintenance
                    ↓
              Export to Media (Full or Differential)
                    ↓
            [Physical Transfer via USB]
                    ↓
Air-Gap WSUS → Import from Media
                    ↓
              Restore Database (if full export)
```

**Export Options:**
- **Full Export** - Complete database and all content files
- **Differential Export** - Only updates from the last N days (default: 30)

**Import Note:** When importing from external media via the GUI, the selected path is used without additional prompts.

---

## Domain Controller Setup

Run on the DC (not WSUS server):

```powershell
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

Imports 3 GPOs: Update Policy, Inbound Firewall, Outbound Firewall.

---

## Directory Layout

```
C:\WSUS\              # Content directory (required path)
C:\WSUS\SQLDB\        # SQL/SSMS installers
C:\WSUS\Logs\         # Log files
C:\WSUS\WsusContent\  # Update files (auto-created)
```

> **Important:** Content path must be `C:\WSUS` - NOT `C:\WSUS\wsuscontent`

---

## Repository Structure

```
GA-WsusManager/
├── WsusManager.exe              # Portable GUI (RECOMMENDED)
├── wsus-icon.ico                # Application icon
├── build.ps1                    # Build script for EXE
├── Scripts/
│   ├── WsusManagementGui.ps1    # GUI source (WPF/XAML)
│   ├── Invoke-WsusManagement.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusClientCheckIn.ps1
│   └── Set-WsusHttps.ps1
├── Modules/
│   ├── WsusUtilities.psm1       # Logging, colors, helpers
│   ├── WsusDatabase.psm1        # Database operations
│   ├── WsusHealth.psm1          # Health checks
│   ├── WsusServices.psm1        # Service management
│   ├── WsusFirewall.psm1        # Firewall rules
│   ├── WsusPermissions.psm1     # Directory permissions
│   ├── WsusConfig.psm1          # Configuration
│   ├── WsusExport.psm1          # Export/import
│   ├── WsusScheduledTask.psm1   # Scheduled tasks
│   └── WsusAutoDetection.psm1   # Server detection
├── Tests/                       # Pester unit tests (323 tests)
└── DomainController/            # GPO deployment scripts
```

---

## Building from Source

```powershell
# Full build with tests and code review
.\build.ps1

# Quick build (skip tests and review)
.\build.ps1 -SkipTests -SkipCodeReview

# Run tests only
.\build.ps1 -TestOnly
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Endless downloads | Use `C:\WSUS` NOT `C:\WSUS\wsuscontent` |
| Clients not updating | Run `gpupdate /force`, check ports 8530/8531 |
| Database errors | Grant sysadmin role to your account in SSMS |
| Services not starting | Use "Start Services" button on dashboard |
| Script not found error | Ensure Scripts folder is alongside the EXE |
| DB size shows "Offline" | SQL Server Express service not running |

---

## References

- [WSUS Maintenance Guide](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide)
- [SQL Server 2022 Express Download](https://www.microsoft.com/en-us/download/details.aspx?id=104781)
- [WSUS Best Practices](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment)
- [PowerShell Gallery - PS2EXE](https://www.powershellgallery.com/packages/ps2exe)

---

*Internal use - General Atomics Aeronautical Systems, Inc.*
