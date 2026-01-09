# CLAUDE.md - AI Assistant Guide for WSUS-SQL

This document provides context and guidance for AI assistants working with this codebase.

## Project Overview

This is a **WSUS (Windows Server Update Services) + SQL Server Express 2022 automation suite**. It automates deployment, maintenance, and management of WSUS servers for both online and air-gapped (offline) network environments.

**Primary Use Case:** Enterprise environments that need to distribute Windows updates to client machines, including disconnected/air-gapped networks that cannot access the internet.

## Architecture

### Entry Points

| File | Purpose | Run On |
|------|---------|--------|
| `Invoke-WsusManagement.ps1` | Main entry point - interactive menu + CLI switches | WSUS Server |
| `Scripts/Install-WsusWithSqlExpress.ps1` | One-time installation | WSUS Server |
| `Scripts/Invoke-WsusMonthlyMaintenance.ps1` | Scheduled maintenance | Online WSUS Server |
| `Scripts/Invoke-WsusClientCheckIn.ps1` | Force client check-in | Client Machines |
| `DomainController/Set-WsusGroupPolicy.ps1` | GPO deployment | Domain Controller |

### Module Architecture

All modules are in `/Modules/` and follow a consistent pattern:

```
WsusUtilities.psm1   - Logging, color output, SQL queries, path utilities
WsusDatabase.psm1    - Database operations (backup, restore, cleanup, indexes)
WsusServices.psm1    - Service management (start/stop WSUS, SQL, IIS)
WsusHealth.psm1      - Health checking and auto-repair
WsusPermissions.psm1 - Content directory permissions
WsusFirewall.psm1    - Firewall rule management
```

**Module Dependencies:**
- `WsusHealth` imports: `WsusServices`, `WsusFirewall`, `WsusPermissions`
- All modules import: `WsusUtilities`

### Key Functions by Module

**WsusUtilities.psm1:**
- `Write-Success`, `Write-Failure`, `Write-Info`, `Write-WsusWarning` - Color output
- `Start-WsusLogging`, `Stop-WsusLogging`, `Write-Log` - Logging
- `Test-AdminPrivileges` - Admin check
- `Invoke-SqlScalar` - Execute SQL queries
- `Get-WsusContentPath`, `Test-WsusPath` - Path utilities

**WsusDatabase.psm1:**
- `Get-WsusDatabaseSize`, `Get-WsusDatabaseStats` - Size queries
- `Remove-DeclinedSupersessionRecords`, `Remove-SupersededSupersessionRecords` - Cleanup
- `Optimize-WsusIndexes`, `Add-WsusPerformanceIndexes` - Index management
- `Update-WsusStatistics`, `Invoke-WsusDatabaseShrink` - Maintenance

**WsusServices.psm1:**
- `Start-WsusServer`, `Stop-WsusServer` - WSUS service
- `Start-SqlServerExpress`, `Stop-SqlServerExpress` - SQL service
- `Start-IISService`, `Stop-IISService` - IIS
- `Get-WsusServiceStatus`, `Start-AllWsusServices`, `Stop-AllWsusServices` - Bulk ops

**WsusHealth.psm1:**
- `Test-WsusDatabaseConnection` - DB connectivity
- `Test-WsusHealth` - Comprehensive health check
- `Repair-WsusHealth` - Automated repair

## Critical Implementation Details

### Content Path (CRITICAL)

```
CORRECT: C:\WSUS
WRONG:   C:\WSUS\wsuscontent
```

Using the wrong path causes endless downloads. The content path is stored in registry:
```
HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup\ContentDir
```

### Default Paths

| Path | Purpose |
|------|---------|
| `C:\WSUS` | WSUS content directory |
| `C:\WSUS\SQLDB` | SQL/SSMS installers |
| `C:\WSUS\Logs` | Log files |
| `\\lab-hyperv\d\WSUS-Exports` | Default export destination |

### Services

