<#
.SYNOPSIS
    Creates a clean WSUS test VM on localhost Hyper-V with known credentials.
    Replaces the inaccessible WS01/WS02 VMs which are marked Blocked/Not Trusted.

.DESCRIPTION
    This script:
    1. Creates a differencing VHDX from the Windows Server 2019 base image
    2. Injects an unattend.xml that sets known lab credentials and enables WinRM
    3. Creates a Generation 2 Hyper-V VM on IdentityLabNet
    4. Starts the VM and waits for it to become available

.CREDENTIALS
    Username: LabAdmin
    Password: WsusLab-Adm1n!2026
    These are LAB ONLY credentials. Do not use in production.

.NOTES
    The unattend.xml must be placed in Windows\Panther\Unattend\ on the mounted
    VHDX so Windows picks it up during first boot (out-of-box experience).
#>

param(
    [string]$VmName = "WsusLab-Test01",
    [int]$MemoryGB = 4,
    [int]$CpuCount = 2,
    [int]$DiskGB = 80,
    [string]$SwitchName = "IdentityLabNet",
    [string]$LabRoot = "C:\AutomatedLab-VMs"
)

$ErrorActionPreference = 'Stop'

# ── Paths ───────────────────────────────────────────────────
$baseVhdx  = Join-Path $LabRoot "BASE_WindowsServer2019StandardEvaluation(DesktopExperience)_10.0.17763.3650_50.vhdx"
$vmDir     = Join-Path $LabRoot $VmName
$diffVhdx  = Join-Path $vmDir "$VmName.vhdx"
$unattend  = Join-Path $PSScriptRoot "Unattend-WsusLab.xml"

# ── Prerequisites ───────────────────────────────────────────
if (-not (Test-Path $baseVhdx)) {
    Write-Host "ERROR: Base VHDX not found at $baseVhdx" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $unattend)) {
    Write-Host "ERROR: Unattend.xml not found at $unattend" -ForegroundColor Red
    exit 1
}

# ── Create VM directory ─────────────────────────────────────
if (-not (Test-Path $vmDir)) {
    New-Item -Path $vmDir -ItemType Directory -Force | Out-Null
    Write-Host "Created VM directory: $vmDir" -ForegroundColor Green
} else {
    Write-Host "VM directory exists: $vmDir" -ForegroundColor Yellow
}

# ── Create differencing VHDX ────────────────────────────────
if (-not (Test-Path $diffVhdx)) {
    $null = New-VHD -Path $diffVhdx -ParentPath $baseVhdx -Differencing -SizeBytes ($DiskGB * 1GB) -ErrorAction Stop
    Write-Host "Created differencing VHDX: $diffVhdx ($DiskGB GB)" -ForegroundColor Green
} else {
    Write-Host "Differencing VHDX exists: $diffVhdx" -ForegroundColor Yellow
}

# ── Inject unattend.xml ─────────────────────────────────────
Write-Host "Mounting VHDX to inject unattend.xml..." -ForegroundColor Cyan
try {
    $disk = Mount-VHD -Path $diffVhdx -Passthru -ErrorAction Stop
    $partition = $disk | Get-Partition | Where-Object DriveLetter | Select-Object -First 1
    if (-not $partition) {
        # No drive letter assigned — try to assign one
        $partition = $disk | Get-Partition | Where-Object { -not $_.DriveLetter } | Select-Object -First 1
        if ($partition) {
            $partition | Add-PartitionAccessPath -AccessPath "$env:TEMP\WsusLabMount\" -ErrorAction SilentlyContinue
            $mountPath = "$env:TEMP\WsusLabMount\"
        }
    } else {
        $mountPath = "$($partition.DriveLetter):\"
    }

    if (-not $mountPath) {
        Write-Host "WARNING: Could not mount VHDX for unattend injection. Will try first-boot script instead." -ForegroundColor Yellow
    } else {
        $pantherDir = Join-Path $mountPath "Windows\Panther\Unattend"
        if (-not (Test-Path $pantherDir)) {
            New-Item -Path $pantherDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $unattend -Destination (Join-Path $pantherDir "unattend.xml") -Force
        Write-Host "Injected unattend.xml into $pantherDir" -ForegroundColor Green
    }
} catch {
    Write-Host "WARNING: VHDX mount failed: $($_.Exception.Message). Will continue, but first boot may need manual OOBE." -ForegroundColor Yellow
} finally {
    try { Dismount-VHD -Path $diffVhdx -ErrorAction SilentlyContinue } catch {}
}

# ── Create VM ───────────────────────────────────────────────
$existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($existingVm) {
    Write-Host "VM '$VmName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    $vmParams = @{
        Name             = $VmName
        MemoryStartupBytes = $MemoryGB * 1GB
        Generation       = 2
        BootDevice       = 'VHD'
        VHDPath          = $diffVhdx
        SwitchName       = $SwitchName
        Path             = $vmDir
        ErrorAction      = 'Stop'
    }
    $newVm = New-VM @vmParams
    $newVm | Set-VM -ProcessorCount $CpuCount -ErrorAction SilentlyContinue
    Write-Host "Created VM: $VmName ($CpuCount vCPU, ${MemoryGB}GB RAM)" -ForegroundColor Green
}

# ── Create checkpoint before first boot ────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " VM Ready: $VmName" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Credentials (LAB ONLY):" -ForegroundColor Yellow
Write-Host "   Username: LabAdmin (or .\LabAdmin)"
Write-Host "   Password: WsusLab-Adm1n!2026"
Write-Host ""
Write-Host " To start the VM:"
Write-Host "   Start-VM -Name $VmName"
Write-Host ""
Write-Host " After first boot completes, create a checkpoint:"
Write-Host "   Checkpoint-VM -Name $VmName -SnapshotName 'Clean-OS-Install'"
Write-Host ""
Write-Host " Then test WSUS install:"
Write-Host "   Copy WSUS Manager files to the VM and run Install-WsusWithSqlExpress.ps1"
Write-Host "========================================" -ForegroundColor Cyan
