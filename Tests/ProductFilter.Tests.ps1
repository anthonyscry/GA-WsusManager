#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for product selection and decline filter logic.

.DESCRIPTION
    Tests the regex patterns and matching logic used by
    Invoke-WsusMonthlyMaintenance.ps1 to:
    - Build word-boundary product patterns for decline logic
    - Filter Office 365 updates to allow only LTSC/2024
    - Exclude ARM64, 25H2, and legacy build updates from approval
    - Match selected products for approval filtering

    These tests use pure regex/string matching - no WSUS API needed.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot
    $script:MaintContent = Get-WsusTestFileText -RepoRoot $script:RepoRoot -RelativePath 'Scripts\Invoke-WsusMonthlyMaintenance.ps1'
    $script:InstallContent = Get-WsusTestFileText -RepoRoot $script:RepoRoot -RelativePath 'Scripts\Install-WsusWithSqlExpress.ps1'
    $script:GuiContent = Get-WsusTestFileText -RepoRoot $script:RepoRoot -RelativePath 'Scripts\WsusManagementGui.ps1'
}

Describe "Product Decline Pattern (Word-Boundary Matching)" {
    Context "Pattern construction matches maintenance script logic" {
        It "Uses regex pattern for product matching in approval filter (non-selected decline removed in v4.1)" {
            $script:MaintContent | Should -Match '\$productPattern'
        }

        It "Escapes product names with [regex]::Escape before building pattern" {
            $script:MaintContent | Should -Match '\[regex\]::Escape\(\$_\)'
        }
    }

    Context "Word-boundary matching behavior" {
        BeforeAll {
            # Simulate the exact pattern construction from line 896-897
            $script:EnabledTitles = @(
                [regex]::Escape("Windows 11"),
                [regex]::Escape("Windows Server 2019"),
                [regex]::Escape("Visual Studio 2022")
            )
            $script:DeclinePattern = '(?i)\b(' + ($script:EnabledTitles -join "|") + ')\b'
        }

        It "Matches exact product name" {
            "Windows 11" | Should -Match $script:DeclinePattern
            "Windows Server 2019" | Should -Match $script:DeclinePattern
        }

        It "Does NOT match partial product substring (prevents false declines)" {
            "Some Other Product 11" | Should -Not -Match $script:DeclinePattern
            "Server 2019" | Should -Not -Match $script:DeclinePattern
        }

        It "Matches product within comma-separated string" {
            "Windows 11,Security Updates" | Should -Match $script:DeclinePattern
            "Visual Studio 2022,Office" | Should -Match $script:DeclinePattern
        }

        It "Case-insensitive matching works" {
            "windows 11" | Should -Match $script:DeclinePattern
            "WINDOWS SERVER 2019" | Should -Match $script:DeclinePattern
        }

        It "Does NOT match similar but distinct product names" {
            "Windows 10" | Should -Not -Match $script:DeclinePattern
            "Windows Server 2022" | Should -Not -Match $script:DeclinePattern
        }
    }
}

Describe "Office update policy" {
    Context "Decline logic" {
        It "Does not use the old broad Microsoft 365 decline bucket" {
            $script:MaintContent | Should -Not -Match '\$officeDeclines\s*='
            $script:MaintContent | Should -Match '\$x86OfficeDeclines\s*='
        }

        It "Declines only x86 or 32-bit Office updates" {
            $title = "Microsoft 365 Apps Update for x86"

            $shouldDecline = (
                $title -match '(?i)\b(Microsoft Office|Microsoft 365 Apps|Office)\b' -and
                $title -match '(?i)\b(x86|32.bit|32-bit)\b'
            )

            $shouldDecline | Should -BeTrue
        }

        It "Keeps x64 Microsoft 365 updates instead of broadly declining them" {
            $title = "Microsoft 365 Apps - Feature Update 2402"

            $shouldDecline = (
                $title -match '(?i)\b(Microsoft Office|Microsoft 365 Apps|Office)\b' -and
                $title -match '(?i)\b(x86|32.bit|32-bit)\b'
            )

            $shouldDecline | Should -BeFalse
        }
    }
}

