namespace WsusManager.App.Services;

/// <summary>
/// Manages runtime theme switching by swapping color ResourceDictionaries
/// in Application.Current.Resources.MergedDictionaries.
/// </summary>
public interface IThemeService
{
    /// <summary>
    /// Gets the name of the currently active theme (e.g., "DefaultDark").
    /// </summary>
    string CurrentTheme { get; }

    /// <summary>
    /// Swaps the active color dictionary to the specified theme.
    /// The theme name must exist in AvailableThemes.
    /// </summary>
    void ApplyTheme(string themeName);

    /// <summary>
    /// Returns the list of available theme names.
    /// </summary>
    IReadOnlyList<string> AvailableThemes { get; }
}
