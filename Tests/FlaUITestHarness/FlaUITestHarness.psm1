<#
 ===============================================================================
 Module: FlaUITestHarness.psm1
 Author: Tony Tran, ISSO, GA-ASI
 Version: 1.0.0
 Date: 2026-03-17
 ===============================================================================

 .SYNOPSIS
     PowerShell wrapper around FlaUI .NET assemblies for automated GUI testing
     of WPF applications compiled with PS2EXE.

 .DESCRIPTION
     Provides high-level cmdlets for launching GUI applications, finding UI
     elements by AutomationId or Name, clicking, typing, reading text, and
     taking screenshots. Built on FlaUI.UIA3 (UI Automation 3) which provides
     native WPF element tree access.

 .PREREQUISITES
     - Windows (UI Automation is Windows-only)
     - FlaUI NuGet packages ( FlaUI.UIA3, FlaUI.Core )
       Install via: .\Tests\FlaUITestHarness\Install-FlaUI.ps1
     - Pester 5+ (for running tests)

 .EXAMPLE
     Import-Module .\Tests\FlaUITestHarness\FlaUITestHarness.psm1 -Force

     $ctx = Start-GuiApplication -Path "C:\app\MyApp.exe" -Timeout 30
     Invoke-UIClick -AppContext $ctx -AutomationId "SaveButton"
     $text = Get-UIText -AppContext $ctx -AutomationId "StatusLabel"
     Stop-GuiApplication -AppContext $ctx
#>

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# Bootstrap: load FlaUI .NET assemblies from the packages directory
# ---------------------------------------------------------------------------

$script:ModuleRoot = $PSScriptRoot
$script:FlaUILoaded = $false
$script:AppContext = $null

function Load-FlaUIAssemblies {
    <#
    .SYNOPSIS
        Loads FlaUI .NET assemblies from the packages directory.
    #>
    if ($script:FlaUILoaded) { return $true }

    # Search for assemblies in standard NuGet layout
    $searchPaths = @(
        (Join-Path $script:ModuleRoot "packages")
        (Join-Path (Split-Path $script:ModuleRoot -Parent) "packages")
    )

    foreach ($basePath in $searchPaths) {
        if (-not (Test-Path $basePath)) { continue }

        $uia3Dir = Get-ChildItem -Path $basePath -Directory -Filter "FlaUI.UIA3.*" -ErrorAction SilentlyContinue | Select-Object -First 1
        $coreDir = Get-ChildItem -Path $basePath -Directory -Filter "FlaUI.Core.*" -ErrorAction SilentlyContinue | Select-Object -First 1
        $interopDir = Get-ChildItem -Path $basePath -Directory -Filter "Interop.UIAutomationClient.*" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($uia3Dir -and $coreDir) {
            try {
                $uia3Lib = Join-Path $uia3Dir.FullName "lib\net48\FlaUI.UIA3.dll"
                $coreLib = Join-Path $coreDir.FullName "lib\net48\FlaUI.Core.dll"
                $interopLib = Join-Path $interopDir.FullName "lib\netstandard2.0\Interop.UIAutomationClient.dll"
                if (-not (Test-Path $interopLib)) {
                    $interopLib = Join-Path $interopDir.FullName "lib\net48\Interop.UIAutomationClient.dll"
                }

                if ((Test-Path $uia3Lib) -and (Test-Path $coreLib)) {
                    Add-Type -Path $coreLib -ErrorAction Stop
                    if (Test-Path $interopLib) {
                        Add-Type -Path $interopLib -ErrorAction Stop
                    }
                    Add-Type -Path $uia3Lib -ErrorAction Stop
                    $script:FlaUILoaded = $true
                    $script:FlaUIPackagePath = $basePath
                    return $true
                }
            }
            catch {
                Write-Warning "Failed to load FlaUI from $basePath : $($_.Exception.Message)"
            }
        }
    }

    # Fallback: try loading by name if already in GAC or AppDomain
    try {
        Add-Type -AssemblyName FlaUI.Core -ErrorAction Stop 2>$null
        Add-Type -AssemblyName FlaUI.UIA3 -ErrorAction Stop 2>$null
        $script:FlaUILoaded = $true
        return $true
    }
    catch {
        # Not available
    }

    return $false
}

# Try to load on import
Load-FlaUIAssemblies | Out-Null

# ---------------------------------------------------------------------------
# Application lifecycle
# ---------------------------------------------------------------------------

