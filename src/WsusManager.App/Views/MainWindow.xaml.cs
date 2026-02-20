using System.Windows;
using WsusManager.App.ViewModels;

namespace WsusManager.App.Views;

/// <summary>
/// Main application window. Constructor-only code-behind that sets DataContext
/// from the DI-injected ViewModel. No other logic belongs here.
/// </summary>
public partial class MainWindow : Window
{
    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
