#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusGroupPolicy.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.2.0
Date: 2026-01-10
===============================================================================

.SYNOPSIS
    Import and configure WSUS Group Policy Objects for client management.

.DESCRIPTION
    Automates the deployment of three WSUS GPOs on a Domain Controller:
    - WSUS Update Policy: Configures Windows Update client settings
    - WSUS Inbound Allow: Firewall rules for inbound WSUS traffic
    - WSUS Outbound Allow: Firewall rules for outbound WSUS traffic

    The script:
    - Auto-detects the domain
    - Prompts for WSUS server name (if not provided)
    - Replaces hardcoded WSUS URLs with your server
    - Links all GPOs to domain root (applies to all computers)

.PARAMETER WsusServerUrl
    WSUS server URL (e.g., http://WSUSServerName:8530).
    If not provided, prompts for server name interactively.

.PARAMETER BackupPath
    Path to GPO backup directory. Defaults to ".\WSUS GPOs" relative to script location.

.PARAMETER TargetOU
    Optional OU to link GPOs. Defaults to domain root (all computers).

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1
    Prompts for WSUS server name and imports all three GPOs.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
    Imports GPOs using specified WSUS server URL.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530" -TargetOU "OU=Workstations,DC=example,DC=local"
    Imports GPOs and links them to the specified OU.

.NOTES
    Requirements:
    - Run on a Domain Controller with Administrator privileges
    - RSAT Group Policy Management tools must be installed
    - WSUS GPOs backup folder must be present in script directory
#>

[CmdletBinding()]
param(
    [string]$WsusServerUrl,
    [string]$BackupPath = (Join-Path $PSScriptRoot "WSUS GPOs"),
    [string]$TargetOU
)

#region Helper Functions

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates required PowerShell modules are available.
    #>
    param([string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        throw "Required module '$ModuleName' not found. Install RSAT Group Policy Management tools."
    }
    Import-Module $ModuleName -ErrorAction Stop
}

function Get-WsusServerUrl {
    <#
    .SYNOPSIS
        Prompts for WSUS server name if not provided via parameter.
    #>
    param([string]$Url)

    if ($Url) {
        return $Url
    }

    $serverName = Read-Host "Enter WSUS server name (e.g., WSUSServerName)"
    if (-not $serverName) {
        throw "WSUS server name is required."
    }
    return "http://$serverName:8530"
}

function Get-DomainInfo {
    <#
    .SYNOPSIS
        Auto-detects domain information from Active Directory.
    #>
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain -ErrorAction Stop
        return @{
            DomainDN = $domain.DistinguishedName
            DomainName = $domain.DNSRoot
            NetBIOSName = $domain.NetBIOSName
        }
    } catch {
        # Fallback to environment variable
        $dnsDomain = $env:USERDNSDOMAIN
        if ($dnsDomain) {
            $domainDN = ($dnsDomain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
            return @{
                DomainDN = $domainDN
                DomainName = $dnsDomain
                NetBIOSName = $env:USERDOMAIN
            }
        }
        return $null
    }
}

function Get-GpoDefinitions {
    <#
    .SYNOPSIS
        Returns array of GPO definitions to process.
    #>
    return @(
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
}

function Import-WsusGpo {
    <#
    .SYNOPSIS
        Processes a single GPO: creates or updates from backup, updates WSUS URLs, and links to OU.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$GpoDefinition,

        [Parameter(Mandatory)]
        [object]$Backup,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [string]$WsusUrl,

        [string]$TargetOU
    )

    $gpoName = $GpoDefinition.DisplayName

    Write-Host "-----------------------------------------------------------"
    Write-Host "Processing: $gpoName"
    Write-Host "Purpose: $($GpoDefinition.Description)"
    Write-Host "-----------------------------------------------------------"

    # Create or update GPO from backup
    $existingGpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue

    if ($existingGpo) {
        Write-Host "GPO already exists. Updating from backup..."
    } else {
        Write-Host "Creating new GPO from backup..."
        $existingGpo = New-GPO -Name $gpoName -ErrorAction Stop
    }

    Import-GPO -BackupId $Backup.Id -Path $BackupPath -TargetName $gpoName -ErrorAction Stop | Out-Null

    # Update WSUS server URLs for Update Policy GPO
    if ($GpoDefinition.UpdateWsusSettings) {
        Write-Host "Updating WSUS server settings to: $WsusUrl"
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "WUServer" -Type String -Value $WsusUrl -ErrorAction Stop
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "WUStatusServer" -Type String -Value $WsusUrl -ErrorAction Stop
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
            -ValueName "UseWUServer" -Type DWord -Value 1 -ErrorAction Stop
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

function Show-Summary {
    <#
    .SYNOPSIS
        Displays configuration summary and next steps.
    #>
    param(
        [string]$WsusUrl,
        [int]$GpoCount,
        [string]$TargetOU
    )

    Write-Host "==============================================================="
    Write-Host "All WSUS GPOs have been configured successfully!"
    Write-Host "==============================================================="
    Write-Host ""
    Write-Host "Summary:"
    Write-Host "- WSUS Server URL: $WsusUrl"
    Write-Host "- GPOs Configured: $GpoCount"
    if ($TargetOU) {
        Write-Host "- Linked to OU: $TargetOU"
    }
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Run 'gpupdate /force' on client machines to apply policies"
    Write-Host "2. Verify client check-in: wuauclt /detectnow /reportnow"
    Write-Host "3. Check WSUS console for client registrations"
    Write-Host ""
}

#endregion

#region Main Script

try {
    # Validate prerequisites
    Test-Prerequisites -ModuleName "GroupPolicy"

    # Display banner
    Write-Host ""
    Write-Host "==============================================================="
    Write-Host "WSUS GPO Configuration"
    Write-Host "==============================================================="

    # Auto-detect domain
    $domainInfo = Get-DomainInfo
    if (-not $domainInfo) {
        throw "Could not detect domain. Run this script on a Domain Controller."
    }
    Write-Host "Domain: $($domainInfo.DomainName)" -ForegroundColor Cyan

    # Get WSUS server URL (prompt if not provided)
    $WsusServerUrl = Get-WsusServerUrl -Url $WsusServerUrl

    Write-Host "WSUS Server URL: $WsusServerUrl"
    Write-Host "GPO Backup Path: $BackupPath"

    # Verify backup path exists
    if (-not (Test-Path $BackupPath)) {
        throw "GPO backup path not found: $BackupPath"
    }

    # Auto-link to domain root if not specified
    if (-not $TargetOU) {
        $TargetOU = $domainInfo.DomainDN
        Write-Host "Linking GPOs to: $TargetOU" -ForegroundColor Cyan
    }

    Write-Host ""

    # Load GPO definitions
    $gpoDefinitions = Get-GpoDefinitions

    # Scan for available backups
    Write-Host "Scanning for GPO backups..."
    $availableBackups = Get-GPOBackup -Path $BackupPath -ErrorAction SilentlyContinue
    if (-not $availableBackups) {
        throw "No GPO backups found in $BackupPath"
    }
    Write-Host "Found $($availableBackups.Count) GPO backup(s)"
    Write-Host ""

    # Process each GPO
    foreach ($gpoDef in $gpoDefinitions) {
        $backup = $availableBackups | Where-Object { $_.DisplayName -eq $gpoDef.DisplayName } | Select-Object -First 1

        if (-not $backup) {
            Write-Warning "No backup found for '$($gpoDef.DisplayName)'. Skipping..."
            continue
        }

        Import-WsusGpo -GpoDefinition $gpoDef `
                       -Backup $backup `
                       -BackupPath $BackupPath `
                       -WsusUrl $WsusServerUrl `
                       -TargetOU $TargetOU
    }

    # Display summary
    Show-Summary -WsusUrl $WsusServerUrl -GpoCount $gpoDefinitions.Count -TargetOU $TargetOU

} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

#endregion
