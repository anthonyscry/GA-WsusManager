#Requires -Version 5.1
<#
.SYNOPSIS
    Operation runner module for the WSUS Manager GUI.
.DESCRIPTION
    Extracts the shared lifecycle (process creation, button state, event wiring,
    timeout watchdog, cleanup) from WsusManagementGui.ps1, keeping mode-specific
    display strategies (Terminal / Embedded) as internal implementation details.
.AUTHOR
    Tony Tran, ISSO, GA-ASI
.VERSION
    1.0.0
.DATE
    2025
#>

#region Internal state

$script:CurrentProcess   = $null
$script:WatchdogTimer    = $null
$script:KeystrokeTimer   = $null
$script:StdinFlushTimer  = $null
$script:OutputEventJob   = $null
$script:ErrorEventJob    = $null
$script:ExitEventJob     = $null

#endregion

#region Private helpers

function Disable-RunnerButtons {
    param([hashtable]$Context)
    foreach ($name in $Context.OperationButtons) {
        $btn = $Context.Controls[$name]
        if ($null -ne $btn) {
            $btn.IsEnabled = $false
            $btn.Opacity   = 0.5
        }
    }
    foreach ($name in $Context.OperationInputs) {
        $inp = $Context.Controls[$name]
        if ($null -ne $inp) {
            $inp.IsEnabled = $false
            $inp.Opacity   = 0.5
        }
    }
}

function Enable-RunnerButtons {
    param([hashtable]$Context)
    foreach ($name in $Context.OperationButtons) {
        $btn = $Context.Controls[$name]
        if ($null -ne $btn) {
            $btn.IsEnabled = $true
            $btn.Opacity   = 1.0
        }
    }
    foreach ($name in $Context.OperationInputs) {
        $inp = $Context.Controls[$name]
        if ($null -ne $inp) {
            $inp.IsEnabled = $true
            $inp.Opacity   = 1.0
        }
    }
}

function Stop-RunnerTimers {
    foreach ($timerVar in @('WatchdogTimer','KeystrokeTimer','StdinFlushTimer')) {
        $timer = Get-Variable -Name $timerVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $timer) {
            try { $timer.Stop() } catch { }
            Set-Variable -Name $timerVar -Value $null -Scope Script
        }
    }
}

function Unregister-RunnerEvents {
    foreach ($jobVar in @('OutputEventJob','ErrorEventJob','ExitEventJob')) {
        $job = Get-Variable -Name $jobVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $job) {
            try { Unregister-Event -SourceIdentifier $job.Name -ErrorAction SilentlyContinue } catch { }
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
            Set-Variable -Name $jobVar -Value $null -Scope Script
        }
    }
}

function Format-LogLine {
    param([string]$Line)
    $level = if ($Line -match 'ERROR|FAIL') { 'Error' }
             elseif ($Line -match 'WARN')   { 'Warning' }
             elseif ($Line -match 'OK|Success|\[PASS\]|\[\+\]') { 'Success' }
             else { 'Info' }
    $prefix = switch ($level) {
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
        default   { '[*]' }
    }
    $ts = (Get-Date).ToString('HH:mm:ss')
    return "$ts $prefix $Line"
}

#endregion

#region Public API

function Find-WsusScript {
<#
.SYNOPSIS
    Locates a WSUS CLI script by searching common paths relative to ScriptRoot.
.DESCRIPTION
    Checks the following locations in order and returns the first match:
      1. $ScriptRoot\$ScriptName
      2. $ScriptRoot\Scripts\$ScriptName
    Returns $null if the script is not found in any location.
.PARAMETER ScriptName
    Filename of the script (e.g. "Invoke-WsusManagement.ps1").
.PARAMETER ScriptRoot
    Base directory to search from. Typically the directory containing the EXE or GUI script.
.EXAMPLE
    $path = Find-WsusScript -ScriptName "Invoke-WsusManagement.ps1" -ScriptRoot $PSScriptRoot
    if ($null -eq $path) { Write-Error "Script not found" }
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    $candidates = @(
        (Join-Path $ScriptRoot $ScriptName),
        (Join-Path $ScriptRoot "Scripts\$ScriptName")
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }
    return $null
}

