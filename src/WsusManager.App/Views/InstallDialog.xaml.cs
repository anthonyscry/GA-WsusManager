using System.IO;
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

        // Set initial validation state
        ValidateInputs();
    }

    private void Input_Changed(object sender, RoutedEventArgs e) => ValidateInputs();

    private void ValidateInputs()
    {
        if (TxtInstallerPath is null || PwdSaPassword is null || BtnInstall is null || TxtValidation is null)
            return;

        var path = TxtInstallerPath.Text.Trim();
        var password = PwdSaPassword.Password;

        // Check installer path
        if (string.IsNullOrWhiteSpace(path))
        {
            TxtValidation.Text = "Installer path is required.";
            BtnInstall.IsEnabled = false;
            return;
        }

        if (!Directory.Exists(path))
        {
            TxtValidation.Text = "Installer directory not found.";
            BtnInstall.IsEnabled = false;
            return;
        }

        // Check SA password
        if (string.IsNullOrEmpty(password))
        {
            TxtValidation.Text = "SA password is required.";
            BtnInstall.IsEnabled = false;
            return;
        }

        if (password.Length < 15)
        {
            TxtValidation.Text = "SA password must be at least 15 characters.";
            BtnInstall.IsEnabled = false;
            return;
        }

        // All valid
        TxtValidation.Text = string.Empty;
        BtnInstall.IsEnabled = true;
    }

    private void BrowseInstallerPath_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "Select Installer Directory"
        };

        if (dialog.ShowDialog() == true)
        {
            TxtInstallerPath.Text = dialog.FolderName;
            ValidateInputs();
        }
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var password = PwdSaPassword.Password;

        // Safety net — button should already be disabled for invalid inputs
        if (string.IsNullOrWhiteSpace(password) || password.Length < 15)
            return;

        if (string.IsNullOrWhiteSpace(TxtInstallerPath.Text))
            return;

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
