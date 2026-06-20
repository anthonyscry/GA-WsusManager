# WSUS Manager Production Deployment Runbook

**Audience:** WSUS operators deploying GA-WsusManager to production WSUS servers.

Use this runbook for a new deployment or an application upgrade. For emergency rollback, use [ROLLBACK.md](ROLLBACK.md).

---

## 1. Deployment prerequisites

### Server and account prerequisites

| Requirement | Production expectation |
|-------------|------------------------|
| OS | Windows Server 2019 or 2022 preferred; Windows Server 2016 supported where already approved |
| PowerShell | Windows PowerShell 5.1 |
| Privileges | Local Administrator on the WSUS server |
| SQL | SQL Server Express 2022 instance `localhost\SQLEXPRESS` for standard deployments |
| SQL access | Operator account or operator group has `sysadmin` on the SQL instance for SUSDB backup/restore |
| Disk | 200 GB recommended for the WSUS server/content drive; allow more for export staging |
| Network | Static address recommended; clients must reach WSUS ports 8530 HTTP or 8531 HTTPS |
| Package layout | `GA-WsusManager.exe`, `Scripts\`, and `Modules\` must stay in the same directory |

### Required installers and media

Place these on the target server before starting an offline install:

| Item | Standard location | Notes |
|------|-------------------|-------|
| SQL Server Express Advanced installer | `C:\WSUS\SQLDB\SQLEXPRADV_x64_ENU.exe` | Required for fresh WSUS + SQL Express install |
| SSMS installer | `C:\WSUS\SQLDB\SSMS-Setup-ENU.exe` | Optional |
| WSUS Manager package | `WsusManager-vX.X.X.zip` | Release artifact from `dist\` or GitHub Releases |

### Pre-change backup checklist for upgrades

Before replacing an existing production deployment:

1. Close all running WSUS Manager windows.
2. Export or note any scheduled WSUS maintenance task configuration.
3. Copy the existing application folder, including `GA-WsusManager.exe`, `Scripts\`, and `Modules\`, to a timestamped backup folder.
4. Copy `%APPDATA%\WsusManager\settings.json`, `history.json`, and `trends.json` for each operator account that uses the GUI.
5. Create a SUSDB backup or confirm a recent known-good backup exists.
6. Record current service states for `W3SVC`, `WsusService`, and `MSSQL$SQLEXPRESS`.

Use [ROLLBACK.md](ROLLBACK.md) for exact backup and restore commands.

---

## 2. Build and package

### Preferred production source

Use the signed or approved release zip when available:

```powershell
# Example destination; use your approved software distribution location.
Expand-Archive -Path .\WsusManager-vX.X.X.zip -DestinationPath C:\WSUS\WsusManager-Staging -Force
```

Confirm the extracted package contains:

```text
GA-WsusManager.exe
Scripts\
Modules\
DomainController\        optional, needed only for GPO deployment support
docs\                    operator documentation
wiki\                    reference documentation
```

### Building from source when required

Only build from source on a controlled build workstation or staging server:

```powershell
# Produces dist\GA-WsusManager.exe and dist\WsusManager-vX.X.X.zip.
.\build.ps1
```

For a release package created after validation has already run in the approved pipeline:

```powershell
.\build.ps1 -SkipTests -NoPush
```

Do not deploy the repository working tree as the production runtime. Deploy the release zip contents so the EXE and companion folders match the tested artifact.

---

## 3. Deploy the package

### New deployment

1. Create the standard directories:

   ```powershell
   New-Item -ItemType Directory -Path C:\WSUS\SQLDB -Force
   New-Item -ItemType Directory -Path C:\WSUS\WsusManager -Force
   ```

2. Copy SQL installers to `C:\WSUS\SQLDB\`.
3. Extract `WsusManager-vX.X.X.zip` to `C:\WSUS\WsusManager\`.
4. If files came from the internet, unblock the extracted PowerShell files:

   ```powershell
   Get-ChildItem -Path C:\WSUS\WsusManager -Recurse -Include *.ps1,*.psm1 | Unblock-File
   ```

5. Right-click `C:\WSUS\WsusManager\GA-WsusManager.exe` and select **Run as administrator**.

### Upgrade deployment

1. Complete the pre-change backup checklist.
2. Extract the new package to a staging folder, not directly over production.
3. Confirm `GA-WsusManager.exe`, `Scripts\`, and `Modules\` are present in the staging folder.
4. Stop any scheduled maintenance task if it could start during the file replacement window.
5. Rename the current production folder to a timestamped backup name, for example `C:\WSUS\WsusManager.backup-YYYYMMDD-HHMM`.
6. Move the staged package into the production path, for example `C:\WSUS\WsusManager\`.
7. Launch the new EXE as Administrator and complete the validation checklist below.
8. Re-enable scheduled maintenance only after validation passes.

---

## 4. First run

### Fresh server

1. Launch `GA-WsusManager.exe` as Administrator.
2. Confirm the dashboard shows WSUS is not installed; this is expected on a fresh host.
3. Click **Install WSUS**.
4. Keep the WSUS root/content path at `C:\WSUS` unless your environment has an approved alternate design.
5. Select the SQL installer folder if prompted.
6. Wait for SQL Express, the WSUS role, post-install configuration, firewall rules, and ACL setup to complete.
7. Reboot if the installer or Windows Server Manager requires it.
8. Launch WSUS Manager again and run **Diagnostics**.

### Existing WSUS server

1. Launch `GA-WsusManager.exe` as Administrator.
2. Open **Settings** and confirm the content path and SQL instance match the existing deployment.
3. Run **Diagnostics** before making changes.
4. If database operations fail with permissions errors, click **Fix SQL Login** in the Diagnostics section. Sign out and back in only if your environment requires a token refresh.

---

## 5. Production configuration

### Standard paths

| Setting | Standard value |
|---------|----------------|
| WSUS root/content path | `C:\WSUS` |
| WSUS content directory | `C:\WSUS\WsusContent` |
| SQL instance | `localhost\SQLEXPRESS` |
| Logs | `C:\WSUS\Logs` |
| Export root | `C:\WSUS\Exports` |
| GUI settings | `%APPDATA%\WsusManager\settings.json` |

### Network and firewall

Confirm the server allows inbound client traffic on the active WSUS endpoint:

| Port | Use |
|------|-----|
| 8530 TCP | WSUS HTTP |
| 8531 TCP | WSUS HTTPS, if configured |
| 1433 TCP / 1434 UDP | SQL access only where explicitly required; normally local-only |


## 6. Validation checklist

Run these checks before handing the server to operations:

### Application package

- `GA-WsusManager.exe`, `Scripts\`, and `Modules\` are in the same directory.
- The EXE launches only through **Run as administrator**.
- The version shown in the GUI matches the release being deployed.
- Logs are written under `C:\WSUS\Logs`.

### WSUS health

- **Diagnostics** completes without critical failures.
- `W3SVC`, `WsusService`, and `MSSQL$SQLEXPRESS` are running.
- IIS `WSUS Administration/Content` points to `C:\WSUS\WsusContent`.
- `Authenticated Users` has read access to `C:\WSUS` for client downloads.
- The dashboard health score, database size, disk free space, and last sync values are visible.

### Database and maintenance

- SQL sysadmin access is confirmed for the operator account or approved operator group.
- A manual SUSDB backup can be created or the scheduled maintenance profile is known to create one.
- Database size is below the SQL Express limit with enough headroom for the next sync cycle.
- Monthly or weekly maintenance task is created only on a connected export server that is intentionally allowed to sync with Microsoft.

### Client path

- A test client can reach the WSUS endpoint on port 8530 or 8531.
- Group Policy points clients to the intended WSUS URL.
- A test client can scan and report to WSUS.

### Air-gap path, if applicable

- The approved export folder contains a matching `SUSDB_YYYYMMDD.bak` and `WsusContent\` tree.
- Air-gap server restores the matching SUSDB backup.
- Air-gap server copies content to `C:\WSUS\WsusContent` with **Robocopy** when needed.
- **Reset Content** is used only if WSUS still reports files as downloading after restore or Robocopy.

---

## 7. Troubleshooting

| Symptom | Operator action |
|---------|-----------------|
| EXE opens but operations fail with missing scripts/modules | Re-deploy the full package; the EXE must sit beside `Scripts\` and `Modules\` |
| Dashboard shows WSUS not installed on a fresh host | Expected before first install; click **Install WSUS** |
| Database operation fails with access denied | Run **Fix SQL Login** in Diagnostics, sign out/in only if your environment requires token refresh, then retry |
| Sync stays at 0% | Confirm DNS, proxy/firewall access, and that the server is an approved connected export server |
| Clients scan but never download | Confirm `Authenticated Users` read access on `C:\WSUS` and IIS `/Content` path points to `C:\WSUS\WsusContent` |
| Air-gap import shows downloads still pending | Confirm the `.bak` and `WsusContent\` came from the same approved export snapshot; then use **Reset Content** if still stuck |
| GUI shows missing symbols as `?` | Confirm the deployed script package was not re-saved without UTF-8 BOM and use the release zip instead of hand-copied files |
| Upgrade behaves unexpectedly | Stop using the new folder and follow [ROLLBACK.md](ROLLBACK.md) |

---

## 8. Handoff notes for operators

Record these values in the site operations log after deployment:

- Deployed WSUS Manager version.
- Production install path.
- SQL instance name.
- WSUS content path.
- Export/share path used for air-gap transfer.
- Scheduled maintenance profile and next run time.
- SUSDB backup location and retention expectation.
- Validation date, operator, and any accepted risks.
