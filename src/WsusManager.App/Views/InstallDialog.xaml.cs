using System.Windows;
using System.Windows.Input;
using WsusManager.Core.Models;

namespace WsusManager.App.Views;

/// <summary>
/// Install WSUS dialog. Collects installer path, SA username, and SA password
/// before installation begins. Returns InstallOptions via public property.
/// </summary>
public partial class InstallDialog : Window
{
    /// <summary>
    /// The install options collected from the dialog. Only valid when DialogResult is true.
    /// </summary>
    public InstallOptions? Options { get; private set; }

    public InstallDialog()
    {
        InitializeComponent();

        // ESC key closes dialog (GUI-04)
        KeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
    }

    private void BrowseInstallerPath_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "Select Installer Directory"
        };

        if (dialog.ShowDialog() == true)
            TxtInstallerPath.Text = dialog.FolderName;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var password = PwdSaPassword.Password;

        if (string.IsNullOrWhiteSpace(password))
        {
            MessageBox.Show("SA password is required.", "Validation",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        Options = new InstallOptions
        {
            InstallerPath = TxtInstallerPath.Text.Trim(),
            SaUsername = string.IsNullOrWhiteSpace(TxtSaUsername.Text) ? "sa" : TxtSaUsername.Text.Trim(),
            SaPassword = password
        };

        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
