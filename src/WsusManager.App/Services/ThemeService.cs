using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using WsusManager.Core.Logging;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.App.Services;

/// <summary>
/// Singleton service that swaps color ResourceDictionaries at runtime.
/// Identifies the current color dictionary by checking for the "PrimaryBackground" key.
/// Also applies Windows title bar colors to match each theme.
/// </summary>
public class ThemeService : IThemeService
{
    private readonly ILogService _logService;
    private readonly Dictionary<string, ResourceDictionary> _themeCache = new(StringComparer.OrdinalIgnoreCase);
    private Window? _mainWindow;

    /// <summary>
    /// Maps theme names to their XAML resource paths (relative to the App project).
    /// </summary>
    private readonly Dictionary<string, string> _themeMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["DefaultDark"] = "Themes/DefaultDark.xaml",
        ["JustBlack"] = "Themes/JustBlack.xaml",
        ["Slate"] = "Themes/Slate.xaml",
        ["Serenity"] = "Themes/Serenity.xaml",
        ["Rose"] = "Themes/Rose.xaml",
        ["ClassicBlue"] = "Themes/ClassicBlue.xaml"
    };

    /// <summary>
    /// Theme metadata for UI binding (display names and swatch preview colors).
    /// </summary>
    private readonly Dictionary<string, ThemeInfo> _themeInfoMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["DefaultDark"] = new ThemeInfo("Default Dark", "#0D1117", "#58A6FF"),
        ["JustBlack"] = new ThemeInfo("Just Black", "#000000", "#4CAF50"),
        ["Slate"] = new ThemeInfo("Slate", "#1B2127", "#78909C"),
        ["Serenity"] = new ThemeInfo("Serenity", "#0F1419", "#4DB6AC"),
        ["Rose"] = new ThemeInfo("Rose", "#1A1118", "#F06292"),
        ["ClassicBlue"] = new ThemeInfo("Classic Blue", "#0D1525", "#42A5F5")
    };

    /// <summary>
    /// Title bar colors for each theme (background and foreground).
    /// </summary>
    private readonly Dictionary<string, (Color? Background, Color? Foreground)> _titleBarColors = new(StringComparer.OrdinalIgnoreCase)
    {
        ["DefaultDark"] = (Color.FromRgb(0x0D, 0x11, 0x17), Color.FromRgb(0xF0, 0xF6, 0xFC)),
        ["JustBlack"] = (Color.FromRgb(0x00, 0x00, 0x00), Color.FromRgb(0xFF, 0xFF, 0xFF)),
        ["Slate"] = (Color.FromRgb(0x1B, 0x21, 0x27), Color.FromRgb(0xE8, 0xEA, 0xED)),
        ["Serenity"] = (Color.FromRgb(0x0F, 0x14, 0x19), Color.FromRgb(0xE0, 0xF2, 0xF1)),
        ["Rose"] = (Color.FromRgb(0x1A, 0x11, 0x18), Color.FromRgb(0xFF, 0xEB, 0xEE)),
        ["ClassicBlue"] = (Color.FromRgb(0x0D, 0x15, 0x25), Color.FromRgb(0xE3, 0xF2, 0xFD))
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
    public IReadOnlyDictionary<string, ThemeInfo> ThemeInfos => _themeInfoMap;

    /// <inheritdoc/>
    public ThemeInfo? GetThemeInfo(string themeName)
    {
        if (string.IsNullOrWhiteSpace(themeName))
            return null;

        _themeInfoMap.TryGetValue(themeName, out var info);
        return info;
    }

    /// <inheritdoc/>
    public void SetMainWindow(Window mainWindow)
    {
        _mainWindow = mainWindow;
        // Apply current theme's title bar colors when window is set
        if (_mainWindow != null && !string.IsNullOrEmpty(CurrentTheme))
        {
            ApplyTitleBarColors(CurrentTheme);
        }
    }

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
            ResourceDictionary? themeDict = null;

            // Try to use pre-loaded theme from cache
            if (_themeCache.TryGetValue(themeName, out var cached))
            {
                themeDict = cached;
            }
            else
            {
                // Fallback: load the theme (shouldn't happen if preload worked)
                _logService.Warning("Theme not pre-loaded, loading on-demand: {ThemeName}", themeName);
                themeDict = LoadThemeDictionary(resourcePath);
                _themeCache[themeName] = themeDict;
            }

            ApplyThemeDictionary(themeDict);
            ApplyTitleBarColors(themeName);
            CurrentTheme = themeName;
            _logService.Info("Theme applied: {ThemeName}", themeName);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to apply theme: {ThemeName}", themeName);
        }
    }

    /// <summary>
    /// Applies title bar colors for the specified theme.
    /// </summary>
    private void ApplyTitleBarColors(string themeName)
    {
        if (_mainWindow == null) return;

        if (_titleBarColors.TryGetValue(themeName, out var colors))
        {
            TitleBarService.SetTitleBarColors(_mainWindow, colors.Background, colors.Foreground);
        }
    }

    /// <summary>
    /// Pre-loads all theme ResourceDictionaries into memory to enable instant theme switching.
    /// Call this during application startup to avoid first-swap delay.
    /// </summary>
    public void PreloadThemes()
    {
        var themes = _themeMap.Keys.ToList();
        var startTime = Stopwatch.StartNew();

        foreach (var theme in themes)
        {
            try
            {
                if (!_themeCache.ContainsKey(theme))
                {
                    var resourcePath = _themeMap[theme];
                    var dict = LoadThemeDictionary(resourcePath);
                    _themeCache[theme] = dict;
                }
            }
            catch (Exception ex)
            {
                _logService.Warning("Failed to preload theme: {Theme}, Error: {Error}", theme, ex.Message);
            }
        }

        startTime.Stop();
        _logService.Info("Preloaded {Count} themes in {Ms}ms", _themeCache.Count, startTime.ElapsedMilliseconds);
    }

    /// <summary>
    /// Loads a ResourceDictionary from the specified relative path.
    /// </summary>
    private ResourceDictionary LoadThemeDictionary(string resourcePath)
    {
        return new ResourceDictionary { Source = new Uri(resourcePath, UriKind.Relative) };
    }

    /// <summary>
    /// Applies a theme ResourceDictionary to the application resources.
    /// Removes any existing theme dictionary before adding the new one.
    /// </summary>
    private void ApplyThemeDictionary(ResourceDictionary themeDict)
    {
        var app = Application.Current;
        if (app == null) return;

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
        app.Resources.MergedDictionaries.Add(themeDict);
    }
}
