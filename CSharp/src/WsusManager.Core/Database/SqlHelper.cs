using Microsoft.Data.SqlClient;
using System.Data;

namespace WsusManager.Core.Database;

/// <summary>
/// Provides SQL Server connectivity and query execution.
/// Replaces PowerShell Invoke-WsusSqlcmd and Invoke-SqlScalar functions.
/// </summary>
public class SqlHelper
{
    private readonly string _connectionString;
    private readonly int _defaultTimeout;

    /// <summary>
    /// Initializes a new SQL helper instance.
    /// </summary>
    /// <param name="serverInstance">SQL Server instance (e.g., .\SQLEXPRESS)</param>
    /// <param name="database">Database name (default: SUSDB)</param>
    /// <param name="defaultTimeout">Default query timeout in seconds (default: 30)</param>
    /// <param name="useIntegratedSecurity">Use Windows authentication (default: true)</param>
    public SqlHelper(
        string serverInstance = @".\SQLEXPRESS",
        string database = "SUSDB",
        int defaultTimeout = 30,
        bool useIntegratedSecurity = true)
    {
        _defaultTimeout = defaultTimeout;

        var builder = new SqlConnectionStringBuilder
        {
            DataSource = serverInstance,
            InitialCatalog = database,
            IntegratedSecurity = useIntegratedSecurity,
            TrustServerCertificate = true, // Required for SQL Server 2022+
            Encrypt = true,
            ConnectTimeout = 15,
            ApplicationName = "WSUS Manager"
        };

        _connectionString = builder.ConnectionString;
    }

    /// <summary>
    /// Executes a SQL query and returns a DataTable with results.
    /// </summary>
    /// <param name="query">SQL query to execute</param>
    /// <param name="timeout">Query timeout in seconds (0 = unlimited)</param>
    /// <param name="parameters">Optional SQL parameters</param>
    /// <returns>DataTable containing query results</returns>
    public async Task<DataTable> ExecuteQueryAsync(
        string query,
        int? timeout = null,
        Dictionary<string, object>? parameters = null)
    {
        await using var connection = new SqlConnection(_connectionString);
        await using var command = new SqlCommand(query, connection)
        {
            CommandTimeout = timeout ?? _defaultTimeout,
            CommandType = CommandType.Text
        };

        // Add parameters if provided
        if (parameters != null)
        {
            foreach (var (key, value) in parameters)
            {
                command.Parameters.AddWithValue(key, value ?? DBNull.Value);
            }
        }

        await connection.OpenAsync();

        var dataTable = new DataTable();
        using var adapter = new SqlDataAdapter(command);
        adapter.Fill(dataTable);

        return dataTable;
    }

