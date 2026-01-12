using Xunit;
using WsusManager.Core.Utilities;

namespace WsusManager.Tests.Utilities;

public class PathHelperTests
{
    [Fact]
    public void IsSafePath_ValidPath_ReturnsTrue()
    {
        // Arrange
        var path = @"C:\WSUS\Logs";

        // Act
        var result = PathHelper.IsSafePath(path);

        // Assert
        Assert.True(result);
    }

    [Theory]
    [InlineData(@"C:\WSUS; rm -rf /")]
    [InlineData(@"C:\WSUS & del *.*")]
    [InlineData(@"C:\WSUS | powershell")]
    [InlineData(@"C:\WSUS`whoami")]
    public void IsSafePath_InjectionCharacters_ReturnsFalse(string path)
    {
        // Act
        var result = PathHelper.IsSafePath(path);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void EscapePath_PathWithQuotes_EscapesCorrectly()
    {
        // Arrange
        var path = @"C:\Program Files\Test";

        // Act
        var result = PathHelper.EscapePath(path);

        // Assert
        Assert.Contains("\"", result);
        Assert.StartsWith("\"", result);
        Assert.EndsWith("\"", result);
    }

    [Fact]
    public void ValidatePath_ExistingPath_ReturnsTrue()
    {
        // Arrange - use a path that should exist on Windows
        var path = @"C:\Windows";

        // Act
        var result = PathHelper.ValidatePath(path, createIfMissing: false);

        // Assert
        Assert.True(result);
    }

    [Fact]
    public void HasSufficientSpace_LargeRequirement_ChecksCorrectly()
    {
        // Arrange
        var path = @"C:\";
        var required = 0.1m; // 100 MB - should be available

        // Act
        var result = PathHelper.HasSufficientSpace(path, required);

        // Assert
        Assert.True(result);
    }
}
