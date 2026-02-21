using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using WsusManager.Core.Models;

namespace WsusManager.App.Views;

/// <summary>
/// Schedule Task dialog. Collects all scheduling parameters:
/// task name, schedule type, day, time, maintenance profile, and credentials.
/// Returns ScheduledTaskOptions via public property.
/// </summary>
public partial class ScheduleTaskDialog : Window
{
    /// <summary>
    /// The schedule options collected from the dialog. Only valid when DialogResult is true.
    /// </summary>
    public ScheduledTaskOptions? Options { get; private set; }

    public ScheduleTaskDialog()
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
        if (BtnCreate is null || TxtValidation is null) return;

        // Task name must not be empty
        if (string.IsNullOrWhiteSpace(TxtTaskName?.Text))
        {
            TxtValidation.Text = "Task name is required.";
            BtnCreate.IsEnabled = false;
            return;
        }

        // Time must match HH:mm format
        var time = TxtTime?.Text ?? string.Empty;
        if (!Regex.IsMatch(time, @"^\d{2}:\d{2}$"))
        {
            TxtValidation.Text = "Time must be in HH:mm format (e.g. 02:00).";
            BtnCreate.IsEnabled = false;
            return;
        }

        // When Monthly: day of month must be 1-31
        var isMonthly = CmbScheduleType?.SelectedIndex == 0;
        if (isMonthly)
        {
            var dayText = TxtDayOfMonth?.Text ?? string.Empty;
            if (!int.TryParse(dayText, out var day) || day < 1 || day > 31)
            {
                TxtValidation.Text = "Day of month must be between 1 and 31.";
                BtnCreate.IsEnabled = false;
                return;
            }
        }

        // Password must not be empty
        if (string.IsNullOrEmpty(PwdPassword?.Password))
        {
            TxtValidation.Text = "Password is required for the scheduled task.";
            BtnCreate.IsEnabled = false;
            return;
        }

        // All valid
        TxtValidation.Text = string.Empty;
        BtnCreate.IsEnabled = true;
    }

    private void ScheduleType_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (DayOfMonthPanel is null || DayOfWeekPanel is null) return;

        var selectedIndex = CmbScheduleType.SelectedIndex;

        // Monthly = 0: show DayOfMonth
        // Weekly = 1: show DayOfWeek
        // Daily = 2: hide both
        DayOfMonthPanel.Visibility = selectedIndex == 0 ? Visibility.Visible : Visibility.Collapsed;
        DayOfWeekPanel.Visibility = selectedIndex == 1 ? Visibility.Visible : Visibility.Collapsed;

        ValidateInputs();
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var password = PwdPassword.Password;

        // Safety net — button should already be disabled for invalid inputs
        if (string.IsNullOrWhiteSpace(password) || string.IsNullOrWhiteSpace(TxtTaskName.Text))
            return;

        // Parse day of month
        if (!int.TryParse(TxtDayOfMonth.Text, out var dayOfMonth) || dayOfMonth < 1 || dayOfMonth > 31)
            dayOfMonth = 15;

        // Parse schedule type
        var scheduleType = CmbScheduleType.SelectedIndex switch
        {
            1 => ScheduleType.Weekly,
            2 => ScheduleType.Daily,
            _ => ScheduleType.Monthly
        };

        // Parse day of week
        var dayOfWeek = CmbDayOfWeek.SelectedIndex switch
        {
            0 => DayOfWeek.Sunday,
            1 => DayOfWeek.Monday,
            2 => DayOfWeek.Tuesday,
            3 => DayOfWeek.Wednesday,
            4 => DayOfWeek.Thursday,
            5 => DayOfWeek.Friday,
            6 => DayOfWeek.Saturday,
            _ => DayOfWeek.Saturday
        };

        // Parse profile
        var profile = (CmbProfile.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "Full";

        Options = new ScheduledTaskOptions
        {
            TaskName = TxtTaskName.Text.Trim(),
            Schedule = scheduleType,
            DayOfMonth = dayOfMonth,
            DayOfWeek = dayOfWeek,
            Time = string.IsNullOrWhiteSpace(TxtTime.Text) ? "02:00" : TxtTime.Text.Trim(),
            MaintenanceProfile = profile,
            Username = string.IsNullOrWhiteSpace(TxtUsername.Text) ? @".\dod_admin" : TxtUsername.Text.Trim(),
            Password = password
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
