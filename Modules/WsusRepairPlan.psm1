#Requires -Version 5.1
<#
.SYNOPSIS
    Named repair actions for WSUS diagnostics.
.DESCRIPTION
    Concentrates WSUS repair execution behind a small interface so diagnostic
    issues can carry stable repair action ids instead of embedding scriptblocks.
#>

$modulePath = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
foreach ($moduleName in @('WsusHostEnvironment.psm1','WsusPermissions.psm1','WsusFirewall.psm1','WsusServices.psm1','WsusUtilities.psm1')) {
    $candidate = Join-Path $modulePath $moduleName
    if (Test-Path $candidate) {
        Import-Module $candidate -Force -DisableNameChecking -ErrorAction SilentlyContinue
    }
}

function Invoke-WsusRepairAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'EnableSqlTcpIp',
            'EnableSqlNamedPipes',
            'RepairContentPermissions',
            'RepairIisContentPath',
            'StartBits',
            'ResetWsusContent',
            'StartWsusPool',
            'TuneWsusPool',
            'StartSqlService',
            'StartSqlBrowser',
            'RepairSqlFirewall',
            'RepairWsusFirewall',
            'StartWsusService',
            'StartIisService',
            'GrantNetworkServiceLogin'
        )]
        [string]$Action,

        [string]$ContentPath = 'C:\WSUS',
        [string]$SqlInstance = '.\SQLEXPRESS',
        [string]$WsusContentPath = '',
        [string]$SqlServiceName = 'MSSQL$SQLEXPRESS'
    )

    if ([string]::IsNullOrWhiteSpace($WsusContentPath)) {
        $WsusContentPath = Join-Path $ContentPath 'WsusContent'
    }

    switch ($Action) {
        'EnableSqlTcpIp' {
            $networkState = Get-WsusHostSqlNetworkingState -SqlInstance $SqlInstance
            if (-not $networkState.Found) { throw 'SQL networking registry path not found.' }
            $tcpPath = Join-Path $networkState.RegistryPath 'Tcp'
            Set-ItemProperty -Path $tcpPath -Name Enabled -Value 1 -ErrorAction Stop
            Set-ItemProperty -Path (Join-Path $tcpPath 'IPAll') -Name TcpDynamicPorts -Value '' -Force -ErrorAction Stop
            Set-ItemProperty -Path (Join-Path $tcpPath 'IPAll') -Name TcpPort -Value '1433' -Force -ErrorAction Stop
            Restart-Service -Name $SqlServiceName -Force -ErrorAction Stop
            return $true
        }
        'EnableSqlNamedPipes' {
            $networkState = Get-WsusHostSqlNetworkingState -SqlInstance $SqlInstance
            if (-not $networkState.Found) { throw 'SQL networking registry path not found.' }
            $npPath = Join-Path $networkState.RegistryPath 'Np'
            Set-ItemProperty -Path $npPath -Name Enabled -Value 1 -ErrorAction Stop
            Restart-Service -Name $SqlServiceName -Force -ErrorAction Stop
            return $true
        }
        'RepairContentPermissions' {
            return (Repair-WsusContentPermissions -ContentPath $ContentPath)
        }
        'RepairIisContentPath' {
            if (-not (Get-Command Set-WsusHostIisContentPath -ErrorAction SilentlyContinue)) {
                throw 'Set-WsusHostIisContentPath is not available.'
            }
            return (Set-WsusHostIisContentPath -PhysicalPath $WsusContentPath)
        }
        'StartBits' {
            Start-WsusHostService -Name 'BITS' | Out-Null
            return $true
        }
        'ResetWsusContent' {
            $environment = New-WsusHostEnvironment -SqlInstance $SqlInstance -ContentPath $ContentPath
            $reset = Invoke-WsusHostCommand -FilePath $environment.WsusUtilPath -ArgumentList @('reset')
            if (-not $reset.Success) {
                if ($reset.Error) { throw $reset.Error }
                throw "wsusutil reset failed with exit code $($reset.ExitCode)"
            }
            return $true
        }
        'StartWsusPool' {
            Import-Module WebAdministration -ErrorAction Stop
            Start-WebAppPool -Name 'WsusPool' -ErrorAction Stop
            return $true
        }
        'TuneWsusPool' {
            Import-Module WebAdministration -ErrorAction Stop
            $appPoolPath = 'IIS:\AppPools\WsusPool'
            Set-ItemProperty -Path $appPoolPath -Name queueLength -Value 25000 -ErrorAction Stop
            Set-ItemProperty -Path $appPoolPath -Name recycling.periodicRestart.privateMemory -Value 0 -ErrorAction Stop
            Set-ItemProperty -Path $appPoolPath -Name processModel.idleTimeout -Value '00:00:00' -ErrorAction Stop
            Set-ItemProperty -Path $appPoolPath -Name recycling.periodicRestart.time -Value '00:00:00' -ErrorAction Stop
            return $true
        }
        'StartSqlService' {
            Start-WsusHostService -Name $SqlServiceName | Out-Null
            return $true
        }
        'StartSqlBrowser' {
            Set-Service SQLBrowser -StartupType Automatic -ErrorAction SilentlyContinue
            Start-WsusHostService -Name 'SQLBrowser' | Out-Null
            return $true
        }
        'RepairSqlFirewall' {
            $null = Repair-SqlFirewallRules
            return $true
        }
        'RepairWsusFirewall' {
            $null = Repair-WsusFirewallRules
            return $true
        }
        'StartWsusService' {
            Start-WsusHostService -Name 'WsusService' | Out-Null
            return $true
        }
        'StartIisService' {
            Start-WsusHostService -Name 'W3SVC' | Out-Null
            return $true
        }
        'GrantNetworkServiceLogin' {
            Invoke-WsusHostSqlQuery -ServerInstance $SqlInstance -Database master -Query "CREATE LOGIN [NT AUTHORITY\NETWORK SERVICE] FROM WINDOWS;" -QueryTimeout 10 -ErrorAction SilentlyContinue | Out-Null
            Invoke-WsusHostSqlQuery -ServerInstance $SqlInstance -Database master -Query "ALTER SERVER ROLE [dbcreator] ADD MEMBER [NT AUTHORITY\NETWORK SERVICE];" -QueryTimeout 10 -ErrorAction SilentlyContinue | Out-Null
            return $true
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-WsusRepairAction'
)
