#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Fallback notification output')]
param()

function New-WsusNotificationIcon {
<#
.SYNOPSIS
    Creates a NotifyIcon instance for system tray balloon tip notifications.
.DESCRIPTION
    Instantiates a System.Windows.Forms.NotifyIcon for use as a fallback
    notification mechanism on systems that do not support Windows 10 toast
    notifications. Optionally loads a custom icon from a file path.
.PARAMETER IconPath
    Optional path to a .ico file. If empty or the file does not exist,
    the default application icon is used.
.OUTPUTS
    System.Windows.Forms.NotifyIcon
.EXAMPLE
    $icon = New-WsusNotificationIcon -IconPath "C:\WSUS\wsus-icon.ico"
#>
    param(
        [string]$IconPath = ""
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon

        if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path $IconPath)) {
            $notifyIcon.Icon = New-Object System.Drawing.Icon $IconPath
        } else {
            $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        }

        $notifyIcon.Visible = $true
        return $notifyIcon
    } catch {
        Write-Verbose "WsusNotification: Failed to create NotifyIcon  - $($_.Exception.Message)"
        return $null
    }
}

function Remove-WsusNotificationIcon {
<#
.SYNOPSIS
    Disposes a NotifyIcon instance created by New-WsusNotificationIcon.
.DESCRIPTION
    Hides the system tray icon and releases its resources. Safe to call
    even if the icon is $null.
.PARAMETER NotifyIcon
    The NotifyIcon instance to dispose.
.EXAMPLE
    Remove-WsusNotificationIcon -NotifyIcon $icon
#>
    param(
        [System.Windows.Forms.NotifyIcon]$NotifyIcon
    )

    if ($null -eq $NotifyIcon) { return }

    try {
        $NotifyIcon.Visible = $false
        $NotifyIcon.Dispose()
    } catch {
        Write-Verbose "WsusNotification: Failed to dispose NotifyIcon  - $($_.Exception.Message)"
    }
}

function Show-WsusNotification {
<#
.SYNOPSIS
    Shows a toast/balloon notification when a WSUS operation completes.
.DESCRIPTION
    Shows a Windows toast notification (Windows 10+) or balloon tip (older Windows).
    Falls back to log-only if no notification API is available.
    Optionally plays a system beep based on operation result.
.PARAMETER Title
    Notification title (e.g., "WSUS Manager  - Cleanup Complete").
.PARAMETER Message
    Notification body (e.g., "Completed in 4m 23s  - Pass").
.PARAMETER Result
    "Pass" or "Fail"  - determines icon and beep behavior.
.PARAMETER Duration
    Optional TimeSpan included in the message if provided.
.PARAMETER EnableBeep
    If true, plays a system beep via MediaPlayer.SystemSounds.
.PARAMETER AppId
    AppId for the toast notification. Defaults to "WSUS Manager".
.EXAMPLE
    Show-WsusNotification -Title "WSUS Manager  - Sync Complete" -Message "Sync finished successfully." -Result "Pass"
.EXAMPLE
    $elapsed = New-TimeSpan -Minutes 4 -Seconds 23
    Show-WsusNotification -Title "WSUS Manager  - Cleanup" -Message "Deep cleanup finished." -Result "Pass" -Duration $elapsed -EnableBeep
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Pass", "Fail")]
        [string]$Result = "Pass",

        [System.TimeSpan]$Duration,

        [switch]$EnableBeep,

        [string]$AppId = "WSUS Manager"
    )

    # Append duration to message if provided
    if ($null -ne $Duration -and $Duration.TotalSeconds -gt 0) {
        $durationText = if ($Duration.TotalMinutes -ge 1) {
            "$([int]$Duration.TotalMinutes)m $($Duration.Seconds)s"
        } else {
            "$($Duration.Seconds)s"
        }
        $Message = "$Message  - $durationText"
    }

    # Append result to message
    $Message = "$Message  - $Result"

    # Play system beep before showing notification
    if ($EnableBeep) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            if ($Result -eq "Pass") {
                [System.Media.SystemSounds]::Asterisk.Play()
            } else {
                [System.Media.SystemSounds]::Exclamation.Play()
            }
        } catch {
            Write-Verbose "WsusNotification: Beep failed  - $($_.Exception.Message)"
        }
    }

    # Attempt 1: Windows 10+ toast notification
    try {
        $toastXml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$Title</text>
      <text>$Message</text>
    </binding>
  </visual>
</toast>
"@
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($toastXml)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
        Write-Verbose "WsusNotification: Toast displayed  - $Title"
        return
    } catch {
        Write-Verbose "WsusNotification: Toast unavailable, trying balloon tip  - $($_.Exception.Message)"
    }

    # Attempt 2: System tray balloon tip
    $notifyIcon = $null
    try {
        $notifyIcon = New-WsusNotificationIcon
        if ($null -ne $notifyIcon) {
            $balloonIcon = if ($Result -eq "Pass") {
                [System.Windows.Forms.ToolTipIcon]::Info
            } else {
                [System.Windows.Forms.ToolTipIcon]::Warning
            }
            $notifyIcon.ShowBalloonTip(5000, $Title, $Message, $balloonIcon)
            Write-Verbose "WsusNotification: Balloon tip displayed  - $Title"

            # Keep icon alive long enough for the balloon to display, then clean up
            Start-Sleep -Seconds 6
            return
        }
    } catch {
        Write-Verbose "WsusNotification: Balloon tip failed  - $($_.Exception.Message)"
    } finally {
        if ($null -ne $notifyIcon) {
            Remove-WsusNotificationIcon -NotifyIcon $notifyIcon
        }
    }

    # Attempt 3: Log-only fallback
    Write-Verbose "WsusNotification: [$Result] $Title  - $Message"
    Write-Host "[$Result] $Title  - $Message"
}

Export-ModuleMember -Function Show-WsusNotification, New-WsusNotificationIcon, Remove-WsusNotificationIcon
