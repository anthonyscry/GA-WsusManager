#Requires -RunAsAdministrator

<#
===============================================================================
Script: Reset-WsusContentDownload.ps1
Purpose: Force WSUS to re-verify content and re-download missing files.
Overview:
  - Stops WSUS service to avoid file lock issues.
  - Runs wsusutil.exe reset to re-check content integrity.
  - Starts WSUS service after the reset completes.
Notes:
  - Run as Administrator on the WSUS server.
  - This operation is heavy and can take 30-60 minutes.
===============================================================================
#>

[CmdletBinding()]
param()

# Import shared modules
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
Import-Module (Join-Path $modulePath "WsusUtilities.ps1") -Force
Import-Module (Join-Path $modulePath "WsusServices.ps1") -Force

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "           WSUS Content Reset" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will re-verify all files and re-download missing content." -ForegroundColor Yellow
Write-Host "Expected duration: 30-60 minutes" -ForegroundColor Yellow
Write-Host ""

$wsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"

if (-not (Test-Path $wsusUtilPath)) {
    Write-Host "[ERROR] wsusutil.exe not found at: $wsusUtilPath" -ForegroundColor Red
    Write-Host "        WSUS may not be installed correctly." -ForegroundColor Red
    exit 1
}

# Stop WSUS service first to avoid file lock issues
Write-Host "[1/3] Stopping WSUS Service..." -ForegroundColor Yellow
if (-not (Stop-WsusServer -Force)) {
    Write-Host "[ERROR] Failed to stop WSUS service" -ForegroundColor Red
    exit 1
}
Write-Host "      WSUS Service stopped" -ForegroundColor Green

# Run reset command
Write-Host ""
Write-Host "[2/3] Running wsusutil reset..." -ForegroundColor Yellow
Write-Host "      This re-verifies all files and re-downloads missing content." -ForegroundColor Gray
Write-Host ""

try {
    $resetProcess = Start-Process $wsusUtilPath -ArgumentList "reset" -Wait -PassThru -NoNewWindow

    if ($resetProcess.ExitCode -eq 0) {
        Write-Host "      Reset completed successfully" -ForegroundColor Green
    } else {
        Write-Host "[WARN] wsusutil reset exited with code: $($resetProcess.ExitCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[ERROR] Reset failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Start WSUS service after reset
Write-Host ""
Write-Host "[3/3] Starting WSUS Service..." -ForegroundColor Yellow
if (Start-WsusServer) {
    Write-Host "      WSUS Service started" -ForegroundColor Green
} else {
    Write-Host "[WARN] Failed to start WSUS service - start manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "WSUS content reset complete - files will now be re-downloaded" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""
