#Requires -Version 5.1
<#
.SYNOPSIS
    Operation History Module for tracking WSUS operation history.

.DESCRIPTION
    Provides functions to write, read, and clear a persistent JSON-based
    history log of WSUS operations (diagnostics, cleanups, syncs, etc.).
    History is stored in %APPDATA%\WsusManager\history.json, newest first,
    capped at 100 entries.
#>

$script:MaxHistoryEntries = 100
$script:RetryCount = 3
$script:RetryDelaySeconds = 1

#region Private Helpers

function Get-HistoryFilePath {
    return Join-Path $env:APPDATA "WsusManager\history.json"
}

function Read-HistoryFile {
    [CmdletBinding()]
    param()

    $path = Get-HistoryFilePath

    if (-not (Test-Path $path)) {
        return @()
    }

    try {
        $raw = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        $entries = $raw | ConvertFrom-Json -ErrorAction Stop

        if ($null -eq $entries) {
            return @()
        }

        # Normalize to array
        if ($entries -isnot [System.Collections.IEnumerable] -or $entries -is [string]) {
            $entries = @($entries)
        }

        # Filter out entries missing required keys
        $valid = @()
        foreach ($e in $entries) {
            if ($null -ne $e.Timestamp -and $null -ne $e.OperationType -and $null -ne $e.Result) {
                $valid += $e
            }
        }
        return $valid
    }
    catch [System.IO.IOException] {
        # File locked  - bubble up to caller to retry
        throw
    }
    catch {
        # Corrupt JSON  - backup and reset
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupPath = "$path.corrupt.$timestamp"
        try {
            Copy-Item -Path $path -Destination $backupPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "WsusHistory: Could not back up corrupt history file - history will be reset without backup"
        }
        Write-Warning "WsusHistory: history.json was corrupt and has been reset. Backup: $backupPath"
        return @()
    }
}

function Write-HistoryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Entries
    )

    $path = Get-HistoryFilePath
    $dir  = Split-Path $path -Parent

    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Entries | ConvertTo-Json -Depth 5
    # ConvertTo-Json returns a string for single-element arrays  - ensure array brackets
    if ($Entries.Count -eq 1 -and $json -notmatch '^\s*\[') {
        $json = "[$json]"
    }
    elseif ($Entries.Count -eq 0) {
        $json = "[]"
    }

    Set-Content -Path $path -Value $json -Encoding UTF8 -Force -ErrorAction Stop
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Records a WSUS operation result to the persistent history log.

.DESCRIPTION
    Appends (prepends) a new entry to %APPDATA%\WsusManager\history.json.
    The file is trimmed to 100 entries and retried up to 3 times if locked.
    Write failures are logged as warnings and do not throw.

.PARAMETER OperationType
    Category of operation. Examples: "Diagnostics", "Cleanup", "OnlineSync",
    "Export", "Import", "Install".

.PARAMETER Duration
    How long the operation took as a TimeSpan.

.PARAMETER Result
    Outcome of the operation. Must be "Pass" or "Fail".

.PARAMETER Summary
    Optional short description of what happened or any notable details.

.PARAMETER SqlInstance
    SQL instance used for context. Defaults to ".\SQLEXPRESS".

.EXAMPLE
    $elapsed = New-TimeSpan -Seconds 42
    Write-WsusOperationHistory -OperationType "Cleanup" -Duration $elapsed -Result "Pass" -Summary "Removed 312 updates"
#>
function Write-WsusOperationHistory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Appending to a local history log does not warrant ShouldProcess.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationType,

        [Parameter(Mandatory)]
        [TimeSpan]$Duration,

        [Parameter(Mandatory)]
        [ValidateSet("Pass", "Fail")]
        [string]$Result,

        [string]$Summary = "",

        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $newEntry = [ordered]@{
        Timestamp       = (Get-Date -Format "o")
        OperationType   = $OperationType
        DurationSeconds = [math]::Round($Duration.TotalSeconds, 1)
        Result          = $Result
        Summary         = $Summary
        SqlInstance     = $SqlInstance
    }

    $attempt = 0
    $saved   = $false

    while ($attempt -lt $script:RetryCount -and -not $saved) {
        $attempt++
        try {
            $existing = Read-HistoryFile
            $combined = @($newEntry) + @($existing)

            if ($combined.Count -gt $script:MaxHistoryEntries) {
                $combined = $combined[0..($script:MaxHistoryEntries - 1)]
            }

            Write-HistoryFile -Entries $combined
            $saved = $true
        }
        catch [System.IO.IOException] {
            if ($attempt -lt $script:RetryCount) {
                Start-Sleep -Seconds $script:RetryDelaySeconds
            }
            else {
                Write-Warning "WsusHistory: Could not write history after $script:RetryCount attempts (file locked): $_"
            }
        }
        catch {
            Write-Warning "WsusHistory: Failed to write operation history: $_"
            break
        }
    }
}

<#
.SYNOPSIS
    Retrieves WSUS operation history entries.

.DESCRIPTION
    Reads %APPDATA%\WsusManager\history.json and returns entries sorted
    newest first. Supports filtering by operation type and result.
    Returns an empty array when no history exists or on error.

.PARAMETER Count
    Maximum number of entries to return. Defaults to 50.

.PARAMETER OperationType
    When specified, returns only entries whose OperationType matches this value.

.PARAMETER ResultFilter
    Filter entries by outcome. "Pass", "Fail", or "All" (default).

.EXAMPLE
    Get-WsusOperationHistory -Count 10 -OperationType "Cleanup" -ResultFilter "Fail"
#>
function Get-WsusOperationHistory {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 2147483647)]
        [int]$Count = 50,

        [string]$OperationType = "",

        [ValidateSet("Pass", "Fail", "All")]
        [string]$ResultFilter = "All"
    )

    try {
        $entries = Read-HistoryFile
    }
    catch {
        Write-Warning "WsusHistory: Failed to read operation history: $_"
        return @()
    }

    if (-not [string]::IsNullOrWhiteSpace($OperationType)) {
        $entries = @($entries | Where-Object { $_.OperationType -eq $OperationType })
    }

    if ($ResultFilter -ne "All") {
        $entries = @($entries | Where-Object { $_.Result -eq $ResultFilter })
    }

    if ($entries.Count -le $Count) {
        return $entries
    }

    return $entries[0..($Count - 1)]
}

<#
.SYNOPSIS
    Removes all stored WSUS operation history.

.DESCRIPTION
    Deletes %APPDATA%\WsusManager\history.json if it exists.

.OUTPUTS
    [bool] $true on success (or if file did not exist), $false on failure.

.EXAMPLE
    Clear-WsusOperationHistory
#>
function Clear-WsusOperationHistory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Clearing a local history file does not require ShouldProcess confirmation.')]
    [CmdletBinding()]
    param()

    $path = Get-HistoryFilePath

    if (-not (Test-Path $path)) {
        return $true
    }

    try {
        Remove-Item -Path $path -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "WsusHistory: Failed to clear history file: $_"
        return $false
    }
}

#endregion

Export-ModuleMember -Function Write-WsusOperationHistory, Get-WsusOperationHistory, Clear-WsusOperationHistory
