# WSUS Manager

| **Author** | Tony Tran, ISSO, GA-ASI |
|------------|-------------------------|
| **Version** | 3.5.2 |

A WSUS + SQL Server Express 2022 automation suite for Windows Server. Supports online and air-gapped networks.

---

## What's New in v3.5.2

### Security Hardening

| Feature | Description |
|---------|-------------|
| SQL Injection Prevention | Added input validation in Test-WsusBackupIntegrity |
| Path Validation | Test-ValidPath and Test-SafePath prevent command injection |
| Safe Path Escaping | Get-EscapedPath ensures safe command string construction |
| DPAPI Documentation | Documented credential storage security limitations |

### Performance Optimizations

| Feature | Description |
|---------|-------------|
| SQL Module Caching | SqlServer module version checked once at load time |
| Batch Service Queries | Single batch query instead of 5 individual calls |
| Dashboard Refresh Guard | Prevents overlapping refresh operations |
| Test Suite Optimization | Shared module pre-loading reduces test time |

### Code Quality

| Feature | Description |
|---------|-------------|
| Pester Unit Tests | 323 unit tests across 10 test files (all passing) |
| PSScriptAnalyzer | Build runs code analysis before compilation |
| Approved Verbs | Renamed Load-Settings to Import-WsusSettings |

### Previous (v3.5.0/3.5.1)

| Feature | Description |
|---------|-------------|
| Server Mode Toggle | Switch between Online and Air-Gap modes |
| Modern WPF GUI | Dark theme matching GA-AppLocker |
| Database Size Indicator | Shows DB size out of 10GB limit with color coding |
| Export/Import Dialogs | Folder pickers for media transfer operations |

---

## Downloads

### Recommended: Portable Executable

| File | Description |
|------|-------------|
| **WsusManager.exe** | Standalone GUI - just download and run (always latest version) |

- Modern dark-themed WPF interface
- Auto-refresh dashboard (30-second interval)
- Database size monitoring with 10GB limit warnings
- No installation required - fully portable
- No PowerShell console window

### Alternative: PowerShell Scripts

| File | Description |
|------|-------------|
| Scripts/Invoke-WsusManagement.ps1 | PowerShell CLI version |

```powershell
.\Scripts\Invoke-WsusManagement.ps1
```

### Required Installers

> Save to C:\WSUS\SQLDB\ before installation

| File | Description |
|------|-------------|
| SQLEXPRADV_x64_ENU.exe | SQL Server Express 2022 |
| SSMS-Setup-ENU.exe | SQL Server Management Studio |

---

## Requirements

| Requirement | Specification |
|-------------|---------------|
| OS | Windows Server 2019+ |
| CPU | 4+ cores |
| RAM | 16+ GB |
| Disk | 50+ GB for updates |
| PowerShell | 5.1+ |
| SQL Server | SQL Server Express 2022 |
| Privileges | Local Admin + SQL sysadmin |

---

## Dashboard

The dashboard displays four status cards with auto-refresh every 30 seconds:

| Card | Information | Color Coding |
|------|-------------|--------------|
| Services | SQL/WSUS/IIS status | Green = All running, Orange = Partial, Red = Stopped |
| Database | SUSDB size / 10GB limit | Green = <7GB, Yellow = 7-9GB, Red = >9GB |
| Disk Space | Free space on C: drive | Green = >50GB, Yellow = 10-50GB, Red = <10GB |
| Automation | Scheduled task status | Green = Ready, Orange = Not Set |

**Quick Actions:**
- Run Health Check
- Deep Cleanup
- Monthly Maintenance
- Start Services (auto-recovery)

---

## Operations Menu

| Menu Item | Description |
|-----------|-------------|
| Install WSUS | Install WSUS + SQL Express from scratch |
| Restore Database | Restore SUSDB from backup |
| Export to Media | Export DB and content to USB (Full or Differential) |
| Import from Media | Import from USB to air-gapped server |
| Monthly Maintenance | Run WSUS cleanup and optimization |
| Deep Cleanup | Aggressive cleanup for space recovery |
| Health Check | Verify WSUS configuration and connectivity |
| Health + Repair | Health check with automatic fixes |
| Settings | Configure paths and SQL instance |
| About | Application info and credits |

---

## Export Options

| Type | Description |
|------|-------------|
| Full Export | Complete database backup and all content files |
| Differential Export | Only updates from the last N days (default: 30 days) |

Both options prompt for destination folder selection.

---

## Air-Gapped Workflow

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS | Monthly Maintenance |
| 2 | Online WSUS | Export to Media (Full or Differential) |
| 3 | - | Physical transfer via USB |
| 4 | Air-Gap WSUS | Import from Media |
| 5 | Air-Gap WSUS | Restore Database (if full export) |

---

## Domain Controller Setup

> Run on DC, not WSUS server

```powershell
.\DomainController\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"
```

Imports three GPOs:
- Update Policy GPO
- Inbound Firewall GPO
- Outbound Firewall GPO

---

## SQL Sysadmin Setup

1. Open SSMS
2. Connect to localhost\SQLEXPRESS
3. Security > Logins > New Login
4. Add your domain group
5. Server Roles > Check **sysadmin** > OK

---

## Directory Layout

| Path | Purpose |
|------|---------|
| C:\WSUS\ | Content directory (required) |
| C:\WSUS\SQLDB\ | SQL/SSMS installers |
| C:\WSUS\Logs\ | Log files |
| C:\WSUS\WsusContent\ | Update files (auto-created) |

> **Important:** Content path must be C:\WSUS - NOT C:\WSUS\wsuscontent

---

## Repository Structure

| Path | Description |
|------|-------------|
| WsusManager.exe | Portable GUI Application (RECOMMENDED) |
| wsus-icon.ico | Application icon |
| build.ps1 | Build script for EXE (includes tests + code review) |
| Scripts/ | PowerShell scripts |
| Modules/ | PowerShell modules (10 modules) |
| Tests/ | Pester unit tests (323 tests) |
| DomainController/ | GPO deployment scripts |

---

## Building from Source

| Command | Description |
|---------|-------------|
| .\build.ps1 | Full build with tests and code review |
| .\build.ps1 -SkipTests -SkipCodeReview | Quick build |
| .\build.ps1 -TestOnly | Run tests only |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Endless downloads | Content path must be C:\WSUS (not C:\WSUS\wsuscontent) |
| Clients not updating | Run gpupdate /force, check ports 8530/8531 |
| Database errors | Grant sysadmin role in SSMS |
| Services not starting | Use "Start Services" button on dashboard |
| Script not found error | Ensure Scripts folder is alongside the EXE |
| DB size shows "Offline" | SQL Server Express service not running |

---

## References

| Topic | Link |
|-------|------|
| WSUS Maintenance | https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide |
| SQL Express Download | https://www.microsoft.com/en-us/download/details.aspx?id=104781 |

---

*Internal use - General Atomics Aeronautical Systems, Inc.*
