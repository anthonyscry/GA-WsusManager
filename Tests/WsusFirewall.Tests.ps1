#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusFirewall.psm1

.DESCRIPTION
    Unit tests for the WsusFirewall module functions including:
    - Firewall rule creation (New-WsusFirewallRule)
    - Firewall rule testing (Test-WsusFirewallRule)
    - Firewall rule removal (Remove-WsusFirewallRule)
    - Bulk firewall operations (Initialize-*, Test-All*, Repair-*)

.NOTES
    These tests use mocking to avoid actual firewall modifications.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusFirewall.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusFirewall -ErrorAction SilentlyContinue
}

Describe "WsusFirewall Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export New-WsusFirewallRule function" {
            Get-Command New-WsusFirewallRule -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusFirewallRule function" {
            Get-Command Test-WsusFirewallRule -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Remove-WsusFirewallRule function" {
            Get-Command Remove-WsusFirewallRule -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Initialize-WsusFirewallRules function" {
            Get-Command Initialize-WsusFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Initialize-SqlFirewallRules function" {
            Get-Command Initialize-SqlFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-AllWsusFirewallRules function" {
            Get-Command Test-AllWsusFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-AllSqlFirewallRules function" {
            Get-Command Test-AllSqlFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Repair-WsusFirewallRules function" {
            Get-Command Repair-WsusFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }

        It "Should export Repair-SqlFirewallRules function" {
            Get-Command Repair-SqlFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Test-WsusFirewallRule" {
    Context "With non-existent rule" {
        BeforeAll {
            Mock Get-NetFirewallRule { $null } -ModuleName WsusFirewall
        }

        It "Should return false for non-existent rule" {
            $result = Test-WsusFirewallRule -DisplayName "NonExistentRule12345"
            $result | Should -Be $false
        }
    }

    Context "With existing rule" {
        BeforeAll {
            Mock Get-NetFirewallRule {
                [PSCustomObject]@{
                    Name = "MockRule"
                    Enabled = "True"
                }
            } -ModuleName WsusFirewall
        }

        It "Should return true for existing rule" {
            $result = Test-WsusFirewallRule -DisplayName "MockRule"
            $result | Should -Be $true
        }
    }
}

Describe "Test-AllWsusFirewallRules" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Test-AllWsusFirewallRules
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain AllPresent key" {
            $result = Test-AllWsusFirewallRules
            $result.Keys | Should -Contain "AllPresent"
        }

        It "Should contain Present or Missing keys" {
            $result = Test-AllWsusFirewallRules
            ($result.Keys -contains "Present") -or ($result.Keys -contains "Missing") | Should -Be $true
        }

        It "AllPresent should be boolean" {
            $result = Test-AllWsusFirewallRules
            $result.AllPresent | Should -BeOfType [bool]
        }
    }
}

Describe "Test-AllSqlFirewallRules" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Test-AllSqlFirewallRules
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain AllPresent key" {
            $result = Test-AllSqlFirewallRules
            $result.Keys | Should -Contain "AllPresent"
        }

        It "Should contain Present or Missing keys" {
            $result = Test-AllSqlFirewallRules
            ($result.Keys -contains "Present") -or ($result.Keys -contains "Missing") | Should -Be $true
        }
    }
}

Describe "New-WsusFirewallRule" {
    Context "With mocked firewall" {
        BeforeAll {
            Mock New-NetFirewallRule { [PSCustomObject]@{ Name = "TestRule" } } -ModuleName WsusFirewall
            Mock Get-NetFirewallRule { $null } -ModuleName WsusFirewall
        }

        It "Should accept required parameters" {
            { New-WsusFirewallRule -DisplayName "TestRule" -LocalPort 8530 -Protocol TCP -Direction Inbound -Action Allow } | Should -Not -Throw
        }
    }
}

Describe "Remove-WsusFirewallRule" {
    Context "Parameter validation" {
        It "Should have DisplayName parameter" {
            (Get-Command Remove-WsusFirewallRule).Parameters.Keys | Should -Contain "DisplayName"
        }
    }

    Context "With non-existent rule" {
        It "Should return false when rule doesn't exist" {
            # Non-existent rule name - module catches the error and returns false
            $result = Remove-WsusFirewallRule -DisplayName "NonExistentRule12345XYZ"
            $result | Should -Be $false
        }
    }
}

Describe "Repair-WsusFirewallRules" {
    Context "Function availability" {
        It "Should be exported from module" {
            Get-Command Repair-WsusFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Repair-SqlFirewallRules" {
    Context "Function availability" {
        It "Should be exported from module" {
            Get-Command Repair-SqlFirewallRules -Module WsusFirewall | Should -Not -BeNullOrEmpty
        }
    }
}
