#Requires -Version 5.1
<#
.SYNOPSIS
    Provisioning helpers for WSUS install and restore workflows.
.DESCRIPTION
    Concentrates SQL installer discovery, backup resolution, and path validation
    so GUI and CLI callers use one interface before starting destructive work.
#>

$script:WsusSqlInstallerCandidates = @(
    'SQL2025-SSEI-Expr.exe',
    'SQLEXPRADV_x64_ENU.exe',
    'SQLEXPR_x64_ENU.exe'
)

function Get-WsusSqlInstallerCandidates {
    [CmdletBinding()]
    param()

    @($script:WsusSqlInstallerCandidates)
}

function Find-WsusSqlInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallerPath
    )

    foreach ($name in $script:WsusSqlInstallerCandidates) {
        $candidate = Join-Path $InstallerPath $name
        if (Test-Path $candidate) {
            return [pscustomobject]@{
                PSTypeName = 'Wsus.SqlInstallerResolution'
                Success = $true
                InstallerPath = $InstallerPath
                InstallerFile = $candidate
                InstallerName = $name
                Message = ''
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Wsus.SqlInstallerResolution'
        Success = $false
        InstallerPath = $InstallerPath
        InstallerFile = $null
        InstallerName = $null
        Message = "No SQL Express installer found in $InstallerPath. Expected one of: $($script:WsusSqlInstallerCandidates -join ', ')"
    }
}

function Resolve-WsusInstallerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallerPath
    )

    if (-not (Test-Path $InstallerPath)) {
        return [pscustomobject]@{
            PSTypeName = 'Wsus.SqlInstallerResolution'
            Success = $false
            InstallerPath = $InstallerPath
            InstallerFile = $null
            InstallerName = $null
            Message = "Installer folder not found: $InstallerPath"
        }
    }

    Find-WsusSqlInstaller -InstallerPath $InstallerPath
}

function Resolve-WsusRestoreBackup {
    [CmdletBinding()]
    param(
        [string]$BackupPath,
        [string]$ContentPath = 'C:\WSUS'
    )

    if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
        if (-not (Test-Path $BackupPath)) {
            return [pscustomobject]@{
                PSTypeName = 'Wsus.RestoreBackupResolution'
                Success = $false
                BackupFile = $null
                Message = "Backup file not found: $BackupPath"
            }
        }

        $backupItem = Get-Item $BackupPath -ErrorAction Stop
        if ($backupItem.Extension -ne '.bak') {
            return [pscustomobject]@{
                PSTypeName = 'Wsus.RestoreBackupResolution'
                Success = $false
                BackupFile = $null
                Message = "Backup file must be a .bak file: $BackupPath"
            }
        }

        return [pscustomobject]@{
            PSTypeName = 'Wsus.RestoreBackupResolution'
            Success = $true
            BackupFile = $backupItem.FullName
            Message = ''
        }
    }

    $backups = Get-ChildItem -Path $ContentPath -Filter '*.bak' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if (-not $backups -or $backups.Count -eq 0) {
        return [pscustomobject]@{
            PSTypeName = 'Wsus.RestoreBackupResolution'
            Success = $false
            BackupFile = $null
            Message = "No .bak files found in $ContentPath"
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Wsus.RestoreBackupResolution'
        Success = $true
        BackupFile = $backups[0].FullName
        Message = ''
    }
}

function Test-WsusProvisioningPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $invalid = [System.IO.Path]::GetInvalidPathChars()
        foreach ($char in $invalid) {
            if ($Path.Contains([string]$char)) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Get-WsusSqlInstallerCandidates',
    'Find-WsusSqlInstaller',
    'Resolve-WsusInstallerPath',
    'Resolve-WsusRestoreBackup',
    'Test-WsusProvisioningPath'
)
