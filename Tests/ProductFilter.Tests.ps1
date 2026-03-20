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
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:MaintScript = Join-Path $script:RepoRoot "Scripts\Invoke-WsusMonthlyMaintenance.ps1"
    $script:MaintContent = Get-Content $script:MaintScript -Raw
}

Describe "Product Decline Pattern (Word-Boundary Matching)" {
    Context "Pattern construction matches maintenance script logic" {
        It "Uses word-boundary pattern (\b) for product matching in decline logic" {
            $script:MaintContent | Should -Match '\\b\('
            $script:MaintContent | Should -Match '\$enabledTitles'
            $script:MaintContent | Should -Match '\$productPattern'
        }

        It "Escapes product titles with [regex]::Escape before building pattern" {
            $script:MaintContent | Should -Match '\[regex\]::Escape\(\$_\.Title\)'
        }
    }

    Context "Word-boundary matching behavior" {
        BeforeAll {
            # Simulate the exact pattern construction from line 896-897
            $script:EnabledTitles = @(
                [regex]::Escape("Windows 11"),
                [regex]::Escape("Windows Server 2019"),
                [regex]::Escape("Microsoft 365 Apps")
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
            "Microsoft 365 Apps,Office" | Should -Match $script:DeclinePattern
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

Describe "Office 365 LTSC Exception (Decline Logic)" {
    Context "Pattern for identifying non-LTSC Microsoft 365 updates" {
        It "Declines Microsoft 365 updates that lack LTSC or 2024 in title" {
            # Simulates the logic at line 900-903
            $updateProductString = "Microsoft 365 Apps"
            $updateTitle = "Microsoft 365 Apps - Feature Update 2402"

            $isM365 = $updateProductString -like "*Microsoft 365*"
            $isLTSC = $updateTitle -like "*LTSC*"
            $is2024 = $updateTitle -like "*2024*"
            $shouldDecline = $isM365 -and (-not $isLTSC) -and (-not $is2024)

            $shouldDecline | Should -BeTrue
        }

        It "Preserves Microsoft 365 updates that have LTSC in title" {
            $updateProductString = "Microsoft 365 Apps"
            $updateTitle = "Microsoft 365 Apps for Enterprise 2024 LTSC"

            $isM365 = $updateProductString -like "*Microsoft 365*"
            $isLTSC = $updateTitle -like "*LTSC*"
            $is2024 = $updateTitle -like "*2024*"
            $shouldDecline = $isM365 -and (-not $isLTSC) -and (-not $is2024)

            $shouldDecline | Should -BeFalse
        }

        It "Preserves Microsoft 365 updates that have 2024 in title" {
            $updateProductString = "Microsoft 365 Apps"
            $updateTitle = "Microsoft 365 Apps - Update 2024.03"

            $isM365 = $updateProductString -like "*Microsoft 365*"
            $isLTSC = $updateTitle -like "*LTSC*"
            $is2024 = $updateTitle -like "*2024*"
            $shouldDecline = $isM365 -and (-not $isLTSC) -and (-not $is2024)

            $shouldDecline | Should -BeFalse
        }

        It "Does NOT affect non-Microsoft 365 updates" {
            $updateProductString = "Windows 11"
            $updateTitle = "Security Update for Windows 11"

            $isM365 = $updateProductString -like "*Microsoft 365*"
            $shouldDecline = $isM365 -and (-not $false) -and (-not $false)

            $shouldDecline | Should -BeFalse
        }

        It "Declines Microsoft 365 without LTSC or 2024 (edge case)" {
            $updateProductString = "Microsoft 365 Apps"
            $updateTitle = "OneDrive sync update"

            $isM365 = $updateProductString -like "*Microsoft 365*"
            $isLTSC = $updateTitle -like "*LTSC*"
            $is2024 = $updateTitle -like "*2024*"
            $shouldDecline = $isM365 -and (-not $isLTSC) -and (-not $is2024)

            $shouldDecline | Should -BeTrue
        }
    }
}

Describe "Office 365 LTSC Exception (Approval Logic)" {
    Context "Pattern for filtering pending approvals" {
        It "Script has the LTSC/2024 filter in approval section" {
            $script:MaintContent | Should -Match 'skip Office 365 updates that are NOT Office 2024 LTSC'
        }

        It "Uses correct filter: notlike LTSC AND notlike 2024" {
            # Simulates the logic at line 1109-1114
            $update = @{
                ProductTitles = @("Microsoft 365 Apps")
                Title = "Feature Update 2402"
            }

            $prodStr = $update.ProductTitles -join ","
            $isM365 = $prodStr -like "*Microsoft 365*"
            $isLTSC = $update.Title -like "*LTSC*"
            $is2024 = $update.Title -like "*2024*"
            $skipApproval = $isM365 -and (-not $isLTSC) -and (-not $is2024)

            $skipApproval | Should -BeTrue
        }

        It "Approves LTSC updates from Microsoft 365" {
            $update = @{
                ProductTitles = @("Microsoft 365 Apps")
                Title = "Microsoft 365 Apps for Enterprise LTSC 2024"
            }

            $prodStr = $update.ProductTitles -join ","
            $isM365 = $prodStr -like "*Microsoft 365*"
            $isLTSC = $update.Title -like "*LTSC*"
            $is2024 = $update.Title -like "*2024*"
            $skipApproval = $isM365 -and (-not $isLTSC) -and (-not $is2024)

            $skipApproval | Should -BeFalse
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

    Context "Legacy build exclusion (21H2/22H2/23H2)" {
        It "Script uses word-boundary match for legacy builds" {
            $script:MaintContent | Should -Match '\\b\(21H2\|22H2\|23H2\)\\b'
        }

        It "Matches 23H2 in update titles" {
            "Windows 11 Version 23H2 Security Update" -match '(?i)\b(21H2|22H2|23H2)\b' | Should -BeTrue
        }

        It "Matches 21H2 in update titles" {
            "Windows 10 Version 21H2 Servicing Stack" -match '(?i)\b(21H2|22H2|23H2)\b' | Should -BeTrue
        }

        It "Does NOT match Windows 11 without build version" {
            "Security Update for Windows 11" -match '(?i)\b(21H2|22H2|23H2)\b' | Should -BeFalse
        }
    }
}

Describe "Product Approval Filter" {
    Context "Product pattern for approval filtering" {
        BeforeAll {
            # Simulate the approval filter pattern from line 1104
            $script:SelectedProducts = @("Windows 11", "Windows Server 2019")
            $script:ApprovalPattern = '(?i)(' + (($script:SelectedProducts | ForEach-Object { [regex]::Escape($_) }) -join "|") + ')'
        }

        It "Matches update belonging to selected product" {
            $updateProducts = "Windows 11,Security Updates"
            $updateProducts | Should -Match $script:ApprovalPattern
        }

        It "Does NOT match update from non-selected product" {
            $updateProducts = "Windows 10,Security Updates"
            $updateProducts | Should -Not -Match $script:ApprovalPattern
        }

        It "Matches update with multiple products including a selected one" {
            $updateProducts = "Windows Server 2019,.NET Framework,SQL Server"
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

Describe "SQL Injection Safety" {
    Context "Install script uses sqlcmd -v for user context" {
        It "Install script passes currentUser via sqlcmd -v variable" {
            $installScript = Get-Content (Join-Path $script:RepoRoot "Scripts\Install-WsusWithSqlExpress.ps1") -Raw
            $installScript | Should -Match '-v CurrentUser='
            $installScript | Should -Match '\$\(CurrentUser\)'  # sqlcmd variable syntax
        }

        It "Does NOT interpolate currentUser directly into SQL string" {
            $installScript = Get-Content (Join-Path $script:RepoRoot "Scripts\Install-WsusWithSqlExpress.ps1") -Raw
            # Old pattern was: -Q "CREATE LOGIN [$currentUser] FROM WINDOWS"
            # New pattern uses $(CurrentUser) which is sqlcmd variable, not PS interpolation
            # Check that there's no bare $currentUser inside -Q strings
            $lines = $installScript -split "`n"
            $sqlLines = $lines | Where-Object { $_ -match '\-Q\s+"' }
            foreach ($line in $sqlLines) {
                # If -Q contains variable syntax, it should be $(CurrentUser) not $currentUser
                if ($line -match '\$currentUser' -and $line -notmatch '\$\(CurrentUser\)') {
                    throw "Found potentially unsafe direct interpolation in SQL: $line"
                }
            }
            $true | Should -BeTrue
        }
    }
}
