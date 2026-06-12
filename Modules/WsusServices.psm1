<#
===============================================================================
Module: WsusServices.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 2.0.0
Date: 2026-06-09
===============================================================================

.SYNOPSIS
    WSUS service management functions (narrowed interface)

.DESCRIPTION
    Provides standardized functions for managing WSUS-related services.
    Per-service wrappers (Start-SqlServerExpress, Start-WsusServer, etc.)
    are now internal — callers use Start-WsusService with the service name.

    Narrowed from 17 exports to 6: Get/Start/Stop/Restart/GetStatus + Start/Stop-All.
    The per-service wrappers still exist as private helper functions.
#>

function Wait-ServiceState {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [Parameter(Mandatory)][ValidateSet('Running', 'Stopped', 'Paused')][string]$TargetState,
        [int]$TimeoutSeconds = 60,
        [int]$PollIntervalMs = 500
    )
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $service = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($service.Status -eq $TargetState) { $stopwatch.Stop(); return $true }
        } catch { $stopwatch.Stop(); return $false }
        Start-Sleep -Milliseconds $PollIntervalMs
    }
    $stopwatch.Stop()
    Write-Warning "Timeout waiting for $ServiceName to reach $TargetState state after $TimeoutSeconds seconds"
    return $false
}

function Test-ServiceRunning {
    param([Parameter(Mandatory)][string]$ServiceName)
    try { $service = Get-Service -Name $ServiceName -ErrorAction Stop; return ($service.Status -eq "Running") }
    catch { return $false }
}

function Test-ServiceExists {
    param([Parameter(Mandatory)][string]$ServiceName)
    try { Get-Service -Name $ServiceName -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Start-WsusService {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [int]$TimeoutSeconds = 60
    )
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -eq "Running") { Write-Host "  $ServiceName is already running" -ForegroundColor Green; return $true }
        Write-Host "  Starting $ServiceName..." -ForegroundColor Yellow
        Start-Service $ServiceName -ErrorAction Stop
        $started = Wait-ServiceState -ServiceName $ServiceName -TargetState 'Running' -TimeoutSeconds $TimeoutSeconds
        if ($started) { Write-Host "  $ServiceName started successfully" -ForegroundColor Green; return $true }
        else { $service.Refresh(); Write-Warning "  $ServiceName did not start within $TimeoutSeconds seconds (Status: $($service.Status))"; return $false }
    } catch { Write-Warning "  Failed to start $ServiceName : $($_.Exception.Message)"; return $false }
}

function Stop-WsusService {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [switch]$Force,
        [int]$TimeoutSeconds = 60
    )
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -eq "Stopped") { Write-Host "  $ServiceName is already stopped" -ForegroundColor Green; return $true }
        Write-Host "  Stopping $ServiceName..." -ForegroundColor Yellow
        if ($Force) { Stop-Service $ServiceName -Force -ErrorAction Stop -NoWait }
        else { Stop-Service $ServiceName -ErrorAction Stop -NoWait }
        $stopped = Wait-ServiceState -ServiceName $ServiceName -TargetState 'Stopped' -TimeoutSeconds $TimeoutSeconds
        if ($stopped) { Write-Host "  $ServiceName stopped successfully" -ForegroundColor Green; return $true }
        else { $service.Refresh(); Write-Warning "  $ServiceName did not stop within $TimeoutSeconds seconds (Status: $($service.Status))"; return $false }
    } catch { Write-Warning "  Failed to stop $ServiceName : $($_.Exception.Message)"; return $false }
}

function Restart-WsusService {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [switch]$Force
    )
    Write-Host "Restarting $ServiceName..." -ForegroundColor Yellow
    $stopped = Stop-WsusService -ServiceName $ServiceName -Force:$Force
    if (-not $stopped) { return $false }
    return (Start-WsusService -ServiceName $ServiceName)
}

