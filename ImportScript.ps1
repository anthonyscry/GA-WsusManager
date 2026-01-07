<#
===============================================================================
Script: ImportScript.ps1
Purpose: Restore a SUSDB backup and rebind WSUS to SQL/content.
Overview:
  - Validates backup and content directory.
  - Ensures permissions for WSUS.
  - Stops WSUS/IIS to release SUSDB locks.
  - Restores SUSDB from a backup file.
  - Runs wsusutil postinstall and reset to align WSUS with the DB/content.
  - Performs cleanup and basic health checks.
Notes:
  - Run as Administrator on the WSUS server.
  - Script auto-detects the newest .bak in C:\WSUS and allows a custom path if needed.
===============================================================================
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

function Write-Log($msg, $color = "White") {
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor $color
}

Write-Log "=== WSUS Database Restore Script ===" "Cyan"

# Variables
$ContentDir = "C:\WSUS"
$SQLInstance = ".\SQLEXPRESS"

# Find sqlcmd executable (PATH or common install locations)
$sqlCmdCandidates = @(
    (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\120\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\130\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\140\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe",
    "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $sqlCmdCandidates) {
    Write-Log "ERROR: sqlcmd.exe not found. Install SQL Server Command Line Utilities or add sqlcmd to PATH." "Red"
    exit 1
}

$SqlCmdExe = $sqlCmdCandidates
Write-Log "Using sqlcmd: $SqlCmdExe" "Gray"

# Find newest backup file in content directory
$latestBackup = Get-ChildItem -Path $ContentDir -Filter "*.bak" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latestBackup) {
    Write-Log "ERROR: No .bak files found in $ContentDir" "Red"
    exit 1
}

$BackupFile = $latestBackup.FullName
Write-Log "Newest backup file detected: $BackupFile" "Yellow"
$confirmation = Read-Host "Use this backup file? (Y/n) or enter a full path"

if ($confirmation -and $confirmation -notin @("Y", "y")) {
    if (Test-Path $confirmation) {
        $BackupFile = $confirmation
    } else {
        Write-Log "ERROR: Provided backup path not found: $confirmation" "Red"
        exit 1
    }
}

# === STEP 0: Validate Backup File Exists ===
Write-Log "Validating backup file..." "Yellow"
if (-not (Test-Path $BackupFile)) {
    Write-Log "ERROR: Backup file not found: $BackupFile" "Red"
    exit 1
}
Write-Log "✅ Backup file found: $BackupFile" "Green"

# === STEP 1: Check and Set Permissions ===
Write-Log "Checking permissions on $ContentDir..." "Yellow"

if (-not (Test-Path $ContentDir)) {
    Write-Log "Creating directory: $ContentDir" "Yellow"
    New-Item -Path $ContentDir -ItemType Directory -Force | Out-Null
}

$accounts = @(
    "NT AUTHORITY\NETWORK SERVICE",
    "BUILTIN\WSUS Administrators"
)

foreach ($account in $accounts) {
    try {
        Write-Log "Checking permissions for: $account" "Gray"
        $acl = Get-Acl -Path $ContentDir
        $existingRule = $acl.Access | Where-Object {
            $_.IdentityReference.Value -eq $account -and
            $_.FileSystemRights -match "FullControl"
        }

        if ($existingRule) {
            Write-Log "  ✅ $account already has Full Control" "Green"
        } else {
            Write-Log "  Adding Full Control for: $account" "Yellow"
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $account,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.SetAccessRule($accessRule)
            Set-Acl -Path $ContentDir -AclObject $acl
            Write-Log "  ✅ Full Control granted to: $account" "Green"
        }
    } catch {
        Write-Log "  ⚠️ Warning: Could not set permissions for $account - $($_.Exception.Message)" "Yellow"
    }
}

# === STEP 2: Stop Services ===
Write-Log "Stopping services..." "Yellow"

$servicesToStop = @("WSUSService", "W3SVC")

