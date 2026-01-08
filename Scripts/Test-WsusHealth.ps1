#Requires -RunAsAdministrator

<#
===============================================================================
Script: Test-WsusHealth.ps1
Purpose: Comprehensive WSUS health check and repair utility
Overview:
  - Checks SQL Server, WSUS, and IIS services
  - Validates firewall rules
  - Verifies content path permissions and configuration
  - Tests database connectivity
  - Provides optional auto-repair for all issues

Notes:
  - Run as Administrator on the WSUS server
  - Combines functionality of service checks and content validation
  - Uses WsusHealth module for comprehensive diagnostics
===============================================================================

.PARAMETER ContentPath
    WSUS content path to validate (default: C:\WSUS)

.PARAMETER SqlInstance
    SQL Server instance name (default: .\SQLEXPRESS)

.PARAMETER Repair
    Automatically repair all detected issues

.PARAMETER SkipDatabase
    Skip database connectivity checks (faster for service-only checks)

.EXAMPLE
    .\Test-WsusHealth.ps1
    Run health check without repairs

.EXAMPLE
    .\Test-WsusHealth.ps1 -Repair
    Run health check and automatically repair all issues

.EXAMPLE
    .\Test-WsusHealth.ps1 -ContentPath "D:\WSUS" -Repair
    Check and repair with custom content path
#>

[CmdletBinding()]
param(
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS",
    [switch]$Repair,
    [switch]$SkipDatabase
)

# Import required modules
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
Import-Module (Join-Path $modulePath "WsusUtilities.ps1") -Force
Import-Module (Join-Path $modulePath "WsusHealth.ps1") -Force

# Check admin privileges
Test-AdminPrivileges -ExitOnFail $true | Out-Null

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "                    WSUS COMPREHENSIVE HEALTH CHECK" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Content Path: $ContentPath"
Write-Host "  SQL Instance: $SqlInstance"
Write-Host "  Repair Mode: $($Repair.IsPresent)"
Write-Host "  Skip Database: $($SkipDatabase.IsPresent)"
Write-Host ""

# Run health check
if ($Repair) {
    Write-Host "Running health check with AUTO-REPAIR enabled..." -ForegroundColor Yellow
    Write-Host ""

    # Run comprehensive health check first
    $healthCheck = Test-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance -IncludeDatabase:(-not $SkipDatabase)

    Write-Host ""

    # If issues found, attempt repairs
    if ($healthCheck.Overall -ne "Healthy") {
        Write-Host "Issues detected. Attempting automatic repairs..." -ForegroundColor Yellow
        Write-Host ""

        $repairResult = Repair-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance

        Write-Host ""
        Write-Host "Re-running health check to verify repairs..." -ForegroundColor Yellow
        Write-Host ""

        # Re-check health after repairs
        $finalCheck = Test-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance -IncludeDatabase:(-not $SkipDatabase)

        Write-Host ""
        Write-Host "===============================================================================" -ForegroundColor Cyan
        Write-Host "                         FINAL STATUS" -ForegroundColor Cyan
        Write-Host "===============================================================================" -ForegroundColor Cyan

        if ($finalCheck.Overall -eq "Healthy") {
            Write-Host ""
            Write-Host "SUCCESS: All issues have been resolved!" -ForegroundColor Green
            Write-Host ""
        } elseif ($finalCheck.Overall -eq "Degraded") {
            Write-Host ""
            Write-Host "PARTIAL: Some issues remain (non-critical)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Remaining issues:" -ForegroundColor Yellow
            $finalCheck.Issues | ForEach-Object {
                Write-Host "  - $_" -ForegroundColor Yellow
            }
            Write-Host ""
        } else {
            Write-Host ""
            Write-Host "FAILED: Critical issues still present" -ForegroundColor Red
            Write-Host ""
            Write-Host "Remaining issues:" -ForegroundColor Red
            $finalCheck.Issues | ForEach-Object {
                Write-Host "  - $_" -ForegroundColor Red
            }
            Write-Host ""
            Write-Host "Manual intervention may be required." -ForegroundColor Yellow
            Write-Host ""
        }
    } else {
        Write-Host ""
        Write-Host "SUCCESS: System is already healthy, no repairs needed!" -ForegroundColor Green
        Write-Host ""
    }
} else {
    Write-Host "Running health check (read-only mode)..." -ForegroundColor Yellow
    Write-Host ""

    $healthCheck = Test-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance -IncludeDatabase:(-not $SkipDatabase)

    Write-Host ""

    if ($healthCheck.Overall -ne "Healthy") {
        Write-Host "===============================================================================" -ForegroundColor Cyan
        Write-Host "                         RECOMMENDATIONS" -ForegroundColor Cyan
        Write-Host "===============================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "To automatically fix detected issues, run:" -ForegroundColor Yellow
        Write-Host "  .\Test-WsusHealth.ps1 -Repair" -ForegroundColor White
        Write-Host ""

        if ($healthCheck.Issues.Count -gt 0) {
            Write-Host "Issues that can be auto-fixed:" -ForegroundColor Yellow
            $healthCheck.Issues | ForEach-Object {
                Write-Host "  - $_" -ForegroundColor Yellow
            }
            Write-Host ""
        }
    }
}

Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# Return exit code based on health status (use final check if repair was run)
$exitStatus = if ($Repair -and $finalCheck) { $finalCheck.Overall } else { $healthCheck.Overall }
switch ($exitStatus) {
    "Healthy" { exit 0 }
    "Degraded" { exit 1 }
    "Unhealthy" { exit 2 }
    default { exit 3 }
}
