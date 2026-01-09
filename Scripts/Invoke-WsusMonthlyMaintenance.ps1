<#
===============================================================================
Script: Invoke-WsusMonthlyMaintenance.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 3.0.1
Date: 2026-01-09
===============================================================================
Purpose: Monthly WSUS maintenance automation.
Overview:
  - Synchronizes WSUS, monitors download progress, and applies approvals.
  - Runs WSUS cleanup tasks and SUSDB index/stat maintenance.
  - Optionally runs an aggressive cleanup stage before the backup.
  - Differential export to network share with year/month/day structure.
Notes:
  - Run as Administrator on the WSUS server.
  - Use -Unattended for scheduled tasks (no prompts, uses defaults).
  - Use -Profile to select preset configurations (Quick, Full, SyncOnly).
  - Use -Operations to run specific phases only.
  - Requires SQL Express instance .\SQLEXPRESS and WSUS on port 8530.
===============================================================================
#>

[CmdletBinding()]
param(
    # Run in unattended mode (no prompts, uses all defaults) - ideal for scheduled tasks
    [switch]$Unattended,

    # Preset configuration profiles
    [ValidateSet("Quick", "Full", "SyncOnly")]
    [string]$Profile,

    # Specific operations to run (default: all)
    [ValidateSet("Sync", "Cleanup", "UltimateCleanup", "Backup", "Export", "All")]
    [string[]]$Operations = @("All"),

    # Skip the heavy "ultimate cleanup" stage before the backup if needed.
    [switch]$SkipUltimateCleanup,

    # Root path for exports (e.g., "\\lab-hyperv\d\WSUS-Exports")
    # Exports will be organized as: ExportPath\Year\Month\Day
    [string]$ExportPath = "\\lab-hyperv\d\WSUS-Exports",

    # Number of days to include in differential export (files modified within this many days)
    # If not specified via command line, user will be prompted (default: 30)
    [int]$ExportDays = 0,

    # Skip the export step entirely
    [switch]$SkipExport
)

# Import shared modules
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
Import-Module (Join-Path $modulePath "WsusUtilities.psm1") -Force
Import-Module (Join-Path $modulePath "WsusDatabase.psm1") -Force
Import-Module (Join-Path $modulePath "WsusServices.psm1") -Force

# Suppress prompts
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'

# Force output redirection to prevent pauses
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# === SCRIPT VERSION ===
$ScriptVersion = "3.0.1"

# === HELPER FUNCTIONS ===

# Colored status output
function Write-Status {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Header", "Phase")]
        [string]$Type = "Info"
    )
    $colors = @{
        Info    = "Cyan"
        Success = "Green"
        Warning = "Yellow"
        Error   = "Red"
        Header  = "Magenta"
        Phase   = "White"
    }
    $prefixes = @{
        Info    = "[i]"
        Success = "[+]"
        Warning = "[!]"
        Error   = "[X]"
        Header  = "==>"
        Phase   = ">>>"
    }
    $prefix = $prefixes[$Type]
    $color = $colors[$Type]
    Write-Host "$prefix " -ForegroundColor $color -NoNewline
    Write-Host $Message
}

# Pre-flight validation
function Test-Prerequisites {
    param(
        [string]$ExportPath,
        [bool]$SkipExport
    )

    $results = @{
        Success = $true
        Errors = @()
        Warnings = @()
    }

    Write-Status "Running pre-flight checks..." -Type Header

    # Check 1: SQL Server service exists
    Write-Host "  Checking SQL Server..." -NoNewline
    if (Test-ServiceExists -ServiceName "MSSQL`$SQLEXPRESS") {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAILED" -ForegroundColor Red
        $results.Errors += "SQL Server Express service not found"
        $results.Success = $false
    }

    # Check 2: WSUS service exists
    Write-Host "  Checking WSUS Service..." -NoNewline
    if (Test-ServiceExists -ServiceName "WSUSService") {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAILED" -ForegroundColor Red
        $results.Errors += "WSUS Service not found"
        $results.Success = $false
    }

    # Check 3: Local disk space (WSUS folder)
    Write-Host "  Checking disk space (C:\WSUS)..." -NoNewline
    $wsusDrive = (Get-Item "C:\WSUS" -ErrorAction SilentlyContinue).PSDrive
    if ($wsusDrive) {
        $freeGB = [math]::Round($wsusDrive.Free / 1GB, 2)
        if ($freeGB -ge 5) {
            Write-Host " OK ($freeGB GB free)" -ForegroundColor Green
        } else {
            Write-Host " LOW ($freeGB GB free)" -ForegroundColor Yellow
            $results.Warnings += "Low disk space on WSUS drive: $freeGB GB"
        }
    } else {
        Write-Host " SKIP (path not found)" -ForegroundColor Yellow
    }

    # Check 4: Export path accessibility (if not skipping export)
    if (-not $SkipExport -and $ExportPath) {
        Write-Host "  Checking export path..." -NoNewline
        $exportAccessible = Test-ExportPathAccess -ExportPath $ExportPath
        if ($exportAccessible) {
            Write-Host " OK" -ForegroundColor Green
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $results.Warnings += "Cannot access export path: $ExportPath"
        }
    }

    # Check 5: WSUS connection test
    Write-Host "  Checking WSUS connection..." -NoNewline
    try {
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $testWsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
        if ($testWsus) {
            Write-Host " OK" -ForegroundColor Green
        }
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        $results.Errors += "Cannot connect to WSUS: $($_.Exception.Message)"
        $results.Success = $false
    }

    Write-Host ""
    return $results
}

# Test export path with write access
function Test-ExportPathAccess {
    param([string]$ExportPath)

    try {
        # First check if path exists or parent exists
        if (Test-Path $ExportPath) {
            $testFile = Join-Path $ExportPath ".wsus_access_test_$(Get-Random).tmp"
            New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop | Out-Null
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            return $true
        } else {
            # Try to create the path
            New-Item -Path $ExportPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            return $true
        }
    } catch {
        return $false
    }
}

