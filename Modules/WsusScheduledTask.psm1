<#
===============================================================================
Module: WsusScheduledTask.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-09
===============================================================================

.SYNOPSIS
    WSUS scheduled task management functions

.DESCRIPTION
    Provides functions for creating and managing Windows Scheduled Tasks for
    WSUS maintenance automation including:
    - Monthly maintenance task creation
    - Task status checking
    - Task removal
#>

# ===========================
# SCHEDULED TASK FUNCTIONS
# ===========================

function New-WsusMaintenanceTask {
    <#
    .SYNOPSIS
        Creates a scheduled task for automated WSUS monthly maintenance

    .PARAMETER TaskName
        Name for the scheduled task (default: WSUS Monthly Maintenance)

    .PARAMETER ScriptPath
        Path to the maintenance script (auto-detected if not specified)

    .PARAMETER Schedule
        When to run: Monthly, Weekly, Daily (default: Monthly)

    .PARAMETER DayOfMonth
        Day of month to run (1-28, default: 15) - for Monthly schedule

    .PARAMETER DayOfWeek
        Day of week to run (Sunday-Saturday, default: Sunday) - for Weekly schedule

    .PARAMETER Time
        Time to run in HH:mm format (default: 02:00)

    .PARAMETER Profile
        Maintenance profile to use: Full, Quick, SyncOnly (default: Full)

    .PARAMETER RunAsSystem
        Run as SYSTEM account (default: true)

    .OUTPUTS
        Hashtable with task creation results
    #>
    param(
        [string]$TaskName = "WSUS Monthly Maintenance",

        [string]$ScriptPath,

        [ValidateSet('Monthly', 'Weekly', 'Daily')]
        [string]$Schedule = 'Monthly',

        [ValidateRange(1, 28)]
        [int]$DayOfMonth = 15,

        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$DayOfWeek = 'Saturday',

        [string]$Time = "01:00",

        [ValidateSet('Full', 'Quick', 'SyncOnly')]
        [string]$Profile = 'Full',

        [switch]$RunAsSystem = $true
    )

    $result = @{
        Success = $false
        TaskName = $TaskName
        Message = ""
    }

    # Auto-detect script path if not provided
    if (-not $ScriptPath) {
        $possiblePaths = @(
            "C:\WSUS\Scripts\Invoke-WsusMonthlyMaintenance.ps1",
            "C:\wsus-sql\Scripts\Invoke-WsusMonthlyMaintenance.ps1",
            (Join-Path (Split-Path $PSScriptRoot -Parent) "Scripts\Invoke-WsusMonthlyMaintenance.ps1")
        )

        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $ScriptPath = $path
                break
            }
        }
    }

    if (-not $ScriptPath -or -not (Test-Path $ScriptPath)) {
        $result.Message = "Maintenance script not found. Please specify -ScriptPath"
        return $result
    }

    try {
        # Build the action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Unattended -Profile $Profile"

        # Build the trigger based on schedule type
        $trigger = switch ($Schedule) {
            'Monthly' {
                New-ScheduledTaskTrigger -Monthly -DaysOfMonth $DayOfMonth -At $Time
            }
            'Weekly' {
                New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
            }
            'Daily' {
                New-ScheduledTaskTrigger -Daily -At $Time
            }
        }

        # Build settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Hours 4)

        # Build principal
        $principal = if ($RunAsSystem) {
            New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        } else {
            New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        }

        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            # Update existing task
            Set-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
            $result.Message = "Scheduled task '$TaskName' updated successfully"
        } else {
            # Create new task
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
            $result.Message = "Scheduled task '$TaskName' created successfully"
        }

        $result.Success = $true

    } catch {
        $result.Message = "Failed to create scheduled task: $($_.Exception.Message)"
    }

    return $result
}

