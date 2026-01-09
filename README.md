# WSUS + SQL Express (2022) Automation

This repository contains a set of PowerShell scripts to deploy a **WSUS server backed by SQL Server Express 2022**, validate content paths/permissions, and run ongoing maintenance.

## First-Time Setup

If you downloaded these scripts from the internet, run these commands once before using:

```powershell
# Set execution policy (allows running local scripts)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Unblock downloaded files (removes internet zone identifier)
Get-ChildItem -Path "C:\WSUS\Scripts" -Recurse -Include *.ps1,*.psm1 | Unblock-File
```

## Repository Structure

```
/
├── Invoke-WsusManagement.ps1     # Main script with switches (recommended entry point)
├── Scripts/
│   ├── Install-WsusWithSqlExpress.ps1     # One-time WSUS + SQL installation
│   ├── Invoke-WsusMonthlyMaintenance.ps1  # Scheduled maintenance
│   └── Invoke-WsusClientCheckIn.ps1       # Client-side check-in (run on clients)
├── DomainController/             # GPO configuration (run on Domain Controller)
│   ├── Set-WsusGroupPolicy.ps1
│   └── WSUS GPOs/
├── Modules/                      # Shared PowerShell modules
└── README.md
```

## Command Reference

All operations are available via `Invoke-WsusManagement.ps1`:

```
.\Invoke-WsusManagement.ps1              # Interactive menu (recommended)

INSTALLATION
  .\Scripts\Install-WsusWithSqlExpress.ps1

DATABASE
  -Restore                               # Restore newest .bak from C:\WSUS
  Menu option 3: Copy Exports            # Copy from lab server to local (differential)

MAINTENANCE
  .\Scripts\Invoke-WsusMonthlyMaintenance.ps1
    -ExportPath <path>                   # Export destination (default: \\lab-hyperv\d\WSUS-Exports)
    -ExportDays <n>                      # Days for differential export (default: prompts, 30)
    -SkipExport                          # Skip export step entirely
    -SkipUltimateCleanup                 # Skip heavy cleanup before backup
  -Cleanup -Force                        # Deep database cleanup (menu only)

EXPORT/TRANSFER
  -Export                                # Export DB + content for airgapped transfer
    -ExportRoot <path>                   # Export destination (default: \\lab-hyperv\d\WSUS-Exports)
    -SinceDays <n>                       # Copy content from last N days (default: 30)
    -SkipDatabase                        # Skip database, export only content

TROUBLESHOOTING
  -Health                                # Run health check (read-only)
  -Repair                                # Run health check + auto-repair
  -Reset                                 # Reset content download

CLIENT
  .\Scripts\Invoke-WsusClientCheckIn.ps1 # Run on client machines
```

## Quick start (recommended flow)

### Option 1: Interactive Menu (Easiest)
1. **Copy repo to target server** and place installers in `C:\WSUS\SQLDB`:
   - `C:\WSUS\SQLDB\SQLEXPRADV_x64_ENU.exe` (SQL Express 2022 Advanced)
   - `C:\WSUS\SQLDB\SSMS-Setup-ENU.exe` (SSMS)

2. **Launch the interactive menu:**
   ```powershell
   .\Invoke-WsusManagement.ps1
   ```
   - Select option **1** to install WSUS + SQL Express
   - Use menu for all other operations (maintenance, troubleshooting, etc.)

### Option 2: Direct Script Execution
1. **Install WSUS + SQL Express:**
   ```powershell
   .\Scripts\Install-WsusWithSqlExpress.ps1
   ```

2. **Online WSUS only:** configure products/classifications in the WSUS console, then synchronize. (Airgapped/offline WSUS imports the database and content from the online server.)

## Domain controller (GPO) setup

**⚠️ IMPORTANT: Run this on your Domain Controller, NOT on the WSUS server!**

### Prerequisites
- Domain Controller with Administrator access
- RSAT Group Policy Management tools installed
- Copy the `DomainController/` folder to your DC:
  - `DomainController/Set-WsusGroupPolicy.ps1` (the script)
  - `DomainController/WSUS GPOs/` (GPO backups)

### What it does
Automatically imports **three WSUS GPOs**:
1. **WSUS Update Policy** - Configures Windows Update client settings
2. **WSUS Inbound Allow** - Firewall rules for inbound traffic
3. **WSUS Outbound Allow** - Firewall rules for outbound traffic

The script automatically replaces hardcoded WSUS server URLs in the backups with your environment's server.

### Quick setup

**Option 1: Interactive mode** (prompts for WSUS server name)
```powershell
.\Set-WsusGroupPolicy.ps1
```

