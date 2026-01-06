#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Combined installer and validator for WSUS + SQL Express.
.DESCRIPTION
    Runs install.ps1 then validates WSUS content path and permissions.
.PARAMETER ContentPath
    WSUS content path (default: C:\WSUS).
.PARAMETER SqlInstance
    SQL Server instance name (default: .\SQLEXPRESS).
.PARAMETER SkipInstall
    Skip running install.ps1.
.PARAMETER SkipContentValidation
    Skip running Check-WSUSContent.ps1.
.PARAMETER FixContentIssues
    Automatically fix issues found during content validation.
#>

[CmdletBinding()]
param(
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS",
    [switch]$SkipInstall,
    [switch]$SkipContentValidation,
    [switch]$FixContentIssues
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-LocalScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path $Path)) {
        throw "Missing script: $Path"
    }

    Write-Host "" 
    Write-Host "==============================================================="
    Write-Host $Description
    Write-Host "==============================================================="

    & $Path @Arguments
}

if ($ContentPath -match "\\wsuscontent$") {
    Write-Warning "ContentPath ends with \\wsuscontent. WSUS expects C:\\WSUS or another root folder, not a nested wsuscontent directory."
}

if (-not $SkipInstall) {
    Invoke-LocalScript -Path (Join-Path $scriptRoot "install.ps1") -Description "Installing SQL Express + SSMS + WSUS"
} else {
    Write-Host "Skipping install.ps1 (SkipInstall specified)."
}

if (-not $SkipContentValidation) {
    $args = @("-ContentPath", $ContentPath, "-SqlInstance", $SqlInstance)
    if ($FixContentIssues) {
        $args += "-FixIssues"
    }

    Invoke-LocalScript -Path (Join-Path $scriptRoot "Check-WSUSContent.ps1") -Description "Validating WSUS content path" -Arguments $args
} else {
    Write-Host "Skipping Check-WSUSContent.ps1 (SkipContentValidation specified)."
}

Write-Host "" 
Write-Host "Setup flow complete. Optional next steps:" 
Write-Host "- Import a SUSDB backup: .\\ImportScript.ps1"
Write-Host "- Run maintenance: .\\WsusMaintenance.ps1"
Write-Host "- Run cleanup: .\\Ultimate-WsusCleanup.ps1"
Write-Host "- Force client check-in: .\\Force-WSUSCheckIn.ps1"
