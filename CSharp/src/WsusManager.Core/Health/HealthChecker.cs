using WsusManager.Core.Services;
using WsusManager.Core.Database;

namespace WsusManager.Core.Health;

/// <summary>
/// Provides comprehensive WSUS health checking and repair functionality.
/// Replaces PowerShell WsusHealth.psm1 functions.
/// </summary>
public class HealthChecker
{
    private readonly DatabaseOperations _database;
    private readonly string _sqlInstance;

    public HealthChecker(string sqlInstance = @".\SQLEXPRESS")
    {
        _database = new DatabaseOperations(sqlInstance);
        _sqlInstance = sqlInstance;
    }

    /// <summary>
    /// Performs a comprehensive WSUS health check.
    /// </summary>
    /// <param name="includeDatabase">Include database health checks</param>
    /// <returns>Health check results</returns>
    public async Task<HealthCheckResult> PerformHealthCheckAsync(bool includeDatabase = true)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("\n========================================");
        Console.WriteLine("WSUS Health Check");
        Console.WriteLine("========================================");
        Console.ResetColor();

        var health = new HealthCheckResult
        {
            Overall = HealthStatus.Healthy,
            Services = new Dictionary<string, ServiceStatus>(),
            Database = new DatabaseHealthStatus(),
            Issues = new List<string>()
        };

        // 1. Check Services
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.WriteLine("\n[1/2] Checking Services...");
        Console.ResetColor();

        var serviceStatus = ServiceManager.GetWsusServiceStatus();
        health.Services = serviceStatus;

        foreach (var (serviceName, status) in serviceStatus)
        {
            if (!status.Running)
            {
                health.Issues.Add($"Service '{serviceName}' is not running (Status: {status.Status})");
                health.Overall = HealthStatus.Unhealthy;
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"  [FAIL] {serviceName} - {status.Status}");
                Console.ResetColor();
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"  [OK] {serviceName} - Running");
                Console.ResetColor();
            }
        }

        // 2. Check Database
        if (includeDatabase)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("\n[2/2] Checking Database...");
            Console.ResetColor();

            try
            {
                var connected = await _database.TestConnectionAsync();
                health.Database.Connected = connected;

                if (connected)
                {
                    health.Database.SizeGB = await _database.GetDatabaseSizeGBAsync();
                    health.Database.Message = "Successfully connected to SUSDB";
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine($"  [OK] Connected - Database Size: {health.Database.SizeGB:F2} GB");
                    Console.ResetColor();
                }
                else
                {
                    health.Database.Message = "Failed to connect to database";
                    health.Issues.Add("Database connection failed");
                    health.Overall = HealthStatus.Unhealthy;
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("  [FAIL] Database connection failed");
                    Console.ResetColor();
                }
            }
            catch (Exception ex)
            {
                health.Database.Message = $"Error checking database: {ex.Message}";
                health.Issues.Add($"Database error: {ex.Message}");
                health.Overall = HealthStatus.Unhealthy;
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"  [FAIL] {ex.Message}");
                Console.ResetColor();
            }
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Gray;
            Console.WriteLine("\n[2/2] Skipping Database Check...");
            Console.ResetColor();
        }

        // Summary
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("\n========================================");
        Console.WriteLine("Health Check Summary");
        Console.WriteLine("========================================");
        Console.ResetColor();

        var statusColor = health.Overall switch
        {
            HealthStatus.Healthy => ConsoleColor.Green,
            HealthStatus.Degraded => ConsoleColor.Yellow,
            HealthStatus.Unhealthy => ConsoleColor.Red,
            _ => ConsoleColor.White
        };

        Console.ForegroundColor = statusColor;
        Console.WriteLine($"Overall Status: {health.Overall.ToString().ToUpper()}");
        Console.ResetColor();

        if (health.Issues.Count > 0)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine("\nIssues Found:");
            foreach (var issue in health.Issues)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"  - {issue}");
            }
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("All systems operational");
            Console.ResetColor();
        }

        Console.WriteLine();

        return health;
    }

    /// <summary>
    /// Attempts to repair common WSUS health issues automatically.
    /// </summary>
    public HealthRepairResult RepairHealth()
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("\n========================================");
        Console.WriteLine("WSUS Health Repair");
        Console.WriteLine("========================================");
        Console.ResetColor();

        var results = new HealthRepairResult
        {
            ServicesStarted = new List<string>(),
            Success = true
        };

        // Start stopped services
        Console.WriteLine("\n[1/1] Starting Services...");
        var serviceStatus = ServiceManager.GetWsusServiceStatus();

        foreach (var (serviceName, status) in serviceStatus)
        {
            if (!status.Running)
            {
                Console.WriteLine($"  Starting {serviceName}...");

                bool started = serviceName switch
                {
                    "SQL Server Express" => WsusServices.StartSqlServerExpress(),
                    "WSUS Service" => WsusServices.StartWsusServer(),
                    "IIS" => WsusServices.StartIIS(),
                    _ => false
                };

                if (started)
                {
                    results.ServicesStarted.Add(serviceName);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine($"  [OK] {serviceName} started");
                    Console.ResetColor();
                }
                else
                {
                    results.Success = false;
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine($"  [FAIL] Failed to start {serviceName}");
                    Console.ResetColor();
                }
            }
        }

        // Summary
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("\n========================================");
        Console.WriteLine("Repair Summary");
        Console.WriteLine("========================================");
        Console.ResetColor();

        Console.WriteLine($"Services Started: {results.ServicesStarted.Count}");

        if (results.Success)
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine("\nRepair completed successfully");
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("\nRepair completed with errors");
            Console.ResetColor();
        }

        Console.WriteLine();

        return results;
    }
}

/// <summary>
/// Overall health status.
/// </summary>
public enum HealthStatus
{
    Healthy,
    Degraded,
    Unhealthy
}

/// <summary>
/// Health check result model.
/// </summary>
public class HealthCheckResult
{
    public HealthStatus Overall { get; set; } = HealthStatus.Healthy;
    public Dictionary<string, ServiceStatus> Services { get; set; } = new();
    public DatabaseHealthStatus Database { get; set; } = new();
    public List<string> Issues { get; set; } = new();

    public bool IsHealthy => Overall == HealthStatus.Healthy;
    public bool IsDegraded => Overall == HealthStatus.Degraded;
    public bool IsUnhealthy => Overall == HealthStatus.Unhealthy;
}

/// <summary>
/// Database health status.
/// </summary>
public class DatabaseHealthStatus
{
    public bool Connected { get; set; }
    public decimal SizeGB { get; set; }
    public string Message { get; set; } = string.Empty;
}

/// <summary>
/// Health repair result model.
/// </summary>
public class HealthRepairResult
{
    public List<string> ServicesStarted { get; set; } = new();
    public bool Success { get; set; }
}
