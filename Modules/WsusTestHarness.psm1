#Requires -Version 5.1
<#
.SYNOPSIS
    Shared test harness helpers for WSUS Manager tests.
.DESCRIPTION
    Concentrates repeated STA runspace setup and temporary workspace creation so
    warning-heavy tests use one interface instead of duplicating host setup.
#>

function Invoke-WsusStaHarness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string[]]$ModulePaths = @()
    )

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()

    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $paths = @($ModulePaths)
        $ps.AddScript({
            param($importPaths)
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction SilentlyContinue
            foreach ($path in $importPaths) {
                if ($path) { Import-Module $path -Force -DisableNameChecking }
            }
        }).AddArgument($paths) | Out-Null
        $ps.Invoke() | Out-Null
        if ($ps.HadErrors) { throw ($ps.Streams.Error | Select-Object -First 1).Exception }

        $ps.Commands.Clear()
        $ps.AddScript($ScriptBlock) | Out-Null
        $result = $ps.Invoke()
        if ($ps.HadErrors) { throw ($ps.Streams.Error | Select-Object -First 1).Exception }
        $result
    } finally {
        if ($ps) { $ps.Dispose() }
        $rs.Close()
        $rs.Dispose()
    }
}

function Resolve-WsusTestRepoRoot {
    [CmdletBinding()]
    param(
        [string]$StartPath = $PSScriptRoot
    )

    $resolved = Resolve-Path -Path $StartPath -ErrorAction Stop
    $current = [System.IO.DirectoryInfo]$resolved.ProviderPath
    while ($current) {
        if ((Test-Path (Join-Path $current.FullName 'Modules')) -and
            (Test-Path (Join-Path $current.FullName 'Scripts'))) {
            return $current.FullName
        }
        $current = $current.Parent
    }

    throw "Unable to resolve WSUS repository root from '$StartPath'."
}

function Get-WsusTestModulePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [string]$RepoRoot = (Resolve-WsusTestRepoRoot)
    )

    $name = if ($ModuleName.EndsWith('.psm1', [System.StringComparison]::OrdinalIgnoreCase)) {
        $ModuleName
    } else {
        "$ModuleName.psm1"
    }

    Join-Path (Join-Path $RepoRoot 'Modules') $name
}

function Import-WsusTestModule {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')][string]$ModuleName,
        [Parameter(Mandatory, ParameterSetName = 'ByPath')][string]$ModulePath,
        [string]$RepoRoot = (Resolve-WsusTestRepoRoot)
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $ModulePath = Get-WsusTestModulePath -ModuleName $ModuleName -RepoRoot $RepoRoot
    }

    Import-Module $ModulePath -Global -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
}

function Remove-WsusTestModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ModuleName
    )

    foreach ($name in $ModuleName) {
        Remove-Module $name -ErrorAction SilentlyContinue
    }
}

function Get-WsusTestFileText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [string]$RepoRoot = (Resolve-WsusTestRepoRoot)
    )

    Get-Content -Path (Join-Path $RepoRoot $RelativePath) -Raw -ErrorAction Stop
}

function Resolve-WsusGuiExecutablePath {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = (Resolve-WsusTestRepoRoot)
    )

    $candidates = @(
        (Join-Path $RepoRoot 'dist\GA-WsusManager.exe'),
        (Join-Path $RepoRoot 'dist\WsusManager.exe'),
        (Join-Path $RepoRoot 'GA-WsusManager.exe'),
        (Join-Path $RepoRoot 'WsusManager.exe'),
        (Join-Path $RepoRoot 'Scripts\WsusManagementGui.ps1')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

function Test-WsusFlaUIAssembliesAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HarnessPath
    )

    if (-not (Test-Path $HarnessPath)) { return $false }

    try {
        Import-Module $HarnessPath -Global -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
    } catch {
        return $false
    }

    try {
        $null = [FlaUI.UIA2.UIA2Automation]::new()
        return $true
    } catch {
        try {
            $null = [FlaUI.UIA3.UIA3Automation]::new()
            return $true
        } catch {
            return $false
        }
    }
}

function Stop-WsusTestProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force
    )

    if ($env:OS -ne 'Windows_NT') { return }

    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return }

    if ($Force) {
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    } else {
        $processes | Stop-Process -ErrorAction SilentlyContinue
    }
}

function New-WsusTestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    $Path
}

function New-WsusTempHarnessRoot {
    [CmdletBinding()]
    param(
        [string]$Prefix = 'WsusHarness'
    )

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("{0}_{1}" -f $Prefix, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $path
}

function New-WsusTestEvidenceRoot {
    [CmdletBinding()]
    param(
        [string]$Prefix = 'WsusEvidence'
    )

    New-WsusTempHarnessRoot -Prefix $Prefix
}

function New-WsusTestArtifactPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$FileName
    )

    if (-not (Test-Path $RootPath)) {
        New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
    }
    Join-Path $RootPath $FileName
}

function Write-WsusTestJsonEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$InputObject
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $InputObject | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    $Path
}

Export-ModuleMember -Function @(
    'Invoke-WsusStaHarness',
    'Resolve-WsusTestRepoRoot',
    'Get-WsusTestModulePath',
    'Import-WsusTestModule',
    'Remove-WsusTestModule',
    'Get-WsusTestFileText',
    'Resolve-WsusGuiExecutablePath',
    'Test-WsusFlaUIAssembliesAvailable',
    'Stop-WsusTestProcess',
    'New-WsusTestDirectory',
    'New-WsusTempHarnessRoot',
    'New-WsusTestEvidenceRoot',
    'New-WsusTestArtifactPath',
    'Write-WsusTestJsonEvidence'
)
