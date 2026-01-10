#Requires -RunAsAdministrator

<#
===============================================================================
Script: Invoke-WsusManagement.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 3.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS Management - Unified script for all WSUS server operations.

.DESCRIPTION
    Consolidated WSUS management with switches for each operation:
    - No switch: Interactive menu
    - -Restore: Restore database from backup
    - -Health/-Repair: Run health check and optional repairs
    - -Cleanup: Deep database cleanup
    - -Reset: Reset content download

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

    # Cleanup parameters
    [Parameter(ParameterSetName = 'Cleanup')]
    [switch]$Force,

    # Common
    [string]$ExportRoot = "\\lab-hyperv\d\WSUS-Exports",
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS"
)

$ErrorActionPreference = 'Continue'

# Determine the project root and scripts folder
# Handle multiple deployment scenarios:
# 1. Standard: Invoke-WsusManagement.ps1 at root, subscripts in Scripts\ subfolder
# 2. Flat: All scripts in same folder (user copied main script into Scripts folder)
# 3. Nested: Script in Scripts\Scripts\ folder
$ScriptRoot = $PSScriptRoot
$ScriptsFolder = $PSScriptRoot

# Check flat layout FIRST (scripts in same folder as main script)
# This prevents double-Scripts path issue when running from Scripts folder
if (Test-Path (Join-Path $PSScriptRoot "Invoke-WsusMonthlyMaintenance.ps1")) {
    # Flat layout - all scripts in same folder (or user is running from Scripts folder)
    $ScriptsFolder = $PSScriptRoot
} elseif (Test-Path (Join-Path $PSScriptRoot "Scripts\Invoke-WsusMonthlyMaintenance.ps1")) {
    # Standard layout - scripts are in Scripts\ subfolder
    $ScriptsFolder = Join-Path $PSScriptRoot "Scripts"
}

# Find modules folder - search multiple locations for flexibility
$ModulesFolder = $null
$moduleSearchPaths = @(
    (Join-Path $PSScriptRoot "Modules"),                                    # Standard (root\Modules)
    (Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"),               # Parent folder
    (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "Modules")  # Grandparent (nested)
)

foreach ($path in $moduleSearchPaths) {
    if (Test-Path (Join-Path $path "WsusUtilities.psm1")) {
        $ModulesFolder = $path
        break
    }
}

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

    # Find newest .bak file in C:\WSUS
    Write-Host "Searching for database backups in $ContentPath..." -ForegroundColor Yellow
    $backupFiles = Get-ChildItem -Path $ContentPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if (-not $backupFiles -or $backupFiles.Count -eq 0) {
        Write-Log "ERROR: No .bak files found in $ContentPath" "Red"
        return
    }

    # Show available backups
    Write-Host ""
    Write-Host "Available backups:" -ForegroundColor Cyan
    $backupFiles | Select-Object -First 5 | ForEach-Object {
        $age = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays, 1)
        Write-Host "  $($_.Name) - $([math]::Round($_.Length / 1GB, 2)) GB - $($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) ($age days old)"
    }

    $newestBackup = $backupFiles | Select-Object -First 1
    Write-Host ""
    Write-Host "Newest backup: $($newestBackup.Name)" -ForegroundColor Green
    Write-Host "  Size: $([math]::Round($newestBackup.Length / 1GB, 2)) GB"
    Write-Host "  Date: $($newestBackup.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
    Write-Host ""

    $confirm = Read-Host "Restore this backup? (Y/n)"
    if ($confirm -notin @("Y", "y", "")) { return }

    # Stop services
    Write-Log "Stopping services..." "Yellow"
    @("WSUSService", "W3SVC") | ForEach-Object {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3

    # Restore database
    Write-Log "Restoring database..." "Yellow"
    & $SqlCmdExe -S $SqlInstance -Q "IF EXISTS (SELECT 1 FROM sys.databases WHERE name='SUSDB') ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;" -b 2>$null
    & $SqlCmdExe -S $SqlInstance -Q "RESTORE DATABASE SUSDB FROM DISK='$($newestBackup.FullName)' WITH REPLACE, STATS=10" -b
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
# COPY FOR AIR-GAP OPERATION
# ============================================================================

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    return [math]::Round($size / 1GB, 2)
}

function Format-SizeDisplay {
    param([decimal]$SizeGB)
    if ($SizeGB -lt 1) {
        return "$([math]::Round($SizeGB * 1024, 0)) MB"
    }
    return "$SizeGB GB"
}

