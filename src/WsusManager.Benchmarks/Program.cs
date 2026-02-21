using BenchmarkDotNet.Running;

namespace WsusManager.Benchmarks;

/// <summary>
/// Benchmark entry point - run all benchmarks in this assembly.
/// </summary>
public class Program
{
    public static void Main(string[] args)
    {
        BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
    }
}
