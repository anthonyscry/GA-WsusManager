# Requirements: GA-WsusManager v4

**Defined:** 2026-02-19
**Core Value:** Rock-solid stability — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure.

## v1 Requirements

Requirements for initial release. Feature parity with PowerShell v3.8.12 in a compiled C#/.NET 9 single-EXE application.

### Foundation

- [x] **FOUND-01**: Application starts in under 1 second on Windows Server 2019+
- [x] **FOUND-02**: Application runs as single self-contained EXE (no external Scripts/Modules folders)
- [x] **FOUND-03**: Application requires and enforces administrator privileges (UAC manifest)
- [x] **FOUND-04**: Application logs all operations to C:\WSUS\Logs\ with structured logging
- [x] **FOUND-05**: Application handles all errors gracefully with user-friendly error dialogs (no unhandled crashes)

### Dashboard

- [x] **DASH-01**: User sees WSUS health status, database size, sync status, and service states on launch
- [x] **DASH-02**: Dashboard auto-refreshes every 30 seconds with visible refresh indicator
- [x] **DASH-03**: Dashboard shows "Not Installed" status when WSUS is not present on the server
- [x] **DASH-04**: User can toggle between Online and Air-Gap server modes
- [x] **DASH-05**: Dashboard displays DB size with warning when approaching 10GB SQL Express limit

### GUI

- [x] **GUI-01**: Application uses modernized dark theme matching GA branding
- [x] **GUI-02**: User can view operation output in expandable/collapsible log panel
- [x] **GUI-03**: User can toggle live terminal mode to open operations in external PowerShell window
- [x] **GUI-04**: All dialogs close with ESC key
- [x] **GUI-05**: Application renders crisply on high-DPI displays (per-monitor DPI awareness)
- [x] **GUI-06**: User can access Settings dialog to configure application preferences
- [x] **GUI-07**: Settings persist to %APPDATA%\WsusManager\settings.json across sessions

### Diagnostics

- [x] **DIAG-01**: User can run comprehensive health check (services, firewall, permissions, connectivity, database)
- [x] **DIAG-02**: Health check auto-repairs detected issues (restart services, fix firewall rules, fix permissions)
- [x] **DIAG-03**: User sees clear pass/fail reporting for each diagnostic check
- [x] **DIAG-04**: SQL sysadmin permissions are verified before database operations
- [x] **DIAG-05**: User can run content reset (wsusutil reset) to fix air-gap import issues

### Database

- [x] **DB-01**: User can run deep cleanup (6-step pipeline: decline superseded, purge supersession records, delete declined updates, rebuild indexes, update statistics, shrink DB)
- [x] **DB-02**: Deep cleanup shows progress and timing for each step
- [x] **DB-03**: Deep cleanup uses batched deletion (10k/batch for supersession, 100/batch for declined updates)
- [x] **DB-04**: Database shrink retries when blocked by backup operations (3 attempts, 30s delay)
- [x] **DB-05**: User can backup the SUSDB database
- [x] **DB-06**: User can restore SUSDB from a backup file with file picker

### Sync

- [x] **SYNC-01**: User can run Online Sync with profile selection (Full Sync, Quick Sync, Sync Only)
- [x] **SYNC-02**: Sync shows progress with phase and percentage updates
- [x] **SYNC-03**: Definition Updates are auto-approved with configurable safety threshold (max 200)
- [x] **SYNC-04**: Approved classifications include Critical, Security, Update Rollups, Service Packs, Updates, Definition Updates
- [x] **SYNC-05**: Upgrades classification is excluded from auto-approval

### Export/Import

- [x] **XFER-01**: User can export WSUS data to media with full export path selection
- [x] **XFER-02**: User can perform differential export (files from last N days) with separate path
- [x] **XFER-03**: User can import WSUS data from external media (source and destination path selection)
- [x] **XFER-04**: Export paths are optional — if not specified, export step is skipped
- [x] **XFER-05**: Pre-flight checks validate access to export/import paths before starting

### Installation

- [x] **INST-01**: User can install WSUS with SQL Server Express through guided wizard
- [x] **INST-02**: Installation wizard runs non-interactively when launched from GUI
- [x] **INST-03**: Operations are disabled when WSUS is not installed (only Install button enabled)

### Scheduling

- [x] **SCHED-01**: User can create Windows scheduled task for automated maintenance
- [x] **SCHED-02**: Scheduled task supports domain credentials (username/password)
- [x] **SCHED-03**: Scheduled task runs whether user is logged on or not
- [x] **SCHED-04**: User can select maintenance profile and schedule (day 1-31)

### Service Management

- [x] **SVC-01**: User can start/stop SQL Server, WSUS, and IIS services
- [x] **SVC-02**: Service status is monitored and displayed in real-time
- [x] **SVC-03**: Service management handles dependency ordering (SQL must run before WSUS)

### Firewall

- [x] **FW-01**: Application manages WSUS firewall rules for ports 8530 and 8531
- [x] **FW-02**: Firewall rules are checked and auto-repaired during diagnostics

### Permissions

- [x] **PERM-01**: Application checks and repairs directory permissions for WSUS content paths
- [x] **PERM-02**: Application checks SQL login permissions

