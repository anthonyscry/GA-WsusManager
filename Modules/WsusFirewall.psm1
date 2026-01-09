<#
===============================================================================
Module: WsusFirewall.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS firewall rule management functions

.DESCRIPTION
    Provides standardized functions for creating, verifying, and managing
    Windows Firewall rules for WSUS and SQL Server
#>

# ===========================
# FIREWALL RULE DEFINITIONS
# ===========================

$script:WsusFirewallRules = @(
    @{
        DisplayName = "WSUS HTTP Traffic (Port 8530)"
        Direction = "Inbound"
        Protocol = "TCP"
        LocalPort = 8530
        Action = "Allow"
        Profile = "Domain,Private,Public"
        Description = "Allows inbound HTTP traffic for WSUS client connections"
    },
    @{
        DisplayName = "WSUS HTTPS Traffic (Port 8531)"
        Direction = "Inbound"
        Protocol = "TCP"
        LocalPort = 8531
        Action = "Allow"
        Profile = "Domain,Private,Public"
        Description = "Allows inbound HTTPS traffic for WSUS client connections"
    }
)

$script:SqlFirewallRules = @(
    @{
        DisplayName = "SQL Server (TCP 1433)"
        Direction = "Inbound"
        Protocol = "TCP"
        LocalPort = 1433
        Action = "Allow"
        Profile = "Domain,Private"
        Description = "Allows inbound SQL Server connections"
    },
    @{
        DisplayName = "SQL Browser (UDP 1434)"
        Direction = "Inbound"
        Protocol = "UDP"
        LocalPort = 1434
        Action = "Allow"
        Profile = "Domain,Private"
        Description = "Allows SQL Server Browser service"
    }
)

# ===========================
# FIREWALL RULE MANAGEMENT FUNCTIONS
# ===========================

