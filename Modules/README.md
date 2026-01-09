# WSUS PowerShell Modules

**Author:** Tony Tran, ISSO, GA-ASI

This directory contains shared PowerShell modules used by the WSUS SQL scripts to eliminate code duplication and improve maintainability.

## Overview

The refactored WSUS scripts now use a modular architecture where common functionality has been extracted into reusable modules. This reduces duplicate code by approximately **480 lines (30% reduction)** across the codebase.

## Available Modules

### WsusUtilities.psm1
**Common utility functions**

Provides:
- Color output functions (`Write-Success`, `Write-Failure`, `Write-Info`, `Write-WsusWarning`)
- Logging functions (`Write-Log`, `Start-WsusLogging`, `Stop-WsusLogging`)
- Admin privilege checks (`Test-AdminPrivileges`)
- SQL helper functions (`Invoke-SqlScalar`)
- Path utilities (`Get-WsusContentPath`, `Test-WsusPath`)

Example usage:
```powershell
Import-Module .\Modules\WsusUtilities.psm1

# Check admin privileges and exit if not admin
Test-AdminPrivileges -ExitOnFail $true

# Start logging
$logFile = Start-WsusLogging -ScriptName "MyScript"

# Color output
Write-Success "Operation completed successfully"
Write-Failure "An error occurred"
```

### WsusDatabase.psm1
**Database cleanup and optimization functions**

Provides:
- Database size queries (`Get-WsusDatabaseSize`, `Get-WsusDatabaseStats`)
- Supersession record cleanup (`Remove-DeclinedSupersessionRecords`, `Remove-SupersededSupersessionRecords`)
- Index optimization (`Optimize-WsusIndexes`, `Add-WsusPerformanceIndexes`)
- Statistics updates (`Update-WsusStatistics`)
- Database shrink operations (`Invoke-WsusDatabaseShrink`, `Get-WsusDatabaseSpace`)

Example usage:
```powershell
Import-Module .\Modules\WsusDatabase.psm1

# Get database size
$size = Get-WsusDatabaseSize -SqlInstance "localhost\SQLEXPRESS"
Write-Host "Database size: $size GB"

# Clean up supersession records
$deleted = Remove-DeclinedSupersessionRecords
Write-Host "Removed $deleted records"

# Optimize indexes
$result = Optimize-WsusIndexes -ShowProgress
Write-Host "Rebuilt: $($result.Rebuilt), Reorganized: $($result.Reorganized)"
```

### WsusPermissions.psm1
**Content directory permissions management**

Provides:
- Set standardized permissions (`Set-WsusContentPermissions`)
- Verify permissions (`Test-WsusContentPermissions`)
- Repair permissions (`Repair-WsusContentPermissions`)
- Initialize directories (`Initialize-WsusDirectories`)

Example usage:
```powershell
Import-Module .\Modules\WsusPermissions.psm1

# Check permissions
$check = Test-WsusContentPermissions -ContentPath "C:\WSUS"
if (-not $check.AllCorrect) {
    Write-Host "Missing permissions: $($check.Missing -join ', ')"
}

# Set permissions
Set-WsusContentPermissions -ContentPath "C:\WSUS"
```

### WsusServices.psm1
**Service management functions**

Provides:
- Service status checks (`Test-ServiceRunning`, `Test-ServiceExists`)
- Generic service operations (`Start-WsusService`, `Stop-WsusService`, `Restart-WsusService`)
- WSUS-specific functions (`Start-WsusServer`, `Stop-WsusServer`)
- SQL Server functions (`Start-SqlServerExpress`, `Stop-SqlServerExpress`)
- IIS functions (`Start-IISService`, `Stop-IISService`)
- Bulk operations (`Start-AllWsusServices`, `Stop-AllWsusServices`, `Get-WsusServiceStatus`)

Example usage:
```powershell
Import-Module .\Modules\WsusServices.psm1

# Start all WSUS services
$result = Start-AllWsusServices
Write-Host "SQL: $($result.SqlServer), IIS: $($result.IIS), WSUS: $($result.WSUS)"

# Check service status
if (Test-ServiceRunning -ServiceName "WSUSService") {
    Write-Host "WSUS is running"
}

# Get comprehensive status
$status = Get-WsusServiceStatus
$status.GetEnumerator() | ForEach-Object {
    Write-Host "$($_.Key): $($_.Value.Status)"
}
```

### WsusFirewall.psm1
**Firewall rule management**

Provides:
- Create firewall rules (`New-WsusFirewallRule`)
- Test rules (`Test-WsusFirewallRule`)
- Remove rules (`Remove-WsusFirewallRule`)
- Bulk operations (`Initialize-WsusFirewallRules`, `Initialize-SqlFirewallRules`)
- Repair operations (`Repair-WsusFirewallRules`, `Repair-SqlFirewallRules`)
- Status checks (`Test-AllWsusFirewallRules`, `Test-AllSqlFirewallRules`)

Example usage:
```powershell
Import-Module .\Modules\WsusFirewall.psm1

# Create all WSUS firewall rules
$result = Initialize-WsusFirewallRules
Write-Host "Created: $($result.Created.Count) rules"

# Check and repair missing rules
$result = Repair-WsusFirewallRules
if ($result.AlreadyPresent) {
    Write-Host "All rules already present"
}
```

### WsusHealth.psm1
**Comprehensive health checking**

Provides:
- Database connectivity tests (`Test-WsusDatabaseConnection`)
- Comprehensive health checks (`Test-WsusHealth`)
- Automated repair (`Repair-WsusHealth`)

Note: This module automatically imports WsusServices, WsusFirewall, and WsusPermissions modules.

Example usage:
```powershell
Import-Module .\Modules\WsusHealth.psm1

# Run comprehensive health check
$health = Test-WsusHealth -ContentPath "C:\WSUS" -IncludeDatabase

if ($health.Overall -eq "Healthy") {
    Write-Host "All systems operational"
} else {
    Write-Host "Issues found: $($health.Issues -join ', ')"
}

# Attempt automatic repair
$result = Repair-WsusHealth
Write-Host "Services started: $($result.ServicesStarted.Count)"
```

## Scripts That Use These Modules

The following scripts use these modules:

### Main Entry Point
- **Invoke-WsusManagement.ps1** - Uses: WsusUtilities, WsusDatabase, WsusServices, WsusHealth

### Maintenance Scripts
- **Invoke-WsusMonthlyMaintenance.ps1** - Uses: WsusUtilities, WsusDatabase, WsusServices

### Client Scripts
- **Invoke-WsusClientCheckIn.ps1** - Uses: WsusUtilities

## Benefits of Modular Architecture

1. **Reduced Code Duplication**: ~480 lines of duplicate code eliminated
2. **Easier Maintenance**: Fix bugs once in the module rather than in multiple scripts
3. **Consistency**: Standardized behavior across all scripts
4. **Testability**: Modules can be tested independently
5. **Reusability**: Functions can be imported into any script or used interactively
6. **Documentation**: Centralized documentation for common operations

## Module Development Guidelines

When extending these modules:

1. **Export Functions Explicitly**: Use `Export-ModuleMember -Function` to control what's exported
2. **Document Functions**: Use PowerShell comment-based help (`<#.SYNOPSIS...#>`)
3. **Error Handling**: Provide meaningful error messages and return status indicators
4. **Consistency**: Follow existing naming conventions and parameter patterns
5. **Dependencies**: Minimize dependencies between modules where possible

## Version History

- **v1.0.0** (2026-01-09): Initial module extraction from consolidated scripts
  - Created 6 core modules
  - Standardized author headers
  - Reduced codebase by ~480 lines
