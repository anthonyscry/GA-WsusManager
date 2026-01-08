<#
===============================================================================
Script: Repair-WsusContentPath.ps1
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

# Import shared modules
$modulePath = Join-Path $PSScriptRoot "Modules"
Import-Module (Join-Path $modulePath "WsusUtilities.ps1") -Force
Import-Module (Join-Path $modulePath "WsusPermissions.ps1") -Force
Import-Module (Join-Path $modulePath "WsusServices.ps1") -Force

function Invoke-SqlScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Instance,
        [Parameter(Mandatory = $true)][string]$Query
    )

    $result = sqlcmd -S $Instance -E -d SUSDB -b -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SQL query failed"
    }

    return $result.Trim()
}

$issuesFound = 0
$issuesFixed = 0

Write-Info "=========================================="
Write-Info "WSUS Content Path Validation Script"
Write-Info "=========================================="
Write-Info "Target Content Path: $ContentPath"
Write-Info "SQL Instance: $SqlInstance"
Write-Info "Fix Mode: $($FixIssues.IsPresent)"
Write-Info ""

# Check if running as administrator using module function
Test-AdminPrivileges -ExitOnFail $true | Out-Null

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
    $dbPath = Invoke-SqlScalar -Instance $SqlInstance -Query "SELECT LocalContentCacheLocation FROM tbConfigurationB;"
    
    if ($dbPath -eq $ContentPath) {
        Write-Success "  [OK] Database path is correct: $dbPath"
    } else {
        Write-Failure "  [FAIL] Database path is incorrect: $dbPath (should be $ContentPath)"
        $issuesFound++
        if ($FixIssues) {
            Write-Warning "  --> Updating database..."
            Invoke-SqlScalar -Instance $SqlInstance -Query "UPDATE tbConfigurationB SET LocalContentCacheLocation = '$ContentPath';" | Out-Null
            Write-Success "  [OK] Database path updated"
            $issuesFixed++
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

$permCheck = Test-WsusContentPermissions -ContentPath $ContentPath

if ($permCheck.AllCorrect) {
    Write-Success "  [OK] All permissions correct"
} else {
    Write-Failure "  [FAIL] Missing permissions:"
    $permCheck.Missing | ForEach-Object {
        Write-Failure "    - $_"
    }
    $issuesFound++

    if ($FixIssues) {
        Write-WsusWarning "  --> Fixing permissions..."
        if (Set-WsusContentPermissions -ContentPath $ContentPath) {
            $issuesFixed++
        }
    }
}

# ===========================
# 6. CHECK FILE RECORDS IN DATABASE
# ===========================
Write-Info "[6/6] Checking file records in database..."
try {
    # Check ActualState in tbFileOnServer
    $filesPresent = Invoke-SqlScalar -Instance $SqlInstance -Query "SELECT COUNT(*) FROM tbFileOnServer WHERE ActualState = 1;"
    $filesTotal = Invoke-SqlScalar -Instance $SqlInstance -Query "SELECT COUNT(*) FROM tbFileOnServer;"
    
    Write-Info "  Files marked as present: $filesPresent / $filesTotal"
    
    if ([int]$filesPresent -lt [int]$filesTotal) {
        Write-Warning "  [WARN] Not all files are marked as present in database"
        $issuesFound++
        if ($FixIssues) {
            Write-Warning "  --> Updating file status in database..."
            Invoke-SqlScalar -Instance $SqlInstance -Query "UPDATE tbFileOnServer SET ActualState = 1 WHERE DesiredState = 1 AND ActualState = 0;" | Out-Null
            Write-Success "  [OK] File status updated"
            $issuesFixed++
        }
    } else {
        Write-Success "  [OK] All files marked as present"
    }
    
    # Check download queue
    $queueCount = Invoke-SqlScalar -Instance $SqlInstance -Query "SELECT COUNT(*) FROM tbFileDownloadProgress;"
    if ([int]$queueCount -gt 0) {
        Write-Warning "  [WARN] $queueCount files in download queue"
        $issuesFound++
        if ($FixIssues) {
            Write-Warning "  --> Clearing download queue..."
            Invoke-SqlScalar -Instance $SqlInstance -Query "DELETE FROM tbFileDownloadProgress;" | Out-Null
            Write-Success "  [OK] Download queue cleared"
            $issuesFixed++
        }
    } else {
        Write-Success "  [OK] Download queue is empty"
    }
} catch {
    Write-Failure "  [FAIL] Error checking file records: $_"
}

# ===========================
# RESTART SERVICES IF FIXED
# ===========================
if ($FixIssues -and $issuesFixed -gt 0) {
    Write-Info ""
    Write-WsusWarning "Restarting WSUS service to apply changes..."
    if (Restart-WsusService -ServiceName "WSUSService" -Force) {
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
    } else {
        Write-Failure "[FAIL] Error restarting WSUS service"
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
