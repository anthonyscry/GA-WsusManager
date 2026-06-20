# WSUS Manager Rollback Runbook

**Audience:** WSUS operators reverting a failed GA-WsusManager application deployment or recovering WSUS state after a bad maintenance action.

Rollback is safest when backups are created before every production upgrade. This runbook covers application files, operator settings, SUSDB, services, and verification.

---

## 1. Decide rollback scope

| Problem observed | Roll back |
|------------------|-----------|
| New EXE will not launch, missing menu actions, module import failures | Application folder only |
| GUI settings corrupted or wrong paths persist after upgrade | Operator settings/config only |
| Bad database restore, bad approval/sync state, or SUSDB corruption | SUSDB from a known-good `.bak` |
| Services left stopped or disabled after a failed operation | Service state only |
| Multiple symptoms after upgrade | Application folder, settings, SUSDB, then services in that order |

Do not restore SUSDB unless the database state is part of the failure. Application rollback alone is enough for most failed EXE/script/module deployments.

---

## 2. Required backups before upgrade

Create these before replacing a production release.

### Application backup

Back up the whole deployed application folder so the EXE, scripts, and modules stay version-matched:

```powershell
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$AppPath = 'C:\WSUS\WsusManager'
$BackupRoot = 'C:\WSUS\Rollback'
$AppBackup = Join-Path $BackupRoot "WsusManager-$Stamp"

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
Copy-Item -Path $AppPath -Destination $AppBackup -Recurse -Force
```

The backup must include:

```text
GA-WsusManager.exe
Scripts\
Modules\
DomainController\        if present in the deployed package
docs\ and wiki\          if present in the deployed package
```

### Operator settings/config backup

GUI settings are per-user under `%APPDATA%\WsusManager`. Run this as each operator account that has production settings, or copy from each profile path explicitly:

```powershell
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SettingsPath = Join-Path $env:APPDATA 'WsusManager'
$SettingsBackup = "C:\WSUS\Rollback\AppData-$env:USERNAME-$Stamp"

if (Test-Path $SettingsPath) {
    Copy-Item -Path $SettingsPath -Destination $SettingsBackup -Recurse -Force
}
```

Important files:

| File | Purpose |
|------|---------|
| `settings.json` | GUI paths, mode, notifications, terminal/tray preferences |
| `history.json` | Recent operation history |
| `trends.json` | Database size trend history |

### SUSDB restore point

Create a database backup before a release upgrade, restore test, cleanup, or major approval change:

```powershell
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupPath = "C:\WSUS\Rollback\SUSDB-$Stamp.bak"

New-Item -ItemType Directory -Path (Split-Path $BackupPath) -Force | Out-Null
sqlcmd -S localhost\SQLEXPRESS -E -Q "BACKUP DATABASE SUSDB TO DISK=N'$BackupPath' WITH INIT, CHECKSUM, COPY_ONLY, STATS=10"
```

Keep the SUSDB backup paired with the matching `C:\WSUS\WsusContent\` snapshot or approved transfer set. Restoring a database that does not match the content tree can leave updates in a downloading or missing-content state.

### Service state snapshot

Record current service states before maintenance:

```powershell
Get-Service W3SVC, WsusService, 'MSSQL$SQLEXPRESS' |
    Select-Object Name, Status, StartType |
    Export-Csv C:\WSUS\Rollback\service-state-before.csv -NoTypeInformation