function Copy-ToDestination {
    param(
        [string]$SourceFolder,
        [string]$Destination,
        [switch]$IncludeDatabase,
        [switch]$IncludeContent
    )

    # Create destination if needed
    if (-not (Test-Path $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }

    $step = 1
    $totalSteps = ([int]$IncludeDatabase.IsPresent + [int]$IncludeContent.IsPresent)

    # Copy database file(s)
    if ($IncludeDatabase) {
        Write-Log "[$step/$totalSteps] Copying database backup..." "Yellow"
        $bakFiles = Get-ChildItem -Path $SourceFolder -Filter "*.bak" -File -ErrorAction SilentlyContinue
        foreach ($bak in $bakFiles) {
            $destBakPath = Join-Path $Destination $bak.Name
            Copy-Item -Path $bak.FullName -Destination $destBakPath -Force
            Write-Host "  Copied: $($bak.Name) ($(Format-SizeDisplay ([math]::Round($bak.Length / 1GB, 2))))" -ForegroundColor Cyan
        }
        Write-Log "[OK] Database copied" "Green"
        $step++
    }

    # Differential copy of content using robocopy
    if ($IncludeContent) {
        $wsusContentSource = Join-Path $SourceFolder "WsusContent"
        if (Test-Path $wsusContentSource) {
            Write-Log "[$step/$totalSteps] Differential copy of content (this may take a while)..." "Yellow"
            $destContent = Join-Path $Destination "WsusContent"

            # /E = include subdirs, /XO = exclude older files, /MT:16 = 16 threads
            $robocopyArgs = @(
                "`"$wsusContentSource`"", "`"$destContent`"",
                "/E", "/XO", "/MT:16", "/R:2", "/W:5", "/NP", "/NDL"
            )

            $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -lt 8) {
                Write-Log "[OK] Content copied" "Green"
            } else {
                Write-Log "[WARN] Robocopy exit code: $($proc.ExitCode)" "Yellow"
            }

            # Show stats
            $destFiles = Get-ChildItem -Path $destContent -Recurse -File -ErrorAction SilentlyContinue
            $destSize = [math]::Round(($destFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
            Write-Host "  Destination content: $($destFiles.Count) files ($(Format-SizeDisplay $destSize))" -ForegroundColor Cyan
        } else {
            Write-Log "[$step/$totalSteps] No WsusContent folder in source" "Yellow"
        }
    }
}

function Select-Destination {
    param([string]$DefaultPath)

    Write-Host ""
    Write-Host "Destination options:" -ForegroundColor Yellow
    Write-Host "  1. $DefaultPath (default)"
    Write-Host "  2. Custom path"
    Write-Host ""
    $destChoice = Read-Host "Select destination (1/2)"

    $destination = if ($destChoice -eq "2") {
        Read-Host "Enter destination path"
    } else {
        $DefaultPath
    }

    if (-not $destination) {
        Write-Log "ERROR: No destination specified" "Red"
        return $null
    }

    return $destination
}

function Invoke-FullCopy {
    param(
        [string]$ExportSource,
        [string]$ContentPath
    )

    Write-Banner "FULL COPY - LATEST EXPORT"

    # Check for root-level database
    $rootBak = Get-ChildItem -Path $ExportSource -Filter "*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $rootContent = Join-Path $ExportSource "WsusContent"
    $hasRootContent = Test-Path $rootContent

    if (-not $rootBak -and -not $hasRootContent) {
        Write-Host "No database or content found in root folder." -ForegroundColor Yellow
        Write-Host "Looking for newest backup in archive..." -ForegroundColor Yellow
        Write-Host ""

        # Fall back to finding newest in archive
        $archiveBak = Get-ChildItem -Path $ExportSource -Filter "*.bak" -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($archiveBak) {
            $ExportSource = $archiveBak.DirectoryName
            $rootBak = $archiveBak
            $rootContent = Join-Path $ExportSource "WsusContent"
            $hasRootContent = Test-Path $rootContent
        } else {
            Write-Log "ERROR: No backups found anywhere in $ExportSource" "Red"
            return
        }
    }

    Write-Host "Source: $ExportSource" -ForegroundColor Cyan
    Write-Host ""

    if ($rootBak) {
        Write-Host "Database:" -ForegroundColor Yellow
        Write-Host "  $($rootBak.Name) ($(Format-SizeDisplay ([math]::Round($rootBak.Length / 1GB, 2))))"
        Write-Host "  Modified: $($rootBak.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
    }

    if ($hasRootContent) {
        $contentSize = Get-FolderSize $rootContent
        $contentFiles = (Get-ChildItem -Path $rootContent -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host ""
        Write-Host "Content:" -ForegroundColor Yellow
        Write-Host "  $contentFiles files ($(Format-SizeDisplay $contentSize))"
    }

    $destination = Select-Destination -DefaultPath $ContentPath
    if (-not $destination) { return }

    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Yellow
    Write-Host "  Source: $ExportSource"
    Write-Host "  Destination: $destination"
    Write-Host "  Mode: Differential copy (only newer/missing files)"
    Write-Host ""

    $confirm = Read-Host "Proceed with copy? (Y/n)"
    if ($confirm -notin @("Y", "y", "")) { return }

    Copy-ToDestination -SourceFolder $ExportSource -Destination $destination `
        -IncludeDatabase:($null -ne $rootBak) -IncludeContent:$hasRootContent

    Write-Banner "COPY COMPLETE"
    Write-Host "Files copied to: $destination" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step: Run option 2 (Restore Database) to restore the database" -ForegroundColor Yellow
}

function Invoke-BrowseArchive {
    param(
        [string]$ExportSource,
        [string]$ContentPath
    )

    $archivePath = Join-Path $ExportSource "Archive"
    $searchPath = if (Test-Path $archivePath) { $archivePath } else { $ExportSource }

    # YEAR SELECTION
    :yearLoop while ($true) {
        Clear-Host
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "              BROWSE ARCHIVE - SELECT YEAR" -ForegroundColor Cyan
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host ""

        $years = Get-ChildItem -Path $searchPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}$' } |
            Sort-Object Name -Descending

        if (-not $years -or $years.Count -eq 0) {
            Write-Host "No year folders found in $searchPath" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Expected structure:" -ForegroundColor Gray
            Write-Host "  $searchPath\2026\Jan\9\" -ForegroundColor Gray
            Write-Host ""
            Read-Host "Press Enter to go back"
            return
        }

        $i = 1
        foreach ($year in $years) {
            $backupCount = (Get-ChildItem -Path $year.FullName -Filter "*.bak" -File -Recurse -ErrorAction SilentlyContinue).Count
            Write-Host "  [$i] $($year.Name) ($backupCount backups)" -ForegroundColor White
            $i++
        }

        Write-Host ""
        Write-Host "  [B] Back" -ForegroundColor Red
        Write-Host ""

        $yearChoice = Read-Host "Select year"
        if ($yearChoice -eq 'B' -or $yearChoice -eq 'b') { return }

        $yearIndex = 0
        if ([int]::TryParse($yearChoice, [ref]$yearIndex) -and $yearIndex -ge 1 -and $yearIndex -le $years.Count) {
            $selectedYear = $years[$yearIndex - 1]

            # MONTH SELECTION
            :monthLoop while ($true) {
                Clear-Host
                Write-Host "=================================================================" -ForegroundColor Cyan
                Write-Host "              BROWSE ARCHIVE - SELECT MONTH ($($selectedYear.Name))" -ForegroundColor Cyan
                Write-Host "=================================================================" -ForegroundColor Cyan
                Write-Host ""

                $months = Get-ChildItem -Path $selectedYear.FullName -Directory -ErrorAction SilentlyContinue |
                    Sort-Object {
                        # Sort by month number or alphabetically
                        $monthNames = @{Jan=1;Feb=2;Mar=3;Apr=4;May=5;Jun=6;Jul=7;Aug=8;Sep=9;Oct=10;Nov=11;Dec=12}
                        if ($monthNames.ContainsKey($_.Name)) { $monthNames[$_.Name] }
                        elseif ($_.Name -match '^\d+$') { [int]$_.Name }
                        else { 99 }
                    }

                if (-not $months -or $months.Count -eq 0) {
                    Write-Host "No month folders found in $($selectedYear.FullName)" -ForegroundColor Yellow
                    Read-Host "Press Enter to go back"
                    continue yearLoop
                }

                $i = 1
                foreach ($month in $months) {
                    $backupCount = (Get-ChildItem -Path $month.FullName -Filter "*.bak" -File -Recurse -ErrorAction SilentlyContinue).Count
                    Write-Host "  [$i] $($month.Name) ($backupCount backups)" -ForegroundColor White
                    $i++
                }

                Write-Host ""
                Write-Host "  [B] Back" -ForegroundColor Red
                Write-Host ""

                $monthChoice = Read-Host "Select month"
                if ($monthChoice -eq 'B' -or $monthChoice -eq 'b') { continue yearLoop }

                $monthIndex = 0
                if ([int]::TryParse($monthChoice, [ref]$monthIndex) -and $monthIndex -ge 1 -and $monthIndex -le $months.Count) {
                    $selectedMonth = $months[$monthIndex - 1]

                    # BACKUP SELECTION
                    :backupLoop while ($true) {
                        Clear-Host
                        Write-Host "=================================================================" -ForegroundColor Cyan
                        Write-Host "       SELECT BACKUP ($($selectedYear.Name) / $($selectedMonth.Name))" -ForegroundColor Cyan
                        Write-Host "=================================================================" -ForegroundColor Cyan
                        Write-Host ""

                        # Find all backup folders (contain .bak files) or day folders
                        $backupFolders = @()

                        # Check for direct backup folders (FULL_YYYYMMDD, DIFF_YYYYMMDD)
                        $directBackups = Get-ChildItem -Path $selectedMonth.FullName -Directory -ErrorAction SilentlyContinue |
                            Where-Object {
                                (Get-ChildItem -Path $_.FullName -Filter "*.bak" -File -ErrorAction SilentlyContinue).Count -gt 0
                            }

                        if ($directBackups) {
                            $backupFolders += $directBackups
                        }

                        # Also check for day subfolders (1, 2, 3... or 01, 02, 03...)
                        $dayFolders = Get-ChildItem -Path $selectedMonth.FullName -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match '^\d+$' }

                        foreach ($day in $dayFolders) {
                            $dayBackups = Get-ChildItem -Path $day.FullName -Directory -ErrorAction SilentlyContinue |
                                Where-Object {
                                    (Get-ChildItem -Path $_.FullName -Filter "*.bak" -File -ErrorAction SilentlyContinue).Count -gt 0
                                }
                            if ($dayBackups) {
                                $backupFolders += $dayBackups
                            }
                            # Also check if the day folder itself contains backups
                            if ((Get-ChildItem -Path $day.FullName -Filter "*.bak" -File -ErrorAction SilentlyContinue).Count -gt 0) {
                                $backupFolders += $day
                            }
                        }

                        # Remove duplicates and sort
                        $backupFolders = $backupFolders | Sort-Object FullName -Unique | Sort-Object Name -Descending

                        if (-not $backupFolders -or $backupFolders.Count -eq 0) {
                            Write-Host "No backups found in $($selectedMonth.FullName)" -ForegroundColor Yellow
                            Read-Host "Press Enter to go back"
                            continue monthLoop
                        }

                        $i = 1
                        $backupInfo = @()
                        foreach ($backup in $backupFolders) {
                            $bakFile = Get-ChildItem -Path $backup.FullName -Filter "*.bak" -File -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                            $contentPath = Join-Path $backup.FullName "WsusContent"
                            $hasContent = Test-Path $contentPath

                            $totalSize = 0
                            if ($bakFile) { $totalSize += $bakFile.Length }
                            if ($hasContent) { $totalSize += (Get-FolderSize $contentPath) * 1GB }
                            $sizeDisplay = Format-SizeDisplay ([math]::Round($totalSize / 1GB, 2))

                            $type = if ($backup.Name -like "FULL*") { "FULL" }
                                    elseif ($backup.Name -like "DIFF*") { "DIFF" }
                                    else { "    " }

                            $contentMarker = if ($hasContent) { "+ Content" } else { "DB only" }

                            Write-Host "  [$i] $($backup.Name) ($sizeDisplay) - $type $contentMarker" -ForegroundColor White
                            $backupInfo += @{
                                Folder = $backup
                                BakFile = $bakFile
                                HasContent = $hasContent
                            }
                            $i++
                        }

                        Write-Host ""
                        Write-Host "  [A] Copy ALL backups listed above" -ForegroundColor Green
                        Write-Host "  [B] Back" -ForegroundColor Red
                        Write-Host ""

                        $backupChoice = Read-Host "Select backup"
                        if ($backupChoice -eq 'B' -or $backupChoice -eq 'b') { continue monthLoop }

                        if ($backupChoice -eq 'A' -or $backupChoice -eq 'a') {
                            # Copy all backups
                            $destination = Select-Destination -DefaultPath $ContentPath
                            if (-not $destination) { continue backupLoop }

                            Write-Host ""
                            Write-Host "Will copy $($backupFolders.Count) backup(s) to: $destination" -ForegroundColor Yellow
                            $confirm = Read-Host "Proceed? (Y/n)"
                            if ($confirm -notin @("Y", "y", "")) { continue backupLoop }

                            foreach ($info in $backupInfo) {
                                Write-Host ""
                                Write-Host "Copying: $($info.Folder.Name)" -ForegroundColor Cyan
                                Copy-ToDestination -SourceFolder $info.Folder.FullName -Destination $destination `
                                    -IncludeDatabase:($null -ne $info.BakFile) -IncludeContent:$info.HasContent
                            }

                            Write-Banner "COPY COMPLETE"
                            Write-Host "All backups copied to: $destination" -ForegroundColor Green
                            Write-Host ""
                            Write-Host "Next step: Run option 2 (Restore Database) to restore the database" -ForegroundColor Yellow
                            Read-Host "Press Enter to continue"
                            return
                        }

                        $backupIndex = 0
                        if ([int]::TryParse($backupChoice, [ref]$backupIndex) -and $backupIndex -ge 1 -and $backupIndex -le $backupFolders.Count) {
                            $selected = $backupInfo[$backupIndex - 1]

                            # Show details and confirm
                            Clear-Host
                            Write-Banner "COPY: $($selected.Folder.Name)"

                            Write-Host "Source: $($selected.Folder.FullName)" -ForegroundColor Cyan
                            Write-Host ""

                            if ($selected.BakFile) {
                                Write-Host "Database:" -ForegroundColor Yellow
                                Write-Host "  $($selected.BakFile.Name) ($(Format-SizeDisplay ([math]::Round($selected.BakFile.Length / 1GB, 2))))"
                            }

                            if ($selected.HasContent) {
                                $contentPath = Join-Path $selected.Folder.FullName "WsusContent"
                                $contentSize = Get-FolderSize $contentPath
                                Write-Host ""
                                Write-Host "Content:" -ForegroundColor Yellow
                                Write-Host "  $(Format-SizeDisplay $contentSize)"
                            }

                            $destination = Select-Destination -DefaultPath $ContentPath
                            if (-not $destination) { continue backupLoop }

                            Write-Host ""
                            $confirm = Read-Host "Proceed with copy? (Y/n)"
                            if ($confirm -notin @("Y", "y", "")) { continue backupLoop }

                            Copy-ToDestination -SourceFolder $selected.Folder.FullName -Destination $destination `
                                -IncludeDatabase:($null -ne $selected.BakFile) -IncludeContent:$selected.HasContent

                            Write-Banner "COPY COMPLETE"
                            Write-Host "Files copied to: $destination" -ForegroundColor Green
                            Write-Host ""
                            Write-Host "Next step: Run option 2 (Restore Database) to restore the database" -ForegroundColor Yellow
                            Read-Host "Press Enter to continue"
                            return
                        }
                    }
                }
            }
        }
    }
}

function Invoke-CopyForAirGap {
    <#
    .SYNOPSIS
        Import WSUS data from external media (Apricorn, optical, USB) to air-gap server
    .DESCRIPTION
        Prompts for source path (where external media is mounted) and copies to local WSUS
    #>
    param(
        [string]$DefaultSource = "\\lab-hyperv\d\WSUS-Exports",
        [string]$ContentPath
    )

    Write-Banner "IMPORT FROM EXTERNAL MEDIA"

    Write-Host "This will import WSUS data from external media to this server." -ForegroundColor Yellow
    Write-Host "Use this on the AIR-GAP server to import transported data." -ForegroundColor Yellow
    Write-Host ""

    # Prompt for source path
    Write-Host "Where is the external media mounted?" -ForegroundColor Cyan
    Write-Host "  Examples: E:\  D:\WSUS-Transfer  F:\AirGap" -ForegroundColor Gray
    Write-Host "  Or press Enter for network share: $DefaultSource" -ForegroundColor Gray
    Write-Host ""
    $sourceInput = Read-Host "Enter source path (or press Enter for default)"

    $ExportSource = if ($sourceInput) { $sourceInput } else { $DefaultSource }

    # Check if source is accessible
    if (-not (Test-Path $ExportSource)) {
        Write-Log "ERROR: Cannot access $ExportSource" "Red"
        Write-Host "Make sure the path exists and media is connected." -ForegroundColor Yellow
        return
    }

    :mainLoop while ($true) {
        Clear-Host
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "              IMPORT FROM EXTERNAL MEDIA" -ForegroundColor Cyan
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Source: $ExportSource" -ForegroundColor Gray
        Write-Host ""

        # Check what's available
        $rootBak = Get-ChildItem -Path $ExportSource -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $rootContent = Join-Path $ExportSource "WsusContent"
        $hasRootContent = Test-Path $rootContent

        if ($rootBak -or $hasRootContent) {
            $rootInfo = ""
            if ($rootBak) {
                $rootInfo += "DB: $($rootBak.LastWriteTime.ToString('yyyy-MM-dd'))"
            }
            if ($hasRootContent) {
                $contentSize = Get-FolderSize $rootContent
                if ($rootInfo) { $rootInfo += ", " }
                $rootInfo += "Content: $(Format-SizeDisplay $contentSize)"
            }
            Write-Host "[F] Full Copy - Import from root ($rootInfo)" -ForegroundColor White
        } else {
            Write-Host "[F] Full Copy - Search for newest backup" -ForegroundColor White
        }

        Write-Host "[B] Browse Archive - Navigate Year/Month folders" -ForegroundColor White
        Write-Host "[C] Change Source Path" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[X] Back to Main Menu" -ForegroundColor Red
        Write-Host ""

        $choice = Read-Host "Select"

        switch ($choice.ToUpper()) {
            'F' { Invoke-FullCopy -ExportSource $ExportSource -ContentPath $ContentPath; break mainLoop }
            'B' { Invoke-BrowseArchive -ExportSource $ExportSource -ContentPath $ContentPath; break mainLoop }
            'C' {
                Write-Host ""
                $newSource = Read-Host "Enter new source path"
                if ($newSource -and (Test-Path $newSource)) {
                    $ExportSource = $newSource
                } else {
                    Write-Host "Invalid path or not accessible" -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
            'X' { return }
            default { Write-Host "Invalid option" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ============================================================================
# EXPORT TO EXTERNAL MEDIA (FOR AIR-GAP TRANSFER)
# ============================================================================

function Invoke-ExportToDvd {
    <#
    .SYNOPSIS
        Export WSUS data as split zip files for DVD burning
    .DESCRIPTION
        Zips source data and splits into 4.3GB chunks for single-layer DVD burning
    #>
    param(
        [string]$DefaultSource = "\\lab-hyperv\d\WSUS-Exports",
        [string]$ContentPath = "C:\WSUS"
    )

    Write-Banner "EXPORT FOR DVD BURNING"

    # Check for 7-Zip
    $sevenZip = $null
    $sevenZipPaths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        (Get-Command 7z.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )
    foreach ($path in $sevenZipPaths) {
        if ($path -and (Test-Path $path)) {
            $sevenZip = $path
            break
        }
    }

    if (-not $sevenZip) {
        Write-Log "ERROR: 7-Zip not found" "Red"
        Write-Host "Please install 7-Zip from https://www.7-zip.org/" -ForegroundColor Yellow
        Write-Host "Required for creating split archives for DVD burning." -ForegroundColor Yellow
        return
    }

    Write-Host "This will create split zip files sized for single-layer DVDs (4.3GB each)." -ForegroundColor Yellow
    Write-Host ""

    # Prompt for source
    Write-Host "Source options:" -ForegroundColor Cyan
    Write-Host "  1. Network share: $DefaultSource"
    Write-Host "  2. Local WSUS: $ContentPath"
    Write-Host "  3. Custom path"
    Write-Host ""
    $sourceChoice = Read-Host "Select source (1/2/3)"

    $source = switch ($sourceChoice) {
        "1" { $DefaultSource }
        "2" { $ContentPath }
        "3" { Read-Host "Enter source path" }
        default { $DefaultSource }
    }

    if (-not $source -or -not (Test-Path $source)) {
        Write-Log "ERROR: Source path not accessible: $source" "Red"
        return
    }

    # Calculate source size
    Write-Host ""
    Write-Host "Calculating source size..." -ForegroundColor Yellow
    $sourceSize = Get-FolderSize $source
    $estimatedDvds = [math]::Ceiling($sourceSize / 4.3)
    Write-Host "Source: $source" -ForegroundColor Cyan
    Write-Host "  Total size: $(Format-SizeDisplay $sourceSize)"
    Write-Host "  Estimated DVDs needed: $estimatedDvds (4.3GB each)"
    Write-Host ""

    # Prompt for output location
    Write-Host "Output location for zip files:" -ForegroundColor Cyan
    Write-Host "  Example: D:\DVD-Export  C:\Temp\WSUS-DVDs" -ForegroundColor Gray
    Write-Host ""
    $outputPath = Read-Host "Enter output path"

    if (-not $outputPath) {
        Write-Log "ERROR: No output path specified" "Red"
        return
    }

    # Create output if needed
    if (-not (Test-Path $outputPath)) {
        New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
    }

    # Check available space
    $outputDrive = (Get-Item $outputPath).PSDrive
    if ($outputDrive) {
        $freeGB = [math]::Round($outputDrive.Free / 1GB, 2)
        Write-Host "  Available space: $freeGB GB" -ForegroundColor $(if ($freeGB -lt $sourceSize) { "Red" } else { "Green" })
        if ($freeGB -lt $sourceSize) {
            Write-Host "  WARNING: May not have enough space for compressed archive" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    $confirm = Read-Host "Proceed with DVD export? (Y/n)"
    if ($confirm -notin @("Y", "y", "")) { return }

    # Create split archive using 7-Zip
    $archiveName = "WSUS_Export_$(Get-Date -Format 'yyyyMMdd')"
    $archivePath = Join-Path $outputPath "$archiveName.7z"

    Write-Log "Creating split archive (4.3GB volumes)..." "Yellow"
    Write-Host "This may take a while depending on data size..." -ForegroundColor Gray
    Write-Host ""

    # 7z a -v4300m = split into 4300MB volumes
    $args = @(
        "a",                    # add to archive
        "-v4300m",              # split into 4.3GB volumes (DVD size)
        "-mx=1",                # fast compression (speed over size)
        "-mmt=on",              # multi-threading
        "`"$archivePath`"",     # output archive
        "`"$source\*`""         # source files
    )

    $proc = Start-Process -FilePath $sevenZip -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        Write-Log "[OK] Archive created successfully" "Green"
    } else {
        Write-Log "[WARN] 7-Zip exit code: $($proc.ExitCode)" "Yellow"
    }

    # List created files
    Write-Host ""
    Write-Host "Created files:" -ForegroundColor Cyan
    $createdFiles = Get-ChildItem -Path $outputPath -Filter "$archiveName.*" | Sort-Object Name
    $totalParts = $createdFiles.Count
    foreach ($file in $createdFiles) {
        Write-Host "  $($file.Name) ($(Format-SizeDisplay ([math]::Round($file.Length / 1GB, 2))))"
    }

    Write-Banner "DVD EXPORT COMPLETE"
    Write-Host "Output location: $outputPath" -ForegroundColor Green
    Write-Host "Total parts: $totalParts" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Burning instructions:" -ForegroundColor Yellow
    Write-Host "  1. Burn each .7z.001, .7z.002, etc. to separate DVDs"
    Write-Host "  2. Label DVDs: 'WSUS Export $(Get-Date -Format 'yyyy-MM-dd') - Disc N of $totalParts'"
    Write-Host "  3. On air-gap server, copy all parts to one folder"
    Write-Host "  4. Extract with: 7z x $archiveName.7z.001"
    Write-Host "  5. Run option 3 to import the extracted data"
    Write-Host ""
}

function Invoke-ExportToMedia {
    <#
    .SYNOPSIS
        Export WSUS data to external media (Apricorn, optical, USB) for air-gap transfer
    .DESCRIPTION
        Prompts for source and destination, then uses robocopy for fast differential copy
    #>
    param(
        [string]$DefaultSource = "\\lab-hyperv\d\WSUS-Exports",
        [string]$ContentPath = "C:\WSUS"
    )

    Write-Banner "EXPORT TO EXTERNAL MEDIA"

    Write-Host "This will copy WSUS data to external media for air-gap transfer." -ForegroundColor Yellow
    Write-Host "Use this on the ONLINE server to prepare data for transport." -ForegroundColor Yellow
    Write-Host ""

    # Prompt for source
    Write-Host "Source options:" -ForegroundColor Cyan
    Write-Host "  1. Network share: $DefaultSource"
    Write-Host "  2. Local WSUS: $ContentPath"
    Write-Host "  3. Custom path"
    Write-Host ""
    $sourceChoice = Read-Host "Select source (1/2/3)"

    $source = switch ($sourceChoice) {
        "1" { $DefaultSource }
        "2" { $ContentPath }
        "3" { Read-Host "Enter source path" }
        default { $DefaultSource }
    }

    if (-not $source -or -not (Test-Path $source)) {
        Write-Log "ERROR: Source path not accessible: $source" "Red"
        return
    }

    # Check what's in source
    $sourceBak = Get-ChildItem -Path $source -Filter "*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $sourceContent = Join-Path $source "WsusContent"
    $hasContent = Test-Path $sourceContent

    Write-Host ""
    Write-Host "Source: $source" -ForegroundColor Cyan
    if ($sourceBak) {
        Write-Host "  Database: $($sourceBak.Name) ($(Format-SizeDisplay ([math]::Round($sourceBak.Length / 1GB, 2))))"
        Write-Host "  Modified: $($sourceBak.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
    } else {
        Write-Host "  Database: None found" -ForegroundColor Yellow
    }
    if ($hasContent) {
        $contentSize = Get-FolderSize $sourceContent
        $contentFiles = (Get-ChildItem -Path $sourceContent -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host "  Content: $contentFiles files ($(Format-SizeDisplay $contentSize))"
    } else {
        Write-Host "  Content: None found" -ForegroundColor Yellow
    }
    Write-Host ""

    # Prompt for destination
    Write-Host "Destination (external media path):" -ForegroundColor Cyan
    Write-Host "  Examples: E:\  D:\WSUS-Transfer  F:\AirGap" -ForegroundColor Gray
    Write-Host ""
    $destination = Read-Host "Enter destination path"

    if (-not $destination) {
        Write-Log "ERROR: No destination specified" "Red"
        return
    }

    # Create destination if needed
    if (-not (Test-Path $destination)) {
        Write-Host "Creating destination: $destination" -ForegroundColor Yellow
        try {
            New-Item -Path $destination -ItemType Directory -Force | Out-Null
        } catch {
            Write-Log "ERROR: Cannot create destination: $($_.Exception.Message)" "Red"
            return
        }
    }

    # Show summary
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Yellow
    Write-Host "  Source:      $source"
    Write-Host "  Destination: $destination"
    Write-Host "  Mode:        Differential (only newer/missing files)"
    Write-Host ""

    $confirm = Read-Host "Proceed with export? (Y/n)"
    if ($confirm -notin @("Y", "y", "")) { return }

    # Copy database
    if ($sourceBak) {
        Write-Log "[1/2] Copying database backup..." "Yellow"
        Copy-Item -Path $sourceBak.FullName -Destination $destination -Force
        Write-Log "[OK] Database copied: $($sourceBak.Name)" "Green"
    } else {
        Write-Log "[1/2] No database backup to copy" "Yellow"
    }

    # Copy content using robocopy
    if ($hasContent) {
        Write-Log "[2/2] Copying content (this may take a while)..." "Yellow"
        $destContent = Join-Path $destination "WsusContent"

        # /E = include subdirs, /XO = exclude older, /MT:16 = 16 threads
        $robocopyArgs = @(
            "`"$sourceContent`"", "`"$destContent`"",
            "/E", "/XO", "/MT:16", "/R:2", "/W:5", "/NP", "/NDL"
        )

        $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -lt 8) {
            Write-Log "[OK] Content copied" "Green"
        } else {
            Write-Log "[WARN] Robocopy exit code: $($proc.ExitCode)" "Yellow"
        }

        # Show stats
        $destFiles = Get-ChildItem -Path $destContent -Recurse -File -ErrorAction SilentlyContinue
        $destSize = [math]::Round(($destFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        Write-Host "  Exported: $($destFiles.Count) files ($(Format-SizeDisplay $destSize))" -ForegroundColor Cyan
    } else {
        Write-Log "[2/2] No content folder to copy" "Yellow"
    }

    Write-Banner "EXPORT COMPLETE"
    Write-Host "Data exported to: $destination" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Safely eject the external media"
    Write-Host "  2. Transport to air-gap server"
    Write-Host "  3. On air-gap server, run option 3 (Import from External Media)"
    Write-Host ""
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

    # Use the globally resolved modules folder
    if ($ModulesFolder -and (Test-Path (Join-Path $ModulesFolder "WsusHealth.psm1"))) {
        try {
            Import-Module (Join-Path $ModulesFolder "WsusUtilities.psm1") -Force -ErrorAction Stop
            Import-Module (Join-Path $ModulesFolder "WsusHealth.psm1") -Force -ErrorAction Stop
        } catch {
            Write-Host "Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
            return
        }

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

    # Use the globally resolved modules folder
    if ($ModulesFolder -and (Test-Path (Join-Path $ModulesFolder "WsusDatabase.psm1"))) {
        try {
            Import-Module (Join-Path $ModulesFolder "WsusUtilities.psm1") -Force -ErrorAction Stop
            Import-Module (Join-Path $ModulesFolder "WsusDatabase.psm1") -Force -ErrorAction Stop
            Import-Module (Join-Path $ModulesFolder "WsusServices.psm1") -Force -ErrorAction Stop
        } catch {
            Write-Host "Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
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
    Write-Host "              WSUS Management v3.0.0" -ForegroundColor Cyan
    Write-Host "              Author: Tony Tran, ISSO, GA-ASI" -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "INSTALLATION" -ForegroundColor Yellow
    Write-Host "  1. Install WSUS with SQL Express 2022"
    Write-Host ""
    Write-Host "DATABASE" -ForegroundColor Yellow
    Write-Host "  2. Restore Database from C:\WSUS"
    Write-Host "  3. Import from External Media (Apricorn/USB/Optical)"
    Write-Host "  4. Export to External Media (for Air-Gap Transfer)"
    Write-Host "  5. Export for DVD Burning (split 4.3GB archives)"
    Write-Host ""
    Write-Host "MAINTENANCE" -ForegroundColor Yellow
    Write-Host "  6. Monthly Maintenance (Sync, Cleanup, Backup, Export)"
    Write-Host "  7. Deep Cleanup (Aggressive DB cleanup)"
    Write-Host ""
    Write-Host "TROUBLESHOOTING" -ForegroundColor Yellow
    Write-Host "  8. Health Check"
    Write-Host "  9. Health Check + Repair"
    Write-Host "  10. Reset Content Download"
    Write-Host ""
    Write-Host "CLIENT" -ForegroundColor Yellow
    Write-Host "  11. Force Client Check-In (run on client)"
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
            '1'  { Invoke-MenuScript -Path "$ScriptsFolder\Install-WsusWithSqlExpress.ps1" -Desc "Install WSUS + SQL Express" }
            '2'  { Invoke-WsusRestore -ContentPath $ContentPath -SqlInstance $SqlInstance; pause }
            '3'  { Invoke-CopyForAirGap -DefaultSource $ExportRoot -ContentPath $ContentPath; pause }
            '4'  { Invoke-ExportToMedia -DefaultSource $ExportRoot -ContentPath $ContentPath; pause }
            '5'  { Invoke-ExportToDvd -DefaultSource $ExportRoot -ContentPath $ContentPath; pause }
            '6'  { Invoke-MenuScript -Path "$ScriptsFolder\Invoke-WsusMonthlyMaintenance.ps1" -Desc "Monthly Maintenance" }
            '7'  { Invoke-WsusCleanup -SqlInstance $SqlInstance; pause }
            '8'  { $null = Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance; pause }
            '9'  { $null = Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance -Repair; pause }
            '10' { Invoke-WsusReset; pause }
            '11' { Invoke-MenuScript -Path "$ScriptsFolder\Invoke-WsusClientCheckIn.ps1" -Desc "Force Client Check-In" }
            'Q'  { Write-Host "Exiting..." -ForegroundColor Green; return }
            default { Write-Host "Invalid option" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($choice -ne 'Q')
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

switch ($PSCmdlet.ParameterSetName) {
    'Restore' { Invoke-WsusRestore -ContentPath $ContentPath -SqlInstance $SqlInstance }
    'Health'  { Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance }
    'Repair'  { Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance -Repair }
    'Cleanup' { Invoke-WsusCleanup -SqlInstance $SqlInstance -Force:$Force }
    'Reset'   { Invoke-WsusReset }
    default   { Start-InteractiveMenu }
}
