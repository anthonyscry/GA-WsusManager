#Requires -Version 5.1
<#
.SYNOPSIS
    Shared diagnostic report interface for WSUS checks and repair planning.
.DESCRIPTION
    Provides a single diagnostic result shape so health, firewall, permission,
    database, IIS, SQL networking, and content checks can return evidence and
    repair-plan entries without leaking implementation-specific hashtables.
#>

function ConvertTo-WsusDiagnosticSeverity {
    [CmdletBinding()]
    param([string]$Severity)

    switch -Regex ([string]$Severity) {
        '^critical$' { 'Critical'; break }
        '^high$'     { 'High'; break }
        '^medium$'   { 'Medium'; break }
        '^low$'      { 'Low'; break }
        '^info$'     { 'Info'; break }
        default          { 'Info' }
    }
}

function ConvertTo-WsusDiagnosticIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]$InputObject,
        [switch]$IncludeLegacyAliases
    )

    process {
        $typeNames = @($InputObject.PSObject.TypeNames)
        $isDictionary = $InputObject -is [System.Collections.IDictionary]
        $messageProperty = $InputObject.PSObject.Properties['Message']
        $recommendationProperty = $InputObject.PSObject.Properties['Recommendation']

        if ($typeNames -contains 'Wsus.DiagnosticIssue' -and $messageProperty -and $recommendationProperty) {
            $issue = $InputObject
        } else {
            $message = if ($isDictionary -and $InputObject.Contains('Message')) { [string]$InputObject['Message'] } elseif ($isDictionary -and $InputObject.Contains('Issue')) { [string]$InputObject['Issue'] } elseif ($messageProperty) { [string]$messageProperty.Value } elseif ($InputObject.PSObject.Properties['Issue']) { [string]$InputObject.Issue } else { [string]$InputObject }
            $recommendation = if ($isDictionary -and $InputObject.Contains('Recommendation')) { [string]$InputObject['Recommendation'] } elseif ($isDictionary -and $InputObject.Contains('Fix')) { [string]$InputObject['Fix'] } elseif ($recommendationProperty) { [string]$recommendationProperty.Value } elseif ($InputObject.PSObject.Properties['Fix']) { [string]$InputObject.Fix } else { '' }
            $severityValue = if ($isDictionary -and $InputObject.Contains('Severity')) { [string]$InputObject['Severity'] } elseif ($InputObject.PSObject.Properties['Severity']) { [string]$InputObject.Severity } else { 'Info' }
            $checkId = if ($isDictionary -and $InputObject.Contains('CheckId')) { [string]$InputObject['CheckId'] } elseif ($InputObject.PSObject.Properties['CheckId']) { [string]$InputObject.CheckId } else { '' }
            $repairAction = if ($isDictionary -and $InputObject.Contains('RepairAction')) { [string]$InputObject['RepairAction'] } elseif ($InputObject.PSObject.Properties['RepairAction']) { [string]$InputObject.RepairAction } else { '' }
            $evidence = if ($isDictionary -and $InputObject.Contains('Evidence') -and $InputObject['Evidence'] -is [hashtable]) { $InputObject['Evidence'] } elseif ($InputObject.PSObject.Properties['Evidence'] -and $InputObject.Evidence -is [hashtable]) { $InputObject.Evidence } else { @{} }

            $issue = New-WsusDiagnosticIssue -Severity (ConvertTo-WsusDiagnosticSeverity -Severity $severityValue) -Message $message -Recommendation $recommendation -CheckId $checkId -RepairAction $repairAction -Evidence $evidence
        }

        if ($IncludeLegacyAliases) {
            $issue | Add-Member -NotePropertyName Issue -NotePropertyValue $issue.Message -Force
            $issue | Add-Member -NotePropertyName Fix -NotePropertyValue $issue.Recommendation -Force
        }

        $issue
    }
}

function New-WsusDiagnosticIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low','Info')][string]$Severity,
        [Parameter(Mandatory)][string]$Message,
        [string]$Recommendation = '',
        [string]$CheckId = '',
        [string]$RepairAction = '',
        [hashtable]$Evidence = @{}
    )

    [pscustomobject]@{
        PSTypeName = 'Wsus.DiagnosticIssue'
        CheckId = $CheckId
        Severity = $Severity
        Message = $Message
        Recommendation = $Recommendation
        RepairAction = $RepairAction
        Repairable = -not [string]::IsNullOrWhiteSpace($RepairAction)
        Evidence = $Evidence
    }
}

