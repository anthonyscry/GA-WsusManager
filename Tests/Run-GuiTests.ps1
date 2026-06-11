param(
    [string]$ResultsPath,
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$testsDir = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ResultsPath)) {
    $ResultsPath = Join-Path $testsDir "flaui-test-results.txt"
}

$repoRoot = Split-Path $testsDir

Write-Host "=== GUI Test Runner ===" -ForegroundColor Cyan
Write-Host "Repo:     $repoRoot"
Write-Host "Results:  $ResultsPath"

$installScript = Join-Path $testsDir "FlaUITestHarness\Install-FlaUI.ps1"
if (Test-Path $installScript) {
    Write-Host "Installing FlaUI packages..." -ForegroundColor Yellow
    & $installScript
}

Get-Process "GA-WsusManager" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process "WsusManager" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

if (Test-Path $ResultsPath) { Remove-Item $ResultsPath -Force }

$taskName = "WsusManagerGuiTests_$([guid]::NewGuid().Guid.Substring(0,8))"
$wrapperPath = Join-Path $testsDir "_gui_wrapper.ps1"

$wrapperContent = @"
Set-Location "$repoRoot"
Import-Module Pester -Force
Remove-Item "$ResultsPath" -Force -ErrorAction SilentlyContinue
Start-Transcript -Path "$ResultsPath" -Force -IncludeInvocationHeader
try {
    Invoke-Pester -Path "$testsDir\FlaUI.Tests.ps1" -Output Detailed
} finally {
    Stop-Transcript
    Get-Process GA-WsusManager -ErrorAction SilentlyContinue | Stop-Process -Force
}
"@
$wrapperContent | Out-File -FilePath $wrapperPath -Encoding UTF8 -Force

Write-Host "Running tests via scheduled task..." -ForegroundColor Yellow
schtasks /Create /TN $taskName /TR "powershell.exe -ExecutionPolicy Bypass -File `"$wrapperPath`"" /SC ONCE /ST 00:00 /F /RL HIGHEST 2>&1 | Out-Null
schtasks /Run /TN $taskName 2>&1 | Out-Null

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$completed = $false
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    if ((Test-Path $ResultsPath) -and (Get-Content $ResultsPath -Raw -ErrorAction SilentlyContinue) -match "Tests completed") {
        $completed = $true
        break
    }
    Start-Sleep -Seconds 5
}
$sw.Stop()

if (-not $completed) {
    Write-Warning "Tests did not complete within ${TimeoutSeconds}s"
    schtasks /End /TN $taskName 2>&1 | Out-Null
}

schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
Remove-Item $wrapperPath -Force -ErrorAction SilentlyContinue

if (Test-Path $ResultsPath) {
    Get-Content $ResultsPath
} else {
    Write-Error "No results file at $ResultsPath"
    exit 1
}
