#Requires -RunAsAdministrator

<#
===============================================================================
Script: Run-WsusUnified.ps1
Purpose: Run service-level auto-fixes and validate WSUS content configuration.
Overview:
  - Executes autofix.ps1 for WSUS + SQL + IIS health checks.
  - Validates WSUS content path configuration (and optionally fixes issues).
Notes:
  - Run as Administrator on the WSUS server.
===============================================================================
.PARAMETER ContentPath
    The correct content path (default: C:\WSUS)
.PARAMETER SqlInstance
    SQL Server instance name (default: .\SQLEXPRESS)
.PARAMETER FixContentIssues
    If specified, automatically fixes any content issues found
.PARAMETER SkipAutoFix
    If specified, skips running autofix.ps1
#>

param(
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS",
    [switch]$FixContentIssues,
    [switch]$SkipAutoFix
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "WSUS Unified Health Check" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Content Path: $ContentPath" -ForegroundColor Gray
Write-Host "SQL Instance: $SqlInstance" -ForegroundColor Gray
Write-Host "Fix Content Issues: $($FixContentIssues.IsPresent)" -ForegroundColor Gray
Write-Host "Skip AutoFix: $($SkipAutoFix.IsPresent)" -ForegroundColor Gray
Write-Host "" 

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$autoFixScript = Join-Path $scriptRoot "autofix.ps1"
$contentCheckScript = Join-Path $scriptRoot "Check-WSUSContent.ps1"

if (-not $SkipAutoFix) {
    if (-not (Test-Path $autoFixScript)) {
        Write-Error "autofix.ps1 not found at $autoFixScript"
        exit 1
    }

    Write-Host "Running auto-fix checks..." -ForegroundColor Yellow
    & $autoFixScript
    Write-Host "" 
}

if (-not (Test-Path $contentCheckScript)) {
    Write-Error "Check-WSUSContent.ps1 not found at $contentCheckScript"
    exit 1
}

Write-Host "Running WSUS content validation..." -ForegroundColor Yellow
$checkArgs = @(
    "-ContentPath", $ContentPath,
    "-SqlInstance", $SqlInstance
)
if ($FixContentIssues) {
    $checkArgs += "-FixIssues"
}

& $contentCheckScript @checkArgs