function Get-WsusServiceStatus {
    param([switch]$IncludeSqlBrowser)
    $serviceMap = @{ "SQL Server Express" = "MSSQL`$SQLEXPRESS"; "WSUS Service" = "WSUSService"; "IIS" = "W3SVC" }
    if ($IncludeSqlBrowser) { $serviceMap["SQL Browser"] = "SQLBrowser" }
    $allServices = Get-Service -Name $serviceMap.Values -ErrorAction SilentlyContinue
    $svcByName = @{}; foreach ($s in $allServices) { $svcByName[$s.Name] = $s }
    $status = @{}
    foreach ($name in $serviceMap.Keys) {
        $serviceName = $serviceMap[$name]
        $svc = $svcByName[$serviceName]
        if ($svc) {
            $status[$name] = @{ Status = $svc.Status.ToString(); StartType = $svc.StartType.ToString(); Running = ($svc.Status -eq "Running") }
        } else {
            $status[$name] = @{ Status = "Not Found"; StartType = "N/A"; Running = $false }
        }
    }
    return $status
}

# Shallow per-service wrappers remain only as private helpers for Start-AllWsusServices/Stop-AllWsusServices

function Start-SqlServerExpress { param([string]$InstanceName = "SQLEXPRESS"); return Start-WsusService -ServiceName "MSSQL`$$InstanceName" -TimeoutSeconds 10 }
function Stop-SqlServerExpress { param([string]$InstanceName = "SQLEXPRESS", [switch]$Force); return Stop-WsusService -ServiceName "MSSQL`$$InstanceName" -Force:$Force }
function Start-SqlBrowserService { try { $service = Get-Service -Name 'SQLBrowser' -ErrorAction SilentlyContinue; if (-not $service) { Write-Warning "  SQL Browser service not found"; return $false }; Set-Service -Name 'SQLBrowser' -StartupType Automatic -ErrorAction SilentlyContinue; return Start-WsusService -ServiceName 'SQLBrowser' -TimeoutSeconds 30 } catch { Write-Warning "  Failed to start SQL Browser: $($_.Exception.Message)"; return $false } }
function Stop-SqlBrowserService { param([switch]$Force); return Stop-WsusService -ServiceName 'SQLBrowser' -Force:$Force }
function Start-WsusServer { return Start-WsusService -ServiceName "WSUSService" -TimeoutSeconds 10 }
function Stop-WsusServer { param([switch]$Force); return Stop-WsusService -ServiceName "WSUSService" -Force:$Force -TimeoutSeconds 5 }
function Start-IISService { return Start-WsusService -ServiceName "W3SVC" -TimeoutSeconds 5 }
function Stop-IISService { param([switch]$Force); return Stop-WsusService -ServiceName "W3SVC" -Force:$Force }

function Start-AllWsusServices {
    Write-Host "Starting all WSUS services..." -ForegroundColor Cyan
    $results = @{ SqlServer = Start-SqlServerExpress; IIS = Start-IISService; WSUS = Start-WsusServer }
    if ($results.SqlServer -and $results.IIS -and $results.WSUS) { Write-Host "All WSUS services started successfully" -ForegroundColor Green }
    else { Write-Warning "Some services failed to start" }
    return $results
}

function Stop-AllWsusServices {
    param([switch]$Force)
    Write-Host "Stopping all WSUS services..." -ForegroundColor Cyan
    $results = @{ WSUS = Stop-WsusServer -Force:$Force; IIS = Stop-IISService -Force:$Force; SqlServer = Stop-SqlServerExpress -Force:$Force }
    if ($results.WSUS -and $results.IIS -and $results.SqlServer) { Write-Host "All WSUS services stopped successfully" -ForegroundColor Green }
    else { Write-Warning "Some services failed to stop" }
    return $results
}

# Full export list for module consumers
Export-ModuleMember -Function @(
    'Start-WsusService',
    'Stop-WsusService',
    'Restart-WsusService',
    'Get-WsusServiceStatus',
    'Test-ServiceRunning',
    'Test-ServiceExists',
    'Wait-ServiceState',
    'Start-SqlServerExpress',
    'Stop-SqlServerExpress',
    'Start-WsusServer',
    'Stop-WsusServer',
    'Start-IISService',
    'Stop-IISService',
    'Start-SqlBrowserService',
    'Stop-SqlBrowserService',
    'Start-AllWsusServices',
    'Stop-AllWsusServices'
)