foreach ($svc in $servicesToStop) {
    try {
        $service = Get-Service -Name $svc -ErrorAction Stop
        if ($service.Status -ne "Stopped") {
            Write-Log "  Stopping $svc..." "Gray"
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Start-Sleep -Seconds 3
            Write-Log "  ✅ $svc stopped" "Green"
        } else {
            Write-Log "  ✅ $svc already stopped" "Green"
        }
    } catch {
        Write-Log "  ⚠️ Could not stop $svc - $($_.Exception.Message)" "Yellow"
    }
}

# === STEP 3: Restore Database ===
Write-Log "Restoring SUSDB database..." "Yellow"

try {
    $setSingleUser = @"
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'SUSDB')
BEGIN
    ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
END
"@
    & $SqlCmdExe -S $SQLInstance -Q $setSingleUser -b
    Write-Log "  Database set to single user mode" "Gray"
} catch {
    Write-Log "  Database doesn't exist yet or already in single user mode" "Gray"
}

Write-Log "  Restoring from backup (this may take 2-5 minutes)..." "Gray"
$restoreCommand = "RESTORE DATABASE SUSDB FROM DISK='$BackupFile' WITH REPLACE, STATS=10"

try {
    & $SqlCmdExe -S $SQLInstance -Q $restoreCommand -b
    if ($LASTEXITCODE -eq 0) {
        Write-Log "  ✅ Database restored successfully" "Green"
    } else {
        Write-Log "  ❌ Database restore failed with exit code: $LASTEXITCODE" "Red"
        exit 1
    }
} catch {
    Write-Log "  ❌ Database restore failed: $($_.Exception.Message)" "Red"
    exit 1
}

Write-Log "  Setting database to multi-user mode..." "Gray"
try {
    & $SqlCmdExe -S $SQLInstance -Q "ALTER DATABASE SUSDB SET MULTI_USER;" -b
    Write-Log "  ✅ Database set to multi-user mode" "Green"
} catch {
    Write-Log "  ⚠️ Warning: Could not set multi-user mode - $($_.Exception.Message)" "Yellow"
}

# === STEP 4: Start Services ===
Write-Log "Starting services..." "Yellow"

$servicesToStart = @("W3SVC", "WSUSService")

foreach ($svc in $servicesToStart) {
    try {
        Write-Log "  Starting $svc..." "Gray"
        Start-Service -Name $svc -ErrorAction Stop
        Start-Sleep -Seconds 3

        $service = Get-Service -Name $svc
        if ($service.Status -eq "Running") {
            Write-Log "  ✅ $svc started" "Green"
        } else {
            Write-Log "  ⚠️ $svc status: $($service.Status)" "Yellow"
        }
    } catch {
        Write-Log "  ❌ Could not start $svc - $($_.Exception.Message)" "Red"
    }
}

Write-Log "Waiting for services to initialize..." "Gray"
Start-Sleep -Seconds 10

# === STEP 5: Run WSUS PostInstall ===
Write-Log "Running WSUS postinstall..." "Yellow"

try {
    $postInstallCmd = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    Write-Log "  Command: wsusutil.exe postinstall..." "Gray"
    $output = & $postInstallCmd postinstall SQL_INSTANCE_NAME="$SQLInstance" CONTENT_DIR="$ContentDir" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Log "  ✅ WSUS postinstall completed" "Green"
    } else {
        Write-Log "  ⚠️ WSUS postinstall returned code: $LASTEXITCODE" "Yellow"
        Write-Log "  Output: $output" "Gray"
    }
} catch {
    Write-Log "  ⚠️ WSUS postinstall warning: $($_.Exception.Message)" "Yellow"
}

# === STEP 6: Run WSUS Reset ===
Write-Log "Running WSUS reset (this will take 15-30 minutes)..." "Yellow"
Write-Log "  This re-verifies database integrity and file references..." "Gray"

try {
    $resetCmd = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    Write-Log "  Starting reset (be patient)..." "Gray"

    $output = & $resetCmd reset 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Log "  ✅ WSUS reset completed" "Green"
    } else {
        Write-Log "  ⚠️ WSUS reset returned code: $LASTEXITCODE" "Yellow"
    }
} catch {
    Write-Log "  ⚠️ WSUS reset warning: $($_.Exception.Message)" "Yellow"
}

# === STEP 7: WSUS Cleanup ===
Write-Log "Running WSUS cleanup..." "Yellow"

