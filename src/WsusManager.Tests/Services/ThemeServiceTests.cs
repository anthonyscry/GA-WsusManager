using Moq;
using WsusManager.App.Services;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Services;

/// <summary>
/// Unit tests for <see cref="ThemeService"/>.
/// Note: Actual ResourceDictionary swapping requires a WPF Application instance
/// and cannot be tested in xUnit. These tests cover basic safety behavior.
/// </summary>
public class ThemeServiceTests
{
    private readonly Mock<ISettingsService> _mockSettings = new();
    private readonly Mock<ILogService> _mockLog = new();

    private ThemeService CreateService()
    {
        _mockSettings.Setup(s => s.Current).Returns(new AppSettings());
        return new ThemeService(_mockSettings.Object, _mockLog.Object);
    }

    [Fact]
    public void CurrentTheme_DefaultsToDefaultDark()
    {
        var service = CreateService();
        Assert.Equal("DefaultDark", service.CurrentTheme);
    }

    [Fact]
    public void AvailableThemes_ContainsDefaultDark()
    {
        var service = CreateService();
        Assert.Contains("DefaultDark", service.AvailableThemes);
    }

    [Fact]
    public void AvailableThemes_HasExactlyOneEntry()
    {
        var service = CreateService();
        Assert.Single(service.AvailableThemes);
    }

    [Fact]
    public void ApplyTheme_WithUnknownName_LogsWarning_DoesNotCrash()
    {
        var service = CreateService();

        // Should not throw
        service.ApplyTheme("NonExistentTheme");

        // CurrentTheme should remain unchanged
        Assert.Equal("DefaultDark", service.CurrentTheme);

        // Should have logged a warning
        _mockLog.Verify(l => l.Warning(
            It.IsAny<string>(),
            It.IsAny<object[]>()), Times.Once);
    }

    [Fact]
    public void ApplyTheme_WithNullName_LogsWarning_DoesNotCrash()
    {
        var service = CreateService();

        // Should not throw even with null
        service.ApplyTheme(null!);

        Assert.Equal("DefaultDark", service.CurrentTheme);
    }

    [Fact]
    public void ApplyTheme_WithValidName_NoApplication_DoesNotCrash()
    {
        // In test context, Application.Current is null
        var service = CreateService();

        // Should not throw — gracefully handles null Application.Current
        service.ApplyTheme("DefaultDark");
    }
}
