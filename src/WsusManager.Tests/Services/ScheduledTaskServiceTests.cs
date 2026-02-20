using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for ScheduledTaskService: argument construction for Monthly/Weekly/Daily,
/// credential inclusion, elevated RunLevel, delete force flag, and query parsing.
/// </summary>
public class ScheduledTaskServiceTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private ScheduledTaskService CreateService() =>
        new(_mockRunner.Object, _mockLog.Object);

    private static ScheduledTaskOptions DefaultOptions(ScheduleType schedule = ScheduleType.Monthly) =>
        new()
        {
            TaskName = "WSUS Monthly Maintenance",
            Schedule = schedule,
            DayOfMonth = 15,
            DayOfWeek = DayOfWeek.Saturday,
            Time = "02:00",
            MaintenanceProfile = "Full",
            Username = @".\dod_admin",
            Password = "TestPass123!"
        };

    // ═══════════════════════════════════════════════════════════════
    // BuildCreateArguments Tests
    // ═══════════════════════════════════════════════════════════════

    [Fact]
    public void BuildArgs_Monthly_Includes_SC_MONTHLY_And_Day()
    {
        var options = DefaultOptions(ScheduleType.Monthly);
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe -File script.ps1");

        Assert.Contains("/SC MONTHLY", args);
        Assert.Contains("/D 15", args);
    }

    [Fact]
    public void BuildArgs_Weekly_Includes_SC_WEEKLY_And_DayOfWeek()
    {
        var options = DefaultOptions(ScheduleType.Weekly);
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe -File script.ps1");

        Assert.Contains("/SC WEEKLY", args);
        Assert.Contains("/D SAT", args);
    }

    [Fact]
    public void BuildArgs_Daily_Includes_SC_DAILY()
    {
        var options = DefaultOptions(ScheduleType.Daily);
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe -File script.ps1");

        Assert.Contains("/SC DAILY", args);
        Assert.DoesNotContain("/D ", args);
    }

    [Fact]
    public void BuildArgs_Includes_Credentials()
    {
        var options = DefaultOptions();
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe");

        Assert.Contains(@"/RU "".\dod_admin""", args);
        Assert.Contains(@"/RP ""TestPass123!""", args);
    }

    [Fact]
    public void BuildArgs_Includes_RL_HIGHEST()
    {
        var options = DefaultOptions();
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe");

        Assert.Contains("/RL HIGHEST", args);
    }

    [Fact]
    public void BuildArgs_Includes_Force_Flag()
    {
        var options = DefaultOptions();
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe");

        Assert.Contains("/F", args);
    }

    [Fact]
    public void BuildArgs_Includes_TaskName()
    {
        var options = DefaultOptions();
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe");

        Assert.Contains(@"/TN ""WSUS Monthly Maintenance""", args);
    }

    [Fact]
    public void BuildArgs_Includes_StartTime()
    {
        var options = DefaultOptions();
        var args = ScheduledTaskService.BuildCreateArguments(options, "powershell.exe");

        Assert.Contains("/ST 02:00", args);
    }

    // ═══════════════════════════════════════════════════════════════
    // DayOfWeekToSchtasks Tests
    // ═══════════════════════════════════════════════════════════════

    [Theory]
    [InlineData(DayOfWeek.Sunday, "SUN")]
    [InlineData(DayOfWeek.Monday, "MON")]
    [InlineData(DayOfWeek.Tuesday, "TUE")]
    [InlineData(DayOfWeek.Wednesday, "WED")]
    [InlineData(DayOfWeek.Thursday, "THU")]
    [InlineData(DayOfWeek.Friday, "FRI")]
    [InlineData(DayOfWeek.Saturday, "SAT")]
    public void DayOfWeekToSchtasks_Maps_Correctly(DayOfWeek day, string expected)
    {
        Assert.Equal(expected, ScheduledTaskService.DayOfWeekToSchtasks(day));
    }

    // ═══════════════════════════════════════════════════════════════
    // DeleteTaskAsync Tests
    // ═══════════════════════════════════════════════════════════════

    [Fact]
    public async Task Delete_Calls_Schtasks_Delete_With_Force()
    {
        var service = CreateService();

        _mockRunner
            .Setup(r => r.RunAsync(
                "schtasks.exe",
                It.Is<string>(a => a.Contains("/Delete") && a.Contains("/F")),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, ["Task deleted."]));

        var result = await service.DeleteTaskAsync("Test Task");

        Assert.True(result.Success);
        _mockRunner.Verify(r => r.RunAsync(
            "schtasks.exe",
            It.Is<string>(a => a.Contains("/Delete") && a.Contains("/F") && a.Contains("Test Task")),
            It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    // ═══════════════════════════════════════════════════════════════
    // QueryTaskAsync Tests
    // ═══════════════════════════════════════════════════════════════

    [Fact]
    public async Task Query_Returns_Ready_When_Output_Contains_Ready()
    {
        var service = CreateService();

        _mockRunner
            .Setup(r => r.RunAsync(
                "schtasks.exe",
                It.IsAny<string>(),
                null,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, [@"""WSUS Monthly Maintenance"",""3/15/2026 2:00:00 AM"",""Ready"""]));

        var result = await service.QueryTaskAsync("WSUS Monthly Maintenance");

        Assert.True(result.Success);
        Assert.Equal("Ready", result.Data);
    }

    [Fact]
    public async Task Query_Returns_Running_When_Output_Contains_Running()
    {
        var service = CreateService();

        _mockRunner
            .Setup(r => r.RunAsync("schtasks.exe", It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, [@"""Task"",""N/A"",""Running"""]));

        var result = await service.QueryTaskAsync("Task");

        Assert.Equal("Running", result.Data);
    }

    [Fact]
    public async Task Query_Returns_Disabled_When_Output_Contains_Disabled()
    {
        var service = CreateService();

        _mockRunner
            .Setup(r => r.RunAsync("schtasks.exe", It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, [@"""Task"",""N/A"",""Disabled"""]));

        var result = await service.QueryTaskAsync("Task");

        Assert.Equal("Disabled", result.Data);
    }

    [Fact]
    public async Task Query_Returns_Not_Found_When_Process_Fails()
    {
        var service = CreateService();

        _mockRunner
            .Setup(r => r.RunAsync("schtasks.exe", It.IsAny<string>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(1, ["ERROR: The system cannot find the file specified."]));

        var result = await service.QueryTaskAsync("NonExistent");

        Assert.Equal("Not Found", result.Data);
    }

    // ═══════════════════════════════════════════════════════════════
    // CreateTaskAsync Tests
    // ═══════════════════════════════════════════════════════════════

    [Fact]
    public async Task Create_Returns_Failure_When_Script_Not_Found()
    {
        var service = CreateService();

        // Delete step will be called first (returns anything)
        _mockRunner
            .Setup(r => r.RunAsync("schtasks.exe", It.Is<string>(a => a.Contains("/Delete")),
                null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ProcessResult(0, []));

        // Script won't be found in test environment
        var result = await service.CreateTaskAsync(DefaultOptions());

        Assert.False(result.Success);
        Assert.Contains("script not found", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void MaintenanceScriptName_Is_Correct()
    {
        Assert.Equal("Invoke-WsusMonthlyMaintenance.ps1", ScheduledTaskService.MaintenanceScriptName);
    }
}
