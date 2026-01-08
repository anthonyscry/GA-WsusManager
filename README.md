# WSUS + SQL Express (2022) Automation

This repository contains a set of PowerShell scripts to deploy a **WSUS server backed by SQL Server Express 2022**, validate content paths/permissions, and run ongoing maintenance.

## Repository Structure

```
/
├── Invoke-WsusManagement.ps1    # Interactive launcher (recommended entry point)
├── Scripts/                      # All WSUS server scripts
│   ├── Install-WsusWithSqlExpress.ps1
│   ├── Invoke-WsusMonthlyMaintenance.ps1
│   ├── Invoke-WsusDeepCleanup.ps1
│   ├── Restore-WsusDatabase.ps1
│   ├── Test-WsusHealth.ps1
│   ├── Reset-WsusContentDownload.ps1
│   └── Invoke-WsusClientCheckIn.ps1
├── DomainController/             # GPO configuration (run on Domain Controller)
│   ├── Set-WsusGroupPolicy.ps1
│   └── WSUS GPOs/
├── Modules/                      # Shared PowerShell modules
└── README.md
```

## Quick start (recommended flow)

### Prerequisites
**Set PowerShell execution policy** (one-time setup):
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
This allows locally created scripts to run without being digitally signed.

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

## What the scripts do (by category)
All script names below match the PowerShell files in the repo root and are grouped by their primary use.
Each entry includes **what it does**, **why you would use it**, and **where to run it** to make the list easier to scan.

---

### <span style="color:#1f77b4;">Install / setup</span>

#### `Run-WsusSql.ps1` (install flow)
- **What it does:** Runs the install script for WSUS + SQL Express (validation is optional).
- **Why use it:** Recommended install flow; run validation separately or opt into validation when needed.
- **Where to run it:** On the **WSUS server** you are provisioning.

```powershell
# Default: install only
.\Run-WsusSql.ps1

# Skip install (validation only)
.\Run-WsusSql.ps1 -SkipInstall -RunContentValidation

# Run content validation after install
.\Run-WsusSql.ps1 -RunContentValidation

# Run content validation and auto-fix issues
.\Run-WsusSql.ps1 -RunContentValidation -FixContentIssues
.\Run-WsusSql.ps1 -RunContentValidation -FixIssues  # Alias for FixContentIssues
```

#### `install.ps1`
- **What it does:** Full **SQL Express 2022 + SSMS + WSUS** installation and configuration, including:
  - SQL Express setup (silent)
  - SSMS install
  - SQL networking + firewall rules
  - WSUS role install + post-install configuration
  - IIS virtual directory fix + permissions
  - Registry settings to bypass the initial WSUS wizard
- **Why use it:** Automates a complete WSUS + SQL Express build without manual steps.
- **Where to run it:** On the **WSUS server** hosting WSUS + SQL Express.

#### `Set-WsusGroupPolicy.ps1`
- **What it does:** Imports and configures all three WSUS GPO backups (Update Policy, Inbound Allow, Outbound Allow) and updates hardcoded WSUS server URLs to match your environment.
- **Why use it:** Centralizes WSUS client settings, update policies, and firewall rules via Group Policy in a single operation.
- **Where to run it:** On a **Domain Controller** with **RSAT Group Policy Management** installed.
- **Key features:**
  - Automatically finds GPO backups in `WSUS GPOs` folder
  - Updates hardcoded server names (e.g., `LSJ-WSUS2`) with your new WSUS server URL
  - Creates or updates all three GPOs in one run
  - Optionally links GPOs to target OUs

---

### <span style="color:#2ca02c;">Import</span>

#### `ImportScript.ps1`
- **What it does:** Restores a SUSDB backup and re-attaches WSUS to it (auto-detects the newest `.bak` in `C:\WSUS` and prompts before use).
- **Why use it:** Rehydrates WSUS from a known-good database backup (e.g., for offline/airgapped servers).
- **Where to run it:** On the **WSUS server** that will host the restored database.

---

### <span style="color:#ff7f0e;">Maintenance / utility</span>

#### `WsusMaintenance.ps1`
- **What it does:** Monthly maintenance automation (run on the **online** WSUS server):
  - Syncs and updates the upstream WSUS server
  - Monitors downloads
  - Declines old superseded updates
  - Runs cleanup tasks
  - Backs up the database and content for later import
  - Optionally runs ultimate cleanup before the backup (use `-SkipUltimateCleanup` to skip)
- **Why use it:** Keeps WSUS healthy and produces backups for downstream/offline use.
- **Where to run it:** On the **online/upstream WSUS server**.

