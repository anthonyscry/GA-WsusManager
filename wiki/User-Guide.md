# User Guide

Run `GA-WsusManager.exe` as Administrator. If WSUS is not installed, click **Install WSUS** first.

## Dashboard

The dashboard shows services, SUSDB size, disk space, scheduled task state, last sync, and Health Score.

Health Score uses only:

| Component | Weight |
|---|---:|
| Services | 40 |
| SUSDB size | 30 |
| Disk free space | 30 |

Last sync and scheduled task state are visible but do not reduce the score.

## Menu layout

**Setup**
- **Install WSUS** — installs SQL Express + WSUS and configures baseline paths/permissions.

**Maintenance**
- **Restore DB** — restores SUSDB from an approved `.bak`.
- **Robocopy** — copies approved export/content folders.
- **Deep Cleanup** — WSUS cleanup, SQL cleanup, index maintenance, and database shrink.

**Online Operations** *(collapsed by default)*
- **Online Sync** — syncs with Microsoft Update, applies approval/decline policy, optionally backs up/exports.
- **Schedule Task** — creates or updates recurring Online Sync.

**Diagnostics** *(collapsed by default)*
- **Run Diagnostics** — checks and auto-fixes services, SQL, firewall, IIS, permissions, and content state.
- **Reset Content** — runs `wsusutil reset` when content appears stuck as downloading.
- **Fix SQL Login** — grants the current operator SQL sysadmin access when preflight fails.

## Install WSUS

1. Click **Install WSUS**.
2. Select the folder containing `SQLEXPRADV_x64_ENU.exe`.
3. Enter and confirm the SQL `sa` password.
4. Keep content path at `C:\WSUS` unless your deployment standard says otherwise.
5. Wait for install to finish, then run **Diagnostics**.

## Air-gap restore

Use this when an approved export folder arrives by USB/removable media.

1. Click **Restore DB** and select the SUSDB `.bak`.
2. Click **Robocopy** if `WsusContent\` still needs to be copied into `C:\WSUS\`.
3. Click **Reset Content** only if WSUS still reports files as downloading.
4. Run **Diagnostics**.

No `manifest.json` is required. Keep the `.bak` and `WsusContent\` from the same export snapshot.

## GPO deployment

The GUI does not have a Create GPO button. Use the packaged script.

1. Copy the whole `DomainController\` folder to the Domain Controller.
2. Open an elevated PowerShell prompt inside that folder.
3. Run:

```powershell
.\Set-WsusGroupPolicy.ps1
```

The script imports:

| GPO | Target |
|---|---|
| WSUS Update Policy - Servers | Domain Controllers, Member Servers |
| WSUS Update Policy - Workstations | Workstations |
| WSUS Inbound Allow | `Member Servers\WSUS Server` |
| WSUS Outbound Allow | Workstations, Member Servers, Domain Controllers |

## Online Sync

Run Online Sync only on a server intentionally allowed to reach Microsoft Update.

| Profile | Operations |
|---|---|
| Full | Sync, Cleanup, Ultimate Cleanup, Backup, Export |
| Quick | Sync, Cleanup, Backup |
| Sync Only | Sync and approval policy only |

Online Sync preserves existing product subscriptions and adds selected products before sync.

## Robocopy

Robocopy is non-destructive.

| Scenario | Source | Destination |
|---|---|---|
| Air-gap restore | approved export folder or `WsusContent\` | `C:\WSUS\` |
| Export staging | WSUS content/export source | approved staging path |

## Diagnostics

Run Diagnostics after install, restore, permission changes, SQL login changes, or GPO deployment.

Diagnostics checks:

- SQL Server, WSUS Service, IIS/W3SVC.
- SUSDB connectivity and SQL login state.
- WSUS and SQL firewall rules.
- IIS content path.
- `C:\WSUS` ACLs for WSUS, IIS, and client download access.
- WsusPool/application health when IIS tooling is available.

## Settings and logs

| Item | Location |
|---|---|
| Settings | `%APPDATA%\WsusManager\settings.json` |
| History | `%APPDATA%\WsusManager\history.json` |
| Trends | `%APPDATA%\WsusManager\trends.json` |
| Logs | `C:\WSUS\Logs\WsusOperations_YYYY-MM-DD.log` |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Ctrl+D | Diagnostics |
| Ctrl+S | Online Sync |
| Ctrl+H | History |
| Ctrl+R / F5 | Refresh Dashboard |

## Related pages

- [[Air-Gap Workflow]]
- [[Troubleshooting]]
- [[Configuration Guide]]
