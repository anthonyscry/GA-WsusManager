#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WSUS Management Launcher - Interactive menu for WSUS administration tasks.

.DESCRIPTION
    Provides a centralized menu-driven interface to all WSUS management scripts:
    - Installation and setup
    - Database operations
    - Maintenance and cleanup
    - Health checks and troubleshooting
    - Client operations

.NOTES
    Run this script on your WSUS server with Administrator privileges.
    For Domain Controller operations, use DomainController\Set-WsusGroupPolicy.ps1 directly.

.EXAMPLE
    .\Invoke-WsusManagement.ps1
    Launches the interactive menu.
#>

[CmdletBinding()]
param()

$ScriptRoot = $PSScriptRoot

function Show-Menu {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "              WSUS Management Launcher" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "INSTALLATION & SETUP" -ForegroundColor Yellow
    Write-Host "  1. Install WSUS with SQL Express 2022"
    Write-Host ""
    Write-Host "DATABASE OPERATIONS" -ForegroundColor Yellow
    Write-Host "  2. Restore WSUS Database from Backup"
    Write-Host ""
    Write-Host "MAINTENANCE & CLEANUP" -ForegroundColor Yellow
    Write-Host "  3. Monthly Maintenance (Sync, Decline, Cleanup, Backup)"
    Write-Host "  4. Deep Cleanup (Ultimate WSUS Cleanup)"
    Write-Host ""
    Write-Host "TROUBLESHOOTING & HEALTH" -ForegroundColor Yellow
    Write-Host "  5. Test WSUS Health (Run Diagnostics & Repairs)"
    Write-Host "  6. Reset WSUS Content Download"
    Write-Host ""
    Write-Host "CLIENT OPERATIONS" -ForegroundColor Yellow
    Write-Host "  7. Force Client Check-In"
    Write-Host ""
    Write-Host "DOMAIN CONTROLLER" -ForegroundColor Yellow
    Write-Host "  8. Configure WSUS GPOs (Run on DC)"
    Write-Host ""
    Write-Host "  Q. Quit" -ForegroundColor Red
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
}

function Invoke-Script {
    param(
        [string]$ScriptPath,
        [string]$Description
    )

    Write-Host ""
    Write-Host "Launching: $Description" -ForegroundColor Green
    Write-Host "Script: $ScriptPath" -ForegroundColor Gray
    Write-Host ""

    if (Test-Path $ScriptPath) {
        & $ScriptPath
    } else {
        Write-Host "ERROR: Script not found at $ScriptPath" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Press any key to return to menu..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-DcInstructions {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "Domain Controller GPO Configuration" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: This script must run on a Domain Controller!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Steps:" -ForegroundColor Green
    Write-Host "  1. Copy the following to your Domain Controller:"
    Write-Host "     - DomainController\Set-WsusGroupPolicy.ps1"
    Write-Host "     - DomainController\WSUS GPOs\ (folder)"
    Write-Host ""
    Write-Host "  2. Run on DC:"
    Write-Host "     .\Set-WsusGroupPolicy.ps1 -WsusServerUrl 'http://YourWsusServer:8530'"
    Write-Host ""
    Write-Host "Current DC script location:" -ForegroundColor Gray
    Write-Host "  $ScriptRoot\DomainController\Set-WsusGroupPolicy.ps1"
    Write-Host ""
    Write-Host "Press any key to return to menu..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        '1' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Install-WsusWithSqlExpress.ps1") `
                         -Description "Install WSUS with SQL Express 2022"
        }
        '2' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Restore-WsusDatabase.ps1") `
                         -Description "Restore WSUS Database from Backup"
        }
        '3' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Invoke-WsusMonthlyMaintenance.ps1") `
                         -Description "Monthly Maintenance"
        }
        '4' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Invoke-WsusDeepCleanup.ps1") `
                         -Description "Deep Cleanup (Ultimate WSUS Cleanup)"
        }
        '5' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Test-WsusHealth.ps1") `
                         -Description "Test WSUS Health"
        }
        '6' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Reset-WsusContentDownload.ps1") `
                         -Description "Reset WSUS Content Download"
        }
        '7' {
            Invoke-Script -ScriptPath (Join-Path $ScriptRoot "Scripts\Invoke-WsusClientCheckIn.ps1") `
                         -Description "Force Client Check-In"
        }
        '8' {
            Show-DcInstructions
        }
        'Q' {
            Write-Host ""
            Write-Host "Exiting..." -ForegroundColor Green
            return
        }
        default {
            Write-Host ""
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne 'Q')