# Interactive menu
function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================================+" -ForegroundColor Cyan
    Write-Host "  |         WSUS Monthly Maintenance v$ScriptVersion                |" -ForegroundColor Cyan
    Write-Host "  +==========================================================+" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |  [1] Full Maintenance                                    |" -ForegroundColor Cyan
    Write-Host "  |      Sync -> Cleanup -> Ultimate Cleanup -> Backup -> Export |" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |  [2] Quick Maintenance                                   |" -ForegroundColor Cyan
    Write-Host "  |      Sync -> Cleanup -> Backup (skip heavy cleanup)      |" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |  [3] Sync Only                                           |" -ForegroundColor Cyan
    Write-Host "  |      Synchronize and approve updates only                |" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |  [4] Backup & Export Only                                |" -ForegroundColor Cyan
    Write-Host "  |      Skip sync/cleanup, just backup and export           |" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |  [5] Database Maintenance Only                           |" -ForegroundColor Cyan
    Write-Host "  |      Cleanup + index optimization (no sync/backup)       |" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  |  [Q] Quit                                                |" -ForegroundColor Cyan
    Write-Host "  |                                                          |" -ForegroundColor Cyan
    Write-Host "  +==========================================================+" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "  Select option"
    return $choice
}

# Apply profile settings
function Set-ProfileSettings {
    param([string]$ProfileName)

    $settings = @{
        Operations = @("All")
        SkipUltimateCleanup = $false
        SkipExport = $false
        ExportDays = 30
    }

    switch ($ProfileName) {
        "Quick" {
            $settings.SkipUltimateCleanup = $true
            $settings.ExportDays = 7
        }
        "Full" {
            $settings.SkipUltimateCleanup = $false
            $settings.ExportDays = 30
        }
        "SyncOnly" {
            $settings.Operations = @("Sync")
            $settings.SkipExport = $true
        }
    }

    return $settings
}

# Check if operation should run
function Test-ShouldRunOperation {
    param(
        [string]$Operation,
        [string[]]$SelectedOperations
    )

    if ($SelectedOperations -contains "All") { return $true }
    return $SelectedOperations -contains $Operation
}

# Show operation summary before starting
function Show-OperationSummary {
    param(
        [string[]]$Operations,
        [bool]$SkipUltimateCleanup,
        [bool]$SkipExport,
        [string]$ExportPath,
        [int]$ExportDays,
        [bool]$Unattended
    )

    Write-Host ""
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor White
    Write-Host "  |  WSUS Monthly Maintenance v$ScriptVersion                         |" -ForegroundColor White
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor White
    Write-Host ""

    # Build operation flow
    $flow = @()
    if (Test-ShouldRunOperation "Sync" $Operations) { $flow += "Sync" }
    if (Test-ShouldRunOperation "Cleanup" $Operations) { $flow += "Cleanup" }
    if ((Test-ShouldRunOperation "UltimateCleanup" $Operations) -and -not $SkipUltimateCleanup) {
        $flow += "UltimateCleanup"
    }
    if (Test-ShouldRunOperation "Backup" $Operations) { $flow += "Backup" }
    if ((Test-ShouldRunOperation "Export" $Operations) -and -not $SkipExport) { $flow += "Export" }

    Write-Host "  Operations:  " -NoNewline -ForegroundColor Gray
    Write-Host ($flow -join " -> ") -ForegroundColor Cyan

    if (-not $SkipExport -and $ExportPath) {
        $year = (Get-Date).ToString("yyyy")
        $month = (Get-Date).ToString("MMM")
        $day = (Get-Date).ToString("dd")
        $fullExportPath = [System.IO.Path]::Combine($ExportPath, $year, $month, $day)
        Write-Host "  Export Path: " -NoNewline -ForegroundColor Gray
        Write-Host $fullExportPath -ForegroundColor Cyan
        Write-Host "  Export Days: " -NoNewline -ForegroundColor Gray
        Write-Host "$ExportDays days" -ForegroundColor Cyan
    }

    Write-Host "  Mode:        " -NoNewline -ForegroundColor Gray
    if ($Unattended) {
        Write-Host "Unattended (no prompts)" -ForegroundColor Yellow
    } else {
        Write-Host "Interactive" -ForegroundColor Green
    }

    Write-Host ""

    if (-not $Unattended) {
        Write-Host "  Press Enter to continue or Ctrl+C to cancel..." -ForegroundColor DarkGray
        Read-Host | Out-Null
    }
}

# Initialize results tracking
$MaintenanceResults = @{
    Success = $true
    StartTime = Get-Date
    EndTime = $null
    Phases = @()
    DeclinedExpired = 0
    DeclinedSuperseded = 0
    DeclinedOld = 0
    Approved = 0
    DatabaseSize = 0
    BackupFile = ""
    BackupSize = 0
    ExportPath = ""
    ExportedFiles = 0
    ExportSize = 0
    Warnings = @()
    Errors = @()
}

# === INTERACTIVE MENU MODE ===
# Show menu if no profile/operations specified and not unattended
if (-not $Unattended -and -not $Profile -and ($Operations.Count -eq 1 -and $Operations[0] -eq "All")) {
    $menuChoice = Show-MainMenu

    switch ($menuChoice) {
        "1" { $Profile = "Full" }
        "2" { $Profile = "Quick" }
        "3" { $Profile = "SyncOnly" }
        "4" {
            $Operations = @("Backup", "Export")
        }
        "5" {
            $Operations = @("Cleanup", "UltimateCleanup")
            $SkipExport = $true
        }
        "Q" { exit 0 }
        "q" { exit 0 }
        default { $Profile = "Full" }
    }
}

