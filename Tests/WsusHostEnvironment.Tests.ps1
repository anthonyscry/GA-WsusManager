#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot
    Import-WsusTestModule -ModuleName 'WsusHostEnvironment' -RepoRoot $script:RepoRoot

    $script:HadInvokeWsusSqlcmdFunction = Test-Path function:\global:Invoke-WsusSqlcmd
    $script:OriginalInvokeWsusSqlcmdFunction = if ($script:HadInvokeWsusSqlcmdFunction) { (Get-Item function:\global:Invoke-WsusSqlcmd).ScriptBlock } else { $null }
    Set-Item -Path function:\global:Invoke-WsusSqlcmd -Value {
        param(
            [string]$ServerInstance,
            [string]$Database,
            [string]$Query,
            [int]$QueryTimeout
        )

        $env:WsusHostEnvironmentSqlCall = @($ServerInstance, $Database, $Query, $QueryTimeout) -join '|'
        [pscustomobject]@{ Count = 42; ServerInstance = $ServerInstance; Database = $Database }
    }
}

AfterAll {
    if ($script:HadInvokeWsusSqlcmdFunction) {
        Set-Item -Path function:\global:Invoke-WsusSqlcmd -Value $script:OriginalInvokeWsusSqlcmdFunction
    } else {
        Remove-Item function:\global:Invoke-WsusSqlcmd -ErrorAction SilentlyContinue
    }
    Remove-WsusTestModule -ModuleName 'WsusHostEnvironment'
}

