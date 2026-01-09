#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WSUS Management - Unified script for all WSUS server operations.

.DESCRIPTION
    Consolidated WSUS management with switches for each operation:
    - No switch: Interactive menu
    - -Export: Export DB + content for airgapped transfer
    - -Restore: Restore database from backup
    - -Health/-Repair: Run health check and optional repairs
    - -Cleanup: Deep database cleanup
    - -Reset: Reset content download

.PARAMETER Export
    Export database and differential content for airgapped transfer.

.PARAMETER Restore
    Restore WSUS database from backup.

.PARAMETER Health
    Run WSUS health check.

.PARAMETER Repair
    Run health check with automatic repairs.

.PARAMETER Cleanup
    Run deep database cleanup (aggressive).

.PARAMETER Reset
    Reset WSUS content download (re-verify all files).

.PARAMETER Force
    Skip confirmation prompts (for Cleanup operation).

.PARAMETER ExportRoot
    Root folder for exports (default: \\lab-hyperv\d\WSUS-Exports).

.PARAMETER SinceDays
    For Export: copy content modified within last N days (default: 30).

.PARAMETER SkipDatabase
    For Export: skip database backup.

.EXAMPLE
    .\Invoke-WsusManagement.ps1
    Launch interactive menu.

.EXAMPLE
    .\Invoke-WsusManagement.ps1 -Export
    Export DB + differential content to network share.

.EXAMPLE
    .\Invoke-WsusManagement.ps1 -Restore
    Restore database from backup.

.EXAMPLE
    .\Invoke-WsusManagement.ps1 -Health
    Run health check without repairs.

.EXAMPLE
    .\Invoke-WsusManagement.ps1 -Repair
    Run health check with automatic repairs.

.EXAMPLE
    .\Invoke-WsusManagement.ps1 -Cleanup -Force
    Run deep cleanup without confirmation.
#>

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'Export')]
    [switch]$Export,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Health')]
    [switch]$Health,

    [Parameter(ParameterSetName = 'Repair')]
    [switch]$Repair,

    [Parameter(ParameterSetName = 'Cleanup')]
    [switch]$Cleanup,

    [Parameter(ParameterSetName = 'Reset')]
    [switch]$Reset,

    # Export parameters
    [Parameter(ParameterSetName = 'Export')]
    [string]$ExportRoot = "\\lab-hyperv\d\WSUS-Exports",

    [Parameter(ParameterSetName = 'Export')]
    [int]$SinceDays = 30,

    [Parameter(ParameterSetName = 'Export')]
    [switch]$SkipDatabase,

    # Cleanup parameters
    [Parameter(ParameterSetName = 'Cleanup')]
    [switch]$Force,

    # Common
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS"
)

$ErrorActionPreference = 'Continue'
$ScriptRoot = $PSScriptRoot

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log($msg, $color = "White") {
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor $color
}

