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

$script:CurrentProcess    = $null
$script:WatchdogTimer     = $null
$script:KeystrokeTimer    = $null
$script:StdinFlushTimer   = $null
$script:OutputEventJob    = $null
$script:ErrorEventJob     = $null
$script:ExitEventJob      = $null
# Tracks operations that have already run Complete-WsusOperation once, so the
# watchdog Tick and the Exited event do not both fire the user's OnComplete
# callback (duplicate history rows, duplicate notifications). Keyed by
# process Id for live operations; tests can clear entries via
# Reset-WsusOperationGuard.
$script:CompletedOperations = @{}


try {
    if (-not (Get-Command New-WsusGuiStatusText -ErrorAction SilentlyContinue)) {
        $guiShellPath = Join-Path $PSScriptRoot 'WsusGuiShell.psm1'
        if (Test-Path -LiteralPath $guiShellPath -PathType Leaf) {
            # -Global: keep the dependency visible to the GUI session after this
            # module loads (otherwise Import-Module -Force re-installs the module
            # in this module's private scope and hides its exports).
            Import-Module $guiShellPath -Global -Force -DisableNameChecking -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Verbose $_.Exception.Message
}
#endregion

#region Private helpers

function Stop-RunnerTimers {
    foreach ($timerVar in @('WatchdogTimer','KeystrokeTimer','StdinFlushTimer')) {
        $timer = Get-Variable -Name $timerVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $timer) {
            try { $timer.Stop() } catch { Write-Verbose $_.Exception.Message }
            Set-Variable -Name $timerVar -Value $null -Scope Script
        }
    }
}

function Start-RunnerTimer {
<#
.SYNOPSIS
    Starts a DispatcherTimer, swallowing the InvalidOperationException that
    fires when the timer was constructed outside a running WPF Dispatcher
    (e.g. in Pester tests, headless runspaces, or programmatic runners).
.DESCRIPTION
    DispatcherTimer.Start() requires an active Dispatcher on the calling
    thread. In a non-WPF context (programmatic E2E, mock dispatcher) it
    throws "You cannot call a method on a null-valued expression." That
    failure was treated as a hard error in the runner, breaking tests that
    exercised the runner without a real WPF UI. Treat the absence of a
    Dispatcher as a soft warning instead.
.PARAMETER Timer
    DispatcherTimer instance to start.
.EXAMPLE
    Start-RunnerTimer -Timer $kTimer
#>
    [CmdletBinding()]
    param([System.Windows.Threading.DispatcherTimer]$Timer)
    if ($null -eq $Timer) { return }
    try {
        $Timer.Start()
    } catch [System.InvalidOperationException] {
        Write-Verbose "Timer start skipped (no Dispatcher): $($_.Exception.Message)"
    } catch {
        Write-Verbose "Timer start failed: $($_.Exception.Message)"
    }
}

function Unregister-RunnerEvents {
    foreach ($jobVar in @('OutputEventJob','ErrorEventJob','ExitEventJob')) {
        $job = Get-Variable -Name $jobVar -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $job) {
            try { Unregister-Event -SourceIdentifier $job.Name -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
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

function New-WsusEnvironmentBootstrapFile {
<#
.SYNOPSIS
    Writes a temporary PowerShell script that exports the supplied environment
    variables, returning the file path so the caller can dot-source it before
    the real command runs.
.DESCRIPTION
    .NET ProcessStartInfo rejects the combination of UseShellExecute=$true and
    a populated EnvironmentVariables hashtable. To still pass secrets (e.g.
    WSUS_INSTALL_SA_PASSWORD) to a child PowerShell process started with a
    visible console window (Terminal mode), this function writes the values to
    a one-line-per-variable bootstrap file under $env:TEMP. The caller injects
    `. "$path"` ahead of the user command so the env vars are in scope before
    the real script runs. The file is created with restrictive ACLs (current
    user only) and must be deleted by the caller.
.PARAMETER Environment
    Hashtable of env var name -> value (values are coerced to [string]).
.OUTPUTS
    [string] Full path to the bootstrap file, or $null if Environment is empty.
.EXAMPLE
    $bootstrap = New-WsusEnvironmentBootstrapFile -Environment @{ WSUS_INSTALL_SA_PASSWORD = 'Secret' }
    $cmd = ". '$bootstrap'; & '$script' -Foo bar"
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Environment
    )

    if (@($Environment.Keys).Count -eq 0) { return $null }

    $fileName = "wsus-env-{0}.ps1" -f ([guid]::NewGuid().ToString('N'))
    $fullPath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("# wsus environment bootstrap - auto-generated, do not edit")
    foreach ($entry in $Environment.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Key)) { continue }
        $name  = [string]$entry.Key
        $value = [string]$entry.Value
        # Single-quoted literal to avoid $env re-evaluation; escape any embedded single quotes
        $escaped = $value -replace "'", "''"
        $null = $sb.AppendLine("Set-Item -LiteralPath 'Env:$name' -Value '$escaped' -Force")
    }

    try {
        Set-Content -LiteralPath $fullPath -Value $sb.ToString() -Encoding UTF8 -Force
    } catch {
        Write-Verbose "Failed to write env bootstrap file '$fullPath': $($_.Exception.Message)"
        return $null
    }

    # Best-effort restrictive ACL: current user only. Ignore on unsupported hosts.
    try {
        $acl = Get-Acl -LiteralPath $fullPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
            'FullControl',
            'Allow')
        $acl.SetAccessRule($rule)
        # Strip inherited rules so non-owner users on the host cannot read the secret
        $acl.SetAccessRuleProtection($true, $false) | Out-Null
        Set-Acl -LiteralPath $fullPath -AclObject $acl
    } catch {
        Write-Verbose "Could not harden ACLs on env bootstrap file: $($_.Exception.Message)"
    }

    return $fullPath
}

