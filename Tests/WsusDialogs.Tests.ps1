#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusDialogs.psm1

.DESCRIPTION
    Unit tests for the WsusDialogs dialog-factory module.

    Tests that construct WPF objects require Windows + STA thread. Those tests
    are skipped automatically when running on Linux/macOS (e.g. CI linting
    runners) via the $script:WpfAvailable guard.

    On Windows, each WPF construction test block spins up a dedicated STA
    runspace, imports the module inside that runspace, and runs assertions
    against the returned objects without ever calling ShowDialog.
#>

BeforeDiscovery {
    # Variables set here are available for -Skip conditions at discovery time
    $script:ModulePath    = Join-Path $PSScriptRoot '..\Modules\WsusDialogs.psm1'
    $script:ModuleExists  = Test-Path $script:ModulePath

    # WPF is only available on Windows — skip WPF construction tests on Linux/macOS
    $script:WpfAvailable  = ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') -and $script:ModuleExists
}

BeforeAll {
    # Redefine for the run phase (BeforeDiscovery vars don't persist to It blocks)
    $script:ModulePath   = Join-Path $PSScriptRoot '..\Modules\WsusDialogs.psm1'
    $script:ModuleExists = Test-Path $script:ModulePath
    $script:WpfAvailable = ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') -and $script:ModuleExists

    # ---------------------------------------------------------------------------
    # Helper: run a scriptblock in a fresh STA runspace and return the result.
    # The module (and WPF assemblies) are loaded inside the runspace.
    # ---------------------------------------------------------------------------
    function script:Invoke-InSta {
        param(
            [Parameter(Mandatory)]
            [scriptblock]$ScriptBlock
        )

        $modPath = $script:ModulePath
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions  = 'ReuseThread'
        $rs.Open()

        try {
            $ps = [powershell]::Create()
            $ps.Runspace = $rs

            $ps.AddScript({
                param($mp)
                Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction SilentlyContinue
                Import-Module $mp -Force -DisableNameChecking
            }).AddArgument($modPath) | Out-Null

            $ps.Invoke() | Out-Null
            if ($ps.HadErrors) {
                throw ($ps.Streams.Error | Select-Object -First 1).Exception
            }

            $ps.Commands.Clear()
            $ps.AddScript($ScriptBlock) | Out-Null

            $result = $ps.Invoke()
            if ($ps.HadErrors) {
                throw ($ps.Streams.Error | Select-Object -First 1).Exception
            }
            $result
        }
        finally {
            $rs.Close()
            $rs.Dispose()
        }
    }
}

# ---------------------------------------------------------------------------
# Module loading  (no WPF needed)
# ---------------------------------------------------------------------------
Describe 'WsusDialogs Module' -Skip:(-not $script:ModuleExists) {

    Context 'Module file' {
        It 'Module file exists' {
            $script:ModulePath | Should -Exist
        }
    }

    Context 'Exported functions' {
        BeforeAll {
            Import-Module $script:ModulePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
        }
        AfterAll {
            Remove-Module WsusDialogs -ErrorAction SilentlyContinue
        }

        It 'Exports New-WsusDialog' {
            Get-Command New-WsusDialog -Module WsusDialogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Exports New-WsusFolderBrowser' {
            Get-Command New-WsusFolderBrowser -Module WsusDialogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Exports New-WsusDialogLabel' {
            Get-Command New-WsusDialogLabel -Module WsusDialogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Exports New-WsusDialogButton' {
            Get-Command New-WsusDialogButton -Module WsusDialogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Exports New-WsusDialogTextBox' {
            Get-Command New-WsusDialogTextBox -Module WsusDialogs -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

# ---------------------------------------------------------------------------
# New-WsusDialog  (WPF required)
# ---------------------------------------------------------------------------
Describe 'New-WsusDialog' -Skip:(-not $script:ModuleExists) {

    Context 'Return type' -Skip:(-not $script:WpfAvailable) {
        It 'Returns a PSCustomObject' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'Test').GetType().Name }
            $result | Should -Be 'PSCustomObject'
        }

        It 'Has a Window property' {
            $result = Invoke-InSta -ScriptBlock { $null -ne (New-WsusDialog -Title 'Test').Window }
            $result | Should -Be $true
        }

        It 'Has a ContentPanel property' {
            $result = Invoke-InSta -ScriptBlock { $null -ne (New-WsusDialog -Title 'Test').ContentPanel }
            $result | Should -Be $true
        }

        It 'ContentPanel is a StackPanel' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'Test').ContentPanel.GetType().Name }
            $result | Should -Be 'StackPanel'
        }

        It 'Window.Content is the ContentPanel' {
            $result = Invoke-InSta -ScriptBlock {
                $d = New-WsusDialog -Title 'Test'
                [object]::ReferenceEquals($d.Window.Content, $d.ContentPanel)
            }
            $result | Should -Be $true
        }
    }

    Context 'Window properties - defaults' -Skip:(-not $script:WpfAvailable) {
        It 'Title is set correctly' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'My Dialog').Window.Title }
            $result | Should -Be 'My Dialog'
        }

        It 'Default Width is 480' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T').Window.Width }
            $result | Should -Be 480
        }

        It 'Default Height is 360' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T').Window.Height }
            $result | Should -Be 360
        }

        It 'ResizeMode is NoResize' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T').Window.ResizeMode.ToString() }
            $result | Should -Be 'NoResize'
        }

        It 'Background is #0D1117' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T').Window.Background.Color.ToString() }
            $result | Should -Be '#FF0D1117'
        }

        It 'Without Owner uses CenterScreen' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T').Window.WindowStartupLocation.ToString() }
            $result | Should -Be 'CenterScreen'
        }

        It 'ContentPanel has Margin of 20 on all sides' {
            $result = Invoke-InSta -ScriptBlock {
                $m = (New-WsusDialog -Title 'T').ContentPanel.Margin
                "$($m.Left),$($m.Top),$($m.Right),$($m.Bottom)"
            }
            $result | Should -Be '20,20,20,20'
        }
    }

    Context 'Window properties - custom size' -Skip:(-not $script:WpfAvailable) {
        It 'Respects custom Width' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T' -Width 600).Window.Width }
            $result | Should -Be 600
        }

        It 'Respects custom Height' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialog -Title 'T' -Height 500).Window.Height }
            $result | Should -Be 500
        }
    }

    Context 'Window with Owner' -Skip:(-not $script:WpfAvailable) {
        It 'Uses CenterOwner when Owner is provided' {
            $result = Invoke-InSta -ScriptBlock {
                $owner = [System.Windows.Window]::new()
                (New-WsusDialog -Title 'Child' -Owner $owner).Window.WindowStartupLocation.ToString()
            }
            $result | Should -Be 'CenterOwner'
        }

        It 'Owner property is assigned' {
            $result = Invoke-InSta -ScriptBlock {
                $owner = [System.Windows.Window]::new()
                $null -ne (New-WsusDialog -Title 'Child' -Owner $owner).Window.Owner
            }
            $result | Should -Be $true
        }
    }
}

