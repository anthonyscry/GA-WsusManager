# Roadmap: GA-WsusManager

## Milestones

- ✅ **v4.0 C# Rewrite** — Phases 1-7 (shipped 2026-02-20)
- ✅ **v4.1 Bug Fixes & Polish** — Phases 8-11 (shipped 2026-02-20)
- 🚧 **v4.2 UX & Client Management** — Phases 12-15 (in progress)

## Phases

<details>
<summary>✅ v4.0 C# Rewrite (Phases 1-7) — SHIPPED 2026-02-20</summary>

- [x] Phase 1: Foundation — Compilable solution with DI, async pattern, single-file publish, UAC, logging (2026-02-19)
- [x] Phase 2: Application Shell and Dashboard — Dark theme, live dashboard, server mode, log panel, settings (2026-02-19)
- [x] Phase 3: Diagnostics and Service Management — Health check with auto-repair, service management, firewall, permissions (2026-02-20)
- [x] Phase 4: Database Operations — 6-step deep cleanup, backup/restore, sysadmin enforcement (2026-02-20)
- [x] Phase 5: WSUS Operations — Online sync with profiles, air-gap export/import, content reset (2026-02-19)
- [x] Phase 6: Installation and Scheduling — Install wizard, scheduled tasks, GPO deployment (2026-02-20)
- [x] Phase 7: Polish and Distribution — 257 tests, CI/CD pipeline, EXE validation, release automation (2026-02-20)

Full details: `.planning/milestones/v4.0-ROADMAP.md`

</details>

<details>
<summary>✅ v4.1 Bug Fixes & Polish (Phases 8-11) — SHIPPED 2026-02-20</summary>

- [x] Phase 8: Build Compatibility — Retarget to .NET 8, fix CI/CD and test paths (2026-02-20)
- [x] Phase 9: Launch and UI Verification — Fix duplicate startup message, add active nav highlighting (2026-02-20)
- [x] Phase 10: Core Operations — Fix 5 bugs in health check, sync, and cleanup services (2026-02-20)
- [x] Phase 11: Stability Hardening — Add CanExecute refresh for proper button disabling (2026-02-20)

Full details: `.planning/milestones/v4.1-ROADMAP.md`

</details>

### 🚧 v4.2 UX & Client Management (In Progress)

**Milestone Goal:** Polish the user experience with editable settings, real operation progress feedback, and a full suite of client troubleshooting tools so admins can diagnose and fix stuck WSUS clients directly from the GUI.

## Phase Details

### Phase 12: Settings & Mode Override
**Goal**: Admins can edit all application settings and manually control Online/Air-Gap mode without restarting the application
**Depends on**: Phase 11
**Requirements**: SET-01, SET-02, SET-03, SET-04
**Success Criteria** (what must be TRUE):
  1. Admin opens Settings dialog and can modify server mode, refresh interval, and content paths — values are editable, not read-only
  2. After saving, changed settings write to settings.json and take effect immediately without restarting the application
  3. Admin clicks the Air-Gap/Online toggle on the dashboard and the mode switches instantly
  4. Manual mode override bypasses network detection — the app stays in the manually chosen mode across dashboard refreshes
**Plans**: 2 plans

Plans:
- [x] 12-01-PLAN.md — Editable Settings dialog (SET-01, SET-02)
- [x] 12-02-PLAN.md — Dashboard mode toggle with override logic (SET-03, SET-04)

### Phase 13: Operation Feedback & Dialog Polish
**Goal**: Every operation gives clear visual feedback during execution and completion, and every dialog validates inputs before the user can proceed
**Depends on**: Phase 12
**Requirements**: UX-01, UX-02, UX-03, UX-04, DLG-01, DLG-02, DLG-03, DLG-04
**Success Criteria** (what must be TRUE):
  1. An indeterminate progress bar is visible whenever an operation is running — no operation runs silently
  2. Multi-step operations show the current step name and step count (e.g., "Step 3/6: Rebuilding indexes") in real time
  3. When an operation completes, a clear success or failure banner with a result summary appears — the admin knows at a glance whether it worked
  4. The log panel scrolls to the latest output automatically during operations so the admin never has to scroll manually
  5. Install, Transfer, and Schedule dialogs disable their primary action button when required inputs are missing or invalid, with visible validation feedback
**Plans**: TBD

### Phase 14: Client Management Core
**Goal**: Admins can perform single-host client troubleshooting operations (cancel stuck jobs, force check-in, test connectivity, run diagnostics, look up error codes) directly from the GUI using WinRM
**Depends on**: Phase 13
**Requirements**: CLI-01, CLI-02, CLI-04, CLI-05, CLI-06, CLI-07
**Success Criteria** (what must be TRUE):
  1. Admin enters a hostname, clicks Cancel Stuck Jobs, and the app remotely stops Windows Update services, clears the cache, and restarts services on that host — result logged in the log panel
  2. Admin clicks Force Check-In for a hostname and the app triggers gpupdate, resetauthorization, detectnow, and reportnow on the remote host
  3. Admin clicks Test Connectivity and sees whether the remote host can reach the WSUS server on ports 8530/8531
  4. Admin clicks Run Diagnostics and sees WSUS settings, service status, last check-in time, and pending reboot state for the remote host
  5. Admin enters an error code in the error code lookup and sees a description and recommended fix without leaving the application
  6. Remote operations execute via WinRM when the target host has it available — no manual PowerShell invocation required
**Plans**: TBD

### Phase 15: Client Management Advanced
**Goal**: Admins can run operations across multiple hosts at once and generate ready-to-run PowerShell scripts as a fallback when WinRM is unavailable
**Depends on**: Phase 14
**Requirements**: CLI-03, CLI-08
**Success Criteria** (what must be TRUE):
  1. Admin provides a list of hostnames (typed or from a text file) and triggers mass GPUpdate — the app processes all hosts and shows per-host results
  2. When WinRM is unavailable for a host, the admin can generate a PowerShell script that performs the same operation and can be run manually on that host
  3. Generated scripts are complete and ready to run — no edits required before execution
**Plans**: TBD

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1. Foundation | v4.0 | 6/6 | Complete | 2026-02-19 |
| 2. Application Shell and Dashboard | v4.0 | 8/8 | Complete | 2026-02-19 |
| 3. Diagnostics and Service Management | v4.0 | 1/1 | Complete | 2026-02-20 |
| 4. Database Operations | v4.0 | 1/1 | Complete | 2026-02-20 |
| 5. WSUS Operations | v4.0 | 8/8 | Complete | 2026-02-19 |
| 6. Installation and Scheduling | v4.0 | 1/1 | Complete | 2026-02-20 |
| 7. Polish and Distribution | v4.0 | 7/7 | Complete | 2026-02-20 |
| 8. Build Compatibility | v4.1 | 1/1 | Complete | 2026-02-20 |
| 9. Launch and UI Verification | v4.1 | 1/1 | Complete | 2026-02-20 |
| 10. Core Operations | v4.1 | 1/1 | Complete | 2026-02-20 |
| 11. Stability Hardening | v4.1 | 1/1 | Complete | 2026-02-20 |
| 12. Settings & Mode Override | 2/2 | Complete   | 2026-02-21 | - |
| 13. Operation Feedback & Dialog Polish | v4.2 | 0/TBD | Not started | - |
| 14. Client Management Core | v4.2 | 0/TBD | Not started | - |
| 15. Client Management Advanced | v4.2 | 0/TBD | Not started | - |
