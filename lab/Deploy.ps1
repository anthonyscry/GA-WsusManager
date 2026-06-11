# AutomatedLab deployment for WSUS dev lab
# Per https://automatedlab.org/en/latest/Wiki/Basic/gettingstarted/
# Run from elevated PowerShell 5.1

$labName = 'WsusDev'

Import-Module AutomatedLab -Force -WarningAction SilentlyContinue

# DO NOT call Remove-Lab - it errors if lab XML is missing.
# Manual cleanup was already done before running this script.

New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV -VmPath "C:\AutomatedLab-VMs\$labName"

# Domain Controller
Add-LabMachineDefinition -Name "DC01" -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Roles RootDC

# WSUS server with 8GB for SQL Express
Add-LabMachineDefinition -Name "WSUS01" -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Memory 8GB -Processors 4

Write-Host "Deploying lab... (30-45 min)"
Install-Lab

Show-LabDeploymentSummary
Checkpoint-LabVM -All -SnapshotName 'Pre-WsusInstall' -ErrorAction SilentlyContinue

Write-Host "LAB DEPLOYED"
Write-Host "Credentials (LAB ONLY): LabAdmin / WsusLab-Adm1n!2026"