function Remove-WsusEnvironmentBootstrapFile {
<#
.SYNOPSIS
    Deletes the env bootstrap file written by New-WsusEnvironmentBootstrapFile.
.DESCRIPTION
    Idempotent. Swallows missing-file errors. The file is unlinked on a best-
    effort basis so secret material does not linger on disk after the operation
    completes.
.PARAMETER Path
    Path returned by New-WsusEnvironmentBootstrapFile.
.EXAMPLE
    Remove-WsusEnvironmentBootstrapFile -Path $bootstrap
#>
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Write-Verbose "Failed to remove env bootstrap file '$Path': $($_.Exception.Message)"
    }
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

    # Guard against double-completion when the watchdog and exit handler race.
    # Uses the (ProcessId, OnComplete-target) pair so concurrent operations on
    # different processes are not affected, and tests that share a mock context
    # can complete the same operation multiple times by clearing the entry.
    # Process.Id is null until Start() succeeds, so fall back to the context hash in that case.
    $guardKey = if ($Context.ContainsKey('Process') -and $null -ne $Context.Process -and $null -ne $Context.Process.Id) { $Context.Process.Id } else { [string]$Context.GetHashCode() }
    if ($script:CompletedOperations.ContainsKey($guardKey)) { return }
    $script:CompletedOperations[$guardKey] = $true

    Stop-RunnerTimers
    Unregister-RunnerEvents

    # Clean up the env bootstrap file (Terminal-mode secret propagation) on
    # every completion path so the SA password does not linger on disk.
    if ($Context.ContainsKey('EnvBootstrapPath') -and -not [string]::IsNullOrWhiteSpace($Context['EnvBootstrapPath'])) {
        Remove-WsusEnvironmentBootstrapFile -Path ([string]$Context['EnvBootstrapPath'])
        $Context['EnvBootstrapPath'] = $null
    }

    # Clean up Live Terminal mode: close the visible PowerShell console window
    # that was launched in parallel with the embedded child, and remove the
    # wrapper script. Close politely (sends WM_CLOSE); fall back to Kill if
    # it doesn't respond within 2s.
    if ($Context.ContainsKey('TerminalProcess') -and $null -ne $Context['TerminalProcess']) {
        try {
            if (-not $Context['TerminalProcess'].HasExited) {
                $Context['TerminalProcess'].CloseMainWindow() | Out-Null
                if (-not $Context['TerminalProcess'].WaitForExit(2000)) {
                    $Context['TerminalProcess'].Kill()
                }
            }
        } catch { Write-Verbose $_.Exception.Message }
        $Context['TerminalProcess'] = $null
    }
    if ($Context.ContainsKey('TerminalWrapperPath') -and -not [string]::IsNullOrWhiteSpace($Context['TerminalWrapperPath'])) {
        try { Remove-Item -LiteralPath ([string]$Context['TerminalWrapperPath']) -Force -ErrorAction SilentlyContinue } catch {}
        $Context['TerminalWrapperPath'] = $null
    }

    $completionState = if ($Success) { 'Completed' } else { 'Failed' }
    if (Get-Command Set-WsusGuiOperationUiState -ErrorAction SilentlyContinue) {
        Set-WsusGuiOperationUiState -Context $Context -State $completionState -Title $Title
    } else {
        $timestamp = (Get-Date).ToString('HH:mm:ss')
        $statusMsg = if ($Success) { "Completed: $Title  [$timestamp]" }
                     else          { "Failed: $Title  [$timestamp]" }

        $Context.Window.Dispatcher.Invoke([Action]{
            $lbl = $Context.Controls['StatusLabel']
            if ($null -ne $lbl) { $lbl.Text = $statusMsg }

            $cancel = $Context.Controls['CancelButton']
            if ($null -ne $cancel) { $cancel.Visibility = 'Collapsed' }

            foreach ($bName in $Context.OperationButtons) {
                $btn = $Context.Controls[$bName]
                if ($null -ne $btn) { $btn.IsEnabled = $true; $btn.Opacity = 1.0 }
            }
            foreach ($iName in $Context.OperationInputs) {
                $inp = $Context.Controls[$iName]
                if ($null -ne $inp) { $inp.IsEnabled = $true; $inp.Opacity = 1.0 }
            }

            if ($Context.ContainsKey('UpdateButtonState') -and $null -ne $Context.UpdateButtonState) {
                try { & $Context.UpdateButtonState } catch { Write-Verbose $_.Exception.Message }
            }
        }.GetNewClosure())
    }

    # Reset flag on the GUI script scope via the supplied setter, or directly
    if ($Context.ContainsKey('SetOperationRunning') -and $null -ne $Context.SetOperationRunning) {
        try { & $Context.SetOperationRunning $false } catch { Write-Verbose $_.Exception.Message }
    }

    $script:CurrentProcess = $null

    if ($null -ne $OnComplete) {
        try { & $OnComplete $Success } catch { Write-Verbose $_.Exception.Message }
    }
}

