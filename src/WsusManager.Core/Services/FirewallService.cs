using WsusManager.Core.Infrastructure;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Firewall rule management via netsh advfirewall commands.
/// Checks for and creates inbound rules on WSUS ports 8530 (HTTP) and 8531 (HTTPS).
/// </summary>
public class FirewallService : IFirewallService
{
    private readonly IProcessRunner _processRunner;
    private readonly ILogService _logService;

    private const string NetshExe = "netsh";
    private const string HttpRuleName = "WSUS HTTP";
    private const string HttpsRuleName = "WSUS HTTPS";
    private const int HttpPort = 8530;
    private const int HttpsPort = 8531;

    public FirewallService(IProcessRunner processRunner, ILogService logService)
    {
        _processRunner = processRunner;
        _logService = logService;
    }

    /// <inheritdoc/>
    public async Task<OperationResult<bool>> CheckWsusRulesExistAsync(CancellationToken ct = default)
    {
        try
        {
            _logService.Debug("Checking WSUS firewall rules");

            var httpResult = await _processRunner.RunAsync(
                NetshExe,
                $"advfirewall firewall show rule name=\"{HttpRuleName}\"",
                ct: ct).ConfigureAwait(false);

            var httpsResult = await _processRunner.RunAsync(
                NetshExe,
                $"advfirewall firewall show rule name=\"{HttpsRuleName}\"",
                ct: ct).ConfigureAwait(false);

            bool bothExist = httpResult.Success && httpsResult.Success;

            _logService.Debug("WSUS firewall rules check: HTTP={HttpExists}, HTTPS={HttpsExists}",
                httpResult.Success, httpsResult.Success);

            return OperationResult<bool>.Ok(bothExist,
                bothExist ? "Both WSUS firewall rules found." : "One or more WSUS firewall rules are missing.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Error checking WSUS firewall rules");
            return OperationResult<bool>.Fail($"Error checking firewall rules: {ex.Message}", ex);
        }
    }

    /// <inheritdoc/>
    public async Task<OperationResult> CreateWsusRulesAsync(
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        try
        {
            _logService.Info("Creating WSUS firewall rules");

            // Create HTTP rule (port 8530)
            progress?.Report($"Creating firewall rule '{HttpRuleName}' (port {HttpPort})...");
            var httpResult = await _processRunner.RunAsync(
                NetshExe,
                $"advfirewall firewall add rule name=\"{HttpRuleName}\" " +
                $"dir=in action=allow protocol=TCP localport={HttpPort}",
                ct: ct).ConfigureAwait(false);

            if (!httpResult.Success)
            {
                var msg = $"Failed to create HTTP firewall rule: {httpResult.Output}";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            progress?.Report($"[OK] Firewall rule '{HttpRuleName}' created (port {HttpPort}).");

            // Create HTTPS rule (port 8531)
            progress?.Report($"Creating firewall rule '{HttpsRuleName}' (port {HttpsPort})...");
            var httpsResult = await _processRunner.RunAsync(
                NetshExe,
                $"advfirewall firewall add rule name=\"{HttpsRuleName}\" " +
                $"dir=in action=allow protocol=TCP localport={HttpsPort}",
                ct: ct).ConfigureAwait(false);

            if (!httpsResult.Success)
            {
                var msg = $"Failed to create HTTPS firewall rule: {httpsResult.Output}";
                _logService.Warning(msg);
                progress?.Report($"[FAIL] {msg}");
                return OperationResult.Fail(msg);
            }

            progress?.Report($"[OK] Firewall rule '{HttpsRuleName}' created (port {HttpsPort}).");

            _logService.Info("WSUS firewall rules created successfully");
            return OperationResult.Ok("WSUS firewall rules created successfully.");
        }
        catch (Exception ex)
        {
            _logService.Error(ex, "Error creating WSUS firewall rules");
            return OperationResult.Fail($"Error creating firewall rules: {ex.Message}", ex);
        }
    }
}
