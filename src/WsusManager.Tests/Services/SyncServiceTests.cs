using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for SyncService orchestration with different sync profiles.
/// </summary>
public class SyncServiceTests
{
    private readonly Mock<IWsusServerService> _mockWsus = new();
    private readonly Mock<ILogService> _mockLog = new();
    private readonly SyncService _service;
    private readonly List<string> _progressMessages = [];
    private readonly IProgress<string> _progress;

    public SyncServiceTests()
    {
        _service = new SyncService(_mockWsus.Object, _mockLog.Object);
        _progress = new Progress<string>(msg => _progressMessages.Add(msg));

        // Default setup: connect succeeds
        _mockWsus.Setup(w => w.ConnectAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Connected."));

        // Default: last sync info succeeds
        _mockWsus.Setup(w => w.GetLastSyncInfoAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<SyncResult>.Ok(
                new SyncResult("Succeeded", 10, 5, DateTime.UtcNow)));

        // Default: sync succeeds
        _mockWsus.Setup(w => w.StartSynchronizationAsync(
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Sync done."));

        // Default: decline succeeds
        _mockWsus.Setup(w => w.DeclineUpdatesAsync(
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<int>.Ok(15, "Declined 15."));

        // Default: approve succeeds
        _mockWsus.Setup(w => w.ApproveUpdatesAsync(
                It.IsAny<int>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<int>.Ok(8, "Approved 8."));
    }

    [Fact]
    public async Task FullSync_Runs_All_Steps()
    {
        var result = await _service.RunSyncAsync(
            SyncProfile.FullSync, 200, _progress, CancellationToken.None);

        Assert.True(result.Success);

        // Verify all steps were called
        _mockWsus.Verify(w => w.ConnectAsync(It.IsAny<CancellationToken>()), Times.Once);
        _mockWsus.Verify(w => w.GetLastSyncInfoAsync(It.IsAny<CancellationToken>()), Times.Once);
        _mockWsus.Verify(w => w.StartSynchronizationAsync(
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Once);
        _mockWsus.Verify(w => w.DeclineUpdatesAsync(
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Once);
        _mockWsus.Verify(w => w.ApproveUpdatesAsync(
            200, It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task QuickSync_Skips_Decline_But_Runs_Approval()
    {
        var result = await _service.RunSyncAsync(
            SyncProfile.QuickSync, 200, _progress, CancellationToken.None);

        Assert.True(result.Success);

        // Decline should NOT be called
        _mockWsus.Verify(w => w.DeclineUpdatesAsync(
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Never);

        // Approval should still be called
        _mockWsus.Verify(w => w.ApproveUpdatesAsync(
            200, It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task SyncOnly_Skips_Both_Decline_And_Approval()
    {
        var result = await _service.RunSyncAsync(
            SyncProfile.SyncOnly, 200, _progress, CancellationToken.None);

        Assert.True(result.Success);

        _mockWsus.Verify(w => w.DeclineUpdatesAsync(
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Never);
        _mockWsus.Verify(w => w.ApproveUpdatesAsync(
            It.IsAny<int>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunSyncAsync_Fails_When_Connect_Fails()
    {
        _mockWsus.Setup(w => w.ConnectAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Fail("Connection failed."));

        var result = await _service.RunSyncAsync(
            SyncProfile.FullSync, 200, _progress, CancellationToken.None);

        Assert.False(result.Success);

        // Sync should not be attempted
        _mockWsus.Verify(w => w.StartSynchronizationAsync(
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunSyncAsync_Fails_When_Sync_Fails()
    {
        _mockWsus.Setup(w => w.StartSynchronizationAsync(
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Fail("Sync timed out."));

        var result = await _service.RunSyncAsync(
            SyncProfile.FullSync, 200, _progress, CancellationToken.None);

        Assert.False(result.Success);
    }

    [Fact]
    public async Task FullSync_Passes_MaxAutoApproveCount_To_Approval()
    {
        await _service.RunSyncAsync(
            SyncProfile.FullSync, 150, _progress, CancellationToken.None);

        _mockWsus.Verify(w => w.ApproveUpdatesAsync(
            150, It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()), Times.Once);
    }
}