function Complete-WsusOperation {
<#
.SYNOPSIS
    Internal cleanup called when a WSUS operation process exits.
.DESCRIPTION
    Intended to be called from the process exit event handler or the watchdog timer.
    Stops all runner-owned timers, unregisters events, resets GUI state (buttons,
    status bar, cancel button), and optionally invokes a caller-supplied completion
    callback.
.PARAMETER Context
    The same hashtable that was passed to Start-WsusOperation.
.PARAMETER Title
    Display name for the operation (used in the completion status message).
.PARAMETER Success
    Whether the operation completed successfully. Defaults to $true.
.PARAMETER OnComplete
    Optional scriptblock invoked after GUI state is restored. Receives one
    [bool] argument indicating success.
.EXAMPLE
    Complete-WsusOperation -Context $ctx -Title "Health Check" -Success $true
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Title,

        [bool]$Success = $true,

        [scriptblock]$OnComplete = $null
    )

    Stop-RunnerTimers
    Unregister-RunnerEvents

    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $statusMsg = if ($Success) { "Completed: $Title  [$timestamp]" }
                 else          { "Failed: $Title  [$timestamp]" }

    $Context.Window.Dispatcher.Invoke([Action]{
        # Status bar
        $lbl = $Context.Controls['StatusLabel']
        if ($null -ne $lbl) { $lbl.Text = $statusMsg }

        # Hide cancel button
        $cancel = $Context.Controls['CancelButton']
        if ($null -ne $cancel) { $cancel.Visibility = 'Collapsed' }

        # Re-enable operation buttons (inlined to remain accessible via DynamicInvoke)
        foreach ($bName in $Context.OperationButtons) {
            $btn = $Context.Controls[$bName]
            if ($null -ne $btn) { $btn.IsEnabled = $true; $btn.Opacity = 1.0 }
        }
        foreach ($iName in $Context.OperationInputs) {
            $inp = $Context.Controls[$iName]
            if ($null -ne $inp) { $inp.IsEnabled = $true; $inp.Opacity = 1.0 }
        }

        # Honour WSUS installation state if helper exists in context
        if ($Context.ContainsKey('UpdateButtonState') -and $null -ne $Context.UpdateButtonState) {
            try { & $Context.UpdateButtonState } catch { }
        }
    }.GetNewClosure())

    # Reset flag on the GUI script scope via the supplied setter, or directly
    if ($Context.ContainsKey('SetOperationRunning') -and $null -ne $Context.SetOperationRunning) {
        try { & $Context.SetOperationRunning $false } catch { }
    }

    $script:CurrentProcess = $null

    if ($null -ne $OnComplete) {
        try { & $OnComplete $Success } catch { }
    }
}

