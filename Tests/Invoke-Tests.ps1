<#
.SYNOPSIS
    Runs all Pester tests for WSUS Manager modules

.DESCRIPTION
    This script runs Pester tests for all WSUS Manager PowerShell modules.
    It can run all tests or specific test files, and optionally generate
    code coverage reports.

.PARAMETER TestName
    Optional. Run only tests matching this name pattern.

.PARAMETER Path
    Optional. Path to specific test file(s). Defaults to all *.Tests.ps1 files.

.PARAMETER CodeCoverage
    Optional. Generate code coverage report for modules.

.PARAMETER OutputFile
    Optional. Path to output test results in NUnitXml format.

.PARAMETER PassThru
    Optional. Return Pester result object.

.EXAMPLE
    .\Invoke-Tests.ps1
    # Runs all tests

.EXAMPLE
    .\Invoke-Tests.ps1 -TestName "WsusConfig"
    # Runs only WsusConfig tests

.EXAMPLE
    .\Invoke-Tests.ps1 -CodeCoverage -OutputFile "TestResults.xml"
    # Runs all tests with coverage and outputs results

.NOTES
    Requires Pester v5.0+
#>
[CmdletBinding()]
param(
    [string]$TestName,

    [string]$Path,

    [switch]$CodeCoverage,

    [string]$OutputFile,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

# Check for Pester module
$pester = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host "Pester module not found. Installing..." -ForegroundColor Yellow
    Install-Module Pester -Force -Scope CurrentUser -SkipPublisherCheck
    Import-Module Pester -Force
} elseif ($pester.Version -lt [Version]"5.0.0") {
    Write-Host "Pester version $($pester.Version) found. Updating to v5+..." -ForegroundColor Yellow
    Install-Module Pester -Force -Scope CurrentUser -SkipPublisherCheck
    Import-Module Pester -Force
} else {
    Import-Module Pester -Force
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  WSUS Manager - Pester Test Runner" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Set up paths
$TestsPath = $PSScriptRoot
$ModulesPath = Join-Path (Split-Path $TestsPath -Parent) "Modules"

# Determine test files to run
if ($Path) {
    $TestFiles = Get-Item $Path
} else {
    $TestFiles = Get-ChildItem -Path $TestsPath -Filter "*.Tests.ps1"
}

Write-Host "Test files to run:" -ForegroundColor Green
$TestFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

# Build Pester configuration
$config = New-PesterConfiguration

# Test paths
$config.Run.Path = $TestFiles.FullName
$config.Run.Exit = $false

# Filter by test name if specified
if ($TestName) {
    $config.Filter.FullName = "*$TestName*"
    Write-Host "Filtering tests by name: $TestName" -ForegroundColor Yellow
}

# Output configuration
$config.Output.Verbosity = 'Detailed'

# Code coverage configuration
if ($CodeCoverage) {
    $moduleFiles = Get-ChildItem -Path $ModulesPath -Filter "*.psm1"
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $moduleFiles.FullName
    $config.CodeCoverage.OutputPath = Join-Path $TestsPath "coverage.xml"
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    Write-Host "Code coverage enabled for:" -ForegroundColor Green
    $moduleFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    Write-Host ""
}

# Test results output
if ($OutputFile) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $OutputFile
    $config.TestResult.OutputFormat = 'NUnitXml'
    Write-Host "Test results will be saved to: $OutputFile" -ForegroundColor Green
}

# Run tests
Write-Host "`nRunning Pester tests...`n" -ForegroundColor Cyan
$result = Invoke-Pester -Configuration $config

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Test Results Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passedColor = if ($result.PassedCount -gt 0) { "Green" } else { "Gray" }
$failedColor = if ($result.FailedCount -gt 0) { "Red" } else { "Gray" }
$skippedColor = if ($result.SkippedCount -gt 0) { "Yellow" } else { "Gray" }

Write-Host "  Passed:  $($result.PassedCount)" -ForegroundColor $passedColor
Write-Host "  Failed:  $($result.FailedCount)" -ForegroundColor $failedColor
Write-Host "  Skipped: $($result.SkippedCount)" -ForegroundColor $skippedColor
Write-Host "  Total:   $($result.TotalCount)" -ForegroundColor Cyan
Write-Host "  Duration: $([math]::Round($result.Duration.TotalSeconds, 2))s" -ForegroundColor Gray
Write-Host ""

if ($CodeCoverage -and $result.CodeCoverage) {
    $coveragePercent = [math]::Round(($result.CodeCoverage.CommandsExecutedCount / $result.CodeCoverage.CommandsAnalyzedCount) * 100, 2)
    $coverageColor = if ($coveragePercent -ge 80) { "Green" } elseif ($coveragePercent -ge 50) { "Yellow" } else { "Red" }
    Write-Host "Code Coverage: $coveragePercent%" -ForegroundColor $coverageColor
    Write-Host "  Commands Executed: $($result.CodeCoverage.CommandsExecutedCount)" -ForegroundColor Gray
    Write-Host "  Commands Analyzed: $($result.CodeCoverage.CommandsAnalyzedCount)" -ForegroundColor Gray
    Write-Host ""
}

# Return result if PassThru
if ($PassThru) {
    return $result
}

# Exit with appropriate code
if ($result.FailedCount -gt 0) {
    Write-Host "TESTS FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
