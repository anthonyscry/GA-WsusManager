<#
===============================================================================
Module: WsusConfig.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    Centralized configuration for WSUS scripts

.DESCRIPTION
    Provides a single source of truth for all configurable values including:
    - SQL instance names
    - File paths
    - Service names
    - Timeout values
    - Port numbers
    This eliminates hardcoded values scattered throughout the codebase.
#>

# ===========================
# DEFAULT CONFIGURATION
# ===========================

$script:WsusConfig = @{
    # SQL Server Configuration
    SqlInstance = ".\SQLEXPRESS"
    DatabaseName = "SUSDB"

    # WSUS Paths
    ContentPath = "C:\WSUS"
    ContentSubfolder = "WsusContent"
    LogPath = "C:\WSUS\Logs"
    SqlInstallerPath = "C:\WSUS\SQLDB"
    DefaultExportPath = "\\lab-hyperv\d\WSUS-Exports"

    # Service Names
    Services = @{
        SqlExpress = "MSSQL`$SQLEXPRESS"
        Wsus = "WSUSService"
        Iis = "W3SVC"
        WindowsUpdate = "wuauserv"
        Bits = "bits"
    }

    # Network Configuration
    WsusPort = 8530
    WsusSslPort = 8531
    SqlPort = 1433
    SqlBrowserPort = 1434

    # Timeout Values (in seconds)
    Timeouts = @{
        SqlQueryDefault = 30
        SqlQueryLong = 300
        SqlQueryUnlimited = 0
        ServiceStart = 10
        ServiceStop = 5
        SyncMaxMinutes = 60
        DownloadMaxIterations = 60
    }

    # Maintenance Settings
    Maintenance = @{
        BackupRetentionDays = 90
        DefaultExportDays = 30
        UpdateAgeCutoffMonths = 6
        MaxAutoApproveCount = 500
        IndexFragmentationThreshold = 10
        IndexRebuildThreshold = 30
        BatchSize = 100
        SupersessionBatchSize = 10000
    }

    # DVD Export Settings
    DvdExport = @{
        VolumeSizeMB = 4300  # 4.3 GB for single-layer DVD
    }
}

# ===========================
# CONFIGURATION FUNCTIONS
# ===========================

function Get-WsusConfig {
    <#
    .SYNOPSIS
        Gets the current WSUS configuration

    .PARAMETER Key
        Optional specific configuration key to retrieve

    .EXAMPLE
        Get-WsusConfig
        # Returns entire configuration

    .EXAMPLE
        Get-WsusConfig -Key "SqlInstance"
        # Returns ".\SQLEXPRESS"

    .EXAMPLE
        Get-WsusConfig -Key "Services.Wsus"
        # Returns "WSUSService"
    #>
    param(
        [string]$Key
    )

    if ([string]::IsNullOrEmpty($Key)) {
        return $script:WsusConfig
    }

    # Support dot notation for nested keys
    $keys = $Key -split '\.'
    $value = $script:WsusConfig

    foreach ($k in $keys) {
        if ($value -is [hashtable] -and $value.ContainsKey($k)) {
            $value = $value[$k]
        } else {
            return $null
        }
    }

    return $value
}

function Set-WsusConfig {
    <#
    .SYNOPSIS
        Sets a WSUS configuration value

    .PARAMETER Key
        Configuration key to set (supports dot notation for nested keys)

    .PARAMETER Value
        Value to set

    .EXAMPLE
        Set-WsusConfig -Key "SqlInstance" -Value "localhost\SQLEXPRESS"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        $Value
    )

    $keys = $Key -split '\.'

    if ($keys.Count -eq 1) {
        $script:WsusConfig[$Key] = $Value
    } else {
        # Navigate to parent, then set the leaf key
        $parent = $script:WsusConfig
        for ($i = 0; $i -lt $keys.Count - 1; $i++) {
            if ($parent.ContainsKey($keys[$i])) {
                $parent = $parent[$keys[$i]]
            } else {
                throw "Configuration key not found: $($keys[0..($i)] -join '.')"
            }
        }
        $parent[$keys[-1]] = $Value
    }
}

function Get-SqlInstanceName {
    <#
    .SYNOPSIS
        Gets the SQL instance name in the requested format

    .PARAMETER Format
        Format to return: 'Short' (SQLEXPRESS), 'Dot' (.\SQLEXPRESS), 'Localhost' (localhost\SQLEXPRESS)

    .OUTPUTS
        String with SQL instance name
    #>
    param(
        [ValidateSet('Short', 'Dot', 'Localhost')]
        [string]$Format = 'Dot'
    )

    switch ($Format) {
        'Short' { return 'SQLEXPRESS' }
        'Dot' { return '.\SQLEXPRESS' }
        'Localhost' { return 'localhost\SQLEXPRESS' }
    }
}

