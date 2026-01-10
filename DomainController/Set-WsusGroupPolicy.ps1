#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusGroupPolicy.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.4.0
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

    Write-Host ""
    Write-Host "WSUS Server Name" -ForegroundColor Yellow
    $serverName = Read-Host "  Enter hostname (e.g., WSUS01)"
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
            Write-Host "  Creating OU: $part..." -NoNewline -ForegroundColor Yellow
            New-ADOrganizationalUnit -Name $part -Path $currentDN -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
            Write-Host " OK" -ForegroundColor Green
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

    Write-Host "[$gpoName]" -ForegroundColor Cyan
    Write-Host "  $($GpoDefinition.Description)" -ForegroundColor Gray

    # Create or update GPO from backup
    $existingGpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue

    if ($existingGpo) {
        Write-Host "  Updating from backup..." -NoNewline
    } else {
        Write-Host "  Creating from backup..." -NoNewline
        $existingGpo = New-GPO -Name $gpoName -ErrorAction Stop
    }

    Import-GPO -BackupId $Backup.Id -Path $BackupPath -TargetName $gpoName -ErrorAction Stop | Out-Null
    Write-Host " OK" -ForegroundColor Green

    # Update WSUS server URLs for Update Policy GPO
    if ($GpoDefinition.UpdateWsusSettings) {
        Write-Host "  Setting WSUS URL..." -NoNewline
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "WUServer" -Type String -Value $WsusUrl -ErrorAction Stop
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "WUStatusServer" -Type String -Value $WsusUrl -ErrorAction Stop
        Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
            -ValueName "UseWUServer" -Type DWord -Value 1 -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
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
    Write-Host "  Linking:" -ForegroundColor Gray
    foreach ($targetOU in $targetOUs) {
        # Shorten the DN for display (show just the OU path, not full DN)
        $shortOU = ($targetOU -replace ',DC=.*$', '') -replace 'OU=', '' -replace ',', '\'
        if ($targetOU -eq $DomainDN) { $shortOU = "(Domain Root)" }

        $existingLink = Get-GPInheritance -Target $targetOU -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty GpoLinks |
            Where-Object { $_.DisplayName -eq $gpoName }

        if ($existingLink) {
            Write-Host "    $shortOU" -NoNewline
            Write-Host " (exists)" -ForegroundColor DarkGray
        } else {
            Write-Host "    $shortOU" -NoNewline
            New-GPLink -Name $gpoName -Target $targetOU -LinkEnabled Yes -ErrorAction Stop | Out-Null
            Write-Host " OK" -ForegroundColor Green
        }
    }
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

    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host " COMPLETE - $GpoCount GPOs configured" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "WSUS Server: " -NoNewline
    Write-Host $WsusUrl -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Move WSUS server computer object to: Member Servers\WSUS Server"
    Write-Host "  2. Run 'gpupdate /force' on clients"
    Write-Host "  3. Verify: wuauclt /detectnow /reportnow"
    Write-Host ""
    Write-Host "NOTE:" -ForegroundColor Yellow -NoNewline
    Write-Host " Computers outside Domain Controllers, Member Servers, or Workstations"
    Write-Host "      need 'WSUS Outbound Allow' linked manually in GPMC."
    Write-Host ""
}

#endregion

#region Main Script

try {
    # Validate prerequisites
    Test-Prerequisites -ModuleName "GroupPolicy"

    # Display banner
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host " WSUS GPO Configuration" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan

    # Auto-detect domain
    $domainInfo = Get-DomainInfo
    if (-not $domainInfo) {
        throw "Could not detect domain. Run this script on a Domain Controller."
    }
    Write-Host "Domain: $($domainInfo.DomainName)"

    # Verify backup path exists
    if (-not (Test-Path $BackupPath)) {
        throw "GPO backup path not found: $BackupPath"
    }

    # Scan for available backups
    $availableBackups = Get-GPOBackup -Path $BackupPath -ErrorAction SilentlyContinue
    if (-not $availableBackups) {
        throw "No GPO backups found in $BackupPath"
    }
    Write-Host "Backups: $($availableBackups.Count) found"

    # Get WSUS server URL (prompt if not provided)
    $WsusServerUrl = Get-WsusServerUrl -Url $WsusServerUrl

    # Load GPO definitions with domain-specific target OUs
    $gpoDefinitions = Get-GpoDefinitions -DomainDN $domainInfo.DomainDN

    Write-Host ""
    Write-Host "Importing GPOs..." -ForegroundColor Yellow
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