function New-WsusDiagnosticCheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CheckId,
        [Parameter(Mandatory)][ValidateSet('Pass','Fail','Warn','Skip')][string]$Status,
        [string]$Message = '',
        [hashtable]$Evidence = @{},
        [object[]]$Issues = @()
    )

    [pscustomobject]@{
        PSTypeName = 'Wsus.DiagnosticCheckResult'
        CheckId = $CheckId
        Status = $Status
        Message = $Message
        Evidence = $Evidence
        Issues = @($Issues)
    }
}

function New-WsusDiagnosticReport {
    [CmdletBinding()]
    param(
        [object[]]$Checks = @(),
        [object[]]$Issues = @(),
        [object[]]$FixesApplied = @(),
        [object[]]$FixesFailed = @(),
        [hashtable]$Evidence = @{},
        [string[]]$Recommendations = @()
    )

    $allIssues = New-Object System.Collections.Generic.List[object]
    foreach ($issue in @($Issues)) { $null = $allIssues.Add((ConvertTo-WsusDiagnosticIssue -InputObject $issue)) }
    foreach ($check in @($Checks)) {
        foreach ($issue in @($check.Issues)) { $null = $allIssues.Add((ConvertTo-WsusDiagnosticIssue -InputObject $issue)) }
    }

    $repairPlan = @($allIssues | Where-Object { $_.Repairable } | ForEach-Object {
        [pscustomobject]@{
            CheckId = $_.CheckId
            Action = $_.RepairAction
            Severity = $_.Severity
            Message = $_.Message
            Recommendation = $_.Recommendation
        }
    })

    [pscustomobject]@{
        PSTypeName = 'Wsus.DiagnosticReport'
        Healthy = ($allIssues.Count -eq 0)
        IssuesFound = [int]$allIssues.Count
        IssuesFixed = [int]@($FixesApplied).Count
        Checks = @($Checks)
        Issues = @($allIssues.ToArray())
        RepairPlan = @($repairPlan)
        FixesApplied = @($FixesApplied)
        FixesFailed = @($FixesFailed)
        Evidence = $Evidence
        Recommendations = @($Recommendations | Select-Object -Unique)
    }
}

function ConvertTo-WsusLegacyDiagnosticResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Report)

    @{
        Healthy = [bool]$Report.Healthy
        IssuesFound = [int]$Report.IssuesFound
        IssuesFixed = [int]$Report.IssuesFixed
        Issues = @($Report.Issues | ConvertTo-WsusDiagnosticIssue -IncludeLegacyAliases)
        FixesApplied = @($Report.FixesApplied)
        FixesFailed = @($Report.FixesFailed)
        Checks = $Report.Evidence
        Recommendations = @($Report.Recommendations)
        RepairPlan = @($Report.RepairPlan)
        DiagnosticReport = $Report
    }
}

function Merge-WsusDiagnosticReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Reports
    )

    $checks = @()
    $issues = @()
    $fixesApplied = @()
    $fixesFailed = @()
    $evidence = @{}
    $recommendations = @()

    foreach ($report in @($Reports | Where-Object { $_ })) {
        foreach ($check in @($report.Checks)) { $checks += $check }
        foreach ($issue in @($report.Issues)) { $issues += $issue }
        foreach ($fix in @($report.FixesApplied)) { $fixesApplied += $fix }
        foreach ($fix in @($report.FixesFailed)) { $fixesFailed += $fix }
        foreach ($key in @($report.Evidence.Keys)) { $evidence[$key] = $report.Evidence[$key] }
        foreach ($recommendation in @($report.Recommendations)) { $recommendations += $recommendation }
    }

    New-WsusDiagnosticReport -Checks $checks -Issues $issues -FixesApplied $fixesApplied -FixesFailed $fixesFailed -Evidence $evidence -Recommendations $recommendations
}

Export-ModuleMember -Function @(
    'ConvertTo-WsusDiagnosticIssue',
    'New-WsusDiagnosticIssue',
    'New-WsusDiagnosticCheckResult',
    'New-WsusDiagnosticReport',
    'ConvertTo-WsusLegacyDiagnosticResult',
    'Merge-WsusDiagnosticReports'
)