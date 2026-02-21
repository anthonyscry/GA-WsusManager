using System.Diagnostics;
using Microsoft.Data.SqlClient;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Implements the 6-step WSUS deep cleanup pipeline.
/// Matches the PowerShell WsusDatabase.psm1 implementation exactly,
/// including SQL batch sizes, retry logic, and progress format.
/// </summary>
public class DeepCleanupService : IDeepCleanupService
{
    private readonly ISqlService _sqlService;
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    // SQL batch sizes matching PowerShell implementation
    private const int SupersessionBatchSize = 10000;
    private const int DeclinedDeleteBatchSize = 100;

    // Shrink retry configuration
    private const int ShrinkMaxRetries = 3;
    private const int ShrinkRetryDelaySeconds = 30;

    private const string SusDb = "SUSDB";

    public DeepCleanupService(
        ISqlService sqlService,
        IProcessRunner processRunner,
        ILogService logService)
    {
        _sqlService = sqlService;
        _processRunner = processRunner;
        _logService = logService;
    }

    /// <inheritdoc/>
    public async Task<OperationResult> RunAsync(
        string sqlInstance,
        IProgress<string> progress,
        CancellationToken ct)
    {
        _logService.Info("Starting deep cleanup pipeline on {SqlInstance}", sqlInstance);

        // Capture DB size before step 1
        var dbSizeBefore = await GetDatabaseSizeGbAsync(sqlInstance, ct).ConfigureAwait(false);
        if (dbSizeBefore >= 0)
            progress.Report($"Current database size: {dbSizeBefore:F2} GB");

        try
        {
            // Step 1: WSUS built-in cleanup
            await RunStep1WsusCleanupAsync(sqlInstance, progress, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();

            // Step 2: Remove declined supersession records
            await RunStep2RemoveDeclinedSupersessionAsync(sqlInstance, progress, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();

            // Step 3: Remove superseded supersession records (batched 10k)
            await RunStep3RemoveSupersededSupersessionAsync(sqlInstance, progress, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();

            // Step 4: Delete declined updates via spDeleteUpdate (100/batch)
            await RunStep4DeleteDeclinedUpdatesAsync(sqlInstance, progress, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();

            // Step 5: Rebuild indexes + update statistics
            await RunStep5RebuildIndexesAsync(sqlInstance, progress, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();

            // Step 6: Shrink database with retry logic
            var dbSizeAfter = await RunStep6ShrinkDatabaseAsync(sqlInstance, dbSizeBefore, progress, ct).ConfigureAwait(false);

            // Final size comparison
            if (dbSizeBefore >= 0 && dbSizeAfter >= 0)
            {
                var saved = dbSizeBefore - dbSizeAfter;
                progress.Report($"Database size: {dbSizeBefore:F2} GB -> {dbSizeAfter:F2} GB (saved {saved:F2} GB)");
            }

            _logService.Info("Deep cleanup pipeline completed successfully");
            return OperationResult.Ok("Deep cleanup completed successfully.");
        }
        catch (OperationCanceledException)
        {
            _logService.Info("Deep cleanup cancelled by user");
            return OperationResult.Fail("Deep cleanup was cancelled.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Deep cleanup pipeline failed");
            return OperationResult.Fail($"Deep cleanup failed: {ex.Message}", ex);
        }
    }

    // ─── Step 1: WSUS built-in cleanup ───────────────────────────────────

    private async Task RunStep1WsusCleanupAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        progress.Report("[Step 1/6] WSUS built-in cleanup...");

        // Run Get-WsusServer | Invoke-WsusServerCleanup via PowerShell
        // WSUS managed API is incompatible with .NET 9 — must use PS subprocess
        var psCommand =
            "Get-WsusServer -Name localhost -PortNumber 8530 | " +
            "Invoke-WsusServerCleanup " +
            "-CleanupObsoleteUpdates " +
            "-CleanupUnneededContentFiles " +
            "-CompressUpdates " +
            "-DeclineSupersededUpdates";

        var result = await _processRunner.RunAsync(
            "powershell.exe",
            $"-NonInteractive -NoProfile -Command \"{psCommand}\"",
            progress,
            ct).ConfigureAwait(false);

        sw.Stop();
        if (result.Success)
            progress.Report($"[Step 1/6] WSUS built-in cleanup... done ({sw.Elapsed.TotalSeconds:F0}s)");
        else
            progress.Report($"[Step 1/6] WSUS built-in cleanup... warning (exit code {result.ExitCode}, {sw.Elapsed.TotalSeconds:F0}s)");

        _logService.Info("Step 1 complete in {Elapsed}s, exit code {ExitCode}", sw.Elapsed.TotalSeconds, result.ExitCode);
    }

    // ─── Step 2: Remove declined supersession records ────────────────────

    private async Task RunStep2RemoveDeclinedSupersessionAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        progress.Report("[Step 2/6] Remove supersession records for declined updates...");

        // Matches Remove-DeclinedSupersessionRecords from WsusDatabase.psm1
        // RevisionState = 2 means "Declined"
        const string sql = @"
            DELETE FROM tbRevisionSupersedesUpdate
            WHERE SupersededRevisionID IN (
                SELECT RevisionID FROM tbRevision
                WHERE RevisionState = 2
            )";

        var rowsDeleted = await _sqlService.ExecuteNonQueryAsync(sqlInstance, SusDb, sql, 0, ct).ConfigureAwait(false);

        sw.Stop();
        progress.Report($"[Step 2/6] Remove supersession records for declined updates... done ({rowsDeleted} records, {sw.Elapsed.TotalSeconds:F0}s)");
        _logService.Info("Step 2 complete: {Rows} records deleted in {Elapsed}s", rowsDeleted, sw.Elapsed.TotalSeconds);
    }

    // ─── Step 3: Remove superseded supersession records (10k batches) ────

    private async Task RunStep3RemoveSupersededSupersessionAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        progress.Report("[Step 3/6] Remove supersession records for superseded updates (batched)...");

        // Matches Remove-SupersededSupersessionRecords from WsusDatabase.psm1
        // RevisionState = 3 means "Superseded"
        // Uses DELETE TOP (10000) loop with 1-second delay between batches
        var totalDeleted = 0;

        while (true)
        {
            ct.ThrowIfCancellationRequested();

            var batchSql = $@"
                DELETE TOP ({SupersessionBatchSize}) FROM tbRevisionSupersedesUpdate
                WHERE SupersededRevisionID IN (
                    SELECT RevisionID FROM tbRevision
                    WHERE RevisionState = 3
                )";

            var rowsDeleted = await _sqlService.ExecuteNonQueryAsync(sqlInstance, SusDb, batchSql, 0, ct).ConfigureAwait(false);
            totalDeleted += rowsDeleted;

            if (rowsDeleted < SupersessionBatchSize)
                break; // No more rows to delete

            // 1-second delay between batches (matching PowerShell)
            await Task.Delay(TimeSpan.FromSeconds(1), ct).ConfigureAwait(false);
        }

        sw.Stop();
        progress.Report($"[Step 3/6] Remove supersession records for superseded updates... done ({totalDeleted} records, {sw.Elapsed.TotalSeconds:F0}s)");
        _logService.Info("Step 3 complete: {Rows} records deleted in {Elapsed}s", totalDeleted, sw.Elapsed.TotalSeconds);
    }

    // ─── Step 4: Delete declined updates via spDeleteUpdate ─────────────

    private async Task RunStep4DeleteDeclinedUpdatesAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        progress.Report("[Step 4/6] Delete declined updates from database...");

        // Query all declined update IDs
        // RevisionState = 2 (Declined) — join tbUpdate with tbRevision
        // BUG-08 fix: SELECT r.LocalUpdateID (INT) not u.UpdateID (GUID)
        // spDeleteUpdate expects @localUpdateID INT
        const string selectSql = @"
            SELECT DISTINCT r.LocalUpdateID
            FROM tbUpdate u
            INNER JOIN tbRevision r ON u.LocalUpdateID = r.LocalUpdateID
            WHERE r.RevisionState = 2";

        var updateIds = new List<int>();

        var connStr = _sqlService.BuildConnectionString(sqlInstance, SusDb);
        using (var conn = new SqlConnection(connStr))
        {
            await conn.OpenAsync(ct).ConfigureAwait(false);
            using var cmd = conn.CreateCommand();
            cmd.CommandText = selectSql;
            cmd.CommandTimeout = 0; // Unlimited
            using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await reader.ReadAsync(ct).ConfigureAwait(false))
            {
                if (!reader.IsDBNull(0))
                    updateIds.Add(reader.GetInt32(0));
            }
        }

        progress.Report($"Found {updateIds.Count} declined updates to delete.");

        if (updateIds.Count == 0)
        {
            sw.Stop();
            progress.Report($"[Step 4/6] Delete declined updates... done (0 updates, {sw.Elapsed.TotalSeconds:F0}s)");
            return;
        }

        // Delete in batches of 100 using spDeleteUpdate stored procedure
        var deleted = 0;
        var errors = 0;

        using (var conn = new SqlConnection(connStr))
        {
            await conn.OpenAsync(ct).ConfigureAwait(false);

            for (int i = 0; i < updateIds.Count; i += DeclinedDeleteBatchSize)
            {
                ct.ThrowIfCancellationRequested();

                var batch = updateIds.Skip(i).Take(DeclinedDeleteBatchSize).ToList();

                foreach (int updateId in batch)
                {
                    try
                    {
                        using var cmd = conn.CreateCommand();
                        cmd.CommandText = "EXEC spDeleteUpdate @localUpdateID";
                        cmd.CommandTimeout = 0; // Unlimited
                        cmd.Parameters.AddWithValue("@localUpdateID", updateId);
                        await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                        deleted++;
                    }
                    catch (SqlException)
                    {
                        // Silently suppress errors for updates with revision dependencies
                        // This matches the PowerShell v3.8.11 fix behavior
                        errors++;
                    }
                }

                if (deleted % DeclinedDeleteBatchSize == 0 || i + DeclinedDeleteBatchSize >= updateIds.Count)
                    progress.Report($"Deleted {deleted}/{updateIds.Count} declined updates...");
            }
        }

        sw.Stop();
        progress.Report($"[Step 4/6] Delete declined updates... done ({deleted} deleted, {errors} skipped with dependencies, {sw.Elapsed.TotalSeconds:F0}s)");
        _logService.Info("Step 4 complete: {Deleted} deleted, {Errors} skipped in {Elapsed}s", deleted, errors, sw.Elapsed.TotalSeconds);
    }

