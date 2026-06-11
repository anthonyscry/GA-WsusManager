# Phase 5: WSUS Operations - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Administrators can run Online Sync with profile selection (Full Sync, Quick Sync, Sync Only), export WSUS data to media (full and differential with robocopy), import from USB or network share, and trigger content reset after air-gap import. This covers the complete air-gap maintenance workflow. Installation, scheduling, and GPO deployment are Phase 6.

</domain>

<decisions>
## Implementation Decisions

### Sync Profile Selection
- Three profiles matching legacy behavior: Full Sync, Quick Sync, Sync Only
- Full Sync: synchronize + decline superseded + approve updates
- Quick Sync: synchronize + approve updates (skip decline step)
- Sync Only: just synchronize metadata, no approval changes
- Profile selection via a WPF dialog before sync starts (radio buttons)
- Sync progress reported with phase name and percentage in the log panel

### Update Auto-Approval
- After sync, auto-approve updates matching 6 classifications: Critical, Security, Update Rollups, Service Packs, Updates, Definition Updates
- Upgrades classification is never auto-approved (requires manual review)
- Safety threshold: max 200 updates auto-approved per run — skip approval if count exceeds threshold
- Superseded updates are declined before approval runs (prevents accumulation)

### WSUS API Access
- Use `Microsoft.UpdateServices.Administration` assembly (ships with WSUS role) for native WSUS server access
- Connect via `AdminProxy.GetUpdateServer("localhost", false, 8530)` for HTTP or port 8531 for HTTPS
- This avoids shelling out to PowerShell and gives type-safe access to IUpdateServer, IUpdate, IUpdateApproval
- Fall back to process-based wsusutil.exe calls only for operations not exposed via the API (e.g., content reset — already in Phase 3)

### Export/Import Dialog Design
- Combined Transfer dialog with direction selector (Export / Import) matching legacy UX
- Export mode shows: Full Export Path (browse), Differential Export Path (browse), Export Days (numeric, default 30)
- Import mode shows: Source Path (browse — e.g., USB drive), Destination Path (browse — default C:\WSUS)
- All export paths are optional — if both blank, export step is skipped
- Pre-flight checks validate path accessibility before any file operations begin

### Export Implementation
- Use robocopy via Process.Start for content copy (multi-threaded, resumable, standard Windows tool)
- Robocopy options: /E /XO /MT:16 /R:2 /W:5 — matching legacy WsusExport.psm1 patterns
- Exclude: *.bak, *.log files; Logs/, SQLDB/, Backup/ directories
- Full export: all content files to full export path
- Differential export: files modified within N days to differential path with Year/Month archive structure
- Database backup file (.bak) optionally included in export

### Import Implementation
- Copy content from source (USB/network) to destination (C:\WSUS) using robocopy
- Pre-flight: validate source path exists, destination path is writable, sufficient disk space
- After import completes, prompt user to run Content Reset (wsusutil reset) — leverages existing IContentResetService from Phase 3
- No interactive prompts during operation — all parameters collected via dialog before starting

### Claude's Discretion
- Exact dialog layout dimensions and spacing
- Progress reporting granularity during robocopy operations
- Whether to show file count/size estimates before starting export/import
- Error recovery strategy for partial robocopy failures
- Whether sync progress polling interval is 1s, 2s, or 5s

</decisions>

<specifics>
## Specific Ideas

- Legacy PowerShell uses `Invoke-WsusRobocopy` wrapper with standardized options — C# service should mirror the same robocopy argument construction
- The Transfer dialog in legacy has source and destination browse buttons with folder browser dialogs — same UX in C#
- Content reset (wsusutil reset) is already implemented as IContentResetService in Phase 3 — Phase 5 just needs to offer it as a post-import action, not reimplement it
- Sync profiles map directly to the legacy MaintenanceProfile parameter: "Full" / "Quick" / "SyncOnly"
- The Microsoft.UpdateServices.Administration DLL is a reference assembly (not NuGet) — it lives on machines with the WSUS role installed at a well-known path

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-wsus-operations*
*Context gathered: 2026-02-19*
