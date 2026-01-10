#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusGroupPolicy.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.3.0
Date: 2026-01-10
===============================================================================

.SYNOPSIS
    Import and configure WSUS Group Policy Objects for client management.

.DESCRIPTION
    Automates the deployment of three WSUS GPOs on a Domain Controller:
    - WSUS Update Policy: Configures Windows Update client settings (linked to domain root)
    - WSUS Inbound Allow: Firewall rules for WSUS server (linked to Member Servers\WSUS Server)
    - WSUS Outbound Allow: Firewall rules for clients (linked to Domain Controllers, Member Servers, Workstations)

    The script:
    - Auto-detects the domain
    - Prompts for WSUS server name (if not provided)
    - Replaces hardcoded WSUS URLs with your server
    - Creates required OUs if they don't exist
    - Links each GPO to its appropriate OU(s)

.PARAMETER WsusServerUrl
    WSUS server URL (e.g., http://WSUSServerName:8530).
    If not provided, prompts for server name interactively.

.PARAMETER BackupPath
    Path to GPO backup directory. Defaults to ".\WSUS GPOs" relative to script location.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1
    Prompts for WSUS server name and imports all three GPOs.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
    Imports GPOs using specified WSUS server URL.

.NOTES
    Requirements:
    - Run on a Domain Controller with Administrator privileges
    - RSAT Group Policy Management tools must be installed
    - WSUS GPOs backup folder must be present in script directory
#>

[CmdletBinding()]
param(
    [string]$WsusServerUrl,
    [string]$BackupPath = (Join-Path $PSScriptRoot "WSUS GPOs")
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

function Ensure-OUExists {
    <#
    .SYNOPSIS
        Creates an OU path if it doesn't exist.
    .DESCRIPTION
        Takes an OU path like "Member Servers/WSUS Server" and creates each level if needed.
    #>
    param(
        [string]$OUPath,
        [string]$DomainDN
    )

    # Split path into parts (e.g., "Member Servers/WSUS Server" -> @("Member Servers", "WSUS Server"))
    $parts = $OUPath -split '/'

    $currentDN = $DomainDN

    foreach ($part in $parts) {
        $ouDN = "OU=$part,$currentDN"

        # Check if OU exists
        $exists = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue

        if (-not $exists) {
            Write-Host "  Creating OU: $part" -ForegroundColor Yellow
            New-ADOrganizationalUnit -Name $part -Path $currentDN -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        }

        $currentDN = $ouDN
    }

    return $currentDN
}

function Get-GpoDefinitions {
    <#
    .SYNOPSIS
        Returns array of GPO definitions with their target OUs.
    .DESCRIPTION
        Each GPO has specific OUs it should be linked to:
        - WSUS Update Policy: Domain root (all computers get update settings)
        - WSUS Inbound Allow: WSUS Server OU only (server needs inbound connections)
        - WSUS Outbound Allow: All client OUs (clients need outbound to WSUS)
    #>
    param([string]$DomainDN)

    return @(
        @{
            DisplayName = "WSUS Update Policy"
            Description = "Client update configuration - applies to all computers"
            UpdateWsusSettings = $true
            TargetOUs = @($DomainDN)  # Domain root
        },
        @{
            DisplayName = "WSUS Inbound Allow"
            Description = "Firewall inbound rules - applies to WSUS server only"
            UpdateWsusSettings = $false
            TargetOUPaths = @("Member Servers/WSUS Server")  # Will be created if needed
        },
        @{
            DisplayName = "WSUS Outbound Allow"
            Description = "Firewall outbound rules - applies to all clients"
            UpdateWsusSettings = $false
            TargetOUPaths = @("Member Servers", "Workstations")  # Client OUs
            IncludeDomainControllers = $true  # Also link to Domain Controllers
        }
    )
}

function Import-WsusGpo {
    <#
    .SYNOPSIS
        Processes a single GPO: creates or updates from backup, updates WSUS URLs, and links to OUs.
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

        [Parameter(Mandatory)]
        [string]$DomainDN
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

    # Build list of target OUs
    $targetOUs = @()

    # Add direct OU DNs if specified
    if ($GpoDefinition.TargetOUs) {
        $targetOUs += $GpoDefinition.TargetOUs
    }

    # Create and add OUs from paths (e.g., "Member Servers/WSUS Server")
    if ($GpoDefinition.TargetOUPaths) {
        foreach ($ouPath in $GpoDefinition.TargetOUPaths) {
            $ouDN = Ensure-OUExists -OUPath $ouPath -DomainDN $DomainDN
            $targetOUs += $ouDN
        }
    }

    # Add Domain Controllers OU if specified
    if ($GpoDefinition.IncludeDomainControllers) {
        $targetOUs += "OU=Domain Controllers,$DomainDN"
    }

    # Link to each target OU
    foreach ($targetOU in $targetOUs) {
        $existingLink = Get-GPInheritance -Target $targetOU -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty GpoLinks |
            Where-Object { $_.DisplayName -eq $gpoName }

        if ($existingLink) {
            Write-Host "  Already linked: $targetOU"
        } else {
            Write-Host "  Linking to: $targetOU" -ForegroundColor Green
            New-GPLink -Name $gpoName -Target $targetOU -LinkEnabled Yes -ErrorAction Stop | Out-Null
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
        [int]$GpoCount
    )

    Write-Host "==============================================================="
    Write-Host "All WSUS GPOs have been configured successfully!"
    Write-Host "==============================================================="
    Write-Host ""
    Write-Host "Summary:"
    Write-Host "- WSUS Server URL: $WsusUrl"
    Write-Host "- GPOs Configured: $GpoCount"
    Write-Host ""
    Write-Host "GPO Linking:"
    Write-Host "- WSUS Update Policy    -> Domain root (all computers)"
    Write-Host "- WSUS Inbound Allow    -> Member Servers\WSUS Server"
    Write-Host "- WSUS Outbound Allow   -> Domain Controllers, Member Servers, Workstations"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Move your WSUS server to: OU=WSUS Server,OU=Member Servers"
    Write-Host "2. Run 'gpupdate /force' on client machines"
    Write-Host "3. Verify client check-in: wuauclt /detectnow /reportnow"
    Write-Host "4. Check WSUS console for client registrations"
    Write-Host ""
    Write-Host "NOTE: If you have computers in OUs other than Domain Controllers," -ForegroundColor Yellow
    Write-Host "      Member Servers, or Workstations, manually link the" -ForegroundColor Yellow
    Write-Host "      'WSUS Outbound Allow' GPO to those OUs in GPMC." -ForegroundColor Yellow
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
    Write-Host ""

    # Verify backup path exists
    if (-not (Test-Path $BackupPath)) {
        throw "GPO backup path not found: $BackupPath"
    }

    # Load GPO definitions with domain-specific target OUs
    $gpoDefinitions = Get-GpoDefinitions -DomainDN $domainInfo.DomainDN

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
                       -DomainDN $domainInfo.DomainDN
    }

    # Display summary
    Show-Summary -WsusUrl $WsusServerUrl -GpoCount $gpoDefinitions.Count

} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

#endregion
