#Requires -Modules Pester
<#
.SYNOPSIS
    Tests for WsusProvisioning.psm1 — provisioning helpers for WSUS install,
    SQL installer discovery, backup resolution, and path validation.
#>

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\Modules\WsusProvisioning.psm1'
    Import-Module $script:ModulePath -Force -DisableNameChecking
}

AfterAll {
    Remove-Module WsusProvisioning -ErrorAction SilentlyContinue
}

# ======================================================================
# Get-WsusSqlInstallerCandidates
# ======================================================================
Describe 'Get-WsusSqlInstallerCandidates' {
    It 'Returns the bootstrapper (SSE) candidate first' {
        $candidates = Get-WsusSqlInstallerCandidates
        $candidates[0] | Should -Be 'SQL2025-SSEI-Expr.exe'
    }

    It 'Includes both ADV and non-ADV offline installers' {
        $candidates = Get-WsusSqlInstallerCandidates
        $candidates | Should -Contain 'SQLEXPRADV_x64_ENU.exe'
        $candidates | Should -Contain 'SQLEXPR_x64_ENU.exe'
    }

    It 'Returns exactly 3 candidates' {
        $candidates = Get-WsusSqlInstallerCandidates
        $candidates.Count | Should -Be 3
    }

    It 'Returns a fresh array each call' {
        $first = Get-WsusSqlInstallerCandidates
        $second = Get-WsusSqlInstallerCandidates
        $first | Should -Be $second
        $first -is [array] | Should -BeTrue
    }
}

# ======================================================================
# Test-WsusProvisioningPath
# ======================================================================
Describe 'Test-WsusProvisioningPath' {
    It 'Returns false for whitespace-only string' {
        Test-WsusProvisioningPath -Path '   ' | Should -BeFalse
    }

    It 'Returns true for a valid local path' {
        Test-WsusProvisioningPath -Path 'C:\WSUS' | Should -BeTrue
    }

    It 'Returns true for a UNC path' {
        Test-WsusProvisioningPath -Path '\\SERVER\Share' | Should -BeTrue
    }

    It 'Returns false for a path with embedded null char' {
        Test-WsusProvisioningPath -Path "C:\`0Bad" | Should -BeFalse
    }

    It 'Returns true for a path with spaces' {
        Test-WsusProvisioningPath -Path 'C:\WSUS Manager\Path' | Should -BeTrue
    }

    It 'Returns true for a nested path' {
        Test-WsusProvisioningPath -Path 'C:\WSUS\SQLDB\Installers' | Should -BeTrue
    }
}

# ======================================================================
# Find-WsusSqlInstaller
# ======================================================================
Describe 'Find-WsusSqlInstaller' {
    It 'Returns Success when a candidate exists' {
        $root = Join-Path $TestDrive 'sql_find'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $root 'SQLEXPRADV_x64_ENU.exe') -ItemType File -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.Success | Should -BeTrue
        $result.InstallerName | Should -Be 'SQLEXPRADV_x64_ENU.exe'
    }

    It 'Returns the bootstrapper when it coexists with offline installer' {
        $root = Join-Path $TestDrive 'sql_find_both'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $root 'SQL2025-SSEI-Expr.exe') -ItemType File -Force | Out-Null
        New-Item -Path (Join-Path $root 'SQLEXPRADV_x64_ENU.exe') -ItemType File -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.Success | Should -BeTrue
        $result.InstallerName | Should -Be 'SQL2025-SSEI-Expr.exe'
    }

    It 'Returns Success=false when no candidate exists' {
        $root = Join-Path $TestDrive 'sql_empty'
        New-Item -Path $root -ItemType Directory -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.Success | Should -BeFalse
        $result.InstallerFile | Should -BeNullOrEmpty
    }

    It 'Returns a descriptive message on failure' {
        $root = Join-Path $TestDrive 'sql_empty_msg'
        New-Item -Path $root -ItemType Directory -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.Message | Should -Match 'No SQL Express installer found'
    }

    It 'Includes expected file names in the failure message' {
        $root = Join-Path $TestDrive 'sql_expected_names'
        New-Item -Path $root -ItemType Directory -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.Message | Should -Match 'SQLEXPRADV_x64_ENU'
        $result.Message | Should -Match 'SQLEXPR_x64_ENU'
    }

    It 'Returns the full path in InstallerFile on success' {
        $root = Join-Path $TestDrive 'sql_fullpath'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $expectedPath = Join-Path $root 'SQLEXPR_x64_ENU.exe'
        New-Item -Path $expectedPath -ItemType File -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.InstallerFile | Should -Be (Resolve-Path $expectedPath).Path
    }

    It 'Handles case-insensitive file extension matching' {
        $root = Join-Path $TestDrive 'sql_case'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $root 'SQLEXPRADV_x64_ENU.EXE') -ItemType File -Force | Out-Null

        $result = Find-WsusSqlInstaller -InstallerPath $root
        $result.Success | Should -BeTrue
    }
}

