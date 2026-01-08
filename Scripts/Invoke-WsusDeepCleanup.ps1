<#
===============================================================================
Script: Invoke-WsusDeepCleanup.ps1
Purpose: Aggressive WSUS database cleanup for large or bloated SUSDBs.
Overview:
  - Removes supersession records for declined/superseded updates.
  - Permanently deletes declined update metadata.
  - Adds indexes, rebuilds indexes, updates stats, and shrinks DB.
Notes:
  - Run as Administrator on the WSUS server.
  - Expect WSUS to be offline during this run.
  - Use quarterly or when DB performance degrades.
===============================================================================
.PARAMETER Force
    Skip confirmation prompt and run cleanup automatically.
.PARAMETER SkipConfirmation
    Alias for -Force parameter.
.PARAMETER LogFile
    Path to log file for transcript output (default: C:\WSUS\Logs\UltimateCleanup_<timestamp>.log).
#>

[CmdletBinding()]
param(
    [Alias("SkipConfirmation")]
    [switch]$Force,
    [string]$LogFile = "C:\WSUS\Logs\UltimateCleanup_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
)

# Import shared modules
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
Import-Module (Join-Path $modulePath "WsusUtilities.ps1") -Force
Import-Module (Join-Path $modulePath "WsusDatabase.ps1") -Force
Import-Module (Join-Path $modulePath "WsusServices.ps1") -Force

# Keep the script moving even if a step fails.
$ErrorActionPreference = 'Continue'

# Setup logging using module function
$LogFile = Start-WsusLogging -ScriptName "UltimateCleanup" -UseTimestamp $true
$ProgressPreference = "SilentlyContinue"

Write-Host "`n===================================================================" -ForegroundColor Cyan
Write-Host "           ULTIMATE WSUS DATABASE CLEANUP" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "Log file: $LogFile" -ForegroundColor Gray
Write-Host "`nThis script performs comprehensive WSUS database cleanup:" -ForegroundColor Yellow
Write-Host "  1. Removes supersession records for declined/superseded updates"
Write-Host "  2. Permanently deletes declined update metadata"
Write-Host "  3. Adds performance indexes"
Write-Host "  4. Rebuilds all indexes"
Write-Host "  5. Updates statistics"
Write-Host "  6. Shrinks database"
Write-Host "`nWARNING: WSUS will be offline for 30-90 minutes`n" -ForegroundColor Red

# === GET CURRENT STATE ===
# Load WSUS APIs and capture current health/size stats so we can compare later.
Write-Host "=== Current State ===" -ForegroundColor Cyan

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
$allUpdates = $wsus.GetUpdates()

$beforeStats = @{
    TotalUpdates = $allUpdates.Count
    DeclinedUpdates = @($allUpdates | Where-Object { $_.IsDeclined }).Count
    SupersededUpdates = @($allUpdates | Where-Object { $_.IsSuperseded -and -not $_.IsDeclined }).Count
    ActiveUpdates = @($allUpdates | Where-Object { -not $_.IsDeclined -and -not $_.IsSuperseded }).Count
}

# Query current SUSDB size and supersession counts using module function
$beforeDb = Get-WsusDatabaseStats -SqlInstance "localhost\SQLEXPRESS"

Write-Host "`nCurrent Database State:" -ForegroundColor Yellow
Write-Host "  Total updates: $($beforeStats.TotalUpdates)"
Write-Host "  Declined updates: $($beforeStats.DeclinedUpdates)"
Write-Host "  Superseded updates: $($beforeStats.SupersededUpdates)"
Write-Host "  Active updates: $($beforeStats.ActiveUpdates)"
Write-Host "  Supersession records: $($beforeDb.SupersessionRecords)"
Write-Host "  Database size: $($beforeDb.SizeGB) GB"

# Calculate expected cleanup (rough estimates).
$expectedSupersessionRemoval = $beforeDb.DeclinedRevisions + $beforeDb.SupersededRevisions
$expectedSpaceSavings = [math]::Round($beforeStats.DeclinedUpdates * 0.0001 + ($expectedSupersessionRemoval * 0.000001), 2)

Write-Host "`nExpected Cleanup:" -ForegroundColor Green
Write-Host "  Remove ~$expectedSupersessionRemoval supersession records"
Write-Host "  Delete ~$($beforeStats.DeclinedUpdates) declined updates"
Write-Host "  Free ~$expectedSpaceSavings GB (approximate)"
Write-Host "  Result: ~$($beforeStats.ActiveUpdates) active updates remaining"

