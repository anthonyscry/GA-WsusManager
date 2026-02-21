using System.Reflection;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Connects to the local WSUS server via the Microsoft.UpdateServices.Administration
/// managed API loaded at runtime. All WSUS API calls are blocking, so they are wrapped
/// in Task.Run to keep the UI responsive.
/// </summary>
public class WsusServerService : IWsusServerService
{
    private readonly ILogService _logService;
    private object? _updateServer;
    private Assembly? _wsusAssembly;

    /// <summary>
    /// Well-known path where the WSUS API DLL is installed with the WSUS role.
    /// </summary>
    private const string WsusApiDllPath =
        @"C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll";

    /// <summary>
    /// Approved classifications for auto-approval (matching PowerShell exactly).
    /// </summary>
    private static readonly string[] ApprovedClassifications =
    [
        "Critical Updates",
        "Security Updates",
        "Update Rollups",
        "Service Packs",
        "Updates",
        "Definition Updates"
    ];

    /// <summary>
    /// Classification excluded from auto-approval.
    /// </summary>
    private const string ExcludedClassification = "Upgrades";

    private const int SyncPollIntervalMs = 5000;
    private const int SyncMaxIterations = 720; // 60 minutes at 5-second intervals

    public WsusServerService(ILogService logService)
    {
        _logService = logService;
    }

    public bool IsConnected => _updateServer is not null;

    public async Task<OperationResult> ConnectAsync(CancellationToken ct = default)
    {
        return await Task.Run(() =>
        {
            try
            {
                if (!File.Exists(WsusApiDllPath))
                {
                    _logService.Warning("WSUS API not found at {Path}", WsusApiDllPath);
                    return OperationResult.Fail(
                        $"WSUS API not found at {WsusApiDllPath}. Is the WSUS role installed?");
                }

                _wsusAssembly = Assembly.LoadFrom(WsusApiDllPath);

                // Get AdminProxy type and call GetUpdateServer("localhost", false, 8530)
                var adminProxyType = _wsusAssembly.GetType(
                    "Microsoft.UpdateServices.Administration.AdminProxy");

                if (adminProxyType is null)
                    return OperationResult.Fail("Could not load AdminProxy type from WSUS API assembly.");

                var getServerMethod = adminProxyType.GetMethod("GetUpdateServer",
                    [typeof(string), typeof(bool), typeof(int)]);

                if (getServerMethod is null)
                    return OperationResult.Fail("Could not find GetUpdateServer method.");

                _updateServer = getServerMethod.Invoke(null, ["localhost", false, 8530]);

                if (_updateServer is null)
                    return OperationResult.Fail("GetUpdateServer returned null.");

                _logService.Info("Connected to WSUS server on localhost:8530");
                return OperationResult.Ok("Connected to WSUS server.");
            }
            catch (Exception ex)
            {
                var inner = ex.InnerException ?? ex;
                _logService.Error(inner, "Failed to connect to WSUS server");
                return OperationResult.Fail($"Failed to connect to WSUS: {inner.Message}", inner);
            }
        }, ct).ConfigureAwait(false);
    }

