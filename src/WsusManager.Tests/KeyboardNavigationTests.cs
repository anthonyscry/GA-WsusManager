using System.IO;
using System.Xml.Linq;
using Xunit;

namespace WsusManager.Tests;

/// <summary>
/// Structural tests for keyboard navigation support in XAML files.
/// Full keyboard navigation testing requires UI automation (manual testing).
/// </summary>
public class KeyboardNavigationTests
{
    // Navigate from test output dir to Views folder
    private static string GetViewsPath() => Path.Combine("..", "..", "..", "..", "WsusManager.App", "Views");

    private static string GetXamlPath(string fileName) => Path.Combine(GetViewsPath(), fileName);

    [Fact]
    public void MainWindow_ShouldHaveKeyboardNavigationAttributes()
    {
        var content = File.ReadAllText(GetXamlPath("MainWindow.xaml"));

        // Verify KeyboardNavigation attributes are present
        Assert.Contains("KeyboardNavigation.", content);
    }

    [Theory]
    [InlineData("SettingsDialog.xaml")]
    [InlineData("SyncProfileDialog.xaml")]
    [InlineData("TransferDialog.xaml")]
    [InlineData("ScheduleTaskDialog.xaml")]
    [InlineData("InstallDialog.xaml")]
    public void Dialogs_ShouldSupportTabNavigation(string dialogFile)
    {
        var dialogPath = GetXamlPath(dialogFile);
        Assert.True(File.Exists(dialogPath), $"{dialogFile} should exist");

        var xaml = XDocument.Load(dialogPath);

        // Count interactive elements (Button, TextBox, ComboBox, CheckBox, RadioButton)
        var interactiveElements = xaml.Descendants()
            .Where(e => e.Name.LocalName is "Button" or "TextBox" or "ComboBox" or "CheckBox" or "RadioButton" or "ListBox")
            .ToList();

        // Verify dialog has interactive elements (sanity check)
        Assert.True(interactiveElements.Count > 0, $"{dialogFile} should have interactive elements");
    }

    [Fact]
    public void MainWindow_ShouldNotContainIsTabStopFalse()
    {
        // Verify no elements explicitly disable tab navigation
        var content = File.ReadAllText(GetXamlPath("MainWindow.xaml"));

        Assert.DoesNotContain("IsTabStop=\"False\"", content);
        Assert.DoesNotContain("IsTabStop=\"false\"", content);
    }

    [Fact]
    public void AllDialogs_ShouldHaveTabNavigationAttribute()
    {
        var dialogFiles = new[]
        {
            "SettingsDialog.xaml",
            "SyncProfileDialog.xaml",
            "TransferDialog.xaml",
            "ScheduleTaskDialog.xaml",
            "InstallDialog.xaml"
        };

        foreach (var dialogFile in dialogFiles)
        {
            var content = File.ReadAllText(GetXamlPath(dialogFile));

            // Verify root Grid has KeyboardNavigation.TabNavigation
            Assert.True(content.Contains("KeyboardNavigation.TabNavigation"),
                $"{dialogFile} should have KeyboardNavigation.TabNavigation attribute");
        }
    }

    [Theory]
    [InlineData("MainWindow.xaml", "KeyboardNavigation.TabNavigation=\"Once\"")]
    [InlineData("SettingsDialog.xaml", "KeyboardNavigation.TabNavigation=\"Continue\"")]
    [InlineData("SyncProfileDialog.xaml", "KeyboardNavigation.TabNavigation=\"Continue\"")]
    public void SpecificFiles_ShouldHaveExpectedNavigationMode(string fileName, string expectedAttribute)
    {
        var content = File.ReadAllText(GetXamlPath(fileName));

        Assert.True(content.Contains(expectedAttribute),
            $"{fileName} should have {expectedAttribute}");
    }

    [Fact]
    public void MainWindow_ShouldHaveInputBindingsForShortcuts()
    {
        var content = File.ReadAllText(GetXamlPath("MainWindow.xaml"));

        // Verify global keyboard shortcuts are defined
        Assert.Contains("<Window.InputBindings>", content);
        Assert.Contains("Key=\"F1\"", content);  // Help
        Assert.Contains("Key=\"F5\"", content);  // Refresh
        Assert.Contains("Key=\"S\" Modifiers=\"Control\"", content);  // Settings
        Assert.Contains("Key=\"Q\" Modifiers=\"Control\"", content);  // Quit
        Assert.Contains("Key=\"Escape\"", content);  // Cancel
    }
}
