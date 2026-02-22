using Xunit;
using WsusManager.Core.Models;

namespace WsusManager.Tests;

public class SettingsTests
{
    [Fact]
    public void DefaultSyncProfile_DefaultIsFull()
    {
        var settings = new AppSettings();
        Assert.Equal(DefaultSyncProfile.Full, settings.DefaultSyncProfile);
    }

    [Fact]
    public void DefaultSyncProfile_CanBeSet()
    {
        var settings = new AppSettings
        {
            DefaultSyncProfile = DefaultSyncProfile.Quick
        };
        Assert.Equal(DefaultSyncProfile.Quick, settings.DefaultSyncProfile);
    }

    [Fact]
    public void LogLevel_DefaultIsInfo()
    {
        var settings = new AppSettings();
        Assert.Equal(LogLevel.Info, settings.LogLevel);
    }

    [Fact]
    public void LogLevel_CanBeSet()
    {
        var settings = new AppSettings
        {
            LogLevel = LogLevel.Debug
        };
        Assert.Equal(LogLevel.Debug, settings.LogLevel);
    }

    [Fact]
    public void DashboardRefreshInterval_DefaultIsSec30()
    {
        var settings = new AppSettings();
        Assert.Equal(DashboardRefreshInterval.Sec30, settings.DashboardRefreshInterval);
    }

    [Fact]
    public void DashboardRefreshInterval_CanBeSet()
    {
        var settings = new AppSettings
        {
            DashboardRefreshInterval = DashboardRefreshInterval.Sec10
        };
        Assert.Equal(DashboardRefreshInterval.Sec10, settings.DashboardRefreshInterval);
    }

    [Fact]
    public void LogRetentionDays_DefaultIs30()
    {
        var settings = new AppSettings();
        Assert.Equal(30, settings.LogRetentionDays);
    }

    [Fact]
    public void LogRetentionDays_CanBeSet()
    {
        var settings = new AppSettings
        {
            LogRetentionDays = 90
        };
        Assert.Equal(90, settings.LogRetentionDays);
    }

    [Fact]
    public void LogMaxFileSizeMb_DefaultIs10()
    {
        var settings = new AppSettings();
        Assert.Equal(10, settings.LogMaxFileSizeMb);
    }

    [Fact]
    public void LogMaxFileSizeMb_CanBeSet()
    {
        var settings = new AppSettings
        {
            LogMaxFileSizeMb = 50
        };
        Assert.Equal(50, settings.LogMaxFileSizeMb);
    }

    [Fact]
    public void PersistWindowState_DefaultIsTrue()
    {
        var settings = new AppSettings();
        Assert.True(settings.PersistWindowState);
    }

    [Fact]
    public void PersistWindowState_CanBeSetToFalse()
    {
        var settings = new AppSettings
        {
            PersistWindowState = false
        };
        Assert.False(settings.PersistWindowState);
    }

    [Fact]
    public void RequireConfirmationDestructive_DefaultIsTrue()
    {
        var settings = new AppSettings();
        Assert.True(settings.RequireConfirmationDestructive);
    }

    [Fact]
    public void RequireConfirmationDestructive_CanBeSetToFalse()
    {
        var settings = new AppSettings
        {
            RequireConfirmationDestructive = false
        };
        Assert.False(settings.RequireConfirmationDestructive);
    }

    [Fact]
    public void WindowBounds_DefaultIsNull()
    {
        var settings = new AppSettings();
        Assert.Null(settings.WindowBounds);
    }

    [Fact]
    public void WindowBounds_CanBeSet()
    {
        var bounds = new WindowBounds
        {
            Width = 1920,
            Height = 1080,
            Left = 100,
            Top = 100,
            WindowState = "Normal"
        };

        var settings = new AppSettings
        {
            WindowBounds = bounds
        };

        Assert.Equal(bounds, settings.WindowBounds);
    }

    [Fact]
    public void WinRMTimeoutSeconds_DefaultIs60()
    {
        var settings = new AppSettings();
        Assert.Equal(60, settings.WinRMTimeoutSeconds);
    }

    [Fact]
    public void WinRMTimeoutSeconds_CanBeSet()
    {
        var settings = new AppSettings
        {
            WinRMTimeoutSeconds = 120
        };
        Assert.Equal(120, settings.WinRMTimeoutSeconds);
    }

    [Fact]
    public void WinRMRetryCount_DefaultIs3()
    {
        var settings = new AppSettings();
        Assert.Equal(3, settings.WinRMRetryCount);
    }

    [Fact]
    public void WinRMRetryCount_CanBeSet()
    {
        var settings = new AppSettings
        {
            WinRMRetryCount = 5
        };
        Assert.Equal(5, settings.WinRMRetryCount);
    }
}
