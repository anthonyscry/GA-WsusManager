namespace WsusManager.Core.Models;

/// <summary>
/// Options for WSUS content import operations.
/// </summary>
public record ImportOptions
{
    /// <summary>Source path for import (e.g., USB drive or network share).</summary>
    public required string SourcePath { get; init; }

    /// <summary>Destination WSUS content path. Defaults to C:\WSUS.</summary>
    public string DestinationPath { get; init; } = @"C:\WSUS";

    /// <summary>Whether to run content reset (wsusutil reset) after import completes.</summary>
    public bool RunContentResetAfterImport { get; init; }
}
