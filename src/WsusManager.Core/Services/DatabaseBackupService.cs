using System.Diagnostics;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Implements database backup and restore operations for the WSUS SUSDB.
/// Backup uses SQL BACKUP DATABASE with compression.
/// Restore uses the full workflow: verify, stop services, single-user, restore,
/// multi-user, wsusutil postinstall, restart services.
/// Both operations require SQL sysadmin permissions.
/// </summary>
public class DatabaseBackupService : IDatabaseBackupService
{
    private readonly ISqlService _sqlService;
    private readonly IPermissionsService _permissionsService;
    private readonly IWindowsServiceManager _serviceManager;
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    private const string SusDb = "SUSDB";
    private const string MasterDb = "master";

    public DatabaseBackupService(
        ISqlService sqlService,
        IPermissionsService permissionsService,
        IWindowsServiceManager serviceManager,
        IProcessRunner processRunner,
        ILogService logService)
    {
        _sqlService = sqlService;
        _permissionsService = permissionsService;
        _serviceManager = serviceManager;
        _processRunner = processRunner;
        _logService = logService;
    }

    // ─── BackupAsync ──────────────────────────────────────────────────────

    /// <inheritdoc/>
    public async Task<OperationResult> BackupAsync(
        string sqlInstance,
        string backupPath,
        IProgress<string> progress,
        CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        _logService.Info("Starting database backup to {BackupPath}", backupPath);

        // 1. Sysadmin check — hard block
        progress.Report("Checking SQL sysadmin permissions...");
        var sysadminResult = await _permissionsService.CheckSqlSysadminAsync(sqlInstance, ct);
        if (!sysadminResult.Success || !sysadminResult.Data)
        {
            var msg = "Database backup requires SQL sysadmin permissions. " +
                      "Current user is not a SQL sysadmin.";
            progress.Report($"[FAIL] {msg}");
            _logService.Warning("Backup blocked: user is not SQL sysadmin on {SqlInstance}", sqlInstance);
            return OperationResult.Fail(msg);
        }
        progress.Report("[OK] SQL sysadmin permissions confirmed.");

        // 2. Get current DB size for disk space estimate
        progress.Report("Getting current database size...");
        var dbSizeGb = await GetDatabaseSizeGbAsync(sqlInstance, ct);
        if (dbSizeGb > 0)
        {
            var estimatedBackupGb = dbSizeGb * 0.80; // compressed backup = ~80% of DB size
            progress.Report($"Database size: {dbSizeGb:F2} GB. Estimated backup size: {estimatedBackupGb:F2} GB");

            // 3. Check disk free space on backup destination drive
            var backupDir = Path.GetDirectoryName(backupPath) ?? Path.GetPathRoot(backupPath) ?? "C:\\";
            var diskFreeGb = GetDiskFreeGb(backupDir);

            if (diskFreeGb >= 0 && diskFreeGb < estimatedBackupGb)
            {
                var msg = $"Insufficient disk space for backup. " +
                          $"Estimated backup: {estimatedBackupGb:F2} GB, " +
                          $"Available: {diskFreeGb:F2} GB on {backupDir}";
                progress.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            if (diskFreeGb >= 0)
                progress.Report($"[OK] Disk space: {diskFreeGb:F2} GB available on backup drive.");
        }

        // 4. Execute backup
        // Sanitize path: escape single quotes to prevent SQL injection
        var safePath = backupPath.Replace("'", "''");
        var backupSql = $"BACKUP DATABASE {SusDb} TO DISK = N'{safePath}' WITH COMPRESSION, INIT";

        progress.Report($"Starting backup to: {backupPath}");
        progress.Report("This may take several minutes for large databases...");

        try
        {
            await _sqlService.ExecuteNonQueryAsync(sqlInstance, MasterDb, backupSql, 0, ct);
        }
        catch (OperationCanceledException)
        {
            return OperationResult.Fail("Backup was cancelled.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Backup SQL command failed");
            return OperationResult.Fail($"Backup failed: {ex.Message}", ex);
        }

        // 5. Report success with file size and duration
        sw.Stop();
        var fileInfo = new FileInfo(backupPath);
        if (fileInfo.Exists)
        {
            var fileSizeGb = fileInfo.Length / 1024.0 / 1024.0 / 1024.0;
            progress.Report($"[OK] Backup completed: {fileSizeGb:F2} GB in {sw.Elapsed.TotalSeconds:F0}s");
            progress.Report($"Backup file: {backupPath}");
        }
        else
        {
            progress.Report($"[OK] Backup completed in {sw.Elapsed.TotalSeconds:F0}s");
        }

        _logService.Info("Database backup completed in {Elapsed}s to {BackupPath}", sw.Elapsed.TotalSeconds, backupPath);
        return OperationResult.Ok($"Database backup completed successfully in {sw.Elapsed.TotalSeconds:F0}s.");
    }

    // ─── RestoreAsync ─────────────────────────────────────────────────────

    /// <inheritdoc/>
    public async Task<OperationResult> RestoreAsync(
        string sqlInstance,
        string backupPath,
        string contentPath,
        IProgress<string> progress,
        CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        _logService.Info("Starting database restore from {BackupPath}", backupPath);

        // 1. Sysadmin check — hard block
        progress.Report("Checking SQL sysadmin permissions...");
        var sysadminResult = await _permissionsService.CheckSqlSysadminAsync(sqlInstance, ct);
        if (!sysadminResult.Success || !sysadminResult.Data)
        {
            var msg = "Database restore requires SQL sysadmin permissions. " +
                      "Current user is not a SQL sysadmin.";
            progress.Report($"[FAIL] {msg}");
            _logService.Warning("Restore blocked: user is not SQL sysadmin on {SqlInstance}", sqlInstance);
            return OperationResult.Fail(msg);
        }
        progress.Report("[OK] SQL sysadmin permissions confirmed.");

        // 2. Verify backup file exists
        if (!File.Exists(backupPath))
        {
            var msg = $"Backup file not found: {backupPath}";
            progress.Report($"[FAIL] {msg}");
            return OperationResult.Fail(msg);
        }
        progress.Report($"[OK] Backup file found: {backupPath}");

        // 3. Verify backup integrity
        progress.Report("Verifying backup integrity...");
        var verifyResult = await VerifyBackupAsync(sqlInstance, backupPath, ct);
        if (!verifyResult.Success || !verifyResult.Data)
        {
            var msg = $"Backup verification failed: {verifyResult.Message}";
            progress.Report($"[FAIL] {msg}");
            return OperationResult.Fail(msg);
        }
        progress.Report("[OK] Backup integrity verified.");

        // 4. Stop WSUS and IIS services (SQL must stay running)
        progress.Report("Stopping WSUS service...");
        var wsusStop = await _serviceManager.StopServiceAsync("WsusService", ct);
        if (!wsusStop.Success)
            progress.Report($"[WARN] WsusService stop: {wsusStop.Message} (continuing anyway)");
        else
            progress.Report("[OK] WSUS service stopped.");

        progress.Report("Stopping IIS (W3SVC)...");
        var iisStop = await _serviceManager.StopServiceAsync("W3SVC", ct);
        if (!iisStop.Success)
            progress.Report($"[WARN] W3SVC stop: {iisStop.Message} (continuing anyway)");
        else
            progress.Report("[OK] IIS stopped.");

        // 5. Set SUSDB to single-user mode
        progress.Report("Setting database to single-user mode...");
        const string singleUserSql = "ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE";
        try
        {
            await _sqlService.ExecuteNonQueryAsync(sqlInstance, MasterDb, singleUserSql, 30, ct);
            progress.Report("[OK] Database set to single-user mode.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to set single-user mode");
            // Try to restart services before returning failure
            await RestartServicesAsync(sqlInstance, progress, ct);
            return OperationResult.Fail($"Failed to set database to single-user mode: {ex.Message}", ex);
        }

        // 6. Restore database
        var safePath = backupPath.Replace("'", "''");
        var restoreSql = $"RESTORE DATABASE {SusDb} FROM DISK = N'{safePath}' WITH REPLACE";

        progress.Report("Restoring database... (this may take several minutes)");
        try
        {
            await _sqlService.ExecuteNonQueryAsync(sqlInstance, MasterDb, restoreSql, 0, ct);
            progress.Report("[OK] Database restored.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Restore SQL command failed");
            // Try to set multi-user before returning failure
            try
            {
                await _sqlService.ExecuteNonQueryAsync(sqlInstance, MasterDb,
                    "ALTER DATABASE SUSDB SET MULTI_USER", 30, CancellationToken.None);
            }
            catch { /* best effort */ }
            await RestartServicesAsync(sqlInstance, progress, CancellationToken.None);
            return OperationResult.Fail($"Restore failed: {ex.Message}", ex);
        }

        // 7. Set SUSDB back to multi-user mode
        progress.Report("Setting database back to multi-user mode...");
        try
        {
            await _sqlService.ExecuteNonQueryAsync(sqlInstance, MasterDb,
                "ALTER DATABASE SUSDB SET MULTI_USER", 30, ct);
            progress.Report("[OK] Database set to multi-user mode.");
        }
        catch (Exception ex)
        {
            _logService.Warning("Failed to set multi-user mode: {Error}", ex.Message);
            progress.Report($"[WARN] Could not set multi-user mode: {ex.Message}");
        }

        // 8. Run wsusutil postinstall
        progress.Report("Running wsusutil postinstall...");
        var wsusutilPath = @"C:\Program Files\Update Services\Tools\wsusutil.exe";
        var wsusutilArgs = $"postinstall SQL_INSTANCE_NAME=\"{sqlInstance}\" CONTENT_DIR=\"{contentPath}\"";

        var postinstallResult = await _processRunner.RunAsync(wsusutilPath, wsusutilArgs, progress, ct);
        if (postinstallResult.Success)
            progress.Report("[OK] wsusutil postinstall completed.");
        else
            progress.Report($"[WARN] wsusutil postinstall exit code {postinstallResult.ExitCode} (check logs).");

        // 9. Restart WSUS and IIS services
        await RestartServicesAsync(sqlInstance, progress, ct);

        sw.Stop();
        progress.Report($"[OK] Database restore completed in {sw.Elapsed.TotalSeconds:F0}s.");
        _logService.Info("Database restore completed in {Elapsed}s from {BackupPath}", sw.Elapsed.TotalSeconds, backupPath);
        return OperationResult.Ok($"Database restore completed successfully in {sw.Elapsed.TotalSeconds:F0}s.");
    }

    // ─── VerifyBackupAsync ────────────────────────────────────────────────

    /// <inheritdoc/>
    public async Task<OperationResult<bool>> VerifyBackupAsync(
        string sqlInstance,
        string backupPath,
        CancellationToken ct)
    {
        try
        {
            _logService.Debug("Verifying backup: {BackupPath}", backupPath);

            var safePath = backupPath.Replace("'", "''");
            var verifySql = $"RESTORE VERIFYONLY FROM DISK = N'{safePath}' WITH CHECKSUM";

            // RESTORE VERIFYONLY returns no rows but throws SqlException on failure
            await _sqlService.ExecuteNonQueryAsync(sqlInstance, MasterDb, verifySql, 0, ct);

            _logService.Debug("Backup verification succeeded: {BackupPath}", backupPath);
            return OperationResult<bool>.Ok(true, "Backup file is valid.");
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logService.Warning("Backup verification failed for {BackupPath}: {Error}", backupPath, ex.Message);
            return OperationResult<bool>.Fail($"Backup verification failed: {ex.Message}", ex);
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private async Task RestartServicesAsync(string sqlInstance, IProgress<string> progress, CancellationToken ct)
    {
        progress.Report("Restarting IIS (W3SVC)...");
        var iisStart = await _serviceManager.StartServiceAsync("W3SVC", ct);
        progress.Report(iisStart.Success ? "[OK] IIS started." : $"[WARN] IIS start: {iisStart.Message}");

        progress.Report("Restarting WSUS service...");
        var wsusStart = await _serviceManager.StartServiceAsync("WsusService", ct);
        progress.Report(wsusStart.Success ? "[OK] WSUS service started." : $"[WARN] WSUS start: {wsusStart.Message}");
    }

    private async Task<double> GetDatabaseSizeGbAsync(string sqlInstance, CancellationToken ct)
    {
        try
        {
            const string sql = @"
                SELECT SUM(size * 8.0 / 1024 / 1024) AS SizeGB
                FROM sys.master_files
                WHERE database_id = DB_ID('SUSDB')
                    AND type = 0";

            var sizeGb = await _sqlService.ExecuteScalarAsync<double>(sqlInstance, MasterDb, sql, 10, ct);
            return sizeGb;
        }
        catch (Exception ex)
        {
            _logService.Warning("Could not get database size: {Error}", ex.Message);
            return -1;
        }
    }

    private static double GetDiskFreeGb(string path)
    {
        try
        {
            var drive = new DriveInfo(path);
            return drive.AvailableFreeSpace / 1024.0 / 1024.0 / 1024.0;
        }
        catch
        {
            return -1; // Can't determine disk space
        }
    }
}
