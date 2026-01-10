# WSUS Manager

| **Author** | Tony Tran, ISSO, GA-ASI |
|------------|-------------------------|
| **Version** | 3.2.0 |

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports online and air-gapped networks.

---

## Downloads

### Recommended: GUI Application

| File | Description |
|------|-------------|
| **`WsusManager.exe`** | Standalone GUI - just download and run |

### Alternative: Script Bundle

| File | Description |
|------|-------------|
| `WSUS_Script_Bundle.zip` | PowerShell scripts (extract to `C:\WSUS\Scripts\`) |

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

1. Download `WsusManager.exe`
2. Double-click to run
3. Select operation from menu

### PowerShell Scripts

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\Invoke-WsusManagement.ps1
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
| `C:\WSUS\Scripts\` | Scripts |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Endless downloads | Content path must be `C:\WSUS` |
| Clients not updating | `gpupdate /force`, check ports 8530/8531 |
| Database errors | Grant sysadmin in SSMS |

---

## References

| Topic | Link |
|-------|------|
| WSUS Maintenance | [Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide) |
| SQL Express Download | [Microsoft](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |

---

*Internal use - GA-ASI*
