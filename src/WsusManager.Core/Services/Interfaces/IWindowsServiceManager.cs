using WsusManager.Core.Models;

namespace WsusManager.Core.Services.Interfaces;

/// <summary>
/// Manages Windows service lifecycle for WSUS-related services.
/// Handles dependency ordering (SQL first, then IIS, then WSUS for start; reverse for stop).
/// All methods return OperationResult — they do not throw for expected service failures.
/// </summary>
public interface IWindowsServiceManager
{
    /// <summary>
    /// Gets the current status of a single service by name.
    /// Returns a result with IsRunning=false if the service is not installed.
    /// </summary>
    Task<ServiceStatusInfo> GetStatusAsync(string serviceName, CancellationToken ct = default);

    /// <summary>
    /// Gets the status of all three monitored WSUS services simultaneously.
    /// Order: SQL Express, IIS (W3SVC), WSUS.
    /// </summary>
    Task<ServiceStatusInfo[]> GetAllStatusAsync(CancellationToken ct = default);

    /// <summary>
    /// Starts a single service by name. Retries up to 3 times with 5-second delays on failure.
    /// </summary>
    Task<OperationResult> StartServiceAsync(string serviceName, CancellationToken ct = default);

    /// <summary>
    /// Stops a single service by name.
    /// </summary>
    Task<OperationResult> StopServiceAsync(string serviceName, CancellationToken ct = default);

    /// <summary>
    /// Starts all three WSUS services in dependency order:
    /// 1. MSSQL$SQLEXPRESS (SQL Server Express)
    /// 2. W3SVC (IIS)
    /// 3. WsusService (WSUS)
    /// Progress messages are reported for each service action.
    /// </summary>
    Task<OperationResult> StartAllServicesAsync(IProgress<string>? progress = null, CancellationToken ct = default);

    /// <summary>
    /// Stops all three WSUS services in reverse dependency order:
    /// 1. WsusService (WSUS)
    /// 2. W3SVC (IIS)
    /// 3. MSSQL$SQLEXPRESS (SQL Server Express)
    /// Progress messages are reported for each service action.
    /// </summary>
    Task<OperationResult> StopAllServicesAsync(IProgress<string>? progress = null, CancellationToken ct = default);
}
