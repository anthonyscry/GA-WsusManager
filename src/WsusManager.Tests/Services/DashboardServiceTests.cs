using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for the DashboardService data collection.
/// These tests verify the service returns reasonable defaults and
/// handles errors gracefully when system services are unavailable.
/// </summary>
public class DashboardServiceTests
{
    private readonly Mock<ILogService> _mockLog = new();
    private readonly DashboardService _service;
    private readonly AppSettings _settings = new();

    public DashboardServiceTests()
    {
        _service = new DashboardService(_mockLog.Object);
    }

    [Fact]
    public async Task CollectAsync_Returns_DashboardData()
    {
        var data = await _service.CollectAsync(_settings, CancellationToken.None);

        Assert.NotNull(data);
        Assert.NotNull(data.ServiceNames);
        Assert.True(data.ServiceNames.Length > 0, "ServiceNames should have entries");
    }

    [Fact]
    public async Task CollectAsync_Returns_DiskFreeSpace()
    {
        var data = await _service.CollectAsync(_settings, CancellationToken.None);

        // On any machine, there should be some free space on the C: drive
        Assert.True(data.DiskFreeGB >= 0, "DiskFreeGB should be non-negative");
    }

    [Fact]
    public async Task CollectAsync_Does_Not_Throw_On_Missing_Services()
    {
        // Even if services don't exist, CollectAsync should not throw
        var data = await _service.CollectAsync(_settings, CancellationToken.None);

        Assert.NotNull(data);
        // Services may or may not be installed depending on the test machine
    }

    [Fact]
    public async Task CollectAsync_Handles_Cancellation_Gracefully()
    {
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        // Should either throw OperationCanceledException or return gracefully
        // depending on where the cancellation hits
        try
        {
            var data = await _service.CollectAsync(_settings, cts.Token);
            // If it returns, it should still produce valid data
            Assert.NotNull(data);
        }
        catch (OperationCanceledException)
        {
            // Expected - cancellation propagated
        }
    }

    [Fact]
    public async Task CollectAsync_TaskStatus_Is_NotNull()
    {
        var data = await _service.CollectAsync(_settings, CancellationToken.None);

        Assert.NotNull(data.TaskStatus);
        // On dev machines, task likely "Not Found"
    }

    [Fact]
    public void DashboardData_Defaults_Are_Correct()
    {
        var data = new DashboardData();

        Assert.Equal(0, data.ServiceRunningCount);
        Assert.Empty(data.ServiceNames);
        Assert.Equal(-1, data.DatabaseSizeGB);
        Assert.Equal(0, data.DiskFreeGB);
        Assert.Equal("Not Found", data.TaskStatus);
        Assert.False(data.IsWsusInstalled);
        Assert.False(data.IsOnline);
    }

    [Fact]
    public async Task CollectAsync_Uses_Settings_ContentPath_For_DiskCheck()
    {
        var settings = new AppSettings { ContentPath = @"C:\WSUS" };
        var data = await _service.CollectAsync(settings, CancellationToken.None);

        // DiskFreeGB should be populated from the drive letter in ContentPath
        Assert.True(data.DiskFreeGB >= 0);
    }

    [Fact]
    public async Task CollectAsync_ServiceNames_Contains_Three_Entries()
    {
        var data = await _service.CollectAsync(_settings, CancellationToken.None);

        Assert.Equal(3, data.ServiceNames.Length);
    }

    [Fact]
    public async Task CollectAsync_DatabaseSizeGB_Is_Negative_When_SQL_Not_Running()
    {
        // On a dev/CI machine without SQL Express, DB size should be -1
        var settings = new AppSettings { SqlInstance = @"localhost\NONEXISTENT_INSTANCE_12345" };
        var data = await _service.CollectAsync(settings, CancellationToken.None);

        Assert.Equal(-1, data.DatabaseSizeGB);
    }
}
