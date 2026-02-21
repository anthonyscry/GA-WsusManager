namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Generates self-contained PowerShell scripts for WSUS client operations.
/// Use this service when WinRM is unavailable on a target host — the generated
/// script can be copied to the target and run manually as Administrator.
/// </summary>
public interface IScriptGeneratorService
{
    /// <summary>
    /// Generates a self-contained PowerShell script for the given operation type.
    /// The script is ready to run on the target host without any external dependencies.
    /// </summary>
    /// <param name="operationType">
    /// The operation to generate. Use one of the display names returned by
    /// <see cref="GetAvailableOperations"/> or the internal type keys:
    /// CancelStuckJobs, ForceCheckIn, TestConnectivity, RunDiagnostics, MassGpUpdate.
    /// </param>
    /// <param name="wsusServerUrl">
    /// WSUS server URL (e.g. http://wsus-server:8530).
    /// Required for TestConnectivity scripts. Ignored for other operation types.
    /// </param>
    /// <param name="hostnames">
    /// List of target hostnames for MassGpUpdate scripts.
    /// If null or empty a placeholder list is embedded in the script.
    /// Ignored for all other operation types.
    /// </param>
    /// <returns>The complete PowerShell script content as a UTF-8 string.</returns>
    /// <exception cref="ArgumentException">
    /// Thrown when <paramref name="operationType"/> is not a recognised operation.
    /// </exception>
    string GenerateScript(
        string operationType,
        string? wsusServerUrl = null,
        IReadOnlyList<string>? hostnames = null);

    /// <summary>
    /// Returns the ordered list of display names shown in the Script Generator UI dropdown.
    /// </summary>
    IReadOnlyList<string> GetAvailableOperations();
}
