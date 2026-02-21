using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Checks and repairs WSUS content directory permissions and SQL login permissions.
/// Content path checks verify NETWORK SERVICE and IIS_IUSRS ACLs.
/// SQL checks query server role membership and login existence.
/// </summary>
public interface IPermissionsService
{
    /// <summary>
    /// Checks whether the WSUS content directory has the required ACL entries.
    /// Verifies NETWORK SERVICE and IIS_IUSRS have Full Control.
    /// </summary>
    Task<OperationResult<bool>> CheckContentPermissionsAsync(string contentPath, CancellationToken ct = default);

    /// <summary>
    /// Repairs content directory permissions by granting Full Control to
    /// NETWORK SERVICE and IIS_IUSRS via icacls.
    /// </summary>
    Task<OperationResult> RepairContentPermissionsAsync(string contentPath, IProgress<string>? progress = null, CancellationToken ct = default);

    /// <summary>
    /// Checks whether the current user running this process is a SQL sysadmin.
    /// Queries: SELECT IS_SRVROLEMEMBER('sysadmin') — returns 1 if yes.
    /// </summary>
    Task<OperationResult<bool>> CheckSqlSysadminAsync(string sqlInstance, CancellationToken ct = default);

    /// <summary>
    /// Checks whether NETWORK SERVICE has a SQL Server login.
    /// Queries sys.server_principals for NT AUTHORITY\NETWORK SERVICE.
    /// </summary>
    Task<OperationResult<bool>> CheckNetworkServiceLoginAsync(string sqlInstance, CancellationToken ct = default);
}
