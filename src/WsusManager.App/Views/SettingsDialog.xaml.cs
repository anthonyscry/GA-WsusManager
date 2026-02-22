using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using WsusManager.App.Services;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.App.Views;

/// <summary>
/// Settings dialog. Allows administrators to edit server mode, refresh interval,
/// content path, SQL instance, and theme selection without restarting the application.
/// Returns updated AppSettings via the Result property when DialogResult is true.
/// </summary>
public partial class SettingsDialog : Window
{
    private readonly IThemeService _themeService;
    private readonly ISettingsValidationService _validationService;
    private readonly string _entryTheme;
    private string _previewTheme;
    private KeyEventHandler? _escHandler;

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
    /// <param name="validationService">Settings validation service.</param>
    public SettingsDialog(AppSettings current, IThemeService themeService, ISettingsValidationService validationService)
    {
        InitializeComponent();

        _themeService = themeService;
        _validationService = validationService;
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

        // Populate Operations section
        PopulateComboBoxFromEnum(CboDefaultSyncProfile, current.DefaultSyncProfile.ToString());

        // Populate Logging section
        PopulateComboBoxFromEnum(CboLogLevel, current.LogLevel.ToString());
        TxtLogRetentionDays.Text = current.LogRetentionDays.ToString();
        TxtLogMaxFileSizeMb.Text = current.LogMaxFileSizeMb.ToString();

        // Populate Behavior section
        ChkPersistWindowState.IsChecked = current.PersistWindowState;
        PopulateComboBoxFromEnum(CboDashboardRefreshInterval, current.DashboardRefreshInterval.ToString());
        ChkRequireConfirmationDestructive.IsChecked = current.RequireConfirmationDestructive;

        // Populate Advanced section
        TxtWinRMTimeoutSeconds.Text = current.WinRMTimeoutSeconds.ToString();
        TxtWinRMRetryCount.Text = current.WinRMRetryCount.ToString();

        // Wire up validation handlers
        TxtLogRetentionDays.LostFocus += (s, e) => ValidateNumericTextBox(
            TxtLogRetentionDays,
            int.TryParse(TxtLogRetentionDays.Text, out var days) ? days : 0,
            _validationService.ValidateRetentionDays(days));

        TxtLogMaxFileSizeMb.LostFocus += (s, e) => ValidateNumericTextBox(
            TxtLogMaxFileSizeMb,
            int.TryParse(TxtLogMaxFileSizeMb.Text, out var size) ? size : 0,
            _validationService.ValidateMaxFileSizeMb(size));

        TxtWinRMTimeoutSeconds.LostFocus += (s, e) => ValidateNumericTextBox(
            TxtWinRMTimeoutSeconds,
            int.TryParse(TxtWinRMTimeoutSeconds.Text, out var timeout) ? timeout : 0,
            _validationService.ValidateWinRMTimeoutSeconds(timeout));

        TxtWinRMRetryCount.LostFocus += (s, e) => ValidateNumericTextBox(
            TxtWinRMRetryCount,
            int.TryParse(TxtWinRMRetryCount.Text, out var count) ? count : 0,
            _validationService.ValidateWinRMRetryCount(count));

        // Build theme swatch grid
        BuildThemeSwatches();

        // ESC key closes dialog without saving (per CLAUDE.md GUI-09)
        // Store handler reference for cleanup to prevent memory leak
        _escHandler = (s, e) =>
        {
            if (e.Key == Key.Escape)
                Close();
        };
        KeyDown += _escHandler;
        Closed += Dialog_Closed;
    }

