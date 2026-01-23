# WSUS Manager v3.8.9 - Standard Operating Procedure

**Version:** 3.8.9
**Author:** Tony Tran, ISSO, GA-ASI
**Last Updated:** January 2026

---

## Table of Contents

1. [File Repository](#file-repository)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [GUI Application](#gui-application)
5. [Command Reference (CLI)](#command-reference-cli)
6. [Air-Gapped Network Workflow](#air-gapped-network-workflow)
7. [Domain Controller Setup](#domain-controller-setup)
8. [HTTPS Configuration (Optional)](#https-configuration-optional)
9. [Scheduled Tasks](#scheduled-tasks)
10. [Logging](#logging)
11. [Troubleshooting](#troubleshooting)
12. [References](#references)

---

## File Repository

### SQL & WSUS Installers

> **Note:** Save these files to `C:\WSUS\SQLDB\` on the target server before running installation.

| File | Description |
|------|-------------|
| SQLEXPRADV_x64_ENU.exe | SQL Server Express 2022 with Advanced Services |
| SSMS-Setup-ENU.exe | SQL Server Management Studio |

### Distribution Package

| File | Description |
|------|-------------|
| WsusManager-v3.8.9.zip | Complete distribution package |

**Package Contents:**

```
WsusManager.exe           # Main GUI application
Scripts/                  # Required - operation scripts
Modules/                  # Required - PowerShell modules (11 modules)
DomainController/         # Optional - GPO deployment scripts
QUICK-START.txt           # Quick reference guide
README.md                 # Full documentation
```

> **IMPORTANT:** The EXE requires Scripts/ and Modules/ folders in the same directory. Do not deploy the EXE alone.

### Source Code

| File | Description |
|------|-------------|
| GitHub Repository | https://github.com/anthonyscry/GA-WsusManager |

---

## Prerequisites

### System Requirements

| Requirement | Specification |
|-------------|---------------|
| Operating System | Windows Server 2016, 2019, or 2022 |
| CPU | 4 cores minimum |
| RAM | 16 GB minimum |
| Disk Space | 125 GB minimum (50 GB for WSUS content) |
| Network | Valid IPv4 configuration (static IP recommended) |
| PowerShell | 5.1 or higher |

### Required Installers

| File | Location |
|------|----------|
| SQLEXPRADV_x64_ENU.exe | C:\WSUS\SQLDB\ |
| SSMS-Setup-ENU.exe | C:\WSUS\SQLDB\ |

### Required Privileges

| Privilege | Scope | Purpose |
|-----------|-------|---------|
| Local Administrator | WSUS server | Script execution, service management |
| sysadmin role | localhost\SQLEXPRESS | SUSDB backup/restore operations |

### Granting SQL Server Sysadmin Privileges

> **Note:** Required for database backup/restore operations. Perform this on both online and air-gapped WSUS servers.

**Step 1: Connect to SQL Server**

| Step | Action |
|------|--------|
| 1 | Launch SQL Server Management Studio (SSMS) |
| 2 | Server type: Database Engine |
| 3 | Server name: `localhost\SQLEXPRESS` |
| 4 | Authentication: SQL Server Authentication |
| 5 | Login: sa (or default admin account) |
| 6 | Check "Trust Server Certificate" |
| 7 | Click Connect |

**Step 2: Add Login with Sysadmin Role**

| Step | Action |
|------|--------|
| 1 | In Object Explorer, expand Security → Logins |
| 2 | Right-click Logins → New Login... |
| 3 | Click Search... to locate the account |
| 4 | Click Locations... → select Entire Directory |
| 5 | Enter domain group (e.g., `DOMAIN\System Administrators`) → OK |
| 6 | Go to Server Roles page |
| 7 | Check sysadmin → OK |

**Step 3: Refresh Permissions**

| Step | Action |
|------|--------|
| 1 | Log out of the WSUS server |
| 2 | Log back in to refresh group membership |

---

## Installation

### First-Time Setup

> **Note:** If downloaded from the internet, unblock the files first.

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Path "C:\WSUS" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

### Installation Steps

| Step | Action |
|------|--------|
| 1 | Place SQL installers in `C:\WSUS\SQLDB\` |
| 2 | Extract `WsusManager-v3.8.9.zip` to `C:\WSUS\` |
| 3 | Verify folder structure (EXE + Scripts/ + Modules/) |
| 4 | Right-click `WsusManager.exe` → Run as Administrator |
| 5 | Click **Install WSUS** and follow prompts |

### Deployment Layout

| Path | Purpose |
|------|---------|
| C:\WSUS\ | Content directory (MUST be this exact path) |
| C:\WSUS\SQLDB\ | SQL + SSMS installers |
| C:\WSUS\Logs\ | Log files |
| C:\WSUS\WsusManager.exe | GUI application |
| C:\WSUS\Scripts\ | PowerShell scripts |
| C:\WSUS\Modules\ | PowerShell modules |
| %APPDATA%\WsusManager\ | User settings (settings.json) |

---

## GUI Application

### Overview

WSUS Manager v3.8.9 includes a full GUI application (`WsusManager.exe`) built with WPF. The GUI provides:

- **Dashboard** with auto-refresh (30-second interval)
- **Server Mode** toggle (Online vs Air-Gap)
- **Live Terminal Mode** for external PowerShell window output
- **Operation buttons** that disable during execution
- **Log panel** showing real-time operation output

### Launching the GUI

1. Right-click `WsusManager.exe` → **Run as Administrator**
2. If WSUS is not installed, only **Install WSUS** will be enabled
3. Dashboard auto-populates once WSUS is detected

### Dashboard Metrics

| Metric | Description |
|--------|-------------|
| Server Status | WSUS service state |
| Database Size | Current SUSDB size (alerts at 8GB+) |
| Last Sync | Most recent synchronization timestamp |
| Update Count | Total updates in database |
| Clients | Number of registered WSUS clients |

### GUI Operations

| Button | Function |
|--------|----------|
| **Install WSUS** | Install WSUS + SQL Server Express 2022 |
| **Health Check** | Read-only diagnostics |
| **Repair Health** | Auto-fix common issues |
| **Deep Cleanup** | Aggressive database cleanup |
| **Monthly Maintenance** | Profile-based maintenance (Light/Standard/Deep) |
| **Transfer** | Export/Import dialog for air-gap operations |
| **Restore Database** | Restore SUSDB from backup file |
| **Schedule Task** | Create scheduled maintenance task |
| **Create GPO** | Copy GPO files to C:\WSUS\WSUS GPO |
| **Settings** | Configure server mode, paths, preferences |

### Server Mode

| Mode | Description |
|------|-------------|
| **Online** | Full internet connectivity, direct sync with Microsoft Update |
| **Air-Gap** | No internet, uses Export/Import for update transfer |

Toggle via **Settings** dialog or mode indicator in GUI.

### Live Terminal Mode

Toggle in log panel header to open operations in an external PowerShell window:

- Console window sized to 100x20 characters
- Useful for long-running operations
- Settings persist to `settings.json`

---

## Command Reference (CLI)

### Interactive Menu

```powershell
.\Scripts\Invoke-WsusManagement.ps1
```

| Option | Description |
|--------|-------------|
| 1 | Install WSUS with SQL Express 2022 |
| 2 | Restore Database from C:\WSUS |
| 3 | Copy Data from External Media (import to air-gap server) |
| 4 | Copy Data to External Media (export for air-gap transfer) |
| 5 | Monthly Maintenance (Sync, Cleanup, Backup, Export) |
| 6 | Deep Cleanup (Aggressive DB cleanup) |
| 7 | Health Check |
| 8 | Health Check + Repair |
| 9 | Reset Content Download |
| 10 | Force Client Check-In |

### Command-Line Switches

| Command | Description |
|---------|-------------|
| `.\Invoke-WsusManagement.ps1 -Restore` | Restore newest .bak from C:\WSUS |
| `.\Invoke-WsusManagement.ps1 -Cleanup -Force` | Deep database cleanup |
| `.\Invoke-WsusManagement.ps1 -Health` | Read-only health check |
| `.\Invoke-WsusManagement.ps1 -Repair` | Health check + auto-repair |
| `.\Invoke-WsusManagement.ps1 -Reset` | Reset content download |

### Export/Import CLI Parameters

```powershell
# Export with full parameters
.\Invoke-WsusManagement.ps1 -Export -SourcePath "C:\WSUS" -DestinationPath "E:\WsusExport" -CopyMode "Full"

# Export differential (files from last N days)
.\Invoke-WsusManagement.ps1 -Export -SourcePath "C:\WSUS" -DestinationPath "E:\WsusExport" -CopyMode "Differential" -DaysOld 30

# Import
.\Invoke-WsusManagement.ps1 -Import -SourcePath "E:\WsusExport" -DestinationPath "C:\WSUS"
```

### Monthly Maintenance Options

| Command | Description |
|---------|-------------|
| `.\Invoke-WsusMonthlyMaintenance.ps1` | Interactive mode |
| `.\Invoke-WsusMonthlyMaintenance.ps1 -Unattended -ExportDays 30` | Unattended mode (scheduled tasks) |
| `.\Invoke-WsusMonthlyMaintenance.ps1 -MaintenanceProfile Light` | Decline superseded, basic cleanup (15-30 min) |
| `.\Invoke-WsusMonthlyMaintenance.ps1 -MaintenanceProfile Standard` | Light + index rebuild, statistics (1-2 hours) |
| `.\Invoke-WsusMonthlyMaintenance.ps1 -MaintenanceProfile Deep` | Standard + obsolete removal, full optimization (2-4 hours) |

### Maintenance Profile Comparison

| Profile | Duration | Actions |
|---------|----------|---------|
| **Light** | 15-30 min | Decline superseded updates, basic cleanup |
| **Standard** | 1-2 hours | Light + index rebuild, statistics update |
| **Deep** | 2-4 hours | Standard + obsolete update removal, full optimization |

**Recommended Schedule:**

- Light: Weekly
- Standard: Monthly
- Deep: Quarterly

---

## Air-Gapped Network Workflow

### Workflow Overview

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS Server | Run **Monthly Maintenance** - Syncs, cleans up, exports to network share |
| 2 | Online WSUS Server | Run **Transfer → Export** - Copy to USB/Apricorn |
| 3 | Physical Transfer | Transport USB/Apricorn drive to air-gapped network |
| 4 | Air-Gapped WSUS Server | Run **Transfer → Import** - Copy from external media |
| 5 | Air-Gapped WSUS Server | Run **Restore Database** |
| 6 | Domain Controller | Run `.\Set-WsusGroupPolicy.ps1` (one-time setup) |

### GUI Transfer Dialog

The Transfer dialog provides:

- **Direction selector**: Export or Import
- **Source folder browser**: Select source path
- **Destination folder browser**: Select destination path
- **Export mode** (Export only):
  - Full copy (all files)
  - Differential copy (files from last N days)
  - Custom days option

### Export Folder Structure

Monthly maintenance exports to two locations:

| Location | Contents | Purpose |
|----------|----------|---------|
| Root folder | SUSDB_YYYYMMDD.bak + WsusContent\ | Latest backup + full content mirror |
| YYYY\Mon\ subfolder | SUSDB_YYYYMMDD.bak + WsusContent\ | Archive by year/month with differential content |

**Example structure:**

```
\\server\WSUS-Exports\
├── SUSDB_20260119.bak           (latest backup)
├── WsusContent\                 (full mirror)
└── 2026\
    └── Jan\
        ├── SUSDB_20260119.bak   (archived)
        └── WsusContent\         (differential)
```

### Robocopy Commands

| Purpose | Command |
|---------|---------|
| Copy latest to USB | `robocopy "\\server\WSUS-Exports" "E:\" /E /MT:16 /R:2 /W:5` |
| Copy specific month | `robocopy "\\server\WSUS-Exports\2026\Jan" "E:\2026\Jan" /E /MT:16 /R:2 /W:5` |
| Import to air-gap server | `robocopy "E:\" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO` |

**Robocopy Flags:**

| Flag | Description |
|------|-------------|
| /E | Copy subdirectories including empty |
| /XO | Skip older files (safe import) |
| /MIR | Mirror - deletes extras (full sync only) |
| /MT:16 | 16 threads for faster transfers |
| /R:2 /W:5 | Retry 2 times, wait 5 seconds |

---

## Domain Controller Setup

> **Warning:** Run on Domain Controller, NOT on WSUS server!

### Prerequisites

- RSAT Group Policy Management tools installed
- Copy `DomainController/` folder to DC

### Usage

| Method | Command |
|--------|---------|
| Interactive | `.\Set-WsusGroupPolicy.ps1` |
| Non-interactive | `.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"` |

### GUI Method

1. On WSUS server, click **Create GPO** button
2. Files are copied to `C:\WSUS\WSUS GPO`
3. Copy folder to Domain Controller
4. Run `.\Set-WsusGroupPolicy.ps1`

### What the Script Does

| Step | Action |
|------|--------|
| 1 | Auto-detect the domain |
| 2 | Import all 3 GPOs from backup |
| 3 | Create required OUs if they don't exist |
| 4 | Link each GPO to appropriate OUs |
| 5 | Push policy update to all domain computers |

### Imported GPOs

#### 1. WSUS Update Policy

Configures Windows Update client behavior via registry settings.

| Setting | Value | Description |
|---------|-------|-------------|
| WUServer | http://\<YourServer\>:8530 | Intranet update service URL (auto-replaced) |
| WUStatusServer | http://\<YourServer\>:8530 | Intranet statistics server (auto-replaced) |
| UseWUServer | Enabled | Use intranet WSUS instead of Microsoft Update |
| DoNotConnectToWindowsUpdateInternetLocations | Enabled | Block direct internet updates (critical for air-gap) |
| AcceptTrustedPublisherCerts | Enabled | Accept signed updates from intranet |
| ElevateNonAdmins | Disabled | Only admins receive update notifications |
| SetDisablePauseUXAccess | Enabled | Remove "Pause updates" option from users |
| AUPowerManagement | Enabled | Wake system from sleep for scheduled updates |
| Configure Automatic Updates | 2 - Notify for download and auto install | Users notified before download |
| AlwaysAutoRebootAtScheduledTime | 15 minutes | Auto-restart warning time |
| ScheduledInstallDay | 0 - Every day | Check for updates daily |
| ScheduledInstallTime | 00:00 | Install time (midnight) |
| NoAUShutdownOption | Disabled | Show "Install Updates and Shut Down" option |

#### 2. WSUS Inbound Allow (Firewall)

| Setting | Value |
|---------|-------|
| Name | WSUS Inbound Allow |
| Direction | Inbound |
| Action | Allow |
| Protocol | TCP |
| Local Ports | 8530, 8531 |
| Profiles | Domain, Private |

#### 3. WSUS Outbound Allow (Firewall)

| Setting | Value |
|---------|-------|
| Name | WSUS Outbound Allow |
| Direction | Outbound |
| Action | Allow |
| Protocol | TCP |
| Remote Ports | 8530, 8531 |
| Profiles | Domain, Private |

### GPO Linking Guide

| GPO | Link To |
|-----|---------|
| WSUS Update Policy | All workstation/server OUs that should receive updates |
| WSUS Inbound Allow | WSUS server OU (allows clients to connect to it) |
| WSUS Outbound Allow | All client OUs (allows them to reach WSUS server) |

### Force Client Check-In

On client machines:

```powershell
gpupdate /force
wuauclt /detectnow /reportnow
```

Verify GPO application:

```powershell
gpresult /r | findstr WSUS
```

---

## HTTPS Configuration (Optional)

The `Scripts/Set-WsusHttps.ps1` script enables HTTPS (SSL/TLS) on your WSUS server.

### Usage

| Method | Command |
|--------|---------|
| Interactive (recommended) | `.\Scripts\Set-WsusHttps.ps1` |
| Specific certificate | `.\Scripts\Set-WsusHttps.ps1 -CertificateThumbprint "1234567890ABCDEF..."` |

### Certificate Options

| Option | Description |
|--------|-------------|
| 1 | Create self-signed certificate (valid 5 years) |
| 2 | Select existing certificate from Local Machine store |
| 3 | Cancel |

### What It Configures

| Step | Action |
|------|--------|
| 1 | IIS Binding - Binds certificate to port 8531 (HTTPS) |
| 2 | WSUS SSL - Runs `wsusutil configuressl` to enable client SSL |
| 3 | Trusted Root - Adds self-signed certs to local trusted root store |
| 4 | Export - Exports certificate to `C:\WSUS\WSUS-SSL-Certificate.cer` |

### After HTTPS Configuration

Update the GPO with the new HTTPS URL:

```powershell
# On Domain Controller
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "https://WSUS01:8531"
```

For self-signed certificates, deploy the exported `.cer` file to clients via:

- **GPO:** Computer Config → Policies → Windows Settings → Security Settings → Public Key Policies → Trusted Root CAs
- **Manual:** Import on each client

---

## Scheduled Tasks

### Create via GUI

1. Click **Schedule Task** button
2. Configure:
   - Task name
   - Maintenance profile (Light/Standard/Deep)
   - Schedule type (Daily/Weekly/Monthly)
   - Day of month (1-31 for monthly)
   - Execution time
3. Enter credentials:
   - Username (default: `.\dod_admin`)
   - Password (required for unattended execution)
4. Click **Create**

### Create via CLI

```powershell
# Create scheduled task for monthly maintenance
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\WSUS\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -MaintenanceProfile Standard -Unattended"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2:00AM

Register-ScheduledTask -TaskName "WSUS Monthly Maintenance" `
    -Action $action -Trigger $trigger `
    -User "DOMAIN\ServiceAccount" -Password "Password" `
    -RunLevel Highest
```

### Verify Scheduled Tasks

```powershell
Get-ScheduledTask -TaskName "WSUS*" | Format-Table TaskName, State, LastRunTime
```

---

## Logging

All operations are logged to a single daily log file.

**Location:** `C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log`

### Logging Features

| Feature | Description |
|---------|-------------|
| Single daily file | All sessions and operations append to the same file per day |
| Session markers | Each script run is clearly marked with timestamps |
| Menu selections | User choices are logged for audit trail |
| No overwrites | Logs accumulate throughout the day |
| GUI logging | Operations from GUI also logged to same location |

### Log Format Example

```
================================================================================
SESSION START: 2026-01-19 10:30:00
================================================================================

2026-01-19 10:30:01 - Menu selection: 4
2026-01-19 10:30:02 - [1/2] Copying database backup...
2026-01-19 10:30:03 - [OK] Database copied
```

### GUI Log Panel

- Expandable/collapsible panel at bottom of window
- Auto-expands when operations start
- Clear button to reset output
- Live Terminal toggle for external window

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Endless downloads | Content path must be `C:\WSUS` (NOT `C:\WSUS\wsuscontent`) |
| Dashboard shows "Not Installed" | WSUS service not detected; run Install WSUS |
| Buttons greyed out | Operation already running, or WSUS not installed |
| Clients not checking in | Verify GPOs are linked, run `gpupdate /force`, check firewall ports 8530/8531 |
| GroupPolicy module not found | Install RSAT: `Install-WindowsFeature GPMC` |
| GPO backup path not found | Ensure WSUS GPOs folder is with the script |
| Database restore fails | Verify sysadmin privileges on SQL Server (see Prerequisites) |
| Database size near 10GB | Run Deep Cleanup; SQL Express limit is 10GB |
| Sync failures | Check internet connectivity (online mode), run Health Check |
| Operations hang | Check if running in non-interactive mode; GUI passes `-NonInteractive` |
| Script not found error | Verify Scripts/ and Modules/ folders are with EXE |

### Diagnostic Commands

| Purpose | Command |
|---------|---------|
| Health check (read-only) | `.\Invoke-WsusManagement.ps1 -Health` |
| Health check with auto-repair | `.\Invoke-WsusManagement.ps1 -Repair` |
| Force client check-in (run on client) | `.\Scripts\Invoke-WsusClientCheckIn.ps1` |
| Check service status | `Get-Service WsusService, MSSQL$SQLEXPRESS, W3SVC` |
| Start all services | `Start-Service MSSQL$SQLEXPRESS, WsusService, W3SVC` |

### Important Notes

> **Critical:** Content path must be `C:\WSUS` - Using `C:\WSUS\wsuscontent` causes endless downloads

| Item | Note |
|------|------|
| Content path | Must be `C:\WSUS` exactly |
| SA password | Install script auto-deletes encrypted SA password file when complete |
| Restore | Auto-detects the newest .bak file in C:\WSUS |
| GPO script | Must run on Domain Controller - copy files to DC before running |
| EXE deployment | Requires Scripts/ and Modules/ folders in same directory |
| Settings location | `%APPDATA%\WsusManager\settings.json` |

---

## Repository Structure

| File/Folder | Description |
|-------------|-------------|
| WsusManager.exe | Main GUI application (compiled from WsusManagementGui.ps1) |
| Scripts/WsusManagementGui.ps1 | GUI source code |
| Scripts/Invoke-WsusManagement.ps1 | CLI entry point (interactive menu + switches) |
| Scripts/Install-WsusWithSqlExpress.ps1 | One-time installation |
| Scripts/Invoke-WsusMonthlyMaintenance.ps1 | Scheduled maintenance |
| Scripts/Invoke-WsusClientCheckIn.ps1 | Client-side check-in |
| Scripts/Set-WsusHttps.ps1 | Optional HTTPS configuration |
| DomainController/Set-WsusGroupPolicy.ps1 | GPO import script |
| DomainController/WSUS GPOs/ | Pre-configured GPO backups |
| Modules/*.psm1 | 11 shared PowerShell modules |

### PowerShell Modules

| Module | Purpose |
|--------|---------|
| WsusUtilities.psm1 | Logging, colors, helpers |
| WsusDatabase.psm1 | Database operations |
| WsusHealth.psm1 | Health checks and repair |
| WsusServices.psm1 | Service management |
| WsusFirewall.psm1 | Firewall rules |
| WsusPermissions.psm1 | Directory permissions |
| WsusConfig.psm1 | Configuration |
| WsusExport.psm1 | Export/import |
| WsusScheduledTask.psm1 | Scheduled tasks |
| WsusAutoDetection.psm1 | Server detection and auto-recovery |
| AsyncHelpers.psm1 | Async/background operation helpers for WPF |

---

## Features Summary

| Feature | Description |
|---------|-------------|
| GUI Application | WPF-based dark theme interface with dashboard |
| Automated Installation | One-click deployment of SQL Server Express 2022 + SSMS + WSUS |
| Air-Gap Support | Full and differential content export/import for offline networks |
| Database Management | Backup, restore, cleanup, and optimization |
| Health Monitoring | Automated diagnostics and repair capabilities |
| Scheduled Maintenance | GUI and CLI support for Windows Task Scheduler |
| GPO Deployment | Pre-configured Group Policy Objects for domain-wide client configuration |
| Live Terminal Mode | External PowerShell window for operation output |
| Server Mode Toggle | Online vs Air-Gap mode switching |
| Auto-Refresh Dashboard | 30-second interval status updates |
| DPI Awareness | Crisp rendering on high-DPI displays |
| Modular Architecture | 11 reusable PowerShell modules |

---

## References

### Microsoft Official Documentation

| Topic | Link |
|-------|------|
| WSUS Maintenance Guide | [Microsoft Learn - WSUS Maintenance](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/manage/wsus-maintenance) |
| WSUS Best Practices | [Microsoft Learn - WSUS Best Practices](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment) |
| WSUS Deployment Planning | [Microsoft Learn - Plan Your WSUS Deployment](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment) |
| WSUS Configuration | [Microsoft Learn - Configure WSUS](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus) |
| SQL Server Installation Guide | [Microsoft Learn - Install SQL Server](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server) |
| SQL Server Network Configuration | [Microsoft Learn - Server Network Configuration](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/server-network-configuration) |
| SQL Server 2022 Express Download | [Microsoft Download Center](https://www.microsoft.com/en-us/sql-server/sql-server-downloads) |

### Additional Resources

| Topic | Link |
|-------|------|
| SQL Server Configuration Manager | [Microsoft Learn - Configuration Manager](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-configuration-manager) |
| WSUS Database Maintenance | [Microsoft Learn - WSUS Automatic Maintenance](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/manage/wsus-maintenance) |
| Enable/Disable Network Protocols | [Microsoft Learn - Network Protocols](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/enable-or-disable-a-server-network-protocol) |

---

*Internal use - GA-ASI*