function Start-GuiApplication {
    <#
    .SYNOPSIS
        Launches a GUI application and returns a test context object.

    .DESCRIPTION
        Starts the specified executable using FlaUI's Application.Launch,
        attaches UIA3 automation, and waits for the main window to appear.

    .PARAMETER Path
        Full path to the executable file.

    .PARAMETER Arguments
        Optional command-line arguments to pass to the executable.

    .PARAMETER Timeout
        Seconds to wait for the main window to appear. Default is 30.

    .OUTPUTS
        PSCustomObject with:
            ProcessId     - Process ID of the launched application
            MainWindow    - FlaUI Window automation element
            Automation    - UIA3Automation instance (keep for element searches)

    .EXAMPLE
        $ctx = Start-GuiApplication -Path "C:\app\MyApp.exe" -Timeout 45
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Arguments = '',

        [int]$Timeout = 30
    )

    if (-not (Test-Path $Path)) {
        throw "Application not found: $Path"
    }

    if (-not $script:FlaUILoaded) {
        Load-FlaUIAssemblies | Out-Null
    }
    if (-not $script:FlaUILoaded) {
        throw "FlaUI assemblies not available. Run .\Tests\FlaUITestHarness\Install-FlaUI.ps1 first."
    }

    Write-Verbose "Launching: $Path $Arguments"

    # Launch the application
    $app = [FlaUI.Core.Application]::Launch($Path, $Arguments)
    Start-Sleep -Seconds 1  # Give process a moment to start

    $automation = [FlaUI.UIA3.UIA3Automation]::new()

    # Wait for main window
    $window = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        try {
            $window = $app.GetMainWindow($automation)
            if ($null -ne $window) {
                Write-Verbose "Main window found after $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
                break
            }
        }
        catch {
            # Window not ready yet
        }
        Start-Sleep -Milliseconds 500
    }

    if ($null -eq $window) {
        # Cleanup
        try { $automation.Dispose() } catch { }
        try {
            $proc = Get-Process -Id $app.ProcessId -ErrorAction SilentlyContinue
            if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue }
        } catch { }
        throw "Main window did not appear within ${Timeout}s for: $Path"
    }

    $script:AppContext = [PSCustomObject]@{
        ProcessId  = $app.ProcessId
        MainWindow = $window
        Automation = $automation
        _App       = $app
    }

    # Store globally for parameterless cmdlets
    $script:CurrentAutomation = $automation

    $script:AppContext
}

function Stop-GuiApplication {
    <#
    .SYNOPSIS
        Stops a running GUI application launched by Start-GuiApplication.

    .PARAMETER AppContext
        The context object returned by Start-GuiApplication.
        If omitted, uses the last started application.

    .PARAMETER Force
        Kill the process if graceful close fails.

    .EXAMPLE
        Stop-GuiApplication -AppContext $ctx
        Stop-GuiApplication -Force
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,

        [switch]$Force
    )

    $ctx = if ($AppContext) { $AppContext } else { $script:AppContext }

    if ($null -eq $ctx) {
        Write-Warning "No application context to stop."
        return
    }

    try {
        if ($null -ne $ctx.MainWindow) {
            try {
                $ctx.MainWindow.Close()
                Start-Sleep -Seconds 2
            } catch { }
        }

        # Verify process is gone
        $proc = Get-Process -Id $ctx.ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $proc) {
            if ($Force) {
                $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            } else {
                Write-Warning "Process $($ctx.ProcessId) still running. Use -Force to kill."
            }
        }
    }
    finally {
        try { $ctx.Automation.Dispose() } catch { }
        $script:AppContext = $null
        $script:CurrentAutomation = $null
    }
}

function Get-GuiApplication {
    <#
    .SYNOPSIS
        Returns the current application context (last started app).
    #>
    [CmdletBinding()]
    param()

    $script:AppContext
}

# ---------------------------------------------------------------------------
# Element finding
# ---------------------------------------------------------------------------

