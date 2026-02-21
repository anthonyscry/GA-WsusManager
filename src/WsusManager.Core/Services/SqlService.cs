using Microsoft.Data.SqlClient;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Centralized SQL execution service for WSUS database operations.
/// All connection strings use Integrated Security and TrustServerCertificate.
/// Operations with commandTimeoutSeconds = 0 run with unlimited timeout —
/// required for maintenance queries (index rebuild, shrink, batch deletes).
/// </summary>
public class SqlService : ISqlService
{
    private readonly ILogService _logService;

    public SqlService(ILogService logService)
    {
        _logService = logService;
    }

    /// <inheritdoc/>
    public string BuildConnectionString(string sqlInstance, string database, int connectTimeoutSeconds = 5) =>
        $"Data Source={sqlInstance};Initial Catalog={database};" +
        $"Integrated Security=True;TrustServerCertificate=True;" +
        $"Connect Timeout={connectTimeoutSeconds}";

    /// <inheritdoc/>
    public async Task<T?> ExecuteScalarAsync<T>(
        string sqlInstance,
        string database,
        string query,
        int commandTimeoutSeconds = 0,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Debug("ExecuteScalar on {Database}: {Query}", database, TruncateForLog(query));

            var connStr = BuildConnectionString(sqlInstance, database);
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            cmd.CommandTimeout = commandTimeoutSeconds; // 0 = unlimited

            var result = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);

            if (result == null || result == DBNull.Value)
                return default;

