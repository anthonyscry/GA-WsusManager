#Requires -Modules Pester
<#
.SYNOPSIS
    CLI Integration tests for WSUS Manager scripts

.DESCRIPTION
    Tests to verify:
    - CLI parameter validation
    - Parameter combinations work correctly
    - Help documentation is present
    - Default values are applied correctly
    - Invalid parameters are rejected
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ScriptsPath = Join-Path $script:RepoRoot "Scripts"
    $script:ModulesPath = Join-Path $script:RepoRoot "Modules"

    # Import config module for testing config values
    Import-Module (Join-Path $script:ModulesPath "WsusConfig.psm1") -Force -DisableNameChecking
}

Describe "Invoke-WsusMonthlyMaintenance.ps1 Parameter Validation" {
    BeforeAll {
        $script:MaintenanceScript = Join-Path $script:ScriptsPath "Invoke-WsusMonthlyMaintenance.ps1"

        # Parse the script to get parameter information
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:MaintenanceScript,
            [ref]$null,
            [ref]$null
        )
        $script:Parameters = $ast.ParamBlock.Parameters
    }

    Context "Required Parameters" {
        It "Has MaintenanceProfile parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MaintenanceProfile' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "MaintenanceProfile accepts valid values: Quick, Full, SyncOnly" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'MaintenanceProfile' }
            $validateSet = $param.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.PositionalArguments.Value | Should -Contain 'Quick'
            $validateSet.PositionalArguments.Value | Should -Contain 'Full'
            $validateSet.PositionalArguments.Value | Should -Contain 'SyncOnly'
        }

        It "Has Operations parameter with valid values" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Operations' }
            $param | Should -Not -BeNullOrEmpty
            $validateSet = $param.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
            $validateSet.PositionalArguments.Value | Should -Contain 'Sync'
            $validateSet.PositionalArguments.Value | Should -Contain 'Cleanup'
            $validateSet.PositionalArguments.Value | Should -Contain 'Backup'
            $validateSet.PositionalArguments.Value | Should -Contain 'Export'
            $validateSet.PositionalArguments.Value | Should -Contain 'All'
        }
    }

    Context "Export Path Parameters" {
        It "Has ExportPath parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ExportPath' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has DifferentialExportPath parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DifferentialExportPath' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has ExportDays parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ExportDays' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "ExportDays has correct type (int)" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ExportDays' }
            $param.StaticType.Name | Should -Be 'Int32'
        }
    }

    Context "Switch Parameters" {
        It "Has SkipUltimateCleanup switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SkipUltimateCleanup' }
            $param | Should -Not -BeNullOrEmpty
            $param.StaticType.Name | Should -Be 'SwitchParameter'
        }

        It "Has SkipExport switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SkipExport' }
            $param | Should -Not -BeNullOrEmpty
            $param.StaticType.Name | Should -Be 'SwitchParameter'
        }

        It "Has Unattended switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Unattended' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has NoTranscript switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'NoTranscript' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has UseWindowsAuth switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'UseWindowsAuth' }
            $param | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Invoke-WsusManagement.ps1 Parameter Validation" {
    BeforeAll {
        $script:ManagementScript = Join-Path $script:ScriptsPath "Invoke-WsusManagement.ps1"

        # Parse the script to get parameter information
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ManagementScript,
            [ref]$null,
            [ref]$null
        )
        $script:Parameters = $ast.ParamBlock.Parameters
    }

    Context "Operation Switches" {
        It "Has Health switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Health' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has Repair switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Repair' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has Cleanup switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Cleanup' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has Export switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Export' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has Import switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Import' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has Restore switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Restore' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has Diagnostics switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Diagnostics' }
            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context "Path Parameters" {
        It "Has ContentPath parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'ContentPath' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has SqlInstance parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SqlInstance' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has SourcePath parameter for Import" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'SourcePath' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has DestinationPath parameter for Import/Export" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DestinationPath' }
            $param | Should -Not -BeNullOrEmpty
        }
    }

    Context "Export/Import Parameters" {
        It "Has CopyMode parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'CopyMode' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "CopyMode accepts Full and Differential" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'CopyMode' }
            $validateSet = $param.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
            $validateSet.PositionalArguments.Value | Should -Contain 'Full'
            $validateSet.PositionalArguments.Value | Should -Contain 'Differential'
        }

        It "Has DaysOld parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DaysOld' }
            $param | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Install-WsusWithSqlExpress.ps1 Parameter Validation" {
    BeforeAll {
        $script:InstallScript = Join-Path $script:ScriptsPath "Install-WsusWithSqlExpress.ps1"

        # Parse the script to get parameter information
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:InstallScript,
            [ref]$null,
            [ref]$null
        )
        $script:Parameters = $ast.ParamBlock.Parameters
    }

    Context "Required Parameters" {
        It "Has InstallerPath parameter" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'InstallerPath' }
            $param | Should -Not -BeNullOrEmpty
        }

        It "Has NonInteractive switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'NonInteractive' }
            $param | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "WsusConfig Module Integration" {
    Context "GUI Configuration Values" {
        It "Returns valid dialog dimensions for Medium" {
            $size = Get-WsusDialogSize -Type "Medium"
            $size.Width | Should -BeGreaterThan 0
            $size.Height | Should -BeGreaterThan 0
        }

        It "Returns valid dialog dimensions for ExtraLarge" {
            $size = Get-WsusDialogSize -Type "ExtraLarge"
            $size.Width | Should -BeGreaterThan 0
            $size.Height | Should -BeGreaterThan 0
        }

        It "Returns valid timer intervals" {
            Get-WsusTimerInterval -Timer "DashboardRefresh" | Should -BeGreaterThan 0
            Get-WsusTimerInterval -Timer "UiUpdate" | Should -BeGreaterThan 0
        }

        It "DashboardRefresh is 30 seconds (30000ms)" {
            Get-WsusTimerInterval -Timer "DashboardRefresh" | Should -Be 30000
        }

        It "UiUpdate is 250ms" {
            Get-WsusTimerInterval -Timer "UiUpdate" | Should -Be 250
        }
    }

    Context "Retry Configuration Values" {
        It "DbShrinkAttempts is 3" {
            Get-WsusRetrySetting -Setting "DbShrinkAttempts" | Should -Be 3
        }

        It "DbShrinkDelaySeconds is 30" {
            Get-WsusRetrySetting -Setting "DbShrinkDelaySeconds" | Should -Be 30
        }

        It "ServiceStartAttempts is 3" {
            Get-WsusRetrySetting -Setting "ServiceStartAttempts" | Should -Be 3
        }
    }

    Context "Maintenance Configuration Values" {
        It "MaxAutoApproveCount is 200" {
            Get-WsusMaintenanceSetting -Setting "MaxAutoApproveCount" | Should -Be 200
        }

        It "UpdateAgeCutoffMonths is 6" {
            Get-WsusMaintenanceSetting -Setting "UpdateAgeCutoffMonths" | Should -Be 6
        }

        It "DefaultExportDays is 30" {
            Get-WsusMaintenanceSetting -Setting "DefaultExportDays" | Should -Be 30
        }
    }
}

