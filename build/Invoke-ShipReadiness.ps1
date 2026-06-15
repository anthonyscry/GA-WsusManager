<#
.SYNOPSIS
    Run the full ship-readiness verification suite.

.DESCRIPTION
    Runs all verification steps from the ship-readiness report in order:
      1. Syntax check (parse all PS files)
      2. PSScriptAnalyzer lint (errors only)
      3. Pester test suite (full)

    Aggregates results into a single pass/fail summary. Use this as the
    pre-release gate before tagging a release.

.PARAMETER SkipTests
    Skip the Pester test step (run lint only).

.PARAMETER SkipLint
    Skip the PSScriptAnalyzer step (syntax + tests only).

.PARAMETER OutputFile
    Write full test results to NUnit3 XML.

.EXAMPLE
    .\build\Invoke-ShipReadiness.ps1
    # Run everything

.EXAMPLE
    .\build\Invoke-ShipReadiness.ps1 -SkipTests -OutputFile ship.xml
    # Lint only, write XML
#>

[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$SkipLint,
    [string]$OutputFile
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$overallPass = $true
$results = @{}

function Write-StepHeader {
    param([string]$Title, [int]$Step, [int]$Total)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host " Step $Step/$Total : $Title" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ""
}

function Write-StepResult {
    param(
        [string]$Step,
        [bool]$Pass,
        [string]$Detail = ""
    )
    $color = if ($Pass) { 'Green' } else { 'Red' }
    $status = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host "  [$status] $Step" -ForegroundColor $color
    if ($Detail) {
        Write-Host "         $Detail" -ForegroundColor Gray
    }
}

# Step 1: Syntax check
Write-StepHeader "Syntax Check" 1 3
$allFiles = Get-ChildItem -Path $root -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|bin|obj|dist|\.planning-archive-reverted-c#-era)[\\/]' }
$syntaxErrors = 0
foreach ($file in $allFiles) {
    $tokens = $null; $errs = $null
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) { $syntaxErrors++ }
    } catch {
        $syntaxErrors++
    }
}
Write-StepResult "Syntax check ($($allFiles.Count) files)" ($syntaxErrors -eq 0) "$syntaxErrors files with parse errors"
$results['SyntaxCheck'] = @{ Pass = ($syntaxErrors -eq 0); Errors = $syntaxErrors }
if ($syntaxErrors -gt 0) { $overallPass = $false }

# Step 2: PSScriptAnalyzer
if (-not $SkipLint) {
    Write-StepHeader "PSScriptAnalyzer" 2 3
    $analyzer = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
    if (-not $analyzer) {
        Write-StepResult "PSScriptAnalyzer" $false "Not installed (run: Install-Module PSScriptAnalyzer -Scope CurrentUser)"
        $results['Lint'] = @{ Pass = $false; Error = 'Not installed' }
        $overallPass = $false
    } else {
        Import-Module PSScriptAnalyzer -Force
        $settings = Join-Path $root '.PSScriptAnalyzerSettings.psd1'
        $params = @{ Severity = @('Error') }
        if (Test-Path $settings) { $params.Settings = $settings }
        $lintErrors = 0
        foreach ($file in $allFiles) {
            $fileErrors = Invoke-ScriptAnalyzer -Path $file.FullName @params -ErrorAction SilentlyContinue
            $lintErrors += ($fileErrors | Measure-Object).Count
        }
        Write-StepResult "PSScriptAnalyzer (errors only)" ($lintErrors -eq 0) "$lintErrors error(s) across $($allFiles.Count) files"
        $results['Lint'] = @{ Pass = ($lintErrors -eq 0); Errors = $lintErrors }
        if ($lintErrors -gt 0) { $overallPass = $false }
    }
} else {
    Write-StepResult "PSScriptAnalyzer" $true "Skipped (-SkipLint)"
    $results['Lint'] = @{ Pass = $true; Skipped = $true }
}

# Step 3: Pester tests
if (-not $SkipTests) {
    Write-StepHeader "Pester Tests" 3 3
    $pester = Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0.0' | Select-Object -First 1
    if (-not $pester) {
        Write-StepResult "Pester" $false "Not installed (run: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force)"
        $results['Tests'] = @{ Pass = $false; Error = 'Not installed' }
        $overallPass = $false
    } else {
        Import-Module Pester -MinimumVersion 5.0.0 -Force
        $testFiles = Get-ChildItem -Path $root -Include '*.Tests.ps1' -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|bin|obj|\.planning-archive-reverted-c#-era)[\\/]' }
        $config = New-PesterConfiguration
        $config.Run.Path = $testFiles.FullName
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Normal'
        if ($OutputFile) {
            $config.TestResult.Enabled = $true
            $config.TestResult.OutputPath = $OutputFile
            $config.TestResult.OutputFormat = 'NUnit3'
        }
        $testResult = Invoke-Pester -Configuration $config
        $testsPass = ($testResult.FailedCount -eq 0)
        Write-StepResult "Pester ($($testFiles.Count) files)" $testsPass "$($testResult.PassedCount)/$($testResult.TotalCount) passed, $($testResult.FailedCount) failed, $($testResult.SkippedCount) skipped"
        $results['Tests'] = @{
            Pass = $testsPass
            Passed = $testResult.PassedCount
            Failed = $testResult.FailedCount
            Skipped = $testResult.SkippedCount
            Total = $testResult.TotalCount
            Duration = $testResult.Duration
        }
        if (-not $testsPass) { $overallPass = $false }
    }
} else {
    Write-StepResult "Pester" $true "Skipped (-SkipTests)"
    $results['Tests'] = @{ Pass = $true; Skipped = $true }
}


# Final summary
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host " Ship Readiness Summary" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
foreach ($k in $results.Keys) {
    $r = $results[$k]
    $pass = $r.Pass
    $color = if ($pass) { 'Green' } else { 'Red' }
    $status = if ($pass) { 'PASS' } else { 'FAIL' }
    Write-Host "  [$status] $k" -ForegroundColor $color
}
Write-Host ""
if ($overallPass) {
    Write-Host " READY TO SHIP" -ForegroundColor Green
    exit 0
} else {
    Write-Host " NOT READY - Fix failures above" -ForegroundColor Red
    exit 1
}
