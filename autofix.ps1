#Requires -RunAsAdministrator

# =====================================================================
# WSUS + SQL SERVER AUTO-FIX SCRIPT
# Detects common issues and offers automated fixes
# =====================================================================

$ErrorActionPreference = "Continue"
$issues = @()
$fixes = @()

Write-Host "=== WSUS + SQL Server Auto-Fix Utility ===" -ForegroundColor Cyan
Write-Host "Scanning for common issues...`n" -ForegroundColor Gray

# -------------------------
# ISSUE CHECKS
# -------------------------

# Check 1: SQL Server Service
Write-Host "[CHECK] SQL Server Service Status..." -NoNewline
$sqlService = Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
if (!$sqlService) {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "CRITICAL"
        Issue = "SQL Server service not found"
        Fix = "Install SQL Server Express or verify instance name"
        AutoFix = $null
    }
} elseif ($sqlService.Status -ne "Running") {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "CRITICAL"
        Issue = "SQL Server service is $($sqlService.Status)"
        Fix = "Start SQL Server service"
        AutoFix = { Start-Service 'MSSQL$SQLEXPRESS' -ErrorAction Stop }
    }
} else {
    Write-Host " OK" -ForegroundColor Green
}

# Check 2: SQL Browser Service
Write-Host "[CHECK] SQL Browser Service Status..." -NoNewline
$browserService = Get-Service 'SQLBrowser' -ErrorAction SilentlyContinue
if (!$browserService) {
    Write-Host " WARN" -ForegroundColor Yellow
    $issues += @{
        Severity = "MEDIUM"
        Issue = "SQL Browser service not found"
        Fix = "SQL Browser is recommended for named instances"
        AutoFix = $null
    }
} elseif ($browserService.Status -ne "Running") {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "MEDIUM"
        Issue = "SQL Browser service is $($browserService.Status)"
        Fix = "Start SQL Browser service"
        AutoFix = { 
            Set-Service SQLBrowser -StartupType Automatic
            Start-Service SQLBrowser -ErrorAction Stop
        }
    }
} else {
    Write-Host " OK" -ForegroundColor Green
}

# Check 3: TCP/IP Protocol
Write-Host "[CHECK] SQL TCP/IP Protocol..." -NoNewline
$tcpPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Tcp"
if (Test-Path $tcpPath) {
    $tcpEnabled = (Get-ItemProperty $tcpPath -ErrorAction SilentlyContinue).Enabled
    if ($tcpEnabled -ne 1) {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "CRITICAL"
            Issue = "TCP/IP protocol is disabled"
            Fix = "Enable TCP/IP and set port 1433"
            AutoFix = {
                Set-ItemProperty "$tcpPath" -Name Enabled -Value 1
                Set-ItemProperty "$tcpPath\IPAll" -Name TcpDynamicPorts -Value "" -Force
                Set-ItemProperty "$tcpPath\IPAll" -Name TcpPort -Value "1433" -Force
                Restart-Service 'MSSQL$SQLEXPRESS' -Force
            }
        }
    } else {
        Write-Host " OK" -ForegroundColor Green
    }
} else {
    Write-Host " SKIP" -ForegroundColor Yellow
}

# Check 4: Named Pipes Protocol
Write-Host "[CHECK] SQL Named Pipes Protocol..." -NoNewline
$npPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQLServer\SuperSocketNetLib\Np"
if (Test-Path $npPath) {
    $npEnabled = (Get-ItemProperty $npPath -ErrorAction SilentlyContinue).Enabled
    if ($npEnabled -ne 1) {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "HIGH"
            Issue = "Named Pipes protocol is disabled"
            Fix = "Enable Named Pipes"
            AutoFix = {
                Set-ItemProperty "$npPath" -Name Enabled -Value 1
                Restart-Service 'MSSQL$SQLEXPRESS' -Force
            }
        }
    } else {
        Write-Host " OK" -ForegroundColor Green
    }
} else {
    Write-Host " SKIP" -ForegroundColor Yellow
}

