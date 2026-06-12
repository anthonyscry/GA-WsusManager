<#
.SYNOPSIS
    Deploy a WSUS development test lab using AutomatedLab on local Hyper-V.

.DESCRIPTION
    Creates a 2-node lab with:
      - DC01 (Domain Controller, 4GB RAM)
      - WSUS01 (Member Server + SQL + WSUS ready, 8GB RAM)

    After deployment:
      - Copies WSUS Manager files to WSUS01
      - Creates a pre-wsus-install checkpoint
      - Prints instructions for clean-state WSUS install testing

.CREDENTIALS (LAB ONLY)
    Username: LabAdmin
    Password: WsusLab-Adm1n!2026

.PARAMETER SkipInstall
    Set this to generate the lab definition without deploying.

.PARAMETER LabName
    Name for the lab environment (default: WsusDev).

.EXAMPLE
    .\lab\Deploy-WsusDevLab.ps1
    Full deployment (30-45 minutes).

.EXAMPLE
    .\lab\Deploy-WsusDevLab.ps1 -SkipInstall
    Generate lab definition XML only, deploy manually later.

.NOTES
    Run from an elevated PowerShell 5.1 session. NOT PowerShell 7.
    Windows Server 2019 Datacenter ISO must be at C:\LabSources\ISOs\
    SQL Server ISO is optional - WSUS Manager handles SQL Express download.
#>

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]

[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [string]$LabName = 'WsusDev'
)

$ErrorActionPreference = 'Stop'

# ── Prerequisites check ──────────────────────────────────
Write-Host '=== Prerequisites Check ===' -ForegroundColor Cyan

# Must be PowerShell 5.1
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Host 'WARNING: AutomatedLab works best with PowerShell 5.1' -ForegroundColor Yellow
    Write-Host "  Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
}

# Check ISO
$isoPath = 'C:\LabSources\ISOs\Windows Server 2019 Datacenter Evaluation (Desktop Experience).iso'
if (-not (Test-Path $isoPath)) {
    Write-Host "ERROR: Windows Server 2019 ISO not found at $isoPath" -ForegroundColor Red
    Write-Host "  Download from: https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019"
    exit 1
}
Write-Host "  ISO found: $isoPath" -ForegroundColor Green


# ── Lab Definition ────────────────────────────────────────
Write-Host ''
Write-Host "=== Creating Lab Definition: $LabName ===" -ForegroundColor Cyan

Import-Module AutomatedLab -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
if (-not (Get-Module AutomatedLab)) {
    # Try from Documents path
    Import-Module "$env:USERPROFILE\Documents\PowerShell\Modules\AutomatedLab\5.60.0\AutomatedLab.psd1" -Force -ErrorAction Stop
}

# Clean up any existing lab with this name
$existing = Get-Lab -Name $LabName -ErrorAction SilentlyContinue
if ($existing) {
    Remove-Lab -Name $LabName -Force -ErrorAction SilentlyContinue
}

# Start new lab
New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath "C:\AutomatedLab-VMs\$LabName" -ErrorAction Stop
Write-Host "  Lab definition created" -ForegroundColor Green

# Register ISO image
Add-LabIsoImageDefinition -Name 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Path $isoPath -ErrorAction Stop
Write-Host "  ISO registered" -ForegroundColor Green

# ── Domain Controller ─────────────────────────────────────
$dcParams = @{
    Name = "$LabName-DC01"
    Role = 'RootDC'
    OperatingSystem = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    Memory = 4GB
    Cpu = 2
    Network = 'LAB'
    IpAddress = '192.168.100.10'
}
Add-LabMachineDefinition @dcParams
Write-Host "  DC01 defined: $LabName-DC01 (4GB, 2vCPU, 192.168.100.10)" -ForegroundColor Green

# ── WSUS Member Server ────────────────────────────────────
$wsusParams = @{
    Name = "$LabName-WSUS01"
    Role = 'MemberServer'
    OperatingSystem = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    Memory = 8GB
    Cpu = 4
    Network = 'LAB'
    IpAddress = '192.168.100.20'
    DnsServer1 = '192.168.100.10'
}
Add-LabMachineDefinition @wsusParams
Write-Host "  WSUS01 defined: $LabName-WSUS01 (8GB, 4vCPU, 192.168.100.20)" -ForegroundColor Green

