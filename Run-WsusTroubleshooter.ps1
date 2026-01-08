#Requires -RunAsAdministrator

<#
===============================================================================
Script: Run-WsusTroubleshooter.ps1
Status: DEPRECATED - This wrapper script is no longer needed.
Purpose: Run the WSUS health check troubleshooter workflow.

DEPRECATION NOTICE:
This script is a thin wrapper that simply calls other scripts. It is
recommended to call those scripts directly instead:

  - For service checks: .\autofix.ps1
  - For content validation: .\Check-WSUSContent.ps1 -FixIssues

This script will be removed in a future version.
===============================================================================
Overview:
  - Runs autofix.ps1 to check/repair WSUS + SQL + IIS services.
  - Validates WSUS content configuration (optionally remediating issues).
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

# DEPRECATION WARNING
Write-Warning @"
=======================================================================
DEPRECATION NOTICE: This script (Run-WsusTroubleshooter.ps1) is deprecated.
Please call the scripts directly instead:
  - For service checks: .\autofix.ps1
  - For content validation: .\Check-WSUSContent.ps1 -FixIssues
This wrapper will be removed in a future version.
=======================================================================
"@

Start-Sleep -Seconds 3

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "WSUS Health Check Troubleshooter" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Content Path: $ContentPath" -ForegroundColor Gray
Write-Host "SQL Instance: $SqlInstance" -ForegroundColor Gray
Write-Host "Fix Content Issues: $($FixContentIssues.IsPresent)" -ForegroundColor Gray
Write-Host "Skip AutoFix: $($SkipAutoFix.IsPresent)" -ForegroundColor Gray
Write-Host "" 

# Resolve script paths relative to this script location.
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$autoFixScript = Join-Path $scriptRoot "autofix.ps1"
$contentCheckScript = Join-Path $scriptRoot "Check-WSUSContent.ps1"

if (-not $SkipAutoFix) {
    # Ensure autofix.ps1 exists before attempting to run it.
    if (-not (Test-Path $autoFixScript)) {
        Write-Error "autofix.ps1 not found at $autoFixScript"
        exit 1
    }

    # Run the service-level WSUS/SQL/IIS health checks and fixes.
    Write-Host "Running auto-fix checks..." -ForegroundColor Yellow
    & $autoFixScript
    Write-Host "" 
}

# Ensure the content validation script exists before running it.
if (-not (Test-Path $contentCheckScript)) {
    Write-Error "Check-WSUSContent.ps1 not found at $contentCheckScript"
    exit 1
}

# Build arguments for the content validation script.
Write-Host "Running WSUS content validation..." -ForegroundColor Yellow
$checkParams = @{
    ContentPath = $ContentPath
    SqlInstance = $SqlInstance
}
if ($FixContentIssues) {
    # Include remediation switch when requested.
    $checkParams.FixIssues = $true
}

# Execute the WSUS content validation (and optional fix).
& $contentCheckScript @checkParams
