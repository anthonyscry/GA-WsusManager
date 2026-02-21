using System.Xml.Linq;
using Xunit;
using WsusManager.Tests.Helpers;

namespace WsusManager.Tests;

/// <summary>
/// WCAG 2.1 AA contrast compliance verification for all theme colors.
/// Tests verify foreground/background color pairs meet minimum contrast ratios.
/// </summary>
public class ThemeContrastTests
{
    private const double WcagAaNormalText = 4.5;
    private const double WcagAaLargeText = 3.0;

    // Theme files to test
    private static readonly string[] ThemeFiles = new[]
    {
        "DefaultDark.xaml",
        "Slate.xaml",
        "Serenity.xaml",
        "Rose.xaml",
        "ClassicBlue.xaml",
        "JustBlack.xaml"
    };

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void TextPrimary_On_PrimaryBackground_ShouldMeetWcagAa(string themeFile)
    {
        var colors = ExtractColorPair(themeFile, "ColorTextPrimary", "ColorPrimaryBackground");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        Assert.True(contrast >= WcagAaNormalText,
            $"{themeFile}: TextPrimary/PrimaryBackground contrast {contrast:F2} fails WCAG AA (minimum {WcagAaNormalText})");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void TextPrimary_On_NavBackground_ShouldMeetWcagAa(string themeFile)
    {
        var colors = ExtractColorPair(themeFile, "ColorTextPrimary", "ColorNavBackground");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        Assert.True(contrast >= WcagAaNormalText,
            $"{themeFile}: TextPrimary/NavBackground contrast {contrast:F2} fails WCAG AA");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void TextPrimary_On_CardBackground_ShouldMeetWcagAa(string themeFile)
    {
        var colors = ExtractColorPair(themeFile, "ColorTextPrimary", "ColorCardBackground");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        Assert.True(contrast >= WcagAaNormalText,
            $"{themeFile}: TextPrimary/CardBackground contrast {contrast:F2} fails WCAG AA");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void TextSecondary_On_PrimaryBackground_ShouldBeReadable(string themeFile)
    {
        var colors = ExtractColorPair(themeFile, "ColorTextSecondary", "ColorPrimaryBackground");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        // TextSecondary may be below 4.5:1 but should still be readable
        Assert.True(contrast >= 3.0,
            $"{themeFile}: TextSecondary/PrimaryBackground contrast {contrast:F2} below minimum readability threshold (3.0)");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void TextMuted_On_PrimaryBackground_ShouldBeVisible(string themeFile)
    {
        var colors = ExtractColorPair(themeFile, "ColorTextMuted", "ColorPrimaryBackground");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        // TextMuted is for decorative text and may be below AA threshold
        Assert.True(contrast >= 2.0,
            $"{themeFile}: TextMuted/PrimaryBackground contrast {contrast:F2} below visibility threshold (2.0)");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void ButtonPrimaryTextContrast_ShouldMeetWcagAa(string themeFile)
    {
        // ButtonPrimary is background, TextPrimary is foreground
        var colors = ExtractColorPair(themeFile, "ColorTextPrimary", "ColorButtonPrimary");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        Assert.True(contrast >= WcagAaNormalText,
            $"{themeFile}: TextPrimary/ButtonPrimary contrast {contrast:F2} fails WCAG AA");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void ButtonDangerTextContrast_ShouldMeetWcagAa(string themeFile)
    {
        var colors = ExtractColorPair(themeFile, "ColorTextPrimary", "ColorButtonDanger");
        var contrast = ColorContrastHelper.CalculateContrastRatio(colors.Foreground, colors.Background);
        Assert.True(contrast >= WcagAaNormalText,
            $"{themeFile}: TextPrimary/ButtonDanger contrast {contrast:F2} fails WCAG AA");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void StatusColors_ShouldMeetWcagAa(string themeFile)
    {
        var cardBg = ExtractColor(themeFile, "ColorCardBackground");

        var successColor = ExtractColor(themeFile, "ColorStatusSuccess");
        var successContrast = ColorContrastHelper.CalculateContrastRatio(successColor, cardBg);
        Assert.True(successContrast >= WcagAaNormalText,
            $"{themeFile}: StatusSuccess/CardBackground contrast {successContrast:F2} fails WCAG AA");

        var warningColor = ExtractColor(themeFile, "ColorStatusWarning");
        var warningContrast = ColorContrastHelper.CalculateContrastRatio(warningColor, cardBg);
        Assert.True(warningContrast >= WcagAaNormalText,
            $"{themeFile}: StatusWarning/CardBackground contrast {warningContrast:F2} fails WCAG AA");

        var errorColor = ExtractColor(themeFile, "ColorStatusError");
        var errorContrast = ColorContrastHelper.CalculateContrastRatio(errorColor, cardBg);
        Assert.True(errorContrast >= WcagAaNormalText,
            $"{themeFile}: StatusError/CardBackground contrast {errorContrast:F2} fails WCAG AA");
    }

    [Theory]
    [InlineData("DefaultDark.xaml")]
    [InlineData("Slate.xaml")]
    [InlineData("Serenity.xaml")]
    [InlineData("Rose.xaml")]
    [InlineData("ClassicBlue.xaml")]
    [InlineData("JustBlack.xaml")]
    public void BorderColors_ShouldBeVisible(string themeFile)
    {
        var bg = ExtractColor(themeFile, "ColorPrimaryBackground");

        var borderPrimary = ExtractColor(themeFile, "ColorBorderPrimary");
        var borderContrast = ColorContrastHelper.CalculateContrastRatio(borderPrimary, bg);
        // Borders don't need to meet AA, but should be visible
        Assert.True(borderContrast >= 1.5,
            $"{themeFile}: BorderPrimary/PrimaryBackground contrast {borderContrast:F2} below visibility threshold (1.5)");
    }

    private static (string Foreground, string Background) ExtractColorPair(string themeFile, string foregroundKey, string backgroundKey)
    {
        return (ExtractColor(themeFile, foregroundKey), ExtractColor(themeFile, backgroundKey));
    }

    private static string ExtractColor(string themeFile, string colorKey)
    {
        // Navigate from WsusManager.Tests/bin/... to WsusManager.App/Themes/
        var themePath = Path.Combine("..", "..", "..", "..", "WsusManager.App", "Themes", themeFile);
        var xaml = XDocument.Load(themePath);
        var colorElement = xaml.Descendants("{http://schemas.microsoft.com/winfx/2006/xaml/presentation}Color")
            .FirstOrDefault(e => e.Attribute("{http://schemas.microsoft.com/winfx/2006/xaml}Key")?.Value == colorKey);
        return colorElement?.Value ?? "#000000";
    }
}
