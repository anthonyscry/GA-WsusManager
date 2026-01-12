# Installation Guide

This guide covers everything you need to install and configure WSUS Manager.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Download Options](#download-options)
3. [First-Time Setup](#first-time-setup)
4. [Installing WSUS + SQL Express](#installing-wsus--sql-express)
5. [SQL Server Configuration](#sql-server-configuration)
6. [Firewall Configuration](#firewall-configuration)
7. [Domain Controller Setup](#domain-controller-setup)
8. [Verification](#verification)

---

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 8 GB | 16+ GB |
| Disk | 30 GB | 50+ GB SSD |
| Network | 1 Gbps | 1 Gbps |

### Software Requirements

| Software | Version | Notes |
|----------|---------|-------|
| Windows Server | 2019+ | Standard or Datacenter |
| PowerShell | 5.1+ | Included with Windows |
| .NET Framework | 4.7.2+ | Usually pre-installed |

### Required Installers

Download these files and save to `C:\WSUS\SQLDB\` (or select their folder when prompted):

| File | Download Link |
|------|---------------|
| SQL Server Express 2022 | [Microsoft Download Center](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |
| SQL Server Management Studio | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |

> **Important**: Download `SQLEXPRADV_x64_ENU.exe` (SQL Express with Advanced Services)

---

## Download Options

### Option 1: Portable Executable (Recommended)

Download `WsusManager.exe` from the [Releases](../../releases) page.

**Advantages:**
- No installation required
- Fully portable
- No PowerShell console window
- Modern GUI interface

### Option 2: Clone Repository

```powershell
# Clone via HTTPS
git clone https://github.com/anthonyscry/GA-WsusManager.git

# Or via SSH
git clone git@github.com:anthonyscry/GA-WsusManager.git
```

### Option 3: Download ZIP

1. Go to the repository main page
2. Click **Code** > **Download ZIP**
3. Extract to desired location

---

## First-Time Setup

### 1. Create Directory Structure

The WSUS Manager expects the following directory structure:

```
C:\WSUS\                    # Main content directory
├── SQLDB\                  # SQL/SSMS installers
├── Logs\                   # Application logs
└── WsusContent\            # Update files (auto-created)
```

Create the directories:

```powershell
New-Item -ItemType Directory -Path "C:\WSUS\SQLDB" -Force
```

### 2. Copy Installers

Copy the downloaded SQL Server installers to `C:\WSUS\SQLDB\`:
- `SQLEXPRADV_x64_ENU.exe`
- `SSMS-Setup-ENU.exe`

### 3. Run as Administrator

Right-click `WsusManager.exe` and select **Run as administrator**.

> **Note**: Administrator privileges are required for all WSUS operations.

### 4. Configure Settings

On first launch, go to **Settings** and configure:
- **WSUS Content Path**: `C:\WSUS` (default)
- **SQL Instance**: `.\SQLEXPRESS` (default)

---

## Installing WSUS + SQL Express

### Using the GUI

1. Launch `WsusManager.exe` as Administrator
2. Click **Install WSUS** in the sidebar
3. Browse to the folder containing SQL installers (`C:\WSUS\SQLDB` if you kept defaults)
4. Click **Install**
5. Wait for installation to complete (15-30 minutes)

> **Note:** If the default installer folder does not contain `SQLEXPRADV_x64_ENU.exe`, the installer will prompt you to select the correct folder.

### What Gets Installed

The installer performs these operations:
1. Installs SQL Server Express 2022
2. Installs SQL Server Management Studio
3. Installs WSUS Windows feature
4. Configures WSUS to use SQL Express
5. Creates SUSDB database
6. Sets appropriate permissions
7. Configures firewall rules

### Installation Log

Logs are saved to `C:\WSUS\Logs\` with timestamps.

---

## SQL Server Configuration

### Grant Sysadmin Access

Your account needs sysadmin privileges to manage SUSDB:

1. Open **SQL Server Management Studio**
2. Connect to `localhost\SQLEXPRESS`
3. Expand **Security** > **Logins**
4. Right-click **Logins** > **New Login**
5. Enter your domain account or group
6. Go to **Server Roles** tab
7. Check **sysadmin**
8. Click **OK**

### Verify Connection

```powershell
# Test SQL connection
sqlcmd -S localhost\SQLEXPRESS -Q "SELECT @@VERSION"
```

### Database Location

The SUSDB database files are stored in:
- `C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\SUSDB.mdf`
- `C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\SUSDB_log.ldf`

---

## Firewall Configuration

### Required Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8530 | TCP | WSUS HTTP |
| 8531 | TCP | WSUS HTTPS |
| 1433 | TCP | SQL Server (optional, local only) |

### Using WSUS Manager

WSUS Manager automatically configures firewall rules during installation. To verify or repair:

1. Run **Health Check**
2. If firewall rules are missing, run **Health + Repair**

### Manual Configuration

```powershell
# Create WSUS HTTP rule
New-NetFirewallRule -DisplayName "WSUS HTTP Traffic (Port 8530)" `
    -Direction Inbound -Protocol TCP -LocalPort 8530 -Action Allow

# Create WSUS HTTPS rule
New-NetFirewallRule -DisplayName "WSUS HTTPS Traffic (Port 8531)" `
    -Direction Inbound -Protocol TCP -LocalPort 8531 -Action Allow
```

---

## Domain Controller Setup

### Deploy WSUS Group Policy

Run this script on your Domain Controller (not the WSUS server):

```powershell
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

### What Gets Configured

The script imports three GPOs:
1. **WSUS Update Policy** - Configures clients to use your WSUS server
2. **WSUS Inbound Firewall** - Allows update traffic
3. **WSUS Outbound Firewall** - Allows reporting traffic

### Manual GPO Configuration

If you prefer manual setup:

1. Open **Group Policy Management**
2. Create new GPO: "WSUS Client Configuration"
3. Edit > **Computer Configuration** > **Administrative Templates** > **Windows Components** > **Windows Update**
4. Configure:
   - **Specify intranet Microsoft update service location**: `http://WSUS01:8530`
   - **Configure Automatic Updates**: Enabled
   - **Automatic Update detection frequency**: 22 hours

---

## Verification

### Check Services

All three services should be running:

| Service | Display Name |
|---------|--------------|
| MSSQL$SQLEXPRESS | SQL Server (SQLEXPRESS) |
| W3SVC | World Wide Web Publishing Service |
| WSUSService | WSUS Service |

```powershell
Get-Service MSSQL`$SQLEXPRESS, W3SVC, WSUSService | Format-Table Name, Status
```

### Check WSUS Console

1. Open **Server Manager**
2. Go to **Tools** > **Windows Server Update Services**
3. Verify you can connect to the WSUS server

### Check Database

```powershell
# Query database size
sqlcmd -S localhost\SQLEXPRESS -d SUSDB -Q "SELECT name, size*8/1024 AS SizeMB FROM sys.database_files"
```

### Run Health Check

Use WSUS Manager's Health Check to verify all components:

1. Launch `WsusManager.exe`
2. Click **Health Check**
3. Review the output for any issues

---

## Next Steps

- [[User Guide]] - Learn to use the GUI
- [[Air-Gap Workflow]] - Set up disconnected network updates
- [[Troubleshooting]] - Fix common issues

---

## Helpful Links

| Resource | URL |
|----------|-----|
| WSUS Deployment Guide | https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/deploy-windows-server-update-services |
| SQL Express Download | https://www.microsoft.com/en-us/download/details.aspx?id=104781 |
| SSMS Download | https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms |
| WSUS Best Practices | https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment |
