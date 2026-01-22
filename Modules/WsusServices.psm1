<#
===============================================================================
Module: WsusServices.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS service management functions

.DESCRIPTION
    Provides standardized functions for managing WSUS-related services including:
    - SQL Server Express
    - WSUS Service
    - IIS (W3SVC)
    - Service health checks
#>

# ===========================
# SERVICE WAIT FUNCTIONS
# ===========================

function Wait-ServiceState {
    <#
    .SYNOPSIS
        Waits for a service to reach a specific state with timeout

    .PARAMETER ServiceName
        Name of the service to wait for

    .PARAMETER TargetState
        Target state: Running, Stopped, Paused

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait (default: 60)

    .PARAMETER PollIntervalMs
        Milliseconds between status checks (default: 500)

    .OUTPUTS
        Boolean indicating if target state was reached
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [ValidateSet('Running', 'Stopped', 'Paused')]
        [string]$TargetState,

        [int]$TimeoutSeconds = 60,

        [int]$PollIntervalMs = 500
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $service = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($service.Status -eq $TargetState) {
                $stopwatch.Stop()
                return $true
            }
        } catch {
            # Service not found
            $stopwatch.Stop()
            return $false
        }

        Start-Sleep -Milliseconds $PollIntervalMs
    }

    $stopwatch.Stop()
    Write-Warning "Timeout waiting for $ServiceName to reach $TargetState state after $TimeoutSeconds seconds"
    return $false
}

# ===========================
# SERVICE CHECK FUNCTIONS
# ===========================

function Test-ServiceRunning {
    <#
    .SYNOPSIS
        Checks if a service is running

    .PARAMETER ServiceName
        Name of the service to check

    .OUTPUTS
        Boolean indicating if service is running
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return ($service.Status -eq "Running")
    } catch {
        return $false
    }
}

function Test-ServiceExists {
    <#
    .SYNOPSIS
        Checks if a service exists

    .PARAMETER ServiceName
        Name of the service to check

    .OUTPUTS
        Boolean indicating if service exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    try {
        Get-Service -Name $ServiceName -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ===========================
# SERVICE START/STOP FUNCTIONS
# ===========================

function Start-WsusService {
    <#
    .SYNOPSIS
        Starts a WSUS-related service with error handling

    .PARAMETER ServiceName
        Name of the service to start

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for service to start (default: 60)

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [int]$TimeoutSeconds = 60
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq "Running") {
            Write-Host "  $ServiceName is already running" -ForegroundColor Green
            return $true
        }

        Write-Host "  Starting $ServiceName..." -ForegroundColor Yellow
        Start-Service $ServiceName -ErrorAction Stop

        # Wait for service to actually start using proper polling
        $started = Wait-ServiceState -ServiceName $ServiceName -TargetState 'Running' -TimeoutSeconds $TimeoutSeconds
        if ($started) {
            Write-Host "  $ServiceName started successfully" -ForegroundColor Green
            return $true
        } else {
            $service.Refresh()
            Write-Warning "  $ServiceName did not start within $TimeoutSeconds seconds (Status: $($service.Status))"
            return $false
        }
    } catch {
        Write-Warning "  Failed to start $ServiceName : $($_.Exception.Message)"
        return $false
    }
}

function Stop-WsusService {
    <#
    .SYNOPSIS
        Stops a WSUS-related service with error handling

    .PARAMETER ServiceName
        Name of the service to stop

    .PARAMETER Force
        Force stop the service

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for service to stop (default: 60)

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [switch]$Force,

        [int]$TimeoutSeconds = 60
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq "Stopped") {
            Write-Host "  $ServiceName is already stopped" -ForegroundColor Green
            return $true
        }

        Write-Host "  Stopping $ServiceName..." -ForegroundColor Yellow

        if ($Force) {
            Stop-Service $ServiceName -Force -ErrorAction Stop -NoWait
        } else {
            Stop-Service $ServiceName -ErrorAction Stop -NoWait
        }

        # Wait for service to actually stop using proper polling
        $stopped = Wait-ServiceState -ServiceName $ServiceName -TargetState 'Stopped' -TimeoutSeconds $TimeoutSeconds
        if ($stopped) {
            Write-Host "  $ServiceName stopped successfully" -ForegroundColor Green
            return $true
        } else {
            $service.Refresh()
            Write-Warning "  $ServiceName did not stop within $TimeoutSeconds seconds (Status: $($service.Status))"
            return $false
        }
    } catch {
        Write-Warning "  Failed to stop $ServiceName : $($_.Exception.Message)"
        return $false
    }
}

function Restart-WsusService {
    <#
    .SYNOPSIS
        Restarts a WSUS-related service

    .PARAMETER ServiceName
        Name of the service to restart

    .PARAMETER Force
        Force stop before restart

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [switch]$Force
    )

    Write-Host "Restarting $ServiceName..." -ForegroundColor Yellow

    $stopped = Stop-WsusService -ServiceName $ServiceName -Force:$Force
    if (-not $stopped) {
        return $false
    }

    $started = Start-WsusService -ServiceName $ServiceName
    return $started
}

# ===========================
# WSUS-SPECIFIC SERVICE FUNCTIONS
# ===========================

function Start-SqlServerExpress {
    <#
    .SYNOPSIS
        Starts SQL Server Express instance

    .PARAMETER InstanceName
        SQL Server instance name (default: SQLEXPRESS)

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [string]$InstanceName = "SQLEXPRESS"
    )

    $serviceName = "MSSQL`$$InstanceName"
    return Start-WsusService -ServiceName $serviceName -TimeoutSeconds 10
}

