#Requires -Version 5.1
<#
.SYNOPSIS
    Host environment adapter helpers for WSUS diagnostics.
.DESCRIPTION
    Concentrates direct Windows host calls behind one module seam so diagnostic
    implementations can consume normalized evidence and tests can exercise the
    interface without depending on live WSUS, SQL, IIS, firewall, or ACL state.
#>

function New-WsusHostEnvironment {
    [CmdletBinding()]
    param(
        [string]$SqlInstance = '.\SQLEXPRESS',
        [string]$ContentPath = 'C:\WSUS',
        [string]$WsusUtilPath = 'C:\Program Files\Update Services\Tools\wsusutil.exe',
        [string]$WsusSiteName = 'WSUS Administration',
        [string]$WsusAppPoolName = 'WsusPool'
    )

    [pscustomobject]@{
        PSTypeName = 'Wsus.HostEnvironment'
        SqlInstance = $SqlInstance
        ContentPath = $ContentPath
        WsusContentPath = (Join-Path $ContentPath 'WsusContent')
        WsusUtilPath = $WsusUtilPath
        WsusSiteName = $WsusSiteName
        WsusAppPoolName = $WsusAppPoolName
        SqlServiceName = if ($SqlInstance -match '\\([^\\]+)$') { "MSSQL`$$($Matches[1])" } else { 'MSSQLSERVER' }
    }
}

function Get-WsusHostServiceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Name
    )

    $services = @{}
    Get-Service -Name $Name -ErrorAction SilentlyContinue | ForEach-Object { $services[$_.Name] = $_ }
    foreach ($serviceName in $Name) {
        $svc = $services[$serviceName]
        [pscustomobject]@{
            Name = $serviceName
            Installed = ($null -ne $svc)
            Status = if ($svc) { $svc.Status.ToString() } else { 'NotInstalled' }
            StartType = if ($svc -and $svc.PSObject.Properties['StartType']) { $svc.StartType.ToString() } else { 'Unknown' }
            Running = ($svc -and $svc.Status -eq 'Running')
        }
    }
}

function Get-WsusHostCurrentSecurityContext {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $groupNames = @($identity.Groups | ForEach-Object {
        try { $_.Translate([Security.Principal.NTAccount]).Value } catch { $_.Value }
    })

    [pscustomobject]@{
        UserName = $identity.Name
        IsAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        GroupNames = $groupNames
    }
}

function Get-WsusHostPathState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $exists = Test-Path $Path
    [pscustomobject]@{
        Path = $Path
        Exists = $exists
        ResolvedPath = if ($exists) { (Resolve-Path $Path -ErrorAction SilentlyContinue).Path } else { $null }
    }
}

function Invoke-WsusHostSqlQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [string]$Database = 'SUSDB',
        [Parameter(Mandatory)][string]$Query,
        [int]$QueryTimeout = 30
    )

    if (Get-Command Invoke-WsusSqlcmd -ErrorAction SilentlyContinue) {
        return Invoke-WsusSqlcmd -ServerInstance $ServerInstance -Database $Database -Query $Query -QueryTimeout $QueryTimeout
    }
    if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
        return Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $Query -QueryTimeout $QueryTimeout -ErrorAction Stop
    }
    throw 'No SQL command adapter is available.'
}

function Get-WsusHostSqlNetworkingState {
    [CmdletBinding()]
    param([string]$SqlInstance = '.\SQLEXPRESS')

    $instanceName = if ($SqlInstance -match '\\([^\\]+)$') { $Matches[1] } else { 'MSSQLSERVER' }
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16',
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15',
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL14',
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL13'
    )

    foreach ($root in $roots) {
        $candidate = if ($instanceName -eq 'MSSQLSERVER') { "$root.MSSQLSERVER\MSSQLServer\SuperSocketNetLib" } else { "$root.$instanceName\MSSQLServer\SuperSocketNetLib" }
        if (Test-Path $candidate) {
            $tcpPath = Join-Path $candidate 'Tcp'
            $tcp = Get-ItemProperty -Path $tcpPath -ErrorAction SilentlyContinue
            $ipAll = Get-ItemProperty -Path (Join-Path $tcpPath 'IPAll') -ErrorAction SilentlyContinue
            $np = Get-ItemProperty -Path (Join-Path $candidate 'Np') -ErrorAction SilentlyContinue
            return [pscustomobject]@{
                Found = $true
                Instance = $instanceName
                RegistryPath = $candidate
                TcpEnabled = $tcp.Enabled
                TcpPort = $ipAll.TcpPort
                TcpDynamicPorts = $ipAll.TcpDynamicPorts
                NamedPipesEnabled = $np.Enabled
                StaticPort1433 = ($tcp.Enabled -eq 1 -and [string]$ipAll.TcpPort -eq '1433' -and [string]::IsNullOrWhiteSpace([string]$ipAll.TcpDynamicPorts))
            }
        }
    }

    [pscustomobject]@{
        Found = $false
        Instance = $instanceName
        RegistryPath = $null
        TcpEnabled = $null
        TcpPort = $null
        TcpDynamicPorts = $null
        NamedPipesEnabled = $null
        StaticPort1433 = $false
    }
}

