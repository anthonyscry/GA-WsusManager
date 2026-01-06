#Requires -RunAsAdministrator

<#
===============================================================================
Script: Run-WsusSql.ps1
Purpose: Run the WSUS + SQL Express setup workflow.
Overview:
  - Runs install.ps1 to install SQL Express, SSMS, and WSUS.
  - Optionally validates the WSUS content path and fixes issues.
Notes:
  - Run as Administrator on the WSUS server.
===============================================================================
.PARAMETER ContentPath
    WSUS content path (default: C:\WSUS).
.PARAMETER SqlInstance
    SQL Server instance name (default: .\SQLEXPRESS).
.PARAMETER SkipInstall
    Skip running install.ps1.
.PARAMETER RunContentValidation
    Run Check-WSUSContent.ps1 after install.
.PARAMETER FixContentIssues
    Automatically fix issues found during content validation.
.PARAMETER FixIssues
    Alias for FixContentIssues (kept for backward compatibility).
#>

[CmdletBinding()]
param(
    [string]$ContentPath = "C:\WSUS",
    [string]$SqlInstance = ".\SQLEXPRESS",
    [switch]$SkipInstall,
    [switch]$RunContentValidation,
    [Alias("FixIssues")]
    [switch]$FixContentIssues
)

# Resolve the directory where this script lives so we can call sibling scripts.
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-LocalScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [string[]]$Arguments = @()
    )

    # Guardrail: fail fast if a required script is missing.
    if (-not (Test-Path $Path)) {
        throw "Missing script: $Path"
    }

    # Consistent banners so logs are easy to scan.
    Write-Host "" 
    Write-Host "==============================================================="
    Write-Host $Description
    Write-Host "==============================================================="

    # Execute the script with any arguments passed in.
    & $Path @Arguments
}

# Warn if the user targets the known-bad nested wsuscontent folder.
if ($ContentPath -match "\\wsuscontent$") {
    Write-Warning "ContentPath ends with \\wsuscontent. WSUS expects C:\\WSUS or another root folder, not a nested wsuscontent directory."
}

if (-not $SkipInstall) {
    # Install SQL Express + SSMS + WSUS roles and baseline configuration.
    Invoke-LocalScript -Path (Join-Path $scriptRoot "install.ps1") -Description "Installing SQL Express + SSMS + WSUS"
} else {
    Write-Host "Skipping install.ps1 (SkipInstall specified)."
}

if ($RunContentValidation) {
    # Build arguments for the validation script.
    $contentArgs = @(
        "-ContentPath", $ContentPath,
        "-SqlInstance", $SqlInstance
    )
    if ($FixContentIssues) {
        # Ask the validator to fix issues it finds.
        $contentArgs += "-FixIssues"
    }

    # Validate and optionally repair the WSUS content path setup.
    Invoke-LocalScript -Path (Join-Path $scriptRoot "Check-WSUSContent.ps1") -Description "Validating WSUS content path" -Arguments $contentArgs
} else {
    Write-Host "Skipping Check-WSUSContent.ps1 (RunContentValidation not specified)."
}

# Friendly guidance for follow-up tasks after the main flow finishes.
Write-Host "" 
Write-Host "Setup flow complete. Optional next steps:" 
Write-Host "- Import a SUSDB backup: .\\ImportScript.ps1"
Write-Host "- Run maintenance: .\\WsusMaintenance.ps1"
Write-Host "- Run cleanup: .\\Ultimate-WsusCleanup.ps1"
Write-Host "- Force client check-in: .\\Force-WSUSCheckIn.ps1"
