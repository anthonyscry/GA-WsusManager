# WSUS Manager - Standard Operating Procedure

| **Document Information** | |
|--------------------------|-------------------------|
| **Author** | Tony Tran, ISSO, GA-ASI |
| **Version** | 3.8.9 |
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

## 3. Quick Start Workflows

### 3.1 First-Time Setup (5 steps)

```
1. Download → Extract WsusManager to C:\WSUS\
2. Download → SQL Express + SSMS to C:\WSUS\SQLDB\
3. Run → WsusManager.exe as Administrator
4. Click → Install WSUS
5. Wait → 15-30 minutes for completion
```

### 3.2 Weekly Online Sync (3 steps)

```
1. Open → WsusManager.exe as Administrator
2. Click → Online Sync → Select "Quick Sync"
3. Wait → 15-30 minutes for completion
```

### 3.3 Air-Gap Transfer Workflow

**On Online Server:**
```
1. Run Online Sync → Full Sync profile
2. Click Export to Media → Select USB drive
3. Wait for export to complete
```

**On Air-Gapped Server:**
```
1. Connect USB drive
2. Click Import from Media → Select USB folder
3. Click Reset Content (if "downloading" status persists)
```

### 3.4 Emergency Recovery

| Problem | Quick Fix |
|---------|-----------|
| Services stopped | Click **Start Services** on dashboard |
| Database issues | Click **Diagnostics** → auto-fixes problems |
| Content mismatch | Click **Reset Content** (after import) |
| Database too large | Click **Deep Cleanup** |

---

## 4. Downloads

### 4.1 WSUS Manager Application

