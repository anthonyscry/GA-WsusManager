namespace WsusManager.Core.Logging;

/// <summary>
/// Logging service interface for structured logging to C:\WSUS\Logs\.
/// Wraps the underlying Serilog implementation for DI injection and testability.
/// </summary>
public interface ILogService
{
    /// <summary>
    /// Logs an informational message.
    /// </summary>
    void Info(string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs a warning message.
    /// </summary>
    void Warning(string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs an error message with optional exception.
    /// </summary>
    void Error(string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs an error with an associated exception.
    /// </summary>
    void Error(Exception exception, string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs a debug-level message.
    /// </summary>
    void Debug(string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs a fatal error (application cannot continue).
    /// </summary>
    void Fatal(string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs a fatal error with an associated exception.
    /// </summary>
    void Fatal(Exception exception, string messageTemplate, params object[] propertyValues);

    /// <summary>
    /// Logs application startup information: version, OS, CLR, startup duration.
    /// </summary>
    void LogStartup(string version, long startupMs);

    /// <summary>
    /// Ensures all buffered log entries are written to disk.
    /// Call during application shutdown.
    /// </summary>
    void Flush();
}
