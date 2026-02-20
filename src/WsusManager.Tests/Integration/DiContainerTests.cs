using Microsoft.Extensions.DependencyInjection;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Integration;

/// <summary>
/// Verifies that all DI service registrations resolve without error.
/// These tests do NOT require WPF runtime -- they only test Core services.
/// </summary>
public class DiContainerTests
{
    private static IServiceProvider BuildTestContainer()
    {
        var services = new ServiceCollection();

        // Register the same Core services as Program.cs
        services.AddSingleton<ILogService>(new LogService(Path.GetTempPath()));
        services.AddSingleton<ISettingsService, SettingsService>();
        services.AddSingleton<IProcessRunner, ProcessRunner>();
        services.AddSingleton<IDashboardService, DashboardService>();

        // Phase 3: Diagnostics and Service Management
        services.AddSingleton<IWindowsServiceManager, WindowsServiceManager>();
        services.AddSingleton<IFirewallService, FirewallService>();
        services.AddSingleton<IPermissionsService, PermissionsService>();
        services.AddSingleton<IHealthService, HealthService>();
        services.AddSingleton<IContentResetService, ContentResetService>();

        return services.BuildServiceProvider();
    }

    [Fact]
    public void LogService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<ILogService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void SettingsService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<ISettingsService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void ProcessRunner_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IProcessRunner>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void DashboardService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IDashboardService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void All_Core_Services_Resolve_Without_Error()
    {
        var sp = BuildTestContainer();

        // Resolve every registered service — will throw if any registration is missing
        var log = sp.GetRequiredService<ILogService>();
        var settings = sp.GetRequiredService<ISettingsService>();
        var process = sp.GetRequiredService<IProcessRunner>();
        var dashboard = sp.GetRequiredService<IDashboardService>();

        Assert.NotNull(log);
        Assert.NotNull(settings);
        Assert.NotNull(process);
        Assert.NotNull(dashboard);
    }

    // ─── Phase 3 Service Resolution Tests ────────────────────────────────

    [Fact]
    public void WindowsServiceManager_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IWindowsServiceManager>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void FirewallService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IFirewallService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void PermissionsService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IPermissionsService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void HealthService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IHealthService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void ContentResetService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IContentResetService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void All_Phase3_Services_Resolve_Without_Error()
    {
        var sp = BuildTestContainer();

        var serviceManager = sp.GetRequiredService<IWindowsServiceManager>();
        var firewall = sp.GetRequiredService<IFirewallService>();
        var permissions = sp.GetRequiredService<IPermissionsService>();
        var health = sp.GetRequiredService<IHealthService>();
        var contentReset = sp.GetRequiredService<IContentResetService>();

        Assert.NotNull(serviceManager);
        Assert.NotNull(firewall);
        Assert.NotNull(permissions);
        Assert.NotNull(health);
        Assert.NotNull(contentReset);
    }
}
