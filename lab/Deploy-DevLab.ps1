<#
.SYNOPSIS
    Per the AutomatedLab getting started guide, deploy a WSUS dev test lab.

.NOTES
    AutomatedLab docs:
      https://automatedlab.org/en/latest/Wiki/Basic/gettingstarted/
    
    Workflow:
      1. New-LabDefinition -Name <name> -DefaultVirtualizationEngine HyperV
      2. Add-LabMachineDefinition -Name <name> -OperatingSystem '<os>'
      3. Install-Lab
      4. Show-LabDeploymentSummary

    OS names available:
      - 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
#>

param(
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$LabName = 'WsusDev'

Import-Module AutomatedLab -Force -WarningAction SilentlyContinue
if (-not (Get-Module AutomatedLab)) {
    Import-Module "$env:USERPROFILE\Documents\PowerShell\Modules\AutomatedLab\5.61.0\AutomatedLab.psd1" -Force
}

# Clean up any previous lab with this name
Remove-Lab -Name $LabName -ErrorAction SilentlyContinue

# Step 1: New-LabDefinition
Write-Host '=== Step 1: New-LabDefinition ===' -ForegroundColor Cyan
New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath "C:\AutomatedLab-VMs\$LabName"

# Step 2: Add machine definitions
Write-Host '=== Step 2: Add-LabMachineDefinition ===' -ForegroundColor Cyan

# Register ISO explicitly per docs example
$isoPath = 'C:\LabSources\ISOs\Windows Server 2019 Datacenter Evaluation (Desktop Experience).iso'
Add-LabIsoImageDefinition -Name ($isoPath -replace '.*\\', '') -Path $isoPath

# Domain Controller
Add-LabMachineDefinition -Name "$LabName-DC01" `
    -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
    -Roles RootDC

# WSUS Member Server  
Add-LabMachineDefinition -Name "$LabName-WSUS01" `
    -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
    -Memory 8GB -Processors 4

Write-Host ''
Write-Host "=== Lab Definition: $LabName ===" -ForegroundColor Green
Write-Host "  DC01: $LabName-DC01 (DC, 4GB default, 2vCPU default)"
Write-Host "  WSUS: $LabName-WSUS01 (Member, 8GB, 4vCPU)"
Write-Host "  Credentials (LAB ONLY): LabAdmin / WsusLab-Adm1n!2026"
Write-Host ""

if ($SkipInstall) {
    Write-Host "Skipping deployment (SkipInstall). Run: Install-Lab -Name $LabName" -ForegroundColor Yellow
    exit 0
}

# Step 3: Install-Lab (takes 30-45 min)
Write-Host '=== Step 3: Install-Lab ===' -ForegroundColor Cyan
Write-Host '  Deploying lab (30-45 minutes)...' -ForegroundColor Yellow
Install-Lab -ErrorAction Stop

# Step 4: Show deployment summary
Show-LabDeploymentSummary

# Create checkpoint
Write-Host ''
Write-Host '=== Creating checkpoints ===' -ForegroundColor Cyan
Checkpoint-LabVM -All -SnapshotName 'Pre-WsusInstall' -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "============================================" -ForegroundColor Green
Write-Host " Lab deployed successfully!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "To test WSUS Manager clean-state install:" -ForegroundColor Yellow
Write-Host "  Copy WSUS Manager files to WSUS01 and run GA-WsusManager.exe"
Write-Host "  Username: .\LabAdmin"
Write-Host "  Password: WsusLab-Adm1n!2026"
Write-Host ""
Write-Host "To restore to clean state:" -ForegroundColor Yellow
Write-Host "  Restore-VMCheckpoint -VMName '$LabName-WSUS01' -Name 'Pre-WsusInstall'"
