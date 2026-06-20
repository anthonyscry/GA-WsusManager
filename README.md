# WSUS Manager

**Version:** 4.1.0
**Author:** Tony Tran, ISSO, GA-ASI

WSUS Manager is a PowerShell GUI application for managing Windows Server Update Services (WSUS) on air-gapped networks. It installs WSUS and SQL Server Express, restores approved WSUS transfer folders on disconnected servers, manages update synchronization/cleanup, deploys air-gap Group Policy Objects, and provides diagnostics/repair workflows.

---

## Table of Contents

- [What is WSUS?](#what-is-wsus)
- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Features](#features)
- [Workflows](#workflows)
  - [Setting Up a New WSUS Server from Scratch](#setting-up-a-new-wsus-server-from-scratch)
  - [Air-Gap Transfer Workflow](#air-gap-transfer-workflow)
  - [Monthly Sync Workflow (Online Operations)](#monthly-sync-workflow-online-operations)
  - [Deploying GPOs to Clients](#deploying-gpos-to-clients)
- [GPO Reference](#gpo-reference)
  - [GPO 1: WSUS Update Policy - Servers](#gpo-1-wsus-update-policy---servers)
  - [GPO 2: WSUS Update Policy - Workstations](#gpo-2-wsus-update-policy---workstations)
  - [GPO 3: WSUS Inbound Allow](#gpo-3-wsus-inbound-allow)
  - [GPO 4: WSUS Outbound Allow](#gpo-4-wsus-outbound-allow)
- [Project Structure](#project-structure)
- [Modules](#modules)
- [Build and Test](#build-and-test)
- [Standard Paths](#standard-paths)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## What is WSUS?

Windows Server Update Services (WSUS) is a Microsoft tool that lets an administrator approve and distribute Windows updates from a central server instead of having every computer download them individually from the internet. This is important in two scenarios:

1. **Controlled environments** -- you want to test updates before rolling them out.
2. **Air-gapped networks** -- your computers have no internet access at all. Updates must be physically carried in on a USB drive.

WSUS stores its data in a SQL Server Express database (called SUSDB) and its update files in a content directory on disk. WSUS Manager automates the setup, maintenance, and monitoring of both.

---

## Quick Start

1. Go to the [Releases](../../releases) page.
2. Download `GA-WsusManager-vX.X.X.zip`.
3. Extract the full archive to a folder (for example, `C:\WsusManager\`).
4. Right-click `GA-WsusManager.exe` and select **Run as Administrator**.

**Important:** The EXE requires the `Scripts/` and `Modules/` folders to be in the same directory. Do not move the EXE without also moving those folders.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows 10/11 or Windows Server 2019/2022 |
| PowerShell | 5.1 or later (ships with Windows) |
| Privileges | Administrator (right-click, Run as Administrator) |
| WSUS role | Installed by the setup workflow if not present |
| SQL Server | SQL Server Express 2022 (installed by the setup workflow) |
| Disk space | At least 200 GB recommended for the WSUS server/content drive |

---

## Features

### Dashboard
- Auto-refreshing dashboard (every 30 seconds) showing service status, disk space, database size, and scheduled task status.
- Health Score (0-100) from services, database size, and disk space with color-coded grade: Green (80+), Yellow (50-79), Red (below 50).
- Database size trending with days-until-full estimate using linear regression. Alerts when approaching the 10 GB SQL Express limit.
- Last successful sync timestamp.

### Server Management
- One-click WSUS + SQL Server Express installation with guided setup.
- Unified Diagnostics (health check + auto-repair in a single operation).
- Database backup, restore, and deep cleanup (6-step maintenance including index rebuild and database shrink).
- Online Sync with Full, Quick, and Sync Only profiles.
- Scheduled task creation for recurring sync operations.
- HTTPS configuration via `Set-WsusHttps.ps1`.

### Air-Gap Support
- Restore approved WSUS transfer folders from USB/removable media on disconnected servers.
- Copy approved content folders with **Robocopy** when needed.
- "Reset Content" button to fix content download status after restore or copy.

### Client Deployment
- GPO deployment scripts for air-gapped domains.
- Copy the whole `DomainController/` folder to the Domain Controller, then run `Set-WsusGroupPolicy.ps1` there.
- Client check-in script to force update detection.

### GUI Features
- Dark theme with light theme toggle in Settings (reserved).
- Startup splash screen with progress bar.
- Keyboard shortcuts: Ctrl+D (Diagnostics), Ctrl+S (Sync), Ctrl+H (History), Ctrl+R or F5 (Refresh Dashboard).
- Right-click context menu on log panel: Copy All / Save to File.
- Operation history view showing last 50 operations.
- Desktop notifications on operation completion (toast, balloon, or log-only fallback).
- Live Terminal Mode to open operations in an external PowerShell window.
- DPI-aware rendering on high-DPI displays.

---

## Workflows

### Setting Up a New WSUS Server from Scratch

This workflow installs WSUS and SQL Server Express on a fresh Windows Server.

1. **Prepare the server.** Log in as an Administrator. Plan for at least 200 GB on the WSUS server/content drive (default: `C:\WSUS\`).

2. **Copy the application.** Extract the `GA-WsusManager-vX.X.X.zip` archive to a folder such as `C:\WsusManager\`.

3. **Place the SQL installer.** If the server has no internet access, download `SQL Server Express 2022` and `SQL Server Management Studio (SSMS)` on a connected machine and copy the installers to `C:\WSUS\SQLDB\` on the target server. The install script will look for them there.

4. **Launch WSUS Manager.** Right-click `GA-WsusManager.exe` and select Run as Administrator. The dashboard will show "WSUS Not Installed" -- this is expected.

5. **Run Install.** Click the **Install WSUS** button. The application will:
   - Prompt for the content directory (default: `C:\WSUS\`).
   - Install SQL Server Express 2022 if not already present.
   - Install the WSUS Windows Server role.
   - Run post-installation configuration.
   - Set up firewall rules and directory permissions.

6. **Verify.** Once installation completes, the dashboard should show green status for SQL Server, IIS, and WSUS services.

7. **Deploy GPOs.** If this is an air-gapped server, follow the [Deploying GPOs to Clients](#deploying-gpos-to-clients) workflow to tell client machines where to find the WSUS server.

### Air-Gap Transfer Workflow

Use this workflow when an approved WSUS transfer folder has been released for a disconnected network.

1. Transfer the complete approved folder to the air-gapped server using approved USB/removable media.

2. Launch WSUS Manager as Administrator.

3. Click **Restore DB** and select the SUSDB backup from the transferred folder.

4. Click **Robocopy** if `WsusContent\` still needs to be copied into `C:\WSUS\`.

5. After restore or Robocopy completes, click **Reset Content** (under Diagnostics) to run `wsusutil reset`. This tells WSUS to re-verify all content files against the database. Without this step, some updates may show "still downloading" even though the files are present.

6. Run **Diagnostics** to verify services, database access, IIS content mapping, and content permissions.

### Monthly Sync Workflow (Online Operations)

Run this monthly on a connected server that is intentionally allowed to sync with Microsoft.

1. **Launch WSUS Manager** as Administrator.

2. **Click Online Sync** in the navigation panel (or use the Quick Action button).

3. **Choose a sync profile:**
   - **Full Sync** -- Sync, cleanup, ultimate cleanup, and backup.
   - **Quick Sync** -- Sync, cleanup, and backup.
   - **Sync Only** -- Just sync with Microsoft and apply the approval policy.

4. **Choose the approved staging path** if the Full profile asks where to place the completed package.

5. **Click OK.** The operation runs in the log panel. A Full Sync typically takes 30-120 minutes depending on how many updates are available.

6. **Check the dashboard.** After the sync completes, the Last Sync timestamp should update and the database size may increase.

**Tip:** To automate this, click **Schedule Task** to create a Windows Scheduled Task that runs the sync monthly.

### Deploying GPOs to Clients

Group Policy Objects (GPOs) tell Windows client machines where the WSUS server is and how to apply updates. This is required on air-gapped networks because clients cannot reach Microsoft's update servers.

**Prerequisites:**
- A Domain Controller with GPMC (Group Policy Management Console) installed.
- The `DomainController/` folder from the WSUS Manager distribution.

**Steps:**

1. Copy the whole `DomainController/` folder to the Domain Controller. Keep `Set-WsusGroupPolicy.ps1` and the `WSUS GPOs/` backup folder together.

2. Open an elevated PowerShell prompt on the Domain Controller.

3. From inside the copied `DomainController/` folder, run the GPO deployment script:
   ```powershell
   .\Set-WsusGroupPolicy.ps1
   ```

4. When prompted, enter the WSUS server hostname (just the name, not the full URL). For example, if your WSUS server is called `WSUS01`, type `WSUS01`. The script builds the URL `http://WSUS01:8530` automatically.

5. The script will:
   - Auto-detect your domain.
   - Import four GPOs from the `WSUS GPOs/` backup folder.
   - Reuse existing `Member Servers` or `Member_Servers` OUs when present.
   - Create missing `Member Servers`, `WSUS Server`, and `Workstations` OUs when needed.
   - Link each GPO to the correct OUs.
   - Replace placeholder WSUS URLs with your server.
   - Prompt to move the WSUS server computer object into `Member Servers\WSUS Server` so the inbound firewall GPO applies.
   - Push a Group Policy update to all domain computers via scheduled task (no WinRM required).

6. **Verify on a client machine:**
   ```powershell
   gpresult /r | findstr WSUS
   ```
   You should see the WSUS GPOs listed under "Applied Group Policy Objects."

---

## GPO Reference

The `DomainController/WSUS GPOs/` folder contains four pre-configured Group Policy Objects. The deployment script (`Set-WsusGroupPolicy.ps1`) imports them, updates WSUS URLs for your environment, links them to the expected OUs, creates missing `Member Servers`, `WSUS Server`, and `Workstations` OUs, and prompts to move the WSUS server computer object into the WSUS Server OU.

**WARNING:** These GPOs are designed for AIR-GAPPED networks only. Deploying them on internet-connected systems will redirect Windows Update traffic to the internal WSUS server and prevent machines from getting updates directly from Microsoft.

### GPO 1: WSUS Update Policy - Servers

**Purpose:** Points domain controllers and member servers to your internal WSUS server and applies the server update schedule/deadline policy.

**Linked to:** `Domain Controllers` and `Member Servers`.

### GPO 2: WSUS Update Policy - Workstations

**Purpose:** Points workstation clients to your internal WSUS server and applies the workstation update schedule/deadline policy.

**Linked to:** `Workstations`.

**Registry keys set by the deployment script for both update-policy GPOs:**

| Registry Path | Value Name | Type | Value | What It Does |
|---------------|-----------|------|-------|--------------|
| `HKLM\...\WindowsUpdate` | `WUServer` | String | `http://WSUS01:8530` | The URL of your WSUS server. The deployment script replaces this with the hostname you provide. |
| `HKLM\...\WindowsUpdate` | `WUStatusServer` | String | `http://WSUS01:8530` | Where clients report update status. Usually the same server. |
| `HKLM\...\WindowsUpdate\AU` | `UseWUServer` | DWORD | `1` | Forces clients to use the intranet WSUS server. |
| `HKLM\...\WindowsUpdate\AU` | `AUOptions` | DWORD | `4` | Auto-download and install on the schedule below. |
| `HKLM\...\WindowsUpdate\AU` | `ScheduledInstallDay` | DWORD | `0` | Install every day. |
| `HKLM\...\WindowsUpdate\AU` | `ScheduledInstallTime` | DWORD | `22` | Install at 10:00 PM. |
| `HKLM\...\WindowsUpdate` | `SetComplianceDeadline` | DWORD | `1` | Enables compliance deadlines. |
| `HKLM\...\WindowsUpdate` | `ConfigureDeadlineForQualityUpdates` | DWORD | `7` | Force-install quality updates after 7 days. |
| `HKLM\...\WindowsUpdate` | `ConfigureDeadlineForFeatureUpdates` | DWORD | `7` | Force-install feature updates after 7 days. |
| `HKLM\...\WindowsUpdate` | `ConfigureDeadlineGracePeriod` | DWORD | `0` | No extra grace period after deadline. |

All registry paths above are under `HKLM\Software\Policies\Microsoft\Windows\`.

**Additional policy intent baked into the update-policy backups:**
- Use the intranet Microsoft update service location.
- Do not connect to Windows Update Internet locations.
- Allow signed updates from an intranet update service.
- Enforce automatic restart behavior for scheduled installs.
### GPO 3: WSUS Inbound Allow


**Purpose:** Opens the WSUS server's firewall to accept incoming connections from client machines. Without this, clients would be told to connect to the WSUS server but the server's firewall would block them.

**Linked to:** `Member Servers\WSUS Server` OU. Apply this only to the WSUS server itself. The deployment script creates this OU if it does not exist.

**Firewall rule:**

| Property | Value |
|----------|-------|
| Rule name | WSUS Inbound Allow |
| Direction | Inbound |
| Action | Allow |
| Protocol | TCP (protocol 6) |
| Local ports | 8530, 8531 |
| Profiles | Domain, Private |
| Description | Allows inbound WSUS connections over TCP 8530 (HTTP) and 8531 (HTTPS). |

**Additional setting:**

| Policy | State | What It Does |
|--------|-------|--------------|
| Windows Defender Firewall: Protect all network connections (Domain Profile) | Enabled | Ensures the Windows firewall is turned on. The firewall rule above then pokes the specific holes WSUS needs. You do not want to disable the firewall entirely. |

**What the ports are for:**
- **Port 8530 (HTTP):** The default WSUS communication port. Clients download update metadata and content files over this port.
- **Port 8531 (HTTPS):** The encrypted alternative. Used if you configure WSUS for SSL/TLS (recommended for sensitive environments).

**After deploying this GPO:** The deployment script prompts to move the WSUS server computer object into `Member Servers\WSUS Server` so this GPO applies to it.

### GPO 4: WSUS Outbound Allow

**Purpose:** Opens the firewall on every client machine so they can reach the WSUS server on ports 8530 and 8531. On a hardened network where outbound traffic is blocked by default, clients need an explicit rule allowing them to talk to the WSUS server.

**Linked to:** Three OUs:
- `Domain Controllers`
- `Member Servers`
- `Workstations`

This covers all domain-joined machines. If you have computers in other OUs, you will need to link this GPO to those OUs manually using the Group Policy Management Console (GPMC).

**Firewall rule:**

| Property | Value |
|----------|-------|
| Rule name | WSUS Outbound Allow |
| Direction | Outbound |
| Action | Allow |
| Protocol | TCP (protocol 6) |
| Remote ports | 8530, 8531 |
| Profiles | Domain, Private |
| Description | Allows outbound WSUS connections over TCP 8530 (HTTP) and 8531 (HTTPS). |

**Why this matters:** Many security-hardened environments block outbound connections by default. Without this rule, the Windows Update client on each machine would try to contact the WSUS server and be silently blocked by the local firewall. The client would then report "unable to contact update server" in its logs.

---

## Project Structure

```
GA-WsusManager/
|-- build.ps1                        # Build script (PS2EXE compiler)
|-- dist/                            # Build output (gitignored)
|   |-- GA-WsusManager.exe
|   +-- GA-WsusManager-vX.X.X.zip
|-- Scripts/
|   |-- WsusManagementGui.ps1        # Main GUI application (WPF/XAML)
|   |-- Invoke-WsusManagement.ps1    # CLI for WSUS operations
|   |-- Invoke-WsusMonthlyMaintenance.ps1  # Online sync CLI
|   |-- Install-WsusWithSqlExpress.ps1     # WSUS + SQL installer
|   |-- Invoke-WsusClientCheckIn.ps1       # Force client check-in
|   +-- Set-WsusHttps.ps1                  # HTTPS configuration
|-- Modules/                         # PowerShell modules
|-- Tests/                           # Pester unit tests
|-- DomainController/                # Air-gap GPO deployment
|   |-- Set-WsusGroupPolicy.ps1      # GPO import + link script
|   +-- WSUS GPOs/                   # GPO backup files (4 GPOs)
|-- icons/                           # Window, tray, sidebar, and About page icon assets
|-- .github/workflows/               # CI/CD pipeline
|-- CLAUDE.md                        # Developer documentation
+-- README.md                        # This file
```

---

## Modules

WSUS Manager uses PowerShell modules in the `Modules/` directory. Core modules include:

| Module | Purpose |
|--------|---------|
| `WsusUtilities.psm1` | Logging, admin checks, SQL helpers, path utilities |
| `WsusConfig.psm1` | Centralized configuration, timeouts, health weights, GUI settings |
| `WsusHealth.psm1` | Diagnostics, auto-repair, health score, repair plans/results |
| `WsusDatabase.psm1` | Database size queries, supersession cleanup, index optimization, shrink |
| `WsusPermissions.psm1` | WSUS content ACL validation and repair |
| `WsusServices.psm1` | SQL Server, IIS, and WSUS service control |
| `WsusFirewall.psm1` | Firewall rule creation, testing, and repair |
| `WsusExport.psm1` | Robocopy/content transfer planning and execution |
| `WsusOperationRunner.psm1` | GUI operation lifecycle, child process hosting, timeouts |
| `WsusAutoDetection.psm1` | Server detection, dashboard data, cached health probes |
| `WsusTrending.psm1` | SUSDB growth history and days-until-full estimate |
| `WsusScheduledTask.psm1` | Recurring online sync task creation and status |
| `WsusNotification.psm1` | Toast/balloon/log-only operation notifications |
| `WsusDialogs.psm1` | WPF dialog helpers |
| `AsyncHelpers.psm1` | Runspace and dispatcher helpers |
| `WsusGuiShell.psm1` / `WsusDashboardViewModel.psm1` | GUI-facing dashboard shaping |
| `WsusProvisioning.psm1` | Install/restore path and backup discovery helpers |
| `WsusHostEnvironment.psm1` | Host adapters for diagnostic probes |
| `WsusOperationPlan.psm1` / `WsusOperationCompletion.psm1` | Operation planning and completion details |
| `WsusDiagnosticResult.psm1` / `WsusRepairPlan.psm1` | Structured diagnostic and repair output |
| `WsusProcessHost.psm1` | Process execution wrapper |
| `WsusStartupProbe.psm1` | GUI startup probe result helpers |
| `WsusTestHarness.psm1` / `WsusRepairHarness.psm1` | Test-facing harness helpers |
See `Modules/README.md` for full API documentation and examples.

---

## Build and Test

The project uses PS2EXE to compile PowerShell scripts into a standalone `.exe`.

```powershell
# Full build: tests + code analysis + compile
.\build.ps1

# Build without running tests
.\build.ps1 -SkipTests

# Build without code review (PSScriptAnalyzer)
.\build.ps1 -SkipCodeReview

# Run tests only (no build)
.\build.ps1 -TestOnly

# Run Pester tests directly
Invoke-Pester -Path .\Tests -Output Detailed

# Run code analysis directly
Invoke-ScriptAnalyzer -Path .\Scripts\WsusManagementGui.ps1 -Severity Error,Warning
```

Build output goes to `dist/` as `GA-WsusManager.exe` and `GA-WsusManager-vX.X.X.zip`. The distribution zip includes the EXE, Scripts, Modules, DomainController scripts, branding assets, and documentation.

**CI pipeline** (`.github/workflows/ci.yml` and `.github/workflows/gui-tests.yml`) runs local validation, PSScriptAnalyzer/Pester checks, packaging checks, and GUI smoke tests on the self-hosted Windows runner.

---

## Standard Paths

| Item | Path |
|------|------|
| WSUS content directory | `C:\WSUS\` |
| SQL Server instance | `localhost\SQLEXPRESS` |
| WSUS database | `SUSDB` |
| Log files | `C:\WSUS\Logs\` |
| SQL/SSMS installers (for offline install) | `C:\WSUS\SQLDB\` |
| WSUS HTTP port | 8530 |
| WSUS HTTPS port | 8531 |
| Application settings | `%APPDATA%\WsusManager\settings.json` |
| Operation history | `%APPDATA%\WsusManager\history.json` |
| Database trend data | `%APPDATA%\WsusManager\trends.json` |

**SQL Express limit:** The free edition of SQL Server Express has a 10 GB database size cap. The dashboard monitors this and shows warnings when the database approaches the limit. The trending module estimates how many days until the limit is reached based on historical growth.

---

## Troubleshooting

**"WSUS Not Installed" on the dashboard**
The WSUS Windows Server role is not present. Click Install WSUS to set it up.


**"Content is still downloading" after air-gap restore**
After restoring the database or copying content with Robocopy, run Diagnostics > Reset Content to execute `wsusutil reset`. This tells WSUS to re-verify all content files against the database.

**Client machines not finding the WSUS server**
Verify GPOs are applied: run `gpresult /r` on the client. Check that the WSUS Outbound Allow GPO is linked to the client's OU. Check that the WSUS server firewall allows inbound on ports 8530/8531.

**Database approaching 10 GB limit**
Run a Deep Cleanup from the Database menu. This declines superseded updates, removes obsolete records, rebuilds indexes, and shrinks the database.


**Script not found errors**
Make sure the `Scripts/` and `Modules/` folders are in the same directory as `GA-WsusManager.exe`. If you moved only the EXE, the application cannot find its scripts.

See [CLAUDE.md](CLAUDE.md) for detailed developer documentation, architecture notes, and a full catalog of known GUI issues with solutions.

---

## License

This project is proprietary software developed for GA-ASI internal use.