function Stop-WsusOperation {
<#
.SYNOPSIS
    Cancels the currently running WSUS operation.
.DESCRIPTION
    Kills the supplied process (and its child tree where possible), then stops
    all runner-owned timers.  Safe to call when no process is running.
.PARAMETER Process
    The System.Diagnostics.Process object to terminate.  Passing $null is safe.
.EXAMPLE
    Stop-WsusOperation -Process $script:CurrentProcess
#>
    [CmdletBinding()]
    param(
        [System.Diagnostics.Process]$Process
    )

    Stop-RunnerTimers

    if ($null -eq $Process) { return }

    try {
        if (-not $Process.HasExited) {
            # Best-effort: kill child processes first (Windows only)
            try {
                $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($Process.Id)" -ErrorAction SilentlyContinue
                foreach ($child in $children) {
                    try { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
                }
            } catch { }

            $Process.Kill()
        }
    } catch { }
}

function Start-WsusOperation {
<#
.SYNOPSIS
    Starts a WSUS CLI operation as a child process with full lifecycle management.
.DESCRIPTION
    Runner owns: process creation, button state, event subscriptions, timeout
    watchdog, and cleanup.  Output display is delegated to the selected mode:

      Embedded  – captures stdout/stderr into the GUI log panel TextBox.
      Terminal  – launches a visible PowerShell console window.

    GUI state is communicated via the Context hashtable so that the module has
    no hard dependency on script-scope variables in the GUI.
.PARAMETER Command
    The PowerShell command string to execute (passed to powershell.exe -Command).
.PARAMETER Title
    Human-readable name shown in the status bar and log panel header.
.PARAMETER Context
    Hashtable containing GUI state references. Expected keys:
      Window           [System.Windows.Window]
      Controls         [hashtable] – named controls dictionary
      OperationButtons [string[]]  – button names to disable during the operation
      OperationInputs  [string[]]  – input field names to disable
      LogOutput        [System.Windows.Controls.TextBox] – log panel (Embedded mode)
      StatusLabel      [System.Windows.Controls.TextBlock]
      CancelButton     [System.Windows.Controls.Button]
      ScriptRoot       [string] – working directory for the child process
      SetOperationRunning [scriptblock] – called with $true/$false to set the flag
      UpdateButtonState   [scriptblock] – (optional) called after completion
.PARAMETER Mode
    "Embedded" (default) captures output to the GUI log panel.
    "Terminal" opens a visible PowerShell console window.
.PARAMETER TimeoutMinutes
    Kills the process after this many minutes. Default 30. Use 0 to disable.
.PARAMETER OnComplete
    Optional scriptblock invoked when the operation finishes.
    Receives one [bool] argument: $true = success, $false = failure/timeout.
.EXAMPLE
    $ctx = @{ Window = $window; Controls = $controls; OperationButtons = $script:OperationButtons;
              OperationInputs = $script:OperationInputs; LogOutput = $controls.LogOutput;
              StatusLabel = $controls.StatusLabel; CancelButton = $controls.BtnCancel;
              ScriptRoot = $PSScriptRoot; SetOperationRunning = { param($v) $script:OperationRunning = $v } }
    Start-WsusOperation -Command $cmd -Title "Health Check" -Context $ctx
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [hashtable]$Context,

        [ValidateSet('Embedded','Terminal')]
        [string]$Mode = 'Embedded',

        [int]$TimeoutMinutes = 30,

        [scriptblock]$OnComplete = $null
    )

    #region Pre-flight UI updates (must run on UI thread)
    $Context.Window.Dispatcher.Invoke([Action]{
        # Expand log panel
        $logPanel = $Context.Controls['LogPanel']
        if ($null -ne $logPanel) { $logPanel.Height = 250 }
        $btnToggle = $Context.Controls['BtnToggleLog']
        if ($null -ne $btnToggle) { $btnToggle.Content = 'Hide' }

        # Status bar
        $lbl = $Context.Controls['StatusLabel']
        if ($null -ne $lbl) { $lbl.Text = "Running: $Title" }

        # Show cancel button
        $cancel = $Context.Controls['CancelButton']
        if ($null -ne $cancel) { $cancel.Visibility = 'Visible' }

        # Disable operation buttons (inlined to remain accessible via DynamicInvoke)
        foreach ($bName in $Context.OperationButtons) {
            $btn = $Context.Controls[$bName]
            if ($null -ne $btn) { $btn.IsEnabled = $false; $btn.Opacity = 0.5 }
        }
        foreach ($iName in $Context.OperationInputs) {
            $inp = $Context.Controls[$iName]
            if ($null -ne $inp) { $inp.IsEnabled = $false; $inp.Opacity = 0.5 }
        }
    }.GetNewClosure())
    #endregion

    # Set the running flag via the supplied setter
    if ($Context.ContainsKey('SetOperationRunning') -and $null -ne $Context.SetOperationRunning) {
        try { & $Context.SetOperationRunning $true } catch { }
    }

    #region Build ProcessStartInfo
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'

    if (-not [string]::IsNullOrWhiteSpace($Context.ScriptRoot)) {
        $psi.WorkingDirectory = $Context.ScriptRoot
    }

    switch ($Mode) {
        'Terminal' {
            $psi.UseShellExecute  = $true
            $psi.CreateNoWindow   = $false
            $psi.Arguments        = "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`""
        }
        'Embedded' {
            $psi.UseShellExecute         = $false
            $psi.RedirectStandardOutput  = $true
            $psi.RedirectStandardError   = $true
            $psi.RedirectStandardInput   = $true
            $psi.CreateNoWindow          = $true
            $psi.Arguments               = "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`""
        }
    }
    #endregion

    #region Create and start process
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo          = $psi
    $proc.EnableRaisingEvents = $true

    $script:CurrentProcess = $proc

    try {
        $proc.Start() | Out-Null
    } catch {
        Complete-WsusOperation -Context $Context -Title $Title -Success $false -OnComplete $OnComplete
        throw
    }
    #endregion

    #region Wire exit event
    $exitData = @{
        Window     = $Context.Window
        Context    = $Context
        Title      = $Title
        OnComplete = $OnComplete
    }

    $exitHandler = {
        $d = $Event.MessageData
        $exitCode = try { $Event.Sender.ExitCode } catch { -1 }
        $success  = ($exitCode -eq 0)
        Complete-WsusOperation -Context $d.Context -Title $d.Title -Success $success -OnComplete $d.OnComplete
    }

    $script:ExitEventJob = Register-ObjectEvent `
        -InputObject $proc `
        -EventName   Exited `
        -Action      $exitHandler `
        -MessageData $exitData
    #endregion

    #region Mode-specific wiring
    switch ($Mode) {
        'Terminal' {
            # Keystroke timer – sends Enter every 2 s to flush PowerShell output buffer
            $kTimer = New-Object System.Windows.Threading.DispatcherTimer
            $kTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
            $kTimerData = @{ Proc = $proc }
            $kTimer.Add_Tick({
                $p = $kTimerData.Proc
                if ($null -ne $p -and -not $p.HasExited) {
                    # Best-effort stdin newline; ignore errors
                    try { $p.StandardInput.WriteLine('') } catch { }
                }
            }.GetNewClosure())
            $kTimer.Start()
            $script:KeystrokeTimer = $kTimer
        }

        'Embedded' {
            # Log accumulator (StringBuilder avoids O(n²) string concat)
            $logBuffer = New-Object System.Text.StringBuilder

            # Shared output/error handler data
            $handlerData = @{
                Window     = $Context.Window
                LogOutput  = $Context.Controls['LogOutput']
                LogBuffer  = $logBuffer
                RecentLines = [System.Collections.Generic.Dictionary[string,long]]::new()
            }

            $outputHandler = {
                $line = $Event.SourceEventArgs.Data
                if ([string]::IsNullOrWhiteSpace($line)) { return }

                # Deduplication within a 2-second window
                $hash  = $line.Trim().GetHashCode().ToString()
                $now   = [DateTime]::UtcNow.Ticks
                $d     = $Event.MessageData
                $last  = $null
                if ($d.RecentLines.TryGetValue($hash, [ref]$last)) {
                    if (($now - $last) -lt 20000000) { return }
                }
                $d.RecentLines[$hash] = $now

                $formatted = (Format-LogLine -Line $line) + "`n"
                $null = $d.LogBuffer.Append($formatted)

                $captured = $formatted
                $d.Window.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Normal,
                    [Action]{
                        if ($null -ne $d.LogOutput) {
                            $d.LogOutput.AppendText($captured)
                            $d.LogOutput.ScrollToEnd()
                        }
                    }.GetNewClosure()
                )
            }

            $script:OutputEventJob = Register-ObjectEvent `
                -InputObject $proc `
                -EventName   OutputDataReceived `
                -Action      $outputHandler `
                -MessageData $handlerData

            $script:ErrorEventJob = Register-ObjectEvent `
                -InputObject $proc `
                -EventName   ErrorDataReceived `
                -Action      $outputHandler `
                -MessageData $handlerData

            $proc.BeginOutputReadLine()
            $proc.BeginErrorReadLine()

            # Stdin flush timer – keeps the process output buffer moving
            $flushTimer = New-Object System.Windows.Threading.DispatcherTimer
            $flushTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
            $flushProc = $proc
            $flushTimer.Add_Tick({
                try {
                    if ($null -ne $flushProc -and -not $flushProc.HasExited) {
                        $flushProc.StandardInput.WriteLine('')
                        $flushProc.StandardInput.Flush()
                    }
                } catch { }
            }.GetNewClosure())
            $flushTimer.Start()
            $script:StdinFlushTimer = $flushTimer
        }
    }
    #endregion

    #region Timeout watchdog
    if ($TimeoutMinutes -gt 0) {
        $wdMs   = $TimeoutMinutes * 60 * 1000
        $wdData = @{
            Proc       = $proc
            Context    = $Context
            Title      = $Title
            OnComplete = $OnComplete
        }

        $wdTimer = New-Object System.Windows.Threading.DispatcherTimer
        $wdTimer.Interval = [TimeSpan]::FromMilliseconds($wdMs)
        $wdData['Timer'] = $wdTimer
        $wdTimer.Add_Tick({
            $wdData.Timer.Stop()
            $p = $wdData.Proc
            if ($null -ne $p -and -not $p.HasExited) {
                try { $p.Kill() } catch { }
            }
            $wdData.Context.Window.Dispatcher.Invoke([Action]{
                $lbl = $wdData.Context.Controls['StatusLabel']
                if ($null -ne $lbl) {
                    $lbl.Text = "Timed out: $($wdData.Title)"
                }
                $logOut = $wdData.Context.Controls['LogOutput']
                if ($null -ne $logOut) {
                    $logOut.AppendText("`n[!] Operation timed out after $TimeoutMinutes minute(s).`n")
                    $logOut.ScrollToEnd()
                }
            }.GetNewClosure())
            Complete-WsusOperation -Context $wdData.Context -Title $wdData.Title -Success $false -OnComplete $wdData.OnComplete
        }.GetNewClosure())
        $wdTimer.Start()
        $script:WatchdogTimer = $wdTimer
    }
    #endregion
}

#endregion

Export-ModuleMember -Function @(
    'Start-WsusOperation',
    'Stop-WsusOperation',
    'Complete-WsusOperation',
    'Find-WsusScript'
)
