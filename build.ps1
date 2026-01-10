# Build WsusManager.exe with icon
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

Import-Module ps2exe -Force

$buildParams = @{
    InputFile = ".\WsusManagementGui.ps1"
    OutputFile = ".\WsusManager.exe"
    IconFile = ".\wsus-icon.ico"
    NoConsole = $true
    RequireAdmin = $false
    Title = "WSUS Manager"
    Description = "WSUS Manager - Modern GUI for Windows Server Update Services"
    Company = "GA-ASI"
    Product = "WSUS Manager"
    Copyright = "Tony Tran, ISSO"
    Version = "3.2.0.0"
    STA = $true
    x64 = $true
}

Write-Host "Building WsusManager.exe..." -ForegroundColor Cyan
Invoke-PS2EXE @buildParams

if (Test-Path ".\WsusManager.exe") {
    $exe = Get-Item ".\WsusManager.exe"
    $sizeMB = [math]::Round($exe.Length / 1MB, 2)
    Write-Host "BUILD SUCCESS: $($exe.FullName) ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
