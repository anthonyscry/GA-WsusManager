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
        $script:MaintenanceContent = Get-Content $script:MaintenanceScript -Raw
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

        It "Imports the shared WsusExport module" {
            $script:MaintenanceContent | Should -Match 'Import-Module\s+\(Join-Path \$modulePath "WsusExport\.psm1"\)'
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

    Context "Shared transfer engine" {
        BeforeAll {
            $script:MonthlyExportSection = [regex]::Match(
                $script:MaintenanceContent,
                '(?s)# === EXPORT TO WSUS-EXPORTS \(OPTIONAL\) ===.*?\} elseif \(\$SkipExport\)'
            ).Value
        }

        It "Calls Invoke-WsusTransferPackage for monthly export" {
            $script:MonthlyExportSection | Should -Match 'Invoke-WsusTransferPackage\s+-Direction\s+Export'
        }

        It "Passes -IncludeDatabase and -DatabaseBackupPath to the monthly export package" {
            $script:MonthlyExportSection | Should -Match '-IncludeDatabase:\$includeDatabase'
            $script:MonthlyExportSection | Should -Match '-DatabaseBackupPath \$backupFile'
        }

        It "Does not manually Copy-Item the backup file in the monthly export block" {
            $script:MonthlyExportSection | Should -Not -Match 'Copy-Item -Path \$backupFile -Destination \$ExportPath'
        }

        It "Does not start robocopy directly in the monthly export phase" {
            $script:MonthlyExportSection | Should -Not -Match 'Start-Process\s+-FilePath\s+"robocopy\.exe"'
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
        $script:ManagementContent = Get-Content $script:ManagementScript -Raw
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

        It "Has DeepDiagnostics switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DeepDiagnostics' }
            $param | Should -Not -BeNullOrEmpty
            $param.StaticType.Name | Should -Be 'SwitchParameter'
        }
        It "Does not expose the removed OfficeUpdates switch" {
            $param = $script:Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'OfficeUpdates' }
            $param | Should -BeNullOrEmpty
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

    Context "Shared transfer engine" {
        BeforeAll {
            $script:CopyToDestinationSection = [regex]::Match(
                $script:ManagementContent,
                '(?s)function Copy-ToDestination \{.*?\r?\n\}[\r\n]+function Select-Destination'
            ).Value
            $script:ExportToMediaSection = [regex]::Match(
                $script:ManagementContent,
                '(?s)function Invoke-ExportToMedia \{.*?# ============================================================================\r?\n# HEALTH CHECK OPERATION'
            ).Value
        }

        It "Calls Invoke-WsusTransferPackage for CLI import copies" {
            $script:CopyToDestinationSection | Should -Match 'Invoke-WsusTransferPackage\s+-Direction\s+Import'
        }

        It "Calls Invoke-WsusTransferPackage for CLI export copies" {
            $script:ExportToMediaSection | Should -Match 'Invoke-WsusTransferPackage\s+-Direction\s+Export'
            $script:ExportToMediaSection | Should -Match '-DatabaseBackupPath \$sourceBak\.FullName'
        }

        It "Does not start robocopy directly in CLI import or export transfer paths" {
            $script:CopyToDestinationSection | Should -Not -Match 'Start-Process\s+-FilePath\s+"robocopy\.exe"'
            $script:ExportToMediaSection | Should -Not -Match 'Start-Process\s+-FilePath\s+"robocopy\.exe"'
        }

        It "Preserves ExportRoot as destination for legacy export callers" {
            $script:ManagementContent | Should -Match '\$ExportRoot -ne \$defaultExportRoot'
            $script:ManagementContent | Should -Match '\$actualDestination = \$ExportRoot'
            $script:ManagementContent | Should -Match '\$actualSource = \$ContentPath'
            $script:ManagementContent | Should -Match '-DestinationPath \$actualDestination'
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

    }
}


Describe "Invoke-WsusManagement.ps1 Restore Safety" {
    BeforeAll {
        $script:ManagementContent = Get-Content (Join-Path $script:ScriptsPath "Invoke-WsusManagement.ps1") -Raw
    }

    It "Verifies backup integrity before RESTORE DATABASE" {
        $script:ManagementContent | Should -Match 'Test-WsusBackupIntegrity'
        $verifyIdx = $script:ManagementContent.IndexOf('Test-WsusBackupIntegrity')
        $restoreIdx = $script:ManagementContent.IndexOf('RESTORE DATABASE SUSDB')
        $verifyIdx | Should -BeGreaterOrEqual 0
        $restoreIdx | Should -BeGreaterOrEqual 0
        $verifyIdx | Should -BeLessThan $restoreIdx
    }

    It "Does not call RESTORE VERIFYONLY directly outside the shared helper" {
        $script:ManagementContent | Should -Not -Match 'RESTORE VERIFYONLY'
    }

    It "Runs restore SQL through checked sqlcmd execution" {
        $script:ManagementContent | Should -Match 'function Invoke-CheckedSqlcmd'
        $script:ManagementContent | Should -Match 'Invoke-CheckedSqlcmd[^\r\n]+RESTORE DATABASE SUSDB'
        $script:ManagementContent | Should -Match 'Invoke-CheckedSqlcmd[^\r\n]+ALTER DATABASE SUSDB SET MULTI_USER'
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

        It "Excludes ARM64 updates from auto-approval" {
            $script:MaintenanceContent | Should -Match 'Title\s*-notmatch\s*''\(\?i\)\\bARM64\\b'''
        }

        It "Excludes 25H2 updates from auto-approval" {
            $script:MaintenanceContent | Should -Match 'Title\s*-notmatch\s*''\(\?i\)\\b25H2\\b'''
        }
    }

    Context "Safety Limits" {
        It "Has MaxAutoApproveCount safety check" {
            $script:MaintenanceContent | Should -Match 'pendingUpdates\.Count\s*-gt\s*200'
        }
    }
}
