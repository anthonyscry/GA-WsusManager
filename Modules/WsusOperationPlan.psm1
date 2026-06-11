#Requires -Version 5.1
<#
.SYNOPSIS
    Shared operation command planning for WSUS Manager GUI and CLI adapters.
.DESCRIPTION
    Separates operation selection from process execution. A plan contains the
    executable command, display title, preferred output mode, timeout, and any
    environment variables required by the operation.
#>

function ConvertTo-WsusCommandLiteral {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return "''" }
    return "'$($Value -replace "'", "''")'"
}


function ConvertFrom-WsusSecureString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Security.SecureString]$Value)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
function New-WsusOperationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Command,
        [AllowNull()][ValidateSet('Embedded','Terminal')][string]$Mode = $null,
        [int]$TimeoutMinutes = 30,
        [hashtable]$Environment = @{},
        [hashtable]$Metadata = @{}
    )

    [pscustomobject]@{
        PSTypeName = 'Wsus.OperationPlan'
        Id = $Id
        Title = $Title
        Command = $Command
        Mode = $Mode
        TimeoutMinutes = $TimeoutMinutes
        Environment = $Environment
        Metadata = $Metadata
    }
}

function New-WsusManagementOperationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('cleanup','diagnostics','reset','restore')][string]$Id,
        [Parameter(Mandatory)][string]$ManagementScriptPath,
        [string]$ContentPath = 'C:\WSUS',
        [string]$SqlInstance = '.\SQLEXPRESS',
        [string]$BackupPath = ''
    )

    $script = ConvertTo-WsusCommandLiteral $ManagementScriptPath
    $content = ConvertTo-WsusCommandLiteral $ContentPath
    $sql = ConvertTo-WsusCommandLiteral $SqlInstance

    switch ($Id) {
        'cleanup' {
            New-WsusOperationPlan -Id $Id -Title 'Deep Cleanup' -Command "& $script -Cleanup -Force -SqlInstance $sql" -TimeoutMinutes 60
        }
        'diagnostics' {
            New-WsusOperationPlan -Id $Id -Title 'Deep Diagnostics' -Command "`$null = & $script -DeepDiagnostics -ContentPath $content -SqlInstance $sql" -TimeoutMinutes 30
        }
        'reset' {
            New-WsusOperationPlan -Id $Id -Title 'Reset Content' -Command "& $script -Reset" -TimeoutMinutes 180
        }
        'restore' {
            if ([string]::IsNullOrWhiteSpace($BackupPath)) { throw 'BackupPath is required for restore operation plans.' }
            $backup = ConvertTo-WsusCommandLiteral $BackupPath
            New-WsusOperationPlan -Id $Id -Title 'Restore Database' -Command "& $script -Restore -ContentPath $content -SqlInstance $sql -BackupPath $backup" -TimeoutMinutes 60
        }
    }
}

function New-WsusInstallOperationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallScriptPath,
        [Parameter(Mandatory)][string]$InstallerPath,
        [string]$SaUsername = 'sa',
        [Parameter(Mandatory)][Security.SecureString]$SaPassword
    )

    $script = ConvertTo-WsusCommandLiteral $InstallScriptPath
    $installer = ConvertTo-WsusCommandLiteral $InstallerPath
    $user = ConvertTo-WsusCommandLiteral $SaUsername
    $passwordValue = ConvertFrom-WsusSecureString -Value $SaPassword
    $secret = New-WsusOperationPlan -Id 'install' -Title 'Install WSUS' `
        -Command "& $script -InstallerPath $installer -SaUsername $user -SaPasswordEnvVar WSUS_INSTALL_SA_PASSWORD -NonInteractive" `
        -TimeoutMinutes 180 `
        -Environment @{ WSUS_INSTALL_SA_PASSWORD = $passwordValue }
    $secret
}

function New-WsusMaintenanceOperationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MaintenanceScriptPath,
        [ValidateSet('Full','Quick','SyncOnly')][string]$Profile = 'Full',
        [string]$ExportPath = '',
        [string[]]$SelectedProducts = @()
    )

    $script = ConvertTo-WsusCommandLiteral $MaintenanceScriptPath
    $command = "& $script -Unattended -MaintenanceProfile '$Profile' -NoTranscript -UseWindowsAuth"
    if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
        $command += " -ExportPath $(ConvertTo-WsusCommandLiteral $ExportPath)"
    } else {
        $command += " -SkipExport"
    }
    if (@($SelectedProducts).Count -gt 0) {
        $safeProducts = @($SelectedProducts | ForEach-Object { ConvertTo-WsusCommandLiteral $_ })
        $command += " -SelectedProducts $($safeProducts -join ',')"
    }

    New-WsusOperationPlan -Id 'maintenance' -Title "Online Sync ($Profile)" -Command $command -TimeoutMinutes 180
}

function New-WsusScheduleOperationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskModulePath,
        [Parameter(Mandatory)][ValidateSet('Weekly','Monthly','Daily')][string]$Schedule,
        [Parameter(Mandatory)][string]$Time,
        [Parameter(Mandatory)][ValidateSet('Full','Quick','SyncOnly')][string]$Profile,
        [Parameter(Mandatory)][string]$RunAsUser,
        [Parameter(Mandatory)][Security.SecureString]$Password,
        [string]$DayOfWeek = 'Tuesday',
        [int]$DayOfMonth = 1
    )

    $taskModule = ConvertTo-WsusCommandLiteral $TaskModulePath
    $runAsUserSafe = ConvertTo-WsusCommandLiteral $RunAsUser
    $args = "-Schedule '$Schedule' -Time '$Time' -MaintenanceProfile '$Profile' -RunAsUser $runAsUserSafe"
    if ($Schedule -eq 'Weekly') {
        $args += " -DayOfWeek '$DayOfWeek'"
    } elseif ($Schedule -eq 'Monthly') {
        $args += " -DayOfMonth $DayOfMonth"
    }


    $passwordValue = ConvertFrom-WsusSecureString -Value $Password
    New-WsusOperationPlan -Id 'schedule' -Title "Schedule Task ($Schedule)" `
        -Command "& { Import-Module $taskModule -Force -DisableNameChecking; `$secPwd = ConvertTo-SecureString `$env:WSUS_TASK_PASSWORD -AsPlainText -Force; New-WsusMaintenanceTask $args -UserPassword `$secPwd | Out-Null }" `
        -TimeoutMinutes 30 `
        -Environment @{ WSUS_TASK_PASSWORD = $passwordValue }
}


function New-WsusTransferOperationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [ValidateSet('Embedded','Terminal')][string]$Mode = 'Embedded'
    )

    $source = ConvertTo-WsusCommandLiteral $SourcePath
    $destination = ConvertTo-WsusCommandLiteral $DestinationPath
    $command = "robocopy $source $destination /E /ZB /COPY:DAT /DCOPY:T /R:1 /W:1 /NDL /NP; if (`$LASTEXITCODE -le 7) { exit 0 } else { exit `$LASTEXITCODE }"
    New-WsusOperationPlan -Id 'transfer' -Title "Transfer ($SourcePath -> $DestinationPath)" -Command $command -Mode $Mode -TimeoutMinutes 180
}
Export-ModuleMember -Function @(
    'ConvertTo-WsusCommandLiteral',
    'ConvertFrom-WsusSecureString',
    'New-WsusOperationPlan',
    'New-WsusManagementOperationPlan',
    'New-WsusInstallOperationPlan',
    'New-WsusMaintenanceOperationPlan',
    'New-WsusScheduleOperationPlan',
    'New-WsusTransferOperationPlan'
)