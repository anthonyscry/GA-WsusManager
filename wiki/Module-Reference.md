# Module Reference

Complete reference for all PowerShell modules in WSUS Manager.

---

## Table of Contents

1. [WsusUtilities](#wsusutilities)
2. [WsusDatabase](#wsusdatabase)
3. [WsusServices](#wsusservices)
4. [WsusHealth](#wsushealth)
5. [WsusFirewall](#wsusfirewall)
6. [WsusPermissions](#wsuspermissions)
7. [WsusConfig](#wsusconfig)
8. [WsusExport](#wsusexport)
9. [WsusScheduledTask](#wsusscheduledtask)
10. [WsusAutoDetection](#wsusautodetection)

---

## WsusUtilities

Core utility functions for logging, output formatting, and common helpers.

### Functions

#### Write-Success
Writes a success message in green.

```powershell
Write-Success "Operation completed successfully"
```

#### Write-Failure
Writes a failure message in red.

```powershell
Write-Failure "Operation failed"
```

#### Write-WsusWarning
Writes a warning message in yellow.

```powershell
Write-WsusWarning "Disk space is running low"
```

#### Write-Info
Writes an informational message in cyan.

```powershell
Write-Info "Starting synchronization..."
```

#### Write-Log
Writes a message to the log file.

```powershell
Write-Log "Processing update batch 1 of 10"
Write-Log "Error occurred" -Level Error
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Message | string | Message to log |
| Level | string | Log level (Info, Warning, Error) |

#### Start-WsusLogging
Starts logging to a new file.

```powershell
$logFile = Start-WsusLogging -ScriptName "Maintenance"
```

#### Stop-WsusLogging
Stops logging and closes the file.

```powershell
Stop-WsusLogging
```

#### Test-AdminPrivileges
Checks if running with administrator privileges.

```powershell
if (-not (Test-AdminPrivileges)) {
    Write-Failure "Admin required"
    exit 1
}
```

| Parameter | Type | Description |
|-----------|------|-------------|
| ExitOnFail | bool | Exit script if not admin |

#### Invoke-SqlScalar
Executes a SQL query and returns a scalar result.

```powershell
$size = Invoke-SqlScalar -Query "SELECT COUNT(*) FROM Updates" -SqlInstance ".\SQLEXPRESS"
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Query | string | SQL query |
| SqlInstance | string | SQL instance (default: .\SQLEXPRESS) |
| Database | string | Database name (default: SUSDB) |
| Timeout | int | Query timeout in seconds |

#### Test-ValidPath
Validates a file system path.

```powershell
if (Test-ValidPath -Path "C:\WSUS") { ... }
```

#### Test-SafePath
Checks if path is safe (no command injection).

```powershell
if (Test-SafePath -Path $userInput) { ... }
```

#### Get-EscapedPath
Escapes a path for safe use in commands.

```powershell
$safePath = Get-EscapedPath -Path "C:\Path With Spaces"
```

---

## WsusDatabase

Database operations, cleanup, and optimization functions.

### Functions

#### Get-WsusDatabaseSize
Gets SUSDB size in GB.

```powershell
$sizeGB = Get-WsusDatabaseSize
# Returns: 5.5
```

#### Get-WsusDatabaseStats
Gets comprehensive database statistics.

```powershell
$stats = Get-WsusDatabaseStats
$stats.SizeGB              # Database size
$stats.SupersessionRecords # Obsolete records count
$stats.UpdateCount         # Total updates
```

#### Remove-DeclinedSupersessionRecords
Removes supersession records for declined updates.

```powershell
$deleted = Remove-DeclinedSupersessionRecords
Write-Host "Removed $deleted records"
```

#### Remove-SupersededSupersessionRecords
Removes supersession records for superseded updates.

```powershell
$deleted = Remove-SupersededSupersessionRecords -BatchSize 1000
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| BatchSize | int | 10000 | Records per batch |
| SqlInstance | string | .\SQLEXPRESS | SQL instance |

#### Optimize-WsusIndexes
Rebuilds and reorganizes fragmented indexes.

```powershell
$result = Optimize-WsusIndexes -ShowProgress
$result.Rebuilt      # Indexes rebuilt
$result.Reorganized  # Indexes reorganized
```

| Parameter | Type | Description |
|-----------|------|-------------|
| FragmentationThreshold | int | Reorganize threshold (default: 10) |
| RebuildThreshold | int | Rebuild threshold (default: 30) |
| ShowProgress | switch | Display progress |

#### Add-WsusPerformanceIndexes
Creates performance indexes if missing.

```powershell
Add-WsusPerformanceIndexes
```

#### Update-WsusStatistics
Updates database statistics.

```powershell
$success = Update-WsusStatistics
```

#### Invoke-WsusDatabaseShrink
Shrinks the database file.

```powershell
$success = Invoke-WsusDatabaseShrink -TargetFreePercent 10
```

#### Get-WsusDatabaseSpace
Gets database space allocation info.

```powershell
$space = Get-WsusDatabaseSpace
$space.AllocatedMB
$space.UsedMB
$space.FreeMB
```

#### Test-WsusBackupIntegrity
Verifies a backup file.

```powershell
$result = Test-WsusBackupIntegrity -BackupPath "C:\WSUS\backup.bak"
$result.IsValid
$result.BackupDate
```

#### Test-WsusDiskSpace
Checks available disk space.

```powershell
$check = Test-WsusDiskSpace -Path "C:\WSUS" -RequiredSpaceGB 10
$check.HasSufficientSpace
$check.FreeSpaceGB
```

#### Test-WsusDatabaseConsistency
Runs DBCC CHECKDB.

```powershell
$result = Test-WsusDatabaseConsistency -PhysicalOnly
$result.IsConsistent
$result.Duration
```

---

## WsusServices

Service management functions.

### Functions

#### Test-ServiceRunning
Checks if a service is running.

```powershell
if (Test-ServiceRunning -ServiceName "WSUSService") { ... }
```

#### Test-ServiceExists
Checks if a service exists.

```powershell
if (Test-ServiceExists -ServiceName "WSUSService") { ... }
```

#### Start-WsusService
Starts a service with retry logic.

```powershell
$success = Start-WsusService -ServiceName "WSUSService" -MaxRetries 3
```

#### Stop-WsusService
Stops a service.

```powershell
$success = Stop-WsusService -ServiceName "WSUSService" -Force
```

#### Restart-WsusService
Restarts a service.

```powershell
$success = Restart-WsusService -ServiceName "WSUSService"
```

#### Start-SqlServerExpress
Starts SQL Server Express.

```powershell
$success = Start-SqlServerExpress
```

#### Stop-SqlServerExpress
Stops SQL Server Express.

```powershell
$success = Stop-SqlServerExpress
```

#### Start-IISService
Starts IIS (W3SVC).

```powershell
$success = Start-IISService
```

#### Stop-IISService
Stops IIS.

```powershell
$success = Stop-IISService
```

#### Start-WsusServer
Starts WSUS service.

```powershell
$success = Start-WsusServer
```

#### Stop-WsusServer
Stops WSUS service.

```powershell
$success = Stop-WsusServer
```

#### Start-AllWsusServices
Starts all WSUS services in order.

```powershell
$result = Start-AllWsusServices
$result.SqlServer  # true/false
$result.IIS        # true/false
$result.WSUS       # true/false
```

#### Stop-AllWsusServices
Stops all WSUS services.

```powershell
$result = Stop-AllWsusServices
```

#### Get-WsusServiceStatus
Gets status of all services.

```powershell
$status = Get-WsusServiceStatus
foreach ($svc in $status.GetEnumerator()) {
    "$($svc.Key): $($svc.Value.Status)"
}
```

---

## WsusHealth

Health checking and repair functions.

### Functions

#### Get-WsusSSLStatus
Gets SSL/HTTPS configuration status.

```powershell
$ssl = Get-WsusSSLStatus
$ssl.SSLEnabled   # true/false
$ssl.Protocol     # HTTP or HTTPS
$ssl.Port         # 8530 or 8531
```

#### Test-WsusDatabaseConnection
Tests database connectivity.

```powershell
$conn = Test-WsusDatabaseConnection -SqlInstance ".\SQLEXPRESS"
$conn.Connected   # true/false
$conn.Message     # Status message
```

#### Test-WsusHealth
Comprehensive health check.

```powershell
$health = Test-WsusHealth -ContentPath "C:\WSUS" -IncludeDatabase
$health.Overall   # Healthy, Degraded, or Unhealthy
$health.Services  # Service status array
$health.Database  # Database status
$health.Firewall  # Firewall status
$health.Permissions # Permission status
$health.Issues    # Array of issues
```

| Parameter | Type | Description |
|-----------|------|-------------|
| ContentPath | string | WSUS content path |
| SqlInstance | string | SQL instance |
| IncludeDatabase | switch | Include DB checks |

#### Repair-WsusHealth
Attempts automatic repair.

```powershell
$repair = Repair-WsusHealth -ContentPath "C:\WSUS"
$repair.ServicesStarted    # Count
$repair.FirewallRulesCreated # Count
$repair.PermissionsFixed   # true/false
```

---

## WsusFirewall

Firewall rule management.

### Functions

#### Test-WsusFirewallRule
Tests if a firewall rule exists.

```powershell
$exists = Test-WsusFirewallRule -DisplayName "WSUS HTTP Traffic (Port 8530)"
```

#### New-WsusFirewallRule
Creates a firewall rule.

```powershell
New-WsusFirewallRule -DisplayName "WSUS HTTP" -Port 8530 -Protocol TCP
```

#### Remove-WsusFirewallRule
Removes a firewall rule.

```powershell
$removed = Remove-WsusFirewallRule -DisplayName "WSUS HTTP Traffic (Port 8530)"
```

#### Initialize-WsusFirewallRules
Creates all required WSUS firewall rules.

```powershell
$result = Initialize-WsusFirewallRules
$result.Created   # Rules created
$result.Existing  # Already existed
```

#### Initialize-SqlFirewallRules
Creates SQL Server firewall rules.

```powershell
$result = Initialize-SqlFirewallRules
```

#### Test-AllWsusFirewallRules
Tests all WSUS firewall rules.

```powershell
$test = Test-AllWsusFirewallRules
$test.AllPresent  # true/false
$test.Present     # Present rules
$test.Missing     # Missing rules
```

#### Test-AllSqlFirewallRules
Tests all SQL firewall rules.

```powershell
$test = Test-AllSqlFirewallRules
```

#### Repair-WsusFirewallRules
Creates missing WSUS firewall rules.

```powershell
$result = Repair-WsusFirewallRules
```

#### Repair-SqlFirewallRules
Creates missing SQL firewall rules.

```powershell
$result = Repair-SqlFirewallRules
```

---

## WsusPermissions

Directory permission management.

### Functions

#### Test-WsusContentPermissions
Tests content directory permissions.

```powershell
$check = Test-WsusContentPermissions -WSUSRoot "C:\WSUS"
$check.AllCorrect  # true/false
$check.Found       # Present permissions
$check.Missing     # Missing permissions
```

#### Set-WsusContentPermissions
Sets required permissions.

```powershell
Set-WsusContentPermissions -WSUSRoot "C:\WSUS"
```

#### Repair-WsusContentPermissions
Repairs missing permissions.

```powershell
$result = Repair-WsusContentPermissions -WSUSRoot "C:\WSUS"
```

#### Initialize-WsusDirectories
Creates WSUS directory structure.

```powershell
Initialize-WsusDirectories -WSUSRoot "C:\WSUS"
# Creates: C:\WSUS\WSUSContent, C:\WSUS\UpdateServicesPackages, C:\WSUS\Logs
```

---

## WsusConfig

Configuration management.

### Functions

#### Get-WsusConfig
Gets configuration values.

```powershell
# Get all config
$config = Get-WsusConfig

# Get specific key
$sqlInstance = Get-WsusConfig -Key "SqlInstance"

# Get nested value
$timeout = Get-WsusConfig -Key "Timeouts.SqlQueryDefault"
```

#### Set-WsusConfig
Sets a configuration value.

```powershell
Set-WsusConfig -Key "SqlInstance" -Value ".\SQLEXPRESS"
Set-WsusConfig -Key "Timeouts.SqlQueryDefault" -Value 120
```

#### Get-SqlInstanceName
Gets SQL instance in various formats.

```powershell
Get-SqlInstanceName -Format Short     # SQLEXPRESS
Get-SqlInstanceName -Format Dot       # .\SQLEXPRESS
Get-SqlInstanceName -Format Localhost # localhost\SQLEXPRESS
```

#### Get-WsusLogPath
Gets the log directory path.

```powershell
$logPath = Get-WsusLogPath
# Returns: C:\WSUS\Logs
```

#### Get-WsusServiceName
Gets service name by alias.

```powershell
Get-WsusServiceName -Alias SqlExpress   # MSSQL$SQLEXPRESS
Get-WsusServiceName -Alias Wsus         # WSUSService
Get-WsusServiceName -Alias Iis          # W3SVC
```

#### Get-WsusTimeout
Gets timeout value.

```powershell
Get-WsusTimeout -Operation SqlQueryDefault  # 120
Get-WsusTimeout -Operation SqlQueryLong     # 600
Get-WsusTimeout -Operation ServiceStart     # 60
```

#### Get-WsusMaintenanceSetting
Gets maintenance settings.

```powershell
Get-WsusMaintenanceSetting -Setting BackupRetentionDays  # 30
Get-WsusMaintenanceSetting -Setting DefaultExportDays    # 30
Get-WsusMaintenanceSetting -Setting BatchSize            # 10000
```

#### Get-WsusConnectionString
Gets SQL connection string.

```powershell
$connStr = Get-WsusConnectionString
# "Server=.\SQLEXPRESS;Database=SUSDB;Integrated Security=True"
```

#### Get-WsusContentPathFromConfig
Gets content path from config.

```powershell
Get-WsusContentPathFromConfig                         # C:\WSUS
Get-WsusContentPathFromConfig -IncludeSubfolder      # C:\WSUS\WSUSContent
```

#### Export-WsusConfigToFile
Exports configuration to JSON file.

```powershell
Export-WsusConfigToFile -Path "C:\backup\wsus-config.json"
```

#### Initialize-WsusConfigFromFile
Loads configuration from file.

```powershell
$loaded = Initialize-WsusConfigFromFile -Path "C:\backup\wsus-config.json"
```

---

## WsusExport

Export and import operations.

### Functions

#### Get-ExportFolderStats
Gets statistics about an export folder.

```powershell
$stats = Get-ExportFolderStats -Path "E:\WSUS_Export"
$stats.FileCount
$stats.TotalSizeGB
$stats.Exists
```

#### Get-ArchiveStructure
Gets structure of exported archive.

```powershell
$structure = Get-ArchiveStructure -BasePath "E:\WSUS_Export"
```

#### Invoke-WsusRobocopy
Performs robocopy with standard options.

```powershell
$result = Invoke-WsusRobocopy -Source "C:\WSUS\WsusContent" -Destination "E:\Export"
$result.Success
$result.FilesCopied
$result.ExitCode
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Source | string | - | Source path |
| Destination | string | - | Destination path |
| ThreadCount | int | 8 | Parallel threads |
| RetryCount | int | 3 | Retry attempts |

#### Export-WsusContent
Exports WSUS content to destination.

```powershell
$result = Export-WsusContent -SourcePath "C:\WSUS" -DestinationPath "E:\Export"
$result.Success
$result.FilesCopied
$result.SizeGB
```

---

## WsusScheduledTask

Scheduled task management.

### Functions

#### Get-WsusMaintenanceTask
Gets the maintenance scheduled task.

```powershell
$task = Get-WsusMaintenanceTask
$task.State       # Ready, Running, Disabled
$task.LastRunTime
$task.NextRunTime
```

#### New-WsusMaintenanceTask
Creates the maintenance scheduled task.

```powershell
New-WsusMaintenanceTask -RunAsUser "SYSTEM" -MonthlyDay 1 -Time "02:00"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| RunAsUser | string | SYSTEM | Account to run as |
| MonthlyDay | int | 1 | Day of month |
| Time | string | 02:00 | Time to run |

#### Remove-WsusMaintenanceTask
Removes the scheduled task.

```powershell
$removed = Remove-WsusMaintenanceTask
```

#### Test-WsusMaintenanceTask
Tests if task exists and is configured.

```powershell
$exists = Test-WsusMaintenanceTask
```

---

## WsusAutoDetection

Auto-detection and recovery functions.

### Functions

#### Get-DetailedServiceStatus
Gets detailed status of all WSUS services.

```powershell
$services = Get-DetailedServiceStatus
foreach ($svc in $services) {
    "$($svc.Name): $($svc.Status) (Critical: $($svc.Critical))"
}
```

Returns array of:
| Property | Type | Description |
|----------|------|-------------|
| Name | string | Friendly name |
| ServiceName | string | Service name |
| Critical | bool | Is critical service |
| Installed | bool | Is installed |
| Status | string | Current status |
| Running | bool | Is running |

#### Get-WsusScheduledTaskStatus
Gets scheduled task status.

```powershell
$task = Get-WsusScheduledTaskStatus -TaskName "WSUS Monthly Maintenance"
$task.Exists
$task.State
$task.LastRunTime
$task.NextRunTime
$task.MissedRuns
```

#### Get-DatabaseSizeStatus
Gets database size with threshold warnings.

```powershell
$db = Get-DatabaseSizeStatus -SqlInstance ".\SQLEXPRESS"
$db.Available      # true/false
$db.SizeGB         # Current size
$db.Status         # Healthy, Moderate, Warning, Critical
$db.PercentOfLimit # Percent of 10GB limit
$db.Warning        # Warning message if any
```

#### Get-WsusCertificateStatus
Gets SSL certificate status.

```powershell
$cert = Get-WsusCertificateStatus
$cert.SSLEnabled
$cert.CertificateFound
$cert.ExpiresIn       # Days until expiration
$cert.ExpirationDate
$cert.Warning         # Warning if expiring soon
```

#### Get-WsusDiskSpaceStatus
Gets disk space status.

```powershell
$disk = Get-WsusDiskSpaceStatus -ContentPath "C:\WSUS"
$disk.Available
$disk.FreeGB
$disk.TotalGB
$disk.UsedPercent
$disk.Status     # Healthy, Warning, Critical
```

#### Get-WsusOverallHealth
Gets comprehensive health status.

```powershell
$health = Get-WsusOverallHealth -ContentPath "C:\WSUS"
$health.Status          # Healthy, Degraded, Unhealthy
$health.Services        # Service status array
$health.Database        # Database status
$health.Certificate     # Cert status
$health.DiskSpace       # Disk status
$health.ScheduledTask   # Task status
$health.Issues          # Critical issues
$health.Warnings        # Warnings
```

#### Start-WsusAutoRecovery
Attempts automatic service recovery.

```powershell
$recovery = Start-WsusAutoRecovery -MaxRetries 3 -WhatIf
$recovery.Attempted       # Services attempted
$recovery.Recovered       # Successfully started
$recovery.Failed          # Failed to start
$recovery.AlreadyRunning  # Already running
$recovery.Success         # Overall success
```

#### Show-WsusHealthSummary
Displays formatted health summary.

```powershell
Show-WsusHealthSummary -ContentPath "C:\WSUS"
```

#### Start-WsusHealthMonitor
Starts background health monitoring.

```powershell
$job = Start-WsusHealthMonitor -IntervalSeconds 300 -AutoRecover
```

#### Stop-WsusHealthMonitor
Stops background monitoring.

```powershell
Stop-WsusHealthMonitor
```

---

## Next Steps

- [[Developer Guide]] - How to extend modules
- [[Troubleshooting]] - Common issues
- [[Home]] - Back to main page
