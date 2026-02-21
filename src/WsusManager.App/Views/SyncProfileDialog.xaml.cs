using System.Windows;
using System.Windows.Input;
using WsusManager.Core.Models;

namespace WsusManager.App.Views;

/// <summary>
/// Sync profile selection dialog. Returns the selected SyncProfile via the SelectedProfile property.
/// </summary>
public partial class SyncProfileDialog : Window
{
    /// <summary>
    /// The profile selected by the user. Only valid when DialogResult is true.
    /// </summary>
    public SyncProfile SelectedProfile { get; private set; } = SyncProfile.FullSync;

    public SyncProfileDialog()
    {
        InitializeComponent();

        // ESC key closes dialog (GUI-04)
        KeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        SelectedProfile = RbFullSync.IsChecked == true ? SyncProfile.FullSync
            : RbQuickSync.IsChecked == true ? SyncProfile.QuickSync
            : SyncProfile.SyncOnly;

        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
