using System.IO;
using Xunit;

namespace WsusManager.Tests;

/// <summary>
/// Tests for keyboard shortcut commands (Phase 26: UX-01).
/// Verifies that all global keyboard shortcut KeyBindings are defined in MainWindow.xaml.
/// This is a structural test that checks XAML directly rather than referencing ViewModels.
/// </summary>
public class KeyboardShortcutsTests
{
    private static string GetViewsPath() => Path.Combine("..", "..", "..", "..", "WsusManager.App", "Views");
    private static string GetXamlPath(string fileName) => Path.Combine(GetViewsPath(), fileName);

    [Fact]
    public void MainWindow_ShouldHaveAllKeyboardShortcutKeyBindings()
    {
        // Arrange - read MainWindow.xaml
        var xamlPath = GetXamlPath("MainWindow.xaml");
        var content = File.ReadAllText(xamlPath);

        // Assert - verify all expected keyboard shortcuts are defined in InputBindings
        Assert.Contains("<Window.InputBindings>", content);
        Assert.Contains("Key=\"F1\"", content);  // Help
        Assert.Contains("Key=\"F5\"", content);  // Refresh
        Assert.Contains("Key=\"S\" Modifiers=\"Control\"", content);  // Settings
        Assert.Contains("Key=\"Q\" Modifiers=\"Control\"", content);  // Quit
        Assert.Contains("Key=\"Escape\"", content);  // Cancel
    }

    [Fact]
    public void MainWindow_KeyBindingsShouldHaveValidCommands()
    {
        // Arrange - read MainWindow.xaml
        var xamlPath = GetXamlPath("MainWindow.xaml");
        var content = File.ReadAllText(xamlPath);

        // Assert - verify KeyBindings reference valid commands
        // Commands must end with "Command" to match CommunityToolkit.Mvvm pattern
        Assert.Contains("Command=\"{Binding ShowHelpCommand}\"", content);
        Assert.Contains("Command=\"{Binding RefreshDashboardFromShortcutCommand}\"", content);
        Assert.Contains("Command=\"{Binding OpenSettingsFromShortcutCommand}\"", content);
        Assert.Contains("Command=\"{Binding QuitCommand}\"", content);
        Assert.Contains("Command=\"{Binding CancelOperationFromShortcutCommand}\"", content);
    }
}
