using System.Text.RegularExpressions;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Validates installation prerequisites and launches the legacy
/// Install-WsusWithSqlExpress.ps1 script via IProcessRunner in non-interactive mode.
/// This is the only operation that deliberately shells out to PowerShell --
/// the install script is complex and re-implementing in C# provides no benefit.
/// </summary>
public class InstallationService : IInstallationService
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    /// <summary>Required SQL Express installer filename.</summary>
    public const string RequiredInstallerExe = "SQLEXPRADV_x64_ENU.exe";

    /// <summary>PowerShell script filename for installation.</summary>
    public const string InstallScriptName = "Install-WsusWithSqlExpress.ps1";

    /// <summary>Minimum SA password length.</summary>
    public const int MinPasswordLength = 15;

    public InstallationService(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner;
        _logService = logService;
    }

    /// <inheritdoc/>
    public Task<OperationResult> ValidatePrerequisitesAsync(InstallOptions options, CancellationToken ct = default)
    {
        // Check installer path exists
        if (string.IsNullOrWhiteSpace(options.InstallerPath) || !Directory.Exists(options.InstallerPath))
        {
            return Task.FromResult(OperationResult.Fail(
                $"Installer path does not exist: {options.InstallerPath}"));
        }

        // Check required EXE is present
        var exePath = Path.Combine(options.InstallerPath, RequiredInstallerExe);
        if (!File.Exists(exePath))
        {
            return Task.FromResult(OperationResult.Fail(
                $"Required installer not found: {exePath}. " +
                $"Place {RequiredInstallerExe} in the installer directory."));
        }

        // Check password not empty
        if (string.IsNullOrWhiteSpace(options.SaPassword))
        {
            return Task.FromResult(OperationResult.Fail(
                "SA password cannot be empty."));
        }

        // Check password complexity: 15+ chars, 1 digit, 1 special char
        if (options.SaPassword.Length < MinPasswordLength)
        {
            return Task.FromResult(OperationResult.Fail(
                $"SA password must be at least {MinPasswordLength} characters long."));
        }

        if (!Regex.IsMatch(options.SaPassword, @"\d"))
        {
            return Task.FromResult(OperationResult.Fail(
                "SA password must contain at least 1 digit."));
        }

        if (!Regex.IsMatch(options.SaPassword, @"[^a-zA-Z0-9]"))
        {
            return Task.FromResult(OperationResult.Fail(
                "SA password must contain at least 1 special character."));
        }

        return Task.FromResult(OperationResult.Ok("All prerequisites met."));
    }

    /// <inheritdoc/>
    public async Task<OperationResult> InstallAsync(
        InstallOptions options,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            // Locate the PowerShell install script
            var scriptPath = LocateScript();
            if (scriptPath is null)
            {
                var msg = $"Install script not found. Searched for '{InstallScriptName}' in:\n" +
                          $"  {GetSearchPaths()[0]}\n  {GetSearchPaths()[1]}";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            _logService.Info("Starting WSUS installation via {Script}", scriptPath);
            progress?.Report($"Script: {scriptPath}");
            progress?.Report($"Installer path: {options.InstallerPath}");
            progress?.Report($"SA Username: {options.SaUsername}");
            progress?.Report("Starting installation (this may take 30+ minutes)...");
            progress?.Report("");

            // Build PowerShell arguments
            var arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" " +
                            $"-NonInteractive " +
                            $"-InstallerPath \"{options.InstallerPath}\" " +
                            $"-SaUsername \"{options.SaUsername}\" " +
                            $"-SaPassword \"{options.SaPassword}\"";

            var result = await _processRunner.RunAsync(
                "powershell.exe",
                arguments,
                progress,
                ct);

            if (result.Success)
            {
                _logService.Info("WSUS installation completed successfully");
                return OperationResult.Ok("WSUS installation completed successfully.");
            }
            else
            {
                var msg = $"Installation failed with exit code {result.ExitCode}.";
                _logService.Warning(msg);
                return OperationResult.Fail(msg);
            }
        }
        catch (OperationCanceledException)
        {
            _logService.Info("WSUS installation cancelled by user");
            throw;
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "WSUS installation failed with unexpected error");
            return OperationResult.Fail($"Installation failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Locates the install script relative to the current executable directory.
    /// Checks: {AppDir}\Scripts\Install-WsusWithSqlExpress.ps1, then {AppDir}\Install-WsusWithSqlExpress.ps1.
    /// </summary>
    internal string? LocateScript()
    {
        foreach (var path in GetSearchPaths())
        {
            if (File.Exists(path))
                return path;
        }
        return null;
    }

    internal string[] GetSearchPaths()
    {
        var appDir = AppContext.BaseDirectory;
        return
        [
            Path.Combine(appDir, "Scripts", InstallScriptName),
            Path.Combine(appDir, InstallScriptName)
        ];
    }
}
