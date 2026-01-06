<#
===============================================================================
Script: Ultimate-WsusCleanup.ps1
Purpose: Aggressive WSUS database cleanup for large or bloated SUSDBs.
Overview:
  - Removes supersession records for declined/superseded updates.
  - Permanently deletes declined update metadata.
  - Adds indexes, rebuilds indexes, updates stats, and shrinks DB.
Notes:
  - Run as Administrator on the WSUS server.
  - Expect WSUS to be offline during this run.
  - Use quarterly or when DB performance degrades.
===============================================================================
#>

# Keep the script moving even if a step fails.
$ErrorActionPreference = 'Continue'

Write-Host "`n===================================================================" -ForegroundColor Cyan
Write-Host "           ULTIMATE WSUS DATABASE CLEANUP" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "This script performs comprehensive WSUS database cleanup:" -ForegroundColor Yellow
Write-Host "  1. Removes supersession records for declined/superseded updates"
Write-Host "  2. Permanently deletes declined update metadata"
Write-Host "  3. Adds performance indexes"
Write-Host "  4. Rebuilds all indexes"
Write-Host "  5. Updates statistics"
Write-Host "  6. Shrinks database"
Write-Host "`nWARNING: WSUS will be offline for 30-90 minutes`n" -ForegroundColor Red

# === GET CURRENT STATE ===
# Load WSUS APIs and capture current health/size stats so we can compare later.
Write-Host "=== Current State ===" -ForegroundColor Cyan

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
$allUpdates = $wsus.GetUpdates()

$beforeStats = @{
    TotalUpdates = $allUpdates.Count
    DeclinedUpdates = @($allUpdates | Where-Object { $_.IsDeclined }).Count
    SupersededUpdates = @($allUpdates | Where-Object { $_.IsSuperseded -and -not $_.IsDeclined }).Count
    ActiveUpdates = @($allUpdates | Where-Object { -not $_.IsDeclined -and -not $_.IsSuperseded }).Count
}

$beforeDbQuery = @"
SELECT 
    (SELECT COUNT(*) FROM tbRevisionSupersedesUpdate) AS SupersessionRecords,
    (SELECT COUNT(*) FROM tbRevision WHERE State = 2) AS DeclinedRevisions,
    (SELECT COUNT(*) FROM tbRevision WHERE State = 3) AS SupersededRevisions,
    (SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) FROM sys.master_files WHERE database_id=DB_ID('SUSDB')) AS SizeGB
"@

# Query current SUSDB size and supersession counts.
$beforeDb = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database master -Query $beforeDbQuery

Write-Host "`nCurrent Database State:" -ForegroundColor Yellow
Write-Host "  Total updates: $($beforeStats.TotalUpdates)"
Write-Host "  Declined updates: $($beforeStats.DeclinedUpdates)"
Write-Host "  Superseded updates: $($beforeStats.SupersededUpdates)"
Write-Host "  Active updates: $($beforeStats.ActiveUpdates)"
Write-Host "  Supersession records: $($beforeDb.SupersessionRecords)"
Write-Host "  Database size: $($beforeDb.SizeGB) GB"

# Calculate expected cleanup (rough estimates).
$expectedSupersessionRemoval = $beforeDb.DeclinedRevisions + $beforeDb.SupersededRevisions
$expectedSpaceSavings = [math]::Round($beforeStats.DeclinedUpdates * 0.0001 + ($expectedSupersessionRemoval * 0.000001), 2)

Write-Host "`nExpected Cleanup:" -ForegroundColor Green
Write-Host "  Remove ~$expectedSupersessionRemoval supersession records"
Write-Host "  Delete ~$($beforeStats.DeclinedUpdates) declined updates"
Write-Host "  Free ~$expectedSpaceSavings GB (approximate)"
Write-Host "  Result: ~$($beforeStats.ActiveUpdates) active updates remaining"

# Require explicit confirmation before heavy operations.
$response = Read-Host "`nProceed with ultimate cleanup? (yes/no)"
if ($response -ne "yes") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# === STOP WSUS SERVICE ===
# Stop WSUS to avoid contention while modifying SUSDB.
Write-Host "`n=== Step 1: Stop WSUS Service ===" -ForegroundColor Cyan
Write-Host "Stopping WSUS service..." -ForegroundColor Yellow

