# Roadmap: GA-WsusManager v4

## Overview

A ground-up C# rewrite of GA-WsusManager, delivering a single-file EXE with zero threading bugs and sub-second startup. The rewrite progresses from compilable foundation through operational feature parity with v3.8.12, ending with a validated distribution pipeline. Every phase delivers a coherent, verifiable capability — each one builds on the last and unblocks the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - Compilable solution with DI wiring, async operation pattern, single-file publish, UAC manifest, and structured logging (completed 2026-02-19)
- [x] **Phase 2: Application Shell and Dashboard** - Working windowed application with dark theme, live dashboard, server mode toggle, operation log panel, and settings persistence (completed 2026-02-19)
- [x] **Phase 3: Diagnostics and Service Management** - Health check with auto-repair, service start/stop, firewall rule management, and permissions checking (completed 2026-02-20)
- [x] **Phase 4: Database Operations** - 6-step deep cleanup pipeline, database backup and restore, and sysadmin permission enforcement (7 plans) (completed 2026-02-20)
- [x] **Phase 5: WSUS Operations** - Online sync with profile selection, air-gap export/import workflow, and content reset (completed 2026-02-19)
- [ ] **Phase 6: Installation and Scheduling** - WSUS + SQL Express installation wizard, scheduled task creation with domain credentials, and GPO deployment
- [ ] **Phase 7: Polish and Distribution** - Comprehensive test suite, CI/CD pipeline, EXE validation, and release automation

## Phase Details