function Get-WsusMaintenanceTask {
    <#
    .SYNOPSIS
        Gets information about WSUS maintenance scheduled tasks

    .PARAMETER TaskName
        Name of the task to check (default: WSUS Monthly Maintenance)

    .OUTPUTS
        Hashtable with task information or $null if not found
    #>
    param(
        [string]$TaskName = "WSUS Monthly Maintenance"
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop

        return @{
            Exists = $true
            TaskName = $task.TaskName
            State = $task.State.ToString()
            LastRunTime = $taskInfo.LastRunTime
            LastResult = $taskInfo.LastTaskResult
            NextRunTime = $taskInfo.NextRunTime
            NumberOfMissedRuns = $taskInfo.NumberOfMissedRuns
            Actions = $task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }
            Triggers = $task.Triggers | ForEach-Object { $_.ToString() }
        }
    } catch {
        return @{
            Exists = $false
            TaskName = $TaskName
            Message = "Task not found"
        }
    }
}

function Remove-WsusMaintenanceTask {
    <#
    .SYNOPSIS
        Removes a WSUS maintenance scheduled task

    .PARAMETER TaskName
        Name of the task to remove (default: WSUS Monthly Maintenance)

    .OUTPUTS
        Hashtable with removal results
    #>
    param(
        [string]$TaskName = "WSUS Monthly Maintenance"
    )

    $result = @{
        Success = $false
        TaskName = $TaskName
        Message = ""
    }

    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            $result.Success = $true
            $result.Message = "Scheduled task '$TaskName' removed successfully"
        } else {
            $result.Message = "Scheduled task '$TaskName' not found"
        }
    } catch {
        $result.Message = "Failed to remove scheduled task: $($_.Exception.Message)"
    }

    return $result
}

function Start-WsusMaintenanceTask {
    <#
    .SYNOPSIS
        Manually starts the WSUS maintenance scheduled task

    .PARAMETER TaskName
        Name of the task to start (default: WSUS Monthly Maintenance)

    .OUTPUTS
        Hashtable with start results
    #>
    param(
        [string]$TaskName = "WSUS Monthly Maintenance"
    )

    $result = @{
        Success = $false
        TaskName = $TaskName
        Message = ""
    }

    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Start-ScheduledTask -TaskName $TaskName
        $result.Success = $true
        $result.Message = "Scheduled task '$TaskName' started"
    } catch {
        $result.Message = "Failed to start scheduled task: $($_.Exception.Message)"
    }

    return $result
}

