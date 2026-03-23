# Air-Gap Workflow

This guide provides detailed instructions for managing Windows updates on air-gapped (disconnected) networks using WSUS Manager.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Initial Setup](#initial-setup)
4. [Copy to USB (Online Server)](#copy-to-usb-online-server)
5. [Physical Transfer](#physical-transfer)
6. [Copy from USB (Air-Gap Server)](#copy-from-usb-air-gap-server)
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
- **Online Sync** - Syncs and approves updates on the internet-connected server
- **Robocopy** - Copies content to/from USB media (non-destructive, both directions)
- **Restore DB** - Restores the SUSDB database backup on the air-gap server
- **Reset Content** - Re-verifies content files against the database after import
- **Server Mode Toggle** - Shows only relevant operations per server role

---

## Architecture

### Two-Server Model

```
┌─────────────────────┐                    ┌─────────────────────┐
│   ONLINE WSUS       │                    │   AIR-GAP WSUS      │
│   (Internet)        │                    │   (Disconnected)    │
├─────────────────────┤                    ├─────────────────────┤
│ - Syncs with MSFT   │    USB Drive       │ - Receives Robocopy │
│ - Approves updates  │ =================> │ - Serves clients    │
│ - Robocopy to USB   │   (Sneakernet)     │ - Restores DB       │
└─────────────────────┘                    └─────────────────────┘
```

### Components

| Server | Network | Mode | Primary Functions |
|--------|---------|------|-------------------|
| Online WSUS | Internet-connected | Online | Sync, approve, Robocopy to USB |
| Air-Gap WSUS | Disconnected | Air-Gap | Robocopy from USB, restore DB, serve clients |

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

## Copy to USB (Online Server)

### Online Sync + Robocopy

Sync updates from Microsoft and copy them to USB media for transport.

**When to use:**
- First-time setup of air-gap server
- Monthly update cycle
- After major configuration changes on the online server

**Steps:**

1. On the **Online** server, run **Online Sync** (Full Sync profile recommended)
   - Syncs with Microsoft Update, declines/approves updates, runs cleanup, and creates a database backup
2. Click **Robocopy** in the Maintenance section
3. In the Robocopy dialog:
   - Set **Source** to `C:\WSUS\WsusContent`
   - Set **Destination** to your USB drive folder (e.g., `E:\WSUS_Transfer`)
4. Click **Start Transfer**
5. Also copy the database backup (`.bak` file from `C:\WSUS\`) to the USB drive

**Time estimate:** 30 minutes to several hours (depending on content size)

---

## Physical Transfer

> **Note:** Depending on your program, transferring files into SAP or collateral spaces may require a Data Transfer Request (DTR). Check with your security team before physically moving media across network boundaries.

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
3. **Enable write-protection** after transfer if possible
4. **Log transfers** per security policy
5. **Wipe after use** if required by policy

### Transfer Verification

Before disconnecting from online server:
```powershell
# Verify Robocopy transfer integrity
Get-FileHash -Path "E:\WSUS_Transfer\*.bak" -Algorithm SHA256
```

Record the hash for verification on the air-gap side.

---

## Copy from USB (Air-Gap Server)

### Pre-Transfer Checklist

- [ ] All WSUS services running on air-gap server
- [ ] Sufficient disk space (check Dashboard)
- [ ] USB drive scanned per security policy

### Robocopy Steps

1. Connect USB drive to the **Air-Gap** server
2. Launch WSUS Manager
3. Click **Robocopy** in the Maintenance section
4. In the Robocopy dialog:
   - Set **Source** to the USB drive folder containing update content (e.g., `E:\WSUS_Transfer`)
   - Set **Destination** to `C:\WSUS`
5. Click **Start Transfer**
6. Wait for transfer to complete

> **Note:** Robocopy is non-destructive and will not delete existing content on the destination.

### Post-Transfer Steps

1. Copy the `.bak` database backup from the USB drive to `C:\WSUS\`
2. Click **Restore DB** (in the SETUP section) and confirm the warning
3. Wait for database restore to complete
4. Click **Reset Content** (in the DIAGNOSTICS section)
   - Runs `wsusutil reset` to re-verify all content files against the restored database
   - Fixes "content is still downloading" status after a database import
5. Wait for Reset Content to complete (may take several minutes depending on content size)
6. Clients will check in and receive updates at their next update cycle

### Verification

After import:
1. Click **Run Diagnostics** to verify all services and configuration
2. Open WSUS console
3. Verify new updates appear
4. Check update approvals

---

## Scheduling

### Recommended Schedule

| Task | Frequency | Server | Day |
|------|-----------|--------|-----|
| Online Sync (Quick) | Weekly | Online | Sunday |
| Online Sync (Full) | Monthly | Online | 1st of month |
| Robocopy to USB | Monthly | Online | After Full Sync |
| Robocopy from USB + Restore DB | Monthly | Air-Gap | 3rd–5th of month |
| Client update window | Monthly | Both | 2nd week |

### Automation

On the **Online** server, schedule Online Sync:

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

### Copy to USB Best Practices

- Run **Online Sync** (Full Sync) before every Robocopy transfer
- Verify the transfer completed before disconnecting the drive

### Copy from USB Best Practices

- Always scan USB per security policy
- Check disk space before starting the transfer
- Run **Diagnostics** after import to verify server health
- Run **Reset Content** after Restore DB to fix content verification status

### Disaster Recovery

Maintain backups on both servers:
- Regular database backups
- Configuration exports
- Documented procedures

### Troubleshooting Common Issues

| Issue | Solution |
|-------|----------|
| Robocopy fails | Check disk space, verify source folder is accessible |
| Updates missing after import | Verify Robocopy completed; check source had all content |
| "Content still downloading" | Run **Reset Content** (DIAGNOSTICS section) after Restore DB |
| Database mismatch | Run Full Sync on online server, redo Robocopy and Restore DB |
| Slow transfer | Use faster USB drive, USB 3.0 port |

---

## Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         ONLINE SERVER                             │
├──────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Online Sync (Full Sync)                                    │ │
│  │  Sync → Approve → Cleanup → Backup DB                      │ │
│  └──────────────────────────────┬──────────────────────────────┘ │
│                                 │                                 │
│                    ┌────────────▼───────────┐                    │
│                    │  Robocopy              │                    │
│                    │  C:\WSUS\WsusContent   │                    │
│                    │  → USB Drive           │                    │
│                    └────────────┬───────────┘                    │
└─────────────────────────────────┼────────────────────────────────┘
                                  │
                       ┌──────────▼──────────┐
                       │     USB Drive       │
                       │   (Sneakernet)      │
                       └──────────┬──────────┘
                                  │
┌─────────────────────────────────┼────────────────────────────────┐
│                         AIR-GAP SERVER                            │
├─────────────────────────────────┼────────────────────────────────┤
│                    ┌────────────▼───────────┐                    │
│                    │  Robocopy              │                    │
│                    │  USB Drive → C:\WSUS   │                    │
│                    └────────────┬───────────┘                    │
│                                 │                                 │
│                    ┌────────────▼───────────┐                    │
│                    │  Restore DB            │                    │
│                    │  + Reset Content       │                    │
│                    └────────────┬───────────┘                    │
│                                 │                                 │
│  ┌──────────────────────────────▼──────────────────────────────┐ │
│  │  Clients Check In (Updates Ready)                           │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

- [[User Guide]] - Complete GUI reference
- [[Troubleshooting]] - Fix common issues
- [[Installation Guide]] - Server setup details
