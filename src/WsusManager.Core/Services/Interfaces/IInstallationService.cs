using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Service for installing WSUS with SQL Server Express.
/// Validates prerequisites and launches the legacy PowerShell install script
/// in non-interactive mode with parameters collected via the GUI dialog.
/// </summary>
public interface IInstallationService
{
    /// <summary>
    /// Validates that all installation prerequisites are met:
    /// installer path exists, required EXE is present, password meets complexity requirements.
    /// </summary>
    Task<OperationResult> ValidatePrerequisitesAsync(InstallOptions options, CancellationToken ct = default);

    /// <summary>
    /// Runs Install-WsusWithSqlExpress.ps1 with -NonInteractive and collected parameters.
    /// Output is streamed to the progress reporter in real-time.
    /// </summary>
    Task<OperationResult> InstallAsync(InstallOptions options, IProgress<string>? progress = null, CancellationToken ct = default);
}
