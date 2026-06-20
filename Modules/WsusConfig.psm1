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
    DefaultExportPath = "C:\WSUS\Exports"

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
        UpdateAgeCutoffMonths = 6
        MaxAutoApproveCount = 200
        IndexFragmentationThreshold = 10
        IndexRebuildThreshold = 30
        BatchSize = 100
        SupersessionBatchSize = 10000
    }

    # DVD Export Settings
    DvdExport = @{
        VolumeSizeMB = 4300  # 4.3 GB for single-layer DVD
    }

    # GUI Configuration
    Gui = @{
        # Main Window
        MainWindow = @{
            Width = 950
            Height = 736
            MinWidth = 800
            MinHeight = 600
        }

        # Standard Dialog Sizes
        Dialogs = @{
            Small = @{ Width = 480; Height = 280 }      # Simple confirmations
            Medium = @{ Width = 480; Height = 360 }     # Settings, About
            Large = @{ Width = 480; Height = 460 }      # Transfer dialog
            ExtraLarge = @{ Width = 520; Height = 580 } # Online Sync with export options
            Schedule = @{ Width = 480; Height = 560 }   # Schedule task dialog
        }

        # Panel Heights
        LogPanelHeight = 250
        LogPanelCollapsed = 36
        NavPanelWidth = 180

        # Timer Intervals (milliseconds)
        Timers = @{
            DashboardRefresh = 30000        # 30 seconds - auto-refresh dashboard
            UiUpdate = 250                   # 250ms - UI responsiveness
            OpCheck = 500                    # 500ms - operation status check
            KeystrokeFlush = 5000            # 5 seconds - flush console buffer
                                       # Sends a periodic Enter to the visible
                                       # PowerShell window in Live Terminal mode
                                       # so it doesn't get stuck waiting for
                                       # input. 5s keeps it responsive without
                                       # being too noisy.
            ProcessWait = 100                # 100ms - wait for process start
        }

        # Console Window (Live Terminal mode)
        Console = @{
            MinWidth = 400
            MinHeight = 300
            WidthRatio = 0.60               # 60% of main window width
            HeightRatio = 0.60              # 60% of main window height
        }

        # List Controls
        ListBox = @{
            MaxHeight = 100
            ComboMaxHeight = 200
        }
    }

    # Retry Configuration
    Retry = @{
        # Database operations
        DbShrinkAttempts = 3
        DbShrinkDelaySeconds = 30

        # Service operations
        ServiceStartAttempts = 3
        ServiceStartDelaySeconds = 5

        # Sync operations
        SyncProgressDelaySeconds = 5
        SyncWaitDelaySeconds = 2

        # General
        DefaultDelaySeconds = 3
        ShortDelaySeconds = 1
        LongDelaySeconds = 15
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
        [ValidateSet('BackupRetentionDays', 'UpdateAgeCutoffMonths',
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

function Test-WsusConfigJsonNode {
    param(
        [Parameter(Mandatory)]
        $Value,

        [Parameter(Mandatory)]
        [hashtable]$Schema,

        [string]$Path = 'configuration'
    )

    if ($null -eq $Value -or $Value -isnot [PSCustomObject]) {
        throw "Invalid config shape at '$Path': expected a JSON object."
    }

    foreach ($prop in @($Value.PSObject.Properties)) {
        $keyPath = "$Path.$($prop.Name)"
        if (-not $Schema.ContainsKey($prop.Name)) {
            throw "Unknown config key '$keyPath'."
        }

        $expected = $Schema[$prop.Name]
        if ($expected -is [hashtable]) {
            Test-WsusConfigJsonNode -Value $prop.Value -Schema $expected -Path $keyPath
        } elseif ($prop.Value -is [PSCustomObject] -or $prop.Value -is [System.Array]) {
            throw "Invalid config shape at '$keyPath': expected a scalar value."
        }
    }
}

function ConvertTo-WsusConfigHashtable {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Value,

        [Parameter(Mandatory)]
        [hashtable]$Schema
    )

    $result = @{}
    foreach ($prop in @($Value.PSObject.Properties)) {
        if ($Schema[$prop.Name] -is [hashtable]) {
            $result[$prop.Name] = ConvertTo-WsusConfigHashtable -Value $prop.Value -Schema $Schema[$prop.Name]
        } else {
            $result[$prop.Name] = $prop.Value
        }
    }

    return $result
}

function Merge-WsusConfigHashtable {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Target,

        [Parameter(Mandatory)]
        [hashtable]$Source
    )

    foreach ($key in $Source.Keys) {
        if ($Target[$key] -is [hashtable] -and $Source[$key] -is [hashtable]) {
            Merge-WsusConfigHashtable -Target $Target[$key] -Source $Source[$key]
        } else {
            $Target[$key] = $Source[$key]
        }
    }
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
        $jsonText = Get-Content $Path -Raw
        if (-not $jsonText.TrimStart().StartsWith('{')) {
            throw "Invalid config shape at 'configuration': expected a JSON object."
        }

        $jsonConfig = $jsonText | ConvertFrom-Json -ErrorAction Stop
        Test-WsusConfigJsonNode -Value $jsonConfig -Schema $script:WsusConfig
        $validatedConfig = ConvertTo-WsusConfigHashtable -Value $jsonConfig -Schema $script:WsusConfig
        Merge-WsusConfigHashtable -Target $script:WsusConfig -Source $validatedConfig

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

function Get-WsusGuiSetting {
    <#
    .SYNOPSIS
        Gets a GUI configuration setting

    .PARAMETER Setting
        Setting path using dot notation (e.g., "Dialogs.Medium", "Timers.DashboardRefresh")

    .EXAMPLE
        Get-WsusGuiSetting -Setting "Dialogs.Medium"
        # Returns @{ Width = 480; Height = 360 }

    .EXAMPLE
        Get-WsusGuiSetting -Setting "Timers.DashboardRefresh"
        # Returns 30000
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Setting
    )

    $keys = $Setting -split '\.'
    $value = $script:WsusConfig.Gui

    foreach ($k in $keys) {
        if ($value -is [hashtable] -and $value.ContainsKey($k)) {
            $value = $value[$k]
        } else {
            return $null
        }
    }

    return $value
}

function Get-WsusRetrySetting {
    <#
    .SYNOPSIS
        Gets a retry configuration setting

    .PARAMETER Setting
        Setting name (e.g., "DbShrinkAttempts", "ServiceStartDelaySeconds")

    .EXAMPLE
        Get-WsusRetrySetting -Setting "DbShrinkAttempts"
        # Returns 3
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DbShrinkAttempts', 'DbShrinkDelaySeconds', 'ServiceStartAttempts',
                     'ServiceStartDelaySeconds', 'SyncProgressDelaySeconds', 'SyncWaitDelaySeconds',
                     'DefaultDelaySeconds', 'ShortDelaySeconds', 'LongDelaySeconds')]
        [string]$Setting
    )

    return $script:WsusConfig.Retry[$Setting]
}

