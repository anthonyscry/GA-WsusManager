<#
===============================================================================
Module: WsusDialogs.psm1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-20
===============================================================================

.SYNOPSIS
    Dialog factory module for WSUS Manager WPF GUI.

.DESCRIPTION
    Provides reusable factory functions for creating consistently styled WPF
    dialog windows and common UI controls. All dialogs use the GA dark theme
    matching the main WsusManagementGui.ps1 application.

    Color palette:
        Background (dark)  : #0D1117
        Card/input bg      : #21262D
        Primary text       : #E6EDF3
        Secondary text     : #8B949E
        Blue accent        : #58A6FF
        Border             : #30363D
#>

#Requires -Version 5.1

# WPF assemblies are only available on Windows. Guard the Add-Type so the module
# can be imported on other platforms (e.g. for syntax/linting checks) without error.
if ($PSVersionTable.PSEdition -eq 'Desktop' -or $env:OS -eq 'Windows_NT') {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction SilentlyContinue
}

# ===========================
# PRIVATE HELPERS
# ===========================

function ConvertTo-Brush {
    param([string]$Hex)
    [System.Windows.Media.BrushConverter]::new().ConvertFrom($Hex)
}

function ConvertTo-Thickness {
    param([string]$Margin)
    $parts = $Margin -split ','
    switch ($parts.Count) {
        1 { [System.Windows.Thickness]::new([double]$parts[0]) }
        2 { [System.Windows.Thickness]::new([double]$parts[0], [double]$parts[1], [double]$parts[0], [double]$parts[1]) }
        4 { [System.Windows.Thickness]::new([double]$parts[0], [double]$parts[1], [double]$parts[2], [double]$parts[3]) }
        default { [System.Windows.Thickness]::new(0) }
    }
}

# ===========================
# PUBLIC FUNCTIONS
# ===========================

function New-WsusDialog {
    <#
    .SYNOPSIS
        Creates a standard dark-themed WPF dialog window shell.

    .DESCRIPTION
        Builds a configured System.Windows.Window with the GA dark theme applied,
        ESC-to-close behaviour, and a StackPanel as the root content area.
        The window is NOT shown by this function  - the caller must invoke
        ShowDialog() when ready. An optional AutomationId can be set on the
        window for UI automation testing.

    .PARAMETER Title
        Text displayed in the dialog title bar.

    .PARAMETER Width
        Width of the dialog window in pixels. Default is 480.

    .PARAMETER Height
        Height of the dialog window in pixels. Default is 360.

    .PARAMETER Owner
        Optional parent System.Windows.Window. When supplied, the dialog is
        centred over the owner window; otherwise it is centred on screen.

    .PARAMETER AutomationId
        Optional automation identifier set via AutomationProperties.AutomationId
        for UI automation testing. When omitted, no AutomationId is set.

    .OUTPUTS
        PSCustomObject with:
            Window       - the System.Windows.Window object
            ContentPanel - the StackPanel (add child controls here)

    .EXAMPLE
        $d = New-WsusDialog -Title "Confirm Action" -Width 480 -Height 240 -Owner $mainWindow
        $d.ContentPanel.Children.Add((New-WsusDialogLabel -Text "Are you sure?"))
        $d.Window.ShowDialog()
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [int]$Width = 480,

        [int]$Height = 360,

        [System.Windows.Window]$Owner,

        [string]$AutomationId = ''
    )

    $window = [System.Windows.Window]::new()
    $window.Title = $Title
    $window.Width = $Width
    $window.Height = $Height
    $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $window.Background = ConvertTo-Brush '#0D1117'
    $window.Foreground = ConvertTo-Brush '#E6EDF3'

    if ($null -ne $Owner) {
        $window.Owner = $Owner
        $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    }
    else {
        $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }

    $window.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() }
    })

    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $window.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, $AutomationId)
    }

    $contentPanel = [System.Windows.Controls.StackPanel]::new()
    $contentPanel.Margin = ConvertTo-Thickness '20'
    $window.Content = $contentPanel

    [PSCustomObject]@{
        Window       = $window
        ContentPanel = $contentPanel
    }
}

