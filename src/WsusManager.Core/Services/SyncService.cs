using System.Diagnostics;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Orchestrates Online Sync workflows by composing IWsusServerService operations
/// according to the selected sync profile.
/// </summary>
public class SyncService : ISyncService
{
    private readonly IWsusServerService _wsusServer;
    private readonly ILogService _logService;

    public SyncService(IWsusServerService wsusServer, ILogService logService)
    {
        _wsusServer = wsusServer;
        _logService = logService;
    }

    public async Task<OperationResult> RunSyncAsync(
        SyncProfile profile,
        int maxAutoApproveCount,
        IProgress<string> progress,
        CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var profileName = profile switch
        {
            SyncProfile.FullSync => "Full Sync",
            SyncProfile.QuickSync => "Quick Sync",
            SyncProfile.SyncOnly => "Sync Only",
            _ => profile.ToString()
        };

        progress.Report($"Starting {profileName}...");
        _logService.Info("Starting sync with profile: {Profile}", profileName);

        // Step 1: Connect to WSUS server
        progress.Report("[Step 1] Connecting to WSUS server...");
        var connectResult = await _wsusServer.ConnectAsync(ct).ConfigureAwait(false);
        if (!connectResult.Success)
        {
            progress.Report($"[FAIL] {connectResult.Message}");
            return connectResult;
        }
        progress.Report("[OK] Connected to WSUS server.");

        // Step 2: Get and report last sync info
        progress.Report("[Step 2] Checking last sync info...");
        var lastSyncResult = await _wsusServer.GetLastSyncInfoAsync(ct).ConfigureAwait(false);
        if (lastSyncResult.Success && lastSyncResult.Data is not null)
        {
            var info = lastSyncResult.Data;
            progress.Report($"  Last sync result: {info.Result}");
            if (info.StartTime.HasValue)
                progress.Report($"  Last sync time: {info.StartTime.Value:yyyy-MM-dd HH:mm:ss}");
        }

        // Step 3: Start synchronization
        progress.Report("[Step 3] Starting synchronization...");
        var syncResult = await _wsusServer.StartSynchronizationAsync(progress, ct).ConfigureAwait(false);
        if (!syncResult.Success)
        {
            progress.Report($"[FAIL] {syncResult.Message}");
            return syncResult;
        }
        progress.Report("[OK] Synchronization completed.");

        int declinedCount = 0;
        int approvedCount = 0;

        // Step 4: Decline expired/superseded/old updates (Full Sync only)
        if (profile == SyncProfile.FullSync)
        {
            progress.Report("[Step 4] Declining expired, superseded, and old updates...");
            var declineResult = await _wsusServer.DeclineUpdatesAsync(progress, ct).ConfigureAwait(false);
            if (declineResult.Success)
            {
                declinedCount = declineResult.Data;
                progress.Report($"[OK] Declined {declinedCount} updates.");
            }
            else
            {
                progress.Report($"[WARNING] Decline step failed: {declineResult.Message}");
            }
        }
        else
        {
            progress.Report("[Step 4] Skipped (decline not included in this profile).");
        }

        // Step 5: Auto-approve updates (Full Sync and Quick Sync)
        if (profile == SyncProfile.FullSync || profile == SyncProfile.QuickSync)
        {
            progress.Report("[Step 5] Auto-approving updates...");
            var approveResult = await _wsusServer.ApproveUpdatesAsync(maxAutoApproveCount, progress, ct).ConfigureAwait(false);
            if (approveResult.Success)
            {
                approvedCount = approveResult.Data;
                progress.Report($"[OK] Approved {approvedCount} updates.");
            }
            else
            {
                progress.Report($"[WARNING] Approval step failed: {approveResult.Message}");
            }
        }
        else
        {
            progress.Report("[Step 5] Skipped (approval not included in this profile).");
        }

        sw.Stop();

        // Summary
        progress.Report("");
        progress.Report($"--- {profileName} Summary ---");
        progress.Report($"  Duration: {sw.Elapsed.TotalMinutes:F1} minutes");
        if (profile == SyncProfile.FullSync)
            progress.Report($"  Updates declined: {declinedCount}");
        if (profile != SyncProfile.SyncOnly)
            progress.Report($"  Updates approved: {approvedCount}");
        progress.Report($"--- End Summary ---");

        _logService.Info("Sync completed: {Profile}, {Declined} declined, {Approved} approved, {Duration}s",
            profileName, declinedCount, approvedCount, sw.Elapsed.TotalSeconds);

        return OperationResult.Ok($"{profileName} completed successfully.");
    }
}
