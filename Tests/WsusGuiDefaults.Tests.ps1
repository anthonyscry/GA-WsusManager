#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for default variable values in the GUI script.

.DESCRIPTION
    Some GUI defaults (like $script:LiveTerminalMode) live at script scope in
    Scripts\WsusManagementGui.ps1 and can't be exercised by importing the file
    (it would actually launch the WPF window). This file checks the source
    text directly to verify the defaults the user sees on first launch.

    These tests are intentionally narrow: they assert the default value, not
    the entire variable declaration. That way a future maintainer can add
    comments or change formatting without breaking the test.
#>

BeforeAll {
    $script:GuiPath = Join-Path $PSScriptRoot '..\Scripts\WsusManagementGui.ps1'
    $script:GuiContent = Get-Content -LiteralPath $script:GuiPath -Raw
}

Describe 'WsusManagementGui.ps1 defaults' {
    Context 'LiveTerminalMode' {
        It 'Defaults to $true so the first operation opens a visible console' {
            # Match an assignment of LiveTerminalMode to a literal $true at
            # script scope. Anchored on the line containing the assignment
            # to avoid false matches in comments or strings.
            $pattern = '(?ms)^\s*\$script:LiveTerminalMode\s*=\s*\$true\b'
            $script:GuiContent | Should -Match $pattern
        }

        It 'Still persists LiveTerminalMode through settings.json load/save' {
            $script:GuiContent | Should -Match 's\.LiveTerminalMode'
            $script:GuiContent | Should -Match 'LiveTerminalMode=\$script:LiveTerminalMode'
        }
    }

    Context 'Live Terminal toggle button' {
        It 'Exposes a BtnLiveTerminal control in the XAML' {
            $script:GuiContent | Should -Match 'x:Name="BtnLiveTerminal"'
        }

        It 'Has a click handler that toggles $script:LiveTerminalMode' {
            $script:GuiContent | Should -Match '\$controls\.BtnLiveTerminal\.Add_Click'
        }
    }
}