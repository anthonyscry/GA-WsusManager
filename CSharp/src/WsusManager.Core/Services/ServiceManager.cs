using System.ServiceProcess;
using System.Diagnostics;

namespace WsusManager.Core.Services;

/// <summary>
/// Provides Windows service management for WSUS-related services.
/// Replaces PowerShell WsusServices.psm1 functions.
/// </summary>
public class ServiceManager
{
    private const int DefaultTimeoutSeconds = 60;

    /// <summary>
    /// Checks if a service is running.
    /// </summary>
    /// <param name="serviceName">Name of the service to check</param>
    /// <returns>True if service is running, false otherwise</returns>
    public static bool IsServiceRunning(string serviceName)
    {
        try
        {
            using var service = new ServiceController(serviceName);
            service.Refresh();
            return service.Status == ServiceControllerStatus.Running;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Checks if a service exists.
    /// </summary>
    /// <param name="serviceName">Name of the service to check</param>
    /// <returns>True if service exists, false otherwise</returns>
    public static bool ServiceExists(string serviceName)
    {
        try
        {
            using var service = new ServiceController(serviceName);
            _ = service.Status; // Access status to verify service exists
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Waits for a service to reach a specific state.
    /// </summary>
    /// <param name="serviceName">Service name</param>
    /// <param name="targetState">Target state to wait for</param>
    /// <param name="timeoutSeconds">Maximum seconds to wait</param>
    /// <returns>True if target state reached, false if timeout</returns>
    public static bool WaitForServiceState(
        string serviceName,
        ServiceControllerStatus targetState,
        int timeoutSeconds = DefaultTimeoutSeconds)
    {
        try
        {
            using var service = new ServiceController(serviceName);
            var timeout = TimeSpan.FromSeconds(timeoutSeconds);
            service.WaitForStatus(targetState, timeout);
            return true;
        }
        catch (System.ServiceProcess.TimeoutException)
        {
            return false;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Starts a Windows service with timeout.
    /// </summary>
    /// <param name="serviceName">Service name</param>
    /// <param name="timeoutSeconds">Maximum seconds to wait for startup</param>
    /// <returns>True if service started successfully</returns>
    public static bool StartService(string serviceName, int timeoutSeconds = DefaultTimeoutSeconds)
    {
        try
        {
            using var service = new ServiceController(serviceName);
            service.Refresh();

            if (service.Status == ServiceControllerStatus.Running)
            {
                Console.WriteLine($"  {serviceName} is already running");
                return true;
            }

            Console.WriteLine($"  Starting {serviceName}...");
            service.Start();

            var success = WaitForServiceState(serviceName, ServiceControllerStatus.Running, timeoutSeconds);
            if (success)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"  {serviceName} started successfully");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"  {serviceName} did not start within {timeoutSeconds} seconds");
                Console.ResetColor();
            }

            return success;
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"  Failed to start {serviceName}: {ex.Message}");
            Console.ResetColor();
            return false;
        }
    }

    /// <summary>
    /// Stops a Windows service with timeout.
    /// </summary>
    /// <param name="serviceName">Service name</param>
    /// <param name="force">Force stop the service</param>
    /// <param name="timeoutSeconds">Maximum seconds to wait for shutdown</param>
    /// <returns>True if service stopped successfully</returns>
    public static bool StopService(
        string serviceName,
        bool force = false,
        int timeoutSeconds = DefaultTimeoutSeconds)
    {
        try
        {
            using var service = new ServiceController(serviceName);
            service.Refresh();

            if (service.Status == ServiceControllerStatus.Stopped)
            {
                Console.WriteLine($"  {serviceName} is already stopped");
                return true;
            }

            Console.WriteLine($"  Stopping {serviceName}...");

            if (service.CanStop)
            {
                service.Stop();
            }
            else if (force)
            {
                // Force kill the service process
                KillServiceProcess(serviceName);
            }
            else
            {
                Console.WriteLine($"  {serviceName} cannot be stopped");
                return false;
            }

            var success = WaitForServiceState(serviceName, ServiceControllerStatus.Stopped, timeoutSeconds);
            if (success)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"  {serviceName} stopped successfully");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"  {serviceName} did not stop within {timeoutSeconds} seconds");
                Console.ResetColor();
            }

            return success;
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"  Failed to stop {serviceName}: {ex.Message}");
            Console.ResetColor();
            return false;
        }
    }

    /// <summary>
    /// Restarts a Windows service.
    /// </summary>
    /// <param name="serviceName">Service name</param>
    /// <param name="force">Force stop before restart</param>
    /// <returns>True if service restarted successfully</returns>
    public static bool RestartService(string serviceName, bool force = false)
    {
        Console.WriteLine($"Restarting {serviceName}...");

        if (!StopService(serviceName, force))
            return false;

        // Wait a moment before starting
        Thread.Sleep(1000);

        return StartService(serviceName);
    }

    /// <summary>
    /// Force kills a service process (dangerous - use only as last resort).
    /// </summary>
    private static void KillServiceProcess(string serviceName)
    {
        try
        {
            using var service = new ServiceController(serviceName);
            var processes = Process.GetProcessesByName(service.ServiceName);
            foreach (var process in processes)
            {
                process.Kill();
                process.WaitForExit(5000);
            }
        }
        catch
        {
            // Best effort
        }
    }

    /// <summary>
    /// Gets the status of all WSUS-related services.
    /// </summary>
    /// <returns>Dictionary of service names and their status</returns>
    public static Dictionary<string, ServiceStatus> GetWsusServiceStatus()
    {
        var services = new Dictionary<string, string>
        {
            ["SQL Server Express"] = "MSSQL$SQLEXPRESS",
            ["WSUS Service"] = "WSUSService",
            ["IIS"] = "W3SVC"
        };

        var status = new Dictionary<string, ServiceStatus>();

        foreach (var (displayName, serviceName) in services)
        {
            try
            {
                using var service = new ServiceController(serviceName);
                service.Refresh();

                status[displayName] = new ServiceStatus
                {
                    Status = service.Status.ToString(),
                    StartType = service.StartType.ToString(),
                    Running = service.Status == ServiceControllerStatus.Running
                };
            }
            catch
            {
                status[displayName] = new ServiceStatus
                {
                    Status = "Not Found",
                    StartType = "N/A",
                    Running = false
                };
            }
        }

        return status;
    }
}

