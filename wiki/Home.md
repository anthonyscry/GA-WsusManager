# WSUS Manager Wiki

WSUS Manager is a PowerShell 5.1 / WPF tool for installing, restoring, maintaining, and diagnosing WSUS servers backed by SQL Server Express.

Current release: **4.1.0**
Release package: **`GA-WsusManager-v4.1.0.zip`**

## Start here

| Need | Page |
|---|---|
| Install the app or build a new WSUS server | [[Installation Guide]] |
| Restore an air-gapped WSUS server from approved media | [[Air-Gap Workflow]] |
| Use the GUI day to day | [[User Guide]] |
| Fix common errors | [[Troubleshooting]] |
| Review runtime paths, ports, and settings | [[Configuration Guide]] |
| Build or modify the app | [[Developer Guide]] |
| Map modules at a glance | [[Module Reference]] |
| See release notes | [[Changelog]] |

## Operator workflow

1. Download `GA-WsusManager-v4.1.0.zip` from [GitHub Releases](https://github.com/anthonyscry/GA-WsusManager/releases).
2. Extract the whole folder under `C:\WSUS\`, for example `C:\WSUS\WsusManager\`.
3. Keep `GA-WsusManager.exe`, `Scripts\`, `Modules\`, and `icons\` together.
4. Run `GA-WsusManager.exe` as Administrator.
5. If WSUS is missing, click **Install WSUS** before restore, Robocopy, diagnostics, or sync operations.

## Main menu order

**Setup**
- Install WSUS

**Maintenance**
- Restore DB
- Robocopy
- Deep Cleanup

**Online Operations** *(collapsed by default)*
- Online Sync
- Schedule Task

**Diagnostics** *(collapsed by default)*
- Run Diagnostics
- Reset Content
- Fix SQL Login

GPO deployment is not a GUI menu item. Copy the whole `DomainController\` folder to the Domain Controller and run `Set-WsusGroupPolicy.ps1` from inside that copied folder.

## Health score

Health Score is intentionally simple:

| Component | Weight |
|---|---:|
| Services | 40 |
| SUSDB size | 30 |
| Disk free space | 30 |

Scheduled task state, last sync, and operation history appear elsewhere in the UI but do not reduce the score.

## Requirements

| Requirement | Recommendation |
|---|---|
| OS | Windows Server 2019+ |
| PowerShell | Windows PowerShell 5.1 |
| Privileges | Local Administrator; SQL sysadmin for database maintenance |
| SQL | SQL Server Express 2022 |
| Disk | 200 GB+ recommended for WSUS server/content drive |

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

## Version history

| Version | Date | Highlights |
|---|---|---|
| 4.1.0 | Jun 2026 | Stable v4.0.5 baseline with GPO OU creation, SQL login repair, ACL auto-fix, live Robocopy, collapsed sections, simple health score, icons folder, zip-only release asset |
| 4.0.5 | Jun 2026 | Rollback baseline with current GPO import, additive product sync, diagnostics, and refreshed operator docs |
| 4.0.4 | Mar 2026 | sqlcmd fallback, age decline preserving approved updates, sysadmin check fallback |
| 4.0.3 | Mar 2026 | Product defaults, smart decline policy, WID migration, first-sync improvements |
| 4.0.2 | Mar 2026 | GPO schtasks push, security hardening, Robocopy fixes |

See [[Changelog]] for release notes.

---

Internal use - General Atomics Aeronautical Systems, Inc.
