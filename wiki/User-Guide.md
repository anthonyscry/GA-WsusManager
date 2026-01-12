# User Guide

This guide explains how to use the WSUS Manager GUI application for day-to-day operations.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Dashboard Overview](#dashboard-overview)
3. [Server Mode Toggle](#server-mode-toggle)
4. [Operations Menu](#operations-menu)
5. [Quick Actions](#quick-actions)
6. [Settings](#settings)
7. [Viewing Logs](#viewing-logs)

---

## Getting Started

### Launching the Application

1. Right-click `WsusManager.exe`
2. Select **Run as administrator**

> **Important**: Administrator privileges are required for all WSUS operations.

### First Launch

On first launch, the application will:
1. Detect your WSUS installation
2. Load default settings
3. Display the dashboard

If WSUS is not installed, you'll see warnings on the dashboard. Use **Install WSUS** to set up a new server.

---

## Dashboard Overview

The dashboard is your main monitoring view, showing the health of your WSUS infrastructure at a glance.

### Status Cards

The dashboard displays four color-coded status cards:

#### Services Card
| Color | Meaning |
|-------|---------|
| Green | All services running (SQL, WSUS, IIS) |
| Orange | Some services running |
| Red | Critical services stopped |

#### Database Card
| Color | Size Range | Action |
|-------|------------|--------|
| Green | < 7 GB | Healthy |
| Yellow | 7-9 GB | Consider cleanup |
| Red | > 9 GB | Cleanup required (approaching 10GB limit) |

#### Disk Space Card
| Color | Free Space | Action |
|-------|------------|--------|
| Green | > 50 GB | Healthy |
| Yellow | 10-50 GB | Monitor |
| Red | < 10 GB | Free space immediately |

#### Automation Card
| Color | Meaning |
|-------|---------|
| Green | Scheduled task configured and ready |
| Orange | No scheduled task configured |

### Auto-Refresh

The dashboard automatically refreshes every **30 seconds**. A refresh guard prevents overlapping operations that could hang the UI.

---

## Server Mode Toggle

WSUS Manager supports two server modes to show only relevant operations:

### Online Mode
For WSUS servers connected to the internet:
- **Visible**: Export to Media, Monthly Maintenance
- **Hidden**: Import from Media

### Air-Gap Mode
For WSUS servers on disconnected networks:
- **Visible**: Import from Media
- **Hidden**: Export to Media, Monthly Maintenance

### Changing Modes

Server Mode is auto-detected based on internet connectivity.

1. Ensure the server has internet access for Online mode
2. Disconnect to switch to Air-Gap mode
3. Menu items update automatically

---

## Operations Menu

### Install WSUS

Installs WSUS with SQL Server Express from scratch.

**Steps:**
1. Click **Install WSUS**
2. Browse to folder containing SQL installers
3. Click **Install**
4. Wait 15-30 minutes for completion

> **Note:** If the default installer folder is missing SQL/SSMS files, the installer will prompt you to select the correct folder.

**Prerequisites:**
- SQL installers in selected folder
- No existing WSUS installation
- Administrator privileges

### Restore Database

Restores SUSDB from a backup file.

**Steps:**
1. Click **Restore Database**
2. Confirm the warning dialog
3. Ensure backup file is at `C:\WSUS\`
4. Wait for restore to complete

**Prerequisites:**
- Valid `.bak` file at `C:\WSUS\`
- Update files in `C:\WSUS\WsusContent\`
- SQL Server running

### Export to Media

Exports database and update files for transfer to air-gapped servers.

**Steps:**
1. Click **Export to Media**
2. Choose export type:
   - **Full Export**: Complete database and all files
   - **Differential Export**: Only recent updates (N days)
3. Select destination folder (USB drive)
4. Wait for export to complete

**Output:**
```
[Destination]\
├── SUSDB_backup_[date].bak     # Database backup
├── WsusContent\                 # Update files
└── export_manifest.json         # Export metadata
```

### Import from Media

Imports updates from USB media to an air-gapped server.

**Steps:**
1. Click **Import from Media**
2. Select source folder (USB drive)
3. Click **Import**
4. Wait for import to complete

> **Note:** The import runs non-interactively using the selected folder and will not prompt for additional input.

**Prerequisites:**
- Valid export folder structure
- Sufficient disk space

### Monthly Maintenance

Runs comprehensive maintenance tasks.

> **Online-only:** Run Monthly Maintenance on the **Online** WSUS server.

**What it does:**
1. Synchronizes with Microsoft Update
2. Declines superseded updates
3. Runs WSUS cleanup wizard
4. Cleans database records
5. Optimizes indexes
6. Backs up database

**When to run:**
- Monthly (recommended)
- After initial sync
- When database grows large

**UX Note:** Some phases can be quiet for several minutes; the GUI refreshes status roughly every 30 seconds.

### Schedule Maintenance Task

Creates or updates the scheduled task that runs Monthly Maintenance.

> **Online-only:** Create the schedule on the **Online** WSUS server.

**Steps:**
1. Click **Schedule Task** in the Maintenance section
2. Choose schedule (Weekly/Monthly/Daily)
3. Set the start time (default: Saturday at 02:00)
4. Select the maintenance profile
5. Click **Create Task**

**Default Recommendation:** Weekly on Saturday at 02:00.

### Deep Cleanup

Aggressive cleanup for space recovery.

**What it does:**
1. Removes obsolete updates
2. Cleans superseded updates
3. Removes unneeded content files
4. Shrinks database
5. Compacts content directory

**When to use:**
- Database approaching 10GB limit
- Disk space critically low
- After declining many updates

### Health Check

Verifies WSUS configuration without making changes.

**Checks performed:**
- Service status (SQL, WSUS, IIS)
- Database connectivity
- Firewall rules
- Directory permissions
- SSL/HTTPS configuration

### Health + Repair

Runs health check and automatically fixes issues.

**What it fixes:**
- Starts stopped services
- Creates missing firewall rules
- Sets directory permissions
- Repairs service dependencies

---

## Quick Actions

The dashboard provides quick action buttons for common tasks:

| Button | Action |
|--------|--------|
| **Health Check** | Run health verification |
| **Deep Cleanup** | Run aggressive cleanup |
| **Maintenance** | Run monthly maintenance |
| **Start Services** | Start all WSUS services |

### Start Services

The **Start Services** button starts services in dependency order:
1. SQL Server Express
2. IIS (W3SVC)
3. WSUS Service

---

## Settings

Access settings via the **Settings** button in the sidebar.

### Configurable Options

| Setting | Default | Description |
|---------|---------|-------------|
| WSUS Content Path | `C:\WSUS` | Root directory for WSUS |
| SQL Instance | `.\SQLEXPRESS` | SQL Server instance name |

### Settings Storage

Settings are saved to:
```
%APPDATA%\WsusManager\settings.json
```

---

## Viewing Logs

### Application Logs

WSUS Manager logs operations to:
```
C:\WSUS\Logs\
```

Log files are named with timestamps:
```
WsusManager_2026-01-11_143022.log
```

### Opening Log Folder

Click the **folder icon** next to "Open Log" in the sidebar to open the logs directory in Explorer.

### Log Format

```
2026-01-11 14:30:22 [INFO] Starting monthly maintenance
2026-01-11 14:30:25 [OK] Database connection verified
2026-01-11 14:31:00 [WARN] High database size: 7.5 GB
2026-01-11 14:35:00 [OK] Maintenance completed successfully
```

---

## Keyboard Shortcuts

Currently, WSUS Manager operates primarily via mouse. Keyboard navigation:
- **Tab**: Navigate between controls
- **Enter**: Activate selected button
- **Escape**: Close dialogs

---

## Tips and Best Practices

### Regular Maintenance
- Run **Monthly Maintenance** on a schedule
- Monitor database size (aim for < 7 GB)
- Keep at least 50 GB free disk space

### Before Major Operations
- Create a database backup
- Check disk space availability
- Verify all services are running

### After Sync
- Review new updates
- Decline unneeded updates
- Run cleanup if needed

### Air-Gap Transfers
- Use USB 3.0 drives for speed
- Verify exports before transport
- Test imports on non-production first

---

## Next Steps

- [[Air-Gap Workflow]] - Detailed disconnected network guide
- [[Troubleshooting]] - Fix common issues
- [[Module Reference]] - PowerShell function documentation
