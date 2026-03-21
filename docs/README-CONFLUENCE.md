h1. WSUS Manager

*Version:* 4.0.2
*Author:* Tony Tran, ISSO, GA-ASI

WSUS Manager is a PowerShell GUI application for managing Windows Server Update Services (WSUS) on air-gapped networks. It handles the entire lifecycle of keeping Windows machines patched when they cannot reach the internet: installing WSUS and SQL Server Express, syncing updates on a connected server, transferring them to a disconnected network via USB, importing them, and pushing updates out to client machines through Group Policy.

----

{toc:printable=true|style=square|maxLevel=3|indent=20px|minLevel=2|class=bigpink|exclude=[1]}

----

h2. What is WSUS?

Windows Server Update Services (WSUS) is a Microsoft tool that lets an administrator approve and distribute Windows updates from a central server instead of having every computer download them individually from the internet. This is important in two scenarios:

# *Controlled environments* -- you want to test updates before rolling them out.
# *Air-gapped networks* -- your computers have no internet access at all. Updates must be physically carried in on a USB drive.

WSUS stores its data in a SQL Server Express database (called SUSDB) and its update files in a content directory on disk. WSUS Manager automates the setup, maintenance, and monitoring of both.

----

h2. Quick Start

# Go to the [Releases|../../releases] page.
# Download {{WsusManager-vX.X.X.zip}}.
# Extract the full archive to a folder (for example, {{C:\WsusManager\}}).
# Right-click {{WsusManager.exe}} and select *Run as Administrator*.

{warning}The EXE requires the {{Scripts/}} and {{Modules/}} folders to be in the same directory. Do not move the EXE without also moving those folders.{warning}

----

h2. Requirements

||Requirement||Details||
|OS|Windows 10/11 or Windows Server 2019/2022|
|PowerShell|5.1 or later (ships with Windows)|
|Privileges|Administrator (right-click, Run as Administrator)|
|WSUS role|Installed by the setup workflow if not present|
|SQL Server|SQL Server Express 2022 (installed by the setup workflow)|
|Disk space|At least 40 GB free on the WSUS content drive|

----

h2. Features

h3. Dashboard

* Auto-refreshing dashboard (every 30 seconds) showing service status, disk space, database size, and scheduled task status.
* Health Score (0-100) with color-coded grade: Green (80+), Yellow (50-79), Red (below 50).
* Database size trending with days-until-full estimate using linear regression. Alerts when approaching the 10 GB SQL Express limit.
* Last successful sync timestamp.

h3. Server Management

* One-click WSUS + SQL Server Express installation with guided setup.
* Unified Diagnostics (health check + auto-repair in a single operation).
* Database backup, restore, and deep cleanup (6-step maintenance including index rebuild and database shrink).
* Online Sync with Full, Quick, and Sync Only profiles.
* Scheduled task creation for recurring sync operations.
* HTTPS configuration via {{Set-WsusHttps.ps1}}.

h3. Air-Gap Support

* Server Mode toggle: Online vs Air-Gap.
* Export updates and content to USB for transfer to disconnected networks.
* Import updates and content from USB on the air-gapped server.
* "Create USB Package" workflow with transfer manifest and checksums.
* "Reset Content" button to fix content download status after import.

h3. Client Deployment

* GPO deployment scripts for air-gapped domains.
* Client check-in script to force update detection.
* "Create GPO" button copies GPO files and shows deployment instructions.

h3. GUI Features

* Dark theme with light theme toggle in Settings (reserved).
* Startup splash screen with progress bar.
* Keyboard shortcuts: Ctrl+D (Diagnostics), Ctrl+S (Sync), Ctrl+H (History), Ctrl+R or F5 (Refresh Dashboard).
* Right-click context menu on log panel: Copy All / Save to File.
* Operation history view showing last 50 operations.
* Desktop notifications on operation completion (toast, balloon, or log-only fallback).
* Live Terminal Mode to open operations in an external PowerShell window.
* DPI-aware rendering on high-DPI displays.

----

h2. Workflows

h3. Setting Up a New WSUS Server from Scratch

This workflow installs WSUS and SQL Server Express on a fresh Windows Server.

