# Troubleshooting

This guide helps you diagnose and resolve common issues with WSUS Manager and WSUS servers.

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Service Issues](#service-issues)
3. [Database Issues](#database-issues)
4. [Client Issues](#client-issues)
5. [GUI Issues](#gui-issues)
6. [Performance Issues](#performance-issues)
7. [Robocopy / Transfer Issues](#robocopy--transfer-issues)
8. [Error Reference](#error-reference)

---

## Quick Diagnostics

### Run Diagnostics

Always start with Diagnostics:

1. Launch `WsusManager.exe`
2. Click **Diagnostics** (in the DIAGNOSTICS section)
3. Review the output

Diagnostics verifies:
- Service status
- Database connectivity
- Firewall rules
- Directory permissions
- SSL configuration

### Common Status Indicators

| Dashboard | Status | Meaning | Action |
|-----------|--------|---------|--------|
| Services | Red | Critical services stopped | Click "Start Services" |
| Database | Red | > 9 GB or offline | Run Deep Cleanup |
| Disk | Red | < 10 GB free | Free disk space |
| Automation | Orange | No scheduled task | Click **Schedule Task** |

---

## Service Issues

### Services Won't Start

**Symptoms:**
- Dashboard shows services as stopped
- "Start Services" button fails
- Manual service start fails

**Solutions:**

1. **Check dependencies**
   ```powershell
   # SQL must start before WSUS
   Start-Service MSSQL`$SQLEXPRESS
   Start-Sleep -Seconds 10
   Start-Service W3SVC
   Start-Sleep -Seconds 5
   Start-Service WSUSService
   ```

2. **Check Event Logs**
   ```powershell
   Get-EventLog -LogName Application -Newest 20 |
       Where-Object { $_.Source -match "WSUS|SQL|IIS" }
   ```

3. **Repair service registration**
   ```powershell
   # Re-register WSUS
   & "C:\Program Files\Update Services\Tools\wsusutil.exe" reset
   ```

### SQL Server Won't Start

**Symptoms:**
- MSSQL$SQLEXPRESS service fails
- Error 17058 or 17207

**Solutions:**

1. **Check disk space**
   - SQL needs space for tempdb
   - Ensure > 5 GB free on data drive

2. **Check file permissions**
   ```powershell
   # SQL service account needs access
   icacls "C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA"
   ```

3. **Check for corrupted files**
   ```powershell
   # Start in minimal mode
   net start MSSQL`$SQLEXPRESS /f /m
   ```

### WSUS Service Crashes

**Symptoms:**
- WSUSService starts then stops
- Application pool stops in IIS

**Solutions:**

1. **Reset WSUS**
   ```powershell
   & "C:\Program Files\Update Services\Tools\wsusutil.exe" reset
   ```

2. **Check IIS application pool**
   ```powershell
   Import-Module WebAdministration
   Get-WebAppPoolState -Name WsusPool
   Start-WebAppPool -Name WsusPool
   ```

3. **Increase memory limit**
   - Open IIS Manager
   - Application Pools > WsusPool > Advanced Settings
   - Private Memory Limit: Set to 0 (unlimited)

---

## Database Issues

### Database Offline

**Symptoms:**
- Dashboard shows "Offline"
- Can't query database size
- WSUS console errors

**Solutions:**

1. **Start SQL Service**
   ```powershell
   Start-Service MSSQL`$SQLEXPRESS
   ```

2. **Check database status**
   ```sql
   -- Run in SSMS or via sqlcmd -S localhost\SQLEXPRESS -E -Q "..."
   SELECT name, state_desc FROM sys.databases WHERE name = 'SUSDB'
   ```

3. **Bring database online**
   ```sql
   ALTER DATABASE SUSDB SET ONLINE
   ```

### Database Too Large (> 9 GB)

**Symptoms:**
- Dashboard shows red database indicator
- SQL Express 10 GB limit approaching
- Sync or cleanup fails

**Solutions:**

1. **Run Deep Cleanup**
   - Click **Deep Cleanup** in WSUS Manager
   - Wait for completion

2. **Manual cleanup**
   ```powershell
   # Decline superseded updates
   Get-WsusUpdate -Approval AnyExceptDeclined |
       Where-Object { $_.Update.IsSuperseded } |
       Deny-WsusUpdate
   ```

3. **Shrink database**
   ```sql
   USE SUSDB
   DBCC SHRINKDATABASE(SUSDB, 10)
   ```

4. **Remove old update revisions**
   ```sql
   -- Clean obsolete revision rows
   EXEC spDeleteObsoleteRevisions
   ```

### Database Connection Failed

**Symptoms:**
- "Cannot connect to database" error
- Timeout errors

**Solutions:**

1. **Verify SQL instance name**
   ```powershell
   sqlcmd -L  # List local instances
   ```

2. **Test connection**
   ```powershell
   sqlcmd -S localhost\SQLEXPRESS -d SUSDB -Q "SELECT 1"
   ```

3. **Check authentication**
   - Windows Authentication must be enabled
   - Your account needs sysadmin role

### Database Corruption

**Symptoms:**
- DBCC errors
- Unexpected query results
- WSUS console crashes

**Solutions:**

1. **Check consistency**
   ```sql
   DBCC CHECKDB('SUSDB')
   ```

2. **Restore from backup**
   - Use WSUS Manager **Restore Database**
   - Or via SSMS restore wizard (if SSMS is installed)

---

## Client Issues

### Clients Not Checking In

**Symptoms:**
- No computers in WSUS console
- Clients report to wrong server

**Solutions:**

1. **Verify GPO applied**
   ```powershell
   # On client machine
   gpresult /h gpo-report.html
   # Look for Windows Update policies
   ```

2. **Force GPO update**
   ```powershell
   gpupdate /force
   ```

3. **Check Windows Update settings**
   ```powershell
   # On client
   reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
   ```

4. **Reset Windows Update**
   ```powershell
   net stop wuauserv
   rd /s /q C:\Windows\SoftwareDistribution
   net start wuauserv
   wuauclt /detectnow
   ```

### Clients Getting Updates from Microsoft

**Symptoms:**
- Clients bypass WSUS
- Dual scan enabled

**Solutions:**

1. **Disable dual scan**
   ```
   GPO: Computer Configuration > Admin Templates >
        Windows Components > Windows Update >
        "Do not allow update deferral policies to cause scans against Windows Update"
        = Enabled
   ```

2. **Block Microsoft Update domains** (firewall)
   - windowsupdate.microsoft.com
   - update.microsoft.com

### Endless Download Loop

**Symptoms:**
- Updates download repeatedly
- Never complete installation

**Root Cause:** Incorrect content path configuration

**Solution:**
- Content path must be `C:\WSUS`
- NOT `C:\WSUS\wsuscontent`
- Reconfigure if incorrect:
  ```powershell
  & "C:\Program Files\Update Services\Tools\wsusutil.exe" movecontent C:\WSUS C:\WSUS\move.log
  ```

---

## GUI Issues

### Application Won't Start

**Symptoms:**
- WsusManager.exe doesn't launch
- No error message

**Solutions:**

1. **Run as Administrator**
   - Right-click > Run as administrator

2. **Check .NET Framework**
   ```powershell
   Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" |
       Select-Object Release
   # Should be 461808 or higher (4.7.2)
   ```

3. **Check execution policy**
   ```powershell
   Get-ExecutionPolicy
   # Should not be "Restricted"
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### Dashboard Not Updating

**Symptoms:**
- Status cards show stale data
- Auto-refresh not working

**Solutions:**

1. **Manual refresh**
   - Navigate away and back to Dashboard

2. **Check for frozen process**
   - Close and reopen application

3. **Check log for errors**
   - Open `C:\WSUS\Logs\` and review latest log

### Script Not Found Error

**Symptoms:**
- "Script not found" when running operations
- Path errors in console

**Solution:**
- Ensure `Scripts\` folder is alongside `WsusManager.exe`
- Required files:
  ```
  WsusManager.exe
  Scripts\
  ├── Invoke-WsusManagement.ps1
  └── Invoke-WsusMonthlyMaintenance.ps1
  Modules\
  └── (all .psm1 files)
  ```

**Note:** If you downloaded just the EXE, you must extract the full distribution zip. The EXE requires Scripts/ and Modules/ folders to function.

### Install WSUS Appears Stuck

**Symptoms:**
- Install WSUS starts but shows no progress
- Log shows "Starting Install WSUS" with no further output

**Cause:** The installer prompt is waiting for a folder selection if the SQL Express installer is missing from the default path.

**Solutions:**
1. Look for a folder picker dialog (may be behind other windows)
2. Select the folder containing `SQLEXPRADV_x64_ENU.exe` (SSMS installer is optional)
3. If you canceled the prompt, re-run Install WSUS and select the correct folder

### Online Sync Appears Idle

**Symptoms:**
- Online Sync runs but log output pauses for several minutes

**Cause:** Some phases (sync, cleanup) can be long-running with minimal output.

**Solution:** Allow the process to continue; the GUI refreshes status roughly every 30 seconds.

### Folder Structure Error

**Symptoms:**
- Operations fail with "cannot find module" or "script not recognized"
- Works in dev environment but not from extracted zip

**Cause:** EXE deployed without required folders

**Solution:**
1. Download the full distribution package (`WsusManager-vX.X.X.zip`)
2. Extract ALL contents, maintaining folder structure:
   ```
   WsusManager.exe      # Main application
   Scripts/             # REQUIRED - operation scripts
   Modules/             # REQUIRED - PowerShell modules
    DomainController/    # Optional - Air-gap GPO deployment scripts
   ```
3. Run `WsusManager.exe` from this folder

**Important:** Do not move `WsusManager.exe` to a different location without also moving the Scripts/ and Modules/ folders.

---

## Performance Issues

### Slow Dashboard

**Symptoms:**
- Dashboard takes long to load
- UI freezes periodically

**Solutions:**

1. **Reduce refresh frequency**
   - Currently 30 seconds; consider extending

2. **Check SQL performance**
   ```sql
   -- Find slow queries
   SELECT TOP 10
       total_elapsed_time / execution_count AS avg_time,
       execution_count,
       SUBSTRING(qt.text, qs.statement_start_offset/2, 100) AS query
   FROM sys.dm_exec_query_stats qs
   CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
   ORDER BY avg_time DESC
   ```

3. **Add performance indexes**
   - Run **Online Sync** (adds performance indexes automatically)

### Slow Sync

**Symptoms:**
- Sync takes hours
- Timeout errors during sync

**Solutions:**

1. **Limit products/classifications**
   - Only select needed products
   - Reduce classification scope

2. **Schedule during off-hours**
   - Avoid peak network times

3. **Check network speed**
   ```powershell
   Test-NetConnection -ComputerName windowsupdate.microsoft.com -Port 443
   ```

### Slow Cleanup

**Symptoms:**
- Cleanup runs for hours
- Database operations timeout

**Solutions:**

1. **Run in batches**
   - **Deep Cleanup** processes in batches
   - Let it complete fully

2. **Increase SQL timeout**
   - Maintenance uses extended timeouts automatically

3. **Run during maintenance window**
   - Avoid client activity during cleanup

---

## Robocopy / Transfer Issues

### Transfer Fails to Start

**Symptoms:**
- Robocopy dialog opens but nothing happens after clicking Start Transfer
- Error message in log panel

**Solutions:**

1. **Verify source path exists**
   - Ensure the source folder is accessible and contains update files

2. **Check destination path**
   - Destination drive/share must be writable
   - Ensure sufficient disk space at destination (full content can be 50+ GB)

3. **Run as Administrator**
   - Robocopy requires elevated privileges for some network paths

### Transfer Stops Mid-Way

**Symptoms:**
- Transfer starts but stops before completion
- Incomplete files at destination

**Solutions:**

1. **Check disk space at destination**
   - Full WSUS content can be 50+ GB
   - FAT32 drives have a 4 GB per-file limit — format destination as NTFS

2. **Check source availability**
   - Source path must remain accessible for the entire transfer
   - Network shares may disconnect; prefer local paths or stable UNC paths

3. **Re-run transfer**
   - Robocopy is resume-friendly — re-running skips already-transferred files

### Wrong Files Transferred

**Symptoms:**
- Files appear at wrong location on destination
- Destination folder structure unexpected

**Note:** Robocopy creates a subfolder at the destination (does not copy files into the root of the destination). This is by design to keep transfer sets organized.

### Content Shows "Downloading" After Import (Air-Gap)

**Symptoms:**
- After importing database to air-gapped server, WSUS console shows updates as "downloading"
- Dashboard shows download progress but content files already exist on disk
- Updates never transition to "ready to install" status

**Root Cause:**
When you restore a database backup, WSUS doesn't know that the content files are already present. The database metadata says "needs download" but the actual .cab/.exe files exist in `C:\WSUS\WsusContent\`.

**Solutions:**

1. **Use Reset Content button** (Recommended)
   - In WSUS Manager, click the **Reset Content** button in the DIAGNOSTICS sidebar section (it is a standalone button, not a sub-option of Run Diagnostics)
   - This runs `wsusutil reset` which:
     - Stops WSUS service
     - Re-verifies all content files against database
     - Updates database to reflect actual file status
     - Restarts WSUS service
   - Takes several minutes depending on content size

2. **Manual CLI method**
   ```powershell
   # Stop WSUS
   Stop-Service WSUSService

   # Reset content verification
   & "C:\Program Files\Update Services\Tools\wsusutil.exe" reset

   # Restart WSUS
   Start-Service WSUSService
   ```

3. **Verify content path matches**
   - Database expects content in specific location
   - Ensure you imported content to `C:\WSUS\WsusContent\`
   - Content path in database must match actual file location

**Prevention:**
- Always export database AND content files together
- Use the same content path on source and destination servers
- Run Reset Content immediately after any database import

---

## Error Reference

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "Access denied" | Not running as admin | Run as Administrator |
| "Database not found" | SUSDB missing | Check SQL, restore backup |
| "Service not found" | WSUS not installed | Run Install WSUS |
| "Connection timeout" | SQL slow/stopped | Start SQL service |
| "Disk full" | No space left | Free disk space |
| "Port in use" | Conflict on 8530/8531 | Check IIS bindings |

### Event Log Errors

**WSUS (Application Log):**
```
Event ID 364: Content file download failed
Event ID 386: Database connection failed
Event ID 10032: Reset required
```

**SQL Server:**
```
Event ID 17058: Server failed to start
Event ID 823: I/O error
Event ID 9002: Transaction log full
```

### Log File Locations

| Log | Location |
|-----|----------|
| WSUS Manager | `C:\WSUS\Logs\` |
| WSUS Server | `C:\Program Files\Update Services\LogFiles\` |
| IIS | `C:\inetpub\logs\LogFiles\` |
| SQL Server | `C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\Log\` |

---

## Getting Help

### Self-Help Resources

1. Run **Diagnostics** first
2. Review logs in `C:\WSUS\Logs\`
3. Check Windows Event Viewer
4. Search this wiki

### Reporting Issues

If you can't resolve the issue:

1. Collect logs from `C:\WSUS\Logs\`
2. Note the exact error message
3. Document steps to reproduce
4. Open issue on [GitHub](../../issues)

### Useful Links

| Topic | URL |
|-------|-----|
| WSUS Troubleshooting | https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-client-fails-to-connect |
| WSUS Maintenance | https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide |
| SQL Express Help | https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022 |

---

## Next Steps

- [[User Guide]] - Learn normal operations
- [[Installation Guide]] - Reinstall if needed
- [[Developer Guide]] - Debug issues in code
