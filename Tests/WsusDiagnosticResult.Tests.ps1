#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Modules\WsusTestHarness.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:RepoRoot = Resolve-WsusTestRepoRoot -StartPath $PSScriptRoot
    Import-WsusTestModule -ModuleName 'WsusDiagnosticResult' -RepoRoot $script:RepoRoot
}

AfterAll {
    Remove-WsusTestModule -ModuleName 'WsusDiagnosticResult'
}

Describe 'WsusDiagnosticResult module' {
    It 'exports the diagnostic result factory and conversion functions' {
        Get-Command ConvertTo-WsusDiagnosticIssue -Module WsusDiagnosticResult | Should -Not -BeNullOrEmpty
        Get-Command New-WsusDiagnosticIssue -Module WsusDiagnosticResult | Should -Not -BeNullOrEmpty
        Get-Command New-WsusDiagnosticCheckResult -Module WsusDiagnosticResult | Should -Not -BeNullOrEmpty
        Get-Command New-WsusDiagnosticReport -Module WsusDiagnosticResult | Should -Not -BeNullOrEmpty
        Get-Command ConvertTo-WsusLegacyDiagnosticResult -Module WsusDiagnosticResult | Should -Not -BeNullOrEmpty
        Get-Command Merge-WsusDiagnosticReports -Module WsusDiagnosticResult | Should -Not -BeNullOrEmpty
    }
}

Describe 'ConvertTo-WsusDiagnosticIssue' {
    It 'converts legacy hashtable keys to the typed issue shape with canonical severity' {
        $issue = ConvertTo-WsusDiagnosticIssue -InputObject @{
            Severity = 'HIGH'
            Issue = 'SQL Browser service is stopped'
            Fix = 'Start SQL Browser'
            CheckId = 'sql-browser'
            RepairAction = 'StartSqlBrowser'
            Evidence = @{ Status = 'Stopped' }
        }

        $issue.PSObject.TypeNames[0] | Should -Be 'Wsus.DiagnosticIssue'
        $issue.Severity | Should -Be 'High'
        $issue.Message | Should -Be 'SQL Browser service is stopped'
        $issue.Recommendation | Should -Be 'Start SQL Browser'
        $issue.CheckId | Should -Be 'sql-browser'
        $issue.RepairAction | Should -Be 'StartSqlBrowser'
        $issue.Repairable | Should -BeTrue
        $issue.Evidence.Status | Should -Be 'Stopped'
    }

    It 'adds legacy Issue and Fix aliases only when requested' {
        $issue = ConvertTo-WsusDiagnosticIssue -InputObject ([pscustomobject]@{
            Severity = 'Medium'
            Message = 'Content mismatch'
            Recommendation = 'Run reset'
        }) -IncludeLegacyAliases

        $issue.Issue | Should -Be 'Content mismatch'
        $issue.Fix | Should -Be 'Run reset'
    }

    It 'defaults unknown severities and string input to an informational issue' {
        $issue = ConvertTo-WsusDiagnosticIssue -InputObject 'Unstructured diagnostic note'

        $issue.Severity | Should -Be 'Info'
        $issue.Message | Should -Be 'Unstructured diagnostic note'
        $issue.Recommendation | Should -Be ''
        $issue.Repairable | Should -BeFalse
    }
}

Describe 'New-WsusDiagnosticIssue and New-WsusDiagnosticCheckResult' {
    It 'creates typed issue objects and marks blank repair actions as not repairable' {
        $issue = New-WsusDiagnosticIssue -Severity Low -Message 'Optional cleanup' -Recommendation 'Review later'

        $issue.PSObject.TypeNames[0] | Should -Be 'Wsus.DiagnosticIssue'
        $issue.Severity | Should -Be 'Low'
        $issue.Repairable | Should -BeFalse
        $issue.Evidence | Should -BeOfType [hashtable]
    }

    It 'creates typed check results with normalized issue arrays' {
        $issue = New-WsusDiagnosticIssue -Severity Critical -Message 'Content missing' -CheckId 'content' -RepairAction 'ResetWsusContent'
        $check = New-WsusDiagnosticCheckResult -CheckId 'content' -Status Fail -Message 'Content check failed' -Evidence @{ Missing = 5 } -Issues @($issue)

        $check.PSObject.TypeNames[0] | Should -Be 'Wsus.DiagnosticCheckResult'
        $check.CheckId | Should -Be 'content'
        $check.Status | Should -Be 'Fail'
        $check.Issues.Count | Should -Be 1
        $check.Evidence.Missing | Should -Be 5
    }
}

