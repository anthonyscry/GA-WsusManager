<#
.SYNOPSIS
    Sets up a Windows VM (triton-ajt) for running automated GUI tests.

.DESCRIPTION
    One-time setup script that installs all prerequisites for running
    FlaUI-based GUI tests on a clean Windows Server VM.

    Prerequisites installed:
    - Pester 5 (test framework)
    - FlaUI NuGet packages (UI automation)
    - PS2EXE (for building the EXE)
    - Git (for cloning the repo)

.EXAMPLE
    # Run as Administrator on triton-ajt
    Set-ExecutionPolicy Bypass -Scope Process -Force
    .\Tests\FlaUITestHarness\Setup-GuiTestEnvironment.ps1

.NOTES
    Run this script as Administrator. Requires internet access for
    NuGet package downloads.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  WSUS Manager GUI Test Environment Setup" -ForegroundColor Cyan
Write-Host "  Target: triton-ajt" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Ensure PowerShellGet and PSGallery
# ---------------------------------------------------------------------------
Write-Host "[1/5] Configuring PowerShellGet..." -ForegroundColor Yellow
try {
    $null = Get-PackageProvider -Name NuGet -ErrorAction Stop
} catch {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
}
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Write-Host "  [OK] PowerShellGet configured" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Install Pester 5
# ---------------------------------------------------------------------------
Write-Host "`n[2/5] Installing Pester..." -ForegroundColor Yellow
$pesterInstalled = Get-Module -ListAvailable Pester -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pesterInstalled -and [version]$pesterInstalled.Version -ge [version]"5.0.0") {
    Write-Host "  [OK] Pester $($pesterInstalled.Version) already installed" -ForegroundColor Green
} else {
    Install-Module Pester -Force -Scope CurrentUser -SkipPublisherCheck
    Write-Host "  [OK] Pester installed" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. Install FlaUI packages
# ---------------------------------------------------------------------------
Write-Host "`n[3/5] Installing FlaUI NuGet packages..." -ForegroundColor Yellow
$installScript = Join-Path $PSScriptRoot "Install-FlaUI.ps1"
if (Test-Path $installScript) {
    & $installScript
} else {
    Write-Error "Install-FlaUI.ps1 not found at: $installScript"
    exit 1
}

# ---------------------------------------------------------------------------
# 4. Verify .NET Framework (required by FlaUI)
# ---------------------------------------------------------------------------
Write-Host "`n[4/5] Verifying .NET Framework..." -ForegroundColor Yellow
$netVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Version
if ($netVersion) {
    Write-Host "  [OK] .NET Framework $netVersion" -ForegroundColor Green
} else {
    Write-Host "  [WARN] .NET Framework 4.x not detected. FlaUI requires .NET Framework 4.6.1+" -ForegroundColor Red
    Write-Host "  Install .NET Framework 4.8 from: https://dotnet.microsoft.com/download/dotnet-framework" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 5. Verify test module loads
# ---------------------------------------------------------------------------
Write-Host "`n[5/5] Verifying FlaUI Test Harness loads..." -ForegroundColor Yellow
$harnessPath = Join-Path $PSScriptRoot "FlaUITestHarness.psm1"
Import-Module $harnessPath -Force

# Test FlaUI assembly loading
try {
    $null = [FlaUI.UIA3.UIA3Automation]::new()
    Write-Host "  [OK] FlaUI.UIA3 loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] FlaUI assemblies failed to load: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Clone the repository (if not already)" -ForegroundColor White
Write-Host "     git clone <repo-url> C:\projects\GA-WsusManager" -ForegroundColor Gray
Write-Host "  2. Build the EXE:" -ForegroundColor White
Write-Host "     cd C:\projects\GA-WsusManager" -ForegroundColor Gray
Write-Host "     .\build.ps1" -ForegroundColor Gray
Write-Host "  3. Run GUI tests:" -ForegroundColor White
Write-Host "     Invoke-Pester -Path .\Tests\FlaUI.Tests.ps1 -Output Detailed" -ForegroundColor Gray
Write-Host "  4. Run unit tests:" -ForegroundColor White
Write-Host "     Invoke-Pester -Path .\Tests -Output Detailed -ExcludeTag 'E2E'" -ForegroundColor Gray
Write-Host ""
