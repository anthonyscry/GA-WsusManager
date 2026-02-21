using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace WsusManager.App.Converters;

/// <summary>
/// Converts boolean values to Visibility enum values.
/// Returns Visible when true, Collapsed when false.
/// </summary>
public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is true ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is Visibility visibility && visibility == Visibility.Visible;
    }
}
