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
- **Health Monitoring** - Real-time status of services, database, and disk space
- **One-Click Operations** - Install, backup, restore, and repair WSUS

---

## Features

### Dashboard
Real-time monitoring with color-coded status cards:
- **Services** - SQL Server, WSUS, IIS status
- **Database** - SUSDB size vs 10GB SQL Express limit
- **Disk Space** - Available storage for updates
- **Automation** - Scheduled task status

### Server Modes
Server Mode auto-detects Online vs Air-Gap based on internet connectivity to show only relevant operations:
- **Online Mode** - Export, Monthly Maintenance
- **Air-Gap Mode** - Import from media

### Operations
| Operation | Description |
|-----------|-------------|
| Install WSUS | Fresh installation with SQL Express |
| Restore Database | Restore SUSDB from backup |
| Export to Media | Full or differential export to USB |
| Import from Media | Import updates to air-gapped server |
| Monthly Maintenance | Sync, cleanup, and backup |
| Schedule Task | Create or update the maintenance scheduled task |
| Deep Cleanup | Aggressive space recovery |
| Health Check | Verify configuration |
| Health + Repair | Auto-fix common issues |

> **Note:** Monthly Maintenance and Schedule Task should run on the **Online** WSUS server only.

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

### Option 1: Portable Executable (Recommended)

1. Download `WsusManager.exe` from the [Releases](../../releases) page
2. Run as Administrator
3. Configure settings on first launch

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
