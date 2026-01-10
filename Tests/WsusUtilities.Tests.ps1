#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusUtilities.psm1

.DESCRIPTION
    Unit tests for the WSUS utilities module functions.
    Uses mocking to avoid dependencies on Windows Server, SQL, etc.
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot '..\Modules\WsusUtilities.psm1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module WsusUtilities -Force -ErrorAction SilentlyContinue
}

Describe 'WsusUtilities Module' {
    Context 'Module Loading' {
        It 'Should export expected functions' {
            $exportedFunctions = (Get-Module WsusUtilities).ExportedFunctions.Keys
            $expectedFunctions = @(
                'Write-ColorOutput',
                'Write-Success',
                'Write-Failure',
                'Write-WsusWarning',
                'Write-Info',
                'Write-Log',
                'Start-WsusLogging',
                'Stop-WsusLogging',
                'Test-AdminPrivileges',
                'Invoke-SqlScalar',
                'Invoke-WsusSqlcmd',
                'Get-WsusContentPath',
                'Test-WsusPath'
            )
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }

    Context 'Write-Log' {
        It 'Should output timestamped message' {
            $result = Write-Log -Message 'Test message'
            # Write-Log uses Write-Output, so we check the format
            $result | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - Test message$'
        }

        It 'Should include correct timestamp format' {
            $before = Get-Date
            $result = Write-Log -Message 'Timestamp test'
            $after = Get-Date

            # Extract timestamp from result
            $timestampStr = $result -replace ' - Timestamp test$', ''
            $timestamp = [datetime]::ParseExact($timestampStr, 'yyyy-MM-dd HH:mm:ss', $null)

            $timestamp | Should -BeGreaterOrEqual $before.AddSeconds(-1)
            $timestamp | Should -BeLessOrEqual $after.AddSeconds(1)
        }
    }

    Context 'Test-WsusPath' {
        BeforeAll {
            $testDir = Join-Path $TestDrive 'TestPath'
        }

        It 'Should return true for existing path' {
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
            $result = Test-WsusPath -Path $testDir
            $result | Should -Be $true
        }

        It 'Should return false for non-existing path without Create' {
            $nonExistent = Join-Path $TestDrive 'NonExistent'
            $result = Test-WsusPath -Path $nonExistent -Create $false
            $result | Should -Be $false
        }

        It 'Should create path when Create is true' {
            $newPath = Join-Path $TestDrive 'NewPath'
            $result = Test-WsusPath -Path $newPath -Create $true
            $result | Should -Be $true
            Test-Path $newPath | Should -Be $true
        }

        It 'Should return false for non-existing path by default' {
            $missingPath = Join-Path $TestDrive 'MissingPath'
            $result = Test-WsusPath -Path $missingPath
            $result | Should -Be $false
        }
    }

    Context 'Start-WsusLogging and Stop-WsusLogging' {
        BeforeAll {
            $testLogDir = Join-Path $TestDrive 'Logs'
        }

        It 'Should create log directory if it does not exist' {
            $logFile = Start-WsusLogging -ScriptName 'TestScript' -LogDirectory $testLogDir
            Test-Path $testLogDir | Should -Be $true
            Stop-WsusLogging
        }

        It 'Should return log file path with timestamp' {
            $logFile = Start-WsusLogging -ScriptName 'TestScript' -LogDirectory $testLogDir -UseTimestamp $true
            $logFile | Should -Match 'TestScript_\d{8}_\d{4}\.log$'
            Stop-WsusLogging
        }

        It 'Should return log file path without timestamp when disabled' {
            $logFile = Start-WsusLogging -ScriptName 'TestScript' -LogDirectory $testLogDir -UseTimestamp $false
            $logFile | Should -Match 'TestScript\.log$'
            Stop-WsusLogging
        }
    }

    Context 'Write-LogError' {
        It 'Should format error message correctly' {
            # Capture output
            $output = Write-LogError -Message 'Test error' 6>&1 | Out-String
            $output | Should -Match 'ERROR: Test error'
        }

        It 'Should include exception message when provided' {
            $testException = [System.Exception]::new('Exception details')
            $output = Write-LogError -Message 'Operation failed' -Exception $testException 6>&1 | Out-String
            $output | Should -Match 'Operation failed - Exception details'
        }

        It 'Should throw when Throw switch is used' {
            { Write-LogError -Message 'Fatal error' -Throw } | Should -Throw 'Fatal error'
        }
    }

    Context 'Write-LogWarning' {
        It 'Should format warning message correctly' {
            $output = Write-LogWarning -Message 'Test warning' 6>&1 | Out-String
            $output | Should -Match 'WARNING: Test warning'
        }
    }

    Context 'Invoke-WithErrorHandling' {
        It 'Should return result from successful script block' {
            $result = Invoke-WithErrorHandling -ScriptBlock { 42 } -ErrorMessage 'Should not fail'
            $result | Should -Be 42
        }

        It 'Should throw on error by default' {
            { Invoke-WithErrorHandling -ScriptBlock { throw 'Test error' } -ErrorMessage 'Operation failed' } |
                Should -Throw
        }

        It 'Should return default value on error when ContinueOnError is set' {
            $result = Invoke-WithErrorHandling -ScriptBlock { throw 'Test error' } `
                -ErrorMessage 'Operation failed' -ContinueOnError -ReturnDefault 'default'
            $result | Should -Be 'default'
        }

        It 'Should return null as default when ReturnDefault not specified' {
            $result = Invoke-WithErrorHandling -ScriptBlock { throw 'Test error' } `
                -ErrorMessage 'Operation failed' -ContinueOnError
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Get-WsusSqlCredentialPath' {
        It 'Should return expected credential file path' {
            $result = Get-WsusSqlCredentialPath
            $result | Should -Be 'C:\WSUS\Config\sql_credential.xml'
        }
    }

    Context 'Color Output Functions' {
        # These functions modify console colors, so we just verify they execute without error
        It 'Write-Success should not throw' {
            { Write-Success 'Test success message' } | Should -Not -Throw
        }

        It 'Write-Failure should not throw' {
            { Write-Failure 'Test failure message' } | Should -Not -Throw
        }

        It 'Write-WsusWarning should not throw' {
            { Write-WsusWarning 'Test warning message' } | Should -Not -Throw
        }

        It 'Write-Info should not throw' {
            { Write-Info 'Test info message' } | Should -Not -Throw
        }

        It 'Write-ColorOutput should not throw' {
            { Write-ColorOutput -ForegroundColor Cyan -Message 'Test colored message' } | Should -Not -Throw
        }
    }

    Context 'SQL Credential Functions - Mocked' {
        BeforeAll {
            $testCredPath = Join-Path $TestDrive 'Config\sql_credential.xml'
        }

        It 'Get-WsusSqlCredential should return null when file does not exist' {
            # The actual path won't exist in test environment
            Mock Test-Path { $false } -ModuleName WsusUtilities
            $result = Get-WsusSqlCredential -Quiet
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'WsusUtilities Parameter Validation' {
    Context 'Write-Log Parameters' {
        It 'Should require Message parameter' {
            { Write-Log } | Should -Throw
        }
    }

    Context 'Start-WsusLogging Parameters' {
        It 'Should require ScriptName parameter' {
            { Start-WsusLogging } | Should -Throw
            Stop-WsusLogging  # Clean up any partial transcript
        }
    }

    Context 'Test-WsusPath Parameters' {
        It 'Should require Path parameter' {
            { Test-WsusPath } | Should -Throw
        }
    }

    Context 'Invoke-SqlScalar Parameters' {
        It 'Should require Instance parameter' {
            { Invoke-SqlScalar -Query 'SELECT 1' } | Should -Throw
        }

        It 'Should require Query parameter' {
            { Invoke-SqlScalar -Instance '.\SQLEXPRESS' } | Should -Throw
        }
    }

    Context 'Invoke-WsusSqlcmd Parameters' {
        It 'Should require Query parameter' {
            { Invoke-WsusSqlcmd } | Should -Throw
        }
    }
}
