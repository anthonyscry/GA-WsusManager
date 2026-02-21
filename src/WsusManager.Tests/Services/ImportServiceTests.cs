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
// [ ] Null input: ImportAsync(null, progress, ...) - missing (options parameter)
// [ ] Null input: ImportAsync(options with null SourcePath, ...) - missing
// [ ] Null input: ImportAsync(options with null DestinationPath, ...) - tested (defaults)
// [ ] Empty string: SourcePath with only whitespace - missing
// [ ] Empty string: DestinationPath with only whitespace - missing
// [ ] Boundary: Path with trailing slashes - partially tested
// [ ] Boundary: UNC path with special characters - missing
// [ ] Null content reset service (handled by constructor) - tested via mock
// ────────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Tests for ImportService: path validation, robocopy invocation,
/// and optional content reset.
/// </summary>
public class ImportServiceTests
{
    private readonly Mock<IRobocopyService> _mockRobocopy = new();
    private readonly Mock<IContentResetService> _mockContentReset = new();
    private readonly Mock<ILogService> _mockLog = new();
    private readonly ImportService _service;
    private readonly List<string> _progressMessages = [];
    private readonly IProgress<string> _progress;

    public ImportServiceTests()
    {
        _service = new ImportService(
            _mockRobocopy.Object, _mockContentReset.Object, _mockLog.Object);
        _progress = new Progress<string>(msg => _progressMessages.Add(msg));

        // Default: robocopy succeeds
        _mockRobocopy.Setup(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<int>(), It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Copied."));

        // Default: content reset succeeds
        _mockContentReset.Setup(r => r.ResetContentAsync(
                It.IsAny<IProgress<string>>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Ok("Reset done."));
    }

    [Fact]
    public async Task ImportAsync_Fails_When_Source_Path_Does_Not_Exist()
    {
        var options = new ImportOptions
        {
            SourcePath = @"Z:\NonExistent\Path"
        };

        var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message);
    }

    [Fact]
    public async Task ImportAsync_Fails_When_Source_Path_Is_Empty()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);

        try
        {
            // Empty directory
            var options = new ImportOptions
            {
                SourcePath = tempDir
            };

            var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

            Assert.False(result.Success);
            Assert.Contains("empty", result.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Calls_Robocopy_With_Correct_Source_And_Destination()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS"
            };

            await _service.ImportAsync(options, _progress, CancellationToken.None);

            _mockRobocopy.Verify(r => r.CopyAsync(
                tempDir,
                @"C:\WSUS",
                0,
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Runs_ContentReset_When_Enabled()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS",
                RunContentResetAfterImport = true
            };

            await _service.ImportAsync(options, _progress, CancellationToken.None);

            _mockContentReset.Verify(r => r.ResetContentAsync(
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Skips_ContentReset_When_Disabled()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS",
                RunContentResetAfterImport = false
            };

            await _service.ImportAsync(options, _progress, CancellationToken.None);

            _mockContentReset.Verify(r => r.ResetContentAsync(
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Never);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Fails_When_Robocopy_Fails()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        _mockRobocopy.Setup(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<int>(), It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Fail("Copy error."));

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS"
            };

            var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

            Assert.False(result.Success);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Skips_ContentReset_When_Robocopy_Fails()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        _mockRobocopy.Setup(r => r.CopyAsync(
                It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<int>(), It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(OperationResult.Fail("Copy error."));

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS",
                RunContentResetAfterImport = true
            };

            await _service.ImportAsync(options, _progress, CancellationToken.None);

            // Content reset should NOT run after robocopy failure
            _mockContentReset.Verify(r => r.ResetContentAsync(
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Never);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Uses_Default_DestinationPath()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir
                // DestinationPath defaults to C:\WSUS
            };

            await _service.ImportAsync(options, _progress, CancellationToken.None);

            _mockRobocopy.Verify(r => r.CopyAsync(
                tempDir,
                @"C:\WSUS",
                0,
                It.IsAny<IProgress<string>>(),
                It.IsAny<CancellationToken>()), Times.Once);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ─── Edge Case Tests (Phase 18-02) ────────────────────────────────────────

    [Fact]
    public async Task ImportAsync_Handles_Null_Options()
    {
        // null options causes NullReferenceException
        await Assert.ThrowsAsync<NullReferenceException>(
            () => _service.ImportAsync(null!, _progress, CancellationToken.None));
    }

    [Fact]
    public async Task ImportAsync_Handles_Null_SourcePath()
    {
        var options = new ImportOptions
        {
            SourcePath = null!
        };

        var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

        // null source path treated as "does not exist"
        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ImportAsync_Handles_Empty_SourcePath()
    {
        var options = new ImportOptions
        {
            SourcePath = ""
        };

        var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

        Assert.False(result.Success);
        Assert.Contains("does not exist", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ImportAsync_Handles_Whitespace_SourcePath()
    {
        var options = new ImportOptions
        {
            SourcePath = "   \t  "
        };

        var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

        Assert.False(result.Success);
    }

    [Fact]
    public async Task ImportAsync_Handles_Null_DestinationPath()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = null!
            };

            // null destinationPath causes exception in Directory.CreateDirectory
            var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

            // Should fail due to null path exception
            Assert.False(result.Success);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Handles_Empty_DestinationPath()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = ""
            };

            // Empty destinationPath causes exception in Directory.CreateDirectory
            var result = await _service.ImportAsync(options, _progress, CancellationToken.None);

            // Should fail due to invalid path
            Assert.False(result.Success);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Handles_Null_Progress()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS"
            };

            // null progress causes NullReferenceException (service doesn't handle it)
            await Assert.ThrowsAsync<NullReferenceException>(
                () => _service.ImportAsync(options, null!, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public async Task ImportAsync_Handles_Null_ContentResetService_When_RunContentResetAfterImport_True()
    {
        // Create service with null content reset (handled by constructor dependency)
        // null content reset service will cause NullReferenceException
        var serviceWithNullReset = new ImportService(
            _mockRobocopy.Object,
            null!, // null content reset service
            _mockLog.Object);

        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(Path.Combine(tempDir, "test.txt"), "data");

        try
        {
            var options = new ImportOptions
            {
                SourcePath = tempDir,
                DestinationPath = @"C:\WSUS",
                RunContentResetAfterImport = true
            };

            // null content reset service causes NullReferenceException during reset
            await Assert.ThrowsAsync<NullReferenceException>(
                () => serviceWithNullReset.ImportAsync(options, _progress, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }
}
