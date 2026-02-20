using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for FirewallService using mock IProcessRunner to avoid requiring
/// admin privileges or a real Windows environment.
/// </summary>
public class FirewallServiceTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private FirewallService CreateService() =>
        new(_mockRunner.Object, _mockLog.Object);

    private static ProcessResult SuccessResult(string output = "") =>
        new(ExitCode: 0, OutputLines: output.Length > 0 ? [output] : []);

    private static ProcessResult FailResult(string output = "No rules match") =>
        new(ExitCode: 1, OutputLines: [output]);

    // ─── CheckWsusRulesExistAsync Tests ───────────────────────────────────

    [Fact]
    public async Task CheckWsusRulesExistAsync_Returns_True_When_Both_Rules_Found()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("WSUS HTTP\"")), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Rule Name: WSUS HTTP"));

        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("WSUS HTTPS\"")), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Rule Name: WSUS HTTPS"));

        var service = CreateService();
        var result = await service.CheckWsusRulesExistAsync();

        Assert.True(result.Success);
        Assert.True(result.Data);
        Assert.Contains("Both", result.Message);
    }

    [Fact]
    public async Task CheckWsusRulesExistAsync_Returns_False_When_Http_Rule_Missing()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("WSUS HTTP\"")), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(FailResult());

        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("WSUS HTTPS\"")), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Rule Name: WSUS HTTPS"));

        var service = CreateService();
        var result = await service.CheckWsusRulesExistAsync();

        Assert.True(result.Success);
        Assert.False(result.Data);
        Assert.Contains("missing", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CheckWsusRulesExistAsync_Returns_False_When_Both_Rules_Missing()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(FailResult());

        var service = CreateService();
        var result = await service.CheckWsusRulesExistAsync();

        Assert.True(result.Success);
        Assert.False(result.Data);
    }

    [Fact]
    public async Task CheckWsusRulesExistAsync_Returns_Failure_On_Exception()
    {
        _mockRunner
            .Setup(r => r.RunAsync(It.IsAny<string>(), It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Process error"));

        var service = CreateService();
        var result = await service.CheckWsusRulesExistAsync();

        Assert.False(result.Success);
        Assert.Contains("Error", result.Message);
    }

    // ─── CreateWsusRulesAsync Tests ───────────────────────────────────────

    [Fact]
    public async Task CreateWsusRulesAsync_Runs_Correct_NetshCommands()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Ok."));

        var service = CreateService();
        var result = await service.CreateWsusRulesAsync();

        Assert.True(result.Success);

        // Verify HTTP rule (port 8530) was created
        _mockRunner.Verify(r => r.RunAsync(
            "netsh",
            It.Is<string>(a => a.Contains("8530")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);

        // Verify HTTPS rule (port 8531) was created
        _mockRunner.Verify(r => r.RunAsync(
            "netsh",
            It.Is<string>(a => a.Contains("8531")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task CreateWsusRulesAsync_Uses_Inbound_Allow_Protocol()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Ok."));

        var service = CreateService();
        await service.CreateWsusRulesAsync();

        // Both calls should specify dir=in, action=allow, protocol=TCP
        _mockRunner.Verify(r => r.RunAsync(
            "netsh",
            It.Is<string>(a => a.Contains("dir=in") && a.Contains("action=allow") && a.Contains("protocol=TCP")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Exactly(2));
    }

    [Fact]
    public async Task CreateWsusRulesAsync_Reports_Progress_For_Each_Rule()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Ok."));

        var progressMessages = new List<string>();
        // Use synchronous progress reporter to avoid race condition with Progress<T> thread dispatch
        var progress = new SynchronousProgress(msg => progressMessages.Add(msg));

        var service = CreateService();
        await service.CreateWsusRulesAsync(progress);

        // At least 4 messages: one "Creating..." + one "[OK]..." per rule = 4 total
        Assert.True(progressMessages.Count >= 4,
            $"Expected at least 4 progress messages, got {progressMessages.Count}: {string.Join(", ", progressMessages)}");
    }

    /// <summary>
    /// Synchronous IProgress implementation that invokes the callback inline
    /// instead of marshaling to a captured SynchronizationContext (which Progress&lt;T&gt; does).
    /// Prevents race conditions in unit tests.
    /// </summary>
    private sealed class SynchronousProgress(Action<string> callback) : IProgress<string>
    {
        public void Report(string value) => callback(value);
    }

    [Fact]
    public async Task CreateWsusRulesAsync_Returns_Failure_When_Http_Rule_Creation_Fails()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("8530")), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(FailResult("Error: Access Denied"));

        var service = CreateService();
        var result = await service.CreateWsusRulesAsync();

        Assert.False(result.Success);
        Assert.Contains("Failed", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CreateWsusRulesAsync_Returns_Failure_When_Https_Rule_Creation_Fails()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("8530")), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Ok."));

        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.Is<string>(a => a.Contains("8531")), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(FailResult("Error: Access Denied"));

        var service = CreateService();
        var result = await service.CreateWsusRulesAsync();

        Assert.False(result.Success);
    }

    [Fact]
    public async Task CreateWsusRulesAsync_Uses_WSUS_Rule_Names()
    {
        _mockRunner
            .Setup(r => r.RunAsync("netsh", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult("Ok."));

        var service = CreateService();
        await service.CreateWsusRulesAsync();

        // Verify HTTP rule (8530) and HTTPS rule (8531) are created separately
        // Use port number to distinguish since "WSUS HTTP" is a substring of "WSUS HTTPS"
        _mockRunner.Verify(r => r.RunAsync(
            "netsh",
            It.Is<string>(a => a.Contains("8530")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);

        _mockRunner.Verify(r => r.RunAsync(
            "netsh",
            It.Is<string>(a => a.Contains("8531")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }
}