### GPO

- [x] **GPO-01**: User can copy GPO deployment files to C:\WSUS\WSUS GPO
- [x] **GPO-02**: User sees instructions for domain controller admin after GPO copy

### Operations Infrastructure

- [x] **OPS-01**: All operations can be cancelled by the user
- [x] **OPS-02**: Only one operation can run at a time (concurrent execution blocked)
- [x] **OPS-03**: All operation buttons are disabled during operation execution
- [x] **OPS-04**: Buttons re-enable on operation completion, error, or cancellation

### Build & Distribution

- [x] **BUILD-01**: CI/CD pipeline builds single-file EXE on push/PR via GitHub Actions
- [x] **BUILD-02**: EXE includes version info, company name, and product name metadata
- [x] **BUILD-03**: Release automation creates GitHub release with EXE artifact
- [x] **BUILD-04**: Comprehensive test suite with xUnit (equivalent coverage to 323 Pester tests)

## v2 Requirements

Deferred to future release. Not in current roadmap.

### Enhanced Monitoring

- **MON-01**: Compliance summary from SUSDB (client count, percentage patched)
- **MON-02**: Historical trend charts for DB size and sync status

### Advanced Operations

- **ADV-01**: Batch operations across multiple WSUS update groups
- **ADV-02**: Custom SQL query runner for SUSDB diagnostics

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-server management | Transforms complexity class; current tool is single-server |
| Update approval UI within tool | Re-implementing native WSUS console is massive scope with no gain |
| Third-party patching | Completely different API surface |
| Web-based or mobile interface | Desktop-only for server administration |
| Linux/macOS support | WSUS is Windows-only |
| Server 2016 support | Dropped to target modern .NET runtime |
| IIS app pool optimization | Overkill for small air-gapped systems |
| PowerShell backward compatibility | Clean break from PS codebase |
| Building on C# POC | Starting fresh per user preference |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 | Complete |
| FOUND-02 | Phase 1 | Complete |
| FOUND-03 | Phase 1 | Complete |
| FOUND-04 | Phase 1 | Complete |
| FOUND-05 | Phase 1 | Complete |
| GUI-05 | Phase 1 | Complete |
| DASH-01 | Phase 2 | Complete |
| DASH-02 | Phase 2 | Complete |
| DASH-03 | Phase 2 | Complete |
| DASH-04 | Phase 2 | Complete |
| DASH-05 | Phase 2 | Complete |
| GUI-01 | Phase 2 | Complete |
| GUI-02 | Phase 2 | Complete |
| GUI-03 | Phase 2 | Complete |
| GUI-04 | Phase 2 | Complete |
| GUI-06 | Phase 2 | Complete |
| GUI-07 | Phase 2 | Complete |
| OPS-01 | Phase 2 | Complete |
| OPS-02 | Phase 2 | Complete |
| OPS-03 | Phase 2 | Complete |
| OPS-04 | Phase 2 | Complete |
| DIAG-01 | Phase 3 | Complete |
| DIAG-02 | Phase 3 | Complete |
| DIAG-03 | Phase 3 | Complete |
| DIAG-04 | Phase 3 | Complete |
| DIAG-05 | Phase 3 | Complete |
| SVC-01 | Phase 3 | Complete |
| SVC-02 | Phase 3 | Complete |
| SVC-03 | Phase 3 | Complete |
| FW-01 | Phase 3 | Complete |
| FW-02 | Phase 3 | Complete |
| PERM-01 | Phase 3 | Complete |
| PERM-02 | Phase 3 | Complete |
| DB-01 | Phase 4 | Complete |
| DB-02 | Phase 4 | Complete |
| DB-03 | Phase 4 | Complete |
| DB-04 | Phase 4 | Complete |
| DB-05 | Phase 4 | Complete |
| DB-06 | Phase 4 | Complete |
| SYNC-01 | Phase 5 | Complete |
| SYNC-02 | Phase 5 | Complete |
| SYNC-03 | Phase 5 | Complete |
| SYNC-04 | Phase 5 | Complete |
| SYNC-05 | Phase 5 | Complete |
| XFER-01 | Phase 5 | Complete |
| XFER-02 | Phase 5 | Complete |
| XFER-03 | Phase 5 | Complete |
| XFER-04 | Phase 5 | Complete |
| XFER-05 | Phase 5 | Complete |
| INST-01 | Phase 6 | Complete |
| INST-02 | Phase 6 | Complete |
| INST-03 | Phase 6 | Complete |
| SCHED-01 | Phase 6 | Complete |
| SCHED-02 | Phase 6 | Complete |
| SCHED-03 | Phase 6 | Complete |
| SCHED-04 | Phase 6 | Complete |
| GPO-01 | Phase 6 | Complete |
| GPO-02 | Phase 6 | Complete |
| BUILD-01 | Phase 7 | Complete |
| BUILD-02 | Phase 7 | Complete |
| BUILD-03 | Phase 7 | Complete |
| BUILD-04 | Phase 7 | Complete |

**Coverage:**
- v1 requirements: 62 total
- Mapped to phases: 62
- Unmapped: 0

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-20 — all v1 requirements complete*
