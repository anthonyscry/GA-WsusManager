#Requires -RunAsAdministrator

<#
===============================================================================
Script: Invoke-WsusManagement.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 3.8.3
Date: 2026-01-10
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

    [Parameter(ParameterSetName = 'Import')]
    [switch]$Import,

    [Parameter(ParameterSetName = 'Export')]
    [switch]$Export,

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

    # Restore parameters
    [Parameter(ParameterSetName = 'Restore')]
    [string]$BackupPath,

    # Export parameters (for non-interactive mode)
    [Parameter(ParameterSetName = 'Export')]
    [string]$SourcePath,

    [Parameter(ParameterSetName = 'Export')]
    [string]$DestinationPath,

    [Parameter(ParameterSetName = 'Export')]
    [ValidateSet('Full', 'Differential')]
    [string]$CopyMode = "Full",

    [Parameter(ParameterSetName = 'Export')]
    [int]$DaysOld = 30,

    # Common
    [string]$ExportRoot = "\\lab-hyperv\d\WSUS-Exports",
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS"
)

$ErrorActionPreference = 'Continue'

# ============================================================================
# CENTRALIZED LOGGING SETUP
# ============================================================================
# Single daily log file - all operations append to same file
$script:LogDirectory = "C:\WSUS\Logs"
$script:LogFileName = "WsusManagement_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:LogFilePath = Join-Path $script:LogDirectory $script:LogFileName

