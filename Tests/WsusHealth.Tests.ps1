#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusHealth.psm1

.DESCRIPTION
    Unit tests for the WsusHealth module functions including:
    - SSL status checking (Get-WsusSSLStatus)
    - Database connection testing (Test-WsusDatabaseConnection)
    - System health checks (Test-WsusHealth)
    - Health repair functions (Repair-WsusHealth)

.NOTES
    These tests use mocking to avoid actual system modifications.
#>

BeforeAll {
    # Import required dependent modules first
    $ModulesPath = Join-Path $PSScriptRoot "..\Modules"
    Import-Module (Join-Path $ModulesPath "WsusUtilities.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $ModulesPath "WsusServices.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $ModulesPath "WsusFirewall.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $ModulesPath "WsusPermissions.psm1") -Force -DisableNameChecking

    # Import the module under test
    $ModulePath = Join-Path $ModulesPath "WsusHealth.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusHealth -ErrorAction SilentlyContinue
    Remove-Module WsusPermissions -ErrorAction SilentlyContinue
    Remove-Module WsusFirewall -ErrorAction SilentlyContinue
    Remove-Module WsusServices -ErrorAction SilentlyContinue
    Remove-Module WsusUtilities -ErrorAction SilentlyContinue
}

Describe "WsusHealth Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusHealth | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusSSLStatus function" {
            Get-Command Get-WsusSSLStatus -Module WsusHealth | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusDatabaseConnection function" {
            Get-Command Test-WsusDatabaseConnection -Module WsusHealth | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusHealth function" {
            Get-Command Test-WsusHealth -Module WsusHealth | Should -Not -BeNullOrEmpty
        }

        It "Should export Repair-WsusHealth function" {
            Get-Command Repair-WsusHealth -Module WsusHealth | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WsusSSLStatus" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-WsusSSLStatus
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain SSLEnabled key" {
            $result = Get-WsusSSLStatus
            $result.Keys | Should -Contain "SSLEnabled"
        }

        It "Should contain Protocol key" {
            $result = Get-WsusSSLStatus
            $result.Keys | Should -Contain "Protocol"
        }

        It "Should contain Port key" {
            $result = Get-WsusSSLStatus
            $result.Keys | Should -Contain "Port"
        }

        It "Should contain Message key" {
            $result = Get-WsusSSLStatus
            $result.Keys | Should -Contain "Message"
        }

        It "SSLEnabled should be boolean" {
            $result = Get-WsusSSLStatus
            $result.SSLEnabled | Should -BeOfType [bool]
        }

        It "Port should be a number" {
            $result = Get-WsusSSLStatus
            $result.Port | Should -BeOfType [int]
        }
    }
}

Describe "Test-WsusDatabaseConnection" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Test-WsusDatabaseConnection
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Connected key" {
            $result = Test-WsusDatabaseConnection
            $result.Keys | Should -Contain "Connected"
        }

        It "Should contain Message key" {
            $result = Test-WsusDatabaseConnection
            $result.Keys | Should -Contain "Message"
        }

        It "Connected should be boolean" {
            $result = Test-WsusDatabaseConnection
            $result.Connected | Should -BeOfType [bool]
        }
    }

    Context "With custom SQL instance" {
        It "Should accept SqlInstance parameter" {
            $result = Test-WsusDatabaseConnection -SqlInstance "localhost\SQLEXPRESS"
            $result | Should -BeOfType [hashtable]
        }
    }
}

Describe "Test-WsusHealth" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Test-WsusHealth
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Overall key" {
            $result = Test-WsusHealth
            $result.Keys | Should -Contain "Overall"
        }

        It "Should contain Services key" {
            $result = Test-WsusHealth
            $result.Keys | Should -Contain "Services"
        }

        It "Should contain Database key" {
            $result = Test-WsusHealth
            $result.Keys | Should -Contain "Database"
        }

        It "Should contain Firewall key" {
            $result = Test-WsusHealth
            $result.Keys | Should -Contain "Firewall"
        }

        It "Should contain Permissions key" {
            $result = Test-WsusHealth
            $result.Keys | Should -Contain "Permissions"
        }

        It "Overall should be a string status" {
            $result = Test-WsusHealth
            $result.Overall | Should -BeOfType [string]
        }
    }
}

Describe "Repair-WsusHealth" {
    Context "Return structure validation" {
        BeforeAll {
            # Mock the repair functions to avoid actual system modifications
            Mock Start-AllWsusServices { @{ SqlServer = $true; IIS = $true; WSUS = $true } } -ModuleName WsusHealth
            Mock Repair-WsusFirewallRules { $true } -ModuleName WsusHealth
            Mock Repair-WsusContentPermissions { $true } -ModuleName WsusHealth
        }

        It "Should return a hashtable" {
            $result = Repair-WsusHealth
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain ServicesStarted key" {
            $result = Repair-WsusHealth
            $result.Keys | Should -Contain "ServicesStarted"
        }

        It "Should contain PermissionsFixed key" {
            $result = Repair-WsusHealth
            $result.Keys | Should -Contain "PermissionsFixed"
        }
    }
}