### Phase 1: Foundation
**Goal**: A compilable C#/.NET 9 WPF solution exists with correct project structure, dependency injection wiring, the async operation runner pattern, UAC admin enforcement, structured logging, and a validated single-file publish pipeline — establishing every architectural constraint before any feature code is written.
**Depends on**: Nothing (first phase)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, GUI-05
**Success Criteria** (what must be TRUE):
  1. The solution builds without errors and the published EXE runs on a clean Windows Server 2019 machine without installing .NET runtime
  2. Launching the EXE without administrator privileges triggers a UAC elevation prompt before the window appears
  3. Every operation invocation routes through a single `RunOperationAsync` wrapper — no raw async void handlers with uncaught exceptions
  4. Application starts and shows its main window in under 1 second on Windows Server 2019
  5. All log output writes structured entries to `C:\WSUS\Logs\` on startup
**Plans**:
  1. Solution scaffold and project structure (FOUND-02, FOUND-03, GUI-05)
  2. Structured logging with Serilog (FOUND-04)
  3. RunOperationAsync pattern and OperationResult (FOUND-05)
  4. Main window shell and global error handling (FOUND-01, FOUND-05)
  5. Settings service and infrastructure helpers (foundation)
  6. DI wiring, integration, publish validation (FOUND-01, FOUND-02)

### Phase 2: Application Shell and Dashboard
**Goal**: The application window is fully functional — dark-themed, DPI-aware, showing live service and database status on the dashboard, with server mode switching, an expandable operation log panel, settings persistence, and all concurrent-operation guards in place.
**Depends on**: Phase 1
**Requirements**: DASH-01, DASH-02, DASH-03, DASH-04, DASH-05, GUI-01, GUI-02, GUI-03, GUI-04, GUI-06, GUI-07, OPS-01, OPS-02, OPS-03, OPS-04
**Success Criteria** (what must be TRUE):
  1. On launch, the dashboard displays WSUS health status, SQL Server DB size with a warning indicator when approaching 10GB, last sync time, and SQL/WSUS/IIS service states — all without freezing the UI
  2. The dashboard auto-refreshes every 30 seconds with a visible refresh indicator, and displays "Not Installed" cards when WSUS is absent from the server
  3. Toggling between Online and Air-Gap modes changes the visible menu items and operation buttons accordingly
  4. Attempting to start a second operation while one is running disables all operation buttons and prevents concurrent execution
  5. Application settings (server mode, log panel state, live terminal toggle) survive a full close and reopen cycle
**Plans**:
  1. Dark theme resource dictionary and base styles (GUI-01)
  2. Main window layout with sidebar navigation (GUI-02, GUI-03)
  3. Dashboard service for data collection (DASH-01, DASH-02, DASH-03, DASH-04)
  4. Dashboard panel with status cards and auto-refresh (DASH-01, DASH-02, DASH-03, DASH-04, DASH-05, GUI-06)
  5. Server mode detection and context-aware menus (GUI-04)
  6. Operation log panel with controls (OPS-01, OPS-02, GUI-07)
  7. WSUS installation detection and button state management (GUI-06, OPS-03, OPS-04)
  8. Settings persistence integration and final wiring (GUI-07, integration)

### Phase 3: Diagnostics and Service Management
**Goal**: Administrators can run a comprehensive health check that detects and auto-repairs service failures, firewall rule problems, content directory permission issues, and SQL connectivity failures — and can start/stop individual services directly from the UI.
**Depends on**: Phase 2
**Requirements**: DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05, SVC-01, SVC-02, SVC-03, FW-01, FW-02, PERM-01, PERM-02
**Success Criteria** (what must be TRUE):
  1. Running Health Check produces a clear pass/fail report for each check: SQL Server connectivity, WSUS service state, IIS app pool, firewall ports 8530 and 8531, content directory permissions
  2. Auto-repair during Health Check successfully restarts stopped services, re-creates missing firewall rules, and fixes content directory permissions without manual intervention
  3. Users can start or stop SQL Server, WSUS, and IIS individually from the Service Management panel — and the dashboard reflects the new state without a manual refresh
  4. Database operations are blocked with a clear error message when the current user lacks SQL sysadmin permissions
  5. Running Content Reset (wsusutil reset) completes without hanging and reports success or failure in the log panel
**Plans**:
  1. Health check models and diagnostic result types (DIAG-03)
  2. Windows service management service (SVC-01, SVC-02, SVC-03)
  3. Firewall rule management service (FW-01, FW-02)
  4. Permissions and SQL sysadmin check services (PERM-01, PERM-02, DIAG-04)
  5. Health check service with auto-repair pipeline (DIAG-01, DIAG-02, DIAG-03)
  6. Content reset service — wsusutil reset (DIAG-05)
  7. Diagnostics UI panel and ViewModel wiring (DIAG-01, DIAG-02, DIAG-03, DIAG-05, SVC-01, SVC-02, SVC-03)
  8. Tests and integration verification (all Phase 3)

### Phase 4: Database Operations
**Goal**: Administrators can run the full 6-step deep cleanup pipeline (decline superseded, remove supersession records in two passes, delete declined updates in batches, rebuild indexes, shrink DB with retry) and can backup or restore the SUSDB database from a file picker.
**Depends on**: Phase 3
**Requirements**: DB-01, DB-02, DB-03, DB-04, DB-05, DB-06
**Success Criteria** (what must be TRUE):
  1. Deep Cleanup runs all 6 steps in sequence, reporting progress and elapsed time for each step in the log panel, with batched deletion (10k/batch for supersession records, 100/batch for declined updates)
  2. DB size is displayed before and after the shrink step, and the shrink retries automatically (up to 3 times with 30-second delays) when blocked by an active backup operation
  3. Deep Cleanup completes on a production SUSDB without SQL timeout errors — all maintenance queries run with unlimited command timeout
  4. User can select a backup destination and successfully back up the SUSDB — and can restore it from a backup file selected via a file picker dialog
**Plans**:
  1. SQL helper service and connection management (foundation)
  2. Deep cleanup steps 1–3 — WSUS cleanup, remove supersession records (DB-01, DB-02, DB-03)
  3. Deep cleanup steps 4–6 — delete declined, rebuild indexes, shrink DB (DB-01, DB-02, DB-03, DB-04)
  4. Database backup service (DB-05)
  5. Database restore service (DB-06)
  6. Database operations UI panel and ViewModel wiring (DB-01–DB-06)
  7. Tests and integration verification (all Phase 4)

### Phase 5: WSUS Operations
**Goal**: Administrators can run Online Sync with profile selection, export WSUS data to media (full and differential), import from USB or network share, and reset content after an air-gap import — covering the full air-gap maintenance workflow end-to-end.
**Depends on**: Phase 4
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05, XFER-01, XFER-02, XFER-03, XFER-04, XFER-05
**Success Criteria** (what must be TRUE):
  1. Online Sync runs with the selected profile (Full Sync, Quick Sync, or Sync Only) and reports sync phase and percentage progress in the log panel without freezing the UI
  2. Definition Updates are auto-approved after sync (up to 200), Critical/Security/Update Rollups/Service Packs/Updates/Definition Updates classifications are approved, and Upgrades are never auto-approved
  3. User can export WSUS data to a full path and/or a differential path (files from the last N days) — if neither path is specified, the export step is skipped
  4. User can import WSUS data from a source path (e.g., USB drive) to a destination path, with pre-flight validation that both paths are accessible before any data is moved
  5. All export/import operations run without interactive prompts when launched from the GUI
**Plans**:
  1. WSUS server connection service (SYNC-01–SYNC-05 foundation)
  2. Online sync service with profile selection (SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05)
  3. Robocopy service for content transfer (XFER-01–XFER-05 foundation)
  4. Export service — full and differential content export (XFER-01, XFER-02, XFER-04, XFER-05)
  5. Import service — content import from external media (XFER-03, XFER-05)
  6. WSUS operations UI — sync dialog and ViewModel commands (SYNC-01–SYNC-05 UI)
  7. WSUS operations UI — transfer dialog and ViewModel commands (XFER-01–XFER-05 UI)
  8. Tests and integration verification (all Phase 5)

### Phase 6: Installation and Scheduling
**Goal**: Administrators can install WSUS with SQL Server Express through a guided wizard that requires no interactive console input, create Windows scheduled tasks for automated maintenance using domain credentials, and copy GPO deployment files with step-by-step instructions.
**Depends on**: Phase 5
**Requirements**: INST-01, INST-02, INST-03, SCHED-01, SCHED-02, SCHED-03, SCHED-04, GPO-01, GPO-02
**Success Criteria** (what must be TRUE):
  1. The installation wizard guides the user through WSUS + SQL Express setup entirely within the GUI — no console prompts appear, and all input (paths, credentials) is collected through dialog fields before installation begins
  2. All WSUS operation buttons are disabled and show visual feedback when WSUS is not yet installed on the server — only the Install WSUS button remains active
  3. User can create a Windows scheduled task that runs maintenance automatically on the configured day using domain credentials, and the task runs successfully whether or not the user is logged on
  4. User can copy GPO deployment files to `C:\WSUS\WSUS GPO` and sees clear instructions for applying the GPO on the domain controller
**Plans**:
  1. Installation service — PowerShell script orchestration (INST-01, INST-02)
  2. Scheduled task service — schtasks.exe orchestration (SCHED-01, SCHED-02, SCHED-03, SCHED-04)
  3. GPO deployment service (GPO-01, GPO-02)
  4. Installation dialog and ViewModel command (INST-01, INST-02, INST-03)
  5. Schedule task dialog and ViewModel command (SCHED-01, SCHED-02, SCHED-03, SCHED-04)
  6. GPO deployment command and sidebar wiring (GPO-01, GPO-02)
  7. Tests and integration verification (all Phase 6)

### Phase 7: Polish and Distribution
**Goal**: The project has a comprehensive xUnit test suite covering all service and ViewModel logic, a GitHub Actions CI/CD pipeline that builds the single-file EXE and creates GitHub releases automatically, and the published EXE is validated on a clean Windows Server 2019 environment with antivirus enabled.
**Depends on**: Phase 6
**Requirements**: BUILD-01, BUILD-02, BUILD-03, BUILD-04
**Success Criteria** (what must be TRUE):
  1. The xUnit test suite covers all Core services and ViewModel logic with coverage equivalent to the 323 Pester tests it replaces — and passes completely in CI
  2. A push to the main branch triggers GitHub Actions to build the single-file EXE with embedded version info, company name, and product name — and the EXE passes PE header and 64-bit architecture validation tests
  3. Tagging a release creates a GitHub release automatically with the EXE artifact attached — no manual upload step required
  4. The published EXE launches successfully on a clean Windows Server 2019 VM with antivirus enabled, without extracting files to `%TEMP%` or triggering AV heuristics
**Plans**:
  1. Test coverage audit and gap-filling — Core services (BUILD-04)
  2. Test coverage audit and gap-filling — ViewModel and integration (BUILD-04)
  3. EXE validation test class in xUnit (BUILD-02, BUILD-04)
  4. GitHub Actions CI/CD workflow for C# build (BUILD-01, BUILD-02, BUILD-03)
  5. Version management and EXE metadata (BUILD-02)
  6. Distribution package validation and smoke test (BUILD-01, BUILD-02, BUILD-04)
  7. Final integration verification and documentation update (all Phase 7)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 6/6 | Complete | 2026-02-19 |
| 2. Application Shell and Dashboard | 8/8 | Complete | 2026-02-19 |
| 3. Diagnostics and Service Management | 1/1 | Complete   | 2026-02-20 |
| 4. Database Operations | 1/1 | Complete   | 2026-02-20 |
| 5. WSUS Operations | 8/8 | Complete | 2026-02-19 |
| 6. Installation and Scheduling | 0/7 | Planned | - |
| 7. Polish and Distribution | 0/7 | Planned | - |
