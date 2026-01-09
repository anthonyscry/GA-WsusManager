<#
===============================================================================
Module: WsusPermissions.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS content directory permissions management

.DESCRIPTION
    Provides standardized functions for setting and verifying WSUS content
    directory permissions across all required service accounts
#>

# ===========================
# PERMISSION SETTING FUNCTIONS
# ===========================

function Set-WsusContentPermissions {
    <#
    .SYNOPSIS
        Sets comprehensive permissions on WSUS content directory

    .PARAMETER ContentPath
        Path to WSUS content directory

    .PARAMETER IncludeWsusPool
        Include IIS APPPOOL\WsusPool permissions (default: true)

    .OUTPUTS
        Boolean indicating success

    .EXAMPLE
        Set-WsusContentPermissions -ContentPath "C:\WSUS"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContentPath,

        [bool]$IncludeWsusPool = $true
    )

    if (-not (Test-Path $ContentPath)) {
        Write-Warning "Content path does not exist: $ContentPath"
        return $false
    }

    try {
        Write-Host "Setting permissions on $ContentPath..." -ForegroundColor Yellow

        # SYSTEM and Administrators - Full Control
        icacls "$ContentPath" /grant "SYSTEM:(OI)(CI)F" /T /Q | Out-Null
        icacls "$ContentPath" /grant "Administrators:(OI)(CI)F" /T /Q | Out-Null

        # NETWORK SERVICE - Full Control (required for WSUS service)
        icacls "$ContentPath" /grant "NETWORK SERVICE:(OI)(CI)F" /T /Q | Out-Null

        # LOCAL SERVICE - Full Control
        icacls "$ContentPath" /grant "NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F" /T /Q | Out-Null

        # IIS_IUSRS - Read (for web access)
        icacls "$ContentPath" /grant "IIS_IUSRS:(OI)(CI)R" /T /Q | Out-Null

        # WsusPool application pool identity - Full Control (if requested)
        if ($IncludeWsusPool) {
            $wsusPoolExists = $false
            if (Get-Command Get-WebAppPoolState -ErrorAction SilentlyContinue) {
                if (Test-Path IIS:\AppPools\WsusPool) {
                    $wsusPoolExists = $true
                }
            }

            if ($wsusPoolExists) {
                icacls "$ContentPath" /grant "IIS APPPOOL\WsusPool:(OI)(CI)F" /T /Q 2>$null | Out-Null
                Write-Host "  WsusPool permissions set" -ForegroundColor Green
            } else {
                Write-Host "  WsusPool not found, skipping" -ForegroundColor Yellow
            }
        }

        Write-Host "  Permissions set successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "Failed to set permissions: $($_.Exception.Message)"
        return $false
    }
}

function Test-WsusContentPermissions {
    <#
    .SYNOPSIS
        Verifies that required permissions are set on WSUS content directory

    .PARAMETER ContentPath
        Path to WSUS content directory

    .OUTPUTS
        Hashtable with permission check results

    .EXAMPLE
        $result = Test-WsusContentPermissions -ContentPath "C:\WSUS"
        if ($result.AllCorrect) { Write-Host "All permissions OK" }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContentPath
    )

    if (-not (Test-Path $ContentPath)) {
        Write-Warning "Content path does not exist: $ContentPath"
        return @{ AllCorrect = $false; Missing = @("Path does not exist") }
    }

    $requiredPermissions = @(
        "SYSTEM",
        "BUILTIN\Administrators",
        "NETWORK SERVICE",
        "NT AUTHORITY\LOCAL SERVICE",
        "BUILTIN\IIS_IUSRS"
    )

    $results = @{
        AllCorrect = $true
        Missing = @()
        Found = @()
    }

    try {
        $acl = Get-Acl $ContentPath

        foreach ($account in $requiredPermissions) {
            $hasPermission = $false

            foreach ($access in $acl.Access) {
                if ($access.IdentityReference -like "*$account*" -or
                    $access.IdentityReference.Value -eq $account) {
                    $hasPermission = $true
                    $results.Found += $account
                    break
                }
            }

            if (-not $hasPermission) {
                $results.Missing += $account
                $results.AllCorrect = $false
            }
        }

        # Check for WsusPool (optional)
        $wsusPoolFound = $false
        foreach ($access in $acl.Access) {
            if ($access.IdentityReference -like "*WsusPool*") {
                $wsusPoolFound = $true
                $results.Found += "IIS APPPOOL\WsusPool"
                break
            }
        }

        if (-not $wsusPoolFound) {
            $results.Missing += "IIS APPPOOL\WsusPool (optional)"
        }

        return $results
    } catch {
        Write-Warning "Failed to check permissions: $($_.Exception.Message)"
        return @{
            AllCorrect = $false
            Missing = @("Error checking permissions")
            Found = @()
        }
    }
}

function Repair-WsusContentPermissions {
    <#
    .SYNOPSIS
        Checks and repairs WSUS content permissions if needed

    .PARAMETER ContentPath
        Path to WSUS content directory

    .PARAMETER Force
        Force repair even if permissions appear correct

    .OUTPUTS
        Boolean indicating if repairs were needed and successful

    .EXAMPLE
        Repair-WsusContentPermissions -ContentPath "C:\WSUS"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContentPath,

        [switch]$Force
    )

    if ($Force) {
        Write-Host "Forcing permission repair..." -ForegroundColor Yellow
        return Set-WsusContentPermissions -ContentPath $ContentPath
    }

    $check = Test-WsusContentPermissions -ContentPath $ContentPath

    if ($check.AllCorrect) {
        Write-Host "All permissions are correct" -ForegroundColor Green
        return $true
    }

    Write-Host "Missing permissions detected:" -ForegroundColor Yellow
    $check.Missing | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Red
    }

    Write-Host "Repairing permissions..." -ForegroundColor Yellow
    return Set-WsusContentPermissions -ContentPath $ContentPath
}

function Initialize-WsusDirectories {
    <#
    .SYNOPSIS
        Creates WSUS directories with proper permissions

    .PARAMETER WSUSRoot
        Root WSUS directory path

    .PARAMETER CreateSubdirectories
        Create standard subdirectories (default: true)

    .OUTPUTS
        Boolean indicating success

    .EXAMPLE
        Initialize-WsusDirectories -WSUSRoot "C:\WSUS"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WSUSRoot,

        [bool]$CreateSubdirectories = $true
    )

    try {
        Write-Host "Creating WSUS directory structure..." -ForegroundColor Yellow

        # Create root directory
        New-Item -Path $WSUSRoot -ItemType Directory -Force | Out-Null

        # Create standard subdirectories
        if ($CreateSubdirectories) {
            $subdirs = @(
                "WSUSContent",
                "UpdateServicesPackages",
                "Logs"
            )

            foreach ($subdir in $subdirs) {
                $path = Join-Path $WSUSRoot $subdir
                New-Item -Path $path -ItemType Directory -Force | Out-Null
                Write-Host "  Created: $path" -ForegroundColor Gray
            }
        }

        Write-Host "  Directories created" -ForegroundColor Green

        # Set permissions
        $result = Set-WsusContentPermissions -ContentPath $WSUSRoot -IncludeWsusPool $false

        return $result
    } catch {
        Write-Warning "Failed to initialize directories: $($_.Exception.Message)"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Set-WsusContentPermissions',
    'Test-WsusContentPermissions',
    'Repair-WsusContentPermissions',
    'Initialize-WsusDirectories'
)
