#Requires -Version 5.1

$script:TrendsFilePath = Join-Path $env:APPDATA "WsusManager\trends.json"
$script:MaxHistoryDays  = 90
$script:SqlExpressLimitGB = 10.0

function Get-TrendsFilePath {
    return $script:TrendsFilePath
}

function Read-TrendData {
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param()

    $path = Get-TrendsFilePath

    if (-not (Test-Path $path)) {
        return [System.Collections.Generic.List[hashtable]]::new()
    }

    try {
        $raw = Get-Content -Path $path -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

        $list = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($entry in $parsed) {
            $list.Add(@{
                Date           = [string]$entry.Date
                DatabaseSizeGB = [double]$entry.DatabaseSizeGB
            })
        }
        return $list
    } catch {
        # Corrupt JSON  - back up and reset
        Write-Verbose "WsusTrending: Corrupt trends file, backing up and resetting  - $($_.Exception.Message)"
        try {
            $backupPath = "$path.bak"
            Copy-Item -Path $path -Destination $backupPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "WsusTrending: Could not back up corrupt file  - $($_.Exception.Message)"
        }
        return [System.Collections.Generic.List[hashtable]]::new()
    }
}

function Save-TrendData {
    param(
        [System.Collections.Generic.List[hashtable]]$Data
    )

    $path = Get-TrendsFilePath
    $dir  = Split-Path $path -Parent

    try {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $Data | ConvertTo-Json -Depth 3 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Verbose "WsusTrending: Failed to save trends data  - $($_.Exception.Message)"
    }
}

function Add-WsusTrendSnapshot {
<#
.SYNOPSIS
    Records a daily database size snapshot for trend analysis.
.DESCRIPTION
    Adds today's snapshot to the trends file if no entry exists for today.
    If an entry for today already exists, it is updated with the new value.
    History is automatically trimmed to the most recent 90 days.
.PARAMETER DatabaseSizeGB
    Current database size in gigabytes.
.EXAMPLE
    Add-WsusTrendSnapshot -DatabaseSizeGB 6.2
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$DatabaseSizeGB
    )

    try {
        $today = (Get-Date).ToString("yyyy-MM-dd")
        $data  = Read-TrendData

        # Update existing entry for today, or add a new one
        $existing = $data | Where-Object { $_.Date -eq $today }
        if ($null -ne $existing) {
            $existing.DatabaseSizeGB = $DatabaseSizeGB
        } else {
            $data.Add(@{ Date = $today; DatabaseSizeGB = $DatabaseSizeGB })
        }

        # Sort ascending and trim to MaxHistoryDays
        $sorted  = @($data | Sort-Object { [datetime]$_.Date })
        $trimmed = [System.Collections.Generic.List[hashtable]]::new()
        $cutoff  = (Get-Date).AddDays(-$script:MaxHistoryDays).ToString("yyyy-MM-dd")
        foreach ($entry in $sorted) {
            if ([string]$entry.Date -ge $cutoff) {
                $trimmed.Add($entry)
            }
        }

        Save-TrendData -Data $trimmed
        Write-Verbose "WsusTrending: Snapshot recorded  - $today = $DatabaseSizeGB GB ($($trimmed.Count) points stored)"
    } catch {
        Write-Verbose "WsusTrending: Add-WsusTrendSnapshot failed  - $($_.Exception.Message)"
    }
}

