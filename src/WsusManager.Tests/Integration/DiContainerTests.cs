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

        // Phase 4: Database Operations
        services.AddSingleton<ISqlService, SqlService>();
        services.AddSingleton<IDeepCleanupService, DeepCleanupService>();
        services.AddSingleton<IDatabaseBackupService, DatabaseBackupService>();

        // Phase 5: WSUS Operations
        services.AddSingleton<IWsusServerService, WsusServerService>();
        services.AddSingleton<ISyncService, SyncService>();
        services.AddSingleton<IRobocopyService, RobocopyService>();
        services.AddSingleton<IExportService, ExportService>();
        services.AddSingleton<IImportService, ImportService>();

        // Phase 6: Installation and Scheduling
        services.AddSingleton<IInstallationService, InstallationService>();
        services.AddSingleton<IScheduledTaskService, ScheduledTaskService>();
        services.AddSingleton<IGpoDeploymentService, GpoDeploymentService>();

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

    // ─── Phase 4 Service Resolution Tests ────────────────────────────────

    [Fact]
    public void SqlService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<ISqlService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void DeepCleanupService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IDeepCleanupService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void DatabaseBackupService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IDatabaseBackupService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void All_Phase4_Services_Resolve_Without_Error()
    {
        var sp = BuildTestContainer();

        var sqlService = sp.GetRequiredService<ISqlService>();
        var deepCleanup = sp.GetRequiredService<IDeepCleanupService>();
        var backup = sp.GetRequiredService<IDatabaseBackupService>();

        Assert.NotNull(sqlService);
        Assert.NotNull(deepCleanup);
        Assert.NotNull(backup);
    }

    // ─── Phase 5 Service Resolution Tests ────────────────────────────────

    [Fact]
    public void WsusServerService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IWsusServerService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void SyncService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<ISyncService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void RobocopyService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IRobocopyService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void ExportService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IExportService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void ImportService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IImportService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void All_Phase5_Services_Resolve_Without_Error()
    {
        var sp = BuildTestContainer();

        var wsusServer = sp.GetRequiredService<IWsusServerService>();
        var syncService = sp.GetRequiredService<ISyncService>();
        var robocopy = sp.GetRequiredService<IRobocopyService>();
        var export = sp.GetRequiredService<IExportService>();
        var import = sp.GetRequiredService<IImportService>();

        Assert.NotNull(wsusServer);
        Assert.NotNull(syncService);
        Assert.NotNull(robocopy);
        Assert.NotNull(export);
        Assert.NotNull(import);
    }

    // ─── Phase 6 Service Resolution Tests ────────────────────────────────

    [Fact]
    public void InstallationService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IInstallationService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void ScheduledTaskService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IScheduledTaskService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void GpoDeploymentService_Resolves()
    {
        var sp = BuildTestContainer();
        var svc = sp.GetRequiredService<IGpoDeploymentService>();
        Assert.NotNull(svc);
    }

    [Fact]
    public void All_Phase6_Services_Resolve_Without_Error()
    {
        var sp = BuildTestContainer();

        var installation = sp.GetRequiredService<IInstallationService>();
        var scheduledTask = sp.GetRequiredService<IScheduledTaskService>();
        var gpo = sp.GetRequiredService<IGpoDeploymentService>();

        Assert.NotNull(installation);
        Assert.NotNull(scheduledTask);
        Assert.NotNull(gpo);
    }

    // ─── Singleton Identity Tests ────────────────────────────────

    [Fact]
    public void Singletons_Return_Same_Instance_On_Second_Resolve()
    {
        var sp = BuildTestContainer();

        var log1 = sp.GetRequiredService<ILogService>();
        var log2 = sp.GetRequiredService<ILogService>();
        Assert.Same(log1, log2);

        var settings1 = sp.GetRequiredService<ISettingsService>();
        var settings2 = sp.GetRequiredService<ISettingsService>();
        Assert.Same(settings1, settings2);

        var health1 = sp.GetRequiredService<IHealthService>();
        var health2 = sp.GetRequiredService<IHealthService>();
        Assert.Same(health1, health2);
    }

    [Fact]
    public void All_17_Service_Interfaces_Resolve()
    {
        var sp = BuildTestContainer();

        // All 17 service interfaces + IProcessRunner = 18 total
        Assert.NotNull(sp.GetRequiredService<ILogService>());
        Assert.NotNull(sp.GetRequiredService<ISettingsService>());
        Assert.NotNull(sp.GetRequiredService<IProcessRunner>());
        Assert.NotNull(sp.GetRequiredService<IDashboardService>());
        Assert.NotNull(sp.GetRequiredService<IWindowsServiceManager>());
        Assert.NotNull(sp.GetRequiredService<IFirewallService>());
        Assert.NotNull(sp.GetRequiredService<IPermissionsService>());
        Assert.NotNull(sp.GetRequiredService<IHealthService>());
        Assert.NotNull(sp.GetRequiredService<IContentResetService>());
        Assert.NotNull(sp.GetRequiredService<ISqlService>());
        Assert.NotNull(sp.GetRequiredService<IDeepCleanupService>());
        Assert.NotNull(sp.GetRequiredService<IDatabaseBackupService>());
        Assert.NotNull(sp.GetRequiredService<IWsusServerService>());
        Assert.NotNull(sp.GetRequiredService<ISyncService>());
        Assert.NotNull(sp.GetRequiredService<IRobocopyService>());
        Assert.NotNull(sp.GetRequiredService<IExportService>());
        Assert.NotNull(sp.GetRequiredService<IImportService>());
        Assert.NotNull(sp.GetRequiredService<IInstallationService>());
        Assert.NotNull(sp.GetRequiredService<IScheduledTaskService>());
        Assert.NotNull(sp.GetRequiredService<IGpoDeploymentService>());
    }
}