**Option 2: Specify WSUS server**
```powershell
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

**Option 3: Link to specific OU**
```powershell
.\Set-WsusGroupPolicy.ps1 `
  -WsusServerUrl "http://WSUS01:8530" `
  -TargetOU "OU=Workstations,DC=example,DC=local"
```

### Workflow
1. Copy script + GPO backups to Domain Controller
2. Run script (specify WSUS server URL or it will prompt)
3. Script imports all three GPOs and updates WSUS URLs
4. (Optional) Script links GPOs to specified OU
5. Clients apply policies on next gpupdate

## What the scripts do

### Main Script: `Invoke-WsusManagement.ps1`

The main script handles all WSUS operations via switches or interactive menu.

| Switch | Description |
|--------|-------------|
| (none) | Interactive menu |
| `-Export` | Export DB + differential content for airgapped transfer |
| `-Restore` | Restore newest .bak from C:\WSUS |
| `-Health` | Run health check (read-only) |
| `-Repair` | Run health check with auto-repair |
| `-Cleanup -Force` | Deep database cleanup |
| `-Reset` | Reset content download |

**Export Parameters:**
- `-ExportRoot <path>`: Export destination (default: `\\lab-hyperv\d\WSUS-Exports`)
- `-SinceDays <n>`: Copy content from last N days (default: 30)
- `-SkipDatabase`: Skip database, export only content

**Interactive Menu Options:**
| Option | Description |
|--------|-------------|
| 1 | Install WSUS with SQL Express 2022 |
| 2 | Restore Database from C:\WSUS (finds newest .bak) |
| 3 | Copy Exports from Lab Server (differential copy to local) |
| 4 | Monthly Maintenance (Sync, Cleanup, Backup, Export) |
| 5 | Deep Cleanup (Aggressive DB cleanup) |
| 6 | Export for Airgapped Transfer |
| 7 | Health Check |
| 8 | Health Check + Repair |
| 9 | Reset Content Download |
| 10 | Force Client Check-In (run on client) |

```powershell
# Interactive menu
.\Invoke-WsusManagement.ps1

# Export to network share
.\Invoke-WsusManagement.ps1 -Export

# Export last 7 days only
.\Invoke-WsusManagement.ps1 -Export -SinceDays 7

# Restore database (finds newest .bak in C:\WSUS)
.\Invoke-WsusManagement.ps1 -Restore

# Health check with repair
.\Invoke-WsusManagement.ps1 -Repair

# Deep cleanup (automated)
.\Invoke-WsusManagement.ps1 -Cleanup -Force
```

---

### Separate Scripts

#### `Scripts/Install-WsusWithSqlExpress.ps1`
- **What it does:** Full **SQL Express 2022 + SSMS + WSUS** installation
- **Where to run it:** On the **WSUS server** you are provisioning
- **Requirements:** Place installers in `C:\WSUS\SQLDB`

```powershell
.\Scripts\Install-WsusWithSqlExpress.ps1
```

#### `Scripts/Invoke-WsusMonthlyMaintenance.ps1`
- **What it does:** Monthly maintenance (sync, decline, cleanup, backup, export)
- **Where to run it:** On the **online/upstream WSUS server**
- **New:** Includes differential export with year/month/day folder structure

**Parameters:**
- `-ExportPath <path>`: Export destination (default: `\\lab-hyperv\d\WSUS-Exports`)
- `-ExportDays <n>`: Days for differential export (default: prompts user, 30)
- `-SkipExport`: Skip the export step entirely
- `-SkipUltimateCleanup`: Skip heavy cleanup before backup

```powershell
# Run with default export (prompts for days)
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1

# Run with 14-day differential export
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -ExportDays 14

# Skip export entirely
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -SkipExport
```

#### `Scripts/Invoke-WsusClientCheckIn.ps1`
- **What it does:** Force Windows Update client to check in with WSUS
- **Where to run it:** On **client machines** (not the WSUS server)

```powershell
.\Scripts\Invoke-WsusClientCheckIn.ps1
```

#### `DomainController/Set-WsusGroupPolicy.ps1`
- **What it does:** Import and configure WSUS GPOs
- **Where to run it:** On a **Domain Controller**

```powershell
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

---

### Operations Summary