# Check 5: SQL Firewall Rule
Write-Host "[CHECK] SQL Server Firewall Rule..." -NoNewline
$sqlFirewallRule = Get-NetFirewallRule -DisplayName "*SQL*1433*" -ErrorAction SilentlyContinue | Where-Object {$_.Enabled -eq $true}
if (!$sqlFirewallRule) {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "HIGH"
        Issue = "No firewall rule for SQL Server port 1433"
        Fix = "Create firewall rule for TCP port 1433"
        AutoFix = {
            New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -ErrorAction Stop
        }
    }
} else {
    Write-Host " OK" -ForegroundColor Green
}

# Check 6: WSUS Service
Write-Host "[CHECK] WSUS Service Status..." -NoNewline
$wsusService = Get-Service 'WsusService' -ErrorAction SilentlyContinue
if (!$wsusService) {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "CRITICAL"
        Issue = "WSUS service not found"
        Fix = "Install WSUS role"
        AutoFix = $null
    }
} elseif ($wsusService.Status -ne "Running") {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "CRITICAL"
        Issue = "WSUS service is $($wsusService.Status)"
        Fix = "Start WSUS service"
        AutoFix = { Start-Service WsusService -ErrorAction Stop }
    }
} else {
    Write-Host " OK" -ForegroundColor Green
}

# Check 7: IIS Service
Write-Host "[CHECK] IIS Service Status..." -NoNewline
$iisService = Get-Service 'W3SVC' -ErrorAction SilentlyContinue
if (!$iisService) {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "HIGH"
        Issue = "IIS service not found"
        Fix = "Install IIS"
        AutoFix = $null
    }
} elseif ($iisService.Status -ne "Running") {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "HIGH"
        Issue = "IIS service is $($iisService.Status)"
        Fix = "Start IIS service"
        AutoFix = { Start-Service W3SVC -ErrorAction Stop }
    }
} else {
    Write-Host " OK" -ForegroundColor Green
}

# Check 8: WSUS Application Pool
Write-Host "[CHECK] WSUS Application Pool..." -NoNewline
try {
    Import-Module WebAdministration -ErrorAction Stop
    $appPool = Get-WebAppPoolState -Name "WsusPool" -ErrorAction SilentlyContinue
    if (!$appPool) {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "HIGH"
            Issue = "WsusPool application pool not found"
            Fix = "Reinstall WSUS or create app pool"
            AutoFix = $null
        }
    } elseif ($appPool.Value -ne "Started") {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "HIGH"
            Issue = "WsusPool is $($appPool.Value)"
            Fix = "Start WsusPool application pool"
            AutoFix = { Start-WebAppPool -Name "WsusPool" -ErrorAction Stop }
        }
    } else {
        Write-Host " OK" -ForegroundColor Green
    }
} catch {
    Write-Host " SKIP" -ForegroundColor Yellow
}

# Check 9: WSUS Firewall Rules
Write-Host "[CHECK] WSUS Firewall Rules..." -NoNewline
$wsusFirewallHttp = Get-NetFirewallRule -DisplayName "*WSUS*8530*" -ErrorAction SilentlyContinue | Where-Object {$_.Enabled -eq $true}
if (!$wsusFirewallHttp) {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "MEDIUM"
        Issue = "No firewall rule for WSUS port 8530"
        Fix = "Create firewall rule for TCP port 8530"
        AutoFix = {
            New-NetFirewallRule -DisplayName "WSUS HTTP (TCP 8530)" -Direction Inbound -Protocol TCP -LocalPort 8530 -Action Allow -ErrorAction Stop
        }
    }
} else {
    Write-Host " OK" -ForegroundColor Green
}

# Check 10: SUSDB Database Exists
Write-Host "[CHECK] SUSDB Database..." -NoNewline
try {
    $dbCheck = sqlcmd -S ".\SQLEXPRESS" -E -Q "SELECT name FROM sys.databases WHERE name='SUSDB'" -h -1 2>&1
    if ($dbCheck -match "SUSDB") {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "CRITICAL"
            Issue = "SUSDB database does not exist"
            Fix = "Run WSUS postinstall: wsusutil.exe postinstall"
            AutoFix = $null
        }
    }
} catch {
    Write-Host " FAIL" -ForegroundColor Red
    $issues += @{
        Severity = "CRITICAL"
        Issue = "Cannot connect to SQL Server"
        Fix = "Verify SQL Server is running and accessible"
        AutoFix = $null
    }
}

