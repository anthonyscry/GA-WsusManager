namespace WsusManager.App.Services;

/// <summary>
/// Theme metadata for UI binding (theme picker display names and swatch preview colors).
/// </summary>
public record ThemeInfo(string DisplayName, string PreviewBackground, string PreviewAccent);

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
    /// Pre-loads all theme ResourceDictionaries into memory to enable instant theme switching.
    /// Call this during application startup to avoid first-swap delay.
    /// </summary>
    void PreloadThemes();

    /// <summary>
    /// Returns the list of available theme names.
    /// </summary>
    IReadOnlyList<string> AvailableThemes { get; }

    /// <summary>
    /// Gets theme metadata (display name, preview colors) for the specified theme name.
    /// Returns null if the theme does not exist.
    /// </summary>
    ThemeInfo? GetThemeInfo(string themeName);

    /// <summary>
    /// Returns a read-only dictionary of all theme metadata keyed by theme name.
    /// </summary>
    IReadOnlyDictionary<string, ThemeInfo> ThemeInfos { get; }
}
