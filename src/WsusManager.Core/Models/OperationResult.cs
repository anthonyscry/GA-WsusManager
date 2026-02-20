namespace WsusManager.Core.Models;

/// <summary>
/// Represents the result of a service operation. Every public service method
/// returns this type instead of throwing exceptions for expected failures.
/// Exceptions are reserved for programming errors only.
/// </summary>
public record OperationResult(bool Success, string Message, Exception? Exception = null)
{
    /// <summary>Creates a successful result.</summary>
    public static OperationResult Ok(string message = "Success") => new(true, message);

    /// <summary>Creates a failed result.</summary>
    public static OperationResult Fail(string message, Exception? ex = null) => new(false, message, ex);
}

/// <summary>
/// Generic version of OperationResult that includes a data payload.
/// </summary>
public record OperationResult<T>(bool Success, string Message, T? Data = default, Exception? Exception = null)
{
    /// <summary>Creates a successful result with data.</summary>
    public static OperationResult<T> Ok(T data, string message = "Success") => new(true, message, data);

    /// <summary>Creates a failed result.</summary>
    public static OperationResult<T> Fail(string message, Exception? ex = null) => new(false, message, default, ex);
}
