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
    public void AvailableThemes_HasSixEntries()
    {
        var service = CreateService();
        Assert.Equal(6, service.AvailableThemes.Count);
    }

    [Fact]
    public void AvailableThemes_ContainsAllExpectedThemes()
    {
        var service = CreateService();
        var expectedThemes = new[] { "DefaultDark", "JustBlack", "Slate", "Serenity", "Rose", "ClassicBlue" };

        foreach (var theme in expectedThemes)
        {
            Assert.Contains(theme, service.AvailableThemes);
        }
    }

    [Fact]
    public void GetThemeInfo_ReturnsInfoForAllThemes()
    {
        var service = CreateService();

        var defaultDarkInfo = service.GetThemeInfo("DefaultDark");
        Assert.NotNull(defaultDarkInfo);
        Assert.Equal("Default Dark", defaultDarkInfo!.DisplayName);
        Assert.Equal("#0D1117", defaultDarkInfo.PreviewBackground);
        Assert.Equal("#58A6FF", defaultDarkInfo.PreviewAccent);

        var justBlackInfo = service.GetThemeInfo("JustBlack");
        Assert.NotNull(justBlackInfo);
        Assert.Equal("Just Black", justBlackInfo!.DisplayName);
        Assert.Equal("#000000", justBlackInfo.PreviewBackground);
        Assert.Equal("#4CAF50", justBlackInfo.PreviewAccent);

        var slateInfo = service.GetThemeInfo("Slate");
        Assert.NotNull(slateInfo);
        Assert.Equal("Slate", slateInfo!.DisplayName);

        var serenityInfo = service.GetThemeInfo("Serenity");
        Assert.NotNull(serenityInfo);
        Assert.Equal("Serenity", serenityInfo!.DisplayName);

        var roseInfo = service.GetThemeInfo("Rose");
        Assert.NotNull(roseInfo);
        Assert.Equal("Rose", roseInfo!.DisplayName);

        var classicBlueInfo = service.GetThemeInfo("ClassicBlue");
        Assert.NotNull(classicBlueInfo);
        Assert.Equal("Classic Blue", classicBlueInfo!.DisplayName);
    }

    [Fact]
    public void GetThemeInfo_UnknownTheme_ReturnsNull()
    {
        var service = CreateService();

        var info = service.GetThemeInfo("NonExistentTheme");
        Assert.Null(info);

        var nullInfo = service.GetThemeInfo(null);
        Assert.Null(nullInfo);

        var emptyInfo = service.GetThemeInfo("");
        Assert.Null(emptyInfo);
    }

    [Fact]
    public void GetThemeInfo_CaseInsensitive()
    {
        var service = CreateService();

        var lowerInfo = service.GetThemeInfo("defaultdark");
        Assert.NotNull(lowerInfo);
        Assert.Equal("Default Dark", lowerInfo!.DisplayName);

        var upperInfo = service.GetThemeInfo("JUSTBLACK");
        Assert.NotNull(upperInfo);
        Assert.Equal("Just Black", upperInfo!.DisplayName);

        var mixedInfo = service.GetThemeInfo("SlAtE");
        Assert.NotNull(mixedInfo);
        Assert.Equal("Slate", mixedInfo!.DisplayName);
    }

    [Fact]
    public void ThemeInfos_ContainsAllSixThemes()
    {
        var service = CreateService();
        Assert.Equal(6, service.ThemeInfos.Count);
    }

    [Fact]
    public void ThemeInfos_DisplayNamesDifferFromKeys()
    {
        var service = CreateService();

        // Display names should have spaces, keys do not
        var defaultDarkInfo = service.ThemeInfos["DefaultDark"];
        Assert.NotEqual("DefaultDark", defaultDarkInfo.DisplayName);
        Assert.Contains(" ", defaultDarkInfo.DisplayName);

        var justBlackInfo = service.ThemeInfos["JustBlack"];
        Assert.NotEqual("JustBlack", justBlackInfo.DisplayName);
        Assert.Contains(" ", justBlackInfo.DisplayName);

        var classicBlueInfo = service.ThemeInfos["ClassicBlue"];
        Assert.NotEqual("ClassicBlue", classicBlueInfo.DisplayName);
        Assert.Contains(" ", classicBlueInfo.DisplayName);
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
    public void ApplyTheme_CaseInsensitive_AppliesTheme()
    {
        // In test context, Application.Current is null, so ApplyTheme handles gracefully
        // But we can verify it doesn't throw and CurrentTheme updates
        var service = CreateService();

        service.ApplyTheme("justblack");

        // Even without Application.Current, the service should update CurrentTheme
        // if the theme name is valid (case-insensitive)
        Assert.Equal("justblack", service.CurrentTheme);
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
