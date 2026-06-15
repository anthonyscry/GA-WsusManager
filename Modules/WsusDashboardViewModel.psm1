<#
===============================================================================
Module: WsusDashboardViewModel.psm1
Author: GA-WsusManager
Version: 1.0.0
Date: 2026-06-13
===============================================================================

.SYNOPSIS
    Dashboard view-model construction for the WSUS Manager GUI.

.DESCRIPTION
    Transforms raw dashboard data (services, database, disk, health) into a
    typed Wsus.DashboardViewModel object for WPF data-binding. Extracted from
    WsusGuiShell.psm1 so the view-model can be tested independently.
#>

function New-WsusDashboardViewModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$WsusInstalled,
        [Parameter(Mandatory)][string]$ServerMode,
        [bool]$ServerModeOverridden = $false,
        [object]$DashboardData = $null,
        [object]$Health = $null,
        [string]$ContentPath = '',
        [string]$SqlInstance = '',
        [string]$ExportRoot = '',
        [string]$LogPath = ''
    )

    $servicesRunning = if ($DashboardData -and $DashboardData.Services -and $null -ne $DashboardData.Services.Running) { [int]$DashboardData.Services.Running } else { 0 }
    $serviceNames = if ($DashboardData -and $DashboardData.Services -and $DashboardData.Services.Names) { @($DashboardData.Services.Names) } else { @() }
    $databaseSize = if ($DashboardData -and $null -ne $DashboardData.DatabaseSizeGB) { [double]$DashboardData.DatabaseSizeGB } else { -1 }
    $diskFree = if ($DashboardData -and $null -ne $DashboardData.DiskFreeGB) { [double]$DashboardData.DiskFreeGB } else { 0 }
    $taskStatus = if ($DashboardData -and $DashboardData.TaskStatus) { [string]$DashboardData.TaskStatus } else { 'Not Set' }

    $card1 = if (-not $WsusInstalled) {
        @{ Value = 'Not Installed'; Sub = 'Use Install WSUS'; Status = 'Fail' }
    } else {
        @{ Value = $(if ($servicesRunning -eq 3) { 'All Running' } else { "$servicesRunning/3" }); Sub = $(if ($serviceNames.Count -gt 0) { $serviceNames -join ', ' } else { 'Stopped' }); Status = $(if ($servicesRunning -eq 3) { 'Pass' } elseif ($servicesRunning -gt 0) { 'Warn' } else { 'Fail' }) }
    }

    $card2 = if (-not $WsusInstalled) {
        @{ Value = 'N/A'; Sub = 'WSUS not installed'; Status = 'Skip' }
    } elseif ($databaseSize -ge 0) {
        @{ Value = "$databaseSize / 10 GB"; Sub = $(if ($databaseSize -ge 9) { 'Critical!' } elseif ($databaseSize -ge 7) { 'Warning' } else { 'Healthy' }); Status = $(if ($databaseSize -ge 9) { 'Fail' } elseif ($databaseSize -ge 7) { 'Warn' } else { 'Pass' }) }
    } else {
        @{ Value = 'Offline'; Sub = 'SQL stopped'; Status = 'Warn' }
    }

    $card3 = @{ Value = "$diskFree GB"; Sub = $(if ($diskFree -lt 10) { 'Critical!' } elseif ($diskFree -lt 50) { 'Low' } else { 'OK' }); Status = $(if ($diskFree -lt 10) { 'Fail' } elseif ($diskFree -lt 50) { 'Warn' } else { 'Pass' }) }
    $card4 = if (-not $WsusInstalled) { @{ Value = 'N/A'; Status = 'Skip' } } else { @{ Value = $taskStatus; Status = $(if ($taskStatus -eq 'Ready') { 'Pass' } else { 'Warn' }) } }

    [pscustomobject]@{
        PSTypeName = 'Wsus.DashboardViewModel'
        ServerMode = [pscustomobject]@{
            Label = $(if ($ServerModeOverridden) { "$ServerMode (Manual)" } else { $ServerMode })
            Online = ($ServerMode -eq 'Online')
        }
        Cards = [pscustomobject]@{
            Services = $card1
            Database = $card2
            Disk = $card3
            Task = $card4
        }
        Health = if ($Health) {
            [pscustomobject]@{
                Score = $Health.Score
                Grade = $Health.Grade
                Available = ($Health.Score -ge 0)
            }
        } else {
            [pscustomobject]@{ Score = -1; Grade = 'Unknown'; Available = $false }
        }
        Configuration = [pscustomobject]@{
            ContentPath = $ContentPath
            SqlInstance = $SqlInstance
            ExportRoot = $ExportRoot
            LogPath = $LogPath
        }
    }
}

Export-ModuleMember -Function @(
    'New-WsusDashboardViewModel'
)
