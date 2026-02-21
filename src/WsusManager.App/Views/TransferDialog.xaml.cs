using System.Windows;
using System.Windows.Input;
using WsusManager.Core.Models;

namespace WsusManager.App.Views;

/// <summary>
/// Transfer dialog for Export/Import operations.
/// Collects all parameters before operation begins -- no interactive prompts during execution.
/// </summary>
public partial class TransferDialog : Window
{
    /// <summary>True when Export is selected, false for Import.</summary>
    public bool IsExportMode => RbExport.IsChecked == true;

    /// <summary>Export options. Only valid when IsExportMode is true and DialogResult is true.</summary>
    public ExportOptions? ExportResult { get; private set; }

    /// <summary>Import options. Only valid when IsExportMode is false and DialogResult is true.</summary>
    public ImportOptions? ImportResult { get; private set; }

    public TransferDialog()
    {
        InitializeComponent();

        // ESC key closes dialog (GUI-04)
        KeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
    }

    private void Input_Changed(object sender, RoutedEventArgs e) => ValidateInputs();

    private void ValidateInputs()
    {
        if (BtnOk is null || TxtValidation is null) return;

        if (IsExportMode)
        {
            // Export mode: all paths optional — always valid
            TxtValidation.Text = string.Empty;
            BtnOk.IsEnabled = true;
        }
        else
        {
            // Import mode: source path is required
            if (string.IsNullOrWhiteSpace(TxtSourcePath?.Text))
            {
                TxtValidation.Text = "Source path is required for import.";
                BtnOk.IsEnabled = false;
            }
            else
            {
                TxtValidation.Text = string.Empty;
                BtnOk.IsEnabled = true;
            }
        }
    }

    private void Direction_Changed(object sender, RoutedEventArgs e)
    {
        if (ExportFields is null || ImportFields is null || BtnOk is null) return;

        if (RbExport.IsChecked == true)
        {
            ExportFields.Visibility = Visibility.Visible;
            ImportFields.Visibility = Visibility.Collapsed;
            BtnOk.Content = "Start Export";
        }
        else
        {
            ExportFields.Visibility = Visibility.Collapsed;
            ImportFields.Visibility = Visibility.Visible;
            BtnOk.Content = "Start Import";
        }

        ValidateInputs();
    }

    private void BrowseFullExport_Click(object sender, RoutedEventArgs e)
    {
        var path = BrowseFolder("Select Full Export Path");
        if (path is not null) TxtFullExportPath.Text = path;
    }

    private void BrowseDiffExport_Click(object sender, RoutedEventArgs e)
    {
        var path = BrowseFolder("Select Differential Export Path");
        if (path is not null) TxtDiffExportPath.Text = path;
    }

    private void BrowseSource_Click(object sender, RoutedEventArgs e)
    {
        var path = BrowseFolder("Select Source Path");
        if (path is not null)
        {
            TxtSourcePath.Text = path;
            ValidateInputs();
        }
    }

    private void BrowseDest_Click(object sender, RoutedEventArgs e)
    {
        var path = BrowseFolder("Select Destination Path");
        if (path is not null) TxtDestPath.Text = path;
    }

    private static string? BrowseFolder(string description)
    {
        // Use OpenFolderDialog (WPF/.NET 8+)
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = description
        };

        return dialog.ShowDialog() == true ? dialog.FolderName : null;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        if (IsExportMode)
        {
            if (!int.TryParse(TxtExportDays.Text, out var days) || days < 1)
                days = 30;

            ExportResult = new ExportOptions
            {
                SourcePath = @"C:\WSUS",
                FullExportPath = string.IsNullOrWhiteSpace(TxtFullExportPath.Text) ? null : TxtFullExportPath.Text.Trim(),
                DifferentialExportPath = string.IsNullOrWhiteSpace(TxtDiffExportPath.Text) ? null : TxtDiffExportPath.Text.Trim(),
                ExportDays = days,
                IncludeDatabaseBackup = ChkIncludeBackup.IsChecked == true
            };
        }
        else
        {
            // Safety net — button should already be disabled for empty source
            if (string.IsNullOrWhiteSpace(TxtSourcePath.Text))
                return;

            ImportResult = new ImportOptions
            {
                SourcePath = TxtSourcePath.Text.Trim(),
                DestinationPath = string.IsNullOrWhiteSpace(TxtDestPath.Text) ? @"C:\WSUS" : TxtDestPath.Text.Trim(),
                RunContentResetAfterImport = ChkContentReset.IsChecked == true
            };
        }

        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