# ---------------------------------------------------------------------------
# New-WsusFolderBrowser  (WPF required)
# ---------------------------------------------------------------------------
Describe 'New-WsusFolderBrowser' -Skip:(-not $script:ModuleExists) {

    Context 'Return type' -Skip:(-not $script:WpfAvailable) {
        It 'Returns a PSCustomObject' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).GetType().Name }
            $result | Should -Be 'PSCustomObject'
        }

        It 'Has a Panel property' {
            $result = Invoke-InSta -ScriptBlock { $null -ne (New-WsusFolderBrowser).Panel }
            $result | Should -Be $true
        }

        It 'Has a TextBox property' {
            $result = Invoke-InSta -ScriptBlock { $null -ne (New-WsusFolderBrowser).TextBox }
            $result | Should -Be $true
        }

        It 'Has a Label property' {
            $result = Invoke-InSta -ScriptBlock { $null -ne (New-WsusFolderBrowser).Label }
            $result | Should -Be $true
        }
    }

    Context 'Control types' -Skip:(-not $script:WpfAvailable) {
        It 'Panel is a DockPanel' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).Panel.GetType().Name }
            $result | Should -Be 'DockPanel'
        }

        It 'TextBox is a TextBox' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).TextBox.GetType().Name }
            $result | Should -Be 'TextBox'
        }

        It 'Label is a TextBlock' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).Label.GetType().Name }
            $result | Should -Be 'TextBlock'
        }
    }

    Context 'Default values' -Skip:(-not $script:WpfAvailable) {
        It 'Default label text is "Path:"' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).Label.Text }
            $result | Should -Be 'Path:'
        }

        It 'Default TextBox is empty' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).TextBox.Text }
            $result | Should -Be ''
        }

        It 'DockPanel has two children (button + textbox)' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).Panel.Children.Count }
            $result | Should -Be 2
        }
    }

    Context 'Custom values' -Skip:(-not $script:WpfAvailable) {
        It 'LabelText parameter sets label text' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser -LabelText 'Export Path:').Label.Text }
            $result | Should -Be 'Export Path:'
        }

        It 'InitialPath sets TextBox text' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser -InitialPath 'C:\WSUS').TextBox.Text }
            $result | Should -Be 'C:\WSUS'
        }
    }

    Context 'Browse button' -Skip:(-not $script:WpfAvailable) {
        It 'First child is the Browse button' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).Panel.Children[0].GetType().Name }
            $result | Should -Be 'Button'
        }

        It 'Browse button is docked Right' {
            $result = Invoke-InSta -ScriptBlock {
                $fb = New-WsusFolderBrowser
                [System.Windows.Controls.DockPanel]::GetDock($fb.Panel.Children[0]).ToString()
            }
            $result | Should -Be 'Right'
        }

        It 'Browse button has text "Browse"' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusFolderBrowser).Panel.Children[0].Content }
            $result | Should -Be 'Browse'
        }
    }
}

