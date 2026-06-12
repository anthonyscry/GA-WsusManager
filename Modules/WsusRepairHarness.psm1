# WsusRepairHarness stub in v4.1 — only the test-facing New-WsusRepairIssueFixture
# helper remains here. The runtime harness logic was inlined into WsusHealth.
# The function is intentionally NOT moved to WsusHealth because
# WsusArchitectureInterfaces.Tests.ps1 asserts it lives in this module.
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