    public async Task<OperationResult> StartSynchronizationAsync(
        IProgress<string>? progress, CancellationToken ct)
    {
        if (_updateServer is null)
            return OperationResult.Fail("Not connected to WSUS server.");

        return await Task.Run(async () =>
        {
            try
            {
                // Get subscription object
                var getSubMethod = _updateServer.GetType().GetMethod("GetSubscription");
                var subscription = getSubMethod?.Invoke(_updateServer, null);

                if (subscription is null)
                    return OperationResult.Fail("Could not get WSUS subscription.");

                // Start synchronization
                var startSyncMethod = subscription.GetType().GetMethod("StartSynchronization");
                startSyncMethod?.Invoke(subscription, null);
                progress?.Report("Synchronization started...");

                // Poll for completion
                var getSyncStatusMethod = subscription.GetType().GetMethod("GetSynchronizationStatus");
                var getSyncProgressMethod = subscription.GetType().GetMethod("GetSynchronizationProgress");
                string lastPhase = "";

                for (int i = 0; i < SyncMaxIterations; i++)
                {
                    ct.ThrowIfCancellationRequested();

                    var status = getSyncStatusMethod?.Invoke(subscription, null);
                    var statusStr = status?.ToString() ?? "Unknown";

                    if (statusStr == "NotProcessing")
                    {
                        progress?.Report("Synchronization completed.");
                        return OperationResult.Ok("Synchronization completed.");
                    }

                    // Try to get progress info
                    try
                    {
                        var syncProgress = getSyncProgressMethod?.Invoke(subscription, null);
                        if (syncProgress is not null)
                        {
                            var phaseProperty = syncProgress.GetType().GetProperty("Phase");
                            var processedProperty = syncProgress.GetType().GetProperty("ProcessedItems");
                            var totalProperty = syncProgress.GetType().GetProperty("TotalItems");

                            var phase = phaseProperty?.GetValue(syncProgress)?.ToString() ?? "Unknown";
                            // BUG-05 fix: WSUS API may return ProcessedItems/TotalItems as boxed long or uint.
                            // Direct (int) cast on a boxed non-int throws InvalidCastException.
                            // Convert.ToInt32 handles all numeric types without throwing.
                            var processed = Convert.ToInt32(processedProperty?.GetValue(syncProgress) ?? 0);
                            var total = Convert.ToInt32(totalProperty?.GetValue(syncProgress) ?? 0);

                            var pct = total > 0 ? (processed * 100.0 / total) : 0;

                            // Report on phase change, 10% progress jumps, or near completion
                            if (phase != lastPhase || pct >= 95)
                            {
                                progress?.Report($"Syncing: {phase} ({pct:F1}%)");
                                lastPhase = phase;
                            }
                        }
                    }
                    catch
                    {
                        // Progress reporting is best-effort
                    }

                    await Task.Delay(SyncPollIntervalMs, ct).ConfigureAwait(false);
                }

                return OperationResult.Fail("Synchronization timed out after 60 minutes.");
            }
            catch (OperationCanceledException)
            {
                // Try to stop sync
                try
                {
                    var getSubMethod = _updateServer.GetType().GetMethod("GetSubscription");
                    var subscription = getSubMethod?.Invoke(_updateServer, null);
                    var stopMethod = subscription?.GetType().GetMethod("StopSynchronization");
                    stopMethod?.Invoke(subscription, null);
                }
                catch { /* best-effort cancellation */ }

                throw;
            }
            catch (Exception ex)
            {
                var inner = ex.InnerException ?? ex;
                _logService.Error(inner, "Synchronization failed");
                return OperationResult.Fail($"Synchronization failed: {inner.Message}", inner);
            }
        }, ct).ConfigureAwait(false);
    }

    public async Task<OperationResult<SyncResult>> GetLastSyncInfoAsync(CancellationToken ct = default)
    {
        if (_updateServer is null)
            return OperationResult<SyncResult>.Fail("Not connected to WSUS server.");

        return await Task.Run(() =>
        {
            try
            {
                var getSubMethod = _updateServer.GetType().GetMethod("GetSubscription");
                var subscription = getSubMethod?.Invoke(_updateServer, null);

                if (subscription is null)
                    return OperationResult<SyncResult>.Fail("Could not get WSUS subscription.");

                var getLastResultMethod = subscription.GetType()
                    .GetMethod("GetLastSynchronizationInfo");
                var syncInfo = getLastResultMethod?.Invoke(subscription, null);

                if (syncInfo is null)
                    return OperationResult<SyncResult>.Ok(
                        new SyncResult("Unknown", 0, 0, null),
                        "No previous sync info available.");

                var resultProp = syncInfo.GetType().GetProperty("Result");
                var startTimeProp = syncInfo.GetType().GetProperty("StartTime");

                var result = resultProp?.GetValue(syncInfo)?.ToString() ?? "Unknown";
                var startTime = startTimeProp?.GetValue(syncInfo) as DateTime?;

                return OperationResult<SyncResult>.Ok(
                    new SyncResult(result, 0, 0, startTime),
                    $"Last sync: {result}");
            }
            catch (Exception ex)
            {
                var inner = ex.InnerException ?? ex;
                _logService.Error(inner, "Failed to get last sync info");
                return OperationResult<SyncResult>.Fail($"Failed to get sync info: {inner.Message}", inner);
            }
        }, ct).ConfigureAwait(false);
    }

