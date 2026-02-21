using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Provides backup and restore operations for the WSUS SUSDB database.
/// All operations require SQL sysadmin permissions (hard-blocked otherwise).
/// </summary>
public interface IDatabaseBackupService
{
    /// <summary>
    /// Backs up the SUSDB database to the specified file path.
    /// Pre-flight checks: sysadmin permission, disk space (80% of DB size estimate).
    /// Uses BACKUP DATABASE ... WITH COMPRESSION, INIT (unlimited timeout).
    /// Reports backup duration and file size on completion.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance (e.g., "localhost\SQLEXPRESS").</param>
    /// <param name="backupPath">Destination file path for the .bak file.</param>
    /// <param name="progress">Progress reporter for status messages.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>OperationResult indicating success or failure.</returns>
    Task<OperationResult> BackupAsync(
        string sqlInstance,
        string backupPath,
        IProgress<string> progress,
        CancellationToken ct);

    /// <summary>
    /// Restores the SUSDB database from a backup file.
    /// Workflow: verify backup integrity, stop WSUS/IIS (SQL stays running),
    /// set single-user, restore, set multi-user, wsusutil postinstall, restart services.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance.</param>
    /// <param name="backupPath">Source backup file (.bak).</param>
    /// <param name="contentPath">WSUS content directory (e.g., "C:\WSUS").</param>
    /// <param name="progress">Progress reporter for status messages.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>OperationResult indicating success or failure.</returns>
    Task<OperationResult> RestoreAsync(
        string sqlInstance,
        string backupPath,
        string contentPath,
        IProgress<string> progress,
        CancellationToken ct);

    /// <summary>
    /// Verifies a backup file integrity using RESTORE VERIFYONLY.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance.</param>
    /// <param name="backupPath">Backup file to verify.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>OperationResult with Data=true if backup is valid.</returns>
    Task<OperationResult<bool>> VerifyBackupAsync(
        string sqlInstance,
        string backupPath,
        CancellationToken ct);
}
