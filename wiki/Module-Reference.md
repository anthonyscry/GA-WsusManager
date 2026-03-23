# Module Reference

Complete reference for all PowerShell modules in WSUS Manager v4.0.4.

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
11. [AsyncHelpers](#asynchelpers)
12. [WsusDialogs](#wsusdialogs)
13. [WsusOperationRunner](#wsusoperationrunner)
14. [WsusHistory](#wsushistory)
15. [WsusNotification](#wsusnotification)
16. [WsusTrending](#wsustrending)

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

#### Get-WsusHealthScore

*Added in v4.0.* Calculates a 0-100 composite health score for the WSUS server using weighted components.

```powershell
$score = Get-WsusHealthScore -ContentPath "C:\WSUS"
$score.Score       # 0-100, or -1 if all sources failed
$score.Grade       # "Green", "Yellow", "Red", or "Unknown"
$score.AllFailed   # true if every data source errored
$score.Components  # Breakdown by category
$score.Components.Services      # 0-30
$score.Components.DatabaseSize  # 0-20
$score.Components.SyncRecency   # 0-20
$score.Components.DiskSpace     # 0-20
$score.Components.LastOperation # 0-10
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| SqlInstance | string | .\SQLEXPRESS | SQL Server instance |
| ContentPath | string | C:\WSUS | WSUS content path for disk check |
| HistoryPath | string | %APPDATA%\WsusManager\history.json | Path to operation history JSON file |

**Weight allocation:**

| Component | Max Points | Scoring |
|-----------|-----------|---------|
| Services | 30 | 3 running = 30, 2 = 20, 1 = 10, 0 = 0 |
| DatabaseSize | 20 | < 7 GB = 20, < 9 GB = 10, >= 9 GB = 0 |
| SyncRecency | 20 | <= 7 days = 20, <= 30 days = 10, > 30 = 0 |
| DiskSpace | 20 | > 50 GB = 20, >= 10 GB = 10, < 10 GB = 0 |
| LastOperation | 10 | Pass = 10, Fail = 0, No history = 5 |

**Grade thresholds:**

| Grade | Condition |
|-------|-----------|
| Green | Score >= 80 |
| Yellow | Score 50-79 |
| Red | Score < 50 |
| Unknown | All data sources failed |

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

#### Get-WsusGuiSetting

*Added in v3.8.9.* Gets a GUI configuration setting using dot notation.

```powershell
Get-WsusGuiSetting -Setting "Dialogs.Medium"
# Returns @{ Width = 480; Height = 360 }

Get-WsusGuiSetting -Setting "Timers.DashboardRefresh"
# Returns 30000
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Setting | string | Setting path using dot notation (e.g., "Dialogs.Medium", "Timers.DashboardRefresh") |

#### Get-WsusRetrySetting

*Added in v3.8.9.* Gets a retry configuration setting.

```powershell
Get-WsusRetrySetting -Setting "DbShrinkAttempts"
# Returns 3
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Setting | string | One of: DbShrinkAttempts, DbShrinkDelaySeconds, ServiceStartAttempts, ServiceStartDelaySeconds, SyncProgressDelaySeconds, SyncWaitDelaySeconds, DefaultDelaySeconds, ShortDelaySeconds, LongDelaySeconds |

#### Get-WsusDialogSize

*Added in v3.8.9.* Gets dialog dimensions for a specific dialog type.

```powershell
$size = Get-WsusDialogSize -Type "Medium"
$size.Width    # 480
$size.Height   # 360
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Type | string | One of: Small, Medium, Large, ExtraLarge, Schedule |

**Dialog size presets:**

| Type | Width | Height |
|------|-------|--------|
| Small | 480 | 280 |
| Medium | 480 | 360 |
| Large | 480 | 460 |
| ExtraLarge | 520 | 580 |
| Schedule | 480 | 560 |

#### Get-WsusTimerInterval

*Added in v3.8.9.* Gets a timer interval in milliseconds.

```powershell
Get-WsusTimerInterval -Timer "DashboardRefresh"
# Returns 30000
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Timer | string | One of: DashboardRefresh, UiUpdate, OpCheck, KeystrokeFlush, ProcessWait |

**Timer presets:**

| Timer | Interval |
|-------|----------|
| DashboardRefresh | 30000 ms (30s) |
| UiUpdate | 250 ms |
| OpCheck | 500 ms |
| KeystrokeFlush | 2000 ms (2s) |

#### Get-WsusHealthWeights

*Added in v4.0.* Returns the component weights used by `Get-WsusHealthScore`. Provides a single source of truth for health scoring.

```powershell
$weights = Get-WsusHealthWeights
$weights.Services       # 30
$weights.DatabaseSize   # 20
$weights.SyncRecency    # 20
$weights.DiskSpace      # 20
$weights.LastOperation  # 10
```

Returns a hashtable with keys: `Services`, `DatabaseSize`, `SyncRecency`, `DiskSpace`, `LastOperation`.

#### Get-WsusOperationTimeout

*Added in v4.0.* Returns the timeout in minutes for a given operation type. Used by the GUI and CLI to enforce per-operation time limits.

```powershell
$mins = Get-WsusOperationTimeout -OperationType 'Sync'
# Returns 120
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| OperationType | string | Default | One of: Cleanup, Sync, Install, Export, Import, Diagnostics, Health, Repair, Default |

**Timeout values:**

| Operation | Minutes |
|-----------|---------|
| Cleanup | 60 |
| Sync | 120 |
| Install | 60 |
| Export | 90 |
| Import | 90 |
| Diagnostics | 30 |
| Health | 30 |
| Repair | 45 |
| Default | 30 |

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

Auto-detection, recovery, and dashboard data functions.

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

#### Get-WsusDashboardServiceStatus

*Added in v4.0.* Gets WSUS-related service running status. Checks SQL Express, WSUS, and IIS services.

```powershell
$svc = Get-WsusDashboardServiceStatus
$svc.Running   # Number of services running (0-3)
$svc.Names     # Array of running service short names, e.g. @("SQL","WSUS","IIS")
```

#### Get-WsusDashboardDiskFreeGB

*Added in v4.0.* Gets free disk space on C: in GB.

```powershell
$freeGB = Get-WsusDashboardDiskFreeGB
# Returns [double] free GB, or 0 on error
```

#### Get-WsusDashboardDatabaseSizeGB

*Added in v4.0.* Gets SUSDB database size in GB. Returns -1 if SQL is offline or an error occurs.

```powershell
$sizeGB = Get-WsusDashboardDatabaseSizeGB -SqlInstance ".\SQLEXPRESS"
# Returns [double] size in GB, or -1 on error
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| SqlInstance | string | .\SQLEXPRESS | SQL Server instance |

#### Get-WsusDashboardTaskStatus

*Added in v4.0.* Gets the Windows Scheduled Task state for WSUS Maintenance.

```powershell
$state = Get-WsusDashboardTaskStatus
# Returns [string] e.g. "Ready", "Running", or "Not Set"
```

#### Test-WsusDashboardInternetConnection

*Added in v4.0.* Non-blocking internet connectivity check using .NET Ping with a 500ms timeout. Prevents UI freezing on slow or offline networks.

```powershell
$online = Test-WsusDashboardInternetConnection
# Returns [bool]
```

#### Get-WsusDashboardData

*Added in v4.0.* Collects all dashboard data in a single call. Designed to be safe for background runspace execution.

```powershell
$data = Get-WsusDashboardData -SqlInstance ".\SQLEXPRESS" -ModulePath $PSScriptRoot
$data.Services        # @{Running=int; Names=string[]}
$data.DiskFreeGB      # double
$data.DatabaseSizeGB  # double (or -1)
$data.TaskStatus      # string
$data.IsOnline        # bool
$data.CollectedAt     # DateTime
$data.Error           # string or $null
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| SqlInstance | string | .\SQLEXPRESS | SQL Server instance |
| ModulePath | string | "" | Path to Modules directory (pass explicitly from runspace) |

#### Get-WsusDashboardCachedData

*Added in v4.0.* Returns cached dashboard data if still fresh (within the 30-second TTL), otherwise returns `$null`.

```powershell
$cached = Get-WsusDashboardCachedData
if ($null -ne $cached) {
    # Use cached data
} else {
    # Collect fresh data
}
```

#### Set-WsusDashboardCache

*Added in v4.0.* Updates the dashboard data cache with fresh data. Resets the failure counter on success; increments it if `$Data` is `$null` or contains an error.

```powershell
Set-WsusDashboardCache -Data $freshData
```

#### Test-WsusDashboardDataUnavailable

*Added in v4.0.* Returns `$true` if the dashboard has failed 10 or more consecutive times, indicating data collection is persistently broken.

```powershell
if (Test-WsusDashboardDataUnavailable) {
    # Show "Data unavailable" in dashboard cards
}
```

---

## AsyncHelpers

Async helpers module for PowerShell WPF GUI applications. Provides non-blocking background operations using runspace pools.

**File:** `Modules\AsyncHelpers.psm1`

### Functions

#### Initialize-AsyncRunspacePool

Creates a shared runspace pool for background operations. Call this once during application startup. The pool uses STA apartment state and reuses threads.

```powershell
Initialize-AsyncRunspacePool -MaxRunspaces 2
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| MaxRunspaces | int | 4 | Maximum number of concurrent runspaces |

Returns the `[System.Management.Automation.Runspaces.RunspacePool]` object.

#### Close-AsyncRunspacePool

Closes and disposes the shared runspace pool. Should be called during application shutdown to clean up resources.

```powershell
Close-AsyncRunspacePool
```

#### Invoke-Async

Invokes a script block asynchronously using the runspace pool. Auto-initializes the pool if not already open. Returns an async handle object for tracking the operation.

```powershell
$handle = Invoke-Async -ScriptBlock { Get-Process } -OnComplete {
    param($result)
    Write-Host "Got $($result.Count) processes"
}
```

| Parameter | Type | Description |
|-----------|------|-------------|
| ScriptBlock | scriptblock | The script block to execute asynchronously |
| ArgumentList | object[] | Arguments to pass to the script block |
| OnComplete | scriptblock | Optional callback executed when the operation completes; receives the result |

Returns a `PSCustomObject` with properties:
| Property | Type | Description |
|----------|------|-------------|
| PowerShell | PowerShell | The PowerShell instance |
| Handle | IAsyncResult | The async operation handle |
| OnComplete | scriptblock | The completion callback |
| StartTime | DateTime | When the operation was started |

#### Wait-Async

Blocks until an async operation completes and returns the result. Executes the OnComplete callback if one was provided. Disposes the PowerShell instance after completion.

```powershell
$handle = Invoke-Async -ScriptBlock { Get-Service }
$services = Wait-Async -AsyncHandle $handle -Timeout 5000
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| AsyncHandle | PSCustomObject | - | The handle returned by Invoke-Async |
| Timeout | int | -1 | Maximum wait time in milliseconds (-1 = infinite) |

#### Test-AsyncComplete

Non-blocking check for async operation completion status.

```powershell
if (Test-AsyncComplete -AsyncHandle $handle) {
    $result = Wait-Async -AsyncHandle $handle
}
```

| Parameter | Type | Description |
|-----------|------|-------------|
| AsyncHandle | PSCustomObject | The handle returned by Invoke-Async |

Returns `[bool]` -- `$true` if the operation has completed.

#### Stop-Async

Cancels a running async operation and cleans up resources. Safe to call on already-completed operations.

```powershell
Stop-Async -AsyncHandle $handle
```

| Parameter | Type | Description |
|-----------|------|-------------|
| AsyncHandle | PSCustomObject | The handle returned by Invoke-Async |

#### Invoke-UIThread

Safely executes code on the WPF dispatcher thread, which is required for all UI updates from background threads. If already on the UI thread, executes directly. Supports synchronous and asynchronous dispatch.

```powershell
Invoke-UIThread -Window $mainWindow -Action {
    $txtStatus.Text = "Operation complete"
}

# Fire-and-forget (async)
Invoke-UIThread -Window $mainWindow -Action { $progressBar.Value = 50 } -Async
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Window | System.Windows.Window | The WPF Window whose dispatcher to use |
| Action | scriptblock | The script block to execute on the UI thread |
| Async | switch | If set, invokes asynchronously (fire-and-forget) |

#### Start-BackgroundOperation

Runs a script block in the background with safe UI completion callbacks. Uses a DispatcherTimer to poll for completion without blocking the UI thread.

```powershell
$op = Start-BackgroundOperation -Window $window -ScriptBlock {
    for ($i = 1; $i -le 100; $i++) {
        Start-Sleep -Milliseconds 50
        $i
    }
} -OnComplete {
    param($result)
    $txtStatus.Text = "Done!"
} -OnError {
    param($err)
    $txtStatus.Text = "Error: $err"
}

# Returns @{ Handle = $asyncHandle; Timer = $dispatcherTimer }
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Window | System.Windows.Window | The WPF Window for dispatcher access |
| ScriptBlock | scriptblock | The script block to execute in the background |
| OnProgress | scriptblock | (Reserved for future use) Called to update UI with progress |
| OnComplete | scriptblock | Called when operation completes; receives result |
| OnError | scriptblock | Called if an error occurs; receives error |

Returns a hashtable with `Handle` (the async handle) and `Timer` (the DispatcherTimer polling for completion).

---

## WsusDialogs

*Added in v4.0.* Dialog factory module for creating consistently styled WPF dialog windows. Eliminates the need to repeat ~40 lines of dark-theme boilerplate for every dialog.

**File:** `Modules\WsusDialogs.psm1`

**Color palette:**

| Element | Hex |
|---------|-----|
| Background (dark) | #0D1117 |
| Card/input bg | #21262D |
| Primary text | #E6EDF3 |
| Secondary text | #8B949E |
| Blue accent | #58A6FF |
| Border | #30363D |

### Functions

#### New-WsusDialog

Creates a standard dark-themed WPF dialog window shell with ESC-to-close behavior. The window is NOT shown -- the caller must call `ShowDialog()` when ready.

```powershell
$d = New-WsusDialog -Title "Confirm Action" -Width 480 -Height 240 -Owner $mainWindow
$d.ContentPanel.Children.Add((New-WsusDialogLabel -Text "Are you sure?"))
$d.Window.ShowDialog()
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Title | string | - | Text displayed in the title bar (required) |
| Width | int | 480 | Dialog width in pixels |
| Height | int | 360 | Dialog height in pixels |
| Owner | Window | $null | Optional parent window; centers over owner when set |
| AutomationId | string | "" | Optional automation identifier for UI testing |

Returns a `PSCustomObject`:
| Property | Type | Description |
|----------|------|-------------|
| Window | System.Windows.Window | The dialog window object |
| ContentPanel | System.Windows.Controls.StackPanel | Add child controls here |

#### New-WsusFolderBrowser

Creates a labelled folder-browse row with a TextBox and a Browse button. Clicking Browse opens a FolderBrowserDialog and populates the TextBox with the selected path.

```powershell
$fb = New-WsusFolderBrowser -LabelText "Export Path:" -InitialPath "C:\WSUS"
$dialog.ContentPanel.Children.Add($fb.Label)
$dialog.ContentPanel.Children.Add($fb.Panel)
# After ShowDialog: $selectedPath = $fb.TextBox.Text
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| LabelText | string | "Path:" | Label text displayed above the browse row |
| InitialPath | string | "" | Optional initial value for the TextBox |
| Owner | Window | $null | Optional parent window handle for the FolderBrowserDialog |
| AutomationId | string | "" | Optional automation identifier for UI testing |

Returns a `PSCustomObject`:
| Property | Type | Description |
|----------|------|-------------|
| Panel | DockPanel | The DockPanel container (add to a parent) |
| TextBox | TextBox | Read `.Text` for the selected path |
| Label | TextBlock | The label above the browse row |

#### New-WsusDialogLabel

Creates a styled TextBlock label for use inside WSUS dialogs.

```powershell
$lbl = New-WsusDialogLabel -Text "Export path:" -IsSecondary $true
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Text | string | - | Label content (required) |
| IsSecondary | bool | $false | When $true, uses muted text color (#8B949E) |
| Margin | string | "0,0,0,6" | Thickness string (CSS shorthand) |
| AutomationId | string | "" | Optional automation identifier |

Returns a `System.Windows.Controls.TextBlock`.

#### New-WsusDialogButton

Creates a styled Button for use inside WSUS dialogs.

```powershell
$okBtn  = New-WsusDialogButton -Text "OK" -IsPrimary $true
$canBtn = New-WsusDialogButton -Text "Cancel" -Margin "8,0,0,0"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Text | string | - | Button label (required) |
| IsPrimary | bool | $false | When $true, uses blue accent background |
| Margin | string | "0" | Thickness string |
| AutomationId | string | "" | Optional automation identifier |

Returns a `System.Windows.Controls.Button`.

#### New-WsusDialogTextBox

Creates a dark-styled TextBox for use inside WSUS dialogs.

```powershell
$tb = New-WsusDialogTextBox -InitialText "C:\WSUS"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| InitialText | string | "" | Starting text value |
| Padding | string | "6,4" | Internal padding |
| AutomationId | string | "" | Optional automation identifier |

Returns a `System.Windows.Controls.TextBox`.

---

## WsusOperationRunner

*Added in v4.0.* Unified operation lifecycle module for the WSUS Manager GUI. Extracts the shared process creation, button state management, event wiring, timeout watchdog, and cleanup logic that was previously duplicated across operation handlers.

**File:** `Modules\WsusOperationRunner.psm1`

### Functions

#### Start-WsusOperation

Starts a WSUS CLI operation as a child process with full lifecycle management. Handles: disabling buttons, starting the process, piping output to the log panel, timeout watchdog, re-enabling buttons on completion, and notification.

Supports two display modes:
- **Embedded** (default) -- captures stdout/stderr into the GUI log panel TextBox
- **Terminal** -- launches a visible PowerShell console window

```powershell
$ctx = @{
    Window            = $window
    Controls          = $controls
    OperationButtons  = $script:OperationButtons
    OperationInputs   = $script:OperationInputs
    ScriptRoot        = $PSScriptRoot
    SetOperationRunning = { param($v) $script:OperationRunning = $v }
}
Start-WsusOperation -Command "& '$mgmt' -Health" -Title "Diagnostics" -Context $ctx
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Command | string | - | PowerShell command string to execute (required) |
| Title | string | - | Human-readable name for status bar and log (required) |
| Context | hashtable | - | GUI state references (required, see below) |
| Mode | string | "Embedded" | "Embedded" or "Terminal" |
| TimeoutMinutes | int | 30 | Kill process after this many minutes; 0 to disable |
| OnComplete | scriptblock | $null | Called when operation finishes; receives [bool] success |

**Context hashtable keys:**
| Key | Type | Description |
|-----|------|-------------|
| Window | Window | The main WPF window |
| Controls | hashtable | Named controls dictionary |
| OperationButtons | string[] | Button names to disable during operation |
| OperationInputs | string[] | Input field names to disable |
| ScriptRoot | string | Working directory for child process |
| SetOperationRunning | scriptblock | Called with $true/$false to set the flag |
| UpdateButtonState | scriptblock | (Optional) Called after completion to respect WSUS install state |

#### Stop-WsusOperation

Cancels the currently running WSUS operation. Kills the process and its child tree, then stops all runner-owned timers. Safe to call when no process is running.

```powershell
Stop-WsusOperation -Process $currentProcess
```

| Parameter | Type | Description |
|-----------|------|-------------|
| Process | System.Diagnostics.Process | The process to terminate; $null is safe |

#### Complete-WsusOperation

Internal cleanup called when a WSUS operation process exits. Stops timers, unregisters events, resets GUI state (buttons, status bar, cancel button), and optionally invokes a completion callback.

```powershell
Complete-WsusOperation -Context $ctx -Title "Health Check" -Success $true
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Context | hashtable | - | Same hashtable passed to Start-WsusOperation (required) |
| Title | string | - | Display name for the operation (required) |
| Success | bool | $true | Whether the operation completed successfully |
| OnComplete | scriptblock | $null | Optional callback; receives [bool] success |

#### Find-WsusScript

Locates a WSUS CLI script by searching common paths relative to a base directory. Checks `$ScriptRoot\$ScriptName` first, then `$ScriptRoot\Scripts\$ScriptName`. Returns `$null` if not found.

```powershell
$path = Find-WsusScript -ScriptName "Invoke-WsusManagement.ps1" -ScriptRoot $PSScriptRoot
if ($null -eq $path) { Write-Error "Script not found" }
```

| Parameter | Type | Description |
|-----------|------|-------------|
| ScriptName | string | Filename of the script, e.g. "Invoke-WsusManagement.ps1" (required) |
| ScriptRoot | string | Base directory to search from (required) |

Returns `[string]` path to the script, or `$null` if not found.

---

## WsusHistory

*Added in v4.0.* Operation history module for tracking WSUS operations. Provides persistent JSON-based history stored at `%APPDATA%\WsusManager\history.json`, capped at 100 entries, with file-lock retry and corrupt JSON recovery.

**File:** `Modules\WsusHistory.psm1`

### Functions

#### Write-WsusOperationHistory

Records a WSUS operation result to the persistent history log. Prepends the new entry and trims to 100 entries. Retries up to 3 times if the file is locked. Write failures are logged as warnings and do not throw.

```powershell
$elapsed = New-TimeSpan -Seconds 42
Write-WsusOperationHistory -OperationType "Cleanup" -Duration $elapsed -Result "Pass" -Summary "Removed 312 updates"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| OperationType | string | - | Category: "Diagnostics", "Cleanup", "OnlineSync", "Export", "Import", "Install" (required) |
| Duration | TimeSpan | - | How long the operation took (required) |
| Result | string | - | "Pass" or "Fail" (required) |
| Summary | string | "" | Short description of what happened |
| SqlInstance | string | .\SQLEXPRESS | SQL instance for context |

**History entry format (JSON):**

```json
{
    "Timestamp": "2026-03-23T14:30:00.0000000-07:00",
    "OperationType": "Cleanup",
    "DurationSeconds": 42.0,
    "Result": "Pass",
    "Summary": "Removed 312 updates",
    "SqlInstance": ".\\SQLEXPRESS"
}
```

#### Get-WsusOperationHistory

Retrieves WSUS operation history entries sorted newest first. Returns an empty array when no history exists or on error.

```powershell
# Get last 10 failed cleanups
Get-WsusOperationHistory -Count 10 -OperationType "Cleanup" -ResultFilter "Fail"

# Get all history (up to 50)
Get-WsusOperationHistory
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Count | int | 50 | Maximum number of entries to return |
| OperationType | string | "" | Filter by operation type (empty = all) |
| ResultFilter | string | "All" | "Pass", "Fail", or "All" |

#### Clear-WsusOperationHistory

Removes all stored WSUS operation history by deleting the `history.json` file.

```powershell
$success = Clear-WsusOperationHistory
# Returns [bool] $true on success or if file did not exist
```

---

## WsusNotification

*Added in v4.0.* Completion notification module with 3-tier fallback: Windows 10 toast notification, system tray balloon tip, or log-only output.

**File:** `Modules\WsusNotification.psm1`

### Functions

#### Show-WsusNotification

Shows a notification when a WSUS operation completes. Tries three methods in order:

1. **Windows 10+ toast** -- uses `Windows.UI.Notifications.ToastNotificationManager`
2. **Balloon tip** -- uses `System.Windows.Forms.NotifyIcon` (older Windows)
3. **Log-only** -- writes to verbose output and host

Optionally plays a system beep: `Asterisk` for Pass, `Exclamation` for Fail.

```powershell
Show-WsusNotification -Title "WSUS Manager - Sync Complete" -Message "Sync finished successfully." -Result "Pass"

# With duration and beep
$elapsed = New-TimeSpan -Minutes 4 -Seconds 23
Show-WsusNotification -Title "WSUS Manager - Cleanup" -Message "Deep cleanup finished." -Result "Pass" -Duration $elapsed -EnableBeep
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Title | string | - | Notification title (required) |
| Message | string | - | Notification body (required) |
| Result | string | "Pass" | "Pass" or "Fail" -- determines icon and beep |
| Duration | TimeSpan | $null | Optional duration appended to message |
| EnableBeep | switch | $false | Play a system sound based on result |
| AppId | string | "WSUS Manager" | AppId for toast notification |

#### New-WsusNotificationIcon

Creates a NotifyIcon instance for system tray balloon tip notifications. Used internally by `Show-WsusNotification` as a fallback.

```powershell
$icon = New-WsusNotificationIcon -IconPath "C:\WSUS\wsus-icon.ico"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| IconPath | string | "" | Path to a .ico file; uses default system icon if empty or missing |

Returns a `System.Windows.Forms.NotifyIcon`, or `$null` on failure.

#### Remove-WsusNotificationIcon

Disposes a NotifyIcon instance. Safe to call with `$null`.

```powershell
Remove-WsusNotificationIcon -NotifyIcon $icon
```

---

## WsusTrending

*Added in v4.0.* Database size trending module with linear regression analysis. Tracks daily SUSDB snapshots in `%APPDATA%\WsusManager\trends.json` and estimates days until the SQL Express 10 GB limit is reached.

**File:** `Modules\WsusTrending.psm1`

### Functions

#### Add-WsusTrendSnapshot

Records a daily database size snapshot for trend analysis. If an entry for today already exists, it is updated. History is automatically trimmed to the most recent 90 days. Oversized trend files (>1 MB) are automatically reset.

```powershell
Add-WsusTrendSnapshot -DatabaseSizeGB 6.2
```

| Parameter | Type | Description |
|-----------|------|-------------|
| DatabaseSizeGB | double | Current database size in gigabytes (required) |

#### Get-WsusTrendSummary

Calculates DB size trend and days-until-full estimate using linear regression over the last 30 days of data points. Requires at least 3 data points for meaningful results.

```powershell
$summary = Get-WsusTrendSummary
$summary.CurrentSizeGB   # 6.2
$summary.GrowthPerMonth  # 0.3
$summary.DaysUntilFull   # 380 (or -1 if unknown/shrinking)
$summary.TrendText       # "6.2 GB +0.3/mo"
$summary.AlertLevel      # "None", "Warning", or "Critical"
$summary.DataPoints      # 45
$summary.Status          # "OK" or "Collecting data..."
```

Returns a hashtable:
| Key | Type | Description |
|-----|------|-------------|
| CurrentSizeGB | double | Latest recorded database size |
| GrowthPerMonth | double | Estimated GB growth per 30-day period |
| DaysUntilFull | int | Estimated days until 10 GB limit; -1 = unknown or shrinking |
| TrendText | string | Human-readable summary, e.g. "6.2 GB +0.3/mo" |
| AlertLevel | string | "None", "Warning" (< 180 days), or "Critical" (< 90 days) |
| DataPoints | int | Number of stored snapshots |
| Status | string | "OK" or "Collecting data..." (< 3 points) |

#### Clear-WsusTrendData

Removes the `trends.json` file, resetting all stored trend history. Safe to call even if the file does not exist. Supports `-WhatIf`.

```powershell
Clear-WsusTrendData
```

---

## Next Steps

- [[Developer Guide]] - How to extend modules
- [[Troubleshooting]] - Common issues
- [[Home]] - Back to main page
