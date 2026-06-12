<#
===============================================================================
Module: WsusHealth.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 2.1.0
Date: 2026-06-09
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
$modulePath = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$requiredModules = @('WsusUtilities', 'WsusServices', 'WsusFirewall', 'WsusPermissions', 'WsusDiagnosticResult', 'WsusHostEnvironment', 'WsusRepairPlan')
foreach ($modName in $requiredModules) {
    $modFile = Join-Path $modulePath "$modName.psm1"
    if (Test-Path $modFile) {
        try {
            Import-Module $modFile -Force -DisableNameChecking -ErrorAction Stop
        } catch {
            Write-Warning "WsusHealth: Failed to import $modName - $($_.Exception.Message)"
        }
    } else {
        Write-Warning "WsusHealth: Required module not found - $modFile"
    }
}

# ===========================
# CONSTANTS
# ===========================
# (Service names are derived inline from SqlInstance or passed as parameters)

# ===========================
# CHECK-RESULT HELPER (internal)
# ===========================
function Write-CheckResult {
    param(
        [string]$CheckName,
        [ValidateSet('OK', 'FAIL', 'WARN', 'SKIP')]
        [string]$Result,
        [string]$Message = "",
        [string]$Prefix = "CHECK"
    )
    Write-Host "[$Prefix] $CheckName..." -NoNewline
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

# ===========================
# SQL SERVICE NAME HELPER
# ===========================
function Get-WsusSqlServiceName {
    <#
    .SYNOPSIS
        Derives the Windows service name from a SQL Server instance path.
        ".\SQLEXPRESS" -> "MSSQL$SQLEXPRESS", "localhost" -> "MSSQLSERVER"
    #>
    param([string]$SqlInstance = '.\SQLEXPRESS')
    if ($SqlInstance -match '\\([^\\]+)$') { "MSSQL`$$($Matches[1])" } else { 'MSSQLSERVER' }
}

# ===========================
# DIAGNOSTIC ISSUE FACTORY
# ===========================
function New-WsusHealthDiagnosticIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')][string]$Severity,
        [Parameter(Mandatory)][string]$Issue,
        [string]$Fix = '',
        [string]$RepairAction = '',
        [string]$CheckId = '',
        [hashtable]$Evidence = @{}
    )

    $normalizedSeverity = $Severity.Substring(0, 1) + $Severity.Substring(1).ToLowerInvariant()
    return New-WsusDiagnosticIssue -Severity $normalizedSeverity -Message $Issue -Recommendation $Fix -CheckId $CheckId -RepairAction $RepairAction -Evidence $Evidence
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
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        if (Get-Module WebAdministration) {
            $wsussite = Get-Website | Where-Object { $_.Name -like "*WSUS*" } | Select-Object -First 1
            if (-not $wsussite) { $wsussite = Get-Website | Where-Object { $_.Id -eq 1 } | Select-Object -First 1 }
            if ($wsussite) {
                $httpsBinding = Get-WebBinding -Name $wsussite.Name -Protocol "https" -Port 8531 -ErrorAction SilentlyContinue
                if ($httpsBinding) {
                    $result.SSLEnabled = $true
                    $result.Protocol = "HTTPS"
                    $result.Port = 8531
                    $certHash = $httpsBinding.certificateHash
                    if ($certHash) {
                        $result.CertificateThumbprint = $certHash
                        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $certHash }
                        if ($cert) { $result.CertificateExpires = $cert.NotAfter }
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
    .OUTPUTS
        Hashtable with connection test results
    #>
    param(
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $result = @{ Connected = $false; Message = ""; DatabaseExists = $false }

    try {
        $sqlServiceName = Get-WsusSqlServiceName -SqlInstance $SqlInstance
        $sqlService = Get-WsusHostServiceState -Name $sqlServiceName | Select-Object -First 1

        if (-not $sqlService.Running) {
            $result.Message = "SQL Server service ($sqlServiceName) is not running"
            return $result
        }

        $dbCheck = Invoke-WsusHostSqlQuery -ServerInstance $SqlInstance -Database master -Query "SELECT DB_ID('SUSDB') AS DatabaseID" -QueryTimeout 10
        if ($null -ne $dbCheck.DatabaseID) {
            $result.Connected = $true
            $result.DatabaseExists = $true
            $result.Message = "Successfully connected to SUSDB"
        } else {
            $result.Connected = $true
            $result.DatabaseExists = $false
            $result.Message = "Connected to SQL Server, but SUSDB does not exist"
        }
    } catch {
        $result.Message = "Connection failed: $($_.Exception.Message)"
    }
    return $result
}

# ===========================
# HEALTH SCORE
# ===========================
function Get-WsusHealthScore {
    <#
    .SYNOPSIS
        Calculates a 0-100 composite health score for the WSUS server.
    .DESCRIPTION
        Weighted composite: Services up (30pts), DB size healthy (20pts),
        Sync recent (20pts), Disk OK (20pts), Last operation passed (10pts).
        Returns -1 if all data sources failed (display as N/A).
    #>
    param(
        [string]$SqlInstance  = '.\SQLEXPRESS',
        [string]$ContentPath  = 'C:\WSUS',
        [string]$HistoryPath  = "$env:APPDATA\WsusManager\history.json"
    )

    $failedSources = 0
    $totalSources  = 5

    $servicesScore = 0
    try {
        $sqlSvcName = Get-WsusSqlServiceName -SqlInstance $SqlInstance
        $serviceNames = @($sqlSvcName, 'WSUSService', 'W3SVC')
        $running = 0
        $svcCmd = Get-Command Get-WsusHostServiceState -ErrorAction SilentlyContinue
        if (-not $svcCmd) { throw 'Get-WsusHostServiceState not available' }
        $serviceStates = @(Get-WsusHostServiceState -Name $serviceNames)
        $svcTable = @{}; foreach ($s in $serviceStates) { $svcTable[$s.Name] = $s }
        foreach ($svc in $serviceNames) {
            $s = $svcTable[$svc]
            if ($s -and $s.Running) { $running++ }
        }
        $servicesScore = switch ($running) { 3 { 30 } 2 { 20 } 1 { 10 } default { 0 } }
    } catch { $failedSources++ }

    $dbScore = 0
    try {
        $query = "SELECT CAST(SUM(size)*8.0/1024/1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')"
        $sqlResult = if (Get-Command 'Invoke-WsusSqlcmd' -ErrorAction SilentlyContinue) {
            Invoke-WsusSqlcmd -ServerInstance $SqlInstance -Database master -Query $query -QueryTimeout 30
        } else {
            Invoke-Sqlcmd -ServerInstance $SqlInstance -Database master -Query $query -QueryTimeout 30
        }
        $sizeGB = [double]$sqlResult.SizeGB
        $dbScore = if ($sizeGB -lt 7) { 20 } elseif ($sizeGB -lt 9) { 10 } else { 0 }
    } catch { $failedSources++ }

    $syncScore = 0
    try {
        $wsusPort = 8530; $useSsl = $false
        $sslStatus = Get-WsusSSLStatus
        if ($sslStatus.SSLEnabled) { $wsusPort = 8531; $useSsl = $true }
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer('localhost', $useSsl, $wsusPort)
        $lastSync = $wsus.GetSubscription().LastSynchronizationTime
        $daysSinceSync = ([datetime]::UtcNow - $lastSync.ToUniversalTime()).TotalDays
        $syncScore = if ($daysSinceSync -le 7) { 20 } elseif ($daysSinceSync -le 30) { 10 } else { 0 }
    } catch { $failedSources++ }

    $diskScore = 0
    try {
        $drive = Split-Path -Qualifier $ContentPath
        $disk = Get-PSDrive -Name ($drive.TrimEnd(':')) -ErrorAction Stop
        $freeGB = [math]::Round($disk.Free / 1GB, 2)
        $diskScore = if ($freeGB -gt 50) { 20 } elseif ($freeGB -ge 10) { 10 } else { 0 }
    } catch { $failedSources++ }

    $opScore = 5
    try {
        if (Test-Path $HistoryPath) {
            $history = Get-Content $HistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($history -and $history.Count -gt 0) {
                $lastTimestamp = [datetime]::MinValue; $last = $null
                foreach ($entry in $history) { $ts = [datetime]$entry.Timestamp; if ($ts -gt $lastTimestamp) { $lastTimestamp = $ts; $last = $entry } }
                $opScore = if ($last.Result -eq 'Pass') { 10 } else { 0 }
            }
        }
    } catch { $failedSources++ }

    $allFailed = ($failedSources -ge $totalSources)
    $total     = $servicesScore + $dbScore + $syncScore + $diskScore + $opScore
    $grade = if ($allFailed) { 'Unknown' } elseif ($total -ge 80) { 'Green' } elseif ($total -ge 50) { 'Yellow' } else { 'Red' }

    return @{
        Score      = if ($allFailed) { -1 } else { [int]$total }
        Components = @{
            Services      = $servicesScore
            DatabaseSize  = $dbScore
            SyncRecency   = $syncScore
            DiskSpace     = $diskScore
            LastOperation = $opScore
        }
        Grade     = $grade
        AllFailed = $allFailed
    }
}

<#
.SYNOPSIS
    Internal helper: batch-query service states for the standard service names.
#>
function Get-WsusStandardServiceStates {
    param([string]$SqlInstance = '.\SQLEXPRESS')
    $sqlServiceName = Get-WsusSqlServiceName -SqlInstance $SqlInstance
    $states = @{}
    Get-WsusHostServiceState -Name @($sqlServiceName, 'SQLBrowser', 'WsusService', 'W3SVC') | ForEach-Object { $states[$_.Name] = $_ }
    return @{ SqlServiceName = $sqlServiceName; States = $states }
}

<#
.SYNOPSIS
    Helper: runs a list of service checks against a batch-queried service state hashtable.
    Returns an array of issue hashtables (each with Severity, Issue, Fix, RepairAction, Repairable).
#>
function Invoke-ServiceCheck {
    param(
        [hashtable]$ServiceStates,
        [string]$ServiceName,
        [string]$DisplayName,
        [string]$Criticality = 'CRITICAL',
        [string]$FixMessage,
        [string]$RepairAction = $null,
        [string]$NotInstalledFix = '',
        [string]$NotInstalledRepairAction = $null
    )

    $svc = $ServiceStates[$ServiceName]
    if (-not $svc.Installed) {
        Write-CheckResult "$DisplayName Status" "FAIL"
        return ,@(@{
            Severity = $Criticality
            Issue = "$DisplayName service not found"
            Fix = $NotInstalledFix
            RepairAction = $NotInstalledRepairAction
            Repairable = (-not [string]::IsNullOrWhiteSpace($NotInstalledRepairAction))
        })
    } elseif (-not $svc.Running) {
        Write-CheckResult "$DisplayName Status" "FAIL" "Status: $($svc.Status)"
        return ,@(@{
            Severity = $Criticality
            Issue = "$DisplayName service is $($svc.Status)"
            Fix = $FixMessage
            RepairAction = $RepairAction
            Repairable = (-not [string]::IsNullOrWhiteSpace($RepairAction))
        })
    } else {
        Write-CheckResult "$DisplayName Status" "OK"
        return ,@()
    }
}

# ===========================
# COMPREHENSIVE DIAGNOSTICS
# ===========================

<#
.SYNOPSIS
    Runs standard WSUS diagnostics checks (services, SQL, firewall, permissions, app pool).

.DESCRIPTION
    Checks SQL Server Express, SQL Browser, WSUS, IIS services; TCP/IP and Named Pipes
    protocols; SQL and WSUS firewall rules; SUSDB existence; NETWORK SERVICE SQL login;
    WSUS content directory permissions; and WSUS Application Pool.

    Designed to be called directly or as a step in a broader diagnostic pipeline.
    Returns diagnostic issues as typed Wsus.DiagnosticIssue objects plus an
    @{ Healthy; IssuesFound; Issues; ... } result hashtable.
#>
function Invoke-WsusDiagnostics {
    [CmdletBinding()]
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS",
        [switch]$AutoFix,
        [switch]$IncludeSqlProtocols
    )

    $autoFixEnabled = if ($PSBoundParameters.ContainsKey('AutoFix')) { [bool]$AutoFix } else { $true }

    Write-Host "`n=== WSUS + SQL Server Diagnostics ===" -ForegroundColor Cyan
    Write-Host "Scanning for common issues...`n" -ForegroundColor Gray

    $issues = [System.Collections.Generic.List[object]]::new()
    $fixesApplied = @()
    $fixesFailed = @()

    # Batch-query service states once
    $svcData = Get-WsusStandardServiceStates -SqlInstance $SqlInstance
    $sqlServiceName = $svcData.SqlServiceName

    # CHECK 1-4: Services (SQL Server, SQL Browser, WSUS, IIS)
    $serviceChecks = @(
        @{ ServiceName = $sqlServiceName; DisplayName = 'SQL Server'; Criticality = 'CRITICAL'; FixMessage = 'Start SQL Server service'; RepairAction = 'StartSqlService'; NotInstalledFix = 'Install SQL Server Express or verify instance name' }
        @{ ServiceName = 'SQLBrowser'; DisplayName = 'SQL Browser'; Criticality = 'MEDIUM'; FixMessage = 'Start SQL Browser service'; RepairAction = 'StartSqlBrowser'; NotInstalledFix = 'SQL Browser is recommended for named instances'; NotInstalledRepairAction = $null }
        @{ ServiceName = 'WsusService'; DisplayName = 'WSUS Service'; Criticality = 'CRITICAL'; FixMessage = 'Start WSUS service'; RepairAction = 'StartWsusService'; NotInstalledFix = 'Install WSUS role' }
        @{ ServiceName = 'W3SVC'; DisplayName = 'IIS Service'; Criticality = 'HIGH'; FixMessage = 'Start IIS service'; RepairAction = 'StartIisService'; NotInstalledFix = 'Install IIS' }
    )

    foreach ($c in $serviceChecks) {
        $result = Invoke-ServiceCheck -ServiceStates $svcData.States -ServiceName $c.ServiceName -DisplayName $c.DisplayName -Criticality $c.Criticality -FixMessage $c.FixMessage -RepairAction $c.RepairAction -NotInstalledFix $c.NotInstalledFix -NotInstalledRepairAction $c.NotInstalledRepairAction
        foreach ($issue in $result) { $null = $issues.Add($issue) }
    }

    # CHECK: SQL protocols (if requested)
    if ($IncludeSqlProtocols) {
        $sqlNetwork = Get-WsusHostSqlNetworkingState -SqlInstance $SqlInstance
        if ($sqlNetwork.Found) {
            if ($sqlNetwork.TcpEnabled -ne 1) {
                Write-CheckResult "SQL TCP/IP Protocol" "FAIL"
                $null = $issues.Add(@{ Severity = 'CRITICAL'; Issue = 'TCP/IP protocol is disabled'; Fix = 'Enable TCP/IP and set port 1433'; RepairAction = 'EnableSqlTcpIp'; Repairable = $true })
            } else {
                Write-CheckResult "SQL TCP/IP Protocol" "OK"
                if (-not $sqlNetwork.StaticPort1433) {
                    Write-CheckResult "SQL TCP Port" "FAIL" "Port: $($sqlNetwork.TcpPort)"
                    $null = $issues.Add(@{ Severity = 'CRITICAL'; Issue = "TCP port is '$($sqlNetwork.TcpPort)' but should be 1433"; Fix = 'Set TCP port to 1433'; RepairAction = 'EnableSqlTcpIp'; Repairable = $true })
                }
            }
            if ($sqlNetwork.NamedPipesEnabled -ne 1) {
                Write-CheckResult "SQL Named Pipes Protocol" "FAIL"
                $null = $issues.Add(@{ Severity = 'MEDIUM'; Issue = 'Named Pipes protocol is disabled'; Fix = 'Enable Named Pipes protocol'; RepairAction = 'EnableSqlNamedPipes'; Repairable = $true })
            } else {
                Write-CheckResult "SQL Named Pipes Protocol" "OK"
            }
        } else {
            Write-CheckResult "SQL networking registry" "SKIP" "Registry path not found"
        }
    }

    # CHECK: SQL firewall rules
    $sqlFirewallCheck = Test-AllSqlFirewallRules
    if (-not $sqlFirewallCheck.AllPresent) {
        Write-CheckResult "SQL Server Firewall Rules" "FAIL" "Missing: $($sqlFirewallCheck.Missing -join ', ')"
        $null = $issues.Add(@{ Severity = 'HIGH'; Issue = "Missing SQL Server firewall rules: $($sqlFirewallCheck.Missing -join ', ')"; Fix = 'Create firewall rules for SQL Server'; RepairAction = 'RepairSqlFirewall'; Repairable = $true })
    } else {
        Write-CheckResult "SQL Server Firewall Rules" "OK"
    }

    # CHECK: IIS content path + WSUS Application Pool
    try {
        $iisContentPath = Join-Path $ContentPath 'WsusContent'
        $iisContent = if (Get-Command Get-WsusHostIisContentPath -ErrorAction SilentlyContinue) { Get-WsusHostIisContentPath -ExpectedPath $iisContentPath } else { $null }
        if ($iisContent -and $iisContent.Found -and -not $iisContent.MatchesExpected) {
            Write-CheckResult "WSUS IIS Content Path" "FAIL" "IIS: $($iisContent.PhysicalPath); expected: $iisContentPath"
            $null = $issues.Add(@{ Severity = 'HIGH'; Issue = 'IIS /Content path does not point to WsusContent'; Fix = "Set IIS /Content physical path to $iisContentPath"; RepairAction = 'RepairIisContentPath'; Repairable = $true })
        } elseif ($iisContent -and $iisContent.Found) {
            Write-CheckResult "WSUS IIS Content Path" "OK"
        }

        Import-Module WebAdministration -ErrorAction Stop
        $appPool = Get-WebAppPoolState -Name "WsusPool" -ErrorAction SilentlyContinue
        if (-not $appPool) {
            Write-CheckResult "WSUS Application Pool" "FAIL"
            $null = $issues.Add(@{ Severity = 'HIGH'; Issue = 'WsusPool application pool not found'; Fix = 'Reinstall WSUS or create app pool'; RepairAction = $null; Repairable = $false })
        } elseif ($appPool.Value -ne "Started") {
            Write-CheckResult "WSUS Application Pool" "FAIL" "Status: $($appPool.Value)"
            $null = $issues.Add(@{ Severity = 'HIGH'; Issue = "WsusPool is $($appPool.Value)"; Fix = 'Start WsusPool application pool'; RepairAction = 'StartWsusPool'; Repairable = $true })
        } else {
            Write-CheckResult "WSUS Application Pool" "OK"
        }
    } catch {
        Write-CheckResult "WSUS Application Pool" "SKIP" "WebAdministration module not available"
    }

    # CHECK: WSUS firewall rules
    $wsusFirewallCheck = Test-AllWsusFirewallRules
    if (-not $wsusFirewallCheck.AllPresent) {
        Write-CheckResult "WSUS Firewall Rules" "FAIL" "Missing: $($wsusFirewallCheck.Missing -join ', ')"
        $null = $issues.Add(@{ Severity = 'MEDIUM'; Issue = "Missing WSUS firewall rules: $($wsusFirewallCheck.Missing -join ', ')"; Fix = 'Create firewall rules for WSUS ports 8530/8531'; RepairAction = 'RepairWsusFirewall'; Repairable = $true })
    } else {
        Write-CheckResult "WSUS Firewall Rules" "OK"
    }

    # CHECK: SUSDB database exists
    $sqlService = $svcData.States[$sqlServiceName]
    if ($sqlService -and $sqlService.Running) {
        try {
            $dbCheck = Invoke-WsusHostSqlQuery -ServerInstance $SqlInstance -Database master -Query "SELECT DB_ID('SUSDB') AS DatabaseID" -QueryTimeout 10
            if ($null -ne $dbCheck.DatabaseID) {
                Write-CheckResult "SUSDB Database" "OK"
            } else {
                Write-CheckResult "SUSDB Database" "FAIL"
                $null = $issues.Add(@{ Severity = 'CRITICAL'; Issue = 'SUSDB database does not exist'; Fix = 'Run WSUS postinstall: wsusutil.exe postinstall'; RepairAction = $null; Repairable = $false })
            }
        } catch {
            Write-CheckResult "SUSDB Database" "FAIL" "Cannot connect to SQL Server"
            $null = $issues.Add(@{ Severity = 'CRITICAL'; Issue = 'Cannot connect to SQL Server to verify SUSDB'; Fix = 'Verify SQL Server is running and accessible'; RepairAction = $null; Repairable = $false })
        }
    } else {
        Write-CheckResult "SUSDB Database" "SKIP" "SQL Server not running"
    }

    # CHECK: NETWORK SERVICE SQL login
    if ($sqlService -and $sqlService.Running) {
        try {
            $loginCheck = Invoke-WsusHostSqlQuery -ServerInstance $SqlInstance -Database master -Query "SELECT name FROM sys.server_principals WHERE name='NT AUTHORITY\NETWORK SERVICE'" -QueryTimeout 10
            if ($loginCheck -and $loginCheck.name) {
                Write-CheckResult "NETWORK SERVICE SQL Login" "OK"
            } else {
                Write-CheckResult "NETWORK SERVICE SQL Login" "FAIL"
                $null = $issues.Add(@{ Severity = 'HIGH'; Issue = 'NT AUTHORITY\NETWORK SERVICE login missing'; Fix = 'Create login and grant dbcreator role'; RepairAction = 'GrantNetworkServiceLogin'; Repairable = $true })
            }
        } catch {
            Write-CheckResult "NETWORK SERVICE SQL Login" "SKIP" "Could not query SQL Server"
        }
    } else {
        Write-CheckResult "NETWORK SERVICE SQL Login" "SKIP" "SQL Server not running"
    }

    # CHECK: content directory permissions
    $wsusContent = Join-Path $ContentPath "WsusContent"
    $contentDirExists = (Test-Path $wsusContent) -or ((Get-WsusHostPathState -Path $ContentPath).Exists)
    if ($contentDirExists) {
        $permCheck = Test-WsusContentPermissions -ContentPath $ContentPath
        if (-not $permCheck.AllCorrect) {
            Write-CheckResult "WSUS Content Permissions" "FAIL" "Missing: $($permCheck.Missing -join ', ')"
            $null = $issues.Add(@{ Severity = 'MEDIUM'; Issue = "Missing permissions on content directory: $($permCheck.Missing -join ', ')"; Fix = "Grant required permissions on $ContentPath"; RepairAction = 'RepairContentPermissions'; Repairable = $true })
        } else {
            Write-CheckResult "WSUS Content Permissions" "OK"
        }
    } else {
        Write-CheckResult "WSUS Content Directory" "WARN" "Path does not exist: $ContentPath"
    }

    # Convert raw issue hashtables to typed Wsus.DiagnosticIssue objects
    $typedIssues = $issues | ForEach-Object { ConvertTo-WsusDiagnosticIssue -InputObject $_ }
    $fixableCount = @($typedIssues | Where-Object { $_.Repairable }).Count

    # AUTO-FIX
    if ($autoFixEnabled -and $fixableCount -gt 0) {
        Write-Host "`n=== APPLYING AUTO-FIXES ===" -ForegroundColor Cyan
        Write-Host "Fixing $fixableCount issue(s)...`n" -ForegroundColor Green

        foreach ($issue in $typedIssues) {
            if ($issue.Repairable) {
                Write-Host "[FIX] $($issue.Message)..." -NoNewline
                try {
                    Invoke-WsusRepairAction -Action $issue.RepairAction -ContentPath $ContentPath -SqlInstance $SqlInstance -WsusContentPath $wsusContent -SqlServiceName $sqlServiceName | Out-Null
                    Write-Host " SUCCESS" -ForegroundColor Green
                    $fixesApplied += $issue.Message
                } catch {
                    Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
                    $fixesFailed += $issue.Message
                }
            }
        }
        Write-Host "`n[COMPLETE] Auto-fix process finished." -ForegroundColor Cyan
    }

    # RESULTS SUMMARY
    Write-Host "`n=== SCAN RESULTS ===" -ForegroundColor Cyan

    $sslStatus = Get-WsusSSLStatus

    if ($typedIssues.Count -eq 0) {
        Write-Host "`n[SUCCESS] No issues detected! System is healthy." -ForegroundColor Green
    } else {
        Write-Host "`nFound $($typedIssues.Count) issue(s):`n" -ForegroundColor Yellow
        foreach ($issue in $typedIssues) {
            $color = switch ($issue.Severity) { 'Critical' { 'Red' } 'High' { 'Red' } 'Medium' { 'Yellow' } 'Low' { 'Gray' } default { 'White' } }
            Write-Host "[$($issue.Severity)] " -ForegroundColor $color -NoNewline
            Write-Host $issue.Message
            Write-Host "    Fix: $($issue.Recommendation)" -ForegroundColor Gray
            if ($issue.Repairable) { Write-Host "    [AUTO-FIX AVAILABLE]" -ForegroundColor Green }
            Write-Host ""
        }
        if ($fixesFailed.Count -gt 0) { Write-Host "Some fixes failed. Please manually resolve these issues." -ForegroundColor Yellow }
    }

    Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Issues Found: $($typedIssues.Count)"
    Write-Host "Auto-Fixes Applied: $($fixesApplied.Count)"
    Write-Host "Fixes Failed: $($fixesFailed.Count)"
    if ($sslStatus.SSLEnabled) { Write-Host "Protocol: HTTPS (port 8531)" -ForegroundColor Green } else { Write-Host "Protocol: HTTP (port 8530)" -ForegroundColor Gray }
    Write-Host ""

    $healthy = ($typedIssues.Count -eq 0) -or ($autoFixEnabled -and $fixableCount -gt 0 -and $fixesApplied.Count -eq $fixableCount -and $fixesFailed.Count -eq 0)
    $diagnosticReport = New-WsusDiagnosticReport -Issues $typedIssues -FixesApplied $fixesApplied -FixesFailed $fixesFailed -Evidence @{ SSL = $sslStatus }
    $diagnosticReport.Healthy = $healthy

    return @{
        Healthy = $healthy
        IssuesFound = $typedIssues.Count
        IssuesFixed = $fixesApplied.Count
        Issues = $typedIssues
        FixesApplied = $fixesApplied
        FixesFailed = $fixesFailed
        SSL = $sslStatus
        DiagnosticReport = $diagnosticReport
    }
}

# ===========================
# DEEP CONTENT/DOWNLOAD DIAGNOSTICS
# ===========================

<#
.SYNOPSIS
    Runs deep WSUS content/download diagnostics for stuck downloads and post-import failures.
#>
function Invoke-WsusDeepDiagnostics {
    [CmdletBinding()]
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS",
        [switch]$AutoFix
    )

    $autoFixEnabled = if ($PSBoundParameters.ContainsKey('AutoFix')) { [bool]$AutoFix } else { $true }

    Write-Host "`n=== WSUS Deep Content/Download Diagnostics ===" -ForegroundColor Cyan
    Write-Host "Checking content parity, IIS paths, WsusPool, download queue, and recent WSUS errors...`n" -ForegroundColor Gray

    $issues = [System.Collections.Generic.List[object]]::new()
    $fixesApplied = @()
    $fixesFailed = @()
    $checks = @{}
    $recommendations = @()

    function Add-DeepIssue {
        param(
            [ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')][string]$Severity,
            [string]$Issue,
            [string]$Fix,
            [string]$RepairAction = ''
        )
        $null = $issues.Add((New-WsusHealthDiagnosticIssue -Severity $Severity -Issue $Issue -Fix $Fix -RepairAction $RepairAction))
    }

    # Uses Write-CheckResult with -Prefix DEEP (defined at module scope)

    # ---- CHECK: Security context ----
    try {
        $securityContext = Get-WsusHostCurrentSecurityContext
        if ($securityContext) {
            $checks.CurrentUser = @{ Name = $securityContext.UserName; IsAdministrator = $securityContext.IsAdministrator; IsWsusAdministrator = ($securityContext.GroupNames -contains 'BUILTIN\WSUS Administrators') }
            if ($securityContext.IsAdministrator) { Write-CheckResult -Prefix DEEP "Current security context" "OK" "$($securityContext.UserName) is elevated/admin-capable" }
            else { Write-CheckResult -Prefix DEEP "Current security context" "FAIL" "$($securityContext.UserName) is not in Administrators"; Add-DeepIssue -Severity "HIGH" -Issue "Current process is not running with Administrator rights" -Fix "Run diagnostics/repair from an elevated Administrator PowerShell session" }
            if ($securityContext.GroupNames -contains 'BUILTIN\WSUS Administrators') { Write-CheckResult -Prefix DEEP "WSUS Administrators membership" "OK" $securityContext.UserName }
            else { Write-CheckResult -Prefix DEEP "WSUS Administrators membership" "WARN" "$($securityContext.UserName) is not in BUILTIN\WSUS Administrators"; Add-DeepIssue -Severity "MEDIUM" -Issue "Current account is not a member of WSUS Administrators" -Fix "Add the repair/admin account to Local Administrators and WSUS Administrators before rerunning postinstall or server repair" }
        }
    } catch { Write-CheckResult -Prefix DEEP "Current security context" "SKIP" "Could not inspect token groups" }

    # ---- CHECK: Content path ----
    $resolvedContentPath = $ContentPath
    try {
        $contentState = Get-WsusHostPathState -Path $ContentPath
        if ($contentState -and $contentState.Exists) { $resolvedContentPath = $contentState.ResolvedPath; Write-CheckResult -Prefix DEEP "WSUS root content path" "OK" $resolvedContentPath }
        elseif ($contentState) { Write-CheckResult -Prefix DEEP "WSUS root content path" "FAIL" "Missing: $ContentPath"; Add-DeepIssue -Severity "CRITICAL" -Issue "WSUS root content path does not exist: $ContentPath" -Fix "Create the path or rerun WSUS postinstall with the correct CONTENT_DIR" }
        elseif (Test-Path $ContentPath) { $resolvedContentPath = (Resolve-Path $ContentPath -ErrorAction Stop).Path; Write-CheckResult -Prefix DEEP "WSUS root content path" "OK" $resolvedContentPath }
        else { Write-CheckResult -Prefix DEEP "WSUS root content path" "FAIL" "Missing: $ContentPath"; Add-DeepIssue -Severity "CRITICAL" -Issue "WSUS root content path does not exist: $ContentPath" -Fix "Create the path or rerun WSUS postinstall with the correct CONTENT_DIR" }
    } catch { Write-CheckResult -Prefix DEEP "WSUS root content path" "FAIL" $_.Exception.Message; Add-DeepIssue -Severity "CRITICAL" -Issue "Could not resolve WSUS content path: $ContentPath" -Fix "Verify the content drive is mounted and accessible" }
    $checks.ContentPath = $resolvedContentPath

    # ---- CHECK: WsusContent directory ----
    $wsusContentPath = Join-Path $resolvedContentPath "WsusContent"
    $wsusContentState = Get-WsusHostPathState -Path $wsusContentPath
    if (($wsusContentState -and $wsusContentState.Exists) -or (Test-Path $wsusContentPath)) { Write-CheckResult -Prefix DEEP "WsusContent directory" "OK" $wsusContentPath }
    else { Write-CheckResult -Prefix DEEP "WsusContent directory" "FAIL" "Missing: $wsusContentPath"; Add-DeepIssue -Severity "CRITICAL" -Issue "WsusContent directory is missing under $resolvedContentPath" -Fix "Import/copy the WsusContent tree, then run wsusutil reset" }
    $checks.WsusContentPath = $wsusContentPath

    # ---- CHECK: Content ACLs ----
    try {
        if (Test-Path $resolvedContentPath) {
            $permissionCheck = Test-WsusContentPermissions -ContentPath $resolvedContentPath
            $checks.ContentPermissions = $permissionCheck
            if ($permissionCheck.AllCorrect) { Write-CheckResult -Prefix DEEP "WSUS content ACLs" "OK" "Required service and read principals present" }
            else { Write-CheckResult -Prefix DEEP "WSUS content ACLs" "FAIL" "Missing: $(@($permissionCheck.Missing) -join ', ')"; Add-DeepIssue -Severity "HIGH" -Issue "WSUS content folder permissions are incomplete" -Fix "Grant NETWORK SERVICE modify, SYSTEM/Administrators full control, and Users/Authenticated Users read access on $resolvedContentPath" -RepairAction "RepairContentPermissions" }
        }
    } catch { Write-CheckResult -Prefix DEEP "WSUS content ACLs" "WARN" "Could not validate ACLs: $($_.Exception.Message)"; Add-DeepIssue -Severity "MEDIUM" -Issue "Could not validate WSUS content folder permissions" -Fix "Run icacls on $resolvedContentPath and verify NETWORK SERVICE, SYSTEM, Administrators, WSUS Administrators, and Users/Authenticated Users access" }

    # ---- CHECK: Registry ContentDir ----
    try {
        $setupKey = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
        $setup = Get-ItemProperty -Path $setupKey -ErrorAction Stop
        $registryContentDir = $setup.ContentDir
        $registrySqlServer = $setup.SqlServerName
        $registrySqlDatabase = $setup.SqlDatabaseName
        $checks.RegistryContentDir = $registryContentDir
        $checks.RegistrySqlServerName = $registrySqlServer
        $checks.RegistrySqlDatabaseName = $registrySqlDatabase
        if ($registryContentDir -and ($registryContentDir.TrimEnd('\') -ieq $resolvedContentPath.TrimEnd('\'))) { Write-CheckResult -Prefix DEEP "WSUS registry ContentDir" "OK" $registryContentDir }
        else { Write-CheckResult -Prefix DEEP "WSUS registry ContentDir" "FAIL" "Registry: $registryContentDir; expected: $resolvedContentPath"; Add-DeepIssue -Severity "HIGH" -Issue "WSUS registry ContentDir does not match the requested content path" -Fix "Run wsusutil postinstall CONTENT_DIR=`"$resolvedContentPath`" or update the WSUS content path" }
        if ($registrySqlServer) {
            $normalizedSqlInstance = $SqlInstance -replace '^\.', $env:COMPUTERNAME
            if ($registrySqlServer -ieq $normalizedSqlInstance -or ($registrySqlServer -ieq $env:COMPUTERNAME -and $SqlInstance -match '\\SQLEXPRESS$')) { Write-CheckResult -Prefix DEEP "WSUS registry SQL server" "OK" $registrySqlServer }
            else { Write-CheckResult -Prefix DEEP "WSUS registry SQL server" "WARN" "Registry: $registrySqlServer; diagnostics using: $SqlInstance"; Add-DeepIssue -Severity "MEDIUM" -Issue "WSUS registry SQL server does not match the diagnostics SQL instance" -Fix "Verify whether this WSUS server is SQL Express-backed or WID-backed before rerunning postinstall; use the installed database backend, not the wrong instance" }
        }
    } catch { Write-CheckResult -Prefix DEEP "WSUS registry ContentDir" "WARN" "Could not read ContentDir"; Add-DeepIssue -Severity "MEDIUM" -Issue "Could not read WSUS ContentDir from registry" -Fix "Verify WSUS postinstall completed and registry permissions allow access" }

    # ---- CHECK: SQL networking ----
    try {
        $sqlNetwork = Get-WsusHostSqlNetworkingState -SqlInstance $SqlInstance
        $checks.SqlNetworking = @{ Instance = $sqlNetwork.Instance; TcpEnabled = $sqlNetwork.TcpEnabled; TcpPort = $sqlNetwork.TcpPort; TcpDynamicPorts = $sqlNetwork.TcpDynamicPorts; NamedPipesEnabled = $sqlNetwork.NamedPipesEnabled; RegistryPath = $sqlNetwork.RegistryPath }
        if ($sqlNetwork.Found) {
            if ($sqlNetwork.StaticPort1433) { Write-CheckResult -Prefix DEEP "SQL TCP/IP networking" "OK" "TCP 1433 static" }
            else { Write-CheckResult -Prefix DEEP "SQL TCP/IP networking" "WARN" "Enabled=$($sqlNetwork.TcpEnabled), TcpPort=$($sqlNetwork.TcpPort), DynamicPorts=$($sqlNetwork.TcpDynamicPorts)"; Add-DeepIssue -Severity "MEDIUM" -Issue "SQL Server TCP/IP networking is not configured for static port 1433" -Fix "Enable TCP/IP for $($sqlNetwork.Instance), clear dynamic ports, set TCP port 1433, then restart SQL Server" }
            if ($sqlNetwork.NamedPipesEnabled -eq 1) { Write-CheckResult -Prefix DEEP "SQL Named Pipes networking" "OK" "Enabled" }
            else { Write-CheckResult -Prefix DEEP "SQL Named Pipes networking" "WARN" "Named Pipes disabled"; Add-DeepIssue -Severity "LOW" -Issue "SQL Server Named Pipes protocol is disabled" -Fix "Enable Named Pipes if local WSUS/SQL connectivity requires it, then restart SQL Server" }
        } else { Write-CheckResult -Prefix DEEP "SQL networking registry" "SKIP" "No SQL Express network registry path found for $($sqlNetwork.Instance)" }
    } catch { Write-CheckResult -Prefix DEEP "SQL networking registry" "SKIP" "Could not inspect SQL networking configuration" }

    # ---- CHECK: IIS content path + WsusPool ----
    try {
        $iisContent = Get-WsusHostIisContentPath -ExpectedPath $wsusContentPath
        if ($iisContent -and $iisContent.Found) {
            $checks.IisContentPhysicalPath = $iisContent.PhysicalPath
            if ($iisContent.MatchesExpected) { Write-CheckResult -Prefix DEEP "IIS WSUS /Content path" "OK" $iisContent.PhysicalPath }
            else { Write-CheckResult -Prefix DEEP "IIS WSUS /Content path" "FAIL" "IIS: $($iisContent.PhysicalPath); expected: $wsusContentPath"; Add-DeepIssue -Severity "HIGH" -Issue "IIS WSUS /Content virtual directory points at the wrong path" -Fix "Set IIS /Content physicalPath to $wsusContentPath" -RepairAction "RepairIisContentPath" }
        } else {
            if ($iisContent -and $iisContent.Error) { Write-CheckResult -Prefix DEEP "IIS deep checks" "SKIP" $iisContent.Error }
            else { Write-CheckResult -Prefix DEEP "IIS WSUS /Content path" "FAIL" "Virtual directory not found"; Add-DeepIssue -Severity "HIGH" -Issue "IIS WSUS /Content virtual directory is missing" -Fix "Repair/reinstall WSUS IIS components or rerun WSUS postinstall" }
        }

        Import-Module WebAdministration -ErrorAction Stop
        $appPoolPath = "IIS:\AppPools\WsusPool"
        if (Test-Path $appPoolPath) {
            $poolState = Get-WebAppPoolState -Name "WsusPool" -ErrorAction SilentlyContinue
            $pool = Get-ItemProperty -Path $appPoolPath -ErrorAction SilentlyContinue
            $checks.WsusPoolState = if ($poolState) { $poolState.Value } else { "Unknown" }
            $checks.WsusPoolQueueLength = $pool.queueLength
            $checks.WsusPoolPrivateMemory = $pool.recycling.periodicRestart.privateMemory
            $checks.WsusPoolIdleTimeout = $pool.processModel.idleTimeout
            $checks.WsusPoolPeriodicRestartTime = $pool.recycling.periodicRestart.time

            if ($poolState -and $poolState.Value -eq "Started") { Write-CheckResult -Prefix DEEP "WsusPool state" "OK" "Started" }
            else { Write-CheckResult -Prefix DEEP "WsusPool state" "FAIL" "State: $($checks.WsusPoolState)"; Add-DeepIssue -Severity "HIGH" -Issue "WsusPool is not started" -Fix "Start WsusPool" -RepairAction "StartWsusPool" }

            $idleTimeout = [string]$pool.processModel.idleTimeout
            $periodicRestartTime = [string]$pool.recycling.periodicRestart.time
            $capacityBad = (($pool.queueLength -and [int]$pool.queueLength -lt 25000) -or ($pool.recycling.periodicRestart.privateMemory -and [int]$pool.recycling.periodicRestart.privateMemory -gt 0))
            $recycleBad = ($idleTimeout -and $idleTimeout -ne "00:00:00") -or ($periodicRestartTime -and $periodicRestartTime -ne "00:00:00")
            if ($capacityBad -or $recycleBad) {
                Write-CheckResult -Prefix DEEP "WsusPool capacity/recycle settings" "WARN" "QueueLength=$($pool.queueLength), PrivateMemoryKB=$($pool.recycling.periodicRestart.privateMemory), Idle=$idleTimeout, Recycle=$periodicRestartTime"
                Add-DeepIssue -Severity "MEDIUM" -Issue "WsusPool capacity or recycle settings may throttle downloads or client installs" -Fix "Set WsusPool queueLength 25000, private memory 0, idle timeout 0, and periodic recycle interval 0" -RepairAction "TuneWsusPool"
            } else { Write-CheckResult -Prefix DEEP "WsusPool capacity/recycle settings" "OK" "QueueLength=$($pool.queueLength), PrivateMemoryKB=$($pool.recycling.periodicRestart.privateMemory), Idle=$idleTimeout, Recycle=$periodicRestartTime" }
        } else { Write-CheckResult -Prefix DEEP "WsusPool configuration" "FAIL" "App pool not found"; Add-DeepIssue -Severity "HIGH" -Issue "WsusPool application pool is missing" -Fix "Repair/reinstall WSUS IIS components" }
    } catch { Write-CheckResult -Prefix DEEP "IIS deep checks" "SKIP" "WebAdministration unavailable or IIS path inaccessible"; $recommendations += "Run this diagnostic on the WSUS server with the WebAdministration module available to validate IIS /Content and WsusPool settings." }

    # ---- CHECK: BITS service ----
    $bits = Get-WsusHostServiceState -Name 'BITS' | Select-Object -First 1
    if ($bits.Installed) {
        $checks.BitsStatus = $bits.Status
        if ($bits.Running) { Write-CheckResult -Prefix DEEP "BITS service" "OK" "Running" }
        else { Write-CheckResult -Prefix DEEP "BITS service" "WARN" "Status: $($bits.Status)"; Add-DeepIssue -Severity "MEDIUM" -Issue "BITS service is not running" -Fix "Start BITS service" -RepairAction "StartBits" }

        try {
            $bitsPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\BITS"
            if (Test-Path $bitsPolicyPath) { $checks.BitsPolicy = Get-ItemProperty -Path $bitsPolicyPath -ErrorAction Stop; Write-CheckResult -Prefix DEEP "BITS throttling policy" "WARN" "BITS policy keys exist on this server"; $recommendations += "Review BITS throttling GPO under Computer Configuration > Administrative Templates > Network > Background Intelligent Transfer Service on WSUS clients and server." }
            else { Write-CheckResult -Prefix DEEP "BITS throttling policy" "OK" "No local BITS policy key found" }
        } catch { Write-CheckResult -Prefix DEEP "BITS throttling policy" "SKIP" "Could not inspect BITS policy" }
    } else { Write-CheckResult -Prefix DEEP "BITS service" "WARN" "Service not found"; Add-DeepIssue -Severity "LOW" -Issue "BITS service was not found" -Fix "Verify Windows BITS component installation" }

    # ---- CHECK: SUSDB content file state ----
    try {
        $downloadQuery = @"
SELECT
    (SELECT COUNT(*) FROM tbFileOnServer) AS FilesTotal,
    (SELECT COUNT(*) FROM tbFileOnServer WHERE ActualState = 1) AS FilesPresent,
    (SELECT COUNT(*) FROM tbFileDownloadProgress) AS FilesInDownloadQueue,
    (SELECT COUNT(*) FROM tbFileOnServer WHERE ActualState <> 1) AS FilesNotPresent
"@
        $downloadState = Invoke-WsusHostSqlQuery -ServerInstance $SqlInstance -Database SUSDB -Query $downloadQuery -QueryTimeout 30
        $filesTotal = [int]$downloadState.FilesTotal; $filesPresent = [int]$downloadState.FilesPresent; $filesInQueue = [int]$downloadState.FilesInDownloadQueue; $filesNotPresent = [int]$downloadState.FilesNotPresent
        $percentPresent = if ($filesTotal -gt 0) { [math]::Round(($filesPresent / $filesTotal) * 100, 2) } else { 0 }
        $checks.DownloadState = @{ FilesTotal = $filesTotal; FilesPresent = $filesPresent; FilesNotPresent = $filesNotPresent; FilesInDownloadQueue = $filesInQueue; PercentPresent = $percentPresent }

        if ($filesTotal -eq 0) { Write-CheckResult -Prefix DEEP "SUSDB content file state" "WARN" "No file rows found"; Add-DeepIssue -Severity "MEDIUM" -Issue "SUSDB has no content file records" -Fix "Verify synchronization/import completed and metadata exists" }
        elseif ($filesInQueue -gt 0 -and $percentPresent -ge 99) { Write-CheckResult -Prefix DEEP "SUSDB download queue" "FAIL" "$percentPresent% present; $filesInQueue files still queued"; Add-DeepIssue -Severity "HIGH" -Issue "Content appears stuck near completion with files still in the download queue" -Fix "Run wsusutil reset to re-verify and requeue missing files" -RepairAction "ResetWsusContent"; Write-CheckResult -Prefix DEEP "SUSDB content file state" "WARN" "$filesNotPresent of $filesTotal files not present ($percentPresent% present)"; Add-DeepIssue -Severity "MEDIUM" -Issue "SUSDB expects content files that are not marked present" -Fix "Confirm the imported WsusContent tree is complete, then run wsusutil reset" -RepairAction "ResetWsusContent" }
        else { Write-CheckResult -Prefix DEEP "SUSDB content file state" "OK" "$filesPresent of $filesTotal files present" }
    } catch { Write-CheckResult -Prefix DEEP "SUSDB content file state" "FAIL" $_.Exception.Message; Add-DeepIssue -Severity "HIGH" -Issue "Could not query SUSDB content/download state" -Fix "Verify SQL connectivity and SUSDB table access" }

    # ---- CHECK: wsusutil checkhealth ----
    try {
        $wsusutil = "C:\Program Files\Update Services\Tools\wsusutil.exe"
        $checkHealth = Invoke-WsusHostCommand -FilePath $wsusutil -ArgumentList @('checkhealth')
        if ($checkHealth.Success) { $checks.WsusUtilCheckHealth = @($checkHealth.Output); Write-CheckResult -Prefix DEEP "wsusutil checkhealth" "OK" "Command completed; review WSUS event log for health details"; $recommendations += "After wsusutil checkhealth, inspect Applications and Services Logs > Microsoft > Windows > Windows Server Update Services for the generated health events." }
        else { Write-CheckResult -Prefix DEEP "wsusutil checkhealth" "WARN" $checkHealth.Error; Add-DeepIssue -Severity "MEDIUM" -Issue "wsusutil checkhealth failed" -Fix "Verify the WSUS role/tools installation under C:\Program Files\Update Services\Tools, then run wsusutil checkhealth from an elevated shell" }
    } catch { Write-CheckResult -Prefix DEEP "wsusutil checkhealth" "WARN" "Command failed: $($_.Exception.Message)"; Add-DeepIssue -Severity "MEDIUM" -Issue "wsusutil checkhealth failed" -Fix "Run wsusutil checkhealth from an elevated shell and inspect WSUS event logs for unauthorized, content, or database errors" }

    # ---- CHECK: WSUS API download progress ----
    try {
        $server = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()
        $subscription = $server.GetSubscription()
        $syncStatus = $subscription.GetSynchronizationStatus()
        $downloadProgress = $server.GetContentDownloadProgress()
        $configuration = $server.GetConfiguration()
        $checks.WsusApi = @{
            SynchronizationStatus = $syncStatus.ToString()
            FilesToDownload = $downloadProgress.FilesToDownload; FilesDownloaded = $downloadProgress.FilesDownloaded
            DownloadedBytes = $downloadProgress.DownloadedBytes; TotalBytesToDownload = $downloadProgress.TotalBytesToDownload; ProxyName = $configuration.ProxyName
        }
        if ($downloadProgress.FilesToDownload -gt $downloadProgress.FilesDownloaded) {
            Write-CheckResult -Prefix DEEP "WSUS API download progress" "WARN" "$($downloadProgress.FilesDownloaded)/$($downloadProgress.FilesToDownload) files downloaded"
            $recommendations += "If progress does not change across repeated runs, run Reset Content and inspect Event Viewer for WSUS Event ID 364 download errors."
        } else { Write-CheckResult -Prefix DEEP "WSUS API download progress" "OK" "$($downloadProgress.FilesDownloaded)/$($downloadProgress.FilesToDownload) files downloaded" }
        Write-CheckResult -Prefix DEEP "WSUS synchronization status" "OK" $syncStatus.ToString()
    } catch { Write-CheckResult -Prefix DEEP "WSUS API progress" "SKIP" "UpdateServices API unavailable or WSUS console components missing"; $recommendations += "Install/use WSUS Administration Console components on the server to inspect live synchronization and content download progress." }

    # ---- CHECK: Recent WSUS/IIS/SQL events ----
    try {
        $since = (Get-Date).AddDays(-2)
        $events = Get-WsusHostEventSummary -LogNames @('Application','Microsoft-Windows-Windows Server Update Services/Operational') -MaxEvents 20 -Since $since |
            Where-Object { $_.ProviderName -match 'Update Services|WSUS|W3SVC|MSSQL|IIS' -or $_.LogName -eq 'Microsoft-Windows-Windows Server Update Services/Operational' }
        if ($events) { Write-CheckResult -Prefix DEEP "Recent WSUS/IIS/SQL events" "WARN" "$(@($events).Count) warnings/errors in the last 48 hours"; $recommendations += "Review Application and Microsoft-Windows-Windows Server Update Services/Operational logs for download, unauthorized, database, and IIS errors; prioritize WSUS Event IDs 364, 386, and 10032." }
        else { Write-CheckResult -Prefix DEEP "Recent WSUS/IIS/SQL events" "OK" "No matching warnings/errors in the last 48 hours" }
    } catch { Write-CheckResult -Prefix DEEP "Recent WSUS/IIS/SQL events" "SKIP" "Could not read Application or WSUS event logs" }

    # ---- AUTO-FIX ----
    $tyDeepIssues = $issues | ForEach-Object { ConvertTo-WsusDiagnosticIssue -InputObject $_ -IncludeLegacyAliases }
    $fixableCount = @($tyDeepIssues | Where-Object { $_.Repairable }).Count
    if ($autoFixEnabled -and $fixableCount -gt 0) {
        $fixSqlServiceName = if ($SqlInstance -match '\\([^\\]+)$') { "MSSQL`$$($Matches[1])" } else { 'MSSQLSERVER' }
        Write-Host "`n=== APPLYING DEEP AUTO-FIXES ===" -ForegroundColor Cyan
        foreach ($issue in $tyDeepIssues) {
            if ($issue.Repairable) {
                Write-Host "[FIX] $($issue.Message)..." -NoNewline
                try {
                    Invoke-WsusRepairAction -Action $issue.RepairAction -ContentPath $resolvedContentPath -SqlInstance $SqlInstance -WsusContentPath $wsusContentPath -SqlServiceName $fixSqlServiceName | Out-Null
                    Write-Host " SUCCESS" -ForegroundColor Green; $fixesApplied += $issue.Message
                } catch { Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red; $fixesFailed += $issue.Message }
            }
        }
    }

    if ($tyDeepIssues.Count -eq 0) { Write-Host "`n[DEEP] No deep content/download issues detected." -ForegroundColor Green }
    else { Write-Host "`n[DEEP] Found $($tyDeepIssues.Count) deep issue(s)." -ForegroundColor Yellow }

    if ($recommendations.Count -gt 0) { Write-Host "`n=== RECOMMENDATIONS ===" -ForegroundColor Cyan; $recommendations | Select-Object -Unique | ForEach-Object { Write-Host "- $_" -ForegroundColor Gray } }

    $deepFixableCount = @($tyDeepIssues | Where-Object { $_.Repairable }).Count
    $healthy = ($tyDeepIssues.Count -eq 0) -or ($autoFixEnabled -and $deepFixableCount -gt 0 -and $fixesFailed.Count -eq 0 -and $fixesApplied.Count -eq $deepFixableCount)
    $diagnosticReport = New-WsusDiagnosticReport -Issues $tyDeepIssues -FixesApplied $fixesApplied -FixesFailed $fixesFailed -Evidence $checks -Recommendations @($recommendations | Select-Object -Unique)
    $diagnosticReport.Healthy = $healthy

    return @{
        Healthy = $healthy
        IssuesFound = [int]$tyDeepIssues.Count; IssuesFixed = [int]$fixesApplied.Count
        Issues = $tyDeepIssues
        RepairPlan = @($diagnosticReport.RepairPlan)
        FixesApplied = $fixesApplied; FixesFailed = $fixesFailed
        Checks = $checks
        Recommendations = @($recommendations | Select-Object -Unique)
        DiagnosticReport = $diagnosticReport
    }
}

# ===========================
# LEGACY COMPATIBILITY WRAPPERS
# ===========================

<#
.SYNOPSIS
    [Legacy] Performs comprehensive WSUS health check. Now implemented as a thin
    wrapper around Invoke-WsusDiagnostics for backward compatibility.
#>
function Test-WsusHealth {
    [CmdletBinding()]
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS",
        [switch]$IncludeDatabase
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "WSUS Health Check (legacy compatibility)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $diagnosticsParams = @{ ContentPath = $ContentPath; SqlInstance = $SqlInstance; AutoFix = $false }
    $diagResult = Invoke-WsusDiagnostics @diagnosticsParams

    $health = @{
        Overall = if ($diagResult.Issues.Count -eq 0) { "Healthy" } elseif ($diagResult.Issues | Where-Object { $_.Severity -in @('Critical','High') }) { "Unhealthy" } else { "Degraded" }
        Issues = @($diagResult.Issues | ForEach-Object { "$($_.Severity): $($_.Message)" })
        SSL = $diagResult.SSL
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Health Check Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    if ($health.SSL.SSLEnabled) {
        Write-Host "Protocol: HTTPS (port 8531)" -ForegroundColor Green
        if ($health.SSL.CertificateExpires -and ($health.SSL.CertificateExpires - (Get-Date)).Days -lt 30) { Write-Host "Certificate expires in $(($health.SSL.CertificateExpires - (Get-Date)).Days) days!" -ForegroundColor Yellow }
    } else { Write-Host "Protocol: HTTP (port 8530)" -ForegroundColor Gray }
    Write-Host ""
    switch ($health.Overall) {
        "Healthy" { Write-Host "Overall Status: HEALTHY" -ForegroundColor Green; Write-Host "All systems operational" -ForegroundColor Green }
        "Degraded" { Write-Host "Overall Status: DEGRADED" -ForegroundColor Yellow; Write-Host "System is operational but has warnings" -ForegroundColor Yellow }
        "Unhealthy" { Write-Host "Overall Status: UNHEALTHY" -ForegroundColor Red; Write-Host "Critical issues detected" -ForegroundColor Red }
    }
    if ($health.Issues.Count -gt 0) { Write-Host "`nIssues Found:" -ForegroundColor Yellow; $health.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red } }
    Write-Host ""
    return $health
}

<#
.SYNOPSIS
    [Legacy] Attempts to automatically repair common WSUS health issues.
    Now delegates to Invoke-WsusDiagnostics for the actual work.
#>
function Repair-WsusHealth {
    [CmdletBinding()]
    param(
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "WSUS Health Repair (legacy compatibility)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $result = Invoke-WsusDiagnostics -ContentPath $ContentPath -SqlInstance $SqlInstance -AutoFix

    $results = @{
        ServicesStarted = @($result.FixesApplied)
        FirewallsCreated = @()
        PermissionsFixed = @($result.FixesApplied | Where-Object { $_ -like 'Missing permissions on content directory:*' }).Count -gt 0
        IisContentPathFixed = @($result.FixesApplied -contains 'IIS /Content path does not point to WsusContent')
        Success = ($result.FixesFailed.Count -eq 0)
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Repair Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Services Started: $($result.FixesApplied.Count)"
    Write-Host "Fixes Failed: $($result.FixesFailed.Count)"
    if ($results.Success) { Write-Host "`nRepair completed successfully" -ForegroundColor Green } else { Write-Host "`nRepair completed with errors" -ForegroundColor Red }
    Write-Host ""
    return $results
}

# Export functions
Export-ModuleMember -Function @(
    'Get-WsusSSLStatus',
    'Test-WsusDatabaseConnection',
    'Test-WsusHealth',
    'Repair-WsusHealth',
    'Invoke-WsusDiagnostics',
    'Invoke-WsusDeepDiagnostics',
    'Get-WsusHealthScore'
)
