using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace WsusManager.App.Services;

/// <summary>
/// Windows title bar color customization service.
/// Uses DWM (Desktop Window Manager) APIs to set title bar colors on Windows 10/11.
/// </summary>
public static class TitleBarService
{
    #region DWM Imports

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        DwmWindowAttribute attr,
        ref int attrValue,
        int attrSize);

    [DllImport("dwmapi.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void DwmSetWindowAttribute(
        IntPtr hwnd,
        DwmWindowAttribute attr,
        ref bool attrValue,
        int attrSize);

    #endregion

    #region Enums

    private enum DwmWindowAttribute
    {
        DWMWA_NCRENDERING_ENABLED = 1,
        DWMWA_NCRENDERING_POLICY = 2,
        DWMWA_TRANSITIONS_FORCEDISABLED = 3,
        DWMWA_ALLOW_NCPAINT = 4,
        DWMWA_CAPTION_BUTTON_BOUNDS = 5,
        DWMWA_NONCLIENT_RTL_LAYOUT = 6,
        DWMWA_FORCE_ICONIC_REPRESENTATION = 7,
        DWMWA_FLIP3D_POLICY = 8,
        DWMWA_EXTENDED_FRAME_BOUNDS = 9,
        DWMWA_HAS_ICONIC_BITMAP = 10,
        DWMWA_DISALLOW_PEEK = 11,
        DWMWA_EXCLUDED_FROM_PEEK = 12,
        DWMWA_CLOAK = 13,
        DWMWA_CLOAKED = 14,
        DWMWA_FREEZE_REPRESENTATION = 15,
        DWMWA_PASSIVE_UPDATE_WINDOW = 16,
        DWMWA_USE_HOSTBACKDROPBRUSH = 17,
        DWMWA_USE_IMMERSIVE_DARK_MODE = 20,
        DWMWA_WINDOW_CORNER_PREFERENCE = 33,
        DWMWA_BORDER_COLOR = 34,
        DWMWA_CAPTION_COLOR = 35,
        DWMWA_TEXT_COLOR = 36,
        DWMWA_VISIBLE_FRAME_BORDER_THICKNESS = 37,
        DWMWA_MICA_EFFECT = 38
    }

    #endregion

    /// <summary>
    /// Sets the title bar colors for the main window.
    /// </summary>
    /// <param name="window">The window to customize.</param>
    /// <param name="backgroundColor">Title bar background color.</param>
    /// <param name="foregroundColor">Title bar text color.</param>
    public static void SetTitleBarColors(Window window, Color? backgroundColor, Color? foregroundColor)
    {
        if (window == null) return;

        var helper = new WindowInteropHelper(window);
        var hwnd = helper.Handle;

        if (hwnd == IntPtr.Zero)
        {
            // Window not yet created, set up loaded handler
            window.Loaded += (s, e) => SetTitleBarColors(window, backgroundColor, foregroundColor);
            return;
        }

        // Enable immersive dark mode for title bar (better for dark themes)
        bool darkMode = true;
        try
        {
            DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_USE_IMMERSIVE_DARK_MODE,
                ref darkMode, sizeof(bool));
        }
        catch { }

        // Set background color if provided
        if (backgroundColor.HasValue)
        {
            int color = ColorToAbgr(backgroundColor.Value);
            try
            {
                DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_CAPTION_COLOR,
                    ref color, sizeof(int));
            }
            catch { }
        }

        // Set text color if provided
        if (foregroundColor.HasValue)
        {
            int color = ColorToArgb(foregroundColor.Value);
            try
            {
                DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_TEXT_COLOR,
                    ref color, sizeof(int));
            }
            catch { }
        }

        // Set border color to match background for seamless look
        if (backgroundColor.HasValue)
        {
            int borderColor = ColorToAbgr(backgroundColor.Value);
            try
            {
                DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_BORDER_COLOR,
                    ref borderColor, sizeof(int));
            }
            catch { }
        }
    }

    /// <summary>
    /// Resets title bar to system default colors.
    /// </summary>
    public static void ResetTitleBarColors(Window window)
    {
        if (window == null) return;

        var helper = new WindowInteropHelper(window);
        var hwnd = helper.Handle;

        if (hwnd == IntPtr.Zero) return;

        // Reset to default (value = -1)
        int defaultValue = -1;

        try
        {
            DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_CAPTION_COLOR,
                ref defaultValue, sizeof(int));
            DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_TEXT_COLOR,
                ref defaultValue, sizeof(int));
            DwmSetWindowAttribute(hwnd, DwmWindowAttribute.DWMWA_BORDER_COLOR,
                ref defaultValue, sizeof(int));
        }
        catch { }
    }

    /// <summary>
    /// Converts a Color to ABGR format (little-endian ARGB) used by DWM.
    /// </summary>
    private static int ColorToAbgr(Color color)
    {
        return (color.A << 24) | (color.B << 16) | (color.G << 8) | color.R;
    }

    /// <summary>
    /// Converts a Color to ARGB format.
    /// </summary>
    private static int ColorToArgb(Color color)
    {
        return (color.A << 24) | (color.R << 16) | (color.G << 8) | color.B;
    }
}