# Check 11: NETWORK SERVICE Login
Write-Host "[CHECK] NETWORK SERVICE SQL Login..." -NoNewline
try {
    $loginCheck = sqlcmd -S ".\SQLEXPRESS" -E -Q "SELECT name FROM sys.server_principals WHERE name='NT AUTHORITY\NETWORK SERVICE'" -h -1 2>&1
    if ($loginCheck -match "NETWORK SERVICE") {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "HIGH"
            Issue = "NT AUTHORITY\NETWORK SERVICE login missing"
            Fix = "Create login and grant dbcreator role"
            AutoFix = {
                sqlcmd -S ".\SQLEXPRESS" -E -Q "CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS;" 2>&1 | Out-Null
                sqlcmd -S ".\SQLEXPRESS" -E -Q "ALTER SERVER ROLE [dbcreator] ADD MEMBER [NT AUTHORITY\NETWORK SERVICE];" 2>&1 | Out-Null
            }
        }
    }
} catch {
    Write-Host " SKIP" -ForegroundColor Yellow
}

# Check 12: WSUS Content Directory
Write-Host "[CHECK] WSUS Content Directory..." -NoNewline
$wsusContent = "C:\WSUS\WsusContent"
if (Test-Path $wsusContent) {
    $acl = Get-Acl $wsusContent
    $networkServiceAccess = $acl.Access | Where-Object {$_.IdentityReference -like "*NETWORK SERVICE*"}
    if (!$networkServiceAccess) {
        Write-Host " FAIL" -ForegroundColor Red
        $issues += @{
            Severity = "MEDIUM"
            Issue = "NETWORK SERVICE lacks permissions on content directory"
            Fix = "Grant NETWORK SERVICE modify permissions"
            AutoFix = {
                icacls $wsusContent /grant "NETWORK SERVICE:(OI)(CI)M" /T /Q | Out-Null
            }
        }
    } else {
        Write-Host " OK" -ForegroundColor Green
    }
} else {
    Write-Host " WARN" -ForegroundColor Yellow
}

# -------------------------
# RESULTS
# -------------------------

Write-Host "`n=== SCAN RESULTS ===" -ForegroundColor Cyan

if ($issues.Count -eq 0) {
    Write-Host "`n[SUCCESS] No issues detected!" -ForegroundColor Green
    exit 0
}

Write-Host "`nFound $($issues.Count) issue(s):`n" -ForegroundColor Yellow

$fixable = 0
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
        $fixable++
        Write-Host "    [AUTO-FIX AVAILABLE]" -ForegroundColor Green
    }
    Write-Host ""
}

# -------------------------
# AUTO-FIX PROMPT
# -------------------------

if ($fixable -gt 0) {
    Write-Host "=== AUTO-FIX OPTIONS ===" -ForegroundColor Cyan
    Write-Host "$fixable issue(s) can be automatically fixed.`n" -ForegroundColor Green
    
    $response = Read-Host "Apply all auto-fixes? (Y/N)"
    
    if ($response -eq "Y" -or $response -eq "y") {
        Write-Host "`nApplying fixes...`n" -ForegroundColor Yellow
        
        foreach ($issue in $issues) {
            if ($issue.AutoFix) {
                Write-Host "[FIX] $($issue.Issue)..." -NoNewline
                try {
                    & $issue.AutoFix
                    Write-Host " SUCCESS" -ForegroundColor Green
                } catch {
                    Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        
        Write-Host "`n[COMPLETE] Auto-fix process finished." -ForegroundColor Cyan
        Write-Host "Please re-run this script to verify all issues are resolved." -ForegroundColor Gray
    } else {
        Write-Host "`nAuto-fix cancelled. Please manually resolve issues above." -ForegroundColor Yellow
    }
} else {
    Write-Host "No auto-fixes available. Please manually resolve issues above." -ForegroundColor Yellow
}

Write-Host "`nFor detailed troubleshooting, refer to the troubleshooting guide." -ForegroundColor Gray