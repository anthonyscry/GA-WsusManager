#Requires -RunAsAdministrator

<#
===============================================================================
Script: Export-WsusIncrementalBackup.ps1
Purpose: Export WSUS database and only NEW content files to a dated folder.
Overview:
  - Creates a dated export folder (e.g., 8Jan2026_WSUS)
  - Copies the SUSDB backup file
  - Uses robocopy to copy only content files modified since a specified date
  - Generates a ready-to-use robocopy command for the destination server
Notes:
  - Run as Administrator on the WSUS server
  - Content is copied incrementally (only new/changed files)
  - Destination servers can merge without losing existing content
===============================================================================
.PARAMETER ExportRoot
    Root folder for exports (default: D:\WSUS-Exports)
.PARAMETER ContentPath
    WSUS content folder (default: C:\WSUS)
.PARAMETER SinceDate
    Only copy content modified on or after this date (default: 30 days ago)
.PARAMETER SinceDays
    Alternative: copy content modified within the last N days (default: 30)
.PARAMETER IncludeDatabase
    Include the SUSDB backup in the export (default: true)
.PARAMETER DatabasePath
    Path to SUSDB backup file (default: auto-detect newest .bak in C:\WSUS)
.EXAMPLE
    .\Export-WsusIncrementalBackup.ps1
    Export database and content modified in the last 30 days
.EXAMPLE
    .\Export-WsusIncrementalBackup.ps1 -SinceDays 7
    Export only content modified in the last 7 days
.EXAMPLE
    .\Export-WsusIncrementalBackup.ps1 -SinceDate "2026-01-01"
    Export content modified since January 1, 2026
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

# Create dated export folder name (e.g., 8Jan2026_WSUS)
$dateSuffix = (Get-Date).ToString("dMMMyyyy")
$exportFolder = "${dateSuffix}_WSUS"
$exportPath = Join-Path $ExportRoot $exportFolder

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Export folder: $exportPath"
Write-Host "  Content source: $ContentPath"
Write-Host "  Include files modified since: $($filterDate.ToString('yyyy-MM-dd'))"
Write-Host "  Include database: $(-not $SkipDatabase)"
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

# Create content subfolder
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
    Write-Host "[1/3] Skipping database backup (disabled)" -ForegroundColor Gray
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
    "`"$ContentPath`""
    "`"$contentExportPath`""
    "/E"
    "/MAXAGE:$maxAgeDays"
    "/MT:16"
    "/R:2"
    "/W:5"
    "/XF", "*.bak", "*.log"
    "/XD", "Logs", "SQLDB"
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
$importInstructions = @"
================================================================================
WSUS INCREMENTAL EXPORT - $exportFolder
Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: $env:COMPUTERNAME
Content modified since: $($filterDate.ToString('yyyy-MM-dd'))
================================================================================

FILES INCLUDED:
- WsusContent\     : WSUS update files (incremental - new files only)
$(if (-not $SkipDatabase -and $backupFile) { "- $($backupFile.Name) : SUSDB database backup" })

--------------------------------------------------------------------------------
IMPORT INSTRUCTIONS
--------------------------------------------------------------------------------

STEP 1: Copy this export folder to your destination (USB drive, network share, etc.)

STEP 2: On the destination WSUS server, run ONE of these commands:

  OPTION A - Merge content (keeps existing files, adds new ones):
  -------------------------------------------------------------
  robocopy "<SOURCE_PATH>\WsusContent" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import_$(Get-Date -Format 'yyyyMMdd').log" /TEE

  OPTION B - From USB/Apricorn drive (replace E: with your drive letter):
  -----------------------------------------------------------------------
  robocopy "E:\$exportFolder\WsusContent" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import_$(Get-Date -Format 'yyyyMMdd').log" /TEE

  OPTION C - From network share:
  ------------------------------
  robocopy "\\SERVER\Share\$exportFolder\WsusContent" "C:\WSUS" /E /MT:16 /R:2 /W:5 /XO /LOG:"C:\WSUS\Logs\Import_$(Get-Date -Format 'yyyyMMdd').log" /TEE

  KEY FLAGS:
  - /E    = Copy subdirectories including empty ones
  - /XO   = eXclude Older files (skip if destination is newer) - SAFE MERGE
  - /MT:16 = Multi-threaded (16 threads)
  - /LOG + /TEE = Log to file and console

  DO NOT USE /MIR - it will delete files not in the source!

$(if (-not $SkipDatabase -and $backupFile) {
@"
STEP 3: Restore the database (if included):
  Copy $($backupFile.Name) to C:\WSUS on the destination server, then run:
  .\Scripts\Restore-WsusDatabase.ps1
"@
})

STEP 4: After import, run content reset to verify files:
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
Write-Host "  robocopy `"$contentExportPath`" `"C:\WSUS`" /E /MT:16 /R:2 /W:5 /XO /LOG:`"C:\WSUS\Logs\Import.log`" /TEE" -ForegroundColor Cyan
Write-Host ""
Write-Host "See IMPORT_INSTRUCTIONS.txt in the export folder for full details." -ForegroundColor Gray
Write-Host ""
