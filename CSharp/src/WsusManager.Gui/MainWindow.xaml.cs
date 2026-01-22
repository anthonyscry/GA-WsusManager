using System.Windows;
using WsusManager.Core.Utilities;

namespace WsusManager.Gui;

/// <summary>
/// Main window code-behind.
/// Notice how simple this is compared to PowerShell version - no manual event handling!
/// </summary>
public partial class MainWindow : Window
{
    public MainWindow()
    {
        // Check admin privileges
        if (!AdminPrivileges.IsAdmin())
        {
            MessageBox.Show(
                "WSUS Manager requires administrator privileges.\n\n" +
                "Please restart the application as Administrator.",
                "Administrator Required",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            Application.Current.Shutdown();
            return;
        }

        InitializeComponent();
    }
}