function Stop-WsusOperation {
    <#
    .SYNOPSIS
        Cancels the currently running WSUS operation.
    .DESCRIPTION
        Kills the supplied process (and its child tree where possible), then stops
        all runner-owned timers. Safe to call when no process is running.
    .PARAMETER Process
        The System.Diagnostics.Process object to terminate. Passing $null is safe.
    .EXAMPLE
        Stop-WsusOperation -Process $script:CurrentProcess
    #>
    [CmdletBinding()]
    param(
        [System.Diagnostics.Process]$Process
    )

    Stop-RunnerTimers

    if ($null -eq $Process) { return }
    if ($Process.HasExited) { return }

    try {
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($Process.Id)" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            try { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue } catch { Write-Verbose $_.Exception.Message }
        }
    } catch {
        Write-Verbose $_.Exception.Message
    }

    $Process.Kill()
}

function Start-WsusOperation {
<#
.SYNOPSIS
    Starts a WSUS CLI operation as a child process with full lifecycle management.
.DESCRIPTION
    Runner owns: process creation, button state, event subscriptions, timeout
    watchdog, and cleanup.  Output display is delegated to the selected mode:

      Embedded  - captures stdout/stderr into the GUI log panel TextBox.
      Terminal  - launches a visible PowerShell console window.

    GUI state is communicated via the Context hashtable so that the module has
    no hard dependency on script-scope variables in the GUI.
.PARAMETER Command
    The PowerShell command string to execute (passed to powershell.exe -Command).
.PARAMETER Title
    Human-readable name shown in the status bar and log panel header.
.PARAMETER Context
    Hashtable containing GUI state references. Expected keys:
      Window           [System.Windows.Window]
      Controls         [hashtable] - named controls dictionary
      OperationButtons [string[]]  - button names to disable during the operation
      OperationInputs  [string[]]  - input field names to disable
      LogOutput        [System.Windows.Controls.TextBox] - log panel (Embedded mode)
      StatusLabel      [System.Windows.Controls.TextBlock]
      CancelButton     [System.Windows.Controls.Button]
      ScriptRoot       [string] - working directory for the child process
      SetOperationRunning [scriptblock] - called with $true/$false to set the flag
      UpdateButtonState   [scriptblock] - (optional) called after completion
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

        [hashtable]$Environment = @{},


        [scriptblock]$OnComplete = $null
    )

    #region Pre-flight UI updates (must run on UI thread)
    if (Get-Command Set-WsusGuiOperationUiState -ErrorAction SilentlyContinue) {
        Set-WsusGuiOperationUiState -Context $Context -State Running -Title $Title
    } else {
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
    }
    #endregion

    # Set the running flag via the supplied setter
    if ($Context.ContainsKey('SetOperationRunning') -and $null -ne $Context.SetOperationRunning) {
        try { & $Context.SetOperationRunning $true } catch { Write-Verbose $_.Exception.Message }
    }

    #region Build ProcessStartInfo
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'

    if (-not [string]::IsNullOrWhiteSpace($Context.ScriptRoot)) {
        $psi.WorkingDirectory = $Context.ScriptRoot
    }

    # Terminal mode (UseShellExecute=$true) cannot carry EnvironmentVariables.
    # To still pass secrets like WSUS_INSTALL_SA_PASSWORD, write them to a
    # temporary bootstrap script and dot-source it ahead of the real command.
    # The bootstrap file is recorded on the context so Complete-WsusOperation
    # can clean it up.
    $envBootstrapPath = $null
    $useEnvBootstrap = ($Mode -eq 'Terminal') -and (@($Environment.Keys).Count -gt 0)

    if ($useEnvBootstrap) {
        $envBootstrapPath = New-WsusEnvironmentBootstrapFile -Environment $Environment
        if ([string]::IsNullOrWhiteSpace($envBootstrapPath)) {
            throw "Failed to materialise environment bootstrap file for Terminal-mode operation '$Title'."
        }
        $Context['EnvBootstrapPath'] = $envBootstrapPath
        # Do not populate ProcessStartInfo.EnvironmentVariables; UseShellExecute=$true
        # would reject them. The bootstrap script injects them into the child PowerShell
        # process scope instead.
    } else {
        foreach ($entry in $Environment.GetEnumerator()) {
            if ($null -ne $entry.Key) {
                $psi.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
            }
        }
    }

    # The wrapped command (with stream preferences forced on and *>&1 redirect)
    # is what both the embedded child and the visible terminal run. Capture it
    # here so the Terminal branch can hand the same string to the visible window.
    $baseWrappedCmd = "`$VerbosePreference='Continue'; `$WarningPreference='Continue'; `$InformationPreference='Continue'; & { $Command } *>&1"
    $Context['BaseWrappedCmd'] = $baseWrappedCmd

    switch ($Mode) {
        'Terminal' {
            # Embedded child runs the same command as the visible terminal,
            # but with redirected stdio so the GUI's OutputDataReceived can
            # capture lines into the embedded log panel. The visible terminal
            # (launched below) runs the identical wrapped command in a real
            # console with no redirection, so the user sees the actual script
            # output (robocopy progress, Write-Host, Write-Output, etc.) live.
            $psi.UseShellExecute        = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.RedirectStandardInput  = $true
            $psi.CreateNoWindow         = $true
            $psi.Arguments              = "-NoProfile -ExecutionPolicy Bypass -Command `"$baseWrappedCmd`""
        }
        'Embedded' {
            $psi.UseShellExecute         = $false
            $psi.RedirectStandardOutput  = $true
            $psi.RedirectStandardError   = $true
            $psi.RedirectStandardInput   = $true
            $psi.CreateNoWindow          = $true
            $psi.Arguments               = "-NoProfile -ExecutionPolicy Bypass -Command `"$baseWrappedCmd`""
        }
    }
    #endregion

    #region Create and start process
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo          = $psi
    $proc.EnableRaisingEvents = $true

    $script:CurrentProcess = $proc
    $Context['Process'] = $proc

    try {
        $proc.Start() | Out-Null
    } catch {
        # Clean up the bootstrap file before bubbling the failure through
        # Complete-WsusOperation (the watchdog/exit paths also clean up, but
        # Process never started so neither will fire here).
        if ($useEnvBootstrap) {
            Remove-WsusEnvironmentBootstrapFile -Path $envBootstrapPath
        }
        Complete-WsusOperation -Context $Context -Title $Title -Success $false -OnComplete $OnComplete
        throw
    }

    # Terminal mode: launch a visible PowerShell console window that runs
    # the SAME wrapped command as the embedded child. The visible console
    # shows the script's real output (Write-Host, robocopy progress, etc.)
    # live, with full scrollback, selection, and Ctrl+C. The embedded child
    # runs in parallel with redirected stdio so the GUI can stream identical
    # output into the embedded log panel.
    #
    # After the operation finishes, the wrapper waits up to 5s for the user
    # to press Q or Escape to dismiss, then auto-closes.
    if ($Mode -eq 'Terminal' -and $Context.ContainsKey('BaseWrappedCmd')) {
        try {
            # Generate a tiny wrapper script so we can keep the visible console
            # open after the operation completes, surface a 'press Q/Esc or wait
            # 5s' prompt, and then close. We can't do that with a -Command
            # string because PowerShell exits as soon as the command finishes.
            $terminalWrapperPath = Join-Path $env:TEMP ("wsusmanager-terminal-wrap-" + [guid]::NewGuid() + ".ps1")
            $baseCmdEscaped = $Context['BaseWrappedCmd']
            $wrapperTemplate = @'
#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
try {
    & { __WSUS_BASE_CMD__ }
} catch {
    Write-Host ('[!] Terminal wrapper caught exception: ' + $_.Exception.Message) -ForegroundColor Red
}
Write-Host ''
Write-Host '--- Operation complete ---' -ForegroundColor Cyan
Write-Host 'Press Q or Escape to close, or wait 5 seconds...' -ForegroundColor DarkGray
$start = Get-Date
while (((Get-Date) - $start).TotalSeconds -lt 5) {
    try {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Escape' -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                exit 0
            }
        }
    } catch {
        # Non-interactive host (no console attached); just wait out the timer.
    }
    Start-Sleep -Milliseconds 100
}
exit 0
'@
            $wrapper = $wrapperTemplate.Replace('__WSUS_BASE_CMD__', $baseCmdEscaped)
            Set-Content -LiteralPath $terminalWrapperPath -Value $wrapper -Force
            $Context['TerminalWrapperPath'] = $terminalWrapperPath

            $visiblePsi = New-Object System.Diagnostics.ProcessStartInfo
            $visiblePsi.FileName        = 'powershell.exe'
            $visiblePsi.UseShellExecute = $true
            $visiblePsi.CreateNoWindow  = $false
            $visiblePsi.WindowStyle     = 'Normal'
            $visiblePsi.Arguments       = "-NoProfile -ExecutionPolicy Bypass -File `"$terminalWrapperPath`""
            $terminalProc = [System.Diagnostics.Process]::Start($visiblePsi)
            $Context['TerminalProcess'] = $terminalProc
        } catch {
            Write-Verbose "Failed to launch terminal window: $($_.Exception.Message)"
        }
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
            # Keystroke timer - sends Enter periodically to flush the PowerShell
            # window's output buffer. Default interval is 30s (configurable via
            # WsusConfig.Gui.Timers.KeystrokeFlush). The PowerShell window can
            # occasionally block waiting for input on certain Read-Host / prompt
            # paths; sending a newline nudges it forward without affecting
            # non-interactive output (Write-Host / Write-Output are unaffected by
            # spurious newlines on stdin).
            $flushMs = 5000
            try {
                $cfgPath = Join-Path $PSScriptRoot 'WsusConfig.psm1'
                if (Test-Path -LiteralPath $cfgPath) {
                    Import-Module $cfgPath -Global -Force -DisableNameChecking -ErrorAction SilentlyContinue
                    if (Get-Command Get-WsusTimerInterval -ErrorAction SilentlyContinue) {
                        $flushMs = Get-WsusTimerInterval -Timer 'KeystrokeFlush'
                    }
                }
            } catch { Write-Verbose $_.Exception.Message }

            $kTimer = New-Object System.Windows.Threading.DispatcherTimer
            $kTimer.Interval = [TimeSpan]::FromMilliseconds($flushMs)
            $kTimerData = @{ Proc = $proc }
            $kTimer.Add_Tick({
                $p = $kTimerData.Proc
                if ($null -ne $p -and -not $p.HasExited) {
                    # Best-effort stdin newline; ignore errors
                    try { $p.StandardInput.WriteLine('') } catch { Write-Verbose $_.Exception.Message }
                }
            }.GetNewClosure())
            Start-RunnerTimer -Timer $kTimer
            $script:KeystrokeTimer = $kTimer
        }

        'Embedded' {
            # Log accumulator (StringBuilder avoids O(n^2) string concat)
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

            # Stdin flush timer - keeps the process output buffer moving
            $flushTimer = New-Object System.Windows.Threading.DispatcherTimer
            $flushTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
            $flushProc = $proc
            $flushTimer.Add_Tick({
                try {
                    if ($null -ne $flushProc -and -not $flushProc.HasExited) {
                        $flushProc.StandardInput.WriteLine('')
                        $flushProc.StandardInput.Flush()
                    }
                } catch { Write-Verbose $_.Exception.Message }
            }.GetNewClosure())
            Start-RunnerTimer -Timer $flushTimer
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
            try {
                $wdData.Timer.Stop()
                $p = $wdData.Proc
                if ($null -ne $p -and -not $p.HasExited) {
                    try { Stop-WsusOperation -Process $p } catch { Write-Verbose $_.Exception.Message }
                }
                $wdData.Context.Window.Dispatcher.Invoke([Action]{
                    $lbl = $wdData.Context.Controls['StatusLabel']
                    if ($null -ne $lbl) {
                        if (Get-Command New-WsusGuiStatusText -ErrorAction SilentlyContinue) {
                            $lbl.Text = New-WsusGuiStatusText -State TimedOut -Title $wdData.Title
                        } else {
                            $lbl.Text = "Timed out: $($wdData.Title)"
                        }
                    }
                    $logOut = $wdData.Context.Controls['LogOutput']
                    if ($null -ne $logOut) {
                        $logOut.AppendText("`n[!] Operation timed out after $TimeoutMinutes minute(s).`n")
                        $logOut.ScrollToEnd()
                    }
                }.GetNewClosure())
                Complete-WsusOperation -Context $wdData.Context -Title $wdData.Title -Success $false -OnComplete $wdData.OnComplete
            } catch {
                Write-Verbose $_.Exception.Message
            }
        }.GetNewClosure())
        $wdTimer.Start()
        $script:WatchdogTimer = $wdTimer
    }
    #endregion

    return $proc
}

function Reset-WsusOperationGuard {
<#
.SYNOPSIS
    Clears the runner's internal double-completion guard.
.DESCRIPTION
    Tests that share a mock context across multiple Complete-WsusOperation
    calls need to clear the guard between calls. Production callers should
    not need this: each Start-WsusOperation creates a fresh process entry
    that is cleaned up automatically.
.EXAMPLE
    Reset-WsusOperationGuard
#>
    [CmdletBinding()]
    param()
    $script:CompletedOperations.Clear()
}

#endregion

function Get-WsusOperationTimeout {
    <#
    .SYNOPSIS
        Returns the timeout in minutes for a given operation type.
    .DESCRIPTION
        Centralised operation timeout table used by GUI and CLI scripts to
        enforce per-operation time limits.
    .PARAMETER OperationType
        One of: Cleanup, Sync, Install, Export, Import, Diagnostics, Health, Repair, Default.
    .OUTPUTS
        Integer timeout value in minutes.
    .EXAMPLE
        $mins = Get-WsusOperationTimeout -OperationType 'Sync'
        # Returns 120
    #>
    param(
        [ValidateSet('Cleanup', 'Sync', 'Install', 'Export', 'Import', 'Diagnostics', 'Health', 'Repair', 'Default')]
        [string]$OperationType = 'Default'
    )
    $timeouts = @{
        Cleanup     = 60
        Sync        = 120
        Install     = 60
        Export      = 90
        Import      = 90
        Diagnostics = 30
        Health      = 30
        Repair      = 45
        Default     = 30
    }
    return $timeouts[$OperationType]
}

Export-ModuleMember -Function @(
    'Get-WsusOperationTimeout',
    'Start-WsusOperation',
    'Stop-WsusOperation',
    'Complete-WsusOperation',
    'Find-WsusScript',
    'Reset-WsusOperationGuard',
    'New-WsusEnvironmentBootstrapFile',
    'Remove-WsusEnvironmentBootstrapFile',
    'Start-RunnerTimer'
)
