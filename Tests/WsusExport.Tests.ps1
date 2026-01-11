#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusExport.psm1

.DESCRIPTION
    Unit tests for the WsusExport module functions including:
    - Robocopy operations (Invoke-WsusRobocopy)
    - Content export (Export-WsusContent)
    - Export statistics (Get-ExportFolderStats)
    - Archive structure (Get-ArchiveStructure)

.NOTES
    These tests use mocking to avoid actual file operations.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusExport.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusExport -ErrorAction SilentlyContinue
}

Describe "WsusExport Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusExport | Should -Not -BeNullOrEmpty
        }

        It "Should export Invoke-WsusRobocopy function" {
            Get-Command Invoke-WsusRobocopy -Module WsusExport | Should -Not -BeNullOrEmpty
        }

        It "Should export Export-WsusContent function" {
            Get-Command Export-WsusContent -Module WsusExport | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-ExportFolderStats function" {
            Get-Command Get-ExportFolderStats -Module WsusExport | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-ArchiveStructure function" {
            Get-Command Get-ArchiveStructure -Module WsusExport | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-ExportFolderStats" {
    Context "With non-existent path" {
        It "Should return hashtable with zero values for non-existent path" {
            $result = Get-ExportFolderStats -Path "C:\NonExistentPath12345"
            $result | Should -BeOfType [hashtable]
            $result.FileCount | Should -Be 0
        }
    }

    Context "Return structure validation" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName WsusExport
            Mock Get-ChildItem { @() } -ModuleName WsusExport
        }

        It "Should return a hashtable" {
            $result = Get-ExportFolderStats -Path "C:\WSUS"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain FileCount key" {
            $result = Get-ExportFolderStats -Path "C:\WSUS"
            $result.Keys | Should -Contain "FileCount"
        }

        It "Should contain TotalSizeGB key" {
            $result = Get-ExportFolderStats -Path "C:\WSUS"
            $result.Keys | Should -Contain "TotalSizeGB"
        }

        It "Should contain Exists key" {
            $result = Get-ExportFolderStats -Path "C:\WSUS"
            $result.Keys | Should -Contain "Exists"
        }
    }
}

Describe "Get-ArchiveStructure" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-ArchiveStructure -Path "C:\Export"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain required keys" {
            $result = Get-ArchiveStructure -Path "C:\Export"
            $result.Keys | Should -Contain "Exists"
        }
    }

    Context "Path validation" {
        It "Should accept Path parameter" {
            $result = Get-ArchiveStructure -Path "D:\MyExport"
            $result | Should -BeOfType [hashtable]
        }
    }
}

Describe "Invoke-WsusRobocopy" {
    Context "Parameter validation" {
        It "Should have Source parameter" {
            (Get-Command Invoke-WsusRobocopy).Parameters.Keys | Should -Contain "Source"
        }

        It "Should have Destination parameter" {
            (Get-Command Invoke-WsusRobocopy).Parameters.Keys | Should -Contain "Destination"
        }

        It "Should have ThreadCount parameter" {
            (Get-Command Invoke-WsusRobocopy).Parameters.Keys | Should -Contain "ThreadCount"
        }
    }

    Context "With mocked robocopy" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName WsusExport
            Mock Start-Process {
                [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName WsusExport
        }

        It "Should return a hashtable" {
            $result = Invoke-WsusRobocopy -Source "C:\Source" -Destination "C:\Dest"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Success key" {
            $result = Invoke-WsusRobocopy -Source "C:\Source" -Destination "C:\Dest"
            $result.Keys | Should -Contain "Success"
        }
    }
}

Describe "Export-WsusContent" {
    Context "Parameter validation" {
        It "Should have SourcePath parameter" {
            (Get-Command Export-WsusContent).Parameters.Keys | Should -Contain "SourcePath"
        }

        It "Should have DestinationPath parameter" {
            (Get-Command Export-WsusContent).Parameters.Keys | Should -Contain "DestinationPath"
        }
    }

    Context "Return structure validation" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName WsusExport
            Mock Invoke-WsusRobocopy { @{ Success = $true; ExitCode = 0 } } -ModuleName WsusExport
            Mock Get-ExportFolderStats { @{ FileCount = 100; TotalSizeGB = 5.0; Exists = $true } } -ModuleName WsusExport
        }

        It "Should return a hashtable" {
            $result = Export-WsusContent -SourcePath "C:\WSUS" -DestinationPath "C:\Export"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Success key" {
            $result = Export-WsusContent -SourcePath "C:\WSUS" -DestinationPath "C:\Export"
            $result.Keys | Should -Contain "Success"
        }
    }
}
