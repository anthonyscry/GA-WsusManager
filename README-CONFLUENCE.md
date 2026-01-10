# WSUS Manager

| **Author** | Tony Tran, ISSO, GA-ASI |
|------------|-------------------------|
| **Version** | 3.3.0 |

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports online and air-gapped networks.

---

## What's New in v3.3.0

| Feature | Description |
|---------|-------------|
| Auto-Refresh Dashboard | Status cards update every 30 seconds |
| Database Size Monitoring | Alerts when approaching 10GB SQL Express limit |
| Disk Space Monitoring | Warnings for low content storage space |
| Scheduled Task Status | Shows maintenance task state and next run |
| Service Recovery | One-click start for stopped services |
| Enhanced Health Checks | Aggregated health with issues/warnings |

---

## Downloads

### Recommended: GUI Application

| File | Description |
|------|-------------|
| **`WsusManager-3.3.0.exe`** | Standalone GUI - just download and run |

### Alternative: Script Bundle

| File | Description |
|------|-------------|
| `Scripts/Invoke-WsusManagement.ps1` | PowerShell CLI version |

### Required Installers

> Save to `C:\WSUS\SQLDB\` before installation

| File | Description |
|------|-------------|
| `SQLEXPRADV_x64_ENU.exe` | SQL Server Express 2022 |
| `SSMS-Setup-ENU.exe` | SQL Server Management Studio |

---

## Requirements

| Requirement | Specification |
|-------------|---------------|
| OS | Windows Server 2019+ |
| CPU | 4+ cores |
| RAM | 16+ GB |
| Disk | 125+ GB |
| Privileges | Local Admin + SQL sysadmin |

---

## Quick Start

### GUI Application

1. Download `WsusManager-3.3.0.exe`
2. Double-click to run (Admin privileges required)
3. Dashboard shows real-time service status
4. Select operation from sidebar menu

### PowerShell Scripts

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\Scripts\Invoke-WsusManagement.ps1
```

---

## Operations Menu

| # | Operation |
|---|-----------|
| 1 | Install WSUS + SQL Express |
| 2 | Restore Database |
| 3 | Import from External Media |
| 4 | Export to External Media |
| 5 | Monthly Maintenance |
| 6 | Deep Cleanup |
| 7 | Health Check |
| 8 | Health Check + Repair |
| 9 | Reset Content Download |
| 10 | Force Client Check-In |

---

## Dashboard Features (v3.3.0)

| Card | Information |
|------|-------------|
| Services | SQL/WSUS/IIS status with color indicators |
| Database | SUSDB size with 10GB limit warnings |
| Disk Space | Free space with low-disk alerts |
| Automation | Scheduled task state and next run time |

**Quick Actions:**
- Run Health Check
- Deep Cleanup
- Maintenance
- Start Services (auto-recovery)

---

## Air-Gapped Workflow

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS | Option 5: Monthly Maintenance |
| 2 | Online WSUS | Option 4: Export to USB |
| 3 | - | Physical transfer |
| 4 | Air-Gap WSUS | Option 3: Import from USB |
| 5 | Air-Gap WSUS | Option 2: Restore Database |

---

## Domain Controller Setup

> Run on DC, not WSUS server

```powershell
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

Imports: Update Policy GPO, Inbound Firewall GPO, Outbound Firewall GPO

---

## SQL Sysadmin Setup

1. Open SSMS → Connect to `localhost\SQLEXPRESS`
2. Security → Logins → New Login
3. Add your domain group
4. Server Roles → Check **sysadmin** → OK

---

## Directory Layout

| Path | Purpose |
|------|---------|
| `C:\WSUS\` | Content directory (required) |
| `C:\WSUS\SQLDB\` | Installers |
| `C:\WSUS\Logs\` | Logs |

---

## Repository Structure

| Path | Description |
|------|-------------|
| `WsusManager-3.3.0.exe` | GUI Application (portable) |
| `Scripts/` | All PowerShell scripts |
| `Modules/` | PowerShell modules |
| `DomainController/` | GPO deployment scripts |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Endless downloads | Content path must be `C:\WSUS` |
| Clients not updating | `gpupdate /force`, check ports 8530/8531 |
| Database errors | Grant sysadmin in SSMS |
| Services not starting | Use "Start Services" button |

---

## References

| Topic | Link |
|-------|------|
| WSUS Maintenance | [Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide) |
| SQL Express Download | [Microsoft](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |

---

*Internal use - GA-ASI*
