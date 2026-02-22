namespace WsusManager.Core.Models;

/// <summary>
/// Logging level for application output. Controls which messages
/// are written to the log panel and log file.
/// </summary>
public enum LogLevel
{
    /// <summary>Detailed debugging information (verbose).</summary>
    Debug,

    /// <summary>General informational messages (default).</summary>
    Info,

    /// <summary>Warning messages for potential issues.</summary>
    Warning,

    /// <summary>Error messages for failures.</summary>
    Error,

    /// <summary>Critical errors that cause operation failure.</summary>
    Fatal
}
