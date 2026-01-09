<#
===============================================================================
Module: WsusExport.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS export and backup functions

.DESCRIPTION
    Provides shared export functionality including:
    - Content export with robocopy
    - Database backup copy
    - Archive structure management
    - Differential export support

    This module consolidates duplicate export logic from multiple scripts.
#>

# ===========================
# ROBOCOPY HELPERS
# ===========================

function Invoke-WsusRobocopy {
    <#
    .SYNOPSIS
        Executes robocopy with standardized options for WSUS exports

    .PARAMETER Source
        Source directory path

    .PARAMETER Destination
        Destination directory path

    .PARAMETER MaxAgeDays
        Only copy files modified within this many days (0 = all files)

    .PARAMETER LogPath
        Path for robocopy log file (optional)

    .PARAMETER ThreadCount
        Number of parallel threads (default: 16)

    .PARAMETER ExcludeExtensions
        File extensions to exclude (default: *.bak, *.log)

    .PARAMETER ExcludeDirs
        Directories to exclude (default: Logs, SQLDB, Backup)

    .OUTPUTS
        Hashtable with Success, ExitCode, and Message
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [int]$MaxAgeDays = 0,

        [string]$LogPath,

        [int]$ThreadCount = 16,

        [string[]]$ExcludeExtensions = @("*.bak", "*.log"),

        [string[]]$ExcludeDirs = @("Logs", "SQLDB", "Backup")
    )

    $result = @{
        Success = $false
        ExitCode = -1
        Message = ""
    }

    if (-not (Test-Path $Source)) {
        $result.Message = "Source path does not exist: $Source"
        return $result
    }

    # Build robocopy arguments
    $robocopyArgs = @(
        "`"$Source`"",
        "`"$Destination`"",
        "/E",           # Include subdirectories (including empty ones)
        "/XO",          # Exclude older files (differential copy)
        "/MT:$ThreadCount",  # Multi-threaded copy
        "/R:2",         # Retry count
        "/W:5",         # Wait time between retries
        "/NP",          # No progress percentage
        "/NDL"          # No directory list
    )

    # Add max age filter if specified
    if ($MaxAgeDays -gt 0) {
        $robocopyArgs += "/MAXAGE:$MaxAgeDays"
    }

    # Add exclusions
    if ($ExcludeExtensions.Count -gt 0) {
        $robocopyArgs += "/XF"
        $robocopyArgs += $ExcludeExtensions
    }

    if ($ExcludeDirs.Count -gt 0) {
        $robocopyArgs += "/XD"
        $robocopyArgs += $ExcludeDirs
    }

    # Add logging if specified
    if ($LogPath) {
        $robocopyArgs += "/LOG:`"$LogPath`""
        $robocopyArgs += "/TEE"  # Output to console and log
    }

    try {
        $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
        $result.ExitCode = $proc.ExitCode

        # Robocopy exit codes: 0-7 = success, 8+ = error
        if ($proc.ExitCode -lt 8) {
            $result.Success = $true
            $result.Message = switch ($proc.ExitCode) {
                0 { "No files copied. Source and destination are synchronized." }
                1 { "All files copied successfully." }
                2 { "Extra files or directories detected." }
                3 { "Some files copied. Extra files detected." }
                4 { "Mismatched files or directories detected." }
                5 { "Some files copied. Mismatched files detected." }
                6 { "Extra and mismatched files detected." }
                7 { "Files copied, extra and mismatched files detected." }
            }
        } else {
            $result.Message = switch ($proc.ExitCode) {
                8 { "Some files or directories could not be copied (copy errors occurred)." }
                16 { "Serious error. Robocopy did not copy any files." }
                default { "Robocopy failed with exit code $($proc.ExitCode)" }
            }
        }
    } catch {
        $result.Message = "Failed to execute robocopy: $($_.Exception.Message)"
    }

    return $result
}

# ===========================
# EXPORT FUNCTIONS
# ===========================

function Export-WsusContent {
    <#
    .SYNOPSIS
        Exports WSUS content to a destination folder

    .PARAMETER SourcePath
        WSUS content source path (default: C:\WSUS)

    .PARAMETER DestinationPath
        Export destination path

    .PARAMETER MaxAgeDays
        Only export files modified within this many days (0 = all files)

    .PARAMETER IncludeDatabase
        Include database backup file in export

    .PARAMETER CreateArchive
        Create year/month archive structure

    .OUTPUTS
        Hashtable with export results
    #>
    param(
        [string]$SourcePath = "C:\WSUS",

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [int]$MaxAgeDays = 0,

        [switch]$IncludeDatabase,

        [switch]$CreateArchive
    )

    $result = @{
        Success = $true
        DatabaseCopied = $false
        ContentCopied = $false
        FilesExported = 0
        ExportSizeGB = 0
        Message = ""
        Errors = @()
    }

    # Validate source
    if (-not (Test-Path $SourcePath)) {
        $result.Success = $false
        $result.Message = "Source path does not exist: $SourcePath"
        return $result
    }

    # Create destination if needed
    if (-not (Test-Path $DestinationPath)) {
        try {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        } catch {
            $result.Success = $false
            $result.Message = "Failed to create destination: $($_.Exception.Message)"
            return $result
        }
    }

    # Create archive structure if requested
    $archivePath = $null
    if ($CreateArchive) {
        $year = (Get-Date).ToString("yyyy")
        $month = (Get-Date).ToString("MMM")
        $archivePath = Join-Path $DestinationPath "$year\$month"

        if (-not (Test-Path $archivePath)) {
            New-Item -Path $archivePath -ItemType Directory -Force | Out-Null
        }
    }

    # Copy database backup if requested
    if ($IncludeDatabase) {
        $bakFiles = Get-ChildItem -Path $SourcePath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

        if ($bakFiles -and $bakFiles.Count -gt 0) {
            $newestBak = $bakFiles | Select-Object -First 1

            # Copy to root destination
            try {
                Copy-Item -Path $newestBak.FullName -Destination $DestinationPath -Force
                $result.DatabaseCopied = $true

                # Also copy to archive if specified
                if ($archivePath) {
                    Copy-Item -Path $newestBak.FullName -Destination $archivePath -Force
                }
            } catch {
                $result.Errors += "Failed to copy database: $($_.Exception.Message)"
            }
        }
    }

    # Copy content folder
    $wsusContent = Join-Path $SourcePath "WsusContent"
    if (Test-Path $wsusContent) {
        # Create log directory
        $logDir = Join-Path $SourcePath "Logs"
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $logFile = Join-Path $logDir "Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        # Copy to root destination
        $rootDestContent = Join-Path $DestinationPath "WsusContent"
        $rootCopyResult = Invoke-WsusRobocopy -Source $wsusContent -Destination $rootDestContent `
            -MaxAgeDays 0 -LogPath $logFile

        if ($rootCopyResult.Success) {
            $result.ContentCopied = $true
        } else {
            $result.Errors += "Root content copy: $($rootCopyResult.Message)"
        }

        # Copy differential to archive if specified
        if ($archivePath -and $MaxAgeDays -gt 0) {
            $archiveDestContent = Join-Path $archivePath "WsusContent"
            $archiveLogFile = Join-Path $logDir "Export_Archive_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

            $archiveCopyResult = Invoke-WsusRobocopy -Source $wsusContent -Destination $archiveDestContent `
                -MaxAgeDays $MaxAgeDays -LogPath $archiveLogFile

            if (-not $archiveCopyResult.Success) {
                $result.Errors += "Archive content copy: $($archiveCopyResult.Message)"
            }
        }

        # Calculate exported file stats
        if (Test-Path $rootDestContent) {
            $exportedFiles = Get-ChildItem -Path $rootDestContent -Recurse -File -ErrorAction SilentlyContinue
            $result.FilesExported = $exportedFiles.Count
            $result.ExportSizeGB = [math]::Round(($exportedFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        }
    } else {
        $result.Errors += "WsusContent folder not found at $wsusContent"
    }

    if ($result.Errors.Count -gt 0) {
        $result.Success = $false
        $result.Message = "Export completed with $($result.Errors.Count) error(s)"
    } else {
        $result.Message = "Export completed successfully"
    }

    return $result
}

function Get-ExportFolderStats {
    <#
    .SYNOPSIS
        Gets statistics about an export folder

    .PARAMETER Path
        Path to the export folder

    .OUTPUTS
        Hashtable with folder statistics
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = @{
        Exists = $false
        TotalSizeGB = 0
        FileCount = 0
        BackupFile = $null
        BackupSizeGB = 0
        HasContent = $false
        ContentSizeGB = 0
        ContentFileCount = 0
    }

    if (-not (Test-Path $Path)) {
        return $result
    }

    $result.Exists = $true

    # Check for backup file
    $bakFile = Get-ChildItem -Path $Path -Filter "*.bak" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($bakFile) {
        $result.BackupFile = $bakFile.Name
        $result.BackupSizeGB = [math]::Round($bakFile.Length / 1GB, 2)
    }

    # Check content folder
    $contentPath = Join-Path $Path "WsusContent"
    if (Test-Path $contentPath) {
        $result.HasContent = $true
        $contentFiles = Get-ChildItem -Path $contentPath -Recurse -File -ErrorAction SilentlyContinue
        $result.ContentFileCount = $contentFiles.Count
        $result.ContentSizeGB = [math]::Round(($contentFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    }

    # Calculate totals
    $allFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
    $result.FileCount = $allFiles.Count
    $result.TotalSizeGB = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)

    return $result
}

function Get-ArchiveStructure {
    <#
    .SYNOPSIS
        Gets the archive folder structure for an export location

    .PARAMETER BasePath
        Base export path

    .OUTPUTS
        Array of archive folder information
    #>
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $archives = @()

    if (-not (Test-Path $BasePath)) {
        return $archives
    }

    # Find year folders
    $yearFolders = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}$' } |
        Sort-Object Name -Descending

    foreach ($year in $yearFolders) {
        # Find month folders
        $monthFolders = Get-ChildItem -Path $year.FullName -Directory -ErrorAction SilentlyContinue

        foreach ($month in $monthFolders) {
            $stats = Get-ExportFolderStats -Path $month.FullName

            $archives += @{
                Year = $year.Name
                Month = $month.Name
                Path = $month.FullName
                Stats = $stats
            }
        }
    }

    return $archives
}

# ===========================
# EXPORTS
# ===========================

Export-ModuleMember -Function @(
    'Invoke-WsusRobocopy',
    'Export-WsusContent',
    'Get-ExportFolderStats',
    'Get-ArchiveStructure'
)
