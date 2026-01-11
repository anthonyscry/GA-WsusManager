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
            $result = Test-WsusFirewallRule -RuleName "NonExistentRule12345"
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
            $result = Test-WsusFirewallRule -RuleName "MockRule"
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
            { New-WsusFirewallRule -RuleName "TestRule" -Port 8530 -Protocol TCP -Direction Inbound } | Should -Not -Throw
        }
    }
}

Describe "Remove-WsusFirewallRule" {
    Context "With existing rule" {
        BeforeAll {
            Mock Get-NetFirewallRule {
                [PSCustomObject]@{ Name = "TestRule" }
            } -ModuleName WsusFirewall
            Mock Remove-NetFirewallRule { } -ModuleName WsusFirewall
        }

        It "Should return true when rule is removed" {
            $result = Remove-WsusFirewallRule -RuleName "TestRule"
            $result | Should -Be $true
        }

        It "Should call Remove-NetFirewallRule" {
            Remove-WsusFirewallRule -RuleName "TestRule"
            Should -Invoke Remove-NetFirewallRule -ModuleName WsusFirewall
        }
    }

    Context "With non-existent rule" {
        BeforeAll {
            Mock Get-NetFirewallRule { $null } -ModuleName WsusFirewall
        }

        It "Should return true when rule doesn't exist" {
            $result = Remove-WsusFirewallRule -RuleName "NonExistent"
            $result | Should -Be $true
        }
    }
}

Describe "Repair-WsusFirewallRules" {
    Context "Return structure validation" {
        BeforeAll {
            Mock Initialize-WsusFirewallRules { $true } -ModuleName WsusFirewall
        }

        It "Should return a boolean" {
            $result = Repair-WsusFirewallRules
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Repair-SqlFirewallRules" {
    Context "Return structure validation" {
        BeforeAll {
            Mock Initialize-SqlFirewallRules { $true } -ModuleName WsusFirewall
        }

        It "Should return a boolean" {
            $result = Repair-SqlFirewallRules
            $result | Should -BeOfType [bool]
        }
    }
}
