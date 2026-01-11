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
    Context "Return structure validation" {
        It "Should return a hashtable" {
            $result = Get-WsusMaintenanceTask
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Exists key" {
            $result = Get-WsusMaintenanceTask
            $result.Keys | Should -Contain "Exists"
        }

        It "Should contain TaskName key" {
            $result = Get-WsusMaintenanceTask
            $result.Keys | Should -Contain "TaskName"
        }
    }

    Context "With non-existent default task" {
        It "Should return Exists=false for non-existent task" {
            # Use a task name that definitely doesn't exist
            $result = Get-WsusMaintenanceTask -TaskName "NonExistentTask12345XYZ"
            $result.Exists | Should -Be $false
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

        It "Should return hashtable with Success=true when task is removed" {
            $result = Remove-WsusMaintenanceTask
            $result | Should -BeOfType [hashtable]
            $result.Success | Should -Be $true
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

        It "Should return hashtable with Success=false when task doesn't exist" {
            $result = Remove-WsusMaintenanceTask
            $result | Should -BeOfType [hashtable]
            $result.Success | Should -Be $false
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

        It "Should return hashtable with Success=true when task starts" {
            $result = Start-WsusMaintenanceTask
            $result | Should -BeOfType [hashtable]
            $result.Success | Should -Be $true
        }

        It "Should call Start-ScheduledTask" {
            Start-WsusMaintenanceTask
            Should -Invoke Start-ScheduledTask -ModuleName WsusScheduledTask
        }
    }

    Context "With non-existent task" {
        BeforeAll {
            Mock Get-ScheduledTask { throw "Task not found" } -ModuleName WsusScheduledTask
        }

        It "Should return hashtable with Success=false when task doesn't exist" {
            $result = Start-WsusMaintenanceTask
            $result | Should -BeOfType [hashtable]
            $result.Success | Should -Be $false
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

        It "Should have RunAsUser parameter" {
            (Get-Command New-WsusMaintenanceTask).Parameters.Keys | Should -Contain "RunAsUser"
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
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "03:00" -RunAsUser "SYSTEM"
            $result | Should -BeOfType [hashtable]
        }

        It "Should contain Success key" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "03:00" -RunAsUser "SYSTEM"
            $result.Keys | Should -Contain "Success"
        }
    }

    Context "DayOfMonth validation" {
        It "Should reject day 0 with validation error" {
            { New-WsusMaintenanceTask -DayOfMonth 0 -Time "03:00" -RunAsUser "SYSTEM" } | Should -Throw
        }

        It "Should reject day 29 with validation error" {
            { New-WsusMaintenanceTask -DayOfMonth 29 -Time "03:00" -RunAsUser "SYSTEM" } | Should -Throw
        }

        It "Should accept day 15" {
            Mock Test-Path { $true } -ModuleName WsusScheduledTask
            Mock Get-ScheduledTask { $null } -ModuleName WsusScheduledTask
            Mock Register-ScheduledTask { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskTrigger { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskAction { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskPrincipal { [PSCustomObject]@{} } -ModuleName WsusScheduledTask
            Mock New-ScheduledTaskSettingsSet { [PSCustomObject]@{} } -ModuleName WsusScheduledTask

            # This won't succeed due to admin check, but it shouldn't throw on validation
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "03:00" -RunAsUser "SYSTEM"
            $result | Should -BeOfType [hashtable]
        }
    }

    Context "Time format validation" {
        It "Should reject invalid time format" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "25:00" -RunAsUser "SYSTEM"
            $result.Success | Should -Be $false
        }

        It "Should reject non-time string" {
            $result = New-WsusMaintenanceTask -DayOfMonth 15 -Time "invalid" -RunAsUser "SYSTEM"
            $result.Success | Should -Be $false
        }
    }
}