# === APPLY PROFILE SETTINGS ===
if ($Profile) {
    $profileSettings = Set-ProfileSettings -ProfileName $Profile
    if (-not $PSBoundParameters.ContainsKey('SkipUltimateCleanup')) {
        $SkipUltimateCleanup = $profileSettings.SkipUltimateCleanup
    }
    if (-not $PSBoundParameters.ContainsKey('SkipExport')) {
        $SkipExport = $profileSettings.SkipExport
    }
    if ($ExportDays -eq 0) {
        $ExportDays = $profileSettings.ExportDays
    }
    if ($profileSettings.Operations[0] -ne "All") {
        $Operations = $profileSettings.Operations
    }
}

# Apply unattended defaults
if ($Unattended) {
    if ($ExportDays -eq 0) { $ExportDays = 30 }
}

# Setup logging using module function
$logFile = Start-WsusLogging -ScriptName "WsusMaintenance" -UseTimestamp $true

Write-Log "Starting WSUS monthly maintenance v$ScriptVersion"

# === SHOW OPERATION SUMMARY ===
Show-OperationSummary -Operations $Operations -SkipUltimateCleanup $SkipUltimateCleanup `
    -SkipExport $SkipExport -ExportPath $ExportPath -ExportDays $ExportDays -Unattended $Unattended

# === PRE-FLIGHT CHECKS ===
$preflightResults = Test-Prerequisites -ExportPath $ExportPath -SkipExport $SkipExport

if (-not $preflightResults.Success) {
    Write-Status "Pre-flight checks failed!" -Type Error
    foreach ($err in $preflightResults.Errors) {
        Write-Status "  $err" -Type Error
        $MaintenanceResults.Errors += $err
    }
    $MaintenanceResults.Success = $false
    Stop-WsusLogging
    exit 1
}

if ($preflightResults.Warnings.Count -gt 0) {
    foreach ($warn in $preflightResults.Warnings) {
        Write-Status $warn -Type Warning
        $MaintenanceResults.Warnings += $warn
    }
}

# === CONNECT TO WSUS ===
Write-Status "Connecting to WSUS..." -Type Phase
Write-Log "Connecting to WSUS..."

# Start services using module functions
Start-SqlServerExpress | Out-Null
Start-WsusServer | Out-Null

try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
    Write-Log "WSUS connection successful"
    Write-Status "WSUS connection successful" -Type Success

    Start-Sleep -Seconds 2
    $subscription = $wsus.GetSubscription()
    Write-Log "Subscription object retrieved"

} catch {
    Write-Status "Failed to connect: $($_.Exception.Message)" -Type Error
    $MaintenanceResults.Errors += "WSUS connection failed: $($_.Exception.Message)"
    $MaintenanceResults.Success = $false
    Stop-WsusLogging
    exit 1
}

# === SYNCHRONIZE ===
if (Test-ShouldRunOperation "Sync" $Operations) {
    Write-Status "Starting synchronization..." -Type Phase
    Write-Log "Starting synchronization..."
    $syncStart = Get-Date
    $syncPhase = @{ Name = "Synchronization"; Status = "In Progress"; Duration = "" }

    try {
        $lastSync = $subscription.GetLastSynchronizationInfo()
        if ($lastSync) {
            Write-Log "Last sync: $($lastSync.StartTime) | Result: $($lastSync.Result) | New: $($lastSync.NewUpdates)"
        }

        $subscription.StartSynchronization()
        Write-Log "Sync triggered, waiting for it to start..."
        Start-Sleep -Seconds 15

        $syncIterations = 0
        $maxIterations = 120

        do {
            Start-Sleep -Seconds 30
            $syncStatus = $subscription.GetSynchronizationStatus()
            $syncProgress = $subscription.GetSynchronizationProgress()

            if ($syncStatus -eq "Running") {
                Write-Log "Syncing: $($syncProgress.Phase) | Items: $($syncProgress.ProcessedItems)/$($syncProgress.TotalItems)"
                $syncIterations++
            } elseif ($syncStatus -eq "NotProcessing") {
                Write-Log "Sync completed or not running"
                break
            } else {
                Write-Log "Sync status: $syncStatus"
                $syncIterations++
            }

            if ($syncIterations -ge $maxIterations) {
                Write-Warning "Sync timeout after 60 minutes"
                break
            }

        } while ($syncStatus -eq "Running" -or $syncIterations -lt 5)

        Start-Sleep -Seconds 5

        $finalSync = $subscription.GetLastSynchronizationInfo()
        if ($finalSync) {
            Write-Log "Sync complete: Result=$($finalSync.Result) | New=$($finalSync.NewUpdates) | Revised=$($finalSync.RevisedUpdates)"

            if ($finalSync.Result -ne "Succeeded") {
                Write-Warning "Sync result: $($finalSync.Result)"
                $MaintenanceResults.Warnings += "Sync result: $($finalSync.Result)"
                if ($finalSync.Error) {
                    Write-Error "Sync error: $($finalSync.Error.Message)"
                }
            }
        } else {
            Write-Warning "Could not retrieve final sync info"
        }

        $syncDuration = [math]::Round(((Get-Date) - $syncStart).TotalMinutes, 1)
        $syncPhase.Status = "Completed"
        $syncPhase.Duration = "$syncDuration min"
        Write-Status "Synchronization completed: $syncDuration minutes" -Type Success
    } catch {
        Write-Status "Sync failed: $($_.Exception.Message)" -Type Error
        $MaintenanceResults.Errors += "Sync failed: $($_.Exception.Message)"
        $syncPhase.Status = "Failed"
    }
    $MaintenanceResults.Phases += $syncPhase
} else {
    Write-Status "Skipping synchronization" -Type Info
    $MaintenanceResults.Phases += @{ Name = "Synchronization"; Status = "Skipped"; Duration = "" }
}

# === CONFIGURATION CHECK ===
Write-Log "Checking configuration..."

$enabledProducts = $subscription.GetUpdateCategories() | Where-Object { $_.Type -eq 'Product' }
Write-Log "Enabled products: $($enabledProducts.Count)"

if ($enabledProducts.Count -eq 0) {
    Write-Warning "No products enabled! Configure in WSUS Console."
}

Write-Log "Note: Verify classifications are enabled in WSUS Console -> Options -> Products and Classifications"

# === MONITOR DOWNLOADS ===
Write-Log "Monitoring downloads..."
$downloadIterations = 0
do {
    $progress = $wsus.GetContentDownloadProgress()
    if ($progress.TotalFileCount -gt 0) {
        $pct = [math]::Round(($progress.DownloadedFileCount / $progress.TotalFileCount) * 100, 1)
        Write-Log "Downloaded: $($progress.DownloadedFileCount)/$($progress.TotalFileCount) - $($pct) percent"
        if ($progress.DownloadedFileCount -ge $progress.TotalFileCount) { break }
    } else {
        Write-Log "No downloads queued"
        break
    }
    Start-Sleep -Seconds 30
    $downloadIterations++
} while ($downloadIterations -lt 60)

# === DECLINE UPDATES (BASED ON MICROSOFT RELEASE DATE) ===
Write-Log "Fetching updates..."
$allUpdates = @()

try {
    Write-Log "Calling GetUpdates - this may take several minutes..."
    $getUpdatesStart = Get-Date
    
    $updateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $allUpdates = $wsus.GetUpdates($updateScope)
    
    $getUpdatesDuration = [math]::Round(((Get-Date) - $getUpdatesStart).TotalSeconds, 1)
    Write-Log "GetUpdates completed in $getUpdatesDuration seconds"
    Write-Log "Total updates: $($allUpdates.Count)"
    
} catch [System.Net.WebException] {
    Write-Warning "GetUpdates timed out after 180 seconds"
    Write-Warning "This indicates SUSDB needs optimization. Running cleanup first..."
    $allUpdates = @()
} catch {
    Write-Warning "Failed to fetch updates: $($_.Exception.Message)"
    $allUpdates = @()
}

# Initialize counters
$expiredCount = 0
$supersededCount = 0
$oldCount = 0
$approvedCount = 0

if ($allUpdates.Count -gt 0) {
    Write-Log "Declining updates based on Microsoft RELEASE DATE..."
    
    $expired = @($allUpdates | Where-Object { -not $_.IsDeclined -and $_.IsExpired })
    $superseded = @($allUpdates | Where-Object { -not $_.IsDeclined -and $_.IsSuperseded })
    $cutoff = (Get-Date).AddMonths(-6)
    # Use CreationDate (Microsoft's release date) not ArrivalDate (when imported to WSUS)
    $oldUpdates = @($allUpdates | Where-Object { -not $_.IsDeclined -and $_.CreationDate -lt $cutoff })

    Write-Log "Found: Expired=$($expired.Count) | Superseded=$($superseded.Count) | Old (released over 6mo ago)=$($oldUpdates.Count)"

    if ($expired.Count -gt 0) {
        $expired | ForEach-Object { 
            try { 
                $_.Decline() | Out-Null
                $expiredCount++
            } catch { 
                Write-Warning "Failed to decline expired: $($_.Title)"
            } 
        }
    }
    
    if ($superseded.Count -gt 0) {
        $superseded | ForEach-Object { 
            try { 
                $_.Decline() | Out-Null
                $supersededCount++
            } catch { 
                Write-Warning "Failed to decline superseded: $($_.Title)"
            } 
        }
    }
    
    if ($oldUpdates.Count -gt 0) {
        $oldUpdates | ForEach-Object { 
            try { 
                $_.Decline() | Out-Null
                $oldCount++
            } catch { 
                Write-Warning "Failed to decline old: $($_.Title)"
            } 
        }
    }

    Write-Log "Successfully declined: Expired=$expiredCount | Superseded=$supersededCount | Old (released over 6mo ago)=$oldCount"

    # === APPROVE UPDATES (CONSERVATIVE) ===
    Write-Log "Checking for updates to approve..."
    $targetGroup = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq "All Computers" }

    if ($targetGroup) {
        # Conservative approval criteria based on enabled classifications
        $pendingUpdates = @($allUpdates | Where-Object { 
            -not $_.IsDeclined -and 
            -not $_.IsSuperseded -and
            -not $_.IsExpired -and
            ($_.GetUpdateApprovals($targetGroup) | Where-Object { $_.Action -eq "Install" }).Count -eq 0 -and
            $_.CreationDate -gt (Get-Date).AddMonths(-6) -and  # Only recent updates (last 6 months)
            $_.Title -notlike "*Preview*" -and
            $_.Title -notlike "*Beta*" -and
            (
                $_.UpdateClassificationTitle -eq "Critical Updates" -or
                $_.UpdateClassificationTitle -eq "Security Updates" -or
                $_.UpdateClassificationTitle -eq "Update Rollups" -or
                $_.UpdateClassificationTitle -eq "Service Packs" -or
                $_.UpdateClassificationTitle -eq "Updates"
                # Excluding "Definition Updates" (too frequent) and "Upgrades" (need manual review)
            )
        })
        
        Write-Log "Pending updates meeting criteria: $($pendingUpdates.Count)"
        Write-Log "  Criteria: Critical/Security/Rollups/SPs/Updates only, released within 6mo, not superseded/expired"
        Write-Log "  Excluded: Definition Updates, Upgrades, Preview/Beta updates"
        
        if ($pendingUpdates.Count -gt 0) {
            # Safety check - don't auto-approve more than 100 updates
            if ($pendingUpdates.Count -gt 100) {
                Write-Warning "Found $($pendingUpdates.Count) updates to approve - this seems high!"
                Write-Warning "SKIPPING auto-approval for safety. Review updates in WSUS Console."
                Write-Log "Top 10 pending updates:"
                $pendingUpdates | Select-Object -First 10 | ForEach-Object {
                    Write-Log "  - $($_.Title) ($($_.UpdateClassificationTitle))"
                }
            } else {
                Write-Log "Approving $($pendingUpdates.Count) updates..."
                $pendingUpdates | ForEach-Object {
                    try { 
                        $_.Approve("Install", $targetGroup) | Out-Null
                        $approvedCount++
                        if ($approvedCount % 10 -eq 0) {
                            Write-Log "  Approved: $approvedCount / $($pendingUpdates.Count)"
                        }
                    } catch { 
                        Write-Warning "Failed to approve: $($_.Title)" 
                    }
                }
                Write-Log "Successfully approved: $approvedCount updates"
            }
        } else {
            Write-Log "No updates meet approval criteria"
        }
    } else {
        Write-Warning "Target group 'All Computers' not found"
    }
} else {
    Write-Warning "No updates retrieved - skipping decline/approve operations"
    Write-Warning "Proceeding with cleanup and database maintenance to improve performance"
}

# Store results for reporting
$MaintenanceResults.DeclinedExpired = $expiredCount
$MaintenanceResults.DeclinedSuperseded = $supersededCount
$MaintenanceResults.DeclinedOld = $oldCount
$MaintenanceResults.Approved = $approvedCount

# === CLEANUP ===
if (Test-ShouldRunOperation "Cleanup" $Operations) {
    # Run the built-in WSUS cleanup tasks to prune obsolete data/files.
    Write-Status "Running WSUS cleanup..." -Type Phase
    Write-Log "Running WSUS cleanup..."
    $cleanupPhase = @{ Name = "WSUS Cleanup"; Status = "In Progress"; Duration = "" }
    $cleanupStart = Get-Date

    try {
        Import-Module UpdateServices -ErrorAction SilentlyContinue

        Write-Log "This may take 10-30 minutes for large databases..."

        $cleanup = Invoke-WsusServerCleanup `
                             -CleanupObsoleteComputers `
                             -CleanupObsoleteUpdates `
                             -CleanupUnneededContentFiles `
                             -CompressUpdates `
                             -DeclineSupersededUpdates `
                             -DeclineExpiredUpdates `
                             -Confirm:$false

        $cleanupDuration = [math]::Round(((Get-Date) - $cleanupStart).TotalMinutes, 1)
        Write-Log "Cleanup completed in $cleanupDuration minutes"
        Write-Log "Results: Obsolete Updates=$($cleanup.ObsoleteUpdatesDeleted) | Computers=$($cleanup.ObsoleteComputersDeleted) | Space=$([math]::Round($cleanup.DiskSpaceFreed/1MB,2))MB"

        # Additional deep cleanup for declined updates
        Write-Log "Running deep cleanup of old declined update metadata..."
        $deepCleanupQuery = @'
