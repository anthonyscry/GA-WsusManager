using System.Windows;
using System.Windows.Controls;
using WsusManager.App.ViewModels;

namespace WsusManager.App.Views;

/// <summary>
/// Main application window. Constructor-only code-behind that sets DataContext
/// from the DI-injected ViewModel. Minimal code-behind for UI-only concerns.
/// </summary>
public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;

    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;

        Loaded += MainWindow_Loaded;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        await _viewModel.InitializeAsync();
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
