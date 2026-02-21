# Performance Baselines

This directory contains baseline performance measurements for WSUS Manager.

## How to Capture Baselines

Run the benchmarks on a Windows machine or in CI:

```bash
# Build the app in Release mode
dotnet build src/WsusManager.App/WsusManager.App.csproj --configuration Release

# Run benchmarks (respond with "*" to select all)
cd src/WsusManager.Benchmarks
dotnet run -c Release
```

## Baseline Files

Place captured baseline files here:

- `startup-baseline.html` - Visual HTML report from BenchmarkDotNet
- `startup-baseline.csv` - Raw measurement data for programmatic comparison

## Baseline Data Format

When benchmarks run successfully, capture:

| Metric | ColdStartup | WarmStartup |
|--------|-------------|-------------|
| Mean (ms) | TBD | TBD |
| StdDev (ms) | TBD | TBD |
| Min (ms) | TBD | TBD |
| Max (ms) | TBD | TBD |
| Allocated MB | TBD | TBD |

## Benchmark Configuration

- **BenchmarkDotNet Version:** 0.14.0
- **Target Framework:** .NET 8.0
- **Warmup Count:** 3 iterations
- **Iteration Count:** 10 iterations
- **Job:** SimpleJob with RuntimeMoniker.Net80

## Hardware Info for Baseline

Capture this information when recording baselines:

- **CPU:** [To be filled]
- **.NET SDK:** [To be filled]
- **OS:** Windows 10/11 or Server
- **Runtime:** .NET 8.0.x

## Notes

- Baselines should be captured on a quiet system (no heavy background tasks)
- Run multiple times and verify consistency before committing
- Update this README when baselines change
- Significant regressions (>10%) should be investigated before release