    /// <summary>
    /// Executes a SQL query synchronously and returns a DataTable.
    /// </summary>
    public DataTable ExecuteQuery(
        string query,
        int? timeout = null,
        Dictionary<string, object>? parameters = null)
    {
        return ExecuteQueryAsync(query, timeout, parameters).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Executes a SQL query and returns a scalar value.
    /// </summary>
    /// <typeparam name="T">Type of the scalar result</typeparam>
    /// <param name="query">SQL query to execute</param>
    /// <param name="timeout">Query timeout in seconds</param>
    /// <param name="parameters">Optional SQL parameters</param>
    /// <returns>Scalar value of type T</returns>
    public async Task<T?> ExecuteScalarAsync<T>(
        string query,
        int? timeout = null,
        Dictionary<string, object>? parameters = null)
    {
        await using var connection = new SqlConnection(_connectionString);
        await using var command = new SqlCommand(query, connection)
        {
            CommandTimeout = timeout ?? _defaultTimeout,
            CommandType = CommandType.Text
        };

        if (parameters != null)
        {
            foreach (var (key, value) in parameters)
            {
                command.Parameters.AddWithValue(key, value ?? DBNull.Value);
            }
        }

        await connection.OpenAsync();
        var result = await command.ExecuteScalarAsync();

        if (result == null || result == DBNull.Value)
            return default;

        return (T)Convert.ChangeType(result, typeof(T));
    }

    /// <summary>
    /// Executes a SQL query synchronously and returns a scalar value.
    /// </summary>
    public T? ExecuteScalar<T>(
        string query,
        int? timeout = null,
        Dictionary<string, object>? parameters = null)
    {
        return ExecuteScalarAsync<T>(query, timeout, parameters).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Executes a non-query SQL command (INSERT, UPDATE, DELETE, etc.).
    /// </summary>
    /// <param name="query">SQL command to execute</param>
    /// <param name="timeout">Query timeout in seconds</param>
    /// <param name="parameters">Optional SQL parameters</param>
    /// <returns>Number of rows affected</returns>
    public async Task<int> ExecuteNonQueryAsync(
        string query,
        int? timeout = null,
        Dictionary<string, object>? parameters = null)
    {
        await using var connection = new SqlConnection(_connectionString);
        await using var command = new SqlCommand(query, connection)
        {
            CommandTimeout = timeout ?? _defaultTimeout,
            CommandType = CommandType.Text
        };

        if (parameters != null)
        {
            foreach (var (key, value) in parameters)
            {
                command.Parameters.AddWithValue(key, value ?? DBNull.Value);
            }
        }

        await connection.OpenAsync();
        return await command.ExecuteNonQueryAsync();
    }

    /// <summary>
    /// Executes a non-query SQL command synchronously.
    /// </summary>
    public int ExecuteNonQuery(
        string query,
        int? timeout = null,
        Dictionary<string, object>? parameters = null)
    {
        return ExecuteNonQueryAsync(query, timeout, parameters).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Tests connectivity to the SQL Server instance.
    /// </summary>
    /// <returns>True if connection successful, false otherwise</returns>
    public async Task<bool> TestConnectionAsync()
    {
        try
        {
            await using var connection = new SqlConnection(_connectionString);
            await connection.OpenAsync();
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Tests connectivity synchronously.
    /// </summary>
    public bool TestConnection()
    {
        return TestConnectionAsync().GetAwaiter().GetResult();
    }

    /// <summary>
    /// Gets the database size in GB.
    /// </summary>
    public async Task<decimal> GetDatabaseSizeGBAsync()
    {
        const string query = @"
            SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB
            FROM sys.master_files
            WHERE database_id=DB_ID('SUSDB')";

        var result = await ExecuteScalarAsync<decimal?>(query);
        return result ?? 0;
    }

    /// <summary>
    /// Gets database statistics.
    /// </summary>
    public async Task<DatabaseStats?> GetDatabaseStatsAsync()
    {
        const string query = @"
            SELECT
                (SELECT COUNT(*) FROM tbRevisionSupersedesUpdate) AS SupersessionRecords,
                (SELECT COUNT(*) FROM tbRevision WHERE State = 2) AS DeclinedRevisions,
                (SELECT COUNT(*) FROM tbRevision WHERE State = 3) AS SupersededRevisions,
                (SELECT COUNT(*) FROM tbFileOnServer WHERE ActualState = 1) AS FilesPresent,
                (SELECT COUNT(*) FROM tbFileOnServer) AS FilesTotal,
                (SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2))
                 FROM master.sys.master_files
                 WHERE database_id=DB_ID('SUSDB')) AS SizeGB";

        var table = await ExecuteQueryAsync(query, timeout: 30);
        if (table.Rows.Count == 0) return null;

        var row = table.Rows[0];
        return new DatabaseStats
        {
            SupersessionRecords = Convert.ToInt32(row["SupersessionRecords"]),
            DeclinedRevisions = Convert.ToInt32(row["DeclinedRevisions"]),
            SupersededRevisions = Convert.ToInt32(row["SupersededRevisions"]),
            FilesPresent = Convert.ToInt32(row["FilesPresent"]),
            FilesTotal = Convert.ToInt32(row["FilesTotal"]),
            SizeGB = Convert.ToDecimal(row["SizeGB"])
        };
    }
}

/// <summary>
/// Database statistics model.
/// </summary>
public class DatabaseStats
{
    public int SupersessionRecords { get; set; }
    public int DeclinedRevisions { get; set; }
    public int SupersededRevisions { get; set; }
    public int FilesPresent { get; set; }
    public int FilesTotal { get; set; }
    public decimal SizeGB { get; set; }
}
