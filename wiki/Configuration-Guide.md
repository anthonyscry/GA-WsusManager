# Configuration Guide

This page documents all configuration values that affect WSUS Manager behavior at runtime. The two categories are **environment variables** and **default paths/settings** stored in `Modules/WsusConfig.psm1`.

## Environment Variables

WSUS Manager uses environment variables to pass secrets safely between processes (parent GUI/CLI → child PowerShell process for long operations). Secrets are never passed on the command line.

| Variable | Purpose | Set By | Read By | Cleared |
|----------|---------|--------|---------|--------|
| `WSUS_INSTALL_SA_PASSWORD` | SQL `sa` password for WSUS + SQL Express install | `Scripts/Install-WsusWithSqlExpress.ps1` (prompts user, then sets in child process env) | `Modules/WsusOperationPlan.psm1` (install plan) → child installer | `try/finally` in OperationPlan |
| `WSUS_TASK_PASSWORD` | Plaintext password (as SecureString conversion) for the user account that runs the maintenance scheduled task | `Modules/WsusOperationPlan.psm1` (scheduling plan) | Child task registration | `try/finally` in OperationPlan |
| `WSUS_REPORT_PATH` | Absolute path where the deep diagnostics operation writes its JSON report | `Scripts/WsusManagementGui.ps1` (sets to `temp\wsus-diagnostic-report-{guid}.json` before launching child) | `Scripts/Invoke-WsusManagement.ps1` deep diagnostics branch | After child returns and JSON is merged into GUI |

### Security Notes

- All three variables hold **sensitive** material; never write them to log files.
- They are scoped to the child process only — they are not inherited by unrelated sessions.
- The OperationPlan module uses `try/finally` to clear the values from the hashtable after the child exits.
- The `WSUS_INSTALL_SA_PASSWORD` flow can optionally persist to an **encrypted file** at `sa.encrypted` (DPAPI scope=CurrentUser) so a fully unattended re-run can decrypt it without re-prompting. This file is only readable by the user account that created it.

### Verifying Values

```powershell
# Show the install plan secret-handling without actually launching install
Import-Module .\Modules\WsusOperationPlan.psm1 -Force -DisableNameChecking
$plan = New-WsusInstallOperationPlan -InstallerPath 'C:\WSUS\SQLDB\setup.exe' -SaUsername 'sa' -SaPasswordEnvVar 'WSUS_INSTALL_SA_PASSWORD' -ScriptPath 'Scripts\Install-WsusWithSqlExpress.ps1'
$plan.Environment.Keys   # Should include 'WSUS_INSTALL_SA_PASSWORD'
$plan.CleanupKeys        # Same list — what gets unset on completion
```

## Default Paths (WsusConfig.psm1)

The `WsusConfig` hashtable (`$script:WsusConfig`) holds default paths, ports, services, and timings. They are constants unless the GUI/CLI receives an explicit override. Override with the corresponding parameter on the CLI.

| Path / Setting | Default | Override Parameter |
|----------------|---------|---------------------|
| `ContentPath` | `C:\WSUS` | `-ContentPath` |
| `ContentSubfolder` | `WsusContent` | — |
| `LogPath` | `C:\WSUS\Logs` | — |
| `SqlInstallerPath` | `C:\WSUS\SQLDB` | — |
| `DefaultExportPath` | `C:\WSUS\Exports` | `-ExportRoot`, `-DestinationPath` |
| `OdtSearchPaths` (Office C2R) | `C:\Program Files\Office\ODT\setup.exe`, `C:\ODT\setup.exe`, `C:\Program Files\Microsoft Office\ODT\setup.exe` | `-OfficeOdtPath` |
| `DefaultUpdateShare` (Office C2R) | *(empty — always prompts)* | `-OfficeSharePath` |

## Network Ports

| Port | Service | Used By |
|------|---------|---------|
| 8530 | WSUS HTTP | IIS WsusPool |
| 8531 | WSUS HTTPS | IIS WsusPool (SSL) |
| 1433 | SQL Server TCP | SUSDB |
| 1434 | SQL Browser UDP | Named instances |

## Service Names

| Config Key | Service | Default Value |
|------------|---------|---------------|
| `SqlExpress` | SQL Server Express instance | `MSSQL$SQLEXPRESS` |
| `Wsus` | WSUS Service | `WSUSService` |
| `Iis` | World Wide Web Publishing | `W3SVC` |
| `WindowsUpdate` | Windows Update Agent | `wuauserv` |
| `Bits` | Background Intelligent Transfer | `bits` |

## Timeouts

All values in seconds, configurable in `$script:WsusConfig.Timeouts`.

| Key | Default | Use |
|-----|---------|-----|
| `SqlQueryDefault` | 30 | Standard SQL queries |
| `SqlQueryLong` | 300 | Cleanup, reindex |
| `SqlQueryUnlimited` | 0 | `waits forever` (used only by SQL maintenance) |
| `ServiceStart` | 10 | Service start wait |
| `ServiceStop` | 5 | Service stop wait |
| `SyncMaxMinutes` | 60 | WSUS sync cap |
| `DownloadMaxIterations` | 60 | Content download cap |

## Reading the Config

```powershell
Import-Module .\Modules\WsusConfig.psm1 -Force -DisableNameChecking
$cfg = Get-WsusRuntimeConfig      # full runtime config
$cfg.Wsus.ContentPath             # C:\WSUS
$cfg.Timeouts.SqlQueryLong        # 300
$cfg.OfficeC2R.DefaultChannel     # MonthlyEnterprise
```

## GUI Persisted Settings

The GUI also persists user-chosen settings to `%APPDATA%\WsusManager\settings.json`. These are read at startup and override defaults. Keys include:

- `ContentPath`
- `SqlInstance`
- `LastExportPath`
- `Theme` (Dark/Light)
- `MaintenanceProfile`

To reset GUI settings, delete the JSON file (the GUI will recreate with defaults on next launch).

---

## Logging and Retention

### Log Files

All operations append to a single daily log file:

| Path | Example |
|------|---------|
| `C:\WSUS\Logs\WsusManagement_YYYY-MM-DD.log` | `C:\WSUS\Logs\WsusManagement_2026-06-07.log` |

### Log Content

Each entry includes a timestamp, the operation type, and the outcome. Session start/end markers separate independent runs.

### Retention Recommendation

WSUS Manager does not automatically rotate or delete old log files. Since each day creates one file, the following retention strategy is recommended:

- **Single-server deployment**: Retain 90 days. Delete files older than 90 days manually or via a monthly scheduled task:

  ```powershell
  # Add to monthly maintenance or run as a scheduled task
  Get-ChildItem C:\WSUS\Logs\*.log | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) } | Remove-Item
  ```

- **Compliance/audit requirement**: Retain 1 year. Archive older files to cold storage.
- **Troubleshooting**: If disk space is critical, retain 30 days and increase verbosity only when actively debugging.

### Related Scripts

| Script | Purpose |
|--------|---------|
| `Scripts/Set-WsusHttps.ps1` | Configure WSUS HTTPS with a self-signed or imported certificate. Creates IIS binding on 8531 and runs `wsusutil configuressl`. See [docs/WSUS-Manager-SOP.md § HTTPS Configuration](../docs/WSUS-Manager-SOP.md#https-configuration-optional) for full instructions. |
| `Scripts/Invoke-WsusClientCheckIn.ps1` | Force a remote client to check in with the WSUS server. Runs `gpupdate`, restarts the Windows Update service, and triggers a detection cycle. Usage: `.\Invoke-WsusClientCheckIn.ps1 -ComputerName "CLIENT01"` |
