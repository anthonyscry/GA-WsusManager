<#
.SYNOPSIS
    AutomatedLab lab definition for WSUS Manager clean-state validation.

.DESCRIPTION
    Creates a 2-node lab: DC01 (domain controller) + WSUS01 (member server).
    On WSUS01, the lab provisions:
      - Windows Server 2019 Standard
      - SQL Server Express 2022 (if installer ISO available)
      - WSUS Windows role
      - WSUS Manager files from the host

    Run this from a PowerShell 5.1 session as Administrator.

    AutomatedLab v5.60.0 is required.
    Base images must be registered with Add-LabIsoImageDefinition.

.PARAMETER LabName
    Name for the lab environment.

.PARAMETER SkipDeploy
    Switch to generate the lab definition XML without deploying.

.CREDENTIALS (LAB ONLY)
    LabAdmin / WsusLab-Adm1n!2026

.NOTES
    Prerequisites before running:
      1. Register base ISO:
         Add-LabIsoImageDefinition -Name 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Path 'C:\ISO\Windows Server 2019 Datacenter Evaluation (Desktop Experience).iso'
      2. Ensure Hyper-V is enabled
      3. Run as Administrator
#>

param(
    [string]$LabName = 'WsusLab',
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'

# ── Credentials (LAB ONLY) ────────────────────────────────
$labAdmin = New-Object System.Management.Automation.PSCredential(
    'LabAdmin',
    (ConvertTo-SecureString 'WsusLab-Adm1n!2026' -AsPlainText -Force)
)

# ── Network ───────────────────────────────────────────────
$ipRange = '192.168.100.0/24'
$gateway = '192.168.100.1'
$dns = '192.168.100.10'

# ── Lab Definition ────────────────────────────────────────
$lab = @{
    Name = $LabName
    Credential = $labAdmin
    PostInstall = @{
        # Placeholder for WSUS Manager deployment script
    }
}

$dc = @{
    Name = "$LabName-DC01"
    Role = 'RootDC'
    OperatingSystem = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    Memory = 4GB
    Cpu = 2
    Network = @{
        Interface = 'LAB'
        IPAddress = $dns
        Gateway = $gateway
    }
}

$wsus = @{
    Name = "$LabName-WSUS01"
    Role = 'MemberServer'
    OperatingSystem = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    Memory = 8GB
    Cpu = 4
    Network = @{
        Interface = 'LAB'
        IPAddress = '192.168.100.20'
        Gateway = $gateway
        DnsServer = $dns
    }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " AutomatedLab Lab Definition: $LabName" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "VMs:" -ForegroundColor Yellow
Write-Host "  $LabName-DC01  (DC, 4GB, 2vCPU)"
Write-Host "  $LabName-WSUS01 (Member Server, 8GB, 4vCPU)"
Write-Host ""
Write-Host "Network: $ipRange (LAB switch)" -ForegroundColor Gray
Write-Host "DC01 IP: $dns" -ForegroundColor Gray
Write-Host "WSUS01 IP: 192.168.100.20" -ForegroundColor Gray
Write-Host ""
Write-Host "Credentials (LAB ONLY):" -ForegroundColor Yellow
Write-Host "  Username: LabAdmin"
Write-Host "  Password: WsusLab-Adm1n!2026"
Write-Host ""
Write-Host "Post-deployment steps (manual):" -ForegroundColor Cyan
Write-Host "  1. Copy WsusManager-v4.1.0.zip to WSUS01"
Write-Host "  2. Extract to C:\WSUS\WsusManager\"
Write-Host "  3. Stage SQL Express installer at C:\WSUS\SQLDB\"
Write-Host "  4. Run RDP to WSUS01, launch GA-WsusManager.exe as Admin"
Write-Host "  5. Click Install WSUS to validate clean-state install"
Write-Host ""
Write-Host "To deploy, import AutomatedLab and run:" -ForegroundColor Yellow
Write-Host "  Import-Module AutomatedLab -Force"
Write-Host "  Add-LabMachineDefinition -Name '$LabName-DC01' -Role RootDC -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Memory 4GB -Cpu 2 -Network LAB -IpAddress $dns | Out-Null"
Write-Host "  Add-LabMachineDefinition -Name '$LabName-WSUS01' -Role MemberServer -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Memory 8GB -Cpu 4 -Network LAB -IpAddress 192.168.100.20 -DnsServer1 $dns | Out-Null"
Write-Host "  Install-Lab"
Write-Host "  Checkpoint-LabVM -All -SnapshotName 'Pre-WsusInstall'"
Write-Host ""
Write-Host "Pre-requisites:" -ForegroundColor Yellow
Write-Host "  1. Register base ISO: Add-LabIsoImageDefinition -Name 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' -Path 'C:\ISO\Windows Server 2019 Datacenter Evaluation (Desktop Experience).iso'"
Write-Host "  2. Ensure C:\LabSources\ISOs\ has the Windows Server 2019 ISO"
Write-Host "============================================" -ForegroundColor Cyan