function Show-WsusScheduledTaskMenu {
    <#
    .SYNOPSIS
        Interactive menu for managing WSUS scheduled tasks
    #>
    param(
        [string]$ScriptPath
    )

    $taskName = "WSUS Monthly Maintenance"

    while ($true) {
        Clear-Host
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host "           WSUS Scheduled Task Management" -ForegroundColor Cyan
        Write-Host "=================================================================" -ForegroundColor Cyan
        Write-Host ""

        # Check current task status
        $taskInfo = Get-WsusMaintenanceTask -TaskName $taskName
        if ($taskInfo.Exists) {
            Write-Host "Current Task Status:" -ForegroundColor Yellow
            Write-Host "  Name:          $($taskInfo.TaskName)" -ForegroundColor White
            Write-Host "  State:         $($taskInfo.State)" -ForegroundColor $(if ($taskInfo.State -eq 'Ready') { 'Green' } else { 'Yellow' })
            Write-Host "  Last Run:      $($taskInfo.LastRunTime)" -ForegroundColor White
            Write-Host "  Last Result:   $($taskInfo.LastResult)" -ForegroundColor $(if ($taskInfo.LastResult -eq 0) { 'Green' } else { 'Red' })
            Write-Host "  Next Run:      $($taskInfo.NextRunTime)" -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host "  No scheduled task configured" -ForegroundColor Yellow
            Write-Host ""
        }

        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  [1] Create/Update Monthly Task (15th of each month, 1:00 AM)"
        Write-Host "  [2] Create/Update Weekly Task (Saturday, 1:00 AM)"
        Write-Host "  [3] Create Custom Task"
        Write-Host "  [4] Run Task Now"
        Write-Host "  [5] Remove Task"
        Write-Host ""
        Write-Host "  [Q] Back" -ForegroundColor Red
        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice.ToUpper()) {
            '1' {
                $result = New-WsusMaintenanceTask -Schedule Monthly -DayOfMonth 15 -Time "01:00" -Profile Full -ScriptPath $ScriptPath
                Write-Host ""
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                } else {
                    Write-Host $result.Message -ForegroundColor Red
                }
                Read-Host "Press Enter to continue"
            }
            '2' {
                $result = New-WsusMaintenanceTask -Schedule Weekly -DayOfWeek Saturday -Time "01:00" -Profile Full -ScriptPath $ScriptPath
                Write-Host ""
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                } else {
                    Write-Host $result.Message -ForegroundColor Red
                }
                Read-Host "Press Enter to continue"
            }
            '3' {
                Write-Host ""
                Write-Host "Custom Task Configuration" -ForegroundColor Yellow

                $scheduleChoice = Read-Host "Schedule (Monthly/Weekly/Daily)"
                if ($scheduleChoice -notin @('Monthly', 'Weekly', 'Daily')) { $scheduleChoice = 'Monthly' }

                $timeInput = Read-Host "Time to run (HH:mm, default 02:00)"
                if (-not $timeInput) { $timeInput = "02:00" }

                $profileChoice = Read-Host "Profile (Full/Quick/SyncOnly)"
                if ($profileChoice -notin @('Full', 'Quick', 'SyncOnly')) { $profileChoice = 'Full' }

                $params = @{
                    Schedule = $scheduleChoice
                    Time = $timeInput
                    Profile = $profileChoice
                    ScriptPath = $ScriptPath
                }

                if ($scheduleChoice -eq 'Monthly') {
                    $dayInput = Read-Host "Day of month (1-28, default 15)"
                    if ($dayInput -match '^\d+$' -and [int]$dayInput -ge 1 -and [int]$dayInput -le 28) {
                        $params.DayOfMonth = [int]$dayInput
                    }
                } elseif ($scheduleChoice -eq 'Weekly') {
                    $dayInput = Read-Host "Day of week (Sunday-Saturday)"
                    if ($dayInput -in @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')) {
                        $params.DayOfWeek = $dayInput
                    }
                }

                $result = New-WsusMaintenanceTask @params
                Write-Host ""
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                } else {
                    Write-Host $result.Message -ForegroundColor Red
                }
                Read-Host "Press Enter to continue"
            }
            '4' {
                if ($taskInfo.Exists) {
                    $result = Start-WsusMaintenanceTask
                    Write-Host ""
                    if ($result.Success) {
                        Write-Host $result.Message -ForegroundColor Green
                    } else {
                        Write-Host $result.Message -ForegroundColor Red
                    }
                } else {
                    Write-Host "No task configured. Create one first." -ForegroundColor Yellow
                }
                Read-Host "Press Enter to continue"
            }
            '5' {
                if ($taskInfo.Exists) {
                    $confirm = Read-Host "Remove task '$taskName'? (Y/N)"
                    if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                        $result = Remove-WsusMaintenanceTask
                        Write-Host ""
                        if ($result.Success) {
                            Write-Host $result.Message -ForegroundColor Green
                        } else {
                            Write-Host $result.Message -ForegroundColor Red
                        }
                    }
                } else {
                    Write-Host "No task to remove." -ForegroundColor Yellow
                }
                Read-Host "Press Enter to continue"
            }
            'Q' { return }
            default {
                Write-Host "Invalid option" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ===========================
# EXPORTS
# ===========================

Export-ModuleMember -Function @(
    'New-WsusMaintenanceTask',
    'Get-WsusMaintenanceTask',
    'Remove-WsusMaintenanceTask',
    'Start-WsusMaintenanceTask',
    'Show-WsusScheduledTaskMenu'
)
