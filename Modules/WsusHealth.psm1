<#
===============================================================================
Module: WsusHealth.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.1.0
Date: 2026-01-10
===============================================================================

.SYNOPSIS
    WSUS comprehensive health check functions

.DESCRIPTION
    Provides health checking and diagnostic functions including:
    - Service health checks
    - Database connectivity
    - Firewall verification
    - Permission validation
    - Overall system health reports

.NOTES
    Requires: WsusServices.psm1, WsusFirewall.psm1, WsusPermissions.psm1
#>

# Import required modules with error handling
# Resolve module path (handles symlinks and different invocation methods)
$modulePath = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Only import if not already loaded (prevents re-import issues)
$requiredModules = @('WsusServices', 'WsusFirewall', 'WsusPermissions')
foreach ($modName in $requiredModules) {
    $modFile = Join-Path $modulePath "$modName.psm1"
    if (Test-Path $modFile) {
        Import-Module $modFile -Force -DisableNameChecking -ErrorAction Stop
    } else {
        throw "Required module not found: $modFile"
    }
}

# ===========================
# SSL/HTTPS STATUS FUNCTION
# ===========================

function Get-WsusSSLStatus {
    <#
    .SYNOPSIS
        Gets the current SSL/HTTPS configuration status for WSUS

    .OUTPUTS
        Hashtable with SSL configuration details
    #>

    $result = @{
        SSLEnabled = $false
        Protocol = "HTTP"
        Port = 8530
        CertificateThumbprint = $null
        CertificateExpires = $null
        Message = ""
    }

    try {
        # Check IIS for HTTPS binding on port 8531
        Import-Module WebAdministration -ErrorAction SilentlyContinue

        if (Get-Module WebAdministration) {
            $wsussite = Get-Website | Where-Object { $_.Name -like "*WSUS*" } | Select-Object -First 1
            if (-not $wsussite) {
                $wsussite = Get-Website | Where-Object { $_.Id -eq 1 } | Select-Object -First 1
            }

            if ($wsussite) {
                $httpsBinding = Get-WebBinding -Name $wsussite.Name -Protocol "https" -Port 8531 -ErrorAction SilentlyContinue

                if ($httpsBinding) {
                    $result.SSLEnabled = $true
                    $result.Protocol = "HTTPS"
                    $result.Port = 8531

                    # Try to get certificate info
                    $certHash = $httpsBinding.certificateHash
                    if ($certHash) {
                        $result.CertificateThumbprint = $certHash
                        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $certHash }
                        if ($cert) {
                            $result.CertificateExpires = $cert.NotAfter
                        }
                    }
                    $result.Message = "HTTPS enabled on port 8531"
                } else {
                    $result.Message = "HTTP only (port 8530)"
                }
            } else {
                $result.Message = "WSUS website not found in IIS"
            }
        } else {
            $result.Message = "WebAdministration module not available"
        }
    } catch {
        $result.Message = "Could not determine SSL status: $($_.Exception.Message)"
    }

    return $result
}

# ===========================
# DATABASE HEALTH FUNCTIONS
# ===========================

function Test-WsusDatabaseConnection {
    <#
    .SYNOPSIS
        Tests connectivity to the WSUS database

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Hashtable with connection test results
    #>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $result = @{
        Connected = $false
        Message = ""
        DatabaseExists = $false
    }

    try {
        # Test if SQL Server is running - extract instance name from SqlInstance parameter
        $instanceName = if ($SqlInstance -match '\\(.+)$') { $Matches[1] } else { "MSSQLSERVER" }
        $sqlServiceName = if ($instanceName -eq "MSSQLSERVER") { "MSSQLSERVER" } else { "MSSQL`$$instanceName" }

        if (-not (Test-ServiceRunning -ServiceName $sqlServiceName)) {
            $result.Message = "SQL Server service ($sqlServiceName) is not running"
            return $result
        }

        # Try to query the database
        $query = "SELECT DB_ID('SUSDB') AS DatabaseID"
        $dbCheck = Invoke-Sqlcmd -ServerInstance $SqlInstance -Database master -Query $query -QueryTimeout 10 -ErrorAction Stop

        if ($dbCheck.DatabaseID -ne $null) {
            $result.Connected = $true
            $result.DatabaseExists = $true
            $result.Message = "Successfully connected to SUSDB"
        } else {
            $result.Connected = $true
            $result.DatabaseExists = $false
            $result.Message = "Connected to SQL Server, but SUSDB does not exist"
        }

        return $result
    } catch {
        $result.Message = "Connection failed: $($_.Exception.Message)"
        return $result
    }
}