```

---

## 3. Application rollback: EXE, scripts, and modules

Use this when the deployed release fails to launch or its operations cannot find the expected scripts/modules.

1. Close `GA-WsusManager.exe` for all users.
2. Stop scheduled WSUS Manager maintenance tasks if one could run during rollback.
3. Rename the failed deployment folder instead of deleting it:

   ```powershell
   $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
   Rename-Item -Path C:\WSUS\WsusManager -NewName "WsusManager.failed-$Stamp"
   ```

4. Restore the known-good application backup:

   ```powershell
   Copy-Item -Path C:\WSUS\Rollback\WsusManager-YYYYMMDD-HHMMSS -Destination C:\WSUS\WsusManager -Recurse -Force
   ```

5. Confirm package structure:

   ```powershell
   Test-Path C:\WSUS\WsusManager\GA-WsusManager.exe
   Test-Path C:\WSUS\WsusManager\Scripts
   Test-Path C:\WSUS\WsusManager\Modules
   ```

6. Launch `GA-WsusManager.exe` as Administrator and run **Diagnostics**.

Do not mix an old EXE with new `Scripts\` or `Modules\`. Roll back the folder as a single unit.

---

## 4. Settings/config rollback

Use this when the application launches but has wrong paths, bad persisted mode, broken notification preferences, or corrupted JSON settings.

1. Close `GA-WsusManager.exe`.
2. Back up the current settings before replacing them:

   ```powershell
   $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
   $SettingsPath = Join-Path $env:APPDATA 'WsusManager'
   if (Test-Path $SettingsPath) {
       Rename-Item -Path $SettingsPath -NewName "WsusManager.failed-$Stamp"
   }
   ```

3. Restore the saved settings folder:

   ```powershell
   Copy-Item -Path C:\WSUS\Rollback\AppData-USERNAME-YYYYMMDD-HHMMSS -Destination (Join-Path $env:APPDATA 'WsusManager') -Recurse -Force
   ```

4. Launch the app and verify **Settings** shows the expected content path, SQL instance, export root, terminal mode, and server mode.

If no settings backup exists, delete or rename `%APPDATA%\WsusManager` and let the GUI recreate defaults, then re-enter production paths from the site runbook.

---

## 5. SUSDB rollback

Use this only when the database state is bad and a known-good `.bak` exists.

### Before restoring

1. Confirm the backup file is from the intended server and date.
2. Confirm whether the matching `WsusContent\` snapshot is also available.
3. Notify operators that WSUS will be unavailable during restore.
4. Close WSUS Manager.
5. Stop WSUS/IIS services to release database activity:

   ```powershell
   Stop-Service WsusService -ErrorAction SilentlyContinue
   Stop-Service W3SVC -ErrorAction SilentlyContinue
   ```

### Restore using WSUS Manager

Preferred operator path:

1. Launch `GA-WsusManager.exe` as Administrator.
2. Click **Restore Database**.
3. Select the known-good `.bak` file.
4. Confirm the destructive restore prompt.
5. Wait for restore and post-restore processing to complete.
6. Run **Diagnostics**.
7. Use **Reset Content** only if updates still show as downloading after the matching content tree is present.

### Restore using sqlcmd when the GUI cannot run

Use this only if the application rollback path cannot launch the GUI:

```powershell
$BackupPath = 'C:\WSUS\Rollback\SUSDB-YYYYMMDD-HHMMSS.bak'

sqlcmd -S localhost\SQLEXPRESS -E -Q "
ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE SUSDB FROM DISK=N'$BackupPath' WITH REPLACE, STATS=10;
ALTER DATABASE SUSDB SET MULTI_USER;
"
```

Then start services:

```powershell
Start-Service 'MSSQL$SQLEXPRESS'
Start-Service W3SVC
Start-Service WsusService
```

If the restored database points at content not present on disk, restore the matching `WsusContent\` tree from the same approved transfer set before declaring rollback complete.

---

## 6. Service rollback

Use this when a failed operation leaves SQL, IIS, or WSUS stopped.

### Standard service recovery

```powershell
Start-Service 'MSSQL$SQLEXPRESS'
Start-Service W3SVC
Start-Service WsusService
Get-Service 'MSSQL$SQLEXPRESS', W3SVC, WsusService
```

### Reset service startup type if changed

```powershell
Set-Service 'MSSQL$SQLEXPRESS' -StartupType Automatic
Set-Service W3SVC -StartupType Automatic
Set-Service WsusService -StartupType Automatic
```

### IIS application pool check

If clients still cannot download after services start:

```powershell
Import-Module WebAdministration
Get-WebAppPoolState -Name WsusPool
Start-WebAppPool -Name WsusPool
```

---

## 7. Rollback verification

Rollback is not complete until these checks pass.

### Application verification

- `GA-WsusManager.exe` launches as Administrator.
- The restored version is the intended known-good release.
- `Scripts\` and `Modules\` are present beside the EXE.
- **Diagnostics** runs from the GUI.
- Logs are written under `C:\WSUS\Logs`.

### Configuration verification

- **Settings** shows the expected content path and SQL instance.
- `%APPDATA%\WsusManager\settings.json` is valid JSON if restored.
- Scheduled maintenance task points to the intended restored application path.

### Database verification

- SQL service is running.
- SUSDB is online.
- WSUS Manager dashboard shows database size and update counts.
- A test health check does not report missing database access.

### WSUS service verification

- `MSSQL$SQLEXPRESS`, `W3SVC`, and `WsusService` are running.
- IIS `/Content` still maps to `C:\WSUS\WsusContent`.
- `Authenticated Users` has read access on `C:\WSUS`.
- A test client can reach port 8530 or 8531 and report to WSUS.

### Air-gap/content verification

- Restored SUSDB backup date matches the restored or existing content snapshot.
- `C:\WSUS\WsusContent` contains update files.
- **Reset Content** has been run only if content state remained stuck after restore.

---

## 8. Post-rollback record

Record the rollback in the operations log:

- Date/time and operator.
- Failed release version and restored release version.
- Application backup path used.
- Settings backup path used, if any.
- SUSDB backup path used, if any.
- Whether `WsusContent\` was restored.
- Service state before and after rollback.
- Verification results and remaining risks.

Keep the failed deployment folder until logs have been reviewed and the incident is closed.