# ======================================================================
# Resolve-WsusInstallerPath
# ======================================================================
Describe 'Resolve-WsusInstallerPath' {
    It 'Returns Success=false when the installer folder does not exist' {
        $result = Resolve-WsusInstallerPath -InstallerPath 'Z:\NonExistentDrive\SQLDB'
        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'not found'
    }

    It 'Delegates to Find-WsusSqlInstaller when folder exists' {
        $root = Join-Path $TestDrive 'resolve_delegation'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $root 'SQLEXPRADV_x64_ENU.exe') -ItemType File -Force | Out-Null

        $result = Resolve-WsusInstallerPath -InstallerPath $root
        $result.Success | Should -BeTrue
        $result.InstallerName | Should -Be 'SQLEXPRADV_x64_ENU.exe'
    }

    It 'Returns a result object with standard keys' {
        $root = Join-Path $TestDrive 'resolve_keys'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $root 'SQLEXPRADV_x64_ENU.exe') -ItemType File -Force | Out-Null

        $result = Resolve-WsusInstallerPath -InstallerPath $root
        $result.Success | Should -BeTrue
        $result.InstallerPath | Should -Be $root
        $result.InstallerName | Should -Be 'SQLEXPRADV_x64_ENU.exe'
        $result.InstallerFile | Should -Not -BeNullOrEmpty
    }
}

# ======================================================================
# Resolve-WsusRestoreBackup
# ======================================================================
Describe 'Resolve-WsusRestoreBackup' {
    Context 'With explicit backup path' {
        It 'Returns Success for a valid .bak file' {
            $bakFile = Join-Path $TestDrive 'SUSDB_20250101.bak'
            New-Item -Path $bakFile -ItemType File -Force | Out-Null

            $result = Resolve-WsusRestoreBackup -BackupPath $bakFile -ContentPath $TestDrive
            $result.Success | Should -BeTrue
            $result.BackupFile | Should -Be (Resolve-Path $bakFile).Path
        }

        It 'Returns Success=false when the file does not exist' {
            $result = Resolve-WsusRestoreBackup -BackupPath (Join-Path $TestDrive 'missing.bak') -ContentPath $TestDrive
            $result.Success | Should -BeFalse
        }

        It 'Returns Success=false when the file is not a .bak extension' {
            $txtFile = Join-Path $TestDrive 'SUSDB_backup.txt'
            New-Item -Path $txtFile -ItemType File -Force | Out-Null

            $result = Resolve-WsusRestoreBackup -BackupPath $txtFile -ContentPath $TestDrive
            $result.Success | Should -BeFalse
            $result.Message | Should -Match '\.bak'
        }

        It 'Rejects a directory path instead of a file' {
            $dir = Join-Path $TestDrive 'not_a_file'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null

            $result = Resolve-WsusRestoreBackup -BackupPath $dir -ContentPath $TestDrive
            $result.Success | Should -BeFalse
        }
    }

    Context 'Without explicit backup path (auto-detect)' {
        It 'Returns Success=false when no .bak files exist in content path' {
            $result = Resolve-WsusRestoreBackup -ContentPath $TestDrive
            $result.Success | Should -BeFalse
            $result.Message | Should -Match 'No \.bak files found'
        }

        It 'Chooses the most recent .bak file' {
            $older = Join-Path $TestDrive 'SUSDB_20240101.bak'
            $newer = Join-Path $TestDrive 'SUSDB_20250101.bak'
            New-Item -Path $older -ItemType File -Force | Out-Null
            Start-Sleep -Milliseconds 100
            New-Item -Path $newer -ItemType File -Force | Out-Null

            $result = Resolve-WsusRestoreBackup -ContentPath $TestDrive
            $result.Success | Should -BeTrue
            $result.BackupFile | Should -Be (Resolve-Path $newer).Path
        }

        It 'Ignores non-.bak files when auto-detecting' {
            $bakFile = Join-Path $TestDrive 'SUSDB_20250101.bak'
            $txtFile = Join-Path $TestDrive 'notes.txt'
            New-Item -Path $txtFile -ItemType File -Force | Out-Null
            New-Item -Path $bakFile -ItemType File -Force | Out-Null

            $result = Resolve-WsusRestoreBackup -ContentPath $TestDrive
            $result.Success | Should -BeTrue
            $result.BackupFile | Should -Be (Resolve-Path $bakFile).Path
        }
    }
}

# ======================================================================
# Module Exports
# ======================================================================
Describe 'Module Exports' {
    It 'Exports Get-WsusSqlInstallerCandidates' {
        Get-Command Get-WsusSqlInstallerCandidates -Module WsusProvisioning | Should -Not -BeNullOrEmpty
    }

    It 'Exports Find-WsusSqlInstaller' {
        Get-Command Find-WsusSqlInstaller -Module WsusProvisioning | Should -Not -BeNullOrEmpty
    }

    It 'Exports Resolve-WsusInstallerPath' {
        Get-Command Resolve-WsusInstallerPath -Module WsusProvisioning | Should -Not -BeNullOrEmpty
    }

    It 'Exports Resolve-WsusRestoreBackup' {
        Get-Command Resolve-WsusRestoreBackup -Module WsusProvisioning | Should -Not -BeNullOrEmpty
    }

    It 'Exports Test-WsusProvisioningPath' {
        Get-Command Test-WsusProvisioningPath -Module WsusProvisioning | Should -Not -BeNullOrEmpty
    }

    It 'Exports exactly 5 functions' {
        (Get-Command -Module WsusProvisioning).Count | Should -Be 5
    }
}
