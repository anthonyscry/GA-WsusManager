<#
===============================================================================
Module: WsusAutoDetection.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-10
===============================================================================

.SYNOPSIS
    Enhanced WSUS auto-detection and automation functions

.DESCRIPTION
    Provides advanced detection and monitoring functions including:
    - Detailed service status with health indicators
    - Database size monitoring with threshold alerts
    - Certificate expiration detection
    - Disk space monitoring
    - Scheduled task status tracking
    - Automatic service recovery
    - Overall health status aggregation
#>

# ============================================================================
# DETAILED SERVICE STATUS
# ============================================================================

# Service definitions (cached at module level)
$script:WsusServiceDefinitions = @(
    @{ Name = "SQL Server Express"; ServiceName = "MSSQL`$SQLEXPRESS"; Critical = $true },
    @{ Name = "WSUS Service"; ServiceName = "WSUSService"; Critical = $true },
    @{ Name = "IIS (W3SVC)"; ServiceName = "W3SVC"; Critical = $true },
    @{ Name = "Windows Update"; ServiceName = "wuauserv"; Critical = $false },
    @{ Name = "BITS"; ServiceName = "bits"; Critical = $false }
)

function Get-DetailedServiceStatus {
    <#
    .SYNOPSIS
        Gets detailed status of all WSUS-related services with health indicators
    .DESCRIPTION
        Optimized to batch-query all services at once instead of individual calls.
        This reduces RPC calls to Service Control Manager from 5 to 1.
    .OUTPUTS
        Array of hashtables with service details
    #>

    # Batch query all services at once (performance optimization)
    # This is faster than calling Get-Service 5 times individually
    $serviceNames = $script:WsusServiceDefinitions | ForEach-Object { $_.ServiceName }
    $allServices = @{}

    Get-Service -Name $serviceNames -ErrorAction SilentlyContinue | ForEach-Object {
        $allServices[$_.Name] = $_
    }

    $results = @()
    foreach ($svcInfo in $script:WsusServiceDefinitions) {
        $svc = $allServices[$svcInfo.ServiceName]
        $result = @{
            Name = $svcInfo.Name
            ServiceName = $svcInfo.ServiceName
            Critical = $svcInfo.Critical
            Installed = ($null -ne $svc)
            Status = if ($svc) { $svc.Status.ToString() } else { "Not Installed" }
            StartType = if ($svc) { $svc.StartType.ToString() } else { "N/A" }
            Running = ($svc -and $svc.Status -eq "Running")
            CanAutoStart = ($svc -and $svc.StartType -in @("Automatic", "Manual"))
        }
        $results += $result
    }
    return $results
}

# ============================================================================
# SCHEDULED TASK STATUS
# ============================================================================
function Get-WsusScheduledTaskStatus {
    <#
    .SYNOPSIS
        Gets status of WSUS maintenance scheduled task
    .OUTPUTS
        Hashtable with task information
    #>
    param(
        [string]$TaskName = "WSUS Monthly Maintenance"
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            return @{
                Exists = $true
                TaskName = $TaskName
                State = $task.State.ToString()
                LastRunTime = if ($taskInfo) { $taskInfo.LastRunTime } else { $null }
                LastResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { $null }
                NextRunTime = if ($taskInfo) { $taskInfo.NextRunTime } else { $null }
                MissedRuns = if ($taskInfo) { $taskInfo.NumberOfMissedRuns } else { 0 }
            }
        }
    } catch {
        Write-Warning "Failed to get scheduled task status: $($_.Exception.Message)"
    }
    return @{ Exists = $false; TaskName = $TaskName }
}