# ===========================
# COMPREHENSIVE HEALTH CHECK
# ===========================

function Test-WsusHealth {
    <#
    .SYNOPSIS
        Performs comprehensive WSUS health check

    .PARAMETER ContentPath
        Path to WSUS content directory (default: C:\WSUS)

    .PARAMETER SqlInstance
        SQL Server instance name

    .PARAMETER IncludeDatabase
        Include database health checks

    .OUTPUTS
        Hashtable with comprehensive health check results
    #>
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS",
        [switch]$IncludeDatabase
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "WSUS Health Check" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $health = @{
        Overall = "Healthy"
        Services = @{}
        Database = @{}
        Firewall = @{}
        Permissions = @{}
        Issues = @()
    }

    # Check Services
    Write-Host "`n[1/4] Checking Services..." -ForegroundColor Yellow
    $serviceStatus = Get-WsusServiceStatus

    foreach ($serviceName in $serviceStatus.Keys) {
        $status = $serviceStatus[$serviceName]
        $health.Services[$serviceName] = $status

        if (-not $status.Running) {
            $health.Issues += "Service '$serviceName' is not running (Status: $($status.Status))"
            $health.Overall = "Unhealthy"
            Write-Host "  [FAIL] $serviceName - $($status.Status)" -ForegroundColor Red
        } else {
            Write-Host "  [OK] $serviceName - Running" -ForegroundColor Green
        }
    }

    # Check Database
    if ($IncludeDatabase) {
        Write-Host "`n[2/4] Checking Database..." -ForegroundColor Yellow
        $dbTest = Test-WsusDatabaseConnection -SqlInstance $SqlInstance
        $health.Database = $dbTest

        if (-not $dbTest.Connected) {
            $health.Issues += "Database connection failed: $($dbTest.Message)"
            $health.Overall = "Unhealthy"
            Write-Host "  [FAIL] $($dbTest.Message)" -ForegroundColor Red
        } elseif (-not $dbTest.DatabaseExists) {
            $health.Issues += "SUSDB database does not exist"
            $health.Overall = "Unhealthy"
            Write-Host "  [FAIL] SUSDB database not found" -ForegroundColor Red
        } else {
            Write-Host "  [OK] $($dbTest.Message)" -ForegroundColor Green
        }
    } else {
        Write-Host "`n[2/4] Skipping Database Check..." -ForegroundColor Gray
    }

    # Check Firewall Rules
    Write-Host "`n[3/4] Checking Firewall Rules..." -ForegroundColor Yellow
    $firewallCheck = Test-AllWsusFirewallRules
    $health.Firewall = $firewallCheck

    if (-not $firewallCheck.AllPresent) {
        $health.Issues += "Missing firewall rules: $($firewallCheck.Missing -join ', ')"
        $health.Overall = "Degraded"
        Write-Host "  [WARN] Missing firewall rules:" -ForegroundColor Yellow
        $firewallCheck.Missing | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  [OK] All firewall rules present" -ForegroundColor Green
    }

    # Check Permissions
    Write-Host "`n[4/4] Checking Permissions..." -ForegroundColor Yellow
    $permCheck = Test-WsusContentPermissions -ContentPath $ContentPath
    $health.Permissions = $permCheck

    if (-not $permCheck.AllCorrect) {
        $health.Issues += "Missing permissions: $($permCheck.Missing -join ', ')"
        if ($health.Overall -ne "Unhealthy") {
            $health.Overall = "Degraded"
        }
        Write-Host "  [WARN] Missing permissions:" -ForegroundColor Yellow
        $permCheck.Missing | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  [OK] All permissions correct" -ForegroundColor Green
    }

    # Get SSL Status (informational)
    $sslStatus = Get-WsusSSLStatus
    $health.SSL = $sslStatus

    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Health Check Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Show protocol status
    if ($sslStatus.SSLEnabled) {
        Write-Host "Protocol: HTTPS (port 8531)" -ForegroundColor Green
        if ($sslStatus.CertificateExpires) {
            $daysUntilExpiry = ($sslStatus.CertificateExpires - (Get-Date)).Days
            if ($daysUntilExpiry -lt 30) {
                Write-Host "Certificate expires in $daysUntilExpiry days!" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Protocol: HTTP (port 8530)" -ForegroundColor Gray
    }
    Write-Host ""

    switch ($health.Overall) {
        "Healthy" {
            Write-Host "Overall Status: HEALTHY" -ForegroundColor Green
            Write-Host "All systems operational" -ForegroundColor Green
        }
        "Degraded" {
            Write-Host "Overall Status: DEGRADED" -ForegroundColor Yellow
            Write-Host "System is operational but has warnings" -ForegroundColor Yellow
        }
        "Unhealthy" {
            Write-Host "Overall Status: UNHEALTHY" -ForegroundColor Red
            Write-Host "Critical issues detected" -ForegroundColor Red
        }
    }

    if ($health.Issues.Count -gt 0) {
        Write-Host "`nIssues Found:" -ForegroundColor Yellow
        $health.Issues | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor Red
        }
    }

    Write-Host ""

    return $health
}

function Repair-WsusHealth {
    <#
    .SYNOPSIS
        Attempts to automatically repair common WSUS health issues

    .PARAMETER ContentPath
        Path to WSUS content directory

    .PARAMETER SqlInstance
        SQL Server instance name

    .OUTPUTS
        Hashtable with repair results
    #>
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "WSUS Health Repair" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $results = @{
        ServicesStarted = @()
        FirewallsCreated = @()
        PermissionsFixed = $false
        Success = $true
    }

    # 1. Start stopped services
    Write-Host "`n[1/3] Starting Services..." -ForegroundColor Yellow
    $serviceStatus = Get-WsusServiceStatus

    foreach ($serviceName in $serviceStatus.Keys) {
        if (-not $serviceStatus[$serviceName].Running) {
            Write-Host "  Starting $serviceName..." -ForegroundColor Yellow

            $started = switch ($serviceName) {
                "SQL Server Express" { Start-SqlServerExpress }
                "WSUS Service" { Start-WsusServer }
                "IIS" { Start-IISService }
            }

            if ($started) {
                $results.ServicesStarted += $serviceName
                Write-Host "  [OK] $serviceName started" -ForegroundColor Green
            } else {
                $results.Success = $false
                Write-Host "  [FAIL] Failed to start $serviceName" -ForegroundColor Red
            }
        }
    }

    # 2. Create missing firewall rules
    Write-Host "`n[2/3] Checking Firewall Rules..." -ForegroundColor Yellow
    $firewallResult = Repair-WsusFirewallRules
    $results.FirewallsCreated = $firewallResult.Created

    # 3. Fix permissions
    Write-Host "`n[3/3] Checking Permissions..." -ForegroundColor Yellow
    $permResult = Repair-WsusContentPermissions -ContentPath $ContentPath
    $results.PermissionsFixed = $permResult

    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Repair Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "Services Started: $($results.ServicesStarted.Count)"
    Write-Host "Firewall Rules Created: $($results.FirewallsCreated.Count)"
    Write-Host "Permissions Fixed: $($results.PermissionsFixed)"

    if ($results.Success) {
        Write-Host "`nRepair completed successfully" -ForegroundColor Green
    } else {
        Write-Host "`nRepair completed with errors" -ForegroundColor Red
    }

    Write-Host ""

    return $results
}

# Export functions
Export-ModuleMember -Function @(
    'Get-WsusSSLStatus',
    'Test-WsusDatabaseConnection',
    'Test-WsusHealth',
    'Repair-WsusHealth'
)
