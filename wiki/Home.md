# WSUS Manager Wiki

Welcome to the WSUS Manager documentation! This wiki provides comprehensive guidance for installing, configuring, and using the WSUS Manager application.

## Quick Links

| Page | Description |
|------|-------------|
| [[Installation Guide]] | System requirements and setup instructions |
| [[User Guide]] | How to use the GUI application |
| [[Air-Gap Workflow]] | Managing updates on disconnected networks |
| [[Troubleshooting]] | Common issues and solutions |
| [[Developer Guide]] | Building from source and contributing |
| [[Module Reference]] | PowerShell module documentation |

---

## What is WSUS Manager?

WSUS Manager is a PowerShell-based automation suite for Windows Server Update Services (WSUS) with SQL Server Express 2022. It provides:

- **Modern GUI Application** - Dark-themed WPF interface with auto-refresh dashboard
- **Air-Gap Support** - Export/import operations for disconnected networks
- **Automated Maintenance** - Scheduled cleanup and optimization tasks
- **Health Monitoring** - Health Score (0-100), service/database/disk status
- **One-Click Operations** - Install, backup, restore, diagnostics
- **Operation History** - Track past operations with completion notifications
- **DB Size Trending** - Linear regression with days-until-full estimate

---

## Features

### Dashboard
Real-time monitoring with color-coded status cards and 30-second auto-refresh:
- **Health Score** - 0-100 weighted composite (Green/Yellow/Red grading)
- **Services** - SQL Server, WSUS, IIS status
- **Database** - SUSDB size vs 10GB SQL Express limit with trend indicator
- **Disk Space** - Available storage for updates
- **Automation** - Scheduled task status
- **Last Sync** - Last successful sync timestamp

### Server Modes
Server Mode auto-detects Online vs Air-Gap based on internet connectivity to show only relevant operations:
- **Online Mode** - Online Sync, Robocopy (outbound transfer to air-gap media)
- **Air-Gap Mode** - Robocopy (inbound from media), Reset Content

### Operations

**SETUP**
| Operation | Description |
|-----------|-------------|
| Install WSUS | Fresh installation with SQL Express 2022 |
| Fix SQL Login | Grant SQL sysadmin permissions to the current user |
| Restore DB | Restore SUSDB from a backup file |
| Create GPO | Copy GPO files and display DC deployment instructions |

**MAINTENANCE**
| Operation | Description |
|-----------|-------------|
| Online Sync | Sync updates with Microsoft (Full Sync / Quick Sync / Sync Only) |
| Schedule Task | Create or update the monthly sync scheduled task |
| Deep Cleanup | Aggressive space recovery — 6-step database maintenance |
| Robocopy | Transfer content to/from media (single dialog: Source + Destination + Start) |

**DIAGNOSTICS**
| Operation | Description |
|-----------|-------------|
| Diagnostics | Comprehensive health check with automatic repair |
| Reset Content | Re-verify content files against database after air-gap import |

> **Note:** Online Sync and Schedule Task should run on the **Online** WSUS server only.

---

## System Requirements

| Requirement | Specification |
|-------------|---------------|
| Operating System | Windows Server 2019 or later |
| CPU | 4+ cores recommended |
| RAM | 16+ GB recommended |
| Disk Space | 50+ GB for updates |
| PowerShell | 5.1 or later |
| SQL Server | SQL Server Express 2022 |
| Privileges | Local Administrator + SQL sysadmin |

---

## Getting Started

### Option 1: Distribution Package (Recommended)

1. Download `WsusManager-vX.X.X.zip` from the [Releases](../../releases) page
2. Extract to `C:\WSUS\` (EXE requires Scripts/ and Modules/ in the same directory)
3. Right-click `WsusManager.exe` -- Run as Administrator

### Option 2: PowerShell Scripts

```powershell
# Clone the repository
git clone https://github.com/anthonyscry/GA-WsusManager.git

# Run the CLI
.\Scripts\Invoke-WsusManagement.ps1
```

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 4.0.4 | Mar 2026 | sqlcmd.exe fallback for all DB ops, 6-month age decline (preserves approved), sysadmin check via sqlcmd |
| 4.0.3 | Mar 2026 | Smart decline policy (Edge/Office/WSL/Preview/ARM64), DNS preflight, 180min sync timeout, default products, WID auto-migration |
| 4.0.2 | Mar 2026 | GPO schtasks push, security hardening, robocopy fix, removed differential export, stream piping fix |
| 4.0.1 | Mar 2026 | GUI automation tests, install script sync, version alignment |
| 4.0.0 | Mar 2026 | Dialog factory, operation runner, health score, history, notifications, trending, splash screen, keyboard shortcuts, system tray |
| 3.9.0 | Mar 2026 | ARM64/25H2 auto-decline, PowerShell-only distribution restored |
| 3.8.12 | Feb 2026 | TrustServerCertificate compatibility fix |
| 3.8.10 | Feb 2026 | Deep Cleanup 6-step workflow, unified Diagnostics |
| 3.8.9 | Feb 2026 | Online Sync rename, Definition Updates, Reset Content |
| 3.8.7 | Jan 2026 | Live Terminal, Create GPO, WSUS install detection |
| 3.5.2 | Jan 2026 | 323 unit tests, security hardening, performance |

See [[Changelog]] for complete version history.

---

## Support

- **Issues**: [GitHub Issues](../../issues)
- **Documentation**: This wiki
- **Author**: Tony Tran, ISSO, GA-ASI

---

*Internal use - General Atomics Aeronautical Systems, Inc.*
