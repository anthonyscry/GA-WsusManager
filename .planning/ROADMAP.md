# Roadmap: GA-WsusManager

## Milestones

- ✅ **v4.0 C# Rewrite** — Phases 1-7 (shipped 2026-02-20)
- **v4.1 Bug Fixes & Polish** — Phases 8-11 (in progress)

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

### v4.1 Bug Fixes & Polish

- [x] **Phase 8: Build Compatibility** — Retarget to .NET 8, fix CI/CD, verify published EXE runs on Windows Server 2019+ (completed 2026-02-21)
- [ ] **Phase 9: Launch and UI Verification** — App launches without crash, dark theme renders, all panels and log panel work
- [ ] **Phase 10: Core Operations** — All 6 operations execute successfully on a real WSUS server
- [ ] **Phase 11: Stability Hardening** — No unhandled exceptions, cancellation works, concurrent operation blocking holds

## Phase Details

### Phase 8: Build Compatibility
**Goal**: The app builds, publishes, and runs as a single-file EXE using the .NET 8 SDK
**Depends on**: Nothing (prerequisite for all other phases)
**Requirements**: COMPAT-01, COMPAT-02, COMPAT-03
**Success Criteria** (what must be TRUE):
  1. `dotnet build` succeeds with .NET 8 SDK targeting all projects
  2. CI/CD pipeline completes without errors using .NET 8
  3. Published EXE launches on a clean Windows Server 2019+ machine (no runtime install required)
**Plans**: 1 plan

Plans:
- [ ] 08-01-PLAN.md — Fix net9.0-windows references in ExeValidationTests.cs and build-csharp.yml, verify build and tests pass

### Phase 9: Launch and UI Verification
**Goal**: The application presents a correct, fully-functional UI from startup through all navigation panels
**Depends on**: Phase 8
**Requirements**: UI-01, UI-02, UI-03, UI-04, UI-05
**Success Criteria** (what must be TRUE):
  1. App launches to the dashboard without any crash dialog or error message
  2. Dashboard cards show real WSUS server status, or show "Not Installed" gracefully when WSUS is absent
  3. Dark theme renders with no white panels, broken colors, or layout corruption
  4. Clicking each nav item (Dashboard, Diagnostics, Database, WSUS Ops, Setup) switches the panel correctly
  5. Log panel expands when an operation starts and shows operation output text
**Plans**: 1 plan

Plans:
- [ ] 09-01-PLAN.md — Fix duplicate startup log message and add active nav button highlighting

### Phase 10: Core Operations
**Goal**: Every core WSUS management operation executes to completion against a real WSUS server
**Depends on**: Phase 9
**Requirements**: OPS-01, OPS-02, OPS-03, OPS-04, OPS-05, OPS-06
**Success Criteria** (what must be TRUE):
  1. Health check runs and displays pass/fail results for services, firewall, permissions, and SQL connectivity
  2. Auto-repair detects and fixes at least one real issue (or confirms no issues found) without crashing
  3. Online sync runs with the selected profile (Full/Quick/SyncOnly) and logs completion status
  4. Deep cleanup runs all 6 steps and reports before/after database size
  5. Database backup produces a .bak file at the specified path
  6. Database restore from a .bak file completes and WSUS returns to operational state
**Plans**: TBD

### Phase 11: Stability Hardening
**Goal**: The application handles edge cases and error conditions without crashing or leaving the UI in a broken state
**Depends on**: Phase 10
**Requirements**: STAB-01, STAB-02, STAB-03
**Success Criteria** (what must be TRUE):
  1. No unhandled exception dialogs appear during any normal operation flow (including when WSUS or SQL is offline)
  2. Clicking Cancel during a running operation stops it and returns all buttons to their enabled state
  3. Double-clicking an operation button while another operation is running shows a graceful warning and does not start a second operation
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
| 8. Build Compatibility | v4.1 | 1/1 | Complete | 2026-02-21 |
| 9. Launch and UI Verification | v4.1 | 0/1 | Not started | - |
| 10. Core Operations | v4.1 | 0/? | Not started | - |
| 11. Stability Hardening | v4.1 | 0/? | Not started | - |