    private void Dialog_Closed(object? sender, EventArgs e)
    {
        // Cleanup event handlers to prevent memory leaks
        if (_escHandler != null)
        {
            KeyDown -= _escHandler;
            _escHandler = null;
        }
        Closed -= Dialog_Closed;
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

        // Validate new numeric fields
        var retentionResult = _validationService.ValidateRetentionDays(
            int.TryParse(TxtLogRetentionDays.Text, out var retention) ? retention : 0);
        if (!retentionResult.IsValid)
        {
            ShowValidationError(retentionResult.ErrorMessage ?? "Validation failed");
            return;
        }

        var sizeResult = _validationService.ValidateMaxFileSizeMb(
            int.TryParse(TxtLogMaxFileSizeMb.Text, out var size) ? size : 0);
        if (!sizeResult.IsValid)
        {
            ShowValidationError(sizeResult.ErrorMessage ?? "Validation failed");
            return;
        }

        var timeoutResult = _validationService.ValidateWinRMTimeoutSeconds(
            int.TryParse(TxtWinRMTimeoutSeconds.Text, out var timeout) ? timeout : 0);
        if (!timeoutResult.IsValid)
        {
            ShowValidationError(timeoutResult.ErrorMessage ?? "Validation failed");
            return;
        }

        var retryResult = _validationService.ValidateWinRMRetryCount(
            int.TryParse(TxtWinRMRetryCount.Text, out var retry) ? retry : 0);
        if (!retryResult.IsValid)
        {
            ShowValidationError(retryResult.ErrorMessage ?? "Validation failed");
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
            LiveTerminalMode = false,
            // New properties
            DefaultSyncProfile = ParseDefaultSyncProfile(),
            LogLevel = ParseLogLevel(),
            LogRetentionDays = int.Parse(TxtLogRetentionDays.Text),
            LogMaxFileSizeMb = int.Parse(TxtLogMaxFileSizeMb.Text),
            PersistWindowState = ChkPersistWindowState.IsChecked ?? true,
            DashboardRefreshInterval = ParseDashboardRefreshInterval(),
            RequireConfirmationDestructive = ChkRequireConfirmationDestructive.IsChecked ?? true,
            WinRMTimeoutSeconds = int.Parse(TxtWinRMTimeoutSeconds.Text),
            WinRMRetryCount = int.Parse(TxtWinRMRetryCount.Text)
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

    private void BtnResetToDefaults_Click(object sender, RoutedEventArgs e)
    {
        // Show confirmation dialog
        var result = MessageBox.Show(
            "Reset all settings to default values? This cannot be undone.",
            "Reset to Defaults",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes)
            return;

        // Create default AppSettings
        var defaults = new AppSettings();

        // Reset all controls to default values
        // Server Mode
        foreach (var item in CboServerMode.Items)
        {
            if (item is ComboBoxItem cbi && string.Equals(cbi.Content?.ToString(), "Online", StringComparison.Ordinal))
                CboServerMode.SelectedItem = cbi;
        }

        // General settings
        TxtRefreshInterval.Text = defaults.RefreshIntervalSeconds.ToString();
        TxtContentPath.Text = defaults.ContentPath;
        TxtSqlInstance.Text = defaults.SqlInstance;

        // New controls
        PopulateComboBoxFromEnum(CboDefaultSyncProfile, defaults.DefaultSyncProfile.ToString());
        PopulateComboBoxFromEnum(CboLogLevel, defaults.LogLevel.ToString());
        TxtLogRetentionDays.Text = defaults.LogRetentionDays.ToString();
        TxtLogMaxFileSizeMb.Text = defaults.LogMaxFileSizeMb.ToString();
        ChkPersistWindowState.IsChecked = defaults.PersistWindowState;
        PopulateComboBoxFromEnum(CboDashboardRefreshInterval, defaults.DashboardRefreshInterval.ToString());
        ChkRequireConfirmationDestructive.IsChecked = defaults.RequireConfirmationDestructive;
        TxtWinRMTimeoutSeconds.Text = defaults.WinRMTimeoutSeconds.ToString();
        TxtWinRMRetryCount.Text = defaults.WinRMRetryCount.ToString();

        // Reset theme
        _previewTheme = defaults.SelectedTheme;
        _themeService.ApplyTheme(_previewTheme);
        BuildThemeSwatches();

        // Clear any validation errors
        ClearValidationErrors();
    }

    /// <summary>
    /// Populates a ComboBox from an enum value by matching Tag property.
    /// </summary>
    private void PopulateComboBoxFromEnum(ComboBox comboBox, string enumValue)
    {
        foreach (var item in comboBox.Items)
        {
            if (item is ComboBoxItem cbi && string.Equals(cbi.Tag?.ToString(), enumValue, StringComparison.Ordinal))
            {
                comboBox.SelectedItem = cbi;
                break;
            }
        }
    }

    /// <summary>
    /// Validates a numeric TextBox and provides visual feedback.
    /// </summary>
    private void ValidateNumericTextBox(TextBox textBox, int value, Core.Models.ValidationResult result)
    {
        if (result.IsValid)
        {
            textBox.BorderBrush = (Brush)FindResource("BorderPrimary");
            textBox.ToolTip = null;
        }
        else
        {
            textBox.BorderBrush = new SolidColorBrush(Colors.Red);
            textBox.ToolTip = result.ErrorMessage;
        }
    }

    /// <summary>
    /// Clears validation errors from all numeric TextBoxes.
    /// </summary>
    private void ClearValidationErrors()
    {
        var primaryBorder = (Brush)FindResource("BorderPrimary");
        TxtLogRetentionDays.BorderBrush = primaryBorder;
        TxtLogRetentionDays.ToolTip = null;
        TxtLogMaxFileSizeMb.BorderBrush = primaryBorder;
        TxtLogMaxFileSizeMb.ToolTip = null;
        TxtWinRMTimeoutSeconds.BorderBrush = primaryBorder;
        TxtWinRMTimeoutSeconds.ToolTip = null;
        TxtWinRMRetryCount.BorderBrush = primaryBorder;
        TxtWinRMRetryCount.ToolTip = null;
    }

    /// <summary>
    /// Shows a validation error message box.
    /// </summary>
    private void ShowValidationError(string message)
    {
        MessageBox.Show(
            message,
            "Validation Error",
            MessageBoxButton.OK,
            MessageBoxImage.Warning);
    }

    /// <summary>
    /// Parses the DefaultSyncProfile enum from the ComboBox selection.
    /// </summary>
    private DefaultSyncProfile ParseDefaultSyncProfile()
    {
        if (CboDefaultSyncProfile.SelectedItem is ComboBoxItem cbi && cbi.Tag is string tag)
        {
            return Enum.Parse<DefaultSyncProfile>(tag);
        }
        return DefaultSyncProfile.Full;
    }

    /// <summary>
    /// Parses the LogLevel enum from the ComboBox selection.
    /// </summary>
    private LogLevel ParseLogLevel()
    {
        if (CboLogLevel.SelectedItem is ComboBoxItem cbi && cbi.Tag is string tag)
        {
            return Enum.Parse<LogLevel>(tag);
        }
        return LogLevel.Info;
    }

    /// <summary>
    /// Parses the DashboardRefreshInterval enum from the ComboBox selection.
    /// </summary>
    private DashboardRefreshInterval ParseDashboardRefreshInterval()
    {
        if (CboDashboardRefreshInterval.SelectedItem is ComboBoxItem cbi && cbi.Tag is string tag)
        {
            return Enum.Parse<DashboardRefreshInterval>(tag);
        }
        return DashboardRefreshInterval.Sec30;
    }
}
