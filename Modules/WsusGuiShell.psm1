#Requires -Version 5.1
<#
.SYNOPSIS
    GUI shell helpers for WSUS Manager.
.DESCRIPTION
    Concentrates GUI-facing dashboard view shaping and short-lived secret
    environment planning so the WPF script consumes a smaller interface and does
    not leak implementation details across event handlers.
#>

function New-WsusSecretEnvironment {
    [CmdletBinding()]
    param(
        [hashtable]$Values = @{}
    )

    $environment = @{}
    $cleanupKeys = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Values.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Key)) { continue }
        $environment[[string]$entry.Key] = [string]$entry.Value
        $null = $cleanupKeys.Add([string]$entry.Key)
    }

    [pscustomobject]@{
        PSTypeName = 'Wsus.SecretEnvironment'
        Environment = $environment
        CleanupKeys = @($cleanupKeys)
    }
}

function Clear-WsusSecretEnvironment {
    [CmdletBinding()]
    param(
        [string[]]$Keys = @()
    )

    foreach ($key in @($Keys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Remove-Item "Env:\$key" -ErrorAction SilentlyContinue
    }
}

function ConvertTo-WsusSecureString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)

    $secure = New-Object Security.SecureString
    foreach ($char in $Value.ToCharArray()) {
        $secure.AppendChar($char)
    }
    $secure.MakeReadOnly()
    $secure
}


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

function Get-WsusGuiProbePopupResult {
    [CmdletBinding()]
    param([object]$Button = $null)

    $buttonText = if ($null -ne $Button) { $Button.ToString() } else { 'OK' }
    if ($buttonText -eq 'YesNo' -or $buttonText -eq 'YesNoCancel') { return 'No' }
    if ($buttonText -eq 'OKCancel') { return 'Cancel' }
    return 'OK'
}

function New-WsusGuiStartupProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason = '',
        [string]$FatalError = '',
        [int]$StartupProbeSeconds = 0,
        [string]$ResultPath = '',
        [object[]]$PopupEvents = @(),
        [datetime]$Timestamp = (Get-Date)
    )

    $errorPopups = @($PopupEvents | Where-Object { $_.icon -eq 'Error' -or $_.Icon -eq 'Error' })
    [pscustomobject]@{
        PSTypeName = 'Wsus.GuiStartupProbeResult'
        status = $Status
        reason = $Reason
        fatalError = $FatalError
        startupProbeSeconds = $StartupProbeSeconds
        resultPath = $ResultPath
        totalPopupCount = @($PopupEvents).Count
        errorPopupCount = $errorPopups.Count
        popupEvents = @($PopupEvents)
        timestamp = $Timestamp.ToString('o')
    }
}

function Write-WsusGuiStartupProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$ResultPath
    )

    $resultDir = Split-Path -Parent $ResultPath
    if (-not [string]::IsNullOrWhiteSpace($resultDir) -and -not (Test-Path $resultDir)) {
        New-Item -Path $resultDir -ItemType Directory -Force | Out-Null
    }

    $Result | ConvertTo-Json -Depth 6 | Set-Content -Path $ResultPath -Encoding UTF8
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
    'New-WsusSecretEnvironment',
    'Clear-WsusSecretEnvironment',
    'ConvertTo-WsusSecureString',
    'New-WsusGuiStatusText',
    'Format-WsusGuiLogLine',
    'Set-WsusGuiStatusText',
    'Write-WsusGuiLogOutput',
    'Set-WsusGuiControlEnabled',
    'Set-WsusGuiOperationUiState',
    'Test-WsusGuiPopupSuppressed',
    'Add-WsusGuiPopupEvent',
    'Get-WsusGuiProbePopupResult',
    'New-WsusGuiStartupProbeResult',
    'Write-WsusGuiStartupProbeResult',
    'New-WsusGuiLifecycleLogEntry',
    'New-WsusGuiOperationCompletion',
    'Invoke-WsusGuiOperationCompletion',
    'New-WsusDashboardViewModel'
)
