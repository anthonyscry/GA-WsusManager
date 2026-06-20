#Requires -Version 5.1
<#
.SYNOPSIS
    Minimal FlaUI-compatible harness for GA-WsusManager GUI tests.
.DESCRIPTION
    Loads FlaUI assemblies when present and drives the WPF application through
    Windows UI Automation. The helper object keeps the raw AutomationElement in
    _ComElement because existing tests use UIA patterns directly for dialogs.
#>

$script:AutomationRoot = $null
$script:CurrentProcess = $null

function Select-FlaUIAssembly {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$FileName
    )

    $matches = @(Get-ChildItem -Path $PackageRoot -Filter $FileName -Recurse -ErrorAction SilentlyContinue)
    $net48 = $matches | Where-Object { $_.FullName -match '[\\/]net48[\\/]' } | Select-Object -First 1
    if ($net48) { return $net48 }
    $matches | Select-Object -First 1
}

function Import-FlaUIAssemblies {
    [CmdletBinding()]
    param(
        [string]$PackageRoot = (Join-Path $PSScriptRoot 'packages')
    )

    $dlls = @(
        (Select-FlaUIAssembly -PackageRoot $PackageRoot -FileName 'Interop.UIAutomationClient.dll'),
        (Select-FlaUIAssembly -PackageRoot $PackageRoot -FileName 'FlaUI.Core.dll'),
        (Select-FlaUIAssembly -PackageRoot $PackageRoot -FileName 'FlaUI.UIA3.dll')
    )

    if ($dlls -contains $null) {
        $installer = Join-Path $PSScriptRoot 'Install-FlaUI.ps1'
        if (Test-Path $installer) {
            & $installer -PackageRoot $PackageRoot | Out-Null
            $dlls = @(
                (Select-FlaUIAssembly -PackageRoot $PackageRoot -FileName 'Interop.UIAutomationClient.dll'),
                (Select-FlaUIAssembly -PackageRoot $PackageRoot -FileName 'FlaUI.Core.dll'),
                (Select-FlaUIAssembly -PackageRoot $PackageRoot -FileName 'FlaUI.UIA3.dll')
            )
        }
    }

    foreach ($dll in @($dlls)) {
        if (-not $dll) { throw "Required FlaUI assembly not found under $PackageRoot." }
        [void][System.Reflection.Assembly]::LoadFrom($dll.FullName)
    }

    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
}

function ConvertTo-HarnessElement {
    param([Parameter(Mandatory)]$Element)

    [pscustomobject]@{
        _ComElement = $Element
        AutomationId = $Element.Current.AutomationId
        Name = $Element.Current.Name
        ClassName = $Element.Current.ClassName
        ControlType = $Element.Current.ControlType.ProgrammaticName
        IsEnabled = $Element.Current.IsEnabled
        IsOffscreen = $Element.Current.IsOffscreen
        Title = $Element.Current.Name
    }
}

function Get-TreeScopeValue {
    param([switch]$Descendants)
    if ($Descendants) { return [System.Windows.Automation.TreeScope]::Descendants }
    [System.Windows.Automation.TreeScope]::Children
}
function Get-WsusKnownElementName {
    param([string]$AutomationId)

    $knownNames = @{
        BtnDashboard = '◉ Dashboard'
        BtnHistory = '☰ History'
        BtnHelp = '? Help'
        BtnSettings = '⚙ Settings'
        BtnAbout = 'ⓘ About'
        BtnInstall = '▶ Install WSUS'
        BtnFixSqlLogin = '[+] Fix SQL Login'
        BtnRestore = '↻ Restore DB'
        BtnMaintenance = '↻ Online Sync'
        BtnSchedule = '⌛ Schedule Task'
        BtnCleanup = '✧ Deep Cleanup'
        BtnTransfer = '⇄ Robocopy'
        BtnDiagnostics = '◎ Deep Diagnostics'
        BtnReset = '↺ Reset Content'
        QBtnDiagnostics = 'Deep Diagnostics'
        QBtnCleanup = 'Deep Cleanup'
        QBtnMaint = 'Online Sync'
        QBtnStart = 'Start Services'
        HelpBtnOverview = 'Overview'
        HelpBtnDashboard = 'Dashboard'
        HelpBtnOperations = 'Operations'
        HelpBtnAirGap = 'Air-Gap'
        HelpBtnTroubleshooting = 'Troubleshooting'
        BtnRefreshHistory = '↻ Refresh'
        BtnClearHistory = '✕ Clear History'
        BtnRunInstall = 'Install WSUS'
        BtnBack = 'Back'
    }

    $knownNames[$AutomationId]
}


function Find-UIElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [string]$ClassName,
        [int]$Timeout = 10
    )

    $root = if ($AppContext.PSObject.Properties['MainWindow'] -and $AppContext.MainWindow.PSObject.Properties['_ComElement']) {
        $AppContext.MainWindow._ComElement
    } elseif ($AppContext.PSObject.Properties['_ComElement']) {
        $AppContext._ComElement
    } else {
        [System.Windows.Automation.AutomationElement]::RootElement
    }

    $conditions = @()
    if ($AutomationId) {
        $idCondition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
        $knownName = Get-WsusKnownElementName -AutomationId $AutomationId
        if ($knownName) {
            $nameCondition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, $knownName)
            $conditions += [System.Windows.Automation.OrCondition]::new([System.Windows.Automation.Condition[]]@($idCondition, $nameCondition))
        } else {
            $conditions += $idCondition
        }
    }
    if ($Name) {
        $conditions += [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    }
    if ($ClassName) {
        $conditions += [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ClassNameProperty, $ClassName)
    }

    if ($conditions.Count -eq 0) { throw 'At least one selector is required.' }
    $condition = if ($conditions.Count -eq 1) { $conditions[0] } else { [System.Windows.Automation.AndCondition]::new([System.Windows.Automation.Condition[]]$conditions) }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $element = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($element) { return (ConvertTo-HarnessElement -Element $element) }
        Start-Sleep -Milliseconds 100
    } while ($watch.Elapsed.TotalSeconds -lt $Timeout)

    return $null
}