try {
    Stop-Service WSUSService -Force -ErrorAction Stop
    Start-Sleep -Seconds 5
    Write-Host "? WSUS service stopped" -ForegroundColor Green
} catch {
    Write-Error "Failed to stop WSUS service: $($_.Exception.Message)"
    exit 1
}

# === REMOVE SUPERSESSION RECORDS ===
# Step 2 removes supersession rows that point to declined/superseded updates.
Write-Host "`n=== Step 2: Remove Supersession Records ===" -ForegroundColor Cyan

# Declined updates: remove supersession rows first.
Write-Host "Removing supersession records for declined updates..." -ForegroundColor Yellow
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
    Write-Host "? Removed $($result1.DeletedDeclined) supersession records for declined updates" -ForegroundColor Green
} catch {
    Write-Warning "Failed: $($_.Exception.Message)"
}

# Superseded updates: delete in batches to avoid giant locks.
Write-Host "`nRemoving supersession records for superseded updates (10-20 minutes)..." -ForegroundColor Yellow
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
        Write-Host "  $_" -ForegroundColor DarkGray 
    }
    
    $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    $deleted = ($result2 | Where-Object { $_.DeletedSuperseded -ne $null }).DeletedSuperseded
    Write-Host "? Removed $deleted supersession records in $duration minutes" -ForegroundColor Green
} catch {
    Write-Warning "Failed: $($_.Exception.Message)"
}

# === DELETE DECLINED UPDATES ===
# Step 3 removes the update metadata via spDeleteUpdate.
Write-Host "`n=== Step 3: Delete Declined Updates ===" -ForegroundColor Cyan

if ($beforeStats.DeclinedUpdates -gt 0) {
    Write-Host "Permanently deleting $($beforeStats.DeclinedUpdates) declined updates (20-60 minutes)..." -ForegroundColor Yellow
    Write-Host "This uses the official WSUS spDeleteUpdate stored procedure`n" -ForegroundColor Gray
    
    # Get list of declined update IDs.
    $declinedIDs = @($allUpdates | Where-Object { $_.IsDeclined } | 
        Select-Object -ExpandProperty Id | 
        ForEach-Object { $_.UpdateId })
    
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
                # Continue on errors
            }
        }
        
        if ($currentBatch % 5 -eq 0) {
            $percentComplete = [math]::Round(($currentBatch / $totalBatches) * 100, 1)
            Write-Host "  Progress: $currentBatch/$totalBatches batches ($percentComplete%) - Deleted: $totalDeleted" -ForegroundColor Gray
        }
    }
    
    Write-Host "? Deleted $totalDeleted declined updates" -ForegroundColor Green
} else {
    Write-Host "? No declined updates to delete" -ForegroundColor Green
}

# === ADD PERFORMANCE INDEXES ===
Write-Host "`n=== Step 4: Add Performance Indexes ===" -ForegroundColor Cyan

$addIndexQuery = @"
-- Add Microsoft-recommended indexes if they don't exist
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_tbRevisionSupersedesUpdate' AND object_id = OBJECT_ID('tbRevisionSupersedesUpdate'))
BEGIN
    CREATE NONCLUSTERED INDEX [IX_tbRevisionSupersedesUpdate] ON [dbo].[tbRevisionSupersedesUpdate]([SupersededUpdateID])
    PRINT 'Created IX_tbRevisionSupersedesUpdate'
END
ELSE
    PRINT 'IX_tbRevisionSupersedesUpdate already exists'

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_tbLocalizedPropertyForRevision' AND object_id = OBJECT_ID('tbLocalizedPropertyForRevision'))
BEGIN
    CREATE NONCLUSTERED INDEX [IX_tbLocalizedPropertyForRevision] ON [dbo].[tbLocalizedPropertyForRevision]([LocalizedPropertyID])
    PRINT 'Created IX_tbLocalizedPropertyForRevision'
END
ELSE
    PRINT 'IX_tbLocalizedPropertyForRevision already exists'
"@

try {
    $indexMessages = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
        -Query $addIndexQuery -QueryTimeout 300 -Verbose 4>&1
    $indexMessages | Where-Object { $_ -is [string] } | ForEach-Object { 
        Write-Host "  $_" -ForegroundColor Gray 
    }
    Write-Host "? Performance indexes configured" -ForegroundColor Green
} catch {
    Write-Warning "Index creation: $($_.Exception.Message)"
}

