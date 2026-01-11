#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusScheduledTask.psm1

.DESCRIPTION
    Unit tests for the WsusScheduledTask module functions including:
    - Task creation (New-WsusMaintenanceTask)
    - Task retrieval (Get-WsusMaintenanceTask)
    - Task removal (Remove-WsusMaintenanceTask)
    - Task execution (Start-WsusMaintenanceTask)

.NOTES
    These tests use mocking to avoid actual scheduled task modifications.
#>

BeforeAll {
    # Import the module under test
    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusScheduledTask.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking
}

AfterAll {
    # Clean up
    Remove-Module WsusScheduledTask -ErrorAction SilentlyContinue
}

Describe "WsusScheduledTask Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusScheduledTask | Should -Not -BeNullOrEmpty
        }

        It "Should export New-WsusMaintenanceTask function" {
            Get-Command New-WsusMaintenanceTask -Module WsusScheduledTask | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusMaintenanceTask function" {
            Get-Command Get-WsusMaintenanceTask -Module WsusScheduledTask | Should -Not -BeNullOrEmpty
        }

        It "Should export Remove-WsusMaintenanceTask function" {
            Get-Command Remove-WsusMaintenanceTask -Module WsusScheduledTask | Should -Not -BeNullOrEmpty
        }

        It "Should export Start-WsusMaintenanceTask function" {
            Get-Command Start-WsusMaintenanceTask -Module WsusScheduledTask | Should -Not -BeNullOrEmpty
        }

        It "Should export Show-WsusScheduledTaskMenu function" {
            Get-Command Show-WsusScheduledTaskMenu -Module WsusScheduledTask | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Get-WsusMaintenanceTask" {
    Context "With non-existent task" {
        BeforeAll {
            Mock Get-ScheduledTask { $null } -ModuleName WsusScheduledTask
        }

        It "Should return hashtable with Exists=false" {
            $result = Get-WsusMaintenanceTask
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
            } -ModuleName WsusScheduledTask
            Mock Get-ScheduledTaskInfo {
                [PSCustomObject]@{
                    LastRunTime = (Get-Date).AddDays(-7)
                    NextRunTime = (Get-Date).AddDays(23)
                    LastTaskResult = 0
                }
            } -ModuleName WsusScheduledTask
        }

        It "Should return hashtable with Exists=true" {
            $result = Get-WsusMaintenanceTask
            $result | Should -BeOfType [hashtable]
            $result.Exists | Should -Be $true
        }

        It "Should contain TaskName" {
            $result = Get-WsusMaintenanceTask
            $result.TaskName | Should -Be "WSUS Monthly Maintenance"
        }

        It "Should contain State" {
            $result = Get-WsusMaintenanceTask
            $result.State | Should -Be "Ready"
        }
    }
}

Describe "Remove-WsusMaintenanceTask" {
    Context "With existing task" {
        BeforeAll {
            Mock Get-ScheduledTask {
                [PSCustomObject]@{ TaskName = "WSUS Monthly Maintenance" }
            } -ModuleName WsusScheduledTask
            Mock Unregister-ScheduledTask { } -ModuleName WsusScheduledTask
        }

        It "Should return true when task is removed" {
            $result = Remove-WsusMaintenanceTask
            $result | Should -Be $true
        }

        It "Should call Unregister-ScheduledTask" {
            Remove-WsusMaintenanceTask
            Should -Invoke Unregister-ScheduledTask -ModuleName WsusScheduledTask
        }
    }

    Context "With non-existent task" {
        BeforeAll {
            Mock Get-ScheduledTask { $null } -ModuleName WsusScheduledTask
        }

        It "Should return true when task doesn't exist" {
            $result = Remove-WsusMaintenanceTask
            $result | Should -Be $true
        }
    }
}

Describe "Start-WsusMaintenanceTask" {
    Context "With existing task" {
        BeforeAll {
            Mock Get-ScheduledTask {
                [PSCustomObject]@{ TaskName = "WSUS Monthly Maintenance" }
            } -ModuleName WsusScheduledTask
            Mock Start-ScheduledTask { } -ModuleName WsusScheduledTask
        }

        It "Should return true when task starts" {
            $result = Start-WsusMaintenanceTask
            $result | Should -Be $true
        }

        It "Should call Start-ScheduledTask" {
            Start-WsusMaintenanceTask
            Should -Invoke Start-ScheduledTask -ModuleName WsusScheduledTask
        }
    }

    Context "With non-existent task" {
        BeforeAll {
            Mock Get-ScheduledTask { $null } -ModuleName WsusScheduledTask
        }

        It "Should return false when task doesn't exist" {
            $result = Start-WsusMaintenanceTask
            $result | Should -Be $false
        }
    }
}

Describe "New-WsusMaintenanceTask" {
    Context "Parameter validation" {
        It "Should have DayOfMonth parameter" {
            (Get-Command New-WsusMaintenanceTask).Parameters.Keys | Should -Contain "DayOfMonth"
        }

        It "Should have Time parameter" {
            (Get-Command New-WsusMaintenanceTask).Parameters.Keys | Should -Contain "Time"
        }

        It "Should have Username parameter" {
            (Get-Command New-WsusMaintenanceTask).Parameters.Keys | Should -Contain "Username"
        }
    }

    Context "With valid parameters" {
        BeforeAll {
            Mock Get-ScheduledTask { $null } -ModuleName WsusScheduledTask
            Mock Register-ScheduledTask {
                [PSCustomObject]@{ TaskName = "WSUS Monthly Maintenance" }
            } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskTrigger { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskAction { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskPrincipal { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskSettingsSet { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock Test-Path { $true } -ModuleName WsusScheduledTask
        }

        It "Should return a hashtable" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "03:00" -Username "SYSTEM"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Success key" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "03:00" -Username "SYSTEM"
            $result.Keys | Should -Contain "Success"
        }
    }

    Context "DayOfMonth validation" {
        It "Should reject day 0" {
            $result = New-WsusMaintenanceTask -DayOfMonth 0 -Time "03:00" -Username "SYSTEM"
            $result.Success | Should -Be $false
        }

        It "Should reject day 29 or higher" {
            $result = New-WsusMaintenanceTask -DayOfMonth 29 -Time "03:00" -Username "SYSTEM"
            $result.Success | Should -Be $false
        }

        It "Should accept day 15" {
            Mock Test-Path { $true } -ModuleName WsusScheduledTask
            Mock Get-ScheduledTask { $null } -ModuleName WsusScheduledTask
            Mock Register-ScheduledTask { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskTrigger { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskAction { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskPrincipal { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskSettingsSet { [PSCustomObject]@{} } -ModuleName WsusScheduledTask

            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "03:00" -Username "SYSTEM"
            $result.Success | Should -Be $true
        }
    }

    Context "Time format validation" {
        It "Should reject invalid time format" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "25:00" -Username "SYSTEM"
            $result.Success | Should -Be $false
        }

        It "Should reject non-time string" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "invalid" -Username "SYSTEM"
            $result.Success | Should -Be $false
        }
    }
}
