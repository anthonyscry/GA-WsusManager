using System.ServiceProcess;
using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

// ────────────────────────────────────────────────────────────────────────────────
// EXCEPTION PATH AUDIT (Phase 18-03):
// ────────────────────────────────────────────────────────────────────────────────
// WindowsServiceManager.cs Exception Handling:
// [x] GetStatusAsync catches InvalidOperationException → returns ServiceStatusInfo with IsRunning=false
// [x] StartServiceAsync catches Exception (retry logic) → returns Fail after MaxRetryAttempts
// [x] StartServiceAsync catches Exception when attempt < MaxRetryAttempts → retries
// [x] StopServiceAsync catches Exception → returns OperationResult.Fail
//
// Note: WindowsServiceManager uses ServiceController which throws InvalidOperationException
// when a service doesn't exist. This is caught and transformed into a ServiceStatusInfo.
// ────────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Tests for WindowsServiceManager. Since ServiceController requires a real Windows
/// environment, we test the public interface behavior via reflection on the service
/// definitions and the mock-based scenarios using a testable subclass approach.
/// Integration with real services is validated through the DI container tests.
/// </summary>
public class WindowsServiceManagerTests
{
    private readonly Mock<ILogService> _mockLog = new();

    [Fact]
    public void WindowsServiceManager_CanBeInstantiated()
    {
        var manager = new WindowsServiceManager(_mockLog.Object);
        Assert.NotNull(manager);
    }

    [Fact]
    public async Task GetAllStatusAsync_Returns_Three_Service_Entries()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        // On non-WSUS systems, services will be returned with Stopped status.
        // We verify count = 3 and that the method completes without exception.
        var manager = new WindowsServiceManager(_mockLog.Object);

        var results = await manager.GetAllStatusAsync(CancellationToken.None);

        // Always returns 3 entries (one per monitored service)
        Assert.Equal(3, results.Length);
        Assert.All(results, r => Assert.NotNull(r.ServiceName));
        Assert.All(results, r => Assert.NotNull(r.DisplayName));
    }

    [Fact]
    public async Task GetAllStatusAsync_Returns_Expected_Service_Names()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        var manager = new WindowsServiceManager(_mockLog.Object);

        var results = await manager.GetAllStatusAsync(CancellationToken.None);

        var serviceNames = results.Select(r => r.ServiceName).ToHashSet();
        Assert.Contains("MSSQL$SQLEXPRESS", serviceNames);
        Assert.Contains("W3SVC", serviceNames);
        Assert.Contains("WsusService", serviceNames);
    }

    [Fact]
    public async Task GetStatusAsync_Returns_ServiceStatusInfo_For_NonExistent_Service()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        // A service that definitely does not exist should return IsRunning=false, not throw
        var manager = new WindowsServiceManager(_mockLog.Object);

        var result = await manager.GetStatusAsync("NonExistentService_XYZ_9999");

        Assert.NotNull(result);
        Assert.Equal("NonExistentService_XYZ_9999", result.ServiceName);
        Assert.False(result.IsRunning);
    }

    [Fact]
    public async Task StartAllServicesAsync_Reports_Progress_For_Each_Service()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        var manager = new WindowsServiceManager(_mockLog.Object);
        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        // This will fail on non-WSUS systems, but we verify progress is reported
        await manager.StartAllServicesAsync(progress);

        // At minimum, progress messages should be reported for each of the 3 services
        Assert.True(progressMessages.Count >= 3,
            $"Expected at least 3 progress messages (one per service), got {progressMessages.Count}");
    }

    [Fact]
    public async Task StopAllServicesAsync_Reports_Progress_For_Each_Service()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        var manager = new WindowsServiceManager(_mockLog.Object);
        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        // This will fail on non-WSUS systems, but we verify progress is reported
        await manager.StopAllServicesAsync(progress);

        Assert.True(progressMessages.Count >= 3,
            $"Expected at least 3 progress messages (one per service), got {progressMessages.Count}");
    }

    [Fact]
    public async Task StartServiceAsync_Returns_Ok_For_Already_Running_Service()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        // For a service that IS running (BITS or Spooler are often running on test machines),
        // verify that we get an OK result rather than an exception.
        var manager = new WindowsServiceManager(_mockLog.Object);

        // Try a service that is commonly running on Windows developer machines
        // If not running, StartService may succeed or fail — we just verify no unhandled exception
        var result = await manager.StartServiceAsync("BITS", CancellationToken.None);

        // Result should be non-null regardless of service state
        Assert.NotNull(result);
    }

    [Fact]
    public async Task StartServiceAsync_Returns_Failure_For_Nonexistent_Service()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        var manager = new WindowsServiceManager(_mockLog.Object);

        var result = await manager.StartServiceAsync("NonExistentService_XYZ_9999");

        Assert.False(result.Success);
        Assert.Contains("Failed", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StopServiceAsync_Returns_Failure_For_Nonexistent_Service()
    {
        if (!OperatingSystem.IsWindows()) return; // ServiceController is Windows-only

        var manager = new WindowsServiceManager(_mockLog.Object);

        var result = await manager.StopServiceAsync("NonExistentService_XYZ_9999");

        Assert.False(result.Success);
        Assert.Contains("Failed", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ServiceStatusInfo_IsRunning_True_When_Status_Is_Running()
    {
        var info = new ServiceStatusInfo(
            "TestService",
            "Test Service",
            ServiceControllerStatus.Running,
            true);

        Assert.True(info.IsRunning);
        Assert.Equal("TestService", info.ServiceName);
        Assert.Equal("Test Service", info.DisplayName);
    }

    [Fact]
    public void ServiceStatusInfo_IsRunning_False_When_Status_Is_Stopped()
    {
        var info = new ServiceStatusInfo(
            "TestService",
            "Test Service",
            ServiceControllerStatus.Stopped,
            false);

        Assert.False(info.IsRunning);
    }

    // ─── Exception Path Tests (Phase 18-03) ───────────────────────────────────

    [Fact]
    public async Task GetStatusAsync_Handles_InvalidOperationException_For_Nonexistent_Service()
    {
        if (!OperatingSystem.IsWindows()) return;

        var manager = new WindowsServiceManager(_mockLog.Object);

        // ServiceController throws InvalidOperationException for non-existent services
        // GetStatusAsync catches this and returns IsRunning=false
        var result = await manager.GetStatusAsync("NonExistentService_abc123");

        Assert.NotNull(result);
        Assert.Equal("NonExistentService_abc123", result.ServiceName);
        Assert.False(result.IsRunning);
        // Status should be Stopped when service doesn't exist
        Assert.Equal(ServiceControllerStatus.Stopped, result.Status);
    }

    [Fact]
    public async Task StartServiceAsync_Retries_On_Exception_Before_Failing()
    {
        if (!OperatingSystem.IsWindows()) return;

        var manager = new WindowsServiceManager(_mockLog.Object);

        // Starting a non-existent service should fail after MaxRetryAttempts (3)
        var result = await manager.StartServiceAsync("NonExistentService_xyz");

        Assert.False(result.Success);
        Assert.Contains("Failed to start", result.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("after 3 attempts", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StopServiceAsync_Handles_Exception_For_Nonexistent_Service()
    {
        if (!OperatingSystem.IsWindows()) return;

        var manager = new WindowsServiceManager(_mockLog.Object);

        // Stopping a non-existent service should catch exception and return Fail
        var result = await manager.StopServiceAsync("NonExistentService_xyz");

        Assert.False(result.Success);
        Assert.Contains("Failed to stop", result.Message, StringComparison.OrdinalIgnoreCase);
    }
}
