# Phase 6: Installation and Scheduling - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Administrators can install WSUS with SQL Server Express through a guided wizard (no console prompts), create Windows scheduled tasks for automated maintenance with domain credentials, and copy GPO deployment files with step-by-step instructions. WSUS operation buttons are disabled when WSUS is not installed. Testing and CI/CD are Phase 7.

</domain>

<decisions>
## Implementation Decisions

### Installation Wizard Dialog
- Single multi-section dialog (not a multi-step wizard) — matching existing dialog patterns in the app
- Fields: Installer Path (browse, default C:\WSUS\SQLDB), SA Username (text, default "sa"), SA Password (password box)
- Pre-flight validation: check installer path exists, required EXE present (SQLEXPRADV_x64_ENU.exe), password not empty
- Installation runs via Process.Start calling the legacy `Install-WsusWithSqlExpress.ps1` with `-NonInteractive -InstallerPath -SaUsername -SaPassword` flags
- This is the one operation that deliberately shells out to PowerShell — the install script is complex (SQL + WSUS role + IIS config) and re-implementing in C# provides no benefit
- Output streams to the log panel in real-time via async process output reading
- On completion, refresh dashboard and re-enable all operation buttons

### WSUS Not-Installed State
- On startup, detect WSUS installation by checking if the WsusService (wsusservice) exists
- When not installed: all operation buttons except "Install WSUS" are disabled with 50% opacity
- Dashboard cards show "Not Installed" / "N/A" status text
- Log panel displays a message: "WSUS is not installed. Use Install WSUS to set up the server."
- After successful install, automatically re-check and enable all buttons

### Scheduled Task Dialog
- Single dialog with all fields visible (matching legacy Schedule Task dialog, ~540px height)
- Fields: Task Name (text, default "WSUS Monthly Maintenance"), Schedule type (combo: Monthly/Weekly/Daily), Day of Month (1-31, default 15), Day of Week (combo, default Saturday), Time (text HH:mm, default "02:00"), Maintenance Profile (combo: Full/Quick/SyncOnly, default Full), Username (text, default ".\dod_admin"), Password (password box)
- Day of Month field visible only when Monthly selected; Day of Week visible only when Weekly
- Uses Windows Task Scheduler COM API (`Microsoft.Win32.TaskScheduler` or direct `schtasks.exe` / PowerShell `Register-ScheduledTask`) — Claude decides best approach
- Task runs with RunLevel Highest, runs whether user is logged on or not
- Existing task with same name is replaced (unregister + register)
- 4-hour execution time limit matching legacy behavior

### GPO Deployment
- Single button "Create GPO" in Setup menu area
- Copies files from embedded resource or app directory `DomainController/` to `C:\WSUS\WSUS GPO\`
- After copy, shows a message dialog with step-by-step instructions for the DC admin:
  1. Copy the GPO folder to the Domain Controller
  2. Run `Set-WsusGroupPolicy.ps1` on the DC
  3. Force client check-in: `gpupdate /force` and `wuauclt /detectnow`
- If DomainController/ source files not found, show error with expected path

### Claude's Discretion
- Whether to use COM TaskScheduler API or shell out to PowerShell for scheduled task creation
- Exact dialog dimensions and field spacing
- Whether install progress shows a progress bar or just streaming log output
- Error message wording for validation failures
- Whether the GPO instructions dialog is a simple MessageBox or a custom dialog with copyable text

</decisions>

<specifics>
## Specific Ideas

- Legacy install script already has `-NonInteractive` mode — C# just needs to collect parameters via dialog and pass them through
- The install script requires `SQLEXPRADV_x64_ENU.exe` and optionally `SSMS-Setup-ENU.exe` in the installer path
- Scheduled task legacy uses `New-ScheduledTaskAction` with PowerShell.exe calling `Invoke-WsusMonthlyMaintenance.ps1 -Unattended -Profile {profile}`
- For the C# version, the scheduled task should call the C# EXE with a CLI flag (e.g., `WsusManager.exe --maintenance --profile Full --unattended`) once CLI support exists, but for now can call the PowerShell script
- GPO source files: `DomainController/Set-WsusGroupPolicy.ps1` and `DomainController/WSUS GPOs/` directory

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-installation-and-scheduling*
*Context gathered: 2026-02-20*
