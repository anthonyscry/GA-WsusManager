using System.Windows;
using Microsoft.Win32;

namespace WsusManager.Gui.Views;

/// <summary>
/// Dialog for Export/Import operations.
/// Demonstrates clean C# dialog pattern - much simpler than PowerShell!
/// </summary>
public partial class ExportImportDialog : Window
{
    public bool IsExport => RadioExport?.IsChecked == true;
    public string SelectedPath => TxtPath?.Text ?? string.Empty;
    public string Direction => IsExport ? "Export" : "Import";

    public ExportImportDialog()
    {
        InitializeComponent();

        // ESC key closes dialog
        KeyDown += (s, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Escape)
                Close();
        };
    }

    private void BtnBrowse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = RadioExport.IsChecked == true
                ? "Select destination folder for export"
                : "Select source folder for import",
            SelectedPath = string.IsNullOrWhiteSpace(TxtPath.Text) ? @"C:\WSUS" : TxtPath.Text
        };

        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            TxtPath.Text = dialog.SelectedPath;
        }
    }

    private void BtnOk_Click(object sender, RoutedEventArgs e)
    {
        // Validate path is not empty
        if (string.IsNullOrWhiteSpace(TxtPath.Text))
        {
            MessageBox.Show(
                "Please select a folder path.",
                "Transfer",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        // Validate path exists
        if (!System.IO.Directory.Exists(TxtPath.Text))
        {
            var result = MessageBox.Show(
                "The selected folder does not exist. Create it?",
                "Transfer",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (result == MessageBoxResult.Yes)
            {
                try
                {
                    System.IO.Directory.CreateDirectory(TxtPath.Text);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(
                        $"Failed to create folder: {ex.Message}",
                        "Error",
                        MessageBoxButton.OK,
                        MessageBoxImage.Error);
                    return;
                }
            }
            else
            {
                return;
            }
        }

        DialogResult = true;
        Close();
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
