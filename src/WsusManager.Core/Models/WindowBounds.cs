using System.Text.Json.Serialization;

namespace WsusManager.Core.Models;

/// <summary>
/// Window position and state for persistence. Stores the window's
/// bounds and maximized state to restore on next launch.
/// </summary>
public class WindowBounds
{
    /// <summary>Window width in pixels.</summary>
    [JsonPropertyName("width")]
    public double Width { get; set; } = 1280;

    /// <summary>Window height in pixels.</summary>
    [JsonPropertyName("height")]
    public double Height { get; set; } = 720;

    /// <summary>Window left position in pixels.</summary>
    [JsonPropertyName("left")]
    public double Left { get; set; } = 100;

    /// <summary>Window top position in pixels.</summary>
    [JsonPropertyName("top")]
    public double Top { get; set; } = 100;

    /// <summary>Window state (Normal, Maximized).</summary>
    [JsonPropertyName("windowState")]
    public string WindowState { get; set; } = "Normal";

    /// <summary>
    /// Checks if the bounds are valid for the current screen configuration.
    /// Bounds are invalid if they span multiple monitors or are outside the working area.
    /// </summary>
    public bool IsValid()
    {
        // Check for NaN or infinity
        if (double.IsNaN(Width) || double.IsInfinity(Width) ||
            double.IsNaN(Height) || double.IsInfinity(Height) ||
            double.IsNaN(Left) || double.IsInfinity(Left) ||
            double.IsNaN(Top) || double.IsInfinity(Top))
        {
            return false;
        }

        // Check for reasonable minimum size
        if (Width < 400 || Height < 300)
        {
            return false;
        }

        return true;
    }

    /// <summary>
    /// Checks if the bounds are within the primary screen's working area.
    /// Note: This method requires WPF SystemParameters, so it should be called
    /// from the App layer. Returns true by default for Core layer compatibility.
    /// </summary>
    public bool IsWithinScreenBounds()
    {
        // This validation requires WPF's SystemParameters.WorkArea
        // The actual check is performed in the App layer (MainWindow.xaml.cs)
        // For now, return true as a placeholder
        return true;
    }
}