    // ─── Step 5: Rebuild indexes + update statistics ──────────────────────

    private async Task RunStep5RebuildIndexesAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        progress.Report("[Step 5/6] Rebuild fragmented indexes and update statistics...");

        // Cursor-based index optimization matching Optimize-WsusIndexes from WsusDatabase.psm1
        // fragmentation > 30% = rebuild, > 10% = reorganize (page_count > 1000 only)
        const string indexSql = @"
            DECLARE @TableName NVARCHAR(256)
            DECLARE @IndexName NVARCHAR(256)
            DECLARE @Fragmentation FLOAT
            DECLARE @Rebuilt INT = 0
            DECLARE @Reorganized INT = 0

            DECLARE IndexCursor CURSOR FOR
                SELECT
                    OBJECT_NAME(ips.object_id) AS TableName,
                    i.name AS IndexName,
                    ips.avg_fragmentation_in_percent
                FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
                INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
                WHERE ips.avg_fragmentation_in_percent > 10
                    AND ips.page_count > 1000
                    AND i.name IS NOT NULL

            OPEN IndexCursor
            FETCH NEXT FROM IndexCursor INTO @TableName, @IndexName, @Fragmentation

            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF @Fragmentation > 30
                BEGIN
                    EXEC('ALTER INDEX [' + @IndexName + '] ON [' + @TableName + '] REBUILD')
                    SET @Rebuilt = @Rebuilt + 1
                END
                ELSE
                BEGIN
                    EXEC('ALTER INDEX [' + @IndexName + '] ON [' + @TableName + '] REORGANIZE')
                    SET @Reorganized = @Reorganized + 1
                END
                FETCH NEXT FROM IndexCursor INTO @TableName, @IndexName, @Fragmentation
            END

