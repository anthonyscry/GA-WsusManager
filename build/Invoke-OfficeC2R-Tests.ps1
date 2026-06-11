<#
.SYNOPSIS
    Runs the WsusOfficeUpdates tests in isolation.

.DESCRIPTION
    Focused test runner for the Office C2R update download feature.
    Useful when iterating on the module, since it skips the full
    700+ test suite and runs only the 40 Office C2R tests in a few
    seconds.

.PARAMETER OutputFile
    Optional path to write NUnit3 test results XML for CI integration.

.EXAMPLE
    .\build\Invoke-OfficeC2R-Tests.ps1
    # Run Office C2R tests

.EXAMPLE
    .\build\Invoke-OfficeC2R-Tests.ps1 -OutputFile test-results.xml
    # Run with XML output
#>

[CmdletBinding()]
param(
    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$pester = Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0.0' | Select-Object -First 1
if (-not $pester) {
    Write-Host "Pester 5.0+ is required. Install with:" -ForegroundColor Red
    Write-Host "  Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force" -ForegroundColor Yellow
    exit 1
}

Import-Module Pester -MinimumVersion 5.0.0 -Force

$testFile = Join-Path $root 'Tests\WsusOfficeUpdates.Tests.ps1'
if (-not (Test-Path $testFile)) {
    Write-Host "Test file not found: $testFile" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Office C2R Module Tests" -ForegroundColor Cyan
Write-Host "  Pester: v$($pester.Version)" -ForegroundColor Gray
Write-Host "  Tests:  $testFile" -ForegroundColor Gray
Write-Host ""

$config = New-PesterConfiguration
$config.Run.Path = $testFile
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'

if ($OutputFile) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $OutputFile
    $config.TestResult.OutputFormat = 'NUnit3'
}

$result = Invoke-Pester -Configuration $config

Write-Host ""
$status = if ($result.FailedCount -gt 0) { 'FAILED' } else { 'PASSED' }
$color = if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' }
Write-Host "Result: $status" -ForegroundColor $color
Write-Host "  Passed: $($result.PassedCount)" -ForegroundColor Green
Write-Host "  Failed: $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "  Skipped: $($result.SkippedCount)" -ForegroundColor $(if ($result.SkippedCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Total:  $($result.TotalCount)" -ForegroundColor Gray
Write-Host "  Time:   $($result.Duration)" -ForegroundColor Gray

if ($OutputFile -and (Test-Path $OutputFile)) {
    Write-Host "  Output: $OutputFile" -ForegroundColor Gray
}

if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
