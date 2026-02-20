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
            await conn.OpenAsync(ct);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            cmd.CommandTimeout = commandTimeoutSeconds; // 0 = unlimited

            var result = await cmd.ExecuteScalarAsync(ct);

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
            await conn.OpenAsync(ct);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            cmd.CommandTimeout = commandTimeoutSeconds; // 0 = unlimited

            return await cmd.ExecuteNonQueryAsync(ct);
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
            await conn.OpenAsync(ct);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = query;
            cmd.CommandTimeout = commandTimeoutSeconds;

            using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
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
}
