<#
===============================================================================
Module: WsusUtilities.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    Common utility functions for WSUS scripts

.DESCRIPTION
    Provides shared functionality including:
    - Color output functions
    - Logging functions
    - Admin privilege checks
    - Common helper functions
#>

# ===========================
# COLOR OUTPUT FUNCTIONS
# ===========================

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Writes output in a specific color
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ConsoleColor]$ForegroundColor
    )

    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor

    if ($args) {
        Write-Output $args
    }

    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success {
    <#
    .SYNOPSIS
        Writes success message in green
    #>
    Write-ColorOutput -ForegroundColor Green @args
}

function Write-Failure {
    <#
    .SYNOPSIS
        Writes failure message in red
    #>
    Write-ColorOutput -ForegroundColor Red @args
}

function Write-WsusWarning {
    <#
    .SYNOPSIS
        Writes warning message in yellow (renamed to avoid conflict with built-in Write-Warning)
    #>
    Write-ColorOutput -ForegroundColor Yellow @args
}

function Write-Info {
    <#
    .SYNOPSIS
        Writes info message in cyan
    #>
    Write-ColorOutput -ForegroundColor Cyan @args
}

# ===========================
# LOGGING FUNCTIONS
# ===========================

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log message

    .PARAMETER Message
        The message to log
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )

    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

function Start-WsusLogging {
    <#
    .SYNOPSIS
        Starts transcript logging with standardized naming

    .PARAMETER ScriptName
        Name of the script (used in log filename)

    .PARAMETER LogDirectory
        Directory to store logs (default: C:\WSUS\Logs)

    .PARAMETER UseTimestamp
        Include timestamp in filename (default: true)

    .EXAMPLE
        Start-WsusLogging -ScriptName "MyScript"
        # Creates C:\WSUS\Logs\MyScript_20250108_1430.log
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [string]$LogDirectory = "C:\WSUS\Logs",

        [bool]$UseTimestamp = $true
    )

    # Create log directory if it doesn't exist
    New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    # Generate log filename
    if ($UseTimestamp) {
        $logFile = Join-Path $LogDirectory "${ScriptName}_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
    } else {
        $logFile = Join-Path $LogDirectory "${ScriptName}.log"
    }

    # Start transcript
    Start-Transcript -Path $logFile -Append -ErrorAction SilentlyContinue | Out-Null

    return $logFile
}

function Stop-WsusLogging {
    <#
    .SYNOPSIS
        Stops transcript logging
    #>
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}

# ===========================
# ADMIN CHECK FUNCTIONS
# ===========================

function Test-AdminPrivileges {
    <#
    .SYNOPSIS
        Checks if the current user has administrator privileges

    .PARAMETER ExitOnFail
        If true, exits the script if not running as admin

    .OUTPUTS
        Boolean indicating if user is admin

    .EXAMPLE
        Test-AdminPrivileges -ExitOnFail $true
    #>
    param(
        [bool]$ExitOnFail = $false
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        if ($ExitOnFail) {
            Write-Failure "ERROR: This script must be run as Administrator!"
            exit 1
        }
        return $false
    }

    return $true
}

# ===========================
# SQL HELPER FUNCTIONS
# ===========================

function Invoke-SqlScalar {
    <#
    .SYNOPSIS
        Executes a SQL query and returns a scalar result

    .PARAMETER Instance
        SQL Server instance name

    .PARAMETER Query
        SQL query to execute

    .PARAMETER Database
        Database name (default: SUSDB)

    .EXAMPLE
        Invoke-SqlScalar -Instance ".\SQLEXPRESS" -Query "SELECT COUNT(*) FROM tbUpdate"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Instance,

        [Parameter(Mandatory = $true)]
        [string]$Query,

        [string]$Database = "SUSDB"
    )

    $result = sqlcmd -S $Instance -E -d $Database -b -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "SQL query failed: $result"
    }

    return $result.Trim()
}

# ===========================
# PATH HELPER FUNCTIONS
# ===========================

function Get-WsusContentPath {
    <#
    .SYNOPSIS
        Gets the WSUS content path from registry

    .OUTPUTS
        String containing the WSUS content path, or $null if not found
    #>
    try {
        $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" -Name ContentDir -ErrorAction Stop
        return $regPath.ContentDir
    } catch {
        return $null
    }
}

function Test-WsusPath {
    <#
    .SYNOPSIS
        Validates that a path exists and creates it if needed

    .PARAMETER Path
        Path to validate

    .PARAMETER Create
        If true, creates the path if it doesn't exist

    .OUTPUTS
        Boolean indicating if path exists
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [bool]$Create = $false
    )

    if (Test-Path $Path) {
        return $true
    }

    if ($Create) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            return $true
        } catch {
            return $false
        }
    }

    return $false
}

# Export functions
Export-ModuleMember -Function @(
    'Write-ColorOutput',
    'Write-Success',
    'Write-Failure',
    'Write-WsusWarning',
    'Write-Info',
    'Write-Log',
    'Start-WsusLogging',
    'Stop-WsusLogging',
    'Test-AdminPrivileges',
    'Invoke-SqlScalar',
    'Get-WsusContentPath',
    'Test-WsusPath'
)