#### `Ultimate-WsusCleanup.ps1`
- **What it does:** Quarterly or emergency cleanup:
  - Deletes supersession records
  - Removes declined updates
  - Rebuilds indexes and updates stats
  - Shrinks SUSDB
  - Logs all operations to file
- **Why use it:** Deep cleanup when WSUS performance/storage needs attention.
- **Where to run it:** On the **WSUS server** (typically the online/upstream instance).
- **Parameters:**
  - `-Force` or `-SkipConfirmation`: Skip confirmation prompt for automation
  - `-LogFile <path>`: Custom log file location (default: `C:\WSUS\Logs\UltimateCleanup_<timestamp>.log`)

#### `Reset-WsusContent.ps1`
- **What it does:** Runs `wsusutil.exe reset` to force a full re-validation of all WSUS content.
- **Why use it:** Fixes or validates content issues and forces a full re-check of downloads.
- **Where to run it:** On the **WSUS server** that hosts the content store.

#### `Force-WSUSCheckIn.ps1`
- **What it does:** Forces a WSUS client to check in (optionally clears Windows Update cache).
- **Why use it:** Troubleshoot client reporting or trigger immediate status updates.
- **Where to run it:** On the **WSUS client machine**.

---

### <span style="color:#d62728;">Troubleshooting / validation</span>

#### `Run-WsusTroubleshooter.ps1`
- **What it does:** Runs service-level auto-fixes (SQL/WSUS/IIS) and then validates WSUS content path configuration.
- **Why use it:** One-stop health check for common WSUS service issues and content path correctness.
- **Where to run it:** On the **WSUS server**.

#### `Check-WSUSContent.ps1`
- **What it does:** Validates that WSUS is correctly using **`C:\WSUS`** and can optionally fix:
  - SUSDB content path
  - Registry content path
  - IIS virtual directory content path
  - Permissions (NETWORK SERVICE, LOCAL SERVICE, IIS_IUSRS, WsusPool)
  - File state records and download queue
- **Why use it:** Diagnose and repair common WSUS content path and permission issues.
- **Where to run it:** On the **WSUS server** hosting the content store.

#### `autofix.ps1`
- **What it does:** Detects and fixes common WSUS + SQL service issues (SQL, WSUS, IIS).
- **Why use it:** Quickly resolve common service-level problems without manual triage.
- **Where to run it:** On the **WSUS server**.

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
The **online WSUS server (Server LSJ)** exports the database and content to:

```text
D:\WSUS-Exports
```

Copy from this location when moving updates to **airgapped WSUS servers**.

## Example usage

### Interactive Menu (Recommended)
```powershell
cd C:\WSUS\wsus-sql
.\Invoke-WsusManagement.ps1
```

### Direct Script Execution

#### Install WSUS + SQL Express
```powershell
.\Scripts\Install-WsusWithSqlExpress.ps1
```

#### Restore a SUSDB backup
```powershell
.\Scripts\Restore-WsusDatabase.ps1
```

#### Monthly maintenance
```powershell
.\Scripts\Invoke-WsusMonthlyMaintenance.ps1
```

#### Deep cleanup
```powershell
.\Scripts\Invoke-WsusDeepCleanup.ps1
```

#### Test WSUS health
```powershell
.\Scripts\Test-WsusHealth.ps1
```

#### Reset content download
```powershell
.\Scripts\Reset-WsusContentDownload.ps1
```

#### Force client check-in (run on client)
```powershell
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
Examples below mirror `Robocopy_example.txt` and show common transfer paths for the WSUS export data.

```powershell
robocopy "D:\WSUS-Exports" "<Apricorn Path>" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE

robocopy "\\10.120.129.172\d\WSUS-Exports" "<Apricorn Path>" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE

robocopy "\\10.120.129.172\d\WSUS-Exports" "\\10.120.129.116\WSUS" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE

robocopy "\\sandbox-hyperv\v\WSUS" "C:\WSUS" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE
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
- Run `.\Scripts\Test-WsusHealth.ps1` to diagnose and repair

**Clients not checking in**
- Verify GPOs are linked to correct OUs
- Run `gpupdate /force` on client
- Check client: `wuauclt /detectnow /reportnow`
- Verify firewall rules allow WSUS traffic (ports 8530/8531)

## Notes and known behaviors
- **Content path must be `C:\WSUS`.** `C:\WSUS\wsuscontent` is known to cause endless downloads and an unregistered file state in SUSDB.
- The **install script deletes its temporary encrypted SA password file** when it finishes.
- `ImportScript.ps1` scans `C:\WSUS` for the newest `.bak` file and prompts before restoring it.
- **Set-WsusGroupPolicy.ps1 runs on Domain Controller**, not on WSUS server. Copy the script and GPO backups to your DC before running.
