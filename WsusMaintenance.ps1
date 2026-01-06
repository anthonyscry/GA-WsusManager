<#
===============================================================================
Script: WsusMaintenance.ps1
Purpose: Monthly WSUS maintenance automation.
Overview:
  - Synchronizes WSUS, monitors download progress, and applies approvals.
  - Runs WSUS cleanup tasks and SUSDB index/stat maintenance.
  - Optionally runs an aggressive cleanup stage before the backup.
Notes:
  - Use -SkipUltimateCleanup to avoid heavy cleanup before backup.
  - Requires SQL Express instance .\SQLEXPRESS and WSUS on port 8530.
===============================================================================
Version: 2.2.0
Date: 2025-12-11
Changes:
  - Integrated ultimate cleanup steps before backup (supersession + declined purge)
  - Added opt-out switch for ultimate cleanup
  - Earlier improvements: decline/approval policy adjustments and service checks
#>

[CmdletBinding()]
param(
    # Skip the heavy "ultimate cleanup" stage before the backup if needed.
    [switch]$SkipUltimateCleanup
)

# Suppress prompts
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'

# Force output redirection to prevent pauses
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

$logFile = "C:\WSUS\Logs\WsusMaintenance_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
Start-Transcript -Path $logFile

function Write-Log($msg) { Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" }

Write-Log "Starting WSUS monthly maintenance v2.2"

# === CONNECT TO WSUS ===
Write-Log "Connecting to WSUS..."

# Check and start SQL Server Express
$sqlService = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
if (-not $sqlService) {
    Write-Error "SQL Server Express service not found. Is SQL Server installed?"
    Stop-Transcript
    exit 1
}

if ($sqlService.Status -ne "Running") {
    Write-Log "SQL Server Express is stopped. Starting service..."
    try {
        Start-Service "MSSQL`$SQLEXPRESS" -ErrorAction Stop
        Start-Sleep -Seconds 10
        Write-Log "SQL Server Express started successfully"
    } catch {
        Write-Error "Failed to start SQL Server Express: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
} else {
    Write-Log "SQL Server Express is running"
}

# Check and start WSUS Service
$wsusService = Get-Service -Name "WSUSService" -ErrorAction SilentlyContinue
if (-not $wsusService) {
    Write-Error "WSUS Service not found. Is WSUS installed?"
    Stop-Transcript
    exit 1
}

if ($wsusService.Status -ne "Running") {
    Write-Log "WSUS Service is stopped. Starting service..."
    try {
        Start-Service "WSUSService" -ErrorAction Stop
        Start-Sleep -Seconds 10
        Write-Log "WSUS Service started successfully"
    } catch {
        Write-Error "Failed to start WSUS Service: $($_.Exception.Message)"
        Stop-Transcript
        exit 1
    }
} else {
    Write-Log "WSUS Service is running"
}

try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
    Write-Log "WSUS connection successful"
    
    Start-Sleep -Seconds 2
    $subscription = $wsus.GetSubscription()
    Write-Log "Subscription object retrieved"
    
} catch {
    Write-Error "Failed to connect: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# === SYNCHRONIZE ===
Write-Log "Starting synchronization..."
try {
    $lastSync = $subscription.GetLastSynchronizationInfo()
    if ($lastSync) {
        Write-Log "Last sync: $($lastSync.StartTime) | Result: $($lastSync.Result) | New: $($lastSync.NewUpdates)"
    }
    
    $subscription.StartSynchronization()
    Write-Log "Sync triggered, waiting for it to start..."
    Start-Sleep -Seconds 15
    
    $syncIterations = 0
    $maxIterations = 120
    
    do {
        Start-Sleep -Seconds 30
        $syncStatus = $subscription.GetSynchronizationStatus()
        $syncProgress = $subscription.GetSynchronizationProgress()
        
        if ($syncStatus -eq "Running") {
            Write-Log "Syncing: $($syncProgress.Phase) | Items: $($syncProgress.ProcessedItems)/$($syncProgress.TotalItems)"
            $syncIterations++
        } elseif ($syncStatus -eq "NotProcessing") {
            Write-Log "Sync completed or not running"
            break
        } else {
            Write-Log "Sync status: $syncStatus"
            $syncIterations++
        }
        
        if ($syncIterations -ge $maxIterations) {
            Write-Warning "Sync timeout after 60 minutes"
            break
        }
        
    } while ($syncStatus -eq "Running" -or $syncIterations -lt 5)
    
    Start-Sleep -Seconds 5
    
    $finalSync = $subscription.GetLastSynchronizationInfo()
    if ($finalSync) {
        Write-Log "Sync complete: Result=$($finalSync.Result) | New=$($finalSync.NewUpdates) | Revised=$($finalSync.RevisedUpdates)"
        
        if ($finalSync.Result -ne "Succeeded") {
            Write-Warning "Sync result: $($finalSync.Result)"
            if ($finalSync.Error) {
                Write-Error "Sync error: $($finalSync.Error.Message)"
            }
        }
    } else {
        Write-Warning "Could not retrieve final sync info"
    }
} catch {
    Write-Error "Sync failed: $($_.Exception.Message)"
}

# === CONFIGURATION CHECK ===
Write-Log "Checking configuration..."

$enabledProducts = $subscription.GetUpdateCategories() | Where-Object { $_.Type -eq 'Product' }
Write-Log "Enabled products: $($enabledProducts.Count)"

if ($enabledProducts.Count -eq 0) {
    Write-Warning "No products enabled! Configure in WSUS Console."
}

Write-Log "Note: Verify classifications are enabled in WSUS Console > Options > Products and Classifications"

# === MONITOR DOWNLOADS ===
Write-Log "Monitoring downloads..."
$downloadIterations = 0
do {
    $progress = $wsus.GetContentDownloadProgress()
    if ($progress.TotalFileCount -gt 0) {
        $pct = [math]::Round(($progress.DownloadedFileCount / $progress.TotalFileCount) * 100, 1)
        Write-Log "Downloaded: $($progress.DownloadedFileCount)/$($progress.TotalFileCount) ($pct%)"
        if ($progress.DownloadedFileCount -ge $progress.TotalFileCount) { break }
    } else {
        Write-Log "No downloads queued"
        break
    }
    Start-Sleep -Seconds 30
    $downloadIterations++
} while ($downloadIterations -lt 60)

# === DECLINE UPDATES (BASED ON MICROSOFT RELEASE DATE) ===
Write-Log "Fetching updates..."
$allUpdates = @()

try {
    Write-Log "Calling GetUpdates() - this may take several minutes..."
    $getUpdatesStart = Get-Date
    
    $updateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $allUpdates = $wsus.GetUpdates($updateScope)
    
    $getUpdatesDuration = [math]::Round(((Get-Date) - $getUpdatesStart).TotalSeconds, 1)
    Write-Log "GetUpdates() completed in $getUpdatesDuration seconds"
    Write-Log "Total updates: $($allUpdates.Count)"
    
} catch [System.Net.WebException] {
    Write-Warning "GetUpdates() timed out after 180 seconds"
    Write-Warning "This indicates SUSDB needs optimization. Running cleanup first..."
    $allUpdates = @()
} catch {
    Write-Warning "Failed to fetch updates: $($_.Exception.Message)"
    $allUpdates = @()
}

# Initialize counters
$expiredCount = 0
$supersededCount = 0
$oldCount = 0
$approvedCount = 0

if ($allUpdates.Count -gt 0) {
    Write-Log "Declining updates based on Microsoft RELEASE DATE..."
    
    $expired = @($allUpdates | Where-Object { -not $_.IsDeclined -and $_.IsExpired })
    $superseded = @($allUpdates | Where-Object { -not $_.IsDeclined -and $_.IsSuperseded })
    $cutoff = (Get-Date).AddMonths(-6)
    # Use CreationDate (Microsoft's release date) not ArrivalDate (when imported to WSUS)
    $oldUpdates = @($allUpdates | Where-Object { -not $_.IsDeclined -and $_.CreationDate -lt $cutoff })

    Write-Log "Found: Expired=$($expired.Count) | Superseded=$($superseded.Count) | Old (Released >6mo ago)=$($oldUpdates.Count)"

    if ($expired.Count -gt 0) {
        $expired | ForEach-Object { 
            try { 
                $_.Decline() | Out-Null
                $expiredCount++
            } catch { 
                Write-Warning "Failed to decline expired: $($_.Title)"
            } 
        }
    }
    
    if ($superseded.Count -gt 0) {
        $superseded | ForEach-Object { 
            try { 
                $_.Decline() | Out-Null
                $supersededCount++
            } catch { 
                Write-Warning "Failed to decline superseded: $($_.Title)"
            } 
        }
    }
    
    if ($oldUpdates.Count -gt 0) {
        $oldUpdates | ForEach-Object { 
            try { 
                $_.Decline() | Out-Null
                $oldCount++
            } catch { 
                Write-Warning "Failed to decline old: $($_.Title)"
            } 
        }
    }

    Write-Log "Successfully declined: Expired=$expiredCount | Superseded=$supersededCount | Old (Released >6mo ago)=$oldCount"

    # === APPROVE UPDATES (CONSERVATIVE) ===
    Write-Log "Checking for updates to approve..."
    $targetGroup = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq "All Computers" }

    if ($targetGroup) {
        # Conservative approval criteria based on enabled classifications
        $pendingUpdates = @($allUpdates | Where-Object { 
            -not $_.IsDeclined -and 
            -not $_.IsSuperseded -and
            -not $_.IsExpired -and
            ($_.GetUpdateApprovals($targetGroup) | Where-Object { $_.Action -eq "Install" }).Count -eq 0 -and
            $_.CreationDate -gt (Get-Date).AddMonths(-6) -and  # Only recent updates (last 6 months)
            $_.Title -notlike "*Preview*" -and
            $_.Title -notlike "*Beta*" -and
            (
                $_.UpdateClassificationTitle -eq "Critical Updates" -or
                $_.UpdateClassificationTitle -eq "Security Updates" -or
                $_.UpdateClassificationTitle -eq "Update Rollups" -or
                $_.UpdateClassificationTitle -eq "Service Packs" -or
                $_.UpdateClassificationTitle -eq "Updates"
                # Excluding "Definition Updates" (too frequent) and "Upgrades" (need manual review)
            )
        })
        
        Write-Log "Pending updates meeting criteria: $($pendingUpdates.Count)"
        Write-Log "  Criteria: Critical/Security/Rollups/SPs/Updates only, <6mo old, not superseded/expired"
        Write-Log "  Excluded: Definition Updates, Upgrades, Preview/Beta updates"
        
        if ($pendingUpdates.Count -gt 0) {
            # Safety check - don't auto-approve more than 100 updates
            if ($pendingUpdates.Count -gt 100) {
                Write-Warning "Found $($pendingUpdates.Count) updates to approve - this seems high!"
                Write-Warning "SKIPPING auto-approval for safety. Review updates in WSUS Console."
                Write-Log "Top 10 pending updates:"
                $pendingUpdates | Select-Object -First 10 | ForEach-Object {
                    Write-Log "  - $($_.Title) ($($_.UpdateClassificationTitle))"
                }
            } else {
                Write-Log "Approving $($pendingUpdates.Count) updates..."
                $pendingUpdates | ForEach-Object {
                    try { 
                        $_.Approve("Install", $targetGroup) | Out-Null
                        $approvedCount++
                        if ($approvedCount % 10 -eq 0) {
                            Write-Log "  Approved: $approvedCount / $($pendingUpdates.Count)"
                        }
                    } catch { 
                        Write-Warning "Failed to approve: $($_.Title)" 
                    }
                }
                Write-Log "Successfully approved: $approvedCount updates"
            }
        } else {
            Write-Log "No updates meet approval criteria"
        }
    } else {
        Write-Warning "Target group 'All Computers' not found"
    }
} else {
    Write-Warning "No updates retrieved - skipping decline/approve operations"
    Write-Warning "Proceeding with cleanup and database maintenance to improve performance"
}

# === CLEANUP ===
# Run the built-in WSUS cleanup tasks to prune obsolete data/files.
Write-Log "Running WSUS cleanup..."
try {
    Import-Module UpdateServices -ErrorAction SilentlyContinue
    
    Write-Log "This may take 10-30 minutes for large databases..."
    $cleanupStart = Get-Date
    
    $cleanup = Invoke-WsusServerCleanup `
                         -CleanupObsoleteComputers `
                         -CleanupObsoleteUpdates `
                         -CleanupUnneededContentFiles `
                         -CompressUpdates `
                         -DeclineSupersededUpdates `
                         -DeclineExpiredUpdates `
                         -Confirm:$false
    
    $cleanupDuration = [math]::Round(((Get-Date) - $cleanupStart).TotalMinutes, 1)
    Write-Log "Cleanup completed in $cleanupDuration minutes"
    Write-Log "Results: Obsolete Updates=$($cleanup.ObsoleteUpdatesDeleted) | Computers=$($cleanup.ObsoleteComputersDeleted) | Space=$([math]::Round($cleanup.DiskSpaceFreed/1MB,2))MB"
    
    # Additional deep cleanup for declined updates
    Write-Log "Running deep cleanup of old declined update metadata..."
    $deepCleanupQuery = @"
-- Remove update status for old declined updates (keeps DB lean)
-- Using correct schema: tbProperty has CreationDate (Microsoft's release date)
-- Join through tbRevision to get to tbProperty
DECLARE @Deleted INT = 0
DECLARE @BatchSize INT = 1000

DELETE TOP (@BatchSize) usc
FROM tbUpdateStatusPerComputer usc
INNER JOIN tbRevision r ON usc.LocalUpdateID = r.LocalUpdateID
INNER JOIN tbProperty p ON r.RevisionID = p.RevisionID
WHERE r.State = 2  -- Declined state
AND p.CreationDate < DATEADD(MONTH, -6, GETDATE())  -- Microsoft released >6 months ago

SET @Deleted = @@ROWCOUNT

-- Return count of declined updates using correct join
SELECT 
    @Deleted AS StatusRecordsDeleted,
    (SELECT COUNT(*) 
     FROM tbRevision r 
     INNER JOIN tbProperty p ON r.RevisionID = p.RevisionID
     WHERE r.State = 2 
     AND p.CreationDate < DATEADD(MONTH, -6, GETDATE())) AS TotalOldDeclined
"@
    
    try {
        $deepResult = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
            -Query $deepCleanupQuery -QueryTimeout 300
        Write-Log "Removed $($deepResult.StatusRecordsDeleted) old status records"
        Write-Log "Total old declined updates (released >6mo ago): $($deepResult.TotalOldDeclined)"
        
        if ($deepResult.TotalOldDeclined -gt 5000) {
            Write-Warning "Large number of old declined updates ($($deepResult.TotalOldDeclined)) detected"
            Write-Warning "Consider running aggressive cleanup script for database optimization"
        }
    } catch {
        Write-Warning "Deep cleanup query failed: $($_.Exception.Message)"
    }
    
} catch {
    Write-Warning "Cleanup failed: $($_.Exception.Message)"
}

# === DATABASE MAINTENANCE ===
# Index optimization and stats updates to keep SUSDB responsive.
Write-Log "Database maintenance..."

# Wait for any pending WSUS operations to complete
Write-Log "Waiting 30 seconds for WSUS operations to complete..."
Start-Sleep -Seconds 30

$indexQuery = @"
SET DEADLOCK_PRIORITY LOW;
SET LOCK_TIMEOUT 300000;

DECLARE @T NVARCHAR(255), @I NVARCHAR(255), @F FLOAT, @S NVARCHAR(MAX), @E NVARCHAR(MAX)
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT OBJECT_NAME(ips.object_id), i.name, ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10 AND ips.page_count > 100 AND i.name IS NOT NULL
ORDER BY ips.avg_fragmentation_in_percent DESC

OPEN c
FETCH NEXT FROM c INTO @T, @I, @F

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @S = CASE WHEN @F > 30 
                    THEN 'ALTER INDEX ['+@I+'] ON ['+@T+'] REBUILD WITH (ONLINE = OFF, MAXDOP = 1)' 
                    ELSE 'ALTER INDEX ['+@I+'] ON ['+@T+'] REORGANIZE' 
                 END
        EXEC sp_executesql @S
    END TRY
    BEGIN CATCH
        SET @E = ERROR_MESSAGE()
        PRINT 'Error on ' + @T + '.' + @I + ': ' + @E
    END CATCH
    
    FETCH NEXT FROM c INTO @T, @I, @F
END

CLOSE c
DEALLOCATE c
"@

try {
    Write-Log "Optimizing indexes (may take 5-15 minutes)..."
    $indexStart = Get-Date
    
    $indexResult = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
        -Query $indexQuery -QueryTimeout 0 -Verbose 4>&1
    
    $indexResult | Where-Object { $_ -is [string] } | ForEach-Object {
        if ($_ -match 'Error') {
            Write-Warning $_
        }
    }
    
    $indexDuration = [math]::Round(((Get-Date) - $indexStart).TotalMinutes, 1)
    Write-Log "Index optimization complete in $indexDuration minutes"
} catch {
    Write-Warning "Index maintenance encountered errors: $($_.Exception.Message)"
    Write-Log "Continuing with remaining maintenance tasks..."
}

try {
    Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
        -Query "EXEC sp_updatestats" -QueryTimeout 0 | Out-Null
    Write-Log "Statistics updated"
} catch {
    Write-Warning "Statistics update failed: $($_.Exception.Message)"
}

# === ULTIMATE CLEANUP (SUPSESSION + DECLINED PURGE) ===
# Optional heavy cleanup before backup to reduce DB size and bloat.
if (-not $SkipUltimateCleanup) {
    Write-Log "Running ultimate cleanup steps before backup..."

    # Stop WSUS to reduce contention while manipulating SUSDB.
    if ($wsusService.Status -eq "Running") {
        Write-Log "Stopping WSUS Service for ultimate cleanup..."
        try {
            Stop-Service WSUSService -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            Write-Log "WSUS Service stopped"
        } catch {
            Write-Warning "Failed to stop WSUS Service: $($_.Exception.Message)"
        }
    }

    # Remove supersession records for declined updates.
    $cleanupDeclined = @"
SET NOCOUNT ON;
DECLARE @Deleted INT = 0

DELETE rsu
FROM tbRevisionSupersedesUpdate rsu
INNER JOIN tbRevision r ON rsu.RevisionID = r.RevisionID
WHERE r.State = 2  -- Declined

SET @Deleted = @@ROWCOUNT
SELECT @Deleted AS DeletedDeclined
"@

    try {
        $result1 = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
            -Query $cleanupDeclined -QueryTimeout 300
        Write-Log "Removed $($result1.DeletedDeclined) supersession records for declined updates"
    } catch {
        Write-Warning "Declined supersession cleanup failed: $($_.Exception.Message)"
    }

    # Remove supersession records for superseded updates in batches.
    $cleanupSuperseded = @"
SET NOCOUNT ON;
DECLARE @Deleted INT = 0
DECLARE @BatchSize INT = 10000
DECLARE @TotalDeleted INT = 0

WHILE 1 = 1
BEGIN
    DELETE TOP (@BatchSize) rsu
    FROM tbRevisionSupersedesUpdate rsu
    INNER JOIN tbRevision r ON rsu.RevisionID = r.RevisionID
    WHERE r.State = 3  -- Superseded

    SET @Deleted = @@ROWCOUNT
    SET @TotalDeleted = @TotalDeleted + @Deleted

    IF @Deleted = 0 BREAK

    IF @TotalDeleted % 50000 = 0
        PRINT 'Deleted ' + CAST(@TotalDeleted AS VARCHAR) + ' supersession records...'

    WAITFOR DELAY '00:00:01'
END

SELECT @TotalDeleted AS DeletedSuperseded
"@

    try {
        $startTime = Get-Date
        $result2 = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
            -Query $cleanupSuperseded -QueryTimeout 0 -Verbose 4>&1

        $result2 | Where-Object { $_ -is [string] } | ForEach-Object {
            Write-Log $_
        }

        $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        $deleted = ($result2 | Where-Object { $_.DeletedSuperseded -ne $null }).DeletedSuperseded
        Write-Log "Removed $deleted supersession records in $duration minutes"
    } catch {
        Write-Warning "Superseded supersession cleanup failed: $($_.Exception.Message)"
    }

    # Delete declined updates using the official spDeleteUpdate procedure.
    try {
        if (-not $allUpdates -or $allUpdates.Count -eq 0) {
            Write-Log "Reloading updates for declined purge..."
            $allUpdates = $wsus.GetUpdates()
        }

        $declinedIDs = @($allUpdates | Where-Object { $_.IsDeclined } |
            Select-Object -ExpandProperty Id |
            ForEach-Object { $_.UpdateId })

        if ($declinedIDs.Count -gt 0) {
            Write-Log "Deleting $($declinedIDs.Count) declined updates from SUSDB..."

            $batchSize = 100
            $totalDeleted = 0
            $totalBatches = [math]::Ceiling($declinedIDs.Count / $batchSize)
            $currentBatch = 0

            for ($i = 0; $i -lt $declinedIDs.Count; $i += $batchSize) {
                $currentBatch++
                $batch = $declinedIDs | Select-Object -Skip $i -First $batchSize

                foreach ($updateId in $batch) {
                    $deleteQuery = @"
DECLARE @LocalUpdateID int
SELECT @LocalUpdateID = LocalUpdateID FROM tbUpdate WHERE UpdateID = '$updateId'
IF @LocalUpdateID IS NOT NULL
    EXEC spDeleteUpdate @localUpdateID = @LocalUpdateID
"@

                    try {
                        Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
                            -Query $deleteQuery -QueryTimeout 300 -ErrorAction SilentlyContinue | Out-Null
                        $totalDeleted++
                    } catch {
                        # Continue on errors to avoid aborting the batch.
                    }
                }

                if ($currentBatch % 5 -eq 0) {
                    $percentComplete = [math]::Round(($currentBatch / $totalBatches) * 100, 1)
                    Write-Log "Declined purge progress: $currentBatch/$totalBatches batches ($percentComplete%) - Deleted: $totalDeleted"
                }
            }

            Write-Log "Declined update purge complete: $totalDeleted deleted"
        } else {
            Write-Log "No declined updates found to delete"
        }
    } catch {
        Write-Warning "Declined update purge failed: $($_.Exception.Message)"
    }

    # Optional shrink after heavy cleanup to reclaim space (can be slow).
    try {
        Write-Log "Shrinking SUSDB after cleanup (this may take a while)..."
        Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
            -Query "DBCC SHRINKDATABASE (SUSDB, 10)" -QueryTimeout 0 | Out-Null
        Write-Log "SUSDB shrink completed"
    } catch {
        Write-Warning "SUSDB shrink failed: $($_.Exception.Message)"
    }

    # Start WSUS service back up after database maintenance.
    $wsusService = Get-Service -Name "WSUSService" -ErrorAction SilentlyContinue
    if ($wsusService -and $wsusService.Status -ne "Running") {
        Write-Log "Starting WSUS Service..."
        try {
            Start-Service WSUSService -ErrorAction Stop
            Start-Sleep -Seconds 5
            Write-Log "WSUS Service started"
        } catch {
            Write-Warning "Failed to start WSUS Service: $($_.Exception.Message)"
        }
    }
} else {
    Write-Log "Skipping ultimate cleanup before backup (SkipUltimateCleanup specified)."
}

# === BACKUP ===
$backupFolder = "C:\WSUS"
$backupFile = Join-Path $backupFolder "SUSDB_$(Get-Date -Format 'yyyyMMdd').bak"

if (Test-Path $backupFile) {
    $counter = 1
    while (Test-Path "$backupFolder\SUSDB_$(Get-Date -Format 'yyyyMMdd')_$counter.bak") { $counter++ }
    $backupFile = "$backupFolder\SUSDB_$(Get-Date -Format 'yyyyMMdd')_$counter.bak"
}

Write-Log "Starting backup: $backupFile"
$backupStart = Get-Date

try {
    $dbSize = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database master `
        -Query "SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')" `
        -QueryTimeout 30
    Write-Log "Database size: $($dbSize.SizeGB) GB"
    
    Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
        -Query "BACKUP DATABASE SUSDB TO DISK=N'$backupFile' WITH INIT, STATS=10" `
        -QueryTimeout 0 | Out-Null
    
    $duration = [math]::Round(((Get-Date) - $backupStart).TotalMinutes, 2)
    $size = [math]::Round((Get-Item $backupFile).Length / 1MB, 2)
    Write-Log "Backup complete: ${size}MB in ${duration} minutes"
} catch {
    Write-Error "Backup failed: $($_.Exception.Message)"
}

# === CLEANUP OLD BACKUPS ===
Write-Log "Cleaning old backups (90-day retention)..."
$cutoffDate = (Get-Date).AddDays(-90)
$oldBackups = Get-ChildItem -Path $backupFolder -Filter "SUSDB*.bak" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }

