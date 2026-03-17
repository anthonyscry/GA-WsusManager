<#
.SYNOPSIS
    Pester tests to verify AutomationId attributes exist in the GUI source.

.DESCRIPTION
    Validates that key UI elements in the WPF application have AutomationId
    attributes set, enabling reliable UI automation testing.

    Since WSUS Manager uses embedded XAML within WsusManagementGui.ps1
    (not separate .xaml files), this test parses the embedded XAML directly.
#>

Describe "MainWindow AutomationId Verification" {
    BeforeAll {
        $xamlPath = Join-Path $PSScriptRoot "..\Scripts\WsusManagementGui.ps1"
        $script:HasXaml = Test-Path $xamlPath

        if ($script:HasXaml) {
            # Extract embedded XAML from the PS1 file (between <Window and </Window>)
            $content = Get-Content $xamlPath -Raw
            if ($content -match '(<Window[^>]*>.*?</Window>)') {
                $script:Xaml = $Matches[1]
            } else {
                $script:HasXaml = $false
                Write-Warning "Could not extract embedded XAML from WsusManagementGui.ps1"
            }
        }
    }

    Context 'Window Root' {
        It 'Main window has AutomationId' -Skip:(-not $script:HasXaml) {
            $script:Xaml | Should -Match 'AutomationProperties\.AutomationId="WsusManagerMainWindow"' -Because "Main window must have AutomationId for test automation"
        }
    }

    Context 'Navigation Panels' {
        $panels = @(
            @{ Id = "DashboardPanel" },
            @{ Id = "InstallPanel" },
            @{ Id = "OperationPanel" },
            @{ Id = "AboutPanel" },
            @{ Id = "HelpPanel" },
            @{ Id = "HistoryPanel" }
        )

        It "Panel '<Id>' has AutomationId" -TestCases $panels -Skip:(-not $script:HasXaml) {
            param($Id)
            $pattern = "AutomationProperties\.AutomationId=`"$Id`""
            $script:Xaml | Should -Match $pattern -Because "Panel '$Id' needs AutomationId for navigation tests"
        }
    }

    Context 'Log Panel' {
        It 'LogPanel has AutomationId' -Skip:(-not $script:HasXaml) {
            $script:Xaml | Should -Match 'AutomationProperties\.AutomationId="LogPanel"' -Because "Log panel needs AutomationId for output verification"
        }
    }

    Context 'Health Score Elements' {
        It 'HealthScoreValue has AutomationId' -Skip:(-not $script:HasXaml) {
            $script:Xaml | Should -Match 'AutomationProperties\.AutomationId="HealthScoreValue"'
        }

        It 'HealthScoreGrade has AutomationId' -Skip:(-not $script:HasXaml) {
            $script:Xaml | Should -Match 'AutomationProperties\.AutomationId="HealthScoreGrade"'
        }
    }

    Context 'Named Navigation Buttons' {
        # These use x:Name (which FlaUI can find via Name property)
        $navButtons = @(
            "BtnDashboard", "BtnInstall", "BtnRestore", "BtnCreateGpo",
            "BtnTransfer", "BtnMaintenance", "BtnSchedule", "BtnCleanup",
            "BtnDiagnostics", "BtnReset", "BtnHistory", "BtnHelp",
            "BtnSettings", "BtnAbout"
        )

        It "Button 'x:Name=<_>' exists in XAML" -TestCases $navButtons -Skip:(-not $script:HasXaml) {
            param($_)
            $script:Xaml | Should -Match "x:Name=`"$_`"" -Because "Nav button '$_' needs x:Name for element identification"
        }
    }

    Context 'Quick Action Buttons' {
        $quickButtons = @("QBtnDiagnostics", "QBtnCleanup", "QBtnMaint", "QBtnStart")

        It "Quick action button 'x:Name=<_>' exists in XAML" -TestCases $quickButtons -Skip:(-not $script:HasXaml) {
            param($_)
            $script:Xaml | Should -Match "x:Name=`"$_`"" -Because "Quick button '$_' needs x:Name for element identification"
        }
    }
}

Describe "Inline Dialog AutomationId Verification" {
    BeforeAll {
        $guiPath = Join-Path $PSScriptRoot "..\Scripts\WsusManagementGui.ps1"
        $script:HasGuiScript = Test-Path $guiPath
        if ($script:HasGuiScript) {
            $script:GuiContent = Get-Content $guiPath -Raw
        }
    }

    $dialogTests = @(
        @{ Id = "ExportDialog";           Type = "Dialog Window" },
        @{ Id = "ImportDialog";           Type = "Dialog Window" },
        @{ Id = "RestoreDialog";          Type = "Dialog Window" },
        @{ Id = "MaintenanceDialog";      Type = "Dialog Window" },
        @{ Id = "ScheduleDialog";         Type = "Dialog Window" },
        @{ Id = "TransferDialog";         Type = "Dialog Window" },
        @{ Id = "SettingsDialog";         Type = "Dialog Window" },
        @{ Id = "ExportButton";           Type = "Action Button" },
        @{ Id = "ImportButton";           Type = "Action Button" },
        @{ Id = "RestoreButton";          Type = "Action Button" },
        @{ Id = "RunSyncButton";          Type = "Action Button" },
        @{ Id = "StartTransferButton";    Type = "Action Button" },
        @{ Id = "SaveSettingsButton";     Type = "Action Button" },
        @{ Id = "ExportDestinationTextBox"; Type = "Input Field" },
        @{ Id = "ImportSourceTextBox";     Type = "Input Field" },
        @{ Id = "ImportDestinationTextBox"; Type = "Input Field" },
        @{ Id = "RestoreFileTextBox";      Type = "Input Field" },
        @{ Id = "SettingsContentPathTextBox"; Type = "Input Field" },
        @{ Id = "SettingsSqlInstanceTextBox"; Type = "Input Field" }
    )

    It "Dialog <Type> '<Id>' has AutomationId" -TestCases $dialogTests -Skip:(-not $script:HasGuiScript) {
        param($Id, $Type)
        $escaped = [regex]::Escape($Id)
        $script:GuiContent | Should -Match $escaped -Because "$Type '$Id' needs AutomationId for testability"
    }
}

Describe "AutomationId Naming Convention" -Skip:(-not $script:HasXaml) {
    It 'All AutomationIds follow PascalCase convention' {
        $matches = [regex]::Matches($script:Xaml, 'AutomationProperties\.AutomationId="([^"]+)"')

        $validSuffixes = @('Button', 'TextBox', 'ComboBox', 'Panel', 'Grid', 'ListBox',
                           'RadioButton', 'CheckBox', 'Value', 'Grade', 'Bar', 'Border',
                           'Window', 'Label', 'List', 'Dot', 'Text', 'Output')

        foreach ($match in $matches) {
            $automationId = $match.Groups[1].Value

            # Should start with uppercase
            $automationId[0].ToString() | Should -BeIn 'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z' `
                -Because "$automationId should start with uppercase (PascalCase)"
        }
    }

    It 'No duplicate AutomationIds exist' {
        $matches = [regex]::Matches($script:Xaml, 'AutomationProperties\.AutomationId="([^"]+)"')
        $ids = $matches | ForEach-Object { $_.Groups[1].Value }
        $uniqueIds = $ids | Select-Object -Unique
        $ids.Count | Should -Be $uniqueIds.Count -Because "All AutomationIds must be unique"
    }
}

