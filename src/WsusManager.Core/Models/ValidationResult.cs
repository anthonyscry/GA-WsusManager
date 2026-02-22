namespace WsusManager.Core.Models;

/// <summary>
/// Result of a settings validation operation. Indicates success or failure
/// with an optional error message.
/// </summary>
public class ValidationResult
{
    /// <summary>Gets whether the validation passed.</summary>
    public bool IsValid { get; init; }

    /// <summary>Gets the error message if validation failed.</summary>
    public string? ErrorMessage { get; init; }

    /// <summary>Creates a successful validation result.</summary>
    public static ValidationResult Success => new() { IsValid = true };

    /// <summary>Creates a failed validation result with an error message.</summary>
    public static ValidationResult Fail(string message) => new()
    {
        IsValid = false,
        ErrorMessage = message
    };
}