Describe 'New-WsusDiagnosticReport' {
    It 'combines top-level issues and check issues into a repair plan' {
        $repairable = New-WsusDiagnosticIssue -Severity High -Message 'SQL Browser stopped' -Recommendation 'Start SQL Browser' -CheckId 'sql-browser' -RepairAction 'StartSqlBrowser'
        $notRepairable = New-WsusDiagnosticIssue -Severity Low -Message 'Review logs' -CheckId 'events'
        $check = New-WsusDiagnosticCheckResult -CheckId 'content' -Status Fail -Issues @(@{ Severity = 'Critical'; Issue = 'Content missing'; Fix = 'Run reset'; RepairAction = 'ResetWsusContent'; CheckId = 'content' })

        $report = New-WsusDiagnosticReport -Checks @($check) -Issues @($repairable, $notRepairable) -FixesApplied @('StartBits') -FixesFailed @('ResetWsusContent') -Evidence @{ Source = 'unit' } -Recommendations @('Run reset', 'Run reset')

        $report.PSObject.TypeNames[0] | Should -Be 'Wsus.DiagnosticReport'
        $report.Healthy | Should -BeFalse
        $report.IssuesFound | Should -Be 3
        $report.IssuesFixed | Should -Be 1
        $report.Issues.Count | Should -Be 3
        $report.RepairPlan.Count | Should -Be 2
        $report.RepairPlan.Action | Should -Contain 'StartSqlBrowser'
        $report.RepairPlan.Action | Should -Contain 'ResetWsusContent'
        $report.FixesFailed | Should -Contain 'ResetWsusContent'
        $report.Evidence.Source | Should -Be 'unit'
        $report.Recommendations.Count | Should -Be 1
    }

    It 'creates a healthy empty report with stable empty collections' {
        $report = New-WsusDiagnosticReport

        $report.Healthy | Should -BeTrue
        $report.IssuesFound | Should -Be 0
        $report.IssuesFixed | Should -Be 0
        $report.Checks.Count | Should -Be 0
        $report.Issues.Count | Should -Be 0
        $report.RepairPlan.Count | Should -Be 0
    }
}

Describe 'ConvertTo-WsusLegacyDiagnosticResult and Merge-WsusDiagnosticReports' {
    It 'converts typed reports to the legacy hashtable while preserving aliases and the original report' {
        $issue = New-WsusDiagnosticIssue -Severity Medium -Message 'Database near limit' -Recommendation 'Decline superseded updates' -CheckId 'database' -RepairAction 'DeclineSupersededUpdates'
        $report = New-WsusDiagnosticReport -Issues @($issue) -Evidence @{ DatabaseSizeGB = 8 }

        $legacy = ConvertTo-WsusLegacyDiagnosticResult -Report $report

        $legacy | Should -BeOfType [hashtable]
        $legacy.Healthy | Should -BeFalse
        $legacy.IssuesFound | Should -Be 1
        $legacy.Issues[0].Issue | Should -Be 'Database near limit'
        $legacy.Issues[0].Fix | Should -Be 'Decline superseded updates'
        $legacy.Checks.DatabaseSizeGB | Should -Be 8
        $legacy.DiagnosticReport | Should -Be $report
    }

    It 'merges reports without losing checks, evidence, fixes, or recommendations' {
        $first = New-WsusDiagnosticReport -Checks @((New-WsusDiagnosticCheckResult -CheckId 'a' -Status Pass)) -FixesApplied @('FixA') -Evidence @{ A = 1 } -Recommendations @('Keep monitoring')
        $second = New-WsusDiagnosticReport -Issues @((New-WsusDiagnosticIssue -Severity High -Message 'B' -CheckId 'b' -RepairAction 'FixB')) -FixesFailed @('FixB') -Evidence @{ B = 2 } -Recommendations @('Keep monitoring', 'Repair B')

        $merged = Merge-WsusDiagnosticReports -Reports @($first, $second)

        $merged.Checks.Count | Should -Be 1
        $merged.IssuesFound | Should -Be 1
        $merged.FixesApplied | Should -Contain 'FixA'
        $merged.FixesFailed | Should -Contain 'FixB'
        $merged.Evidence.A | Should -Be 1
        $merged.Evidence.B | Should -Be 2
        $merged.Recommendations.Count | Should -Be 2
    }
}
