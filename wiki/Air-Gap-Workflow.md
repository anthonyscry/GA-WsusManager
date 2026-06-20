# Air-Gap Workflow

Use this page when an approved WSUS export folder has already been transferred into the disconnected network by approved removable media.

No `manifest.json` is required by the current restore workflow. The required inputs are:

```text
Approved export folder
+-- SUSDB_YYYYMMDD.bak      # SUSDB backup
+-- WsusContent\            # update content files
```

Keep the `.bak` and `WsusContent\` from the same export snapshot.

## Restore workflow

1. Install WSUS Manager on the air-gapped WSUS server.
2. If WSUS is missing, launch `GA-WsusManager.exe` as Administrator and click **Install WSUS** first.
3. Copy the complete approved export folder from USB/removable media to the server, or attach the media directly.
4. Click **Restore DB** and select the SUSDB `.bak` from the approved export folder.
5. Click **Robocopy** only if `WsusContent\` still needs to be copied into `C:\WSUS\`.
6. Click **Reset Content** only if WSUS still reports content as downloading after restore/Robocopy.
7. Run **Diagnostics** and review any auto-fix output.

## Robocopy destination

For the normal air-gap restore path:

| Field | Value |
|---|---|
| Source | approved export folder or its `WsusContent\` folder |
| Destination | `C:\WSUS\` |

Robocopy is non-destructive. It copies content and does not delete files from the source.

## Diagnostics must confirm

- `BUILTIN\IIS_IUSRS` has list/read/execute access on `C:\WSUS`.
- `NT AUTHORITY\Authenticated Users` has list/read/execute access on `C:\WSUS`.
- IIS `WSUS Administration/Content` points to `C:\WSUS\WsusContent`.
- SQL Server, WSUS Service, and IIS are running.
- No content/download errors remain.

## Reset Content guidance

Use **Reset Content** only when WSUS still shows files as downloading even though content is present.

After Reset Content:

1. Wait 5-10 minutes for WSUS to register file state.
2. Run **Diagnostics**.
3. Refresh the dashboard and confirm status improves.

## GPO deployment for air-gapped domains

The GUI no longer has a Create GPO button. The GPO files are already packaged.

On the Domain Controller:

1. Copy the whole `DomainController\` folder from the WSUS Manager package to the DC.
2. Keep `Set-WsusGroupPolicy.ps1` and `WSUS GPOs\` together.
3. Open an elevated PowerShell prompt inside that copied folder.
4. Run:

```powershell
.\Set-WsusGroupPolicy.ps1
```

The script imports four GPOs, creates missing OUs when needed, links policy, and can move the WSUS server computer object into `Member Servers\WSUS Server` so the inbound firewall GPO applies.

## Transfer practices

- Use approved USB/removable media only.
- Use NTFS for large content folders.
- Scan media per security policy before connecting it.
- Keep the export folder intact; do not cherry-pick files.
- Record the SUSDB backup hash if your transfer process requires it:

```powershell
Get-FileHash -Path "E:\WSUS-Export\*.bak" -Algorithm SHA256
```

## Common issues

| Issue | Fix |
|---|---|
| Restore cannot find a backup | Select the `.bak` file inside the approved export folder. |
| Updates show as downloading | Confirm content exists, then run **Reset Content** and wait 5-10 minutes. |
| Clients scan but cannot download | Run **Diagnostics** and verify IIS path + `Authenticated Users` read access. |
| Robocopy fails | Check destination space and source accessibility. |
| GPO script says OU is missing | Use the v4.1.0 script; it creates `Member Servers`, `WSUS Server`, and `Workstations` when needed. |

## Related pages

- [[Installation Guide]]
- [[User Guide]]
- [[Troubleshooting]]
