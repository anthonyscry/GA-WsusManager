#Requires -Version 5.1
<#
===============================================================================
Script: Build-WsusGui.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
===============================================================================
.SYNOPSIS
    Compiles WsusManagementGui.ps1 to a portable standalone EXE.

.DESCRIPTION
    Uses PS2EXE module to compile the PowerShell GUI script into a single
    executable file that can run without PowerShell installation.

.EXAMPLE
    .\Build-WsusGui.ps1
    Compiles to WsusManagement.exe in the current directory.

.EXAMPLE
    .\Build-WsusGui.ps1 -OutputPath "C:\Tools\WsusGui.exe"
    Compiles to specified path.

.NOTES
    Requires internet access on first run to install PS2EXE module.
#>

param(
    [string]$OutputPath = ".\WsusManagement.exe",
    [switch]$NoConsole,
    [switch]$RequireAdmin
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WSUS GUI Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for PS2EXE module
Write-Host "Checking for PS2EXE module..." -ForegroundColor Yellow
$ps2exe = Get-Module -ListAvailable -Name ps2exe

if (-not $ps2exe) {
    Write-Host "PS2EXE not found. Installing..." -ForegroundColor Yellow

    # Check if running as admin for module installation
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Installing PS2EXE for current user..." -ForegroundColor Gray
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    } else {
        Install-Module -Name ps2exe -Force -AllowClobber
    }

    Write-Host "PS2EXE installed successfully!" -ForegroundColor Green
}

Import-Module ps2exe -Force

# Source script
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$sourceScript = Join-Path $ScriptRoot "WsusManagementGui.ps1"

if (-not (Test-Path $sourceScript)) {
    Write-Host "ERROR: Source script not found: $sourceScript" -ForegroundColor Red
    exit 1
}

# Resolve output path
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $ScriptRoot $OutputPath
}

Write-Host ""
Write-Host "Build Configuration:" -ForegroundColor Yellow
Write-Host "  Source: $sourceScript" -ForegroundColor Gray
Write-Host "  Output: $OutputPath" -ForegroundColor Gray
Write-Host "  Console: $(if ($NoConsole) { 'Hidden' } else { 'Visible' })" -ForegroundColor Gray
Write-Host "  Require Admin: $RequireAdmin" -ForegroundColor Gray
Write-Host ""

# Build parameters
$buildParams = @{
    InputFile = $sourceScript
    OutputFile = $OutputPath
    NoConsole = $NoConsole
    RequireAdmin = $RequireAdmin
    Title = "WSUS Management"
    Description = "WSUS Management GUI - Windows Server Update Services Administration"
    Company = "GA-ASI"
    Product = "WSUS Management Suite"
    Copyright = "Tony Tran, ISSO"
    Version = "3.2.0.0"
    STA = $true
    MTA = $false
    ThreadApartment = 'STA'
    x64 = $true
}

Write-Host "Compiling to EXE..." -ForegroundColor Yellow

try {
    Invoke-PS2EXE @buildParams

    if (Test-Path $OutputPath) {
        $fileInfo = Get-Item $OutputPath
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  BUILD SUCCESSFUL!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Output: $OutputPath" -ForegroundColor Cyan
        Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  Double-click WsusManagement.exe to run" -ForegroundColor Gray
        Write-Host "  Right-click > Run as Administrator for full functionality" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "ERROR: Output file not created!" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Build failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
