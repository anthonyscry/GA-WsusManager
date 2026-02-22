using Xunit;
using Xunit.Abstractions;
using WsusManager.Core.Services;
using WsusManager.Core.Models;

namespace WsusManager.Tests.Services;

/// <summary>
/// Unit tests for CSV export service (Phase 30).
/// Tests UTF-8 BOM, CSV format, field escaping, and cancellation.
/// </summary>
public class CsvExportServiceTests : IDisposable
{
    private readonly ITestOutputHelper _output;
    private readonly CsvExportService _service;
    private readonly string _tempPath;

    public CsvExportServiceTests(ITestOutputHelper output)
    {
        _output = output;
        _service = new CsvExportService();
        _tempPath = Path.Combine(Path.GetTempPath(), $"csv-test-{Guid.NewGuid()}");
        Directory.CreateDirectory(_tempPath);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempPath))
        {
            try
            {
                Directory.Delete(_tempPath, true);
            }
            catch
            {
                // Ignore cleanup errors
            }
        }
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldCreateCsvFile()
    {
        // Arrange
        var computers = CreateMockComputers(5);

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);

        // Assert
        Assert.True(File.Exists(filePath));
        Assert.Contains("WsusManager-Computers-", Path.GetFileName(filePath));
        Assert.EndsWith(".csv", Path.GetFileName(filePath));

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldIncludeUtf8Bom()
    {
        // Arrange
        var computers = CreateMockComputers(1);

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);
        var bytes = await File.ReadAllBytesAsync(filePath);

        // Assert - First 3 bytes should be UTF-8 BOM (EF BB BF)
        Assert.Equal(0xEF, bytes[0]);
        Assert.Equal(0xBB, bytes[1]);
        Assert.Equal(0xBF, bytes[2]);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldIncludeHeaderRow()
    {
        // Arrange
        var computers = CreateMockComputers(1);

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert
        Assert.Contains("Hostname,IP Address,Status,Last Sync,Pending Updates,OS Version", content);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldEscapeCommas()
    {
        // Arrange
        var computers = new List<ComputerInfo>
        {
            new("COMPUTER,TEST", "192.168.1.1", "Online", DateTime.Now, 0, "Windows Server 2022")
        };

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert - Comma should be quoted
        Assert.Contains("\"COMPUTER,TEST\"", content);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldEscapeQuotes()
    {
        // Arrange
        var computers = new List<ComputerInfo>
        {
            new("COMPUTER\"TEST", "192.168.1.1", "Online", DateTime.Now, 0, "Windows Server 2022")
        };

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert - Quote should be doubled
        Assert.Contains("\"COMPUTER\"\"TEST\"", content);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldExportAllComputers()
    {
        // Arrange
        var computers = CreateMockComputers(100);

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);
        var lines = await File.ReadAllLinesAsync(filePath);

        // Assert - Header + 100 data rows
        Assert.Equal(101, lines.Length);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportUpdatesAsync_ShouldIncludeAllColumns()
    {
        // Arrange
        var updates = CreateMockUpdates(1);

        // Act
        var filePath = await _service.ExportUpdatesAsync(updates, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert
        Assert.Contains("KB Number,Title,Classification,Approval Status,Approval Date", content);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportUpdatesAsync_ShouldIncludeUtf8Bom()
    {
        // Arrange
        var updates = CreateMockUpdates(1);

        // Act
        var filePath = await _service.ExportUpdatesAsync(updates, null, CancellationToken.None);
        var bytes = await File.ReadAllBytesAsync(filePath);

        // Assert
        Assert.Equal(0xEF, bytes[0]);
        Assert.Equal(0xBB, bytes[1]);
        Assert.Equal(0xBF, bytes[2]);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportUpdatesAsync_ShouldExportAllUpdates()
    {
        // Arrange
        var updates = CreateMockUpdates(50);

        // Act
        var filePath = await _service.ExportUpdatesAsync(updates, null, CancellationToken.None);
        var lines = await File.ReadAllLinesAsync(filePath);

        // Assert - Header + 50 data rows
        Assert.Equal(51, lines.Length);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldReportProgress()
    {
        // Arrange
        var computers = CreateMockComputers(250);
        var progressMessages = new List<string>();
        var progress = new Progress<string>(msg => progressMessages.Add(msg));

        // Act
        await _service.ExportComputersAsync(computers, progress, CancellationToken.None);

        // Assert - Should report progress at least twice (Creating + 100 + 100 + remaining)
        Assert.True(progressMessages.Count >= 2);

        // First message should be "Creating CSV file..."
        Assert.Contains("Creating", progressMessages[0]);

        // Should have at least one "Exported" message
        var exportedMessages = progressMessages.Where(m => m.Contains("Exported")).ToList();
        Assert.NotEmpty(exportedMessages);
    }

    [Fact]
    public async Task ExportComputersAsync_ShouldRespectCancellation()
    {
        // Arrange
        var computers = CreateMockComputers(10000);
        var cts = new CancellationTokenSource();

        // Act - Cancel immediately
        cts.Cancel();
        var exception = await Record.ExceptionAsync(async () =>
        {
            await _service.ExportComputersAsync(computers, null, cts.Token).ConfigureAwait(false);
        }).ConfigureAwait(false);

        // Assert - Should throw OperationCanceledException
        Assert.IsType<OperationCanceledException>(exception);
    }

    [Fact]
    public async Task ExportComputersAsync_EmptyList_ShouldCreateFileWithHeaderOnly()
    {
        // Arrange
        var computers = new List<ComputerInfo>();

        // Act
        var filePath = await _service.ExportComputersAsync(computers, null, CancellationToken.None);
        var lines = await File.ReadAllLinesAsync(filePath);

        // Assert - Header only, no data rows
        Assert.Single(lines);
        Assert.Contains("Hostname", lines[0]);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportUpdatesAsync_ShouldHandleSpecialCharacters()
    {
        // Arrange
        var updates = new List<UpdateInfo>
        {
            new(Guid.NewGuid(), "Update with \"quotes\" and, commas", "KB123456", "Security", DateTime.Now.AddDays(-1), true, false)
        };

        // Act
        var filePath = await _service.ExportUpdatesAsync(updates, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert
        Assert.Contains("\"\"quotes\"\" and, commas\"", content);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportUpdatesAsync_ShouldMapApprovalStatusCorrectly()
    {
        // Arrange
        var updates = new List<UpdateInfo>
        {
            new(Guid.NewGuid(), "Approved Update", "KB001", "Security", DateTime.Now, true, false),
            new(Guid.NewGuid(), "Declined Update", "KB002", "Critical", DateTime.Now, false, true),
            new(Guid.NewGuid(), "Not Approved Update", "KB003", "Updates", DateTime.Now, false, false)
        };

        // Act
        var filePath = await _service.ExportUpdatesAsync(updates, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert
        Assert.Contains("Approved", content);
        Assert.Contains("Declined", content);
        Assert.Contains("Not Approved", content);

        // Cleanup
        File.Delete(filePath);
    }

    [Fact]
    public async Task ExportUpdatesAsync_ShouldHandleNullKbArticle()
    {
        // Arrange
        var updates = new List<UpdateInfo>
        {
            new(Guid.NewGuid(), "Update without KB", null, "Updates", DateTime.Now, true, false)
        };

        // Act
        var filePath = await _service.ExportUpdatesAsync(updates, null, CancellationToken.None);
        var content = await File.ReadAllTextAsync(filePath);

        // Assert
        Assert.Contains("N/A", content);

        // Cleanup
        File.Delete(filePath);
    }

    private static List<ComputerInfo> CreateMockComputers(int count)
    {
        var computers = new List<ComputerInfo>(count);
        for (int i = 0; i < count; i++)
        {
            computers.Add(new ComputerInfo(
                $"COMPUTER-{i:D4}",
                $"192.168.1.{(i % 255) + 1}",
                "Online",
                DateTime.Now.AddHours(-i),
                i % 10,
                "Windows Server 2022"));
        }
        return computers;
    }

    private static List<UpdateInfo> CreateMockUpdates(int count)
    {
        var updates = new List<UpdateInfo>(count);
        var classifications = new[] { "Critical", "Security", "Definition", "Updates" };

        for (int i = 0; i < count; i++)
        {
            bool isApproved = i % 3 == 0;
            bool isDeclined = i % 3 == 1;

            updates.Add(new UpdateInfo(
                Guid.NewGuid(),
                $"Update {i + 1}",
                $"KB{i + 500000:D7}",
                classifications[i % classifications.Length],
                DateTime.Now.AddDays(-i % 30),
                isApproved,
                isDeclined));
        }
        return updates;
    }
}