-- Remove update status for old declined updates (keeps DB lean)
-- Using correct schema: tbProperty has CreationDate (Microsoft's release date)
-- Join through tbRevision to get to tbProperty
DECLARE @Deleted INT = 0
DECLARE @BatchSize INT = 1000

DELETE TOP (@BatchSize) usc
FROM tbUpdateStatusPerComputer usc
INNER JOIN tbRevision r ON usc.LocalUpdateID = r.LocalUpdateID
INNER JOIN tbProperty p ON r.RevisionID = p.RevisionID
WHERE r.State = 2  -- Declined state
AND p.CreationDate < DATEADD(MONTH, -6, GETDATE())  -- Microsoft released over 6 months ago

SET @Deleted = @@ROWCOUNT

-- Return count of declined updates using correct join
SELECT
    @Deleted AS StatusRecordsDeleted,
    (SELECT COUNT(*)
     FROM tbRevision r
     INNER JOIN tbProperty p ON r.RevisionID = p.RevisionID
     WHERE r.State = 2
     AND p.CreationDate < DATEADD(MONTH, -6, GETDATE())) AS TotalOldDeclined
'@

        try {
            $deepResult = Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
                -Query $deepCleanupQuery -QueryTimeout 300
            Write-Log "Removed $($deepResult.StatusRecordsDeleted) old status records"
            Write-Log "Total old declined updates (released over 6mo ago): $($deepResult.TotalOldDeclined)"

            if ($deepResult.TotalOldDeclined -gt 5000) {
                Write-Warning "Large number of old declined updates ($($deepResult.TotalOldDeclined)) detected"
                Write-Warning "Consider running aggressive cleanup script for database optimization"
                $MaintenanceResults.Warnings += "Large number of old declined updates: $($deepResult.TotalOldDeclined)"
            }
        } catch {
            Write-Warning "Deep cleanup query failed: $($_.Exception.Message)"
        }

        $cleanupPhase.Status = "Completed"
        $cleanupPhase.Duration = "$cleanupDuration min"
        Write-Status "Cleanup completed ($cleanupDuration min)" -Type Success

    } catch {
        Write-Status "Cleanup failed: $($_.Exception.Message)" -Type Error
        $MaintenanceResults.Errors += "Cleanup failed: $($_.Exception.Message)"
        $cleanupPhase.Status = "Failed"
    }
    $MaintenanceResults.Phases += $cleanupPhase

    # === DATABASE MAINTENANCE ===
    # Index optimization and stats updates to keep SUSDB responsive.
    Write-Status "Running database maintenance..." -Type Phase
    Write-Log "Database maintenance..."

    # Wait for any pending WSUS operations to complete
    Write-Log "Waiting 30 seconds for WSUS operations to complete..."
    Start-Sleep -Seconds 30

    # Use module functions for index optimization
    try {
        Write-Log "Optimizing indexes (may take 5-15 minutes)..."
        $indexStart = Get-Date

        $indexResult = Optimize-WsusIndexes -SqlInstance "localhost\SQLEXPRESS"

        $indexDuration = [math]::Round(((Get-Date) - $indexStart).TotalMinutes, 1)
        Write-Log "Index optimization complete in $indexDuration minutes (Rebuilt: $($indexResult.Rebuilt), Reorganized: $($indexResult.Reorganized))"
        Write-Status "Database maintenance completed" -Type Success
    } catch {
        Write-Warning "Index maintenance encountered errors: $($_.Exception.Message)"
        Write-Log "Continuing with remaining maintenance tasks..."
    }

    # Update statistics using module function
    if (Update-WsusStatistics -SqlInstance "localhost\SQLEXPRESS") {
        Write-Log "Statistics updated"
    }
} else {
    Write-Status "Skipping cleanup" -Type Info
    $MaintenanceResults.Phases += @{ Name = "WSUS Cleanup"; Status = "Skipped"; Duration = "" }
}