function Get-WsusHostIisContentPath {
    [CmdletBinding()]
    param(
        [string]$ExpectedPath = ''
    )

    try {
        Import-Module WebAdministration -ErrorAction Stop
        $contentVdirPath = "IIS:\Sites\WSUS Administration\Content"
        if (-not (Test-Path $contentVdirPath)) {
            return [pscustomobject]@{
                Found = $false
                PhysicalPath = $null
                MatchesExpected = $false
            }
        }

        $vdir = Get-ItemProperty -Path $contentVdirPath -ErrorAction Stop
        $physicalPath = [string]$vdir.physicalPath
        $matchesExpected = $false
        if (-not [string]::IsNullOrWhiteSpace($ExpectedPath) -and -not [string]::IsNullOrWhiteSpace($physicalPath)) {
            $matchesExpected = ($physicalPath.TrimEnd('\') -ieq $ExpectedPath.TrimEnd('\'))
        }

        [pscustomobject]@{
            Found = $true
            PhysicalPath = $physicalPath
            MatchesExpected = $matchesExpected
        }
    } catch {
        [pscustomobject]@{
            Found = $false
            PhysicalPath = $null
            MatchesExpected = $false
            Error = $_.Exception.Message
        }
    }
}

function Start-WsusHostService {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    Start-Service -Name $Name -ErrorAction Stop
    Get-WsusHostServiceState -Name @($Name) | Select-Object -First 1
}

function Restart-WsusHostService {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    Restart-Service -Name $Name -Force -ErrorAction Stop
    Get-WsusHostServiceState -Name @($Name) | Select-Object -First 1
}

function Get-WsusHostEventSummary {
    [CmdletBinding()]
    param(
        [string[]]$LogNames = @('Application'),
        [int]$MaxEvents = 20,
        [datetime]$Since = (Get-Date).AddDays(-2)
    )

    $events = foreach ($logName in $LogNames) {
        Get-WinEvent -FilterHashtable @{ LogName = $logName; StartTime = $Since } -ErrorAction SilentlyContinue |
            Where-Object { $_.LevelDisplayName -in @('Error', 'Warning') } |
            Select-Object -First $MaxEvents TimeCreated, ProviderName, Id, LevelDisplayName, Message, LogName
    }

    @($events)
}

function Set-WsusHostIisContentPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PhysicalPath
    )

    Import-Module WebAdministration -ErrorAction Stop
    $contentVdirPath = "IIS:\Sites\WSUS Administration\Content"
    if (-not (Test-Path $contentVdirPath)) {
        throw "WSUS /Content virtual directory not found."
    }
    Set-ItemProperty -Path $contentVdirPath -Name physicalPath -Value $PhysicalPath -ErrorAction Stop
    Get-WsusHostIisContentPath -ExpectedPath $PhysicalPath
}


function Invoke-WsusHostCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    if (-not (Test-Path $FilePath)) {
        return [pscustomobject]@{ Success = $false; ExitCode = -1; Output = @(); Error = "Command not found: $FilePath" }
    }

    try {
        $output = & $FilePath @ArgumentList
        [pscustomobject]@{ Success = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE); ExitCode = [int]$LASTEXITCODE; Output = @($output); Error = $null }
    } catch {
        [pscustomobject]@{ Success = $false; ExitCode = -1; Output = @(); Error = $_.Exception.Message }
    }
}
Export-ModuleMember -Function @(
    'New-WsusHostEnvironment',
    'Get-WsusHostServiceState',
    'Get-WsusHostCurrentSecurityContext',
    'Get-WsusHostPathState',
    'Invoke-WsusHostSqlQuery',
    'Get-WsusHostSqlNetworkingState',
    'Get-WsusHostIisContentPath',
    'Set-WsusHostIisContentPath',
    'Start-WsusHostService',
    'Restart-WsusHostService',
    'Get-WsusHostEventSummary',
    'Invoke-WsusHostCommand'
)
