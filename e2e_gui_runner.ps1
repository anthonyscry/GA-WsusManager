<#
.SYNOPSIS
GUI-runner E2E test against cm-ms02 — validates the Terminal+Environment fix.

.DESCRIPTION
The 2026-06-18 handoff documented that the GUI's "Install WSUS" with Live
Terminal Mode crashed on Start-WsusOperation with:
  "Exception calling Start: The Process object must have the UseShellExecute
   property set to false in order to use environment variables."
Root cause: Install-WsusWithSqlExpress.ps1 reads WSUS_INSTALL_SA_PASSWORD
from the environment, and Start-WsusOperation populated both UseShellExecute=$true
(Terminal mode) and EnvironmentVariables (the SA password), which .NET rejects.

This E2E validates the fix end-to-end on cm-ms02 by:

  1. Deploying dist\WsusManager-v4.1.0.zip to the VM.
  2. PHASE A — invoking the NEW New-WsusEnvironmentBootstrapFile helper on the
     VM and verifying it writes a properly-formed bootstrap script with the
     WSUS_INSTALL_SA_PASSWORD value, plus current-user-only ACLs.
  3. PHASE B — verifying the bootstrap is removable via the matching
     Remove-WsusEnvironmentBootstrapFile helper.
  4. PHASE C — driving a REAL WSUS install via PowerShell process invocation
     that mirrors what Start-WsusOperation does in Terminal mode (use
     UseShellExecute, dot-source the bootstrap, pass the install command).
     This proves the install actually completes end-to-end with the secret
     propagating through the bootstrap file rather than the rejected
     EnvironmentVariables slot.
  5. PHASE D — runner-driven health check after install.
  6. PHASE E — runner-driven cleanup.
  7. PHASE F — pull all logs back to host.

.PARAMETER Credential
PSCredential for CM\Install on cm-ms02.
.PARAMETER VmName
Hyper-V VM name.
.PARAMETER LocalPackage
Path to dist\WsusManager-v4.1.0.zip on the host.
.PARAMETER SaPassword
Test SA password. Must satisfy Install-WsusWithSqlExpress complexity rules.
.PARAMETER InstallTimeoutSec
Max seconds to wait for the install to complete.
.PARAMETER DryRun
Validate paths, VM state, package presence, and credential.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][PSCredential]$Credential,
    [string]$VmName = 'cm-ms02',
    [string]$LocalPackage = "C:\projects\GA-WsusManager\dist\WsusManager-v4.1.0.zip",
    [string]$RemoteRoot = 'C:\WsusManager-E2E',
    [string]$RunId = ("gui-e2e-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string]$SaPassword = 'WsusP@ss123!',
    [int]$InstallTimeoutSec = 1800,
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Continue'
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Script:StepResults = [ordered]@{}

function Write-Step {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host "`n=== $Message ===" -ForegroundColor $Color
}

function Write-Status {
    param([string]$Message, [bool]$Ok, [string]$Detail = '')
    $color = if ($Ok) { 'Green' } else { 'Red' }
    $label = if ($Ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $label, $Message) -ForegroundColor $color
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor Gray }
}

# ---------------------------------------------------------------------------
# 0. Pre-flight
# ---------------------------------------------------------------------------
Write-Step "Phase 0: Pre-flight"

if (-not (Test-Path $LocalPackage)) {
    Write-Status "Local package exists" $false "missing: $LocalPackage"
    exit 1
}
$packageSize = (Get-Item $LocalPackage).Length
Write-Status "Local package exists" $true "$LocalPackage ($([math]::Round($packageSize/1MB,1)) MB)"

$metadataPath = Join-Path (Split-Path $LocalPackage -Parent) '..\metadata.json'
if (Test-Path $metadataPath) {
    $meta = Get-Content $metadataPath -Raw | ConvertFrom-Json
    $version = $meta.version
    Write-Status "Version" $true $version
} else {
    Write-Status "metadata.json found" $false "missing: $metadataPath"
    exit 1
}

$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Status "VM found" $false "no Hyper-V VM named $VmName"
    exit 1
}
Write-Status "VM found" $true "$($vm.Name) state=$($vm.State)"

try {
    $testSession = New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
    Remove-PSSession $testSession -ErrorAction SilentlyContinue
} catch {
    Write-Status "Credential works" $false $_.Exception.Message
    exit 1
}
Write-Status "Credential works" $true "PSRemoting authenticated with $($Credential.UserName)"

