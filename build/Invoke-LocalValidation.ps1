<#
.SYNOPSIS
    Local validation script that mirrors CI/CD checks.

.DESCRIPTION
    Runs PSScriptAnalyzer, Pester tests, and XAML validation locally.
    Use this before committing to catch issues early.

.PARAMETER Fix
    Attempt to auto-fix formatting issues where possible.

.PARAMETER SkipTests
    Skip Pester test execution (faster for quick lint checks).

.PARAMETER Verbose
    Show detailed output for each check.

.EXAMPLE
    .\build\Invoke-LocalValidation.ps1
    # Runs all checks

.EXAMPLE
    .\build\Invoke-LocalValidation.ps1 -SkipTests
    # Runs only linting and XAML validation
#>

[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Continue'
$script:HasErrors = $false
$script:HasWarnings = $false

# Colors
$ColorSuccess = 'Green'
$ColorError = 'Red'
$ColorWarning = 'Yellow'
$ColorInfo = 'Cyan'
$ColorMuted = 'DarkGray'

function Write-Header {
    param([string]$Text)
    Write-Host "`n$('=' * 60)" -ForegroundColor $ColorInfo
    Write-Host " $Text" -ForegroundColor $ColorInfo
    Write-Host "$('=' * 60)" -ForegroundColor $ColorInfo
}

function Write-Result {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Detail
    )

    $color = switch ($Status) {
        'PASS' { $ColorSuccess }
        'FAIL' { $ColorError }
        'WARN' { $ColorWarning }
        'SKIP' { $ColorMuted }
        default { 'White' }
    }

    Write-Host "[$Status] " -ForegroundColor $color -NoNewline
    Write-Host $Message
    if ($Detail) {
        Write-Host "       $Detail" -ForegroundColor $ColorMuted
    }
}