Describe 'WsusHostEnvironment module' {
    It 'exports the host adapter functions used by diagnostics' {
        Get-Command Get-WsusHostServiceState -Module WsusHostEnvironment | Should -Not -BeNullOrEmpty
        Get-Command Invoke-WsusHostSqlQuery -Module WsusHostEnvironment | Should -Not -BeNullOrEmpty
        Get-Command Get-WsusHostSqlNetworkingState -Module WsusHostEnvironment | Should -Not -BeNullOrEmpty
        Get-Command Get-WsusHostIisContentPath -Module WsusHostEnvironment | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-WsusHostServiceState' {
    BeforeEach {
        Mock Get-Service {
            foreach ($serviceName in @($Name)) {
                if ($serviceName -eq 'BITS') {
                    [pscustomobject]@{
                        Name = 'BITS'
                        Status = 'Running'
                        StartType = 'Automatic'
                    }
                }
            }
        } -ModuleName WsusHostEnvironment
    }

    It 'returns one normalized row per requested service including missing services' {
        $result = @(Get-WsusHostServiceState -Name @('BITS', 'MissingService'))

        $result.Count | Should -Be 2
        $result[0].Name | Should -Be 'BITS'
        $result[0].Installed | Should -BeTrue
        $result[0].Running | Should -BeTrue
        $result[0].Status | Should -Be 'Running'
        $result[0].StartType | Should -Be 'Automatic'
        $result[1].Name | Should -Be 'MissingService'
        $result[1].Installed | Should -BeFalse
        $result[1].Running | Should -BeFalse
        $result[1].Status | Should -Be 'NotInstalled'
        $result[1].StartType | Should -Be 'Unknown'
    }
}

Describe 'Invoke-WsusHostSqlQuery' {
    It 'prefers the repository SQL adapter and forwards query parameters' {
        Remove-Item Env:\WsusHostEnvironmentSqlCall -ErrorAction SilentlyContinue

        $result = Invoke-WsusHostSqlQuery -ServerInstance '.\SQLEXPRESS' -Database 'SUSDB' -Query 'SELECT 42 AS Count' -QueryTimeout 12
        $sqlCall = $env:WsusHostEnvironmentSqlCall -split '\|'

        $result.Count | Should -Be 42
        $sqlCall[0] | Should -Be '.\SQLEXPRESS'
        $sqlCall[1] | Should -Be 'SUSDB'
        $sqlCall[2] | Should -Be 'SELECT 42 AS Count'
        [int]$sqlCall[3] | Should -Be 12
    }

    It 'throws a clear error when no SQL adapter exists' {
        Mock Get-Command { $null } -ModuleName WsusHostEnvironment -ParameterFilter {
            $Name -in @('Invoke-WsusSqlcmd', 'Invoke-Sqlcmd')
        }

        { Invoke-WsusHostSqlQuery -ServerInstance '.\SQLEXPRESS' -Query 'SELECT 1' } | Should -Throw 'No SQL command adapter is available.'
    }
}

Describe 'Get-WsusHostSqlNetworkingState' {
    It 'reports static TCP 1433 and named pipes settings from the SQL registry path' {
        Mock Test-Path {
            $Path -like '*MSSQL15.SQLEXPRESS\MSSQLServer\SuperSocketNetLib'
        } -ModuleName WsusHostEnvironment
        Mock Get-ItemProperty {
            if ($Path -like '*\Tcp\IPAll') {
                [pscustomobject]@{ TcpPort = '1433'; TcpDynamicPorts = '' }
            } elseif ($Path -like '*\Tcp') {
                [pscustomobject]@{ Enabled = 1 }
            } elseif ($Path -like '*\Np') {
                [pscustomobject]@{ Enabled = 1 }
            }
        } -ModuleName WsusHostEnvironment

        $state = Get-WsusHostSqlNetworkingState -SqlInstance '.\SQLEXPRESS'

        $state.Found | Should -BeTrue
        $state.Instance | Should -Be 'SQLEXPRESS'
        $state.TcpEnabled | Should -Be 1
        $state.TcpPort | Should -Be '1433'
        $state.NamedPipesEnabled | Should -Be 1
        $state.StaticPort1433 | Should -BeTrue
    }

    It 'returns a non-found shape without touching registry values when no SQL path exists' {
        Mock Test-Path { $false } -ModuleName WsusHostEnvironment
        Mock Get-ItemProperty { throw 'Get-ItemProperty should not run for missing registry paths.' } -ModuleName WsusHostEnvironment

        $state = Get-WsusHostSqlNetworkingState -SqlInstance 'localhost'

        $state.Found | Should -BeFalse
        $state.Instance | Should -Be 'MSSQLSERVER'
        $state.RegistryPath | Should -BeNullOrEmpty
        $state.StaticPort1433 | Should -BeFalse
        Should -Invoke Get-ItemProperty -ModuleName WsusHostEnvironment -Times 0
    }
}

Describe 'Get-WsusHostIisContentPath' {
    It 'normalizes the IIS content virtual directory and matches the expected path ignoring trailing slashes' {
        Mock Import-Module { } -ModuleName WsusHostEnvironment -ParameterFilter { $Name -eq 'WebAdministration' }
        Mock Test-Path { $true } -ModuleName WsusHostEnvironment -ParameterFilter { $Path -eq 'IIS:\Sites\WSUS Administration\Content' }
        Mock Get-ItemProperty { [pscustomobject]@{ physicalPath = 'D:\WSUS\WsusContent\' } } -ModuleName WsusHostEnvironment

        $state = Get-WsusHostIisContentPath -ExpectedPath 'D:\WSUS\WsusContent'

        $state.Found | Should -BeTrue
        $state.PhysicalPath | Should -Be 'D:\WSUS\WsusContent\'
        $state.MatchesExpected | Should -BeTrue
    }

    It 'returns a non-found result with error details when IIS administration cannot be loaded' {
        Mock Import-Module { throw 'WebAdministration is unavailable' } -ModuleName WsusHostEnvironment -ParameterFilter { $Name -eq 'WebAdministration' }

        $state = Get-WsusHostIisContentPath -ExpectedPath 'D:\WSUS\WsusContent'

        $state.Found | Should -BeFalse
        $state.PhysicalPath | Should -BeNullOrEmpty
        $state.MatchesExpected | Should -BeFalse
        $state.Error | Should -Match 'WebAdministration is unavailable'
    }
}
