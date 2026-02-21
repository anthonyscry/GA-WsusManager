using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Data.SqlClient;
using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Checks and repairs WSUS content directory permissions and SQL login permissions.
/// Content permissions use System.Security.AccessControl for checking and icacls for repair.
/// SQL checks use Microsoft.Data.SqlClient with integrated security (Integrated Security=True).
/// </summary>
public class PermissionsService : IPermissionsService
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    private const string NetworkServiceAccount = "NT AUTHORITY\\NETWORK SERVICE";
    private const string IisIusrsAccount = "IIS_IUSRS";
    private const int SqlConnectTimeoutSeconds = 5;
    private const int SqlCommandTimeoutSeconds = 10;

    public PermissionsService(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner;
        _logService = logService;
    }

    /// <inheritdoc/>
    public Task<OperationResult<bool>> CheckContentPermissionsAsync(string contentPath, CancellationToken ct = default)
    {
        return Task.Run<OperationResult<bool>>(() =>
        {
            try
            {
                _logService.Debug("Checking content permissions for: {Path}", contentPath);

                if (!Directory.Exists(contentPath))
                {
                    return OperationResult<bool>.Fail($"Content directory does not exist: {contentPath}");
                }

                var dirInfo = new DirectoryInfo(contentPath);
                var acl = dirInfo.GetAccessControl();
                var rules = acl.GetAccessRules(
                    includeExplicit: true,
                    includeInherited: true,
                    targetType: typeof(NTAccount));

                bool hasNetworkService = false;
                bool hasIisIusrs = false;

                foreach (FileSystemAccessRule rule in rules)
                {
                    if (rule.AccessControlType != AccessControlType.Allow) continue;
                    if ((rule.FileSystemRights & FileSystemRights.FullControl) == 0 &&
                        (rule.FileSystemRights & FileSystemRights.Modify) == 0) continue;

                    var identity = rule.IdentityReference.Value;

                    if (identity.Contains("NETWORK SERVICE", StringComparison.OrdinalIgnoreCase))
                        hasNetworkService = true;

                    if (identity.Contains("IIS_IUSRS", StringComparison.OrdinalIgnoreCase))
                        hasIisIusrs = true;
                }

                bool hasPermissions = hasNetworkService && hasIisIusrs;

                _logService.Debug(
                    "Content permissions: NETWORK SERVICE={HasNS}, IIS_IUSRS={HasIIS}",
                    hasNetworkService, hasIisIusrs);

                return OperationResult<bool>.Ok(hasPermissions,
                    hasPermissions
                        ? "Content directory permissions are correct."
                        : $"Missing permissions: " +
                          $"{(hasNetworkService ? "" : "NETWORK SERVICE ")}" +
                          $"{(hasIisIusrs ? "" : "IIS_IUSRS")}");
            }
            catch (Exception ex)
            {
                _logService.Error(ex, "Error checking content permissions for {Path}", contentPath);
                return OperationResult<bool>.Fail($"Error checking permissions: {ex.Message}", ex);
            }
        }, ct);
    }

    /// <inheritdoc/>
    public async Task<OperationResult> RepairContentPermissionsAsync(
        string contentPath,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Info("Repairing content permissions for: {Path}", contentPath);

            if (!Directory.Exists(contentPath))
            {
                return OperationResult.Fail($"Content directory does not exist: {contentPath}");
            }

            // Grant Full Control to NETWORK SERVICE (OI)(CI) = Object Inherit + Container Inherit
            progress?.Report($"Granting Full Control to NETWORK SERVICE on {contentPath}...");
            var nsResult = await _processRunner.RunAsync(
                "icacls",
                $"\"{contentPath}\" /grant \"NETWORK SERVICE:(OI)(CI)F\" /T",
                ct: ct).ConfigureAwait(false);

            if (!nsResult.Success)
            {
                var msg = $"Failed to grant NETWORK SERVICE permissions: {nsResult.Output}";
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            progress?.Report("[OK] NETWORK SERVICE granted Full Control.");

            // Grant Full Control to IIS_IUSRS (OI)(CI) = Object Inherit + Container Inherit
            progress?.Report($"Granting Full Control to IIS_IUSRS on {contentPath}...");
            var iisResult = await _processRunner.RunAsync(
                "icacls",
                $"\"{contentPath}\" /grant \"IIS_IUSRS:(OI)(CI)F\" /T",
                ct: ct).ConfigureAwait(false);

            if (!iisResult.Success)
            {
                var msg = $"Failed to grant IIS_IUSRS permissions: {iisResult.Output}";
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            progress?.Report("[OK] IIS_IUSRS granted Full Control.");

            _logService.Info("Content permissions repaired successfully for: {Path}", contentPath);
            return OperationResult.Ok("Content directory permissions repaired successfully.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Error repairing content permissions for {Path}", contentPath);
            return OperationResult.Fail($"Error repairing permissions: {ex.Message}", ex);
        }
    }

    /// <inheritdoc/>
    public async Task<OperationResult<bool>> CheckSqlSysadminAsync(string sqlInstance, CancellationToken ct = default)
    {
        try
        {
            _logService.Debug("Checking SQL sysadmin role membership on {SqlInstance}", sqlInstance);

            var connStr = BuildConnectionString(sqlInstance, "master");
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT IS_SRVROLEMEMBER('sysadmin')";
            cmd.CommandTimeout = SqlCommandTimeoutSeconds;

            var result = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
            bool isSysadmin = result != null && result != DBNull.Value && Convert.ToInt32(result) == 1;

            _logService.Debug("SQL sysadmin check: {IsSysadmin}", isSysadmin);

            return OperationResult<bool>.Ok(isSysadmin,
                isSysadmin
                    ? "Current user has SQL sysadmin permissions."
                    : "Current user lacks SQL sysadmin permissions.");
        }
        catch (SqlException ex)
        {
            _logService.Warning("SQL sysadmin check failed (SQL may be offline): {Error}", ex.Message);
            return OperationResult<bool>.Fail($"SQL connection failed: {ex.Message}", ex);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Error checking SQL sysadmin on {SqlInstance}", sqlInstance);
            return OperationResult<bool>.Fail($"Error checking sysadmin: {ex.Message}", ex);
        }
    }

    /// <inheritdoc/>
    public async Task<OperationResult<bool>> CheckNetworkServiceLoginAsync(string sqlInstance, CancellationToken ct = default)
    {
        try
        {
            _logService.Debug("Checking NETWORK SERVICE SQL login on {SqlInstance}", sqlInstance);

            var connStr = BuildConnectionString(sqlInstance, "master");
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync(ct).ConfigureAwait(false);

            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sys.server_principals " +
                              "WHERE name = 'NT AUTHORITY\\NETWORK SERVICE'";
            cmd.CommandTimeout = SqlCommandTimeoutSeconds;

            var result = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
            bool loginExists = result != null && result != DBNull.Value;

            _logService.Debug("NETWORK SERVICE SQL login exists: {LoginExists}", loginExists);

            return OperationResult<bool>.Ok(loginExists,
                loginExists
                    ? "NETWORK SERVICE SQL login exists."
                    : "NETWORK SERVICE SQL login is missing.");
        }
        catch (SqlException ex)
        {
            _logService.Warning("NETWORK SERVICE login check failed: {Error}", ex.Message);
            return OperationResult<bool>.Fail($"SQL connection failed: {ex.Message}", ex);
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Error checking NETWORK SERVICE login on {SqlInstance}", sqlInstance);
            return OperationResult<bool>.Fail($"Error checking login: {ex.Message}", ex);
        }
    }

    private static string BuildConnectionString(string sqlInstance, string database) =>
        $"Data Source={sqlInstance};Initial Catalog={database};" +
        $"Integrated Security=True;TrustServerCertificate=True;" +
        $"Connect Timeout={SqlConnectTimeoutSeconds}";
}
