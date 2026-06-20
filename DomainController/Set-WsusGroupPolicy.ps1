#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusGroupPolicy.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.7.0
Date: 2026-06-19
===============================================================================

.SYNOPSIS
    Import and configure WSUS Group Policy Objects for air-gapped client management.

.DESCRIPTION
    For AIR-GAPPED networks only. Do NOT deploy on internet-connected systems.

    Automates the deployment of four WSUS GPOs on a Domain Controller:
    - WSUS Update Policy - Servers: Configures Windows Update client settings (linked to Domain Controllers + Member Servers)
    - WSUS Update Policy - Workstations: Configures Windows Update client settings (linked to Workstations OU only)
    - WSUS Inbound Allow: Firewall rules for WSUS server (linked to Member Servers\WSUS Server)
    - WSUS Outbound Allow: Firewall rules for clients (linked to Domain Controllers, Member Servers, Workstations)

    The script:
    - Auto-detects the domain
    - Prompts for WSUS server name (if not provided)
    - Replaces hardcoded WSUS URLs with your server
    - Reuses existing OU structures such as Member Servers or Member_Servers
    - Creates child OUs such as WSUS Server when the parent structure already exists

.PARAMETER WsusServerUrl
    WSUS server URL (e.g., http://WSUSServerName:8530).
    If not provided, prompts for server name interactively.

.PARAMETER BackupPath
    Path to GPO backup directory. Defaults to ".\WSUS GPOs" relative to script location.

.PARAMETER MoveWsusServer
    Computer name to move into OU=WSUS Server,OU=Member Servers. Defaults to the hostname
    extracted from -WsusServerUrl (e.g., "WSUS01" from "http://WSUS01:8530"). Skipped
    automatically if the computer is already in the target OU. Use -SkipComputerMove
    to disable the move entirely, or -ForceComputerMove to bypass the [Y/n] prompt.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1
    Prompts for WSUS server name and imports all four GPOs.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
    Imports GPOs using specified WSUS server URL, then prompts to move WSUS01 into
    Member Servers\WSUS Server.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530" -ForceComputerMove
    Same as above but skips the [Y/n] prompt.

.EXAMPLE
    .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530" -SkipComputerMove
    Imports GPOs only; leaves the computer object where it is.

.NOTES
    IMPORTANT: These GPOs are designed for AIR-GAPPED systems only.
    Deploying on internet-connected systems will direct all Windows
    Update traffic to the internal WSUS server and prevent updates
    from Microsoft.

    Requirements:
    - Run on a Domain Controller with Administrator privileges
    - RSAT Group Policy Management tools must be installed
    - WSUS GPOs backup folder must be present in script directory
#>

[CmdletBinding()]
param(
    [string]$WsusServerUrl,
    [string]$BackupPath = (Join-Path $PSScriptRoot "WSUS GPOs"),
    [string]$MoveWsusServer,
    [switch]$SkipComputerMove,
    [switch]$ForceComputerMove
)

#region Helper Functions

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates required PowerShell modules are available.
    #>
    param([string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "  Module '$ModuleName' not found. Installing GPMC feature..." -ForegroundColor Yellow
        try {
            $feature = Add-WindowsFeature GPMC -ErrorAction Stop
            if (-not $feature.Success) { throw "Feature install returned failure." }
            Write-Host "  GPMC installed successfully." -ForegroundColor Green
        } catch {
            throw "Could not install GPMC feature: $_. Run: Add-WindowsFeature GPMC"
        }
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
    Write-Host "WSUS Server Name" -ForegroundColor Cyan
    Write-Host "  Enter just the hostname - the script will build the full URL." -ForegroundColor Gray
    Write-Host "  Example: SRV01  ->  http://SRV01:8530" -ForegroundColor Gray
    Write-Host ""
    $serverName = Read-Host "  Hostname"
    if (-not $serverName) {
        throw "WSUS server name is required."
    }
    $url = "http://$($serverName.Trim()):8530"
    Write-Host "  Using: $url" -ForegroundColor Green
    return $url
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

function Resolve-ExistingOuName {
    <#
    .SYNOPSIS
        Resolves a preferred OU name to an existing variant when one is present.
    .DESCRIPTION
        For legacy domains, "Member Servers" may already exist as either
        "Member Servers" or "Member_Servers". This helper returns the existing
        variant and avoids creating a new top-level OU with the other spelling.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ParentDn
    )

    $candidateNames = @($Name)
    if ($Name -eq 'Member Servers') {
        $candidateNames = @('Member Servers', 'Member_Servers')
    }

    foreach ($candidateName in $candidateNames) {
        $candidateDn = "OU=$candidateName,$ParentDn"
        try {
            $existing = Get-ADOrganizationalUnit -Identity $candidateDn -ErrorAction Stop
            if ($existing) {
                return $candidateName
            }
        } catch {
            Write-Verbose $_.Exception.Message
        }
    }

    return $Name
}

function Assert-OUExists {
    <#
    .SYNOPSIS
        Creates an OU path if it doesn't exist.
    .DESCRIPTION
        Takes an OU path like "Member Servers/WSUS Server" and creates each level if needed.
        For legacy domains with either "Member Servers" or "Member_Servers", the existing
        OU name is reused. If neither exists, this function creates "Member Servers" and
        then creates the requested child OU.
    #>
    param(
        [string]$OUPath,
        [string]$DomainDN
    )

    $parts = $OUPath -split '/'
    $currentDN = $DomainDN

    foreach ($part in $parts) {
        $resolvedPart = Resolve-ExistingOuName -Name $part -ParentDn $currentDN
        $ouDN = "OU=$resolvedPart,$currentDN"

        $exists = $null
        try {
            $exists = Get-ADOrganizationalUnit -Identity $ouDN -ErrorAction Stop
        } catch {
            $exists = $null
        }


        if (-not $exists) {
            Write-Host "  Creating OU: $resolvedPart..." -NoNewline -ForegroundColor Yellow
            New-ADOrganizationalUnit -Name $resolvedPart -Path $currentDN -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
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
        - WSUS Update Policy - Servers: Domain Controllers + Member Servers
        - WSUS Update Policy - Workstations: Workstations OU only
        - WSUS Inbound Allow: WSUS Server OU only (server needs inbound connections)
        - WSUS Outbound Allow: All client OUs (clients need outbound to WSUS)
    #>
    param([string]$DomainDN)

    return @(
        @{
            DisplayName = "WSUS Update Policy - Servers"
            Description = "Client update configuration - applies to Domain Controllers and Member Servers"
            UpdateWsusSettings = $true
            TargetOUPaths = @("Member Servers")
            IncludeDomainControllers = $true
        },
        @{
            DisplayName = "WSUS Update Policy - Workstations"
            Description = "Client update configuration - applies to Workstations only"
            UpdateWsusSettings = $true
            TargetOUPaths = @("Workstations")
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

function Get-GpoTargetOUs {
    <#
    .SYNOPSIS
        Resolves all target OUs for a GPO definition.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$GpoDefinition,

        [Parameter(Mandatory)]
        [string]$DomainDN
    )

    $targetOUs = @()

    if ($GpoDefinition.TargetOUs) {
        $targetOUs += $GpoDefinition.TargetOUs
    }

    if ($GpoDefinition.TargetOUPaths) {
        foreach ($ouPath in $GpoDefinition.TargetOUPaths) {
            $ouDN = Assert-OUExists -OUPath $ouPath -DomainDN $DomainDN
            if ($ouDN) {
                $targetOUs += $ouDN
            }
        }
    }

    if ($GpoDefinition.IncludeDomainControllers) {
        $targetOUs += "OU=Domain Controllers,$DomainDN"
    }

    @($targetOUs | Select-Object -Unique)
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

    # Delete existing GPO and reimport for a clean state (Import-GPO merges
    # and never removes old values, so updating causes stale registry entries)
    $existingGpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue

    $targetOUs = Get-GpoTargetOUs -GpoDefinition $GpoDefinition -DomainDN $DomainDN

    if ($existingGpo) {
        Write-Host "  Removing existing GPO for clean import..." -NoNewline
        foreach ($targetOU in $targetOUs) {
            try {
                $existingLink = Get-GPInheritance -Target $targetOU -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty GpoLinks |
                    Where-Object { $_.DisplayName -eq $gpoName }
                if ($existingLink) {
                    Remove-GPLink -Name $gpoName -Target $targetOU -Confirm:$false -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Verbose "Could not remove existing link for $gpoName on ${targetOU}: $($_.Exception.Message)"
            }
        }
        Remove-GPO -Name $gpoName -ErrorAction Stop | Out-Null
        Write-Host " OK" -ForegroundColor Yellow
    }

    Write-Host "  Importing from backup..." -NoNewline
    $existingGpo = New-GPO -Name $gpoName -ErrorAction Stop
    Import-GPO -BackupId $Backup.Id -Path $BackupPath -TargetName $gpoName -ErrorAction Stop | Out-Null
    Write-Host " OK" -ForegroundColor Green

    # Update WSUS server URLs for Update Policy GPO
    if ($GpoDefinition.UpdateWsusSettings) {
        # Helper: Set-GPRegistryValue occasionally fails with COM E_FAIL when
        # AD/sysvol replication is still settling after Import-GPO. Retry a
        # few times before giving up.
        function Set-GPRegistryValueWithRetry {
            param(
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Key,
                [Parameter(Mandatory)][string]$ValueName,
                [Parameter(Mandatory)][string]$Type,
                [Parameter(Mandatory)]$Value
            )
            $lastError = $null
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                try {
                    Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type $Type -Value $Value -ErrorAction Stop | Out-Null
                    return
                } catch {
                    $lastError = $_
                    Start-Sleep -Seconds 5
                }
            }
            throw $lastError
        }

        Write-Host "  Setting WSUS URL..." -NoNewline
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "WUServer" -Type String -Value $WsusUrl
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "WUStatusServer" -Type String -Value $WsusUrl
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
            -ValueName "UseWUServer" -Type DWord -Value 1
        Write-Host " OK" -ForegroundColor Green

        # Schedule: auto-download and install daily at 22:00
        Write-Host "  Setting install schedule (daily 22:00)..." -NoNewline
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
            -ValueName "AUOptions" -Type DWord -Value 4
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
            -ValueName "ScheduledInstallDay" -Type DWord -Value 0
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
            -ValueName "ScheduledInstallTime" -Type DWord -Value 22
        Write-Host " OK" -ForegroundColor Green

        # Deadline: 7 days to install, auto-restart
        Write-Host "  Setting 7-day deadline with auto-restart..." -NoNewline
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "SetComplianceDeadline" -Type DWord -Value 1
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "ConfigureDeadlineForQualityUpdates" -Type DWord -Value 7
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "ConfigureDeadlineForFeatureUpdates" -Type DWord -Value 7
        Set-GPRegistryValueWithRetry -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" `
            -ValueName "ConfigureDeadlineGracePeriod" -Type DWord -Value 0
        Write-Host " OK" -ForegroundColor Green
    }

    # Remove values baked into the backup that lack ADMX definitions - causes
    # "Extra Registry Settings" warnings in GPMC. Must run AFTER Import-GPO and
    # Set-GPRegistryValue so any re-introduced values are caught.
    $staleValues = @(
        @{ Key = "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU";    Name = "ScheduledInstallEveryWeek" },
        @{ Key = "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate";       Name = "ConfigureDeadlineNoAutoReboot" },
        @{ Key = "HKLM\Software\Policies\Microsoft\WindowsFirewall\DomainProfile"; Name = "EnableFirewall" },
        @{ Key = "HKLM\Software\Policies\Microsoft\WindowsFirewall";             Name = "PolicyVersion" }
    )
    $removed = 0
    foreach ($sv in $staleValues) {
        try {
            $existing = Get-GPRegistryValue -Name $gpoName -Key $sv.Key -ValueName $sv.Name -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-GPRegistryValue -Name $gpoName -Key $sv.Key -ValueName $sv.Name -ErrorAction Stop
                Write-Host "  Removed stale value: $($sv.Name)" -ForegroundColor DarkGray
                $removed++
            }
        } catch {
            Write-Warning "  Could not remove stale value $($sv.Name): $_"
        }
    }
    if ($removed -eq 0) { Write-Host "  No stale registry values found." -ForegroundColor DarkGray }


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

function Push-GPUpdateToAll {
    <#
    .SYNOPSIS
        Forces Group Policy update on all domain computers via scheduled task (no WinRM required).
    .DESCRIPTION
        Uses schtasks.exe over RPC/SMB to create a one-shot SYSTEM task that runs
        'gpupdate /force'. Works on domain machines without WinRM enabled.
    #>
    param([string]$DomainDN)

    Write-Host ""
    Write-Host "Pushing GPO to all domain computers (via schtasks/RPC)..." -ForegroundColor Yellow

    $computers = Get-ADComputer -Filter "Enabled -eq `$true" -SearchBase $DomainDN -ErrorAction SilentlyContinue |
        Where-Object { $_.DistinguishedName -notlike "*OU=Domain Controllers*" }

    $total   = $computers.Count
    $success = 0
    $failed  = 0
    $okList  = @()
    $failList = @()
    $taskName = "WSUS-GpUpdate-Temp"

    Write-Host "  Found $total computers (excluding DCs)"

    foreach ($computer in $computers) {
        $cn = $computer.Name
        $err = $null

        # Advisory ping check (ICMP may be blocked on hardened domains; still attempt schtasks)
        $pingFailed = -not (Test-Connection -ComputerName $cn -Count 1 -Quiet -ErrorAction SilentlyContinue)
        if ($pingFailed) {
            Write-Host "    $cn" -NoNewline
            Write-Host " ping failed, trying RPC..." -ForegroundColor DarkYellow
        }

        try {
            # Create one-shot SYSTEM task, run it, then delete it
            $output = schtasks.exe /create /s $cn /tn $taskName /tr "gpupdate /force /wait:0" /sc once /st 00:00 /f /ru SYSTEM 2>&1
            if ($output -match 'ERROR:|ACCESS_DENIED|RPC.*unavailable|network.*path.*not found') {
                $err = ($output | Where-Object { $_ -match 'ERROR:' }) -join '; '
            }

            if (-not $err) {
                $output = schtasks.exe /run /s $cn /tn $taskName 2>&1
                if ($output -match 'ERROR:') {
                    $err = ($output | Where-Object { $_ -match 'ERROR:' }) -join '; '
                }
                Start-Sleep -Milliseconds 500
            }

            # Always clean up (ignore errors on delete)
            schtasks.exe /delete /s $cn /tn $taskName /f 2>&1 | Out-Null

            if ($err) {
                Write-Host "    $cn" -NoNewline
                Write-Host " FAILED: $err" -ForegroundColor DarkGray
                $failList += "$cn ($err)"
                $failed++
            } else {
                Write-Host "    $cn" -NoNewline
                Write-Host " OK" -ForegroundColor Green
                $okList += $cn
                $success++
            }
        } catch {
            Write-Host "    $cn" -NoNewline
            Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor DarkGray
            $failList += "$cn ($($_.Exception.Message))"
            $failed++
        }
    }

    Write-Host ""
    if ($okList.Count -gt 0) {
        Write-Host "  Pushed OK:  $($okList -join ', ')" -ForegroundColor Green
    }
    if ($failList.Count -gt 0) {
        Write-Host "  Failed:     $($failList -join ', ')" -ForegroundColor Yellow
        Write-Host "  NOTE: Failed computers will apply GPOs within 90 min or on next reboot." -ForegroundColor Gray
    }
    if ($okList.Count -eq 0 -and $failList.Count -eq 0) {
        Write-Host "  No computers found." -ForegroundColor Gray
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays configuration summary and next steps.
    #>
    param(
        [string]$WsusUrl,
        [int]$GpoCount,
        [bool]$MovedComputer
    )

    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host " COMPLETE - $GpoCount GPOs configured" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "WSUS Server: " -NoNewline
    Write-Host $WsusUrl -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    if ($MovedComputer) {
        Write-Host "  1. Verify on clients: gpresult /r | findstr WSUS"
    } else {
        Write-Host "  1. Move WSUS server computer object to: Member Servers\WSUS Server"
        Write-Host "  2. Verify on clients: gpresult /r | findstr WSUS"
    }
    Write-Host ""
    Write-Host "NOTE:" -ForegroundColor Yellow -NoNewline
    Write-Host " Computers outside Domain Controllers, Member Servers, or Workstations"
    Write-Host "      need 'WSUS Outbound Allow' linked manually in GPMC."
    Write-Host ""
}

function Move-WsusServerComputer {
    <#
    .SYNOPSIS
        Moves the WSUS server computer object into OU=WSUS Server,OU=Member Servers so the
        Inbound Allow firewall GPO applies to it. Idempotent: skips if already in target OU.
    .DESCRIPTION
        Interactive [Y/n] prompt unless -Force is passed. Requires the ActiveDirectory
        module (auto-imports it).
    #>
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [string]$DomainDN,
        [string]$TargetOuPath = 'OU=WSUS Server,OU=Member Servers',
        [switch]$Force,
        [switch]$Skip
    )

    if ($Skip) { return $false }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-Warning "  ActiveDirectory module not available. Skipping computer move. Move manually with Move-ADObject."
        return $false
    }

    $targetOuParts = @($TargetOuPath -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_.Substring(3) })
    if ($targetOuParts.Count -gt 0) {
        [array]::Reverse($targetOuParts)
        $targetOuPath = $targetOuParts -join '/'
    } else {
        $targetOuPath = $TargetOuPath
    }

    $targetDn = Assert-OUExists -OUPath $targetOuPath -DomainDN $DomainDN
    if (-not $targetDn) {
        Write-Warning "  Target OU not found and could not be created: $targetOuPath,$DomainDN. Skipping computer move."
        return $false
    }

    $comp = Get-ADComputer -Identity $ComputerName -ErrorAction SilentlyContinue
    if (-not $comp) {
        Write-Warning "  Computer '$ComputerName' not found in AD. Skipping computer move."
        return $false
    }

    if ($comp.DistinguishedName -eq "CN=$ComputerName,$targetDn") {
        Write-Host "  $ComputerName is already in $targetOuPath" -ForegroundColor DarkGray
        return $true
    }

    if (-not $Force) {
        Write-Host ""
        Write-Host "  Move $ComputerName to $targetOuPath ? [Y/n]:" -NoNewline -ForegroundColor Yellow
        $answer = Read-Host
        if ($answer -and $answer -notin @('y','Y','yes','Yes')) {
            Write-Host "  Skipped." -ForegroundColor DarkGray
            return $false
        }
    }

    Write-Host "  Moving $ComputerName ... " -NoNewline
    Move-ADObject -Identity $comp.DistinguishedName -TargetPath $targetDn -ErrorAction Stop
    Write-Host "OK" -ForegroundColor Green
    return $true
}

#endregion

#region Main Script

function Invoke-WsusGroupPolicyImport {
    [CmdletBinding()]
    param(
        [string]$WsusServerUrl,
        [string]$BackupPath = (Join-Path $PSScriptRoot "WSUS GPOs"),
        [string]$MoveWsusServer,
        [switch]$SkipComputerMove,
        [switch]$ForceComputerMove
    )

    try {
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Write-Host "GroupPolicy module not found. Installing GPMC..." -ForegroundColor Yellow
            $r = Add-WindowsFeature GPMC -ErrorAction Stop
            if ($r.RestartNeeded -eq 'Yes') {
                Write-Host "GPMC installed. A restart is required. Please reboot and re-run this script." -ForegroundColor Red
                exit 1
            }
        }
        Import-Module GroupPolicy -ErrorAction Stop
        Write-Host "GroupPolicy module loaded." -ForegroundColor Green

        Test-Prerequisites -ModuleName "GroupPolicy"

        Write-Host ""
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host " WSUS GPO Configuration" -ForegroundColor Cyan
        Write-Host "===============================================================" -ForegroundColor Cyan

        $domainInfo = Get-DomainInfo
        if (-not $domainInfo) {
            throw "Could not detect domain. Run this script on a Domain Controller."
        }
        Write-Host "Domain: $($domainInfo.DomainName)"

        if (-not (Test-Path $BackupPath)) {
            throw "GPO backup path not found: $BackupPath"
        }

        $availableBackups = @()
        Get-ChildItem -Path $BackupPath -Directory | Where-Object { $_.Name -match '^\{[0-9A-Fa-f\-]+\}$' } | ForEach-Object {
            $bkupFile = Join-Path $_.FullName "bkupInfo.xml"
            if (Test-Path $bkupFile) {
                try {
                    [xml]$xml = Get-Content $bkupFile -ErrorAction Stop
                    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
                    $ns.AddNamespace("gp", "http://www.microsoft.com/GroupPolicy/GPOOperations/Manifest")
                    $displayNameNode = $xml.SelectSingleNode("//gp:GPODisplayName", $ns)
                    $displayName = if ($displayNameNode) { $displayNameNode.InnerText } else { $null }
                    $backupId = $_.Name.Trim('{}')
                    if ($displayName) {
                        $availableBackups += [PSCustomObject]@{ Id = $backupId; DisplayName = $displayName }
                    }
                } catch {
                    Write-Warning "Could not parse bkupInfo.xml in $($_.FullName): $_"
                }
            }
        }
        if (-not $availableBackups) {
            throw "No GPO backups found in $BackupPath"
        }
        Write-Host "Backups: $($availableBackups.Count) found"

        $WsusServerUrl = Get-WsusServerUrl -Url $WsusServerUrl
        $gpoDefinitions = Get-GpoDefinitions -DomainDN $domainInfo.DomainDN

        Write-Host ""
        Write-Host "Importing GPOs..." -ForegroundColor Yellow
        Write-Host ""

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

        # Move WSUS server computer object into Member Servers\WSUS Server so the
        # Inbound Allow firewall GPO applies to it. Auto-derives computer name from
        # the WsusServerUrl hostname unless -MoveWsusServer is passed explicitly.
        if (-not $MoveWsusServer -and $WsusServerUrl -match '://([^:/\s]+)') {
            $MoveWsusServer = $Matches[1]
        }
        $movedComputer = $false
        if ($MoveWsusServer -and -not $SkipComputerMove) {
            Write-Host ""
            Write-Host "Moving WSUS server computer object..." -ForegroundColor Yellow
            $movedComputer = Move-WsusServerComputer `
                -ComputerName $MoveWsusServer `
                -DomainDN $domainInfo.DomainDN `
                -Force:$ForceComputerMove
        }

        Show-Summary -WsusUrl $WsusServerUrl -GpoCount $gpoDefinitions.Count -MovedComputer $movedComputer
    } catch {
        Write-Host ""
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-WsusGroupPolicyImport -WsusServerUrl $WsusServerUrl -BackupPath $BackupPath `
        -MoveWsusServer $MoveWsusServer -SkipComputerMove:$SkipComputerMove -ForceComputerMove:$ForceComputerMove
}

#endregion