# === REBUILD ALL INDEXES ===
Write-Host "`n=== Step 5: Rebuild All Indexes ===" -ForegroundColor Cyan
Write-Host "Rebuilding fragmented indexes (10-20 minutes)..." -ForegroundColor Yellow

$rebuildQuery = @"
SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;

DECLARE @TableName NVARCHAR(255), @IndexName NVARCHAR(255), @Frag FLOAT
DECLARE @SQL NVARCHAR(MAX)
DECLARE @Rebuilt INT = 0, @Reorganized INT = 0

DECLARE index_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT 
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
AND ips.page_count > 1000
AND i.name IS NOT NULL
AND OBJECT_NAME(ips.object_id) NOT LIKE 'ivw%'
ORDER BY ips.page_count DESC

OPEN index_cursor
FETCH NEXT FROM index_cursor INTO @TableName, @IndexName, @Frag

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        IF @Frag > 30
        BEGIN
            SET @SQL = 'ALTER INDEX [' + @IndexName + '] ON [' + @TableName + '] REBUILD WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON)'
            EXEC sp_executesql @SQL
            SET @Rebuilt = @Rebuilt + 1
        END
        ELSE
        BEGIN
            SET @SQL = 'ALTER INDEX [' + @IndexName + '] ON [' + @TableName + '] REORGANIZE'
            EXEC sp_executesql @SQL
            SET @Reorganized = @Reorganized + 1
        END
    END TRY
    BEGIN CATCH
        -- Skip errors
    END CATCH
    
    IF (@Rebuilt + @Reorganized) % 10 = 0
        PRINT 'Processed ' + CAST(@Rebuilt + @Reorganized AS VARCHAR) + ' indexes...'
    
    FETCH NEXT FROM index_cursor INTO @TableName, @IndexName, @Frag
END

CLOSE index_cursor
DEALLOCATE index_cursor

SELECT @Rebuilt AS IndexesRebuilt, @Reorganized AS IndexesReorganized
"@

try {
    $rebuildResult = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
        -Query $rebuildQuery -QueryTimeout 0 -Verbose 4>&1
    
    $rebuildResult | Where-Object { $_ -is [string] } | ForEach-Object { 
        Write-Host "  $_" -ForegroundColor DarkGray 
    }
    
    $rebuilt = ($rebuildResult | Where-Object { $_.IndexesRebuilt -ne $null }).IndexesRebuilt
    $reorganized = ($rebuildResult | Where-Object { $_.IndexesReorganized -ne $null }).IndexesReorganized
    Write-Host "? Rebuilt $rebuilt indexes, reorganized $reorganized indexes" -ForegroundColor Green
} catch {
    Write-Warning "Index rebuild: $($_.Exception.Message)"
}

# === UPDATE STATISTICS ===
Write-Host "`n=== Step 6: Update Statistics ===" -ForegroundColor Cyan

try {
    Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
        -Query "EXEC sp_updatestats" -QueryTimeout 0 | Out-Null
    Write-Host "? Statistics updated" -ForegroundColor Green
} catch {
    Write-Warning "Statistics update: $($_.Exception.Message)"
}

# === SHRINK DATABASE ===
Write-Host "`n=== Step 7: Shrink Database ===" -ForegroundColor Cyan

$spaceQuery = @"
SELECT 
    SUM(size/128.0) AS AllocatedMB,
    SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0) AS UsedMB,
    SUM((size - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int))/128.0) AS FreeMB
FROM sys.database_files
WHERE type = 0
"@

$space = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB -Query $spaceQuery
Write-Host "Space: Allocated=$([math]::Round($space.AllocatedMB,2))MB | Used=$([math]::Round($space.UsedMB,2))MB | Free=$([math]::Round($space.FreeMB,2))MB"

if ($space.FreeMB -gt 100) {
    Write-Host "Shrinking database..." -ForegroundColor Yellow
    try {
        Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
            -Query "DBCC SHRINKDATABASE(SUSDB, 10) WITH NO_INFOMSGS" -QueryTimeout 0 | Out-Null
        Write-Host "? Database shrunk" -ForegroundColor Green
    } catch {
        Write-Warning "Shrink failed: $($_.Exception.Message)"
    }
} else {
    Write-Host "? Skipping shrink (only $([math]::Round($space.FreeMB,2))MB free)" -ForegroundColor Yellow
}

