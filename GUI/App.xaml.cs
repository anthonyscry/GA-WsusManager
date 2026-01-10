using System;
using System.IO;
using System.Windows;

namespace WsusManager
{
    public partial class App : Application
    {
        public static string ModulesPath { get; private set; } = string.Empty;
        public static string LogsPath { get; private set; } = string.Empty;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            // Determine the modules path relative to the application
            var appDir = AppDomain.CurrentDomain.BaseDirectory;
            var projectRoot = Path.GetFullPath(Path.Combine(appDir, "..", "..", "..", ".."));

            ModulesPath = Path.Combine(projectRoot, "Modules");
            LogsPath = Path.Combine("C:\\WSUS", "Logs");

            // Fallback if running from different location
            if (!Directory.Exists(ModulesPath))
            {
                ModulesPath = Path.Combine(appDir, "Modules");
            }

            // Set up global exception handling
            AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;
            DispatcherUnhandledException += OnDispatcherUnhandledException;
        }

        private void OnUnhandledException(object sender, UnhandledExceptionEventArgs e)
        {
            var exception = e.ExceptionObject as Exception;
            LogException(exception);

            MessageBox.Show(
                $"An unexpected error occurred:\n\n{exception?.Message}\n\nThe application will now close.",
                "WSUS Manager - Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }

        private void OnDispatcherUnhandledException(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
        {
            LogException(e.Exception);

            MessageBox.Show(
                $"An error occurred:\n\n{e.Exception.Message}",
                "WSUS Manager - Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);

            e.Handled = true;
        }

        private void LogException(Exception? exception)
        {
            if (exception == null) return;

            try
            {
                var logFile = Path.Combine(LogsPath, $"WsusManager_{DateTime.Now:yyyy-MM-dd}.log");
                Directory.CreateDirectory(LogsPath);

                var logEntry = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] ERROR: {exception.Message}\n{exception.StackTrace}\n\n";
                File.AppendAllText(logFile, logEntry);
            }
            catch
            {
                // Ignore logging errors
            }
        }
    }
}
