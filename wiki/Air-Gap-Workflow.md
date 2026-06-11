# Air-Gap Workflow

This guide provides detailed instructions for managing Windows updates on air-gapped (disconnected) networks using WSUS Manager.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Initial Setup](#initial-setup)
4. [Build the Air-Gap WSUS Server from the Existing Share](#build-the-air-gap-wsus-server-from-the-existing-share)
5. [Physical Transfer](#physical-transfer)
6. [Reference: Source Server Export](#reference-source-server-export)
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

For most operators, WSUS Manager is used to:
- **Install WSUS** on the disconnected server
- **Robocopy / Transfer Import** update files into `C:\WSUS`
- **Restore DB** from a `SUSDB_YYYYMMDD.bak` file
- **Diagnostics** to verify:
  - `Authenticated Users` read access on `C:\WSUS`
  - IIS `/Content` = `C:\WSUS\WsusContent`
  - use **Reset Content** only when content registration is stuck

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

### Source Server Setup (Reference Only)

If you maintain the source/online WSUS server yourself:
1. Install WSUS Manager
2. Run **Install WSUS**
3. Configure products and classifications
4. Run initial sync with Microsoft
5. Publish the latest `SUSDB_YYYYMMDD.bak` plus `WsusContent\` to the approved share drive

### Air-Gap Server Setup

This is the primary operator workflow:
1. Copy WSUS Manager to a folder under `C:\WSUS\` on the air-gapped server
2. Stage SQL installers in `C:\WSUS\SQLDB\`
3. Run **Install WSUS**
4. Keep the WSUS root/content path at `C:\WSUS`
5. Confirm IIS `WSUS Administration/Content` points to `C:\WSUS\WsusContent`
6. Set mode to **Air-Gap**

### Matching Configuration

The air-gapped server should match the source server for:
- Product selections
- Classification selections
- Computer groups
- Approval rules
---

## Build the Air-Gap WSUS Server from the Existing Share

Assumption: the online/source WSUS server is already maintained and the latest database backup plus `WsusContent` are available on an approved share drive or transfer media.

### Air-Gap Import Steps

1. Build the air-gapped WSUS server first
2. Copy these items from the share drive or media:
   - latest `SUSDB_YYYYMMDD.bak`
   - latest `WsusContent\`
3. Launch WSUS Manager on the air-gapped server
4. Click **Robocopy** in the Maintenance section
5. Set:
   - **Source** = share-drive copy or USB folder
   - **Destination** = `C:\WSUS`
6. Click **Start Transfer**
7. Confirm update files are present in `C:\WSUS\WsusContent`
8. Copy or confirm the `.bak` file is present in `C:\WSUS\`
9. Click **Restore DB**
10. Run **Diagnostics**

### Use Reset Content only when needed

- The install workflow already performs the normal post-install content step.
- Use **Reset Content** only if WSUS still shows files as downloading after import/restore.
- After running **Reset Content**, wait about 5-10 minutes for WSUS to register files.
- If the dashboard exposes file status, click **Refresh** and watch items move from **Downloading** to **Downloaded / Ready to Install**.

### Diagnostics must confirm

- `Authenticated Users` has read access on `C:\WSUS`
- IIS `/Content` points to `C:\WSUS\WsusContent`
- no content/download errors remain
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

## Reference: Source Server Export

Only the source-server maintainer needs this section.

### Export Checklist

1. On the **Online** server, run **Online Sync** (Full Sync profile recommended)
2. Publish or copy these items to the approved share drive or transfer media:
   - latest `SUSDB_YYYYMMDD.bak`
   - full `WsusContent\` tree

### Recommended export layout

```text
<share or media root>\
├── SUSDB_YYYYMMDD.bak
└── WsusContent\
```

### Verification

Before handing off to the air-gapped operator:
1. Confirm the `.bak` file exists
2. Confirm the `WsusContent\` tree exists
3. Confirm the air-gapped operator should import into `C:\WSUS`, not into `C:\WSUS\WsusContent` directly
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

- Always scan USB per security policy
- Check disk space before starting the transfer
- Run **Diagnostics** after import to verify server health
- Use **Reset Content** only when WSUS still shows files as downloading after import/restore
- Confirm `Authenticated Users` has read access on `C:\WSUS`
- Confirm IIS `/Content` points to `C:\WSUS\WsusContent`

### Disaster Recovery

Maintain backups on both servers:
- Regular database backups
- Configuration exports
- Documented procedures

### Troubleshooting Common Issues

| Issue | Solution |
|-------|----------|
| Robocopy fails | Check disk space, verify source folder is accessible |
| Updates missing after import | Verify `WsusContent` was copied into `C:\WSUS\WsusContent` |
| "Content still downloading" | Run **Reset Content**, wait 5-10 minutes, then run **Diagnostics** |
| Clients can scan but never download | Confirm `Authenticated Users` read access on `C:\WSUS` and IIS `/Content` = `C:\WSUS\WsusContent` |
| Database mismatch | Restore the matching `.bak`; use **Reset Content** only if content state is still stuck afterward |
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
