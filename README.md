# WSUS Manager

**Author:** Tony Tran, ISSO, GA-ASI | **Version:** 3.5.2

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports both online and air-gapped networks.

---

## What's New in v3.5.2

- **Server Mode Toggle** - Switch between Online and Air-Gap modes to show only relevant menu items
- **Context-Aware Menu** - Online mode shows Export/Maintenance; Air-Gap mode shows Import
- **Cleaner Codebase** - Refactored UI code, removed unused files

### Previous (v3.5.1)

- **Modern WPF GUI** - Complete rewrite with dark theme matching GA-AppLocker
- **Database Size Indicator** - Shows current DB size out of 10GB limit with color coding
- **Export/Import Dialogs** - Folder pickers for media transfer operations
- **General Atomics Icon** - Consistent branding across GA tools

---

## Quick Start

### Option 1: Portable Executable (Recommended)

Download and run **`WsusManager.exe`** - no installation required.

- Modern dark-themed WPF interface
- Auto-refresh dashboard (30-second interval)
- Database size monitoring with 10GB limit warnings
- No PowerShell console window
- Portable standalone executable

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

### Required Installers (place in `C:\WSUS\SQLDB\`)

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

Toggle between **Online** and **Air-Gap** modes using the switch in the sidebar. This shows only the relevant menu options for your server type.

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
| Deep Cleanup | Both | Aggressive cleanup for space recovery |
| Health Check | Both | Verify WSUS configuration and connectivity |
| Health + Repair | Both | Health check with automatic fixes |

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
├── Tests/                       # Pester unit tests
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
- [SQL Server 2022 Express](https://www.microsoft.com/en-us/download/details.aspx?id=104781)

---

*Internal use - General Atomics Aeronautical Systems, Inc.*
