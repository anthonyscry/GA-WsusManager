using System.Security.Principal;

namespace WsusManager.Core.Utilities;

/// <summary>
/// Provides admin privilege checking functionality.
/// Replaces PowerShell Test-AdminPrivileges function.
/// </summary>
public static class AdminPrivileges
{
    /// <summary>
    /// Checks if the current process is running with administrator privileges.
    /// </summary>
    /// <returns>True if running as admin, false otherwise</returns>
    public static bool IsAdmin()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Ensures the current process is running with administrator privileges.
    /// </summary>
    /// <param name="throwOnFail">If true, throws an exception if not admin</param>
    /// <exception cref="UnauthorizedAccessException">Thrown when not running as admin and throwOnFail is true</exception>
    public static void RequireAdmin(bool throwOnFail = true)
    {
        if (!IsAdmin())
        {
            if (throwOnFail)
            {
                throw new UnauthorizedAccessException(
                    "This application must be run as Administrator. " +
                    "Please restart with elevated privileges.");
            }
        }
    }

    /// <summary>
    /// Gets the current user's name and domain.
    /// </summary>
    public static (string Domain, string Username) GetCurrentUser()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var parts = identity.Name.Split('\\');
            return parts.Length == 2
                ? (parts[0], parts[1])
                : (Environment.MachineName, parts[0]);
        }
        catch
        {
            return (Environment.MachineName, Environment.UserName);
        }
    }
}
