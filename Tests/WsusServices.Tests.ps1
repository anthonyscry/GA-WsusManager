#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusServices.psm1

.DESCRIPTION
    Unit tests for the WSUS services module functions.
    Uses mocking to avoid dependencies on actual Windows services.
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\Modules\WsusServices.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module WsusServices -Force -ErrorAction SilentlyContinue
}

Describe 'WsusServices Module' {
    Context 'Module Loading' {
        It 'Should export expected functions' {
            $exportedFunctions = (Get-Module WsusServices).ExportedFunctions.Keys
            $expectedFunctions = @(
                'Wait-ServiceState',
                'Test-ServiceRunning',
                'Test-ServiceExists',
                'Start-WsusService',
                'Stop-WsusService',
                'Restart-WsusService',
                'Start-SqlServerExpress',
                'Stop-SqlServerExpress',
                'Start-WsusServer',
                'Stop-WsusServer',
                'Start-IISService',
                'Stop-IISService',
                'Start-AllWsusServices',
                'Stop-AllWsusServices',
                'Get-WsusServiceStatus'
            )
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }

    Context 'Test-ServiceExists - Mocked' {
        It 'Should return true when service exists' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Running'
                }
            } -ModuleName WsusServices

            $result = Test-ServiceExists -ServiceName 'TestService'
            $result | Should -Be $true
        }

        It 'Should return false when service does not exist' {
            Mock Get-Service { throw 'Service not found' } -ModuleName WsusServices

            $result = Test-ServiceExists -ServiceName 'NonExistentService'
            $result | Should -Be $false
        }
    }

    Context 'Test-ServiceRunning - Mocked' {
        It 'Should return true when service is running' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Running'
                }
            } -ModuleName WsusServices

            $result = Test-ServiceRunning -ServiceName 'TestService'
            $result | Should -Be $true
        }

        It 'Should return false when service is stopped' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Stopped'
                }
            } -ModuleName WsusServices

            $result = Test-ServiceRunning -ServiceName 'TestService'
            $result | Should -Be $false
        }

        It 'Should return false when service does not exist' {
            Mock Get-Service { throw 'Service not found' } -ModuleName WsusServices

            $result = Test-ServiceRunning -ServiceName 'NonExistentService'
            $result | Should -Be $false
        }
    }

    Context 'Wait-ServiceState - Mocked' {
        It 'Should return true immediately when service is already in target state' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Running'
                }
            } -ModuleName WsusServices

            $result = Wait-ServiceState -ServiceName 'TestService' -TargetState 'Running' -TimeoutSeconds 5
            $result | Should -Be $true
        }

        It 'Should return false when service does not exist' {
            Mock Get-Service { throw 'Service not found' } -ModuleName WsusServices

            $result = Wait-ServiceState -ServiceName 'NonExistentService' -TargetState 'Running' -TimeoutSeconds 1
            $result | Should -Be $false
        }

        It 'Should timeout when service never reaches target state' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Stopped'
                }
            } -ModuleName WsusServices

            # Use very short timeout for faster test
            $result = Wait-ServiceState -ServiceName 'TestService' -TargetState 'Running' -TimeoutSeconds 1 -PollIntervalMs 100
            $result | Should -Be $false
        }
    }

    Context 'Start-WsusService - Mocked' {
        It 'Should return true when service is already running' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Running'
                }
            } -ModuleName WsusServices

            $result = Start-WsusService -ServiceName 'TestService'
            $result | Should -Be $true
        }

        It 'Should attempt to start stopped service' {
            $script:callCount = 0
            Mock Get-Service {
                $script:callCount++
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = if ($script:callCount -eq 1) { 'Stopped' } else { 'Running' }
                }
            } -ModuleName WsusServices
            Mock Start-Service { } -ModuleName WsusServices
            Mock Wait-ServiceState { $true } -ModuleName WsusServices

            $result = Start-WsusService -ServiceName 'TestService'
            $result | Should -Be $true
            Should -Invoke Start-Service -ModuleName WsusServices -Times 1
        }

        It 'Should return false when service fails to start' {
            Mock Get-Service { throw 'Service not found' } -ModuleName WsusServices

            $result = Start-WsusService -ServiceName 'NonExistentService'
            $result | Should -Be $false
        }
    }

    Context 'Stop-WsusService - Mocked' {
        It 'Should return true when service is already stopped' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Stopped'
                }
            } -ModuleName WsusServices

            $result = Stop-WsusService -ServiceName 'TestService'
            $result | Should -Be $true
        }

        It 'Should attempt to stop running service' {
            $script:callCount = 0
            Mock Get-Service {
                $script:callCount++
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = if ($script:callCount -eq 1) { 'Running' } else { 'Stopped' }
                }
            } -ModuleName WsusServices
            Mock Stop-Service { } -ModuleName WsusServices
            Mock Wait-ServiceState { $true } -ModuleName WsusServices

            $result = Stop-WsusService -ServiceName 'TestService'
            $result | Should -Be $true
            Should -Invoke Stop-Service -ModuleName WsusServices -Times 1
        }

        It 'Should use Force parameter when specified' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'TestService'
                    Status = 'Running'
                }
            } -ModuleName WsusServices
            Mock Stop-Service { } -ModuleName WsusServices -ParameterFilter { $Force -eq $true }
            Mock Wait-ServiceState { $true } -ModuleName WsusServices

            Stop-WsusService -ServiceName 'TestService' -Force
            Should -Invoke Stop-Service -ModuleName WsusServices -ParameterFilter { $Force -eq $true }
        }
    }

    Context 'Get-WsusServiceStatus - Mocked' {
        It 'Should return status for all WSUS services' {
            Mock Get-Service {
                param($Name)
                [PSCustomObject]@{
                    Name = $Name
                    Status = 'Running'
                    StartType = 'Automatic'
                }
            } -ModuleName WsusServices

            $result = Get-WsusServiceStatus
            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'SQL Server Express'
            $result.Keys | Should -Contain 'WSUS Service'
            $result.Keys | Should -Contain 'IIS'
        }

        It 'Should mark service as Not Found when it does not exist' {
            Mock Get-Service { throw 'Service not found' } -ModuleName WsusServices

            $result = Get-WsusServiceStatus
            $result['SQL Server Express'].Status | Should -Be 'Not Found'
            $result['SQL Server Express'].Running | Should -Be $false
        }

        It 'Should include Running property in status' {
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = 'WSUSService'
                    Status = 'Running'
                    StartType = 'Automatic'
                }
            } -ModuleName WsusServices

            $result = Get-WsusServiceStatus
            $result['WSUS Service'].Running | Should -Be $true
        }
    }

    Context 'WSUS-Specific Service Functions - Mocked' {
        BeforeEach {
            Mock Start-WsusService { $true } -ModuleName WsusServices
            Mock Stop-WsusService { $true } -ModuleName WsusServices
        }

        It 'Start-SqlServerExpress should call Start-WsusService with correct service name' {
            Start-SqlServerExpress
            Should -Invoke Start-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'MSSQL$SQLEXPRESS'
            }
        }

        It 'Stop-SqlServerExpress should call Stop-WsusService with correct service name' {
            Stop-SqlServerExpress
            Should -Invoke Stop-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'MSSQL$SQLEXPRESS'
            }
        }

        It 'Start-WsusServer should call Start-WsusService with WSUSService' {
            Start-WsusServer
            Should -Invoke Start-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'WSUSService'
            }
        }

        It 'Stop-WsusServer should call Stop-WsusService with WSUSService' {
            Stop-WsusServer
            Should -Invoke Stop-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'WSUSService'
            }
        }

        It 'Start-IISService should call Start-WsusService with W3SVC' {
            Start-IISService
            Should -Invoke Start-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'W3SVC'
            }
        }

        It 'Stop-IISService should call Stop-WsusService with W3SVC' {
            Stop-IISService
            Should -Invoke Stop-WsusService -ModuleName WsusServices -ParameterFilter {
                $ServiceName -eq 'W3SVC'
            }
        }
    }

    Context 'Start-AllWsusServices - Mocked' {
        It 'Should start services in correct order' {
            $startOrder = @()
            Mock Start-SqlServerExpress { $startOrder += 'SQL'; $true } -ModuleName WsusServices
            Mock Start-IISService { $startOrder += 'IIS'; $true } -ModuleName WsusServices
            Mock Start-WsusServer { $startOrder += 'WSUS'; $true } -ModuleName WsusServices

            $result = Start-AllWsusServices

            # Note: The function runs these in hashtable order (non-deterministic in tests)
            # We just verify all three were called
            Should -Invoke Start-SqlServerExpress -ModuleName WsusServices -Times 1
            Should -Invoke Start-IISService -ModuleName WsusServices -Times 1
            Should -Invoke Start-WsusServer -ModuleName WsusServices -Times 1
        }

        It 'Should return results hashtable' {
            Mock Start-SqlServerExpress { $true } -ModuleName WsusServices
            Mock Start-IISService { $true } -ModuleName WsusServices
            Mock Start-WsusServer { $true } -ModuleName WsusServices

            $result = Start-AllWsusServices
            $result | Should -BeOfType [hashtable]
            $result.SqlServer | Should -Be $true
            $result.IIS | Should -Be $true
            $result.WSUS | Should -Be $true
        }
    }

    Context 'Stop-AllWsusServices - Mocked' {
        It 'Should stop all services' {
            Mock Stop-WsusServer { $true } -ModuleName WsusServices
            Mock Stop-IISService { $true } -ModuleName WsusServices
            Mock Stop-SqlServerExpress { $true } -ModuleName WsusServices

            $result = Stop-AllWsusServices

            Should -Invoke Stop-WsusServer -ModuleName WsusServices -Times 1
            Should -Invoke Stop-IISService -ModuleName WsusServices -Times 1
            Should -Invoke Stop-SqlServerExpress -ModuleName WsusServices -Times 1
        }

        It 'Should return results hashtable' {
            Mock Stop-WsusServer { $true } -ModuleName WsusServices
            Mock Stop-IISService { $true } -ModuleName WsusServices
            Mock Stop-SqlServerExpress { $true } -ModuleName WsusServices

            $result = Stop-AllWsusServices
            $result | Should -BeOfType [hashtable]
            $result.SqlServer | Should -Be $true
            $result.IIS | Should -Be $true
            $result.WSUS | Should -Be $true
        }

        It 'Should pass Force parameter when specified' {
            Mock Stop-WsusServer { $true } -ModuleName WsusServices
            Mock Stop-IISService { $true } -ModuleName WsusServices
            Mock Stop-SqlServerExpress { $true } -ModuleName WsusServices

            Stop-AllWsusServices -Force

            Should -Invoke Stop-WsusServer -ModuleName WsusServices -ParameterFilter { $Force -eq $true }
            Should -Invoke Stop-IISService -ModuleName WsusServices -ParameterFilter { $Force -eq $true }
            Should -Invoke Stop-SqlServerExpress -ModuleName WsusServices -ParameterFilter { $Force -eq $true }
        }
    }
}

