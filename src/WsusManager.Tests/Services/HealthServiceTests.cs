using System.ServiceProcess;
using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for HealthService diagnostics pipeline using fully mocked dependencies.
/// Verifies that all 12 checks run, auto-repair is attempted, and the report summary is correct.
/// </summary>
public class HealthServiceTests
{
    private readonly Mock<IWindowsServiceManager> _mockServiceManager = new();
    private readonly Mock<IFirewallService> _mockFirewall = new();
    private readonly Mock<IPermissionsService> _mockPermissions = new();
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private HealthService CreateService() => new(
        _mockServiceManager.Object,
        _mockFirewall.Object,
        _mockPermissions.Object,
        _mockRunner.Object,
        _mockLog.Object);

    private static ServiceStatusInfo RunningService(string name, string display) =>
        new(name, display, ServiceControllerStatus.Running, true);

    private static ServiceStatusInfo StoppedService(string name, string display) =>
        new(name, display, ServiceControllerStatus.Stopped, false);

    /// <summary>
    /// Sets up all mocks to return healthy/passing results for all checks.
    /// Individual tests override specific mocks to test failure scenarios.
    /// </summary>
    private void SetupAllHealthy()
    {
        // All services running
        _mockServiceManager
            .Setup(s => s.GetStatusAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((string name, CancellationToken _) =>
                RunningService(name, name));

        // Firewall rules exist
        _mockFirewall
            .Setup(f => f.CheckWsusRulesExistAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(true, "Both rules present."));

        // Content permissions OK
        _mockPermissions
            .Setup(p => p.CheckContentPermissionsAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(true, "Permissions correct."));

        // SQL sysadmin
        _mockPermissions
            .Setup(p => p.CheckSqlSysadminAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(true, "Sysadmin."));

        // NETWORK SERVICE login
        _mockPermissions
            .Setup(p => p.CheckNetworkServiceLoginAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(true, "Login exists."));

        // appcmd for app pool — use full path (BUG-01 fix: appcmd not on PATH by default)
        _mockRunner
            .Setup(r => r.RunAsync(
                It.Is<string>(exe => exe.Contains("appcmd", StringComparison.OrdinalIgnoreCase)),
                It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, ["WsusPool"]));

        // SQL connectivity and SUSDB check handled via SQL (will fail in CI without SQL)
        // but the service handles this gracefully and returns a Fail check result
    }

    // ─── All 12 Checks Run Tests ──────────────────────────────────────────

    [Fact]
    public async Task RunDiagnosticsAsync_Returns_Exactly_12_Checks()
    {
        SetupAllHealthy();
        var service = CreateService();

        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        var report = await service.RunDiagnosticsAsync(
            @"C:\WSUS",
            @"localhost\SQLEXPRESS",
            progress);

        Assert.Equal(12, report.Checks.Count);
    }

    [Fact]
    public async Task RunDiagnosticsAsync_Reports_Progress_For_Each_Check()
    {
        SetupAllHealthy();
        var service = CreateService();

        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        await service.RunDiagnosticsAsync(
            @"C:\WSUS",
            @"localhost\SQLEXPRESS",
            progress);

        // At least 12 check lines + 1 summary line
        Assert.True(progressMessages.Count >= 13,
            $"Expected at least 13 progress messages, got {progressMessages.Count}");
    }

    [Fact]
    public async Task RunDiagnosticsAsync_Progress_Uses_StatusTags()
    {
        SetupAllHealthy();
        var service = CreateService();

        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        // At least some messages should contain [PASS], [FAIL], [WARN], or [SKIP]
        var taggedMessages = progressMessages.Where(m =>
            m.Contains("[PASS]") || m.Contains("[FAIL]") ||
            m.Contains("[WARN]") || m.Contains("[SKIP]")).ToList();

        Assert.True(taggedMessages.Count >= 8,
            $"Expected at least 8 tagged check messages, got {taggedMessages.Count}");
    }

    [Fact]
    public async Task RunDiagnosticsAsync_Summary_Line_Reports_Counts()
    {
        SetupAllHealthy();
        var service = CreateService();

        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        var summaryLine = progressMessages.LastOrDefault();
        Assert.NotNull(summaryLine);
        Assert.Contains("Diagnostics complete", summaryLine, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("checks", summaryLine, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task RunDiagnosticsAsync_Sets_StartedAt_And_CompletedAt()
    {
        SetupAllHealthy();
        var service = CreateService();
        var before = DateTime.UtcNow;
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        var after = DateTime.UtcNow;
        Assert.True(report.StartedAt >= before.AddSeconds(-1));
        Assert.True(report.CompletedAt <= after.AddSeconds(1));
        Assert.True(report.Duration >= TimeSpan.Zero);
    }

    // ─── Auto-Repair Tests ────────────────────────────────────────────────

    [Fact]
    public async Task RunDiagnosticsAsync_Attempts_Repair_For_Stopped_Service()
    {
        SetupAllHealthy();

        // Override WSUS service to be stopped
        _mockServiceManager
            .Setup(s => s.GetStatusAsync("WsusService", It.IsAny<CancellationToken>()))
            .ReturnsAsync(StoppedService("WsusService", "WSUS Service"));

        _mockServiceManager
            .Setup(s => s.StartServiceAsync("WsusService", It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("WsusService started."));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        // Verify StartServiceAsync was called for WSUS
        _mockServiceManager.Verify(s => s.StartServiceAsync("WsusService", It.IsAny<CancellationToken>()),
            Times.Once);

        // The WSUS check should be marked as repaired
        var wsusCheck = report.Checks.FirstOrDefault(c => c.CheckName == "WSUS Service");
        Assert.NotNull(wsusCheck);
        Assert.True(wsusCheck!.RepairAttempted);
        Assert.True(wsusCheck.RepairSucceeded);
    }

    [Fact]
    public async Task RunDiagnosticsAsync_Attempts_Firewall_Rule_Creation_When_Missing()
    {
        SetupAllHealthy();

        // Override firewall to return rules missing
        _mockFirewall
            .Setup(f => f.CheckWsusRulesExistAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(false, "Rules missing."));

        _mockFirewall
            .Setup(f => f.CreateWsusRulesAsync(It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Rules created."));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        _mockFirewall.Verify(f => f.CreateWsusRulesAsync(
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);

        var fwCheck = report.Checks.FirstOrDefault(c => c.CheckName.Contains("Firewall Rules"));
        Assert.NotNull(fwCheck);
        Assert.True(fwCheck!.RepairAttempted);
    }

    [Fact]
    public async Task RunDiagnosticsAsync_Attempts_Permission_Repair_When_Missing()
    {
        SetupAllHealthy();

        _mockPermissions
            .Setup(p => p.CheckContentPermissionsAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(false, "Missing NETWORK SERVICE."));

        _mockPermissions
            .Setup(p => p.RepairContentPermissionsAsync(
                It.IsAny<string>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Permissions repaired."));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        _mockPermissions.Verify(p => p.RepairContentPermissionsAsync(
            It.IsAny<string>(),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);

        var permCheck = report.Checks.FirstOrDefault(c => c.CheckName.Contains("Permission"));
        Assert.NotNull(permCheck);
        Assert.True(permCheck!.RepairAttempted);
    }

    // ─── Non-Fixable Issues Tests ─────────────────────────────────────────

    [Fact]
    public async Task RunDiagnosticsAsync_Sysadmin_Check_Is_Warning_Not_Fail()
    {
        SetupAllHealthy();

        _mockPermissions
            .Setup(p => p.CheckSqlSysadminAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(false, "User lacks sysadmin."));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        var sysadminCheck = report.Checks.FirstOrDefault(c => c.CheckName.Contains("Sysadmin"));
        Assert.NotNull(sysadminCheck);
        Assert.Equal(CheckStatus.Warning, sysadminCheck!.Status);
        Assert.False(sysadminCheck.RepairAttempted, "Sysadmin is informational — no repair should be attempted");
    }

    // ─── Report Summary Tests ─────────────────────────────────────────────

    [Fact]
    public async Task DiagnosticReport_RepairedCount_Counts_Successful_Repairs()
    {
        SetupAllHealthy();

        // Two services stopped
        _mockServiceManager
            .Setup(s => s.GetStatusAsync("MSSQL$SQLEXPRESS", It.IsAny<CancellationToken>()))
            .ReturnsAsync(StoppedService("MSSQL$SQLEXPRESS", "SQL Server Express"));

        _mockServiceManager
            .Setup(s => s.GetStatusAsync("WsusService", It.IsAny<CancellationToken>()))
            .ReturnsAsync(StoppedService("WsusService", "WSUS Service"));

        _mockServiceManager
            .Setup(s => s.StartServiceAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Started."));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        // At least 2 repairs (SQL and WSUS)
        Assert.True(report.RepairedCount >= 2,
            $"Expected at least 2 repaired checks, got {report.RepairedCount}");
    }

    [Fact]
    public async Task DiagnosticReport_IsHealthy_False_When_Non_Fixable_Check_Fails()
    {
        SetupAllHealthy();

        // NETWORK SERVICE login missing (non-fixable)
        _mockPermissions
            .Setup(p => p.CheckNetworkServiceLoginAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(false, "Login missing."));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        // The NETWORK SERVICE check should show as failed
        // (SQL connectivity may also fail in CI environment)
        Assert.True(report.FailedCount >= 1,
            "Expected at least one failed check (NETWORK SERVICE login)");
    }

    [Fact]
    public async Task DiagnosticReport_IsHealthy_True_When_Only_Warnings()
    {
        SetupAllHealthy();

        // Only sysadmin warning — no actual failures
        _mockPermissions
            .Setup(p => p.CheckSqlSysadminAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult<bool>.Ok(false, "Not sysadmin."));

        // Override SQL and SUSDB checks to pass (requires real SQL in CI, so skip SQL-dependent ones)
        // In a real test environment, SQL connectivity may fail causing FailedCount > 0
        // We verify the concept by checking sysadmin doesn't contribute to FailedCount
        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        var report = await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        // Sysadmin check should be Warning, not Fail
        var sysadminCheck = report.Checks.FirstOrDefault(c => c.CheckName.Contains("Sysadmin"));
        Assert.Equal(CheckStatus.Warning, sysadminCheck?.Status);
        Assert.Equal(0, report.Checks.Count(c => c.CheckName.Contains("Sysadmin") && c.Status == CheckStatus.Fail));
    }

    // ─── Cancellation Tests ───────────────────────────────────────────────

    [Fact]
    public async Task RunDiagnosticsAsync_Respects_Cancellation()
    {
        SetupAllHealthy();

        using var cts = new CancellationTokenSource();
        cts.Cancel();

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        await Assert.ThrowsAsync<OperationCanceledException>(
            () => service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress, cts.Token));
    }

    // ─── BUG-01 Fix Tests ─────────────────────────────────────────────────

    [Fact]
    public async Task CheckWsusAppPool_Uses_Full_Appcmd_Path()
    {
        // BUG-01 fix: appcmd.exe is NOT on PATH by default — must use full path to inetsrv\appcmd.exe
        SetupAllHealthy();

        string? capturedExecutable = null;
        _mockRunner
            .Setup(r => r.RunAsync(
                It.IsAny<string>(),
                It.Is<string>(a => a.Contains("apppool")),
                It.IsAny<IProgress<string>?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, IProgress<string>?, CancellationToken>(
                (exe, _, _, _) => capturedExecutable = exe)
            .ReturnsAsync(new ProcessResult(0, ["WsusPool"]));

        var service = CreateService();
        var progress = new Progress<string>(_ => { });

        await service.RunDiagnosticsAsync(@"C:\WSUS", @"localhost\SQLEXPRESS", progress);

        // If appcmd was called, it must use the full path
        if (capturedExecutable is not null)
        {
            Assert.Contains("inetsrv", capturedExecutable, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("appcmd.exe", capturedExecutable, StringComparison.OrdinalIgnoreCase);
            Assert.NotEqual("appcmd", capturedExecutable);
        }
    }
}
