using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Diagnosers;
using BenchmarkDotNet.Environments;
using BenchmarkDotNet.Jobs;
using WsusManager.Core.Services;
using WsusManager.Core.Logging;

namespace WsusManager.Benchmarks;

/// <summary>
/// Benchmarks for WinRM operations including connectivity checks and string manipulation overhead.
/// Note: Actual WinRM operations require domain-joined machines and are excluded from automated runs.
/// </summary>
[MemoryDiagnoser]
[SimpleJob(warmupCount: 5, iterationCount: 50, runtimeMoniker: RuntimeMoniker.Net80)]
[HtmlExporter]
[CsvExporter]
[RPlotExporter]
[StopOnFirstError]
public class BenchmarkWinRMOperations
{
    private ClientService _clientService = null!;
    private WinRmExecutor _winrmExecutor = null!;

    [GlobalSetup]
    public void Setup()
    {
        var logService = new LogService();
        var processRunner = new Core.Infrastructure.ProcessRunner(logService);
        _winrmExecutor = new WinRmExecutor(processRunner, logService);
        _clientService = new ClientService(_winrmExecutor, logService);
    }

    [GlobalCleanup]
    public void Cleanup()
    {
    }

    [Benchmark]
    [BenchmarkCategory("WinRM")]
    public async Task<bool> TestConnectivity()
    {
        try
        {
            var result = await _winrmExecutor.TestWinRmAsync("localhost").ConfigureAwait(false);
            return result;
        }
        catch
        {
            return false;
        }
    }

    [Benchmark]
    [BenchmarkCategory("Mock")]
    public void StringManipulation()
    {
        var hosts = Enumerable.Range(1, 10).Select(i => $"CLIENT-{i:D3}").ToArray();
        string.Join(" ", hosts.Select(h => $"Invoke-GPUpdate -Computer {h} -Force"));
    }

    [Benchmark]
    [BenchmarkCategory("Mock")]
    public string[] HostArrayCreation()
    {
        return Enumerable.Range(1, 100)
            .Select(i => $"CLIENT-{i:D3}")
            .ToArray();
    }

    [Benchmark]
    [BenchmarkCategory("Mock")]
    public bool HostnameValidation()
    {
        var hostname = "CLIENT-001";
        var regex = new System.Text.RegularExpressions.Regex(@"^[A-Za-z0-9.\-]+$");
        return regex.IsMatch(hostname);
    }

    [Benchmark]
    [BenchmarkCategory("Mock")]
    public bool HostnameValidationFqdn()
    {
        var hostname = "client001.example.com";
        var regex = new System.Text.RegularExpressions.Regex(@"^[A-Za-z0-9.\-]+$");
        return regex.IsMatch(hostname);
    }
}