function New-WsusFirewallRule {
    <#
    .SYNOPSIS
        Creates a single firewall rule

    .PARAMETER DisplayName
        Display name for the firewall rule

    .PARAMETER Direction
        Inbound or Outbound

    .PARAMETER Protocol
        TCP or UDP

    .PARAMETER LocalPort
        Port number

    .PARAMETER Action
        Allow or Block

    .PARAMETER Profile
        Firewall profiles (Domain, Private, Public)

    .PARAMETER Description
        Rule description

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Inbound", "Outbound")]
        [string]$Direction,

        [Parameter(Mandatory = $true)]
        [ValidateSet("TCP", "UDP")]
        [string]$Protocol,

        [Parameter(Mandatory = $true)]
        [int]$LocalPort,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Allow", "Block")]
        [string]$Action,

        [string]$Profile = "Domain,Private",

        [string]$Description = ""
    )

    try {
        # Remove existing rule if it exists
        Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue

        # Create new rule
        New-NetFirewallRule -DisplayName $DisplayName `
            -Direction $Direction `
            -Protocol $Protocol `
            -LocalPort $LocalPort `
            -Action $Action `
            -Profile $Profile `
            -Description $Description `
            -ErrorAction Stop | Out-Null

        Write-Host "  Created: $DisplayName" -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "  Failed to create rule '$DisplayName': $($_.Exception.Message)"
        return $false
    }
}

function Test-WsusFirewallRule {
    <#
    .SYNOPSIS
        Checks if a firewall rule exists

    .PARAMETER DisplayName
        Display name of the firewall rule

    .OUTPUTS
        Boolean indicating if rule exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    try {
        $rule = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction Stop
        return ($null -ne $rule)
    } catch {
        return $false
    }
}

function Remove-WsusFirewallRule {
    <#
    .SYNOPSIS
        Removes a firewall rule

    .PARAMETER DisplayName
        Display name of the firewall rule

    .OUTPUTS
        Boolean indicating success
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    try {
        Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction Stop |
            Remove-NetFirewallRule -ErrorAction Stop

        Write-Host "  Removed: $DisplayName" -ForegroundColor Yellow
        return $true
    } catch {
        return $false
    }
}

# ===========================
# WSUS-SPECIFIC FIREWALL FUNCTIONS
# ===========================

function Initialize-WsusFirewallRules {
    <#
    .SYNOPSIS
        Creates all standard WSUS firewall rules

    .OUTPUTS
        Hashtable with creation results
    #>
    Write-Host "Configuring WSUS firewall rules..." -ForegroundColor Cyan

    $results = @{
        Created = @()
        Failed = @()
    }

    foreach ($rule in $script:WsusFirewallRules) {
        $success = New-WsusFirewallRule @rule

        if ($success) {
            $results.Created += $rule.DisplayName
        } else {
            $results.Failed += $rule.DisplayName
        }
    }

    if ($results.Failed.Count -eq 0) {
        Write-Host "All WSUS firewall rules created successfully" -ForegroundColor Green
    } else {
        Write-Warning "Some firewall rules failed to create"
    }

    return $results
}

function Initialize-SqlFirewallRules {
    <#
    .SYNOPSIS
        Creates all standard SQL Server firewall rules

    .OUTPUTS
        Hashtable with creation results
    #>
    Write-Host "Configuring SQL Server firewall rules..." -ForegroundColor Cyan

    $results = @{
        Created = @()
        Failed = @()
    }

    foreach ($rule in $script:SqlFirewallRules) {
        $success = New-WsusFirewallRule @rule

        if ($success) {
            $results.Created += $rule.DisplayName
        } else {
            $results.Failed += $rule.DisplayName
        }
    }

    if ($results.Failed.Count -eq 0) {
        Write-Host "All SQL Server firewall rules created successfully" -ForegroundColor Green
    } else {
        Write-Warning "Some firewall rules failed to create"
    }

    return $results
}

function Test-AllWsusFirewallRules {
    <#
    .SYNOPSIS
        Checks if all WSUS firewall rules exist

    .OUTPUTS
        Hashtable with rule status
    #>
    $results = @{
        AllPresent = $true
        Present = @()
        Missing = @()
    }

    foreach ($rule in $script:WsusFirewallRules) {
        if (Test-WsusFirewallRule -DisplayName $rule.DisplayName) {
            $results.Present += $rule.DisplayName
        } else {
            $results.Missing += $rule.DisplayName
            $results.AllPresent = $false
        }
    }

    return $results
}

function Test-AllSqlFirewallRules {
    <#
    .SYNOPSIS
        Checks if all SQL Server firewall rules exist

    .OUTPUTS
        Hashtable with rule status
    #>
    $results = @{
        AllPresent = $true
        Present = @()
        Missing = @()
    }

    foreach ($rule in $script:SqlFirewallRules) {
        if (Test-WsusFirewallRule -DisplayName $rule.DisplayName) {
            $results.Present += $rule.DisplayName
        } else {
            $results.Missing += $rule.DisplayName
            $results.AllPresent = $false
        }
    }

    return $results
}

function Repair-WsusFirewallRules {
    <#
    .SYNOPSIS
        Checks and creates any missing WSUS firewall rules

    .OUTPUTS
        Hashtable with repair results
    #>
    Write-Host "Checking WSUS firewall rules..." -ForegroundColor Cyan

    $check = Test-AllWsusFirewallRules

    if ($check.AllPresent) {
        Write-Host "All WSUS firewall rules are present" -ForegroundColor Green
        return @{ Repaired = @(); AlreadyPresent = $check.Present }
    }

    Write-Host "Missing firewall rules detected, creating..." -ForegroundColor Yellow
    $check.Missing | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Red
    }

    return Initialize-WsusFirewallRules
}

function Repair-SqlFirewallRules {
    <#
    .SYNOPSIS
        Checks and creates any missing SQL Server firewall rules

    .OUTPUTS
        Hashtable with repair results
    #>
    Write-Host "Checking SQL Server firewall rules..." -ForegroundColor Cyan

    $check = Test-AllSqlFirewallRules

    if ($check.AllPresent) {
        Write-Host "All SQL Server firewall rules are present" -ForegroundColor Green
        return @{ Repaired = @(); AlreadyPresent = $check.Present }
    }

    Write-Host "Missing firewall rules detected, creating..." -ForegroundColor Yellow
    $check.Missing | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Red
    }

    return Initialize-SqlFirewallRules
}

# Export functions
Export-ModuleMember -Function @(
    'New-WsusFirewallRule',
    'Test-WsusFirewallRule',
    'Remove-WsusFirewallRule',
    'Initialize-WsusFirewallRules',
    'Initialize-SqlFirewallRules',
    'Test-AllWsusFirewallRules',
    'Test-AllSqlFirewallRules',
    'Repair-WsusFirewallRules',
    'Repair-SqlFirewallRules'
)