| File | Description |
|------|-------------|
| **WsusManager.exe** | Portable GUI application (recommended) |
| **Scripts/** | PowerShell scripts (required - keep with EXE) |
| **Modules/** | PowerShell modules (required - keep with EXE) |

**Important:** The EXE requires the `Scripts/` and `Modules/` folders in the same directory.

### 4.2 Required Installers

Download and save to `C:\WSUS\SQLDB\` before installation:

| File | Description | Download Link |
|------|-------------|---------------|
| SQLEXPRADV_x64_ENU.exe | SQL Server Express 2022 | [Microsoft Download](https://www.microsoft.com/en-us/download/details.aspx?id=104781) |
| SSMS-Setup-ENU.exe | SQL Server Management Studio | [SSMS Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms) |

---

## 5. System Requirements

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

## 6. Directory Structure

| Path | Purpose |
|------|---------|
| `C:\WSUS\` | Content directory (required) |
| `C:\WSUS\SQLDB\` | SQL/SSMS installer files |
| `C:\WSUS\Logs\` | Application and maintenance logs |
| `C:\WSUS\WsusContent\` | Update files (auto-created by WSUS) |

**Critical:** Content path must be `C:\WSUS\` - NOT `C:\WSUS\wsuscontent\`

---

## 7. Installation Procedure

### 7.1 Pre-Installation Checklist

| Step | Action | Verification |
|------|--------|--------------|
| 1 | Download WSUS Manager package | Extract to `C:\WSUS\` |
| 2 | Download SQL Server Express 2022 | Save to `C:\WSUS\SQLDB\` |
| 3 | Download SSMS (optional) | Save to `C:\WSUS\SQLDB\` |
| 4 | Verify disk space | Minimum 50 GB free on C: |
| 5 | Verify admin privileges | Right-click > Run as Administrator |

### 7.2 Installation Steps

| Step | Action |
|------|--------|
| 1 | Launch `WsusManager.exe` as Administrator |
| 2 | Click **Install WSUS** from the Operations menu |
| 3 | Select the folder containing SQL installers (default: `C:\WSUS\SQLDB\`) |
| 4 | Wait for installation to complete (10-30 minutes) |
| 5 | Verify dashboard shows all services running (green) |

---

## 8. Dashboard Overview

The dashboard displays real-time status with auto-refresh every 30 seconds.

### 8.1 Status Cards

| Card | Information | Status Colors |
|------|-------------|---------------|
| **Services** | SQL Server, WSUS, IIS status | Green = All running, Orange = Partial, Red = Stopped |
| **Database** | SUSDB size vs 10GB limit | Green = <7GB, Yellow = 7-9GB, Red = >9GB |
| **Disk Space** | Free space on system drive | Green = >50GB, Yellow = 10-50GB, Red = <10GB |
| **Automation** | Scheduled task status | Green = Configured, Orange = Not configured |

### 8.2 Quick Actions

| Button | Function |
|--------|----------|
| Health Check | Verify WSUS configuration and connectivity |
| Deep Cleanup | Remove obsolete updates, optimize database |
| Online Sync | Run sync with Microsoft Update and maintenance |
| Start Services | Auto-recover stopped services |

---

## 9. Server Mode Configuration

The application auto-detects network connectivity and configures the appropriate mode.

| Mode | Description | Available Operations |
|------|-------------|---------------------|
| **Online** | Internet-connected WSUS server | Export, Online Sync |
| **Air-Gap** | Isolated network WSUS server | Import, Restore Database |

Mode is saved to user settings and persists across restarts.

---

## 10. Operations Reference

### 10.1 Operations Menu

| Operation | Description | Mode |
|-----------|-------------|------|
| Install WSUS | Install WSUS + SQL Express from scratch | Both |
| Restore Database | Restore SUSDB from backup file | Air-Gap |
| Create GPO | Copy GPO files to `C:\WSUS GPO` for DC import | Both |
| Export to Media | Export DB and content to USB drive | Online |
| Import from Media | Import updates from USB drive | Air-Gap |
| Online Sync | Run sync with Microsoft Update and optimization | Online |
| Schedule Task | Configure automated Online Sync | Online |
| Deep Cleanup | Aggressive cleanup for space recovery | Both |
| Diagnostics | Comprehensive scan with automatic fixes | Both |
| Reset Content | Re-verify content files after DB import | Air-Gap |

---

## 11. Routine Maintenance Procedures

### 11.1 Daily Checks (Automated)

| Check | Expected Result |
|-------|-----------------|
| Services Status | All services running (green) |
| Database Size | Below 9 GB |
| Disk Space | Above 10 GB free |

### 11.2 Online Sync Procedure

| Step | Action | Notes |
|------|--------|-------|
| 1 | Launch WSUS Manager as Administrator | |
| 2 | Verify all services are running | Use "Start Services" if needed |
| 3 | Click **Online Sync** | |
| 4 | Select sync profile: | |
| | - **Sync Only**: Just sync and approve | 5-10 minutes |
| | - **Quick Sync**: Sync + cleanup + backup | 15-30 minutes |
| | - **Full Sync**: Complete maintenance cycle | 30-60 minutes |
| 5 | (Optional) Configure export paths: | |
| | - **Full Export Path**: Network share for backup | |
| | - **Differential Path**: USB drive for air-gap | |
| | - **Export Days**: Age filter (default: 30) | |
| 6 | Click **Run Sync** | |
| 7 | Monitor progress in log panel | Some phases may be quiet for several minutes |
| 8 | Verify completion message | |

### 11.3 Scheduling Automated Maintenance

| Step | Action |
|------|--------|
| 1 | Click **Schedule Task** from Operations menu |
| 2 | Select frequency: Daily, Weekly, or Monthly |
| 3 | Set preferred time (recommended: 2:00 AM) |
| 4 | Enter domain credentials for task execution |
| 5 | Click **Create** to register the scheduled task |

---

## 12. Air-Gapped Network Procedure

### 12.1 Export from Online Server

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS | Run **Online Sync** to prepare updates |
| 2 | Online WSUS | Click **Export to Media** (or use export options in Online Sync dialog) |
| 3 | Online WSUS | Select export type: |
| | | - **Full**: Complete database and all content |
| | | - **Differential**: Only updates from last N days |
| 4 | Online WSUS | Select destination folder (USB drive) |
| 5 | Online WSUS | Wait for export to complete |

### 12.2 Import to Air-Gapped Server

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

## 13. Database Management

### 13.1 Database Backup

Database backups are automatically created during:
- Monthly Maintenance (Full profile)
- Export to Media operations

Backup location: `C:\WSUS\SUSDB_backup_YYYYMMDD.bak`

### 13.2 Database Restore Procedure

| Step | Action |
|------|--------|
| 1 | Click **Restore Database** from Operations menu |
| 2 | Select backup file (.bak) |
| 3 | Confirm restore operation |
| 4 | Wait for restore to complete |
| 5 | Verify dashboard shows database status |

**Important:** After restoring the database, the WSUS server will need to re-verify and re-download update content. **This process can take 30+ minutes depending on your content size.** The dashboard may show "Update is downloading" status during this time - this is normal behavior. Do not interrupt the process. Large content stores (50GB+) may take several hours to fully re-verify.

### 13.3 SQL Sysadmin Permission Setup

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

## 14. Domain Controller Configuration

Run on the Domain Controller, not the WSUS server.

### 14.1 GPO Deployment

| Step | Action |
|------|--------|
| 1 | On WSUS server: Click **Create GPO** to copy files to `C:\WSUS GPO` |
| 2 | Copy `C:\WSUS GPO` folder to Domain Controller |
| 3 | On DC: Open PowerShell as Administrator |
| 4 | Run: `.\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://WSUS01:8530"` |

### 14.2 GPOs Created

| GPO Name | Purpose |
|----------|---------|
| WSUS Update Policy | Client update settings |
| WSUS Inbound Firewall | Inbound firewall rules |
| WSUS Outbound Firewall | Outbound firewall rules |

### 14.3 Client Verification

On client machines, run:
```powershell
gpupdate /force
wuauclt /detectnow /reportnow
```

---

## 15. Troubleshooting

### 15.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Endless downloads | Wrong content path | Set content path to `C:\WSUS\` (not `C:\WSUS\wsuscontent\`) |
| "Content downloading" after import | DB/content mismatch | Click **Reset Content** to re-verify files |
| Clients not updating | GPO not applied | Run `gpupdate /force`, check ports 8530/8531 |
| Database errors | Missing sysadmin | Grant sysadmin role in SSMS |
| Services not starting | Dependency issues | Use "Start Services" button on dashboard |
| Script not found | Missing folders | Ensure Scripts/ and Modules/ are with EXE |
| DB size shows "Offline" | SQL not running | Start SQL Server Express service |

### 15.2 Diagnostics Failures

| Check | Resolution |
|-------|------------|
| Services Stopped | Run **Diagnostics** to auto-recover |
| SQL Browser Not Running | Diagnostics will start and set to Automatic |
| Firewall Rules Missing | Diagnostics creates required rules automatically |
| Permissions Incorrect | Diagnostics sets correct ACLs on content folder |
| Database Connection Failed | Verify SQL Server is running, check sysadmin role |
| NETWORK SERVICE Login Missing | Diagnostics creates SQL login with dbcreator role |
| WSUS Application Pool Stopped | Diagnostics starts the WsusPool |

---

## 16. Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.8.9 | Jan 2026 | Reset Content button for air-gap import fix, renamed Monthly Maintenance to Online Sync, export path options, Definition Updates auto-approved |
| 3.8.8 | Jan 2026 | Fixed declined update purge error, database shrink retry logic, suppressed noisy spDeleteUpdate errors |
| 3.8.7 | Jan 2026 | Live Terminal mode, import dialog improvements, Create GPO button, non-blocking network check |
| 3.8.6 | Jan 2026 | Input fields disabled during operations, code cleanup |
| 3.8.5 | Jan 2026 | Fixed output log refresh, non-interactive install, domain credentials for tasks |
| 3.8.4 | Jan 2026 | Fixed export hanging, export mode options, GitHub Actions fixes |
| 3.8.3 | Jan 2026 | Script validation, button state management, distribution package fixes |
| 3.5.2 | Jan 2026 | Security hardening, service refresh fix, 323 unit tests |

---

## 17. Reference Links

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

## 18. Support

| Contact | Information |
|---------|-------------|
| Author | Tony Tran, ISSO |
| Organization | Classified Computing, GA-ASI |
| Repository | GitHub Issues |

---

*Internal Use Only - General Atomics Aeronautical Systems, Inc.*