function Find-UIElement {
    <#
    .SYNOPSIS
        Finds a UI element by AutomationId, Name, or control type.

    .DESCRIPTION
        Searches descendants of the main window (or a specified parent element)
        for an element matching the given criteria. Returns null if not found.

    .PARAMETER AppContext
        Application context from Start-GuiApplication. Uses last started app if omitted.

    .PARAMETER AutomationId
        Find by AutomationProperties.AutomationId.

    .PARAMETER Name
        Find by element Name (x:Name in WPF XAML).

    .PARAMETER ClassName
        Find by element class name (e.g., "Button", "TextBox").

    .PARAMETER ControlType
        Find by FlaUI ControlType (e.g., [FlaUI.Core.Definitions.ControlType]::Button).

    .PARAMETER Parent
        Parent element to search under. Defaults to MainWindow.

    .PARAMETER Timeout
        Seconds to wait for element to appear. Default is 10.

    .OUTPUTS
        FlaUI.Core.AutomationElements.AutomationElement (or null)
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,

        [string]$AutomationId,

        [string]$Name,

        [string]$ClassName,

        $ControlType,

        $Parent,

        [int]$Timeout = 10
    )

    $ctx = if ($AppContext) { $AppContext } else { $script:AppContext }
    if ($null -eq $ctx -or $null -eq $ctx.MainWindow) {
        throw "No active application. Call Start-GuiApplication first."
    }

    $searchRoot = if ($Parent) { $Parent } else { $ctx.MainWindow }

    # Build condition tree (use PS array — generic List<ConditionFactory> fails in PS 5.1)
    $conditions = @()
    $cf = [FlaUI.Core.Definitions.ConditionFactory]::new($ctx.Automation.ConditionFactory)

    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $conditions += $cf.ByAutomationId($AutomationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $conditions += $cf.ByName($Name)
    }
    if (-not [string]::IsNullOrWhiteSpace($ClassName)) {
        $conditions += $cf.ByClassName($ClassName)
    }
    if ($null -ne $ControlType) {
        $conditions += $cf.ByControlType($ControlType)
    }

    if ($conditions.Count -eq 0) {
        throw "Specify at least one search criterion: AutomationId, Name, ClassName, or ControlType."
    }

    # Combine conditions with AND
    $condition = $conditions[0]
    for ($i = 1; $i -lt $conditions.Count; $i++) {
        $condition = $condition.And($conditions[$i])
    }

    # Wait for element with timeout
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $element = $null

    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        try {
            $element = $searchRoot.FindFirstDescendant($condition)
            if ($null -ne $element) {
                Write-Verbose "Found element (AutomationId=$AutomationId, Name=$Name) in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
                return $element
            }
        }
        catch {
            # Element tree may be updating
        }
        Start-Sleep -Milliseconds 300
    }

    Write-Warning "Element not found (AutomationId=$AutomationId, Name=$Name) after ${Timeout}s"
    return $null
}

function Find-AllUIElements {
    <#
    .SYNOPSIS
        Finds all descendant elements matching the criteria.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,

        [string]$AutomationId,

        [string]$Name,

        [string]$ClassName,

        $ControlType,

        $Parent
    )

    $ctx = if ($AppContext) { $AppContext } else { $script:AppContext }
    if ($null -eq $ctx) { throw "No active application." }

    $searchRoot = if ($Parent) { $Parent } else { $ctx.MainWindow }
    $cf = [FlaUI.Core.Definitions.ConditionFactory]::new($ctx.Automation.ConditionFactory)

    $conditions = @()  # PS array (generic List<object> fails in PS 5.1)
    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $conditions += $cf.ByAutomationId($AutomationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $conditions += $cf.ByName($Name)
    }
    if (-not [string]::IsNullOrWhiteSpace($ClassName)) {
        $conditions += $cf.ByClassName($ClassName)
    }
    if ($null -ne $ControlType) {
        $conditions += $cf.ByControlType($ControlType)
    }

    if ($conditions.Count -eq 0) { throw "Specify at least one search criterion." }

    $condition = $conditions[0]
    for ($i = 1; $i -lt $conditions.Count; $i++) {
        $condition = $condition.And($conditions[$i])
    }

    $searchRoot.FindAllDescendants($condition)
}

# ---------------------------------------------------------------------------
# Element interaction
# ---------------------------------------------------------------------------

function Invoke-UIClick {
    <#
    .SYNOPSIS
        Clicks a UI element found by AutomationId or Name.

    .PARAMETER AppContext
        Application context. Uses last started app if omitted.

    .PARAMETER AutomationId
        AutomationId of the element to click.

    .PARAMETER Name
        Name of the element to click.

    .PARAMETER Element
        Direct FlaUI element reference (skips finding).

    .PARAMETER Delay
        Milliseconds to wait after click. Default 300.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        $Element,
        [int]$Delay = 300
    )

    $el = if ($Element) {
        $Element
    } else {
        Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout 5
    }

    if ($null -eq $el) {
        throw "Element not found (AutomationId=$AutomationId, Name=$Name)"
    }

    try {
        $btn = $el.AsButton()
        $btn.Invoke()
        Write-Verbose "Clicked: AutomationId=$AutomationId Name=$Name"
    }
    catch {
        # Fallback: try pattern invoke
        try {
            $invokePattern = $el.Patterns.Invoke
            if ($null -ne $invokePattern) {
                $invokePattern.Invoke.Invoke()
            } else {
                throw $_
            }
        }
        catch {
            throw "Failed to click element (AutomationId=$AutomationId): $($_.Exception.Message)"
        }
    }

    if ($Delay -gt 0) {
        Start-Sleep -Milliseconds $Delay
    }
}