# === ULTIMATE CLEANUP (SUPSESSION + DECLINED PURGE) ===
# Optional heavy cleanup before backup to reduce DB size and bloat.
if ((Test-ShouldRunOperation "UltimateCleanup" $Operations) -and -not $SkipUltimateCleanup) {
    Write-Status "Running ultimate cleanup..." -Type Phase
    Write-Log "Running ultimate cleanup steps before backup..."
    $ultimatePhase = @{ Name = "Ultimate Cleanup"; Status = "In Progress"; Duration = "" }
    $ultimateStart = Get-Date

    # Stop WSUS to reduce contention while manipulating SUSDB.
    if (Test-ServiceRunning -ServiceName "WSUSService") {
        Write-Log "Stopping WSUS Service for ultimate cleanup..."
        if (Stop-WsusServer -Force) {
            Write-Log "WSUS Service stopped"
        } else {
            Write-Warning "Failed to stop WSUS Service"
        }
    }

    # Remove supersession records using module functions
    $deletedDeclined = Remove-DeclinedSupersessionRecords -SqlInstance "localhost\SQLEXPRESS"
    Write-Log "Removed $deletedDeclined supersession records for declined updates"

    # Remove supersession records for superseded updates
    $deletedSuperseded = Remove-SupersededSupersessionRecords -SqlInstance "localhost\SQLEXPRESS" -ShowProgress
    Write-Log "Removed $deletedSuperseded supersession records for superseded updates"

    # Delete declined updates using the official spDeleteUpdate procedure.
    try {
        if (-not $allUpdates -or $allUpdates.Count -eq 0) {
            Write-Log "Reloading updates for declined purge..."
            $allUpdates = $wsus.GetUpdates()
        }

        $declinedIDs = @($allUpdates | Where-Object { $_.IsDeclined } |
            Select-Object -ExpandProperty Id |
            ForEach-Object { $_.UpdateId })

        if ($declinedIDs.Count -gt 0) {
            Write-Log "Deleting $($declinedIDs.Count) declined updates from SUSDB..."

            $batchSize = 100
            $totalDeleted = 0
            $totalBatches = [math]::Ceiling($declinedIDs.Count / $batchSize)
            $currentBatch = 0

            for ($i = 0; $i -lt $declinedIDs.Count; $i += $batchSize) {
                $currentBatch++
                $batch = $declinedIDs | Select-Object -Skip $i -First $batchSize

                foreach ($updateId in $batch) {
                    $deleteQuery = @"
DECLARE @LocalUpdateID int
SELECT @LocalUpdateID = LocalUpdateID FROM tbUpdate WHERE UpdateID = '$updateId'
IF @LocalUpdateID IS NOT NULL
    EXEC spDeleteUpdate @localUpdateID = @LocalUpdateID
"@

                    try {
                        Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
                            -Query $deleteQuery -QueryTimeout 300 -ErrorAction SilentlyContinue | Out-Null
                        $totalDeleted++
                    } catch {
                        # Continue on errors to avoid aborting the batch.
                    }
                }

                if ($currentBatch % 5 -eq 0) {
                    $percentComplete = [math]::Round(($currentBatch / $totalBatches) * 100, 1)
                    Write-Log "Declined purge progress: $currentBatch/$totalBatches batches ($percentComplete%) - Deleted: $totalDeleted"
                }
            }

            Write-Log "Declined update purge complete: $totalDeleted deleted"
        } else {
            Write-Log "No declined updates found to delete"
        }
    } catch {
        Write-Warning "Declined update purge failed: $($_.Exception.Message)"
    }

    # Optional shrink after heavy cleanup to reclaim space (can be slow).
    Write-Log "Shrinking SUSDB after cleanup (this may take a while)..."
    if (Invoke-WsusDatabaseShrink -SqlInstance "localhost\SQLEXPRESS") {
        Write-Log "SUSDB shrink completed"
    }

    # Start WSUS service back up after database maintenance.
    if (-not (Test-ServiceRunning -ServiceName "WSUSService")) {
        Write-Log "Starting WSUS Service..."
        Start-WsusServer | Out-Null
    }

    $ultimateDuration = [math]::Round(((Get-Date) - $ultimateStart).TotalMinutes, 1)
    $ultimatePhase.Status = "Completed"
    $ultimatePhase.Duration = "$ultimateDuration min"
    $MaintenanceResults.Phases += $ultimatePhase
    Write-Status "Ultimate cleanup completed ($ultimateDuration min)" -Type Success
} else {
    Write-Status "Skipping ultimate cleanup" -Type Info
    Write-Log "Skipping ultimate cleanup before backup (SkipUltimateCleanup specified or not selected)."
    $MaintenanceResults.Phases += @{ Name = "Ultimate Cleanup"; Status = "Skipped"; Duration = "" }
}

