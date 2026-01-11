#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusConfig.psm1

.DESCRIPTION
    Unit tests for the WsusConfig module functions including:
    - Configuration retrieval (Get-WsusConfig)
    - Configuration setting (Set-WsusConfig)
    - Helper functions for SQL, paths, services, timeouts
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusConfig.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusConfig -ErrorAction SilentlyContinue
}

Describe "WsusConfig Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusConfig | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusConfig function" {
            Get-Command Get-WsusConfig -Module WsusConfig | Should -Not -BeNullOrEmpty
        }

        It "Should export Set-WsusConfig function" {
            Get-Command Set-WsusConfig -Module WsusConfig | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-SqlInstanceName function" {
            Get-Command Get-SqlInstanceName -Module WsusConfig | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WsusConfig" {
    Context "Without Key parameter" {
        It "Should return entire configuration hashtable" {
            $config = Get-WsusConfig
            $config | Should -BeOfType [hashtable]
        }

        It "Should contain SqlInstance key" {
            $config = Get-WsusConfig
            $config.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Should contain Services key" {
            $config = Get-WsusConfig
            $config.Services | Should -BeOfType [hashtable]
        }

        It "Should contain Timeouts key" {
            $config = Get-WsusConfig
            $config.Timeouts | Should -BeOfType [hashtable]
        }
    }

    Context "With Key parameter" {
        It "Should return SqlInstance value" {
            $result = Get-WsusConfig -Key "SqlInstance"
            $result | Should -Be ".\SQLEXPRESS"
        }

        It "Should return DatabaseName value" {
            $result = Get-WsusConfig -Key "DatabaseName"
            $result | Should -Be "SUSDB"
        }

        It "Should return ContentPath value" {
            $result = Get-WsusConfig -Key "ContentPath"
            $result | Should -Be "C:\WSUS"
        }

        It "Should return WsusPort value" {
            $result = Get-WsusConfig -Key "WsusPort"
            $result | Should -Be 8530
        }

        It "Should return WsusSslPort value" {
            $result = Get-WsusConfig -Key "WsusSslPort"
            $result | Should -Be 8531
        }
    }

    Context "With nested Key parameter (dot notation)" {
        It "Should return Services.Wsus value" {
            $result = Get-WsusConfig -Key "Services.Wsus"
            $result | Should -Be "WSUSService"
        }

        It "Should return Services.SqlExpress value" {
            $result = Get-WsusConfig -Key "Services.SqlExpress"
            $result | Should -Be 'MSSQL$SQLEXPRESS'
        }

        It "Should return Timeouts.SqlQueryDefault value" {
            $result = Get-WsusConfig -Key "Timeouts.SqlQueryDefault"
            $result | Should -Be 30
        }

        It "Should return Maintenance.BackupRetentionDays value" {
            $result = Get-WsusConfig -Key "Maintenance.BackupRetentionDays"
            $result | Should -Be 90
        }

        It "Should return null for non-existent nested key" {
            $result = Get-WsusConfig -Key "Services.NonExistent"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "With invalid Key parameter" {
        It "Should return null for non-existent key" {
            $result = Get-WsusConfig -Key "NonExistentKey"
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Set-WsusConfig" {
    BeforeEach {
        # Store original values to restore after tests
        $script:OriginalSqlInstance = Get-WsusConfig -Key "SqlInstance"
    }

    AfterEach {
        # Restore original values
        Set-WsusConfig -Key "SqlInstance" -Value $script:OriginalSqlInstance
    }

    It "Should set a top-level configuration value" {
        Set-WsusConfig -Key "SqlInstance" -Value "localhost\TEST"
        $result = Get-WsusConfig -Key "SqlInstance"
        $result | Should -Be "localhost\TEST"
    }

    It "Should set a nested configuration value" {
        $originalValue = Get-WsusConfig -Key "Timeouts.SqlQueryDefault"
        Set-WsusConfig -Key "Timeouts.SqlQueryDefault" -Value 60
        $result = Get-WsusConfig -Key "Timeouts.SqlQueryDefault"
        $result | Should -Be 60
        # Restore
        Set-WsusConfig -Key "Timeouts.SqlQueryDefault" -Value $originalValue
    }

    It "Should throw for non-existent nested parent key" {
        { Set-WsusConfig -Key "NonExistent.Key" -Value "test" } | Should -Throw
    }
}

Describe "Get-SqlInstanceName" {
    It "Should return Short format" {
        $result = Get-SqlInstanceName -Format 'Short'
        $result | Should -Be "SQLEXPRESS"
    }

    It "Should return Dot format" {
        $result = Get-SqlInstanceName -Format 'Dot'
        $result | Should -Be ".\SQLEXPRESS"
    }

    It "Should return Localhost format" {
        $result = Get-SqlInstanceName -Format 'Localhost'
        $result | Should -Be "localhost\SQLEXPRESS"
    }

    It "Should default to Dot format" {
        $result = Get-SqlInstanceName
        $result | Should -Be ".\SQLEXPRESS"
    }
}

Describe "Get-WsusLogPath" {
    It "Should return a valid path string" {
        $result = Get-WsusLogPath
        $result | Should -Be "C:\WSUS\Logs"
    }
}

Describe "Get-WsusServiceName" {
    It "Should return SqlExpress service name" {
        $result = Get-WsusServiceName -Service 'SqlExpress'
        $result | Should -Be 'MSSQL$SQLEXPRESS'
    }

    It "Should return Wsus service name" {
        $result = Get-WsusServiceName -Service 'Wsus'
        $result | Should -Be "WSUSService"
    }

    It "Should return Iis service name" {
        $result = Get-WsusServiceName -Service 'Iis'
        $result | Should -Be "W3SVC"
    }

    It "Should return WindowsUpdate service name" {
        $result = Get-WsusServiceName -Service 'WindowsUpdate'
        $result | Should -Be "wuauserv"
    }

    It "Should return Bits service name" {
        $result = Get-WsusServiceName -Service 'Bits'
        $result | Should -Be "bits"
    }
}

Describe "Get-WsusTimeout" {
    It "Should return SqlQueryDefault timeout" {
        $result = Get-WsusTimeout -Type 'SqlQueryDefault'
        $result | Should -Be 30
    }

    It "Should return SqlQueryLong timeout" {
        $result = Get-WsusTimeout -Type 'SqlQueryLong'
        $result | Should -Be 300
    }

    It "Should return SqlQueryUnlimited timeout (0)" {
        $result = Get-WsusTimeout -Type 'SqlQueryUnlimited'
        $result | Should -Be 0
    }

    It "Should return ServiceStart timeout" {
        $result = Get-WsusTimeout -Type 'ServiceStart'
        $result | Should -Be 10
    }

    It "Should return ServiceStop timeout" {
        $result = Get-WsusTimeout -Type 'ServiceStop'
        $result | Should -Be 5
    }
}

Describe "Get-WsusMaintenanceSetting" {
    It "Should return BackupRetentionDays" {
        $result = Get-WsusMaintenanceSetting -Setting 'BackupRetentionDays'
        $result | Should -Be 90
    }

    It "Should return DefaultExportDays" {
        $result = Get-WsusMaintenanceSetting -Setting 'DefaultExportDays'
        $result | Should -Be 30
    }

    It "Should return IndexFragmentationThreshold" {
        $result = Get-WsusMaintenanceSetting -Setting 'IndexFragmentationThreshold'
        $result | Should -Be 10
    }

    It "Should return IndexRebuildThreshold" {
        $result = Get-WsusMaintenanceSetting -Setting 'IndexRebuildThreshold'
        $result | Should -Be 30
    }

    It "Should return BatchSize" {
        $result = Get-WsusMaintenanceSetting -Setting 'BatchSize'
        $result | Should -Be 100
    }
}

Describe "Get-WsusConnectionString" {
    It "Should return a valid connection string" {
        $result = Get-WsusConnectionString
        $result | Should -Match "Server=.*SQLEXPRESS"
        $result | Should -Match "Database=SUSDB"
        $result | Should -Match "Integrated Security=True"
    }
}

Describe "Get-WsusContentPathFromConfig" {
    It "Should return base path without subfolder" {
        $result = Get-WsusContentPathFromConfig
        $result | Should -Not -BeNullOrEmpty
    }

    It "Should return path with subfolder when IncludeSubfolder is set" {
        $result = Get-WsusContentPathFromConfig -IncludeSubfolder
        $result | Should -Match "WsusContent$"
    }
}

Describe "Initialize-WsusConfigFromFile" {
    It "Should return false when config file doesn't exist" {
        $result = Initialize-WsusConfigFromFile -Path "C:\NonExistent\config.json"
        $result | Should -Be $false
    }
}

Describe "Export-WsusConfigToFile" {
    BeforeAll {
        $TestConfigPath = Join-Path $env:TEMP "wsus-test-config.json"
    }

    AfterAll {
        if (Test-Path $TestConfigPath) {
            Remove-Item $TestConfigPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should export configuration to JSON file" {
        Export-WsusConfigToFile -Path $TestConfigPath
        Test-Path $TestConfigPath | Should -Be $true
    }

    It "Should create valid JSON" {
        Export-WsusConfigToFile -Path $TestConfigPath
        $content = Get-Content $TestConfigPath -Raw
        { $content | ConvertFrom-Json } | Should -Not -Throw
    }
}
