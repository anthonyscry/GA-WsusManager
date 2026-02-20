using System.ServiceProcess;

namespace WsusManager.Core.Models;

/// <summary>
/// Status snapshot of a Windows service at a point in time.
/// </summary>
public record ServiceStatusInfo(
    string ServiceName,
    string DisplayName,
    ServiceControllerStatus Status,
    bool IsRunning);