# === BACKUP ===
if (Test-ShouldRunOperation "Backup" $Operations) {
    Write-Status "Starting database backup..." -Type Phase
    $backupPhase = @{ Name = "Database Backup"; Status = "In Progress"; Duration = "" }

    $backupFolder = "C:\WSUS"
    $backupFile = Join-Path $backupFolder "SUSDB_$(Get-Date -Format 'yyyyMMdd').bak"

    if (Test-Path $backupFile) {
        $counter = 1
        while (Test-Path "$backupFolder\SUSDB_$(Get-Date -Format 'yyyyMMdd')_$counter.bak") { $counter++ }
        $backupFile = "$backupFolder\SUSDB_$(Get-Date -Format 'yyyyMMdd')_$counter.bak"
    }

    Write-Log "Starting backup: $backupFile"
    $backupStart = Get-Date

    try {
        $dbSize = Get-WsusDatabaseSize -SqlInstance "localhost\SQLEXPRESS"
        Write-Log "Database size: $dbSize GB"
        $MaintenanceResults.DatabaseSize = $dbSize

        Invoke-Sqlcmd -ServerInstance "localhost\SQLEXPRESS" -Database SUSDB `
            -Query "BACKUP DATABASE SUSDB TO DISK=N'$backupFile' WITH INIT, STATS=10" `
            -QueryTimeout 0 | Out-Null

        $duration = [math]::Round(((Get-Date) - $backupStart).TotalMinutes, 2)
        $size = [math]::Round((Get-Item $backupFile).Length / 1MB, 2)
        Write-Log "Backup complete: ${size}MB in ${duration} minutes"

        $MaintenanceResults.BackupFile = $backupFile
        $MaintenanceResults.BackupSize = $size
        $backupPhase.Status = "Completed"
        $backupPhase.Duration = "$duration min"
        Write-Status "Backup completed: ${size}MB ($duration min)" -Type Success
    } catch {
        Write-Status "Backup failed: $($_.Exception.Message)" -Type Error
        $MaintenanceResults.Errors += "Backup failed: $($_.Exception.Message)"
        $backupPhase.Status = "Failed"
    }
    $MaintenanceResults.Phases += $backupPhase
} else {
    Write-Status "Skipping backup" -Type Info
    $MaintenanceResults.Phases += @{ Name = "Database Backup"; Status = "Skipped"; Duration = "" }
}

