#Requires -Version 5.1
<#
.SYNOPSIS
    GUI operation completion helpers for WSUS Manager.
.DESCRIPTION
    Builds completion details and invokes optional GUI callbacks after a child
    operation finishes.
#>

function New-WsusGuiOperationCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [bool]$Success,
        [datetime]$StartedAt = (Get-Date),
        [string]$ReportPath = '',
        [string[]]$CleanupKeys = @(),
        [datetime]$CompletedAt = (Get-Date)
    )

    $duration = $CompletedAt - $StartedAt
    $resultText = if ($Success) { 'Pass' } else { 'Fail' }
    $reportAvailable = -not [string]::IsNullOrWhiteSpace($ReportPath) -and (Test-Path -LiteralPath $ReportPath -PathType Leaf)

    [pscustomobject]@{
        PSTypeName = 'Wsus.GuiOperationCompletion'
        Title = $Title
        Success = $Success
        Duration = $duration
        ResultText = $resultText
        ReportPath = $ReportPath
        ReportAvailable = $reportAvailable
        ReportMessage = if ($reportAvailable) { "Diagnostic report saved to: $ReportPath" } else { '' }
        NotificationTitle = "WSUS Manager - $Title Complete"
        NotificationMessage = "$resultText in $([int]$duration.TotalMinutes)m $($duration.Seconds)s"
        HistorySummary = 'Completed via GUI operation runner'
        CleanupKeys = @($CleanupKeys)
    }
}

function Invoke-WsusGuiOperationCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Completion,
        [scriptblock]$LogAction = $null,
        [scriptblock]$NotificationAction = $null,
        [scriptblock]$HistoryAction = $null,
        [scriptblock]$CleanupAction = $null,
        [bool]$NotificationsEnabled = $true,
        [bool]$HistoryEnabled = $true
    )

    if ($Completion.ReportAvailable -and $LogAction) {
        & $LogAction $Completion.ReportMessage 'Info'
    }

    if ($NotificationsEnabled -and $NotificationAction) {
        & $NotificationAction $Completion.NotificationTitle $Completion.NotificationMessage $Completion.ResultText
    }

    if ($HistoryEnabled -and $HistoryAction) {
        & $HistoryAction $Completion.Title $Completion.Duration $Completion.ResultText $Completion.HistorySummary
    }

    if (@($Completion.CleanupKeys).Count -gt 0 -and $CleanupAction) {
        & $CleanupAction @($Completion.CleanupKeys)
    }
}

Export-ModuleMember -Function @(
    'New-WsusGuiOperationCompletion',
    'Invoke-WsusGuiOperationCompletion'
)
