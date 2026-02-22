using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Validates settings values against acceptable ranges.
/// </summary>
public class SettingsValidationService : ISettingsValidationService
{
    private const int MinRetentionDays = 1;
    private const int MaxRetentionDays = 365;
    private const int MinMaxFileSizeMb = 1;
    private const int MaxMaxFileSizeMb = 1000;
    private const int MinWinRMTimeoutSeconds = 10;
    private const int MaxWinRMTimeoutSeconds = 300;
    private const int MinWinRMRetryCount = 1;
    private const int MaxWinRMRetryCount = 10;

    public ValidationResult ValidateRetentionDays(int days)
    {
        if (days < MinRetentionDays || days > MaxRetentionDays)
        {
            return ValidationResult.Fail(
                $"Log retention must be between {MinRetentionDays} and {MaxRetentionDays} days.");
        }
        return ValidationResult.Success;
    }

    public ValidationResult ValidateMaxFileSizeMb(int sizeMb)
    {
        if (sizeMb < MinMaxFileSizeMb || sizeMb > MaxMaxFileSizeMb)
        {
            return ValidationResult.Fail(
                $"Max file size must be between {MinMaxFileSizeMb} and {MaxMaxFileSizeMb} MB.");
        }
        return ValidationResult.Success;
    }

    public ValidationResult ValidateWinRMTimeoutSeconds(int timeout)
    {
        if (timeout < MinWinRMTimeoutSeconds || timeout > MaxWinRMTimeoutSeconds)
        {
            return ValidationResult.Fail(
                $"WinRM timeout must be between {MinWinRMTimeoutSeconds} and {MaxWinRMTimeoutSeconds} seconds.");
        }
        return ValidationResult.Success;
    }

    public ValidationResult ValidateWinRMRetryCount(int count)
    {
        if (count < MinWinRMRetryCount || count > MaxWinRMRetryCount)
        {
            return ValidationResult.Fail(
                $"WinRM retry count must be between {MinWinRMRetryCount} and {MaxWinRMRetryCount}.");
        }
        return ValidationResult.Success;
    }

    public ValidationResult ValidateAll(AppSettings settings)
    {
        var retentionResult = ValidateRetentionDays(settings.LogRetentionDays);
        if (!retentionResult.IsValid) return retentionResult;

        var sizeResult = ValidateMaxFileSizeMb(settings.LogMaxFileSizeMb);
        if (!sizeResult.IsValid) return sizeResult;

        var timeoutResult = ValidateWinRMTimeoutSeconds(settings.WinRMTimeoutSeconds);
        if (!timeoutResult.IsValid) return timeoutResult;

        var retryResult = ValidateWinRMRetryCount(settings.WinRMRetryCount);
        if (!retryResult.IsValid) return retryResult;

        return ValidationResult.Success;
    }
}
