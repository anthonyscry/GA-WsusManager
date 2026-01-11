#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusDatabase.psm1

.DESCRIPTION
    Unit tests for the WsusDatabase module functions including:
    - Database size queries
    - Supersession cleanup functions
    - Index optimization functions
    - Database maintenance functions

.NOTES
    These tests use mocking to avoid actual database operations.
    Most functions require SQL Server connectivity for integration tests.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusDatabase.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusDatabase -ErrorAction SilentlyContinue
}

Describe "WsusDatabase Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusDatabase | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusDatabaseSize function" {
            Get-Command Get-WsusDatabaseSize -Module WsusDatabase | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusDatabaseStats function" {
            Get-Command Get-WsusDatabaseStats -Module WsusDatabase | Should -Not -BeNullOrEmpty
        }

        It "Should export Remove-DeclinedSupersessionRecords function" {
            Get-Command Remove-DeclinedSupersessionRecords -Module WsusDatabase | Should -Not -BeNullOrEmpty
        }

        It "Should export Optimize-WsusIndexes function" {
            Get-Command Optimize-WsusIndexes -Module WsusDatabase | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusDiskSpace function" {
            Get-Command Test-WsusDiskSpace -Module WsusDatabase | Should -Not -BeNullOrEmpty
        }

        It "Should export Test-WsusDatabaseConsistency function" {
            Get-Command Test-WsusDatabaseConsistency -Module WsusDatabase | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WsusDatabaseSize" {
    Context "With mocked SQL query" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{ SizeGB = 5.25 }
            } -ModuleName WsusDatabase
        }

        It "Should return database size in GB" {
            $result = Get-WsusDatabaseSize
            $result | Should -Be 5.25
        }

        It "Should accept SqlInstance parameter" {
            $result = Get-WsusDatabaseSize -SqlInstance "localhost\SQLEXPRESS"
            $result | Should -Be 5.25
        }
    }

    Context "With mocked SQL error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "SQL connection failed"
            } -ModuleName WsusDatabase
        }

        It "Should return 0 on error" {
            $result = Get-WsusDatabaseSize
            $result | Should -Be 0
        }
    }
}

Describe "Get-WsusDatabaseStats" {
    Context "With mocked SQL query" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{
                    SupersessionRecords = 50000
                    DeclinedRevisions = 1000
                    SupersededRevisions = 5000
                    FilesPresent = 10000
                    FilesTotal = 15000
                    FilesInDownloadQueue = 50
                    SizeGB = 5.25
                }
            } -ModuleName WsusDatabase
        }

        It "Should return database stats object" {
            $result = Get-WsusDatabaseStats
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should include SupersessionRecords" {
            $result = Get-WsusDatabaseStats
            $result.SupersessionRecords | Should -Be 50000
        }

        It "Should include SizeGB" {
            $result = Get-WsusDatabaseStats
            $result.SizeGB | Should -Be 5.25
        }
    }

    Context "With mocked SQL error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "SQL connection failed"
            } -ModuleName WsusDatabase
        }

        It "Should return null on error" {
            $result = Get-WsusDatabaseStats
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Remove-DeclinedSupersessionRecords" {
    Context "With mocked successful cleanup" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{ DeletedDeclined = 500 }
            } -ModuleName WsusDatabase
        }

        It "Should return number of deleted records" {
            $result = Remove-DeclinedSupersessionRecords
            $result | Should -Be 500
        }
    }

    Context "With mocked SQL error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "SQL error"
            } -ModuleName WsusDatabase
        }

        It "Should return 0 on error" {
            $result = Remove-DeclinedSupersessionRecords
            $result | Should -Be 0
        }
    }
}

