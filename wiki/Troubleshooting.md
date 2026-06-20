# Troubleshooting

Start with **Run Diagnostics**. It checks services, SQL, firewall, IIS, permissions, and content state, then applies safe auto-fixes when available.

## Fast checks

| Symptom | First action |
|---|---|
| WSUS missing | Run **Install WSUS**. |
| SQL permission/preflight failure | Run **Fix SQL Login** from Diagnostics. |
| Content stuck downloading | Confirm content exists, then run **Reset Content** and wait 5-10 minutes. |
| Clients scan but do not download | Run **Diagnostics**; verify IIS `/Content` and `C:\WSUS` read ACLs. |
| Robocopy output missing | Turn on Live Terminal and run Robocopy again. |
| App missing after minimize | Check taskbar/tray; v4.1.0 keeps a recovery path. |

## Folder structure errors

Operations fail if the EXE is separated from its companion folders.

Correct package layout:

```text
GA-WsusManager.exe
Scripts\
Modules\
icons\
DomainController\     optional, needed for GPO deployment
metadata.json
README.md
QUICK-START.txt
```

Fix:

1. Download the full release package: `GA-WsusManager-v4.1.0.zip`.
2. Extract all contents together.
3. Run `GA-WsusManager.exe` from the extracted folder.

## SQL login or sysadmin failure

Symptoms:

- Online Sync preflight says the current user is not SQL sysadmin.
- Database maintenance cannot connect to SUSDB.
- Fix SQL Login was needed after install.

Fix:

1. Open **Diagnostics**.
2. Click **Fix SQL Login**.
3. Re-run **Diagnostics**.
4. Re-run the failed operation.

The installer and Fix SQL Login can use SQL client fallback paths when `Invoke-Sqlcmd`/`sqlcmd.exe` are unavailable.

## Content permission failures

Symptoms:

- Diagnostics reports missing `BUILTIN\IIS_IUSRS` or `NT AUTHORITY\Authenticated Users`.
- Clients can scan but cannot download updates.

Fix:

1. Run **Diagnostics** and allow auto-fix.
2. Confirm `C:\WSUS` grants list/read/execute to:
   - `BUILTIN\IIS_IUSRS`
   - `NT AUTHORITY\Authenticated Users`
3. Confirm IIS `WSUS Administration/Content` points to `C:\WSUS\WsusContent`.

## Air-gap restore problems

| Problem | Fix |
|---|---|
| No `manifest.json` | Current workflow does not require one. Use the SUSDB `.bak` and matching `WsusContent\`. |
| Restore cannot find backup | Select the `.bak` file from the approved export folder. |
| Updates still downloading | Copy content into `C:\WSUS\`, run **Reset Content**, wait 5-10 minutes, then run **Diagnostics**. |
| Database/content mismatch | Use a `.bak` and `WsusContent\` from the same export snapshot. |

## GPO deployment problems

The app has no Create GPO menu item. Use the packaged Domain Controller script.

Fix:

1. Copy the whole `DomainController\` folder to the DC.
2. Run PowerShell as Administrator from inside that folder.
3. Run `.[0m\Set-WsusGroupPolicy.ps1`.
4. Allow the WSUS server computer object move when prompted.

If OUs are missing, use the v4.1.0 script. It creates `Member Servers`, `WSUS Server`, and `Workstations` as needed.

## Health Score below expected

Health Score uses only:

- Services: 40
- SUSDB size: 30
- Disk free space: 30

To reach 100:

1. SQL Server, WSUS Service, and IIS must be running.
2. SUSDB must be below 7 GB.
3. Content drive free space must be above 50 GB.

Scheduled task state and last sync do not reduce Health Score.

## Online Sync appears idle

Some sync/cleanup phases can be quiet for several minutes. The GUI refreshes status periodically. Use Live Terminal when you need real-time process output.

## Logs

| Log | Location |
|---|---|
| Daily operation log | `C:\WSUS\Logs\WsusOperations_YYYY-MM-DD.log` |
| GUI settings | `%APPDATA%\WsusManager\settings.json` |
| Operation history | `%APPDATA%\WsusManager\history.json` |

## Related pages

- [[Installation Guide]]
- [[Air-Gap Workflow]]
- [[User Guide]]