if ($oldBackups) {
    $spaceFreed = [math]::Round(($oldBackups | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $oldBackups | ForEach-Object {
        Write-Log "  Deleting: $($_.Name) ($([math]::Round($_.Length/1MB,2))MB)"
        Remove-Item $_.FullName -Force -Confirm:$false
    }
    Write-Log "Freed: ${spaceFreed}MB"
} else {
    Write-Log "No old backups to delete"
}

$currentBackups = Get-ChildItem -Path $backupFolder -Filter "SUSDB*.bak" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($currentBackups) {
    $totalSize = [math]::Round(($currentBackups | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    Write-Log "Current backups: $($currentBackups.Count) files | ${totalSize}MB total"
}

# === SUMMARY ===
Write-Output "`n============================================================"
Write-Log "MAINTENANCE SUMMARY"
Write-Output "------------------------------------------------------------"
Write-Log "Declined: Expired=$expiredCount | Superseded=$supersededCount | Old (Released >6mo ago)=$oldCount"
Write-Log "Approved: $approvedCount updates (excluding Definition Updates)"

try {
    $dbSize = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database master `
        -Query "SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')" `
        -QueryTimeout 30
    Write-Log "SUSDB size: $($dbSize.SizeGB) GB"
    if ($dbSize.SizeGB -ge 9.0) { Write-Warning "Database approaching 10GB limit!" }
} catch {}

Write-Log "Backup: $backupFile"

if ($allUpdates.Count -eq 0) {
    Write-Output "------------------------------------------------------------"
    Write-Warning "GetUpdates() timed out - consider running this script again"
    Write-Warning "after the cleanup and index optimization have improved DB performance"
}

Write-Output "============================================================`n"

# === COPY TO LAB SERVER ===
Write-Log "Copying to lab server..."
$robocopyLogDir = "C:\Logs"
if (-not (Test-Path $robocopyLogDir)) {
    New-Item -Path $robocopyLogDir -ItemType Directory -Force | Out-Null
    Write-Log "Created log directory: $robocopyLogDir"
}
$robocopyLog = "C:\Logs\Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
robocopy "C:\WSUS" "\\lab-hyperv\d\WSUS-Exports" /MIR /MT:16 /R:2 /W:5 /LOG:$robocopyLog /TEE

Write-Log "Maintenance complete"
Stop-Transcript
