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

    .PARAMETER WaitSeconds
        Seconds to wait after starting (default: 5)

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [int]$WaitSeconds = 5
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq "Running") {
            Write-Host "  $ServiceName is already running" -ForegroundColor Green
            return $true
        }

        Write-Host "  Starting $ServiceName..." -ForegroundColor Yellow
        Start-Service $ServiceName -ErrorAction Stop

        if ($WaitSeconds -gt 0) {
            Start-Sleep -Seconds $WaitSeconds
        }

        $service.Refresh()
        if ($service.Status -eq "Running") {
            Write-Host "  $ServiceName started successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "  $ServiceName did not start properly (Status: $($service.Status))"
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

    .PARAMETER WaitSeconds
        Seconds to wait after stopping (default: 3)

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [switch]$Force,

        [int]$WaitSeconds = 3
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq "Stopped") {
            Write-Host "  $ServiceName is already stopped" -ForegroundColor Green
            return $true
        }

        Write-Host "  Stopping $ServiceName..." -ForegroundColor Yellow

        if ($Force) {
            Stop-Service $ServiceName -Force -ErrorAction Stop
        } else {
            Stop-Service $ServiceName -ErrorAction Stop
        }

        if ($WaitSeconds -gt 0) {
            Start-Sleep -Seconds $WaitSeconds
        }

        $service.Refresh()
        if ($service.Status -eq "Stopped") {
            Write-Host "  $ServiceName stopped successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "  $ServiceName did not stop properly (Status: $($service.Status))"
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
    return Start-WsusService -ServiceName $serviceName -WaitSeconds 10
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

function Start-WsusServer {
    <#
    .SYNOPSIS
        Starts WSUS Server service

    .OUTPUTS
        Boolean indicating success
    #>
    return Start-WsusService -ServiceName "WSUSService" -WaitSeconds 10
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

    return Stop-WsusService -ServiceName "WSUSService" -Force:$Force -WaitSeconds 5
}

function Start-IISService {
    <#
    .SYNOPSIS
        Starts IIS World Wide Web Publishing Service

    .OUTPUTS
        Boolean indicating success
    #>
    return Start-WsusService -ServiceName "W3SVC" -WaitSeconds 5
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

    .OUTPUTS
        Hashtable with service status information
    #>
    $services = @{
        "SQL Server Express" = "MSSQL`$SQLEXPRESS"
        "WSUS Service" = "WSUSService"
        "IIS" = "W3SVC"
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
    'Test-ServiceRunning',
    'Test-ServiceExists',
    'Start-WsusService',
    'Stop-WsusService',
    'Restart-WsusService',
    'Start-SqlServerExpress',
    'Stop-SqlServerExpress',
    'Start-WsusServer',
    'Stop-WsusServer',
    'Start-IISService',
    'Stop-IISService',
    'Start-AllWsusServices',
    'Stop-AllWsusServices',
    'Get-WsusServiceStatus'
)
