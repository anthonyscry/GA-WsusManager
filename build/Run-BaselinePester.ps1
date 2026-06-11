#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Exclude = @('WsusAutoDetection.Tests.ps1','WsusGroupPolicy.Tests.ps1','WsusFirewall.Tests.ps1','Integration.Tests.ps1','StartupE2E.Tests.ps1')
)
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$cfg = New-PesterConfiguration
$testsDir = Join-Path $PSScriptRoot '..\Tests' | Resolve-Path
$cfg.Run.Path = (Get-ChildItem -Path (Join-Path $testsDir '*.Tests.ps1') -File | Where-Object { $_.Name -notin $Exclude }).FullName
$cfg.Run.Exit = $false
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'None'

$r = Invoke-Pester -Configuration $cfg -ErrorAction SilentlyContinue
$summary = [pscustomobject]@{
    Passed = $r.PassedCount
    Failed = $r.FailedCount
    Skipped = $r.SkippedCount
    Total = $r.TotalCount
}
$summary | Format-Table -AutoSize | Out-String | Write-Host
$r.Failed | ForEach-Object {
    Write-Host "FAILED: $($_.ExpandedPath):$($_.ExpandedName) - $($_.ErrorRecord.Exception.Message)"
}
exit $r.FailedCount
