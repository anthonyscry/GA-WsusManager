# WSUS Manager - Standard Operating Procedure

| **Document Information** | |
|--------------------------|-------------------------|
| **Author** | Tony Tran, ISSO, GA-ASI |
| **Version** | 4.0.4 |
| **Last Updated** | March 2026 |
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
| **WsusManager.exe** | GUI application (requires Scripts/ and Modules/ in same directory) |
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
| Diagnostics | Comprehensive health check with automatic repair |
| Deep Cleanup | Full database cleanup (supersession, indexes, shrink) |
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
| Deep Cleanup | Full 6-step database maintenance (see below) | Both |
| Diagnostics | Comprehensive health check with automatic repair | Both |
| Reset Content | Re-verify content files after DB import | Air-Gap |

### 10.2 Deep Cleanup Details

Deep Cleanup performs comprehensive database maintenance:

| Step | Operation | Description |
|------|-----------|-------------|
| 1 | WSUS Built-in | Declines superseded, removes obsolete updates |
| 2 | Declined Supersession | Removes records from tbRevisionSupersedesUpdate |
| 3 | Superseded Supersession | Batched removal (10k/batch) for superseded records |
| 4 | Declined Purge | Deletes declined updates via spDeleteUpdate |
| 5 | Index Optimization | Rebuilds/reorganizes fragmented indexes |
| 6 | Database Shrink | Compacts database to reclaim space |

**Duration:** 30-90 minutes | **Note:** WSUS service stopped during operation

### 10.3 Smart Update Policy

**Default Products:** Windows 11, Windows Server 2019, Microsoft Edge, Microsoft Defender Antivirus, Microsoft Defender for Endpoint, Office 2016, Microsoft 365 Apps, SQL Server 2022, Security Essentials

**Default Classifications:** Critical Updates, Security Updates, Definition Updates, Updates, Update Rollups

**Auto-Decline Rules (removed from catalog):**
- Expired, superseded, and updates older than 6 months (preserves already-approved)
- ARM64, Legacy builds (21H2, 22H2, 23H2), Preview/Beta
- Edge non-stable (Dev/Beta/Extended Stable), Office 365/2019/LTSC 2021, WSL

**Not Approved (kept for manual review):** 25H2, x86/32-bit, Upgrades

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
| 5 | (Optional) Configure export path: | |
| | - **Full Export Path**: Network share for backup | |
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

> **Note:** Depending on your program, transferring files into SAP or collateral spaces may require a Data Transfer Request (DTR). Check with your security team before physically moving media across network boundaries.

### 12.1 Export from Online Server

| Step | Location | Action |
|------|----------|--------|
| 1 | Online WSUS | Run **Online Sync** to prepare updates |
| 2 | Online WSUS | Click **Export to Media** (or use export options in Online Sync dialog) |
| 3 | Online WSUS | Select destination folder (USB drive) |
| 4 | Online WSUS | Wait for export to complete |

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

> **AIR-GAP ONLY:** These GPOs direct all Windows Update traffic to the internal
> WSUS server and block Microsoft Update. Do NOT deploy on internet-connected systems.

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
| 4.0.4 | Mar 2026 | sqlcmd.exe fallback for all DB operations, 6-month age decline (preserves approved updates), sysadmin check via sqlcmd, explicit SQLPS module import |
| 4.0.3 | Mar 2026 | Smart decline policy (Edge/Office/WSL/Preview/ARM64), DNS preflight check, 180-minute sync timeout, default products and classifications, WID auto-migration, exact product name matching |
| 4.0.2 | Mar 2026 | GPO schtasks push (no WinRM), 15+ security fixes, robocopy exit code normalization, removed differential export, removed .GetNewClosure() |
| 4.0.1 | Mar 2026 | GUI automation tests (49 tests), FlaUI test coverage (71 tests), install script sync, version alignment |
| 4.0.0 | Mar 2026 | Dialog factory, operation runner, health score (0-100), operation history, notifications, DB trending, splash screen, keyboard shortcuts, system tray, 490+ tests |
| 3.9.0 | Mar 2026 | ARM64/25H2 auto-decline, PowerShell-only distribution restored |
| 3.8.12 | Feb 2026 | TrustServerCertificate compatibility fix |
| 3.8.10 | Feb 2026 | Deep Cleanup 6-step workflow, unified Diagnostics |
| 3.8.9 | Feb 2026 | Online Sync rename, Definition Updates auto-approval, Reset Content button |
| 3.8.8 | Jan 2026 | Declined update purge fix, shrink retry logic |
| 3.8.7 | Jan 2026 | Live Terminal mode, Create GPO button, WSUS install detection |

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