# *Prepare the server.* Log in as an Administrator. Make sure you have at least 40 GB free on the drive where WSUS content will be stored (default: {{C:\WSUS\}}).
# *Copy the application.* Extract the {{WsusManager-vX.X.X.zip}} archive to a folder such as {{C:\WsusManager\}}.
# *Place the SQL installer.* If the server has no internet access, download SQL Server Express 2022 and SQL Server Management Studio (SSMS) on a connected machine and copy the installers to {{C:\WSUS\SQLDB\}} on the target server. The install script will look for them there.
# *Launch WSUS Manager.* Right-click {{WsusManager.exe}} and select Run as Administrator. The dashboard will show "WSUS Not Installed" -- this is expected.
# *Run Install.* Click the *Install WSUS* button. The application will:
#* Prompt for the content directory (default: {{C:\WSUS\}}).
#* Install SQL Server Express 2022 if not already present.
#* Install the WSUS Windows Server role.
#* Run post-installation configuration.
#* Set up firewall rules and directory permissions.
# *Verify.* Once installation completes, the dashboard should show green status for SQL Server, IIS, and WSUS services.
# *Deploy GPOs.* If this is an air-gapped server, follow the [Deploying GPOs to Clients|#deploying-gpos-to-clients] workflow to tell client machines where to find the WSUS server.

h3. Monthly Sync Workflow (Online Server)

Run this monthly on the internet-connected WSUS server to download the latest updates from Microsoft.

# *Launch WSUS Manager* as Administrator.
# *Click Online Sync* in the navigation panel (or use the Quick Action button).
# *Choose a sync profile:*
#* *Full Sync* -- Decline superseded updates, sync with Microsoft, approve new updates, clean up the database, and export.
#* *Quick Sync* -- Sync and approve only (skip cleanup).
#* *Sync Only* -- Just sync with Microsoft, no approvals or cleanup.
# *Set the export path* (optional). If you plan to transfer updates to an air-gapped network, enter a destination folder (for example, a USB drive path like {{E:\WSUS-Export}}). If you leave this blank, the sync runs without exporting.
# *Click OK.* The operation runs in the log panel. A Full Sync typically takes 30-120 minutes depending on how many updates are available.
# *Check the dashboard.* After the sync completes, the Last Sync timestamp should update and the database size may increase.

*Tip:* To automate this, click *Schedule* to create a Windows Scheduled Task that runs the sync monthly.

h3. Air-Gap Transfer Workflow

This is how you move updates from an internet-connected WSUS server to an air-gapped WSUS server.

*On the online server:*

# Run an Online Sync (see above) with the export path set to a USB drive or staging folder.
# The sync will export the WSUS metadata and content files to the destination. Alternatively, click *Transfer > Export* and select the source (your WSUS content folder, default {{C:\WSUS\}}) and destination (USB drive).
# Safely eject the USB drive.

*On the air-gapped server:*

# Plug in the USB drive.
# Launch WSUS Manager as Administrator.
# Switch to *Air-Gap* mode using the Server Mode toggle (if not already set).
# Click *Transfer > Import*. Select the USB drive as the source and {{C:\WSUS\}} as the destination.
# The import copies content files and imports the WSUS metadata.
# After import completes, click *Reset Content* (under Diagnostics) to run {{wsusutil reset}}. This tells WSUS to re-verify all content files against the database. Without this step, some updates may show "still downloading" even though the files are present.
# Run *Diagnostics* to verify everything is healthy.

*Tip:* Use the "Create USB Package" button to generate a transfer manifest with checksums for each file, which helps verify nothing was corrupted during the physical transfer.

h3. Deploying GPOs to Clients

Group Policy Objects (GPOs) tell Windows client machines where the WSUS server is and how to apply updates. This is required on air-gapped networks because clients cannot reach Microsoft's update servers.

{warning}These GPOs are designed for AIR-GAPPED networks only. Deploying them on internet-connected systems will redirect all Windows Update traffic to the internal WSUS server and prevent machines from getting updates directly from Microsoft.{warning}

*Prerequisites:*

* A Domain Controller with GPMC (Group Policy Management Console) installed.
* The {{DomainController/}} folder from the WSUS Manager distribution.

*Steps:*

# Copy the {{DomainController/}} folder to the Domain Controller.
# Open an elevated PowerShell prompt on the Domain Controller.
# Run the GPO deployment script:
{code:language=powershell}
.\Set-WsusGroupPolicy.ps1
{code}
# When prompted, enter the WSUS server hostname (just the name, not the full URL). For example, if your WSUS server is called {{WSUS01}}, type {{WSUS01}}. The script builds the URL {{http://WSUS01:8530}} automatically.
# The script will:
#* Auto-detect your domain.
#* Delete and reimport three GPOs from the {{WSUS GPOs/}} backup folder (removes stale registry values).
#* Create any needed OUs (Member Servers, WSUS Server, Workstations).
#* Link each GPO to the correct OUs.
#* Replace placeholder WSUS URLs with your server.
#* Push a Group Policy update to all domain computers via schtasks RPC (no WinRM required).
# *Move your WSUS server's computer object* in Active Directory to the {{Member Servers\WSUS Server}} OU. This ensures the WSUS server gets the inbound firewall GPO.
# *Verify on a client machine:*
{code:language=powershell}
gpresult /r | findstr WSUS
{code}
You should see the three WSUS GPOs listed under "Applied Group Policy Objects."

