# WSUS Manager v4.0.4 - Quick Start Guide

**Author:** Tony Tran, ISSO, GA-ASI

---

## What You Need

| Item | Details |
|------|---------|
| Server | Windows Server 2019 or 2022, 16 GB RAM, 150 GB disk |
| Installers | `SQLEXPRADV_x64_ENU.exe` in `C:\WSUS\SQLDB\` (SSMS optional) |
| Package | `WsusManager-v4.0.4.zip` extracted to `C:\WSUS\` |
| Privileges | Local Administrator |

---

## 1. Install WSUS

1. Extract `WsusManager-v4.0.4.zip` to `C:\WSUS\`
2. Place SQL installers in `C:\WSUS\SQLDB\`
3. Right-click `WsusManager.exe` -- Run as Administrator
4. Click **Install WSUS** and follow prompts
5. Wait 15-30 minutes for SQL Express + WSUS installation
6. Dashboard turns green when services are running

The installer auto-detects WID and migrates to SQL Express if needed. No SqlServer PowerShell module required -- all database operations use sqlcmd.exe fallback.

---

## 2. First Sync (Online Server)

1. Click **Online Sync**
2. Select **Full** profile
3. Optionally set an export path (USB drive or network share)
4. Click **OK**

The sync runs a DNS preflight check, then:
- Sets default products (Windows 11, Server 2019, Edge, Defender, Office 2016, SQL Server 2022)
- Syncs with Microsoft Update (first sync: 2-4 hours, timeout: 180 min)
- Auto-declines expired, superseded, old (>6 months), ARM64, legacy, preview, and non-stable Edge/Office updates
- Auto-approves Critical, Security, Definition, Updates, and Update Rollups
- Cleans up the database and exports if a path was set

---

## 3. Air-Gap Transfer

> **Note:** Depending on your program, transferring files into SAP or collateral spaces may require a Data Transfer Request (DTR). Check with your security team before physically moving media across network boundaries.

**On the online server:**

1. Run Online Sync with export path set to a staging folder
2. Click **Robocopy**, set source to your WSUS content folder (e.g. `C:\WSUS\WsusContent`) and destination to the USB drive, then click **Start Transfer**
3. Eject USB

**On the air-gapped server:**

4. Plug in USB drive
5. Click **Robocopy**, set source to the USB drive folder and destination to `C:\WSUS\`, then click **Start Transfer**
6. Click **Restore DB** to import the SUSDB backup
7. Click **Reset Content** (in the DIAGNOSTICS section) to re-verify content files
8. Run **Diagnostics** to confirm everything is healthy

---

## 4. Deploy GPOs (Air-Gap Only)

> **WARNING:** These GPOs block all direct Microsoft Update traffic. Only deploy on air-gapped networks.

**On the Domain Controller:**

1. Copy the `DomainController/` folder from the WSUS Manager package to the DC
2. Open an elevated PowerShell prompt
3. Run:

```powershell
.\Set-WsusGroupPolicy.ps1
```

4. Enter the WSUS server hostname when prompted (e.g., `WSUS01`)
5. The script imports 3 GPOs, creates OUs, and pushes policy via schtasks (no WinRM needed)
6. Move the WSUS server computer object to the `Member Servers\WSUS Server` OU

**Verify on a client:**

```powershell
gpresult /r | findstr WSUS
```

---

## 5. Schedule Recurring Sync

1. Click **Schedule Task** in the GUI
2. Select a maintenance profile:
   - **Full** (recommended monthly) -- full cycle: sync, auto-decline, auto-approve, deep cleanup, optional export
   - **Quick** (weekly) -- sync and approve only, skips cleanup
   - **Sync Only** -- sync with Microsoft only, no approvals or cleanup
3. Set day and time (default: Tuesday 23:00)
4. Enter credentials and click **Create**

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+D | Diagnostics |
| Ctrl+S | Online Sync |
| Ctrl+H | History |
| Ctrl+R / F5 | Refresh Dashboard |

---

## Common Issues

| Problem | Fix |
|---------|-----|
| Dashboard shows "Not Installed" | Click Install WSUS |
| Sync stuck at 0% | Check DNS configuration |
| "Content is still downloading" after import | Click **Reset Content** in the DIAGNOSTICS nav section |
| Buttons greyed out | Wait for current operation to finish |
| Database near 10 GB | Run Deep Cleanup |

For detailed troubleshooting, see the full [README](../README.md) or [SOP](WSUS-Manager-SOP.md).

---

*WSUS Manager v4.0.4 -- GA-ASI Internal Use*