            return (T)Convert.ChangeType(result, typeof(T));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "ExecuteScalar failed on {Database}: {Query}", database, TruncateForLog(query));
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task<int> ExecuteNonQueryAsync(
        string sqlInstance,
        string database,
        string query,
        int commandTimeoutSeconds = 0,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Debug("ExecuteNonQuery on {Database}: {Query}", database, TruncateForLog(query));

            var connStr = BuildConnectionString(sqlInstance, database);
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            cmd.CommandTimeout = commandTimeoutSeconds; // 0 = unlimited

            return await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "ExecuteNonQuery failed on {Database}: {Query}", database, TruncateForLog(query));
            throw;
        }
    }

    /// <inheritdoc/>
    public async Task<OperationResult<T>> ExecuteReaderFirstAsync<T>(
        string sqlInstance,
        string database,
        string query,
        Func<System.Data.IDataReader, T> mapper,
        int commandTimeoutSeconds = 0,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Debug("ExecuteReaderFirst on {Database}: {Query}", database, TruncateForLog(query));

            var connStr = BuildConnectionString(sqlInstance, database);
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            cmd.CommandTimeout = commandTimeoutSeconds;

            using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);

            if (!await reader.ReadAsync(ct).ConfigureAwait(false))
                return OperationResult<T>.Fail("Query returned no rows.");

            var result = mapper(reader);
            return OperationResult<T>.Ok(result);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "ExecuteReaderFirst failed on {Database}: {Query}", database, TruncateForLog(query));
            return OperationResult<T>.Fail($"SQL error: {ex.Message}", ex);
        }
    }

    private static string TruncateForLog(string query, int maxLength = 120) =>
        query.Length > maxLength ? query[..maxLength] + "..." : query;

    /// <summary>
    /// Fetches a page of updates from the WSUS database with optional filtering.
    /// Supports pagination for large result sets to enable lazy-loading scenarios.
    /// </summary>
    /// <param name="sqlInstance">SQL Server instance (e.g., "localhost\SQLEXPRESS").</param>
    /// <param name="pageNumber">Page number to fetch (1-based).</param>
    /// <param name="pageSize">Number of items per page (default: 100).</param>
    /// <param name="whereClause">Optional WHERE clause filter (without "WHERE" keyword).</param>
    /// <param name="ct">Cancellation token.</param>
    /// <returns>Paged result containing update metadata and pagination information.</returns>
    public async Task<PagedResult<UpdateInfo>> FetchUpdatesPageAsync(
        string sqlInstance,
        int pageNumber = 1,
        int pageSize = 100,
        string? whereClause = null,
        CancellationToken ct = default)
    {
        try
        {
            var offset = (pageNumber - 1) * pageSize;
            var where = BuildWhereClause(whereClause);

            // Count total matching records
            var countQuery = $@"
                SELECT COUNT(*) FROM tbUpdate
                WHERE {where};";

            _logService.Debug("Counting updates: {Query}", TruncateForLog(countQuery));

            var connStr = BuildConnectionString(sqlInstance, "SUSDB");
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using (var countCmd = conn.CreateCommand())
            {
                countCmd.CommandText = countQuery;
                countCmd.CommandTimeout = 30;
                var countResult = await countCmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
                var totalCount = countResult != null && countResult != DBNull.Value
                    ? Convert.ToInt32(countResult)
                    : 0;

                if (totalCount == 0)
                {
                    return new PagedResult<UpdateInfo>(Array.Empty<UpdateInfo>(), 0, pageNumber, pageSize);
                }

                // Fetch page using OFFSET-FETCH
                var dataQuery = $@"
                    SELECT TOP ({pageSize})
                        u.UpdateId, u.DefaultTitle, u.KBArticle, u.UpdateClassification,
                        u.CreationDate, u.Approved, u.Declined
                    FROM tbUpdate u
                    WHERE {where}
                    ORDER BY u.CreationDate DESC
                    OFFSET {offset} ROWS;";

                _logService.Debug("Fetching updates page {Page}/{PageSize}: {Query}",
                    pageNumber, pageSize, TruncateForLog(dataQuery));

                var items = new List<UpdateInfo>();

                using (var dataCmd = conn.CreateCommand())
                {
                    dataCmd.CommandText = dataQuery;
                    dataCmd.CommandTimeout = 30;

                    using var reader = await dataCmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
                    while (await reader.ReadAsync(ct).ConfigureAwait(false))
                    {
                        items.Add(MapUpdateInfo(reader));
                    }
                }

                return new PagedResult<UpdateInfo>(items, totalCount, pageNumber, pageSize);
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "FetchUpdatesPageAsync failed on page {Page}", pageNumber);
            throw;
        }
    }

    /// <summary>
    /// Builds a safe WHERE clause, defaulting to "1=1" if no clause is provided.
    /// </summary>
    private static string BuildWhereClause(string? whereClause)
        => string.IsNullOrWhiteSpace(whereClause) ? "1=1" : whereClause;

    /// <summary>
    /// Maps a SqlDataReader row to an UpdateInfo record.
    /// </summary>
    private static UpdateInfo MapUpdateInfo(SqlDataReader reader)
    {
        var updateId = reader.GetGuid(0);
        var title = reader.GetString(1);
        var kbArticle = reader.IsDBNull(2) ? null : reader.GetString(2);
        var classification = reader.IsDBNull(3) ? null : reader.GetString(3);
        var createdDate = reader.GetDateTime(4);
        var isApproved = reader.GetBoolean(5);
        var isDeclined = reader.GetBoolean(6);

        return new UpdateInfo(updateId, title, kbArticle, classification, createdDate, isApproved, isDeclined);
    }

    /// <inheritdoc/>
    public async Task<double> GetDatabaseSizeAsync(string sqlInstance, string databaseName, CancellationToken ct = default)
    {
        try
        {
            const string sql = @"
                SELECT SUM(size * 8.0 / 1024 / 1024) AS SizeGB
                FROM sys.master_files
                WHERE database_id = DB_ID(@DatabaseName)
                    AND type = 0"; // type=0 = data files only

            var connStr = BuildConnectionString(sqlInstance, "master");
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = sql;
            cmd.CommandTimeout = 10;
            cmd.Parameters.AddWithValue("@DatabaseName", databaseName);

            var result = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);

            if (result == null || result == DBNull.Value)
                return -1;

            return Convert.ToDouble(result);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logService.Warning("Could not get database size for {Database}: {Error}", databaseName, ex.Message);
            return -1;
        }
    }
}
