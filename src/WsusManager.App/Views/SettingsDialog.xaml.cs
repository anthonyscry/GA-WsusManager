using System.Windows;
using System.Windows.Input;
using WsusManager.Core.Models;

namespace WsusManager.App.Views;

/// <summary>
/// Settings dialog. Allows administrators to edit server mode, refresh interval,
/// content path, and SQL instance without restarting the application.
/// Returns updated AppSettings via the Result property when DialogResult is true.
/// </summary>
public partial class SettingsDialog : Window
{
    /// <summary>
    /// The updated settings collected from the dialog. Only valid when DialogResult is true.
    /// The caller must copy LogPanelExpanded and LiveTerminalMode from the current settings
    /// before persisting, as those fields are not shown in this dialog.
    /// </summary>
    public AppSettings? Result { get; private set; }

    /// <summary>
    /// Initializes a new SettingsDialog pre-populated with the current settings.
    /// </summary>
    /// <param name="current">Current application settings to display as defaults.</param>
    public SettingsDialog(AppSettings current)
    {
        InitializeComponent();

        // Pre-populate fields from current settings
        // ComboBox: select by matching string content
        foreach (var item in CboServerMode.Items)
        {
            if (item is System.Windows.Controls.ComboBoxItem cbi)
            {
                var text = cbi.Content?.ToString();
                if (current.ServerMode == "AirGap" && text == "Air-Gap")
                    CboServerMode.SelectedItem = cbi;
                else if (current.ServerMode != "AirGap" && text == "Online")
                    CboServerMode.SelectedItem = cbi;
            }
        }

        TxtRefreshInterval.Text = current.RefreshIntervalSeconds.ToString();
        TxtContentPath.Text = current.ContentPath;
        TxtSqlInstance.Text = current.SqlInstance;

        // ESC key closes dialog without saving (per CLAUDE.md GUI-09)
        KeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
    }

    private void BtnSave_Click(object sender, RoutedEventArgs e)
    {
        // Validate refresh interval: must be a positive integer >= 5
        if (!int.TryParse(TxtRefreshInterval.Text, out var interval) || interval < 5)
        {
            MessageBox.Show(
                "Refresh interval must be a number >= 5 seconds.",
                "Validation Error",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        // Determine server mode from ComboBox selection
        var selectedMode = "Online";
        if (CboServerMode.SelectedItem is System.Windows.Controls.ComboBoxItem selected &&
            selected.Content?.ToString() == "Air-Gap")
        {
            selectedMode = "AirGap";
        }

        Result = new AppSettings
        {
            ServerMode = selectedMode,
            RefreshIntervalSeconds = interval,
            ContentPath = TxtContentPath.Text.Trim(),
            SqlInstance = TxtSqlInstance.Text.Trim(),
            // These fields are not shown in this dialog.
            // The caller (MainViewModel.OpenSettings) will overwrite these
            // with the current in-memory values before saving to disk.
            LogPanelExpanded = true,
            LiveTerminalMode = false
        };

        DialogResult = true;
        Close();
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
