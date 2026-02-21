using System.Text.Json;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Settings service that persists application settings to JSON at
/// %APPDATA%\WsusManager\settings.json.
/// </summary>
public class SettingsService : ISettingsService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private readonly string _settingsPath;
    private readonly ILogService _logService;

    public AppSettings Current { get; private set; } = new();

    public SettingsService(ILogService logService)
        : this(logService, GetDefaultSettingsPath())
    {
    }

    /// <summary>
    /// Initializes a new instance of the <see cref="SettingsService"/> class.
    /// Constructor with explicit path for testing.
    /// </summary>
    public SettingsService(ILogService logService, string settingsPath)
    {
        _logService = logService;
        _settingsPath = settingsPath;
    }

    public async Task<AppSettings> LoadAsync()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                _logService.Info("Settings file not found, using defaults: {Path}", _settingsPath);
                Current = new AppSettings();
                return Current;
            }

            var json = await File.ReadAllTextAsync(_settingsPath).ConfigureAwait(false);
            var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
            Current = settings ?? new AppSettings();
            _logService.Info("Settings loaded from {Path}", _settingsPath);
            return Current;
        }
        catch (Exception ex)
        {
            _logService.Warning("Failed to load settings, using defaults: {Error}", ex.Message);
            Current = new AppSettings();
            return Current;
        }
    }

    public async Task SaveAsync(AppSettings settings)
    {
        try
        {
            var directory = Path.GetDirectoryName(_settingsPath);
            if (directory != null && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var json = JsonSerializer.Serialize(settings, JsonOptions);
            await File.WriteAllTextAsync(_settingsPath, json).ConfigureAwait(false);
            Current = settings;
            _logService.Info("Settings saved to {Path}", _settingsPath);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Failed to save settings to {Path}", _settingsPath);
            throw;
        }
    }

    private static string GetDefaultSettingsPath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "WsusManager", "settings.json");
    }
}
