using Moq;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services;

namespace WsusManager.Tests.Foundation;

public class SettingsServiceTests : IDisposable
{
    private readonly Mock<ILogService> _mockLog = new();
    private readonly string _tempDir;
    private readonly string _settingsPath;

    public SettingsServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"WsusManagerTests_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        _settingsPath = Path.Combine(_tempDir, "settings.json");
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, recursive: true); } catch { }
    }

    [Fact]
    public async Task LoadAsync_Returns_Defaults_When_File_Missing()
    {
        var svc = new SettingsService(_mockLog.Object, _settingsPath);
        var settings = await svc.LoadAsync();

        Assert.NotNull(settings);
        Assert.Equal("Online", settings.ServerMode);
        Assert.True(settings.LogPanelExpanded);
        Assert.False(settings.LiveTerminalMode);
        Assert.Equal(@"C:\WSUS", settings.ContentPath);
        Assert.Equal(@"localhost\SQLEXPRESS", settings.SqlInstance);
        Assert.Equal(30, settings.RefreshIntervalSeconds);
    }

    [Fact]
    public async Task SaveAsync_Creates_File()
    {
        var svc = new SettingsService(_mockLog.Object, _settingsPath);
        var settings = new AppSettings { ServerMode = "AirGap", RefreshIntervalSeconds = 60 };

        await svc.SaveAsync(settings);

        Assert.True(File.Exists(_settingsPath));
        var json = await File.ReadAllTextAsync(_settingsPath);
        Assert.Contains("AirGap", json);
        Assert.Contains("60", json);
    }

    [Fact]
    public async Task SaveAsync_Then_LoadAsync_Roundtrips()
    {
        var svc = new SettingsService(_mockLog.Object, _settingsPath);
        var original = new AppSettings
        {
            ServerMode = "AirGap",
            LogPanelExpanded = false,
            LiveTerminalMode = true,
            ContentPath = @"D:\WSUS",
            SqlInstance = @"SERVER1\SQLEXPRESS",
            RefreshIntervalSeconds = 45
        };

        await svc.SaveAsync(original);

        // Create a new instance to verify loading from disk
        var svc2 = new SettingsService(_mockLog.Object, _settingsPath);
        var loaded = await svc2.LoadAsync();

        Assert.Equal(original.ServerMode, loaded.ServerMode);
        Assert.Equal(original.LogPanelExpanded, loaded.LogPanelExpanded);
        Assert.Equal(original.LiveTerminalMode, loaded.LiveTerminalMode);
        Assert.Equal(original.ContentPath, loaded.ContentPath);
        Assert.Equal(original.SqlInstance, loaded.SqlInstance);
        Assert.Equal(original.RefreshIntervalSeconds, loaded.RefreshIntervalSeconds);
    }

    [Fact]
    public async Task LoadAsync_Returns_Defaults_When_File_Corrupt()
    {
        await File.WriteAllTextAsync(_settingsPath, "not valid json{{{");

        var svc = new SettingsService(_mockLog.Object, _settingsPath);
        var settings = await svc.LoadAsync();

        Assert.NotNull(settings);
        Assert.Equal("Online", settings.ServerMode);
    }

    [Fact]
    public async Task SaveAsync_Creates_Directory_If_Missing()
    {
        var deepPath = Path.Combine(_tempDir, "sub", "dir", "settings.json");
        var svc = new SettingsService(_mockLog.Object, deepPath);

        await svc.SaveAsync(new AppSettings());

        Assert.True(File.Exists(deepPath));
    }

    [Fact]
    public async Task Current_Updates_After_Load()
    {
        var svc = new SettingsService(_mockLog.Object, _settingsPath);
        await svc.SaveAsync(new AppSettings { ServerMode = "AirGap" });

        var svc2 = new SettingsService(_mockLog.Object, _settingsPath);
        Assert.Equal("Online", svc2.Current.ServerMode); // Default before load

        await svc2.LoadAsync();
        Assert.Equal("AirGap", svc2.Current.ServerMode); // Updated after load
    }
}
