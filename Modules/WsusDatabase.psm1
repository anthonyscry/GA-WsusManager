<#
===============================================================================
Module: WsusDatabase.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS database cleanup and optimization functions

.DESCRIPTION
    Provides shared database maintenance functionality including:
    - Supersession record cleanup
    - Declined update deletion
    - Index optimization
    - Statistics updates
    - Database size queries
#>

# ===========================
# DATABASE SIZE FUNCTIONS
# ===========================

function Get-WsusDatabaseSize {
    <#
    .SYNOPSIS
        Gets the current WSUS database size in GB

    .PARAMETER SqlInstance
        SQL Server instance name (default: localhost\SQLEXPRESS)

    .OUTPUTS
        Decimal value representing database size in GB
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS"
    )

    $query = "SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')"

    try {
        $result = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database master -Query $query -QueryTimeout 30
        return $result.SizeGB
    } catch {
        Write-Warning "Failed to get database size: $($_.Exception.Message)"
        return 0
    }
}

function Get-WsusDatabaseStats {
    <#
    .SYNOPSIS
        Gets comprehensive database statistics

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Custom object with database statistics
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS"
    )

    $query = @"
SELECT
    (SELECT COUNT(*) FROM tbRevisionSupersedesUpdate) AS SupersessionRecords,
    (SELECT COUNT(*) FROM tbRevision WHERE State = 2) AS DeclinedRevisions,
    (SELECT COUNT(*) FROM tbRevision WHERE State = 3) AS SupersededRevisions,
    (SELECT COUNT(*) FROM tbFileOnServer WHERE ActualState = 1) AS FilesPresent,
    (SELECT COUNT(*) FROM tbFileOnServer) AS FilesTotal,
    (SELECT COUNT(*) FROM tbFileDownloadProgress) AS FilesInDownloadQueue,
    (SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) FROM master.sys.master_files WHERE database_id=DB_ID('SUSDB')) AS SizeGB
"@

    try {
        return Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB -Query $query -QueryTimeout 30
    } catch {
        Write-Warning "Failed to get database stats: $($_.Exception.Message)"
        return $null
    }
}

# ===========================
# SUPERSESSION CLEANUP FUNCTIONS
# ===========================

function Remove-DeclinedSupersessionRecords {
    <#
    .SYNOPSIS
        Removes supersession records for declined updates

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Number of records deleted
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS"
    )

    $query = @"
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
        $result = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 300
        return $result.DeletedDeclined
    } catch {
        Write-Warning "Failed to remove declined supersession records: $($_.Exception.Message)"
        return 0
    }
}

function Remove-SupersededSupersessionRecords {
    <#
    .SYNOPSIS
        Removes supersession records for superseded updates in batches

    .PARAMETER SqlInstance
        SQL Server instance name

    .PARAMETER BatchSize
        Number of records to delete per batch (default: 10000)

    .PARAMETER Verbose
        Show progress messages

    .OUTPUTS
        Number of records deleted
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS",
        [int]$BatchSize = 10000,
        [switch]$ShowProgress
    )

    $query = @"
SET NOCOUNT ON;
DECLARE @Deleted INT = 0
DECLARE @BatchSize INT = $BatchSize
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
        $result = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 0 -Verbose 4>&1

        if ($ShowProgress) {
            $result | Where-Object { $_ -is [string] } | ForEach-Object {
                Write-Host "  $_" -ForegroundColor DarkGray
            }
        }

        $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        $deleted = ($result | Where-Object { $_.DeletedSuperseded -ne $null }).DeletedSuperseded

        if ($ShowProgress) {
            Write-Host "Removed $deleted supersession records in $duration minutes" -ForegroundColor Green
        }

        return $deleted
    } catch {
        Write-Warning "Failed to remove superseded supersession records: $($_.Exception.Message)"
        return 0
    }
}

# ===========================
# INDEX OPTIMIZATION FUNCTIONS
# ===========================

