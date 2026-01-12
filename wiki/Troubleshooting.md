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
7. [Export/Import Issues](#exportimport-issues)
8. [Error Reference](#error-reference)

---

## Quick Diagnostics

### Health Check

Always start with a Health Check:

1. Launch `WsusManager.exe`
2. Click **Health Check**
3. Review the output

The Health Check verifies:
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
| Automation | Orange | No scheduled task | Run Monthly Maintenance |

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
   -- Run in SSMS
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
   - Or via SSMS restore wizard

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

### Folder Structure Error

**Symptoms:**
- Operations fail with "cannot find module" or "script not recognized"
- Works in dev environment but not from extracted zip

**Cause:** EXE deployed without required folders

**Solution:**
1. Download the full distribution package (`WsusManager-vX.X.X.zip`)
2. Extract ALL contents, maintaining folder structure:
   ```
   WsusManager-vX.X.X/
   ├── WsusManager.exe      # Main application
   ├── Scripts/             # REQUIRED - operation scripts
   ├── Modules/             # REQUIRED - PowerShell modules
   └── DomainController/    # Optional - GPO scripts
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
   - Run Monthly Maintenance (adds indexes automatically)

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
   - Monthly Maintenance processes in batches
   - Let it complete fully

2. **Increase SQL timeout**
   - Maintenance uses extended timeouts automatically

3. **Run during maintenance window**
   - Avoid client activity during cleanup

---

## Export/Import Issues

### Export Hangs (No Progress)

**Symptoms:**
- Export operation starts but hangs with no output
- Script waiting for input
- GUI appears frozen

**Cause:** Old CLI script version prompting for interactive input

**Solutions:**

1. **Update to v3.8.4+**
   - Download latest release from GitHub
   - Extract and replace all files

2. **Verify Scripts folder**
   - Ensure `Scripts\Invoke-WsusManagement.ps1` is from v3.8.4+
   - Check file date is recent

3. **Manual CLI test**
   ```powershell
   # Test non-interactive mode directly
   .\Scripts\Invoke-WsusManagement.ps1 -Export -DestinationPath "D:\Export" -CopyMode "Full"
   ```

### Export Fails

**Symptoms:**
- Export stops mid-way
- Incomplete files on USB

**Solutions:**

1. **Check disk space**
   - USB needs space for all content
   - Full export can be 50+ GB

2. **Use NTFS format**
   - FAT32 has 4 GB file limit
   - Format USB as NTFS

3. **Check for file locks**
   - Close WSUS console during export

### Import Fails

**Symptoms:**
- Import completes but updates missing
- Database restore fails

**Solutions:**

1. **Verify export integrity**
   - Check manifest file exists
   - Verify backup file not corrupted

2. **Check SQL service**
   - Must be running before restore

3. **Sufficient disk space**
   - Need space for database + content

4. **Run Health Check after import**
   - Identify any remaining issues

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

1. Run **Health Check** first
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
