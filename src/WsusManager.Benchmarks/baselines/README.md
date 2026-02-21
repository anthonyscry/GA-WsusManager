# Benchmark Baselines

This directory contains baseline measurements for performance regression detection.

## Baseline Files

- `startup-baseline.csv` - Cold/warm startup time measurements
- `database-baseline.csv` - Database operation performance (queries, connections, etc.)
- `winrm-baseline.csv` - WinRM operation measurements

## Capturing Baselines

To capture new baselines on Windows (required for WinRM and database benchmarks):

```powershell
# Run all benchmarks
dotnet run --project src/WsusManager.Benchmarks/WsusManager.Benchmarks.csproj -c Release

# Copy results to baselines
cp src/WsusManager.Benchmarks/BenchmarkDotNet.Artifacts/results-BenchmarkStartup-report.csv src/WsusManager.Benchmarks/baselines/startup-baseline.csv
cp src/WsusManager.Benchmarks/BenchmarkDotNet.Artifacts/results-BenchmarkDatabaseOperations-report.csv src/WsusManager.Benchmarks/baselines/database-baseline.csv
cp src/WsusManager.Benchmarks/BenchmarkDotNet.Artifacts/results-BenchmarkWinRMOperations-report.csv src/WsusManager.Benchmarks/baselines/winrm-baseline.csv
```

## Updating Baselines

When performance legitimately changes (e.g., new features, optimizations):

1. Run benchmarks on a Windows machine with WSUS installed
2. Review the HTML report for unexpected regressions
3. Copy new CSV results to this directory
4. Commit the updated baseline files

## Regression Detection

The CI pipeline runs `detect-regression.ps1` with a 10% threshold. If any benchmark
degrades more than 10% from baseline, the build fails.

## Current Baseline Status

### Startup (Plan 22-01)
- Cold startup: <2 seconds (target)
- Warm startup: <500ms (target)
- Status: Requires Windows execution for accurate measurements

### Database (Plan 22-02)
- Simple query: <10ms (target)
- Connection overhead: <50ms (target)
- Status: Requires SQL Server for accurate measurements

### WinRM (Plan 22-03)
- Connectivity check: <2s (target)
- Mock operations: <100us (target)
- Status: Requires WinRM for real operations, mock benchmarks work anywhere
