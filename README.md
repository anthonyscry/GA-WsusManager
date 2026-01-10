# WSUS Manager

**Author:** Tony Tran, ISSO, GA-ASI | **Version:** 3.2.0

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports both online and air-gapped networks.

---

## Quick Start

### Option 1: GUI Application (Recommended)

Download and run **`WsusManager.exe`** - no installation required.

- Modern dark-themed interface
- No PowerShell console window
- Portable standalone executable

### Option 2: PowerShell Scripts

```powershell
.\Invoke-WsusManagement.ps1
```

---

## Requirements

| Requirement | Specification |
|-------------|---------------|
| OS | Windows Server 2019+ |
| CPU | 4+ cores |
| RAM | 16+ GB |
| Disk | 125+ GB |
| PowerShell | 5.0+ |

### Required Installers (place in `C:\WSUS\SQLDB\`)

- `SQLEXPRADV_x64_ENU.exe` - SQL Server Express 2022
- `SSMS-Setup-ENU.exe` - SQL Server Management Studio

---

## Main Operations

| Option | Description |
|--------|-------------|
| 1 | Install WSUS + SQL Express |
| 2 | Restore Database |
| 3 | Import from External Media (air-gap) |
| 4 | Export to External Media (air-gap) |
| 5 | Monthly Maintenance |
| 6 | Deep Cleanup |
| 7 | Health Check |
| 8 | Health Check + Repair |
| 9 | Reset Content Download |
| 10 | Force Client Check-In |

---

## Air-Gapped Workflow

```
Online WSUS → Option 5 (Monthly Maintenance)
                    ↓
              Option 4 (Export to USB)
                    ↓
            [Physical Transfer]
                    ↓
Air-Gap WSUS → Option 3 (Import from USB)
                    ↓
              Option 2 (Restore Database)
```

---

## Domain Controller Setup

Run on the DC (not WSUS server):

```powershell
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

Imports 3 GPOs: Update Policy, Inbound Firewall, Outbound Firewall.

---

## Directory Layout

```
C:\WSUS\              # Content directory (required path)
C:\WSUS\SQLDB\        # SQL/SSMS installers
C:\WSUS\Logs\         # Log files
C:\WSUS\Scripts\      # This repository
```

---

## Repository Structure

```
wsus-sql/
├── WsusManager.exe           # GUI Application (RECOMMENDED)
├── Invoke-WsusManagement.ps1 # CLI (backup option)
├── Scripts/                  # Automation scripts
├── DomainController/         # GPO deployment
├── Modules/                  # PowerShell modules
└── Tests/                    # Unit tests
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Endless downloads | Use `C:\WSUS` NOT `C:\WSUS\wsuscontent` |
| Clients not updating | Run `gpupdate /force`, check ports 8530/8531 |
| Database errors | Grant sysadmin role to your account in SSMS |

---

## References

- [WSUS Maintenance Guide](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide)
- [SQL Server 2022 Express](https://www.microsoft.com/en-us/download/details.aspx?id=104781)

---

*Internal use - GA-ASI*
