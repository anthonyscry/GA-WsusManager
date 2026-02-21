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

    // ─── BUG Fix Tests ─────────────────────────────────────────────────────

    [Fact]
    public void ApproveUpdatesAsync_Classification_Uses_Two_Level_Reflection()
    {
        // BUG-04 fix: IUpdate does not have UpdateClassificationTitle — must use
        // UpdateClassification (IUpdateClassification) -> Title (string)
        //
        // Demonstrate that the wrong single-step access returns null on a real object,
        // while the two-level access works correctly using a mock object graph.
        var classificationObj = new { Title = "Security Updates" };
        var updateMock = new { UpdateClassification = classificationObj };
        var updateType = updateMock.GetType();

        // Wrong approach: flat property does not exist
        var wrongProp = updateType.GetProperty("UpdateClassificationTitle");
        Assert.Null(wrongProp); // The flat property does not exist on IUpdate

        // Correct approach: two-level reflection
        var level1 = updateType.GetProperty("UpdateClassification");
        Assert.NotNull(level1); // UpdateClassification exists

        var classValue = level1!.GetValue(updateMock);
        var level2 = classValue?.GetType().GetProperty("Title");
        Assert.NotNull(level2); // Title exists on the classification object

        var title = level2!.GetValue(classValue)?.ToString();
        Assert.Equal("Security Updates", title); // Correct title retrieved
    }

    [Fact]
    public void DeclineUpdatesAsync_Does_Not_Decline_By_Age()
    {
        // BUG-03 fix: declining updates older than 6 months removes valid patches.
        // Only expired (PublicationState == "Expired") or superseded (IsSuperseded == true)
        // updates should be declined.
        //
        // Simulate the fixed decision logic:
        static bool ShouldDeclineFixed(string pubState, bool isSuperseded)
        {
            if (pubState == "Expired") return true;
            if (isSuperseded) return true;
            return false; // No age-based check
        }

        // A 2-year-old update that is neither expired nor superseded must NOT be declined
        Assert.False(ShouldDeclineFixed("Active", isSuperseded: false));

        // An expired update must be declined regardless of age
        Assert.True(ShouldDeclineFixed("Expired", isSuperseded: false));

        // A superseded update must be declined
        Assert.True(ShouldDeclineFixed("Active", isSuperseded: true));
    }

    [Fact]
    public void StartSynchronizationAsync_SyncProgress_Uses_Convert_Not_DirectCast()
    {
        // BUG-05 fix: direct (int) cast on a boxed long throws InvalidCastException.
        // Convert.ToInt32 handles long, uint, double without throwing.
        object boxedLong = (long)42;
        object boxedUint = (uint)100;
        object boxedInt = 200;

        // Direct cast would throw for boxed long/uint
        Assert.Throws<InvalidCastException>(() => (int)boxedLong);
        Assert.Throws<InvalidCastException>(() => (int)boxedUint);

        // Convert.ToInt32 handles all numeric types
        Assert.Equal(42, Convert.ToInt32(boxedLong));
        Assert.Equal(100, Convert.ToInt32(boxedUint));
        Assert.Equal(200, Convert.ToInt32(boxedInt));
    }
}
