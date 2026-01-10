# WSUS + SQL Server Express 2022 Automation Suite

**Author:** Tony Tran, ISSO, GA-ASI
**Version:** 3.0.0
**Last Updated:** 2026-01-09

A production-ready PowerShell automation suite for deploying, managing, and maintaining Windows Server Update Services (WSUS) backed by SQL Server Express 2022. Designed for both online and air-gapped (offline) network environments.

---

## Features

- **Automated Installation** - One-script deployment of SQL Server Express 2022 + SSMS + WSUS
- **Air-Gap Support** - Differential content export/import for offline networks
- **Database Management** - Backup, restore, cleanup, and optimization
- **Health Monitoring** - Automated diagnostics and repair capabilities
- **Scheduled Maintenance** - Unattended mode for Windows Task Scheduler
- **GPO Deployment** - Pre-configured Group Policy Objects for domain-wide client configuration
- **Modular Architecture** - 6 reusable PowerShell modules (~30% code reduction)

---

## Quick Start

### Prerequisites

- Windows Server 2016+ with Administrator access
- PowerShell 5.0+
- SQL Server Express 2022 installer (`SQLEXPRADV_x64_ENU.exe`)
- SQL Server Management Studio installer (`SSMS-Setup-ENU.exe`)

### First-Time Setup

If downloaded from the internet, unblock the scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Path "C:\WSUS\scripts" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

### Installation

1. Place installers in `C:\WSUS\SQLDB\`:
   ```
   C:\WSUS\SQLDB\SQLEXPRADV_x64_ENU.exe
   C:\WSUS\SQLDB\SSMS-Setup-ENU.exe
   ```

2. Run the interactive menu:
   ```powershell
   .\Invoke-WsusManagement.ps1
   ```

3. Select **Option 1** to install WSUS + SQL Express

---

## Repository Structure

```
wsus-sql/
├── Invoke-WsusManagement.ps1           # Main entry point (interactive menu + CLI)
├── Scripts/
│   ├── Install-WsusWithSqlExpress.ps1  # One-time installation
│   ├── Invoke-WsusMonthlyMaintenance.ps1  # Scheduled maintenance
│   └── Invoke-WsusClientCheckIn.ps1    # Client-side check-in
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
| 3 | Copy for Air-Gap Server (Full/Browse Archive) |
| 4 | Monthly Maintenance |
| 5 | Deep Cleanup |
| 6 | Export for Airgapped Transfer |
| 7 | Health Check |
| 8 | Health Check + Repair |
| 9 | Reset Content Download |
| 10 | Force Client Check-In |

### Command-Line Switches

```powershell
# Database Operations
.\Invoke-WsusManagement.ps1 -Restore              # Restore newest .bak from C:\WSUS
.\Invoke-WsusManagement.ps1 -Cleanup -Force       # Deep database cleanup

# Export Operations
.\Invoke-WsusManagement.ps1 -Export               # Export DB + differential content
.\Invoke-WsusManagement.ps1 -Export -SinceDays 7  # Export last 7 days only
.\Invoke-WsusManagement.ps1 -Export -SkipDatabase # Content only, skip DB

# Troubleshooting
.\Invoke-WsusManagement.ps1 -Health               # Read-only health check
.\Invoke-WsusManagement.ps1 -Repair               # Health check + auto-repair
.\Invoke-WsusManagement.ps1 -Reset                # Reset content download
```

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
│  .\Scripts\Invoke-WsusMonthlyMaintenance.ps1                    │
│  → Syncs, cleans up, exports to \\lab-hyperv\d\WSUS-Exports\    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  COPY TO USB/APRICORN                                           │
│  robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan\09" "E:\" /E    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  AIRGAPPED WSUS SERVER                                          │
│  Option 3: Copy for Air-Gap → Browse Archive or Full Copy       │
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

```
\\lab-hyperv\d\WSUS-Exports\
└── 2026/
    └── Jan/
        └── 09/
            ├── SUSDB_20260109.bak   # Full database backup
            └── WsusContent/         # Differential content (files modified within N days)
```

### Robocopy Commands

```powershell
# Copy export to USB
robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan\09" "E:\2026\Jan\09" /E /MT:16 /R:2 /W:5

# Import to airgapped server (safe - keeps existing files)
robocopy "E:\2026\Jan\09" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO
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
