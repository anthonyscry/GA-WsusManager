#Requires -Version 5.1
<#
.SYNOPSIS
    Startup probe result helpers for the WSUS Manager GUI.
.DESCRIPTION
    Shapes startup probe popup responses and writes E2E startup probe result files
    without requiring WPF automation.
#>

function Get-WsusGuiProbePopupResult {
    [CmdletBinding()]
    param([object]$Button = $null)

    $buttonText = if ($null -ne $Button) { $Button.ToString() } else { 'OK' }
    if ($buttonText -eq 'YesNo' -or $buttonText -eq 'YesNoCancel') { return 'No' }
    if ($buttonText -eq 'OKCancel') { return 'Cancel' }
    return 'OK'
}

function New-WsusGuiStartupProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason = '',
        [string]$FatalError = '',
        [int]$StartupProbeSeconds = 0,
        [string]$ResultPath = '',
        [object[]]$PopupEvents = @(),
        [datetime]$Timestamp = (Get-Date)
    )

    $errorPopups = @($PopupEvents | Where-Object { $_.icon -eq 'Error' -or $_.Icon -eq 'Error' })
    [pscustomobject]@{
        PSTypeName = 'Wsus.GuiStartupProbeResult'
        status = $Status
        reason = $Reason
        fatalError = $FatalError
        startupProbeSeconds = $StartupProbeSeconds
        resultPath = $ResultPath
        totalPopupCount = @($PopupEvents).Count
        errorPopupCount = $errorPopups.Count
        popupEvents = @($PopupEvents)
        timestamp = $Timestamp.ToString('o')
    }
}

function Write-WsusGuiStartupProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$ResultPath
    )

    $resultDir = Split-Path -Parent $ResultPath
    if (-not [string]::IsNullOrWhiteSpace($resultDir) -and -not (Test-Path $resultDir)) {
        New-Item -Path $resultDir -ItemType Directory -Force | Out-Null
    }

    $Result | ConvertTo-Json -Depth 6 | Set-Content -Path $ResultPath -Encoding UTF8
}

Export-ModuleMember -Function @(
    'Get-WsusGuiProbePopupResult',
    'New-WsusGuiStartupProbeResult',
    'Write-WsusGuiStartupProbeResult'
)
