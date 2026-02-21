using System.Globalization;

namespace WsusManager.Tests.Helpers;

/// <summary>
/// Utility class for calculating WCAG 2.0 contrast ratios between colors.
/// Used to verify theme accessibility compliance.
/// </summary>
public static class ColorContrastHelper
{
    // WCAG 2.0 relative luminance constants for sRGB color space
    private const double LinearThreshold = 0.03928; // Threshold for linear vs gamma-corrected values
    private const double LinearDivisor = 12.92;     // Divisor for linear color values
    private const double Gamma = 2.4;                // Gamma correction exponent
    private const double GammaOffset = 0.055;        // Offset for gamma correction
    private const double GammaDivisor = 1.055;              // Divisor for gamma correction
    private const double LuminanceOffset = 0.05;     // Offset added in contrast ratio calculation
    private const double RedCoefficient = 0.2126;    // sRGB luminance coefficient for red
    private const double GreenCoefficient = 0.7152;  // sRGB luminance coefficient for green
    private const double BlueCoefficient = 0.0722;   // sRGB luminance coefficient for blue

    /// <summary>
    /// Calculates contrast ratio between two colors using WCAG 2.0 formula.
    /// Returns a value from 1:1 (no contrast) to 21:1 (maximum contrast).
    /// WCAG AA requires 4.5:1 for normal text, 3:1 for large text.
    /// </summary>
    /// <param name="foregroundHex">Foreground color in hex format (e.g., "#FFFFFF").</param>
    /// <param name="backgroundHex">Background color in hex format (e.g., "#000000").</param>
    /// <returns>Contrast ratio from 1.0 to 21.0.</returns>
    public static double CalculateContrastRatio(string foregroundHex, string backgroundHex)
    {
        var (r1, g1, b1) = ParseColor(foregroundHex);
        var (r2, g2, b2) = ParseColor(backgroundHex);

        var fgLuminance = CalculateRelativeLuminance(r1, g1, b1);
        var bgLuminance = CalculateRelativeLuminance(r2, g2, b2);

        var lighter = Math.Max(fgLuminance, bgLuminance);
        var darker = Math.Min(fgLuminance, bgLuminance);

        return (lighter + LuminanceOffset) / (darker + LuminanceOffset);
    }

    /// <summary>
    /// Parses a hex color string to RGB byte values (0-255).
    /// </summary>
    private static (byte R, byte G, byte B) ParseColor(string hex)
    {
        hex = hex.TrimStart('#');
        var r = byte.Parse(hex.Substring(0, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        var g = byte.Parse(hex.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        var b = byte.Parse(hex.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return (r, g, b);
    }

    /// <summary>
    /// Calculates relative luminance according to WCAG 2.0 specification.
    /// Formula: L = 0.2126 * R + 0.7152 * G + 0.0722 * B
    /// Where each channel is first gamma-corrected.
    /// </summary>
    private static double CalculateRelativeLuminance(byte r, byte g, byte b)
    {
        // Convert 0-255 to 0-1 range
        var rNormalized = r / 255.0;
        var gNormalized = g / 255.0;
        var bNormalized = b / 255.0;

        // Apply gamma correction for each channel
        var rLinear = rNormalized <= LinearThreshold
            ? rNormalized / LinearDivisor
            : Math.Pow((rNormalized + GammaOffset) / GammaDivisor, Gamma);
        var gLinear = gNormalized <= LinearThreshold
            ? gNormalized / LinearDivisor
            : Math.Pow((gNormalized + GammaOffset) / GammaDivisor, Gamma);
        var bLinear = bNormalized <= LinearThreshold
            ? bNormalized / LinearDivisor
            : Math.Pow((bNormalized + GammaOffset) / GammaDivisor, Gamma);

        // Calculate luminance using sRGB coefficients
        return (RedCoefficient * rLinear) + (GreenCoefficient * gLinear) + (BlueCoefficient * bLinear);
    }

    /// <summary>
    /// Returns a WCAG compliance rating for a given contrast ratio.
    /// </summary>
    /// <param name="contrastRatio">The calculated contrast ratio.</param>
    /// <param name="isLargeText">Whether the text is large (≥18pt or ≥14pt bold).</param>
    /// <returns>A string indicating the WCAG level: "AAA", "AA", or "Fail".</returns>
    public static string GetContrastRating(double contrastRatio, bool isLargeText = false)
    {
        var threshold = isLargeText ? 3.0 : 4.5;
        if (contrastRatio >= 7.0)
        {
            return "AAA"; // Enhanced contrast
        }

        if (contrastRatio >= threshold)
        {
            return "AA"; // Minimum compliance
        }

        return "Fail";
    }
}
