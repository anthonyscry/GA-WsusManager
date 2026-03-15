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

Describe "Dashboard Data Functions" {
    Context "Module exports" {
        It "Should export Get-WsusDashboardData" {
            Get-Command Get-WsusDashboardData -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Get-WsusDashboardServiceStatus" {
            Get-Command Get-WsusDashboardServiceStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Get-WsusDashboardDiskFreeGB" {
            Get-Command Get-WsusDashboardDiskFreeGB -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Get-WsusDashboardDatabaseSizeGB" {
            Get-Command Get-WsusDashboardDatabaseSizeGB -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Get-WsusDashboardTaskStatus" {
            Get-Command Get-WsusDashboardTaskStatus -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Test-WsusDashboardInternetConnection" {
            Get-Command Test-WsusDashboardInternetConnection -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Get-WsusDashboardCachedData" {
            Get-Command Get-WsusDashboardCachedData -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Set-WsusDashboardCache" {
            Get-Command Set-WsusDashboardCache -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
        It "Should export Test-WsusDashboardDataUnavailable" {
            Get-Command Test-WsusDashboardDataUnavailable -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
        }
    }

    Context "Get-WsusDashboardData return structure" {
        BeforeAll {
            Mock Get-Service { $null } -ModuleName WsusAutoDetection
            Mock Get-PSDrive {
                [PSCustomObject]@{ Free = 50GB }
            } -ModuleName WsusAutoDetection
            Mock Get-ScheduledTask { $null } -ModuleName WsusAutoDetection
        }

        It "Should return a hashtable" {
            $result = Get-WsusDashboardData
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Services key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "Services"
        }

        It "Should contain DiskFreeGB key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "DiskFreeGB"
        }

        It "Should contain DatabaseSizeGB key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "DatabaseSizeGB"
        }

        It "Should contain TaskStatus key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "TaskStatus"
        }

        It "Should contain IsOnline key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "IsOnline"
        }

        It "Should contain CollectedAt key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "CollectedAt"
        }

        It "Should contain Error key" {
            $result = Get-WsusDashboardData
            $result.Keys | Should -Contain "Error"
        }

        It "Services value should be a hashtable with Running and Names" {
            $result = Get-WsusDashboardData
            $result.Services | Should -BeOfType [hashtable]
            $result.Services.Keys | Should -Contain "Running"
            $result.Services.Keys | Should -Contain "Names"
        }

        It "CollectedAt should be a DateTime" {
            $result = Get-WsusDashboardData
            $result.CollectedAt | Should -BeOfType [DateTime]
        }
    }

    Context "Get-WsusDashboardDiskFreeGB" {
        It "Should return a non-negative number" {
            Mock Get-PSDrive {
                [PSCustomObject]@{ Free = 100GB }
            } -ModuleName WsusAutoDetection
            $result = Get-WsusDashboardDiskFreeGB
            $result | Should -BeGreaterOrEqual 0
        }

        It "Should return 0 when drive query fails" {
            Mock Get-PSDrive { throw "Drive not found" } -ModuleName WsusAutoDetection
            $result = Get-WsusDashboardDiskFreeGB
            $result | Should -Be 0
        }
    }

    Context "Get-WsusDashboardTaskStatus" {
        It "Should return 'Not Set' when task does not exist" {
            Mock Get-ScheduledTask { $null } -ModuleName WsusAutoDetection
            $result = Get-WsusDashboardTaskStatus
            $result | Should -Be "Not Set"
        }

        It "Should return task state string when task exists" {
            Mock Get-ScheduledTask {
                [PSCustomObject]@{ State = "Ready" }
            } -ModuleName WsusAutoDetection
            $result = Get-WsusDashboardTaskStatus
            $result | Should -Be "Ready"
        }
    }

    Context "Get-WsusDashboardServiceStatus" {
        It "Should return a hashtable" {
            Mock Get-Service { $null } -ModuleName WsusAutoDetection
            $result = Get-WsusDashboardServiceStatus
            $result | Should -BeOfType [hashtable]
        }

        It "Should have Running=0 when all services are stopped" {
            Mock Get-Service {
                [PSCustomObject]@{ Name = $args[0]; Status = "Stopped" }
            } -ModuleName WsusAutoDetection
            $result = Get-WsusDashboardServiceStatus
            $result.Running | Should -Be 0
        }
    }

    Context "Cache roundtrip - Set-WsusDashboardCache and Get-WsusDashboardCachedData" {
        It "Should return null before any data is cached" {
            # Re-import to reset module state
            $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusAutoDetection.psm1"
            Import-Module $ModulePath -Force -DisableNameChecking
            $result = Get-WsusDashboardCachedData
            $result | Should -BeNullOrEmpty
        }

        It "Should return cached data after Set-WsusDashboardCache is called" {
            $fakeData = @{
                Services = @{Running=2; Names=@("SQL","WSUS")}
                DiskFreeGB = 42.5
                DatabaseSizeGB = 1.2
                TaskStatus = "Ready"
                IsOnline = $true
                CollectedAt = Get-Date
                Error = $null
            }
            Set-WsusDashboardCache -Data $fakeData
            $result = Get-WsusDashboardCachedData
            $result | Should -Not -BeNullOrEmpty
            $result.DiskFreeGB | Should -Be 42.5
        }

        It "Should not cache data with an error" {
            # Re-import to reset module state
            $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusAutoDetection.psm1"
            Import-Module $ModulePath -Force -DisableNameChecking
            $errorData = @{
                Services = @{Running=0; Names=@()}
                DiskFreeGB = 0
                DatabaseSizeGB = -1
                TaskStatus = "Not Set"
                IsOnline = $false
                CollectedAt = Get-Date
                Error = "Something went wrong"
            }
            Set-WsusDashboardCache -Data $errorData
            $result = Get-WsusDashboardCachedData
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Test-WsusDashboardDataUnavailable" {
        It "Should return false initially" {
            # Re-import to reset module state
            $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusAutoDetection.psm1"
            Import-Module $ModulePath -Force -DisableNameChecking
            $result = Test-WsusDashboardDataUnavailable
            $result | Should -Be $false
        }

        It "Should return true after 10 consecutive failures" {
            $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusAutoDetection.psm1"
            Import-Module $ModulePath -Force -DisableNameChecking
            $errorData = @{ Error = "fail" }
            1..10 | ForEach-Object { Set-WsusDashboardCache -Data $errorData }
            $result = Test-WsusDashboardDataUnavailable
            $result | Should -Be $true
        }

        It "Should reset to false after successful cache set" {
            $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusAutoDetection.psm1"
            Import-Module $ModulePath -Force -DisableNameChecking
            $errorData = @{ Error = "fail" }
            1..10 | ForEach-Object { Set-WsusDashboardCache -Data $errorData }
            $goodData = @{
                Services = @{Running=1; Names=@("SQL")}
                DiskFreeGB = 10
                DatabaseSizeGB = 0.5
                TaskStatus = "Ready"
                IsOnline = $false
                CollectedAt = Get-Date
                Error = $null
            }
            Set-WsusDashboardCache -Data $goodData
            $result = Test-WsusDashboardDataUnavailable
            $result | Should -Be $false
        }
    }
}