            CLOSE IndexCursor
            DEALLOCATE IndexCursor

            SELECT @Rebuilt AS Rebuilt, @Reorganized AS Reorganized";

        // Execute index optimization
        var connStr = _sqlService.BuildConnectionString(sqlInstance, SusDb);
        int rebuilt = 0, reorganized = 0;

        using (var conn = new SqlConnection(connStr))
        {
            await conn.OpenAsync(ct).ConfigureAwait(false);
            using var cmd = conn.CreateCommand();
            cmd.CommandText = indexSql;
            cmd.CommandTimeout = 0; // Unlimited — index rebuild can take a long time

            using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            if (await reader.ReadAsync(ct).ConfigureAwait(false))
            {
                rebuilt = reader.GetInt32(0);
                reorganized = reader.GetInt32(1);
            }
        }

        progress.Report($"Indexes: Rebuilt={rebuilt}, Reorganized={reorganized}");

        // Update statistics
        await _sqlService.ExecuteNonQueryAsync(sqlInstance, SusDb, "EXEC sp_updatestats", 0, ct).ConfigureAwait(false);
        progress.Report("Statistics updated.");

        sw.Stop();
        progress.Report($"[Step 5/6] Rebuild indexes and update statistics... done (Rebuilt: {rebuilt}, Reorganized: {reorganized}, {sw.Elapsed.TotalSeconds:F0}s)");
        _logService.Info("Step 5 complete: Rebuilt={Rebuilt}, Reorganized={Reorganized} in {Elapsed}s", rebuilt, reorganized, sw.Elapsed.TotalSeconds);
    }

    // ─── Step 6: Shrink database with retry logic ─────────────────────────

    private async Task<double> RunStep6ShrinkDatabaseAsync(
        string sqlInstance,
        double dbSizeBefore,
        IProgress<string> progress,
        CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        progress.Report("[Step 6/6] Shrink database...");

        const string shrinkSql = "DBCC SHRINKDATABASE(SUSDB, 10) WITH NO_INFOMSGS";

        var attempt = 0;
        var shrinkSucceeded = false;

        while (attempt < ShrinkMaxRetries && !shrinkSucceeded)
        {
            attempt++;
            ct.ThrowIfCancellationRequested();

            try
            {
                await _sqlService.ExecuteNonQueryAsync(sqlInstance, SusDb, shrinkSql, 0, ct).ConfigureAwait(false);
                shrinkSucceeded = true;
            }
            catch (SqlException ex) when (IsBackupBlockingError(ex.Message))
            {
                _logService.Warning("Shrink blocked by backup operation (attempt {Attempt}/{Max}): {Error}",
                    attempt, ShrinkMaxRetries, ex.Message);

                if (attempt < ShrinkMaxRetries)
                {
                    progress.Report($"Shrink blocked by active backup. Retrying in {ShrinkRetryDelaySeconds}s (attempt {attempt}/{ShrinkMaxRetries})...");
                    await Task.Delay(TimeSpan.FromSeconds(ShrinkRetryDelaySeconds), ct).ConfigureAwait(false);
                }
                else
                {
                    progress.Report($"Shrink blocked after {ShrinkMaxRetries} attempts — skipping.");
                }
            }
        }

        var dbSizeAfter = await GetDatabaseSizeGbAsync(sqlInstance, ct).ConfigureAwait(false);

        sw.Stop();
        progress.Report($"[Step 6/6] Shrink database... done ({sw.Elapsed.TotalSeconds:F0}s)");
        _logService.Info("Step 6 complete in {Elapsed}s", sw.Elapsed.TotalSeconds);

        return dbSizeAfter;
    }

    private static bool IsBackupBlockingError(string message) =>
        message.Contains("serialized", StringComparison.OrdinalIgnoreCase) ||
        (message.Contains("backup", StringComparison.OrdinalIgnoreCase) && message.Contains("operation", StringComparison.OrdinalIgnoreCase)) ||
        message.Contains("file manipulation", StringComparison.OrdinalIgnoreCase);

    // ─── Helpers ─────────────────────────────────────────────────────────

    private async Task<double> GetDatabaseSizeGbAsync(string sqlInstance, CancellationToken ct)
    {
        try
        {
            const string sql = @"
                SELECT SUM(size * 8.0 / 1024 / 1024) AS SizeGB
                FROM sys.master_files
                WHERE database_id = DB_ID('SUSDB')
                    AND type = 0"; // type=0 = data files only

            var sizeGb = await _sqlService.ExecuteScalarAsync<double>(sqlInstance, "master", sql, 10, ct).ConfigureAwait(false);
            return sizeGb;
        }
        catch (Exception ex)
        {
            _logService.Warning("Could not get database size: {Error}", ex.Message);
            return -1;
        }
    }
}