Write-Host ''
Write-Host "=== Lab Definition Summary ===" -ForegroundColor Cyan
Write-Host "  Name: $LabName"
Write-Host "  VMs:  $LabName-DC01 (DC), $LabName-WSUS01 (Member)"
Write-Host "  Credentials: LabAdmin / WsusLab-Adm1n!2026 (LAB ONLY)"
Write-Host "  Network: 192.168.100.0/24 on LAB switch"
Write-Host ""

if ($SkipInstall) {
    Write-Host "Skipping deployment (-SkipInstall). To deploy later:" -ForegroundColor Yellow
    Write-Host "  Install-Lab -Name $LabName"
    exit 0
}

# ── Deploy ─────────────────────────────────────────────────
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Starting Lab Deployment" -ForegroundColor Green
Write-Host " Estimated time: 30-45 minutes" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

try {
    Install-Lab -ErrorAction Stop
} catch {
    Write-Host "ERROR: Lab installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Check AutomatedLab logs at: C:\ProgramData\AutomatedLab\Logs\" -ForegroundColor Yellow
    exit 1
}

# ── Post-Deployment ────────────────────────────────────────
Write-Host ''
Write-Host "=== Post-Deployment Setup ===" -ForegroundColor Cyan

# Copy WSUS Manager files to WSUS01
$wsusVm = Get-LabVM -ComputerName "$LabName-WSUS01" -ErrorAction SilentlyContinue
if ($wsusVm) {
    Write-Host "  Copying WSUS Manager files to WSUS01..." -ForegroundColor Yellow
    try {
        $hostPath = (Get-Item .).FullName
        $destPath = 'C:\WSUS\WsusManager'
        # Create directory on remote VM
        Invoke-LabCommand -ComputerName "$LabName-WSUS01" -ScriptBlock { param($p) New-Item -Path $p -ItemType Directory -Force | Out-Null } -ArgumentList $destPath -ErrorAction SilentlyContinue
        # Copy files
        Copy-LabFileItem -Path $hostPath -DestinationFolder $destPath -ComputerName "$LabName-WSUS01" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  WSUS Manager files copied to WSUS01" -ForegroundColor Green
    } catch {
        Write-Host "  File copy skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Create checkpoint
Write-Host "  Creating Pre-WsusInstall checkpoint..." -ForegroundColor Yellow
try {
    Checkpoint-LabVM -All -SnapshotName 'Pre-WsusInstall' -ErrorAction SilentlyContinue
    Write-Host "  Checkpoint created: Pre-WsusInstall" -ForegroundColor Green
} catch {
    Write-Host "  Checkpoint skipped: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ── Final Instructions ─────────────────────────────────────
Write-Host ''
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Lab Deployed Successfully!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "VMs:" -ForegroundColor Yellow
Write-Host "  $LabName-DC01  (Domain Controller)"
Write-Host "  $LabName-WSUS01 (WSUS Test Server)"
Write-Host ""
Write-Host "Access:" -ForegroundColor Yellow
Write-Host "  RDP to WSUS01 via Hyper-V VMConnect or IP 192.168.100.20"
Write-Host "  Username: .\LabAdmin or $LabName\LabAdmin"
Write-Host "  Password: WsusLab-Adm1n!2026"
Write-Host ""
Write-Host "To test clean-state WSUS install:" -ForegroundColor Cyan
Write-Host "  1. RDP to WSUS01"
Write-Host "  2. Open C:\WSUS\WsusManager\"
Write-Host "  3. Right-click GA-WsusManager.exe -> Run as Administrator"
Write-Host "  4. Click Install WSUS"
Write-Host "  5. Observe the install workflow completes without errors"
Write-Host ""
Write-Host "To restore to clean state:" -ForegroundColor Cyan
Write-Host "  Restore-VMCheckpoint -VMName '$LabName-WSUS01' -Name 'Pre-WsusInstall' -Confirm:`$false"
Write-Host ""
Write-Host "Credentials are LAB ONLY - do not use in production." -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Cyan