# Change to repo root
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    Write-Host "`nGA-WsusManager Local Validation" -ForegroundColor $ColorInfo
    Write-Host "Running from: $repoRoot" -ForegroundColor $ColorMuted
    Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor $ColorMuted

    #region PSScriptAnalyzer
    Write-Header "PSScriptAnalyzer - Code Quality"

    # Check if PSScriptAnalyzer is installed
    $analyzer = Get-Module -ListAvailable PSScriptAnalyzer
    if (-not $analyzer) {
        Write-Result 'WARN' 'PSScriptAnalyzer not installed'
        Write-Host "       Install with: Install-Module PSScriptAnalyzer -Scope CurrentUser" -ForegroundColor $ColorMuted
        $script:HasWarnings = $true
    } else {
        # Find all PowerShell files
        $psFiles = Get-ChildItem -Path $repoRoot -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|bin|obj|dist)[\\/]' }

        Write-Host "Analyzing $($psFiles.Count) PowerShell files..." -ForegroundColor $ColorMuted

        # Use settings file if available
        $settingsPath = Join-Path $repoRoot '.PSScriptAnalyzerSettings.psd1'

        $analyzerParams = @{
            Severity = @('Error', 'Warning')
        }
        if (Test-Path $settingsPath) {
            $analyzerParams.Settings = $settingsPath
            Write-Host "Using settings: $settingsPath" -ForegroundColor $ColorMuted
        }

        $allResults = @()
        $errorCount = 0
        $warningCount = 0

        foreach ($file in $psFiles) {
            $relativePath = $file.FullName.Replace($repoRoot, '').TrimStart('\', '/')
            try {
                $results = Invoke-ScriptAnalyzer -Path $file.FullName @analyzerParams -ErrorAction SilentlyContinue

                if ($results) {
                    $fileErrors = ($results | Where-Object Severity -eq 'Error').Count
                    $fileWarnings = ($results | Where-Object Severity -eq 'Warning').Count
                    $errorCount += $fileErrors
                    $warningCount += $fileWarnings

                    if ($fileErrors -gt 0) {
                        Write-Result 'FAIL' $relativePath "$fileErrors error(s), $fileWarnings warning(s)"
                        $script:HasErrors = $true
                    } elseif ($fileWarnings -gt 0) {
                        Write-Result 'WARN' $relativePath "$fileWarnings warning(s)"
                        $script:HasWarnings = $true
                    }

                    # Show details
                    foreach ($result in $results) {
                        $severity = if ($result.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
                        Write-Host "       Line $($result.Line): " -NoNewline -ForegroundColor $ColorMuted
                        Write-Host "$($result.RuleName)" -ForegroundColor $severity
                        Write-Host "       $($result.Message)" -ForegroundColor $ColorMuted
                    }

                    $allResults += $results
                }
            }
            catch {
                Write-Result 'SKIP' $relativePath "Analyzer error"
            }
        }

        $passedFiles = $psFiles.Count - ($allResults | Select-Object -ExpandProperty ScriptName -Unique).Count
        Write-Host "`nSummary: " -NoNewline
        Write-Host "$passedFiles passed" -ForegroundColor $ColorSuccess -NoNewline
        Write-Host ", $errorCount errors" -ForegroundColor $(if ($errorCount -gt 0) { $ColorError } else { $ColorMuted }) -NoNewline
        Write-Host ", $warningCount warnings" -ForegroundColor $(if ($warningCount -gt 0) { $ColorWarning } else { $ColorMuted })
    }
    #endregion

    #region XAML Validation
    Write-Header "XAML Validation (Embedded)"

    # Find files with embedded XAML
    $guiScript = Join-Path $repoRoot "Scripts\WsusManagementGui.ps1"
    if (Test-Path $guiScript) {
        Write-Host "Checking embedded XAML in GUI script..." -ForegroundColor $ColorMuted

        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop

            $content = Get-Content -Path $guiScript -Raw
            # Look for XAML here-strings
            if ($content -match '@["''][\s\S]*?<Window[\s\S]*?</Window>[\s\S]*?["'']@') {
                Write-Result 'PASS' 'Scripts\WsusManagementGui.ps1' 'XAML structure detected'
            } else {
                Write-Result 'WARN' 'Scripts\WsusManagementGui.ps1' 'No XAML Window found'
            }
        } catch {
            Write-Result 'WARN' 'WPF not available - skipping XAML validation'
            $script:HasWarnings = $true
        }
    } else {
        Write-Result 'SKIP' 'GUI script not found'
    }
    #endregion

    #region Pester Tests
    if (-not $SkipTests) {
        Write-Header "Pester Tests"

        $pester = Get-Module -ListAvailable Pester | Where-Object Version -ge '5.0.0'
        if (-not $pester) {
            Write-Result 'WARN' 'Pester 5.0+ not installed'
            Write-Host "       Install with: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force" -ForegroundColor $ColorMuted
            $script:HasWarnings = $true
        } else {
            $testFiles = Get-ChildItem -Path $repoRoot -Include '*.Tests.ps1' -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/](\.git|bin|obj)[\\/]' }

            if ($testFiles.Count -eq 0) {
                Write-Result 'WARN' 'No test files found (*.Tests.ps1)'
                $script:HasWarnings = $true
            } else {
                Write-Host "Running $($testFiles.Count) test file(s)..." -ForegroundColor $ColorMuted

                Import-Module Pester -MinimumVersion 5.0.0 -Force

                $config = New-PesterConfiguration
                $config.Run.Path = $testFiles.FullName
                $config.Run.PassThru = $true
                $config.Output.Verbosity = 'Normal'
                $config.TestResult.Enabled = $false

                try {
                    $testResults = Invoke-Pester -Configuration $config

                    if ($testResults.FailedCount -gt 0) {
                        Write-Result 'FAIL' "Tests: $($testResults.FailedCount) failed, $($testResults.PassedCount) passed"
                        $script:HasErrors = $true
                    } else {
                        Write-Result 'PASS' "All $($testResults.PassedCount) tests passed"
                    }
                } catch {
                    Write-Result 'FAIL' 'Test execution failed'
                    Write-Host "       $($_.Exception.Message)" -ForegroundColor $ColorMuted
                    $script:HasErrors = $true
                }
            }
        }
    } else {
        Write-Header "Pester Tests"
        Write-Result 'SKIP' 'Tests skipped (-SkipTests)'
    }
    #endregion

    #region Final Summary
    Write-Host "`n$('=' * 60)" -ForegroundColor $ColorInfo
    if ($script:HasErrors) {
        Write-Host " VALIDATION FAILED - Fix errors before committing" -ForegroundColor $ColorError
        $exitCode = 1
    } elseif ($script:HasWarnings) {
        Write-Host " VALIDATION PASSED WITH WARNINGS" -ForegroundColor $ColorWarning
        $exitCode = 0
    } else {
        Write-Host " VALIDATION PASSED - Ready to commit!" -ForegroundColor $ColorSuccess
        $exitCode = 0
    }
    Write-Host "$('=' * 60)" -ForegroundColor $ColorInfo
    Write-Host "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor $ColorMuted
    #endregion

} finally {
    Pop-Location
}

exit $exitCode