    public async Task<OperationResult<int>> DeclineUpdatesAsync(
        IProgress<string>? progress, CancellationToken ct)
    {
        if (_updateServer is null)
            return OperationResult<int>.Fail("Not connected to WSUS server.");

        return await Task.Run(() =>
        {
            try
            {
                var getUpdatesMethod = _updateServer.GetType().GetMethod("GetUpdates");
                if (getUpdatesMethod is null)
                    return OperationResult<int>.Fail("Could not find GetUpdates method.");

                // Get all updates
                var updates = getUpdatesMethod.Invoke(_updateServer, null);
                if (updates is null)
                    return OperationResult<int>.Ok(0, "No updates found.");

                var updateList = updates as System.Collections.IEnumerable;
                if (updateList is null)
                    return OperationResult<int>.Ok(0, "No updates to process.");

                int declined = 0;

                foreach (var update in updateList)
                {
                    ct.ThrowIfCancellationRequested();

                    var isDeclinedProp = update.GetType().GetProperty("IsDeclined");
                    if ((bool)(isDeclinedProp?.GetValue(update) ?? false))
                        continue;

                    bool shouldDecline = false;
                    string reason = "";

                    // Check if expired
                    var publicationStateProp = update.GetType().GetProperty("PublicationState");
                    var pubState = publicationStateProp?.GetValue(update)?.ToString() ?? "";
                    if (pubState == "Expired")
                    {
                        shouldDecline = true;
                        reason = "expired";
                    }

                    // Check if superseded
                    // BUG-03 fix: do NOT decline by age (>6 months) — that removes valid patches.
                    // Decline only expired or superseded updates (matching PowerShell implementation).
                    if (!shouldDecline)
                    {
                        var isSupersededProp = update.GetType().GetProperty("IsSuperseded");
                        if ((bool)(isSupersededProp?.GetValue(update) ?? false))
                        {
                            shouldDecline = true;
                            reason = "superseded";
                        }
                    }

                    if (shouldDecline)
                    {
                        try
                        {
                            var declineMethod = update.GetType().GetMethod("Decline");
                            declineMethod?.Invoke(update, null);
                            declined++;

                            if (declined % 50 == 0)
                                progress?.Report($"Declined {declined} updates so far...");
                        }
                        catch (Exception ex)
                        {
                            _logService.Debug("Could not decline update ({Reason}): {Error}", reason, ex.Message);
                        }
                    }
                }

                progress?.Report($"Declined {declined} updates total.");
                _logService.Info("Declined {Count} updates", declined);
                return OperationResult<int>.Ok(declined, $"Declined {declined} updates.");
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                var inner = ex.InnerException ?? ex;
                _logService.Error(inner, "Failed to decline updates");
                return OperationResult<int>.Fail($"Failed to decline updates: {inner.Message}", inner);
            }
        }, ct);
    }