function New-WsusFolderBrowser {
    <#
    .SYNOPSIS
        Creates a labelled folder-browse row (TextBox + Browse button).

    .DESCRIPTION
        Returns a DockPanel containing a right-docked Browse button and a
        fill TextBox. Clicking Browse opens a WinForms FolderBrowserDialog and
        populates the TextBox with the selected path. An optional AutomationId
        can be set on the DockPanel for UI automation testing.

    .PARAMETER LabelText
        Text for the label displayed above the browse row. Default is "Path:".

    .PARAMETER InitialPath
        Optional initial value for the TextBox.

    .PARAMETER Owner
        Optional parent window handle used to centre the FolderBrowserDialog.

    .PARAMETER AutomationId
        Optional automation identifier set via AutomationProperties.AutomationId
        on the DockPanel for UI automation testing. When omitted, no
        AutomationId is set.

    .OUTPUTS
        PSCustomObject with:
            Panel   - the DockPanel (add to a parent container)
            TextBox - the System.Windows.Controls.TextBox (read .Text for value)
            Label   - the TextBlock label (hide or modify as needed)

    .EXAMPLE
        $fb = New-WsusFolderBrowser -LabelText "Export Path:" -InitialPath "C:\WSUS"
        $dialog.ContentPanel.Children.Add($fb.Label)
        $dialog.ContentPanel.Children.Add($fb.Panel)
        # After ShowDialog: $selectedPath = $fb.TextBox.Text
    #>
    [CmdletBinding()]
    param(
        [string]$LabelText = 'Path:',

        [string]$InitialPath = '',

        [System.Windows.Window]$Owner,

        [string]$AutomationId = ''
    )

    $label = New-WsusDialogLabel -Text $LabelText -IsSecondary $true

    $textBox = New-WsusDialogTextBox -InitialText $InitialPath

    $browseBtn = New-WsusDialogButton -Text 'Browse'
    $browseBtn.Padding = ConvertTo-Thickness '10,4'
    [System.Windows.Controls.DockPanel]::SetDock($browseBtn, [System.Windows.Controls.Dock]::Right)

    $dockPanel = [System.Windows.Controls.DockPanel]::new()
    $dockPanel.LastChildFill = $true
    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $dockPanel.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, $AutomationId)
    }
    $textBox.Margin = ConvertTo-Thickness '0,0,8,0'

    $dockPanel.Children.Add($browseBtn) | Out-Null
    $dockPanel.Children.Add($textBox) | Out-Null

    # Capture for closure
    $capturedTextBox = $textBox
    $capturedOwner = $Owner

    $browseBtn.Add_Click({
        $fbd = [System.Windows.Forms.FolderBrowserDialog]::new()
        try {
            $fbd.Description = 'Select a folder'
            if (-not [string]::IsNullOrWhiteSpace($capturedTextBox.Text)) {
                $fbd.SelectedPath = $capturedTextBox.Text
            }
            $handle = if ($null -ne $capturedOwner) {
                [System.Windows.Interop.WindowInteropHelper]::new($capturedOwner).Handle
            }
            else {
                [System.IntPtr]::Zero
            }
            $hwndWrapper = [System.Windows.Forms.NativeWindow]::new()
            if ($handle -ne [System.IntPtr]::Zero) {
                $hwndWrapper.AssignHandle($handle)
            }
            $result = $fbd.ShowDialog($hwndWrapper)
            if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                $capturedTextBox.Text = $fbd.SelectedPath
            }
            if ($handle -ne [System.IntPtr]::Zero) {
                $hwndWrapper.ReleaseHandle()
            }
        }
        finally {
            $fbd.Dispose()
        }
    }.GetNewClosure())

    [PSCustomObject]@{
        Panel   = $dockPanel
        TextBox = $textBox
        Label   = $label
    }
}