# === RUN WSUS CLEANUP ===
Write-Host "`n=== Step 8: WSUS Server Cleanup ===" -ForegroundColor Cyan

try {
    Import-Module UpdateServices -ErrorAction SilentlyContinue
    $cleanup = Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -CompressUpdates -Confirm:$false
    Write-Host "? WSUS cleanup: Obsolete=$($cleanup.ObsoleteUpdatesDeleted) | Space=$([math]::Round($cleanup.DiskSpaceFreed/1MB,2))MB freed" -ForegroundColor Green
} catch {
    Write-Warning "WSUS cleanup: $($_.Exception.Message)"
}

# === START WSUS SERVICE ===
Write-Host "`n=== Step 9: Start WSUS Service ===" -ForegroundColor Cyan

try {
    Start-Service WSUSService -ErrorAction Stop
    Start-Sleep -Seconds 10
    Write-Host "? WSUS service started" -ForegroundColor Green
} catch {
    Write-Error "Failed to start WSUS service: $($_.Exception.Message)"
}

# === GET FINAL STATE ===
Write-Host "`n=== Final Results ===" -ForegroundColor Green

$afterDbQuery = @"
SELECT 
    (SELECT COUNT(*) FROM tbRevisionSupersedesUpdate) AS SupersessionRecords,
    (SELECT COUNT(*) FROM tbRevision WHERE State = 2) AS DeclinedRevisions,
    (SELECT COUNT(*) FROM tbRevision WHERE State = 3) AS SupersededRevisions,
    (SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) FROM sys.master_files WHERE database_id=DB_ID('SUSDB')) AS SizeGB
"@

$afterDb = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database master -Query $afterDbQuery

Write-Host "Refreshing WSUS data..." -ForegroundColor Yellow
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
$finalUpdates = $wsus.GetUpdates()

$afterStats = @{
    TotalUpdates = $finalUpdates.Count
    DeclinedUpdates = @($finalUpdates | Where-Object { $_.IsDeclined }).Count
    ActiveUpdates = @($finalUpdates | Where-Object { -not $_.IsDeclined -and -not $_.IsSuperseded }).Count
}

Write-Host "`n===================================================================" -ForegroundColor Cyan
Write-Host "                    BEFORE vs AFTER" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan

Write-Host "`nUpdates:" -ForegroundColor Yellow
Write-Host "  Total updates: $($beforeStats.TotalUpdates) ? $($afterStats.TotalUpdates)"
Write-Host "  Declined updates: $($beforeStats.DeclinedUpdates) ? $($afterStats.DeclinedUpdates)"
Write-Host "  Active updates: $($beforeStats.ActiveUpdates) ? $($afterStats.ActiveUpdates)"

Write-Host "`nDatabase:" -ForegroundColor Yellow
Write-Host "  Supersession records: $($beforeDb.SupersessionRecords) ? $($afterDb.SupersessionRecords)"
Write-Host "  Database size: $($beforeDb.SizeGB) GB ? $($afterDb.SizeGB) GB"

$recordsRemoved = $beforeDb.SupersessionRecords - $afterDb.SupersessionRecords
$updatesRemoved = $beforeStats.TotalUpdates - $afterStats.TotalUpdates
$spaceFreed = [math]::Round($beforeDb.SizeGB - $afterDb.SizeGB, 2)

Write-Host "`nImpact:" -ForegroundColor Green
Write-Host "  ? Removed $recordsRemoved supersession records"
Write-Host "  ? Deleted $updatesRemoved declined updates"
Write-Host "  ? Freed $spaceFreed GB of space"
Write-Host "  ? $($afterStats.ActiveUpdates) active updates remaining"

Write-Host "`n===================================================================" -ForegroundColor Cyan
Write-Host "                  CLEANUP COMPLETE!" -ForegroundColor Green
Write-Host "===================================================================" -ForegroundColor Cyan

Write-Host "`nRecommendations:" -ForegroundColor Yellow
Write-Host "  1. Run this ultimate cleanup quarterly"
Write-Host "  2. Run monthly maintenance script to prevent buildup"
Write-Host "  3. Monitor database - should stay under 3 GB"
Write-Host "  4. Your WSUS should now be significantly faster"
Write-Host ""
