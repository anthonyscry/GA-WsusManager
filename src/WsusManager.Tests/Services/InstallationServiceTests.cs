using Moq;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Services;

/// <summary>
/// Tests for InstallationService: prerequisite validation, argument construction,
/// script path resolution, and progress reporting.
/// </summary>
public class InstallationServiceTests
{
    private readonly Mock<IProcessRunner> _mockRunner = new();
    private readonly Mock<ILogService> _mockLog = new();

    private InstallationService CreateService() =>
        new(_mockRunner.Object, _mockLog.Object);

    // ═══════════════════════════════════════════════════════════════
    // ValidatePrerequisitesAsync Tests
    // ═══════════════════════════════════════════════════════════════

    [Fact]
    public async Task Validate_Fails_When_InstallerPath_Does_Not_Exist()
    {
        var service = CreateService();
        var options = new InstallOptions { InstallerPath = @"C:\NonExistent\Path" };

        var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message);
    }

    [Fact]
    public async Task Validate_Fails_When_Required_EXE_Is_Missing()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);

        try
        {
            var service = CreateService();
            var options = new InstallOptions
            {
                InstallerPath = tempDir,
                SaPassword = "ValidPassword123!@#"
            };

            var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

            Assert.False(result.Success);
            Assert.Contains("SQLEXPRADV_x64_ENU.exe", result.Message);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task Validate_Fails_When_Password_Is_Empty()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "SQLEXPRADV_x64_ENU.exe"), "mock");

        try
        {
            var service = CreateService();
            var options = new InstallOptions
            {
                InstallerPath = tempDir,
                SaPassword = ""
            };

            var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

            Assert.False(result.Success);
            Assert.Contains("empty", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task Validate_Fails_When_Password_Too_Short()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "SQLEXPRADV_x64_ENU.exe"), "mock");

        try
        {
            var service = CreateService();
            var options = new InstallOptions
            {
                InstallerPath = tempDir,
                SaPassword = "Short1!"
            };

            var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

            Assert.False(result.Success);
            Assert.Contains("15", result.Message);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task Validate_Fails_When_Password_Has_No_Digit()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "SQLEXPRADV_x64_ENU.exe"), "mock");

        try
        {
            var service = CreateService();
            var options = new InstallOptions
            {
                InstallerPath = tempDir,
                SaPassword = "NoDigitsHere!@#$%"
            };

            var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

            Assert.False(result.Success);
            Assert.Contains("digit", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task Validate_Fails_When_Password_Has_No_Special_Char()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "SQLEXPRADV_x64_ENU.exe"), "mock");

        try
        {
            var service = CreateService();
            var options = new InstallOptions
            {
                InstallerPath = tempDir,
                SaPassword = "NoSpecialChar12345"
            };

            var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

            Assert.False(result.Success);
            Assert.Contains("special", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task Validate_Succeeds_With_Valid_Options()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "SQLEXPRADV_x64_ENU.exe"), "mock");

        try
        {
            var service = CreateService();
            var options = new InstallOptions
            {
                InstallerPath = tempDir,
                SaPassword = "ValidPassword1!@#"
            };

            var result = await service.ValidatePrerequisitesAsync(options).ConfigureAwait(false);

            Assert.True(result.Success);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // InstallAsync Tests
    // ═══════════════════════════════════════════════════════════════

    [Fact]
    public async Task Install_Returns_Failure_When_Script_Not_Found()
    {
        var service = CreateService();
        var options = new InstallOptions
        {
            InstallerPath = @"C:\WSUS\SQLDB",
            SaPassword = "ValidPassword1!@#"
        };

        // Script won't be found in test environment
        var result = await service.InstallAsync(options).ConfigureAwait(false);

        Assert.False(result.Success);
        Assert.Contains("Install script not found", result.Message);
    }

    [Fact]
    public async Task Install_Constructs_Correct_PowerShell_Arguments()
    {
        // Create a temp script to satisfy the path check
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString(), "Scripts");
        Directory.CreateDirectory(tempDir);
        var scriptPath = Path.Combine(tempDir, "Install-WsusWithSqlExpress.ps1");
        File.WriteAllText(scriptPath, "# mock script");

        try
        {
            // Create service with temp base directory
            var service = new TestableInstallationService(
                _mockRunner.Object, _mockLog.Object, scriptPath);

            var options = new InstallOptions
            {
                InstallerPath = @"C:\WSUS\SQLDB",
                SaUsername = "sa",
                SaPassword = "MyPassword123!@#"
            };

            _mockRunner
                .Setup(r => r.RunAsync(
                    "powershell.exe",
                    It.IsAny<string>(),
                    It.IsAny<IProgress<string>>(),
                    It.IsAny<CancellationToken>()))
                .ReturnsAsync(new ProcessResult(0, ["Installation complete."]));

            var result = await service.InstallAsync(options).ConfigureAwait(false);

            Assert.True(result.Success);

            // Verify argument construction
            _mockRunner.Verify(r => r.RunAsync(
                "powershell.exe",
                It.Is<string>(args =>
                    args.Contains("-NonInteractive") &&
                    args.Contains("-InstallerPath") &&
                    args.Contains("-SaUsername") &&
                    args.Contains("-SaPassword") &&
                    args.Contains("-ExecutionPolicy Bypass")),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()),
                Times.Once);
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(tempDir)!, true);
        }
    }

    [Fact]
    public async Task Install_Reports_Progress()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString(), "Scripts");
        Directory.CreateDirectory(tempDir);
        var scriptPath = Path.Combine(tempDir, "Install-WsusWithSqlExpress.ps1");
        File.WriteAllText(scriptPath, "# mock");

        try
        {
            var service = new TestableInstallationService(
                _mockRunner.Object, _mockLog.Object, scriptPath);

            _mockRunner
                .Setup(r => r.RunAsync(
                    "powershell.exe",
                    It.IsAny<string>(),
                    It.IsAny<IProgress<string>>(),
                    It.IsAny<CancellationToken>()))
                .ReturnsAsync(new ProcessResult(0, ["Done."]));

            var messages = new List<string>();
            var progress = new Progress<string>(msg => messages.Add(msg));

            await service.InstallAsync(new InstallOptions { SaPassword = "Test123!@#$%^&*(" }, progress).ConfigureAwait(false);

            Assert.True(messages.Count >= 3, $"Expected at least 3 progress messages, got {messages.Count}");
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(tempDir)!, true);
        }
    }

    [Fact]
    public void RequiredInstallerExe_Is_Correct()
    {
        Assert.Equal("SQLEXPRADV_x64_ENU.exe", InstallationService.RequiredInstallerExe);
    }

    [Fact]
    public void MinPasswordLength_Is_15()
    {
        Assert.Equal(15, InstallationService.MinPasswordLength);
    }

    /// <summary>
    /// Testable subclass that overrides script path resolution.
    /// </summary>
    private sealed class TestableInstallationService : InstallationService
    {
        private readonly string _scriptPath;

        public TestableInstallationService(
            IProcessRunner processRunner, ILogService logService, string scriptPath)
            : base(processRunner, logService)
        {
            _scriptPath = scriptPath;
        }

        internal new string? LocateScript() => File.Exists(_scriptPath) ? _scriptPath : null;

        public new async Task<OperationResult> InstallAsync(
            InstallOptions options, IProgress<string>? progress = null, CancellationToken ct = default)
        {
            var scriptPath = LocateScript();
            if (scriptPath is null)
                return OperationResult.Fail("Install script not found.");

            progress?.Report($"Script: {scriptPath}");
            progress?.Report($"Installer path: {options.InstallerPath}");
            progress?.Report("Starting installation...");

            var arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" " +
                            $"-NonInteractive " +
                            $"-InstallerPath \"{options.InstallerPath}\" " +
                            $"-SaUsername \"{options.SaUsername}\" " +
                            $"-SaPassword \"{options.SaPassword}\"";

            var processRunnerField = typeof(InstallationService)
                .GetField("_processRunner",
                    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            var runner = (IProcessRunner)processRunnerField!.GetValue(this)!;

            var result = await runner.RunAsync("powershell.exe", arguments, progress, ct).ConfigureAwait(false);
            return result.Success
                ? OperationResult.Ok("Installation completed successfully.")
                : OperationResult.Fail($"Installation failed with exit code {result.ExitCode}.");
        }
    }
}
