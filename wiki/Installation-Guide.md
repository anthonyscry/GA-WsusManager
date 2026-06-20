# Installation Guide

This page covers installing WSUS Manager and building a WSUS + SQL Express server.

## Requirements

| Item | Requirement |
|---|---|
| OS | Windows Server 2019+ |
| PowerShell | Windows PowerShell 5.1 |
| Privileges | Local Administrator |
| Disk | 200 GB+ recommended for the WSUS server/content drive |
| SQL installer | `SQLEXPRADV_x64_ENU.exe` in `C:\WSUS\SQLDB\` |
| Optional installer | `SSMS-Setup-ENU.exe` in `C:\WSUS\SQLDB\` |

## Install WSUS Manager

1. Download `GA-WsusManager-v4.1.0.zip` from [GitHub Releases](https://github.com/anthonyscry/GA-WsusManager/releases).
2. Extract the whole package under `C:\WSUS\`, for example `C:\WSUS\WsusManager\`.
3. Confirm the package stays together:

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

Do not copy `GA-WsusManager.exe` by itself. Operations need the adjacent `Scripts\`, `Modules\`, and `icons\` folders.

## Prepare SQL installer folder

```powershell
New-Item -ItemType Directory -Path 'C:\WSUS\SQLDB' -Force
```

Copy the SQL Express installer into that folder:

```text
C:\WSUS\SQLDB\SQLEXPRADV_x64_ENU.exe
```

SSMS is optional.

## Build a new WSUS server

1. Right-click `GA-WsusManager.exe` and select **Run as Administrator**.
2. If the dashboard says WSUS is missing, click **Install WSUS**.
3. Select the SQL installer folder (`C:\WSUS\SQLDB` if you used the default).
4. Enter and confirm the SQL `sa` password.
5. Keep the WSUS root/content path at `C:\WSUS` unless your deployment standard says otherwise.
6. Wait for SQL Express + WSUS installation to finish.
7. Run **Diagnostics**.

The installer handles WID detection/removal, SQL Express setup, WSUS role install, directory creation, permissions, firewall rules, and SQL sysadmin grants for the operator account.

## Air-gapped server setup

After WSUS is installed, follow [[Air-Gap Workflow]] to restore the approved transfer folder:

1. Transfer the approved folder by approved USB/removable media.
2. Click **Restore DB** and select the SUSDB `.bak`.
3. Use **Robocopy** if content still needs to be copied into `C:\WSUS\`.
4. Run **Diagnostics**.

## GPO setup

On the Domain Controller:

1. Copy the whole `DomainController\` folder from the extracted package to the DC.
2. Open an elevated PowerShell prompt inside that copied folder.
3. Run:

```powershell
.\Set-WsusGroupPolicy.ps1
```

The script imports four packaged GPOs and creates missing OUs when needed.

## Verify installation

Run **Diagnostics** and confirm:

- SQL Server Express service is running.
- WSUS Service is running.
- IIS/W3SVC is running.
- SUSDB connection works.
- `C:\WSUS` permissions include IIS and client read access.
- Health Score is Green when services, database size, and disk are healthy.

## Related pages

- [[User Guide]]
- [[Air-Gap Workflow]]
- [[Troubleshooting]]