function Stop-SqlServerExpress {
    <#
    .SYNOPSIS
        Stops SQL Server Express instance

    .PARAMETER InstanceName
        SQL Server instance name (default: SQLEXPRESS)

    .PARAMETER Force
        Force stop the service

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [string]$InstanceName = "SQLEXPRESS",
        [switch]$Force
    )

    $serviceName = "MSSQL`$$InstanceName"
    return Stop-WsusService -ServiceName $serviceName -Force:$Force
}

function Start-SqlBrowserService {
    <#
    .SYNOPSIS
        Starts SQL Server Browser service

    .DESCRIPTION
        Starts the SQL Browser service and sets it to Automatic startup.
        SQL Browser is recommended for named SQL Server instances.

    .OUTPUTS
        Boolean indicating success
    #>
    try {
        $service = Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Warning "  SQL Browser service not found"
            return $false
        }

        # Set to Automatic startup
        Set-Service -Name 'SQLBrowser' -StartupType Automatic -ErrorAction SilentlyContinue

        return Start-WsusService -ServiceName 'SQLBrowser' -TimeoutSeconds 30
    } catch {
        Write-Warning "  Failed to start SQL Browser: $($_.Exception.Message)"
        return $false
    }
}

function Stop-SqlBrowserService {
    <#
    .SYNOPSIS
        Stops SQL Server Browser service

    .PARAMETER Force
        Force stop the service

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [switch]$Force
    )

    return Stop-WsusService -ServiceName 'SQLBrowser' -Force:$Force
}

function Start-WsusServer {
    <#
    .SYNOPSIS
        Starts WSUS Server service

    .OUTPUTS
        Boolean indicating success
    #>
    return Start-WsusService -ServiceName "WSUSService" -TimeoutSeconds 10
}

function Stop-WsusServer {
    <#
    .SYNOPSIS
        Stops WSUS Server service

    .PARAMETER Force
        Force stop the service

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [switch]$Force
    )

    return Stop-WsusService -ServiceName "WSUSService" -Force:$Force -TimeoutSeconds 5
}

function Start-IISService {
    <#
    .SYNOPSIS
        Starts IIS World Wide Web Publishing Service

    .OUTPUTS
        Boolean indicating success
    #>
    return Start-WsusService -ServiceName "W3SVC" -TimeoutSeconds 5
}

function Stop-IISService {
    <#
    .SYNOPSIS
        Stops IIS World Wide Web Publishing Service

    .PARAMETER Force
        Force stop the service

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [switch]$Force
    )

    return Stop-WsusService -ServiceName "W3SVC" -Force:$Force
}

# ===========================
# COMPREHENSIVE SERVICE MANAGEMENT
# ===========================

function Start-AllWsusServices {
    <#
    .SYNOPSIS
        Starts all WSUS-related services in correct order

    .OUTPUTS
        Hashtable with results for each service
    #>
    Write-Host "Starting all WSUS services..." -ForegroundColor Cyan

    $results = @{
        SqlServer = Start-SqlServerExpress
        IIS = Start-IISService
        WSUS = Start-WsusServer
    }

    if ($results.SqlServer -and $results.IIS -and $results.WSUS) {
        Write-Host "All WSUS services started successfully" -ForegroundColor Green
    } else {
        Write-Warning "Some services failed to start"
    }

    return $results
}

function Stop-AllWsusServices {
    <#
    .SYNOPSIS
        Stops all WSUS-related services in correct order

    .PARAMETER Force
        Force stop all services

    .OUTPUTS
        Hashtable with results for each service
    #>
    param(
        [switch]$Force
    )

    Write-Host "Stopping all WSUS services..." -ForegroundColor Cyan

    # Stop in reverse order
    $results = @{
        WSUS = Stop-WsusServer -Force:$Force
        IIS = Stop-IISService -Force:$Force
        SqlServer = Stop-SqlServerExpress -Force:$Force
    }

    if ($results.WSUS -and $results.IIS -and $results.SqlServer) {
        Write-Host "All WSUS services stopped successfully" -ForegroundColor Green
    } else {
        Write-Warning "Some services failed to stop"
    }

    return $results
}

function Get-WsusServiceStatus {
    <#
    .SYNOPSIS
        Gets status of all WSUS-related services

    .PARAMETER IncludeSqlBrowser
        Include SQL Browser service in the status check (default: $false)

    .OUTPUTS
        Hashtable with service status information
    #>
    param(
        [switch]$IncludeSqlBrowser
    )

    $services = @{
        "SQL Server Express" = "MSSQL`$SQLEXPRESS"
        "WSUS Service" = "WSUSService"
        "IIS" = "W3SVC"
    }

    if ($IncludeSqlBrowser) {
        $services["SQL Browser"] = "SQLBrowser"
    }

    $status = @{}

    foreach ($name in $services.Keys) {
        $serviceName = $services[$name]
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $status[$name] = @{
                Status = $service.Status.ToString()
                StartType = $service.StartType.ToString()
                Running = ($service.Status -eq "Running")
            }
        } catch {
            $status[$name] = @{
                Status = "Not Found"
                StartType = "N/A"
                Running = $false
            }
        }
    }

    return $status
}

# Export functions
Export-ModuleMember -Function @(
    'Wait-ServiceState',
    'Test-ServiceRunning',
    'Test-ServiceExists',
    'Start-WsusService',
    'Stop-WsusService',
    'Restart-WsusService',
    'Start-SqlServerExpress',
    'Stop-SqlServerExpress',
    'Start-SqlBrowserService',
    'Stop-SqlBrowserService',
    'Start-WsusServer',
    'Stop-WsusServer',
    'Start-IISService',
    'Stop-IISService',
    'Start-AllWsusServices',
    'Stop-AllWsusServices',
    'Get-WsusServiceStatus'
)
