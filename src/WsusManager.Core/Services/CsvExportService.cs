using System.Text;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Service for exporting dashboard data to CSV format with UTF-8 BOM for Excel compatibility.
/// Uses streaming writes for memory efficiency with large datasets.
/// </summary>
public sealed class CsvExportService : ICsvExportService
{
    private const int BatchSize = 100;

    /// <summary>
    /// Exports computer list to CSV file with UTF-8 BOM.
    /// </summary>
    public async Task<string> ExportComputersAsync(
        IEnumerable<ComputerInfo> computers,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var fileName = $"WsusManager-Computers-{DateTime.Now:yyyyMMdd-HHmmss}.csv";
        var documentsPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var filePath = Path.Combine(documentsPath, fileName);

        progress?.Report("Creating CSV file...");

        var stream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None);
        // Use UTF-8 with BOM for Excel compatibility
        var writer = new StreamWriter(stream, new UTF8Encoding(true));

        try
        {
            // Write header
            await writer.WriteLineAsync("Hostname,IP Address,Status,Last Sync,Pending Updates,OS Version").ConfigureAwait(false);

            // Write data in batches
            var batch = new List<ComputerInfo>(BatchSize);
            var count = 0;

            foreach (var computer in computers)
            {
                cancellationToken.ThrowIfCancellationRequested();
                batch.Add(computer);

                if (batch.Count >= BatchSize)
                {
                    await WriteBatchAsync(writer, batch, cancellationToken).ConfigureAwait(false);
                    count += batch.Count;
                    progress?.Report($"Exported {count} computers...");
                    batch.Clear();
                }
            }

            // Write remaining items
            if (batch.Count > 0)
            {
                await WriteBatchAsync(writer, batch, cancellationToken).ConfigureAwait(false);
                count += batch.Count;
            }

            await writer.FlushAsync().ConfigureAwait(false);
        }
        finally
        {
            await writer.DisposeAsync().ConfigureAwait(false);
        }

        return filePath;
    }

    /// <summary>
    /// Exports update list to CSV file with UTF-8 BOM.
    /// </summary>
    public async Task<string> ExportUpdatesAsync(
        IEnumerable<UpdateInfo> updates,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var fileName = $"WsusManager-Updates-{DateTime.Now:yyyyMMdd-HHmmss}.csv";
        var documentsPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var filePath = Path.Combine(documentsPath, fileName);

        progress?.Report("Creating CSV file...");

        var stream = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None);
        // Use UTF-8 with BOM for Excel compatibility
        var writer = new StreamWriter(stream, new UTF8Encoding(true));

        try
        {
            // Write header
            await writer.WriteLineAsync("KB Number,Title,Classification,Approval Status,Approval Date").ConfigureAwait(false);

            // Write data in batches
            var batch = new List<UpdateInfo>(BatchSize);
            var count = 0;

            foreach (var update in updates)
            {
                cancellationToken.ThrowIfCancellationRequested();
                batch.Add(update);

                if (batch.Count >= BatchSize)
                {
                    await WriteBatchAsync(writer, batch, cancellationToken).ConfigureAwait(false);
                    count += batch.Count;
                    progress?.Report($"Exported {count} updates...");
                    batch.Clear();
                }
            }

            // Write remaining items
            if (batch.Count > 0)
            {
                await WriteBatchAsync(writer, batch, cancellationToken).ConfigureAwait(false);
                count += batch.Count;
            }

            await writer.FlushAsync().ConfigureAwait(false);
        }
        finally
        {
            await writer.DisposeAsync().ConfigureAwait(false);
        }

        return filePath;
    }

    /// <summary>
    /// Writes a batch of computers to the CSV stream.
    /// </summary>
    private static async Task WriteBatchAsync(StreamWriter writer, List<ComputerInfo> batch, CancellationToken ct)
    {
        foreach (var computer in batch)
        {
            ct.ThrowIfCancellationRequested();
            var line = $"{EscapeField(computer.Hostname)},{EscapeField(computer.IpAddress)}," +
                       $"{EscapeField(computer.Status)},{EscapeField(computer.LastSync.ToString("yyyy-MM-dd HH:mm:ss"))}," +
                       $"{computer.PendingUpdates},{EscapeField(computer.OsVersion)}";
            await writer.WriteLineAsync(line).ConfigureAwait(false);
        }
    }

    /// <summary>
    /// Writes a batch of updates to the CSV stream.
    /// </summary>
    private static async Task WriteBatchAsync(StreamWriter writer, List<UpdateInfo> batch, CancellationToken ct)
    {
        foreach (var update in batch)
        {
            ct.ThrowIfCancellationRequested();
            var approvalStatus = update.IsDeclined ? "Declined" : update.IsApproved ? "Approved" : "Not Approved";
            var line = $"{EscapeField(update.KbArticle ?? "N/A")},{EscapeField(update.Title)}," +
                       $"{EscapeField(update.Classification)},{EscapeField(approvalStatus)}," +
                       $"{EscapeField(update.ApprovalDate.ToString("yyyy-MM-dd HH:mm:ss"))}";
            await writer.WriteLineAsync(line).ConfigureAwait(false);
        }
    }

    /// <summary>
    /// Escapes a CSV field by wrapping in quotes if it contains special characters.
    /// Quotes are escaped by doubling them.
    /// </summary>
    private static string EscapeField(string? field)
    {
        if (string.IsNullOrEmpty(field))
            return string.Empty;

        // Quote if contains comma, quote, or newline
        if (field.Contains(',') || field.Contains('"') || field.Contains('\n') || field.Contains('\r'))
        {
            return $"\"{field.Replace("\"", "\"\"")}\"";
        }
        return field;
    }
}