----

h2. GPO Reference

The {{DomainController/WSUS GPOs/}} folder contains three pre-configured Group Policy Objects. The deployment script ({{Set-WsusGroupPolicy.ps1}}) imports these and configures them for your environment. Below is a detailed explanation of what each GPO does, which computers it applies to, and what registry keys or firewall rules it sets.

{warning}These GPOs are designed for AIR-GAPPED networks only. Deploying them on internet-connected systems will redirect all Windows Update traffic to the internal WSUS server and prevent machines from getting updates directly from Microsoft.{warning}

h3. GPO 1: WSUS Update Policy

*Purpose:* Tells every computer in the domain to get its updates from your internal WSUS server instead of Microsoft's internet servers. Also controls the update schedule and deadline behavior.

*Linked to:* Domain root (applies to all computers in the domain).

*Registry keys set by the deployment script:*

||Registry Path||Value Name||Type||Value||What It Does||
|{{HKLM\...\WindowsUpdate}}|WUServer|String|{{http://WSUS01:8530}}|The URL of your WSUS server. Clients connect here to check for updates. The deployment script replaces this with whatever hostname you provide.|
|{{HKLM\...\WindowsUpdate}}|WUStatusServer|String|{{http://WSUS01:8530}}|Where clients report their update status back to. Usually the same server.|
|{{HKLM\...\WindowsUpdate\AU}}|UseWUServer|DWORD|1|The master switch. Value 1 means "use the intranet WSUS server" instead of Microsoft's servers. If this is 0 or missing, the WUServer setting is ignored.|
|{{HKLM\...\WindowsUpdate\AU}}|AUOptions|DWORD|4|How updates are handled: 4 means "auto-download and install on the schedule below." Other options are 2 (notify before download) and 3 (download but ask before install).|
|{{HKLM\...\WindowsUpdate\AU}}|ScheduledInstallDay|DWORD|0|Which day to install updates. 0 means every day. Values 1-7 mean Sunday through Saturday.|
|{{HKLM\...\WindowsUpdate\AU}}|ScheduledInstallTime|DWORD|22|The hour (in 24-hour format) to install updates. 22 means 10:00 PM.|
|{{HKLM\...\WindowsUpdate}}|SetComplianceDeadline|DWORD|1|Enables compliance deadlines. When set to 1, Windows will force-install updates after the deadline passes, even if the user keeps postponing.|
|{{HKLM\...\WindowsUpdate}}|ConfigureDeadlineForQualityUpdates|DWORD|7|Days until quality updates (security patches, bug fixes) are force-installed. After 7 days, the machine will install and restart automatically.|
|{{HKLM\...\WindowsUpdate}}|ConfigureDeadlineForFeatureUpdates|DWORD|7|Days until feature updates are force-installed. Same 7-day deadline.|
|{{HKLM\...\WindowsUpdate}}|ConfigureDeadlineGracePeriod|DWORD|0|Extra grace period after the deadline before the machine restarts. 0 means no extra grace -- restart happens immediately after the deadline.|

All registry paths above are under {{HKLM\Software\Policies\Microsoft\Windows\}}.

*Additional policies baked into the GPO backup:*

||Policy Name||State||What It Does||
|Specify intranet Microsoft update service location|Enabled|Points clients to the WSUS server for both update detection and status reporting.|
|Configure Automatic Updates|Enabled (option 4)|Auto-download and install on schedule (every day at the time specified above).|
|Do not connect to any Windows Update Internet locations|Enabled|Blocks the client from ever reaching out to Microsoft's public update servers. Essential for air-gapped networks so clients do not stall trying to reach the internet.|
|Allow Automatic Updates immediate installation|Enabled|Updates that do not require a restart are installed immediately after download.|
|Allow signed updates from an intranet update service|Enabled|Accepts updates signed by certificates in the local Trusted Publishers store, not just Microsoft-signed updates. Useful if you publish custom packages through WSUS.|
|Always automatically restart at the scheduled time|Enabled (15 min)|After installing updates that need a restart, give the user a 15-minute warning, then restart automatically.|
|Enabling Windows Update Power Management|Enabled|Wakes the computer from sleep to install scheduled updates.|
|Remove access to "Pause updates" feature|Enabled|Prevents users from pausing updates through the Settings app. On an air-gapped network you want updates applied promptly since they have already been vetted.|
|Allow non-administrators to receive update notifications|Disabled|Only administrators see update notifications. Standard users are not prompted.|
|Automatic Updates detection frequency|Disabled|Uses the default 22-hour check interval rather than a custom one.|
|Do not display "Install Updates and Shut Down" option|Disabled|Keeps the "Install Updates and Shut Down" option visible in the shutdown dialog so users can choose to install pending updates when shutting down.|

h3. GPO 2: WSUS Inbound Allow

*Purpose:* Opens the WSUS server's firewall to accept incoming connections from client machines. Without this, clients would be told to connect to the WSUS server but the server's firewall would block them.

*Linked to:* {{Member Servers\WSUS Server}} OU. Apply this only to the WSUS server itself. The deployment script creates this OU if it does not exist.

*Firewall rule:*

||Property||Value||
|Rule name|WSUS Inbound Allow|
|Direction|Inbound|
|Action|Allow|
|Protocol|TCP (protocol 6)|
|Local ports|8530, 8531|
|Profiles|Domain, Private|
|Description|Allows inbound WSUS connections over TCP 8530 (HTTP) and 8531 (HTTPS).|

*Additional setting:*

||Policy||State||What It Does||
|Windows Defender Firewall: Protect all network connections (Domain Profile)|Enabled|Ensures the Windows firewall is turned on. The firewall rule above then pokes the specific holes WSUS needs. You do not want to disable the firewall entirely.|

*What the ports are for:*
* *Port 8530 (HTTP):* The default WSUS communication port. Clients download update metadata and content files over this port.
* *Port 8531 (HTTPS):* The encrypted alternative. Used if you configure WSUS for SSL/TLS (recommended for sensitive environments).

*After deploying this GPO:* Move your WSUS server's computer object in Active Directory into the {{Member Servers\WSUS Server}} OU so this GPO applies to it.

h3. GPO 3: WSUS Outbound Allow

*Purpose:* Opens the firewall on every client machine so they can reach the WSUS server on ports 8530 and 8531. On a hardened network where outbound traffic is blocked by default, clients need an explicit rule allowing them to talk to the WSUS server.

*Linked to:* Three OUs:
* {{Domain Controllers}}
* {{Member Servers}}
* {{Workstations}}

This covers all domain-joined machines. If you have computers in other OUs, you will need to link this GPO to those OUs manually using the Group Policy Management Console (GPMC).

*Firewall rule:*

||Property||Value||
|Rule name|WSUS Outbound Allow|
|Direction|Outbound|
|Action|Allow|
|Protocol|TCP (protocol 6)|
|Remote ports|8530, 8531|
|Profiles|Domain, Private|
|Description|Allows outbound WSUS connections over TCP 8530 (HTTP) and 8531 (HTTPS).|

*Why this matters:* Many security-hardened environments block outbound connections by default. Without this rule, the Windows Update client on each machine would try to contact the WSUS server and be silently blocked by the local firewall. The client would then report "unable to contact update server" in its logs.

----

h2. Project Structure

{code}
GA-WsusManager/
|-- build.ps1                        # Build script (PS2EXE compiler)
|-- dist/                            # Build output (gitignored)
|   |-- WsusManager.exe
|   +-- WsusManager-vX.X.X.zip
|-- Scripts/
|   |-- WsusManagementGui.ps1        # Main GUI application (WPF/XAML)
|   |-- Invoke-WsusManagement.ps1    # CLI for WSUS operations
|   |-- Invoke-WsusMonthlyMaintenance.ps1  # Online sync CLI
|   |-- Install-WsusWithSqlExpress.ps1     # WSUS + SQL installer
|   |-- Invoke-WsusClientCheckIn.ps1       # Force client check-in
|   +-- Set-WsusHttps.ps1                  # HTTPS configuration
|-- Modules/                         # 16 PowerShell modules
|-- Tests/                           # Pester unit tests
|-- DomainController/                # Air-gap GPO deployment
|   |-- Set-WsusGroupPolicy.ps1      # GPO import + link script
|   +-- WSUS GPOs/                   # GPO backup files (3 GPOs)
|-- .github/workflows/               # CI/CD pipeline
|-- CLAUDE.md                        # Developer documentation
+-- README.md                        # Full documentation
{code}

----

h2. Modules

WSUS Manager uses 16 PowerShell modules in the {{Modules/}} directory:

||Module||Purpose||
|{{WsusUtilities.psm1}}|Logging, color output, admin checks, SQL helpers, path utilities|
|{{WsusDatabase.psm1}}|Database size queries, supersession cleanup, index optimization, shrink|
|{{WsusHealth.psm1}}|Health checks, auto-repair, health score (0-100 weighted composite)|
|{{WsusServices.psm1}}|Start/stop/restart for SQL Server, IIS, and WSUS services|
|{{WsusFirewall.psm1}}|Firewall rule creation, testing, and repair|
|{{WsusPermissions.psm1}}|Content directory permission management|
|{{WsusConfig.psm1}}|Centralized configuration, timeouts, health weights, GUI settings|
|{{WsusExport.psm1}}|Robocopy wrapper, content export for air-gap transfer|
|{{WsusScheduledTask.psm1}}|Windows Scheduled Task creation and management|
|{{WsusAutoDetection.psm1}}|Server detection, dashboard data, 30-second TTL cache, auto-recovery|
|{{AsyncHelpers.psm1}}|Runspace pool management, async execution, UI thread dispatch|
|{{WsusDialogs.psm1}}|Dialog factory for WPF (dark-themed window shell, folder browser)|
|{{WsusOperationRunner.psm1}}|Unified operation lifecycle (start/stop/complete), timeout watchdog|
|{{WsusHistory.psm1}}|Operation history (JSON at {{%APPDATA%\WsusManager\history.json}})|
|{{WsusNotification.psm1}}|Toast/balloon notifications on operation completion|
|{{WsusTrending.psm1}}|Database size trending with linear regression, days-until-full estimate|

----

h2. Build and Test

The project uses PS2EXE to compile PowerShell scripts into a standalone {{.exe}}.

{code:language=powershell}
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
{code}

Build output goes to {{dist/}} as {{WsusManager.exe}} and {{WsusManager-vX.X.X.zip}}. The distribution zip includes the EXE, Scripts, Modules, DomainController scripts, branding assets, and documentation.

*CI pipeline* ({{.github/workflows/build.yml}}) runs PSScriptAnalyzer, Pester tests, PS2EXE compilation, EXE validation (PE header, 64-bit architecture, version info), and startup benchmarks on every push and pull request.

----

h2. Standard Paths

||Item||Path||
|WSUS content directory|{{C:\WSUS\}}|
|SQL Server instance|{{localhost\SQLEXPRESS}}|
|WSUS database|{{SUSDB}}|
|Log files|{{C:\WSUS\Logs\}}|
|SQL/SSMS installers (for offline install)|{{C:\WSUS\SQLDB\}}|
|WSUS HTTP port|8530|
|WSUS HTTPS port|8531|
|Application settings|{{%APPDATA%\WsusManager\settings.json}}|
|Operation history|{{%APPDATA%\WsusManager\history.json}}|
|Database trend data|{{%APPDATA%\WsusManager\trending.json}}|

*SQL Express limit:* The free edition of SQL Server Express has a 10 GB database size cap. The dashboard monitors this and shows warnings when the database approaches the limit. The trending module estimates how many days until the limit is reached based on historical growth.

----

h2. Troubleshooting

*"WSUS Not Installed" on the dashboard*
The WSUS Windows Server role is not present. Click Install WSUS to set it up.

*Operations show a blank window before a dialog appears*
This is a known GUI pattern issue. If you see it, the operation should still work -- just wait for the dialog to appear.

*"Content is still downloading" after air-gap import*
After importing updates from USB, run Diagnostics > Reset Content to execute {{wsusutil reset}}. This tells WSUS to re-verify all content files against the database.

*Client machines not finding the WSUS server*
Verify GPOs are applied: run {{gpresult /r}} on the client. Check that the WSUS Outbound Allow GPO is linked to the client's OU. Check that the WSUS server firewall allows inbound on ports 8530/8531.

*Database approaching 10 GB limit*
Run a Deep Cleanup from the Database menu. This declines superseded updates, removes obsolete records, rebuilds indexes, and shrinks the database.

*Buttons stay greyed out after an operation finishes*
Close and reopen WSUS Manager. This can happen if an operation exits unexpectedly without resetting the operation-running flag.

*Script not found errors*
Make sure the {{Scripts/}} and {{Modules/}} folders are in the same directory as {{WsusManager.exe}}. If you moved only the EXE, the application cannot find its scripts.

See [CLAUDE.md] for detailed developer documentation, architecture notes, and a full catalog of known GUI issues with solutions.

----

h2. License

This project is proprietary software developed for GA-ASI internal use.
