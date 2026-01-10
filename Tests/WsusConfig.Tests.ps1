#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusConfig.psm1

.DESCRIPTION
    Unit tests for the WSUS configuration module functions.
    These tests can run without Windows Server or WSUS installed.
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\Modules\WsusConfig.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module WsusConfig -Force -ErrorAction SilentlyContinue
}

Describe 'WsusConfig Module' {
    Context 'Module Loading' {
        It 'Should export expected functions' {
            $exportedFunctions = (Get-Module WsusConfig).ExportedFunctions.Keys
            $expectedFunctions = @(
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
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }

    Context 'Get-WsusConfig' {
        It 'Should return entire config when no key specified' {
            $config = Get-WsusConfig
            $config | Should -BeOfType [hashtable]
            $config.Keys | Should -Contain 'SqlInstance'
            $config.Keys | Should -Contain 'DatabaseName'
            $config.Keys | Should -Contain 'Services'
        }

        It 'Should return specific value for top-level key' {
            $sqlInstance = Get-WsusConfig -Key 'SqlInstance'
            $sqlInstance | Should -Be '.\SQLEXPRESS'
        }

        It 'Should return specific value for nested key using dot notation' {
            $wsusService = Get-WsusConfig -Key 'Services.Wsus'
            $wsusService | Should -Be 'WSUSService'
        }

        It 'Should return null for non-existent key' {
            $result = Get-WsusConfig -Key 'NonExistentKey'
            $result | Should -BeNullOrEmpty
        }

        It 'Should return null for non-existent nested key' {
            $result = Get-WsusConfig -Key 'Services.NonExistent'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Set-WsusConfig' {
        BeforeEach {
            # Store original value to restore after test
            $script:originalSqlInstance = Get-WsusConfig -Key 'SqlInstance'
        }

        AfterEach {
            # Restore original value
            Set-WsusConfig -Key 'SqlInstance' -Value $script:originalSqlInstance
        }

        It 'Should set top-level configuration value' {
            Set-WsusConfig -Key 'SqlInstance' -Value 'localhost\TESTINSTANCE'
            $result = Get-WsusConfig -Key 'SqlInstance'
            $result | Should -Be 'localhost\TESTINSTANCE'
        }

        It 'Should set nested configuration value' {
            $originalTimeout = Get-WsusConfig -Key 'Timeouts.SqlQueryDefault'
            Set-WsusConfig -Key 'Timeouts.SqlQueryDefault' -Value 60
            $result = Get-WsusConfig -Key 'Timeouts.SqlQueryDefault'
            $result | Should -Be 60
            # Restore
            Set-WsusConfig -Key 'Timeouts.SqlQueryDefault' -Value $originalTimeout
        }

        It 'Should throw for invalid nested key path' {
            { Set-WsusConfig -Key 'Invalid.Path.Key' -Value 'test' } | Should -Throw
        }
    }

    Context 'Get-SqlInstanceName' {
        It 'Should return short format' {
            $result = Get-SqlInstanceName -Format 'Short'
            $result | Should -Be 'SQLEXPRESS'
        }

        It 'Should return dot format by default' {
            $result = Get-SqlInstanceName
            $result | Should -Be '.\SQLEXPRESS'
        }

        It 'Should return dot format explicitly' {
            $result = Get-SqlInstanceName -Format 'Dot'
            $result | Should -Be '.\SQLEXPRESS'
        }

        It 'Should return localhost format' {
            $result = Get-SqlInstanceName -Format 'Localhost'
            $result | Should -Be 'localhost\SQLEXPRESS'
        }
    }

    Context 'Get-WsusServiceName' {
        It 'Should return SQL Express service name' {
            $result = Get-WsusServiceName -Service 'SqlExpress'
            $result | Should -Be 'MSSQL$SQLEXPRESS'
        }

        It 'Should return WSUS service name' {
            $result = Get-WsusServiceName -Service 'Wsus'
            $result | Should -Be 'WSUSService'
        }

        It 'Should return IIS service name' {
            $result = Get-WsusServiceName -Service 'Iis'
            $result | Should -Be 'W3SVC'
        }

        It 'Should return Windows Update service name' {
            $result = Get-WsusServiceName -Service 'WindowsUpdate'
            $result | Should -Be 'wuauserv'
        }

        It 'Should return BITS service name' {
            $result = Get-WsusServiceName -Service 'Bits'
            $result | Should -Be 'bits'
        }
    }

    Context 'Get-WsusTimeout' {
        It 'Should return default SQL query timeout' {
            $result = Get-WsusTimeout -Type 'SqlQueryDefault'
            $result | Should -Be 30
        }

        It 'Should return long SQL query timeout' {
            $result = Get-WsusTimeout -Type 'SqlQueryLong'
            $result | Should -Be 300
        }

        It 'Should return unlimited SQL query timeout' {
            $result = Get-WsusTimeout -Type 'SqlQueryUnlimited'
            $result | Should -Be 0
        }

        It 'Should return service start timeout' {
            $result = Get-WsusTimeout -Type 'ServiceStart'
            $result | Should -Be 10
        }

        It 'Should return service stop timeout' {
            $result = Get-WsusTimeout -Type 'ServiceStop'
            $result | Should -Be 5
        }
    }

    Context 'Get-WsusMaintenanceSetting' {
        It 'Should return backup retention days' {
            $result = Get-WsusMaintenanceSetting -Setting 'BackupRetentionDays'
            $result | Should -Be 90
        }

        It 'Should return default export days' {
            $result = Get-WsusMaintenanceSetting -Setting 'DefaultExportDays'
            $result | Should -Be 30
        }

        It 'Should return index fragmentation threshold' {
            $result = Get-WsusMaintenanceSetting -Setting 'IndexFragmentationThreshold'
            $result | Should -Be 10
        }

        It 'Should return batch size' {
            $result = Get-WsusMaintenanceSetting -Setting 'BatchSize'
            $result | Should -Be 100
        }
    }

    Context 'Get-WsusConnectionString' {
        It 'Should return valid connection string format' {
            $result = Get-WsusConnectionString
            $result | Should -Match 'Server=.*SQLEXPRESS'
            $result | Should -Match 'Database=SUSDB'
            $result | Should -Match 'Integrated Security=True'
        }

        It 'Should contain correct SQL instance' {
            $result = Get-WsusConnectionString
            $result | Should -Be 'Server=.\SQLEXPRESS;Database=SUSDB;Integrated Security=True'
        }
    }

    Context 'Initialize-WsusConfigFromFile' {
        It 'Should return false for non-existent file' {
            $result = Initialize-WsusConfigFromFile -Path 'C:\NonExistent\config.json'
            $result | Should -Be $false
        }
    }

    Context 'Default Configuration Values' {
        It 'Should have correct default content path' {
            $config = Get-WsusConfig
            $config.ContentPath | Should -Be 'C:\WSUS'
        }

        It 'Should have correct default database name' {
            $config = Get-WsusConfig
            $config.DatabaseName | Should -Be 'SUSDB'
        }

        It 'Should have correct default WSUS port' {
            $config = Get-WsusConfig
            $config.WsusPort | Should -Be 8530
        }

        It 'Should have correct default WSUS SSL port' {
            $config = Get-WsusConfig
            $config.WsusSslPort | Should -Be 8531
        }

        It 'Should have correct DVD volume size' {
            $config = Get-WsusConfig
            $config.DvdExport.VolumeSizeMB | Should -Be 4300
        }
    }
}