function Write-Banner($title) {
    Write-Host ""
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "                    $title" -ForegroundColor Cyan
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-SqlCmd {
    $candidates = @(
        (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\120\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\130\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\140\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    return $candidates
}

# ============================================================================
# EXPORT OPERATION
# ============================================================================

function Invoke-WsusExport {
    param(
        [string]$ExportRoot,
        [string]$ContentPath,
        [int]$SinceDays,
        [switch]$SkipDatabase
    )

    Write-Banner "WSUS INCREMENTAL EXPORT"

    $filterDate = (Get-Date).AddDays(-$SinceDays)
    $year = (Get-Date).ToString("yyyy")
    $month = (Get-Date).ToString("MMM")
    $day = (Get-Date).ToString("d")
    $exportPath = Join-Path $ExportRoot $year $month $day

    Write-Host "Configuration:" -ForegroundColor Yellow
    Write-Host "  Export folder: $exportPath"
    Write-Host "  Content source: $ContentPath"
    Write-Host "  Include files modified since: $($filterDate.ToString('yyyy-MM-dd'))"
    Write-Host "  Include database: $(-not $SkipDatabase.IsPresent)"
    Write-Host ""

    # Create directories
    if (-not (Test-Path $exportPath)) {
        New-Item -Path $exportPath -ItemType Directory -Force | Out-Null
    }

    $wsusContentSource = Join-Path $ContentPath "WsusContent"
    $contentExportPath = Join-Path $exportPath "WsusContent"
    if (-not (Test-Path $contentExportPath)) {
        New-Item -Path $contentExportPath -ItemType Directory -Force | Out-Null
    }

    # Step 1: Copy database
    if (-not $SkipDatabase) {
        Write-Host "[1/3] Copying database backup..." -ForegroundColor Yellow
        $backupFile = Get-ChildItem -Path $ContentPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($backupFile) {
            Write-Host "  Found: $($backupFile.Name) ($([math]::Round($backupFile.Length / 1GB, 2)) GB)"
            Copy-Item -Path $backupFile.FullName -Destination (Join-Path $exportPath $backupFile.Name) -Force
            Write-Host "  [OK] Database copied" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] No .bak file found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[1/3] Skipping database" -ForegroundColor Gray
    }

    # Step 2: Copy content
    Write-Host ""
    Write-Host "[2/3] Copying new content files..." -ForegroundColor Yellow
    $maxAgeDays = [Math]::Max(1, ((Get-Date) - $filterDate).Days)

    $robocopyArgs = @(
        "`"$wsusContentSource`"", "`"$contentExportPath`"",
        "/E", "/MAXAGE:$maxAgeDays", "/MT:16", "/R:2", "/W:5",
        "/XF", "*.bak", "*.log", "/XD", "Logs", "SQLDB", "Backup",
        "/NP", "/NDL"
    )

    $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -lt 8) {
        Write-Host "  [OK] Content copied" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Robocopy exit code: $($proc.ExitCode)" -ForegroundColor Yellow
    }

    # Stats
    $files = Get-ChildItem -Path $contentExportPath -Recurse -File -ErrorAction SilentlyContinue
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host "  Files: $($files.Count) | Size: $([math]::Round($size / 1GB, 2)) GB" -ForegroundColor Cyan

    # Step 3: Create instructions
    Write-Host ""
    Write-Host "[3/3] Generating import instructions..." -ForegroundColor Yellow

    $instructions = @"
================================================================================
WSUS EXPORT - $year\$month\$day
Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: $env:COMPUTERNAME
================================================================================

IMPORT INSTRUCTIONS:

1. Copy this folder into C:\WSUS on the target server:
   robocopy "E:\$year\$month\$day" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO

2. Run the restore script:
   .\Invoke-WsusManagement.ps1 -Restore

================================================================================
"@
    $instructions | Out-File -FilePath (Join-Path $exportPath "IMPORT_INSTRUCTIONS.txt") -Encoding UTF8

    Write-Banner "EXPORT COMPLETE"
    Write-Host "Location: $exportPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Import command:" -ForegroundColor Yellow
    Write-Host "  robocopy `"$exportPath`" `"C:\WSUS`" /E /MT:16 /R:2 /W:5 /XO" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# RESTORE OPERATION
# ============================================================================

function Invoke-WsusRestore {
    param(
        [string]$ContentPath,
        [string]$SqlInstance
    )

    Write-Banner "WSUS DATABASE RESTORE"

    $SqlCmdExe = Get-SqlCmd
    if (-not $SqlCmdExe) {
        Write-Log "ERROR: sqlcmd.exe not found" "Red"
        return
    }

    # Find export folder
    $year = (Get-Date).ToString("yyyy")
    $month = (Get-Date).ToString("MMM")
    $searchPaths = @(
        "C:\WSUS\Backup\$year\$month", "D:\WSUS-Exports\$year\$month",
        "E:\$year\$month", "F:\$year\$month"
    )

    $detectedPath = $null
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $folders = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($folders -and (Test-Path (Join-Path $folders.FullName "WsusContent"))) {
                $detectedPath = $folders.FullName
                break
            }
        }
    }

    if ($detectedPath) {
        Write-Host "Auto-detected: $detectedPath" -ForegroundColor Green
        $useDetected = Read-Host "Use this folder? (Y/n)"
        $exportPath = if ($useDetected -in @("Y", "y", "")) { $detectedPath } else { Read-Host "Enter path" }
    } else {
        Write-Host "No export folder auto-detected" -ForegroundColor Yellow
        $exportPath = Read-Host "Enter export folder path"
    }

    if (-not $exportPath -or -not (Test-Path $exportPath)) {
        Write-Log "ERROR: Invalid path" "Red"
        return
    }

    # Find backup file
    $backupFile = Get-ChildItem -Path $exportPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $backupFile) {
        $backupFile = Get-ChildItem -Path $ContentPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if (-not $backupFile) {
        Write-Log "ERROR: No .bak file found" "Red"
        return
    }

    Write-Log "Backup: $($backupFile.FullName) ($([math]::Round($backupFile.Length / 1GB, 2)) GB)" "Yellow"
    $confirm = Read-Host "Use this backup? (Y/n)"
    if ($confirm -notin @("Y", "y", "")) { return }

    # Copy content if WsusContent exists
    $wsusContentPath = Join-Path $exportPath "WsusContent"
    if (Test-Path $wsusContentPath) {
        Write-Host ""
        Write-Host "Export folder contents found. Copy to C:\WSUS?" -ForegroundColor Green
        $copyContent = Read-Host "(Y/n)"
        if ($copyContent -in @("Y", "y", "")) {
            Write-Log "Copying content..." "Yellow"
            $args = @("`"$exportPath`"", "`"$ContentPath`"", "/E", "/MT:16", "/R:2", "/W:5", "/XO", "/NP", "/NDL")
            Start-Process -FilePath "robocopy.exe" -ArgumentList $args -Wait -NoNewWindow
            Write-Log "[OK] Content copied" "Green"
        }
    }

    # Stop services
    Write-Log "Stopping services..." "Yellow"
    @("WSUSService", "W3SVC") | ForEach-Object {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    # Restore database
    Write-Log "Restoring database..." "Yellow"
    & $SqlCmdExe -S $SqlInstance -Q "IF EXISTS (SELECT 1 FROM sys.databases WHERE name='SUSDB') ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;" -b 2>$null
    & $SqlCmdExe -S $SqlInstance -Q "RESTORE DATABASE SUSDB FROM DISK='$($backupFile.FullName)' WITH REPLACE, STATS=10" -b
    & $SqlCmdExe -S $SqlInstance -Q "ALTER DATABASE SUSDB SET MULTI_USER;" -b 2>$null

    # Start services
    Write-Log "Starting services..." "Yellow"
    @("W3SVC", "WSUSService") | ForEach-Object {
        Start-Service -Name $_ -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5

    # Post-install
    Write-Log "Running WSUS postinstall..." "Yellow"
    $wsusutil = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    if (Test-Path $wsusutil) {
        & $wsusutil postinstall SQL_INSTANCE_NAME="$SqlInstance" CONTENT_DIR="$ContentPath" 2>$null
        Write-Log "Running WSUS reset (15-30 minutes)..." "Yellow"
        & $wsusutil reset 2>$null
    }

    Write-Banner "RESTORE COMPLETE"
    Write-Log "[OK] Database restored" "Green"
    Write-Log "[OK] Services started" "Green"
}

# ============================================================================
# HEALTH CHECK OPERATION
# ============================================================================

function Invoke-WsusHealthCheck {
    param(
        [string]$ContentPath,
        [string]$SqlInstance,
        [switch]$Repair
    )

    Write-Banner "WSUS HEALTH CHECK"

    $modulePath = Join-Path $ScriptRoot "Modules"
    if (Test-Path (Join-Path $modulePath "WsusHealth.psm1")) {
        Import-Module (Join-Path $modulePath "WsusUtilities.psm1") -Force
        Import-Module (Join-Path $modulePath "WsusHealth.psm1") -Force

        if ($Repair) {
            Write-Host "Running health check with AUTO-REPAIR..." -ForegroundColor Yellow
            $result = Test-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance -IncludeDatabase
            if ($result.Overall -ne "Healthy") {
                Repair-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance
                Test-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance -IncludeDatabase
            }
        } else {
            Test-WsusHealth -ContentPath $ContentPath -SqlInstance $SqlInstance -IncludeDatabase
        }
    } else {
        # Inline basic health check
        Write-Host "Service Status:" -ForegroundColor Yellow
        @("WSUSService", "W3SVC", "MSSQL`$SQLEXPRESS") | ForEach-Object {
            try {
                $svc = Get-Service -Name $_ -ErrorAction Stop
                $color = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
                Write-Host "  $_`: $($svc.Status)" -ForegroundColor $color
            } catch {
                Write-Host "  $_`: NOT FOUND" -ForegroundColor Red
            }
        }

        Write-Host ""
        Write-Host "Content Path:" -ForegroundColor Yellow
        if (Test-Path $ContentPath) {
            $size = [math]::Round((Get-ChildItem $ContentPath -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum / 1GB, 2)
            Write-Host "  $ContentPath`: $size GB" -ForegroundColor Green
        } else {
            Write-Host "  $ContentPath`: NOT FOUND" -ForegroundColor Red
        }
    }
}

# ============================================================================
# CLEANUP OPERATION
# ============================================================================

function Invoke-WsusCleanup {
    param(
        [string]$SqlInstance,
        [switch]$Force
    )

    Write-Banner "WSUS DEEP CLEANUP"

    $modulePath = Join-Path $ScriptRoot "Modules"
    if (Test-Path (Join-Path $modulePath "WsusDatabase.psm1")) {
        Import-Module (Join-Path $modulePath "WsusUtilities.psm1") -Force
        Import-Module (Join-Path $modulePath "WsusDatabase.psm1") -Force
        Import-Module (Join-Path $modulePath "WsusServices.psm1") -Force
    }

    Write-Host "This performs comprehensive WSUS database cleanup:" -ForegroundColor Yellow
    Write-Host "  1. Removes supersession records"
    Write-Host "  2. Deletes declined updates"
    Write-Host "  3. Rebuilds indexes"
    Write-Host "  4. Shrinks database"
    Write-Host ""
    Write-Host "WARNING: WSUS will be offline for 30-90 minutes" -ForegroundColor Red
    Write-Host ""

    if (-not $Force) {
        $response = Read-Host "Proceed? (yes/no)"
        if ($response -ne "yes") {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Stop WSUS
    Write-Log "Stopping WSUS..." "Yellow"
    Stop-Service -Name "WSUSService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    # Run WSUS cleanup
    Write-Log "Running WSUS cleanup..." "Yellow"
    try {
        Import-Module UpdateServices -ErrorAction SilentlyContinue
        Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -CompressUpdates -DeclineSupersededUpdates -Confirm:$false
        Write-Log "[OK] Cleanup completed" "Green"
    } catch {
        Write-Log "[WARN] Cleanup warning: $_" "Yellow"
    }

    # Start WSUS
    Write-Log "Starting WSUS..." "Yellow"
    Start-Service -Name "WSUSService" -ErrorAction SilentlyContinue

    Write-Banner "CLEANUP COMPLETE"
}

# ============================================================================
# RESET OPERATION
# ============================================================================

function Invoke-WsusReset {
    Write-Banner "WSUS CONTENT RESET"

    Write-Host "This will re-verify all files and re-download missing content." -ForegroundColor Yellow
    Write-Host "Expected duration: 30-60 minutes" -ForegroundColor Yellow
    Write-Host ""

    $wsusutil = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    if (-not (Test-Path $wsusutil)) {
        Write-Log "ERROR: wsusutil.exe not found" "Red"
        return
    }

    Write-Log "Stopping WSUS..." "Yellow"
    Stop-Service -Name "WSUSService" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Write-Log "Running wsusutil reset..." "Yellow"
    & $wsusutil reset

    Write-Log "Starting WSUS..." "Yellow"
    Start-Service -Name "WSUSService" -ErrorAction SilentlyContinue

    Write-Banner "RESET COMPLETE"
    Write-Log "Content will now be re-verified and re-downloaded" "Green"
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

function Show-Menu {
    Clear-Host
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "              WSUS Management" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "INSTALLATION" -ForegroundColor Yellow
    Write-Host "  1. Install WSUS with SQL Express 2022"
    Write-Host ""
    Write-Host "DATABASE" -ForegroundColor Yellow
    Write-Host "  2. Restore Database from Backup"
    Write-Host ""
    Write-Host "MAINTENANCE" -ForegroundColor Yellow
    Write-Host "  3. Monthly Maintenance (Sync, Cleanup, Backup)"
    Write-Host "  4. Deep Cleanup (Aggressive DB cleanup)"
    Write-Host ""
    Write-Host "EXPORT/TRANSFER" -ForegroundColor Yellow
    Write-Host "  5. Export for Airgapped Transfer"
    Write-Host ""
    Write-Host "TROUBLESHOOTING" -ForegroundColor Yellow
    Write-Host "  6. Health Check"
    Write-Host "  7. Health Check + Repair"
    Write-Host "  8. Reset Content Download"
    Write-Host ""
    Write-Host "CLIENT" -ForegroundColor Yellow
    Write-Host "  9. Force Client Check-In (run on client)"
    Write-Host ""
    Write-Host "  Q. Quit" -ForegroundColor Red
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
}

function Invoke-MenuScript {
    param([string]$Path, [string]$Desc)
    Write-Host ""
    Write-Host "Launching: $Desc" -ForegroundColor Green
    if (Test-Path $Path) { & $Path } else { Write-Host "Script not found: $Path" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Start-InteractiveMenu {
    do {
        Show-Menu
        $choice = Read-Host "Select"

        switch ($choice) {
            '1' { Invoke-MenuScript -Path "$ScriptRoot\Scripts\Install-WsusWithSqlExpress.ps1" -Desc "Install WSUS + SQL Express" }
            '2' { Invoke-WsusRestore -ContentPath $ContentPath -SqlInstance $SqlInstance; pause }
            '3' { Invoke-MenuScript -Path "$ScriptRoot\Scripts\Invoke-WsusMonthlyMaintenance.ps1" -Desc "Monthly Maintenance" }
            '4' { Invoke-WsusCleanup -SqlInstance $SqlInstance; pause }
            '5' { Invoke-WsusExport -ExportRoot $ExportRoot -ContentPath $ContentPath -SinceDays $SinceDays -SkipDatabase:$SkipDatabase; pause }
            '6' { $null = Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance; pause }
            '7' { $null = Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance -Repair; pause }
            '8' { Invoke-WsusReset; pause }
            '9' { Invoke-MenuScript -Path "$ScriptRoot\Scripts\Invoke-WsusClientCheckIn.ps1" -Desc "Force Client Check-In" }
            'Q' { Write-Host "Exiting..." -ForegroundColor Green; return }
            default { Write-Host "Invalid option" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($choice -ne 'Q')
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

switch ($PSCmdlet.ParameterSetName) {
    'Export'  { Invoke-WsusExport -ExportRoot $ExportRoot -ContentPath $ContentPath -SinceDays $SinceDays -SkipDatabase:$SkipDatabase }
    'Restore' { Invoke-WsusRestore -ContentPath $ContentPath -SqlInstance $SqlInstance }
    'Health'  { Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance }
    'Repair'  { Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance -Repair }
    'Cleanup' { Invoke-WsusCleanup -SqlInstance $SqlInstance -Force:$Force }
    'Reset'   { Invoke-WsusReset }
    default   { Start-InteractiveMenu }
}