function Get-UIText {
    <#
    .SYNOPSIS
        Gets the text content of a UI element.

    .PARAMETER AutomationId
    .PARAMETER Name
    .PARAMETER Element
    .PARAMETER AppContext

    .OUTPUTS
        String — the element's text/value content.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        $Element
    )

    $el = if ($Element) {
        $Element
    } else {
        Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout 5
    }

    if ($null -eq $el) {
        throw "Element not found (AutomationId=$AutomationId, Name=$Name)"
    }

    try {
        # Try ValuePattern (for TextBoxes)
        $valPattern = $el.Patterns.Value
        if ($null -ne $valPattern -and $null -ne $valPattern.Value) {
            return $valPattern.Value.Value
        }

        # Try TextPattern (for TextBlocks, Labels)
        $txtPattern = $el.Patterns.Text
        if ($null -ne $txtPattern -and $null -ne $txtPattern.Text) {
            return $txtPattern.Text.Document.GetText(-1).TrimEnd("`r`n")
        }

        # Fallback: Name property often contains the text
        return $el.Name
    }
    catch {
        # Final fallback
        return $el.Name
    }
}

function Set-UIText {
    <#
    .SYNOPSIS
        Sets the text of a UI element (TextBox).

    .PARAMETER Text
        Text to set. If -Clear is specified, the field is cleared first.

    .PARAMETER Clear
        Clear existing text before setting new text.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [Parameter(Mandatory)]
        [string]$AutomationId,
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Text,
        [string]$Element,
        [switch]$Clear
    )

    $el = if ($Element) {
        $Element
    } else {
        Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout 5
    }

    if ($null -eq $el) {
        throw "Element not found (AutomationId=$AutomationId, Name=$Name)"
    }

    try {
        $valPattern = $el.Patterns.Value
        if ($null -ne $valPattern -and $null -ne $valPattern.Value) {
            if ($Clear) {
                $valPattern.Value.SetValue("")
                Start-Sleep -Milliseconds 100
            }
            $valPattern.Value.SetValue($Text)
            Write-Verbose "Set text on AutomationId=$AutomationId to: $Text"
        }
        else {
            # Fallback: focus + keyboard input
            $el.Focus()
            Start-Sleep -Milliseconds 100
            if ($Clear) {
                [System.Windows.Forms.SendKeys]::SendWait("^a")
                Start-Sleep -Milliseconds 50
                [System.Windows.Forms.SendKeys]::SendWait("{DEL}")
                Start-Sleep -Milliseconds 100
            }
            [System.Windows.Forms.SendKeys]::SendWait($Text)
            Write-Verbose "Set text via SendKeys on AutomationId=$AutomationId"
        }
    }
    catch {
        throw "Failed to set text on AutomationId=$AutomationId : $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Assertions (Pester-friendly)
# ---------------------------------------------------------------------------

function Assert-UIElementExists {
    <#
    .SYNOPSIS
        Asserts that a UI element exists. Throws if not found within timeout.

    .OUTPUTS
        The found element (for chaining).
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [string]$ClassName,
        $ControlType,
        [int]$Timeout = 10
    )

    $el = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name `
        -ClassName $ClassName -ControlType $ControlType -Timeout $Timeout

    if ($null -eq $el) {
        throw "ASSERT FAILED: Element not found (AutomationId=$AutomationId, Name=$Name, ClassName=$ClassName) within ${Timeout}s"
    }

    $el
}

function Assert-UIElementEnabled {
    <#
    .SYNOPSIS
        Asserts that a UI element is enabled (not disabled/greyed out).
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [Parameter(Mandatory)]
        [string]$AutomationId,
        [string]$Name,
        [int]$Timeout = 10
    )

    $el = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout $Timeout

    if ($null -eq $el) {
        throw "ASSERT FAILED: Element not found (AutomationId=$AutomationId)"
    }

    if (-not $el.IsEnabled) {
        throw "ASSERT FAILED: Element (AutomationId=$AutomationId) is disabled"
    }

    $el
}

function Assert-UIElementDisabled {
    <#
    .SYNOPSIS
        Asserts that a UI element is disabled.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [Parameter(Mandatory)]
        [string]$AutomationId,
        [string]$Name,
        [int]$Timeout = 10
    )

    $el = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout $Timeout

    if ($null -eq $el) {
        throw "ASSERT FAILED: Element not found (AutomationId=$AutomationId)"
    }

    if ($el.IsEnabled) {
        throw "ASSERT FAILED: Element (AutomationId=$AutomationId) is enabled (expected disabled)"
    }

    $el
}

function Assert-UIElementVisible {
    <#
    .SYNOPSIS
        Asserts that a UI element is visible (not offscreen, not collapsed).
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [Parameter(Mandatory)]
        [string]$AutomationId,
        [string]$Name,
        [int]$Timeout = 10
    )

    $el = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout $Timeout

    if ($null -eq $el) {
        throw "ASSERT FAILED: Element not found (AutomationId=$AutomationId)"
    }

    if ($el.IsOffscreen) {
        throw "ASSERT FAILED: Element (AutomationId=$AutomationId) is offscreen"
    }

    $el
}

function Assert-UIText {
    <#
    .SYNOPSIS
        Asserts that a UI element's text matches expected value.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [Parameter(Mandatory)]
        [string]$AutomationId,
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$ExpectedText,
        [int]$Timeout = 10
    )

    $actual = Get-UIText -AppContext $AppContext -AutomationId $AutomationId -Name $Name

    if ($actual -ne $ExpectedText) {
        throw "ASSERT FAILED: Element (AutomationId=$AutomationId) text mismatch. Expected: '$ExpectedText', Actual: '$actual'"
    }

    $actual
}

# ---------------------------------------------------------------------------
# Wait helpers
# ---------------------------------------------------------------------------

function Wait-UIElement {
    <#
    .SYNOPSIS
        Waits for a UI element to appear. Returns the element when found.

    .OUTPUTS
        The found automation element.

    .EXAMPLE
        Wait-UIElement -AutomationId "DashboardPanel" -Timeout 15
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [string]$ClassName,
        [int]$Timeout = 15
    )

    Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name `
        -ClassName $ClassName -Timeout $Timeout
}

