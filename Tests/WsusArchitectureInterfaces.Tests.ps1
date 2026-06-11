#Requires -Version 5.1

BeforeAll {
    $script:ModulesPath = Join-Path $PSScriptRoot '..\Modules'
    Import-Module (Join-Path $script:ModulesPath 'WsusDiagnosticResult.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusOperationPlan.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusProvisioning.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusConfig.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusExport.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusHostEnvironment.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusGuiShell.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusProcessHost.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusRepairPlan.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusRepairHarness.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusAutoDetection.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $script:ModulesPath 'WsusTestHarness.psm1') -Force -DisableNameChecking
}

AfterAll {
    'WsusDiagnosticResult','WsusOperationPlan','WsusProvisioning','WsusConfig','WsusExport','WsusHostEnvironment','WsusGuiShell','WsusProcessHost','WsusRepairPlan','WsusRepairHarness','WsusAutoDetection','WsusTestHarness' | ForEach-Object {
        Remove-Module $_ -ErrorAction SilentlyContinue
    }
}

Describe 'Diagnostic result interface' {
    It 'Creates one report shape with repair plan entries' {
        $issue = New-WsusDiagnosticIssue -Severity High -Message 'WSUS content missing' -Recommendation 'Run reset' -CheckId 'content' -RepairAction 'ResetContent'
        $report = New-WsusDiagnosticReport -Issues @($issue)

        $report.PSObject.TypeNames[0] | Should -Be 'Wsus.DiagnosticReport'
        $report.Healthy | Should -BeFalse
        $report.IssuesFound | Should -Be 1
        $report.RepairPlan[0].Action | Should -Be 'ResetContent'
    }

    It 'Converts report to legacy hashtable without losing the diagnostic report' {
        $report = New-WsusDiagnosticReport
        $legacy = ConvertTo-WsusLegacyDiagnosticResult -Report $report

        $legacy | Should -BeOfType [hashtable]
        $legacy.Keys | Should -Contain 'DiagnosticReport'
        $legacy.Healthy | Should -BeTrue
    }

    It 'Merges reports into one diagnostic report interface' {
        $first = New-WsusDiagnosticReport -Issues @(New-WsusDiagnosticIssue -Severity High -Message 'A' -CheckId 'a' -RepairAction 'FixA')
        $second = New-WsusDiagnosticReport -Issues @(New-WsusDiagnosticIssue -Severity Medium -Message 'B' -CheckId 'b')
        $merged = Merge-WsusDiagnosticReports -Reports @($first, $second)

        $merged.IssuesFound | Should -Be 2
        $merged.RepairPlan.Count | Should -Be 1
    }

    It 'Preserves repair action ids in the repair plan' {
        $issue = New-WsusRepairIssueFixture -RepairAction 'RepairContentPermissions'
        $report = New-WsusDiagnosticReport -Issues @($issue)

        $report.RepairPlan[0].Action | Should -Be 'RepairContentPermissions'
    }

    It 'Canonicalizes legacy repair issue hashtables into diagnostic issues' {
        $legacyIssue = @{
            Severity = 'HIGH'
            Issue = 'SQL Browser service is Stopped'
            Fix = 'Start SQL Browser service'
            RepairAction = 'StartSqlBrowser'
        }

        $issue = ConvertTo-WsusDiagnosticIssue -InputObject $legacyIssue
        $report = New-WsusDiagnosticReport -Issues @($legacyIssue)
        $legacy = ConvertTo-WsusLegacyDiagnosticResult -Report $report

        $issue.PSObject.TypeNames[0] | Should -Be 'Wsus.DiagnosticIssue'
        $issue.Severity | Should -Be 'High'
        $issue.Message | Should -Be 'SQL Browser service is Stopped'
        $report.RepairPlan[0].Action | Should -Be 'StartSqlBrowser'
        $legacy.Issues[0].Issue | Should -Be 'SQL Browser service is Stopped'
        $legacy.Issues[0].Fix | Should -Be 'Start SQL Browser service'
    }
}

Describe 'Operation planning interface' {
    It 'Builds the deep diagnostics command from a plan' {
        $plan = New-WsusManagementOperationPlan -Id diagnostics -ManagementScriptPath 'C:\App\Invoke-WsusManagement.ps1' -ContentPath 'C:\WSUS' -SqlInstance '.\SQLEXPRESS'

        $plan.PSObject.TypeNames[0] | Should -Be 'Wsus.OperationPlan'
        $plan.Title | Should -Be 'Deep Diagnostics'
        $plan.Command | Should -Match '-DeepDiagnostics'
        $plan.Command | Should -Match '-SqlInstance'
    }

    It 'Builds a transfer command that normalizes robocopy success exit codes' {
        $plan = New-WsusTransferOperationPlan -SourcePath 'E:\Export' -DestinationPath 'C:\WSUS\Import'

        $plan.Command | Should -Match 'robocopy'
        $plan.Command | Should -Match '\$LASTEXITCODE -le 7'
        $plan.Mode | Should -Be 'Embedded'
    }

    It 'Builds an install plan with secret environment instead of inline password' {
        $password = ConvertTo-WsusSecureString -Value 'SecretValue!'
        $plan = New-WsusInstallOperationPlan -InstallScriptPath 'C:\App\Install-WsusWithSqlExpress.ps1' -InstallerPath 'C:\WSUS\SQLDB' -SaUsername 'sa' -SaPassword $password

        $plan.Environment.WSUS_INSTALL_SA_PASSWORD | Should -Be 'SecretValue!'
        $plan.Command | Should -Match 'WSUS_INSTALL_SA_PASSWORD'
    }

    It 'Builds a schedule plan with short-lived task password environment' {
        $password = ConvertTo-WsusSecureString -Value 'TaskSecret!'
        $plan = New-WsusScheduleOperationPlan -TaskModulePath 'C:\App\WsusScheduledTask.psm1' -Schedule Weekly -Time '02:00' -Profile Full -RunAsUser 'DOMAIN\User' -Password $password -DayOfWeek Saturday

        $plan.Environment.WSUS_TASK_PASSWORD | Should -Be 'TaskSecret!'
        $plan.Command | Should -Match 'ConvertTo-SecureString'
    }

    It 'Skips export when maintenance export path is blank' {
        $plan = New-WsusMaintenanceOperationPlan -MaintenanceScriptPath 'C:\App\Invoke-WsusMonthlyMaintenance.ps1' -Profile Full -ExportPath ''

        $plan.Command | Should -Match '-SkipExport'
    }
}

Describe 'Provisioning interface' {
    It 'Exports installer and backup resolution helpers' {
        Get-Command Resolve-WsusInstallerPath -Module WsusProvisioning | Should -Not -BeNullOrEmpty
        Get-Command Resolve-WsusRestoreBackup -Module WsusProvisioning | Should -Not -BeNullOrEmpty
    }
}

Describe 'Repair planning interface' {
    It 'Exports Invoke-WsusRepairAction' {
        Get-Command Invoke-WsusRepairAction -Module WsusRepairPlan | Should -Not -BeNullOrEmpty
    }

    It 'Exports repair harness fixture helper' {
        Get-Command New-WsusRepairIssueFixture -Module WsusRepairHarness | Should -Not -BeNullOrEmpty
    }

    It 'Runs ResetWsusContent through the host command adapter' {
        Mock Invoke-WsusHostCommand {
            [pscustomobject]@{ Success = $true; ExitCode = 0; Output = @(); Error = $null }
        } -ModuleName WsusRepairPlan

        Invoke-WsusRepairAction -Action ResetWsusContent | Should -BeTrue

        Should -Invoke Invoke-WsusHostCommand -ModuleName WsusRepairPlan -Times 1 -ParameterFilter {
            $FilePath -match 'wsusutil\.exe' -and $ArgumentList -contains 'reset'
        }
    }
}

Describe 'Runtime and transfer interfaces' {
    It 'Returns one runtime config shape' {
        $config = Get-WsusRuntimeConfig

        $config.PSObject.TypeNames[0] | Should -Be 'Wsus.RuntimeConfig'
        $config.ContentPath | Should -Be 'C:\WSUS'
        $config.Ports.Sql | Should -Be 1433
        $config.Tools.WsusUtil | Should -Match 'wsusutil.exe'
    }

    It 'Creates a transfer plan with content source and destination' {
        $plan = New-WsusTransferPlan -Direction Export -SourcePath 'C:\WSUS' -DestinationPath 'E:\WSUS'

        $plan.PSObject.TypeNames[0] | Should -Be 'Wsus.TransferPlan'
        $plan.ContentSource | Should -Be 'C:\WSUS\WsusContent'
        $plan.ContentDestination | Should -Be 'E:\WSUS\WsusContent'
    }
    It 'Exports the host environment adapter shape' {
        Import-Module (Join-Path $script:ModulesPath 'WsusHostEnvironment.psm1') -Force -DisableNameChecking
        Get-Command New-WsusHostEnvironment | Should -Not -BeNullOrEmpty
    }

    It 'Creates a GUI secret environment plan' {
        $secret = New-WsusSecretEnvironment -Values @{ WSUS_INSTALL_SA_PASSWORD = 'SecretValue!' }

        $secret.PSObject.TypeNames[0] | Should -Be 'Wsus.SecretEnvironment'
        $secret.CleanupKeys | Should -Contain 'WSUS_INSTALL_SA_PASSWORD'
    }

    It 'Formats GUI lifecycle and status text through the shell interface' {
        $started = [datetime]'2026-06-02T00:00:00'
        $completed = $started.AddMilliseconds(1250)

        New-WsusGuiStatusText -State Completed -Title 'Deep Diagnostics' -Timestamp $completed | Should -Be 'Completed: Deep Diagnostics  [00:00:01]'
        New-WsusGuiLifecycleLogEntry -Event StartupCompleted -StartedAt $started -CompletedAt $completed | Should -Be 'Startup completed in 1250ms'
    }

    It 'Owns popup duplicate and startup probe shaping' {
        $history = @{}
        $now = [datetime]'2026-06-02T00:00:00'

        Test-WsusGuiPopupSuppressed -Message 'Same popup' -Title 'T' -Button 'OK' -Icon 'Information' -SuppressDuplicateSeconds 10 -PopupHistory $history -Now $now | Should -BeFalse
        Test-WsusGuiPopupSuppressed -Message 'Same popup' -Title 'T' -Button 'OK' -Icon 'Information' -SuppressDuplicateSeconds 10 -PopupHistory $history -Now $now.AddSeconds(1) | Should -BeTrue

        $events = New-Object System.Collections.Generic.List[object]
        Add-WsusGuiPopupEvent -EventList $events -Message 'Broken' -Title 'T' -Button 'OK' -Icon 'Error' -Timestamp $now
        $probe = New-WsusGuiStartupProbeResult -Status fail -Reason 'Error popup' -StartupProbeSeconds 8 -ResultPath 'probe.json' -PopupEvents @($events.ToArray())

        $probe.PSObject.TypeNames[0] | Should -Be 'Wsus.GuiStartupProbeResult'
        $probe.errorPopupCount | Should -Be 1
        Get-WsusGuiProbePopupResult -Button 'YesNo' | Should -Be 'No'
    }

    It 'Builds operation completion details and invokes shell callbacks' {
        $reportPath = Join-Path ([System.IO.Path]::GetTempPath()) "wsus-report-$([guid]::NewGuid().ToString('N')).json"
        try {
            '{}' | Set-Content -Path $reportPath -Encoding UTF8
            $started = [datetime]'2026-06-02T00:00:00'
            $completed = $started.AddSeconds(75)
            $completion = New-WsusGuiOperationCompletion -Title 'Deep Diagnostics' -Success:$true -StartedAt $started -CompletedAt $completed -ReportPath $reportPath -CleanupKeys @('WSUS_SECRET')

            $completion.PSObject.TypeNames[0] | Should -Be 'Wsus.GuiOperationCompletion'
            $completion.ReportAvailable | Should -BeTrue
            $completion.NotificationMessage | Should -Be 'Pass in 1m 15s'

            $script:GuiShellCallbacks = New-Object System.Collections.Generic.List[string]
            Invoke-WsusGuiOperationCompletion -Completion $completion `
                -LogAction { param($message, $level) $script:GuiShellCallbacks.Add("log:${level}:${message}") | Out-Null } `
                -NotificationAction { param($title, $message, $result) $script:GuiShellCallbacks.Add("notify:${result}:${title}") | Out-Null } `
                -HistoryAction { param($operationType, $duration, $result, $summary) $script:GuiShellCallbacks.Add("history:${result}:${operationType}") | Out-Null } `
                -CleanupAction { param([string[]]$keys) $script:GuiShellCallbacks.Add("cleanup:$($keys -join ',')") | Out-Null }

            $script:GuiShellCallbacks | Should -Contain "notify:Pass:WSUS Manager - Deep Diagnostics Complete"
            $script:GuiShellCallbacks | Should -Contain 'history:Pass:Deep Diagnostics'
            $script:GuiShellCallbacks | Should -Contain 'cleanup:WSUS_SECRET'
        } finally {
            Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Creates a dashboard view model interface' {
        $view = New-WsusDashboardViewModel -WsusInstalled:$true -ServerMode 'Online' -DashboardData ([pscustomobject]@{
            Services = @{ Running = 3; Names = @('SQL','WSUS','IIS') }
            DatabaseSizeGB = 4.5
            DiskFreeGB = 100
            TaskStatus = 'Ready'
        }) -ContentPath 'C:\WSUS' -SqlInstance '.\SQLEXPRESS' -ExportRoot 'E:\Exports' -LogPath 'C:\WSUS\Logs'

        $view.PSObject.TypeNames[0] | Should -Be 'Wsus.DashboardViewModel'
        $view.Cards.Services.Status | Should -Be 'Pass'
        $view.Configuration.SqlInstance | Should -Be '.\SQLEXPRESS'
    }

    It 'Creates a process host adapter shape' {
        $processHostAdapter = New-WsusPowerShellProcessHost
        $processHostAdapter.PSObject.TypeNames[0] | Should -Be 'Wsus.ProcessHost'
    }
}

Describe 'Dashboard snapshot interface' {
    It 'Exports the dashboard snapshot function' {
        Get-Command Get-WsusDashboardSnapshot -Module WsusAutoDetection | Should -Not -BeNullOrEmpty
    }
}
