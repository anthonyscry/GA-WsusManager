#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot

    $script:HadStartWebAppPoolFunction = Test-Path function:\global:Start-WebAppPool
    $script:OriginalStartWebAppPoolFunction = if ($script:HadStartWebAppPoolFunction) { (Get-Item function:\global:Start-WebAppPool).ScriptBlock } else { $null }
    Set-Item -Path function:\global:Start-WebAppPool -Value { param([string]$Name) $env:WsusRepairPlanStartWebAppPoolName = $Name }

    Import-WsusTestModule -ModuleName 'WsusRepairPlan' -RepoRoot $script:RepoRoot
}

AfterAll {
    Remove-WsusTestModule -ModuleName 'WsusRepairPlan'
    if ($script:HadStartWebAppPoolFunction) {
        Set-Item -Path function:\global:Start-WebAppPool -Value $script:OriginalStartWebAppPoolFunction
    } else {
        Remove-Item -Path function:\global:Start-WebAppPool -ErrorAction SilentlyContinue
    }
}

Describe 'WsusRepairPlan module' {
    It 'exports the repair action dispatcher' {
        Get-Command Invoke-WsusRepairAction -Module WsusRepairPlan | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-WsusRepairAction' {
    BeforeEach {
        Mock Get-WsusHostSqlNetworkingState {
            [pscustomobject]@{ Found = $true; RegistryPath = 'HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQLServer\SuperSocketNetLib' }
        } -ModuleName WsusRepairPlan
        Mock Set-ItemProperty { } -ModuleName WsusRepairPlan
        Mock Restart-Service { } -ModuleName WsusRepairPlan
        Mock Repair-WsusContentPermissions { [pscustomobject]@{ Success = $true; ContentPath = $ContentPath } } -ModuleName WsusRepairPlan
        Mock Get-Command { [pscustomobject]@{ Name = 'Set-WsusHostIisContentPath' } } -ModuleName WsusRepairPlan -ParameterFilter { $Name -eq 'Set-WsusHostIisContentPath' }
        Mock Set-WsusHostIisContentPath { [pscustomobject]@{ Found = $true; PhysicalPath = $PhysicalPath; MatchesExpected = $true } } -ModuleName WsusRepairPlan
        Mock Start-WsusHostService { [pscustomobject]@{ Name = $Name; Running = $true } } -ModuleName WsusRepairPlan
        Mock New-WsusHostEnvironment { [pscustomobject]@{ WsusUtilPath = 'C:\Program Files\Update Services\Tools\wsusutil.exe' } } -ModuleName WsusRepairPlan
        Mock Invoke-WsusHostCommand { [pscustomobject]@{ Success = $true; ExitCode = 0; Output = @(); Error = $null } } -ModuleName WsusRepairPlan
        Mock Import-Module { } -ModuleName WsusRepairPlan -ParameterFilter { $Name -eq 'WebAdministration' }
        Mock Set-Service { } -ModuleName WsusRepairPlan
        Mock Repair-SqlFirewallRules { $true } -ModuleName WsusRepairPlan
        Mock Repair-WsusFirewallRules { $true } -ModuleName WsusRepairPlan
        Mock Invoke-WsusHostSqlQuery { [pscustomobject]@{} } -ModuleName WsusRepairPlan
    }

    It 'enables SQL TCP/IP with static port 1433 and restarts SQL' {
        Invoke-WsusRepairAction -Action EnableSqlTcpIp -SqlInstance '.\SQLEXPRESS' -SqlServiceName 'MSSQL$SQLEXPRESS' | Should -BeTrue

        Should -Invoke Get-WsusHostSqlNetworkingState -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $SqlInstance -eq '.\SQLEXPRESS' }
        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Path -like '*\Tcp' -and $Name -eq 'Enabled' -and $Value -eq 1 }
        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Path -like '*\Tcp\IPAll' -and $Name -eq 'TcpDynamicPorts' -and $Value -eq '' }
        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Path -like '*\Tcp\IPAll' -and $Name -eq 'TcpPort' -and $Value -eq '1433' }
        Should -Invoke Restart-Service -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'MSSQL$SQLEXPRESS' -and $Force }
    }

    It 'enables SQL named pipes and restarts SQL' {
        Invoke-WsusRepairAction -Action EnableSqlNamedPipes -SqlServiceName 'MSSQL$SQLEXPRESS' | Should -BeTrue

        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Path -like '*\Np' -and $Name -eq 'Enabled' -and $Value -eq 1 }
        Should -Invoke Restart-Service -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'MSSQL$SQLEXPRESS' -and $Force }
    }

    It 'throws when SQL networking registry state cannot be found' {
        Mock Get-WsusHostSqlNetworkingState { [pscustomobject]@{ Found = $false; RegistryPath = $null } } -ModuleName WsusRepairPlan

        { Invoke-WsusRepairAction -Action EnableSqlTcpIp } | Should -Throw 'SQL networking registry path not found.'
    }

    It 'delegates content ACL repair to the permissions module' {
        $result = Invoke-WsusRepairAction -Action RepairContentPermissions -ContentPath 'C:\WSUS'

        $result.Success | Should -BeTrue
        $result.ContentPath | Should -Be 'C:\WSUS'
        Should -Invoke Repair-WsusContentPermissions -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $ContentPath -eq 'C:\WSUS' }
    }

    It 'repairs the IIS content path using the default WsusContent child path' {
        $result = Invoke-WsusRepairAction -Action RepairIisContentPath -ContentPath 'C:\WSUS'

        $result.PhysicalPath | Should -Be 'C:\WSUS\WsusContent'
        Should -Invoke Set-WsusHostIisContentPath -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $PhysicalPath -eq 'C:\WSUS\WsusContent' }
    }

    It 'throws when the IIS content path adapter is unavailable' {
        Mock Get-Command { $null } -ModuleName WsusRepairPlan -ParameterFilter { $Name -eq 'Set-WsusHostIisContentPath' }

        { Invoke-WsusRepairAction -Action RepairIisContentPath } | Should -Throw 'Set-WsusHostIisContentPath is not available.'
    }

    It 'runs wsusutil reset through the host command adapter' {
        Invoke-WsusRepairAction -Action ResetWsusContent -ContentPath 'C:\WSUS' -SqlInstance '.\SQLEXPRESS' | Should -BeTrue

        Should -Invoke New-WsusHostEnvironment -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $SqlInstance -eq '.\SQLEXPRESS' -and $ContentPath -eq 'C:\WSUS' }
        Should -Invoke Invoke-WsusHostCommand -ModuleName WsusRepairPlan -Times 1 -ParameterFilter {
            $FilePath -like '*wsusutil.exe' -and $ArgumentList -contains 'reset'
        }
    }

    It 'throws the wsusutil error when reset fails with an adapter error' {
        Mock Invoke-WsusHostCommand { [pscustomobject]@{ Success = $false; ExitCode = 13; Output = @(); Error = 'reset failed' } } -ModuleName WsusRepairPlan

        { Invoke-WsusRepairAction -Action ResetWsusContent } | Should -Throw 'reset failed'
    }

    It 'throws the wsusutil exit code when reset fails without an adapter error' {
        Mock Invoke-WsusHostCommand { [pscustomobject]@{ Success = $false; ExitCode = 7; Output = @(); Error = $null } } -ModuleName WsusRepairPlan

        { Invoke-WsusRepairAction -Action ResetWsusContent } | Should -Throw 'wsusutil reset failed with exit code 7'
    }

    It 'starts the WSUS application pool through WebAdministration' {
        Remove-Item Env:\WsusRepairPlanStartWebAppPoolName -ErrorAction SilentlyContinue

        Invoke-WsusRepairAction -Action StartWsusPool | Should -BeTrue

        Should -Invoke Import-Module -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'WebAdministration' }
        $env:WsusRepairPlanStartWebAppPoolName | Should -Be 'WsusPool'
    }

    It 'tunes the WSUS application pool queue, memory, idle, and recycle settings' {
        Invoke-WsusRepairAction -Action TuneWsusPool | Should -BeTrue

        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Path -eq 'IIS:\AppPools\WsusPool' -and $Name -eq 'queueLength' -and $Value -eq 25000 }
        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'recycling.periodicRestart.privateMemory' -and $Value -eq 0 }
        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'processModel.idleTimeout' -and $Value -eq '00:00:00' }
        Should -Invoke Set-ItemProperty -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'recycling.periodicRestart.time' -and $Value -eq '00:00:00' }
    }

    It 'starts service-based repair actions with their expected service names' -ForEach @(
        @{ Action = 'StartBits'; ServiceName = 'BITS' },
        @{ Action = 'StartSqlService'; ServiceName = 'MSSQL$SQLEXPRESS' },
        @{ Action = 'StartWsusService'; ServiceName = 'WsusService' },
        @{ Action = 'StartIisService'; ServiceName = 'W3SVC' }
    ) {
        Invoke-WsusRepairAction -Action $Action -SqlServiceName 'MSSQL$SQLEXPRESS' | Should -BeTrue

        Should -Invoke Start-WsusHostService -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq $ServiceName }
    }

    It 'makes SQL Browser automatic before starting it' {
        Invoke-WsusRepairAction -Action StartSqlBrowser | Should -BeTrue

        Should -Invoke Set-Service -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'SQLBrowser' -and $StartupType -eq 'Automatic' }
        Should -Invoke Start-WsusHostService -ModuleName WsusRepairPlan -Times 1 -ParameterFilter { $Name -eq 'SQLBrowser' }
    }

    It 'delegates firewall repairs to the firewall module' {
        Invoke-WsusRepairAction -Action RepairSqlFirewall | Should -BeTrue
        Invoke-WsusRepairAction -Action RepairWsusFirewall | Should -BeTrue

        Should -Invoke Repair-SqlFirewallRules -ModuleName WsusRepairPlan -Times 1
        Should -Invoke Repair-WsusFirewallRules -ModuleName WsusRepairPlan -Times 1
    }

    It 'grants NETWORK SERVICE SQL login and dbcreator role using short master queries' {
        Invoke-WsusRepairAction -Action GrantNetworkServiceLogin -SqlInstance '.\SQLEXPRESS' | Should -BeTrue

        Should -Invoke Invoke-WsusHostSqlQuery -ModuleName WsusRepairPlan -Times 1 -ParameterFilter {
            $ServerInstance -eq '.\SQLEXPRESS' -and
            $Database -eq 'master' -and
            $Query -like 'CREATE LOGIN*NETWORK SERVICE*' -and
            $QueryTimeout -eq 10
        }
        Should -Invoke Invoke-WsusHostSqlQuery -ModuleName WsusRepairPlan -Times 1 -ParameterFilter {
            $ServerInstance -eq '.\SQLEXPRESS' -and
            $Database -eq 'master' -and
            $Query -like 'ALTER SERVER ROLE*dbcreator*NETWORK SERVICE*' -and
            $QueryTimeout -eq 10
        }
    }
}
