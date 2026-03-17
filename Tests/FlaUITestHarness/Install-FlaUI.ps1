<#
.SYNOPSIS
    Installs FlaUI NuGet packages for the FlaUI Test Harness.

.DESCRIPTION
    Downloads FlaUI.UIA3 and FlaUI.Core NuGet packages to the
    Tests/FlaUITestHarness/packages directory. Required before running
    GUI automation tests.

.EXAMPLE
    .\Tests\FlaUITestHarness\Install-FlaUI.ps1
#>

$ErrorActionPreference = "Stop"

$ModuleRoot = $PSScriptRoot
$PackagesDir = Join-Path $ModuleRoot "packages"
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "FlaUI-Install-$(Get-Random)"

# Packages to install
$Packages = @(
    @{ Id = "FlaUI.UIA3"; Version = "4.0.0" }
    @{ Id = "FlaUI.Core"; Version = "4.0.0" }
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FlaUI NuGet Package Installer" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check for NuGet
$nugetExe = $null
$nugetPaths = @(
    (Join-Path $ModuleRoot "nuget.exe"),
    "nuget",
    "${env:ProgramFiles}\NuGet\nuget.exe",
    "${env:LOCALAPPDATA}\Microsoft\NuGet\NuGet.exe"
)

foreach ($p in $nugetPaths) {
    if (Test-Path $p) {
        $nugetExe = $p
        break
    }
    # Try as command
    if (Get-Command $p -ErrorAction SilentlyContinue) {
        $nugetExe = (Get-Command $p).Source
        break
    }
}

if (-not $nugetExe) {
    # Download nuget.exe
    Write-Host "Downloading nuget.exe..." -ForegroundColor Yellow
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    $nugetExe = Join-Path $ModuleRoot "nuget.exe"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
        Write-Host "  Downloaded: $nugetExe" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download nuget.exe: $($_.Exception.Message)"
        Write-Host "Download manually from: $nugetUrl" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "NuGet: $nugetExe" -ForegroundColor Green
Write-Host "Target: $PackagesDir`n" -ForegroundColor Green

# Create packages directory
if (-not (Test-Path $PackagesDir)) {
    New-Item -Path $PackagesDir -ItemType Directory -Force | Out-Null
}

# Create temp directory
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

# Install each package
foreach ($pkg in $Packages) {
    Write-Host "Installing $($pkg.Id) v$($pkg.Version)..." -ForegroundColor Yellow

    $outputDir = Join-Path $PackagesDir "$($pkg.Id).$($pkg.Version)"
    if (Test-Path $outputDir) {
        Write-Host "  Already installed: $outputDir" -ForegroundColor Green
        continue
    }

    try {
        & $nugetExe install $pkg.Id -Version $pkg.Version -OutputDirectory $PackagesDir -Source "https://api.nuget.org/v3/index.json" -NonInteractive
        Write-Host "  Installed: $outputDir" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install $($pkg.Id): $($_.Exception.Message)"
        exit 1
    }
}

# Verify assemblies exist
Write-Host "`nVerifying assemblies..." -ForegroundColor Yellow
$allOk = $true
foreach ($pkg in $Packages) {
    $pkgDir = Join-Path $PackagesDir "$($pkg.Id).$($pkg.Version)"
    $dll = Join-Path $pkgDir "lib\net48\$($pkg.Id).dll"
    if (-not (Test-Path $dll)) {
        # Try netstandard2.0
        $dll = Join-Path $pkgDir "lib\netstandard2.0\$($pkg.Id).dll"
    }
    if (Test-Path $dll) {
        Write-Host "  [OK] $dll" -ForegroundColor Green
    }
    else {
        Write-Host "  [MISSING] $dll" -ForegroundColor Red
        $allOk = $false
    }
}

# Cleanup temp
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n========================================" -ForegroundColor Cyan
if ($allOk) {
    Write-Host "  FlaUI installation complete!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
}
else {
    Write-Host "  Some assemblies missing - check output" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Cyan
    exit 1
}