function Optimize-WsusIndexes {
    <#
    .SYNOPSIS
        Rebuilds or reorganizes fragmented indexes

    .PARAMETER SqlInstance
        SQL Server instance name

    .PARAMETER FragmentationThreshold
        Minimum fragmentation percentage to reorganize (default: 10)

    .PARAMETER RebuildThreshold
        Minimum fragmentation percentage to rebuild (default: 30)

    .PARAMETER ShowProgress
        Show progress messages

    .OUTPUTS
        Custom object with rebuild and reorganize counts
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS",
        [int]$FragmentationThreshold = 10,
        [int]$RebuildThreshold = 30,
        [switch]$ShowProgress
    )

    $query = @"
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
WHERE ips.avg_fragmentation_in_percent > $FragmentationThreshold
AND ips.page_count > 1000
AND i.name IS NOT NULL
AND OBJECT_NAME(ips.object_id) NOT LIKE 'ivw%'
ORDER BY ips.page_count DESC

OPEN index_cursor
FETCH NEXT FROM index_cursor INTO @TableName, @IndexName, @Frag

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        IF @Frag > $RebuildThreshold
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
        $result = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 0 -Verbose 4>&1

        if ($ShowProgress) {
            $result | Where-Object { $_ -is [string] } | ForEach-Object {
                Write-Host "  $_" -ForegroundColor DarkGray
            }
        }

        $rebuilt = ($result | Where-Object { $_.IndexesRebuilt -ne $null }).IndexesRebuilt
        $reorganized = ($result | Where-Object { $_.IndexesReorganized -ne $null }).IndexesReorganized

        return @{
            Rebuilt = $rebuilt
            Reorganized = $reorganized
        }
    } catch {
        Write-Warning "Index optimization failed: $($_.Exception.Message)"
        return @{ Rebuilt = 0; Reorganized = 0 }
    }
}

function Add-WsusPerformanceIndexes {
    <#
    .SYNOPSIS
        Adds Microsoft-recommended performance indexes if they don't exist

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Array of messages about index creation
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS"
    )

    $query = @"
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
        $messages = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 300 -Verbose 4>&1

        $messages | Where-Object { $_ -is [string] } | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }

        return $messages
    } catch {
        Write-Warning "Failed to add performance indexes: $($_.Exception.Message)"
        return @()
    }
}

# ===========================
# STATISTICS FUNCTIONS
# ===========================

function Update-WsusStatistics {
    <#
    .SYNOPSIS
        Updates all database statistics

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS"
    )

    try {
        Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query "EXEC sp_updatestats" -QueryTimeout 0 | Out-Null
        return $true
    } catch {
        Write-Warning "Statistics update failed: $($_.Exception.Message)"
        return $false
    }
}

# ===========================
# DATABASE SHRINK FUNCTIONS
# ===========================

function Invoke-WsusDatabaseShrink {
    <#
    .SYNOPSIS
        Shrinks the WSUS database

    .PARAMETER SqlInstance
        SQL Server instance name

    .PARAMETER TargetFreePercent
        Target free space percentage (default: 10)

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS",
        [int]$TargetFreePercent = 10
    )

    try {
        Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query "DBCC SHRINKDATABASE(SUSDB, $TargetFreePercent) WITH NO_INFOMSGS" `
            -QueryTimeout 0 | Out-Null
        return $true
    } catch {
        Write-Warning "Database shrink failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-WsusDatabaseSpace {
    <#
    .SYNOPSIS
        Gets database space usage information

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Custom object with allocated, used, and free space in MB
    #>
    param(
        [string]$SqlInstance = "localhost\SQLEXPRESS"
    )

    $query = @"
SELECT
    SUM(size/128.0) AS AllocatedMB,
    SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0) AS UsedMB,
    SUM((size - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int))/128.0) AS FreeMB
FROM sys.database_files
WHERE type = 0
"@

    try {
        return Invoke-Sqlcmd -ServerInstance $SqlInstance -Database SUSDB -Query $query
    } catch {
        Write-Warning "Failed to get database space info: $($_.Exception.Message)"
        return $null
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-WsusDatabaseSize',
    'Get-WsusDatabaseStats',
    'Remove-DeclinedSupersessionRecords',
    'Remove-SupersededSupersessionRecords',
    'Optimize-WsusIndexes',
    'Add-WsusPerformanceIndexes',
    'Update-WsusStatistics',
    'Invoke-WsusDatabaseShrink',
    'Get-WsusDatabaseSpace'
)
