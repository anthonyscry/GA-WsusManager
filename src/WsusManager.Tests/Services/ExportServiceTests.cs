using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Services;

// ────────────────────────────────────────────────────────────────────────────────
// EDGE CASE AUDIT (Phase 18-02):
// ────────────────────────────────────────────────────────────────────────────────
// High Priority - External data handlers (file paths, directory paths):
// [ ] Null input: ExportAsync(null, progress, ...) - missing (options parameter)
// [ ] Null input: ExportAsync(options with null SourcePath, ...) - missing
// [ ] Null input: ExportAsync(options with null FullExportPath, ...) - partially tested
// [ ] Null input: ExportAsync(options with null DifferentialExportPath, ...) - partially tested
// [ ] Empty string: SourcePath with only whitespace - missing
// [ ] Empty string: FullExportPath with only whitespace - partially tested
// [ ] Empty string: DifferentialExportPath with only whitespace - partially tested
// [ ] Boundary: ExportDays = 0 (no files) - missing
// [ ] Boundary: ExportDays = -1 (negative value) - missing
// [ ] Boundary: ExportDays = int.MaxValue (unrealistic large) - missing
// ────────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Tests for ExportService: path validation, full/differential modes,
/// and database backup copy.
/// </summary>
public class ExportServiceTests
{
    private readonly Mock<IRobocopyService> _mockRobocopy = new();
    private readonly Mock<ILogService> _mockLog = new();
    private readonly ExportService _service;
    private readonly List<string> _progressMessages = [];
    private readonly IProgress<string> _progress;

    public ExportServiceTests()
    {
        _service = new ExportService(_mockRobocopy.Object, _mockLog.Object);
        _progress = new Progress<string>(msg => _progressMessages.Add(msg));

        // Default: robocopy succeeds
        _mockRobocopy.Setup(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<int>(), It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Copied."));
    }

    [Fact]
    public async Task ExportAsync_Returns_Skip_When_Both_Paths_Blank()
    {
        var options = new ExportOptions
        {
            FullExportPath = null,
            DifferentialExportPath = null
        };

        var result = await _service.ExportAsync(options, _progress, CancellationToken.None);

        Assert.True(result.Success);
        Assert.Contains("skip", result.Message, StringComparison.OrdinalIgnoreCase);

        // Robocopy should not be called
        _mockRobocopy.Verify(r => r.CopyAsync(
            It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int>(), It.IsAny<IProgress<string>>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ExportAsync_Fails_When_Source_Path_Does_Not_Exist()
    {
        var options = new ExportOptions
        {
            SourcePath = @"Z:\NonExistent\Path",
            FullExportPath = @"D:\Export"
        };

        var result = await _service.ExportAsync(options, _progress, CancellationToken.None);

        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message);
    }

    [Fact]
    public async Task ExportAsync_Full_Export_Calls_Robocopy_With_Zero_MaxAge()
    {
        // Use temp directory as source
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);

        try
        {
            var options = new ExportOptions
            {
                SourcePath = tempDir,
                FullExportPath = @"D:\Export"
            };

            await _service.ExportAsync(options, _progress, CancellationToken.None);

            _mockRobocopy.Verify(r => r.CopyAsync(
                It.IsAny<string>(),
                It.Is<string>(d => d.Contains("WsusContent")),
                0, // maxAgeDays = 0 for full export
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ExportAsync_Differential_Export_Uses_YearMonth_Path_And_MaxAge()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);

        try
        {
            var options = new ExportOptions
            {
                SourcePath = tempDir,
                DifferentialExportPath = @"D:\DiffExport",
                ExportDays = 45
            };

            await _service.ExportAsync(options, _progress, CancellationToken.None);

            var now = DateTime.Now;
            var expectedPathPart = Path.Combine(now.Year.ToString(), now.ToString("MM"));

            _mockRobocopy.Verify(r => r.CopyAsync(
                It.IsAny<string>(),
                It.Is<string>(d => d.Contains(expectedPathPart) && d.Contains("WsusContent")),
                45, // maxAgeDays = ExportDays
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ExportAsync_Returns_Skip_When_Paths_Are_Empty_Strings()
    {
        var options = new ExportOptions
        {
            FullExportPath = "   ",
            DifferentialExportPath = ""
        };

        var result = await _service.ExportAsync(options, _progress, CancellationToken.None);

        Assert.True(result.Success);
        Assert.Contains("skip", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ExportAsync_Full_And_Differential_Both_Call_Robocopy()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);

        try
        {
            var options = new ExportOptions
            {
                SourcePath = tempDir,
                FullExportPath = @"D:\FullExport",
                DifferentialExportPath = @"D:\DiffExport",
                ExportDays = 30
            };

            await _service.ExportAsync(options, _progress, CancellationToken.None);

            // Both full (maxAge=0) and differential (maxAge=30) should call robocopy
            _mockRobocopy.Verify(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                0, It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);

            _mockRobocopy.Verify(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                30, It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ExportAsync_Uses_WsusContent_Subdirectory_When_Present()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var wsusContentDir = Path.Combine(tempDir, "WsusContent");
        Directory.CreateDirectory(wsusContentDir);

        try
        {
            var options = new ExportOptions
            {
                SourcePath = tempDir,
                FullExportPath = @"D:\Export"
            };

            await _service.ExportAsync(options, _progress, CancellationToken.None);

            // Source should be the WsusContent subdirectory
            _mockRobocopy.Verify(r => r.CopyAsync(
                wsusContentDir,
                It.IsAny<string>(),
                It.IsAny<int>(),
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ExportAsync_Succeeds_Even_When_Full_Export_Fails()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);

        // Full export fails but differential succeeds
        int callCount = 0;
        _mockRobocopy.Setup(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<int>(), It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(() =>
            {
                callCount++;
                return callCount == 1
                    ? OperationResult.Fail("Full export failed.")
                    : OperationResult.Ok("Diff export ok.");
            });

        try
        {
            var options = new ExportOptions
            {
                SourcePath = tempDir,
                FullExportPath = @"D:\Full",
                DifferentialExportPath = @"D:\Diff"
            };

            var result = await _service.ExportAsync(options, _progress, CancellationToken.None);

            // Export should still succeed (with warnings)
            Assert.True(result.Success);
            Assert.Contains("warning", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }
}