Describe "Remove-SupersededSupersessionRecords" {
    Context "With mocked successful cleanup" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{ DeletedSuperseded = 10000 }
            } -ModuleName WsusDatabase
        }

        It "Should return number of deleted records" {
            $result = Remove-SupersededSupersessionRecords
            $result | Should -Be 10000
        }

        It "Should accept BatchSize parameter" {
            $result = Remove-SupersededSupersessionRecords -BatchSize 5000
            $result | Should -Be 10000
        }
    }

    Context "With null result" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                $null
            } -ModuleName WsusDatabase
        }

        It "Should return 0 when result is null" {
            $result = Remove-SupersededSupersessionRecords
            $result | Should -Be 0
        }
    }
}

Describe "Optimize-WsusIndexes" {
    Context "With mocked successful optimization" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{
                    IndexesRebuilt = 5
                    IndexesReorganized = 10
                }
            } -ModuleName WsusDatabase
        }

        It "Should return hashtable with results" {
            $result = Optimize-WsusIndexes
            $result | Should -BeOfType [hashtable]
        }

        It "Should include Rebuilt count" {
            $result = Optimize-WsusIndexes
            $result.Rebuilt | Should -Be 5
        }

        It "Should include Reorganized count" {
            $result = Optimize-WsusIndexes
            $result.Reorganized | Should -Be 10
        }
    }

    Context "With null result" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                $null
            } -ModuleName WsusDatabase
        }

        It "Should return 0 for both counts when result is null" {
            $result = Optimize-WsusIndexes
            $result.Rebuilt | Should -Be 0
            $result.Reorganized | Should -Be 0
        }
    }

    Context "With mocked SQL error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "SQL error"
            } -ModuleName WsusDatabase
        }

        It "Should return 0 for both counts on error" {
            $result = Optimize-WsusIndexes
            $result.Rebuilt | Should -Be 0
            $result.Reorganized | Should -Be 0
        }
    }
}

Describe "Add-WsusPerformanceIndexes" {
    Context "With mocked SQL execution" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                "Created IX_tbRevisionSupersedesUpdate"
            } -ModuleName WsusDatabase
        }

        It "Should not throw" {
            { Add-WsusPerformanceIndexes } | Should -Not -Throw
        }
    }
}

Describe "Update-WsusStatistics" {
    Context "With mocked successful update" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd { } -ModuleName WsusDatabase
        }

        It "Should return true on success" {
            $result = Update-WsusStatistics
            $result | Should -Be $true
        }
    }

    Context "With mocked SQL error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "SQL error"
            } -ModuleName WsusDatabase
        }

        It "Should return false on error" {
            $result = Update-WsusStatistics
            $result | Should -Be $false
        }
    }
}

Describe "Invoke-WsusDatabaseShrink" {
    Context "With mocked successful shrink" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd { } -ModuleName WsusDatabase
        }

        It "Should return true on success" {
            $result = Invoke-WsusDatabaseShrink
            $result | Should -Be $true
        }

        It "Should accept TargetFreePercent parameter" {
            $result = Invoke-WsusDatabaseShrink -TargetFreePercent 5
            $result | Should -Be $true
        }
    }

    Context "With mocked SQL error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "SQL error"
            } -ModuleName WsusDatabase
        }

        It "Should return false on error" {
            $result = Invoke-WsusDatabaseShrink
            $result | Should -Be $false
        }
    }
}

Describe "Get-WsusDatabaseSpace" {
    Context "With mocked SQL query" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                [PSCustomObject]@{
                    AllocatedMB = 5000
                    UsedMB = 4500
                    FreeMB = 500
                }
            } -ModuleName WsusDatabase
        }

        It "Should return space info object" {
            $result = Get-WsusDatabaseSpace
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should include AllocatedMB" {
            $result = Get-WsusDatabaseSpace
            $result.AllocatedMB | Should -Be 5000
        }

        It "Should include UsedMB" {
            $result = Get-WsusDatabaseSpace
            $result.UsedMB | Should -Be 4500
        }

        It "Should include FreeMB" {
            $result = Get-WsusDatabaseSpace
            $result.FreeMB | Should -Be 500
        }
    }
}