function Get-WsusTrendSummary {
<#
.SYNOPSIS
    Calculates DB size trend and days-until-full estimate.
.DESCRIPTION
    Reads the stored trend snapshots and performs a linear regression over
    the last 30 days to estimate monthly growth rate and days until the
    SQL Express 10 GB database size limit is reached.
.OUTPUTS
    Hashtable with the following keys:
        CurrentSizeGB  [double]  - Latest recorded size
        GrowthPerMonth [double]  - Estimated GB growth per 30-day period
        DaysUntilFull  [int]     - Estimated days until 10 GB limit (-1 = unknown)
        TrendText      [string]  - Human-readable summary, e.g. "6.2 GB +0.3/mo"
        AlertLevel     [string]  - "None", "Warning" (< 180 days), or "Critical" (< 90 days)
        DataPoints     [int]     - Number of stored snapshots
        Status         [string]  - "Collecting data..." if < 3 points, else "OK"
.EXAMPLE
    $summary = Get-WsusTrendSummary
    Write-Host $summary.TrendText
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $defaultResult = @{
        CurrentSizeGB  = 0.0
        GrowthPerMonth = 0.0
        DaysUntilFull  = -1
        TrendText      = "N/A"
        AlertLevel     = "None"
        DataPoints     = 0
        Status         = "Collecting data..."
    }

    try {
        $data = Read-TrendData

        if ($data.Count -eq 0) {
            return $defaultResult
        }

        # Sort ascending by date
        $sorted = @($data | Sort-Object { [datetime]$_.Date })

        $defaultResult.DataPoints = $sorted.Count
        $defaultResult.CurrentSizeGB = $sorted[-1].DatabaseSizeGB

        if ($sorted.Count -lt 3) {
            $defaultResult.TrendText = "$([math]::Round($defaultResult.CurrentSizeGB, 1)) GB  - collecting data"
            return $defaultResult
        }

        # Use last 30 days of data points
        $cutoff30    = (Get-Date).AddDays(-30)
        $recentPoints = @($sorted | Where-Object { [datetime]$_.Date -ge $cutoff30 })

        # Need at least 2 points for regression
        if ($recentPoints.Count -lt 2) {
            $recentPoints = @($sorted[-2], $sorted[-1])
        }

        $first = $recentPoints[0]
        $last  = $recentPoints[-1]

        $daysDiff = ([datetime]$last.Date - [datetime]$first.Date).TotalDays
        if ($daysDiff -le 0) {
            # All points on same day  - no trend calculable
            $growthPerMonth = 0.0
        } else {
            $rawGrowth      = $last.DatabaseSizeGB - $first.DatabaseSizeGB
            $growthPerMonth = ($rawGrowth / $daysDiff) * 30.0
        }

        $currentSizeGB = $last.DatabaseSizeGB
        $daysUntilFull = -1

        if ($growthPerMonth -gt 0) {
            $gbRemaining   = $script:SqlExpressLimitGB - $currentSizeGB
            $daysUntilFull = [int][math]::Floor($gbRemaining / ($growthPerMonth / 30.0))
            if ($daysUntilFull -lt 0) { $daysUntilFull = 0 }
        }

        # Build TrendText
        $sizeStr = [math]::Round($currentSizeGB, 1).ToString("F1")
        if ($growthPerMonth -eq 0) {
            $growthStr = "+0/mo"
        } elseif ($growthPerMonth -gt 0) {
            $growthStr = "+$([math]::Round($growthPerMonth, 1).ToString("F1"))/mo"
        } else {
            $growthStr = "$([math]::Round($growthPerMonth, 1).ToString("F1"))/mo"
        }
        $trendText = "$sizeStr GB $growthStr"

        # AlertLevel
        $alertLevel = "None"
        if ($daysUntilFull -ge 0) {
            if ($daysUntilFull -lt 90) {
                $alertLevel = "Critical"
            } elseif ($daysUntilFull -lt 180) {
                $alertLevel = "Warning"
            }
        }

        return @{
            CurrentSizeGB  = [math]::Round($currentSizeGB, 2)
            GrowthPerMonth = [math]::Round($growthPerMonth, 2)
            DaysUntilFull  = $daysUntilFull
            TrendText      = $trendText
            AlertLevel     = $alertLevel
            DataPoints     = $sorted.Count
            Status         = "OK"
        }
    } catch {
        Write-Verbose "WsusTrending: Get-WsusTrendSummary failed  - $($_.Exception.Message)"
        return $defaultResult
    }
}

function Clear-WsusTrendData {
<#
.SYNOPSIS
    Removes the trends.json file, resetting all stored trend history.
.DESCRIPTION
    Deletes the WsusManager trends.json file located at
    %APPDATA%\WsusManager\trends.json. Safe to call even if the file
    does not exist.
.EXAMPLE
    Clear-WsusTrendData
#>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $path = Get-TrendsFilePath

    if (-not (Test-Path $path)) {
        Write-Verbose "WsusTrending: trends.json does not exist, nothing to clear."
        return
    }

    try {
        if ($PSCmdlet.ShouldProcess($path, "Delete trend data")) {
            Remove-Item -Path $path -Force -ErrorAction Stop
            Write-Verbose "WsusTrending: Trend data cleared  - $path"
        }
    } catch {
        Write-Verbose "WsusTrending: Clear-WsusTrendData failed  - $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Add-WsusTrendSnapshot, Get-WsusTrendSummary, Clear-WsusTrendData
