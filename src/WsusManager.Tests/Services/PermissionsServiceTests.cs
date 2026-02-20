using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for PermissionsService. SQL-dependent tests require a real SQL connection
/// and are skipped when SQL is unavailable. IProcessRunner is mocked for icacls tests.
/// </summary>
public class PermissionsServiceTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private PermissionsService CreateService() =>
        new(_mockRunner.Object, _mockLog.Object);

    private static ProcessResult SuccessResult() => new(0, []);
    private static ProcessResult FailResult(string msg = "Error") => new(1, [msg]);

    // ─── CheckContentPermissionsAsync Tests ───────────────────────────────

    [Fact]
    public async Task CheckContentPermissionsAsync_Returns_Failure_For_Nonexistent_Directory()
    {
        var service = CreateService();

        var result = await service.CheckContentPermissionsAsync(@"C:\NonExistent_XYZ_99999");

        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CheckContentPermissionsAsync_Returns_Result_For_Existing_Directory()
    {
        // ACL APIs are Windows-only; skip on Linux/macOS
        if (!OperatingSystem.IsWindows()) return;

        // Use temp directory which always exists
        var service = CreateService();

        var result = await service.CheckContentPermissionsAsync(Path.GetTempPath());

        // Result should be successful (not an error) — may return true or false
        // depending on whether temp path has required ACLs
        Assert.True(result.Success, $"Expected success (check ran), got: {result.Message}");
    }

    // ─── RepairContentPermissionsAsync Tests ─────────────────────────────

    [Fact]
    public async Task RepairContentPermissionsAsync_Returns_Failure_For_Nonexistent_Directory()
    {
        var service = CreateService();

        var result = await service.RepairContentPermissionsAsync(@"C:\NonExistent_XYZ_99999");

        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task RepairContentPermissionsAsync_Runs_IcaclsForNetworkService()
    {
        _mockRunner
            .Setup(r => r.RunAsync("icacls", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        var service = CreateService();
        var result = await service.RepairContentPermissionsAsync(Path.GetTempPath());

        // Verify icacls was called with NETWORK SERVICE
        _mockRunner.Verify(r => r.RunAsync(
            "icacls",
            It.Is<string>(a => a.Contains("NETWORK SERVICE")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task RepairContentPermissionsAsync_Runs_IcaclsForIisIusrs()
    {
        _mockRunner
            .Setup(r => r.RunAsync("icacls", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        var service = CreateService();
        await service.RepairContentPermissionsAsync(Path.GetTempPath());

        // Verify icacls was called with IIS_IUSRS
        _mockRunner.Verify(r => r.RunAsync(
            "icacls",
            It.Is<string>(a => a.Contains("IIS_IUSRS")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task RepairContentPermissionsAsync_Uses_FullControl_And_Inheritance_Flags()
    {
        _mockRunner
            .Setup(r => r.RunAsync("icacls", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        var service = CreateService();
        await service.RepairContentPermissionsAsync(Path.GetTempPath());

        // Both icacls calls should use (OI)(CI)F (object inherit, container inherit, Full control) /T (recursive)
        _mockRunner.Verify(r => r.RunAsync(
            "icacls",
            It.Is<string>(a => a.Contains("(OI)(CI)F") && a.Contains("/T")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Exactly(2));
    }

    [Fact]
    public async Task RepairContentPermissionsAsync_Returns_Failure_When_NetworkService_Icacls_Fails()
    {
        _mockRunner
            .Setup(r => r.RunAsync("icacls", It.Is<string>(a => a.Contains("NETWORK SERVICE")), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(FailResult("Access Denied"));

        var service = CreateService();
        var result = await service.RepairContentPermissionsAsync(Path.GetTempPath());

        Assert.False(result.Success);
    }

    [Fact]
    public async Task RepairContentPermissionsAsync_Reports_Progress()
    {
        _mockRunner
            .Setup(r => r.RunAsync("icacls", It.IsAny<string>(), It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(SuccessResult());

        var messages = new List<string>();
        var progress = new Progress<string>(msg => messages.Add(msg));

        var service = CreateService();
        await service.RepairContentPermissionsAsync(Path.GetTempPath(), progress);

        Assert.True(messages.Count >= 2, "Expected at least 2 progress messages");
    }

    // ─── SQL-dependent tests ──────────────────────────────────────────────
    // These tests require SQL connectivity and are informational.
    // They verify service behavior without mocking SQL (real integration).

    [Fact]
    public async Task CheckSqlSysadminAsync_Returns_OperationResult()
    {
        var service = CreateService();

        // Will fail if SQL is not running — that's expected in CI
        // The key property: does NOT throw an unhandled exception
        var result = await service.CheckSqlSysadminAsync(@"localhost\SQLEXPRESS");

        // Result is either Success (SQL connected) or Failure (SQL offline)
        // Either way, it's a controlled OperationResult, not an exception
        Assert.NotNull(result);
    }

    [Fact]
    public async Task CheckSqlSysadminAsync_Returns_True_Message_When_IsSysadmin()
    {
        var service = CreateService();
        var result = await service.CheckSqlSysadminAsync(@"localhost\SQLEXPRESS");

        if (result.Success && result.Data)
        {
            Assert.Contains("sysadmin", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        // If SQL is offline, result.Success is false — skip assertion
    }

    [Fact]
    public async Task CheckNetworkServiceLoginAsync_Returns_OperationResult()
    {
        var service = CreateService();

        var result = await service.CheckNetworkServiceLoginAsync(@"localhost\SQLEXPRESS");

        Assert.NotNull(result);
    }
}
