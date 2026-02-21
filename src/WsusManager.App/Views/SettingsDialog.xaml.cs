using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using WsusManager.App.Services;
using WsusManager.Core.Models;

namespace WsusManager.App.Views;

/// <summary>
/// Settings dialog. Allows administrators to edit server mode, refresh interval,
/// content path, SQL instance, and theme selection without restarting the application.
/// Returns updated AppSettings via the Result property when DialogResult is true.
/// </summary>
public partial class SettingsDialog : Window
{
    private readonly IThemeService _themeService;
    private readonly string _entryTheme;
    private string _previewTheme;

    /// <summary>
    /// The updated settings collected from the dialog. Only valid when DialogResult is true.
    /// The caller must copy LogPanelExpanded and LiveTerminalMode from the current settings
    /// before persisting, as those fields are not shown in this dialog.
    /// </summary>
    public AppSettings? Result { get; private set; }

    /// <summary>
    /// Initializes a new instance of the <see cref="SettingsDialog"/> class.
    /// Initializes a new SettingsDialog pre-populated with the current settings.
    /// </summary>
    /// <param name="current">Current application settings to display as defaults.</param>
    /// <param name="themeService">Theme service for live theme preview.</param>
    public SettingsDialog(AppSettings current, IThemeService themeService)
    {
        InitializeComponent();

        _themeService = themeService;
        _entryTheme = themeService.CurrentTheme;
        _previewTheme = _entryTheme;

        // Pre-populate fields from current settings
        // ComboBox: select by matching string content
        foreach (var item in CboServerMode.Items)
        {
            if (item is ComboBoxItem cbi)
            {
                var text = cbi.Content?.ToString();
                if (string.Equals(current.ServerMode, "AirGap", StringComparison.Ordinal) && string.Equals(text, "Air-Gap", StringComparison.Ordinal))
                    CboServerMode.SelectedItem = cbi;
                else if (!string.Equals(current.ServerMode, "AirGap", StringComparison.Ordinal) && string.Equals(text, "Online", StringComparison.Ordinal))
                    CboServerMode.SelectedItem = cbi;
            }
        }

        TxtRefreshInterval.Text = current.RefreshIntervalSeconds.ToString();
        TxtContentPath.Text = current.ContentPath;
        TxtSqlInstance.Text = current.SqlInstance;

        // Build theme swatch grid
        BuildThemeSwatches();

        // ESC key closes dialog without saving (per CLAUDE.md GUI-09)
        KeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
    }

    /// <summary>
    /// Builds the theme swatch grid from ThemeService metadata.
    /// </summary>
    private void BuildThemeSwatches()
    {
        ThemeSwatchGrid.Children.Clear();

        foreach (var kvp in _themeService.ThemeInfos.OrderBy(x => x.Key))
        {
            var themeName = kvp.Key;
            var themeInfo = kvp.Value;

            // Create swatch container
            var swatchContainer = new Border
            {
                Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(themeInfo.PreviewBackground)),
                CornerRadius = new CornerRadius(6),
                Padding = new Thickness(8),
                Margin = new Thickness(4),
                Cursor = Cursors.Hand,
                BorderBrush = new SolidColorBrush(Colors.Transparent),
                BorderThickness = new Thickness(2),
                Tag = themeName
            };

            // Accent bar at bottom
            var accentBar = new Border
            {
                Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(themeInfo.PreviewAccent)),
                Height = 4,
                CornerRadius = new CornerRadius(2),
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Stretch
            };

            // Theme name
            var themeNameBlock = new TextBlock
            {
                Text = themeInfo.DisplayName,
                Foreground = new SolidColorBrush(Colors.White),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 8)
            };

            // Stack layout
            var stackPanel = new StackPanel();
            stackPanel.Children.Add(themeNameBlock);
            stackPanel.Children.Add(accentBar);
            swatchContainer.Child = stackPanel;

            // Highlight active theme
            if (string.Equals(themeName, _previewTheme, StringComparison.OrdinalIgnoreCase))
            {
                var accentColor = (Color)ColorConverter.ConvertFromString(themeInfo.PreviewAccent);
                swatchContainer.BorderBrush = new SolidColorBrush(accentColor);
            }

            // Click handler
            swatchContainer.MouseLeftButtonUp += (s, e) =>
            {
                if (s is Border border && border.Tag is string clickedTheme)
                {
                    OnThemeSwatchClicked(clickedTheme);
                }
            };

            ThemeSwatchGrid.Children.Add(swatchContainer);
        }

        UpdateThemeDescription();
    }

    /// <summary>
    /// Handles theme swatch click: applies theme immediately (live preview).
    /// </summary>
    private void OnThemeSwatchClicked(string themeName)
    {
        _previewTheme = themeName;
        _themeService.ApplyTheme(themeName);

        // Refresh swatch borders to show new selection
        BuildThemeSwatches();
    }

    /// <summary>
    /// Updates the theme description text based on current preview theme.
    /// </summary>
    private void UpdateThemeDescription()
    {
        var info = _themeService.GetThemeInfo(_previewTheme);
        if (info != null)
        {
            ThemeDescriptionText.Text = $"Previewing: {info.DisplayName}. Changes apply immediately. Cancel to revert.";
        }
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
        if (CboServerMode.SelectedItem is ComboBoxItem selected &&
string.Equals(selected.Content?.ToString(), "Air-Gap", StringComparison.Ordinal))
        {
            selectedMode = "AirGap";
        }

        Result = new AppSettings
        {
            ServerMode = selectedMode,
            RefreshIntervalSeconds = interval,
            ContentPath = TxtContentPath.Text.Trim(),
            SqlInstance = TxtSqlInstance.Text.Trim(),
            SelectedTheme = _previewTheme,
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
        // Revert to entry theme
        if (!string.Equals(_previewTheme, _entryTheme, StringComparison.Ordinal))
        {
            _themeService.ApplyTheme(_entryTheme);
        }

        DialogResult = false;
        Close();
    }
}
