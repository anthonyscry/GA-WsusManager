# Configuration Guide

This page lists the runtime values operators usually need.

## Standard paths

| Item | Default |
|---|---|
| WSUS root/content path | `C:\WSUS` |
| WSUS content files | `C:\WSUS\WsusContent` |
| Logs | `C:\WSUS\Logs` |
| SQL installer folder | `C:\WSUS\SQLDB` |
| GUI settings | `%APPDATA%\WsusManager\settings.json` |
| Operation history | `%APPDATA%\WsusManager\history.json` |
| DB trends | `%APPDATA%\WsusManager\trends.json` |

## SQL and WSUS defaults

| Item | Default |
|---|---|
| SQL instance | `.\SQLEXPRESS` |
| Database | `SUSDB` |
| WSUS HTTP | `8530` |
| WSUS HTTPS | `8531` |
| SQL TCP | `1433` |
| SQL Browser UDP | `1434` |

## Services

| Service | Name |
|---|---|
| SQL Express | `MSSQL$SQLEXPRESS` |
| SQL Browser | `SQLBrowser` |
| WSUS Service | `WSUSService` |
| IIS | `W3SVC` |
| Windows Update | `wuauserv` |
| BITS | `bits` |

## Secrets

WSUS Manager does not pass passwords on the command line. Long-running child processes receive secrets through scoped environment variables.

| Variable | Purpose |
|---|---|
| `WSUS_INSTALL_SA_PASSWORD` | SQL `sa` password for install/bootstrap |
| `WSUS_TASK_PASSWORD` | Scheduled task credential handoff |
| `WSUS_REPORT_PATH` | Temporary deep-diagnostics JSON report path |

These are process-scoped and cleared after use.

## Health score weights

| Component | Weight |
|---|---:|
| Services | 40 |
| SUSDB size | 30 |
| Disk free space | 30 |

Scheduled task state, last sync, and last operation history do not affect the score.

## Package layout

```text
GA-WsusManager-v4.1.0\
+-- GA-WsusManager.exe
+-- Scripts\
+-- Modules\
+-- icons\
+-- DomainController\
+-- metadata.json
+-- README.md
+-- QUICK-START.txt
```

## Related pages

- [[Installation Guide]]
- [[User Guide]]
- [[Troubleshooting]]