| Operation | Command |
|-----------|---------|
| Install WSUS | `.\Scripts\Install-WsusWithSqlExpress.ps1` |
| Restore Database | `.\Invoke-WsusManagement.ps1 -Restore` |
| Copy Exports from Lab | Menu option 3 (interactive only) |
| Monthly Maintenance | `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1` |
| Monthly Maintenance + Export | `.\Scripts\Invoke-WsusMonthlyMaintenance.ps1 -ExportDays 30` |
| Export for Airgapped | `.\Invoke-WsusManagement.ps1 -Export` |
| Health Check | `.\Invoke-WsusManagement.ps1 -Health` |
| Health + Repair | `.\Invoke-WsusManagement.ps1 -Repair` |
| Deep Cleanup | `.\Invoke-WsusManagement.ps1 -Cleanup -Force` |
| Reset Content | `.\Invoke-WsusManagement.ps1 -Reset` |
| Client Check-In | `.\Scripts\Invoke-WsusClientCheckIn.ps1` |
| Configure GPOs | `.\DomainController\Set-WsusGroupPolicy.ps1` |

## Suggested deployment layout

### On the WSUS server:
```text
C:\WSUS\SQLDB\               # SQL + SSMS installers + logs
C:\WSUS\                    # WSUS content (must be this path)
C:\WSUS\Logs\               # Log output
C:\WSUS\wsus-sql\           # This repository
    ├── Invoke-WsusManagement.ps1  # Run this for interactive menu
    ├── Scripts\                    # All server scripts
    ├── DomainController\          # Copy this folder to DC
    └── Modules\
```

### On the Domain Controller:
```text
<Any location>\DomainController\
    ├── Set-WsusGroupPolicy.ps1
    └── WSUS GPOs\
```

## Online WSUS export location
The **online WSUS server** exports the database and content to:

```text
\\lab-hyperv\d\WSUS-Exports
```

Copy from this location when moving updates to **airgapped WSUS servers**.

## Example usage

### Interactive Menu (Recommended)
```powershell
cd C:\WSUS\wsus-sql
.\Invoke-WsusManagement.ps1
```

### Direct Commands
```powershell
# Install WSUS + SQL Express
.\Scripts\Install-WsusWithSqlExpress.ps1

# Monthly maintenance
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1

# Export for airgapped transfer
.\Invoke-WsusManagement.ps1 -Export

# Restore database
.\Invoke-WsusManagement.ps1 -Restore

# Health check + repair
.\Invoke-WsusManagement.ps1 -Repair

# Deep cleanup
.\Invoke-WsusManagement.ps1 -Cleanup -Force

# Reset content
.\Invoke-WsusManagement.ps1 -Reset

# Force client check-in (run on client)
.\Scripts\Invoke-WsusClientCheckIn.ps1
```

### Configure WSUS GPOs (on Domain Controller)
```powershell
# Copy DomainController folder to DC first
cd <DomainController folder location>

# Interactive mode - prompts for WSUS server name
.\Set-WsusGroupPolicy.ps1

# Or specify server and link to OU
.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530" -TargetOU "OU=Workstations,DC=example,DC=local"
```

## Robocopy examples (moving exports to airgapped WSUS servers)

### Export folder structure

```
\\lab-hyperv\d\WSUS-Exports\
├── 2026\
│   ├── Jan\
│   │   ├── 9\                 # Export from day 9
│   │   │   ├── SUSDB.bak      # Full database
│   │   │   └── WsusContent\   # Only new/changed files
│   │   └── 15\                # Export from day 15
│   │       ├── SUSDB.bak
│   │       └── WsusContent\
│   └── Feb\
│       └── 5\
│           ├── SUSDB.bak
│           └── WsusContent\
```

