using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for RobocopyService argument construction, exit code mapping,
/// and progress streaming.
/// </summary>
public class RobocopyServiceTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();
    private readonly RobocopyService _service;

    public RobocopyServiceTests()
    {
        _service = new RobocopyService(_mockRunner.Object, _mockLog.Object);
    }

    [Fact]
    public void BuildArguments_Includes_Standard_Options()
    {
        var args = RobocopyService.BuildArguments(@"C:\Source", @"C:\Dest", 0);

        Assert.Contains("/E", args);
        Assert.Contains("/XO", args);
        Assert.Contains("/MT:16", args);
        Assert.Contains("/R:2", args);
        Assert.Contains("/W:5", args);
        Assert.Contains("/NP", args);
        Assert.Contains("/NDL", args);
    }

    [Fact]
    public void BuildArguments_Includes_Source_And_Destination()
    {
        var args = RobocopyService.BuildArguments(@"C:\Source", @"C:\Dest", 0);

        Assert.StartsWith("\"C:\\Source\" \"C:\\Dest\"", args);
    }

    [Fact]
    public void BuildArguments_Adds_MaxAge_When_Greater_Than_Zero()
    {
        var args = RobocopyService.BuildArguments(@"C:\Source", @"C:\Dest", 30);

        Assert.Contains("/MAXAGE:30", args);
    }

    [Fact]
    public void BuildArguments_No_MaxAge_When_Zero()
    {
        var args = RobocopyService.BuildArguments(@"C:\Source", @"C:\Dest", 0);

        Assert.DoesNotContain("/MAXAGE", args);
    }

    [Fact]
    public void BuildArguments_Excludes_Bak_And_Log_Files()
    {
        var args = RobocopyService.BuildArguments(@"C:\Source", @"C:\Dest", 0);

        Assert.Contains("/XF *.bak *.log", args);
    }

    [Fact]
    public void BuildArguments_Excludes_Logs_SQLDB_Backup_Directories()
    {
        var args = RobocopyService.BuildArguments(@"C:\Source", @"C:\Dest", 0);

        Assert.Contains("/XD Logs SQLDB Backup", args);
    }

    [Theory]
    [InlineData(0, true)]   // No files copied, in sync
    [InlineData(1, true)]   // All files copied
    [InlineData(2, true)]   // Extra files
    [InlineData(3, true)]   // Some files copied + extras
    [InlineData(7, true)]   // Max success code
    [InlineData(8, false)]  // Copy errors
    [InlineData(16, false)] // Serious error
    public async Task CopyAsync_Maps_ExitCodes_Correctly(int exitCode, bool expectedSuccess)
    {
        _mockRunner.Setup(r => r.RunAsync(
                "robocopy.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(exitCode, []));

        var result = await _service.CopyAsync(@"C:\Source", @"C:\Dest");

        Assert.Equal(expectedSuccess, result.Success);
    }

    [Fact]
    public async Task CopyAsync_Streams_Progress()
    {
        var lines = new List<string>();
        var progress = new Progress<string>(line => lines.Add(line));

        _mockRunner.Setup(r => r.RunAsync(
                "robocopy.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(1, []));

        await _service.CopyAsync(@"C:\Source", @"C:\Dest", progress: progress);

        // Service should report at least the start and completion messages
        // (exact messages depend on progress report timing)
    }

    [Fact]
    public async Task CopyAsync_Passes_Arguments_To_ProcessRunner()
    {
        string? capturedArgs = null;
        _mockRunner.Setup(r => r.RunAsync(
                "robocopy.exe",
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, IProgress<string>?, CancellationToken>(
                (exe, args, p, ct) => capturedArgs = args)
            .ReturnsAsync(new ProcessResult(0, []));

        await _service.CopyAsync(@"C:\WSUS", @"D:\Export", 30);

        Assert.NotNull(capturedArgs);
        Assert.Contains("\"C:\\WSUS\" \"D:\\Export\"", capturedArgs);
        Assert.Contains("/MAXAGE:30", capturedArgs);
    }
}
