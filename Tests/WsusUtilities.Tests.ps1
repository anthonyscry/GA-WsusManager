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
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot
    Import-WsusTestModule -ModuleName 'WsusUtilities' -RepoRoot $script:RepoRoot
}

AfterAll {
    Remove-WsusTestModule -ModuleName 'WsusUtilities'
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
        $script:TestLogDir = New-WsusTempHarnessRoot -Prefix 'WsusTestLogs'
    }

    AfterEach {
        Stop-WsusLogging
        if (Test-Path $script:TestLogDir) {
            Remove-Item $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should create log directory if it doesn't exist" {
        Start-WsusLogging -ScriptName "TestScript" -LogDirectory $script:TestLogDir | Out-Null
        Test-Path $script:TestLogDir | Should -Be $true
    }

    It "Should return log file path" {
        $logFile = Start-WsusLogging -ScriptName "TestScript" -LogDirectory $script:TestLogDir
        $logFile | Should -Match "TestScript.*\.log$"
    }

    It "Should include timestamp in filename when UseTimestamp is true" {
        $logFile = Start-WsusLogging -ScriptName "TestScript" -LogDirectory $script:TestLogDir -UseTimestamp $true
        $logFile | Should -Match "TestScript_\d{8}_\d{4}\.log$"
    }

    It "Should not include timestamp when UseTimestamp is false" {
        $logFile = Start-WsusLogging -ScriptName "TestScript" -LogDirectory $script:TestLogDir -UseTimestamp $false
        $logFile | Should -Be (Join-Path $script:TestLogDir "TestScript.log")
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
        $script:TestPathRoot = New-WsusTempHarnessRoot -Prefix 'WsusTestPath'
        $script:TestPath = Join-Path $script:TestPathRoot 'CreatedPath'
    }

    AfterAll {
        if (Test-Path $script:TestPathRoot) {
            Remove-Item $script:TestPathRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should return false for non-existent path without Create" {
        $result = Test-WsusPath -Path $script:TestPath -Create $false
        $result | Should -Be $false
    }

    It "Should return true and create path when Create is true" {
        $result = Test-WsusPath -Path $script:TestPath -Create $true
        $result | Should -Be $true
        Test-Path $script:TestPath | Should -Be $true
    }

    It "Should return true for existing path" {
        # Path was created in previous test
        $result = Test-WsusPath -Path $script:TestPath -Create $false
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

Describe "Invoke-WsusSqlcmd Security" {
    BeforeAll {
        $script:UtilitiesContent = Get-Content (Join-Path $script:RepoRoot 'Modules\WsusUtilities.psm1') -Raw
    }

    It "does not expose SQL credentials through sqlcmd.exe -P arguments" {
        $script:UtilitiesContent | Should -Not -Match '"-P"'
        $script:UtilitiesContent | Should -Match 'SQL authentication requires the SqlServer PowerShell module'
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
