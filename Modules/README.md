# WSUS PowerShell Modules

**Author:** Tony Tran, ISSO, GA-ASI
**Last Updated:** 2026-01-14
**Module Count:** 11 modules

This directory contains shared PowerShell modules used by the WSUS Manager application and CLI scripts to eliminate code duplication and improve maintainability.

## Overview

The WSUS Manager uses a modular architecture where common functionality has been extracted into reusable modules. This provides:
- **Code Reusability**: Functions can be imported into any script or used interactively
- **Maintainability**: Fix bugs once in the module rather than in multiple scripts
- **Testability**: 323 Pester unit tests across all modules
- **Documentation**: Centralized, standardized documentation

## Available Modules (11 Total)

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
- SSL/HTTPS status detection (`Get-WsusSSLStatus`)
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

### WsusConfig.psm1
**Centralized configuration management**

Provides:
- Configuration access (`Get-WsusConfig`, `Set-WsusConfig`)
- SQL instance helpers (`Get-SqlInstanceName`, `Get-WsusConnectionString`)
- Path helpers (`Get-WsusContentPathFromConfig`, `Get-WsusLogPath`)
- Service/timeout lookups (`Get-WsusServiceName`, `Get-WsusTimeout`)
- Maintenance settings (`Get-WsusMaintenanceSetting`)
- Configuration file I/O (`Initialize-WsusConfigFromFile`, `Export-WsusConfigToFile`)

Example usage:
```powershell
Import-Module .\Modules\WsusConfig.psm1

# Get SQL instance name in various formats
$sqlDot = Get-SqlInstanceName -Format 'Dot'        # .\SQLEXPRESS
$sqlFull = Get-SqlInstanceName -Format 'Localhost' # localhost\SQLEXPRESS

# Get timeout values
$timeout = Get-WsusTimeout -Type 'SqlQueryLong'    # 300 seconds

# Export config to JSON
Export-WsusConfigToFile -Path "C:\WSUS\wsus-config.json"
```

### WsusExport.psm1
**Export and backup functions for air-gapped networks**

Provides:
- Robocopy wrapper (`Invoke-WsusRobocopy`)
- Content export (`Export-WsusContent`)
- Export statistics (`Get-ExportFolderStats`)
- Archive management (`Get-ArchiveStructure`)

Example usage:
```powershell
Import-Module .\Modules\WsusExport.psm1

# Export WSUS content to external media
$result = Export-WsusContent -DestinationPath "E:\WSUS-Export" -IncludeDatabase

# Get export statistics
$stats = Get-ExportFolderStats -Path "E:\WSUS-Export"
Write-Host "Exported $($stats.FileCount) files ($($stats.TotalSizeGB) GB)"
```

### WsusScheduledTask.psm1
**Scheduled task management for automated maintenance**

Provides:
- Task creation (`New-WsusMaintenanceTask`)
- Task status (`Get-WsusMaintenanceTask`)
- Task removal (`Remove-WsusMaintenanceTask`)
- Manual execution (`Start-WsusMaintenanceTask`)
- Interactive menu (`Show-WsusScheduledTaskMenu`)

Example usage:
```powershell
Import-Module .\Modules\WsusScheduledTask.psm1

# Create monthly maintenance task
$result = New-WsusMaintenanceTask -Schedule Monthly -DayOfMonth 15 -Time "02:00" -MaintenanceProfile Full

# Check task status
$status = Get-WsusMaintenanceTask
if ($status.Exists) {
    Write-Host "Next run: $($status.NextRunTime)"
}
```

### WsusAutoDetection.psm1
**Enhanced auto-detection and monitoring**

Provides:
- Detailed service status (`Get-DetailedServiceStatus`)
- Scheduled task status (`Get-WsusScheduledTaskStatus`)
- Database size monitoring (`Get-DatabaseSizeStatus`)
- Certificate expiration checks (`Get-WsusCertificateStatus`)
- Disk space monitoring (`Get-WsusDiskSpaceStatus`)
- Overall health aggregation (`Get-WsusOverallHealth`)
- Auto-recovery (`Start-WsusAutoRecovery`)
- Background monitoring (`Start-WsusHealthMonitor`, `Stop-WsusHealthMonitor`)
- Health summary display (`Show-WsusHealthSummary`)

