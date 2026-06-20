# Air-Gap Workflow

This guide provides detailed instructions for managing Windows updates on air-gapped (disconnected) networks using WSUS Manager.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Initial Setup](#initial-setup)
4. [Restore from Approved Media](#restore-from-approved-media)
5. [Physical Transfer](#physical-transfer)
6. [Scheduling](#scheduling)
7. [Best Practices](#best-practices)

---

## Overview

### What is an Air-Gap?

An air-gapped network is physically isolated from the internet and other networks. This is common in:
- Classified environments
- Critical infrastructure
- Industrial control systems
- High-security facilities

### The Challenge

WSUS cannot download updates directly on an air-gapped network. Updates arrive as an approved export folder that must be:
1. Physically transferred by approved removable media.
2. Restored into SUSDB.
3. Copied into the WSUS content directory when needed.

### WSUS Manager Solution

For most operators, WSUS Manager is used to:
- **Install WSUS** on the disconnected server
- **Restore DB** from a `SUSDB_YYYYMMDD.bak` file
- **Robocopy** update files into `C:\WSUS` when needed
- **Diagnostics** to verify:
  - `Authenticated Users` read access on `C:\WSUS`
  - IIS `/Content` = `C:\WSUS\WsusContent`
  - use **Reset Content** only when content registration is stuck

---

## Architecture

### Approved Export Folder Model

```text
Approved USB/removable media
└── WSUS export folder
    ├── SUSDB_YYYYMMDD.bak
    └── WsusContent\
            │
            ▼
Air-gap WSUS server
├── Restore DB from .bak
├── Robocopy WsusContent into C:\WSUS\ if needed
└── Run Diagnostics / Reset Content if needed
```

### Components

| Server | Network | Mode | Primary Functions |
|--------|---------|------|-------------------|
| Air-Gap WSUS | Disconnected | Air-Gap | Restore DB from approved export folder, copy content with Robocopy when needed, serve clients |

---

## Initial Setup

### Approved Export Folder

The air-gapped restore starts with the approved export folder delivered by your transfer process:
1. Transfer the full export folder by approved USB/removable media.
2. Keep the folder intact; do not cherry-pick files.
3. Confirm the folder contains a SUSDB `.bak` and `WsusContent\`.

### Air-Gap Server Setup

This is the primary operator workflow:
1. Copy WSUS Manager to a folder under `C:\WSUS\` on the air-gapped server
2. Stage SQL installers in `C:\WSUS\SQLDB\`
3. Run **Install WSUS**
4. Keep the WSUS root/content path at `C:\WSUS`
5. Confirm IIS `WSUS Administration/Content` points to `C:\WSUS\WsusContent`
6. Set mode to **Air-Gap**

### Matching Configuration

The approved export folder should match the product/classification scope expected by the air-gapped WSUS server. Keep the SUSDB backup and `WsusContent\` from the same export snapshot.
---

## Restore from Approved Media

### Air-Gap Import Steps

1. Build the air-gapped WSUS server first.
2. Copy the complete approved export folder from USB/removable media to the server, or attach the media directly.
3. Launch WSUS Manager on the air-gapped server.
4. Click **Restore DB** in the Maintenance section and select the SUSDB `.bak` file from the export folder.
5. Click **Robocopy** if `WsusContent\` still needs to be copied into `C:\WSUS\`.
6. Run **Reset Content** if WSUS still shows files as downloading.
7. Run **Diagnostics** and review any auto-fix output.

### Use Reset Content only when needed

- The install workflow already performs the normal post-install content step.
- Use **Reset Content** only if WSUS still shows files as downloading after restore or Robocopy.
- After running **Reset Content**, wait about 5-10 minutes for WSUS to register files.
- If the dashboard exposes file status, click **Refresh** and watch items move from **Downloading** to **Downloaded / Ready to Install**.

### Diagnostics must confirm

- `BUILTIN\IIS_IUSRS` has list/read/execute access on `C:\WSUS`
- `NT AUTHORITY\Authenticated Users` has list/read/execute access on `C:\WSUS`
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

Before handing media to the air-gapped operator:
```powershell
# Verify backup file integrity
Get-FileHash -Path "E:\WSUS-Export\*.bak" -Algorithm SHA256
```

Record the hash for verification on the air-gap side.

## Scheduling

Do not schedule Online Sync on the air-gapped WSUS server. Schedule Online Sync only on a connected server that is intentionally used to create approved export folders.

### Approved export layout

```text
<media root>\
├── SUSDB_YYYYMMDD.bak
└── WsusContent\
```

### Handoff verification

Before handing off to the air-gapped operator:
1. Confirm the `.bak` file exists.
2. Confirm the `WsusContent\` tree exists.
3. Confirm the air-gapped operator should restore the database first, then copy content into `C:\WSUS` with **Robocopy** if needed.
---


### Automation

Schedule **Online Sync** only on the connected server that intentionally creates approved export folders:

1. Click **Schedule Task** in the Online Operations section.
2. Choose Weekly/Monthly/Daily and set the start time.
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

### Transfer Best Practices

- Keep the approved export folder intact.
- Verify the transfer completed before disconnecting the drive.

- Always scan USB per security policy
- Check disk space before starting the transfer
- Run **Diagnostics** after restore to verify server health
- Use **Reset Content** only when WSUS still shows files as downloading after restore or Robocopy
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
| Updates missing after restore | Verify `WsusContent` was copied into `C:\WSUS\WsusContent` |
| "Content still downloading" | Run **Reset Content**, wait 5-10 minutes, then run **Diagnostics** |
| Clients can scan but never download | Confirm `Authenticated Users` read access on `C:\WSUS` and IIS `/Content` = `C:\WSUS\WsusContent` |
| Database mismatch | Restore the matching `.bak`; use **Reset Content** only if content state is still stuck afterward |
| Slow transfer | Use faster USB drive, USB 3.0 port |
---

## Workflow Diagram

```text
Approved USB/removable media
└── WSUS export folder
    ├── SUSDB_YYYYMMDD.bak
    └── WsusContent\
            │
            ▼
Air-gap WSUS server
├── Restore DB from SUSDB backup
├── Robocopy WsusContent into C:\WSUS\ if needed
├── Reset Content only if WSUS still shows files as downloading
├── Run Diagnostics and fix reported issues
└── Clients check in and download from internal WSUS
```

---

## Next Steps

- [[User Guide]] - Complete GUI reference
- [[Troubleshooting]] - Fix common issues
- [[Installation Guide]] - Server setup details