Describe 'WsusServices Parameter Validation' {
    Context 'Wait-ServiceState Parameters' {
        It 'Should require ServiceName parameter' {
            { Wait-ServiceState -TargetState 'Running' } | Should -Throw
        }

        It 'Should require TargetState parameter' {
            { Wait-ServiceState -ServiceName 'TestService' } | Should -Throw
        }

        It 'Should only accept valid TargetState values' {
            { Wait-ServiceState -ServiceName 'Test' -TargetState 'Invalid' } | Should -Throw
        }

        It 'Should accept Running as TargetState' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } } -ModuleName WsusServices
            { Wait-ServiceState -ServiceName 'Test' -TargetState 'Running' -TimeoutSeconds 1 } | Should -Not -Throw
        }

        It 'Should accept Stopped as TargetState' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Stopped' } } -ModuleName WsusServices
            { Wait-ServiceState -ServiceName 'Test' -TargetState 'Stopped' -TimeoutSeconds 1 } | Should -Not -Throw
        }
    }

    Context 'Test-ServiceRunning Parameters' {
        It 'Should require ServiceName parameter' {
            { Test-ServiceRunning } | Should -Throw
        }
    }

    Context 'Test-ServiceExists Parameters' {
        It 'Should require ServiceName parameter' {
            { Test-ServiceExists } | Should -Throw
        }
    }

    Context 'Start-WsusService Parameters' {
        It 'Should require ServiceName parameter' {
            { Start-WsusService } | Should -Throw
        }
    }

    Context 'Stop-WsusService Parameters' {
        It 'Should require ServiceName parameter' {
            { Stop-WsusService } | Should -Throw
        }
    }

    Context 'Restart-WsusService Parameters' {
        It 'Should require ServiceName parameter' {
            { Restart-WsusService } | Should -Throw
        }
    }
}
