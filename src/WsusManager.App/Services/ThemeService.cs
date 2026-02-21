using System.Windows;
using WsusManager.Core.Logging;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.App.Services;

/// <summary>
/// Singleton service that swaps color ResourceDictionaries at runtime.
/// Identifies the current color dictionary by checking for the "PrimaryBackground" key.
/// </summary>
public class ThemeService : IThemeService
{
    private readonly ILogService _logService;

    /// <summary>
    /// Maps theme names to their XAML resource paths (relative to the App project).
    /// Phase 17 will add additional theme entries here.
    /// </summary>
    private readonly Dictionary<string, string> _themeMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["DefaultDark"] = "Themes/DefaultDark.xaml"
    };

    public ThemeService(ISettingsService settingsService, ILogService logService)
    {
        _logService = logService;
        CurrentTheme = "DefaultDark";
    }

    /// <inheritdoc/>
    public string CurrentTheme { get; private set; }

    /// <inheritdoc/>
    public IReadOnlyList<string> AvailableThemes => _themeMap.Keys.ToList().AsReadOnly();

    /// <inheritdoc/>
    public void ApplyTheme(string themeName)
    {
        if (!_themeMap.TryGetValue(themeName, out var resourcePath))
        {
            _logService.Warning("Theme not found: {ThemeName}. Available: {Available}",
                themeName, string.Join(", ", _themeMap.Keys));
            return;
        }

        try
        {
            var app = Application.Current;
            if (app == null) return;

            // Create the new theme ResourceDictionary
            var newThemeDict = new ResourceDictionary
            {
                Source = new Uri(resourcePath, UriKind.Relative)
            };

            // Find and remove the current color dictionary (identified by "PrimaryBackground" key)
            ResourceDictionary? existingColorDict = null;
            foreach (var dict in app.Resources.MergedDictionaries)
            {
                if (dict.Contains("PrimaryBackground"))
                {
                    existingColorDict = dict;
                    break;
                }
            }

            if (existingColorDict != null)
            {
                app.Resources.MergedDictionaries.Remove(existingColorDict);
            }

            // Add the new color dictionary
            app.Resources.MergedDictionaries.Add(newThemeDict);

            CurrentTheme = themeName;
            _logService.Info("Theme applied: {ThemeName}", themeName);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to apply theme: {ThemeName}", themeName);
        }
    }
}
