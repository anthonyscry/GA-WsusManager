using System.Diagnostics;
using System.IO;
using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Serilog;
using WsusManager.App.Views;
using WsusManager.App.ViewModels;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Services;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.App;

/// <summary>
/// Application entry point. Sets up the DI host, resolves the main window,
/// and runs the WPF application. All service dependencies are registered here.
/// </summary>
public static class Program
{
    public const string AppVersion = "4.0.0";
    private const string LogDirectory = @"C:\WSUS\Logs";

    [STAThread]
    public static void Main(string[] args)
    {
        var startupTimer = Stopwatch.StartNew();

        // Create structured logger early so all startup activity is captured
        var logService = new LogService(LogDirectory);

        var host = CreateHost(args, logService);

        var app = new App();
        app.InitializeComponent();
        app.ConfigureServices(host.Services);

        var window = host.Services.GetRequiredService<MainWindow>();

        startupTimer.Stop();
        logService.LogStartup(AppVersion, startupTimer.ElapsedMilliseconds);

        app.MainWindow = window;

        try
        {
            app.Run(window);
        }
        finally
        {
            logService.Flush();
        }
    }

    /// <summary>
    /// Creates the DI host with all services registered.
    /// Exposed as internal for integration testing.
    /// </summary>
    internal static IHost CreateHost(string[] args, LogService logService)
    {
        var builder = Host.CreateApplicationBuilder(args);

        // Configure Serilog as the logging provider for Microsoft.Extensions.Logging
        var serilogLogger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .WriteTo.File(
                Path.Combine(LogDirectory, "WsusManager-.log"),
                rollingInterval: Serilog.RollingInterval.Day,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff} [{Level:u3}] {Message:lj}{NewLine}{Exception}",
                retainedFileCountLimit: 30,
                shared: true)
            .CreateLogger();

        builder.Logging.ClearProviders();
        builder.Logging.AddSerilog(serilogLogger);

        // Core services
        builder.Services.AddSingleton<ILogService>(logService);
        builder.Services.AddSingleton<ISettingsService, SettingsService>();
        builder.Services.AddSingleton<IProcessRunner, ProcessRunner>();
        builder.Services.AddSingleton<IDashboardService, DashboardService>();

        // Phase 3: Diagnostics and Service Management
        builder.Services.AddSingleton<IWindowsServiceManager, WindowsServiceManager>();
        builder.Services.AddSingleton<IFirewallService, FirewallService>();

        // ViewModels
        builder.Services.AddSingleton<MainViewModel>();

        // Views
        builder.Services.AddSingleton<MainWindow>();

        return builder.Build();
    }
}