# Require explicit confirmation before heavy operations (unless -Force is specified).
if (-not $Force) {
    $response = Read-Host "`nProceed with ultimate cleanup? (yes/no)"
    if ($response -ne "yes") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        Stop-Transcript -ErrorAction SilentlyContinue
        exit 0
    }
} else {
    Write-Host "`nSkipping confirmation (-Force specified)" -ForegroundColor Yellow
}

# === STOP WSUS SERVICE ===
# Stop WSUS to avoid contention while modifying SUSDB.
Write-Host "`n=== Step 1: Stop WSUS Service ===" -ForegroundColor Cyan

if (-not (Stop-WsusServer -Force)) {
    Write-Error "Failed to stop WSUS service"
    exit 1
}

# === REMOVE SUPERSESSION RECORDS ===
# Step 2 removes supersession rows that point to declined/superseded updates.
Write-Host "`n=== Step 2: Remove Supersession Records ===" -ForegroundColor Cyan

# Declined updates: remove supersession rows first.
Write-Host "Removing supersession records for declined updates..." -ForegroundColor Yellow
$deletedDeclined = Remove-DeclinedSupersessionRecords -SqlInstance "localhost\SQLEXPRESS"
Write-Host "? Removed $deletedDeclined supersession records for declined updates" -ForegroundColor Green

# Superseded updates: delete in batches to avoid giant locks.
Write-Host "`nRemoving supersession records for superseded updates (10-20 minutes)..." -ForegroundColor Yellow
$deletedSuperseded = Remove-SupersededSupersessionRecords -SqlInstance "localhost\SQLEXPRESS" -ShowProgress
Write-Host "? Cleanup complete" -ForegroundColor Green

# === DELETE DECLINED UPDATES ===
# Step 3 removes the update metadata via spDeleteUpdate.
Write-Host "`n=== Step 3: Delete Declined Updates ===" -ForegroundColor Cyan

if ($beforeStats.DeclinedUpdates -gt 0) {
    Write-Host "Permanently deleting $($beforeStats.DeclinedUpdates) declined updates (20-60 minutes)..." -ForegroundColor Yellow
    Write-Host "This uses the official WSUS spDeleteUpdate stored procedure`n" -ForegroundColor Gray
    
    # Get list of declined update IDs.
    $declinedIDs = @($allUpdates | Where-Object { $_.IsDeclined } | 
        Select-Object -ExpandProperty Id | 
        ForEach-Object { $_.UpdateId })
    
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
                # Continue on errors
            }
        }
        
        if ($currentBatch % 5 -eq 0) {
            $percentComplete = [math]::Round(($currentBatch / $totalBatches) * 100, 1)
            Write-Host "  Progress: $currentBatch/$totalBatches batches ($percentComplete%) - Deleted: $totalDeleted" -ForegroundColor Gray
        }
    }
    
    Write-Host "? Deleted $totalDeleted declined updates" -ForegroundColor Green
} else {
    Write-Host "? No declined updates to delete" -ForegroundColor Green
}

# === ADD PERFORMANCE INDEXES ===
Write-Host "`n=== Step 4: Add Performance Indexes ===" -ForegroundColor Cyan
Add-WsusPerformanceIndexes -SqlInstance "localhost\SQLEXPRESS" | Out-Null
Write-Host "? Performance indexes configured" -ForegroundColor Green

# === REBUILD ALL INDEXES ===
Write-Host "`n=== Step 5: Rebuild All Indexes ===" -ForegroundColor Cyan
Write-Host "Rebuilding fragmented indexes (10-20 minutes)..." -ForegroundColor Yellow

$rebuildResult = Optimize-WsusIndexes -SqlInstance "localhost\SQLEXPRESS" -ShowProgress
Write-Host "? Rebuilt $($rebuildResult.Rebuilt) indexes, reorganized $($rebuildResult.Reorganized) indexes" -ForegroundColor Green

# === UPDATE STATISTICS ===
Write-Host "`n=== Step 6: Update Statistics ===" -ForegroundColor Cyan
if (Update-WsusStatistics -SqlInstance "localhost\SQLEXPRESS") {
    Write-Host "? Statistics updated" -ForegroundColor Green
}

# === SHRINK DATABASE ===
Write-Host "`n=== Step 7: Shrink Database ===" -ForegroundColor Cyan

