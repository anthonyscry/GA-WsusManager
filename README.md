# WSUS + SQL Server Express 2022 Automation Suite

**Author:** Tony Tran, ISSO, GA-ASI
**Version:** 3.2.0
**Last Updated:** 2026-01-10

A production-ready PowerShell automation suite for deploying, managing, and maintaining Windows Server Update Services (WSUS) backed by SQL Server Express 2022. Designed for both online and air-gapped (offline) network environments.

---

## Official Documentation

### Microsoft References

- [WSUS Maintenance Guide](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide)
- [WSUS Best Practices](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/windows-server-update-services-best-practices)
- [Plan Your WSUS Deployment](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment)
- [Configure WSUS](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/2-configure-wsus)
- [SQL Server Installation Guide](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server)
- [SQL Server Network Configuration](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/server-network-configuration)
- [SQL Server 2022 Express Download](https://www.microsoft.com/en-us/download/details.aspx?id=104781)

---

## Features

- **Automated Installation** - One-script deployment of SQL Server Express 2022 + SSMS + WSUS
- **Air-Gap Support** - Differential content export/import for offline networks
- **Database Management** - Backup, restore, cleanup, and optimization
- **Health Monitoring** - Automated diagnostics and repair capabilities
- **Scheduled Maintenance** - Unattended mode for Windows Task Scheduler
- **GPO Deployment** - Pre-configured Group Policy Objects for domain-wide client configuration
- **Modular Architecture** - 6 reusable PowerShell modules

---

## Quick Start

### Prerequisites

#### System Requirements

- **Operating System:** Windows Server 2019+ (physical or VM)
- **CPU:** 4 cores minimum
- **RAM:** 16 GB minimum
- **Disk Space:** 125 GB minimum
- **Network:** Valid IPv4 configuration (static IP recommended)
- **PowerShell:** 5.0+

#### Required Installers

Place these in `C:\WSUS\SQLDB\`:
- `SQLEXPRADV_x64_ENU.exe` - SQL Server Express 2022 with Advanced Services
- `SSMS-Setup-ENU.exe` - SQL Server Management Studio

#### Required Privileges

- **Local Administrator** on WSUS server (source & destination)
- **sysadmin role** on `localhost\SQLEXPRESS` (required for SUSDB backup/restore)

### Granting SQL Server Sysadmin Privileges

> Required for database backup/restore operations. Perform on both online and air-gapped WSUS servers.

**Step 1: Connect to SQL Server**
1. Launch **SQL Server Management Studio (SSMS)**
2. Server type: **Database Engine**
3. Server name: `localhost\SQLEXPRESS`
4. Authentication: **SQL Server Authentication**
5. Login: `sa` (or default admin account)
6. Check **Trust Server Certificate** → Click **Connect**

**Step 2: Add Login with Sysadmin Role**
1. In Object Explorer, expand **Security** → **Logins**
2. Right-click **Logins** → **New Login...**
3. Click **Search...** → Click **Locations...** → Select **Entire Directory**
4. Enter domain group (e.g., `DOMAIN\System Administrators`) → **OK**
5. Go to **Server Roles** page → Check **sysadmin** → **OK**

**Step 3: Refresh Permissions**
- Log out of the WSUS server and log back in to refresh group membership

### First-Time Setup

If downloaded from the internet, unblock the scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Path "C:\WSUS\scripts" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

### Installation

1. Place installers in `C:\WSUS\SQLDB\`
2. Extract script bundle to `C:\WSUS\Scripts\`
3. Run the interactive menu:
   ```powershell
   .\Invoke-WsusManagement.ps1
   ```
4. Select **Option 1** to install WSUS + SQL Express

---

## Repository Structure

```
wsus-sql/
├── Invoke-WsusManagement.ps1           # Main entry point (interactive menu + CLI)
├── Scripts/
│   ├── Install-WsusWithSqlExpress.ps1  # One-time installation
│   ├── Invoke-WsusMonthlyMaintenance.ps1  # Scheduled maintenance
│   ├── Invoke-WsusClientCheckIn.ps1    # Client-side check-in
│   └── Set-WsusHttps.ps1               # Optional HTTPS configuration
├── DomainController/
│   ├── Set-WsusGroupPolicy.ps1         # GPO import script
│   └── WSUS GPOs/                      # Pre-configured GPO backups
├── Modules/                            # Shared PowerShell modules
│   ├── WsusUtilities.psm1              # Common utilities
│   ├── WsusDatabase.psm1               # Database operations
│   ├── WsusServices.psm1               # Service management
│   ├── WsusHealth.psm1                 # Health checking
│   ├── WsusPermissions.psm1            # Permission management
│   └── WsusFirewall.psm1               # Firewall rules
└── README.md
```

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

```powershell
# Database Operations
.\Invoke-WsusManagement.ps1 -Restore              # Restore newest .bak from C:\WSUS
.\Invoke-WsusManagement.ps1 -Cleanup -Force       # Deep database cleanup

# Troubleshooting
.\Invoke-WsusManagement.ps1 -Health               # Read-only health check
.\Invoke-WsusManagement.ps1 -Repair               # Health check + auto-repair
.\Invoke-WsusManagement.ps1 -Reset                # Reset content download
```

> **Note:** For export operations, use the Monthly Maintenance script or the interactive menu (options 4-5).

### Monthly Maintenance

```powershell
# Interactive mode
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1

# Unattended mode (for scheduled tasks)
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Unattended -ExportDays 30

# Profiles
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Profile Quick      # Sync + basic cleanup
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Profile Full       # All operations
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Profile SyncOnly   # Sync only

# Specific operations
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -Operations Sync,Backup
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -SkipExport -GenerateReport
```

---

## Air-Gapped Network Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  ONLINE WSUS SERVER                                             │
│  Option 5: Monthly Maintenance                                  │
│  → Syncs, cleans up, exports to \\lab-hyperv\d\WSUS-Exports\    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  COPY TO USB/APRICORN                                           │
│  Option 4: Copy Data to External Media                          │
│  → Or: robocopy "\\lab-hyperv\d\WSUS-Exports" "E:\" /E          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  AIRGAPPED WSUS SERVER                                          │
│  Option 3: Copy Data from External Media                        │
│  Option 2: Restore Database                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  DOMAIN CONTROLLER (one-time setup)                             │
│  .\DomainController\Set-WsusGroupPolicy.ps1                     │
│  → Imports GPOs, links to OUs, pushes policy to all clients     │
└─────────────────────────────────────────────────────────────────┘
```

### Export Folder Structure

Monthly maintenance exports to two locations:

```
\\lab-hyperv\d\WSUS-Exports\
├── SUSDB_20260109.bak              # Latest backup at root (for quick access)
├── WsusContent/                    # Full content mirror at root
└── 2026/                           # Archive by year/month
    └── Jan/
        ├── SUSDB_20260109.bak      # Archived backup
        ├── SUSDB_20260109_2.bak    # Multiple backups same day get numbered
        └── WsusContent/            # Differential content (files from last N days)
```

- **Root folder**: Always contains the latest backup + full content (mirror sync)
- **Archive folders**: Year/Month structure for historical backups + differential content

### Robocopy Commands

```powershell
# Copy latest export to USB (from root - includes full backup + content)
robocopy "\\lab-hyperv\d\WSUS-Exports" "E:\" /E /MT:16 /R:2 /W:5

# Or copy specific month from archive
robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan" "E:\2026\Jan" /E /MT:16 /R:2 /W:5

# Import to airgapped server (safe - keeps existing files)
robocopy "E:\" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO
```

| Flag | Purpose |
|------|---------|
| `/E` | Copy subdirectories including empty |
| `/XO` | Skip older files (safe import) |
| `/MIR` | Mirror - deletes extras (full sync only) |
| `/MT:16` | 16 threads for faster transfers |
| `/R:2 /W:5` | Retry 2 times, wait 5 seconds |

---

## Domain Controller Setup

**Run on Domain Controller, NOT on WSUS server!**

### Prerequisites
- RSAT Group Policy Management tools
- Copy `DomainController/` folder to DC

### Usage

```powershell
# Interactive (prompts for WSUS server name)
.\Set-WsusGroupPolicy.ps1

# Non-interactive (specify WSUS server URL)
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

The script will:
1. Auto-detect the domain
2. Import all 3 GPOs from backup
3. Create required OUs if they don't exist
4. Link each GPO to appropriate OUs
5. Push policy update to all domain computers

### Imported GPOs

The script imports three pre-configured GPOs. The WSUS server URL is automatically updated to match your environment.

#### 1. WSUS Update Policy

Configures Windows Update client behavior via registry settings under:
- `HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate`
- `HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU`

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

#### 2. WSUS Inbound Allow

Creates Windows Defender Firewall inbound rule:

| Property | Value |
|----------|-------|
| Name | WSUS Inbound Allow |
| Direction | Inbound |
| Action | Allow |
| Protocol | TCP |
| Local Ports | 8530, 8531 |
| Profiles | Domain, Private |
| Description | Allows inbound WSUS connections over TCP 8530 (HTTP) and 8531 (HTTPS) |

#### 3. WSUS Outbound Allow

Creates Windows Defender Firewall outbound rule:

| Property | Value |
|----------|-------|
| Name | WSUS Outbound Allow |
| Direction | Outbound |
| Action | Allow |
| Protocol | TCP |
| Remote Ports | 8530, 8531 |
| Profiles | Domain, Private |
| Description | Allows outbound WSUS connections over TCP 8530 (HTTP) and 8531 (HTTPS) |

#### GPO Linking

After import, link the GPOs to appropriate OUs:
- **WSUS Update Policy** → Link to all workstation/server OUs that should receive updates
- **WSUS Inbound Allow** → Link to WSUS server OU (allows clients to connect to it)
- **WSUS Outbound Allow** → Link to all client OUs (allows them to reach WSUS server)

---

## Optional: HTTPS Configuration

The `Scripts/Set-WsusHttps.ps1` script enables HTTPS (SSL/TLS) on your WSUS server. This is optional but recommended for production environments.

### Usage

```powershell
# Interactive mode (recommended)
.\Scripts\Set-WsusHttps.ps1

# Use specific certificate by thumbprint
.\Scripts\Set-WsusHttps.ps1 -CertificateThumbprint "1234567890ABCDEF..."
```

### Certificate Options

The interactive menu offers:

| Option | Description |
|--------|-------------|
| 1 | Create self-signed certificate (valid 5 years) |
| 2 | Select existing certificate from Local Machine store |
| 3 | Cancel |

### What It Configures

1. **IIS Binding** - Binds certificate to port 8531 (HTTPS)
2. **WSUS SSL** - Runs `wsusutil configuressl` to enable client SSL
3. **Trusted Root** - Adds self-signed certs to local trusted root store
4. **Export** - Exports certificate to `C:\WSUS\WSUS-SSL-Certificate.cer` for distribution

### After HTTPS Configuration

Update the GPO with the new HTTPS URL:

```powershell
# On Domain Controller
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "https://WSUS01:8531"
```

For self-signed certificates, deploy the exported `.cer` file to clients via:
- GPO: Computer Config > Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Root CAs
- Or manually import on each client

---

## Deployment Layout

### WSUS Server
```
C:\WSUS\                    # Content directory (MUST be this path)
C:\WSUS\SQLDB\              # SQL + SSMS installers
C:\WSUS\Logs\               # Log files
C:\WSUS\scripts\            # This repository
```

### Domain Controller
```
<Any location>\DomainController\
├── Set-WsusGroupPolicy.ps1
└── WSUS GPOs\
```

---

## Logging

All operations are logged to a single daily log file:

```
C:\WSUS\Logs\WsusManagement_2026-01-10.log
```

### Features

- **Single daily file** - All sessions and operations append to the same file per day
- **Session markers** - Each script run is clearly marked with timestamps
- **Menu selections** - User choices are logged for audit trail
- **No overwrites** - Logs accumulate throughout the day

### Log Format

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

### Diagnostic Commands

```powershell
# Health check (read-only)
.\Invoke-WsusManagement.ps1 -Health

# Health check with auto-repair
.\Invoke-WsusManagement.ps1 -Repair

# Force client check-in (run on client)
.\Scripts\Invoke-WsusClientCheckIn.ps1
```

---

## Important Notes

- **Content path must be `C:\WSUS`** - Using `C:\WSUS\wsuscontent` causes endless downloads
- **Install script auto-deletes encrypted SA password file** when complete
- **Restore command auto-detects** the newest `.bak` file in `C:\WSUS`
- **GPO script runs on Domain Controller** - Copy files to DC before running

---

## License

Internal use - GA-ASI
