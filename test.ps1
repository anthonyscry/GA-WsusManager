# This forces WSUS to re-verify all files and re-download missing ones
Write-Host "Running wsusutil reset..." -ForegroundColor Yellow
Write-Host "This will take 30-60 minutes and re-download all needed content`n" -ForegroundColor Cyan

cd "C:\Program Files\Update Services\Tools"

# Stop WSUS service first
Stop-Service WSUSService
Start-Sleep -Seconds 5

# Reset WSUS - this re-verifies all files and re-downloads missing
.\wsusutil.exe reset

# Start WSUS service
Start-Service WSUSService

Write-Host "`nWSUS reset complete - files will now be re-downloaded" -ForegroundColor Green