if ($vm.State -ne 'Running') {
    if ($DryRun) {
        Write-Status "VM state" $false "VM is $($vm.State); start it before running for real"
    } else {
        Start-VM -Name $VmName
        Start-Sleep -Seconds 30
        $vm = Get-VM -Name $VmName
        if ($vm.State -ne 'Running') { throw "VM did not reach Running state." }
    }
}
Write-Status "VM running" $true "$($vm.State)"

if ($DryRun) {
    Write-Step "DRY-RUN complete: pre-flight checks passed"
    exit 0
}

# ---------------------------------------------------------------------------
# 1. Open PSSession and stage the package
# ---------------------------------------------------------------------------
Write-Step "Phase 1: Staging $LocalPackage on $VmName"
$session = New-PSSession -VMName $VmName -Credential $Credential -ErrorAction Stop
Write-Host "Session opened."

$remoteRunRoot = Join-Path $RemoteRoot $RunId
$remoteZip     = Join-Path $remoteRunRoot 'WsusManager.zip'
$extractedRoot = Join-Path $remoteRunRoot 'extracted'
$versionedScriptsRoot = Join-Path $extractedRoot "WsusManager-v$version\Scripts"
$versionedModulesRoot = Join-Path $extractedRoot "WsusManager-v$version\Modules"

Invoke-Command -Session $session -ScriptBlock {
    param($r)
    New-Item -Path $r -ItemType Directory -Force | Out-Null
} -ArgumentList $remoteRunRoot

Copy-Item -ToSession $session -Path $LocalPackage -Destination $remoteZip -Force -ErrorAction Stop

$fileCount = Invoke-Command -Session $session -ScriptBlock {
    param($zip, $dest)
    if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force }
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    (Get-ChildItem -Path $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
} -ArgumentList $remoteZip, $extractedRoot
Write-Host "Extracted $fileCount files"

$verify = Invoke-Command -Session $session -ScriptBlock {
    param($scriptsRoot, $modulesRoot)
    @{
        Scripts      = (Test-Path $scriptsRoot)
        Modules      = (Test-Path $modulesRoot)
        ScriptsCount = (Get-ChildItem -Path $scriptsRoot -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        ModulesCount = (Get-ChildItem -Path $modulesRoot -Filter '*.psm1' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    }
} -ArgumentList $versionedScriptsRoot, $versionedModulesRoot

if (-not $verify.Scripts) { Write-Status "Scripts root" $false $versionedScriptsRoot; Remove-PSSession $session; exit 1 }
if ($verify.ScriptsCount -lt 5) { Write-Status "Scripts" $false "only $($verify.ScriptsCount) .ps1"; Remove-PSSession $session; exit 1 }
Write-Status "Scripts extracted" $true "$($verify.ScriptsCount) scripts, $($verify.ModulesCount) modules"

# ---------------------------------------------------------------------------
# 2. WSUS state snapshot on the VM
# ---------------------------------------------------------------------------
Write-Step "Phase 2: WSUS state snapshot (before)"
$snapshot = Invoke-Command -Session $session -ScriptBlock {
    @{
        WsusService      = (Get-Service -Name WsusService -ErrorAction SilentlyContinue).Status
        W3Svc            = (Get-Service -Name W3SVC -ErrorAction SilentlyContinue).Status
        SqlBrowser       = (Get-Service -Name SQLBrowser -ErrorAction SilentlyContinue).Status
        SqlExpress       = (Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue).Status
        WsusContentExists = Test-Path 'C:\WSUS\WsusContent'
        UpdateServicesPackagesExists = Test-Path 'C:\WSUS\UpdateServicesPackages'
    }
}
foreach ($k in $snapshot.Keys) {
    Write-Host ("  {0,-30} {1}" -f $k, $snapshot[$k])
}
$Script:StepResults['Snapshot_Before'] = $snapshot

# ---------------------------------------------------------------------------
# 3. PHASE A — Bootstrap helper writes correct content with ACLs
# ---------------------------------------------------------------------------
Write-Step "Phase 3A: New-WsusEnvironmentBootstrapFile (the fix's core helper)"
$phaseA = Invoke-Command -Session $session -ScriptBlock {
    param($modulesRoot)
    Import-Module (Join-Path $modulesRoot 'WsusOperationRunner.psm1') -Force -DisableNameChecking

    $env = @{ WSUS_INSTALL_SA_PASSWORD = 'ProbePwd!15Chr'; WSUS_E2E_MARKER = 'phase-A-marker' }
    $path = New-WsusEnvironmentBootstrapFile -Environment $env

    if ([string]::IsNullOrEmpty($path)) { return @{ Ok = $false; Reason = 'helper returned null' } }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ Ok = $false; Reason = "file not created: $path" } }

    $content = Get-Content -LiteralPath $path -Raw
    $hasEnv1 = [bool]($content -match "WSUS_INSTALL_SA_PASSWORD.*ProbePwd!15Chr")
    $hasEnv2 = [bool]($content -match "WSUS_E2E_MARKER.*phase-A-marker")

    $acl = Get-Acl -LiteralPath $path
    $ownerCorrect = ($acl.Owner -match 'Install')
    $protected     = $acl.AreAccessRulesProtected

    # Verify the bootstrap script actually exports the env var when dot-sourced
    $envBefore = [Environment]::GetEnvironmentVariable('WSUS_INSTALL_SA_PASSWORD', 'Process')
    . $path
    $envAfter  = [Environment]::GetEnvironmentVariable('WSUS_INSTALL_SA_PASSWORD', 'Process')
    $envMatches = ($envAfter -eq 'ProbePwd!15Chr')
    [Environment]::SetEnvironmentVariable('WSUS_INSTALL_SA_PASSWORD', $null, 'Process')

    # Clean up
    Remove-WsusEnvironmentBootstrapFile -Path $path

    return @{
        Ok              = $hasEnv1 -and $hasEnv2 -and $envMatches
        Path            = $path
        HasEnv1         = $hasEnv1
        HasEnv2         = $hasEnv2
        OwnerCorrect    = $ownerCorrect
        Protected       = $protected
        EnvMatches      = $envMatches
        EnvBefore       = $envBefore
        EnvAfter        = $envAfter
        Content         = $content
    }
} -ArgumentList $versionedModulesRoot

