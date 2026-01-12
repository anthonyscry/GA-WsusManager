using Microsoft.Win32;

namespace WsusManager.Core.Utilities;

/// <summary>
/// Provides path validation and WSUS configuration helpers.
/// Replaces PowerShell Get-WsusContentPath and Test-WsusPath functions.
/// </summary>
public static class PathHelper
{
    /// <summary>
    /// Gets the WSUS content path from the Windows registry.
    /// </summary>
    /// <returns>WSUS content path, or null if not found</returns>
    public static string? GetWsusContentPath()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Update Services\Server\Setup");
            return key?.GetValue("ContentDir") as string;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Validates that a path exists.
    /// </summary>
    /// <param name="path">Path to validate</param>
    /// <param name="createIfMissing">If true, creates the directory if it doesn't exist</param>
    /// <returns>True if path exists (or was created), false otherwise</returns>
    public static bool ValidatePath(string path, bool createIfMissing = false)
    {
        try
        {
            if (Directory.Exists(path))
                return true;

            if (createIfMissing)
            {
                Directory.CreateDirectory(path);
                return true;
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Validates that a path is safe (not containing injection characters).
    /// Prevents command injection vulnerabilities.
    /// </summary>
    /// <param name="path">Path to validate</param>
    /// <returns>True if path is safe, false otherwise</returns>
    public static bool IsSafePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return false;

        // Check for command injection characters
        var dangerousChars = new[] { ';', '&', '|', '<', '>', '`', '$', '(', ')', '{', '}' };
        if (dangerousChars.Any(path.Contains))
            return false;

        // Validate it's a valid Windows path
        try
        {
            var fullPath = Path.GetFullPath(path);
            return fullPath.StartsWith(@"C:\", StringComparison.OrdinalIgnoreCase) ||
                   fullPath.StartsWith(@"D:\", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Escapes a path for safe use in command strings.
    /// </summary>
    /// <param name="path">Path to escape</param>
    /// <returns>Escaped path</returns>
    public static string EscapePath(string path)
    {
        return $"\"{path.Replace("\"", "\"\"")}\"";
    }

    /// <summary>
    /// Gets the standard WSUS paths.
    /// </summary>
    public static class StandardPaths
    {
        public const string WsusContent = @"C:\WSUS";
        public const string WsusLogs = @"C:\WSUS\Logs";
        public const string WsusSqlDb = @"C:\WSUS\SQLDB";
        public const string WsusConfig = @"C:\WSUS\Config";

        public static void EnsureStandardPathsExist()
        {
            ValidatePath(WsusContent, createIfMissing: true);
            ValidatePath(WsusLogs, createIfMissing: true);
            ValidatePath(WsusConfig, createIfMissing: true);
        }
    }

    /// <summary>
    /// Gets available disk space for a given path.
    /// </summary>
    /// <param name="path">Path to check</param>
    /// <returns>Available space in GB, or null if path invalid</returns>
    public static decimal? GetAvailableSpaceGB(string path)
    {
        try
        {
            var driveInfo = new DriveInfo(Path.GetPathRoot(path) ?? "C:\\");
            return (decimal)driveInfo.AvailableFreeSpace / 1024 / 1024 / 1024;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Checks if there's sufficient disk space for an operation.
    /// </summary>
    /// <param name="path">Path to check</param>
    /// <param name="requiredGB">Required space in GB</param>
    /// <returns>True if sufficient space available</returns>
    public static bool HasSufficientSpace(string path, decimal requiredGB)
    {
        var available = GetAvailableSpaceGB(path);
        return available.HasValue && available.Value >= requiredGB;
    }
}
