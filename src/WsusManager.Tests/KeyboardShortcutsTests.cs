using System;
using System.Linq;
using System.Windows.Input;
using WsusManager.App.ViewModels;
using Xunit;

namespace WsusManager.Tests;

/// <summary>
/// Tests for keyboard shortcut commands (Phase 26: UX-01).
/// Verifies that all global keyboard shortcut commands exist on MainViewModel.
/// </summary>
public class KeyboardShortcutsTests
{
    [Fact]
    public void MainViewModel_ShouldHaveAllKeyboardShortcutCommands()
    {
        // Arrange & Act - get command types via reflection
        var viewModelType = typeof(MainViewModel);
        var commandProperties = viewModelType.GetProperties()
            .Where(p => p.PropertyType == typeof(ICommand) && p.Name.EndsWith("Command", StringComparison.Ordinal))
            .Select(p => p.Name)
            .ToList();

        // Assert - verify all expected keyboard shortcut commands exist
        Assert.Contains("ShowHelpCommand", commandProperties);
        Assert.Contains("RefreshDashboardFromShortcutCommand", commandProperties);
        Assert.Contains("OpenSettingsFromShortcutCommand", commandProperties);
        Assert.Contains("QuitCommand", commandProperties);
        Assert.Contains("CancelOperationFromShortcutCommand", commandProperties);
    }
}
