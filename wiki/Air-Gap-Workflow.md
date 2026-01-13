# Air-Gap Workflow

This guide provides detailed instructions for managing Windows updates on air-gapped (disconnected) networks using WSUS Manager.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Initial Setup](#initial-setup)
4. [Export Process](#export-process)
5. [Physical Transfer](#physical-transfer)
6. [Import Process](#import-process)
7. [Scheduling](#scheduling)
8. [Best Practices](#best-practices)

---

## Overview

### What is an Air-Gap?

An air-gapped network is physically isolated from the internet and other networks. This is common in:
- Classified environments
- Critical infrastructure
- Industrial control systems
- High-security facilities

### The Challenge

WSUS normally downloads updates directly from Microsoft. On an air-gapped network, updates must be:
1. Downloaded on an internet-connected server
2. Physically transferred via removable media
3. Imported to the disconnected WSUS server

### WSUS Manager Solution

WSUS Manager automates this workflow with:
- **Export to Media** - Creates portable update package
- **Import from Media** - Applies updates to air-gapped server
- **Server Mode Toggle** - Shows only relevant operations

---

## Architecture

### Two-Server Model

```
┌─────────────────────┐                    ┌─────────────────────┐
│   ONLINE WSUS       │                    │   AIR-GAP WSUS      │
│   (Internet)        │                    │   (Disconnected)    │
├─────────────────────┤                    ├─────────────────────┤
│ - Syncs with MSFT   │    USB Drive       │ - Receives imports  │
│ - Approves updates  │ =================> │ - Serves clients    │
│ - Exports to media  │   (Sneakernet)     │ - Local approvals   │
└─────────────────────┘                    └─────────────────────┘
```

### Components

| Server | Network | Mode | Primary Functions |
|--------|---------|------|-------------------|
| Online WSUS | Internet-connected | Online | Sync, approve, export |
| Air-Gap WSUS | Disconnected | Air-Gap | Import, serve clients |

---

## Initial Setup

### Online Server Setup

1. Install WSUS Manager
2. Run **Install WSUS** to set up fresh installation
3. Configure products and classifications
4. Run initial sync with Microsoft
5. Approve required updates
6. Set mode to **Online**

### Air-Gap Server Setup

1. Copy WSUS Manager to the air-gapped server
2. Run **Install WSUS** (SQL installers must be pre-staged)
3. Set mode to **Air-Gap**
4. Configure to match online server settings

### Matching Configuration

Both servers should have identical:
- Product selections
- Classification selections
- Computer groups
- Approval rules

---

## Export Process

### Full Export

Use for initial transfer or complete refresh.

**When to use:**
- First-time setup of air-gap server
- After major changes to online server
- To reset air-gap server state

**Steps:**

1. On the **Online** server, run **Monthly Maintenance**
2. Click **Export to Media**
3. Select **Full Export**
4. Choose destination (USB drive letter)
5. Wait for export to complete

**Export Contents:**
```
E:\WSUS_Export_2026-01-11\
├── SUSDB_backup_20260111.bak    # Complete database backup
├── WsusContent\                  # All approved update files
│   ├── 00\                       # Content organized by hash
│   ├── 01\
│   └── ...
└── export_manifest.json          # Export metadata
```

**Time estimate:** 30 minutes to several hours (depending on content size)

### Differential Export

Use for regular update transfers.

**When to use:**
- Regular monthly updates
- Incremental transfers
- Limited USB capacity

**Steps:**

1. On the **Online** server, run **Monthly Maintenance**
2. Click **Export to Media**
3. Select **Differential Export**
4. Enter days to include (default: 30)
5. Choose destination
6. Wait for export to complete

**Export Contents:**
```
E:\WSUS_Export_Diff_2026-01-11\
├── SUSDB_diff_20260111.bak      # Differential backup (smaller)
├── WsusContent\                  # Only recent update files
└── export_manifest.json          # Export metadata
```

**Time estimate:** 5-30 minutes

---

## Physical Transfer

### USB Drive Recommendations

| Factor | Recommendation |
|--------|----------------|
| Capacity | 128 GB minimum, 256+ GB preferred |
| Speed | USB 3.0 or faster |
| Format | NTFS (for files > 4 GB) |
| Encryption | BitLocker recommended |

### Security Considerations

1. **Scan the drive** before connecting to air-gapped network
2. **Use dedicated drives** - don't mix with other data
3. **Enable write-protection** after export if possible
4. **Log transfers** per security policy
5. **Wipe after use** if required by policy

### Transfer Verification

Before disconnecting from online server:
```powershell
# Verify export integrity
Get-FileHash -Path "E:\WSUS_Export_*\*.bak" -Algorithm SHA256
```

Record the hash for verification on the air-gap side.

---

## Import Process

### Pre-Import Checklist

- [ ] All WSUS services running on air-gap server
- [ ] Sufficient disk space (check Dashboard)
- [ ] Database in healthy state
- [ ] USB drive scanned per security policy

### Import Steps

1. Connect USB drive to **Air-Gap** server
2. Launch WSUS Manager
3. Click **Import from Media**
4. In the Transfer dialog:
   - Select **Import** direction
   - **Source (External Media)**: Browse to the export folder on USB (e.g., `E:\WSUS_Export_2026-01-11`)
   - **Destination (WSUS Server)**: Verify destination folder (default: `C:\WSUS`)
5. Click **Start Transfer**
6. Wait for import to complete

> **Note:** The import runs fully non-interactive using the selected folders. No additional prompts will appear during the copy operation.

### Post-Import Steps

#### For Full Imports

1. Click **Restore Database**
2. Confirm the warning
3. Wait for restore to complete
4. Restart WSUS services

#### For Differential Imports

1. Import completes automatically
2. New updates are available
3. No database restore needed

### Verification

After import:
1. Run **Health Check**
2. Open WSUS console
3. Verify new updates appear
4. Check update approvals

---

## Scheduling

### Recommended Schedule

| Task | Frequency | Server | Day |
|------|-----------|--------|-----|
| Sync with Microsoft | Weekly | Online | Sunday |
| Monthly Maintenance | Monthly | Online | 1st of month |
| Export to Media | Monthly | Online | 2nd of month |
| Import from Media | Monthly | Air-Gap | 3rd-5th of month |
| Client update window | Monthly | Both | 2nd week |

### Automation

On the **Online** server, schedule Monthly Maintenance:

1. Click **Schedule Task** in the Maintenance section
2. Choose Weekly/Monthly/Daily and set the start time (recommended: Saturday at 02:00)

Or manually:
```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\WSUS\Scripts\Invoke-WsusMonthlyMaintenance.ps1"
$trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 2:00AM
Register-ScheduledTask -TaskName "WSUS Monthly Maintenance" -Action $action -Trigger $trigger
```

---

## Best Practices

### General

1. **Test in lab first** - Validate workflow before production
2. **Document everything** - Keep records of transfers
3. **Monitor capacity** - Track database and disk growth
4. **Maintain parity** - Keep servers in sync

### Export Best Practices

- Run **Monthly Maintenance** before every export
- Use **Differential** for routine updates
- Use **Full** only when necessary
- Verify export before disconnecting drive

### Import Best Practices

- Always scan USB per security policy
- Check disk space before import
- Run **Health Check** after import
- Verify update counts match export

### Disaster Recovery

Maintain backups on both servers:
- Regular database backups
- Configuration exports
- Documented procedures

### Troubleshooting Common Issues

| Issue | Solution |
|-------|----------|
| Import fails | Check disk space, run Health Check |
| Updates missing | Verify export included all files |
| Database mismatch | Perform full export/restore |
| Slow transfer | Use faster USB drive, USB 3.0 port |

---

## Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         ONLINE SERVER                             │
├──────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │   Sync      │───>│   Approve   │───>│ Monthly Maintenance │  │
│  │   Updates   │    │   Updates   │    │                     │  │
│  └─────────────┘    └─────────────┘    └──────────┬──────────┘  │
│                                                    │             │
│                                       ┌────────────▼───────────┐ │
│                                       │   Export to Media      │ │
│                                       │   (Full/Differential)  │ │
│                                       └────────────┬───────────┘ │
└────────────────────────────────────────────────────┼────────────┘
                                                     │
                                          ┌──────────▼──────────┐
                                          │     USB Drive       │
                                          │   (Sneakernet)      │
                                          └──────────┬──────────┘
                                                     │
┌────────────────────────────────────────────────────┼─────────────┐
│                         AIR-GAP SERVER             │              │
├────────────────────────────────────────────────────┼─────────────┤
│                                        ┌───────────▼───────────┐ │
│                                        │  Import from Media    │ │
│                                        └───────────┬───────────┘ │
│                                                    │              │
│  ┌─────────────────────┐               ┌───────────▼───────────┐ │
│  │  Serve Clients      │<──────────────│  Restore Database     │ │
│  │  (Updates Ready)    │               │  (If Full Export)     │ │
│  └─────────────────────┘               └───────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

- [[User Guide]] - Complete GUI reference
- [[Troubleshooting]] - Fix common issues
- [[Installation Guide]] - Server setup details