function Wait-UIElementGone {
    <#
    .SYNOPSIS
        Waits for a UI element to disappear from the tree.

    .OUTPUTS
        $true if element disappeared, $false if still present after timeout.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [int]$Timeout = 15
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        $el = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout 1
        if ($null -eq $el) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    return $false
}

# ---------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------

function Save-UIScreenshot {
    <#
    .SYNOPSIS
        Captures a screenshot of the GUI application window.

    .PARAMETER Path
        Output file path. Supports .png, .jpg, .bmp.

    .PARAMETER AppContext
        Application context. Uses last started app if omitted.

    .OUTPUTS
        Full path to the saved screenshot file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [PSCustomObject]$AppContext
    )

    $ctx = if ($AppContext) { $AppContext } else { $script:AppContext }
    if ($null -eq $ctx -or $null -eq $ctx.MainWindow) {
        Write-Warning "No active application window to screenshot."
        return $null
    }

    try {
        # Ensure parent directory exists
        $dir = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }

        $bounds = $ctx.MainWindow.BoundingRectangle
        $bitmap = [System.Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen(
            [System.Drawing.Point]::new([int]$bounds.X, [int]$bounds.Y),
            [System.Drawing.Point]::Empty,
            [System.Drawing.Size]::new([int]$bounds.Width, [int]$bounds.Height)
        )

        # Default to PNG if no extension
        $ext = [System.IO.Path]::GetExtension($Path)
        if ([string]::IsNullOrWhiteSpace($ext)) {
            $Path = "$Path.png"
        }

        $format = switch ($ext.ToLower()) {
            '.jpg'  { [System.Drawing.Imaging.ImageFormat]::Jpeg }
            '.bmp'  { [System.Drawing.Imaging.ImageFormat]::Bmp }
            default { [System.Drawing.Imaging.ImageFormat]::Png }
        }

        $bitmap.Save($Path, $format)

        Write-Verbose "Screenshot saved: $Path"
        $Path
    }
    catch {
        Write-Warning "Failed to capture screenshot: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap)  { $bitmap.Dispose()  }
    }
}

