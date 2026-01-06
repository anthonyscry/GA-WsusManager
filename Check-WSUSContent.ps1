<#
===============================================================================
Script: Check-WSUSContent.ps1
Purpose: Validate and optionally fix WSUS content path configuration.
Overview:
  - Verifies content path in SUSDB, registry, and IIS.
  - Ensures permissions for WSUS and IIS identities.
  - Optionally fixes mismatches and clears download queue.
Notes:
  - Run as Administrator on the WSUS server.
  - Default content path is C:\WSUS for reliable DB file registration.
===============================================================================
.PARAMETER ContentPath
    The correct content path (default: C:\WSUS)
.PARAMETER SqlInstance
    SQL Server instance name (default: .\SQLEXPRESS)
.PARAMETER FixIssues
    If specified, automatically fixes any issues found
#>

param(
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS",
    [switch]$FixIssues
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success { Write-ColorOutput Green $args }
function Write-Failure { Write-ColorOutput Red $args }
function Write-Warning { Write-ColorOutput Yellow $args }
function Write-Info { Write-ColorOutput Cyan $args }

$issuesFound = 0
$issuesFixed = 0

Write-Info "=========================================="
Write-Info "WSUS Content Path Validation Script"
Write-Info "=========================================="
Write-Info "Target Content Path: $ContentPath"
Write-Info "SQL Instance: $SqlInstance"
Write-Info "Fix Mode: $($FixIssues.IsPresent)"
Write-Info ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Failure "ERROR: This script must be run as Administrator!"
    exit 1
}

# ===========================
# 1. CHECK CONTENT PATH EXISTS
# ===========================
Write-Info "[1/6] Checking if content path exists..."
if (Test-Path $ContentPath) {
    Write-Success "  [OK] Content path exists: $ContentPath"
} else {
    Write-Failure "  [FAIL] Content path does not exist: $ContentPath"
    if ($FixIssues) {
        Write-Warning "  --> Creating directory..."
        New-Item -Path $ContentPath -ItemType Directory -Force | Out-Null
        Write-Success "  [OK] Directory created"
        $issuesFixed++
    }
    $issuesFound++
}

# ===========================
# 2. CHECK DATABASE CONFIGURATION
# ===========================
Write-Info "[2/6] Checking database configuration..."
try {
    $dbPath = sqlcmd -S $SqlInstance -E -Q "USE SUSDB; SELECT LocalContentCacheLocation FROM tbConfigurationB;" -h -1 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SQL query failed"
    }
    $dbPath = $dbPath.Trim()
    
    if ($dbPath -eq $ContentPath) {
        Write-Success "  [OK] Database path is correct: $dbPath"
    } else {
        Write-Failure "  [FAIL] Database path is incorrect: $dbPath (should be $ContentPath)"
        $issuesFound++
        if ($FixIssues) {
            Write-Warning "  --> Updating database..."
            sqlcmd -S $SqlInstance -E -Q "USE SUSDB; UPDATE tbConfigurationB SET LocalContentCacheLocation = '$ContentPath';" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  [OK] Database path updated"
                $issuesFixed++
            } else {
                Write-Failure "  [FAIL] Failed to update database"
            }
        }
    }
} catch {
    Write-Failure "  [FAIL] Error checking database: $_"
    $issuesFound++
}

# ===========================
# 3. CHECK REGISTRY
# ===========================
Write-Info "[3/6] Checking registry configuration..."
try {
    $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" -Name ContentDir -ErrorAction Stop
    if ($regPath.ContentDir -eq $ContentPath) {
        Write-Success "  [OK] Registry path is correct: $($regPath.ContentDir)"
    } else {
        Write-Failure "  [FAIL] Registry path is incorrect: $($regPath.ContentDir) (should be $ContentPath)"
        $issuesFound++
        if ($FixIssues) {
            Write-Warning "  --> Updating registry..."
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" -Name ContentDir -Value $ContentPath
            Write-Success "  [OK] Registry path updated"
            $issuesFixed++
        }
    }
} catch {
    Write-Failure "  [FAIL] Error checking registry: $_"
    $issuesFound++
}

# ===========================
# 4. CHECK IIS VIRTUAL DIRECTORY
# ===========================
Write-Info "[4/6] Checking IIS virtual directory configuration..."
try {
    Import-Module WebAdministration -ErrorAction Stop
    $iisPath = Get-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='WSUS Administration']/application[@path='/']/virtualDirectory[@path='/Content']" -Name physicalPath -ErrorAction Stop
    
    if ($iisPath.Value -eq $ContentPath) {
        Write-Success "  [OK] IIS virtual directory is correct: $($iisPath.Value)"
    } else {
        Write-Failure "  [FAIL] IIS virtual directory is incorrect: $($iisPath.Value) (should be $ContentPath)"
        $issuesFound++
        if ($FixIssues) {
            Write-Warning "  --> Updating IIS virtual directory..."
            Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/site[@name='WSUS Administration']/application[@path='/']/virtualDirectory[@path='/Content']" -Name physicalPath -Value $ContentPath
            Write-Success "  [OK] IIS virtual directory updated"
            $issuesFixed++
        }
    }
} catch {
    Write-Failure "  [FAIL] Error checking IIS: $_"
    $issuesFound++
}

# ===========================
# 5. CHECK AND FIX PERMISSIONS
# ===========================
Write-Info "[5/6] Checking permissions on content directory..."
$permissionsNeeded = @(
    @{Account = "NETWORK SERVICE"; Rights = "FullControl"},
    @{Account = "NT AUTHORITY\LOCAL SERVICE"; Rights = "FullControl"},
    @{Account = "IIS_IUSRS"; Rights = "Read"},
    @{Account = "IIS APPPOOL\WsusPool"; Rights = "FullControl"}
)

