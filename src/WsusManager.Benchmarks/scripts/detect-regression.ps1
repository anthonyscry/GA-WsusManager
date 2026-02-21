param(
    [Parameter(Mandatory=$true)]
    [string]$CurrentResultsPath,

    [Parameter(Mandatory=$true)]
    [string]$BaselinePath,

    [Parameter(Mandatory=$false)]
    [double]$ThresholdPercent = 10.0
)

$ErrorActionPreference = "Stop"

# Import CSV files
if (-not (Test-Path $CurrentResultsPath)) {
    Write-Host "ERROR: Current results file not found: $CurrentResultsPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BaselinePath)) {
    Write-Host "ERROR: Baseline file not found: $BaselinePath" -ForegroundColor Red
    exit 1
}

$current = Import-Csv $CurrentResultsPath
$baseline = Import-Csv $BaselinePath

# Group by benchmark name (extract base name before parameters)
$currentGrouped = $current | Group-Object { ($_.Benchmark -split '\s*\|\s*')[0] }
$baselineGrouped = $baseline | Group-Object { ($_.Benchmark -split '\s*\|\s*')[0] }

$regressions = @()
$comparisons = @()

foreach ($group in $currentGrouped) {
    $name = $group.Name
    $baselineGroup = $baselineGrouped | Where-Object { $_.Name -eq $name }

    if (-not $baselineGroup) {
        Write-Host "WARNING: No baseline found for '$name' - skipping comparison" -ForegroundColor Yellow
        continue
    }

    # Get mean values (handle "us" vs "ms" vs "ns" units)
    $currentMeanRaw = $group.Group[0]."Mean"
    $baselineMeanRaw = $baselineGroup.Group[0]."Mean"

    # Extract numeric value (remove unit suffixes like "us", "ms", "ns")
    $currentMean = ($currentMeanRaw -replace '[^\d.]', '').Trim()
    $baselineMean = ($baselineMeanRaw -replace '[^\d.]', '').Trim()

    if (-not [double]::TryParse($currentMean, [ref]$null) -or
        -not [double]::TryParse($baselineMean, [ref]$null)) {
        Write-Host "WARNING: Could not parse numeric values for '$name' (Current: '$currentMeanRaw', Baseline: '$baselineMeanRaw')" -ForegroundColor Yellow
        continue
    }

    $currentVal = [double]$currentMean
    $baselineVal = [double]$baselineMean

    # Calculate percent change
    if ($baselineVal -eq 0) {
        $percentChange = 0
    } else {
        $percentChange = (($currentVal - $baselineVal) / $baselineVal) * 100
    }

    $comparison = [PSCustomObject]@{
        Benchmark = $name
        Baseline = "$baselineMeanRaw"
        Current = "$currentMeanRaw"
        Change = "$percentChange:F2"
        Status = if ($percentChange -gt $ThresholdPercent) { "REGRESSION" } else { "OK" }
    }

    $comparisons += $comparison

    if ($percentChange -gt $ThresholdPercent) {
        $regressions += $comparison
        Write-Host "REGRESSION: '$name' degraded by $($percentChange:F2)% (threshold: $ThresholdPercent%)" -ForegroundColor Red
    } else {
        Write-Host "OK: '$name' changed by $($percentChange:F2)%" -ForegroundColor Green
    }
}

# Output summary
Write-Host "`n=== Performance Regression Summary ===" -ForegroundColor Cyan
Write-Host "Benchmarks compared: $($comparisons.Count)"
Write-Host "Regressions found: $($regressions.Count)"
Write-Host "Threshold: $ThresholdPercent%`n"

# Exit with error if regressions detected
if ($regressions.Count -gt 0) {
    Write-Host "`nRegressions detected:" -ForegroundColor Red
    $regressions | Format-Table -AutoSize
    exit 1
} else {
    Write-Host "No performance regressions detected!" -ForegroundColor Green
    exit 0
}
