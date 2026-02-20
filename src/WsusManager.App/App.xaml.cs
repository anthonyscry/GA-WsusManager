using System.Windows;
using System.Windows.Threading;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace WsusManager.App;

/// <summary>
/// WPF Application class. Handles global unhandled exception handlers.
/// DI host and window creation are managed in Program.cs.
/// </summary>
public partial class App : Application
{
    private IServiceProvider? _serviceProvider;
    private ILogger<App>? _logger;

    /// <summary>
    /// Sets the DI service provider for resolving logger and services.
    /// Called from Program.cs after the host is built.
    /// </summary>
    public void ConfigureServices(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
        _logger = serviceProvider.GetService<ILogger<App>>();
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // WPF dispatcher unhandled exceptions (UI thread)
        DispatcherUnhandledException += OnDispatcherUnhandledException;

        // Task scheduler unobserved exceptions (async void, fire-and-forget)
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;

        // AppDomain unhandled exceptions (last resort)
        AppDomain.CurrentDomain.UnhandledException += OnAppDomainUnhandledException;
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        _logger?.LogError(e.Exception, "Unhandled UI thread exception");
        ShowErrorDialog(e.Exception);
        e.Handled = true;
    }

    private void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        _logger?.LogError(e.Exception, "Unobserved task exception");
        e.SetObserved();

        Dispatcher.Invoke(() => ShowErrorDialog(e.Exception.InnerException ?? e.Exception));
    }

    private void OnAppDomainUnhandledException(object sender, UnhandledExceptionEventArgs e)
    {
        var exception = e.ExceptionObject as Exception;
        _logger?.LogCritical(exception, "Fatal unhandled exception (IsTerminating={IsTerminating})", e.IsTerminating);

        if (exception != null)
        {
            try
            {
                ShowErrorDialog(exception, isFatal: true);
            }
            catch
            {
                // Cannot show dialog during termination — already logged
            }
        }
    }

    /// <summary>
    /// Shows a user-friendly error dialog with expandable details.
    /// </summary>
    private static void ShowErrorDialog(Exception exception, bool isFatal = false)
    {
        var title = isFatal ? "WSUS Manager - Fatal Error" : "WSUS Manager - Error";
        var header = isFatal
            ? "A fatal error occurred and the application must close."
            : "An unexpected error occurred.";

        var message = $"{header}\n\n{exception.Message}\n\n--- Details ---\n{exception}";

        MessageBox.Show(
            message,
            title,
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }
}
