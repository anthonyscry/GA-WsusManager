using System.Windows;
using System.Windows.Controls;
using WsusManager.App.ViewModels;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.App.Views;

/// <summary>
/// Main application window. Constructor-only code-behind that sets DataContext
/// from the DI-injected ViewModel. Minimal code-behind for UI-only concerns.
/// </summary>
public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private readonly ISettingsService _settingsService;
    private AppSettings _settings;

    public MainWindow(MainViewModel viewModel, ISettingsService settingsService)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _settingsService = settingsService;
        _settings = _settingsService.Current;
        DataContext = viewModel;

        Loaded += MainWindow_Loaded;
        Closing += MainWindow_Closing;
        Closed += MainWindow_Closed;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        // Restore window bounds if enabled and valid
        if (_settings.PersistWindowState && _settings.WindowBounds != null)
        {
            var bounds = _settings.WindowBounds;

            // Validate bounds are within screen
            if (bounds.IsValid() && IsWithinScreenBounds(bounds))
            {
                Width = bounds.Width;
                Height = bounds.Height;
                Left = bounds.Left;
                Top = bounds.Top;

                if (string.Equals(bounds.WindowState, "Maximized", StringComparison.Ordinal))
                {
                    WindowState = WindowState.Maximized;
                }
            }
            // If bounds invalid, use default XAML values
        }

        await _viewModel.InitializeAsync().ConfigureAwait(false);

        // Unsubscribe from Loaded event to prevent memory leak
        Loaded -= MainWindow_Loaded;
    }

    private void MainWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        // Save window bounds if enabled
        if (_settings.PersistWindowState)
        {
            _settings.WindowBounds = new WindowBounds
            {
                Width = WindowState == WindowState.Maximized ? RestoreBounds.Width : ActualWidth,
                Height = WindowState == WindowState.Maximized ? RestoreBounds.Height : ActualHeight,
                Left = WindowState == WindowState.Maximized ? RestoreBounds.Left : Left,
                Top = WindowState == WindowState.Maximized ? RestoreBounds.Top : Top,
                WindowState = WindowState == WindowState.Maximized ? "Maximized" : "Normal"
            };

            // Save settings to disk (fire and forget)
            _ = _settingsService.SaveAsync(_settings);
        }
        else if (!_settings.PersistWindowState)
        {
            // Clear saved bounds
            _settings.WindowBounds = null;
            _ = _settingsService.SaveAsync(_settings);
        }
    }

    private void MainWindow_Closed(object? sender, EventArgs e)
    {
        // Cleanup ViewModel resources (timer, CTS, log builder)
        _viewModel.Dispose();
    }

    /// <summary>
    /// Checks if window bounds are within the primary screen's working area.
    /// </summary>
    private bool IsWithinScreenBounds(WindowBounds bounds)
    {
        try
        {
            var workingArea = SystemParameters.WorkArea;
            return bounds.Left >= workingArea.Left &&
                   bounds.Top >= workingArea.Top &&
                   bounds.Left + bounds.Width <= workingArea.Right &&
                   bounds.Top + bounds.Height <= workingArea.Bottom;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Auto-scroll log text to the bottom when new text is added.
    /// This is a UI-only concern, not business logic.
    /// </summary>
    private void LogTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            textBox.ScrollToEnd();
        }
    }
}
