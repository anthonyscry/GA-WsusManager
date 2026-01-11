#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusAutoDetection.psm1

.DESCRIPTION
    Unit tests for the WsusAutoDetection module functions including:
    - Service status detection (Get-DetailedServiceStatus)
    - Scheduled task status (Get-WsusScheduledTaskStatus)
    - Database size monitoring (Get-DatabaseSizeStatus)
    - Certificate status (Get-WsusCertificateStatus)
    - Disk space monitoring (Get-WsusDiskSpaceStatus)
    - Overall health aggregation (Get-WsusOverallHealth)

.NOTES
    These tests use mocking to avoid actual system queries.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusAutoDetection.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusAutoDetection -ErrorAction SilentlyContinue
}

Describe "WsusAutoDetection Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-DetailedServiceStatus function" {
            Get-Command Get-DetailedServiceStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusScheduledTaskStatus function" {
            Get-Command Get-WsusScheduledTaskStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-DatabaseSizeStatus function" {
            Get-Command Get-DatabaseSizeStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusCertificateStatus function" {
            Get-Command Get-WsusCertificateStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusDiskSpaceStatus function" {
            Get-Command Get-WsusDiskSpaceStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusOverallHealth function" {
            Get-Command Get-WsusOverallHealth -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Start-WsusAutoRecovery function" {
            Get-Command Start-WsusAutoRecovery -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }

        It "Should export Show-WsusHealthSummary function" {
            Get-Command Show-WsusHealthSummary -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-DetailedServiceStatus" {
    Context "Return structure validation" {
        It "Should return results" {
            $result = Get-DetailedServiceStatus
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return status for WSUS-related services" {
            $result = @(Get-DetailedServiceStatus)
            $result.Count | Should -BeGreaterThan 0
        }

        It "Each item should contain Name key" {
            $result = @(Get-DetailedServiceStatus)
            foreach ($item in $result) {
                $item.Keys | Should -Contain "Name"
            }
        }

        It "Each item should contain Status key" {
            $result = @(Get-DetailedServiceStatus)
            foreach ($item in $result) {
                $item.Keys | Should -Contain "Status"
            }
        }

        It "Each item should contain Critical key" {
            $result = @(Get-DetailedServiceStatus)
            foreach ($item in $result) {
                $item.Keys | Should -Contain "Critical"
            }
        }
    }
}

Describe "Get-WsusScheduledTaskStatus" {
    Context "With non-existent task" {
        BeforeAll {
            Mock Get-ScheduledTask { $null } -ModuleName WsusAutoDetection
        }

        It "Should return hashtable with Exists=false" {
            $result = Get-WsusScheduledTaskStatus
            $result | Should -BeOfType [hashtable]
            $result.Exists | Should -Be $false
        }
    }

    Context "With existing task" {
        BeforeAll {
            Mock Get-ScheduledTask {
                [PSCustomObject]@{
                    TaskName = "WSUS Monthly Maintenance"
                    State = "Ready"
                }
            } -ModuleName WsusAutoDetection
            Mock Get-ScheduledTaskInfo {
                [PSCustomObject]@{
                    LastRunTime = (Get-Date).AddDays(-7)
                    NextRunTime = (Get-Date).AddDays(23)
                    LastTaskResult = 0
                    NumberOfMissedRuns = 0
                }
            } -ModuleName WsusAutoDetection
        }

        It "Should return hashtable with Exists=true" {
            $result = Get-WsusScheduledTaskStatus
            $result | Should -BeOfType [hashtable]
            $result.Exists | Should -Be $true
        }
    }
}

Describe "Get-DatabaseSizeStatus" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-DatabaseSizeStatus
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Status key" {
            $result = Get-DatabaseSizeStatus
            $result.Keys | Should -Contain "Status"
        }

        It "Should contain SizeGB key" {
            $result = Get-DatabaseSizeStatus
            $result.Keys | Should -Contain "SizeGB"
        }

        It "Should contain PercentOfLimit key" {
            $result = Get-DatabaseSizeStatus
            $result.Keys | Should -Contain "PercentOfLimit"
        }
    }

    Context "Status values" {
        It "Status should be one of known values" {
            $result = Get-DatabaseSizeStatus
            $validStatuses = @("Unknown", "Healthy", "Moderate", "Warning", "Critical")
            $validStatuses | Should -Contain $result.Status
        }
    }
}

Describe "Get-WsusCertificateStatus" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-WsusCertificateStatus
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain SSLEnabled key" {
            $result = Get-WsusCertificateStatus
            $result.Keys | Should -Contain "SSLEnabled"
        }

        It "Should contain CertificateFound key" {
            $result = Get-WsusCertificateStatus
            $result.Keys | Should -Contain "CertificateFound"
        }
    }
}

Describe "Get-WsusDiskSpaceStatus" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-WsusDiskSpaceStatus
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Status key" {
            $result = Get-WsusDiskSpaceStatus
            $result.Keys | Should -Contain "Status"
        }

        It "Should contain FreeGB key" {
            $result = Get-WsusDiskSpaceStatus
            $result.Keys | Should -Contain "FreeGB"
        }

        It "Should contain TotalGB key" {
            $result = Get-WsusDiskSpaceStatus
            $result.Keys | Should -Contain "TotalGB"
        }
    }

    Context "With custom path" {
        It "Should accept ContentPath parameter" {
            $result = Get-WsusDiskSpaceStatus -ContentPath "C:\WSUS"
            $result | Should -BeOfType [hashtable]
        }
    }
}

Describe "Get-WsusOverallHealth" {
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-WsusOverallHealth
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Status key" {
            $result = Get-WsusOverallHealth
            $result.Keys | Should -Contain "Status"
        }

        It "Should contain Services key" {
            $result = Get-WsusOverallHealth
            $result.Keys | Should -Contain "Services"
        }

        It "Should contain Database key" {
            $result = Get-WsusOverallHealth
            $result.Keys | Should -Contain "Database"
        }

        It "Should contain DiskSpace key" {
            $result = Get-WsusOverallHealth
            $result.Keys | Should -Contain "DiskSpace"
        }
    }

    Context "Status values" {
        It "Status should be one of known values" {
            $result = Get-WsusOverallHealth
            # Module uses: Healthy, Unhealthy, Degraded, Warning, Critical, Unknown, Moderate
            $validStatuses = @("Healthy", "Unhealthy", "Degraded", "Warning", "Critical", "Unknown", "Moderate")
            $validStatuses | Should -Contain $result.Status
        }
    }
}

Describe "Start-WsusAutoRecovery" {
    Context "Return structure validation" {
        BeforeAll {
            Mock Start-Service { } -ModuleName WsusAutoDetection
            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "MockService"
                    Status = "Stopped"
                }
            } -ModuleName WsusAutoDetection
        }

        It "Should return a hashtable" {
            $result = Start-WsusAutoRecovery
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Success key" {
            $result = Start-WsusAutoRecovery
            $result.Keys | Should -Contain "Success"
        }

        It "Should contain Attempted key" {
            $result = Start-WsusAutoRecovery
            $result.Keys | Should -Contain "Attempted"
        }
    }
}
