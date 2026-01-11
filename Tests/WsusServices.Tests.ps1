#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusServices.psm1

.DESCRIPTION
    Unit tests for the WsusServices module functions including:
    - Service state checking (Test-ServiceRunning, Test-ServiceExists)
    - Service wait functions (Wait-ServiceState)
    - Service start/stop functions
    - Comprehensive service status functions

.NOTES
    These tests use mocking to avoid actually starting/stopping services.
    Some tests require actual services to exist on the system.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusServices.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusServices -ErrorAction SilentlyContinue
}

Describe "WsusServices Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusServices | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-ServiceRunning function" {
            Get-Command Test-ServiceRunning -Module WsusServices | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-ServiceExists function" {
            Get-Command Test-ServiceExists -Module WsusServices | Should -Not -BeNullOrEmpty
        }

        It "Should export Start-WsusService function" {
            Get-Command Start-WsusService -Module WsusServices | Should -Not -BeNullOrEmpty
        }

        It "Should export Stop-WsusService function" {
            Get-Command Stop-WsusService -Module WsusServices | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusServiceStatus function" {
            Get-Command Get-WsusServiceStatus -Module WsusServices | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Test-ServiceExists" {
    Context "With real services" {
        It "Should return true for existing service (Spooler)" {
            $result = Test-ServiceExists -ServiceName "Spooler"
            $result | Should -Be $true
        }

        It "Should return true for existing service (W32Time)" {
            $result = Test-ServiceExists -ServiceName "W32Time"
            $result | Should -Be $true
        }

        It "Should return false for non-existent service" {
            $result = Test-ServiceExists -ServiceName "NonExistentService12345"
            $result | Should -Be $false
        }
    }
}

Describe "Test-ServiceRunning" {
    Context "With real services" {
        It "Should return boolean for existing service" {
            $result = Test-ServiceRunning -ServiceName "Spooler"
            $result | Should -BeOfType [bool]
        }

        It "Should return false for non-existent service" {
            $result = Test-ServiceRunning -ServiceName "NonExistentService12345"
            $result | Should -Be $false
        }
    }

    Context "With mocked services" {
        BeforeAll {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "MockService"
                    Status = "Running"
                }
            } -ModuleName WsusServices
        }

        It "Should return true when service is running" {
            $result = Test-ServiceRunning -ServiceName "MockService"
            $result | Should -Be $true
        }
    }

    Context "With mocked stopped service" {
        BeforeAll {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "MockService"
                    Status = "Stopped"
                }
            } -ModuleName WsusServices
        }

        It "Should return false when service is stopped" {
            $result = Test-ServiceRunning -ServiceName "MockService"
            $result | Should -Be $false
        }
    }
}

Describe "Wait-ServiceState" {
    Context "With mocked service already in target state" {
        BeforeAll {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "MockService"
                    Status = "Running"
                }
            } -ModuleName WsusServices
        }

        It "Should return true immediately when service is already in target state" {
            $result = Wait-ServiceState -ServiceName "MockService" -TargetState "Running" -TimeoutSeconds 5
            $result | Should -Be $true
        }
    }

    Context "With non-existent service" {
        BeforeAll {
            Mock Get-Service {
                throw "Service not found"
            } -ModuleName WsusServices
        }

        It "Should return false for non-existent service" {
            $result = Wait-ServiceState -ServiceName "NonExistent" -TargetState "Running" -TimeoutSeconds 1
            $result | Should -Be $false
        }
    }
}

Describe "Get-WsusServiceStatus" {
    It "Should return a hashtable" {
        $result = Get-WsusServiceStatus
        $result | Should -BeOfType [hashtable]
    }

    It "Should contain SQL Server Express key" {
        $result = Get-WsusServiceStatus
        $result.Keys | Should -Contain "SQL Server Express"
    }

    It "Should contain WSUS Service key" {
        $result = Get-WsusServiceStatus
        $result.Keys | Should -Contain "WSUS Service"
    }

    It "Should contain IIS key" {
        $result = Get-WsusServiceStatus
        $result.Keys | Should -Contain "IIS"
    }

    It "Should return status info for each service" {
        $result = Get-WsusServiceStatus
        foreach ($key in $result.Keys) {
            $result[$key] | Should -BeOfType [hashtable]
            $result[$key].Keys | Should -Contain "Status"
            $result[$key].Keys | Should -Contain "Running"
        }
    }
}

Describe "Start-WsusService" {
    Context "With mocked already running service" {
        BeforeAll {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "MockService"
                    Status = "Running"
                }
            } -ModuleName WsusServices
        }

        It "Should return true when service is already running" {
            $result = Start-WsusService -ServiceName "MockService"
            $result | Should -Be $true
        }
    }

    Context "With mocked service start success" {
        BeforeAll {
            $script:CallCount = 0
            Mock Get-Service {
                $script:CallCount++
                if ($script:CallCount -eq 1) {
                    [PSCustomObject]@{
                        Name = "MockService"
                        Status = "Stopped"
                    }
                } else {
                    [PSCustomObject]@{
                        Name = "MockService"
                        Status = "Running"
                    }
                }
            } -ModuleName WsusServices

            Mock Start-Service { } -ModuleName WsusServices
        }

        AfterAll {
            $script:CallCount = 0
        }

        It "Should attempt to start stopped service" {
            Start-WsusService -ServiceName "MockService" -TimeoutSeconds 2
            Should -Invoke Start-Service -ModuleName WsusServices
        }
    }
}