# ---------------------------------------------------------------------------
# Element introspection (debugging)
# ---------------------------------------------------------------------------

function Get-UIElementInfo {
    <#
    .SYNOPSIS
        Returns diagnostic information about a UI element (for debugging).

    .OUTPUTS
        PSCustomObject with Name, AutomationId, ClassName, ControlType, IsEnabled, IsOffscreen, BoundingRectangle.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [string]$AutomationId,
        [string]$Name,
        [int]$Timeout = 5
    )

    $el = Find-UIElement -AppContext $AppContext -AutomationId $AutomationId -Name $Name -Timeout $Timeout

    if ($null -eq $el) {
        return $null
    }

    [PSCustomObject]@{
        Name              = $el.Name
        AutomationId      = if ($el.Properties.AutomationId.IsSupported) { $el.Properties.AutomationId.Value } else { '' }
        ClassName         = if ($el.Properties.ClassName.IsSupported) { $el.Properties.ClassName.Value } else { '' }
        ControlType       = $el.ControlType.ToString()
        IsEnabled         = $el.IsEnabled
        IsOffscreen       = $el.IsOffscreen
        BoundingRectangle = "$($el.BoundingRectangle)"
    }
}

function Get-UIElementTree {
    <#
    .SYNOPSIS
        Dumps the UI element tree from the main window (for debugging test failures).
        Limits output to first $MaxDepth levels and $MaxChildren per node.

    .PARAMETER MaxDepth
        Maximum tree depth. Default 3.

    .PARAMETER MaxChildren
        Maximum children per node to display. Default 20.

    .OUTPUTS
        String array of tree lines.
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject]$AppContext,
        [int]$MaxDepth = 3,
        [int]$MaxChildren = 20
    )

    $ctx = if ($AppContext) { $AppContext } else { $script:AppContext }
    if ($null -eq $ctx -or $null -eq $ctx.MainWindow) { return @() }

    $lines = @()  # PS array (generic List<string> fails in PS 5.1)

    function Walk($el, $depth) {
        if ($depth -gt $MaxDepth) { return }

        $indent = "  " * $depth
        $aid = if ($el.Properties.AutomationId.IsSupported) { $el.Properties.AutomationId.Value } else { '' }
        $name = $el.Name
        $type = $el.ControlType.ToString()
        $class = if ($el.Properties.ClassName.IsSupported) { $el.Properties.ClassName.Value } else { '' }
        $enabled = $(if ($el.IsEnabled) { "" } else { " [DISABLED]" })
        $offscreen = $(if ($el.IsOffscreen) { " [OFFSCREEN]" } else { "" })
        $label = $type
        if ($aid) { $label += " #$aid" }
        if ($name) { $label += " `"$name`"" }
        if ($class) { $label += " <$class>" }
        $label += "$enabled$offscreen"

        $lines += "$indent$label"

        $children = $el.FindAllDescendants()
        $count = 0
        foreach ($child in $children) {
            if ($count -ge $MaxChildren) {
                $remaining = $children.Count - $MaxChildren
                if ($remaining -gt 0) {
                    $lines += "$indent  ... ($remaining more)"
                }
                break
            }
            Walk $child ($depth + 1)
            $count++
        }
    }

    Walk $ctx.MainWindow 0
    $lines
}

# ---------------------------------------------------------------------------
# Keyboard
# ---------------------------------------------------------------------------

function Send-UIKeys {
    <#
    .SYNOPSIS
        Sends keystrokes to the active window.

    .PARAMETER Keys
        Key sequence using SendKeys syntax (e.g., "{ESC}", "^a", "%F4").

    .PARAMETER Delay
        Milliseconds after sending keys. Default 200.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Keys,
        [int]$Delay = 200
    )

    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    if ($Delay -gt 0) {
        Start-Sleep -Milliseconds $Delay
    }
}

# ---------------------------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Start-GuiApplication',
    'Stop-GuiApplication',
    'Get-GuiApplication',
    'Find-UIElement',
    'Find-AllUIElements',
    'Invoke-UIClick',
    'Get-UIText',
    'Set-UIText',
    'Assert-UIElementExists',
    'Assert-UIElementEnabled',
    'Assert-UIElementDisabled',
    'Assert-UIElementVisible',
    'Assert-UIText',
    'Wait-UIElement',
    'Wait-UIElementGone',
    'Save-UIScreenshot',
    'Get-UIElementInfo',
    'Get-UIElementTree',
    'Send-UIKeys'
)
