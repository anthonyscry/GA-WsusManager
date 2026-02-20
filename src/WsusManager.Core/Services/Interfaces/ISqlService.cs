using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Centralized SQL execution service for all WSUS database operations.
/// Manages connection string construction, TrustServerCertificate handling,
/// and timeout configuration. All methods accept CancellationToken and
/// configurable CommandTimeout (0 = unlimited for maintenance queries).
/// </summary>
public interface ISqlService
{
    /// <summary>
    /// Executes a scalar SQL query and returns the first column of the first row.
    /// </summary>
    /// <typeparam name="T">Return type of the scalar value.</typeparam>
    /// <param name="sqlInstance">SQL Server instance (e.g., "localhost\SQLEXPRESS").</param>
    /// <param name="database">Database name (e.g., "SUSDB" or "master").</param>
    /// <param name="query">SQL query to execute.</param>
    /// <param name="commandTimeoutSeconds">0 = unlimited (default); use for maintenance queries.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>The scalar result, or default(T) if result is null/DBNull.</returns>
    Task<T?> ExecuteScalarAsync<T>(
        string sqlInstance,
        string database,
        string query,
        int commandTimeoutSeconds = 0,
        CancellationToken ct = default);

    /// <summary>
    /// Executes a SQL non-query (INSERT, UPDATE, DELETE, DDL) and returns the row count.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance.</param>
    /// <param name="database">Database name.</param>
    /// <param name="query">SQL statement to execute.</param>
    /// <param name="commandTimeoutSeconds">0 = unlimited (default); use for maintenance queries.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>Number of rows affected.</returns>
    Task<int> ExecuteNonQueryAsync(
        string sqlInstance,
        string database,
        string query,
        int commandTimeoutSeconds = 0,
        CancellationToken ct = default);

    /// <summary>
    /// Executes a SQL query and maps the first row via a reader delegate.
    /// Returns a failed OperationResult if no rows are returned.
    /// </summary>
    /// <typeparam name="T">Return type from the reader mapper.</typeparam>
    /// <param name="sqlInstance">SQL Server instance.</param>
    /// <param name="database">Database name.</param>
    /// <param name="query">SQL SELECT query.</param>
    /// <param name="mapper">Function to convert a row to T.</param>
    /// <param name="commandTimeoutSeconds">0 = unlimited.</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>OperationResult with mapped data if successful.</returns>
    Task<OperationResult<T>> ExecuteReaderFirstAsync<T>(
        string sqlInstance,
        string database,
        string query,
        Func<System.Data.IDataReader, T> mapper,
        int commandTimeoutSeconds = 0,
        CancellationToken ct = default);

    /// <summary>
    /// Builds a connection string for the given SQL instance and database.
    /// Always includes Integrated Security=True and TrustServerCertificate=True.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance.</param>
    /// <param name="database">Database name.</param>
    /// <param name="connectTimeoutSeconds">Connection timeout (default 5s).</param>
    /// <returns>ADO.NET connection string.</returns>
    string BuildConnectionString(string sqlInstance, string database, int connectTimeoutSeconds = 5);
}