### Airgapped WSUS workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ONLINE WSUS SERVER                                │
│                                                                             │
│  1. Monthly Maintenance     ──►  Sync, cleanup, backup, AND export         │
│     .\Scripts\Invoke-WsusMonthlyMaintenance.ps1                             │
│                                                                             │
│     - Prompts for export days (default: 30)                                 │
│     - Creates: \\lab-hyperv\d\WSUS-Exports\2026\Jan\09\                     │
│       ├── SUSDB_20260109.bak                                                │
│       └── WsusContent\ (files modified within N days)                       │
│                                                                             │
│  (Alternative: Manual export if needed)                                     │
│     .\Invoke-WsusManagement.ps1 -Export                                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     ANY MACHINE (with network access)                       │
│                                                                             │
│  2. Copy to USB/Apricorn                                                    │
│     robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan\09" "E:\2026\Jan\09" /E  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                              [ USB / Apricorn ]
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AIRGAPPED WSUS SERVER                              │
│                                                                             │
│  3. Option A: Copy Exports via Menu (RECOMMENDED)                           │
│     .\Invoke-WsusManagement.ps1  →  Select option 3                         │
│     - Auto-finds newest export on lab server                                │
│     - Differential copy to C:\WSUS                                          │
│                                                                             │
│  3. Option B: Manual robocopy                                               │
│     robocopy "E:\2026\Jan\09" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO             │
│                                                                             │
│  4. Restore database                                                        │
│     .\Invoke-WsusManagement.ps1  →  Select option 2                         │
│     (or: .\Invoke-WsusManagement.ps1 -Restore)                              │
│                                                                             │
│     - Finds newest .bak in C:\WSUS                                          │
│     - Shows available backups with dates                                    │
│     - Restores DB, runs postinstall                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Step 1: Monthly maintenance with export** *(Run on: ONLINE WSUS server)*
```powershell
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1
# Prompts: "Export files modified within how many days? (default: 30)"
```
Downloads updates, backs up database, exports to `\\lab-hyperv\d\WSUS-Exports\2026\Jan\09\`.

**Step 2: Copy to USB/Apricorn** *(Run on: any machine with network access)*
```powershell
robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan\09" "E:\2026\Jan\09" /E /MT:16 /R:2 /W:5
```
Copies export folder to removable drive.

**Step 3: Copy exports to airgapped server** *(Run on: AIRGAPPED WSUS server)*

Option A - Via menu (recommended):
```powershell
.\Invoke-WsusManagement.ps1
# Select option 3: Copy Exports from Lab Server
# Auto-finds newest export, differential copies to C:\WSUS
```

Option B - Manual robocopy:
```powershell
robocopy "E:\2026\Jan\09" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import.log" /TEE
```

**Step 4: Restore database** *(Run on: AIRGAPPED WSUS server)*
```powershell
.\Invoke-WsusManagement.ps1 -Restore
# Or use menu option 2
```
Finds newest `.bak` in `C:\WSUS`, shows available backups, restores DB, runs postinstall.

### Key robocopy flags

| Flag | Meaning | When to use |
|------|---------|-------------|
| `/E` | Copy subdirectories (including empty) | Always |
| `/XO` | Exclude older files | **Safe import** - skip files if destination is newer |
| `/MIR` | Mirror (delete extras at destination) | **Full sync only** - deletes files not in source! |
| `/MT:16` | Multi-threaded (16 threads) | Always - faster transfers |
| `/R:2 /W:5` | Retry 2 times, wait 5 seconds | Always - handles transient errors |

### Common transfer examples

```powershell
# [Any machine with network access] Copy export to USB/Apricorn
robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan\9" "E:\2026\Jan\9" /E /MT:16 /R:2 /W:5 /LOG:"C:\WSUS\Logs\ToUSB.log" /TEE

# [AIRGAPPED server] Import from USB INTO C:\WSUS (SAFE - keeps existing files)
robocopy "E:\2026\Jan\9" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import.log" /TEE

# [AIRGAPPED server] Import directly from network share (if accessible)
robocopy "\\lab-hyperv\d\WSUS-Exports\2026\Jan\9" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import.log" /TEE
```

## Troubleshooting

### GPO script issues

**"Required module 'GroupPolicy' not found"**
- Install RSAT Group Policy Management tools on your Domain Controller
- Windows Server: `Install-WindowsFeature GPMC`
- Windows Client: Install RSAT from Optional Features

**"GPO backup path not found"**
- Ensure `WSUS GPOs` folder is in the same directory as the script
- Use `-BackupPath` parameter to specify custom location

**"No GPO backups found"**
- Verify the `WSUS GPOs` folder contains the three GPO backup subdirectories
- Each backup folder should have a `bkupInfo.xml` file

### WSUS content issues

**Endless downloads / content not appearing**
- Verify content path is `C:\WSUS` (NOT `C:\WSUS\wsuscontent`)
- Run `.\Invoke-WsusManagement.ps1 -Repair` to diagnose and fix

**Clients not checking in**
- Verify GPOs are linked to correct OUs
- Run `gpupdate /force` on client
- Check client: `wuauclt /detectnow /reportnow`
- Verify firewall rules allow WSUS traffic (ports 8530/8531)

## Notes and known behaviors
- **Content path must be `C:\WSUS`.** `C:\WSUS\wsuscontent` is known to cause endless downloads and an unregistered file state in SUSDB.
- The **install script deletes its temporary encrypted SA password file** when it finishes.
- The **restore command** (`.\Invoke-WsusManagement.ps1 -Restore`) auto-detects the newest `.bak` file in `C:\WSUS`.
- **Set-WsusGroupPolicy.ps1 runs on Domain Controller**, not on WSUS server. Copy the script and GPO backups to your DC before running.
