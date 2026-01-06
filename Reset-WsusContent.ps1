<#
===============================================================================
Script: Reset-WsusContent.ps1
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

# This forces WSUS to re-verify all files and re-download missing ones.
# Use this if content is missing or stuck in a download loop.
Write-Host "Running wsusutil reset..." -ForegroundColor Yellow
Write-Host "This will take 30-60 minutes and re-download all needed content`n" -ForegroundColor Cyan

# Switch to WSUS tools directory so wsusutil is available.
cd "C:\Program Files\Update Services\Tools"

# Stop WSUS service first to avoid file lock issues.
Stop-Service WSUSService
Start-Sleep -Seconds 5

# Reset WSUS - this re-verifies all files and re-downloads missing.
.\wsusutil.exe reset

# Start WSUS service after reset.
Start-Service WSUSService

Write-Host "`nWSUS reset complete - files will now be re-downloaded" -ForegroundColor Green