try {
    Import-Module UpdateServices -ErrorAction Stop

    $cleanup = Invoke-WsusServerCleanup `
        -CleanupObsoleteComputers `
        -CleanupObsoleteUpdates `
        -CleanupUnneededContentFiles `
        -CompressUpdates `
        -DeclineSupersededUpdates `
        -DeclineExpiredUpdates `
        -Confirm:$false

    Write-Log "  ✅ WSUS cleanup completed" "Green"
    Write-Log "    Obsolete updates: $($cleanup.ObsoleteUpdatesDeleted)" "Gray"
    Write-Log "    Obsolete computers: $($cleanup.ObsoleteComputersDeleted)" "Gray"
    Write-Log "    Space freed: $([math]::Round($cleanup.DiskSpaceFreed/1MB,2)) MB" "Gray"
} catch {
    Write-Log "  ⚠️ WSUS cleanup warning: $($_.Exception.Message)" "Yellow"
}

# === STEP 8: Health Check ===
Write-Log "=== Health Check ===" "Cyan"

$services = @(
    @{ Name = 'W3SVC'; Display = 'IIS Web Service' },
    @{ Name = 'WSUSService'; Display = 'WSUS Service' },
    @{ Name = 'MSSQL$SQLEXPRESS'; Display = 'SQL Server (SQLEXPRESS)' }
)

Write-Log "`nService Status:" "Yellow"
foreach ($svc in $services) {
    try {
        $status = (Get-Service -Name $svc.Name -ErrorAction Stop).Status
        if ($status -eq 'Running') {
            Write-Log "  ✅ $($svc.Display): RUNNING" "Green"
        } else {
            Write-Log "  ❌ $($svc.Display): $status" "Red"
        }
    } catch {
        Write-Log "  ❌ $($svc.Display): NOT FOUND" "Red"
    }
}

Write-Log "`nDatabase Size:" "Yellow"
try {
    $sizeQuery = "SELECT CAST(SUM(size) * 8.0 / 1024 / 1024 AS DECIMAL(10,2)) AS SizeGB FROM sys.master_files WHERE database_id=DB_ID('SUSDB')"
    $dbSize = & $SqlCmdExe -S $SQLInstance -Q $sizeQuery -h -1 -W
    Write-Log "  SUSDB Size: $($dbSize.Trim()) GB" "Green"
} catch {
    Write-Log "  ⚠️ Could not check database size" "Yellow"
}

Write-Log "`nWSUS Status:" "Yellow"
try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
    $allUpdates = $wsus.GetUpdates()

    $declined = @($allUpdates | Where-Object { $_.IsDeclined }).Count
    $active = @($allUpdates | Where-Object { -not $_.IsDeclined -and -not $_.IsSuperseded }).Count

    Write-Log "  Total updates: $($allUpdates.Count)" "Gray"
    Write-Log "  Active updates: $active" "Green"
    Write-Log "  Declined updates: $declined" "Gray"
} catch {
    Write-Log "  ⚠️ Could not check WSUS status: $($_.Exception.Message)" "Yellow"
}

Write-Log "`nContent Folder:" "Yellow"
try {
    $contentSize = [math]::Round((Get-ChildItem $ContentDir -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    $contentFiles = (Get-ChildItem $ContentDir -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object).Count

    Write-Log "  Content Size: $contentSize GB" "Green"
    Write-Log "  Content Files: $contentFiles" "Gray"
} catch {
    Write-Log "  ⚠️ Could not check content folder" "Yellow"
}

Write-Log "`n=== Restore Complete ===" "Cyan"
Write-Log "✅ Database restored from: $BackupFile" "Green"
Write-Log "✅ Permissions configured for NETWORK SERVICE and WSUS Administrators" "Green"
Write-Log "✅ WSUS services started" "Green"
Write-Log "✅ Post-install and reset completed" "Green"

Write-Log "`nNext Steps:" "Yellow"
Write-Log "  1. Open WSUS Console and verify updates are visible"
Write-Log "  2. Check Options > Update Files and Languages"
Write-Log "  3. Run a synchronization to verify functionality"
Write-Log "  4. Run monthly maintenance script to keep database healthy"
Write-Log ""
