<#
===============================================================================
Module: WsusScheduledTask.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.1.0
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
# PRIVATE HELPER FUNCTIONS
# ===========================

function Test-ValidTimeFormat {
    <#
    .SYNOPSIS
        Validates time string is in HH:mm format
    #>
    param([string]$Time)

    if ($Time -notmatch '^\d{1,2}:\d{2}$') {
        return $false
    }

    $parts = $Time -split ':'
    $hour = [int]$parts[0]
    $minute = [int]$parts[1]

    return ($hour -ge 0 -and $hour -le 23 -and $minute -ge 0 -and $minute -le 59)
}

function Test-ValidUserFormat {
    <#
    .SYNOPSIS
        Validates user account format (.\user, DOMAIN\user, or user@domain)
    #>
    param([string]$User)

    if ([string]::IsNullOrWhiteSpace($User)) {
        return $false
    }

    # Accept: .\username, DOMAIN\username, username@domain.com, or just username
    return ($User -match '^\.\\[\w\-]+$' -or
            $User -match '^[\w\-]+\\[\w\-]+$' -or
            $User -match '^[\w\-\.]+@[\w\-\.]+$' -or
            $User -match '^[\w\-]+$')
}

function ConvertFrom-SecureStringToPlainText {
    <#
    .SYNOPSIS
        Converts SecureString to plain text (for Register-ScheduledTask)
    #>
    param([securestring]$SecureString)

    if (-not $SecureString -or $SecureString.Length -eq 0) {
        return $null
    }

    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks if current session has administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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
        Day of month to run (1-31, default: 15) - for Monthly schedule

    .PARAMETER DayOfWeek
        Day of week to run (Sunday-Saturday, default: Sunday) - for Weekly schedule

    .PARAMETER Time
        Time to run in HH:mm format (default: 02:00)

    .PARAMETER MaintenanceProfile
        Maintenance profile to use: Full, Quick, SyncOnly (default: Full)

    .PARAMETER RunAsUser
        User account to run the task as (default: dod_admin)

    .PARAMETER UserPassword
        Password for the user account (will prompt if not provided)

    .OUTPUTS
        Hashtable with task creation results
    #>
    param(
        [string]$TaskName = "WSUS Monthly Maintenance",

        [string]$ScriptPath,

        [ValidateSet('Monthly', 'Weekly', 'Daily')]
        [string]$Schedule = 'Monthly',

        [ValidateRange(1, 31)]
        [int]$DayOfMonth = 15,

        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$DayOfWeek = 'Saturday',

        [string]$Time = "02:00",

        [ValidateSet('Full', 'Quick', 'SyncOnly')]
        [string]$MaintenanceProfile = 'Full',

        [string]$RunAsUser = "dod_admin",

        [securestring]$UserPassword
    )

    $result = @{
        Success = $false
        TaskName = $TaskName
        Message = ""
    }

    # Auto-detect script path if not provided
    # Search multiple deployment layouts for flexibility
    if (-not $ScriptPath) {
        $modulePath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $possiblePaths = @(
            # Standard deployment: C:\WSUS with Scripts subfolder
            "C:\WSUS\Scripts\Invoke-WsusMonthlyMaintenance.ps1",
            # Flat deployment: C:\WSUS\Scripts as root
            "C:\WSUS\Scripts\Scripts\Invoke-WsusMonthlyMaintenance.ps1",
            # Parent folder of Modules
            (Join-Path (Split-Path $modulePath -Parent) "Scripts\Invoke-WsusMonthlyMaintenance.ps1"),
            # Same level as Modules folder (Scripts folder sibling)
            (Join-Path (Split-Path $modulePath -Parent) "Scripts\Scripts\Invoke-WsusMonthlyMaintenance.ps1"),
            # Grandparent folder
            (Join-Path (Split-Path (Split-Path $modulePath -Parent) -Parent) "Scripts\Invoke-WsusMonthlyMaintenance.ps1")
        )

        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $ScriptPath = $path
                break
            }
        }
    }

    # === INPUT VALIDATION ===

    # Check admin privileges
    if (-not (Test-IsAdministrator)) {
        $result.Message = "Administrator privileges required to create scheduled tasks"
        return $result
    }

    # Validate script path
    if (-not $ScriptPath -or -not (Test-Path $ScriptPath)) {
        $result.Message = "Maintenance script not found. Please specify -ScriptPath"
        return $result
    }

    # Validate time format
    if (-not (Test-ValidTimeFormat -Time $Time)) {
        $result.Message = "Invalid time format '$Time'. Use HH:mm format (e.g., 01:00, 14:30)"
        return $result
    }

    # Validate user format
    if (-not (Test-ValidUserFormat -User $RunAsUser)) {
        $result.Message = "Invalid user format '$RunAsUser'. Use .\username, DOMAIN\username, or username@domain"
        return $result
    }

    # Auto-prefix local usernames with .\ for Register-ScheduledTask compatibility
    # Local accounts need .\username format when running "whether user is logged on or not"
    if ($RunAsUser -notmatch '\\' -and $RunAsUser -notmatch '@' -and $RunAsUser -ne "SYSTEM") {
        $RunAsUser = ".\$RunAsUser"
        Write-Host "[i] Using local account format: $RunAsUser" -ForegroundColor Cyan
    }

    $useServiceAccount = $RunAsUser -eq "SYSTEM"

    if (-not $useServiceAccount) {
        # Prompt for password if not provided
        if (-not $UserPassword) {
            Write-Host "Enter password for $RunAsUser to run scheduled task:" -ForegroundColor Yellow
            $UserPassword = Read-Host -AsSecureString "Password"
        }

        # Validate password was provided
        $PlainPassword = ConvertFrom-SecureStringToPlainText -SecureString $UserPassword
        if ([string]::IsNullOrEmpty($PlainPassword)) {
            $result.Message = "Password is required for scheduled task creation"
            return $result
        }
    }

    try {
        # Build the action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Unattended -Profile $MaintenanceProfile"

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

        # Build settings - RunOnlyIfNetworkAvailable removed to allow offline runs
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Hours 4)

        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            # Remove existing task first (easier than updating with credentials)
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
        }

        if ($useServiceAccount) {
            Register-ScheduledTask -TaskName $TaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -User "SYSTEM" `
                -LogonType ServiceAccount `
                -RunLevel Highest | Out-Null
        } else {
            # Create task with user credentials - runs whether user is logged on or not
            Register-ScheduledTask -TaskName $TaskName `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -User $RunAsUser `
                -Password $PlainPassword `
                -RunLevel Highest | Out-Null
        }

        $runAsMessage = if ($useServiceAccount) { "SYSTEM" } else { $RunAsUser }
        $result.Message = "Scheduled task '$TaskName' created to run as $runAsMessage (no login required)"
        $result.Success = $true

    } catch {
        $result.Message = "Failed to create scheduled task: $($_.Exception.Message)"
    } finally {
        # Clear password from memory
        $PlainPassword = $null
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
        $null = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
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
                $result = New-WsusMaintenanceTask -Schedule Monthly -DayOfMonth 15 -Time "01:00" -MaintenanceProfile Full -ScriptPath $ScriptPath
                Write-Host ""
                if ($result.Success) {
                    Write-Host $result.Message -ForegroundColor Green
                } else {
                    Write-Host $result.Message -ForegroundColor Red
                }
                Read-Host "Press Enter to continue"
            }
            '2' {
                $result = New-WsusMaintenanceTask -Schedule Weekly -DayOfWeek Saturday -Time "01:00" -MaintenanceProfile Full -ScriptPath $ScriptPath
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
                    MaintenanceProfile = $profileChoice
                    ScriptPath = $ScriptPath
                }

                if ($scheduleChoice -eq 'Monthly') {
                    $dayInput = Read-Host "Day of month (1-31, default 15)"
                    if ($dayInput -match '^\d+$' -and [int]$dayInput -ge 1 -and [int]$dayInput -le 31) {
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
