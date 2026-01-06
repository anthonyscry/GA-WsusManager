# 1. Import SQL DB
net stop WSUSService
net stop W3SVC
sqlcmd -S .\SQLEXPRESS -Q "RESTORE DATABASE SUSDB FROM DISK='C:\WSUS\SUSDB_20251124.bak' WITH REPLACE"
sqlcmd -S .\SQLEXPRESS -Q "ALTER DATABASE SUSDB SET MULTI_USER;"
net start W3SVC
net start WSUSService
& "C:\Program Files\Update Services\Tools\wsusutil.exe" postinstall SQL_INSTANCE_NAME=".\SQLEXPRESS" CONTENT_DIR="C:\WSUS"
& "C:\Program Files\Update Services\Tools\wsusutil.exe" reset

# 2. WSUS Cleanup
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Importing UpdateServices module..."
Import-Module UpdateServices

try {
    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Running WSUS Cleanup..."
    Invoke-WsusServerCleanup -CleanupObsoleteComputers `
                             -CleanupObsoleteUpdates `
                             -CleanupUnneededContentFiles `
                             -CompressUpdates `
                             -DeclineSupersededUpdates `
                             -DeclineExpiredUpdates

    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WSUS Cleanup completed successfully"
}
catch {
    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - WSUS Cleanup failed: $($_.Exception.Message)"
}


# 3. Check Service Status and SUSDB Size
# Health Check Script for IIS, WSUS, and SQL Express
# Using single quotes for $SQLEXPRESS services

$services = @(
    @{ Name = 'W3SVC'; Display = 'IIS Web Service' },                 
    @{ Name = 'WSUSService'; Display = 'WSUS Service' },              
    @{ Name = 'MSSQL$SQLEXPRESS'; Display = 'SQL Server (SQLEXPRESS)' }, 
    @{ Name = 'MSSQLFDLauncher$SQLEXPRESS'; Display = 'SQL Full-text Filter Daemon (SQLEXPRESS)' }, 
    @{ Name = 'MSSQLLaunchpad$SQLEXPRESS'; Display = 'SQL Server Launchpad (SQLEXPRESS)' }
)

Write-Host "===== Health Check Report =====" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

foreach ($svc in $services) {
    try {
        $status = (Get-Service -Name $svc.Name -ErrorAction Stop).Status
        if ($status -eq 'Running') {
            Write-Host "$($svc.Display): RUNNING" -ForegroundColor Green
        } else {
            Write-Host "$($svc.Display): $status" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$($svc.Display): NOT FOUND" -ForegroundColor Yellow
    }
}

Write-Host "================================" -ForegroundColor Cyan

sqlcmd -S localhost\SQLEXPRESS -E -Q "SELECT CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS DatabaseSizeGB FROM sys.master_files"
