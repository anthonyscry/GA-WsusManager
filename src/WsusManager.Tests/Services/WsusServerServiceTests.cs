using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for WsusServerService. Since the WSUS API DLL is not available in
/// test environments, these tests verify behavior when the DLL is missing
/// and validate the service's contract behavior.
/// </summary>
public class WsusServerServiceTests
{
    private readonly Mock<ILogService> _mockLog = new();

    [Fact]
    public async Task ConnectAsync_Returns_Failure_When_WsusDll_Not_Found()
    {
        // The WSUS API DLL won't exist on dev/CI machines
        var service = new WsusServerService(_mockLog.Object);

        var result = await service.ConnectAsync();

        Assert.False(result.Success);
        Assert.Contains("WSUS API not found", result.Message);
    }

    [Fact]
    public void IsConnected_False_Initially()
    {
        var service = new WsusServerService(_mockLog.Object);

        Assert.False(service.IsConnected);
    }

    [Fact]
    public async Task StartSynchronizationAsync_Returns_Failure_When_Not_Connected()
    {
        var service = new WsusServerService(_mockLog.Object);

        var result = await service.StartSynchronizationAsync(null, CancellationToken.None);

        Assert.False(result.Success);
        Assert.Contains("Not connected", result.Message);
    }

    [Fact]
    public async Task GetLastSyncInfoAsync_Returns_Failure_When_Not_Connected()
    {
        var service = new WsusServerService(_mockLog.Object);

        var result = await service.GetLastSyncInfoAsync();

        Assert.False(result.Success);
        Assert.Contains("Not connected", result.Message);
    }

    [Fact]
    public async Task DeclineUpdatesAsync_Returns_Failure_When_Not_Connected()
    {
        var service = new WsusServerService(_mockLog.Object);

        var result = await service.DeclineUpdatesAsync(null, CancellationToken.None);

        Assert.False(result.Success);
        Assert.Contains("Not connected", result.Message);
    }

    [Fact]
    public async Task ApproveUpdatesAsync_Returns_Failure_When_Not_Connected()
    {
        var service = new WsusServerService(_mockLog.Object);

        var result = await service.ApproveUpdatesAsync(200, null, CancellationToken.None);

        Assert.False(result.Success);
        Assert.Contains("Not connected", result.Message);
    }

    [Fact]
    public async Task ConnectAsync_Supports_Cancellation()
    {
        var service = new WsusServerService(_mockLog.Object);
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => service.ConnectAsync(cts.Token));
    }

    [Fact]
    public async Task IsConnected_Remains_False_After_Failed_Connect()
    {
        var service = new WsusServerService(_mockLog.Object);

        // Connect will fail because WSUS API DLL is not present
        var result = await service.ConnectAsync();

        Assert.False(result.Success);
        Assert.False(service.IsConnected);
    }

    [Fact]
    public async Task ConnectAsync_Logs_Warning_When_Dll_Missing()
    {
        var service = new WsusServerService(_mockLog.Object);

        await service.ConnectAsync();

        _mockLog.Verify(l => l.Warning(
            It.Is<string>(s => s.Contains("WSUS API not found")),
            It.IsAny<object[]>()), Times.Once);
    }
}
