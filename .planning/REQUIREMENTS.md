# Requirements: GA-WsusManager

**Defined:** 2026-02-20
**Core Value:** Rock-solid stability — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure.

## v4.2 Requirements

Requirements for UX & Client Management milestone. Each maps to roadmap phases.

### Settings & Configuration

- [ ] **SET-01**: User can edit all settings (server mode, refresh interval, paths) via Settings dialog
- [ ] **SET-02**: Settings changes persist to settings.json and take effect immediately
- [ ] **SET-03**: User can toggle Air-Gap/Online mode from dashboard quick button
- [ ] **SET-04**: Manual mode override bypasses automatic network detection

### Operation Feedback

- [ ] **UX-01**: Operations display progress indicator (indeterminate progress bar) during execution
- [ ] **UX-02**: Multi-step operations show current step name and step count (e.g., "Step 3/6: Rebuilding indexes")
- [ ] **UX-03**: Operations show clear success/failure banner with summary when complete
- [ ] **UX-04**: Log panel auto-scrolls to latest output during operations

### Dialog Polish

- [ ] **DLG-01**: Install dialog validates installer path exists and contains required EXE before enabling Install button
- [ ] **DLG-02**: Transfer dialog shows validation feedback for source/destination paths
- [ ] **DLG-03**: All dialogs have consistent dark theme styling and spacing
- [ ] **DLG-04**: Schedule Task dialog validates all fields before enabling Create button

### Client Management

- [ ] **CLI-01**: User can cancel stuck Windows Update jobs on a remote host (stop services, clear cache, restart)
- [ ] **CLI-02**: User can force WSUS check-in on a remote host (gpupdate + resetauthorization + detectnow + reportnow)
- [ ] **CLI-03**: User can run mass GPUpdate across multiple hosts (from text file or manual entry)
- [ ] **CLI-04**: User can test WSUS port connectivity from a remote host to WSUS server
- [ ] **CLI-05**: User can run quick diagnostics on a remote host (WSUS settings, service status, last check-in, pending reboot)
- [ ] **CLI-06**: User can look up common WSUS error codes with descriptions and fixes
- [ ] **CLI-07**: Remote operations execute via WinRM when available
- [ ] **CLI-08**: User can generate ready-to-run PowerShell scripts as fallback when WinRM unavailable

## Future Requirements

### Advanced Client Management

- **CLI-F01**: User can view all WSUS-registered clients with status in a data grid
- **CLI-F02**: User can push updates to specific client groups
- **CLI-F03**: User can view update compliance per client

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-server WSUS management | Single server focus per PROJECT.md constraints |
| Client-side agent/service | Admin tool only, not a client endpoint |
| SCCM/Intune integration | Different tooling ecosystem |
| Active Directory browser | Use existing AD tools, just accept hostnames |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SET-01 | TBD | Pending |
| SET-02 | TBD | Pending |
| SET-03 | TBD | Pending |
| SET-04 | TBD | Pending |
| UX-01 | TBD | Pending |
| UX-02 | TBD | Pending |
| UX-03 | TBD | Pending |
| UX-04 | TBD | Pending |
| DLG-01 | TBD | Pending |
| DLG-02 | TBD | Pending |
| DLG-03 | TBD | Pending |
| DLG-04 | TBD | Pending |
| CLI-01 | TBD | Pending |
| CLI-02 | TBD | Pending |
| CLI-03 | TBD | Pending |
| CLI-04 | TBD | Pending |
| CLI-05 | TBD | Pending |
| CLI-06 | TBD | Pending |
| CLI-07 | TBD | Pending |
| CLI-08 | TBD | Pending |

**Coverage:**
- v4.2 requirements: 20 total
- Mapped to phases: 0
- Unmapped: 20 ⚠️

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after initial definition*
