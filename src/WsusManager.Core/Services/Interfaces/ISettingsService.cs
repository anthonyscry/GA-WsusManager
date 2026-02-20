using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Persists and loads application settings from %APPDATA%\WsusManager\settings.json.
/// </summary>
public interface ISettingsService
{
    /// <summary>
    /// Loads settings from disk. Returns default settings if file is missing or corrupt.
    /// </summary>
    Task<AppSettings> LoadAsync();

    /// <summary>
    /// Saves settings to disk. Creates the directory if it doesn't exist.
    /// </summary>
    Task SaveAsync(AppSettings settings);

    /// <summary>
    /// Gets the current in-memory settings (loaded on startup).
    /// </summary>
    AppSettings Current { get; }
}
