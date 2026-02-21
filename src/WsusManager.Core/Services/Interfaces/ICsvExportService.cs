using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Exports dashboard data to CSV format with UTF-8 BOM for Excel compatibility.
/// </summary>
public interface ICsvExportService
{
    /// <summary>
    /// Exports computer list to CSV file.
    /// </summary>
    /// <param name="computers">Collection of computers to export.</param>
    /// <param name="progress">Optional progress reporter for status updates.</param>
    /// <param name="cancellationToken">Cancellation token for aborting export.</param>
    /// <returns>Full path to the created CSV file.</returns>
    /// <exception cref="IOException">Thrown when Documents folder is inaccessible or disk is full.</exception>
    Task<string> ExportComputersAsync(
        IEnumerable<ComputerInfo> computers,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Exports update list to CSV file.
    /// </summary>
    /// <param name="updates">Collection of updates to export.</param>
    /// <param name="progress">Optional progress reporter for status updates.</param>
    /// <param name="cancellationToken">Cancellation token for aborting export.</param>
    /// <returns>Full path to the created CSV file.</returns>
    /// <exception cref="IOException">Thrown when Documents folder is inaccessible or disk is full.</exception>
    Task<string> ExportUpdatesAsync(
        IEnumerable<UpdateInfo> updates,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);
}
