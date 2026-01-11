<#
.SYNOPSIS
    Build portable executable from WSUS Manager PowerShell script.

.DESCRIPTION
    Uses PS2EXE to convert WsusManagementGui.ps1 into a standalone .exe file.
    Includes code review with PSScriptAnalyzer before building.

.PARAMETER OutputName
    Name of the output executable (default: WsusManager.exe)

.PARAMETER SkipCodeReview
    Skip the PSScriptAnalyzer code review step.

.EXAMPLE
    .\build.ps1

.PARAMETER SkipTests
    Skip running Pester unit tests.

.PARAMETER TestOnly
    Only run tests, don't build the executable.

.EXAMPLE
    .\build.ps1 -SkipCodeReview

.EXAMPLE
    .\build.ps1 -SkipTests

.EXAMPLE
    .\build.ps1 -TestOnly
#>

param(
    [string]$OutputName,
    [switch]$SkipCodeReview,
    [switch]$SkipTests,
    [switch]$TestOnly
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

$Version = "3.8.0"
if (-not $OutputName) { $OutputName = "WsusManager.exe" }

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  WSUS Manager Executable Builder" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================
# CODE REVIEW WITH PSSCRIPTANALYZER
# ============================================

if (-not $SkipCodeReview) {
    Write-Host "[*] Running code review with PSScriptAnalyzer..." -ForegroundColor Yellow

    # Check if PSScriptAnalyzer is installed (including OneDrive module path)
    $psaModule = Get-Module -ListAvailable -Name PSScriptAnalyzer
    $oneDriveModulePath = Join-Path $env:USERPROFILE "OneDrive\Documents\WindowsPowerShell\Modules\PSScriptAnalyzer"
    if (-not $psaModule -and (Test-Path $oneDriveModulePath)) {
        $psaModule = $oneDriveModulePath
    }

    if (-not $psaModule) {
        Write-Host "    Installing PSScriptAnalyzer..." -ForegroundColor Gray
        try {
            Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
        }
        catch {
            Write-Host "[!] Could not install PSScriptAnalyzer. Skipping code review." -ForegroundColor Yellow
            $SkipCodeReview = $true
        }
    }

    if (-not $SkipCodeReview) {
        # Import from OneDrive path if standard import fails
        try {
            Import-Module PSScriptAnalyzer -Force -ErrorAction Stop
        }
        catch {
            if (Test-Path $oneDriveModulePath) {
                Import-Module $oneDriveModulePath -Force
            } else {
                throw $_
            }
        }

        # Define scripts and modules to analyze
        $ScriptsToAnalyze = @(
            "Scripts\WsusManagementGui.ps1",
            "Scripts\Invoke-WsusManagement.ps1"
        )

        # Add all modules to analysis
        $ModuleFiles = Get-ChildItem -Path (Join-Path $ScriptRoot "Modules") -Filter "*.psm1" -ErrorAction SilentlyContinue
        if ($ModuleFiles) {
            $ScriptsToAnalyze += $ModuleFiles | ForEach-Object { "Modules\$($_.Name)" }
        }

        $TotalIssues = 0
        $ErrorCount = 0
        $WarningCount = 0
        $InfoCount = 0
        $AllIssues = @()

        Write-Host ""
        foreach ($script in $ScriptsToAnalyze) {
            $scriptPath = Join-Path $ScriptRoot $script
            if (Test-Path $scriptPath) {
                $issues = Invoke-ScriptAnalyzer -Path $scriptPath -Severity @('Error', 'Warning', 'Information')

                if ($issues) {
                    $scriptErrors = ($issues | Where-Object { $_.Severity -eq 'Error' }).Count
                    $scriptWarnings = ($issues | Where-Object { $_.Severity -eq 'Warning' }).Count
                    $scriptInfo = ($issues | Where-Object { $_.Severity -eq 'Information' }).Count

                    $ErrorCount += $scriptErrors
                    $WarningCount += $scriptWarnings
                    $InfoCount += $scriptInfo
                    $TotalIssues += $issues.Count

                    foreach ($issue in $issues) {
                        $AllIssues += [PSCustomObject]@{
                            Script = $script
                            Line = $issue.Line
                            Severity = $issue.Severity
                            Rule = $issue.RuleName
                            Message = $issue.Message
                        }
                    }

                    $statusIcon = if ($scriptErrors -gt 0) { "X" } elseif ($scriptWarnings -gt 0) { "!" } else { "i" }
                    $statusColor = if ($scriptErrors -gt 0) { "Red" } elseif ($scriptWarnings -gt 0) { "Yellow" } else { "Cyan" }
                    Write-Host "    [$statusIcon] $script - $($issues.Count) issue(s)" -ForegroundColor $statusColor
                }
                else {
                    Write-Host "    [+] $script - No issues" -ForegroundColor Green
                }
            }
        }

        Write-Host ""

        # Summary
        if ($TotalIssues -gt 0) {
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "  Code Review Summary" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "  Errors:      $ErrorCount" -ForegroundColor $(if ($ErrorCount -gt 0) { "Red" } else { "Green" })
            Write-Host "  Warnings:    $WarningCount" -ForegroundColor $(if ($WarningCount -gt 0) { "Yellow" } else { "Green" })
            Write-Host "  Information: $InfoCount" -ForegroundColor Cyan
            Write-Host "  Total:       $TotalIssues" -ForegroundColor White
            Write-Host ""

            # Show detailed issues
            if ($ErrorCount -gt 0) {
                Write-Host "ERRORS (must fix):" -ForegroundColor Red
                $AllIssues | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object {
                    Write-Host "  $($_.Script):$($_.Line) - $($_.Rule)" -ForegroundColor Red
                    Write-Host "    $($_.Message)" -ForegroundColor Gray
                }
                Write-Host ""
            }

            if ($WarningCount -gt 0 -and $ErrorCount -eq 0) {
                Write-Host "WARNINGS (recommended to fix):" -ForegroundColor Yellow
                $AllIssues | Where-Object { $_.Severity -eq 'Warning' } | Select-Object -First 5 | ForEach-Object {
                    Write-Host "  $($_.Script):$($_.Line) - $($_.Rule)" -ForegroundColor Yellow
                    Write-Host "    $($_.Message)" -ForegroundColor Gray
                }
                if ($WarningCount -gt 5) {
                    Write-Host "  ... and $($WarningCount - 5) more warnings" -ForegroundColor Yellow
                }
                Write-Host ""
            }

            # Block build on errors
            if ($ErrorCount -gt 0) {
                Write-Host "[!] Build blocked: $ErrorCount error(s) found. Fix errors before building." -ForegroundColor Red
                Write-Host "    Run with -SkipCodeReview to bypass (not recommended)" -ForegroundColor Gray
                exit 1
            }

            # Warn but continue on warnings
            if ($WarningCount -gt 0) {
                Write-Host "[*] Proceeding with build despite $WarningCount warning(s)..." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  Code Review: All Clear!" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  No issues found in any scripts." -ForegroundColor Green
            Write-Host ""
        }
    }
}
else {
    Write-Host "[*] Skipping code review (-SkipCodeReview specified)" -ForegroundColor Gray
}

# ============================================
# PESTER TESTS
# ============================================

if (-not $SkipTests) {
    Write-Host "`n[*] Running Pester tests..." -ForegroundColor Yellow

    # Check if Pester is installed
    $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pesterModule) {
        Write-Host "    Installing Pester..." -ForegroundColor Gray
        try {
            Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
        }
        catch {
            Write-Host "[!] Could not install Pester. Skipping tests." -ForegroundColor Yellow
            $SkipTests = $true
        }
    }
    elseif ($pesterModule.Version -lt [Version]"5.0.0") {
        Write-Host "    Updating Pester to v5+..." -ForegroundColor Gray
        try {
            Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
        }
        catch {
            Write-Host "[!] Could not update Pester. Skipping tests." -ForegroundColor Yellow
            $SkipTests = $true
        }
    }

    if (-not $SkipTests) {
        Import-Module Pester -Force

        $TestsPath = Join-Path $ScriptRoot "Tests"
        $TestFiles = Get-ChildItem -Path $TestsPath -Filter "*.Tests.ps1" -ErrorAction SilentlyContinue

        if ($TestFiles) {
            Write-Host ""
            $TestFiles | ForEach-Object { Write-Host "    [>] $($_.Name)" -ForegroundColor Gray }
            Write-Host ""

            # Pre-load all modules once (performance optimization)
            # This avoids repeated Import-Module calls across test files
            $TestSetupPath = Join-Path $TestsPath "TestSetup.ps1"
            if (Test-Path $TestSetupPath) {
                . $TestSetupPath
            }

            # Configure Pester
            $config = New-PesterConfiguration
            $config.Run.Path = $TestFiles.FullName
            $config.Run.Exit = $false
            $config.Output.Verbosity = 'Normal'

            # Run tests
            $testResult = Invoke-Pester -Configuration $config

            # Summary
            Write-Host ""
            Write-Host "========================================" -ForegroundColor $(if ($testResult.FailedCount -gt 0) { "Red" } else { "Green" })
            Write-Host "  Test Results" -ForegroundColor $(if ($testResult.FailedCount -gt 0) { "Red" } else { "Green" })
            Write-Host "========================================" -ForegroundColor $(if ($testResult.FailedCount -gt 0) { "Red" } else { "Green" })
            Write-Host "  Passed:  $($testResult.PassedCount)" -ForegroundColor $(if ($testResult.PassedCount -gt 0) { "Green" } else { "Gray" })
            Write-Host "  Failed:  $($testResult.FailedCount)" -ForegroundColor $(if ($testResult.FailedCount -gt 0) { "Red" } else { "Gray" })
            Write-Host "  Skipped: $($testResult.SkippedCount)" -ForegroundColor $(if ($testResult.SkippedCount -gt 0) { "Yellow" } else { "Gray" })
            Write-Host "  Duration: $([math]::Round($testResult.Duration.TotalSeconds, 2))s" -ForegroundColor Gray
            Write-Host ""

            # Block build on test failures
            if ($testResult.FailedCount -gt 0) {
                Write-Host "[!] Build blocked: $($testResult.FailedCount) test(s) failed." -ForegroundColor Red
                Write-Host "    Run with -SkipTests to bypass (not recommended)" -ForegroundColor Gray
                exit 1
            }
        }
        else {
            Write-Host "    No test files found in $TestsPath" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "[*] Skipping tests (-SkipTests specified)" -ForegroundColor Gray
}

# Exit early if TestOnly mode
if ($TestOnly) {
    Write-Host "`n[*] TestOnly mode - skipping build" -ForegroundColor Yellow
    exit 0
}

# ============================================
# BUILD PROCESS
# ============================================

# Check if PS2EXE is installed (including OneDrive module path)
$ps2exeModule = Get-Module -ListAvailable -Name ps2exe
$oneDrivePs2exePath = Join-Path $env:USERPROFILE "OneDrive\Documents\WindowsPowerShell\Modules\ps2exe"
if (-not $ps2exeModule -and (Test-Path $oneDrivePs2exePath)) {
    $ps2exeModule = $oneDrivePs2exePath
}

if (-not $ps2exeModule) {
    Write-Host "[*] Installing PS2EXE module..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
        Write-Host "[+] PS2EXE installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Failed to install PS2EXE. Try running:" -ForegroundColor Red
        Write-Host "    Install-Module -Name ps2exe -Scope CurrentUser -Force" -ForegroundColor White
        exit 1
    }
}

# Import ps2exe (try standard path first, then OneDrive)
try {
    Import-Module ps2exe -Force -ErrorAction Stop
}
catch {
    if (Test-Path $oneDrivePs2exePath) {
        Import-Module $oneDrivePs2exePath -Force
    } else {
        throw $_
    }
}

Write-Host "[*] Preparing build..." -ForegroundColor Yellow

# Build parameters
$buildParams = @{
    InputFile = ".\Scripts\WsusManagementGui.ps1"
    OutputFile = ".\$OutputName"
    NoConsole = $true
    RequireAdmin = $true
    Title = "WSUS Manager"
    Description = "WSUS Manager - Modern GUI for Windows Server Update Services"
    Company = "GA-ASI"
    Product = "WSUS Manager"
    Copyright = "Tony Tran, ISSO - GA-ASI"
    Version = "$Version.0"
    STA = $true
    x64 = $true
}

# Add icon if exists
if (Test-Path ".\wsus-icon.ico") {
    $buildParams.IconFile = ".\wsus-icon.ico"
    Write-Host "[+] Using custom icon: wsus-icon.ico" -ForegroundColor Green
}

Write-Host "[*] Converting to executable..." -ForegroundColor Yellow
Write-Host "    Output: $OutputName" -ForegroundColor Gray
Write-Host "    NoConsole: True (GUI mode)" -ForegroundColor Gray
Write-Host "    RequireAdmin: True" -ForegroundColor Gray
Write-Host "    x64: True" -ForegroundColor Gray

# Clean up previous build artifact
if (Test-Path ".\$OutputName") {
    Write-Host "[*] Removing previous build..." -ForegroundColor Gray
    Remove-Item ".\$OutputName" -Force
}

try {
    Invoke-PS2EXE @buildParams

    if (Test-Path ".\$OutputName") {
        $exe = Get-Item ".\$OutputName"
        $sizeMB = [math]::Round($exe.Length / 1MB, 2)

        Write-Host "`n[+] Build successful!" -ForegroundColor Green
        Write-Host "    File: $($exe.FullName)" -ForegroundColor White
        Write-Host "    Size: $sizeMB MB" -ForegroundColor White

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Build Complete!" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`nUsage:" -ForegroundColor Yellow
        Write-Host "  .\$OutputName    # Run WSUS Manager GUI" -ForegroundColor White
        Write-Host "`nThe executable is fully portable - copy it anywhere!" -ForegroundColor Gray
    }
    else {
        Write-Host "[!] Build may have failed - output file not found" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "[!] Build failed: $_" -ForegroundColor Red
    exit 1
}
