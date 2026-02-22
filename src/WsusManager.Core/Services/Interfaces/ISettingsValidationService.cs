using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Provides validation for application settings values.
/// </summary>
public interface ISettingsValidationService
{
    /// <summary>Validates log retention days (1-365).</summary>
    ValidationResult ValidateRetentionDays(int days);

    /// <summary>Validates max log file size in MB (1-1000).</summary>
    ValidationResult ValidateMaxFileSizeMb(int sizeMb);

    /// <summary>Validates WinRM timeout in seconds (10-300).</summary>
    ValidationResult ValidateWinRMTimeoutSeconds(int timeout);

    /// <summary>Validates WinRM retry count (1-10).</summary>
    ValidationResult ValidateWinRMRetryCount(int count);

    /// <summary>Validates all settings in an AppSettings instance.</summary>
    ValidationResult ValidateAll(AppSettings settings);
}
