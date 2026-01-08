# WSUS + SQL Express (2022) Automation

This repository contains a set of PowerShell scripts to deploy a **WSUS server backed by SQL Server Express 2022**, validate content paths/permissions, and run ongoing maintenance.

## Quick start (recommended flow)

1. **Copy the repo to the target server** and place installers in `C:\WSUS\SQLDB`:
   - `C:\WSUS\SQLDB\SQLEXPRADV_x64_ENU.exe` (SQL Express 2022 Advanced)
   - `C:\WSUS\SQLDB\SSMS-Setup-ENU.exe` (SSMS)

2. **Run the install script** (installs SQL + WSUS):
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Run-WsusSql.ps1
   ```

3. **Verify content path and permissions** (fixes any issues found):
   ```powershell
   .\Check-WSUSContent.ps1 -FixIssues
   ```
   > `-FixIssues` is for the validator script only. Use `-RunContentValidation -FixContentIssues` (or `-FixIssues` alias) with `Run-WsusSql.ps1` if you want validation after install.

4. **Online WSUS only:** configure products/classifications in the WSUS console, then synchronize. (Airgapped/offline WSUS imports the database and content from the online server.)

## Domain controller (GPO) setup

**IMPORTANT: Run this script on a Domain Controller, NOT on the WSUS server.**

Copy `Set-WsusGroupPolicy.ps1` and the `WSUS GPOs` folder to your domain controller, then run the script with **RSAT Group Policy Management** installed.

The script automatically imports **all three WSUS GPOs** from the `WSUS GPOs` folder:
- **WSUS Update Policy** - Client update configuration with WSUS server URLs
- **WSUS Inbound Allow** - Firewall rules for inbound WSUS traffic
- **WSUS Outbound Allow** - Firewall rules for outbound WSUS traffic

### Basic usage (prompts for WSUS server name):
```powershell
# Run on Domain Controller
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGroupPolicy.ps1
```

### Specify WSUS server URL:
```powershell
# Run on Domain Controller
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUSServerName:8530"
```

### Link GPOs to an OU:
```powershell
# Run on Domain Controller
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGroupPolicy.ps1 `
  -WsusServerUrl "http://WSUSServerName:8530" `
  -TargetOU "OU=Workstations,DC=example,DC=local"
```

The script automatically:
- Finds all three GPO backups in the `WSUS GPOs` directory
- Creates or updates each GPO from the backup
- Replaces hardcoded server names with your new WSUS server URL
- Optionally links all GPOs to your target OU

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

## Suggested folder layout

### On the WSUS server:
```text
C:\WSUS\SQLDB\               # SQL + SSMS installers + logs
C:\WSUS\                    # WSUS content (must be this path)
C:\WSUS\Scripts\            # WSUS server scripts (Install, Maintenance, Cleanup, etc.)
C:\WSUS\Logs\               # Log output
```

### On the Domain Controller:
```text
<Any location>\              # Copy Set-WsusGroupPolicy.ps1 here
<Any location>\WSUS GPOs\    # Copy WSUS GPOs folder here (required for script)
```

## Online WSUS export location
The **online WSUS server (Server LSJ)** exports the database and content to:

```text
D:\WSUS-Exports
```

Copy from this location when moving updates to **airgapped WSUS servers**.

## Example usage

### Install WSUS + SQL Express
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Run-WsusSql.ps1
```

### Validate + fix content configuration
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Check-WSUSContent.ps1 -FixIssues
```

### Troubleshooter (services + content)
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Run-WsusTroubleshooter.ps1 -FixContentIssues
```

### Restore a SUSDB backup
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\ImportScript.ps1
```

### Monthly maintenance
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\WsusMaintenance.ps1
```

Skip the heavy cleanup stage if needed:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\WsusMaintenance.ps1 -SkipUltimateCleanup
```

### Force a client check-in
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Force-WSUSCheckIn.ps1
```

### Reset WSUS content files
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Reset-WsusContent.ps1
```

### Ultimate WSUS cleanup
Run the comprehensive cleanup interactively (prompts for confirmation):

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Ultimate-WsusCleanup.ps1
```

Run non-interactively with `-Force` (useful for scheduled tasks):

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Ultimate-WsusCleanup.ps1 -Force
```

Specify a custom log file location:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Ultimate-WsusCleanup.ps1 -Force -LogFile "D:\Logs\Cleanup.log"
```

### Create or import WSUS GPOs (on Domain Controller)
```powershell
# Copy Set-WsusGroupPolicy.ps1 and WSUS GPOs folder to your Domain Controller first
# Run this on the Domain Controller, NOT on the WSUS server
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUSServerName:8530"
```

Link to an OU:
```powershell
# Run on Domain Controller
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGroupPolicy.ps1 `
  -WsusServerUrl "http://WSUSServerName:8530" `
  -TargetOU "OU=Workstations,DC=example,DC=local"
```

## Robocopy examples (moving exports to airgapped WSUS servers)
Examples below mirror `Robocopy_example.txt` and show common transfer paths for the WSUS export data.

```powershell
robocopy "D:\WSUS-Exports" "<Apricorn Path>" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE

robocopy "\\10.120.129.172\d\WSUS-Exports" "<Apricorn Path>" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE

robocopy "\\10.120.129.172\d\WSUS-Exports" "\\10.120.129.116\WSUS" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE

robocopy "\\sandbox-hyperv\v\WSUS" "C:\WSUS" /MIR /MT:16 /R:2 /W:5 /LOG:"C:\Logs\Export_%DATE%_%TIME%.log" /TEE
```

## Notes and known behaviors
- **Content path must be `C:\WSUS`.** `C:\WSUS\wsuscontent` is known to cause endless downloads and an unregistered file state in SUSDB.
- The **install script deletes its temporary encrypted SA password file** when it finishes.
- `ImportScript.ps1` scans `C:\WSUS` for the newest `.bak` file and prompts before restoring it.
