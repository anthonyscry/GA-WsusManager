# WSUS Manager v4.1.0 — Quick Start Guide

**Author:** Tony Tran, ISSO, GA-ASI
**Last updated:** 2026-06-07

This is a quick-start guide for new operators. For the full reference see [WSUS-Manager-SOP.md](WSUS-Manager-SOP.md) and the [README](../README.md).

---

## What You Need

| Item | Details |
|------|---------|
| Server | Windows Server 2019 or 2022, 16 GB RAM, 150 GB disk |
| Installers | `SQLEXPRADV_x64_ENU.exe` in `C:\WSUS\SQLDB\` (SSMS optional) |
| Package | `WsusManager-v4.1.0.zip` extracted to a folder under `C:\WSUS\` (e.g. `C:\WSUS\WsusManager\`) |
| Privileges | Local Administrator |
| Office C2R (optional) | Office Deployment Tool `setup.exe` (see [Office C2R Updates](../wiki/Office-C2R-Updates.md)) |

---

## 1. Install WSUS

1. Extract `WsusManager-v4.1.0.zip` to a folder under `C:\WSUS\`, e.g. `C:\WSUS\WsusManager\`.
2. Place SQL installers in `C:\WSUS\SQLDB\`.
3. Right-click `GA-WsusManager.exe` → **Run as Administrator**.
4. Click **Install WSUS** and follow the prompts.
5. Wait 15-30 minutes for SQL Express + WSUS installation.
6. The dashboard turns green when services are running.

The installer auto-detects WID and migrates to SQL Express if needed. No `SqlServer` PowerShell module required — all database operations fall back to `sqlcmd.exe`.

---

## 2. Build an Air-Gapped WSUS Server from the Existing Share

**Assumption:** the online/source WSUS server is already maintained and publishes the latest database backup plus `WsusContent` to your approved share drive.

**On the air-gapped server:**

1. Build the server using the install steps above.
2. Copy the latest `SUSDB_YYYYMMDD.bak` and `WsusContent\` from the share drive or transfer media to the new server.
3. Click **Robocopy**. Set source to the share-drive copy or USB folder and destination to `C:\WSUS\`, then click **Start Transfer**.
4. Click **Restore DB** to import the SUSDB backup from `C:\WSUS\`.
5. Run **Diagnostics** to confirm:
   - `Authenticated Users` has read access on `C:\WSUS`
   - IIS `/Content` points to `C:\WSUS\WsusContent`
   - Update files are present in `C:\WSUS\WsusContent`
6. Only use **Reset Content** if WSUS still shows files as downloading after import or restore.
7. After running **Reset Content**, wait 5-10 minutes for file registration to settle before re-checking status.

---

## 3. Reference: Source Server Sync

Only the source/online WSUS maintainer needs this section.

1. Run **Online Sync** with export path set to the approved share drive or staging folder.
2. Verify the share contains:
   - `SUSDB_YYYYMMDD.bak`
   - `WsusContent\`

---

## 4. Deploy GPOs (Air-Gap Only)

> **WARNING:** These GPOs block all direct Microsoft Update traffic. Only deploy on air-gapped networks.

**On the Domain Controller:**

1. Copy the `DomainController/` folder from the WSUS Manager package to the DC.
2. Open an elevated PowerShell prompt.
3. Run:
   ```powershell
   .\Set-WsusGroupPolicy.ps1
   ```
4. Enter the WSUS server hostname when prompted (e.g. `WSUS01`).
5. The script imports 3 GPOs, reuses an existing `Member Servers` (or `Member_Servers`) OU if present, creates the `WSUS Server` child OU when possible, and pushes policy via schtasks (no WinRM needed).
6. Move the WSUS server computer object to the `Member Servers\WSUS Server` OU.

**Verify on a client:**

```powershell
gpresult /r | findstr WSUS
```

---

## 5. Schedule Recurring Sync

1. Click **Schedule Task** in the GUI.
2. Select a maintenance profile:
   - **Full** (recommended monthly) — full cycle: sync, auto-decline, auto-approve, deep cleanup, optional export
   - **Quick** (weekly) — sync and approve only, skips cleanup
   - **Sync Only** — sync with Microsoft only, no approvals or cleanup
3. Set the schedule (daily / weekly / monthly) and time (default: Tuesday 23:00).
4. Enter credentials and click **Create**.

> The scheduled task is created via the WMI-compatible XML registration path so it works in PowerShell 5.1 without the `-Monthly` switch on `New-ScheduledTaskTrigger`.

---

## 6. Office C2R Updates (Optional)

If your environment also has Microsoft 365 Apps or Office LTSC 2024 on the air-gap network, use this workflow to download the Click-to-Run update content:

1. On an internet-connected staging machine, install the [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117) (place `setup.exe` in `C:\ODT\`).
2. Run WSUS Manager, choose option **10. Download Office LTSC / M365 Apps Updates to Share**.
3. Enter the network share (e.g. `\\FILESERVER\Software\OfficeC2R`).
4. Pick the product (Office LTSC 2024, M365 Apps, Visio LTSC 2024, or Project LTSC 2024), channel, and language.
5. Click through. The download runs `setup.exe /download` and reports file count, size, and per-channel summary.

For the full guide including GPO client configuration see [wiki/Office-C2R-Updates.md](../wiki/Office-C2R-Updates.md).

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
| Dashboard shows "Not Installed" | Click **Install WSUS** |
| Sync stuck at 0% | Check DNS configuration |
| "Content is still downloading" after import | Click **Reset Content**, wait 5-10 minutes, then run **Diagnostics** to verify `C:\WSUS` ACLs and IIS `/Content` |
| Database near 10 GB | Run **Deep Cleanup** |
| `?` boxes in GUI buttons | File lacks UTF-8 BOM, or non-BMP character was used. See [Configuration Guide](../wiki/Configuration-Guide.md) |

For detailed troubleshooting, see the full [README](../README.md), [SOP](WSUS-Manager-SOP.md), or [wiki/Troubleshooting.md](../wiki/Troubleshooting.md).

---

*WSUS Manager v4.1.0 — GA-ASI Internal Use*