function New-WsusDialogLabel {
    <#
    .SYNOPSIS
        Creates a styled TextBlock label for use inside WSUS dialogs.

    .PARAMETER Text
        The label content string.

    .PARAMETER IsSecondary
        When $true, applies the secondary (muted) text colour. Default $false.

    .PARAMETER Margin
        Thickness string (CSS-shorthand notation). Default "0,0,0,6".

    .PARAMETER AutomationId
        Optional automation identifier set via AutomationProperties.AutomationId
        for UI automation testing. When omitted, no AutomationId is set.

    .OUTPUTS
        System.Windows.Controls.TextBlock

    .EXAMPLE
        $lbl = New-WsusDialogLabel -Text "Export path:" -IsSecondary $true
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [bool]$IsSecondary = $false,

        [string]$Margin = '0,0,0,6',

        [string]$AutomationId = ''
    )

    $tb = [System.Windows.Controls.TextBlock]::new()
    $tb.Text = $Text
    $tb.Foreground = if ($IsSecondary) { ConvertTo-Brush '#8B949E' } else { ConvertTo-Brush '#E6EDF3' }
    $tb.Margin = ConvertTo-Thickness $Margin
    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $tb.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, $AutomationId)
    }
    $tb
}

function New-WsusDialogButton {
    <#
    .SYNOPSIS
        Creates a styled Button for use inside WSUS dialogs.

    .PARAMETER Text
        The button label.

    .PARAMETER IsPrimary
        When $true, applies the blue accent background. Default $false (dark bg).

    .PARAMETER Margin
        Thickness string. Default "0".

    .PARAMETER AutomationId
        Optional automation identifier set via AutomationProperties.AutomationId
        for UI automation testing. When omitted, no AutomationId is set.

    .OUTPUTS
        System.Windows.Controls.Button

    .EXAMPLE
        $okBtn   = New-WsusDialogButton -Text "OK"     -IsPrimary $true
        $canBtn  = New-WsusDialogButton -Text "Cancel" -Margin "8,0,0,0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [bool]$IsPrimary = $false,

        [string]$Margin = '0',

        [string]$AutomationId = ''
    )

    $btn = [System.Windows.Controls.Button]::new()
    $btn.Content = $Text
    $btn.Padding = ConvertTo-Thickness '14,6'
    $btn.Margin = ConvertTo-Thickness $Margin
    $btn.BorderThickness = ConvertTo-Thickness '0'
    $btn.Cursor = [System.Windows.Input.Cursors]::Hand

    if ($IsPrimary) {
        $btn.Background = ConvertTo-Brush '#58A6FF'
        $btn.Foreground = ConvertTo-Brush '#0D1117'
    }
    else {
        $btn.Background = ConvertTo-Brush '#21262D'
        $btn.Foreground = ConvertTo-Brush '#E6EDF3'
    }

    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $btn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, $AutomationId)
    }
    $btn
}

function New-WsusDialogTextBox {
    <#
    .SYNOPSIS
        Creates a dark-styled TextBox for use inside WSUS dialogs.

    .PARAMETER InitialText
        Optional starting text value. Default "".

    .PARAMETER Padding
        Internal padding. Default "6,4".

    .PARAMETER AutomationId
        Optional automation identifier set via AutomationProperties.AutomationId
        for UI automation testing. When omitted, no AutomationId is set.

    .OUTPUTS
        System.Windows.Controls.TextBox

    .EXAMPLE
        $tb = New-WsusDialogTextBox -InitialText "C:\WSUS"
    #>
    [CmdletBinding()]
    param(
        [string]$InitialText = '',

        [string]$Padding = '6,4',

        [string]$AutomationId = ''
    )

    $tb = [System.Windows.Controls.TextBox]::new()
    $tb.Text = $InitialText
    $tb.Background = ConvertTo-Brush '#21262D'
    $tb.Foreground = ConvertTo-Brush '#E6EDF3'
    $tb.CaretBrush = ConvertTo-Brush '#E6EDF3'
    $tb.BorderBrush = ConvertTo-Brush '#30363D'
    $tb.BorderThickness = ConvertTo-Thickness '1'
    $tb.Padding = ConvertTo-Thickness $Padding
    if (-not [string]::IsNullOrWhiteSpace($AutomationId)) {
        $tb.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, $AutomationId)
    }
    $tb
}

# ===========================
# EXPORTS
# ===========================

Export-ModuleMember -Function @(
    'New-WsusDialog',
    'New-WsusFolderBrowser',
    'New-WsusDialogLabel',
    'New-WsusDialogButton',
    'New-WsusDialogTextBox'
)
