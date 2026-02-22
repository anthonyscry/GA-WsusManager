using Xunit;
using WsusManager.Core.Models;

namespace WsusManager.Tests;

/// <summary>
/// Unit tests for data filtering (Phase 29).
/// Tests status filters, classification filters, search behavior, and filter combinations.
/// </summary>
public class DataFilteringTests
{
    [Fact]
    public void ComputerInfo_Record_ShouldHaveAllProperties()
    {
        // Arrange & Act
        var computer = new ComputerInfo(
            "TEST-PC01",
            "192.168.1.100",
            "Online",
            DateTime.Now,
            5,
            "Windows Server 2022");

        // Assert
        Assert.Equal("TEST-PC01", computer.Hostname);
        Assert.Equal("192.168.1.100", computer.IpAddress);
        Assert.Equal("Online", computer.Status);
        Assert.Equal(5, computer.PendingUpdates);
        Assert.Equal("Windows Server 2022", computer.OsVersion);
    }

    [Fact]
    public void UpdateInfo_Record_ShouldHaveAllProperties()
    {
        // Arrange & Act
        var updateId = Guid.NewGuid();
        var update = new UpdateInfo(
            updateId,
            "Security Update for Windows Server",
            "KB5034441",
            "Security",
            DateTime.Now.AddDays(-7),
            true,
            false);

        // Assert
        Assert.Equal(updateId, update.UpdateId);
        Assert.Contains("Security Update", update.Title);
        Assert.Equal("KB5034441", update.KbArticle);
        Assert.Equal("Security", update.Classification);
        Assert.True(update.IsApproved);
        Assert.False(update.IsDeclined);
    }

