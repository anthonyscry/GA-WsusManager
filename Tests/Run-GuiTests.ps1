<#
.SYNOPSIS
    CI test runner for FlaUI GUI tests via scheduled task.

.DESCRIPTION
    GUI automation tests require an interactive desktop session.
    On self-hosted GitHub Actions runners running as a Windows service,
    there's no interactive desktop. This script creates a scheduled task
    to run the GUI tests in the interactive console session, then
    collects the results.

.PARAMETER ResultsPath
    Path to write the test results transcript. Default: .\Tests\flaui-test-results.txt

.PARAMETER TimeoutSeconds
    Maximum time to wait for test completion. Default: 300 (5 minutes)

.NOTES
    The scheduled task approach works because Windows maintains an
    interactive desktop session for logged-in users (Session 1).
    The task runs under the same user account and has access to
    the interactive desktop where UI Automation works.
#>
[CmdletBinding()]
param(
    [string]$ResultsPath = (Join-Path $PSScriptRoot "Tests\flaui-test-results.txt"),
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot

Write-Host "=== GUI Test Runner (Interactive Session) ===" -ForegroundColor Cyan
Write-Host "Repository: $RepoRoot"
Write-Host "Results:    $ResultsPath"
Write-Host "Timeout:    ${TimeoutSeconds}s"

# Step 1: Install FlaUI packages
Write-Host "`n[1/5] Installing FlaUI packages..." -ForegroundColor Yellow
$installScript = Join-Path $RepoRoot "Tests\FlaUITestHarness\Install-FlaUI.ps1"
if (Test-Path $installScript) {
    & $installScript
} else {
    Write-Warning "Install script not found: $installScript"
}

# Step 2: Kill any existing instances
Write-Host "`n[2/5] Cleaning up existing processes..." -ForegroundColor Yellow
Get-Process -Name "GA-WsusManager" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "WsusManager" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Step 3: Remove old results
if (Test-Path $ResultsPath) {
    Remove-Item $ResultsPath -Force
}

# Step 4: Create the wrapper script that the scheduled task will run
$wrapperScript = Join-Path $RepoRoot "Tests\_ci-gui-test-wrapper.ps1"
$wrapperContent = @"
Set-Location "$RepoRoot"
Import-Module Pester -Force
`$resultFile = "$ResultsPath"

Remove-Item `$resultFile -Force -ErrorAction SilentlyContinue
Start-Transcript -Path `$resultFile -Force -IncludeInvocationHeader

try {
    Invoke-Pester -Path .\Tests\FlaUI.Tests.ps1 -Output Detailed
} finally {
    Stop-Transcript
    Get-Process GA-WsusManager -ErrorAction SilentlyContinue | Stop-Process -Force
}
"@
$wrapperContent | Out-File -FilePath $wrapperScript -Encoding UTF8 -Force

# Step 5: Create and run the scheduled task
$taskName = "WsusManagerGuiTests_CI"

Write-Host "`n[3/5] Creating scheduled task '$taskName'..." -ForegroundColor Yellow
schtasks /Create /TN $taskName /TR "powershell.exe -ExecutionPolicy Bypass -File `"$wrapperScript`"" /SC ONCE /ST 00:00 /F /RL HIGHEST 2>&1 | Out-Null

Write-Host "`n[4/5] Running tests via scheduled task..." -ForegroundColor Yellow
schtasks /Run /TN $taskName 2>&1 | Out-Null

# Wait for results
Write-Host "`n[5/5] Waiting for results (max ${TimeoutSeconds}s)..." -ForegroundColor Yellow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$completed = $false

while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    if (Test-Path $ResultsPath) {
        $content = Get-Content $ResultsPath -Raw -ErrorAction SilentlyContinue
        if ($content -match "Tests completed") {
            $completed = $true
            break
        }
    }
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds)
    Write-Host "  Waiting... ${elapsed}s"
    Start-Sleep -Seconds 5
}

$sw.Stop()

if (-not $completed) {
    Write-Warning "Tests did not complete within ${TimeoutSeconds}s timeout"
    schtasks /End /TN $taskName 2>&1 | Out-Null
}

# Cleanup
Write-Host "`nCleaning up..." -ForegroundColor Yellow
schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
if (Test-Path $wrapperScript) {
    Remove-Item $wrapperScript -Force
}

# Display results
if (Test-Path $ResultsPath) {
    Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
    Get-Content $ResultsPath
} else {
    Write-Error "No results file found at $ResultsPath"
    exit 1
}
