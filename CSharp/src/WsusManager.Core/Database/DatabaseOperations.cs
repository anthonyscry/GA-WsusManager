using System.Data;

namespace WsusManager.Core.Database;

/// <summary>
/// Provides WSUS database maintenance and cleanup operations.
/// Replaces PowerShell WsusDatabase.psm1 functions.
/// </summary>
public class DatabaseOperations
{
    private readonly SqlHelper _sql;

    public DatabaseOperations(SqlHelper sqlHelper)
    {
        _sql = sqlHelper;
    }

    public DatabaseOperations(string serverInstance = @".\SQLEXPRESS")
    {
        _sql = new SqlHelper(serverInstance);
    }

    /// <summary>
    /// Gets the current database size in GB.
    /// </summary>
    public async Task<decimal> GetDatabaseSizeGBAsync()
    {
        return await _sql.GetDatabaseSizeGBAsync();
    }

    /// <summary>
    /// Gets comprehensive database statistics.
    /// </summary>
    public async Task<DatabaseStats?> GetDatabaseStatsAsync()
    {
        return await _sql.GetDatabaseStatsAsync();
    }

    /// <summary>
    /// Removes supersession records for declined updates.
    /// </summary>
    /// <returns>Number of records deleted</returns>
    public async Task<int> RemoveDeclinedSupersessionRecordsAsync()
    {
        const string query = @"
            SET NOCOUNT ON;
            DECLARE @Deleted INT = 0

            DELETE rsu
            FROM tbRevisionSupersedesUpdate rsu
            INNER JOIN tbRevision r ON rsu.RevisionID = r.RevisionID
            WHERE r.State = 2  -- Declined

            SET @Deleted = @@ROWCOUNT
            SELECT @Deleted AS DeletedDeclined";

        try
        {
            var result = await _sql.ExecuteScalarAsync<int?>(query, timeout: 300);
            return result ?? 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Failed to remove declined supersession records: {ex.Message}");
            return 0;
        }
    }

    /// <summary>
    /// Removes supersession records for superseded updates in batches.
    /// </summary>
    /// <param name="batchSize">Number of records per batch (default: 10000)</param>
    /// <param name="showProgress">Show progress messages</param>
    /// <returns>Number of records deleted</returns>
    public async Task<int> RemoveSupersededSupersessionRecordsAsync(
        int batchSize = 10000,
        bool showProgress = false)
    {
        var query = $@"
            SET NOCOUNT ON;
            DECLARE @Deleted INT = 0
            DECLARE @BatchSize INT = {batchSize}
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

            SELECT @TotalDeleted AS DeletedSuperseded";

        try
        {
            var startTime = DateTime.Now;
            var result = await _sql.ExecuteScalarAsync<int?>(query, timeout: 0);
            var deleted = result ?? 0;
            var duration = Math.Round((DateTime.Now - startTime).TotalMinutes, 1);

            if (showProgress)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"Removed {deleted} supersession records in {duration} minutes");
                Console.ResetColor();
            }

            return deleted;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Failed to remove superseded supersession records: {ex.Message}");
            return 0;
        }
    }

    /// <summary>
    /// Optimizes database indexes (rebuild or reorganize based on fragmentation).
    /// </summary>
    /// <param name="fragmentationThreshold">Min fragmentation % to reorganize (default: 10)</param>
    /// <param name="rebuildThreshold">Min fragmentation % to rebuild (default: 30)</param>
    /// <returns>Result containing rebuild and reorganize counts</returns>
    public async Task<IndexOptimizationResult> OptimizeIndexesAsync(
        int fragmentationThreshold = 10,
        int rebuildThreshold = 30)
    {
        var query = $@"
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
            WHERE ips.avg_fragmentation_in_percent > {fragmentationThreshold}
            AND ips.page_count > 1000
            AND i.name IS NOT NULL
            AND OBJECT_NAME(ips.object_id) NOT LIKE 'ivw%'
            ORDER BY ips.page_count DESC

            OPEN index_cursor
            FETCH NEXT FROM index_cursor INTO @TableName, @IndexName, @Frag

            WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    IF @Frag > {rebuildThreshold}
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

            SELECT @Rebuilt AS IndexesRebuilt, @Reorganized AS IndexesReorganized";

        try
        {
            var table = await _sql.ExecuteQueryAsync(query, timeout: 0);
            if (table.Rows.Count > 0)
            {
                var row = table.Rows[0];
                return new IndexOptimizationResult
                {
                    Rebuilt = Convert.ToInt32(row["IndexesRebuilt"]),
                    Reorganized = Convert.ToInt32(row["IndexesReorganized"])
                };
            }

            return new IndexOptimizationResult();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Index optimization failed: {ex.Message}");
            return new IndexOptimizationResult();
        }
    }

    /// <summary>
    /// Updates all database statistics.
    /// </summary>
    public async Task<bool> UpdateStatisticsAsync()
    {
        try
        {
            await _sql.ExecuteNonQueryAsync("EXEC sp_updatestats", timeout: 0);
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Statistics update failed: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Shrinks the database to reclaim free space.
    /// </summary>
    /// <param name="targetFreePercent">Target free space percentage (default: 10)</param>
    public async Task<bool> ShrinkDatabaseAsync(int targetFreePercent = 10)
    {
        try
        {
            var query = $"DBCC SHRINKDATABASE(SUSDB, {targetFreePercent}) WITH NO_INFOMSGS";
            await _sql.ExecuteNonQueryAsync(query, timeout: 0);
            return true;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Database shrink failed: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Gets database space usage information.
    /// </summary>
    public async Task<DatabaseSpaceInfo?> GetDatabaseSpaceAsync()
    {
        const string query = @"
            SELECT
                SUM(size/128.0) AS AllocatedMB,
                SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0) AS UsedMB,
                SUM((size - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int))/128.0) AS FreeMB
            FROM sys.database_files
            WHERE type = 0";

        try
        {
            var table = await _sql.ExecuteQueryAsync(query);
            if (table.Rows.Count > 0)
            {
                var row = table.Rows[0];
                return new DatabaseSpaceInfo
                {
                    AllocatedMB = Convert.ToDecimal(row["AllocatedMB"]),
                    UsedMB = Convert.ToDecimal(row["UsedMB"]),
                    FreeMB = Convert.ToDecimal(row["FreeMB"])
                };
            }

            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Failed to get database space info: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Tests database connectivity.
    /// </summary>
    public async Task<bool> TestConnectionAsync()
    {
        return await _sql.TestConnectionAsync();
    }
}

/// <summary>
/// Result of index optimization operation.
/// </summary>
public class IndexOptimizationResult
{
    public int Rebuilt { get; set; }
    public int Reorganized { get; set; }
}

/// <summary>
/// Database space usage information.
/// </summary>
public class DatabaseSpaceInfo
{
    public decimal AllocatedMB { get; set; }
    public decimal UsedMB { get; set; }
    public decimal FreeMB { get; set; }
    public decimal UsedPercentage => AllocatedMB > 0 ? (UsedMB / AllocatedMB) * 100 : 0;
}