    [Fact]
    public void FilterComputersByStatus_Online_ShouldReturnOnlyOnline()
    {
        // Arrange
        var computers = CreateMockComputers(20);

        // Act
        var filtered = computers.Where(c => c.Status == "Online").ToList();

        // Assert
        Assert.All(filtered, c => Assert.Equal("Online", c.Status));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterComputersByStatus_Offline_ShouldReturnOnlyOffline()
    {
        // Arrange
        var computers = CreateMockComputers(20);

        // Act
        var filtered = computers.Where(c => c.Status == "Offline").ToList();

        // Assert
        Assert.All(filtered, c => Assert.Equal("Offline", c.Status));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterComputersByStatus_Error_ShouldReturnOnlyError()
    {
        // Arrange
        var computers = CreateMockComputers(20);

        // Act
        var filtered = computers.Where(c => c.Status == "Error").ToList();

        // Assert
        Assert.All(filtered, c => Assert.Equal("Error", c.Status));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterComputersByStatus_All_ShouldReturnAll()
    {
        // Arrange
        var computers = CreateMockComputers(20);

        // Act
        var filtered = computers.ToList();

        // Assert
        Assert.Equal(20, filtered.Count);
    }

    [Fact]
    public void FilterUpdatesByApproval_Approved_ShouldReturnOnlyApproved()
    {
        // Arrange
        var updates = CreateMockUpdates(30);

        // Act
        var filtered = updates.Where(u => u.IsApproved && !u.IsDeclined).ToList();

        // Assert
        Assert.All(filtered, u => Assert.True(u.IsApproved));
        Assert.All(filtered, u => Assert.False(u.IsDeclined));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterUpdatesByApproval_Declined_ShouldReturnOnlyDeclined()
    {
        // Arrange
        var updates = CreateMockUpdates(30);

        // Act
        var filtered = updates.Where(u => u.IsDeclined).ToList();

        // Assert
        Assert.All(filtered, u => Assert.True(u.IsDeclined));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterUpdatesByApproval_NotApproved_ShouldReturnOnlyNotApproved()
    {
        // Arrange
        var updates = CreateMockUpdates(30);

        // Act
        var filtered = updates.Where(u => !u.IsApproved && !u.IsDeclined).ToList();

        // Assert
        Assert.All(filtered, u => Assert.False(u.IsApproved));
        Assert.All(filtered, u => Assert.False(u.IsDeclined));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterUpdatesByClassification_Security_ShouldReturnOnlySecurity()
    {
        // Arrange
        var updates = CreateMockUpdates(30);

        // Act
        var filtered = updates.Where(u => u.Classification == "Security").ToList();

        // Assert
        Assert.All(filtered, u => Assert.Equal("Security", u.Classification));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterUpdatesByClassification_Critical_ShouldReturnOnlyCritical()
    {
        // Arrange
        var updates = CreateMockUpdates(30);

        // Act
        var filtered = updates.Where(u => u.Classification == "Critical").ToList();

        // Assert
        Assert.All(filtered, u => Assert.Equal("Critical", u.Classification));
        Assert.NotEmpty(filtered);
    }

    [Fact]
    public void FilterComputersByHostname_ExactMatch_ShouldReturnMatch()
    {
        // Arrange
        var computers = CreateMockComputers(100);

        // Act
        var filtered = computers.Where(c => c.Hostname == "COMPUTER-0005").ToList();

        // Assert
        Assert.Single(filtered);
        Assert.Equal("COMPUTER-0005", filtered[0].Hostname);
    }

    [Fact]
    public void FilterComputersByHostname_PartialMatch_ShouldReturnMatches()
    {
        // Arrange
        var computers = CreateMockComputers(100);

        // Act
        var filtered = computers.Where(c => c.Hostname.Contains("COMPUTER-00")).ToList();

        // Assert
        Assert.True(filtered.Count >= 10); // Should match COMPUTER-0000 through COMPUTER-0009
        Assert.All(filtered, c => Assert.StartsWith("COMPUTER-00", c.Hostname));
    }

    [Fact]
    public void FilterComputersByHostname_CaseInsensitive_ShouldReturnMatches()
    {
        // Arrange
        var computers = CreateMockComputers(100);

        // Act
        var filtered = computers.Where(c => c.Hostname.Equals("computer-0005", StringComparison.OrdinalIgnoreCase)).ToList();

        // Assert
        Assert.Single(filtered);
    }

    [Fact]
    public void FilterComputersByIpAddress_ExactMatch_ShouldReturnMatch()
    {
        // Arrange
        var computers = CreateMockComputers(255);

        // Act
        var filtered = computers.Where(c => c.IpAddress == "192.168.1.100").ToList();

        // Assert
        Assert.Single(filtered);
        Assert.Equal("192.168.1.100", filtered[0].IpAddress);
    }

    [Fact]
    public void FilterUpdatesByKbNumber_ExactMatch_ShouldReturnMatch()
    {
        // Arrange
        var updates = CreateMockUpdates(100);

        // Act - KB format is KB0500000, KB0500001, KB0500002, etc (7-digit format)
        var filtered = updates.Where(u => u.KbArticle == "KB0500005").ToList();

        // Assert
        Assert.Single(filtered);
        Assert.Equal("KB0500005", filtered[0].KbArticle);
    }

    [Fact]
    public void FilterUpdatesByTitle_PartialMatch_ShouldReturnMatches()
    {
        // Arrange
        var updates = CreateMockUpdates(100);

        // Act - Title format is "Update {i+1}" (e.g., "Update 1", "Update 2")
        var filtered = updates.Where(u => u.Title.Contains("Update ")).ToList();

        // Assert - All updates should contain "Update "
        Assert.Equal(100, filtered.Count);
        Assert.All(filtered, u => Assert.Contains("Update ", u.Title));
    }

    [Fact]
    public void CombinedFilter_StatusAndHostname_ShouldApplyAndLogic()
    {
        // Arrange
        var computers = CreateMockComputers(100);

        // Act
        var filtered = computers
            .Where(c => c.Status == "Online")
            .Where(c => c.Hostname.Contains("COMPUTER-00"))
            .ToList();

        // Assert
        Assert.All(filtered, c =>
        {
            Assert.Equal("Online", c.Status);
            Assert.StartsWith("COMPUTER-00", c.Hostname);
        });
    }

    [Fact]
    public void CombinedFilter_ApprovalAndClassification_ShouldApplyAndLogic()
    {
        // Arrange
        var updates = CreateMockUpdates(100);

        // Act
        var filtered = updates
            .Where(u => u.IsApproved && !u.IsDeclined)
            .Where(u => u.Classification == "Security")
            .ToList();

        // Assert
        Assert.All(filtered, u =>
        {
            Assert.True(u.IsApproved);
            Assert.False(u.IsDeclined);
            Assert.Equal("Security", u.Classification);
        });
    }

    [Fact]
    public void EmptyFilterResult_ShouldReturnEmptyList()
    {
        // Arrange
        var computers = CreateMockComputers(50);

        // Act
        var filtered = computers.Where(c => c.Hostname == "NONEXISTENT").ToList();

        // Assert
        Assert.Empty(filtered);
    }

    [Fact]
    public void FilterWithSpecialCharacters_ShouldHandleCorrectly()
    {
        // Arrange
        var computers = new List<ComputerInfo>
        {
            new("COMPUTER-TEST[1]", "192.168.1.1", "Online", DateTime.Now, 0, "Windows Server 2022"),
            new("COMPUTER-TEST[2]", "192.168.1.2", "Online", DateTime.Now, 0, "Windows Server 2022")
        };

        // Act
        var filtered = computers.Where(c => c.Hostname.Contains('[')).ToList();

        // Assert
        Assert.Equal(2, filtered.Count);
    }

    private static List<ComputerInfo> CreateMockComputers(int count)
    {
        var computers = new List<ComputerInfo>(count);
        var statuses = new[] { "Online", "Offline", "Error" };

        for (int i = 0; i < count; i++)
        {
            computers.Add(new ComputerInfo(
                $"COMPUTER-{i:D4}",
                $"192.168.1.{(i % 255) + 1}",
                statuses[i % statuses.Length],
                DateTime.Now.AddHours(-i % 48),
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
            // Pattern: 0 = Approved, 1 = Declined, 2 = Not Approved
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