# === CLEANUP OLD BACKUPS ===
Write-Log "Cleaning old backups (90-day retention)..."
$cutoffDate = (Get-Date).AddDays(-90)
$oldBackups = Get-ChildItem -Path $backupFolder -Filter "SUSDB*.bak" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }

if ($oldBackups) {
    $spaceFreed = [math]::Round(($oldBackups | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $oldBackups | ForEach-Object {
        Write-Log "  Deleting: $($_.Name) ($([math]::Round($_.Length/1MB,2))MB)"
        Remove-Item $_.FullName -Force -Confirm:$false
    }
    Write-Log "Freed: ${spaceFreed}MB"
} else {
    Write-Log "No old backups to delete"
}

$currentBackups = Get-ChildItem -Path $backupFolder -Filter "SUSDB*.bak" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($currentBackups) {
    $totalSize = [math]::Round(($currentBackups | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    Write-Log "Current backups: $($currentBackups.Count) files | ${totalSize}MB total"
}

# === SUMMARY ===
Write-Output "`n============================================================"
Write-Log "MAINTENANCE SUMMARY"
Write-Output "------------------------------------------------------------"
Write-Log "Declined: Expired=$expiredCount | Superseded=$supersededCount | Old (released over 6mo ago)=$oldCount"
Write-Log "Approved: $approvedCount updates (excluding Definition Updates)"

try {
    $dbSize = Get-WsusDatabaseSize -SqlInstance "localhost\SQLEXPRESS"
    Write-Log "SUSDB size: $dbSize GB"
    if ($dbSize -ge 9.0) { Write-Warning "Database approaching 10GB limit!" }
} catch {}

Write-Log "Backup: $backupFile"

if ($allUpdates.Count -eq 0) {
    Write-Output "------------------------------------------------------------"
    Write-Warning "GetUpdates timed out - consider running this script again"
    Write-Warning "after the cleanup and index optimization have improved DB performance"
}

Write-Output "============================================================`n"

# === DIFFERENTIAL EXPORT TO WSUS-EXPORTS (OPTIONAL) ===
if ((Test-ShouldRunOperation "Export" $Operations) -and -not $SkipExport -and $ExportPath) {
    Write-Status "Starting differential export..." -Type Phase
    Write-Log "Starting differential export..."
    $exportPhase = @{ Name = "Export"; Status = "In Progress"; Duration = "" }
    $exportStart = Get-Date

    # Prompt for days if not specified via command line (skip in unattended mode)
    if ($ExportDays -eq 0) {
        if ($Unattended) {
            $ExportDays = 30
        } else {
            Write-Host ""
            Write-Host "Differential Export Configuration" -ForegroundColor Yellow
            Write-Host "Export files modified within how many days? (default: 30)" -ForegroundColor Cyan
            $daysInput = Read-Host "Days"
            $ExportDays = if ($daysInput -match '^\d+$') { [int]$daysInput } else { 30 }
        }
    }
    Write-Log "Export will include files modified within last $ExportDays days"

    # Create year/month/day structure
    $year = (Get-Date).ToString("yyyy")
    $month = (Get-Date).ToString("MMM")
    $day = (Get-Date).ToString("dd")
    $exportDestination = [System.IO.Path]::Combine($ExportPath, $year, $month, $day)

    Write-Log "Export destination: $exportDestination"

    # Check if export path is accessible using improved test
    if (-not (Test-ExportPathAccess -ExportPath $ExportPath)) {
        Write-Status "Cannot access export path: $ExportPath" -Type Error
        Write-Warning "Skipping export - check network connectivity"
        $MaintenanceResults.Errors += "Export path inaccessible: $ExportPath"
        $exportPhase.Status = "Failed"
    } else {
        # Create export directory
        if (-not (Test-Path $exportDestination)) {
            New-Item -Path $exportDestination -ItemType Directory -Force | Out-Null
            Write-Log "Created export directory: $exportDestination"
        }

        # Copy database backup
        Write-Log "[1/2] Copying database backup..."
        if (Test-Path $backupFile) {
            Copy-Item -Path $backupFile -Destination $exportDestination -Force
            Write-Log "Database copied: $(Split-Path $backupFile -Leaf)"
        } else {
            Write-Warning "Backup file not found: $backupFile"
        }

        # Differential copy of content using robocopy with MAXAGE
        Write-Log "[2/2] Differential copy of content (files modified within $ExportDays days)..."
        $wsusContentSource = "C:\WSUS\WsusContent"
        $contentExportPath = Join-Path $exportDestination "WsusContent"

        if (Test-Path $wsusContentSource) {
            $robocopyLogDir = "C:\WSUS\Logs"
            if (-not (Test-Path $robocopyLogDir)) {
                New-Item -Path $robocopyLogDir -ItemType Directory -Force | Out-Null
            }
            $robocopyLog = "$robocopyLogDir\Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

            # /E = include subdirs, /MAXAGE:N = only files modified within N days
            # /XO = exclude older files (differential), /MT:16 = 16 threads
            $robocopyArgs = @(
                $wsusContentSource,
                $contentExportPath,
                "/E", "/MAXAGE:$ExportDays", "/XO", "/MT:16", "/R:2", "/W:5",
                "/XF", "*.bak", "*.log",
                "/XD", "Logs", "SQLDB", "Backup",
                "/LOG:$robocopyLog", "/TEE", "/NP", "/NDL"
            )

            $robocopyResult = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
            if ($robocopyResult.ExitCode -lt 8) {
                Write-Log "Content export completed successfully"
            } else {
                Write-Warning "Robocopy exit code: $($robocopyResult.ExitCode)"
                $MaintenanceResults.Warnings += "Robocopy exit code: $($robocopyResult.ExitCode)"
            }

            # Show export stats
            if (Test-Path $contentExportPath) {
                $exportedFiles = Get-ChildItem -Path $contentExportPath -Recurse -File -ErrorAction SilentlyContinue
                $exportedSize = [math]::Round(($exportedFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
                Write-Log "Exported: $($exportedFiles.Count) files ($exportedSize GB)"
                $MaintenanceResults.ExportedFiles = $exportedFiles.Count
                $MaintenanceResults.ExportSize = $exportedSize
            }
        } else {
            Write-Warning "WsusContent folder not found: $wsusContentSource"
        }

        $exportDuration = [math]::Round(((Get-Date) - $exportStart).TotalMinutes, 1)
        $MaintenanceResults.ExportPath = $exportDestination
        $exportPhase.Status = "Completed"
        $exportPhase.Duration = "$exportDuration min"
        Write-Log "Export complete: $exportDestination"
        Write-Status "Export completed ($exportDuration min)" -Type Success
    }
    $MaintenanceResults.Phases += $exportPhase
} elseif ($SkipExport) {
    Write-Status "Skipping export (SkipExport specified)" -Type Info
    Write-Log "Skipping export (SkipExport specified)"
    $MaintenanceResults.Phases += @{ Name = "Export"; Status = "Skipped"; Duration = "" }
} else {
    Write-Status "Skipping export" -Type Info
    Write-Log "Skipping export (no ExportPath specified or not selected)"
    $MaintenanceResults.Phases += @{ Name = "Export"; Status = "Skipped"; Duration = "" }
}

# === FINALIZE RESULTS ===
$MaintenanceResults.EndTime = Get-Date
$totalDuration = [math]::Round(($MaintenanceResults.EndTime - $MaintenanceResults.StartTime).TotalMinutes, 1)

# Check if any errors occurred
if ($MaintenanceResults.Errors.Count -gt 0) {
    $MaintenanceResults.Success = $false
}

# === FINAL SUMMARY ===
Write-Host ""
$summaryColor = if ($MaintenanceResults.Success) { "Green" } else { "Red" }
Write-Host "  +============================================================+" -ForegroundColor $summaryColor
Write-Host "  |                   MAINTENANCE COMPLETE                      |" -ForegroundColor $summaryColor
Write-Host "  +============================================================+" -ForegroundColor $summaryColor
Write-Host ""
Write-Status "Total duration: $totalDuration minutes" -Type Info
Write-Status "Declined: Expired=$($MaintenanceResults.DeclinedExpired) | Superseded=$($MaintenanceResults.DeclinedSuperseded) | Old=$($MaintenanceResults.DeclinedOld)" -Type Info
Write-Status "Approved: $($MaintenanceResults.Approved) updates" -Type Info

if ($MaintenanceResults.DatabaseSize -gt 0) {
    Write-Status "Database: $($MaintenanceResults.DatabaseSize) GB" -Type Info
}
if ($MaintenanceResults.BackupFile) {
    Write-Status "Backup: $($MaintenanceResults.BackupFile) ($($MaintenanceResults.BackupSize) MB)" -Type Info
}
if ($MaintenanceResults.ExportPath) {
    Write-Status "Export: $($MaintenanceResults.ExportPath)" -Type Info
}

if ($MaintenanceResults.Warnings.Count -gt 0) {
    Write-Host ""
    Write-Status "Warnings: $($MaintenanceResults.Warnings.Count)" -Type Warning
}

if ($MaintenanceResults.Errors.Count -gt 0) {
    Write-Host ""
    Write-Status "Errors: $($MaintenanceResults.Errors.Count)" -Type Error
    foreach ($err in $MaintenanceResults.Errors) {
        Write-Status "  $err" -Type Error
    }
}

Write-Host ""

Write-Log "Maintenance complete"
Stop-WsusLogging
