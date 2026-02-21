using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Unit tests for <see cref="ClientService"/> using mocked IProcessRunner and ILogService.
/// WinRmExecutor is constructed from the mock runner so its real logic is exercised.
/// </summary>
public class ClientServiceTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private ClientService CreateService()
    {
        var executor = new WinRmExecutor(_mockRunner.Object, _mockLog.Object);
        return new ClientService(executor, _mockLog.Object);
    }

    /// <summary>
    /// Creates a ProcessResult representing a successful process exit (exit code 0).
    /// </summary>
    private static ProcessResult SuccessResult(string output = "OK") =>
        new(0, [output]);

    /// <summary>
    /// Creates a ProcessResult representing a failed process exit (exit code 1).
    /// </summary>
    private static ProcessResult FailResult(string output = "Error occurred") =>
        new(1, [output]);

    /// <summary>
    /// Creates a ProcessResult that simulates a WinRM connectivity failure.
    /// </summary>
    private static ProcessResult WinRmFailResult() =>
        new(1, ["WinRM cannot complete the operation. Verify WSManFault."]);

    /// <summary>
    /// Captures progress messages reported during an operation.
    /// Uses a thread-safe collection because Progress&lt;T&gt; can post callbacks on the thread pool
    /// when there is no SynchronizationContext (e.g., in xUnit tests).
    /// </summary>
    private static (System.Collections.Concurrent.ConcurrentBag<string> Messages, IProgress<string> Progress) CreateProgressCapture()
    {
        var messages = new System.Collections.Concurrent.ConcurrentBag<string>();
        var progress = new Progress<string>(m => messages.Add(m));
        return (messages, progress);
    }

    // -------------------------------------------------------------------------
    // CancelStuckJobsAsync
    // -------------------------------------------------------------------------

    [Fact]
    public async Task CancelStuckJobs_Returns_Success_When_Remote_Succeeds()
    {
        // Arrange: Test-WSMan succeeds, then the remote command succeeds
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("WSMan responding"));

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("STEP=StopServices\nSTEP=ClearCache\nSTEP=RestartServices\nSTEP=Done"));

        var (_, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.CancelStuckJobsAsync("testhost01", progress);

        // Assert
        Assert.True(result.Success);
        Assert.Contains("testhost01", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CancelStuckJobs_Returns_Failure_When_WinRm_Unavailable()
    {
        // Arrange: Test-WSMan fails
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(WinRmFailResult());

        var (messages, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.CancelStuckJobsAsync("unreachable-host", progress);

        // Assert
        Assert.False(result.Success);
        Assert.Contains("WinRM", result.Message, StringComparison.OrdinalIgnoreCase);

        // Should not have made a remote command call
        _mockRunner.Verify(r => r.RunAsync("powershell.exe",
            It.Is<string>(a => a.Contains("Invoke-Command")),
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task CancelStuckJobs_Validates_Hostname_Returns_Failure_For_Empty()
    {
        // Arrange: no mock setup needed — validation should fail before any process call
        var service = CreateService();
        var (_, progress) = CreateProgressCapture();

        // Act
        var result = await service.CancelStuckJobsAsync("", progress);

        // Assert
        Assert.False(result.Success);
        Assert.Contains("empty", result.Message, StringComparison.OrdinalIgnoreCase);

        // No process should have been launched
        _mockRunner.Verify(r => r.RunAsync(
            It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    // -------------------------------------------------------------------------
    // ForceCheckInAsync
    // -------------------------------------------------------------------------

    [Fact]
    public async Task ForceCheckIn_Returns_Success_When_Remote_Succeeds()
    {
        // Arrange: WinRM available, remote command succeeds
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("STEP=GpUpdate\nSTEP=ResetAuth\nSTEP=DetectNow\nSTEP=ReportNow\nSTEP=Done"));

        var service = CreateService();
        var (_, progress) = CreateProgressCapture();

        // Act
        var result = await service.ForceCheckInAsync("testclient", progress);

        // Assert
        Assert.True(result.Success);
        Assert.Contains("testclient", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ForceCheckIn_Reports_Step_Progress()
    {
        // Arrange: WinRM available, remote command returns step markers
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, [
                "STEP=GpUpdate",
                "STEP=ResetAuth",
                "STEP=DetectNow",
                "STEP=ReportNow",
                "STEP=Done"
            ]));

        var (messages, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        await service.ForceCheckInAsync("testclient", progress);

        // Assert: progress messages should include [Step N/4] prefixes
        Assert.True(messages.Any(m => m.Contains("[Step") && m.Contains("/4")),
            $"Expected [Step N/4] progress message. Messages: {string.Join("; ", messages)}");
    }

    // -------------------------------------------------------------------------
    // TestConnectivityAsync
    // -------------------------------------------------------------------------

    [Fact]
    public async Task TestConnectivity_Parses_Port_Results_Correctly()
    {
        // Arrange: WinRM available, remote command returns parsed connectivity data
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, ["PORT8530=True;PORT8531=False;LATENCY=5"]));

        var (_, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.TestConnectivityAsync(
            "testclient", "http://wsus-server:8530", progress);

        // Assert
        Assert.True(result.Success);
        Assert.NotNull(result.Data);
        Assert.True(result.Data.Port8530Reachable);
        Assert.False(result.Data.Port8531Reachable);
        Assert.Equal(5, result.Data.LatencyMs);
    }

    [Fact]
    public async Task TestConnectivity_Returns_Failure_When_WinRm_Unavailable()
    {
        // Arrange: WinRM test fails
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(WinRmFailResult());

        var (_, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.TestConnectivityAsync(
            "disconnected-host", "http://wsus01:8530", progress);

        // Assert
        Assert.False(result.Success);
        Assert.Contains("WinRM", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TestConnectivity_Extracts_Server_From_Url()
    {
        // Verify the URL parsing extracts "wsus01" from "http://wsus01:8530"
        var extracted = ClientService.ExtractHostname("http://wsus01:8530");
        Assert.Equal("wsus01", extracted);

        // Also test https, no port
        Assert.Equal("wsus-server", ClientService.ExtractHostname("https://wsus-server"));
        Assert.Equal("192.168.1.100", ClientService.ExtractHostname("http://192.168.1.100:8531/path"));
        Assert.Equal("plainname", ClientService.ExtractHostname("plainname"));
    }

    // -------------------------------------------------------------------------
    // RunDiagnosticsAsync
    // -------------------------------------------------------------------------

    [Fact]
    public async Task RunDiagnostics_Parses_Registry_Values_Correctly()
    {
        // Arrange: WinRM available, remote returns populated diagnostic line
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        // Simulate output with known values
        const string diagnosticOutput =
            "WSUS=http://wsus01:8530;STATUS=http://wsus01:8530;USE=1;SVCS=wuauserv=Running,bits=Running,cryptsvc=Stopped;REBOOT=False;LASTCHECKIN=;AGENT=10.0.19041.1949";

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, [diagnosticOutput]));

        var (_, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.RunDiagnosticsAsync("testclient", progress);

        // Assert
        Assert.True(result.Success);
        Assert.NotNull(result.Data);
        Assert.Equal("http://wsus01:8530", result.Data.WsusServerUrl);
        Assert.Equal("http://wsus01:8530", result.Data.WsusStatusServerUrl);
        Assert.True(result.Data.UseWUServer);
        Assert.False(result.Data.PendingRebootRequired);
        Assert.Equal("10.0.19041.1949", result.Data.WindowsUpdateAgentVersion);
        Assert.Equal("Running", result.Data.ServiceStatuses["wuauserv"]);
        Assert.Equal("Running", result.Data.ServiceStatuses["bits"]);
        Assert.Equal("Stopped", result.Data.ServiceStatuses["cryptsvc"]);
    }

    [Fact]
    public async Task RunDiagnostics_Handles_Missing_Registry_Keys()
    {
        // Arrange: WinRM available, remote returns minimal/empty values
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        // Simulate PowerShell output where registry keys are not present (empty/null values)
        const string minimalOutput =
            "WSUS=;STATUS=;USE=;SVCS=;REBOOT=False;LASTCHECKIN=;AGENT=";

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, [minimalOutput]));

        var (_, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act — should not throw
        var result = await service.RunDiagnosticsAsync("freshclient", progress);

        // Assert: completes without exception, data has sensible defaults
        Assert.True(result.Success);
        Assert.NotNull(result.Data);
        Assert.Null(result.Data.WsusServerUrl);
        Assert.Null(result.Data.WsusStatusServerUrl);
        Assert.False(result.Data.UseWUServer);
        Assert.False(result.Data.PendingRebootRequired);
        Assert.Null(result.Data.WindowsUpdateAgentVersion);
        Assert.Empty(result.Data.ServiceStatuses);
    }

    // -------------------------------------------------------------------------
    // LookupErrorCode
    // -------------------------------------------------------------------------

    [Fact]
    public void LookupErrorCode_Returns_Known_Code()
    {
        var service = CreateService();

        // 0x80072EE2 = WININET_E_TIMEOUT
        var result = service.LookupErrorCode("0x80072EE2");

        Assert.True(result.Success);
        Assert.NotNull(result.Data);
        Assert.Equal("0x80072EE2", result.Data.Code);

        // Description should mention timeout or connection
        var description = result.Data.Description.ToLowerInvariant();
        Assert.True(
            description.Contains("timeout") || description.Contains("connect"),
            $"Expected 'timeout' or 'connect' in description: '{result.Data.Description}'");
    }

    [Fact]
    public void LookupErrorCode_Returns_Failure_For_Unknown_Code()
    {
        var service = CreateService();

        var result = service.LookupErrorCode("0xDEADBEEF");

        Assert.False(result.Success);
        Assert.Null(result.Data);
        Assert.Contains("not found", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void LookupErrorCode_Works_Without_0x_Prefix()
    {
        var service = CreateService();

        // Same code, without 0x prefix
        var result = service.LookupErrorCode("80072EE2");

        Assert.True(result.Success);
        Assert.NotNull(result.Data);
        Assert.Equal("0x80072EE2", result.Data.Code);
    }

    [Fact]
    public void LookupErrorCode_Works_With_Decimal_Input()
    {
        var service = CreateService();

        // -2147012894 is the signed decimal of 0x80072EE2
        var result = service.LookupErrorCode("-2147012894");

        Assert.True(result.Success);
        Assert.NotNull(result.Data);
        Assert.Equal("0x80072EE2", result.Data.Code);
    }

    // -------------------------------------------------------------------------
    // MassForceCheckInAsync
    // -------------------------------------------------------------------------

    [Fact]
    public async Task MassForceCheckIn_AllSucceed_Returns_True_And_Mentions_All_Hosts()
    {
        // Arrange: WinRM available for all 3 hosts, all remote commands succeed
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("STEP=GpUpdate\nSTEP=ResetAuth\nSTEP=DetectNow\nSTEP=ReportNow\nSTEP=Done"));

        var hostnames = new List<string> { "host01", "host02", "host03" };
        var (messages, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.MassForceCheckInAsync(hostnames, progress);

        // Assert
        Assert.True(result.Success);
        // Summary should mention 3/3 succeeded
        Assert.Contains("3/3", result.Message, StringComparison.OrdinalIgnoreCase);
        // Progress messages should include per-host markers
        Assert.True(messages.Any(m => m.Contains("host01")),
            "Expected progress message mentioning host01");
        Assert.True(messages.Any(m => m.Contains("host02")),
            "Expected progress message mentioning host02");
        Assert.True(messages.Any(m => m.Contains("host03")),
            "Expected progress message mentioning host03");
    }

    [Fact]
    public async Task MassForceCheckIn_OneHostFails_Returns_False_Shows_PassFail_Count()
    {
        // Arrange: WinRM available on host1 (success), host2 WinRM unavailable (fail)
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan") && a.Contains("host-ok")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan") && a.Contains("host-fail")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(WinRmFailResult());

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("STEP=Done"));

        var hostnames = new List<string> { "host-ok", "host-fail" };
        var (messages, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act
        var result = await service.MassForceCheckInAsync(hostnames, progress);

        // Assert
        Assert.False(result.Success);
        // Summary should show 1 passed, 1 failed
        Assert.Contains("1/2", result.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("1 failed", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task MassForceCheckIn_EmptyList_Returns_Failure_With_Descriptive_Message()
    {
        // Arrange: empty list — no mock setup needed, validation fires first
        var service = CreateService();
        var (_, progress) = CreateProgressCapture();

        // Act
        var result = await service.MassForceCheckInAsync([], progress);

        // Assert
        Assert.False(result.Success);
        Assert.Contains("hostname", result.Message, StringComparison.OrdinalIgnoreCase);

        // No process should have been launched
        _mockRunner.Verify(r => r.RunAsync(
            It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task MassForceCheckIn_WhitespaceOnlyEntries_TreatedAsEmpty()
    {
        // Arrange: list with only whitespace/empty entries — treated as empty
        var service = CreateService();
        var (_, progress) = CreateProgressCapture();

        // Act: whitespace-only entries should be filtered out, leaving an empty valid list
        var result = await service.MassForceCheckInAsync(["   ", "", "\t"], progress);

        // Assert: same behaviour as empty list
        Assert.False(result.Success);
        Assert.Contains("hostname", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task MassForceCheckIn_Cancellation_StopsProcessingRemainingHosts()
    {
        // Arrange: use CancellationTokenSource cancelled after first host
        using var cts = new CancellationTokenSource();

        int callCount = 0;
        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Test-WSMan")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(() =>
            {
                callCount++;
                // Cancel after the first Test-WSMan call
                if (callCount >= 1) cts.Cancel();
                return SuccessResult();
            });

        _mockRunner
            .Setup(r => r.RunAsync("powershell.exe",
                It.Is<string>(a => a.Contains("Invoke-Command")),
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("STEP=Done"));

        var hostnames = new List<string> { "host01", "host02", "host03" };
        var (messages, progress) = CreateProgressCapture();
        var service = CreateService();

        // Act: should throw OperationCanceledException from the ct.ThrowIfCancellationRequested()
        await Assert.ThrowsAsync<OperationCanceledException>(() =>
            service.MassForceCheckInAsync(hostnames, progress, cts.Token));
    }
}
