<#
===============================================================================
Module: AsyncHelpers.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-14
===============================================================================

.SYNOPSIS
    Async helpers module for PowerShell GUI applications

.DESCRIPTION
    Provides helper functions for running background operations in WPF applications
    without blocking the UI thread. Designed for use with PS2EXE compiled applications.

    Key features:
    - Runspace pool management for efficient parallel execution
    - Async invocation with completion callbacks
    - WPF dispatcher helpers for safe UI updates from background threads
    - Background operation wrapper with progress and error handling

.NOTES
    This module is used by the WSUS Manager GUI (WsusManagementGui.ps1) for
    non-blocking operations. Can be reused in any WPF PowerShell application.
#>

#region Runspace Pool Management

$script:RunspacePool = $null
$script:MaxRunspaces = 4

<#
.SYNOPSIS
    Initializes a shared runspace pool for background operations.

.DESCRIPTION
    Creates a runspace pool that can be reused across multiple async operations.
    Call this once during application startup.

.PARAMETER MaxRunspaces
    Maximum number of concurrent runspaces. Default is 4.

.EXAMPLE
    Initialize-AsyncRunspacePool -MaxRunspaces 2
#>
function Initialize-AsyncRunspacePool {
    [CmdletBinding()]
    param(
        [int]$MaxRunspaces = 4
    )

    if ($null -eq $script:RunspacePool -or $script:RunspacePool.RunspacePoolStateInfo.State -ne 'Opened') {
        $script:MaxRunspaces = $MaxRunspaces
        $script:RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxRunspaces)
        $script:RunspacePool.ApartmentState = [System.Threading.ApartmentState]::STA
        $script:RunspacePool.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $script:RunspacePool.Open()
    }

    return $script:RunspacePool
}

<#
.SYNOPSIS
    Closes and disposes the shared runspace pool.

.DESCRIPTION
    Should be called during application shutdown to clean up resources.

.EXAMPLE
    Close-AsyncRunspacePool
#>
function Close-AsyncRunspacePool {
    [CmdletBinding()]
    param()

    if ($null -ne $script:RunspacePool) {
        try {
            $script:RunspacePool.Close()
            $script:RunspacePool.Dispose()
        } catch [System.Exception] {
            # Cleanup errors are expected during shutdown - log but don't throw
            Write-Verbose "Runspace pool cleanup: $($_.Exception.Message)"
        }
        $script:RunspacePool = $null
    }
}

#endregion

#region Async Invocation

<#
.SYNOPSIS
    Invokes a script block asynchronously using the runspace pool.

.DESCRIPTION
    Runs a script block in a background runspace and returns an async handle
    that can be used to retrieve results or check completion status.

.PARAMETER ScriptBlock
    The script block to execute asynchronously.

.PARAMETER ArgumentList
    Arguments to pass to the script block.

.PARAMETER OnComplete
    Optional callback script block to execute when the operation completes.
    Receives the result as a parameter.

.EXAMPLE
    $handle = Invoke-Async -ScriptBlock { Get-Process } -OnComplete { param($result) Write-Host "Got $($result.Count) processes" }

.OUTPUTS
    PSCustomObject with Handle and PowerShell properties for tracking the async operation.
#>
function Invoke-Async {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$ArgumentList,

        [scriptblock]$OnComplete
    )

    # Ensure pool is initialized
    if ($null -eq $script:RunspacePool -or $script:RunspacePool.RunspacePoolStateInfo.State -ne 'Opened') {
        Initialize-AsyncRunspacePool | Out-Null
    }

    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $script:RunspacePool

    $null = $powershell.AddScript($ScriptBlock)

    if ($ArgumentList) {
        foreach ($arg in $ArgumentList) {
            $null = $powershell.AddArgument($arg)
        }
    }

    $handle = $powershell.BeginInvoke()

    return [PSCustomObject]@{
        PowerShell = $powershell
        Handle     = $handle
        OnComplete = $OnComplete
        StartTime  = Get-Date
    }
}

<#
.SYNOPSIS
    Waits for an async operation to complete and returns the result.

.DESCRIPTION
    Blocks until the async operation completes, then returns the result.
    For non-blocking checks, use Test-AsyncComplete.

.PARAMETER AsyncHandle
    The handle returned by Invoke-Async.

.PARAMETER Timeout
    Maximum time to wait in milliseconds. Default is infinite (-1).

.EXAMPLE
    $handle = Invoke-Async -ScriptBlock { Get-Service }
    $services = Wait-Async -AsyncHandle $handle
#>
function Wait-Async {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$AsyncHandle,

        [int]$Timeout = -1
    )

    try {
        if ($Timeout -gt 0) {
            $completed = $AsyncHandle.Handle.AsyncWaitHandle.WaitOne($Timeout)
            if (-not $completed) {
                throw "Async operation timed out after $Timeout ms"
            }
        }

        $result = $AsyncHandle.PowerShell.EndInvoke($AsyncHandle.Handle)

        # Execute callback if provided
        if ($AsyncHandle.OnComplete) {
            & $AsyncHandle.OnComplete $result
        }

        return $result
    }
    finally {
        $AsyncHandle.PowerShell.Dispose()
    }
}

