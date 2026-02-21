using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

// ────────────────────────────────────────────────────────────────────────────────
// EXCEPTION PATH AUDIT (Phase 18-03):
// ────────────────────────────────────────────────────────────────────────────────
// WinRmExecutor.cs Exception Handling:
// [x] Constructor throws ArgumentNullException if processRunner is null
// [x] Constructor throws ArgumentNullException if logService is null
// [x] ExecuteRemoteAsync validates hostname - returns failure ProcessResult for invalid hostnames
// [x] ExecuteRemoteAsync handles WinRM connectivity errors - returns ProcessResult with error message
// [x] TestWinRmAsync validates hostname - returns false for invalid hostnames
// [x] No explicit try-catch blocks - uses ProcessResult.Success checks for error handling
//
// Note: WinRmExecutor doesn't have traditional try-catch blocks. Instead, it validates
// inputs upfront and returns ProcessResult objects with appropriate error information.
// ────────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Tests for WinRmExecutor. All tests are unit tests with mocked dependencies.
/// WinRM connectivity tests verify error handling without requiring actual WinRM.
/// </summary>
public class WinRmExecutorTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private WinRmExecutor CreateExecutor() => new(_mockRunner.Object, _mockLog.Object);

    // ─── Constructor Tests ─────────────────────────────────────────────────────

    [Fact]
    public void Constructor_Throws_When_ProcessRunner_Is_Null()
    {
        Assert.Throws<ArgumentNullException>(() =>
        {
            new WinRmExecutor(null!, _mockLog.Object);
        });
    }

    [Fact]
    public void Constructor_Throws_When_LogService_Is_Null()
    {
        Assert.Throws<ArgumentNullException>(() =>
        {
            new WinRmExecutor(_mockRunner.Object, null!);
        });
    }

    [Fact]
    public void Constructor_Can_Be_Instantiated()
    {
        var executor = CreateExecutor();
        Assert.NotNull(executor);
    }

    // ─── Hostname Validation Tests ─────────────────────────────────────────────

    [Fact]
    public async Task ExecuteRemoteAsync_Returns_Fail_For_Null_Hostname()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        var result = await executor.ExecuteRemoteAsync(null!, "Get-Service", progress);

        Assert.Equal(-1, result.ExitCode);
        Assert.Single(result.OutputLines);
        Assert.Contains("must not be empty", result.OutputLines[0], StringComparison.OrdinalIgnoreCase);
        Assert.Contains("[FAIL]", progressMessages[0]);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Returns_Fail_For_Empty_Hostname()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        var result = await executor.ExecuteRemoteAsync("", "Get-Service", progress);

        Assert.Equal(-1, result.ExitCode);
        Assert.Contains("must not be empty", result.OutputLines[0], StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Returns_Fail_For_Whitespace_Hostname()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        var result = await executor.ExecuteRemoteAsync("   ", "Get-Service", progress);

        Assert.Equal(-1, result.ExitCode);
        Assert.Contains("must not be empty", result.OutputLines[0], StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Returns_Fail_For_Invalid_Hostname_With_Special_Chars()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        var result = await executor.ExecuteRemoteAsync("bad@host#name!", "Get-Service", progress);

        Assert.Equal(-1, result.ExitCode);
        Assert.Contains("only letters, digits, hyphens, and dots are allowed",
            result.OutputLines[0], StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Returns_Fail_For_Hostname_Exceeding_Max_Length()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        // Hostname max length is 253 characters
        var longHostname = new string('a', 254);
        var result = await executor.ExecuteRemoteAsync(longHostname, "Get-Service", progress);

        Assert.Equal(-1, result.ExitCode);
        Assert.Contains("exceeds the maximum length", result.OutputLines[0], StringComparison.OrdinalIgnoreCase);
    }

    // ─── WinRM Connectivity Error Handling Tests ────────────────────────────────

    [Fact]
    public async Task ExecuteRemoteAsync_Handles_WinRM_Connection_Error()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        // Simulate WinRM connection error output
        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(
                1,
                new[] { "WinRM cannot complete the operation", "Error code 0x803380E4" }));

        var result = await executor.ExecuteRemoteAsync("server01", "Get-Service", progress);

        Assert.False(result.Success);
        Assert.Contains("Cannot connect to server01 via WinRM", result.OutputLines[^1], StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Handles_Access_Denied_Error()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        // Simulate access denied error
        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(
                1,
                new[] { "Access is denied", "Connecting to remote server failed" }));

        var result = await executor.ExecuteRemoteAsync("server01", "Get-Service", progress);

        Assert.False(result.Success);
        Assert.Contains("Cannot connect to server01 via WinRM", result.OutputLines[^1], StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Passes_Through_Process_Output_On_Success()
    {
        var executor = CreateExecutor();

        // Simulate successful command
        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(
                0,
                new[] { "Service1", "Service2", "Service3" }));

        var result = await executor.ExecuteRemoteAsync("server01", "Get-Service", null);

        Assert.True(result.Success);
        Assert.Equal(0, result.ExitCode);
        Assert.Equal(3, result.OutputLines.Count);
    }

    // ─── TestWinRmAsync Tests ───────────────────────────────────────────────────

    [Fact]
    public async Task TestWinRmAsync_Returns_False_For_Null_Hostname()
    {
        var executor = CreateExecutor();

        var result = await executor.TestWinRmAsync(null!);

        Assert.False(result);
    }

    [Fact]
    public async Task TestWinRmAsync_Returns_False_For_Empty_Hostname()
    {
        var executor = CreateExecutor();

        var result = await executor.TestWinRmAsync("");

        Assert.False(result);
    }

    [Fact]
    public async Task TestWinRmAsync_Returns_False_For_Invalid_Hostname()
    {
        var executor = CreateExecutor();

        var result = await executor.TestWinRmAsync("bad@host#");

        Assert.False(result);
    }

    [Fact]
    public async Task TestWinRmAsync_Returns_True_When_TestWSMan_Succeeds()
    {
        var executor = CreateExecutor();

        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, Array.Empty<string>()));

        var result = await executor.TestWinRmAsync("server01");

        Assert.True(result);
    }

    [Fact]
    public async Task TestWinRmAsync_Returns_False_When_TestWSMan_Fails()
    {
        var executor = CreateExecutor();

        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(1, new[] { "WinRM error" }));

        var result = await executor.TestWinRmAsync("server01");

        Assert.False(result);
    }

    // ─── Exception Path Tests (Phase 18-03) ───────────────────────────────────

    [Fact]
    public async Task ExecuteRemoteAsync_Handles_Non_WinRM_Command_Failure()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        // Simulate a non-WinRM error (e.g., script error, not connection error)
        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(
                1,
                new[] { "Script error: variable not defined" }));

        var result = await executor.ExecuteRemoteAsync("server01", "Get-InvalidVariable", progress);

        Assert.False(result.Success);
        // Should NOT include WinRM-specific message since error is not connectivity-related
        Assert.DoesNotContain("Cannot connect to server01 via WinRM",
            string.Join(" ", result.OutputLines), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExecuteRemoteAsync_Handles_WSManFault_Error()
    {
        var executor = CreateExecutor();
        var progressMessages = new List<string>();
        var progress = new Progress<string>(m => progressMessages.Add(m));

        // Simulate WSManFault error
        _mockRunner
            .Setup(r => r.RunAsync(
                "powershell.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(
                1,
                new[] { "WSManFault: Cannot connect to destination" }));

        var result = await executor.ExecuteRemoteAsync("server01", "Get-Service", progress);

        Assert.False(result.Success);
        Assert.Contains("Cannot connect to server01 via WinRM",
            result.OutputLines[^1], StringComparison.OrdinalIgnoreCase);
    }
}