function Get-WsusContentPathFromConfig {
    <#
    .SYNOPSIS
        Gets the full WSUS content path from config or registry (with subfolder option)

    .DESCRIPTION
        This function is distinct from Get-WsusContentPath in WsusUtilities.psm1.
        Use this when you need the IncludeSubfolder option.

    .PARAMETER IncludeSubfolder
        If true, appends WsusContent subfolder

    .OUTPUTS
        String containing the WSUS content path
    #>
    param(
        [switch]$IncludeSubfolder
    )

    # Try registry first
    try {
        $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" -Name ContentDir -ErrorAction Stop
        $basePath = $regPath.ContentDir
    } catch {
        # Fall back to config
        $basePath = $script:WsusConfig.ContentPath
    }

    if ($IncludeSubfolder) {
        return Join-Path $basePath $script:WsusConfig.ContentSubfolder
    }

    return $basePath
}

function Get-WsusLogPath {
    <#
    .SYNOPSIS
        Gets the WSUS log directory path, creating it if needed

    .OUTPUTS
        String containing the log path
    #>
    $logPath = $script:WsusConfig.LogPath

    if (-not (Test-Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    return $logPath
}

function Get-WsusServiceName {
    <#
    .SYNOPSIS
        Gets the name of a WSUS-related service

    .PARAMETER Service
        Service type: SqlExpress, Wsus, Iis, WindowsUpdate, Bits

    .OUTPUTS
        String containing the service name
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('SqlExpress', 'Wsus', 'Iis', 'WindowsUpdate', 'Bits')]
        [string]$Service
    )

    return $script:WsusConfig.Services[$Service]
}

function Get-WsusTimeout {
    <#
    .SYNOPSIS
        Gets a timeout value in seconds

    .PARAMETER Type
        Timeout type: SqlQueryDefault, SqlQueryLong, SqlQueryUnlimited, ServiceStart, ServiceStop

    .OUTPUTS
        Integer timeout value in seconds
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('SqlQueryDefault', 'SqlQueryLong', 'SqlQueryUnlimited', 'ServiceStart', 'ServiceStop', 'SyncMaxMinutes', 'DownloadMaxIterations')]
        [string]$Type
    )

    return $script:WsusConfig.Timeouts[$Type]
}

function Get-WsusMaintenanceSetting {
    <#
    .SYNOPSIS
        Gets a maintenance setting value

    .PARAMETER Setting
        Setting name

    .OUTPUTS
        The setting value
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BackupRetentionDays', 'DefaultExportDays', 'UpdateAgeCutoffMonths',
                     'MaxAutoApproveCount', 'IndexFragmentationThreshold', 'IndexRebuildThreshold',
                     'BatchSize', 'SupersessionBatchSize')]
        [string]$Setting
    )

    return $script:WsusConfig.Maintenance[$Setting]
}

function Get-WsusConnectionString {
    <#
    .SYNOPSIS
        Gets a SQL connection string for WSUS database

    .OUTPUTS
        String containing the connection string
    #>
    $instance = $script:WsusConfig.SqlInstance
    $database = $script:WsusConfig.DatabaseName

    return "Server=$instance;Database=$database;Integrated Security=True"
}

function Initialize-WsusConfigFromFile {
    <#
    .SYNOPSIS
        Loads configuration from a JSON file if it exists

    .PARAMETER Path
        Path to configuration file (default: C:\WSUS\wsus-config.json)

    .OUTPUTS
        Boolean indicating if config was loaded
    #>
    param(
        [string]$Path = "C:\WSUS\wsus-config.json"
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $jsonConfig = Get-Content $Path -Raw | ConvertFrom-Json

        # Merge JSON config into script config
        foreach ($prop in $jsonConfig.PSObject.Properties) {
            if ($script:WsusConfig.ContainsKey($prop.Name)) {
                if ($prop.Value -is [PSCustomObject]) {
                    # Convert PSCustomObject to hashtable for nested objects
                    $hashtable = @{}
                    foreach ($nestedProp in $prop.Value.PSObject.Properties) {
                        $hashtable[$nestedProp.Name] = $nestedProp.Value
                    }
                    $script:WsusConfig[$prop.Name] = $hashtable
                } else {
                    $script:WsusConfig[$prop.Name] = $prop.Value
                }
            }
        }

        return $true
    } catch {
        Write-Warning "Failed to load configuration from $Path : $($_.Exception.Message)"
        return $false
    }
}

function Export-WsusConfigToFile {
    <#
    .SYNOPSIS
        Exports current configuration to a JSON file

    .PARAMETER Path
        Path to save configuration file (default: C:\WSUS\wsus-config.json)
    #>
    param(
        [string]$Path = "C:\WSUS\wsus-config.json"
    )

    try {
        $script:WsusConfig | ConvertTo-Json -Depth 4 | Set-Content -Path $Path -Encoding UTF8
        Write-Host "Configuration exported to: $Path" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to export configuration: $($_.Exception.Message)"
    }
}

# ===========================
# INITIALIZATION
# ===========================

# Try to load config from file on module import
Initialize-WsusConfigFromFile | Out-Null

# ===========================
# EXPORTS
# ===========================

Export-ModuleMember -Function @(
    'Get-WsusConfig',
    'Set-WsusConfig',
    'Get-SqlInstanceName',
    'Get-WsusContentPathFromConfig',
    'Get-WsusLogPath',
    'Get-WsusServiceName',
    'Get-WsusTimeout',
    'Get-WsusMaintenanceSetting',
    'Get-WsusConnectionString',
    'Initialize-WsusConfigFromFile',
    'Export-WsusConfigToFile'
)
