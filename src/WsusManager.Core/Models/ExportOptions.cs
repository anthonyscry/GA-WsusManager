namespace WsusManager.Core.Models;

/// <summary>
/// Options for WSUS content export operations.
/// </summary>
public record ExportOptions
{
    /// <summary>Source WSUS content path. Defaults to C:\WSUS.</summary>
    public string SourcePath { get; init; } = @"C:\WSUS";

    /// <summary>Full export destination path. Null or empty to skip full export.</summary>
    public string? FullExportPath { get; init; }

    /// <summary>Differential export destination path. Null or empty to skip differential export.</summary>
    public string? DifferentialExportPath { get; init; }

    /// <summary>Number of days for differential export (files modified within N days). Defaults to 30.</summary>
    public int ExportDays { get; init; } = 30;

    /// <summary>Whether to include the newest .bak database backup file in the export.</summary>
    public bool IncludeDatabaseBackup { get; init; }
}