# Create log directory if needed
if (-not (Test-Path $script:LogDirectory)) {
    New-Item -Path $script:LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Write session start marker
$sessionMarker = @"

================================================================================
SESSION START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================================================
"@
Add-Content -Path $script:LogFilePath -Value $sessionMarker -ErrorAction SilentlyContinue

# Determine the project root and scripts folder
# Handle multiple deployment scenarios:
# 1. Standard: Invoke-WsusManagement.ps1 at root, subscripts in Scripts\ subfolder
# 2. Flat: All scripts in same folder (user copied main script into Scripts folder)
# 3. Nested: Script in Scripts\Scripts\ folder

# Resolve script location (handles symlinks and dot-sourcing)
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ScriptsFolder = $ScriptRoot

# Check flat layout FIRST (scripts in same folder as main script)
# This prevents double-Scripts path issue when running from Scripts folder
if (Test-Path (Join-Path $ScriptRoot "Invoke-WsusMonthlyMaintenance.ps1")) {
    # Flat layout - all scripts in same folder (or user is running from Scripts folder)
    $ScriptsFolder = $ScriptRoot
} elseif (Test-Path (Join-Path $ScriptRoot "Scripts\Invoke-WsusMonthlyMaintenance.ps1")) {
    # Standard layout - scripts are in Scripts\ subfolder
    $ScriptsFolder = Join-Path $ScriptRoot "Scripts"
}

# Find modules folder - search multiple locations for flexibility
$ModulesFolder = $null
$moduleSearchPaths = @(
    (Join-Path $ScriptRoot "Modules"),                                      # Standard (root\Modules)
    (Join-Path (Split-Path $ScriptRoot -Parent) "Modules"),                 # Parent folder
    (Join-Path (Split-Path (Split-Path $ScriptRoot -Parent) -Parent) "Modules"),  # Grandparent (nested)
    $ScriptsFolder                                                           # Same folder as scripts
)

foreach ($path in $moduleSearchPaths) {
    $utilPath = Join-Path $path "WsusUtilities.psm1"
    if (Test-Path $utilPath) {
        # Verify the module file has expected content
        $content = Get-Content $utilPath -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match 'function Start-WsusLogging') {
            $ModulesFolder = $path
            break
        }
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log($msg, $color = "White") {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "$timestamp - $msg"

    # Write to console
    Write-Host $logMessage -ForegroundColor $color

    # Append to daily log file
    Add-Content -Path $script:LogFilePath -Value $logMessage -ErrorAction SilentlyContinue
}

function Write-Banner($title) {
    $banner = @"

===============================================================================
                    $title
===============================================================================

"@
    Write-Host $banner -ForegroundColor Cyan

    # Also log to file
    Add-Content -Path $script:LogFilePath -Value $banner -ErrorAction SilentlyContinue
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

function Test-ValidPath {
    <#
    .SYNOPSIS
        Validates a user-provided path for safety and existence
    .PARAMETER Path
        The path to validate
    .PARAMETER MustExist
        If true, the path must already exist
    .PARAMETER PathType
        Expected type: 'Container' (directory), 'Leaf' (file), or 'Any'
    .OUTPUTS
        Hashtable with IsValid, Message, and CleanPath properties
    #>
    param(
        [string]$Path,
        [switch]$MustExist,
        [ValidateSet('Container', 'Leaf', 'Any')]
        [string]$PathType = 'Any'
    )

    $result = @{ IsValid = $false; Message = ""; CleanPath = "" }

    # Check for empty/null
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $result.Message = "Path cannot be empty"
        return $result
    }

    # Trim whitespace
    $Path = $Path.Trim()

    # Check for dangerous characters that could enable injection
    if ($Path -match '[`$;|&<>]') {
        $result.Message = "Path contains invalid characters"
        return $result
    }

    # Must start with valid drive letter or UNC path
    if ($Path -notmatch '^[A-Za-z]:\\' -and $Path -notmatch '^\\\\[^\\]+\\') {
        $result.Message = "Path must be a valid Windows path (e.g., C:\folder or \\server\share)"
        return $result
    }

    # Check existence if required
    if ($MustExist) {
        if (-not (Test-Path $Path)) {
            $result.Message = "Path does not exist: $Path"
            return $result
        }

        if ($PathType -ne 'Any') {
            if (-not (Test-Path $Path -PathType $PathType)) {
                $typeDesc = if ($PathType -eq 'Container') { 'directory' } else { 'file' }
                $result.Message = "Path is not a $typeDesc`: $Path"
                return $result
            }
        }
    }

    $result.IsValid = $true
    $result.CleanPath = $Path
    return $result
}

# ============================================================================
# RESTORE OPERATION
# ============================================================================

function Invoke-WsusRestore {
    param(
        [string]$ContentPath,
        [string]$SqlInstance,
        [string]$BackupPath
    )

    Write-Banner "WSUS DATABASE RESTORE"

    $SqlCmdExe = Get-SqlCmd
    if (-not $SqlCmdExe) {
        Write-Log "ERROR: sqlcmd.exe not found" "Red"
        return
    }

    # If specific backup path provided, use it directly
    if ($BackupPath -and (Test-Path $BackupPath)) {
        $selectedBackup = Get-Item $BackupPath
        Write-Host "Using specified backup file:" -ForegroundColor Cyan
        Write-Host "  $($selectedBackup.Name)" -ForegroundColor Green
        Write-Host "  Size: $([math]::Round($selectedBackup.Length / 1GB, 2)) GB"
        Write-Host "  Date: $($selectedBackup.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
        Write-Host ""
    } else {
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

        $selectedBackup = $backupFiles | Select-Object -First 1
        Write-Host ""
        Write-Host "Newest backup: $($selectedBackup.Name)" -ForegroundColor Green
        Write-Host "  Size: $([math]::Round($selectedBackup.Length / 1GB, 2)) GB"
        Write-Host "  Date: $($selectedBackup.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
        Write-Host ""

        $confirm = Read-Host "Restore this backup? (Y/n)"
        if ($confirm -notin @("Y", "y", "")) { return }
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
    & $SqlCmdExe -S $SqlInstance -Q "RESTORE DATABASE SUSDB FROM DISK='$($selectedBackup.FullName)' WITH REPLACE, STATS=10" -b
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

    while ($true) {
        Write-Host ""
        Write-Host "Destination options:" -ForegroundColor Yellow
        Write-Host "  1. $DefaultPath (default)"
        Write-Host "  2. Custom path"
        Write-Host ""
        $destChoice = Read-Host "Select destination (1/2)"

        # Validate input - only accept 1, 2, or empty (default)
        if ($destChoice -eq "" -or $destChoice -eq "1") {
            return $DefaultPath
        }
        elseif ($destChoice -eq "2") {
            $customPath = Read-Host "Enter destination path"
            # Validate the custom path
            $validation = Test-ValidPath -Path $customPath
            if (-not $validation.IsValid) {
                Write-Log "ERROR: $($validation.Message)" "Red"
                return $null
            }
            return $validation.CleanPath
        }
        else {
            Write-Host "Invalid selection '$destChoice'. Please enter 1 or 2." -ForegroundColor Red
            # Loop continues to re-prompt
        }
    }
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

                        # Find all .bak files directly in the month folder
                        $bakFiles = Get-ChildItem -Path $selectedMonth.FullName -Filter "*.bak" -File -ErrorAction SilentlyContinue |
                            Sort-Object Name -Descending

                        if (-not $bakFiles -or $bakFiles.Count -eq 0) {
                            Write-Host "No backups found in $($selectedMonth.FullName)" -ForegroundColor Yellow
                            Read-Host "Press Enter to go back"
                            continue monthLoop
                        }

                        # Check if WsusContent folder exists alongside the backups
                        $contentPath = Join-Path $selectedMonth.FullName "WsusContent"
                        $hasContent = Test-Path $contentPath

                        $i = 1
                        $backupInfo = @()
                        foreach ($bakFile in $bakFiles) {
                            $sizeDisplay = Format-SizeDisplay ([math]::Round($bakFile.Length / 1GB, 2))

                            $type = if ($bakFile.Name -like "FULL*") { "FULL" }
                                    elseif ($bakFile.Name -like "DIFF*") { "DIFF" }
                                    else { "    " }

                            $contentMarker = if ($hasContent) { "+ Content" } else { "DB only" }

                            Write-Host "  [$i] $($bakFile.Name) ($sizeDisplay) - $type $contentMarker" -ForegroundColor White
                            $backupInfo += @{
                                Folder = $selectedMonth
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
                            Write-Host "Will copy $($bakFiles.Count) backup(s) to: $destination" -ForegroundColor Yellow
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
                        if ([int]::TryParse($backupChoice, [ref]$backupIndex) -and $backupIndex -ge 1 -and $backupIndex -le $bakFiles.Count) {
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

    # Validate DefaultSource - use C:\ if empty
    if ([string]::IsNullOrWhiteSpace($DefaultSource)) {
        $DefaultSource = "C:\"
    }

    # Prompt for source path
    Write-Host "Where is the external media mounted?" -ForegroundColor Cyan
    Write-Host "  Examples: E:\  D:\WSUS-Transfer  F:\AirGap" -ForegroundColor Gray
    Write-Host "  Or press Enter for: $DefaultSource" -ForegroundColor Gray
    Write-Host ""
    $sourceInput = Read-Host "Enter source path (or press Enter for default)"

    $ExportSource = if ($sourceInput) { $sourceInput } else { $DefaultSource }

    # Validate the source path
    $validation = Test-ValidPath -Path $ExportSource -MustExist -PathType Container
    if (-not $validation.IsValid) {
        Write-Log "ERROR: $($validation.Message)" "Red"
        Write-Host "Make sure the path exists and media is connected." -ForegroundColor Yellow
        return
    }
    $ExportSource = $validation.CleanPath

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
                $validation = Test-ValidPath -Path $newSource -MustExist -PathType Container
                if ($validation.IsValid) {
                    $ExportSource = $validation.CleanPath
                } else {
                    Write-Host "$($validation.Message)" -ForegroundColor Red
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
        "3" {
            $customSource = Read-Host "Enter source path"
            $validation = Test-ValidPath -Path $customSource -MustExist -PathType Container
            if ($validation.IsValid) { $validation.CleanPath } else { $null }
        }
        default { $DefaultSource }
    }

    if (-not $source) {
        Write-Log "ERROR: Invalid source path" "Red"
        return
    }

    $validation = Test-ValidPath -Path $source -MustExist -PathType Container
    if (-not $validation.IsValid) {
        Write-Log "ERROR: $($validation.Message)" "Red"
        return
    }
    $source = $validation.CleanPath

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

    # Validate output path format (doesn't need to exist yet)
    $validation = Test-ValidPath -Path $outputPath
    if (-not $validation.IsValid) {
        Write-Log "ERROR: $($validation.Message)" "Red"
        return
    }
    $outputPath = $validation.CleanPath

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
    $sevenZipArgs = @(
        "a",                    # add to archive
        "-v4300m",              # split into 4.3GB volumes (DVD size)
        "-mx=1",                # fast compression (speed over size)
        "-mmt=on",              # multi-threading
        "`"$archivePath`"",     # output archive
        "`"$source\*`""         # source files
    )

    $proc = Start-Process -FilePath $sevenZip -ArgumentList $sevenZipArgs -Wait -PassThru -NoNewWindow
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
        Copy WSUS data to external media (Apricorn, USB) for air-gap transfer
    .DESCRIPTION
        Prompts for source and destination, supports full or differential copy modes.
        When DestinationPath is provided, runs in non-interactive mode (for GUI).
    #>
    param(
        [string]$DefaultSource = "\\lab-hyperv\d\WSUS-Exports",
        [string]$ContentPath = "C:\WSUS",
        [string]$SourcePath,
        [string]$DestinationPath,
        [ValidateSet('Full', 'Differential')]
        [string]$ExportCopyMode = "Full",
        [int]$ExportDaysOld = 30
    )

    # Determine if running in non-interactive mode (GUI mode)
    $nonInteractive = -not [string]::IsNullOrWhiteSpace($DestinationPath)

    Write-Banner "COPY DATA TO EXTERNAL MEDIA"

    Write-Host "This will copy WSUS data to external media for air-gap transfer." -ForegroundColor Yellow
    Write-Host "Use this on the ONLINE server to prepare data for transport." -ForegroundColor Yellow
    if ($nonInteractive) {
        Write-Host "Copy mode: $ExportCopyMode$(if($ExportCopyMode -eq 'Differential'){" (last $ExportDaysOld days)"})" -ForegroundColor Cyan
    }
    Write-Host ""

    # Validate paths - use defaults if empty
    if ([string]::IsNullOrWhiteSpace($DefaultSource)) {
        $DefaultSource = "C:\"
    }
    if ([string]::IsNullOrWhiteSpace($ContentPath)) {
        $ContentPath = "C:\WSUS"
    }

    # Set copy mode variables
    $copyMode = $ExportCopyMode
    $maxAgeDays = $ExportDaysOld

    if (-not $nonInteractive) {
        # Interactive mode: Prompt for copy mode
        Write-Host "Copy mode:" -ForegroundColor Cyan
        Write-Host "  1. Full copy (all files)"
        Write-Host "  2. Differential copy (files from last 30 days) [Default]"
        Write-Host "  3. Differential copy (custom days)"
        Write-Host ""
        $modeChoice = Read-Host "Select mode (1/2/3) [2]"
        if ([string]::IsNullOrWhiteSpace($modeChoice)) { $modeChoice = "2" }

        switch ($modeChoice) {
            "1" {
                $copyMode = "Full"
                $maxAgeDays = 0
            }
            "2" {
                $copyMode = "Differential"
                $maxAgeDays = 30
            }
            "3" {
                $copyMode = "Differential"
                $daysInput = Read-Host "Enter number of days [30]"
                if ([string]::IsNullOrWhiteSpace($daysInput)) { $daysInput = "30" }
                if ([int]::TryParse($daysInput, [ref]$maxAgeDays)) {
                    if ($maxAgeDays -le 0) { $maxAgeDays = 30 }
                } else {
                    $maxAgeDays = 30
                }
            }
            default {
                $copyMode = "Differential"
                $maxAgeDays = 30
            }
        }
        Write-Host ""
    }

    # Determine source path
    if ($nonInteractive) {
        # Non-interactive: Use SourcePath if provided, otherwise use ContentPath (local WSUS)
        $source = if (-not [string]::IsNullOrWhiteSpace($SourcePath)) { $SourcePath } else { $ContentPath }
    } else {
        # Interactive mode: Prompt for source
        Write-Host "Source options:" -ForegroundColor Cyan
        Write-Host "  1. Network share: $DefaultSource [Default]"
        Write-Host "  2. Local WSUS: $ContentPath"
        Write-Host "  3. Custom path"
        Write-Host ""
        $sourceChoice = Read-Host "Select source (1/2/3) [1]"
        if ([string]::IsNullOrWhiteSpace($sourceChoice)) { $sourceChoice = "1" }

        $source = switch ($sourceChoice) {
            "1" { $DefaultSource }
            "2" { $ContentPath }
            "3" {
                $customSource = Read-Host "Enter source path"
                $validation = Test-ValidPath -Path $customSource -MustExist -PathType Container
                if ($validation.IsValid) { $validation.CleanPath } else { $null }
            }
            default { $DefaultSource }
        }
    }

    # Validate source path
    if (-not $source) {
        Write-Log "ERROR: Invalid source path" "Red"
        return
    }
    $validation = Test-ValidPath -Path $source -MustExist -PathType Container
    if (-not $validation.IsValid) {
        Write-Log "ERROR: $($validation.Message)" "Red"
        return
    }
    $source = $validation.CleanPath

    # Check what's in source
    $sourceBak = Get-ChildItem -Path $source -Filter "*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $sourceContent = Join-Path $source "WsusContent"
    $hasContent = Test-Path $sourceContent -ErrorAction SilentlyContinue

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

    # Determine destination path
    if ($nonInteractive) {
        # Non-interactive: Use provided DestinationPath
        $destination = $DestinationPath
    } else {
        # Interactive mode: Prompt for destination
        Write-Host "Destination (external media path):" -ForegroundColor Cyan
        Write-Host "  Examples: E:\  D:\WSUS-Transfer  F:\AirGap" -ForegroundColor Gray
        Write-Host ""
        $destination = Read-Host "Enter destination path"
    }

    # Validate destination path format
    $validation = Test-ValidPath -Path $destination
    if (-not $validation.IsValid) {
        Write-Log "ERROR: $($validation.Message)" "Red"
        return
    }
    $destination = $validation.CleanPath

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
    if ($copyMode -eq "Full") {
        Write-Host "  Mode:        Full (all files)"
    } else {
        Write-Host "  Mode:        Differential (files from last $maxAgeDays days)"
    }
    Write-Host ""

    # Skip confirmation in non-interactive mode
    if (-not $nonInteractive) {
        $confirm = Read-Host "Proceed with copy? (Y/n)"
        if ($confirm -notin @("Y", "y", "")) { return }
    }

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

        # Build robocopy arguments
        # /E = include subdirs, /MT:16 = 16 threads
        $robocopyArgs = @(
            "`"$sourceContent`"", "`"$destContent`"",
            "/E", "/MT:16", "/R:2", "/W:5", "/NP", "/NDL"
        )

        if ($copyMode -eq "Differential") {
            # /MAXAGE:n = exclude files older than n days
            $robocopyArgs += "/MAXAGE:$maxAgeDays"
        }

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

    Write-Banner "COPY COMPLETE"
    Write-Host "Data copied to: $destination" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Safely eject the external media"
    Write-Host "  2. Transport to air-gap server"
    Write-Host "  3. On air-gap server, run option 3 (Copy Data from External Media)"
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
    Write-Host "              WSUS Management v3.3.0" -ForegroundColor Cyan
    Write-Host "              Author: Tony Tran, ISSO, GA-ASI" -ForegroundColor Gray
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "INSTALLATION" -ForegroundColor Yellow
    Write-Host "  1. Install WSUS with SQL Express 2022"
    Write-Host ""
    Write-Host "DATABASE" -ForegroundColor Yellow
    Write-Host "  2. Restore Database from C:\WSUS"
    Write-Host "  3. Copy Data from External Media (Apricorn)"
    Write-Host "  4. Copy Data to External Media (Apricorn)"
    Write-Host ""
    Write-Host "MAINTENANCE" -ForegroundColor Yellow
    Write-Host "  5. Monthly Maintenance (Sync, Cleanup, Backup, Export)"
    Write-Host "  6. Deep Cleanup (Aggressive DB cleanup)"
    Write-Host ""
    Write-Host "TROUBLESHOOTING" -ForegroundColor Yellow
    Write-Host "  7. Health Check"
    Write-Host "  8. Health Check + Repair"
    Write-Host "  9. Reset Content Download"
    Write-Host ""
    Write-Host "CLIENT" -ForegroundColor Yellow
    Write-Host "  10. Force Client Check-In (run on client)"
    Write-Host ""
    Write-Host "  Q. Quit" -ForegroundColor Red
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
}

function Invoke-MenuScript {
    param([string]$Path, [string]$Desc)
    Write-Log "Launching: $Desc" "Green"
    if (Test-Path $Path) { & $Path } else { Write-Log "Script not found: $Path" "Red" }
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Start-InteractiveMenu {
    param(
        [string]$MenuExportRoot
    )
    do {
        Show-Menu
        $choice = Read-Host "Select"

        # Log user menu selection
        Add-Content -Path $script:LogFilePath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Menu selection: $choice" -ErrorAction SilentlyContinue

        switch ($choice) {
            '1'  { Invoke-MenuScript -Path "$ScriptsFolder\Install-WsusWithSqlExpress.ps1" -Desc "Install WSUS + SQL Express" }
            '2'  { Invoke-WsusRestore -ContentPath $ContentPath -SqlInstance $SqlInstance; pause }
            '3'  { Invoke-CopyForAirGap -DefaultSource $MenuExportRoot -ContentPath $ContentPath; pause }
            '4'  { Invoke-ExportToMedia -DefaultSource $MenuExportRoot -ContentPath $ContentPath; pause }
            '5'  { Invoke-MenuScript -Path "$ScriptsFolder\Invoke-WsusMonthlyMaintenance.ps1" -Desc "Monthly Maintenance" }
            '6'  { Invoke-WsusCleanup; pause }
            '7'  { $null = Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance; pause }
            '8'  { $null = Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance -Repair; pause }
            '9'  { Invoke-WsusReset; pause }
            '10' { Invoke-MenuScript -Path "$ScriptsFolder\Invoke-WsusClientCheckIn.ps1" -Desc "Force Client Check-In" }
            'D'  { Invoke-ExportToDvd -DefaultSource $MenuExportRoot -ContentPath $ContentPath; pause }  # Hidden: DVD export
            'Q'  { Write-Log "Exiting WSUS Management" "Green"; return }
            default { Write-Host "Invalid option" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($choice -ne 'Q')
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

# Handle CLI switches directly to avoid PSScriptAnalyzer unused parameter warnings
if ($Restore) {
    Invoke-WsusRestore -ContentPath $ContentPath -SqlInstance $SqlInstance -BackupPath $BackupPath
} elseif ($Import) {
    Invoke-CopyForAirGap -DefaultSource $ExportRoot -ContentPath $ContentPath
} elseif ($Export) {
    # For backward compatibility with current GUI:
    # - If DestinationPath is set explicitly, use it
    # - Otherwise, if ExportRoot differs from default, interpret it as the destination
    $actualDestination = $DestinationPath
    $actualSource = $SourcePath
    $defaultExportRoot = "\\lab-hyperv\d\WSUS-Exports"

    if ([string]::IsNullOrWhiteSpace($actualDestination) -and $ExportRoot -ne $defaultExportRoot) {
        # GUI is passing destination as ExportRoot - use it as destination, use ContentPath as source
        $actualDestination = $ExportRoot
        $actualSource = $ContentPath
    }

    Invoke-ExportToMedia -DefaultSource $defaultExportRoot -ContentPath $ContentPath `
        -SourcePath $actualSource -DestinationPath $actualDestination `
        -ExportCopyMode $CopyMode -ExportDaysOld $DaysOld
} elseif ($Health) {
    Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance
} elseif ($Repair) {
    Invoke-WsusHealthCheck -ContentPath $ContentPath -SqlInstance $SqlInstance -Repair
} elseif ($Cleanup) {
    Invoke-WsusCleanup -Force:$Force
} elseif ($Reset) {
    Invoke-WsusReset
} else {
    Start-InteractiveMenu -MenuExportRoot $ExportRoot
}
