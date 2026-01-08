#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusGroupPolicy.ps1
Purpose: Import and configure WSUS Group Policy Objects with updated server settings.
Overview:
  - Imports three WSUS-related GPO backups from the WSUS GPOs directory
  - Updates WSUS server URLs in the Update Policy GPO
  - Configures client update settings, firewall rules, and policies
  - Optionally links GPOs to target OUs
GPO Backups Included:
  1. WSUS Update Policy - Client update configuration with WSUS server URLs
  2. WSUS Inbound Allow - Firewall rules for inbound WSUS traffic
  3. WSUS Outbound Allow - Firewall rules for outbound WSUS traffic
Notes:
  - Run as Administrator on a domain controller with RSAT Group Policy Management tools.
  - Requires RSAT Group Policy Management tools (GroupPolicy module).
  - Automatically updates hardcoded server names from backups with new WSUS server URL.
===============================================================================
.PARAMETER WsusServerUrl
    WSUS server URL (e.g. http://WSUSServerName:8530). If not provided, prompts for server name.
.PARAMETER BackupPath
    Path containing GPO backups. Defaults to ".\WSUS GPOs" in the script directory.
.PARAMETER TargetOU
    Optional distinguished name of the OU to link the GPOs to.
.PARAMETER ImportAll
    Import all three WSUS GPOs (Update Policy, Inbound Allow, Outbound Allow). Default: $true.
#>

[CmdletBinding()]
param(
    [string]$WsusServerUrl,
    [string]$BackupPath = (Join-Path $PSScriptRoot "WSUS GPOs"),
    [string]$TargetOU,
    [switch]$ImportAll = $true
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

# Prompt for WSUS server URL if not provided
if (-not $WsusServerUrl) {
    $wsusServerName = Read-Host "Enter WSUS server name (e.g. WSUSServerName)"
    if (-not $wsusServerName) {
        throw "WSUS server name is required."
    }
    $WsusServerUrl = "http://$wsusServerName:8530"
}

Write-Host "WSUS Server URL: $WsusServerUrl"
Write-Host "GPO Backup Path: $BackupPath"
Write-Host ""

# Verify backup path exists
if (-not (Test-Path $BackupPath)) {
    throw "GPO backup path not found: $BackupPath"
}

# Define the three GPOs to import
$gpoDefinitions = @(
    @{
        DisplayName = "WSUS Update Policy"
        Description = "Client update configuration with WSUS server URLs"
        UpdateWsusSettings = $true
    },
    @{
        DisplayName = "WSUS Inbound Allow"
        Description = "Firewall rules for inbound WSUS traffic"
        UpdateWsusSettings = $false
    },
    @{
        DisplayName = "WSUS Outbound Allow"
        Description = "Firewall rules for outbound WSUS traffic"
        UpdateWsusSettings = $false
    }
)

# Get all available backups from the backup path
Write-Host "Scanning for GPO backups..."
$availableBackups = Get-GPOBackup -Path $BackupPath -ErrorAction SilentlyContinue
if (-not $availableBackups) {
    throw "No GPO backups found in $BackupPath"
}
Write-Host "Found $($availableBackups.Count) GPO backup(s)"
Write-Host ""

# Process each GPO definition
foreach ($gpoDef in $gpoDefinitions) {
    $gpoName = $gpoDef.DisplayName
    Write-Host "-----------------------------------------------------------"
    Write-Host "Processing: $gpoName"
    Write-Host "Purpose: $($gpoDef.Description)"
    Write-Host "-----------------------------------------------------------"

    # Find matching backup
    $backup = $availableBackups | Where-Object { $_.DisplayName -eq $gpoName } | Select-Object -First 1

    if (-not $backup) {
        Write-Warning "No backup found for '$gpoName'. Skipping..."
        continue
    }

    # Check if GPO already exists
    $existingGpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue

    if ($existingGpo) {
        Write-Host "GPO already exists. Updating from backup..."
        Import-GPO -BackupId $backup.Id -Path $BackupPath -TargetName $gpoName -ErrorAction Stop | Out-Null
    } else {
        Write-Host "Creating new GPO from backup..."
        $existingGpo = New-GPO -Name $gpoName -ErrorAction Stop
        Import-GPO -BackupId $backup.Id -Path $BackupPath -TargetName $gpoName -ErrorAction Stop | Out-Null
    }

    # Update WSUS server URLs if this is the Update Policy GPO
    if ($gpoDef.UpdateWsusSettings) {
        Write-Host "Updating WSUS server settings to: $WsusServerUrl"
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "WUServer" -Type String -Value $WsusServerUrl -ErrorAction Stop
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "WUStatusServer" -Type String -Value $WsusServerUrl -ErrorAction Stop
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "UseWUServer" -Type DWord -Value 1 -ErrorAction Stop
    }

    # Link to target OU if specified
    if ($TargetOU) {
        $existingLink = Get-GPInheritance -Target $TargetOU -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty GpoLinks |
            Where-Object { $_.DisplayName -eq $gpoName }

        if ($existingLink) {
            Write-Host "GPO already linked to OU: $TargetOU"
        } else {
            Write-Host "Linking GPO to OU: $TargetOU"
            New-GPLink -Name $gpoName -Target $TargetOU -LinkEnabled Yes -ErrorAction Stop | Out-Null
        }
    }

    Write-Host "Successfully configured: $gpoName"
    Write-Host ""
}

Write-Host "==============================================================="
Write-Host "All WSUS GPOs have been configured successfully!"
Write-Host "==============================================================="
Write-Host ""
Write-Host "Summary:"
Write-Host "- WSUS Server URL: $WsusServerUrl"
Write-Host "- GPOs Configured: $($gpoDefinitions.Count)"
if ($TargetOU) {
    Write-Host "- Linked to OU: $TargetOU"
}
Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Run 'gpupdate /force' on client machines to apply policies"
Write-Host "2. Verify client check-in with: wuauclt /detectnow /reportnow"
Write-Host "3. Check WSUS console for client registrations"
Write-Host ""
