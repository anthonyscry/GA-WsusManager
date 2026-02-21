# AutomationId.Tests.ps1
# Pester tests to verify AutomationId attributes exist in XAML files for UI automation

Describe "MainWindow AutomationId Verification" {
    BeforeAll {
        $xamlPath = "..\src\WsusManager.App\Views\MainWindow.xaml"
        $mainWindowXaml = Get-Content $xamlPath -Raw
    }

    It "Should have AutomationId on Window element" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="MainWindow"'
    }

    It "Should have AutomationId on InstallButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="InstallButton"'
    }

    It "Should have AutomationId on CreateGpoButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="CreateGpoButton"'
    }

    It "Should have AutomationId on TransferButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="TransferButton"'
    }

    It "Should have AutomationId on OnlineSyncButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="OnlineSyncButton"'
    }

    It "Should have AutomationId on ScheduleTaskButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="ScheduleTaskButton"'
    }

    It "Should have AutomationId on DiagnosticsButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="DiagnosticsButton"'
    }

    It "Should have AutomationId on ClientToolsButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="ClientToolsButton"'
    }

    It "Should have AutomationId on DatabaseButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="DatabaseButton"'
    }

    It "Should have AutomationId on DashboardButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="DashboardButton"'
    }

    It "Should have AutomationId on SettingsButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="SettingsButton"'
    }

    It "Should have AutomationId on HelpButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="HelpButton"'
    }

    It "Should have AutomationId on AboutButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="AboutButton"'
    }

    It "Should have AutomationId on DashboardPanel" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="DashboardPanel"'
    }

    It "Should have AutomationId on DiagnosticsPanel" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="DiagnosticsPanel"'
    }

    It "Should have AutomationId on DatabasePanel" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="DatabasePanel"'
    }

    It "Should have AutomationId on ClientToolsPanel" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="ClientToolsPanel"'
    }

    It "Should have AutomationId on LogOutputTextBox" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="LogOutputTextBox"'
    }

    It "Should have AutomationId on QuickDiagnosticsButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="QuickDiagnosticsButton"'
    }

    It "Should have AutomationId on QuickCleanupButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="QuickCleanupButton"'
    }

    It "Should have AutomationId on QuickSyncButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="QuickSyncButton"'
    }

    It "Should have AutomationId on QuickStartServicesButton" {
        $mainWindowXaml | Should -Match 'automation:AutomationProperties\.AutomationId="QuickStartServicesButton"'
    }
}

Describe "Dialog AutomationId Verification" {
    It "SettingsDialog should have AutomationId on root" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\SettingsDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="SettingsDialog"'
    }

    It "SettingsDialog should have SaveSettingsButton" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\SettingsDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="SaveSettingsButton"'
    }

    It "SyncProfileDialog should have AutomationId on root" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\SyncProfileDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="SyncProfileDialog"'
    }

    It "SyncProfileDialog should have OkSyncProfileButton" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\SyncProfileDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="OkSyncProfileButton"'
    }

    It "TransferDialog should have AutomationId on root" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\TransferDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="TransferDialog"'
    }

    It "TransferDialog should have StartTransferButton" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\TransferDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="StartTransferButton"'
    }

    It "ScheduleTaskDialog should have AutomationId on root" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\ScheduleTaskDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="ScheduleTaskDialog"'
    }

    It "ScheduleTaskDialog should have CreateScheduleButton" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\ScheduleTaskDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="CreateScheduleButton"'
    }

    It "InstallDialog should have AutomationId on root" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\InstallDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="InstallDialog"'
    }

    It "InstallDialog should have StartInstallButton" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\InstallDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="StartInstallButton"'
    }

    It "GpoInstructionsDialog should have AutomationId on root" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\GpoInstructionsDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="GpoInstructionsDialog"'
    }

    It "GpoInstructionsDialog should have CopyGpoFilesButton" {
        $xaml = Get-Content "..\src\WsusManager.App\Views\GpoInstructionsDialog.xaml" -Raw
        $xaml | Should -Match 'automation:AutomationProperties\.AutomationId="CopyGpoFilesButton"'
    }
}

Describe "AutomationId Naming Convention" {
    It "MainWindow AutomationIds should follow [Purpose][Type] PascalCase convention" {
        $mainWindowXaml = Get-Content "..\src\WsusManager.App\Views\MainWindow.xaml" -Raw

        # Extract all AutomationId values
        $matches = [regex]::Matches($mainWindowXaml, 'automation:AutomationProperties\.AutomationId="([^"]+)"')

        # Check naming convention: ends with Button, TextBox, ComboBox, Panel, etc.
        $validSuffixes = @('Button', 'TextBox', 'ComboBox', 'Panel', 'Grid', 'ListBox', 'RadioButton', 'CheckBox')

        foreach ($match in $matches) {
            $automationId = $match.Groups[1].Value

            # Should be PascalCase (first letter uppercase)
            $automationId[0].ToString() | Should -BeIn @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') -Because "$automationId should start with uppercase letter"

            # Should end with a valid type suffix (except MainWindow which is special)
            if ($automationId -ne 'MainWindow' -and $automationId -ne 'OperationPanel') {
                $hasValidSuffix = $false
                foreach ($suffix in $validSuffixes) {
                    if ($automationId.EndsWith($suffix)) {
                        $hasValidSuffix = $true
                        break
                    }
                }
                $hasValidSuffix | Should -BeTrue -Because "$automationId should end with a type suffix"
            }
        }
    }

    It "All XAML files should have AutomationProperties namespace declared" {
        $xamlFiles = @(
            "..\src\WsusManager.App\Views\MainWindow.xaml",
            "..\src\WsusManager.App\Views\SettingsDialog.xaml",
            "..\src\WsusManager.App\Views\SyncProfileDialog.xaml",
            "..\src\WsusManager.App\Views\TransferDialog.xaml",
            "..\src\WsusManager.App\Views\ScheduleTaskDialog.xaml",
            "..\src\WsusManager.App\Views\InstallDialog.xaml",
            "..\src\WsusManager.App\Views\GpoInstructionsDialog.xaml"
        )

        foreach ($xamlFile in $xamlFiles) {
            $xaml = Get-Content $xamlFile -Raw -ErrorAction SilentlyContinue
            if ($xaml) {
                $xaml | Should -Match 'xmlns:automation="clr-namespace:System\.Windows\.Automation;assembly=PresentationCore"' -Because "$(Split-Path $xamlFile -Leaf) should declare AutomationProperties namespace"
            }
        }
    }
}