# ============================================================================
# DATABASE SIZE STATUS
# ============================================================================
function Get-DatabaseSizeStatus {
    <#
    .SYNOPSIS
        Gets SUSDB size with threshold warnings
    .DESCRIPTION
        Monitors database size and alerts when approaching SQL Express 10GB limit
    .OUTPUTS
        Hashtable with size information and warnings
    #>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS",
        [decimal]$CriticalThresholdGB = 9.5,
        [decimal]$WarningThresholdGB = 8.0,
        [decimal]$ModerateThresholdGB = 5.0
    )

    $result = @{
        Available = $false
        SizeGB = 0
        Status = "Unknown"
        Warning = $null
        PercentOfLimit = 0
    }

    try {
        $sqlService = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
        if ($sqlService -and $sqlService.Status -eq "Running") {
            $query = "SELECT CAST(SUM(size * 8.0 / 1024 / 1024) AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id = DB_ID('SUSDB')"

            # Find sqlcmd.exe
            $sqlcmdPath = $null
            $possiblePaths = @(
                "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
                "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\sqlcmd.exe",
                "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\sqlcmd.exe"
            )
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) { $sqlcmdPath = $path; break }
            }
            if (-not $sqlcmdPath) {
                $sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source
            }

            if ($sqlcmdPath) {
                $output = & $sqlcmdPath -S $SqlInstance -d "master" -Q $query -h -1 -W 2>$null
                if ($output -and $output -match '[\d.]+') {
                    $sizeGB = [decimal]($Matches[0])
                    $result.Available = $true
                    $result.SizeGB = $sizeGB
                    $result.PercentOfLimit = [math]::Round(($sizeGB / 10) * 100, 1)

                    if ($sizeGB -ge $CriticalThresholdGB) {
                        $result.Status = "Critical"
                        $result.Warning = "Database at $($result.PercentOfLimit)% of 10GB SQL Express limit!"
                    } elseif ($sizeGB -ge $WarningThresholdGB) {
                        $result.Status = "Warning"
                        $result.Warning = "Database size is high ($sizeGB GB). Consider running cleanup."
                    } elseif ($sizeGB -ge $ModerateThresholdGB) {
                        $result.Status = "Moderate"
                    } else {
                        $result.Status = "Healthy"
                    }
                }
            }
        }
    } catch {
        Write-Warning "Failed to query database size: $($_.Exception.Message)"
    }

    return $result
}

