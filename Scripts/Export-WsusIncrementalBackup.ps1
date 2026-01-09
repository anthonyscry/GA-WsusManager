#Requires -RunAsAdministrator

<#
===============================================================================
Script: Export-WsusIncrementalBackup.ps1
Purpose: Export WSUS database and differential content files to a dated folder.
Overview:
  - Creates a dated export folder (e.g., D:\WSUS-Exports\2026\Jan\9_Updates)
  - Copies the SUSDB database backup
  - Uses robocopy to copy only content files modified since a specified date
  - Generates a ready-to-use robocopy command for the destination server
Notes:
  - Run as Administrator on the WSUS server
  - Exports DB + differential content for airgapped server transfers
  - Users copy the export folder to USB/media for import on airgapped servers
===============================================================================
.PARAMETER ExportRoot
    Root folder for exports (default: D:\WSUS-Exports)
.PARAMETER ContentPath
    WSUS content folder (default: C:\WSUS)
.PARAMETER SinceDate
    Only copy content modified on or after this date (default: 30 days ago)
.PARAMETER SinceDays
    Alternative: copy content modified within the last N days (default: 30)
.PARAMETER SkipDatabase
    Skip copying the SUSDB backup file
.PARAMETER DatabasePath
    Path to SUSDB backup file (default: auto-detect newest .bak in C:\WSUS)
.EXAMPLE
    .\Export-WsusIncrementalBackup.ps1
    Export DB + content modified in last 30 days to D:\WSUS-Exports\2026\Jan\9_Updates\
.EXAMPLE
    .\Export-WsusIncrementalBackup.ps1 -SinceDays 7
    Export DB + content modified in the last 7 days
.EXAMPLE
    .\Export-WsusIncrementalBackup.ps1 -SkipDatabase
    Export only differential content (no database)
#>

[CmdletBinding()]
param(
    [string]$ExportRoot = "D:\WSUS-Exports",
    [string]$ContentPath = "C:\WSUS",
    [DateTime]$SinceDate,
    [int]$SinceDays = 30,
    [switch]$SkipDatabase,
    [string]$DatabasePath
)

# Import shared modules
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
if (Test-Path (Join-Path $modulePath "WsusUtilities.ps1")) {
    Import-Module (Join-Path $modulePath "WsusUtilities.ps1") -Force
}

# Helper functions if module not available
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log($msg, $color = "White") {
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "              WSUS INCREMENTAL EXPORT" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# Calculate the date filter
if ($PSBoundParameters.ContainsKey('SinceDate')) {
    $filterDate = $SinceDate
} else {
    $filterDate = (Get-Date).AddDays(-$SinceDays)
}

# Create dated export folder structure (e.g., D:\WSUS-Exports\2026\Jan\9_Updates)
$year = (Get-Date).ToString("yyyy")
$month = (Get-Date).ToString("MMM")
$day = (Get-Date).ToString("d")
$exportFolder = "${day}_Updates"
$exportPath = Join-Path $ExportRoot $year $month $exportFolder

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Export folder: $exportPath"
Write-Host "  Content source: $ContentPath"
Write-Host "  Include files modified since: $($filterDate.ToString('yyyy-MM-dd'))"
Write-Host "  Include database: $(-not $SkipDatabase.IsPresent)"
Write-Host ""

# Create export directories
if (-not (Test-Path $ExportRoot)) {
    Write-Host "Creating export root: $ExportRoot" -ForegroundColor Yellow
    New-Item -Path $ExportRoot -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $exportPath)) {
    Write-Host "Creating export folder: $exportPath" -ForegroundColor Yellow
    New-Item -Path $exportPath -ItemType Directory -Force | Out-Null
}

# Content will be copied to WsusContent subfolder (mirrors C:\WSUS\WsusContent structure)
$wsusContentSource = Join-Path $ContentPath "WsusContent"
$contentExportPath = Join-Path $exportPath "WsusContent"
if (-not (Test-Path $contentExportPath)) {
    New-Item -Path $contentExportPath -ItemType Directory -Force | Out-Null
}

