# WSUS + SQL Express (2022) Automation

This repository contains a set of PowerShell scripts to deploy a **WSUS server backed by SQL Server Express 2022**, validate content paths/permissions, and run ongoing maintenance.

> **Important content path rule**
> - **Content folder must be `C:\WSUS`.**
> - If you set `CONTENT_DIR` to `C:\WSUS\wsuscontent`, WSUS will stay in a **constant download state** because the database does not register files correctly.

## Quick start (recommended flow)

1. **Copy the repo to the target server** and place installers in `C:\SQLDB`:
   - `C:\SQLDB\SQLEXPRADV_x64_ENU.exe` (SQL Express 2022 Advanced)
   - `C:\SQLDB\SSMS-Setup-ENU.exe` (SSMS)

2. **Run the combined setup script** (installs SQL + WSUS, then validates content):
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Run-WsusSql.ps1
   ```

3. **Verify content path and permissions** (fixes any issues found):
   ```powershell
   .\Check-WSUSContent.ps1 -FixIssues
   ```

4. **Configure products/classifications** in the WSUS console, then synchronize.

## Domain controller (GPO) setup

To push WSUS settings to clients via Group Policy, run the new GPO script on a domain controller with **RSAT Group Policy Management** installed:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGpo.ps1 -WsusServerUrl "http://WSUSServerName:8530"
```

Optional: import a backed up GPO (if present) and link to an OU:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Set-WsusGpo.ps1 `
  -WsusServerUrl "http://WSUSServerName:8530" `
  -BackupPath "C:\WSUS\Scripts\GpoBackups" `
  -TargetOU "OU=Workstations,DC=example,DC=local"
```

## What the scripts do

### `Run-WsusSql.ps1` (new, combined flow)
Runs the install script and then validates the WSUS content path/permissions.

```powershell
# Default: install + validate
.\Run-WsusSql.ps1

# Skip install (only validate)
.\Run-WsusSql.ps1 -SkipInstall

# Skip content validation
.\Run-WsusSql.ps1 -SkipContentValidation

# Auto-fix any content path issues
.\Run-WsusSql.ps1 -FixContentIssues
```

### `install.ps1`
Full **SQL Express 2022 + SSMS + WSUS** installation and configuration, including:
- SQL Express setup (silent)
- SSMS install
- SQL networking + firewall rules
- WSUS role install + post-install configuration
- IIS virtual directory fix + permissions
- Registry settings to bypass the initial WSUS wizard

### `Check-WSUSContent.ps1`
Validates that WSUS is correctly using **`C:\WSUS`** and can optionally fix:
- SUSDB content path
- Registry content path
- IIS virtual directory content path
- Permissions (NETWORK SERVICE, LOCAL SERVICE, IIS_IUSRS, WsusPool)
- File state records and download queue

### `ImportScript.ps1`
Restores a SUSDB backup and re-attaches WSUS to it.

> **Note:** the backup path is currently hard-coded:
> `C:\WSUS\SUSDB_20251124.bak`

### `WsusMaintenance.ps1`
Monthly maintenance automation:
- Syncs WSUS
- Monitors downloads
- Declines old superseded updates
- Runs cleanup tasks
- Optionally runs ultimate cleanup before the backup (use `-SkipUltimateCleanup` to skip)

### `Ultimate-WsusCleanup.ps1`
Quarterly or emergency cleanup:
- Deletes supersession records
- Removes declined updates
- Rebuilds indexes and updates stats
- Shrinks SUSDB

### `Force-WSUSCheckIn.ps1`
Forces a WSUS client to check in (optionally clears Windows Update cache).

### `Set-WsusGpo.ps1`
Creates or imports a WSUS client GPO and applies the required Windows Update policy keys.

### `autofix.ps1`
Detects and fixes common WSUS + SQL service issues (SQL, WSUS, IIS).

### `Reset-WsusContent.ps1`
Runs `wsusutil.exe reset` to force a full re-validation of all WSUS content.

## Suggested folder layout on the WSUS server
```
C:\SQLDB\                   # SQL + SSMS installers + logs
C:\WSUS\                    # WSUS content (must be this path)
C:\WSUS\Scripts\            # Put these scripts here for consistency
C:\WSUS\Logs\               # Log output
```

## Example usage

### Install WSUS + SQL Express
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Run-WsusSql.ps1
```

### Validate + fix content configuration
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Check-WSUSContent.ps1 -FixIssues
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

### Create or import WSUS GPOs
```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\WSUS\Scripts\Set-WsusGpo.ps1 -WsusServerUrl "http://WSUSServerName:8530"
```

## Notes and known behaviors
- **Content path must be `C:\WSUS`.** `C:\WSUS\wsuscontent` is known to cause endless downloads and an unregistered file state in SUSDB.
- The **install script removes its temporary SA password file** for security.
- `ImportScript.ps1` uses a **fixed backup path** today; update it if your backup name changes.

## Consolidation suggestions
If you want fewer entry points, here are safe merge/rename ideas:
- Keep `Run-WsusSql.ps1`, `install.ps1`, and `Check-WSUSContent.ps1` as the main deployment flow.
- `PS commands.txt` and `Robocopy_example.txt` are reference snippets; move them into scripts if you want everything executable.

## References
- The Confluence snapshot in this repo is included for context, but some steps and scripts may be outdated.
