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

.PARAMETER NoPush
    Skip git commit and push after successful build.

.EXAMPLE
    .\build.ps1 -TestOnly

.EXAMPLE
    .\build.ps1 -NoPush
#>

param(
    [string]$OutputName,
    [switch]$SkipCodeReview,
    [switch]$SkipTests,
    [switch]$TestOnly,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

$Version = "3.8.8"
if (-not $OutputName) { $OutputName = "GA-WsusManager.exe" }

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

        # Use settings file if available
        $settingsPath = Join-Path $ScriptRoot ".PSScriptAnalyzerSettings.psd1"
        $analyzerParams = @{
            Severity = @('Error', 'Warning')
        }
        if (Test-Path $settingsPath) {
            $analyzerParams.Settings = $settingsPath
            Write-Host "Using settings: .PSScriptAnalyzerSettings.psd1" -ForegroundColor Gray
        }

        Write-Host ""
        foreach ($script in $ScriptsToAnalyze) {
            $scriptPath = Join-Path $ScriptRoot $script
            if (Test-Path $scriptPath) {
                try {
                    $issues = Invoke-ScriptAnalyzer -Path $scriptPath @analyzerParams -ErrorAction Stop

                    if ($issues) {
                        $scriptErrors = ($issues | Where-Object { $_.Severity -eq 'Error' }).Count
                        $scriptWarnings = ($issues | Where-Object { $_.Severity -eq 'Warning' }).Count

                        $ErrorCount += $scriptErrors
                        $WarningCount += $scriptWarnings
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
                catch {
                    Write-Host "    [?] $script - Skipped (analyzer error)" -ForegroundColor Gray
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

    # Check if Pester is installed (including OneDrive module path)
    $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
    $oneDrivePesterPath = Join-Path $env:USERPROFILE "OneDrive\Documents\WindowsPowerShell\Modules\Pester"

    # Check OneDrive path for newer versions
    if (Test-Path $oneDrivePesterPath) {
        $oneDriveVersions = Get-ChildItem -Path $oneDrivePesterPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.' } |
            Sort-Object { [Version]$_.Name } -Descending |
            Select-Object -First 1
        if ($oneDriveVersions -and (!$pesterModule -or [Version]$oneDriveVersions.Name -gt $pesterModule.Version)) {
            $pesterModule = @{ Version = [Version]$oneDriveVersions.Name; ModuleBase = $oneDriveVersions.FullName }
        }
    }

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
        # Import Pester - try OneDrive path first if available
        if ($pesterModule.ModuleBase -and (Test-Path (Join-Path $pesterModule.ModuleBase "Pester.psd1"))) {
            Import-Module (Join-Path $pesterModule.ModuleBase "Pester.psd1") -Force
        } else {
            Import-Module Pester -MinimumVersion 5.0.0 -Force -ErrorAction SilentlyContinue
            if (-not (Get-Command New-PesterConfiguration -ErrorAction SilentlyContinue)) {
                # Fallback: try OneDrive path directly
                $fallbackPath = Get-ChildItem -Path $oneDrivePesterPath -Directory -ErrorAction SilentlyContinue |
                    Sort-Object { [Version]$_.Name } -Descending | Select-Object -First 1
                if ($fallbackPath) {
                    Import-Module (Join-Path $fallbackPath.FullName "Pester.psd1") -Force
                }
            }
        }

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

        # ============================================
        # CREATE DISTRIBUTION ZIP
        # ============================================

        Write-Host "`n[*] Creating distribution package..." -ForegroundColor Yellow

        $packageName = "WsusManager-v$Version"
        $zipFileName = "$packageName.zip"
        $stagingDir = Join-Path $env:TEMP "WsusManager-Package-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $packageDir = Join-Path $stagingDir $packageName

        # Create staging directory structure
        New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $packageDir "Scripts") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $packageDir "Modules") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $packageDir "DomainController") -Force | Out-Null

        # Copy distribution files
        Copy-Item ".\$OutputName" -Destination $packageDir
        if (Test-Path ".\wsus-icon.ico") { Copy-Item ".\wsus-icon.ico" -Destination $packageDir }
        if (Test-Path ".\README.md") { Copy-Item ".\README.md" -Destination $packageDir }

        # Copy logo files for sidebar and About page
        if (Test-Path ".\general_atomics_logo_small.ico") {
            Copy-Item ".\general_atomics_logo_small.ico" -Destination $packageDir
            Write-Host "    Included sidebar logo" -ForegroundColor Gray
        }
        if (Test-Path ".\general_atomics_logo_big.ico") {
            Copy-Item ".\general_atomics_logo_big.ico" -Destination $packageDir
            Write-Host "    Included About page logo" -ForegroundColor Gray
        }

        # Copy Scripts folder (required for operations)
        if (Test-Path ".\Scripts") {
            Copy-Item ".\Scripts\*.ps1" -Destination (Join-Path $packageDir "Scripts")
            Write-Host "    Included Scripts folder" -ForegroundColor Gray
        }

        # Copy Modules folder (required for scripts)
        if (Test-Path ".\Modules") {
            Copy-Item ".\Modules\*.psm1" -Destination (Join-Path $packageDir "Modules")
            Write-Host "    Included Modules folder" -ForegroundColor Gray
        }

        if (Test-Path ".\DomainController") {
            Copy-Item ".\DomainController\*" -Destination (Join-Path $packageDir "DomainController") -Recurse
        }

        # Create quick start guide
        $quickStart = @"
WSUS Manager v$Version - Quick Start Guide
============================================

REQUIREMENTS
------------
- Windows Server 2016, 2019, 2022, or 2025
- Administrator privileges
- .NET Framework 4.7.2 or later

INSTALLATION
------------
1. Extract the entire folder to your WSUS server (e.g., C:\WSUS\WsusManager)
2. Keep the folder structure intact:
   WsusManager-v$Version\
   ├── GA-WsusManager.exe   (main application)
   ├── Scripts\             (required - operation scripts)
   ├── Modules\             (required - PowerShell modules)
   └── DomainController\    (optional - GPO scripts)
3. Right-click GA-WsusManager.exe and select "Run as administrator"

IMPORTANT: Do not move GA-WsusManager.exe without its Scripts and Modules folders!

FIRST RUN
---------
1. Launch GA-WsusManager.exe as Administrator
2. The dashboard will auto-detect your WSUS configuration
3. Use the menu for WSUS operations

DOMAIN CONTROLLER SETUP (Optional)
----------------------------------
The DomainController folder contains GPO deployment scripts.
Run Set-WsusGroupPolicy.ps1 on your DC to configure clients.

Author: Tony Tran, ISSO, GA-ASI
"@
        $quickStart | Out-File -FilePath (Join-Path $packageDir "QUICK-START.txt") -Encoding UTF8

        # Remove existing zip if present
        if (Test-Path ".\$zipFileName") { Remove-Item ".\$zipFileName" -Force }

        # Create zip archive
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($packageDir, ".\$zipFileName", [System.IO.Compression.CompressionLevel]::Optimal, $true)
        }
        catch {
            Compress-Archive -Path "$packageDir\*" -DestinationPath ".\$zipFileName" -Force
        }

        # Cleanup staging
        Remove-Item $stagingDir -Recurse -Force

        if (Test-Path ".\$zipFileName") {
            $zipFile = Get-Item ".\$zipFileName"
            $zipSizeMB = [math]::Round($zipFile.Length / 1MB, 2)
            Write-Host "[+] Package created: $zipFileName ($zipSizeMB MB)" -ForegroundColor Green
        }

        # ============================================
        # COPY TO DIST FOLDER AND GIT COMMIT
        # ============================================

        Write-Host "`n[*] Updating dist folder..." -ForegroundColor Yellow

        $distDir = Join-Path $ScriptRoot "dist"
        if (-not (Test-Path $distDir)) {
            New-Item -ItemType Directory -Path $distDir -Force | Out-Null
        }

        # Copy exe, zip, and logo files to dist
        Copy-Item ".\$OutputName" -Destination $distDir -Force
        Copy-Item ".\$zipFileName" -Destination $distDir -Force
        if (Test-Path ".\general_atomics_logo_small.ico") { Copy-Item ".\general_atomics_logo_small.ico" -Destination $distDir -Force }
        if (Test-Path ".\general_atomics_logo_big.ico") { Copy-Item ".\general_atomics_logo_big.ico" -Destination $distDir -Force }
        Write-Host "[+] Copied to dist\$OutputName" -ForegroundColor Green
        Write-Host "[+] Copied to dist\$zipFileName" -ForegroundColor Green

        # Git operations
        if ($NoPush) {
            Write-Host "`n[*] Skipping git operations (-NoPush specified)" -ForegroundColor Gray
        }
        else {
            Write-Host "`n[*] Committing to git..." -ForegroundColor Yellow

            # Check if we're in a git repo
            $gitDir = Join-Path $ScriptRoot ".git"
            if (Test-Path $gitDir) {
                try {
                    # Add dist folder
                    & git add "dist\*" 2>$null

                    # Check if there are changes to commit
                    $gitStatus = & git status --porcelain "dist\" 2>$null
                    if ($gitStatus) {
                        & git commit -m "Build v$Version - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>$null
                        Write-Host "[+] Committed dist folder to git" -ForegroundColor Green

                        # Push to remote
                        & git push 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[+] Pushed to remote repository" -ForegroundColor Green
                        }
                        else {
                            Write-Host "[!] Push failed - you may need to push manually" -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "[*] No changes to commit in dist folder" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "[!] Git operations failed: $_" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "[*] Not a git repository - skipping git operations" -ForegroundColor Gray
            }
        }

        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "  Build Complete!" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "`nOutputs:" -ForegroundColor Yellow
        Write-Host "  .\$OutputName           # Run WSUS Manager GUI" -ForegroundColor White
        Write-Host "  .\$zipFileName       # Distribution package" -ForegroundColor White
        Write-Host "  .\dist\                  # Git-tracked distribution" -ForegroundColor White
        Write-Host "`nThe dist folder has been committed and pushed to git." -ForegroundColor Gray
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
