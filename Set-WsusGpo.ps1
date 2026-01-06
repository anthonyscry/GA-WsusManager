#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusGpo.ps1
Purpose: Create or import WSUS client GPOs and apply WSUS policy settings.
Overview:
  - Imports a GPO backup when provided, or creates a new GPO when missing.
  - Sets WSUS policy values (WUServer, WUStatusServer, UseWUServer).
  - Optionally links the GPO to a target OU.
Notes:
  - Requires RSAT Group Policy Management tools (GroupPolicy module).
===============================================================================
.PARAMETER GpoName
    Name of the GPO to create or import.
.PARAMETER WsusServerUrl
    WSUS server URL (e.g. http://WSUSServerName:8530).
.PARAMETER BackupPath
    Optional path containing GPO backups to import.
.PARAMETER TargetOU
    Optional distinguished name of the OU to link the GPO to.
#>

[CmdletBinding()]
param(
    [string]$GpoName = "WSUS - Client Settings",
    [string]$WsusServerUrl,
    [string]$BackupPath,
    [string]$TargetOU
)

function Assert-Module {
    param([string]$Name)
    # Ensure required modules are available before continuing.
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        throw "Required module '$Name' not found. Install RSAT Group Policy Management tools."
    }
    # Import the module so cmdlets like New-GPO and Set-GPRegistryValue are available.
    Import-Module $Name -ErrorAction Stop
}

# GroupPolicy module is required for all GPO operations.
Assert-Module -Name GroupPolicy

Write-Host "" 
Write-Host "==============================================================="
Write-Host "WSUS GPO Configuration"
Write-Host "==============================================================="
if (-not $WsusServerUrl) {
    $wsusServerName = Read-Host "Enter WSUS server name (e.g. WSUSServerName)"
    if (-not $wsusServerName) {
        throw "WSUS server name is required."
    }
    $WsusServerUrl = "http://$wsusServerName:8530"
}

Write-Host "GPO Name: $GpoName"
Write-Host "WSUS URL: $WsusServerUrl"

# Try to locate an existing GPO with the requested name.
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

if ($BackupPath -and (Test-Path $BackupPath)) {
    # Look for a matching GPO backup by DisplayName.
    $backup = Get-GPOBackup -Path $BackupPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $GpoName } | Select-Object -First 1
    if ($backup) {
        if (-not $gpo) {
            # Create the target GPO before importing the backup settings.
            Write-Host "Creating GPO $GpoName from backup..."
            $gpo = New-GPO -Name $GpoName
        }

        # Import the backed-up settings into the target GPO.
        Write-Host "Importing GPO settings from backup: $($backup.Id)"
        Import-GPO -BackupId $backup.Id -Path $BackupPath -TargetName $GpoName -CreateIfNeeded -ErrorAction Stop | Out-Null
    } else {
        Write-Warning "No GPO backup named '$GpoName' found in $BackupPath. Creating a new GPO instead."
    }
}

if (-not $gpo) {
    # Create a new GPO if none exists and no backup was imported.
    Write-Host "Creating new GPO: $GpoName"
    $gpo = New-GPO -Name $GpoName
}

Write-Host "Applying WSUS policy settings..."

# Configure WSUS client policies (registry-based policies).
Set-GPRegistryValue -Name $GpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "WUServer" -Type String -Value $WsusServerUrl
Set-GPRegistryValue -Name $GpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "WUStatusServer" -Type String -Value $WsusServerUrl
Set-GPRegistryValue -Name $GpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "UseWUServer" -Type DWord -Value 1

if ($TargetOU) {
    # Optionally link the GPO to a target OU so it applies to clients.
    Write-Host "Linking GPO to OU: $TargetOU"
    New-GPLink -Name $GpoName -Target $TargetOU -LinkEnabled Yes | Out-Null
}

Write-Host "" 
Write-Host "GPO configuration complete."