# === STEP 1: Copy Database Backup ===
if (-not $SkipDatabase) {
    Write-Host ""
    Write-Host "[1/3] Copying database backup..." -ForegroundColor Yellow

    # Find database backup
    if ($DatabasePath -and (Test-Path $DatabasePath)) {
        $backupFile = Get-Item $DatabasePath
    } else {
        # Auto-detect newest .bak file
        $backupFile = Get-ChildItem -Path $ContentPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if ($backupFile) {
        Write-Host "  Found backup: $($backupFile.FullName)"
        Write-Host "  Size: $([math]::Round($backupFile.Length / 1GB, 2)) GB"
        Write-Host "  Modified: $($backupFile.LastWriteTime)"

        $destBackup = Join-Path $exportPath $backupFile.Name
        Write-Host "  Copying to: $destBackup"

        Copy-Item -Path $backupFile.FullName -Destination $destBackup -Force
        Write-Host "  [OK] Database backup copied" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] No .bak file found in $ContentPath" -ForegroundColor Yellow
        Write-Host "         Run database backup first or specify -DatabasePath" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[1/3] Skipping database (use without -SkipDatabase to include)" -ForegroundColor Gray
}

# === STEP 2: Copy New Content Files ===
Write-Host ""
Write-Host "[2/3] Copying new content files..." -ForegroundColor Yellow

# Calculate MAXAGE in days for robocopy
$maxAgeDays = ((Get-Date) - $filterDate).Days
if ($maxAgeDays -lt 1) { $maxAgeDays = 1 }

Write-Host "  Using MAXAGE: $maxAgeDays days"

# Build robocopy command for content
# /E = include subdirectories (including empty)
# /MAXAGE:n = only files modified within n days
# /MT:16 = multi-threaded
# /R:2 /W:5 = retry 2 times, wait 5 seconds
# /XF *.bak = exclude database backups from content copy
# /NP = no progress (cleaner output)
# /NDL = no directory list
# /NFL = no file list (use /V for verbose)

$robocopyArgs = @(
    "`"$wsusContentSource`""
    "`"$contentExportPath`""
    "/E"
    "/MAXAGE:$maxAgeDays"
    "/MT:16"
    "/R:2"
    "/W:5"
    "/XF", "*.bak", "*.log"
    "/XD", "Logs", "SQLDB", "Backup"
    "/NP"
    "/NDL"
)

$robocopyCmd = "robocopy $($robocopyArgs -join ' ')"
Write-Host "  Command: $robocopyCmd" -ForegroundColor Gray

# Execute robocopy
$robocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow

# Robocopy exit codes: 0-7 are success/partial, 8+ are errors
if ($robocopyProcess.ExitCode -lt 8) {
    Write-Host "  [OK] Content files copied (exit code: $($robocopyProcess.ExitCode))" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Robocopy reported issues (exit code: $($robocopyProcess.ExitCode))" -ForegroundColor Yellow
}

# Get stats on what was copied
$copiedFiles = Get-ChildItem -Path $contentExportPath -Recurse -File -ErrorAction SilentlyContinue
$totalSize = ($copiedFiles | Measure-Object -Property Length -Sum).Sum
$fileCount = $copiedFiles.Count

Write-Host ""
Write-Host "  Export summary:" -ForegroundColor Cyan
Write-Host "    Files copied: $fileCount"
Write-Host "    Total size: $([math]::Round($totalSize / 1GB, 2)) GB"

# === STEP 3: Generate Import Commands ===
Write-Host ""
Write-Host "[3/3] Generating import commands..." -ForegroundColor Yellow

# Create a readme with import instructions
$exportFolderName = "$year\$month\$exportFolder"
$importInstructions = @"
================================================================================
WSUS EXPORT - $year\$month\$exportFolder
Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: $env:COMPUTERNAME
Content modified since: $($filterDate.ToString('yyyy-MM-dd'))
================================================================================

FILES INCLUDED:
$(if (-not $SkipDatabase -and $backupFile) { "- $($backupFile.Name) : SUSDB database backup`n" })- WsusContent\     : WSUS update files (differential - files from last $SinceDays days)

--------------------------------------------------------------------------------
IMPORT INSTRUCTIONS (on airgapped WSUS server)
--------------------------------------------------------------------------------

STEP 1: Copy this folder to your airgapped server (USB, network, etc.)

STEP 2: Copy entire export folder INTO C:\WSUS (SAFE MERGE - keeps existing files):
        robocopy "E:\$year\$month\$exportFolder" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import.log" /TEE

        Or run the restore script for guided restore:
        .\Scripts\Restore-WsusDatabase.ps1

  RESULT: This copies everything into C:\WSUS:
          - SUSDB.bak -> C:\WSUS\SUSDB.bak
          - WsusContent\ -> C:\WSUS\WsusContent\

  KEY FLAGS:
  - /E    = Copy subdirectories including empty ones
  - /XO   = eXclude Older files (skip if destination is newer) - SAFE MERGE
  - /MT:16 = Multi-threaded (16 threads)

  DO NOT USE /MIR - it will delete files not in the source!

STEP 3: After import, run content reset to verify files:
        .\Scripts\Reset-WsusContentDownload.ps1

================================================================================
"@

$readmePath = Join-Path $exportPath "IMPORT_INSTRUCTIONS.txt"
$importInstructions | Out-File -FilePath $readmePath -Encoding UTF8
Write-Host "  Created: $readmePath" -ForegroundColor Green

# === FINAL SUMMARY ===
Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "                         EXPORT COMPLETE" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Export location: $exportPath" -ForegroundColor Green
Write-Host ""
Write-Host "Contents:" -ForegroundColor Yellow
Get-ChildItem -Path $exportPath | ForEach-Object {
    if ($_.PSIsContainer) {
        $size = (Get-ChildItem -Path $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
        Write-Host "  [DIR]  $($_.Name) ($([math]::Round($size / 1GB, 2)) GB)"
    } else {
        Write-Host "  [FILE] $($_.Name) ($([math]::Round($_.Length / 1GB, 2)) GB)"
    }
}

Write-Host ""
Write-Host "To import on destination server (SAFE MERGE - won't delete existing files):" -ForegroundColor Yellow
Write-Host ""
Write-Host "  robocopy `"$exportPath`" `"C:\WSUS`" /E /MT:16 /R:2 /W:5 /XO /LOG:`"C:\WSUS\Logs\Import.log`" /TEE" -ForegroundColor Cyan
Write-Host ""
Write-Host "This copies the entire export folder INTO C:\WSUS:" -ForegroundColor Gray
Write-Host "  - SUSDB.bak -> C:\WSUS\SUSDB.bak" -ForegroundColor Gray
Write-Host "  - WsusContent\ -> C:\WSUS\WsusContent\" -ForegroundColor Gray
Write-Host ""
Write-Host "See IMPORT_INSTRUCTIONS.txt in the export folder for full details." -ForegroundColor Gray
Write-Host ""
