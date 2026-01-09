<#
===============================================================================
Module: WsusDatabase.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.1
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

# Import WsusUtilities for Invoke-WsusSqlcmd wrapper
$modulePath = $PSScriptRoot
if (Test-Path (Join-Path $modulePath "WsusUtilities.psm1")) {
    Import-Module (Join-Path $modulePath "WsusUtilities.psm1") -Force -ErrorAction SilentlyContinue
}

# ===========================
# DATABASE SIZE FUNCTIONS
# ===========================

function Get-WsusDatabaseSize {
    <#
    .SYNOPSIS
        Gets the current WSUS database size in GB

    .PARAMETER SqlInstance
        SQL Server instance name (default: .\SQLEXPRESS)

    .OUTPUTS
        Decimal value representing database size in GB
    #>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $query = "SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')"

    try {
        $result = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query $query -QueryTimeout 30
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
        [string]$SqlInstance = ".\SQLEXPRESS"
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
        return Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB -Query $query -QueryTimeout 30
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
        [string]$SqlInstance = ".\SQLEXPRESS"
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
        $result = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB `
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
        [string]$SqlInstance = ".\SQLEXPRESS",
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
        $result = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 0

        $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        $deleted = if ($result.DeletedSuperseded) { $result.DeletedSuperseded } else { 0 }

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
        [string]$SqlInstance = ".\SQLEXPRESS",
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
        $result = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 0

        $rebuilt = if ($result.IndexesRebuilt) { $result.IndexesRebuilt } else { 0 }
        $reorganized = if ($result.IndexesReorganized) { $result.IndexesReorganized } else { 0 }

        if ($ShowProgress) {
            Write-Host "Index optimization complete: Rebuilt=$rebuilt, Reorganized=$reorganized" -ForegroundColor Green
        }

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
        [string]$SqlInstance = ".\SQLEXPRESS"
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
        $result = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB `
            -Query $query -QueryTimeout 300

        Write-Host "  Performance indexes verified/created" -ForegroundColor Gray

        return $result
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
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    try {
        Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB `
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
        [string]$SqlInstance = ".\SQLEXPRESS",
        [int]$TargetFreePercent = 10
    )

    try {
        Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB `
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
        [string]$SqlInstance = ".\SQLEXPRESS"
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
        return Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database SUSDB -Query $query
    } catch {
        Write-Warning "Failed to get database space info: $($_.Exception.Message)"
        return $null
    }
}

# ===========================
# BACKUP VERIFICATION FUNCTIONS
# ===========================

function Test-WsusBackupIntegrity {
    <#
    .SYNOPSIS
        Verifies the integrity of a WSUS database backup file

    .PARAMETER BackupPath
        Full path to the .bak file to verify

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Hashtable with verification results
    #>
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,

        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $result = @{
        IsValid = $false
        BackupFile = $BackupPath
        BackupSizeMB = 0
        DatabaseName = ""
        BackupDate = $null
        Message = ""
    }

    # Check if file exists
    if (-not (Test-Path $BackupPath)) {
        $result.Message = "Backup file not found: $BackupPath"
        return $result
    }

    $result.BackupSizeMB = [math]::Round((Get-Item $BackupPath).Length / 1MB, 2)

    try {
        # Get backup header information
        $headerQuery = "RESTORE HEADERONLY FROM DISK = N'$BackupPath'"
        $header = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master `
            -Query $headerQuery -QueryTimeout 60

        if ($header) {
            $result.DatabaseName = $header.DatabaseName
            $result.BackupDate = $header.BackupFinishDate
        }

        # Verify backup integrity using RESTORE VERIFYONLY
        $verifyQuery = "RESTORE VERIFYONLY FROM DISK = N'$BackupPath' WITH CHECKSUM"
        Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master `
            -Query $verifyQuery -QueryTimeout 300

        $result.IsValid = $true
        $result.Message = "Backup verified successfully"

    } catch {
        $result.Message = "Backup verification failed: $($_.Exception.Message)"
    }

    return $result
}

# ===========================
# DISK SPACE CHECK FUNCTIONS
# ===========================

function Test-WsusDiskSpace {
    <#
    .SYNOPSIS
        Checks available disk space before backup/maintenance operations

    .PARAMETER Path
        Path to check (uses drive letter from path)

    .PARAMETER RequiredSpaceGB
        Minimum required free space in GB (default: 5)

    .PARAMETER DatabaseSizeMultiplier
        Multiplier of database size to require as free space (default: 1.5)

    .PARAMETER SqlInstance
        SQL Server instance name (used to get database size)

    .OUTPUTS
        Hashtable with disk space check results
    #>
    param(
        [string]$Path = "C:\WSUS",

        [decimal]$RequiredSpaceGB = 5,

        [decimal]$DatabaseSizeMultiplier = 1.5,

        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $result = @{
        HasSufficientSpace = $false
        DriveLetter = ""
        FreeSpaceGB = 0
        RequiredSpaceGB = $RequiredSpaceGB
        DatabaseSizeGB = 0
        EstimatedBackupSizeGB = 0
        Message = ""
    }

    try {
        # Get drive from path
        $drive = (Get-Item $Path -ErrorAction Stop).PSDrive
        if (-not $drive) {
            # Try to extract drive letter from path
            if ($Path -match '^([A-Z]):') {
                $driveLetter = $Matches[1]
                $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
            }
        }

        if ($drive) {
            $result.DriveLetter = $drive.Name
            $result.FreeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        } else {
            $result.Message = "Could not determine drive for path: $Path"
            return $result
        }

        # Get current database size
        $dbSize = Get-WsusDatabaseSize -SqlInstance $SqlInstance
        if ($dbSize) {
            $result.DatabaseSizeGB = $dbSize
            $result.EstimatedBackupSizeGB = [math]::Round($dbSize * 0.8, 2)  # Compressed backup estimate
        }

        # Calculate required space
        $requiredFromDb = $result.DatabaseSizeGB * $DatabaseSizeMultiplier
        $actualRequired = [math]::Max($RequiredSpaceGB, $requiredFromDb)
        $result.RequiredSpaceGB = [math]::Round($actualRequired, 2)

        # Check if sufficient
        if ($result.FreeSpaceGB -ge $result.RequiredSpaceGB) {
            $result.HasSufficientSpace = $true
            $result.Message = "Sufficient disk space available"
        } else {
            $deficit = [math]::Round($result.RequiredSpaceGB - $result.FreeSpaceGB, 2)
            $result.Message = "Insufficient disk space. Need $deficit GB more free space."
        }

    } catch {
        $result.Message = "Disk space check failed: $($_.Exception.Message)"
    }

    return $result
}

# ===========================
# DATABASE CONSISTENCY FUNCTIONS
# ===========================

function Test-WsusDatabaseConsistency {
    <#
    .SYNOPSIS
        Runs DBCC CHECKDB to verify database consistency

    .PARAMETER SqlInstance
        SQL Server instance name

    .PARAMETER RepairMode
        Repair mode: None (check only), RepairAllowDataLoss, RepairRebuild
        Default is None (check only, no repairs)

    .PARAMETER PhysicalOnly
        If true, limits checking to physical consistency (faster)

    .OUTPUTS
        Hashtable with consistency check results
    #>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS",

        [ValidateSet('None', 'RepairAllowDataLoss', 'RepairRebuild')]
        [string]$RepairMode = 'None',

        [switch]$PhysicalOnly
    )

    $result = @{
        IsConsistent = $false
        ErrorCount = 0
        WarningCount = 0
        Duration = 0
        Message = ""
        Details = @()
    }

    $startTime = Get-Date

    try {
        # Build DBCC CHECKDB command
        $options = @()
        if ($PhysicalOnly) {
            $options += "PHYSICAL_ONLY"
        }
        if ($RepairMode -ne 'None') {
            $options += "REPAIR_$($RepairMode.Replace('Repair', ''))"
        }

        $optionString = if ($options.Count -gt 0) { "WITH $($options -join ', ')" } else { "" }
        $query = "DBCC CHECKDB('SUSDB') $optionString"

        # If repair mode, need single user mode
        if ($RepairMode -ne 'None') {
            Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master `
                -Query "ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE" `
                -QueryTimeout 60
        }

        # Run DBCC CHECKDB
        $checkResult = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master `
            -Query $query -QueryTimeout 0

        # Return to multi-user mode if needed
        if ($RepairMode -ne 'None') {
            try {
                Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master `
                    -Query "ALTER DATABASE SUSDB SET MULTI_USER" `
                    -QueryTimeout 60
            } catch { }
        }

        # Parse results - CHECKDB returns messages
        $result.IsConsistent = $true
        $result.Message = "Database consistency check completed successfully"

        # Look for error indicators in output
        if ($checkResult) {
            foreach ($row in $checkResult) {
                if ($row -match 'error|corrupt|fail') {
                    $result.IsConsistent = $false
                    $result.ErrorCount++
                    $result.Details += $row
                }
            }
        }

    } catch {
        $result.Message = "Consistency check failed: $($_.Exception.Message)"

        # Ensure database is back to multi-user mode
        try {
            Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master `
                -Query "ALTER DATABASE SUSDB SET MULTI_USER" `
                -QueryTimeout 60
        } catch { }
    }

    $result.Duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

    return $result
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
    'Get-WsusDatabaseSpace',
    'Test-WsusBackupIntegrity',
    'Test-WsusDiskSpace',
    'Test-WsusDatabaseConsistency'
)
