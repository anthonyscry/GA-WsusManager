using System.Diagnostics;

namespace WsusManager.Core.Utilities;

/// <summary>
/// Provides logging functionality for WSUS Manager operations.
/// Replaces PowerShell Start-WsusLogging, Stop-WsusLogging, Write-Log functions.
/// </summary>
public sealed class Logger : IDisposable
{
    private readonly string _logFilePath;
    private StreamWriter? _writer;
    private readonly object _lockObject = new();
    private bool _disposed;

    public string LogFilePath => _logFilePath;

    /// <summary>
    /// Initializes a new logger instance with automatic log file creation.
    /// </summary>
    /// <param name="scriptName">Name of the script/operation for log filename</param>
    /// <param name="logDirectory">Directory for log files (default: C:\WSUS\Logs)</param>
    /// <param name="useTimestamp">Include timestamp in filename (default: true)</param>
    public Logger(string scriptName, string logDirectory = @"C:\WSUS\Logs", bool useTimestamp = true)
    {
        // Create log directory if it doesn't exist
        Directory.CreateDirectory(logDirectory);

        // Generate log filename
        var timestamp = useTimestamp ? DateTime.Now.ToString("yyyyMMdd_HHmm") : string.Empty;
        var fileName = useTimestamp ? $"{scriptName}_{timestamp}.log" : $"{scriptName}.log";
        _logFilePath = Path.Combine(logDirectory, fileName);

        // Initialize writer (append mode)
        _writer = new StreamWriter(_logFilePath, append: true)
        {
            AutoFlush = true
        };

        Log($"=== Log started: {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===");
    }

    /// <summary>
    /// Writes a timestamped log entry to both file and console.
    /// </summary>
    /// <param name="message">Message to log</param>
    /// <param name="level">Log level (INFO, WARNING, ERROR)</param>
    public void Log(string message, LogLevel level = LogLevel.Info)
    {
        if (_disposed) return;

        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        var prefix = level != LogLevel.Info ? $"{level.ToString().ToUpper()}: " : string.Empty;
        var logEntry = $"{timestamp} - {prefix}{message}";

        lock (_lockObject)
        {
            // Write to file
            _writer?.WriteLine(logEntry);

            // Write to console with color
            var originalColor = Console.ForegroundColor;
            Console.ForegroundColor = level switch
            {
                LogLevel.Success => ConsoleColor.Green,
                LogLevel.Warning => ConsoleColor.Yellow,
                LogLevel.Error => ConsoleColor.Red,
                LogLevel.Info => ConsoleColor.Cyan,
                _ => ConsoleColor.White
            };
            Console.WriteLine(logEntry);
            Console.ForegroundColor = originalColor;
        }
    }

    /// <summary>
    /// Logs a success message in green.
    /// </summary>
    public void Success(string message) => Log(message, LogLevel.Success);

    /// <summary>
    /// Logs a warning message in yellow.
    /// </summary>
    public void Warning(string message) => Log(message, LogLevel.Warning);

    /// <summary>
    /// Logs an error message in red.
    /// </summary>
    public void Error(string message) => Log(message, LogLevel.Error);

    /// <summary>
    /// Logs an error message with exception details.
    /// </summary>
    public void Error(string message, Exception exception)
    {
        Log($"{message} - {exception.Message}", LogLevel.Error);
        if (exception.StackTrace != null)
        {
            Log($"Stack trace: {exception.StackTrace}", LogLevel.Error);
        }
    }

    /// <summary>
    /// Measures and logs the execution time of an operation.
    /// </summary>
    public T MeasureTime<T>(string operationName, Func<T> operation)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            Log($"Starting: {operationName}");
            var result = operation();
            sw.Stop();
            Log($"Completed: {operationName} ({sw.ElapsedMilliseconds}ms)");
            return result;
        }
        catch (Exception ex)
        {
            sw.Stop();
            Error($"Failed: {operationName} ({sw.ElapsedMilliseconds}ms)", ex);
            throw;
        }
    }

    /// <summary>
    /// Measures and logs the execution time of an async operation.
    /// </summary>
    public async Task<T> MeasureTimeAsync<T>(string operationName, Func<Task<T>> operation)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            Log($"Starting: {operationName}");
            var result = await operation();
            sw.Stop();
            Log($"Completed: {operationName} ({sw.ElapsedMilliseconds}ms)");
            return result;
        }
        catch (Exception ex)
        {
            sw.Stop();
            Error($"Failed: {operationName} ({sw.ElapsedMilliseconds}ms)", ex);
            throw;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;

        lock (_lockObject)
        {
            Log($"=== Log ended: {DateTime.Now:yyyy-MM-dd HH:mm:ss} ===");
            _writer?.Dispose();
            _writer = null;
        }

        _disposed = true;
    }
}

/// <summary>
/// Log levels for message categorization.
/// </summary>
public enum LogLevel
{
    Info,
    Success,
    Warning,
    Error
}
