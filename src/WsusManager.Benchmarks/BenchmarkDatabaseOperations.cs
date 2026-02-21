using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Diagnosers;
using BenchmarkDotNet.Environments;
using BenchmarkDotNet.Jobs;
using Microsoft.Data.SqlClient;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;

namespace WsusManager.Benchmarks;

/// <summary>
/// Benchmarks for critical database operations.
/// Measures query performance for server status, update counts, database size checks,
/// and low-level SQL connection operations.
/// Real database benchmarks will fail without WSUS - this is expected behavior.
/// </summary>
[MemoryDiagnoser]
[SimpleJob(warmupCount: 10, iterationCount: 100, runtimeMoniker: RuntimeMoniker.Net80)]
[HtmlExporter]
[CsvExporter]
[RPlotExporter]
[StopOnFirstError]
public class BenchmarkDatabaseOperations
{

    private readonly string _connectionString = "Data Source=localhost\\SQLEXPRESS;Initial Catalog=SUSDB;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=5";

    private ISqlService _sqlService = null!;
    private IDashboardService _dashboardService = null!;

    [GlobalSetup]
    public void Setup()
    {
        var logService = new LogService();
        _sqlService = new SqlService(logService);
        _dashboardService = new DashboardService(logService, _sqlService);
    }

    [GlobalCleanup]
    public void Cleanup()
    {
        // Services don't need disposal in this implementation
    }

    // ─── Real Database Operations ─────────────────────────────────────────────

    /// <summary>
    /// Benchmark: Get server status via DashboardService.
    /// Measures the full dashboard collection including service checks and DB size.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("SQL", "Dashboard")]
    public async Task<DashboardData> GetServerStatus()
    {
        // Measure query performance for server status check
        try
        {
            var settings = new AppSettings
            {
                SqlInstance = "localhost\\SQLEXPRESS",
                ContentPath = "C:\\WSUS"
            };
            return await _dashboardService.CollectAsync(settings, CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // Expected - WSUS not available in CI
            // Still measures the query execution path
            return new DashboardData();
        }
    }

    /// <summary>
    /// Benchmark: Get database size query.
    /// Measures the SQL query performance for checking database file sizes.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("SQL", "Query")]
    public async Task<double?> GetDatabaseSize()
    {
        // Measure query performance for size check
        try
        {
            const string sql = @"
                SELECT SUM(size * 8.0 / 1024 / 1024) AS SizeGB
                FROM sys.master_files
                WHERE database_id = DB_ID('SUSDB')
                    AND type = 0";

            return await _sqlService.ExecuteScalarAsync<double>(
                "localhost\\SQLEXPRESS",
                "master",
                sql,
                10,
                CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            // Expected - WSUS not available in CI
            return null;
        }
    }

    // ─── SQL Connection Micro-benchmarks ───────────────────────────────────────

    /// <summary>
    /// Benchmark: Open a SQL connection.
    /// Measures the overhead of establishing a connection to SQL Server.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("SQL", "Connection")]
    public async Task<SqlConnection> OpenConnection()
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync().ConfigureAwait(false);
        return connection;
    }

    /// <summary>
    /// Benchmark: Execute a simple SQL query.
    /// Measures the overhead of opening a connection and executing a trivial query.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("SQL", "Query")]
    public async Task<int?> ExecuteSimpleQuery()
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync().ConfigureAwait(false);

        using var command = new SqlCommand("SELECT 1", connection);
        var result = await command.ExecuteScalarAsync().ConfigureAwait(false);
        return result != null ? Convert.ToInt32(result) : null;
    }

    /// <summary>
    /// Benchmark: Execute a parameterized query.
    /// Measures the overhead of parameterized queries with a simple WHERE clause.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("SQL", "Query")]
    public async Task<int?> ExecuteParameterizedQuery()
    {
        using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync().ConfigureAwait(false);

        using var command = new SqlCommand(
            "SELECT COUNT(*) FROM sys.databases WHERE name = @dbName",
            connection);
        command.Parameters.AddWithValue("@dbName", "SUSDB");
        var result = await command.ExecuteScalarAsync().ConfigureAwait(false);
        return result != null ? Convert.ToInt32(result) : null;
    }

    // ─── Mock Benchmarks (CI-compatible) ───────────────────────────────────────

    /// <summary>
    /// Benchmark: In-memory data processing.
    /// Simulates data processing work without SQL dependency for CI baseline.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("Mock", "Processing")]
    public int InMemoryDataProcessing()
    {
        // Simulate data processing work without SQL dependency
        var data = Enumerable.Range(1, 1000).Select(i => new
        {
            Id = i,
            Name = $"Update-{i}",
            IsApproved = i % 2 == 0
        }).ToList();

        // Simulate filtering and counting (common query patterns)
        var approved = data.Count(x => x.IsApproved);
        var pending = data.Count(x => !x.IsApproved);

        return approved + pending;
    }

    /// <summary>
    /// Benchmark: String processing (logging simulation).
    /// Simulates log message construction common in database operations.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("Mock", "String")]
    public string StringProcessing()
    {
        // Simulate log message construction (common in database operations)
        var updates = Enumerable.Range(1, 100).Select(i => $"Update-{i}").ToList();
        return string.Join(", ", updates);
    }

    /// <summary>
    /// Benchmark: LINQ projection and filtering.
    /// Simulates common data transformation patterns.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("Mock", "Linq")]
    public int LinqProjectionAndFiltering()
    {
        var items = Enumerable.Range(1, 500)
            .Select(i => new { Id = i, Value = i * 2 })
            .ToList();

        // Simulate filtering, projection, and aggregation
        var result = items
            .Where(x => x.Value > 100)
            .Select(x => x.Id)
            .Count();

        return result;
    }
}