Example usage:
```powershell
Import-Module .\Modules\WsusAutoDetection.psm1

# Get comprehensive health status
$health = Get-WsusOverallHealth -ContentPath "C:\WSUS"

# Display formatted summary
Show-WsusHealthSummary

# Attempt auto-recovery of stopped services
$result = Start-WsusAutoRecovery -MaxRetries 3
```

### AsyncHelpers.psm1
**Async helpers for WPF GUI applications**

Provides:
- Runspace pool management (`Initialize-AsyncRunspacePool`, `Close-AsyncRunspacePool`)
- Async execution (`Invoke-Async`, `Wait-Async`, `Test-AsyncComplete`, `Stop-Async`)
- UI thread dispatch (`Invoke-UIThread`)
- Background operations (`Start-BackgroundOperation`)

Example usage:
```powershell
Import-Module .\Modules\AsyncHelpers.psm1

# Initialize runspace pool
Initialize-AsyncRunspacePool -MaxRunspaces 4

# Run async operation
$handle = Invoke-Async -ScriptBlock { Get-Service }

# Check completion
if (Test-AsyncComplete -AsyncHandle $handle) {
    $result = Wait-Async -AsyncHandle $handle
}

# Cleanup
Close-AsyncRunspacePool
```

## Scripts That Use These Modules

The following scripts use these modules:

### GUI Application
- **WsusManagementGui.ps1** - Uses: All modules (loaded dynamically based on operation)

### CLI Scripts
- **Invoke-WsusManagement.ps1** - Uses: WsusUtilities, WsusDatabase, WsusServices, WsusHealth, WsusExport, WsusScheduledTask
- **Invoke-WsusMonthlyMaintenance.ps1** - Uses: WsusUtilities, WsusDatabase, WsusServices, WsusScheduledTask
- **Install-WsusWithSqlExpress.ps1** - Uses: WsusUtilities, WsusFirewall, WsusPermissions
- **Set-WsusHttps.ps1** - Uses: WsusUtilities, WsusServices
- **Invoke-WsusClientCheckIn.ps1** - Uses: WsusUtilities

### Domain Controller Scripts
- **Set-WsusGroupPolicy.ps1** - Standalone script for GPO deployment

## Module Dependencies

```
WsusHealth.psm1
├── WsusUtilities.psm1
├── WsusServices.psm1
├── WsusFirewall.psm1
└── WsusPermissions.psm1

WsusDatabase.psm1
└── WsusUtilities.psm1

WsusAutoDetection.psm1
└── (No module dependencies, uses native PowerShell)

AsyncHelpers.psm1
└── (No module dependencies, uses .NET runspaces)
```

## Benefits of Modular Architecture

1. **Reduced Code Duplication**: Common functionality shared across all scripts
2. **Easier Maintenance**: Fix bugs once in the module rather than in multiple scripts
3. **Consistency**: Standardized behavior across all scripts
4. **Testability**: 323 Pester unit tests across 10 test files
5. **Reusability**: Functions can be imported into any script or used interactively
6. **Documentation**: Centralized documentation with comment-based help

## Module Development Guidelines

When extending these modules:

1. **Export Functions Explicitly**: Use `Export-ModuleMember -Function` to control what's exported
2. **Document Functions**: Use PowerShell comment-based help (`<#.SYNOPSIS...#>`)
3. **Include Examples**: Add `.EXAMPLE` blocks for common use cases
4. **Error Handling**: Provide meaningful error messages and return status indicators
5. **Consistency**: Follow existing naming conventions and parameter patterns
6. **Dependencies**: Minimize dependencies between modules where possible
7. **Testing**: Add Pester tests in the `Tests/` directory for new functions

## Version History

- **v1.1.0** (2026-01-14): Documentation update and module expansion
  - Updated all module documentation
  - Added comprehensive examples
  - Documented all 11 modules
  - Updated dependency diagram

- **v1.0.0** (2026-01-09): Initial module extraction from consolidated scripts
  - Created 11 core modules
  - Standardized author headers
  - Implemented modular architecture
