using Microsoft.Extensions.DependencyInjection;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Tests.Integration;

/// <summary>
/// Verifies that all DI service registrations resolve without error.
/// These tests do NOT require WPF runtime — they only test Core services.
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
    public void All_Core_Services_Resolve_Without_Error()
    {
        var sp = BuildTestContainer();

        // Resolve every registered service — will throw if any registration is missing
        var log = sp.GetRequiredService<ILogService>();
        var settings = sp.GetRequiredService<ISettingsService>();
        var process = sp.GetRequiredService<IProcessRunner>();

        Assert.NotNull(log);
        Assert.NotNull(settings);
        Assert.NotNull(process);
    }
}