# ============================================================================
# CERTIFICATE STATUS
# ============================================================================
function Get-WsusCertificateStatus {
    <#
    .SYNOPSIS
        Gets WSUS HTTPS certificate status with expiration warning
    .DESCRIPTION
        Checks if HTTPS is enabled and monitors certificate expiration
    .OUTPUTS
        Hashtable with certificate information and warnings
    #>
    param(
        [int]$CriticalDays = 14,
        [int]$WarningDays = 30
    )

    $result = @{
        SSLEnabled = $false
        CertificateFound = $false
        ExpiresIn = $null
        ExpirationDate = $null
        Thumbprint = $null
        Subject = $null
        Warning = $null
    }

    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        if (Get-Module WebAdministration) {
            # Find WSUS website
            $wsussite = Get-Website | Where-Object { $_.Name -like "*WSUS*" } | Select-Object -First 1
            if (-not $wsussite) {
                $wsussite = Get-Website | Where-Object { $_.Id -eq 1 } | Select-Object -First 1
            }

            if ($wsussite) {
                $httpsBinding = Get-WebBinding -Name $wsussite.Name -Protocol "https" -Port 8531 -ErrorAction SilentlyContinue
                if ($httpsBinding) {
                    $result.SSLEnabled = $true
                    $certHash = $httpsBinding.certificateHash
                    if ($certHash) {
                        $result.Thumbprint = $certHash
                        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -ieq $certHash }
                        if ($cert) {
                            $result.CertificateFound = $true
                            $result.Subject = $cert.Subject
                            $result.ExpirationDate = $cert.NotAfter
                            $daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
                            $result.ExpiresIn = $daysUntilExpiry

                            if ($daysUntilExpiry -le 0) {
                                $result.Warning = "Certificate EXPIRED!"
                            } elseif ($daysUntilExpiry -le $CriticalDays) {
                                $result.Warning = "Certificate expires in $daysUntilExpiry days - URGENT!"
                            } elseif ($daysUntilExpiry -le $WarningDays) {
                                $result.Warning = "Certificate expires in $daysUntilExpiry days"
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warning "Failed to get certificate status: $($_.Exception.Message)"
    }

    return $result
}

# ============================================================================
# DISK SPACE STATUS
# ============================================================================
function Get-WsusDiskSpaceStatus {
    <#
    .SYNOPSIS
        Gets disk space status for WSUS content path
    .OUTPUTS
        Hashtable with disk space information and warnings
    #>
    param(
        [string]$ContentPath = "C:\WSUS",
        [decimal]$CriticalFreeGB = 5,
        [decimal]$WarningFreeGB = 20
    )

    $result = @{
        Available = $false
        Path = $ContentPath
        DriveLetter = $null
        FreeGB = 0
        TotalGB = 0
        UsedGB = 0
        UsedPercent = 0
        Status = "Unknown"
        Warning = $null
    }

    try {
        if ($ContentPath -and (Test-Path $ContentPath)) {
            $drive = (Get-Item $ContentPath).PSDrive
            if ($drive -and $drive.Free) {
                $freeGB = [math]::Round($drive.Free / 1GB, 2)
                $usedGB = [math]::Round($drive.Used / 1GB, 2)
                $totalGB = $freeGB + $usedGB

                $result.Available = $true
                $result.DriveLetter = $drive.Name
                $result.FreeGB = $freeGB
                $result.TotalGB = $totalGB
                $result.UsedGB = $usedGB
                $result.UsedPercent = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

                if ($freeGB -lt $CriticalFreeGB) {
                    $result.Status = "Critical"
                    $result.Warning = "Only $freeGB GB free - downloads may fail!"
                } elseif ($freeGB -lt $WarningFreeGB) {
                    $result.Status = "Warning"
                    $result.Warning = "Low disk space ($freeGB GB free)"
                } else {
                    $result.Status = "Healthy"
                }
            }
        }
    } catch {
        Write-Warning "Failed to check disk space: $($_.Exception.Message)"
    }

    return $result
}

# ============================================================================
# OVERALL HEALTH STATUS
# ============================================================================
function Get-WsusOverallHealth {
    <#
    .SYNOPSIS
        Calculates overall WSUS system health based on all checks
    .DESCRIPTION
        Aggregates all health checks and provides an overall status
    .OUTPUTS
        Hashtable with comprehensive health information
    #>
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $services = Get-DetailedServiceStatus
    $dbStatus = Get-DatabaseSizeStatus -SqlInstance $SqlInstance
    $certStatus = Get-WsusCertificateStatus
    $diskStatus = Get-WsusDiskSpaceStatus -ContentPath $ContentPath
    $taskStatus = Get-WsusScheduledTaskStatus

    $issues = @()
    $warnings = @()
    $status = "Healthy"

    # Check critical services
    $criticalDown = $services | Where-Object { $_.Critical -and -not $_.Running }
    if ($criticalDown) {
        $status = "Unhealthy"
        foreach ($svc in $criticalDown) {
            $issues += "$($svc.Name) is not running"
        }
    }

    # Check database size
    if ($dbStatus.Status -eq "Critical") {
        $status = "Unhealthy"
        $issues += $dbStatus.Warning
    } elseif ($dbStatus.Status -eq "Warning" -and $status -ne "Unhealthy") {
        $status = "Degraded"
        $warnings += $dbStatus.Warning
    }

    # Check certificate
    if ($certStatus.Warning -and $certStatus.Warning -match "EXPIRED") {
        $status = "Unhealthy"
        $issues += $certStatus.Warning
    } elseif ($certStatus.Warning -and $status -ne "Unhealthy") {
        if ($status -eq "Healthy") { $status = "Degraded" }
        $warnings += $certStatus.Warning
    }

    # Check disk space
    if ($diskStatus.Status -eq "Critical") {
        $status = "Unhealthy"
        $issues += $diskStatus.Warning
    } elseif ($diskStatus.Status -eq "Warning" -and $status -ne "Unhealthy") {
        if ($status -eq "Healthy") { $status = "Degraded" }
        $warnings += $diskStatus.Warning
    }

    # Check scheduled task
    if (-not $taskStatus.Exists) {
        $warnings += "No scheduled maintenance task configured"
    } elseif ($taskStatus.MissedRuns -gt 0) {
        $warnings += "Scheduled task has $($taskStatus.MissedRuns) missed runs"
    }

    return @{
        Status = $status
        Timestamp = Get-Date
        Services = $services
        Database = $dbStatus
        Certificate = $certStatus
        DiskSpace = $diskStatus
        ScheduledTask = $taskStatus
        Issues = $issues
        Warnings = $warnings
        IssueCount = $issues.Count
        WarningCount = $warnings.Count
    }
}

# ============================================================================
# AUTO SERVICE RECOVERY
# ============================================================================
function Start-WsusAutoRecovery {
    <#
    .SYNOPSIS
        Attempts to automatically recover stopped critical services
    .DESCRIPTION
        Starts services in dependency order with retry logic
    .OUTPUTS
        Hashtable with recovery results
    #>
    param(
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5,
        [switch]$WhatIf
    )

    $results = @{
        Timestamp = Get-Date
        Attempted = @()
        Recovered = @()
        Failed = @()
        AlreadyRunning = @()
        Success = $true
    }

    # Services in dependency order
    $criticalServices = @(
        @{ Name = "SQL Server Express"; ServiceName = "MSSQL`$SQLEXPRESS"; Order = 1 },
        @{ Name = "IIS"; ServiceName = "W3SVC"; Order = 2 },
        @{ Name = "WSUS Service"; ServiceName = "WSUSService"; Order = 3 }
    )

    foreach ($svcInfo in ($criticalServices | Sort-Object { $_.Order })) {
        $svc = Get-Service -Name $svcInfo.ServiceName -ErrorAction SilentlyContinue

        if (-not $svc) {
            Write-Warning "$($svcInfo.Name) is not installed"
            continue
        }

        if ($svc.Status -eq "Running") {
            $results.AlreadyRunning += $svcInfo.Name
            continue
        }

        $results.Attempted += $svcInfo.Name

        if ($WhatIf) {
            Write-Host "WhatIf: Would attempt to start $($svcInfo.Name)" -ForegroundColor Yellow
            continue
        }

        $recovered = $false
        for ($i = 1; $i -le $MaxRetries; $i++) {
            try {
                Write-Host "  Starting $($svcInfo.Name) (attempt $i of $MaxRetries)..." -ForegroundColor Yellow
                Start-Service -Name $svcInfo.ServiceName -ErrorAction Stop
                Start-Sleep -Seconds 3

                # Re-query the service to get fresh status instead of using Refresh()
                # This avoids issues where Get-Service returns a PSCustomObject
                $svcCheck = Get-Service -Name $svcInfo.ServiceName -ErrorAction SilentlyContinue
                if ($svcCheck -and $svcCheck.Status -eq "Running") {
                    Write-Host "  $($svcInfo.Name) started successfully" -ForegroundColor Green
                    $recovered = $true
                    break
                }
            } catch {
                Write-Warning "  Attempt $i failed: $($_.Exception.Message)"
                if ($i -lt $MaxRetries) {
                    Start-Sleep -Seconds $RetryDelaySeconds
                }
            }
        }

        if ($recovered) {
            $results.Recovered += $svcInfo.Name
        } else {
            $results.Failed += $svcInfo.Name
            $results.Success = $false
        }
    }

    return $results
}

# ============================================================================
# MONITORING TIMER FUNCTIONS
# ============================================================================
function Start-WsusHealthMonitor {
    <#
    .SYNOPSIS
        Starts a background health monitoring job
    .DESCRIPTION
        Periodically checks WSUS health and can trigger notifications
    .OUTPUTS
        Job object for the monitoring job
    #>
    param(
        [int]$IntervalSeconds = 300,  # 5 minutes default
        [string]$ContentPath = "C:\WSUS",
        [switch]$AutoRecover
    )

    $scriptBlock = {
        param($IntervalSeconds, $ContentPath, $AutoRecover, $ModulePath)

        # Import module in job runspace (Start-Job creates a clean process)
        if ($ModulePath -and (Test-Path $ModulePath)) {
            Import-Module $ModulePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
        }

        while ($true) {
            $health = Get-WsusOverallHealth -ContentPath $ContentPath

            if ($AutoRecover -and $health.Status -eq "Unhealthy") {
                $criticalDown = $health.Services | Where-Object { $_.Critical -and -not $_.Running }
                if ($criticalDown) {
                    Start-WsusAutoRecovery
                }
            }

            Start-Sleep -Seconds $IntervalSeconds
        }
    }

    $moduleSelf = Join-Path $PSScriptRoot "WsusAutoDetection.psm1"
    Start-Job -ScriptBlock $scriptBlock -ArgumentList $IntervalSeconds, $ContentPath, $AutoRecover, $moduleSelf -Name "WsusHealthMonitor"
}

function Stop-WsusHealthMonitor {
    <#
    .SYNOPSIS
        Stops the background health monitoring job
    #>
    Get-Job -Name "WsusHealthMonitor" -ErrorAction SilentlyContinue | Stop-Job -PassThru | Remove-Job
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================
function Show-WsusHealthSummary {
    <#
    .SYNOPSIS
        Displays a formatted health summary to the console
    #>
    param(
        [string]$ContentPath = "C:\WSUS"
    )

    $health = Get-WsusOverallHealth -ContentPath $ContentPath

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " WSUS Health Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Overall Status
    $statusColor = switch ($health.Status) {
        "Healthy" { "Green" }
        "Degraded" { "Yellow" }
        "Unhealthy" { "Red" }
        default { "Gray" }
    }
    Write-Host "Overall Status: " -NoNewline
    Write-Host $health.Status -ForegroundColor $statusColor
    Write-Host ""

    # Services
    Write-Host "Services:" -ForegroundColor White
    foreach ($svc in $health.Services) {
        $svcColor = if ($svc.Running) { "Green" } else { if ($svc.Critical) { "Red" } else { "Yellow" } }
        $status = if ($svc.Running) { "Running" } else { $svc.Status }
        $marker = if ($svc.Critical) { "*" } else { " " }
        Write-Host "  $marker $($svc.Name): " -NoNewline
        Write-Host $status -ForegroundColor $svcColor
    }
    Write-Host ""

    # Database
    if ($health.Database.Available) {
        Write-Host "Database: " -NoNewline
        $dbColor = switch ($health.Database.Status) {
            "Healthy" { "Green" }
            "Moderate" { "Cyan" }
            "Warning" { "Yellow" }
            "Critical" { "Red" }
            default { "Gray" }
        }
        Write-Host "$($health.Database.SizeGB) GB " -ForegroundColor $dbColor -NoNewline
        Write-Host "($($health.Database.PercentOfLimit)% of 10GB limit)"
    }

    # Disk Space
    if ($health.DiskSpace.Available) {
        Write-Host "Disk Space: " -NoNewline
        $diskColor = switch ($health.DiskSpace.Status) {
            "Healthy" { "Green" }
            "Warning" { "Yellow" }
            "Critical" { "Red" }
            default { "Gray" }
        }
        Write-Host "$($health.DiskSpace.FreeGB) GB free " -ForegroundColor $diskColor -NoNewline
        Write-Host "($($health.DiskSpace.UsedPercent)% used)"
    }

    # Certificate
    if ($health.Certificate.SSLEnabled) {
        Write-Host "Certificate: " -NoNewline
        if ($health.Certificate.Warning) {
            Write-Host $health.Certificate.Warning -ForegroundColor Yellow
        } else {
            Write-Host "Valid (expires in $($health.Certificate.ExpiresIn) days)" -ForegroundColor Green
        }
    } else {
        Write-Host "Certificate: " -NoNewline
        Write-Host "HTTP only (no SSL)" -ForegroundColor Gray
    }

    # Scheduled Task
    Write-Host "Scheduled Task: " -NoNewline
    if ($health.ScheduledTask.Exists) {
        $taskColor = if ($health.ScheduledTask.State -eq "Ready") { "Green" } else { "Yellow" }
        Write-Host "$($health.ScheduledTask.State)" -ForegroundColor $taskColor -NoNewline
        if ($health.ScheduledTask.NextRunTime) {
            Write-Host " (Next: $($health.ScheduledTask.NextRunTime))"
        } else {
            Write-Host ""
        }
    } else {
        Write-Host "Not configured" -ForegroundColor Yellow
    }

    Write-Host ""

    # Issues and Warnings
    if ($health.Issues.Count -gt 0) {
        Write-Host "Issues:" -ForegroundColor Red
        foreach ($issue in $health.Issues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
        Write-Host ""
    }

    if ($health.Warnings.Count -gt 0) {
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($warning in $health.Warnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    return $health
}

#region Dashboard Data Functions

# Module-level cache state
$script:DashboardCache = $null
$script:DashboardCacheTime = [DateTime]::MinValue
$script:DashboardCacheTTLSeconds = 30
$script:DashboardFailureCount = 0
$script:DashboardMaxFailures = 10  # 5 minutes at 30s intervals

function Get-WsusDashboardServiceStatus {
<#
.SYNOPSIS Gets WSUS-related service running status.
.OUTPUTS Hashtable: @{ Running=[int]; Names=[string[]] }
#>
    $result = @{Running=0; Names=@()}
    foreach ($svc in @("MSSQL`$SQLEXPRESS","WSUSService","W3SVC")) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq "Running") {
                $result.Running++
                $result.Names += switch($svc){"MSSQL`$SQLEXPRESS"{"SQL"}"WSUSService"{"WSUS"}"W3SVC"{"IIS"}}
            }
        } catch { }
    }
    return $result
}

function Get-WsusDashboardDiskFreeGB {
<#
.SYNOPSIS Gets free disk space on C: in GB.
.OUTPUTS [double] Free GB, or 0 on error.
#>
    try {
        $d = Get-PSDrive -Name "C" -ErrorAction SilentlyContinue
        if ($d.Free) { return [math]::Round($d.Free/1GB,1) }
    } catch { }
    return 0
}

function Get-WsusDashboardDatabaseSizeGB {
    param([string]$SqlInstance = ".\SQLEXPRESS")
<#
.SYNOPSIS Gets SUSDB database size in GB.
.OUTPUTS [double] Size in GB, or -1 if SQL offline or error.
#>
    try {
        $sql = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
        if ($sql -and $sql.Status -eq "Running") {
            # Import WsusDatabase module for Invoke-WsusSqlcmd wrapper (only if not already loaded)
            if (-not (Get-Module WsusDatabase -ErrorAction SilentlyContinue)) {
                $dbModule = Join-Path $PSScriptRoot "WsusDatabase.psm1"
                if (Test-Path $dbModule) {
                    Import-Module $dbModule -DisableNameChecking -ErrorAction SilentlyContinue
                }
            }
            $q = "SELECT SUM(size * 8 / 1024.0) AS SizeMB FROM sys.master_files WHERE database_id = DB_ID('SUSDB')"
            $r = $null
            if (Get-Command Invoke-WsusSqlcmd -ErrorAction SilentlyContinue) {
                $r = Invoke-WsusSqlcmd -Query $q -SqlInstance $SqlInstance -ErrorAction SilentlyContinue
            } else {
                $r = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $q -ErrorAction SilentlyContinue
            }
            if ($r -and $r.SizeMB) { return [math]::Round($r.SizeMB / 1024, 2) }
        }
    } catch { }
    return -1
}

function Get-WsusDashboardTaskStatus {
<#
.SYNOPSIS Gets the Windows Scheduled Task state for WSUS Maintenance.
.OUTPUTS [string] Task state (e.g., "Ready", "Running", "Not Set")
#>
    try {
        $t = Get-ScheduledTask -TaskName "WSUS Monthly Maintenance" -ErrorAction SilentlyContinue
        if ($t) { return $t.State.ToString() }
    } catch { }
    return "Not Set"
}

function Test-WsusDashboardInternetConnection {
<#
.SYNOPSIS Non-blocking internet connectivity check using .NET Ping (500ms timeout).
.OUTPUTS [bool]
#>
    $ping = $null
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send("8.8.8.8", 500)
        return ($null -ne $reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
    } catch { return $false }
    finally { if ($null -ne $ping) { $ping.Dispose() } }
}

function Get-WsusDashboardData {
<#
.SYNOPSIS
    Collects all dashboard data in a single call. Designed to run in a background runspace.
.DESCRIPTION
    Returns a hashtable with all dashboard card data. Safe to call from a runspace.
    Pass resolved module directory path as argument since $PSScriptRoot may not be available.
.PARAMETER SqlInstance
    SQL Server instance. Default ".\SQLEXPRESS".
.PARAMETER ModulePath
    Path to the Modules directory (pass explicitly when calling from runspace).
.OUTPUTS
    Hashtable: @{
        Services = @{Running=int; Names=string[]}
        DiskFreeGB = double
        DatabaseSizeGB = double (or -1)
        TaskStatus = string
        IsOnline = bool
        CollectedAt = DateTime
        Error = string (or $null)
    }
#>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS",
        [string]$ModulePath = ""
    )
    $data = @{
        Services = @{Running=0; Names=@()}
        DiskFreeGB = 0
        DatabaseSizeGB = -1
        TaskStatus = "Not Set"
        IsOnline = $false
        CollectedAt = Get-Date
        Error = $null
    }
    try {
        # Import self if running in a runspace (PSScriptRoot not available)
        if ($ModulePath -and (Test-Path $ModulePath)) {
            $autoDetectModule = Join-Path $ModulePath "WsusAutoDetection.psm1"
            if (Test-Path $autoDetectModule) {
                Import-Module $autoDetectModule -Force -DisableNameChecking -ErrorAction SilentlyContinue
            }
        }
        $data.Services = Get-WsusDashboardServiceStatus
        $data.DiskFreeGB = Get-WsusDashboardDiskFreeGB
        $data.DatabaseSizeGB = Get-WsusDashboardDatabaseSizeGB -SqlInstance $SqlInstance
        $data.TaskStatus = Get-WsusDashboardTaskStatus
        $data.IsOnline = Test-WsusDashboardInternetConnection
    } catch {
        $data.Error = $_.Exception.Message
    }
    return $data
}

function Get-WsusDashboardCachedData {
<#
.SYNOPSIS Returns cached dashboard data if fresh, otherwise $null.
#>
    param([string]$SqlInstance = ".\SQLEXPRESS")
    $age = ([DateTime]::Now - $script:DashboardCacheTime).TotalSeconds
    if ($null -ne $script:DashboardCache -and $age -lt $script:DashboardCacheTTLSeconds) {
        return $script:DashboardCache
    }
    return $null
}

function Set-WsusDashboardCache {
<#
.SYNOPSIS Updates the dashboard data cache with fresh data.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param([hashtable]$Data)
    if ($null -ne $Data -and $null -eq $Data.Error) {
        $script:DashboardCache = $Data
        $script:DashboardCacheTime = [DateTime]::Now
        $script:DashboardFailureCount = 0
    } else {
        $script:DashboardFailureCount++
    }
}

function Test-WsusDashboardDataUnavailable {
<#
.SYNOPSIS Returns $true if dashboard has failed too many consecutive times.
#>
    return $script:DashboardFailureCount -ge $script:DashboardMaxFailures
}

#endregion Dashboard Data Functions

# ============================================================================
# EXPORTS
# ============================================================================
Export-ModuleMember -Function @(
    'Get-DetailedServiceStatus',
    'Get-WsusScheduledTaskStatus',
    'Get-DatabaseSizeStatus',
    'Get-WsusCertificateStatus',
    'Get-WsusDiskSpaceStatus',
    'Get-WsusOverallHealth',
    'Start-WsusAutoRecovery',
    'Start-WsusHealthMonitor',
    'Stop-WsusHealthMonitor',
    'Show-WsusHealthSummary',
    'Get-WsusDashboardServiceStatus',
    'Get-WsusDashboardDiskFreeGB',
    'Get-WsusDashboardDatabaseSizeGB',
    'Get-WsusDashboardTaskStatus',
    'Test-WsusDashboardInternetConnection',
    'Get-WsusDashboardData',
    'Get-WsusDashboardCachedData',
    'Set-WsusDashboardCache',
    'Test-WsusDashboardDataUnavailable'
)
