<#
.SYNOPSIS
    Builds the WSUS Manager GUI application.

.DESCRIPTION
    Compiles the WPF application and creates a standalone executable.

.PARAMETER Configuration
    Build configuration (Debug or Release). Default: Release

.PARAMETER SelfContained
    If true, includes .NET runtime in output (~150MB). If false, requires .NET 6 installed (~5MB).

.PARAMETER OutputPath
    Output directory for published files. Default: .\publish

.EXAMPLE
    .\Build.ps1

.EXAMPLE
    .\Build.ps1 -Configuration Debug -SelfContained $false
#>

param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [bool]$SelfContained = $true,

    [string]$OutputPath = '.\publish'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== WSUS Manager GUI Build ===" -ForegroundColor Cyan
Write-Host ""

# Check for .NET SDK
try {
    $dotnetVersion = dotnet --version
    Write-Host "[OK] .NET SDK found: $dotnetVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] .NET SDK not found. Install from https://dotnet.microsoft.com/download/dotnet/6.0" -ForegroundColor Red
    exit 1
}

# Clean previous build
if (Test-Path $OutputPath) {
    Write-Host "Cleaning previous build..." -ForegroundColor Yellow
    Remove-Item -Path $OutputPath -Recurse -Force
}

# Restore packages
Write-Host "Restoring packages..." -ForegroundColor Yellow
dotnet restore

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Package restore failed" -ForegroundColor Red
    exit 1
}

# Build
Write-Host "Building ($Configuration)..." -ForegroundColor Yellow
dotnet build -c $Configuration --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Build failed" -ForegroundColor Red
    exit 1
}

# Publish
Write-Host "Publishing..." -ForegroundColor Yellow
$publishArgs = @(
    'publish'
    '-c', $Configuration
    '-r', 'win-x64'
    '--self-contained', $SelfContained.ToString().ToLower()
    '-o', $OutputPath
    '-p:PublishSingleFile=true'
    '-p:IncludeNativeLibrariesForSelfExtract=true'
)

dotnet @publishArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Publish failed" -ForegroundColor Red
    exit 1
}

# Copy modules folder reference
Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Output: $((Resolve-Path $OutputPath).Path)" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run: .\publish\WsusManager.exe" -ForegroundColor White
Write-Host ""

# Show file size
$exe = Get-Item "$OutputPath\WsusManager.exe" -ErrorAction SilentlyContinue
if ($exe) {
    $sizeMB = [math]::Round($exe.Length / 1MB, 2)
    Write-Host "Executable size: $sizeMB MB" -ForegroundColor Gray
}