$permissionsCorrect = $true
try {
    $acl = Get-Acl $ContentPath
    
    foreach ($perm in $permissionsNeeded) {
        $account = $perm.Account
        $hasPermission = $false
        
        foreach ($access in $acl.Access) {
            if ($access.IdentityReference -like "*$account*") {
                $hasPermission = $true
                break
            }
        }
        
        if ($hasPermission) {
            Write-Success "  [OK] $account has permissions"
        } else {
            Write-Failure "  [FAIL] $account is missing permissions"
            $permissionsCorrect = $false
            $issuesFound++
        }
    }
    
    if (-not $permissionsCorrect -and $FixIssues) {
        Write-Warning "  --> Fixing permissions..."
        
        # Grant permissions
        icacls "$ContentPath" /grant "NETWORK SERVICE:(OI)(CI)F" /T /Q | Out-Null
        icacls "$ContentPath" /grant "NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F" /T /Q | Out-Null
        icacls "$ContentPath" /grant "IIS_IUSRS:(OI)(CI)R" /T /Q | Out-Null
        icacls "$ContentPath" /grant "IIS APPPOOL\WsusPool:(OI)(CI)F" /T /Q | Out-Null
        
        Write-Success "  [OK] Permissions updated"
        $issuesFixed++
    }
} catch {
    Write-Failure "  [FAIL] Error checking permissions: $_"
    $issuesFound++
}

# ===========================
# 6. CHECK FILE RECORDS IN DATABASE
# ===========================
Write-Info "[6/6] Checking file records in database..."
try {
    # Check ActualState in tbFileOnServer
    $filesPresent = sqlcmd -S $SqlInstance -E -Q "USE SUSDB; SELECT COUNT(*) FROM tbFileOnServer WHERE ActualState = 1;" -h -1 2>&1
    $filesTotal = sqlcmd -S $SqlInstance -E -Q "USE SUSDB; SELECT COUNT(*) FROM tbFileOnServer;" -h -1 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $filesPresent = $filesPresent.Trim()
        $filesTotal = $filesTotal.Trim()
        
        Write-Info "  Files marked as present: $filesPresent / $filesTotal"
        
        if ([int]$filesPresent -lt [int]$filesTotal) {
            Write-Warning "  [WARN] Not all files are marked as present in database"
            $issuesFound++
            if ($FixIssues) {
                Write-Warning "  --> Updating file status in database..."
                sqlcmd -S $SqlInstance -E -Q "USE SUSDB; UPDATE tbFileOnServer SET ActualState = 1 WHERE DesiredState = 1 AND ActualState = 0;" | Out-Null
                Write-Success "  [OK] File status updated"
                $issuesFixed++
            }
        } else {
            Write-Success "  [OK] All files marked as present"
        }
    }
    
    # Check download queue
    $queueCount = sqlcmd -S $SqlInstance -E -Q "USE SUSDB; SELECT COUNT(*) FROM tbFileDownloadProgress;" -h -1 2>&1
    if ($LASTEXITCODE -eq 0) {
        $queueCount = $queueCount.Trim()
        if ([int]$queueCount -gt 0) {
            Write-Warning "  [WARN] $queueCount files in download queue"
            $issuesFound++
            if ($FixIssues) {
                Write-Warning "  --> Clearing download queue..."
                sqlcmd -S $SqlInstance -E -Q "USE SUSDB; DELETE FROM tbFileDownloadProgress;" | Out-Null
                Write-Success "  [OK] Download queue cleared"
                $issuesFixed++
            }
        } else {
            Write-Success "  [OK] Download queue is empty"
        }
    }
} catch {
    Write-Failure "  [FAIL] Error checking file records: $_"
}

# ===========================
# RESTART SERVICES IF FIXED
# ===========================
if ($FixIssues -and $issuesFixed -gt 0) {
    Write-Info ""
    Write-Warning "Restarting WSUS service to apply changes..."
    try {
        Restart-Service WsusService -Force -ErrorAction Stop
        Write-Success "[OK] WSUS service restarted successfully"
        
        # Wait and check event log
        Start-Sleep -Seconds 5
        Write-Info "Checking WSUS event log..."
        $recentEvents = Get-EventLog -LogName Application -Source "Windows Server Update Services" -Newest 2 -ErrorAction SilentlyContinue | Select-Object EntryType, Message
        
        foreach ($event in $recentEvents) {
            if ($event.Message -like "*content directory is accessible*") {
                Write-Success "[OK] WSUS reports content directory is accessible"
            } elseif ($event.Message -like "*not accessible*") {
                Write-Failure "[FAIL] WSUS reports content directory is NOT accessible"
            }
        }
    } catch {
        Write-Failure "[FAIL] Error restarting WSUS service: $_"
    }
}

# ===========================
# SUMMARY
# ===========================
Write-Info ""
Write-Info "=========================================="
Write-Info "SUMMARY"
Write-Info "=========================================="
Write-Info "Issues Found: $issuesFound"
if ($FixIssues) {
    Write-Info "Issues Fixed: $issuesFixed"
}

if ($issuesFound -eq 0) {
    Write-Success "[OK] All checks passed! WSUS is configured correctly."
} elseif ($FixIssues) {
    if ($issuesFixed -eq $issuesFound) {
        Write-Success "[OK] All issues have been fixed!"
    } else {
        Write-Warning "[WARN] Some issues remain. Manual intervention may be required."
    }
} else {
    Write-Warning "[WARN] Issues found. Run with -FixIssues to automatically fix them."
}

Write-Info ""
