# WSUS Manager - Standard Operating Procedure

| **Document Information** | |
|--------------------------|-------------------------|
| **Author** | Tony Tran, ISSO, GA-ASI |
| **Version** | 3.8.8 |
| **Last Updated** | January 2026 |
| **Classification** | Internal Use Only |

---

## 1. Purpose

This document provides standard operating procedures for deploying, configuring, and maintaining Windows Server Update Services (WSUS) using the WSUS Manager application. The application automates WSUS management tasks and supports both online and air-gapped network environments.

---

## 2. Scope

This SOP applies to:
- Initial WSUS server installation and configuration
- Routine maintenance and health monitoring
- Air-gapped network update distribution
- Database backup and recovery operations
- Scheduled maintenance task configuration

---

## 3. Downloads

### 3.1 WSUS Manager Application

| File | Description |
|------|-------------|
| **WsusManager.exe** | Portable GUI application (recommended) |
| **Scripts/** | PowerShell scripts (required - keep with EXE) |
| **Modules/** | PowerShell modules (required - keep with EXE) |

**Important:** The EXE requires the `Scripts/` and `Modules/` folders in the same directory.

### 3.2 Required Installers

Download and save to `C:\WSUS\SQLDB\` before installation:

| File | Description | Download Link |
|------|-------------|---------------|
| SQLEXPRADV_x64_ENU.exe | SQL Server Express 2022 | [Microsoft Download](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |
| SSMS-Setup-ENU.exe | SQL Server Management Studio | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |

---

## 4. System Requirements

| Requirement | Minimum Specification |
|-------------|----------------------|
| Operating System | Windows Server 2019, 2022, or Windows 10/11 |
| CPU | 4+ cores |
| RAM | 16+ GB |
| Disk Space | 50+ GB for update content |
| PowerShell | 5.1 or later |
| SQL Server | SQL Server Express 2022 |
| Privileges | Local Administrator + SQL sysadmin role |

---

## 5. Directory Structure

| Path | Purpose |
|------|---------|
| `C:\WSUS\` | Content directory (required) |
| `C:\WSUS\SQLDB\` | SQL/SSMS installer files |
| `C:\WSUS\Logs\` | Application and maintenance logs |
| `C:\WSUS\WsusContent\` | Update files (auto-created by WSUS) |

**Critical:** Content path must be `C:\WSUS\` - NOT `C:\WSUS\wsuscontent\`

---

## 6. Installation Procedure

### 6.1 Pre-Installation Checklist

| Step | Action | Verification |
|------|--------|--------------|
| 1 | Download WSUS Manager package | Extract to `C:\WSUS\` |
| 2 | Download SQL Server Express 2022 | Save to `C:\WSUS\SQLDB\` |
| 3 | Download SSMS (optional) | Save to `C:\WSUS\SQLDB\` |
| 4 | Verify disk space | Minimum 50 GB free on C: |
| 5 | Verify admin privileges | Right-click > Run as Administrator |

### 6.2 Installation Steps

| Step | Action |
|------|--------|
| 1 | Launch `WsusManager.exe` as Administrator |
| 2 | Click **Install WSUS** from the Operations menu |
| 3 | Select the folder containing SQL installers (default: `C:\WSUS\SQLDB\`) |
| 4 | Wait for installation to complete (10-30 minutes) |
| 5 | Verify dashboard shows all services running (green) |

---

## 7. Dashboard Overview

The dashboard displays real-time status with auto-refresh every 30 seconds.

### 7.1 Status Cards

| Card | Information | Status Colors |
|------|-------------|---------------|
| **Services** | SQL Server, WSUS, IIS status | Green = All running, Orange = Partial, Red = Stopped |
| **Database** | SUSDB size vs 10GB limit | Green = <7GB, Yellow = 7-9GB, Red = >9GB |
| **Disk Space** | Free space on system drive | Green = >50GB, Yellow = 10-50GB, Red = <10GB |
| **Automation** | Scheduled task status | Green = Configured, Orange = Not configured |

### 7.2 Quick Actions

| Button | Function |
|--------|----------|
| Health Check | Verify WSUS configuration and connectivity |
| Deep Cleanup | Remove obsolete updates, optimize database |
| Monthly Maintenance | Run full maintenance cycle |
| Start Services | Auto-recover stopped services |

---

## 8. Server Mode Configuration

The application auto-detects network connectivity and configures the appropriate mode.

| Mode | Description | Available Operations |
|------|-------------|---------------------|
| **Online** | Internet-connected WSUS server | Export, Monthly Maintenance, Sync |
| **Air-Gap** | Isolated network WSUS server | Import, Restore Database |

Mode is saved to user settings and persists across restarts.

---

## 9. Operations Reference

### 9.1 Operations Menu

| Operation | Description | Mode |
|-----------|-------------|------|
| Install WSUS | Install WSUS + SQL Express from scratch | Both |
| Restore Database | Restore SUSDB from backup file | Air-Gap |
| Create GPO | Copy GPO files to `C:\WSUS GPO` for DC import | Both |
| Export to Media | Export DB and content to USB drive | Online |
| Import from Media | Import updates from USB drive | Air-Gap |
| Monthly Maintenance | Run WSUS cleanup and optimization | Online |
| Schedule Task | Configure automated maintenance | Online |
| Deep Cleanup | Aggressive cleanup for space recovery | Both |
| Health Check | Verify configuration and connectivity | Both |
| Health + Repair | Health check with automatic fixes | Both |

---

## 10. Routine Maintenance Procedures

### 10.1 Daily Checks (Automated)

| Check | Expected Result |
|-------|-----------------|
| Services Status | All services running (green) |
| Database Size | Below 9 GB |
| Disk Space | Above 10 GB free |

### 10.2 Monthly Maintenance Procedure

| Step | Action | Notes |
|------|--------|-------|
| 1 | Launch WSUS Manager as Administrator | |
| 2 | Verify all services are running | Use "Start Services" if needed |
| 3 | Click **Monthly Maintenance** | |
| 4 | Select maintenance profile: | |
| | - **Quick**: Basic cleanup | 5-10 minutes |
| | - **Standard**: Cleanup + optimization | 15-30 minutes |
| | - **Full**: Complete maintenance cycle | 30-60 minutes |
| 5 | Monitor progress in log panel | Some phases may be quiet for several minutes |
| 6 | Verify completion message | |

### 10.3 Scheduling Automated Maintenance

| Step | Action |
|------|--------|
| 1 | Click **Schedule Task** from Operations menu |
| 2 | Select frequency: Daily, Weekly, or Monthly |
| 3 | Set preferred time (recommended: 2:00 AM) |
| 4 | Enter domain credentials for task execution |
| 5 | Click **Create** to register the scheduled task |

---

## 11. Air-Gapped Network Procedure

### 11.1 Export from Online Server

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS | Run Monthly Maintenance to prepare updates |
| 2 | Online WSUS | Click **Export to Media** |
| 3 | Online WSUS | Select export type: |
| | | - **Full**: Complete database and all content |
| | | - **Differential**: Only updates from last N days |
| 4 | Online WSUS | Select destination folder (USB drive) |
| 5 | Online WSUS | Wait for export to complete |

### 11.2 Import to Air-Gapped Server

| Step | Location | Action |
|------|----------|--------|
| 1 | Air-Gap WSUS | Connect USB drive with exported data |
| 2 | Air-Gap WSUS | Launch WSUS Manager as Administrator |
| 3 | Air-Gap WSUS | Click **Import from Media** |
| 4 | Air-Gap WSUS | Select source folder (USB drive) |
| 5 | Air-Gap WSUS | Select destination folder (default: `C:\WSUS`) |
| 6 | Air-Gap WSUS | Wait for import to complete |
| 7 | Air-Gap WSUS | If full export: Click **Restore Database** |

---

## 12. Database Management

### 12.1 Database Backup

Database backups are automatically created during:
- Monthly Maintenance (Full profile)
- Export to Media operations

Backup location: `C:\WSUS\SUSDB_backup_YYYYMMDD.bak`

### 12.2 Database Restore Procedure

| Step | Action |
|------|--------|
| 1 | Click **Restore Database** from Operations menu |
| 2 | Select backup file (.bak) |
| 3 | Confirm restore operation |
| 4 | Wait for restore to complete |
| 5 | Verify dashboard shows database status |

### 12.3 SQL Sysadmin Permission Setup

Required for database operations (Restore, Deep Cleanup, Maintenance).

| Step | Action |
|------|--------|
| 1 | Open SQL Server Management Studio (SSMS) |
| 2 | Connect to `localhost\SQLEXPRESS` |
| 3 | Expand Security > Logins |
| 4 | Right-click Logins > New Login |
| 5 | Add your domain user or group |
| 6 | Select Server Roles > Check **sysadmin** |
| 7 | Click OK |

---

## 13. Domain Controller Configuration

Run on the Domain Controller, not the WSUS server.

### 13.1 GPO Deployment

| Step | Action |
|------|--------|
| 1 | On WSUS server: Click **Create GPO** to copy files to `C:\WSUS GPO` |
| 2 | Copy `C:\WSUS GPO` folder to Domain Controller |
| 3 | On DC: Open PowerShell as Administrator |
| 4 | Run: `.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"` |

### 13.2 GPOs Created

| GPO Name | Purpose |
|----------|---------|
| WSUS Update Policy | Client update settings |
| WSUS Inbound Firewall | Inbound firewall rules |
| WSUS Outbound Firewall | Outbound firewall rules |

### 13.3 Client Verification

On client machines, run:
```powershell
gpupdate /force
wuauclt /detectnow /reportnow
```

---

## 14. Troubleshooting

### 14.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Endless downloads | Wrong content path | Set content path to `C:\WSUS\` (not `C:\WSUS\wsuscontent\`) |
| Clients not updating | GPO not applied | Run `gpupdate /force`, check ports 8530/8531 |
| Database errors | Missing sysadmin | Grant sysadmin role in SSMS |
| Services not starting | Dependency issues | Use "Start Services" button on dashboard |
| Script not found | Missing folders | Ensure Scripts/ and Modules/ are with EXE |
| DB size shows "Offline" | SQL not running | Start SQL Server Express service |

### 14.2 Health Check Failures

| Check | Resolution |
|-------|------------|
| Services Stopped | Click "Health + Repair" to auto-recover |
| Firewall Rules Missing | Repair creates required rules automatically |
| Permissions Incorrect | Repair sets correct ACLs on content folder |
| Database Connection Failed | Verify SQL Server is running, check sysadmin role |

---

## 15. Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.8.8 | Jan 2026 | Fixed declined update purge error, database shrink retry logic, suppressed noisy spDeleteUpdate errors |
| 3.8.7 | Jan 2026 | Live Terminal mode, import dialog improvements, Create GPO button, non-blocking network check |
| 3.8.6 | Jan 2026 | Input fields disabled during operations, code cleanup |
| 3.8.5 | Jan 2026 | Fixed output log refresh, non-interactive install, domain credentials for tasks |
| 3.8.4 | Jan 2026 | Fixed export hanging, export mode options, GitHub Actions fixes |
| 3.8.3 | Jan 2026 | Script validation, button state management, distribution package fixes |
| 3.5.2 | Jan 2026 | Security hardening, service refresh fix, 323 unit tests |

---

## 16. Reference Links

### Microsoft Documentation

| Topic | Link |
|-------|------|
| WSUS Maintenance Guide | [Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/update-management/wsus-maintenance-guide) |
| WSUS Deployment Planning | [Microsoft Docs](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment) |
| WSUS GPO Settings | [Microsoft Docs](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/deploy/4-configure-group-policy-settings-for-automatic-updates) |

### Download Links

| Resource | Link |
|----------|------|
| SQL Server Express 2022 | [Microsoft Download](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |
| SQL Server Management Studio | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |

---

## 17. Support

| Contact | Information |
|---------|-------------|
| Author | Tony Tran, ISSO |
| Organization | Classified Computing, GA-ASI |
| Repository | GitHub Issues |

---

*Internal Use Only - General Atomics Aeronautical Systems, Inc.*
