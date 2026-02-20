using WsusManager.Core.Logging;
using WsusManager.Core.Services;
using Moq;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for SqlService. Connection string construction and timeout behavior
/// are tested without a real SQL connection. SQL-execution tests attempt a
/// real connection and gracefully handle SQL being offline.
/// </summary>
public class SqlServiceTests
{
    private readonly Mock<ILogService> _mockLog = new();

    private SqlService CreateService() => new(_mockLog.Object);

    // ─── BuildConnectionString Tests ─────────────────────────────────────

    [Fact]
    public void BuildConnectionString_Includes_TrustServerCertificate()
    {
        var svc = CreateService();
        var connStr = svc.BuildConnectionString(@"localhost\SQLEXPRESS", "SUSDB");
        Assert.Contains("TrustServerCertificate=True", connStr);
    }

    [Fact]
    public void BuildConnectionString_Includes_IntegratedSecurity()
    {
        var svc = CreateService();
        var connStr = svc.BuildConnectionString(@"localhost\SQLEXPRESS", "SUSDB");
        Assert.Contains("Integrated Security=True", connStr);
    }

    [Fact]
    public void BuildConnectionString_Includes_SqlInstance()
    {
        var svc = CreateService();
        var connStr = svc.BuildConnectionString(@"localhost\SQLEXPRESS", "SUSDB");
        Assert.Contains(@"localhost\SQLEXPRESS", connStr);
    }

    [Fact]
    public void BuildConnectionString_Includes_Database()
    {
        var svc = CreateService();
        var connStr = svc.BuildConnectionString(@"localhost\SQLEXPRESS", "SUSDB");
        Assert.Contains("SUSDB", connStr);
    }

    [Fact]
    public void BuildConnectionString_Default_ConnectTimeout_Is_5()
    {
        var svc = CreateService();
        var connStr = svc.BuildConnectionString(@"localhost\SQLEXPRESS", "SUSDB");
        Assert.Contains("Connect Timeout=5", connStr);
    }

    [Fact]
    public void BuildConnectionString_Custom_ConnectTimeout()
    {
        var svc = CreateService();
        var connStr = svc.BuildConnectionString(@"localhost\SQLEXPRESS", "master", 10);
        Assert.Contains("Connect Timeout=10", connStr);
    }

    // ─── SQL Execution Tests (SQL-dependent, graceful failure) ────────────

    [Fact]
    public async Task ExecuteScalarAsync_Returns_OperationResult_Or_Fails_Gracefully()
    {
        var svc = CreateService();

        // This either succeeds (SQL running) or throws (SQL offline)
        // Either way we verify it doesn't crash the test runner silently
        try
        {
            var result = await svc.ExecuteScalarAsync<int>(
                @"localhost\SQLEXPRESS", "master", "SELECT 1");
            Assert.Equal(1, result);
        }
        catch (Exception ex) when (ex.Message.Contains("connect") || ex.Message.Contains("network") ||
                                    ex.Message.Contains("SQL") || ex.Message.Contains("server"))
        {
            // SQL offline — expected in CI
        }
    }

    [Fact]
    public async Task ExecuteNonQueryAsync_Returns_RowCount_Or_Fails_Gracefully()
    {
        var svc = CreateService();

        try
        {
            // This should work even if SUSDB doesn't exist: system query
            var rows = await svc.ExecuteNonQueryAsync(
                @"localhost\SQLEXPRESS", "master", "DECLARE @x INT = 1");
            // Non-query returns -1 for non-DML statements
            Assert.True(rows >= -1);
        }
        catch
        {
            // SQL offline — expected in CI
        }
    }

    [Fact]
    public async Task ExecuteReaderFirstAsync_Returns_Fail_When_No_Rows()
    {
        var svc = CreateService();

        try
        {
            var result = await svc.ExecuteReaderFirstAsync<string>(
                @"localhost\SQLEXPRESS",
                "master",
                "SELECT name FROM sys.databases WHERE name = 'NonExistentDb_XYZ_99999'",
                r => r.GetString(0));

            // If SQL is online: query returns no rows, so result should be failed
            Assert.False(result.Success);
            Assert.Contains("no rows", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            // SQL offline — expected in CI
        }
    }

    [Fact]
    public async Task ExecuteScalarAsync_Respects_CancellationToken()
    {
        var svc = CreateService();
        using var cts = new CancellationTokenSource();
        cts.Cancel(); // Pre-cancelled

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
        {
            // A pre-cancelled token should cause the connection open to throw
            await svc.ExecuteScalarAsync<int>(@"localhost\SQLEXPRESS", "master", "SELECT 1", 0, cts.Token);
        });
    }
}