| Service | Purpose |
|---------|---------|
| `WSUSService` | WSUS main service |
| `MSSQL$SQLEXPRESS` | SQL Server Express instance |
| `W3SVC` | IIS |
| `wuauserv` | Windows Update (client-side) |
| `bits` | Background Intelligent Transfer |

### Database

- **Database Name:** SUSDB
- **SQL Instance:** `.\SQLEXPRESS`
- **Connection String:** `Server=.\SQLEXPRESS;Database=SUSDB;Integrated Security=True`

## Common Tasks

### Adding a New Feature to Main Menu

1. Edit `Invoke-WsusManagement.ps1`
2. Add menu option in `Show-MainMenu` function
3. Add case handler in the switch statement
4. Follow existing patterns for user prompts and error handling

### Adding a New Module Function

1. Add function to appropriate module in `/Modules/`
2. Export function in module's `Export-ModuleMember` (if present)
3. Document function with comment-based help
4. Follow naming convention: `Verb-WsusNoun`

### Modifying Export Logic

Export functionality is in two places:
- `Invoke-WsusManagement.ps1` - `-Export` switch handler
- `Scripts/Invoke-WsusMonthlyMaintenance.ps1` - Export step

Both use robocopy with these key flags:
```powershell
robocopy $source $dest /E /MT:16 /R:2 /W:5 /MINAGE:$days
```

## Code Style Guidelines

### PowerShell Conventions

- Use approved verbs: `Get-`, `Set-`, `New-`, `Remove-`, `Test-`, `Invoke-`
- Prefix all WSUS-related functions with `Wsus`: `Test-WsusHealth`, `Start-WsusServer`
- Use `Write-Success`/`Write-Failure`/`Write-Info` from WsusUtilities for colored output
- Always check admin privileges at script start with `Test-AdminPrivileges`
- Use try/catch with meaningful error messages

### Logging Pattern

```powershell
Start-WsusLogging -LogPath "C:\WSUS\Logs\script.log"
Write-Log "Operation started"
# ... operations ...
Write-Log "Operation completed"
Stop-WsusLogging
```

### Error Handling Pattern

```powershell
try {
    # Operation
    Write-Success "Operation completed"
} catch {
    Write-Failure "Operation failed: $($_.Exception.Message)"
    Write-Log "Error: $($_.Exception.Message)"
}
```

## Testing Considerations

- Scripts require Administrator privileges
- Scripts are designed for Windows Server 2016+
- SQL Server Express 2022 must be installed for database operations
- WSUS role must be installed for WSUS operations
- Some operations stop services (SQL, IIS, WSUS) - warn users about downtime

## Common Pitfalls

1. **Content path mismatch** - Always verify `C:\WSUS` is used, not subfolders
2. **Service state** - Check service status before operations that require them running/stopped
3. **Database locks** - Stop WSUS service before database operations
4. **Permission issues** - Content directory needs specific NTFS permissions for WSUS to function
5. **Here-strings in PowerShell** - Cannot be nested; use string concatenation or variables instead

## Useful SQL Queries

```sql
-- Check database size
SELECT DB_NAME(database_id) AS DatabaseName,
       (size * 8 / 1024) AS SizeMB
FROM sys.master_files WHERE database_id = DB_ID('SUSDB')

-- Count updates
SELECT COUNT(*) FROM tbUpdate

-- Find superseded updates
SELECT COUNT(*) FROM tbSupersededUpdate
```

## GPO Structure

Three pre-configured GPOs in `DomainController/WSUS GPOs/`:
1. `{A806083D-...}` - WSUS Update Policy (client settings)
2. `{50621A3B-...}` - WSUS Inbound Allow (firewall)
3. `{D1E8733B-...}` - WSUS Outbound Allow (firewall)

The GPO script replaces hardcoded URLs with the user's WSUS server URL.

## File Modification Checklist

When modifying scripts:
- [ ] Test with `-WhatIf` if supported
- [ ] Verify admin privilege checks are present
- [ ] Add appropriate logging
- [ ] Handle errors gracefully
- [ ] Update version number if significant change
- [ ] Test on both online and air-gapped scenarios if applicable
