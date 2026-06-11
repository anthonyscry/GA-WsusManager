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
| SQL Server Management Studio (optional) | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |

> **Important**: Download `SQLEXPRADV_x64_ENU.exe` (SQL Express with Advanced Services)

---

## Download Options

### Option 1: Distribution Package (Recommended)

Download `WsusManager-vX.X.X.zip` from the [Releases](../../releases) page and extract to `C:\WSUS\`.

The package includes the EXE, Scripts/, Modules/, DomainController/, and documentation. The EXE requires the Scripts/ and Modules/ folders in the same directory.

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
├── SQLDB\                  # SQL Express installer (SSMS optional)
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
- `SSMS-Setup-ENU.exe` (optional -- skipped if not present)

### 3. Run as Administrator

Right-click `GA-WsusManager.exe` and select **Run as administrator**.

> **Note**: Administrator privileges are required for all WSUS operations.

### 4. Configure Settings

On first launch, go to **Settings** and configure:
- **WSUS Content Path**: `C:\WSUS` (default)
- **SQL Instance**: `.\SQLEXPRESS` (default)

---

## Installing WSUS + SQL Express

### Using the GUI

1. Launch `GA-WsusManager.exe` as Administrator
2. Click **Install WSUS** in the sidebar
3. Browse to the folder containing SQL installers (`C:\WSUS\SQLDB` if you kept defaults)
4. Click **Install**
5. Wait for installation to complete (15-30 minutes)

> **Note:** If the default installer folder does not contain `SQLEXPRADV_x64_ENU.exe`, the installer will prompt you to select the correct folder.

### What Gets Installed

The installer performs these operations in order:
1. Auto-detects and removes Windows Internal Database (WID) if present
2. Installs SQL Server Express 2022
3. Cleans up any leftover WID data files to prevent conflicts
4. Installs SQL Server Management Studio (SSMS) if installer is present
5. Installs the WSUS Windows feature with SQL Express backend (`UpdateServices-DB`)
6. Creates and configures the SUSDB database
7. Sets language to English only via the WSUS API
8. Configures default update classifications via the WSUS API
9. Suppresses the WSUS initial configuration wizard (registry + per-user + API)
10. Sets appropriate directory permissions
11. Configures firewall rules (ports 8530 HTTP and 8531 HTTPS)

### Installation Log

Logs are saved to `C:\WSUS\Logs\` with timestamps.

---

## SQL Server Configuration

### Grant Sysadmin Access

Your account needs sysadmin privileges to manage SUSDB. Choose one of these methods:

**Option A: Use WSUS Manager GUI (Recommended)**

1. Launch `GA-WsusManager.exe` as Administrator
2. Click **Fix SQL Login** in the Setup section
3. The app automatically adds the current user as sysadmin

**Option B: Use sqlcmd (No SSMS Required)**

Open an elevated PowerShell prompt:

```powershell
# Replace DOMAIN\Username with your account
sqlcmd -S localhost\SQLEXPRESS -E -Q "
  IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'DOMAIN\Username')
    CREATE LOGIN [DOMAIN\Username] FROM WINDOWS;
  EXEC sp_addsrvrolemember @loginame = N'DOMAIN\Username', @rolename = N'sysadmin';
"
```

> `sqlcmd.exe` ships with SQL Server Express -- no additional downloads needed.

**Option C: Use SSMS (Optional)**

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

1. Run **Diagnostics** (in the DIAGNOSTICS section)
2. If firewall rules are missing, the Diagnostics repair step will automatically recreate them

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

> **AIR-GAP ONLY:** These GPOs direct all Windows Update traffic to the internal
> WSUS server and block Microsoft Update. Do NOT deploy on internet-connected systems.

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

### Run Diagnostics

Use WSUS Manager's Diagnostics to verify all components:

1. Launch `GA-WsusManager.exe`
2. Click **Diagnostics** (in the DIAGNOSTICS section of the sidebar)
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
| SSMS Download (optional) | https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms |
| WSUS Best Practices | https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment |
