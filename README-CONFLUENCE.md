# WSUS + SQL Server Express 2022 Automation Suite

| **Author** | Tony Tran, ISSO, GA-ASI |
|------------|-------------------------|
| **Version** | 3.2.0 |
| **Last Updated** | 2026-01-10 |

A production-ready PowerShell automation suite for deploying, managing, and maintaining Windows Server Update Services (WSUS) backed by SQL Server Express 2022. Designed for both online and air-gapped (offline) network environments.

---

## Table of Contents

1. [File Repository](#file-repository)
2. [Official Documentation](#official-documentation)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Command Reference](#command-reference)
6. [Air-Gapped Network Workflow](#air-gapped-network-workflow)
7. [Domain Controller Setup](#domain-controller-setup)
8. [HTTPS Configuration (Optional)](#optional-https-configuration)
9. [Logging](#logging)
10. [Troubleshooting](#troubleshooting)

---

## File Repository

### SQL & WSUS Installers

> **Note:** Save these files to `C:\WSUS\SQLDB\` on the target server before running installation.

| File | Description |
|------|-------------|
| `SQLEXPRADV_x64_ENU.exe` | SQL Server Express 2022 with Advanced Services |
| `SSMS-Setup-ENU.exe` | SQL Server Management Studio |

### Script Bundle

| File | Description |
|------|-------------|
| `WSUS_Script_Bundle.zip` | Extract to `C:\WSUS\Scripts\` |

### Source Code

| Resource | Link |
|----------|------|
| GitHub Repository (latest) | *[Insert GitHub URL]* |

---

## Official Documentation

### Microsoft References

| Topic | Link |
|-------|------|
| WSUS Maintenance Guide | [Microsoft Learn - WSUS Maintenance](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide) |
| WSUS Best Practices | [Microsoft Learn - WSUS Best Practices](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/windows-server-update-services-best-practices) |
| WSUS Deployment Planning | [Microsoft Learn - Plan Your WSUS Deployment](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment) |
| WSUS Configuration | [Microsoft Learn - Configure WSUS](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus) |
| SQL Server Installation Guide | [Microsoft Learn - Install SQL Server](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server) |
| SQL Server Network Configuration | [Microsoft Learn - Server Network Configuration](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/server-network-configuration) |
| SQL Server 2022 Express Download | [Microsoft Download Center](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |

### Additional Resources

| Topic | Link |
|-------|------|
| SQL Server Configuration Manager | [Microsoft Learn - Configuration Manager](https://learn.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-configuration-manager) |
| WSUS Database Maintenance | [Microsoft Learn - WSUS Automatic Maintenance](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-automatic-maintenance) |
| Enable/Disable Network Protocols | [Microsoft Learn - Network Protocols](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/enable-or-disable-a-server-network-protocol) |

---

## Prerequisites

### System Requirements

| Requirement | Specification |
|-------------|---------------|
| Operating System | Windows Server 2019+ (physical or VM) |
| CPU | 4 cores minimum |
| RAM | 16 GB minimum |
| Disk Space | 125 GB minimum |
| Network | Valid IPv4 configuration (static IP recommended) |
| PowerShell | 5.0+ |

### Required Installers

| File | Location |
|------|----------|
| `SQLEXPRADV_x64_ENU.exe` | `C:\WSUS\SQLDB\` |
| `SSMS-Setup-ENU.exe` | `C:\WSUS\SQLDB\` |

### Required Privileges

| Privilege | Scope | Purpose |
|-----------|-------|---------|
| Local Administrator | WSUS server (source & destination) | Script execution, service management |
| sysadmin role | `localhost\SQLEXPRESS` | SUSDB backup/restore operations |

---

## Granting SQL Server Sysadmin Privileges

> **Note:** Required for database backup/restore operations. Perform this on both online and air-gapped WSUS servers.

### Step 1: Connect to SQL Server

| Step | Action |
|------|--------|
| 1 | Launch **SQL Server Management Studio (SSMS)** |
| 2 | Server type: **Database Engine** |
| 3 | Server name: `localhost\SQLEXPRESS` |
| 4 | Authentication: **SQL Server Authentication** |
| 5 | Login: `sa` (or default admin account) |
| 6 | Check **Trust Server Certificate** |
| 7 | Click **Connect** |

### Step 2: Add Login with Sysadmin Role

| Step | Action |
|------|--------|
| 1 | In Object Explorer, expand **Security** → **Logins** |
| 2 | Right-click **Logins** → **New Login...** |
| 3 | Click **Search...** to locate the account |
| 4 | Click **Locations...** → select **Entire Directory** |
| 5 | Enter domain group (e.g., `DOMAIN\System Administrators`) → **OK** |
| 6 | Go to **Server Roles** page |
| 7 | Check **sysadmin** → **OK** |

### Step 3: Refresh Permissions

| Step | Action |
|------|--------|
| 1 | Log out of the WSUS server |
| 2 | Log back in to refresh group membership |

---

## Installation

### First-Time Setup

> **Note:** If downloaded from the internet, unblock the scripts first.

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Path "C:\WSUS\scripts" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

### Installation Steps

| Step | Action |
|------|--------|
| 1 | Place installers in `C:\WSUS\SQLDB\` |
| 2 | Extract script bundle to `C:\WSUS\Scripts\` |
| 3 | Run `.\Invoke-WsusManagement.ps1` |
| 4 | Select **Option 1** to install WSUS + SQL Express |

### Deployment Layout

| Path | Purpose |
|------|---------|
| `C:\WSUS\` | Content directory (MUST be this exact path) |
| `C:\WSUS\SQLDB\` | SQL + SSMS installers |
| `C:\WSUS\Logs\` | Log files |
| `C:\WSUS\Scripts\` | Script repository |

---

## Command Reference

### Interactive Menu (Recommended)

```powershell
.\Invoke-WsusManagement.ps1
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

> **Note:** For export operations, use the Monthly Maintenance script or the interactive menu (options 4-5).

### Monthly Maintenance Options

| Command | Description |
|---------|-------------|
| `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1` | Interactive mode |
| `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Unattended -ExportDays 30` | Unattended mode (scheduled tasks) |
| `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Profile Quick` | Sync + basic cleanup |
| `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Profile Full` | All operations |
| `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Profile SyncOnly` | Sync only |

---

## Air-Gapped Network Workflow

### Workflow Overview

| Step | Location | Action |
|------|----------|--------|
| 1 | **Online WSUS Server** | Run **Option 5: Monthly Maintenance** - Syncs, cleans up, exports to network share |
| 2 | **Online WSUS Server** | Run **Option 4: Copy Data to External Media** - Copy to USB/Apricorn |
| 3 | **Physical Transfer** | Transport USB/Apricorn drive to air-gapped network |
| 4 | **Air-Gapped WSUS Server** | Run **Option 3: Copy Data from External Media** |
| 5 | **Air-Gapped WSUS Server** | Run **Option 2: Restore Database** |
| 6 | **Domain Controller** | Run `.\Set-WsusGroupPolicy.ps1` (one-time setup) |

### Export Folder Structure

Monthly maintenance exports to two locations:

| Location | Contents | Purpose |
|----------|----------|---------|
| Root folder | `SUSDB_YYYYMMDD.bak` + `WsusContent\` | Latest backup + full content mirror |
| `YYYY\Mon\` subfolder | `SUSDB_YYYYMMDD.bak` + `WsusContent\` | Archive by year/month with differential content |

**Example structure:**
```
\\server\WSUS-Exports\
├── SUSDB_20260109.bak           (latest backup)
├── WsusContent\                 (full mirror)
└── 2026\
    └── Jan\
        ├── SUSDB_20260109.bak   (archived)
        └── WsusContent\         (differential)
```

### Robocopy Commands

| Purpose | Command |
|---------|---------|
| Copy latest to USB | `robocopy "\\server\WSUS-Exports" "E:\" /E /MT:16 /R:2 /W:5` |
| Copy specific month | `robocopy "\\server\WSUS-Exports\2026\Jan" "E:\2026\Jan" /E /MT:16 /R:2 /W:5` |
| Import to air-gap server | `robocopy "E:\" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO` |

**Robocopy Flags:**

| Flag | Purpose |
|------|---------|
| `/E` | Copy subdirectories including empty |
| `/XO` | Skip older files (safe import) |
| `/MIR` | Mirror - deletes extras (full sync only) |
| `/MT:16` | 16 threads for faster transfers |
| `/R:2 /W:5` | Retry 2 times, wait 5 seconds |

---

## Domain Controller Setup

> **Warning:** Run on Domain Controller, NOT on WSUS server!

### Prerequisites

- RSAT Group Policy Management tools installed
- Copy `DomainController/` folder to DC

### Usage

| Mode | Command |
|------|---------|
| Interactive | `.\Set-WsusGroupPolicy.ps1` |
| Non-interactive | `.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"` |

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
| WUServer | `http://<YourServer>:8530` | Intranet update service URL (auto-replaced) |
| WUStatusServer | `http://<YourServer>:8530` | Intranet statistics server (auto-replaced) |
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

| Property | Value |
|----------|-------|
| Name | WSUS Inbound Allow |
| Direction | Inbound |
| Action | Allow |
| Protocol | TCP |
| Local Ports | 8530, 8531 |
| Profiles | Domain, Private |

#### 3. WSUS Outbound Allow (Firewall)

| Property | Value |
|----------|-------|
| Name | WSUS Outbound Allow |
| Direction | Outbound |
| Action | Allow |
| Protocol | TCP |
| Remote Ports | 8530, 8531 |
| Profiles | Domain, Private |

#### GPO Linking Guide

| GPO | Link To |
|-----|---------|
| WSUS Update Policy | All workstation/server OUs that should receive updates |
| WSUS Inbound Allow | WSUS server OU (allows clients to connect to it) |
| WSUS Outbound Allow | All client OUs (allows them to reach WSUS server) |

---

## Optional: HTTPS Configuration

The `Scripts/Set-WsusHttps.ps1` script enables HTTPS (SSL/TLS) on your WSUS server.

### Usage

| Mode | Command |
|------|---------|
| Interactive (recommended) | `.\Scripts\Set-WsusHttps.ps1` |
| Specific certificate | `.\Scripts\Set-WsusHttps.ps1 -CertificateThumbprint "1234567890ABCDEF..."` |

### Certificate Options

| Option | Description |
|--------|-------------|
| 1 | Create self-signed certificate (valid 5 years) |
| 2 | Select existing certificate from Local Machine store |
| 3 | Cancel |

### What It Configures

| Step | Configuration |
|------|---------------|
| 1 | **IIS Binding** - Binds certificate to port 8531 (HTTPS) |
| 2 | **WSUS SSL** - Runs `wsusutil configuressl` to enable client SSL |
| 3 | **Trusted Root** - Adds self-signed certs to local trusted root store |
| 4 | **Export** - Exports certificate to `C:\WSUS\WSUS-SSL-Certificate.cer` |

### After HTTPS Configuration

Update the GPO with the new HTTPS URL:

```powershell
# On Domain Controller
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "https://WSUS01:8531"
```

For self-signed certificates, deploy the exported `.cer` file to clients via:
- **GPO:** Computer Config > Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Root CAs
- **Manual:** Import on each client

---

## Logging

All operations are logged to a single daily log file:

**Location:** `C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log`

### Logging Features

| Feature | Description |
|---------|-------------|
| Single daily file | All sessions and operations append to the same file per day |
| Session markers | Each script run is clearly marked with timestamps |
| Menu selections | User choices are logged for audit trail |
| No overwrites | Logs accumulate throughout the day |

### Log Format Example

```
================================================================================
SESSION START: 2026-01-10 10:30:00
================================================================================

2026-01-10 10:30:01 - Menu selection: 4
2026-01-10 10:30:02 - [1/2] Copying database backup...
2026-01-10 10:30:03 - [OK] Database copied
```

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| Endless downloads | Content path must be `C:\WSUS` (NOT `C:\WSUS\wsuscontent`) |
| Clients not checking in | Verify GPOs are linked, run `gpupdate /force`, check firewall ports 8530/8531 |
| GroupPolicy module not found | Install RSAT: `Install-WindowsFeature GPMC` |
| GPO backup path not found | Ensure `WSUS GPOs` folder is with the script |
| Database restore fails | Verify sysadmin privileges on SQL Server (see Prerequisites) |

### Diagnostic Commands

| Purpose | Command |
|---------|---------|
| Health check (read-only) | `.\Invoke-WsusManagement.ps1 -Health` |
| Health check with auto-repair | `.\Invoke-WsusManagement.ps1 -Repair` |
| Force client check-in (run on client) | `.\Scripts\Invoke-WsusClientCheckIn.ps1` |

---

## Important Notes

> **Critical:** Content path must be `C:\WSUS` - Using `C:\WSUS\wsuscontent` causes endless downloads

| Note | Details |
|------|---------|
| Content path | Must be `C:\WSUS` exactly |
| SA password | Install script auto-deletes encrypted SA password file when complete |
| Restore | Auto-detects the newest `.bak` file in `C:\WSUS` |
| GPO script | Must run on Domain Controller - copy files to DC before running |

---

## Repository Structure

| Path | Description |
|------|-------------|
| `Invoke-WsusManagement.ps1` | Main entry point (interactive menu + CLI) |
| `Scripts/Install-WsusWithSqlExpress.ps1` | One-time installation |
| `Scripts/Invoke-WsusMonthlyMaintenance.ps1` | Scheduled maintenance |
| `Scripts/Invoke-WsusClientCheckIn.ps1` | Client-side check-in |
| `Scripts/Set-WsusHttps.ps1` | Optional HTTPS configuration |
| `DomainController/Set-WsusGroupPolicy.ps1` | GPO import script |
| `DomainController/WSUS GPOs/` | Pre-configured GPO backups |
| `Modules/*.psm1` | Shared PowerShell modules |

---

## Features

| Feature | Description |
|---------|-------------|
| Automated Installation | One-script deployment of SQL Server Express 2022 + SSMS + WSUS |
| Air-Gap Support | Differential content export/import for offline networks |
| Database Management | Backup, restore, cleanup, and optimization |
| Health Monitoring | Automated diagnostics and repair capabilities |
| Scheduled Maintenance | Unattended mode for Windows Task Scheduler |
| GPO Deployment | Pre-configured Group Policy Objects for domain-wide client configuration |
| Modular Architecture | 6 reusable PowerShell modules |

---

*Internal use - GA-ASI*
