#Requires -Version 5.1
<#
.SYNOPSIS
    GUI shell helpers for WSUS Manager.
.DESCRIPTION
    Concentrates GUI-facing dashboard view shaping and UI state helpers so the WPF
    script consumes a smaller interface and does not leak implementation details
    across event handlers.
#>



function New-WsusGuiStatusText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Running','Completed','Failed','TimedOut','Cancelled','Error')]
        [string]$State,

        [string]$Title = '',

        [datetime]$Timestamp = (Get-Date)
    )

    $timeText = $Timestamp.ToString('HH:mm:ss')
    switch ($State) {
        'Running'   { if ([string]::IsNullOrWhiteSpace($Title)) { 'Running' } else { "Running: $Title" } }
        'Completed' { "Completed: $Title  [$timeText]" }
        'Failed'    { "Failed: $Title  [$timeText]" }
        'TimedOut'  { if ([string]::IsNullOrWhiteSpace($Title)) { 'Timed out' } else { "Timed out: $Title" } }
        'Cancelled' { 'Cancelled' }
        'Error'     { 'Error' }
    }
}

function Format-WsusGuiLogLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Message = '',

        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info',

        [datetime]$Timestamp = (Get-Date)
    )

    $prefix = switch ($Level) {
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        default   { '[*]' }
    }

    '[{0}] {1} {2}' -f $Timestamp.ToString('HH:mm:ss'), $prefix, $Message
}

function Set-WsusGuiStatusText {
    [CmdletBinding()]
    param(
        [hashtable]$Controls,
        [string]$Text,
        [switch]$UseDashPrefix
    )

    if ($null -eq $Controls) { return }
    $label = $Controls['StatusLabel']
    if ($null -eq $label) { return }

    $statusText = if ($UseDashPrefix) { " - $Text" } else { $Text }
    $setAction = {
        if ($null -ne $label) {
            $label.Text = $statusText
        }
    }.GetNewClosure()

    try {
        if ($label.PSObject.Properties['Dispatcher'] -and $null -ne $label.Dispatcher) {
            $label.Dispatcher.Invoke([Action]$setAction)
        } else {
            & $setAction
        }
    } catch {
        & $setAction
    }
}

function Write-WsusGuiLogOutput {
    [CmdletBinding()]
    param(
        [hashtable]$Controls,
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info'
    )

    if ($null -eq $Controls) { return }
    $logOutput = $Controls['LogOutput']
    if ($null -eq $logOutput) { return }

    $prefix = switch ($Level) {
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        default   { '[*]' }
    }
    $line = ('[{0}] {1} {2}' -f (Get-Date).ToString('HH:mm:ss'), $prefix, $Message) + "`r`n"
    $appendAction = {
        if ($null -ne $logOutput) {
            if ($logOutput.PSObject.Methods['AppendText']) {
                $logOutput.AppendText($line)
            } else {
                $logOutput.Text = [string]$logOutput.Text + $line
            }
            if ($logOutput.PSObject.Methods['ScrollToEnd']) {
                $logOutput.ScrollToEnd()
            }
        }
    }.GetNewClosure()

    try {
        if ($logOutput.PSObject.Properties['Dispatcher'] -and $null -ne $logOutput.Dispatcher) {
            $logOutput.Dispatcher.Invoke([Action]$appendAction)
        } else {
            & $appendAction
        }
    } catch {
        & $appendAction
    }
}

function Set-WsusGuiControlEnabled {
    [CmdletBinding()]
    param(
        [hashtable]$Controls,
        [string[]]$Names = @(),
        [bool]$Enabled
    )

    if ($null -eq $Controls) { return }
    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $control = $Controls[$name]
        if ($null -eq $control) { continue }
        $control.IsEnabled = $Enabled
        $control.Opacity = if ($Enabled) { 1.0 } else { 0.5 }
    }
}