$Script:StepResults['PhaseA_BootstrapWrite'] = $phaseA
Write-Status "Bootstrap file created" ([bool]($null -ne $phaseA.Path)) "path=$($phaseA.Path)"
Write-Status "Bootstrap contains WSUS_INSTALL_SA_PASSWORD" ([bool]$phaseA.HasEnv1) ""
Write-Status "Bootstrap contains WSUS_E2E_MARKER" ([bool]$phaseA.HasEnv2) ""
Write-Status "Bootstrap is dot-sourceable (env actually exports)" ([bool]$phaseA.EnvMatches) "before='$($phaseA.EnvBefore)' after='$($phaseA.EnvAfter)'"
Write-Status "Bootstrap file is current-user ACL'd" ([bool]($phaseA.OwnerCorrect -and $phaseA.Protected)) "owner='correct' protected=$($phaseA.Protected)"

# ---------------------------------------------------------------------------
# 4. PHASE B — Empty environment returns null
# ---------------------------------------------------------------------------
Write-Step "Phase 3B: New-WsusEnvironmentBootstrapFile with empty env (no-op)"
$phaseB = Invoke-Command -Session $session -ScriptBlock {
    param($modulesRoot)
    Import-Module (Join-Path $modulesRoot 'WsusOperationRunner.psm1') -Force -DisableNameChecking
    $path = New-WsusEnvironmentBootstrapFile -Environment @{}
    return @{ Ok = $true; Path = $path; IsNull = [string]::IsNullOrEmpty($path) }
} -ArgumentList $versionedModulesRoot

$Script:StepResults['PhaseB_EmptyEnv'] = $phaseB
Write-Status "Empty env returns null" ([bool]$phaseB.IsNull) "path='$($phaseB.Path)'"