Describe "Stop-WsusService" {
    Context "With mocked already stopped service" {
        BeforeAll {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "MockService"
                    Status = "Stopped"
                }
            } -ModuleName WsusServices
        }

        It "Should return true when service is already stopped" {
            $result = Stop-WsusService -ServiceName "MockService"
            $result | Should -Be $true
        }
    }

    Context "With mocked service stop success" {
        BeforeAll {
            $script:StopCallCount = 0
            Mock Get-Service {
                $script:StopCallCount++
                if ($script:StopCallCount -eq 1) {
                    [PSCustomObject]@{
                        Name = "MockService"
                        Status = "Running"
                    }
                } else {
                    [PSCustomObject]@{
                        Name = "MockService"
                        Status = "Stopped"
                    }
                }
            } -ModuleName WsusServices

            Mock Stop-Service { } -ModuleName WsusServices
        }

        AfterAll {
            $script:StopCallCount = 0
        }

        It "Should attempt to stop running service" {
            Stop-WsusService -ServiceName "MockService" -TimeoutSeconds 2
            Should -Invoke Stop-Service -ModuleName WsusServices
        }
    }
}

Describe "Restart-WsusService" {
    Context "With mocked service restart" {
        BeforeAll {
            Mock Stop-WsusService { $true } -ModuleName WsusServices
            Mock Start-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call both Stop and Start functions" {
            $result = Restart-WsusService -ServiceName "MockService"
            Should -Invoke Stop-WsusService -ModuleName WsusServices
            Should -Invoke Start-WsusService -ModuleName WsusServices
        }

        It "Should return true when both operations succeed" {
            $result = Restart-WsusService -ServiceName "MockService"
            $result | Should -Be $true
        }
    }

    Context "With mocked stop failure" {
        BeforeAll {
            Mock Stop-WsusService { $false } -ModuleName WsusServices
            Mock Start-WsusService { $true } -ModuleName WsusServices
        }

        It "Should return false when stop fails" {
            $result = Restart-WsusService -ServiceName "MockService"
            $result | Should -Be $false
        }

        It "Should not attempt to start when stop fails" {
            Restart-WsusService -ServiceName "MockService"
            Should -Not -Invoke Start-WsusService -ModuleName WsusServices
        }
    }
}

Describe "Start-SqlServerExpress" {
    Context "With mocked service" {
        BeforeAll {
            Mock Start-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call Start-WsusService with correct service name" {
            Start-SqlServerExpress
            Should -Invoke Start-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'MSSQL$SQLEXPRESS'
            }
        }
    }
}

Describe "Stop-SqlServerExpress" {
    Context "With mocked service" {
        BeforeAll {
            Mock Stop-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call Stop-WsusService with correct service name" {
            Stop-SqlServerExpress
            Should -Invoke Stop-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'MSSQL$SQLEXPRESS'
            }
        }
    }
}

Describe "Start-WsusServer" {
    Context "With mocked service" {
        BeforeAll {
            Mock Start-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call Start-WsusService with WSUSService" {
            Start-WsusServer
            Should -Invoke Start-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq "WSUSService"
            }
        }
    }
}

Describe "Stop-WsusServer" {
    Context "With mocked service" {
        BeforeAll {
            Mock Stop-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call Stop-WsusService with WSUSService" {
            Stop-WsusServer
            Should -Invoke Stop-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq "WSUSService"
            }
        }
    }
}

Describe "Start-IISService" {
    Context "With mocked service" {
        BeforeAll {
            Mock Start-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call Start-WsusService with W3SVC" {
            Start-IISService
            Should -Invoke Start-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq "W3SVC"
            }
        }
    }
}

Describe "Stop-IISService" {
    Context "With mocked service" {
        BeforeAll {
            Mock Stop-WsusService { $true } -ModuleName WsusServices
        }

        It "Should call Stop-WsusService with W3SVC" {
            Stop-IISService
            Should -Invoke Stop-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq "W3SVC"
            }
        }
    }
}

Describe "Start-AllWsusServices" {
    Context "With mocked services" {
        BeforeAll {
            Mock Start-SqlServerExpress { $true } -ModuleName WsusServices
            Mock Start-IISService { $true } -ModuleName WsusServices
            Mock Start-WsusServer { $true } -ModuleName WsusServices
        }

        It "Should return a hashtable with results" {
            $result = Start-AllWsusServices
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain SqlServer result" {
            $result = Start-AllWsusServices
            $result.Keys | Should -Contain "SqlServer"
        }

        It "Should contain IIS result" {
            $result = Start-AllWsusServices
            $result.Keys | Should -Contain "IIS"
        }

        It "Should contain WSUS result" {
            $result = Start-AllWsusServices
            $result.Keys | Should -Contain "WSUS"
        }
    }
}

Describe "Stop-AllWsusServices" {
    Context "With mocked services" {
        BeforeAll {
            Mock Stop-SqlServerExpress { $true } -ModuleName WsusServices
            Mock Stop-IISService { $true } -ModuleName WsusServices
            Mock Stop-WsusServer { $true } -ModuleName WsusServices
        }

        It "Should return a hashtable with results" {
            $result = Stop-AllWsusServices
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain SqlServer result" {
            $result = Stop-AllWsusServices
            $result.Keys | Should -Contain "SqlServer"
        }

        It "Should contain IIS result" {
            $result = Stop-AllWsusServices
            $result.Keys | Should -Contain "IIS"
        }

        It "Should contain WSUS result" {
            $result = Stop-AllWsusServices
            $result.Keys | Should -Contain "WSUS"
        }
    }
}
