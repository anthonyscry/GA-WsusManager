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
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var password = PwdPassword.Password;

        if (string.IsNullOrWhiteSpace(password))
        {
            MessageBox.Show("Password is required for the scheduled task.", "Validation",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (string.IsNullOrWhiteSpace(TxtTaskName.Text))
        {
            MessageBox.Show("Task name is required.", "Validation",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

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