function Get-WsusDialogSize {
    <#
    .SYNOPSIS
        Gets dialog dimensions for a specific dialog type

    .PARAMETER Type
        Dialog type: Small, Medium, Large, ExtraLarge, Schedule

    .OUTPUTS
        Hashtable with Width and Height properties

    .EXAMPLE
        $size = Get-WsusDialogSize -Type "Medium"
        $dlg.Width = $size.Width
        $dlg.Height = $size.Height
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Small', 'Medium', 'Large', 'ExtraLarge', 'Schedule')]
        [string]$Type
    )

    return $script:WsusConfig.Gui.Dialogs[$Type]
}

function Get-WsusTimerInterval {
    <#
    .SYNOPSIS
        Gets a timer interval in milliseconds

    .PARAMETER Timer
        Timer type: DashboardRefresh, UiUpdate, OpCheck, KeystrokeFlush, ProcessWait

    .OUTPUTS
        Integer interval in milliseconds
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DashboardRefresh', 'UiUpdate', 'OpCheck', 'KeystrokeFlush', 'ProcessWait')]
        [string]$Timer
    )

    return $script:WsusConfig.Gui.Timers[$Timer]
}

#region Health and Operation Config (moved to domain modules)
# Get-WsusHealthWeights  → WsusHealth
# Get-WsusOperationTimeout → WsusOperationRunner
# Get-WsusAppDataPath      → WsusUtilities
#endregion

function Get-WsusAppVersion {
    <#
    .SYNOPSIS
        Returns the single-source-of-truth app version from metadata.json

    .DESCRIPTION
        Reads metadata.json (which lives at the repo root, one level above the
        Modules folder) and returns the value of its "version" field. If the
        file is missing or unreadable, falls back to a hard-coded default that
        is bumped manually each release. This is the canonical way to get the
        version from any module or script — never hard-code the version in
        individual files.

    .OUTPUTS
        String with semver-style version (e.g. "4.1.0")

    .EXAMPLE
        Get-WsusAppVersion
        # Returns "4.1.0"
    #>
    $metadataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'metadata.json'
    if ($PSScriptRoot -and (Test-Path $metadataPath)) {
        try {
            $meta = Get-Content $metadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($meta.version) {
                return ([string]$meta.version).Trim()
            }
        } catch {
            Write-Verbose "Could not read metadata.json: $($_.Exception.Message)"
        }
    }
    # Hard-coded fallback. Keep in sync with metadata.json.
    return '4.1.0'
}


function Get-WsusRuntimeConfig {
    <#
    .SYNOPSIS
        Returns one runtime configuration interface for WSUS operations.
    .DESCRIPTION
        Concentrates SQL, WSUS content, port, service, and tool-path defaults so
        GUI, CLI, diagnostics, dashboard, and transfer modules do not duplicate
        deployment assumptions.
    #>
    [CmdletBinding()]
    param()

    $contentPath = $script:WsusConfig.ContentPath
    [pscustomobject]@{
        PSTypeName = 'Wsus.RuntimeConfig'
        SqlInstance = $script:WsusConfig.SqlInstance
        DatabaseName = $script:WsusConfig.DatabaseName
        ContentPath = $contentPath
        WsusContentPath = Join-Path $contentPath $script:WsusConfig.ContentSubfolder
        LogPath = $script:WsusConfig.LogPath
        DefaultExportPath = $script:WsusConfig.DefaultExportPath
        Services = $script:WsusConfig.Services.Clone()
        Ports = @{
            Wsus = $script:WsusConfig.WsusPort
            WsusSsl = $script:WsusConfig.WsusSslPort
            Sql = $script:WsusConfig.SqlPort
            SqlBrowser = $script:WsusConfig.SqlBrowserPort
        }
        Tools = @{
            WsusUtil = 'C:\Program Files\Update Services\Tools\wsusutil.exe'
            Robocopy = 'robocopy.exe'
            PowerShell = 'powershell.exe'
            Sqlcmd = 'sqlcmd.exe'
        }
        SqlExpressLimitGB = 10
    }
}

#endregion Health and Operation Config (moved to domain modules)

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
    'Export-WsusConfigToFile',
    'Get-WsusGuiSetting',
    'Get-WsusRetrySetting',
    'Get-WsusDialogSize',
    'Get-WsusTimerInterval',
    'Get-WsusAppVersion',
    'Get-WsusRuntimeConfig'
)