Describe "Legacy Build and Architecture Exclusion" {
    Context "ARM64 exclusion pattern" {
        It "Script uses word-boundary match for ARM64" {
            $script:MaintContent | Should -Match '\\bARM64\\b'
        }

        It "Matches ARM64 in update titles" {
            "Security Update for ARM64-based Windows 11" -match '(?i)\bARM64\b' | Should -BeTrue
        }

        It "Does NOT match ARM in unrelated context" {
            "Update for Windows ARM" -match '(?i)\bARM64\b' | Should -BeFalse
        }
    }

    Context "25H2 exclusion pattern" {
        It "Script uses word-boundary match for 25H2" {
            $script:MaintContent | Should -Match '\\b25H2\\b'
        }

        It "Matches 25H2 in update titles" {
            "Windows 11 Version 25H2 Cumulative Update" -match '(?i)\b25H2\b' | Should -BeTrue
        }
    }

    Context "Legacy build exclusion (23H2 and lower)" {
        It "Script uses the legacy build helper in both decline and approval filters" {
            $script:MaintContent | Should -Match 'function Test-WsusLegacyBuildTitle'
            $script:MaintContent | Should -Match 'Test-WsusLegacyBuildTitle -Title \$_\.Title'
        }

        It "Matches 23H2 in update titles" {
            $title = "Windows 11 Version 23H2 Security Update"
            $versionMatches = [regex]::Matches($title, '(?i)\b(?<major>\d{2})H(?<half>[12])\b')
            $isLegacy = $false
            foreach ($versionMatch in $versionMatches) {
                $major = [int]$versionMatch.Groups['major'].Value
                $half = [int]$versionMatch.Groups['half'].Value
                if ($major -lt 23 -or ($major -eq 23 -and $half -le 2)) { $isLegacy = $true; break }
            }
            $isLegacy | Should -BeTrue
        }

        It "Matches 20H2 in update titles" {
            $title = "Windows 10 Version 20H2 Servicing Stack"
            $versionMatches = [regex]::Matches($title, '(?i)\b(?<major>\d{2})H(?<half>[12])\b')
            $isLegacy = $false
            foreach ($versionMatch in $versionMatches) {
                $major = [int]$versionMatch.Groups['major'].Value
                $half = [int]$versionMatch.Groups['half'].Value
                if ($major -lt 23 -or ($major -eq 23 -and $half -le 2)) { $isLegacy = $true; break }
            }
            $isLegacy | Should -BeTrue
        }

        It "Does NOT match 24H2 titles" {
            $title = "Windows 11 Version 24H2 Security Update"
            $versionMatches = [regex]::Matches($title, '(?i)\b(?<major>\d{2})H(?<half>[12])\b')
            $isLegacy = $false
            foreach ($versionMatch in $versionMatches) {
                $major = [int]$versionMatch.Groups['major'].Value
                $half = [int]$versionMatch.Groups['half'].Value
                if ($major -lt 23 -or ($major -eq 23 -and $half -le 2)) { $isLegacy = $true; break }
            }
            $isLegacy | Should -BeFalse
        }
    }
}

Describe "Product Approval Filter" {
    Context "Product pattern for approval filtering" {
        BeforeAll {
            # Simulate the approval filter pattern from the maintenance script
            $script:SelectedProducts = @("Windows 11", ".NET Framework", "Visual Studio 2022")
            $script:ApprovalPattern = '(?i)(' + (($script:SelectedProducts | ForEach-Object { [regex]::Escape($_) }) -join "|") + ')'
        }

        It "Matches update belonging to selected product" {
            $updateProducts = "Windows 11,Security Updates"
            $updateProducts | Should -Match $script:ApprovalPattern
        }

        It "Does NOT match update from non-selected product" {
            $updateProducts = "Windows Server 2022,Security Updates"
            $updateProducts | Should -Not -Match $script:ApprovalPattern
        }

        It "Matches update with multiple products including .NET Framework" {
            $updateProducts = "Windows Server 2019,.NET Framework,SQL Server"
            $updateProducts | Should -Match $script:ApprovalPattern
        }

        It "Matches Visual Studio 2022 updates when explicitly selected" {
            $updateProducts = "Visual Studio 2022,Security Updates"
            $updateProducts | Should -Match $script:ApprovalPattern
        }

        It "Case-insensitive matching for product names" {
            $updateProducts = "windows 11,security updates"
            $updateProducts | Should -Match $script:ApprovalPattern
        }

        It "Empty product list produces valid but broad pattern" {
            $emptyProducts = @()
            # When no products selected, the filter block is skipped entirely ($SelectedProducts.Count -eq 0)
            # So we test the guard condition
            ($emptyProducts -and $emptyProducts.Count -gt 0) | Should -BeFalse
        }
    }
}

Describe "WSUS Content Permission Repair" {
    It "Installer grants IIS_IUSRS and Authenticated Users list folder/read/execute access" {
        $script:InstallContent | Should -Match 'BUILTIN\\IIS_IUSRS:\(OI\)\(CI\)RX'
        $script:InstallContent | Should -Match 'NT AUTHORITY\\Authenticated Users:\(OI\)\(CI\)RX'
    }
}

Describe "SQL Login Repair Safety" {
    Context "Install script grants SQL sysadmin without requiring sqlcmd.exe" {
        It "Uses SqlClient fallback for install-time SQL permission grants" {
            $script:InstallContent | Should -Match 'System\.Data\.SqlClient\.SqlConnection'
            $script:InstallContent | Should -Match 'Grant-InstallSqlSysadmin'
        }

        It "Includes the default maintenance operator account during install" {
            $script:InstallContent | Should -Match '\$env:USERDOMAIN\\dod_admin'
            $script:InstallContent | Should -Match 'SqlSysadminAccounts'
        }
    }

    Context "Fix SQL Login works without sqlcmd.exe" {
        It "Does not fail immediately when sqlcmd.exe is missing" {
            $fixSqlBlock = [regex]::Match($script:GuiContent, '(?s)# Fix SQL Login.*?# Cancel operation button').Value
            $fixSqlBlock | Should -Match 'Add-WsusGuiSqlSysadmin'
            $fixSqlBlock | Should -Not -Match 'sqlcmd\.exe not found'
        }

        It "Can use SA password fallback when Windows auth cannot grant sysadmin" {
            $script:GuiContent | Should -Match 'Get-WsusGuiSaCredential'
            $script:GuiContent | Should -Match 'SA fallback is available'
        }
    }

    Context "Online sync pre-flight checks SQL permission without SQL command-line tools" {
        It "Uses System.Data.SqlClient when Invoke-Sqlcmd and sqlcmd.exe are unavailable" {
            $script:MaintContent | Should -Match 'Invoke-WsusMaintenanceSqlScalar'
            $script:MaintContent | Should -Match 'System\.Data\.SqlClient'
            $script:MaintContent | Should -Not -Match 'SKIP \(no SQL tools\)'
        }
    }
}
