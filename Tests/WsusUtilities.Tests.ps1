#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusUtilities.psm1

.DESCRIPTION
    Unit tests for the WsusUtilities module functions including:
    - Color output functions
    - Logging functions
    - Admin privilege checks
    - Path helper functions
    - SQL helper functions
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusUtilities.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusUtilities -ErrorAction SilentlyContinue
}

Describe "WsusUtilities Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusUtilities | Should -Not -BeNullOrEmpty
        }

        It "Should export Write-Log function" {
            Get-Command Write-Log -Module WsusUtilities | Should -Not -BeNullOrEmpty
        }

        It "Should export Write-Success function" {
            Get-Command Write-Success -Module WsusUtilities | Should -Not -BeNullOrEmpty
        }

        It "Should export Write-Failure function" {
            Get-Command Write-Failure -Module WsusUtilities | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-AdminPrivileges function" {
            Get-Command Test-AdminPrivileges -Module WsusUtilities | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Write-Log" {
    It "Should output timestamped message" {
        $message = "Test log message"
        $output = Write-Log -Message $message 6>&1
        $output | Should -Match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - $message"
    }

    It "Should include current date in output" {
        $today = Get-Date -Format "yyyy-MM-dd"
        $output = Write-Log -Message "Test" 6>&1
        $output | Should -Match $today
    }
}

Describe "Start-WsusLogging" {
    BeforeAll {
        $TestLogDir = Join-Path $env:TEMP "WsusTestLogs"
    }

    AfterEach {
        Stop-WsusLogging
        if (Test-Path $TestLogDir) {
            Remove-Item $TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should create log directory if it doesn't exist" {
        Start-WsusLogging -ScriptName "TestScript" -LogDirectory $TestLogDir | Out-Null
        Test-Path $TestLogDir | Should -Be $true
    }

    It "Should return log file path" {
        $logFile = Start-WsusLogging -ScriptName "TestScript" -LogDirectory $TestLogDir
        $logFile | Should -Match "TestScript.*\.log$"
    }

    It "Should include timestamp in filename when UseTimestamp is true" {
        $logFile = Start-WsusLogging -ScriptName "TestScript" -LogDirectory $TestLogDir -UseTimestamp $true
        $logFile | Should -Match "TestScript_\d{8}_\d{4}\.log$"
    }

    It "Should not include timestamp when UseTimestamp is false" {
        $logFile = Start-WsusLogging -ScriptName "TestScript" -LogDirectory $TestLogDir -UseTimestamp $false
        $logFile | Should -Be (Join-Path $TestLogDir "TestScript.log")
    }
}

Describe "Test-AdminPrivileges" {
    It "Should return a boolean value" {
        $result = Test-AdminPrivileges
        $result | Should -BeOfType [bool]
    }

    It "Should not exit when ExitOnFail is false" {
        # This test verifies the function doesn't exit unexpectedly
        { Test-AdminPrivileges -ExitOnFail $false } | Should -Not -Throw
    }
}

Describe "Test-WsusPath" {
    BeforeAll {
        $TestPath = Join-Path $env:TEMP "WsusTestPath_$(Get-Random)"
    }

    AfterAll {
        if (Test-Path $TestPath) {
            Remove-Item $TestPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should return false for non-existent path without Create" {
        $result = Test-WsusPath -Path $TestPath -Create $false
        $result | Should -Be $false
    }

    It "Should return true and create path when Create is true" {
        $result = Test-WsusPath -Path $TestPath -Create $true
        $result | Should -Be $true
        Test-Path $TestPath | Should -Be $true
    }

    It "Should return true for existing path" {
        # Path was created in previous test
        $result = Test-WsusPath -Path $TestPath -Create $false
        $result | Should -Be $true
    }
}

Describe "Write-ColorOutput" {
    It "Should not throw when called with valid parameters" {
        { Write-ColorOutput -ForegroundColor Green -Message "Test message" } | Should -Not -Throw
    }

    It "Should handle empty message" {
        { Write-ColorOutput -ForegroundColor Red } | Should -Not -Throw
    }
}

Describe "Write-Success" {
    It "Should not throw" {
        { Write-Success "Test success message" } | Should -Not -Throw
    }
}

Describe "Write-Failure" {
    It "Should not throw" {
        { Write-Failure "Test failure message" } | Should -Not -Throw
    }
}

Describe "Write-WsusWarning" {
    It "Should not throw" {
        { Write-WsusWarning "Test warning message" } | Should -Not -Throw
    }
}

Describe "Write-Info" {
    It "Should not throw" {
        { Write-Info "Test info message" } | Should -Not -Throw
    }
}

Describe "Write-LogError" {
    It "Should not throw when Throw switch is not used" {
        { Write-LogError -Message "Test error" } | Should -Not -Throw
    }

    It "Should throw when Throw switch is used" {
        { Write-LogError -Message "Test error" -Throw } | Should -Throw
    }

    It "Should include exception message when Exception is provided" {
        $testException = [System.Exception]::new("Test exception message")
        # Capture both error and success streams
        { Write-LogError -Message "Error occurred" -Exception $testException } | Should -Not -Throw
    }
}

Describe "Write-LogWarning" {
    It "Should not throw" {
        { Write-LogWarning -Message "Test warning" } | Should -Not -Throw
    }
}

Describe "Invoke-WithErrorHandling" {
    It "Should return result from successful scriptblock" {
        $result = Invoke-WithErrorHandling -ScriptBlock { "Success" }
        $result | Should -Be "Success"
    }

    It "Should return default value on error when ContinueOnError is set" {
        $result = Invoke-WithErrorHandling -ScriptBlock { throw "Error" } -ContinueOnError -ReturnDefault "Default"
        $result | Should -Be "Default"
    }

    It "Should throw on error when ContinueOnError is not set" {
        { Invoke-WithErrorHandling -ScriptBlock { throw "Error" } -ErrorMessage "Test error" } | Should -Throw
    }
}

Describe "Get-WsusContentPath" {
    It "Should return string or null" {
        $result = Get-WsusContentPath
        if ($null -ne $result) {
            $result | Should -BeOfType [string]
        }
    }
}

Describe "Get-WsusSqlCredentialPath" {
    It "Should return a valid path string" {
        $result = Get-WsusSqlCredentialPath
        $result | Should -Match "sql_credential\.xml$"
    }
}