$space = Get-WsusDatabaseSpace -SqlInstance "localhost\SQLEXPRESS"
Write-Host "Space: Allocated=$([math]::Round($space.AllocatedMB,2))MB | Used=$([math]::Round($space.UsedMB,2))MB | Free=$([math]::Round($space.FreeMB,2))MB"

if ($space.FreeMB -gt 100) {
    Write-Host "Shrinking database..." -ForegroundColor Yellow
    if (Invoke-WsusDatabaseShrink -SqlInstance "localhost\SQLEXPRESS") {
        Write-Host "? Database shrunk" -ForegroundColor Green
    }
} else {
    Write-Host "? Skipping shrink (only $([math]::Round($space.FreeMB,2))MB free)" -ForegroundColor Yellow
}

# === RUN WSUS CLEANUP ===
Write-Host "`n=== Step 8: WSUS Server Cleanup ===" -ForegroundColor Cyan

try {
    Import-Module UpdateServices -ErrorAction SilentlyContinue
    $cleanup = Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -CompressUpdates -Confirm:$false
    Write-Host "? WSUS cleanup: Obsolete=$($cleanup.ObsoleteUpdatesDeleted) | Space=$([math]::Round($cleanup.DiskSpaceFreed/1MB,2))MB freed" -ForegroundColor Green
} catch {
    Write-Warning "WSUS cleanup: $($_.Exception.Message)"
}

# === START WSUS SERVICE ===
Write-Host "`n=== Step 9: Start WSUS Service ===" -ForegroundColor Cyan
Start-WsusServer | Out-Null

# === GET FINAL STATE ===
Write-Host "`n=== Final Results ===" -ForegroundColor Green

$afterDb = Get-WsusDatabaseStats -SqlInstance "localhost\SQLEXPRESS"

Write-Host "Refreshing WSUS data..." -ForegroundColor Yellow
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
$finalUpdates = $wsus.GetUpdates()

$afterStats = @{
    TotalUpdates = $finalUpdates.Count
    DeclinedUpdates = @($finalUpdates | Where-Object { $_.IsDeclined }).Count
    ActiveUpdates = @($finalUpdates | Where-Object { -not $_.IsDeclined -and -not $_.IsSuperseded }).Count
}

Write-Host "`n===================================================================" -ForegroundColor Cyan
Write-Host "                    BEFORE vs AFTER" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan

Write-Host "`nUpdates:" -ForegroundColor Yellow
Write-Host "  Total updates: $($beforeStats.TotalUpdates) ? $($afterStats.TotalUpdates)"
Write-Host "  Declined updates: $($beforeStats.DeclinedUpdates) ? $($afterStats.DeclinedUpdates)"
Write-Host "  Active updates: $($beforeStats.ActiveUpdates) ? $($afterStats.ActiveUpdates)"

Write-Host "`nDatabase:" -ForegroundColor Yellow
Write-Host "  Supersession records: $($beforeDb.SupersessionRecords) ? $($afterDb.SupersessionRecords)"
Write-Host "  Database size: $($beforeDb.SizeGB) GB ? $($afterDb.SizeGB) GB"

$recordsRemoved = $beforeDb.SupersessionRecords - $afterDb.SupersessionRecords
$updatesRemoved = $beforeStats.TotalUpdates - $afterStats.TotalUpdates
$spaceFreed = [math]::Round($beforeDb.SizeGB - $afterDb.SizeGB, 2)

Write-Host "`nImpact:" -ForegroundColor Green
Write-Host "  ? Removed $recordsRemoved supersession records"
Write-Host "  ? Deleted $updatesRemoved declined updates"
Write-Host "  ? Freed $spaceFreed GB of space"
Write-Host "  ? $($afterStats.ActiveUpdates) active updates remaining"

Write-Host "`n===================================================================" -ForegroundColor Cyan
Write-Host "                  CLEANUP COMPLETE!" -ForegroundColor Green
Write-Host "===================================================================" -ForegroundColor Cyan

Write-Host "`nRecommendations:" -ForegroundColor Yellow
Write-Host "  1. Run this ultimate cleanup quarterly"
Write-Host "  2. Run monthly maintenance script to prevent buildup"
Write-Host "  3. Monitor database - should stay under 3 GB"
Write-Host "  4. Your WSUS should now be significantly faster"
Write-Host ""

# Stop transcript logging using module function
Stop-WsusLogging