function Assert-UIElementExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [string]$ClassName,
        [int]$Timeout = 10
    )

    $element = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -ClassName $ClassName -Timeout $Timeout
    if (-not $element) {
        $selector = @($AutomationId, $Name, $ClassName) | Where-Object { $_ } | Select-Object -First 1
        throw "UI element not found: $selector"
    }
    $element
}

function Invoke-UIClick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AppContext,
        [Parameter(Mandatory)][string]$AutomationId,
        [int]$Delay = 0
    )

    $element = Assert-UIElementExists -AppContext $AppContext -AutomationId $AutomationId -Timeout 10
    $raw = $element._ComElement
    try {
        $pattern = $raw.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $pattern.Invoke()
    } catch {
        $point = $raw.GetClickablePoint()
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new([int]$point.X, [int]$point.Y)
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MouseClicker {
  [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);
}
'@ -ErrorAction SilentlyContinue
        [MouseClicker]::mouse_event(0x0002, 0, 0, 0, 0)
        [MouseClicker]::mouse_event(0x0004, 0, 0, 0, 0)
    }

    if ($Delay -gt 0) { Start-Sleep -Milliseconds $Delay }
}

function Save-UIScreenshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    $Path
}

function Test-WsusMainWindowCandidate {
    param([Parameter(Mandatory)]$Element)

    if ($Element.Current.Name -match 'WSUS Manager') {
        return $true
    }

    $knownButtonIds = 'BtnDashboard', 'BtnSettings', 'BtnInstall', 'QBtnDiagnostics'
    foreach ($buttonId in $knownButtonIds) {
        $buttonCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $buttonId
        )
        $button = $Element.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)
        if ($button) {
            return $true
        }
    }

    return $false
}

function Test-WsusMainWindowReady {
    param([Parameter(Mandatory)]$Element)

    if ($Element.Current.IsOffscreen) {
        return $false
    }

    foreach ($buttonId in 'BtnDashboard', 'BtnSettings', 'BtnInstall') {
        $buttonCondition = [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            $buttonId
        )
        if ($Element.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)) {
            return $true
        }
    }

    return $false
}

function Start-GuiApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$Timeout = 45
    )

    Import-FlaUIAssemblies

    if (-not (Test-Path $Path)) { throw "Application path not found: $Path" }

    Get-Process -Name 'GA-WsusManager', 'WsusManager' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name 'powershell' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -like '*WSUS*' -or $_.MainWindowTitle -like '*Wsus*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*WsusManagementGui.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 250

    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -ieq '.ps1') {
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $Path) -PassThru
    } else {
        $process = Start-Process -FilePath $Path -PassThru
    }
    $script:CurrentProcess = $process

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $processCondition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $processCondition)
        $window = $null
        foreach ($candidate in $windows) {
            if (Test-WsusMainWindowCandidate -Element $candidate) {
                $window = $candidate
                break
            }
        }
        if ($window -and (Test-WsusMainWindowReady -Element $window)) {
            return [pscustomobject]@{
                Process = $process
                ProcessId = $process.Id
                MainWindow = (ConvertTo-HarnessElement -Element $window)
            }
        }
        if ($process.HasExited) { throw "Application exited during startup with code $($process.ExitCode)." }
        Start-Sleep -Milliseconds 250
    } while ($watch.Elapsed.TotalSeconds -lt $Timeout)

    throw "Timed out waiting for main window from process $($process.Id)."
}

function Stop-GuiApplication {
    [CmdletBinding()]
    param([switch]$Force)

    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        if ($Force) {
            $script:CurrentProcess.Kill()
        } else {
            [void]$script:CurrentProcess.CloseMainWindow()
        }
        $script:CurrentProcess.WaitForExit(5000) | Out-Null
    }

    Get-Process -Name 'GA-WsusManager', 'WsusManager' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($Force) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } else { Stop-Process -Id $_.Id -ErrorAction SilentlyContinue }
    }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*WsusManagementGui.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Wait-UIElementGone {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [string]$ClassName,
        [int]$Timeout = 10
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        $element = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -ClassName $ClassName -Timeout 1
        if (-not $element) { return $true }
        Start-Sleep -Milliseconds 100
    } while ($watch.Elapsed.TotalSeconds -lt $Timeout)

    return $false
}

Import-FlaUIAssemblies -ErrorAction SilentlyContinue

Export-ModuleMember -Function @(
    'Import-FlaUIAssemblies',
    'Start-GuiApplication',
    'Stop-GuiApplication',
    'Find-UIElement',
    'Assert-UIElementExists',
    'Invoke-UIClick',
    'Wait-UIElementGone',
    'Save-UIScreenshot'
)
