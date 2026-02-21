using System.ServiceProcess;
using WsusManager.Core.Logging;
using WsusManager.Core.Models;
using WsusManager.Core.Services.Interfaces;

namespace WsusManager.Core.Services;

/// <summary>
/// Manages Windows services for WSUS using System.ServiceProcess.ServiceController.
/// Service dependency order for start: SQL(1) -> IIS(2) -> WSUS(3).
/// Service dependency order for stop: WSUS(1) -> IIS(2) -> SQL(3).
/// Retry logic: 3 attempts with 5-second delays for service start failures.
/// </summary>
public class WindowsServiceManager : IWindowsServiceManager
{
    private readonly ILogService _logService;

    // Service definitions in start-order: SQL -> IIS -> WSUS
    private static readonly (string ServiceName, string DisplayName)[] ServiceDefinitions =
    [
        ("MSSQL$SQLEXPRESS", "SQL Server Express"),
        ("W3SVC", "IIS"),
        ("WsusService", "WSUS")
    ];

    private const int MaxRetryAttempts = 3;
    private const int RetryDelaySeconds = 5;
    private static readonly TimeSpan ServiceTimeout = TimeSpan.FromSeconds(30);

    public WindowsServiceManager(ILogService logService)
    {
        _logService = logService;
    }

    /// <inheritdoc/>
    public Task<ServiceStatusInfo> GetStatusAsync(string serviceName, CancellationToken ct = default)
    {
        return Task.Run(() =>
        {
            var displayName = ServiceDefinitions
                .FirstOrDefault(d => string.Equals(d.ServiceName, serviceName, StringComparison.Ordinal)).DisplayName
                ?? serviceName;

            try
            {
                using var sc = new ServiceController(serviceName);
                var status = sc.Status;
                return new ServiceStatusInfo(
                    serviceName,
                    displayName,
                    status,
                    status == ServiceControllerStatus.Running);
            }
            catch (InvalidOperationException)
            {
                // Service not installed
                return new ServiceStatusInfo(
                    serviceName,
                    displayName,
                    ServiceControllerStatus.Stopped,
                    false);
            }
        }, ct);
    }

    /// <inheritdoc/>
    public async Task<ServiceStatusInfo[]> GetAllStatusAsync(CancellationToken ct = default)
    {
        var tasks = ServiceDefinitions
            .Select(d => GetStatusAsync(d.ServiceName, ct))
            .ToArray();

        return await Task.WhenAll(tasks).ConfigureAwait(false);
    }

    /// <inheritdoc/>
    public Task<OperationResult> StartServiceAsync(string serviceName, CancellationToken ct = default)
    {
        return Task.Run(async () =>
        {
            for (int attempt = 1; attempt <= MaxRetryAttempts; attempt++)
            {
                try
                {
                    using var sc = new ServiceController(serviceName);

                    if (sc.Status == ServiceControllerStatus.Running)
                    {
                        _logService.Debug("Service {ServiceName} is already running", serviceName);
                        return OperationResult.Ok($"{serviceName} is already running.");
                    }

                    _logService.Info("Starting service {ServiceName} (attempt {Attempt}/{Max})",
                        serviceName, attempt, MaxRetryAttempts);

                    sc.Start();
                    sc.WaitForStatus(ServiceControllerStatus.Running, ServiceTimeout);

                    _logService.Info("Service {ServiceName} started successfully", serviceName);
                    return OperationResult.Ok($"{serviceName} started successfully.");
                }
                catch (Exception ex) when (attempt < MaxRetryAttempts)
                {
                    _logService.Warning("Service {ServiceName} start attempt {Attempt} failed: {Error}",
                        serviceName, attempt, ex.Message);

                    await Task.Delay(TimeSpan.FromSeconds(RetryDelaySeconds), ct).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    _logService.Error(ex, "Service {ServiceName} failed to start after {Max} attempts",
                        serviceName, MaxRetryAttempts);
                    return OperationResult.Fail(
                        $"Failed to start {serviceName} after {MaxRetryAttempts} attempts: {ex.Message}", ex);
                }
            }

            return OperationResult.Fail($"Failed to start {serviceName} after {MaxRetryAttempts} attempts.");
        }, ct);
    }

    /// <inheritdoc/>
    public Task<OperationResult> StopServiceAsync(string serviceName, CancellationToken ct = default)
    {
        return Task.Run(() =>
        {
            try
            {
                using var sc = new ServiceController(serviceName);

                if (sc.Status == ServiceControllerStatus.Stopped)
                {
                    _logService.Debug("Service {ServiceName} is already stopped", serviceName);
                    return OperationResult.Ok($"{serviceName} is already stopped.");
                }

                _logService.Info("Stopping service {ServiceName}", serviceName);
                sc.Stop();
                sc.WaitForStatus(ServiceControllerStatus.Stopped, ServiceTimeout);

                _logService.Info("Service {ServiceName} stopped successfully", serviceName);
                return OperationResult.Ok($"{serviceName} stopped successfully.");
            }
            catch (Exception ex)
            {
                _logService.Error(ex, "Service {ServiceName} failed to stop", serviceName);
                return OperationResult.Fail($"Failed to stop {serviceName}: {ex.Message}", ex);
            }
        }, ct);
    }

    /// <inheritdoc/>
    public async Task<OperationResult> StartAllServicesAsync(
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        // Start in ascending order: SQL(1) -> IIS(2) -> WSUS(3)
        foreach (var (serviceName, displayName) in ServiceDefinitions)
        {
            ct.ThrowIfCancellationRequested();

            progress?.Report($"Starting {displayName} ({serviceName})...");
            var result = await StartServiceAsync(serviceName, ct).ConfigureAwait(false);

            if (result.Success)
            {
                progress?.Report($"[OK] {displayName} running.");
            }
            else
            {
                progress?.Report($"[FAIL] {displayName}: {result.Message}");
                return OperationResult.Fail($"Failed to start {displayName}: {result.Message}");
            }
        }

        return OperationResult.Ok("All services started successfully.");
    }

    /// <inheritdoc/>
    public async Task<OperationResult> StopAllServicesAsync(
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        // Stop in reverse order: WSUS(3) -> IIS(2) -> SQL(1)
        foreach (var (serviceName, displayName) in ServiceDefinitions.Reverse())
        {
            ct.ThrowIfCancellationRequested();

            progress?.Report($"Stopping {displayName} ({serviceName})...");
            var result = await StopServiceAsync(serviceName, ct).ConfigureAwait(false);

            if (result.Success)
            {
                progress?.Report($"[OK] {displayName} stopped.");
            }
            else
            {
                progress?.Report($"[FAIL] {displayName}: {result.Message}");
                // Continue stopping other services even if one fails
            }
        }

        return OperationResult.Ok("All services stopped.");
    }
}
