using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Manages WSUS firewall rules for ports 8530 (HTTP) and 8531 (HTTPS).
/// Uses netsh advfirewall commands via IProcessRunner for compatibility
/// with all Windows Server versions (no managed firewall API required).
/// </summary>
public interface IFirewallService
{
    /// <summary>
    /// Checks whether both WSUS firewall rules (HTTP:8530 and HTTPS:8531) exist.
    /// Returns true only when both inbound rules are present.
    /// </summary>
    Task<OperationResult<bool>> CheckWsusRulesExistAsync(CancellationToken ct = default);

    /// <summary>
    /// Creates the WSUS firewall rules for ports 8530 and 8531.
    /// Does not fail if rules already exist (idempotent).
    /// Progress messages are reported for each rule creation.
    /// </summary>
    Task<OperationResult> CreateWsusRulesAsync(IProgress<string>? progress = null, CancellationToken ct = default);
}
