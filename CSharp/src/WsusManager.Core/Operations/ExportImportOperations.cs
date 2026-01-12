using System.Diagnostics;
using WsusManager.Core.Utilities;

namespace WsusManager.Core.Operations;

/// <summary>
/// Provides WSUS export/import operations for air-gap network support.
/// Wraps PowerShell CLI scripts for now - full C# implementation in Phase 2.
/// </summary>
public class ExportImportOperations
{
    private readonly string _contentPath;
    private readonly Logger? _logger;

    public ExportImportOperations(string contentPath = @"C:\WSUS", Logger? logger = null)
    {
        _contentPath = contentPath;
        _logger = logger;
    }

    /// <summary>
    /// Exports WSUS metadata and updates to a folder for transfer to air-gapped network.
    /// </summary>
    /// <param name="exportPath">Destination folder for export</param>
    /// <param name="progress">Optional progress callback</param>
    /// <returns>True if export successful</returns>
    public async Task<bool> ExportAsync(
        string exportPath,
        IProgress<string>? progress = null)
    {
        try
        {
            // Validate paths
            if (!PathHelper.IsSafePath(exportPath))
            {
                _logger?.Error($"Invalid export path: {exportPath}");
                return false;
            }

            // Ensure export directory exists
            Directory.CreateDirectory(exportPath);

            _logger?.Log($"Starting export to {exportPath}");
            progress?.Report($"Starting export to {exportPath}");

            // For POC: Call PowerShell CLI script
            // In Phase 2: Implement native C# export logic
            var scriptPath = FindManagementScript();
            if (scriptPath == null)
            {
                _logger?.Error("Could not find Invoke-WsusManagement.ps1");
                return false;
            }

            var result = await RunPowerShellScriptAsync(
                scriptPath,
                $"-Export -ContentPath '{_contentPath}' -ExportRoot '{exportPath}'",
                progress);

            if (result)
            {
                _logger?.Success($"Export completed successfully");
                progress?.Report("Export completed successfully");
            }
            else
            {
                _logger?.Error("Export failed");
                progress?.Report("Export failed");
            }

            return result;
        }
        catch (Exception ex)
        {
            _logger?.Error($"Export error", ex);
            progress?.Report($"Error: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Imports WSUS metadata and updates from a folder (for air-gapped servers).
    /// </summary>
    /// <param name="importPath">Source folder containing export</param>
    /// <param name="progress">Optional progress callback</param>
    /// <returns>True if import successful</returns>
    public async Task<bool> ImportAsync(
        string importPath,
        IProgress<string>? progress = null)
    {
        try
        {
            // Validate paths
            if (!PathHelper.IsSafePath(importPath))
            {
                _logger?.Error($"Invalid import path: {importPath}");
                return false;
            }

            if (!Directory.Exists(importPath))
            {
                _logger?.Error($"Import path does not exist: {importPath}");
                return false;
            }

            _logger?.Log($"Starting import from {importPath}");
            progress?.Report($"Starting import from {importPath}");

            // For POC: Call PowerShell CLI script
            var scriptPath = FindManagementScript();
            if (scriptPath == null)
            {
                _logger?.Error("Could not find Invoke-WsusManagement.ps1");
                return false;
            }

            var result = await RunPowerShellScriptAsync(
                scriptPath,
                $"-Import -ContentPath '{_contentPath}' -ExportRoot '{importPath}'",
                progress);

            if (result)
            {
                _logger?.Success("Import completed successfully");
                progress?.Report("Import completed successfully");
            }
            else
            {
                _logger?.Error("Import failed");
                progress?.Report("Import failed");
            }

            return result;
        }
        catch (Exception ex)
        {
            _logger?.Error("Import error", ex);
            progress?.Report($"Error: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Finds the PowerShell management script in standard locations.
    /// </summary>
    private static string? FindManagementScript()
    {
        var exePath = AppContext.BaseDirectory;
        var locations = new[]
        {
            Path.Combine(exePath, "Scripts", "Invoke-WsusManagement.ps1"),
            Path.Combine(exePath, "..", "Scripts", "Invoke-WsusManagement.ps1"),
            Path.Combine(exePath, "..", "..", "Scripts", "Invoke-WsusManagement.ps1")
        };

        return locations.FirstOrDefault(File.Exists);
    }

    /// <summary>
    /// Runs a PowerShell script and captures output.
    /// </summary>
    private async Task<bool> RunPowerShellScriptAsync(
        string scriptPath,
        string arguments,
        IProgress<string>? progress)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" {arguments}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? Environment.CurrentDirectory
        };

        using var process = new Process { StartInfo = psi };

        // Capture output
        process.OutputDataReceived += (s, e) =>
        {
            if (!string.IsNullOrEmpty(e.Data))
            {
                _logger?.Log(e.Data);
                progress?.Report(e.Data);
            }
        };

        process.ErrorDataReceived += (s, e) =>
        {
            if (!string.IsNullOrEmpty(e.Data))
            {
                _logger?.Error(e.Data);
                progress?.Report($"ERROR: {e.Data}");
            }
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        await process.WaitForExitAsync();

        return process.ExitCode == 0;
    }
}
