# User Guide

This guide explains how to use the WSUS Manager GUI application for day-to-day operations.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Dashboard Overview](#dashboard-overview)
3. [Server Mode Toggle](#server-mode-toggle)
4. [Operations Menu](#operations-menu)
5. [Quick Actions](#quick-actions)
6. [Operation History](#operation-history)
7. [Notifications](#notifications)
8. [Settings](#settings)
9. [Viewing Logs](#viewing-logs)
10. [Keyboard Shortcuts](#keyboard-shortcuts)

---

## Getting Started

### Launching the Application

1. Right-click `GA-WsusManager.exe`
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

The dashboard displays color-coded status cards plus a Health Score band:

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

### Health Score

The dashboard displays a **Health Score** band (0-100) that combines multiple indicators into a single weighted score:

| Component | Weight | What It Measures |
|-----------|--------|------------------|
| Services | 30 | SQL Server, WSUS, IIS running status |
| Database | 20 | SUSDB size relative to 10GB limit |
| Sync Recency | 20 | Time since last successful sync |
| Disk Space | 20 | Available storage for updates |
| Last Operation | 10 | Result of most recent operation |

**Grading:**
| Grade | Score Range | Color |
|-------|------------|-------|
| Green | 80-100 | Healthy |
| Yellow | 50-79 | Needs attention |
| Red | 0-49 | Critical issues |
| Unknown | N/A | All data sources failed |

### DB Size Trend Indicator

The database card includes a **trend indicator** showing the projected days until the database reaches the 10GB SQL Express limit. This uses linear regression over the last 30 days of size snapshots.

| Alert Level | Days Until Full | Action |
|-------------|-----------------|--------|
| Normal | > 180 days | No action needed |
| Warning | 90-180 days | Plan a cleanup |
| Critical | < 90 days | Run Deep Cleanup immediately |

### Last Successful Sync

A timestamp showing when the last successful sync completed:

| Color | Time Since Sync | Meaning |
|-------|-----------------|---------|
| Green | < 7 days | Up to date |
| Yellow | 7-30 days | Sync soon |
| Red | > 30 days | Overdue -- sync immediately |

### Auto-Refresh

The dashboard automatically refreshes every **30 seconds**. A refresh guard prevents overlapping operations that could hang the UI. Dashboard refresh is also skipped while an operation is running to prevent log output stutter.

---

## Server Mode Toggle

WSUS Manager supports two server modes to show only relevant operations:

### Online Mode
For WSUS servers connected to the internet:
- **Visible**: Online Sync (sync with Microsoft Update), Robocopy

### Air-Gap Mode
For WSUS servers on disconnected networks:
- **Hidden**: Online Sync (not applicable without internet)
- **Always available**: Robocopy (for file transfers in both directions)

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

> **Note:** If the default installer folder is missing the SQL Express installer, the app will prompt you to select the correct folder. SSMS is optional and will be skipped if not present.

**Prerequisites:**
- SQL installers in selected folder
- No existing WSUS installation
- Administrator privileges

### Create GPO

> **AIR-GAP ONLY:** These GPOs direct all Windows Update traffic to the internal
> WSUS server and block Microsoft Update. Do NOT deploy on internet-connected systems.

Copies Group Policy Objects to `C:\WSUS\WSUS GPO` for transfer to a Domain Controller.

**Steps:**
1. Click **Create GPO**
2. Confirm the copy operation
3. Copy the `C:\WSUS\WSUS GPO` folder to the Domain Controller
4. On the DC, run as Administrator:
   ```powershell
   cd 'C:\WSUS\WSUS GPO'
   .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://YOURSERVER:8530"
   ```

**To force clients to update:**
```powershell
# On individual clients:
gpupdate /force

# Verify on clients:
gpresult /r | findstr WSUS
```

**GPOs Created:**
| GPO Name | Purpose | Link Target |
|----------|---------|-------------|
| WSUS Update Policy | Client update settings | Domain root |
| WSUS Inbound Allow | Firewall rules for WSUS server | Member Servers\WSUS Server |
| WSUS Outbound Allow | Firewall rules for clients | Workstations, Member Servers, DCs |

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

### Robocopy

Copies update content between servers and USB media. Used for both directions: online server → USB (for transport to air-gap site), and USB → air-gap server (after physical transfer).

**Steps:**
1. Click **Robocopy** in the Maintenance section
2. In the Robocopy dialog:
   - Browse to **Source** folder
   - Browse to **Destination** folder
3. Click **Start Transfer**
4. Wait for transfer to complete

> **Note:** Robocopy is non-destructive. It creates a subfolder at the destination and will not delete any files from the source.

**Common Usage:**
| Direction | Source | Destination |
|-----------|--------|-------------|
| Online → USB | `C:\WSUS\WsusContent` | USB drive folder (e.g., `E:\WSUS_Transfer`) |
| USB → Air-Gap | USB drive folder | `C:\WSUS` |

**Prerequisites:**
- Sufficient disk space on destination
- Source folder accessible

### Online Sync

Runs comprehensive sync and maintenance tasks.

> **Online-only:** Run Online Sync on the **Online** WSUS server.

**Sync Profiles:**
| Profile | Operations | Use When |
|---------|------------|----------|
| **Full Sync** | Sync -> Cleanup -> Ultimate Cleanup -> Backup -> Export | Monthly maintenance |
| **Quick Sync** | Sync -> Cleanup -> Backup (skip heavy cleanup) | Weekly quick sync |
| **Sync Only** | Synchronize and approve updates only | Just need updates |

**What Full Sync does:**
1. Synchronizes with Microsoft Update
2. Declines superseded, expired, and old updates
3. Approves new updates (Critical, Security, Rollups, Service Packs, Updates, Definition Updates)
4. Runs WSUS cleanup wizard
5. Cleans database records and purges declined updates
6. Optimizes indexes
7. Backs up database
8. Exports to configured paths (optional)

**Export Options (Optional):**
| Field | Description |
|-------|-------------|
| **Full Export Path** | Network share for complete backup + content mirror |

> **Note:** Export path is optional. If not specified, the export step is skipped.

**When to run:**
- Monthly (Full Sync recommended)
- Weekly (Quick Sync)
- After initial sync
- When database grows large

**UX Note:** Some phases can be quiet for several minutes; the GUI refreshes status roughly every 30 seconds.

### Schedule Online Sync Task

Creates or updates the scheduled task that runs Online Sync.

> **Online-only:** Create the schedule on the **Online** WSUS server.

**Steps:**
1. Click **Schedule Task** in the Online Sync section
2. Choose schedule (Weekly/Monthly/Daily)
3. Set the start time (default: Saturday at 02:00)
4. Select the sync profile (Full, Quick, or SyncOnly)
5. Enter credentials for unattended execution
6. Click **Create Task**

**Default Recommendation:** Weekly Full Sync on Saturday at 02:00.

### Deep Cleanup

Comprehensive database cleanup for space recovery and performance optimization.

**What it does (6 steps):**
1. **WSUS built-in cleanup** - Declines superseded updates, removes obsolete updates, cleans unneeded content files
2. **Remove declined supersession records** - Cleans `tbRevisionSupersedesUpdate` table for declined updates
3. **Remove superseded supersession records** - Batched cleanup (10,000 records per batch) for superseded updates
4. **Delete declined updates** - Purges declined updates from database via `spDeleteUpdate` (100-record batches)
5. **Index optimization** - Rebuilds highly fragmented indexes (>30%), reorganizes moderately fragmented (10-30%), updates statistics
6. **Database shrink** - Compacts database to reclaim disk space (with retry logic for backup contention)

**Progress reporting:**
- Shows step number and description for each phase
- Reports batch progress during large operations
- Displays database size before and after shrink
- Shows total duration at completion

**When to use:**
- Database approaching 10GB limit (SQL Express)
- Disk space critically low
- After declining many updates manually
- Quarterly maintenance

**Duration:** 30-90 minutes depending on database size

### Diagnostics

Comprehensive health check with automatic repair (combines former Health Check and Health + Repair).

**What it checks and fixes:**
- **Services**: SQL Server, WSUS, IIS - starts stopped services, sets correct startup type
- **SQL Browser**: Starts and sets to Automatic if not running
- **Database connectivity**: Verifies connection to SUSDB
- **SQL Login**: Creates NETWORK SERVICE login with dbcreator role if missing
- **Firewall rules**: Creates inbound rules for ports 8530/8531 if missing
- **Directory permissions**: Sets correct ACLs on WSUS content folder
- **Application Pool**: Starts WsusPool if stopped

**Output:**
- Clear pass/fail status for each check
- Automatic fix applied when issues detected
- Summary of all findings at completion

### Reset Content

Forces WSUS to re-verify all content files against the database.

> **Air-Gap Tip:** Use this after importing a database backup when WSUS shows "content is still downloading" even though files exist.

**What it does:**
1. Stops WSUS service
2. Runs `wsusutil reset`
3. Restarts WSUS service

**When to use:**
- After database restore/import on air-gapped servers
- When WSUS shows download status but content files are present
- To fix content verification mismatches

**Note:** This operation can take several minutes depending on content size, as WSUS re-verifies each file.

---

## Quick Actions

The dashboard provides quick action buttons for common tasks:

| Button | Action |
|--------|--------|
| **Diagnostics** | Run comprehensive health check with automatic repair |
| **Deep Cleanup** | Run full database cleanup (supersession, indexes, shrink) |
| **Online Sync** | Run online sync with Microsoft Update |
| **Start Services** | Start all WSUS services (SQL, WSUS, IIS) |

### Start Services

The **Start Services** button starts services in dependency order:
1. SQL Server Express
2. IIS (W3SVC)
3. WSUS Service

---

## Operation History

Click the **History** button in the bottom bar (or press **Ctrl+H**) to view a list of past operations.

### What It Shows

The History view displays the last **50 operations** with:
- Operation type (Diagnostics, Online Sync, Deep Cleanup, etc.)
- Duration
- Result (Success, Failed, Cancelled)
- Summary text

### Storage

History is stored in JSON format at:
```
%APPDATA%\WsusManager\history.json
```

The file is automatically trimmed to 100 entries. File-lock retry logic prevents corruption if multiple processes access the file simultaneously.

---

## Notifications

WSUS Manager displays a notification when an operation completes. This is useful when running long operations (Deep Cleanup, Online Sync) while working in other applications.

### Notification Fallback

The notification system uses a 3-tier fallback:
1. **Windows 10 Toast** -- native toast notification (preferred)
2. **Balloon Tip** -- system tray balloon notification (fallback)
3. **Log Only** -- writes to the application log if neither UI method is available

### Configuration

Notifications can be enabled or disabled in the **Settings** dialog:
- **Enable Notifications** -- toggle completion notifications on/off
- **Enable Beep** -- play a sound on operation completion

---

## Settings

Access settings via the **Settings** button in the bottom bar.

### Configurable Options

| Setting | Default | Description |
|---------|---------|-------------|
| WSUS Content Path | `C:\WSUS` | Root directory for WSUS |
| SQL Instance | `.\SQLEXPRESS` | SQL Server instance name |
| Notifications | Enabled | Show toast/balloon on operation completion |
| Beep on Completion | Disabled | Play sound when operations finish |
| Minimize to Tray | Disabled | Minimize to system tray instead of taskbar |

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

WSUS Manager supports the following keyboard shortcuts:

| Shortcut | Action |
|----------|--------|
| **Ctrl+D** | Run Diagnostics |
| **Ctrl+S** | Run Online Sync |
| **Ctrl+H** | Open History view |
| **Ctrl+R** / **F5** | Refresh Dashboard |
| **Tab** | Navigate between controls |
| **Enter** | Activate selected button |
| **Escape** | Close dialogs |

The log panel also supports right-click context menu with **Copy All** and **Save to File** options.

---

## Tips and Best Practices

### Regular Maintenance
- Run **Online Sync** on a schedule
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
- Verify the Robocopy transfer completed before disconnecting the drive
- Test the workflow on non-production servers first

---

## Next Steps

- [[Air-Gap Workflow]] - Detailed disconnected network guide
- [[Troubleshooting]] - Fix common issues
- [[Module Reference]] - PowerShell function documentation