Describe "Test-WsusBackupIntegrity" {
    Context "With non-existent backup file" {
        It "Should return IsValid = false for non-existent file" {
            $result = Test-WsusBackupIntegrity -BackupPath "C:\NonExistent\backup.bak"
            $result.IsValid | Should -Be $false
            $result.Message | Should -Match "not found"
        }
    }

    Context "With mocked backup verification" {
        BeforeAll {
            # Create a temp file to simulate backup with some content
            $script:TempBackup = Join-Path $env:TEMP "test-backup.bak"
            # Write at least 1KB of data so size is measurable
            $fakeData = "X" * 1024
            Set-Content -Path $script:TempBackup -Value $fakeData -NoNewline

            Mock Invoke-WsusSqlcmd {
                if ($Query -match "HEADERONLY") {
                    [PSCustomObject]@{
                        DatabaseName = "SUSDB"
                        BackupFinishDate = Get-Date
                    }
                }
            } -ModuleName WsusDatabase
        }

        AfterAll {
            if (Test-Path $script:TempBackup) {
                Remove-Item $script:TempBackup -Force
            }
        }

        It "Should return backup file info" {
            $result = Test-WsusBackupIntegrity -BackupPath $script:TempBackup
            $result.BackupFile | Should -Be $script:TempBackup
            $result.BackupSizeMB | Should -BeGreaterOrEqual 0
        }
    }
}

Describe "Test-WsusDiskSpace" {
    Context "With valid path" {
        BeforeAll {
            Mock Get-WsusDatabaseSize { 5 } -ModuleName WsusDatabase
        }

        It "Should return hashtable with disk space info" {
            $result = Test-WsusDiskSpace -Path $env:TEMP
            $result | Should -BeOfType [hashtable]
        }

        It "Should include HasSufficientSpace key" {
            $result = Test-WsusDiskSpace -Path $env:TEMP
            $result.Keys | Should -Contain "HasSufficientSpace"
        }

        It "Should include FreeSpaceGB key" {
            $result = Test-WsusDiskSpace -Path $env:TEMP
            $result.Keys | Should -Contain "FreeSpaceGB"
        }

        It "Should include RequiredSpaceGB key" {
            $result = Test-WsusDiskSpace -Path $env:TEMP
            $result.Keys | Should -Contain "RequiredSpaceGB"
        }

        It "Should accept RequiredSpaceGB parameter" {
            $result = Test-WsusDiskSpace -Path $env:TEMP -RequiredSpaceGB 1
            $result.RequiredSpaceGB | Should -BeGreaterOrEqual 1
        }
    }
}

Describe "Test-WsusDatabaseConsistency" {
    Context "With mocked successful check" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd { } -ModuleName WsusDatabase
        }

        It "Should return hashtable with results" {
            $result = Test-WsusDatabaseConsistency
            $result | Should -BeOfType [hashtable]
        }

        It "Should include IsConsistent key" {
            $result = Test-WsusDatabaseConsistency
            $result.Keys | Should -Contain "IsConsistent"
        }

        It "Should include Duration key" {
            $result = Test-WsusDatabaseConsistency
            $result.Keys | Should -Contain "Duration"
        }

        It "Should return IsConsistent = true on success" {
            $result = Test-WsusDatabaseConsistency
            $result.IsConsistent | Should -Be $true
        }
    }

    Context "With mocked consistency error" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd {
                throw "CHECKDB error"
            } -ModuleName WsusDatabase
        }

        It "Should return IsConsistent = false on error" {
            $result = Test-WsusDatabaseConsistency
            $result.IsConsistent | Should -Be $false
        }

        It "Should include error in Message" {
            $result = Test-WsusDatabaseConsistency
            $result.Message | Should -Match "failed"
        }
    }

    Context "With PhysicalOnly parameter" {
        BeforeAll {
            Mock Invoke-WsusSqlcmd { } -ModuleName WsusDatabase
        }

        It "Should accept PhysicalOnly switch" {
            { Test-WsusDatabaseConsistency -PhysicalOnly } | Should -Not -Throw
        }
    }
}
