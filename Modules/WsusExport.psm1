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
    - Export path validation

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
        "/XO",          # Exclude older files (skip files already up to date)
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
        # Invoke robocopy line-by-line so each progress line streams to the GUI
        # log panel as it's produced. Two non-obvious pitfalls drive this design:
        #
        # 1. Start-Process -Wait buffers everything until robocopy exits, so the
        #    GUI sees nothing until the copy is done.
        # 2. PowerShell captures native-exe stdout into the assignment variable
        #    if you write `$x = & robocopy.exe ...`. To make lines flow to the
        #    parent pipeline you must NOT assign the call directly.
        # 3. Even piping through `Out-Default` is not enough: the line goes to
        #    THIS function's success stream, which is captured by the caller's
        #    `$contentResult = Invoke-WsusRobocopy ...` and never reaches the
        #    outer pipeline that the GUI's OutputDataReceived is reading.
        #
        # The fix is to read stdout line-by-line via a StreamReader and emit each
        # line via Write-Host. Write-Host bypasses the function output stream
        # entirely; combined with the GUI's `& { ... } *>&1` wrapper, each line
        # ends up in the child process's stdout where the GUI captures it.
        #
        # /TEE (added above when LogPath is set) makes robocopy also write to the
        # log file so we have a complete record afterwards.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = 'robocopy.exe'
        $psi.Arguments              = [string[]]$robocopyArgs
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $null = $proc.Start()

        # Stream stdout and stderr concurrently. We can't use async event
        # handlers in a synchronous helper without blocking, so we drain stdout
        # line-by-line; stderr gets drained in the background and we join at
        # the end.
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ($null -ne $line -and $line -ne '') {
                Write-Host $line
            }
        }
        $proc.WaitForExit()
        $stderrText = $stderrTask.Result
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            foreach ($line in $stderrText -split "`r?`n") {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line }
            }
        }
        $result.ExitCode = $proc.ExitCode

        # Robocopy exit codes: 0-7 = success, 8+ = error
        if ($result.ExitCode -lt 8) {
            $result.Success = $true
            $result.Message = switch ($result.ExitCode) {
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
            $result.Message = switch ($result.ExitCode) {
                8 { "Some files or directories could not be copied (copy errors occurred)." }
                16 { "Serious error. Robocopy did not copy any files." }
                default { "Robocopy failed with exit code $($result.ExitCode)" }
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

    .OUTPUTS
        Hashtable with export results
    #>
    param(
        [string]$SourcePath = "C:\WSUS",

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [int]$MaxAgeDays = 0,

        [switch]$IncludeDatabase
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
            -MaxAgeDays $MaxAgeDays -LogPath $logFile

        if ($rootCopyResult.Success) {
            $result.ContentCopied = $true
        } else {
            $result.Errors += "Root content copy: $($rootCopyResult.Message)"
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


function New-WsusTransferPlan {
    <#
    .SYNOPSIS
        Creates a normalized WSUS import/export transfer plan.
    .DESCRIPTION
        Concentrates air-gap transfer decisions in one interface. Callers provide
        source, destination, direction, and mode; execution code consumes the
        returned plan instead of rebuilding robocopy/archive decisions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Import','Export')][string]$Direction,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [ValidateSet('Full','Differential')][string]$Mode = 'Full',
        [int]$MaxAgeDays = 0,
        [switch]$IncludeDatabase
    )

    $sourceTrimmed = $SourcePath.TrimEnd('\')
    $destinationTrimmed = $DestinationPath.TrimEnd('\')
    $contentSource = if ((Split-Path $sourceTrimmed -Leaf) -ieq 'WsusContent') { $sourceTrimmed } else { "$sourceTrimmed\WsusContent" }
    $contentDestination = if ((Split-Path $destinationTrimmed -Leaf) -ieq 'WsusContent') { $destinationTrimmed } else { "$destinationTrimmed\WsusContent" }
    $effectiveMaxAge = if ($Mode -eq 'Differential') { $MaxAgeDays } else { 0 }

    [pscustomobject]@{
        PSTypeName = 'Wsus.TransferPlan'
        Direction = $Direction
        SourcePath = $SourcePath
        DestinationPath = $DestinationPath
        ContentSource = $contentSource
        ContentDestination = $contentDestination
        Mode = $Mode
        MaxAgeDays = $effectiveMaxAge
        IncludeDatabase = [bool]$IncludeDatabase
    }
}

function Invoke-WsusTransferPlan {
    <#
    .SYNOPSIS
        Executes a normalized WSUS transfer plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [string]$LogPath
    )

    Invoke-WsusRobocopy -Source $Plan.ContentSource -Destination $Plan.ContentDestination -MaxAgeDays $Plan.MaxAgeDays -LogPath $LogPath
}

function Invoke-WsusTransferPackage {
    <#
    .SYNOPSIS
        Copies a WSUS transfer package through the shared transfer engine.
    .DESCRIPTION
        Normalizes WSUS import/export content paths, optionally copies package-level
        database backup files, and delegates content copy execution to robocopy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Import','Export','Generic')][string]$Direction,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [switch]$IncludeDatabase,
        [switch]$IncludeContent,
        [ValidateSet('Full','Differential')][string]$Mode = 'Full',
        [int]$MaxAgeDays = 0,
        [string]$LogPath,
        [int]$ThreadCount = 16,
        [string[]]$ExcludeExtensions = @('*.bak', '*.log'),
        [string[]]$ExcludeDirs = @('Logs', 'SQLDB', 'Backup'),
        [string]$DatabaseBackupPath
    )

    $effectiveMaxAge = if ($Mode -eq 'Differential') { $MaxAgeDays } else { 0 }
    $contentSource = $null
    $contentDestination = $null
    $contentResult = $null
    $databaseFiles = @()
    $errors = @()
    $warnings = @()

    if ($IncludeContent) {
        if ($Direction -eq 'Generic') {
            $contentSource = $SourcePath
            $contentDestination = $DestinationPath
        } else {
            $plan = New-WsusTransferPlan -Direction $Direction -SourcePath $SourcePath -DestinationPath $DestinationPath -Mode $Mode -MaxAgeDays $MaxAgeDays -IncludeDatabase:$IncludeDatabase
            $contentSource = $plan.ContentSource
            $contentDestination = $plan.ContentDestination
            $effectiveMaxAge = $plan.MaxAgeDays
        }
    }

    if (-not (Test-Path $DestinationPath)) {
        try {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        } catch {
            $errors += "Failed to create destination: $($_.Exception.Message)"
        }
    }

    if ($errors.Count -eq 0 -and $IncludeDatabase) {
        $backupFiles = @()
        $backupSource = if ($DatabaseBackupPath) { $DatabaseBackupPath } else { $SourcePath }

        if ($DatabaseBackupPath -and (Test-Path -Path $DatabaseBackupPath -PathType Leaf)) {
            $backupFiles = @([pscustomobject]@{ FullName = $DatabaseBackupPath })
        } else {
            $backupFiles = @(Get-ChildItem -Path $backupSource -Filter '*.bak' -File -ErrorAction SilentlyContinue)
        }

        if ($backupFiles.Count -eq 0) {
            $warnings += "No database backup files found in $backupSource."
        } else {
            foreach ($backupFile in $backupFiles) {
                try {
                    Copy-Item -Path $backupFile.FullName -Destination $DestinationPath -Force
                    $databaseFiles += $backupFile.FullName
                } catch {
                    $errors += "Failed to copy database backup '$($backupFile.FullName)': $($_.Exception.Message)"
                }
            }
        }
    }

    $effectiveExcludeExtensions = @($ExcludeExtensions | Where-Object { $_ })
    if (-not ($effectiveExcludeExtensions | Where-Object { $_ -ieq '*.bak' })) {
        $effectiveExcludeExtensions += '*.bak'
    }

    if ($errors.Count -eq 0 -and $IncludeContent) {
        $contentResult = Invoke-WsusRobocopy -Source $contentSource -Destination $contentDestination `
            -MaxAgeDays $effectiveMaxAge -LogPath $LogPath -ThreadCount $ThreadCount `
            -ExcludeExtensions $effectiveExcludeExtensions -ExcludeDirs $ExcludeDirs

        if (-not $contentResult.Success) {
            $errors += $contentResult.Message
        }
    }

    $success = ($errors.Count -eq 0)
    $message = if ($success) {
        "Transfer package completed successfully."
    } else {
        "Transfer package completed with $($errors.Count) error(s)."
    }

    [pscustomobject]@{
        PSTypeName = 'Wsus.TransferResult'
        Success = $success
        Direction = $Direction
        SourcePath = $SourcePath
        DestinationPath = $DestinationPath
        ContentSource = $contentSource
        ContentDestination = $contentDestination
        DatabaseFiles = $databaseFiles
        ContentResult = $contentResult
        Errors = $errors
        Warnings = $warnings
        Message = $message
    }
}

# ===========================
# EXPORTS
# ===========================

Export-ModuleMember -Function @(
    'Invoke-WsusRobocopy',
    'Export-WsusContent',
    'Get-ExportFolderStats',
    'Get-ArchiveStructure',
    'New-WsusTransferPlan',
    'Invoke-WsusTransferPlan',
    'Invoke-WsusTransferPackage'
)
