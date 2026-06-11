# WsusRepairHarness removed in v4.1 — New-WsusRepairIssueFixture merged into WsusHealth
function New-WsusRepairIssueFixture {
    [CmdletBinding()]
    param(
        [string]$Severity = 'High',
        [string]$Message = 'Repair issue',
        [string]$RepairAction = ''
    )
    if (Get-Command New-WsusDiagnosticIssue -ErrorAction SilentlyContinue) {
        return New-WsusDiagnosticIssue -Severity $Severity -Message $Message -Recommendation 'Fix it' -RepairAction $RepairAction -CheckId 'fixture'
    }
    [pscustomobject]@{
        Severity = $Severity
        Message = $Message
        Recommendation = 'Fix it'
        RepairAction = $RepairAction
        Repairable = -not [string]::IsNullOrWhiteSpace($RepairAction)
    }
}