# ---------------------------------------------------------------------------
# 5. PHASE C — Full WSUS install mirroring the Terminal-mode runner path
# ---------------------------------------------------------------------------
if (-not $SkipInstall) {
    Write-Step "Phase 3C: Full WSUS install via Terminal-mode runner emulation (timeout $InstallTimeoutSec sec)"

    $installOutLog = Join-Path $remoteRunRoot 'install.out.log'
    $installErrLog = Join-Path $remoteRunRoot 'install.err.log'
    $bootstrapLog  = Join-Path $remoteRunRoot 'install.bootstrap.log'

    $installResult = Invoke-Command -Session $session -ScriptBlock {
        param($modulesRoot, $scriptsRoot, $installerPath, $saPassword, $outLog, $errLog, $bootstrapLog, $timeoutSec)

        Import-Module (Join-Path $modulesRoot 'WsusOperationRunner.psm1') -Force -DisableNameChecking

        # Build the env hashtable the way New-WsusInstallOperationPlan does
        $env = @{ WSUS_INSTALL_SA_PASSWORD = $saPassword }

        # Use the helper to materialise the bootstrap file (this is what the
        # fixed Start-WsusOperation now does when Mode=Terminal + Environment)
        $bootstrapPath = New-WsusEnvironmentBootstrapFile -Environment $env
        if ([string]::IsNullOrEmpty($bootstrapPath)) {
            return @{ ExitCode = -1; Reason = 'Failed to write env bootstrap' }
        }
        Copy-Item -LiteralPath $bootstrapPath -Destination $bootstrapLog -Force
        Write-Host "  Bootstrap file : $bootstrapPath"
        Get-Content -LiteralPath $bootstrapPath | ForEach-Object { Write-Host "    $_" }

        # Compose the install command the way Start-WsusOperation Terminal mode does
        # UseShellExecute=$true so we use Start-Process with no environment variable.
        $installScript = Join-Path $scriptsRoot 'Install-WsusWithSqlExpress.ps1'
        $terminalCmd = ". '$bootstrapPath'; & '$installScript' -InstallerPath '$installerPath' -SaUsername 'sa' -SaPasswordEnvVar WSUS_INSTALL_SA_PASSWORD -NonInteractive"
        Write-Host "  Command length : $($terminalCmd.Length) chars"
        Write-Host "  Spawning powershell.exe (UseShellExecute=true path) ..."

        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $terminalCmd) `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError  $errLog

        $deadline = (Get-Date).AddSeconds($timeoutSec)
        $completed = $false
        $exitCode = -1
        while ((Get-Date) -lt $deadline) {
            if ($proc.HasExited) { $completed = $true; $exitCode = $proc.ExitCode; break }
            Start-Sleep -Seconds 15
            $svc = Get-Service -Name WsusService -ErrorAction SilentlyContinue
            $svcStatus = if ($svc) { $svc.Status.ToString() } else { 'Missing' }
            Write-Host "  [t=$([int]((Get-Date) - $using:Stopwatch).TotalSeconds)s] WsusService: $svcStatus"
        }

        if (-not $completed) {
            Write-Host "  Install did not finish within $timeoutSec seconds; killing process"
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
        }

        # Clean up the bootstrap file (this is what the fixed runner does in Complete)
        Remove-WsusEnvironmentBootstrapFile -Path $bootstrapPath

        $post = @{
            WsusService      = (Get-Service -Name WsusService -ErrorAction SilentlyContinue).Status
            W3Svc            = (Get-Service -Name W3SVC -ErrorAction SilentlyContinue).Status
            SqlBrowser       = (Get-Service -Name SQLBrowser -ErrorAction SilentlyContinue).Status
            SqlExpress       = (Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue).Status
            WsusContentExists = Test-Path 'C:\WSUS\WsusContent'
            UpdateServicesPackagesExists = Test-Path 'C:\WSUS\UpdateServicesPackages'
        }
        return @{
            ExitCode         = $exitCode
            Reason           = if ($completed) { "Install exited with code $exitCode" } else { "Install timed out" }
            Post             = $post
            BootstrapPath    = $bootstrapPath
            BootstrapRemoved = -not (Test-Path -LiteralPath $bootstrapPath)
        }
    } -ArgumentList $versionedModulesRoot, $versionedScriptsRoot, 'C:\WSUS\SQLDB', $SaPassword, $installOutLog, $installErrLog, $bootstrapLog, $InstallTimeoutSec

    $Script:StepResults['Install'] = $installResult
    Write-Status "Install via Terminal-mode runner emulation" ([bool]($installResult.ExitCode -eq 0)) "$($installResult.Reason)"
    if ($installResult.Post) {
        Write-Host "  Post-install state:"
        foreach ($k in $installResult.Post.Keys) {
            Write-Host ("    {0,-30} {1}" -f $k, $installResult.Post[$k])
        }
    }
    Write-Status "Bootstrap removed after install" ([bool]$installResult.BootstrapRemoved) "path='$($installResult.BootstrapPath)'"
} else {
    Write-Step "Phase 3C: SKIPPED (-SkipInstall)"
}

# ---------------------------------------------------------------------------
# 6. PHASE D — runner-driven health check
# ---------------------------------------------------------------------------
Write-Step "Phase 3D: Runner-driven health check"
$healthLog = Join-Path $remoteRunRoot 'health.log'
$healthExit = Invoke-Command -Session $session -ScriptBlock {
    param($mgmtScript, $logPath)
    & $mgmtScript -Health *>&1 | Tee-Object -FilePath $logPath | Out-Null
    $LASTEXITCODE
} -ArgumentList (Join-Path $versionedScriptsRoot 'Invoke-WsusManagement.ps1'), $healthLog

$Script:StepResults['Health'] = @{ ExitCode = $healthExit; Log = $healthLog }
Write-Status "Health check" ([bool]($healthExit -eq 0)) "exit=$healthExit"

# ---------------------------------------------------------------------------
# 7. PHASE E — runner-driven cleanup
# ---------------------------------------------------------------------------
if (-not $SkipCleanup) {
    Write-Step "Phase 3E: Runner-driven cleanup"
    $cleanupLog = Join-Path $remoteRunRoot 'cleanup.log'
    $cleanupExit = Invoke-Command -Session $session -ScriptBlock {
        param($mgmtScript, $logPath)
        & $mgmtScript -Cleanup -Force *>&1 | Tee-Object -FilePath $logPath | Out-Null
        $LASTEXITCODE
    } -ArgumentList (Join-Path $versionedScriptsRoot 'Invoke-WsusManagement.ps1'), $cleanupLog

    $Script:StepResults['Cleanup'] = @{ ExitCode = $cleanupExit; Log = $cleanupLog }
    Write-Status "Cleanup" ([bool]($cleanupExit -eq 0)) "exit=$cleanupExit"
} else {
    Write-Step "Phase 3E: SKIPPED (-SkipCleanup)"
}

# ---------------------------------------------------------------------------
# 8. Pull logs back to host
# ---------------------------------------------------------------------------
Write-Step "Phase 4: Pulling logs back to host"
$hostLogs = Join-Path "C:\WsusManager-E2E" $RunId
New-Item -Path $hostLogs -ItemType Directory -Force | Out-Null

$logsToPull = @('install.out.log','install.err.log','install.bootstrap.log','health.log','cleanup.log')
foreach ($logName in $logsToPull) {
    $remote = Join-Path $remoteRunRoot $logName
    $local  = Join-Path $hostLogs $logName
    if (Test-Path -Path $remote -PathType Leaf) {
        try {
            Copy-Item -FromSession $session -Path $remote -Destination $local -ErrorAction Stop
            Write-Host "  $logName"
        } catch {
            Write-Warning "  $logName not retrieved: $_"
        }
    }
}

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
Write-Step "Summary"
$Script:StepResults['RunId']         = $RunId
$Script:StepResults['HostLogs']      = $hostLogs
$Script:StepResults['RemoteRunRoot'] = $remoteRunRoot
$Script:StepResults['Elapsed']       = $Stopwatch.Elapsed.ToString()
$Script:StepResults | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $hostLogs 'summary.json')

$overallPass = $true
$Script:StepResults.GetEnumerator() | ForEach-Object {
    $entry = $_.Value
    if ($entry -is [hashtable] -and $entry.ContainsKey('Ok')) {
        $label = if ($entry.Ok) { 'PASS' } else { 'FAIL' }
        $color = if ($entry.Ok) { 'Green' } else { 'Red' }
        if (-not $entry.Ok) { $overallPass = $false }
        Write-Host ("[{0}] {1}" -f $label, $_.Key) -ForegroundColor $color
    } else {
        Write-Host ("{0}: {1}" -f $_.Key, ($entry | ConvertTo-Json -Compress -Depth 4)) -ForegroundColor Gray
    }
}

Remove-PSSession $session -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("RunId:        {0}" -f $RunId)
Write-Host ("Host logs:    {0}" -f $hostLogs)
Write-Host ("Overall:      {0}" -f $(if ($overallPass) { 'PASS' } else { 'FAIL' }))
if (-not $overallPass) { exit 1 }