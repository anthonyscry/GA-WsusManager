# WSUS Manager v4.1.0 — Quick Start Guide

**Author:** Tony Tran, ISSO, GA-ASI
**Last updated:** 2026-06-20

This is a quick-start guide for new operators. For the full reference see [WSUS-Manager-SOP.md](WSUS-Manager-SOP.md) and the [README](../README.md).

---

## What You Need

| Item | Details |
|------|---------|
| Server | Windows Server 2019 or 2022, 16 GB RAM, 200 GB disk recommended |
| Installers | `SQLEXPRADV_x64_ENU.exe` in `C:\WSUS\SQLDB\` (SSMS optional) |
| Package | `GA-WsusManager-v4.1.0.zip` extracted to a folder under `C:\WSUS\` (e.g. `C:\WSUS\WsusManager\`) |
| Privileges | Local Administrator |

---

## 1. Install WSUS

1. Extract `GA-WsusManager-v4.1.0.zip` to a folder under `C:\WSUS\`, e.g. `C:\WSUS\WsusManager\`.
2. Place SQL installers in `C:\WSUS\SQLDB\`.
3. Right-click `GA-WsusManager.exe` → **Run as Administrator**.
4. If the dashboard shows WSUS is missing, click **Install WSUS** and follow the prompts.
5. Wait 15-30 minutes for SQL Express + WSUS installation.
6. The dashboard turns green when services are running.

The installer auto-detects WID and migrates to SQL Express if needed. Database operations use `Invoke-Sqlcmd`, `sqlcmd.exe`, or .NET SQL client fallback depending on what is available.

---

## 2. Restore an Air-Gapped WSUS Server from Approved Media

Use this when an approved export folder has been transferred into the air-gapped network by USB/removable media.

1. Build the server using the install steps above.
2. Copy the complete export folder from the approved USB drive to the server or attach the drive directly.
3. Click **Restore DB** and select the SUSDB `.bak` file from the export folder.
4. Click **Robocopy** if the exported `WsusContent\` folder still needs to be copied into `C:\WSUS\`.
5. Run **Diagnostics** to confirm:
   - `BUILTIN\IIS_IUSRS` has list/read/execute access on `C:\WSUS`
   - `NT AUTHORITY\Authenticated Users` has list/read/execute access on `C:\WSUS`
   - IIS `/Content` points to `C:\WSUS\WsusContent`
   - Update files are present in `C:\WSUS\WsusContent`
6. Click **Reset Content** if WSUS still shows files as downloading after restore or Robocopy.
7. After running **Reset Content**, wait 5-10 minutes for file registration to settle before re-checking status.

---

## 3. Deploy GPOs (Air-Gap Only)

> **WARNING:** These GPOs block all direct Microsoft Update traffic. Only deploy on air-gapped networks.

**On the Domain Controller:**

1. Copy the whole `DomainController/` folder from the WSUS Manager package to the DC. Keep `Set-WsusGroupPolicy.ps1` and `WSUS GPOs\` together.
2. Open an elevated PowerShell prompt.
3. From inside the copied `DomainController/` folder, run:
   ```powershell
   .\Set-WsusGroupPolicy.ps1
   ```
4. Enter the WSUS server hostname when prompted (e.g. `WSUS01`).
5. The script imports 4 GPOs, reuses an existing `Member Servers` or `Member_Servers` OU if present, creates missing `Member Servers`, `WSUS Server`, and `Workstations` OUs, and pushes policy via schtasks (no WinRM required).
6. When prompted, allow the script to move the WSUS server computer object to the `Member Servers\WSUS Server` OU so the inbound firewall GPO applies.

**Verify on a client:**

```powershell
gpresult /r | findstr WSUS
```

---

## 4. Schedule Recurring Sync

1. Click **Schedule Task** in the GUI.
2. Select a maintenance profile:
   - **Full** (recommended monthly) — sync, cleanup, ultimate cleanup, backup, and export
   - **Quick** (weekly) — sync, cleanup, and backup; skips heavy cleanup and export
   - **Sync Only** — sync with Microsoft and apply the approval policy
3. Set the schedule (daily / weekly / monthly) and time (default: Tuesday 23:00).
4. Enter credentials and click **Create**.

> The scheduled task is created via the WMI-compatible XML registration path so it works in PowerShell 5.1 without the `-Monthly` switch on `New-ScheduledTaskTrigger`.

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
| "Content is still downloading" after restore | Click **Reset Content**, wait 5-10 minutes, then run **Diagnostics** to verify `C:\WSUS` ACLs and IIS `/Content` |
| Database near 10 GB | Run **Deep Cleanup** |
| `?` boxes in GUI buttons | File lacks UTF-8 BOM, or non-BMP character was used. See [Configuration Guide](../wiki/Configuration-Guide.md) |

For detailed troubleshooting, see the full [README](../README.md), [SOP](WSUS-Manager-SOP.md), or [wiki/Troubleshooting.md](../wiki/Troubleshooting.md).

---

*WSUS Manager v4.1.0 — GA-ASI Internal Use*