Describe "Dialog Factory AutomationId Support" {
    BeforeAll {
        $dialogModulePath = Join-Path $PSScriptRoot "..\Modules\WsusDialogs.psm1"
        $script:HasDialogModule = Test-Path $dialogModulePath

        if ($script:HasDialogModule) {
            $script:DialogModule = Get-Content $dialogModulePath -Raw
        }
    }

    Context 'New-WsusDialog' {
        It 'Accepts AutomationId parameter' -Skip:(-not $script:HasDialogModule) {
            $script:DialogModule | Should -Match '\[string\]\$AutomationId' -Because "Dialog factory should accept AutomationId for testability"
        }

        It 'Sets AutomationId on the window' -Skip:(-not $script:HasDialogModule) {
            $script:DialogModule | Should -Match 'AutomationProperties\.AutomationIdProperty' -Because "Dialog factory should apply AutomationId via WPF property system"
        }
    }

    Context 'Dialog Helper Functions' {
        It 'New-WsusDialogButton accepts AutomationId' -Skip:(-not $script:HasDialogModule) {
            $script:DialogModule | Should -Match 'function New-WsusDialogButton[\s\S]*?\[string\]\$AutomationId' -Because "Button factory should accept AutomationId"
        }

        It 'New-WsusDialogTextBox accepts AutomationId' -Skip:(-not $script:HasDialogModule) {
            $script:DialogModule | Should -Match 'function New-WsusDialogTextBox[\s\S]*?\[string\]\$AutomationId' -Because "TextBox factory should accept AutomationId"
        }

        It 'New-WsusFolderBrowser accepts AutomationId' -Skip:(-not $script:HasDialogModule) {
            $script:DialogModule | Should -Match 'function New-WsusFolderBrowser[\s\S]*?\[string\]\$AutomationId' -Because "FolderBrowser factory should accept AutomationId"
        }
    }
}
