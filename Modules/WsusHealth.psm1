<#
===============================================================================
Module: WsusHealth.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 2.0.0
Date: 2026-01-22
===============================================================================

.SYNOPSIS
    WSUS comprehensive diagnostics and auto-fix functions

.DESCRIPTION
    Provides comprehensive diagnostics and automatic repair including:
    - Service health checks (SQL Server, SQL Browser, WSUS, IIS)
    - SQL Server protocol configuration (TCP/IP, Named Pipes)
    - Database connectivity and existence verification
    - SQL login verification (NETWORK SERVICE)
    - Firewall rule verification (WSUS and SQL ports)
    - Permission validation
    - WSUS Application Pool status
    - Automated fixes for detected issues

.NOTES
    Requires: WsusServices.psm1, WsusFirewall.psm1, WsusPermissions.psm1
#>

# Import required modules with error handling
# Resolve module path (handles symlinks and different invocation methods)
$modulePath = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Only import if not already loaded (prevents re-import issues)
$requiredModules = @('WsusUtilities', 'WsusServices', 'WsusFirewall', 'WsusPermissions')
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

        # Try to query the database using the wrapper for TrustServerCertificate compatibility
        $query = "SELECT DB_ID('SUSDB') AS DatabaseID"
        $dbCheck = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query $query -QueryTimeout 10

        if ($null -ne $dbCheck.DatabaseID) {
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

    # SqlInstance parameter reserved for future database repair functionality
    Write-Verbose "SQL Instance: $SqlInstance (reserved for future database repairs)"

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

# ===========================
# COMPREHENSIVE DIAGNOSTICS
# ===========================

function Invoke-WsusDiagnostics {
    <#
    .SYNOPSIS
        Performs comprehensive WSUS diagnostics with automatic fixes

    .DESCRIPTION
        Scans for common WSUS and SQL Server issues and offers automated fixes.
        Checks include:
        - SQL Server Express service
        - SQL Browser service
        - TCP/IP protocol configuration
        - Named Pipes protocol configuration
        - SQL Server firewall rules
        - WSUS service
        - IIS service
        - WSUS Application Pool
        - WSUS firewall rules
        - SUSDB database existence
        - NETWORK SERVICE SQL login
        - WSUS content directory permissions

    .PARAMETER ContentPath
        Path to WSUS content directory (default: C:\WSUS)

    .PARAMETER SqlInstance
        SQL Server instance name (default: .\SQLEXPRESS)

    .PARAMETER AutoFix
        Automatically apply fixes for detected issues (default: $true)

    .PARAMETER IncludeSqlProtocols
        Include SQL protocol checks (TCP/IP, Named Pipes) - requires registry access

    .OUTPUTS
        Hashtable with diagnostic results and fixes applied
    #>
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS",
        [switch]$AutoFix = $true,
        [switch]$IncludeSqlProtocols
    )

    Write-Host "`n=== WSUS + SQL Server Diagnostics ===" -ForegroundColor Cyan
    Write-Host "Scanning for common issues...`n" -ForegroundColor Gray

    $issues = @()
    $fixesApplied = @()
    $fixesFailed = @()

    # Helper function for consistent check output
    function Write-CheckResult {
        param(
            [string]$CheckName,
            [ValidateSet('OK', 'FAIL', 'WARN', 'SKIP')]
            [string]$Result,
            [string]$Message = ""
        )
        Write-Host "[CHECK] $CheckName..." -NoNewline
        switch ($Result) {
            'OK'   { Write-Host " OK" -ForegroundColor Green }
            'FAIL' { Write-Host " FAIL" -ForegroundColor Red }
            'WARN' { Write-Host " WARN" -ForegroundColor Yellow }
            'SKIP' { Write-Host " SKIP" -ForegroundColor Yellow }
        }
        if ($Message) {
            Write-Host "        $Message" -ForegroundColor Gray
        }
    }

    # -------------------------
    # CHECK 1: SQL Server Service
    # -------------------------
    $sqlServiceName = 'MSSQL$SQLEXPRESS'
    $sqlService = Get-Service $sqlServiceName -ErrorAction SilentlyContinue
    if (-not $sqlService) {
        Write-CheckResult "SQL Server Service Status" "FAIL"
        $issues += @{
            Severity = "CRITICAL"
            Issue = "SQL Server service not found"
            Fix = "Install SQL Server Express or verify instance name"
            AutoFix = $null
        }
    } elseif ($sqlService.Status -ne "Running") {
        Write-CheckResult "SQL Server Service Status" "FAIL" "Status: $($sqlService.Status)"
        $issues += @{
            Severity = "CRITICAL"
            Issue = "SQL Server service is $($sqlService.Status)"
            Fix = "Start SQL Server service"
            AutoFix = { Start-Service 'MSSQL$SQLEXPRESS' -ErrorAction Stop }
        }
    } else {
        Write-CheckResult "SQL Server Service Status" "OK"
    }

    # -------------------------
    # CHECK 2: SQL Browser Service
    # -------------------------
    $browserService = Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue
    if (-not $browserService) {
        Write-CheckResult "SQL Browser Service Status" "WARN"
        $issues += @{
            Severity = "MEDIUM"
            Issue = "SQL Browser service not found"
            Fix = "SQL Browser is recommended for named instances"
            AutoFix = $null
        }
    } elseif ($browserService.Status -ne "Running") {
        Write-CheckResult "SQL Browser Service Status" "FAIL" "Status: $($browserService.Status)"
        $issues += @{
            Severity = "MEDIUM"
            Issue = "SQL Browser service is $($browserService.Status)"
            Fix = "Start SQL Browser service"
            AutoFix = {
                Set-Service SQLBrowser -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service SQLBrowser -ErrorAction Stop
            }
        }
    } else {
        Write-CheckResult "SQL Browser Service Status" "OK"
    }

    # -------------------------
    # CHECK 3: TCP/IP Protocol (if requested)
    # -------------------------
    if ($IncludeSqlProtocols) {
        # Try multiple SQL Server versions
        $tcpPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Tcp",
            "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Tcp",
            "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL14.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Tcp"
        )
        $tcpPath = $tcpPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($tcpPath) {
            $tcpEnabled = (Get-ItemProperty $tcpPath -ErrorAction SilentlyContinue).Enabled
            if ($tcpEnabled -ne 1) {
                Write-CheckResult "SQL TCP/IP Protocol" "FAIL"
                $issues += @{
                    Severity = "CRITICAL"
                    Issue = "TCP/IP protocol is disabled"
                    Fix = "Enable TCP/IP and set port 1433"
                    AutoFix = {
                        param($path)
                        Set-ItemProperty $path -Name Enabled -Value 1
                        Set-ItemProperty "$path\IPAll" -Name TcpDynamicPorts -Value "" -Force
                        Set-ItemProperty "$path\IPAll" -Name TcpPort -Value "1433" -Force
                        Restart-Service 'MSSQL$SQLEXPRESS' -Force
                    }.GetNewClosure()
                }
            } else {
                Write-CheckResult "SQL TCP/IP Protocol" "OK"
            }
        } else {
            Write-CheckResult "SQL TCP/IP Protocol" "SKIP" "Registry path not found"
        }

        # -------------------------
        # CHECK 4: Named Pipes Protocol
        # -------------------------
        $npPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Np",
            "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Np",
            "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL14.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Np"
        )
        $npPath = $npPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($npPath) {
            $npEnabled = (Get-ItemProperty $npPath -ErrorAction SilentlyContinue).Enabled
            if ($npEnabled -ne 1) {
                Write-CheckResult "SQL Named Pipes Protocol" "FAIL"
                $issues += @{
                    Severity = "HIGH"
                    Issue = "Named Pipes protocol is disabled"
                    Fix = "Enable Named Pipes"
                    AutoFix = {
                        param($path)
                        Set-ItemProperty $path -Name Enabled -Value 1
                        Restart-Service 'MSSQL$SQLEXPRESS' -Force
                    }.GetNewClosure()
                }
            } else {
                Write-CheckResult "SQL Named Pipes Protocol" "OK"
            }
        } else {
            Write-CheckResult "SQL Named Pipes Protocol" "SKIP" "Registry path not found"
        }
    }

    # -------------------------
    # CHECK 5: SQL Firewall Rule
    # -------------------------
    $sqlFirewallCheck = Test-AllSqlFirewallRules
    if (-not $sqlFirewallCheck.AllPresent) {
        Write-CheckResult "SQL Server Firewall Rules" "FAIL" "Missing: $($sqlFirewallCheck.Missing -join ', ')"
        $issues += @{
            Severity = "HIGH"
            Issue = "Missing SQL Server firewall rules: $($sqlFirewallCheck.Missing -join ', ')"
            Fix = "Create firewall rules for SQL Server"
            AutoFix = { $null = Repair-SqlFirewallRules }
        }
    } else {
        Write-CheckResult "SQL Server Firewall Rules" "OK"
    }

    # -------------------------
    # CHECK 6: WSUS Service
    # -------------------------
    $wsusService = Get-Service 'WsusService' -ErrorAction SilentlyContinue
    if (-not $wsusService) {
        Write-CheckResult "WSUS Service Status" "FAIL"
        $issues += @{
            Severity = "CRITICAL"
            Issue = "WSUS service not found"
            Fix = "Install WSUS role"
            AutoFix = $null
        }
    } elseif ($wsusService.Status -ne "Running") {
        Write-CheckResult "WSUS Service Status" "FAIL" "Status: $($wsusService.Status)"
        $issues += @{
            Severity = "CRITICAL"
            Issue = "WSUS service is $($wsusService.Status)"
            Fix = "Start WSUS service"
            AutoFix = { Start-Service WsusService -ErrorAction Stop }
        }
    } else {
        Write-CheckResult "WSUS Service Status" "OK"
    }

    # -------------------------
    # CHECK 7: IIS Service
    # -------------------------
    $iisService = Get-Service 'W3SVC' -ErrorAction SilentlyContinue
    if (-not $iisService) {
        Write-CheckResult "IIS Service Status" "FAIL"
        $issues += @{
            Severity = "HIGH"
            Issue = "IIS service not found"
            Fix = "Install IIS"
            AutoFix = $null
        }
    } elseif ($iisService.Status -ne "Running") {
        Write-CheckResult "IIS Service Status" "FAIL" "Status: $($iisService.Status)"
        $issues += @{
            Severity = "HIGH"
            Issue = "IIS service is $($iisService.Status)"
            Fix = "Start IIS service"
            AutoFix = { Start-Service W3SVC -ErrorAction Stop }
        }
    } else {
        Write-CheckResult "IIS Service Status" "OK"
    }

    # -------------------------
    # CHECK 8: WSUS Application Pool
    # -------------------------
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $appPool = Get-WebAppPoolState -Name "WsusPool" -ErrorAction SilentlyContinue
        if (-not $appPool) {
            Write-CheckResult "WSUS Application Pool" "FAIL"
            $issues += @{
                Severity = "HIGH"
                Issue = "WsusPool application pool not found"
                Fix = "Reinstall WSUS or create app pool"
                AutoFix = $null
            }
        } elseif ($appPool.Value -ne "Started") {
            Write-CheckResult "WSUS Application Pool" "FAIL" "Status: $($appPool.Value)"
            $issues += @{
                Severity = "HIGH"
                Issue = "WsusPool is $($appPool.Value)"
                Fix = "Start WsusPool application pool"
                AutoFix = { Start-WebAppPool -Name "WsusPool" -ErrorAction Stop }
            }
        } else {
            Write-CheckResult "WSUS Application Pool" "OK"
        }
    } catch {
        Write-CheckResult "WSUS Application Pool" "SKIP" "WebAdministration module not available"
    }

    # -------------------------
    # CHECK 9: WSUS Firewall Rules
    # -------------------------
    $wsusFirewallCheck = Test-AllWsusFirewallRules
    if (-not $wsusFirewallCheck.AllPresent) {
        Write-CheckResult "WSUS Firewall Rules" "FAIL" "Missing: $($wsusFirewallCheck.Missing -join ', ')"
        $issues += @{
            Severity = "MEDIUM"
            Issue = "Missing WSUS firewall rules: $($wsusFirewallCheck.Missing -join ', ')"
            Fix = "Create firewall rules for WSUS ports 8530/8531"
            AutoFix = { $null = Repair-WsusFirewallRules }
        }
    } else {
        Write-CheckResult "WSUS Firewall Rules" "OK"
    }

    # -------------------------
    # CHECK 10: SUSDB Database Exists
    # -------------------------
    if ($sqlService -and $sqlService.Status -eq "Running") {
        try {
            $dbCheck = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query "SELECT DB_ID('SUSDB') AS DatabaseID" -QueryTimeout 10
            if ($null -ne $dbCheck.DatabaseID) {
                Write-CheckResult "SUSDB Database" "OK"
            } else {
                Write-CheckResult "SUSDB Database" "FAIL"
                $issues += @{
                    Severity = "CRITICAL"
                    Issue = "SUSDB database does not exist"
                    Fix = "Run WSUS postinstall: wsusutil.exe postinstall"
                    AutoFix = $null
                }
            }
        } catch {
            Write-CheckResult "SUSDB Database" "FAIL" "Cannot connect to SQL Server"
            $issues += @{
                Severity = "CRITICAL"
                Issue = "Cannot connect to SQL Server to verify SUSDB"
                Fix = "Verify SQL Server is running and accessible"
                AutoFix = $null
            }
        }
    } else {
        Write-CheckResult "SUSDB Database" "SKIP" "SQL Server not running"
    }

    # -------------------------
    # CHECK 11: NETWORK SERVICE Login
    # -------------------------
    if ($sqlService -and $sqlService.Status -eq "Running") {
        try {
            $loginCheck = Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query "SELECT name FROM sys.server_principals WHERE name='NT AUTHORITY\NETWORK SERVICE'" -QueryTimeout 10
            if ($loginCheck -and $loginCheck.name) {
                Write-CheckResult "NETWORK SERVICE SQL Login" "OK"
            } else {
                Write-CheckResult "NETWORK SERVICE SQL Login" "FAIL"
                $issues += @{
                    Severity = "HIGH"
                    Issue = "NT AUTHORITY\NETWORK SERVICE login missing"
                    Fix = "Create login and grant dbcreator role"
                    AutoFix = {
                        Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query "CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS;" -QueryTimeout 10 -ErrorAction SilentlyContinue
                        Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query "ALTER SERVER ROLE [dbcreator] ADD MEMBER [NT AUTHORITY\NETWORK SERVICE];" -QueryTimeout 10 -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch {
            Write-CheckResult "NETWORK SERVICE SQL Login" "SKIP" "Could not query SQL Server"
        }
    } else {
        Write-CheckResult "NETWORK SERVICE SQL Login" "SKIP" "SQL Server not running"
    }

    # -------------------------
    # CHECK 12: WSUS Content Directory Permissions
    # -------------------------
    $wsusContent = Join-Path $ContentPath "WsusContent"
    if (Test-Path $wsusContent) {
        $permCheck = Test-WsusContentPermissions -ContentPath $ContentPath
        if (-not $permCheck.AllCorrect) {
            Write-CheckResult "WSUS Content Permissions" "FAIL" "Missing: $($permCheck.Missing -join ', ')"
            $issues += @{
                Severity = "MEDIUM"
                Issue = "Missing permissions on content directory: $($permCheck.Missing -join ', ')"
                Fix = "Grant required permissions on $ContentPath"
                AutoFix = { $null = Repair-WsusContentPermissions -ContentPath $ContentPath }
            }
        } else {
            Write-CheckResult "WSUS Content Permissions" "OK"
        }
    } elseif (Test-Path $ContentPath) {
        $permCheck = Test-WsusContentPermissions -ContentPath $ContentPath
        if (-not $permCheck.AllCorrect) {
            Write-CheckResult "WSUS Content Permissions" "FAIL" "Missing: $($permCheck.Missing -join ', ')"
            $issues += @{
                Severity = "MEDIUM"
                Issue = "Missing permissions on content directory: $($permCheck.Missing -join ', ')"
                Fix = "Grant required permissions on $ContentPath"
                AutoFix = { $null = Repair-WsusContentPermissions -ContentPath $ContentPath }
            }
        } else {
            Write-CheckResult "WSUS Content Permissions" "OK"
        }
    } else {
        Write-CheckResult "WSUS Content Directory" "WARN" "Path does not exist: $ContentPath"
    }

    # -------------------------
    # RESULTS SUMMARY
    # -------------------------
    Write-Host "`n=== SCAN RESULTS ===" -ForegroundColor Cyan

    if ($issues.Count -eq 0) {
        Write-Host "`n[SUCCESS] No issues detected! System is healthy." -ForegroundColor Green
        return @{
            Healthy = $true
            IssuesFound = 0
            IssuesFixed = 0
            Issues = @()
            FixesApplied = @()
            FixesFailed = @()
        }
    }

    Write-Host "`nFound $($issues.Count) issue(s):`n" -ForegroundColor Yellow

    $fixableCount = 0
    foreach ($issue in $issues) {
        $color = switch ($issue.Severity) {
            "CRITICAL" { "Red" }
            "HIGH" { "Red" }
            "MEDIUM" { "Yellow" }
            "LOW" { "Gray" }
            default { "White" }
        }

        Write-Host "[$($issue.Severity)] " -ForegroundColor $color -NoNewline
        Write-Host $issue.Issue
        Write-Host "    Fix: $($issue.Fix)" -ForegroundColor Gray

        if ($issue.AutoFix) {
            $fixableCount++
            Write-Host "    [AUTO-FIX AVAILABLE]" -ForegroundColor Green
        }
        Write-Host ""
    }

    # -------------------------
    # AUTO-FIX
    # -------------------------
    if ($AutoFix -and $fixableCount -gt 0) {
        Write-Host "=== APPLYING AUTO-FIXES ===" -ForegroundColor Cyan
        Write-Host "Fixing $fixableCount issue(s)...`n" -ForegroundColor Green

        foreach ($issue in $issues) {
            if ($issue.AutoFix) {
                Write-Host "[FIX] $($issue.Issue)..." -NoNewline
                try {
                    & $issue.AutoFix
                    Write-Host " SUCCESS" -ForegroundColor Green
                    $fixesApplied += $issue.Issue
                } catch {
                    Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
                    $fixesFailed += $issue.Issue
                }
            }
        }

        Write-Host "`n[COMPLETE] Auto-fix process finished." -ForegroundColor Cyan

        if ($fixesFailed.Count -gt 0) {
            Write-Host "Some fixes failed. Please manually resolve these issues." -ForegroundColor Yellow
        }
    } elseif ($fixableCount -eq 0) {
        Write-Host "No auto-fixes available. Please manually resolve the issues above." -ForegroundColor Yellow
    }

    # Get SSL status for summary
    $sslStatus = Get-WsusSSLStatus

    Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Issues Found: $($issues.Count)"
    Write-Host "Auto-Fixes Applied: $($fixesApplied.Count)"
    Write-Host "Fixes Failed: $($fixesFailed.Count)"
    if ($sslStatus.SSLEnabled) {
        Write-Host "Protocol: HTTPS (port 8531)" -ForegroundColor Green
    } else {
        Write-Host "Protocol: HTTP (port 8530)" -ForegroundColor Gray
    }
    Write-Host ""

    return @{
        Healthy = ($issues.Count -eq 0) -or ($fixesApplied.Count -eq $issues.Count -and $fixesFailed.Count -eq 0)
        IssuesFound = $issues.Count
        IssuesFixed = $fixesApplied.Count
        Issues = $issues
        FixesApplied = $fixesApplied
        FixesFailed = $fixesFailed
        SSL = $sslStatus
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-WsusSSLStatus',
    'Test-WsusDatabaseConnection',
    'Test-WsusHealth',
    'Repair-WsusHealth',
    'Invoke-WsusDiagnostics'
)