function Set-WsusGuiOperationUiState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][ValidateSet('Running','Completed','Failed','TimedOut','Cancelled','Error')][string]$State,
        [string]$Title = ''
    )

    $controls = $Context.Controls
    if ($null -eq $controls) { return }

    $applyState = {
        if ($State -eq 'Running') {
            $logPanel = $controls['LogPanel']
            if ($null -ne $logPanel) { $logPanel.Height = 250 }
            $btnToggle = $controls['BtnToggleLog']
            if ($null -ne $btnToggle) { $btnToggle.Content = 'Hide' }
        }

        $timeText = (Get-Date).ToString('HH:mm:ss')
        $status = switch ($State) {
            'Running'   { if ([string]::IsNullOrWhiteSpace($Title)) { 'Running' } else { "Running: $Title" } }
            'Completed' { "Completed: $Title  [$timeText]" }
            'Failed'    { "Failed: $Title  [$timeText]" }
            'TimedOut'  { if ([string]::IsNullOrWhiteSpace($Title)) { 'Timed out' } else { "Timed out: $Title" } }
            'Cancelled' { 'Cancelled' }
            'Error'     { 'Error' }
        }
        $label = $controls['StatusLabel']
        if ($null -ne $label) { $label.Text = $status }

        $cancel = $controls['CancelButton']
        if ($null -eq $cancel) { $cancel = $controls['BtnCancelOp'] }
        if ($null -ne $cancel) {
            $cancel.Visibility = if ($State -eq 'Running') { 'Visible' } else { 'Collapsed' }
        }

        $enabled = ($State -ne 'Running')
        foreach ($controlName in @($Context.OperationButtons) + @($Context.OperationInputs)) {
            if ([string]::IsNullOrWhiteSpace($controlName)) { continue }
            $control = $controls[$controlName]
            if ($null -eq $control) { continue }
            $control.IsEnabled = $enabled
            $control.Opacity = if ($enabled) { 1.0 } else { 0.5 }
        }

        if ($enabled -and $Context.ContainsKey('UpdateButtonState') -and $null -ne $Context.UpdateButtonState) {
            try { & $Context.UpdateButtonState } catch { Write-Verbose $_.Exception.Message }
        }
    }.GetNewClosure()

    try {
        if ($Context.Window -and $Context.Window.PSObject.Properties['Dispatcher'] -and $null -ne $Context.Window.Dispatcher) {
            $Context.Window.Dispatcher.Invoke([Action]$applyState)
        } else {
            & $applyState
        }
    } catch {
        & $applyState
    }
}

function Test-WsusGuiPopupSuppressed {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'WSUS Manager',
        [object]$Button = $null,
        [object]$Icon = $null,
        [int]$SuppressDuplicateSeconds = 0,
        [hashtable]$PopupHistory = @{},
        [datetime]$Now = (Get-Date)
    )

    if ($SuppressDuplicateSeconds -le 0) { return $false }
    if ($null -eq $PopupHistory) { return $false }
    if ($PopupHistory.Count -gt 100) { $PopupHistory.Clear() }

    $popupKey = "$Title|$Button|$Icon|$Message"
    if ($PopupHistory.ContainsKey($popupKey)) {
        $elapsed = ($Now - [datetime]$PopupHistory[$popupKey]).TotalSeconds
        if ($elapsed -lt $SuppressDuplicateSeconds) { return $true }
    }

    $PopupHistory[$popupKey] = $Now
    return $false
}

function Add-WsusGuiPopupEvent {
    [CmdletBinding()]
    param(
        [object]$EventList,
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'WSUS Manager',
        [object]$Button = $null,
        [object]$Icon = $null,
        [datetime]$Timestamp = (Get-Date)
    )

    if ($null -eq $EventList) { return }

    $event = [pscustomobject]@{
        timestamp = $Timestamp.ToString('o')
        title = $Title
        button = if ($null -ne $Button) { $Button.ToString() } else { '' }
        icon = if ($null -ne $Icon) { $Icon.ToString() } else { '' }
        message = $Message
    }

    if ($EventList.PSObject.Methods['Add']) {
        $EventList.Add($event) | Out-Null
    }
}



function New-WsusGuiLifecycleLogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Starting','StartupCompleted','RunningForm','ApplicationClosed')]
        [string]$Event,

        [string]$AppVersion = '',

        [datetime]$StartedAt = (Get-Date),

        [datetime]$CompletedAt = (Get-Date)
    )

    switch ($Event) {
        'Starting' {
            if ([string]::IsNullOrWhiteSpace($AppVersion)) { '=== Starting ===' } else { "=== Starting v$AppVersion ===" }
        }
        'StartupCompleted' {
            $duration = ($CompletedAt - $StartedAt).TotalMilliseconds
            'Startup completed in {0}ms' -f [math]::Round($duration, 0)
        }
        'RunningForm' { 'Running WPF form' }
        'ApplicationClosed' { '=== Application closed ===' }
    }
}


# New-WsusDashboardViewModel moved to Modules/WsusDashboardViewModel.psm1

Export-ModuleMember -Function @(
    'New-WsusGuiStatusText',
    'Format-WsusGuiLogLine',
    'Set-WsusGuiStatusText',
    'Write-WsusGuiLogOutput',
    'Set-WsusGuiControlEnabled',
    'Set-WsusGuiOperationUiState',
    'Test-WsusGuiPopupSuppressed',
    'Add-WsusGuiPopupEvent',
    'New-WsusGuiLifecycleLogEntry'
)