    public async Task<OperationResult<int>> ApproveUpdatesAsync(
        int maxCount, IProgress<string>? progress, CancellationToken ct)
    {
        if (_updateServer is null)
            return OperationResult<int>.Fail("Not connected to WSUS server.");

        return await Task.Run(() =>
        {
            try
            {
                var getUpdatesMethod = _updateServer.GetType().GetMethod("GetUpdates");
                if (getUpdatesMethod is null)
                    return OperationResult<int>.Fail("Could not find GetUpdates method.");

                var updates = getUpdatesMethod.Invoke(_updateServer, null);
                var updateList = updates as System.Collections.IEnumerable;
                if (updateList is null)
                    return OperationResult<int>.Ok(0, "No updates to process.");

                // Get "All Computers" target group
                var getGroupsMethod = _updateServer.GetType().GetMethod("GetComputerTargetGroups");
                var groups = getGroupsMethod?.Invoke(_updateServer, null) as System.Collections.IEnumerable;
                object? allComputersGroup = null;

                if (groups is not null)
                {
                    foreach (var group in groups)
                    {
                        var nameProp = group.GetType().GetProperty("Name");
                        if (nameProp?.GetValue(group)?.ToString() == "All Computers")
                        {
                            allComputersGroup = group;
                            break;
                        }
                    }
                }

                if (allComputersGroup is null)
                    return OperationResult<int>.Fail("Could not find 'All Computers' target group.");

                // Count eligible updates first
                var eligible = new List<object>();
                foreach (var update in updateList)
                {
                    ct.ThrowIfCancellationRequested();

                    // Skip declined updates
                    var isDeclinedProp = update.GetType().GetProperty("IsDeclined");
                    if ((bool)(isDeclinedProp?.GetValue(update) ?? false))
                        continue;

                    // Check title for Preview/Beta exclusion
                    var titleProp = update.GetType().GetProperty("Title");
                    var title = titleProp?.GetValue(update)?.ToString() ?? "";
                    if (title.Contains("Preview", StringComparison.OrdinalIgnoreCase) ||
                        title.Contains("Beta", StringComparison.OrdinalIgnoreCase))
                        continue;

                    // Check classification
                    // BUG-04 fix: IUpdate has no flat UpdateClassificationTitle property.
                    // Must use two-level reflection: UpdateClassification -> Title
                    var classificationObj = update.GetType()
                        .GetProperty("UpdateClassification")
                        ?.GetValue(update);
                    var classification = classificationObj?.GetType()
                        .GetProperty("Title")
                        ?.GetValue(classificationObj)
                        ?.ToString() ?? "";

                    // Exclude Upgrades
                    if (string.Equals(classification, ExcludedClassification, StringComparison.OrdinalIgnoreCase))
                        continue;

                    // Must be in an approved classification
                    bool isApprovedClassification = ApprovedClassifications.Any(
                        ac => string.Equals(ac, classification, StringComparison.OrdinalIgnoreCase));
                    if (!isApprovedClassification)
                        continue;

                    eligible.Add(update);
                }

                progress?.Report($"Found {eligible.Count} updates eligible for approval.");

                // Safety threshold
                if (eligible.Count > maxCount)
                {
                    var msg = $"Safety threshold exceeded: {eligible.Count} updates eligible but max is {maxCount}. Skipping approval.";
                    progress?.Report($"[WARNING] {msg}");
                    _logService.Warning(msg);
                    return OperationResult<int>.Ok(0, msg);
                }

                // Approve eligible updates
                int approved = 0;
                // Get the Install approval action enum value
                var installActionType = _wsusAssembly?.GetType(
                    "Microsoft.UpdateServices.Administration.UpdateApprovalAction");
                var installAction = installActionType is not null
                    ? Enum.Parse(installActionType, "Install")
                    : null;

                foreach (var update in eligible)
                {
                    ct.ThrowIfCancellationRequested();

                    try
                    {
                        var approveMethod = update.GetType().GetMethod("Approve",
                            [installActionType!, allComputersGroup.GetType()]);

                        if (approveMethod is not null && installAction is not null)
                        {
                            approveMethod.Invoke(update, [installAction, allComputersGroup]);
                            approved++;

                            if (approved % 25 == 0)
                                progress?.Report($"Approved {approved} of {eligible.Count} updates...");
                        }
                    }
                    catch (Exception ex)
                    {
                        _logService.Debug("Could not approve update: {Error}", ex.Message);
                    }
                }

                progress?.Report($"Approved {approved} updates.");
                _logService.Info("Approved {Count} updates", approved);
                return OperationResult<int>.Ok(approved, $"Approved {approved} updates.");
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex)
            {
                var inner = ex.InnerException ?? ex;
                _logService.Error(inner, "Failed to approve updates");
                return OperationResult<int>.Fail($"Failed to approve updates: {inner.Message}", inner);
            }
        }, ct);
    }
}