<#
.SYNOPSIS
    Tests if an async operation has completed.

.DESCRIPTION
    Non-blocking check for async operation completion status.

.PARAMETER AsyncHandle
    The handle returned by Invoke-Async.

.EXAMPLE
    if (Test-AsyncComplete -AsyncHandle $handle) {
        $result = Wait-Async -AsyncHandle $handle
    }
#>
function Test-AsyncComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$AsyncHandle
    )

    return $AsyncHandle.Handle.IsCompleted
}

<#
.SYNOPSIS
    Cancels a running async operation.

.DESCRIPTION
    Attempts to stop a running async operation and clean up resources.

.PARAMETER AsyncHandle
    The handle returned by Invoke-Async.

.EXAMPLE
    Stop-Async -AsyncHandle $handle
#>
function Stop-Async {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$AsyncHandle
    )

    try {
        $AsyncHandle.PowerShell.Stop()
        $AsyncHandle.PowerShell.Dispose()
    } catch [System.Exception] {
        # Stop errors are expected for already-completed operations
        Write-Verbose "Async stop: $($_.Exception.Message)"
    }
}

#endregion

#region WPF Dispatcher Helpers

<#
.SYNOPSIS
    Invokes an action on the WPF UI thread.

.DESCRIPTION
    Safely executes code on the WPF dispatcher thread, which is required
    for any UI updates from background threads.

.PARAMETER Window
    The WPF Window object whose dispatcher to use.

.PARAMETER Action
    The script block to execute on the UI thread.

.PARAMETER Async
    If specified, invokes asynchronously (fire-and-forget).

.EXAMPLE
    Invoke-UIThread -Window $mainWindow -Action {
        $txtStatus.Text = "Operation complete"
    }
#>
function Invoke-UIThread {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [switch]$Async
    )

    $dispatcher = $Window.Dispatcher

    if ($dispatcher.CheckAccess()) {
        # Already on UI thread, execute directly
        & $Action
    }
    elseif ($Async) {
        $null = $dispatcher.BeginInvoke([Action]$Action, [System.Windows.Threading.DispatcherPriority]::Normal)
    }
    else {
        $dispatcher.Invoke([Action]$Action, [System.Windows.Threading.DispatcherPriority]::Normal)
    }
}

<#
.SYNOPSIS
    Runs a background operation with UI progress updates.

.DESCRIPTION
    Executes a script block in the background while allowing safe UI updates
    through a progress callback.

.PARAMETER Window
    The WPF Window for dispatcher access.

.PARAMETER ScriptBlock
    The script block to execute in the background.

.PARAMETER OnProgress
    Script block called to update UI with progress. Receives progress message as parameter.

.PARAMETER OnComplete
    Script block called when operation completes. Receives result as parameter.

.PARAMETER OnError
    Script block called if an error occurs. Receives error as parameter.

.EXAMPLE
    Start-BackgroundOperation -Window $window -ScriptBlock {
        for ($i = 1; $i -le 100; $i++) {
            Start-Sleep -Milliseconds 50
            $i  # Output progress
        }
    } -OnProgress { param($p) $progressBar.Value = $p } -OnComplete { param($r) $txtStatus.Text = "Done!" }
#>
function Start-BackgroundOperation {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [scriptblock]$OnProgress,
        [scriptblock]$OnComplete,
        [scriptblock]$OnError
    )

    # Capture callback references for use in closure
    # Note: $progressCallback reserved for future streaming progress support
    $null = $OnProgress  # Suppress unused variable warning - progress streaming not yet implemented
    $completeCallback = $OnComplete
    $errorCallback = $OnError
    $targetWindow = $Window

    $handle = Invoke-Async -ScriptBlock $ScriptBlock

    # Start a timer to poll for completion
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    $timer.Add_Tick({
        if (Test-AsyncComplete -AsyncHandle $handle) {
            $timer.Stop()

            try {
                $result = Wait-Async -AsyncHandle $handle
                if ($completeCallback) {
                    Invoke-UIThread -Window $targetWindow -Action { & $completeCallback $result }
                }
            }
            catch {
                if ($errorCallback) {
                    $err = $_
                    Invoke-UIThread -Window $targetWindow -Action { & $errorCallback $err }
                }
            }
        }
    }.GetNewClosure())

    $timer.Start()

    return @{
        Handle = $handle
        Timer  = $timer
    }
}

#endregion

#region Export

Export-ModuleMember -Function @(
    'Initialize-AsyncRunspacePool',
    'Close-AsyncRunspacePool',
    'Invoke-Async',
    'Wait-Async',
    'Test-AsyncComplete',
    'Stop-Async',
    'Invoke-UIThread',
    'Start-BackgroundOperation'
)

#endregion