/// <summary>
/// Service status model.
/// </summary>
public class ServiceStatus
{
    public string Status { get; set; } = string.Empty;
    public string StartType { get; set; } = string.Empty;
    public bool Running { get; set; }
}

/// <summary>
/// Convenience methods for specific WSUS services.
/// </summary>
public static class WsusServices
{
    public static bool StartSqlServerExpress(string instanceName = "SQLEXPRESS")
    {
        var serviceName = instanceName == "MSSQLSERVER" ? "MSSQLSERVER" : $"MSSQL${instanceName}";
        return ServiceManager.StartService(serviceName, timeoutSeconds: 10);
    }

    public static bool StopSqlServerExpress(string instanceName = "SQLEXPRESS", bool force = false)
    {
        var serviceName = instanceName == "MSSQLSERVER" ? "MSSQLSERVER" : $"MSSQL${instanceName}";
        return ServiceManager.StopService(serviceName, force);
    }

    public static bool StartWsusServer()
    {
        return ServiceManager.StartService("WSUSService", timeoutSeconds: 10);
    }

    public static bool StopWsusServer(bool force = false)
    {
        return ServiceManager.StopService("WSUSService", force, timeoutSeconds: 5);
    }

    public static bool StartIIS()
    {
        return ServiceManager.StartService("W3SVC", timeoutSeconds: 5);
    }

    public static bool StopIIS(bool force = false)
    {
        return ServiceManager.StopService("W3SVC", force);
    }

    /// <summary>
    /// Starts all WSUS-related services in the correct order.
    /// </summary>
    public static Dictionary<string, bool> StartAllWsusServices()
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("Starting all WSUS services...");
        Console.ResetColor();

        var results = new Dictionary<string, bool>
        {
            ["SqlServer"] = StartSqlServerExpress(),
            ["IIS"] = StartIIS(),
            ["WSUS"] = StartWsusServer()
        };

        if (results.Values.All(r => r))
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("All WSUS services started successfully");
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("Some services failed to start");
            Console.ResetColor();
        }

        return results;
    }

    /// <summary>
    /// Stops all WSUS-related services in reverse order.
    /// </summary>
    public static Dictionary<string, bool> StopAllWsusServices(bool force = false)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("Stopping all WSUS services...");
        Console.ResetColor();

        // Stop in reverse order
        var results = new Dictionary<string, bool>
        {
            ["WSUS"] = StopWsusServer(force),
            ["IIS"] = StopIIS(force),
            ["SqlServer"] = StopSqlServerExpress(force: force)
        };

        if (results.Values.All(r => r))
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("All WSUS services stopped successfully");
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("Some services failed to stop");
            Console.ResetColor();
        }

        return results;
    }
}
