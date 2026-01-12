# WSUS Manager

| **Author** | Tony Tran, ISSO, GA-ASI |
|------------|-------------------------|
| **Version** | 3.8.3 |
| **Last Updated** | March 2026 |

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports online and air-gapped networks.

---

## Downloads

### Project Bundle

> **Upload your project bundle here:**
>
> **[PLACEHOLDER: Upload WsusManager-v3.8.3.zip here]**
>
> The bundle includes:
> - WsusManager.exe (portable GUI)
> - All PowerShell scripts and modules
> - Documentation and tests

---

### Recommended: Portable Executable

| File | Description |
|------|-------------|
| **WsusManager.exe** | Standalone GUI - just download and run (always latest version) |

- Modern dark-themed WPF interface
- Auto-refresh dashboard (30-second interval)
- Database size monitoring with 10GB limit warnings
- No installation required - fully portable
- No PowerShell console window

### Alternative: PowerShell Scripts

| File | Description |
|------|-------------|
| Scripts/Invoke-WsusManagement.ps1 | PowerShell CLI version |

```powershell
.\Scripts\Invoke-WsusManagement.ps1
```

### Required Installers

> Save to C:\WSUS\SQLDB\ before installation (or select folder when prompted)

| File | Description | Download Link |
|------|-------------|---------------|
| SQLEXPRADV_x64_ENU.exe | SQL Server Express 2022 | [Microsoft Download](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |
| SSMS-Setup-ENU.exe | SQL Server Management Studio | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |

---

## What's New in v3.8.3

### Improvements

| Feature | Description |
|---------|-------------|
| Installer Prompt | Install WSUS now prompts for the SQL/SSMS installer folder if files are missing |
| Air-Gap Import | Import from external media runs non-interactively when launched from GUI/CLI |
| Maintenance UX | Monthly maintenance logs note that some phases can be quiet for several minutes |
| Packaging | Distribution zip includes required Scripts/Modules and branding assets |

### Previous Highlights

| Feature | Description |
|---------|-------------|
| Server Mode Toggle | Switch between Online and Air-Gap modes |
| Modern WPF GUI | Dark theme matching GA-AppLocker |
| Database Size Indicator | Shows DB size out of 10GB limit with color coding |
| Export/Import Dialogs | Folder pickers for media transfer operations |

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
| Privileges | Local Admin + SQL sysadmin |

---

## Dashboard

The dashboard displays four status cards with auto-refresh every 30 seconds:

| Card | Information | Color Coding |
|------|-------------|--------------|
| Services | SQL/WSUS/IIS status | Green = All running, Orange = Partial, Red = Stopped |
| Database | SUSDB size / 10GB limit | Green = <7GB, Yellow = 7-9GB, Red = >9GB |
| Disk Space | Free space on C: drive | Green = >50GB, Yellow = 10-50GB, Red = <10GB |
| Automation | Scheduled task status | Green = Ready, Orange = Not Set |

**Quick Actions:**
- Run Health Check
- Deep Cleanup
- Monthly Maintenance
- Start Services (auto-recovery)

---

## Server Mode Toggle

Server Mode auto-detects **Online** vs **Air-Gap** based on internet connectivity.

| Mode | Visible Operations | Hidden Operations |
|------|-------------------|-------------------|
| **Online** | Export to Media, Monthly Maintenance | Import from Media |
| **Air-Gap** | Import from Media | Export to Media, Monthly Maintenance |

The mode is saved to user settings and persists across restarts.

---

## Operations Menu

| Menu Item | Description |
|-----------|-------------|
| Install WSUS | Install WSUS + SQL Express from scratch |
| Restore Database | Restore SUSDB from backup |
| Export to Media | Export DB and content to USB (Full or Differential) |
| Import from Media | Import from USB to air-gapped server |
| Monthly Maintenance | Run WSUS cleanup and optimization |
| Schedule Task | Create or update the scheduled maintenance task |
| Deep Cleanup | Aggressive cleanup for space recovery |
| Health Check | Verify WSUS configuration and connectivity |
| Health + Repair | Health check with automatic fixes |
| Settings | Configure paths and SQL instance |
| About | Application info and credits |

> **Note:** Monthly Maintenance and Schedule Task are intended for the **Online** WSUS server only.

---

## Export Options

| Type | Description |
|------|-------------|
| Full Export | Complete database backup and all content files |
| Differential Export | Only updates from the last N days (default: 30 days) |

Both options prompt for destination folder selection.

---

## Air-Gapped Workflow

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS | Monthly Maintenance |
| 2 | Online WSUS | Export to Media (Full or Differential) |
| 3 | - | Physical transfer via USB |
| 4 | Air-Gap WSUS | Import from Media |
| 5 | Air-Gap WSUS | Restore Database (if full export) |

---

## Domain Controller Setup

> Run on DC, not WSUS server

```powershell
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

Imports three GPOs:
- Update Policy GPO
- Inbound Firewall GPO
- Outbound Firewall GPO

---

## SQL Sysadmin Setup

1. Open SSMS
2. Connect to localhost\SQLEXPRESS
3. Security > Logins > New Login
4. Add your domain group
5. Server Roles > Check **sysadmin** > OK

---

## Directory Layout

| Path | Purpose |
|------|---------|
| C:\WSUS\ | Content directory (required) |
| C:\WSUS\SQLDB\ | SQL/SSMS installers |
| C:\WSUS\Logs\ | Log files |
| C:\WSUS\WsusContent\ | Update files (auto-created) |

> **Important:** Content path must be C:\WSUS - NOT C:\WSUS\wsuscontent

---

## Repository Structure

| Path | Description |
|------|-------------|
| WsusManager.exe | Portable GUI Application (RECOMMENDED) |
| wsus-icon.ico | Application icon |
| build.ps1 | Build script for EXE (includes tests + code review) |
| Scripts/ | PowerShell scripts (6 scripts) |
| Modules/ | PowerShell modules (10 modules) |
| Tests/ | Pester unit tests (323 tests) |
| DomainController/ | GPO deployment scripts |

---

## Building from Source

| Command | Description |
|---------|-------------|
| .\build.ps1 | Full build with tests and code review |
| .\build.ps1 -SkipTests -SkipCodeReview | Quick build |
| .\build.ps1 -TestOnly | Run tests only |

---

## PowerShell Modules

The application uses a modular architecture with 10 PowerShell modules:

| Module | Description |
|--------|-------------|
| WsusUtilities.psm1 | Logging, color output, helpers |
| WsusDatabase.psm1 | Database operations, cleanup, optimization |
| WsusHealth.psm1 | Health checks and diagnostics |
| WsusServices.psm1 | Service management (start/stop/restart) |
| WsusFirewall.psm1 | Firewall rule management |
| WsusPermissions.psm1 | Directory permissions |
| WsusConfig.psm1 | Configuration management |
| WsusExport.psm1 | Export/import operations |
| WsusScheduledTask.psm1 | Scheduled task management |
| WsusAutoDetection.psm1 | Server detection and auto-recovery |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Endless downloads | Content path must be C:\WSUS (not C:\WSUS\wsuscontent) |
| Clients not updating | Run gpupdate /force, check ports 8530/8531 |
| Database errors | Grant sysadmin role in SSMS |
| Services not starting | Use "Start Services" button on dashboard |
| Script not found error | Ensure Scripts folder is alongside the EXE |
| DB size shows "Offline" | SQL Server Express service not running |
| Service refresh errors | Fixed in v3.5.2 - upgrade to latest version |

---

## Helpful Links

### Microsoft Documentation

| Topic | Link |
|-------|------|
| WSUS Maintenance Guide | [https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide) |
| WSUS Deployment Planning | [https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment) |
| WSUS Administration Guide | [https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/manage/wsus-messages-and-troubleshooting-tips](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/manage/wsus-messages-and-troubleshooting-tips) |
| WSUS Troubleshooting | [https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-client-fails-to-connect](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-client-fails-to-connect) |

### SQL Server Resources

| Topic | Link |
|-------|------|
| SQL Server Express 2022 Download | [https://www.microsoft.com/en-us/download/details.aspx?id=104781](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |
| SSMS Download | [https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |
| SQL Express Limitations | [https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022](https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022) |

### PowerShell Resources

| Topic | Link |
|-------|------|
| PS2EXE Module | [https://www.powershellgallery.com/packages/ps2exe](https://www.powershellgallery.com/packages/ps2exe) |
| Pester Testing Framework | [https://pester.dev/](https://pester.dev/) |
| PSScriptAnalyzer | [https://www.powershellgallery.com/packages/PSScriptAnalyzer](https://www.powershellgallery.com/packages/PSScriptAnalyzer) |

### Windows Server Update Services

| Topic | Link |
|-------|------|
| WSUS Content Directory | [https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus) |
| WSUS GPO Settings | [https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/4-configure-group-policy-settings-for-automatic-updates](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/4-configure-group-policy-settings-for-automatic-updates) |
| WSUS SSL Configuration | [https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus#25-secure-wsus-with-the-secure-sockets-layer-protocol](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus#25-secure-wsus-with-the-secure-sockets-layer-protocol) |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.5.2 | Jan 2026 | Security hardening, service refresh fix, 323 unit tests |
| 3.5.1 | Jan 2026 | Performance optimizations, batch queries |
| 3.5.0 | Jan 2026 | Server mode toggle, modern WPF GUI |
| 3.4.x | Dec 2025 | Database size indicator, export/import dialogs |

---

*Internal use - General Atomics Aeronautical Systems, Inc.*