# ---------------------------------------------------------------------------
# New-WsusDialogLabel  (WPF required)
# ---------------------------------------------------------------------------
Describe 'New-WsusDialogLabel' -Skip:(-not $script:ModuleExists) {

    Context 'Primary label' -Skip:(-not $script:WpfAvailable) {
        It 'Returns a TextBlock' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogLabel -Text 'Hello').GetType().Name }
            $result | Should -Be 'TextBlock'
        }

        It 'Text is set correctly' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogLabel -Text 'My Label').Text }
            $result | Should -Be 'My Label'
        }

        It 'Primary colour is #E6EDF3' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogLabel -Text 'T').Foreground.Color.ToString() }
            $result | Should -Be '#FFE6EDF3'
        }

        It 'Default margin bottom is 6' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogLabel -Text 'T').Margin.Bottom }
            $result | Should -Be 6
        }
    }

    Context 'Secondary label' -Skip:(-not $script:WpfAvailable) {
        It 'Secondary colour is #8B949E' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogLabel -Text 'T' -IsSecondary $true).Foreground.Color.ToString() }
            $result | Should -Be '#FF8B949E'
        }
    }

    Context 'Custom margin' -Skip:(-not $script:WpfAvailable) {
        It 'Applies custom margin string' {
            $result = Invoke-InSta -ScriptBlock {
                $m = (New-WsusDialogLabel -Text 'T' -Margin '4,8,4,8').Margin
                "$($m.Left),$($m.Top),$($m.Right),$($m.Bottom)"
            }
            $result | Should -Be '4,8,4,8'
        }
    }
}

# ---------------------------------------------------------------------------
# New-WsusDialogButton  (WPF required)
# ---------------------------------------------------------------------------
Describe 'New-WsusDialogButton' -Skip:(-not $script:ModuleExists) {

    Context 'Control basics' -Skip:(-not $script:WpfAvailable) {
        It 'Returns a Button' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'OK').GetType().Name }
            $result | Should -Be 'Button'
        }

        It 'Content is set to Text parameter' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'Cancel').Content }
            $result | Should -Be 'Cancel'
        }

        It 'Has no border (BorderThickness 0)' {
            $result = Invoke-InSta -ScriptBlock {
                $bt = (New-WsusDialogButton -Text 'T').BorderThickness
                $bt.Left -eq 0 -and $bt.Top -eq 0 -and $bt.Right -eq 0 -and $bt.Bottom -eq 0
            }
            $result | Should -Be $true
        }
    }

    Context 'Secondary (non-primary) button' -Skip:(-not $script:WpfAvailable) {
        It 'Background is #21262D' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'T').Background.Color.ToString() }
            $result | Should -Be '#FF21262D'
        }

        It 'Foreground is #E6EDF3' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'T').Foreground.Color.ToString() }
            $result | Should -Be '#FFE6EDF3'
        }
    }

    Context 'Primary button' -Skip:(-not $script:WpfAvailable) {
        It 'Background is #58A6FF' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'T' -IsPrimary $true).Background.Color.ToString() }
            $result | Should -Be '#FF58A6FF'
        }

        It 'Foreground is #0D1117 (dark text on blue)' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'T' -IsPrimary $true).Foreground.Color.ToString() }
            $result | Should -Be '#FF0D1117'
        }
    }

    Context 'Custom margin' -Skip:(-not $script:WpfAvailable) {
        It 'Applies Margin parameter' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogButton -Text 'T' -Margin '8,0,0,0').Margin.Left }
            $result | Should -Be 8
        }
    }
}

# ---------------------------------------------------------------------------
# New-WsusDialogTextBox  (WPF required)
# ---------------------------------------------------------------------------
Describe 'New-WsusDialogTextBox' -Skip:(-not $script:ModuleExists) {

    Context 'Control basics' -Skip:(-not $script:WpfAvailable) {
        It 'Returns a TextBox' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogTextBox).GetType().Name }
            $result | Should -Be 'TextBox'
        }

        It 'Default Text is empty' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogTextBox).Text }
            $result | Should -Be ''
        }

        It 'InitialText is applied' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogTextBox -InitialText 'hello').Text }
            $result | Should -Be 'hello'
        }
    }

    Context 'Dark styling' -Skip:(-not $script:WpfAvailable) {
        It 'Background is #21262D' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogTextBox).Background.Color.ToString() }
            $result | Should -Be '#FF21262D'
        }

        It 'Foreground is #E6EDF3' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogTextBox).Foreground.Color.ToString() }
            $result | Should -Be '#FFE6EDF3'
        }

        It 'BorderBrush is #30363D' {
            $result = Invoke-InSta -ScriptBlock { (New-WsusDialogTextBox).BorderBrush.Color.ToString() }
            $result | Should -Be '#FF30363D'
        }
    }

    Context 'Custom padding' -Skip:(-not $script:WpfAvailable) {
        It 'Applies custom Padding string' {
            $result = Invoke-InSta -ScriptBlock {
                $p = (New-WsusDialogTextBox -Padding '10,8').Padding
                "$($p.Left),$($p.Top)"
            }
            $result | Should -Be '10,8'
        }
    }
}
