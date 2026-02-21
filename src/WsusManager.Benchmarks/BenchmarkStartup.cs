using System.Diagnostics;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Diagnosers;
using BenchmarkDotNet.Environments;
using BenchmarkDotNet.Jobs;

namespace WsusManager.Benchmarks;

/// <summary>
/// Startup performance benchmarks for WSUS Manager application.
/// Measures cold startup (first launch) and warm startup (subsequent launches).
/// Note: These benchmarks require a built application and may not work in all CI environments.
/// </summary>
[MemoryDiagnoser]
[SimpleJob(warmupCount: 3, iterationCount: 10, runtimeMoniker: RuntimeMoniker.Net80)]
[HtmlExporter]
[CsvMeasurementsExporter]
[RPlotExporter]
[KeepBenchmarkFiles]
public class BenchmarkStartup
{
    private const string AppProjectPath = "src/WsusManager.App/WsusManager.App.csproj";
    private string _exePath = string.Empty;

    [GlobalSetup]
    public void Setup()
    {
        // Build the app once before benchmarking
        var buildInfo = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"build \"{AppProjectPath}\" --configuration Release --no-restore",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using var build = Process.Start(buildInfo);
        build?.WaitForExit();

        if (build?.ExitCode != 0)
        {
            var error = build?.StandardError.ReadToEnd() ?? string.Empty;
            throw new InvalidOperationException($"Failed to build app: {error}");
        }

        // Determine the executable path
        var possiblePaths = new[]
        {
            "src/WsusManager.App/bin/Release/net8.0-windows/win-x64/publish/WsusManager.App.exe",
            "src/WsusManager.App/bin/Release/net8.0-windows/WsusManager.App.dll"
        };

        foreach (var path in possiblePaths)
        {
            if (File.Exists(path))
            {
                _exePath = Path.GetFullPath(path);
                break;
            }
        }

        if (string.IsNullOrEmpty(_exePath))
        {
            // Fallback to using dotnet run with the DLL
            _exePath = "src/WsusManager.App/bin/Release/net8.0-windows/WsusManager.App.dll";
        }
    }

    /// <summary>
    /// Cold startup benchmark - measures time to launch the application from a stopped state.
    /// This is the first launch after system boot or after a long idle period.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("Startup", "Cold")]
    public void ColdStartup()
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"\"{_exePath}\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using var proc = Process.Start(startInfo);

        // Wait for initialization - kill after 3 seconds max
        // (we just want to measure startup, not run the app)
        bool exited = proc?.WaitForExit(3000) ?? false;

        if (!exited && proc != null && !proc.HasExited)
        {
            proc.Kill();
        }
    }

    /// <summary>
    /// Warm startup benchmark - measures time to launch the application when .NET runtime
    /// is already loaded in memory (simulates subsequent launches).
    /// BenchmarkDotNet will run this multiple times automatically.
    /// </summary>
    [Benchmark]
    [BenchmarkCategory("Startup", "Warm")]
    public void WarmStartup()
    {
        // Same as cold startup - BenchmarkDotNet handles the repetition
        // The difference is that .NET runtime assemblies are cached
        ColdStartup();
    }
}
