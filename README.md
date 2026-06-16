# WSUS Manager

**Version:** 4.1.0
**Author:** Tony Tran, ISSO, GA-ASI

WSUS Manager is a PowerShell GUI + CLI application for managing Windows Server Update Services (WSUS) on air-gapped and controlled networks. It handles the entire lifecycle of keeping Windows machines patched: installing WSUS and SQL Server Express, syncing updates on a connected server, transferring them to a disconnected network via USB or share, importing them, configuring HTTPS, and pushing updates out to client machines through Group Policy.


---

## Table of Contents

- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Features](#features)
- [Workflows](#workflows)
  - [Setting Up a New WSUS Server from Scratch](#setting-up-a-new-wsus-server-from-scratch)
  - [Air-Gapped Server Build + Import Workflow](#air-gapped-server-build--import-workflow)
  - [Reference: Online Sync Workflow (Source Server Only)](#reference-online-sync-workflow-source-server-only)
  - [Deploying GPOs to Clients](#deploying-gpos-to-clients)
- [Project Structure](#project-structure)
- [Modules](#modules)
- [Build, Test, and CI](#build-test-and-ci)
- [Standard Paths](#standard-paths)
- [Environment Variables](#environment-variables)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Quick Start

1. Download `WsusManager-vX.X.X.zip` from the [Releases](https://github.com/anthonyscry/GA-WsusManager/releases) page.
2. Extract the full archive to a folder under `C:\WSUS\` (for example, `C:\WSUS\WsusManager\`).
3. Right-click `GA-WsusManager.exe` and select **Run as Administrator**.

> **Important:** The EXE requires the `Scripts/` and `Modules/` folders in the same directory. Do not move the EXE without also moving those folders.

**If your online/source WSUS server is already set up:** skip straight to the [Air-Gapped Server Build + Import Workflow](#air-gapped-server-build--import-workflow).

For step-by-step installation including the SQL Server Express prerequisite, see [docs/QUICK-START.md](docs/QUICK-START.md).

---

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows 10/11 or Windows Server 2019/2022 |
| PowerShell | 5.1 or later (ships with Windows) |
| Privileges | Administrator (right-click, Run as Administrator) |
| WSUS role | Installed by the setup workflow if not present |
| SQL Server | SQL Server Express 2022 (installed by the setup workflow) |
| Disk space | At least 40 GB free on the WSUS content drive |

---

## Features

### Dashboard
- Auto-refreshing dashboard (every 30 seconds) showing service status, disk space, database size, and scheduled task status.
- Health Score (0-100) with color-coded grade: Green (80+), Yellow (50-79), Red (below 50).
- Database size trending with days-until-full estimate using linear regression. Alerts when approaching the 10 GB SQL Express limit.
- Last successful sync timestamp.

### Server Management
- One-click WSUS + SQL Server Express 2022 installation with guided setup.
- Unified Diagnostics (health check + auto-repair in a single operation).
- Database backup, restore, and deep cleanup (6-step maintenance including index rebuild and database shrink).
- Online Sync with Full, Quick, and Sync Only profiles.
- Scheduled task creation for recurring sync operations (daily, weekly, monthly).
- HTTPS configuration via `Set-WsusHttps.ps1`.

### Air-Gap Support
- Server Mode toggle: Online vs Air-Gap.
- Export updates and content to USB for transfer to disconnected networks.
- Import updates and content from USB on the air-gapped server.
- "Reset Content" button for troubleshooting content registration issues after import.
- Diagnostics verify both WSUS root permissions on `C:\WSUS` and the IIS `/Content` path to `C:\WSUS\WsusContent`.


### Client Deployment
- GPO deployment scripts for air-gapped domains (no WinRM required).
- Client check-in script to force update detection.
- "Create GPO" button copies GPO files and shows deployment instructions.

### GUI Features
- Dark theme with high-DPI awareness.
- Startup splash screen with progress bar.
- Keyboard shortcuts: Ctrl+D (Diagnostics), Ctrl+S (Sync), Ctrl+H (History), Ctrl+R or F5 (Refresh Dashboard).
- Right-click context menu on log panel: Copy All / Save to File.
- Operation history view showing last 50 operations.
- Desktop notifications on operation completion (toast, balloon, or log-only fallback).
- Live Terminal Mode to open operations in an external PowerShell window.

---

## Workflows

### Setting Up a New WSUS Server from Scratch

This workflow installs WSUS and SQL Server Express on a fresh Windows Server.

1. **Copy the application.** Extract `WsusManager-vX.X.X.zip` to a folder under `C:\WSUS\` (e.g. `C:\WSUS\WsusManager\`).
2. **Place the SQL installer.** If the server has no internet access, download SQL Server Express 2022 and SSMS on a connected machine and copy the installers to `C:\WSUS\SQLDB\` on the target server.
3. **Launch WSUS Manager.** Right-click `GA-WsusManager.exe` and select **Run as Administrator**. The dashboard will show "WSUS Not Installed" — this is expected.
4. **Run Install.** Click the **Install WSUS** button. The application will:
   - Use `C:\WSUS` as the WSUS root/content directory by default.
   - Install SQL Server Express 2022 if not already present.
   - Install the WSUS Windows Server role.
   - Run post-installation configuration.
   - Set up firewall rules and directory permissions.
5. **Verify.** Once installation completes, the dashboard should show green status for SQL Server, IIS, and WSUS services.
6. **Deploy GPOs** (air-gapped networks only) — see [Deploying GPOs to Clients](#deploying-gpos-to-clients).

### Air-Gapped Server Build + Import Workflow

If your online WSUS server is already syncing updates and publishing a database backup plus `WsusContent` to a share drive, this is the workflow most operators should follow.
GUI transfer, CLI import/export, and monthly export use the same non-destructive transfer engine.

**On the air-gapped server:**

1. Build the server using the steps above.
2. Copy these items from the approved share drive or transfer media:
   - Latest `SUSDB_YYYYMMDD.bak`
   - Latest `WsusContent\` tree
3. Click **Transfer > Import**. Select the share-drive copy or USB folder as the source and `C:\WSUS\` as the destination.
4. Confirm the update files land in `C:\WSUS\WsusContent`.
5. Click **Restore Database** and select the copied `.bak` file from `C:\WSUS\`.
6. Run **Diagnostics** and confirm:
   - `Authenticated Users` has read access on `C:\WSUS`
   - IIS `WSUS Administration/Content` points to `C:\WSUS\WsusContent`
   - No permission or content-path errors remain

### Reference: Online Sync Workflow (Source Server Only)

This section is only for the internet-connected source WSUS server that produces the share-drive export for the air-gapped server.

1. Launch WSUS Manager as Administrator.
2. Click **Online Sync** in the navigation panel (or use the Quick Action button).
3. Choose a sync profile:
   - **Full Sync** — Decline superseded updates, sync with Microsoft, approve new updates, clean up the database, and export.
   - **Quick Sync** — Sync and approve only (skip cleanup).
   - **Sync Only** — Just sync with Microsoft, no approvals or cleanup.
4. Set the export path to the approved share drive or staging folder used for air-gap transfer.
5. Click **OK.** A Full Sync typically takes 30-120 minutes depending on how many updates are available.
6. Check the dashboard. After the sync completes, the Last Sync timestamp should update and the database size may increase.

> **Tip:** To automate this, click **Schedule** to create a Windows Scheduled Task that runs the sync monthly.

### Deploying GPOs to Clients

Group Policy Objects (GPOs) tell Windows client machines where the WSUS server is and how to apply updates. This is required on air-gapped networks because clients cannot reach Microsoft's update servers.

**Prerequisites:**
- A Domain Controller with GPMC (Group Policy Management Console) installed.
- The `DomainController/` folder from the WSUS Manager distribution.

**Steps:**

1. Copy the `DomainController/` folder to the Domain Controller.
2. Open an elevated PowerShell prompt on the Domain Controller.
3. Run the GPO deployment script:
   ```powershell
   .\Set-WsusGroupPolicy.ps1
   ```
4. When prompted, enter the WSUS server hostname (just the name, not the full URL). For example, if your WSUS server is called `WSUS01`, type `WSUS01`. The script builds the URL `http://WSUS01:8530` automatically.
5. The script will:
   - Auto-detect your domain.
   - Import three GPOs from the `WSUS GPOs/` backup folder.
   - Reuse an existing `Member Servers` or `Member_Servers` OU if present, and create `WSUS Server` beneath it when needed.
6. Move the WSUS server computer object to the `Member Servers\WSUS Server` OU.

**Verify on a client:**
```powershell
gpresult /r | findstr WSUS
```


---

## Project Structure

```
GA-WsusManager/
├── Scripts/             # PowerShell entry points (GUI, CLI, install, monthly maintenance, HTTPS, client check-in)
├── Modules/             # 26 shared PowerShell modules
├── Tests/               # 752 Pester tests across 25 test files
├── DomainController/    # GPO deployment script + backed-up GPOs
├── build/               # Local validation + ship-readiness scripts
├── docs/                # SOP, quick-start, CI/CD docs, Confluence export
├── wiki/                # User / developer / configuration guides
├── .github/workflows/   # CI pipelines (ci.yml for standard, gui-tests.yml for self-hosted)
├── build.ps1            # EXE + ZIP packaging
└── metadata.json        # Single source of truth for version (read by Get-WsusAppVersion)
```

---

## Modules

26 PowerShell modules live in `Modules/`. Key ones:

| Module | Purpose |
|--------|---------|
| `WsusUtilities.psm1` | Logging, colors, helpers |
| `WsusConfig.psm1` | Configuration, operation timeouts, health weights, version |
| `WsusDatabase.psm1` | Database operations with sqlcmd.exe fallback |
| `WsusHealth.psm1` | Health checks, repair, health score |
| `WsusServices.psm1` | Service management |
| `WsusFirewall.psm1` | Firewall rules |
| `WsusPermissions.psm1` | Directory permissions |
| `WsusExport.psm1` | Export/import for air-gap transfer |
| `WsusScheduledTask.psm1` | Scheduled tasks (daily/weekly/monthly) |
| `WsusAutoDetection.psm1` | Server detection, dashboard data, 30s TTL cache |
| `WsusDialogs.psm1` | Dialog factory for WPF GUI |
| `WsusOperationRunner.psm1` | Unified operation lifecycle with timeout watchdog |
| `WsusHistory.psm1` | Operation history (JSON at `%APPDATA%\WsusManager\history.json`) |
| `WsusNotification.psm1` | Toast/balloon/log-only completion notifications |
| `WsusTrending.psm1` | DB size trending with linear regression |
| `WsusOperationPlan.psm1` | Cross-process plan for child PowerShell operations |
| `WsusProvisioning.psm1` | Pre-install provisioning checks |
| `WsusGuiShell.psm1` | WPF shell for GUI application |
| `WsusProcessHost.psm1` | Long-running process management |
| `WsusHostEnvironment.psm1` | Environment detection helpers |
| `WsusRepairPlan.psm1` | Repair plan builder |
| `WsusRepairHarness.psm1` | Repair execution harness |
| `WsusDiagnosticResult.psm1` | Diagnostic result types |
| `WsusTestHarness.psm1` | Test harness for modules |
| `AsyncHelpers.psm1` | Async/background operation helpers for WPF |

See [wiki/Module-Reference.md](wiki/Module-Reference.md) for the full reference.

---

## Build, Test, and CI

### Local validation

```powershell
# Aggregate gate (matches what CI runs)
.\build\Invoke-ShipReadiness.ps1

# Quick syntax check across all PS files
.\build\Invoke-SyntaxCheck.ps1


# Full local validation (lint + tests + XAML)
.\build\Invoke-LocalValidation.ps1

# Full build pipeline (EXE + ZIP, git publish opt-in)
.\build.ps1
```

### CI

Two-tier CI model — see [docs/ci-cd.md](docs/ci-cd.md) for the full design.

| Workflow | Trigger | Runner | Purpose |
|----------|---------|--------|---------|
| `.github/workflows/ci.yml` | every push + PR | `windows-latest` (GitHub-hosted) | syntax, lint, unit tests, EXE build |
| `.github/workflows/gui-tests.yml` | manual + daily | `self-hosted, windows, triton-ajt` | full Pester suite including FlaUI GUI automation |

### Test counts (as of v4.1.0)

- **791 tests** in the standard unit suite gate
- **Last standard validation run:** 790 pass, 0 fail, 1 skip (excluding E2E / GUI / Integration / FlaUI)

---

## Standard Paths

| Path | Purpose |
|------|---------|
| `C:\WSUS` | WSUS root + content directory |
| `C:\WSUS\WsusContent` | WSUS update file store |
| `C:\WSUS\UpdateServicesPackages` | WSUS update packages |
| `C:\WSUS\Logs` | Daily log files (`WsusManagement_YYYY-MM-DD.log`) |
| `C:\WSUS\SQLDB` | SQL installer staging area |
| `C:\WSUS\Exports` | Default export destination for air-gap transfer |
| `%APPDATA%\WsusManager\settings.json` | GUI persisted settings |
| `%APPDATA%\WsusManager\history.json` | Operation history |
| `%APPDATA%\WsusManager\trends.json` | DB size trend data |

Network ports: 8530 (WSUS HTTP), 8531 (WSUS HTTPS), 1433 (SQL TCP), 1434 (SQL Browser UDP).

---

## Environment Variables

| Variable | Purpose | Lifetime |
|----------|---------|----------|
| `WSUS_INSTALL_SA_PASSWORD` | SQL `sa` password for install | Set in child process by `WsusOperationPlan.psm1`, cleared in `try/finally` |
| `WSUS_TASK_PASSWORD` | User password for scheduled task | Same |
| `WSUS_REPORT_PATH` | Path where deep diagnostics writes JSON report | Set by GUI, read by child |

See [wiki/Configuration-Guide.md](wiki/Configuration-Guide.md) for the full reference including how to read all config values via `Get-WsusRuntimeConfig` and `Get-WsusAppVersion`.

---

## Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | This file — project overview and quick start |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Production deployment runbook |
| [docs/ROLLBACK.md](docs/ROLLBACK.md) | Application, settings, SUSDB, and service rollback runbook |
| [docs/QUICK-START.md](docs/QUICK-START.md) | Step-by-step install guide |
| [docs/WSUS-Manager-SOP.md](docs/WSUS-Manager-SOP.md) | Full operator Standard Operating Procedure |
| [docs/WSUS-Manager-SOP-Confluence.txt](docs/WSUS-Manager-SOP-Confluence.txt) | Confluence wiki markup version of the SOP |
| [docs/ci-cd.md](docs/ci-cd.md) | Build, test, and CI/CD pipeline |
| [docs/releases.md](docs/releases.md) | Release process |
| [CHANGELOG.md](CHANGELOG.md) | Version history with added/changed/fixed sections |
| [wiki/Home.md](wiki/Home.md) | Wiki landing page |
| [wiki/Installation-Guide.md](wiki/Installation-Guide.md) | Detailed install walk-through |
| [wiki/User-Guide.md](wiki/User-Guide.md) | GUI usage guide |
| [wiki/Air-Gap-Workflow.md](wiki/Air-Gap-Workflow.md) | Air-gapped network operations |
| [wiki/Troubleshooting.md](wiki/Troubleshooting.md) | Common issues |
| [wiki/Developer-Guide.md](wiki/Developer-Guide.md) | Building from source |
| [wiki/Configuration-Guide.md](wiki/Configuration-Guide.md) | Env vars, paths, ports, timeouts |
| [wiki/Module-Reference.md](wiki/Module-Reference.md) | Module function reference |
| [wiki/Changelog.md](wiki/Changelog.md) | Wiki changelog mirror |
| [docs/ai-audit/README.md](docs/ai-audit/README.md) | AI ship-readiness audit instruction pack |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Dashboard shows "Not Installed" | Click **Install WSUS** |
| Sync stuck at 0% | Check DNS; GUI runs a DNS preflight check before sync |
| Endless downloads | Content path must be `C:\WSUS` (NOT `C:\WSUS\wsuscontent`) |
| Clients scan but never download | Verify `Authenticated Users` read access on `C:\WSUS` and IIS `/Content` points to `C:\WSUS\WsusContent` |
| Database near 10 GB | Run **Deep Cleanup** |
| Database restore fails | Verify sysadmin privileges on SQL Server |
| `SqlServer` module missing | v4.0.4+ auto-falls back to `sqlcmd.exe` — no manual install needed |
| GroupPolicy module not found | Install RSAT: `Install-WindowsFeature GPMC` |
| GUI shows `?` for emoji/symbols | v4.1.0+ has UTF-8 BOM applied; symbols verified against Segoe UI font coverage |
| Operation hangs | Check whether running in non-interactive mode; GUI passes `-NonInteractive` |

For the full troubleshooting guide see [wiki/Troubleshooting.md](wiki/Troubleshooting.md) and [docs/WSUS-Manager-SOP.md § Troubleshooting](docs/WSUS-Manager-SOP.md#troubleshooting).

---

## License

*Internal use — General Atomics Aeronautical Systems, Inc.*
