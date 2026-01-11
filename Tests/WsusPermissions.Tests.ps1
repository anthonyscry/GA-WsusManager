#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusPermissions.psm1

.DESCRIPTION
    Unit tests for the WsusPermissions module functions including:
    - Permission setting (Set-WsusContentPermissions)
    - Permission testing (Test-WsusContentPermissions)
    - Permission repair (Repair-WsusContentPermissions)
    - Directory initialization (Initialize-WsusDirectories)

.NOTES
    These tests use mocking to avoid actual permission modifications.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusPermissions.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusPermissions -ErrorAction SilentlyContinue
}

Describe "WsusPermissions Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusPermissions | Should -Not -BeNullOrEmpty
        }

        It "Should export Set-WsusContentPermissions function" {
            Get-Command Set-WsusContentPermissions -Module WsusPermissions | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusContentPermissions function" {
            Get-Command Test-WsusContentPermissions -Module WsusPermissions | Should -Not -BeNullOrEmpty
        }

        It "Should export Repair-WsusContentPermissions function" {
            Get-Command Repair-WsusContentPermissions -Module WsusPermissions | Should -Not -BeNullOrEmpty
        }

        It "Should export Initialize-WsusDirectories function" {
            Get-Command Initialize-WsusDirectories -Module WsusPermissions | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Test-WsusContentPermissions" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Test-WsusContentPermissions -ContentPath "C:\WSUS"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain AllCorrect key" {
            $result = Test-WsusContentPermissions -ContentPath "C:\WSUS"
            $result.Keys | Should -Contain "AllCorrect"
        }

        It "Should contain Found key" {
            $result = Test-WsusContentPermissions -ContentPath "C:\WSUS"
            $result.Keys | Should -Contain "Found"
        }

        It "Should contain Missing key" {
            $result = Test-WsusContentPermissions -ContentPath "C:\WSUS"
            $result.Keys | Should -Contain "Missing"
        }

        It "AllCorrect should be boolean" {
            $result = Test-WsusContentPermissions -ContentPath "C:\WSUS"
            $result.AllCorrect | Should -BeOfType [bool]
        }
    }

    Context "With non-existent path" {
        It "Should return AllCorrect=false for non-existent path" {
            $result = Test-WsusContentPermissions -ContentPath "C:\NonExistentPath12345"
            $result.AllCorrect | Should -Be $false
        }
    }
}

Describe "Set-WsusContentPermissions" {
    Context "With mocked icacls" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName WsusPermissions
            Mock icacls { } -ModuleName WsusPermissions
        }

        It "Should accept ContentPath parameter" {
            { Set-WsusContentPermissions -ContentPath "C:\WSUS" } | Should -Not -Throw
        }

        It "Should return a boolean" {
            $result = Set-WsusContentPermissions -ContentPath "C:\WSUS"
            $result | Should -BeOfType [bool]
        }
    }

    Context "With non-existent path" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName WsusPermissions
        }

        It "Should return false for non-existent path" {
            $result = Set-WsusContentPermissions -ContentPath "C:\NonExistentPath12345"
            $result | Should -Be $false
        }
    }
}

Describe "Repair-WsusContentPermissions" {
    Context "With mocked functions" {
        BeforeAll {
            Mock Set-WsusContentPermissions { $true } -ModuleName WsusPermissions
        }

        It "Should return a boolean" {
            $result = Repair-WsusContentPermissions -ContentPath "C:\WSUS"
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Initialize-WsusDirectories" {
    Context "Parameter validation" {
        It "Should have WSUSRoot parameter" {
            (Get-Command Initialize-WsusDirectories).Parameters.Keys | Should -Contain "WSUSRoot"
        }

        It "Should have CreateSubdirectories parameter" {
            (Get-Command Initialize-WsusDirectories).Parameters.Keys | Should -Contain "CreateSubdirectories"
        }
    }

    Context "Return type validation" {
        BeforeAll {
            Mock New-Item { } -ModuleName WsusPermissions
            Mock Set-WsusContentPermissions { $true } -ModuleName WsusPermissions
        }

        It "Should return a boolean" {
            $result = Initialize-WsusDirectories -WSUSRoot "C:\WSUS"
            $result | Should -BeOfType [bool]
        }
    }
}