Describe "Script Help Documentation" {
    Context "Invoke-WsusMonthlyMaintenance.ps1 has help" {
        BeforeAll {
            $script:MaintenanceContent = Get-Content (Join-Path $script:ScriptsPath "Invoke-WsusMonthlyMaintenance.ps1") -Raw
        }

        It "Has SYNOPSIS section" {
            $script:MaintenanceContent | Should -Match '\.SYNOPSIS'
        }

        It "Has DESCRIPTION section" {
            $script:MaintenanceContent | Should -Match '\.DESCRIPTION'
        }

        It "Has PARAMETER documentation" {
            $script:MaintenanceContent | Should -Match '\.PARAMETER'
        }
    }

    Context "Invoke-WsusManagement.ps1 has help" {
        BeforeAll {
            $script:ManagementContent = Get-Content (Join-Path $script:ScriptsPath "Invoke-WsusManagement.ps1") -Raw
        }

        It "Has SYNOPSIS section" {
            $script:ManagementContent | Should -Match '\.SYNOPSIS'
        }

        It "Has DESCRIPTION section" {
            $script:ManagementContent | Should -Match '\.DESCRIPTION'
        }
    }
}

Describe "Update Classifications Configuration" {
    BeforeAll {
        $script:MaintenanceContent = Get-Content (Join-Path $script:ScriptsPath "Invoke-WsusMonthlyMaintenance.ps1") -Raw
    }

    Context "Approved Classifications" {
        It "Approves Critical Updates" {
            $script:MaintenanceContent | Should -Match 'Critical Updates'
        }

        It "Approves Security Updates" {
            $script:MaintenanceContent | Should -Match 'Security Updates'
        }

        It "Approves Update Rollups" {
            $script:MaintenanceContent | Should -Match 'Update Rollups'
        }

        It "Approves Service Packs" {
            $script:MaintenanceContent | Should -Match 'Service Packs'
        }

        It "Approves Definition Updates" {
            $script:MaintenanceContent | Should -Match 'Definition Updates'
        }
    }

    Context "Excluded Classifications" {
        It "Excludes Upgrades from auto-approval" {
            # Should mention Upgrades as excluded
            $script:MaintenanceContent | Should -Match 'Upgrades.*manual review|Excluding.*Upgrades'
        }
    }

    Context "Safety Limits" {
        It "Has MaxAutoApproveCount safety check" {
            $script:MaintenanceContent | Should -Match 'pendingUpdates\.Count\s*-gt\s*200'
        }
    }
}

Describe "Export Path Handling" {
    BeforeAll {
        $script:MaintenanceContent = Get-Content (Join-Path $script:ScriptsPath "Invoke-WsusMonthlyMaintenance.ps1") -Raw
    }

    Context "Export Path Parameters" {
        It "Supports separate DifferentialExportPath" {
            $script:MaintenanceContent | Should -Match '\[string\]\$DifferentialExportPath'
        }

        It "Creates year/month subfolder when DifferentialExportPath not specified" {
            $script:MaintenanceContent | Should -Match 'archiveDestination.*ExportPath.*year.*month|Combine.*ExportPath.*year.*month'
        }

        It "Uses DifferentialExportPath directly when specified" {
            $script:MaintenanceContent | Should -Match 'if.*DifferentialExportPath'
        }
    }
}
