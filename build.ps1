# Build script for WSUS Manager
# Compiles WsusManagementGui.ps1 to a standalone EXE

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

$Version = "3.2.0"
$ExeName = "WsusManager-$Version.exe"

Write-Host "Building WSUS Manager v$Version..." -ForegroundColor Cyan

# Check for ps2exe
$ps2exe = Get-Module ps2exe -ListAvailable
if (-not $ps2exe) {
    Write-Host "Installing ps2exe module..." -ForegroundColor Yellow
    Install-Module ps2exe -Force -Scope CurrentUser
}

Import-Module ps2exe -Force

# Build parameters
$buildParams = @{
    InputFile = ".\WsusManagementGui.ps1"
    OutputFile = ".\$ExeName"
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
}

Write-Host "Compiling $ExeName..." -ForegroundColor Yellow
Write-Host "  NoConsole: True (GUI mode)" -ForegroundColor Gray
Write-Host "  RequireAdmin: True" -ForegroundColor Gray
Write-Host "  x64: True" -ForegroundColor Gray

Invoke-PS2EXE @buildParams

if (Test-Path ".\$ExeName") {
    $exe = Get-Item ".\$ExeName"
    $sizeMB = [math]::Round($exe.Length / 1MB, 2)
    Write-Host ""
    Write-Host "BUILD SUCCESS!" -ForegroundColor Green
    Write-Host "  Output: $($exe.FullName)" -ForegroundColor Cyan
    Write-Host "  Size: $sizeMB MB" -ForegroundColor Gray

    # Also copy to generic name for backwards compatibility
    Copy-Item ".\$ExeName" ".\WsusManager.exe" -Force
    Write-Host "  Also copied to: WsusManager.exe" -ForegroundColor Gray
} else {
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    exit 1
}
