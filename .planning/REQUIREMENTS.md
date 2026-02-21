# Requirements: GA-WsusManager v4.1

**Defined:** 2026-02-20
**Core Value:** Rock-solid stability — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure.

## v4.1 Requirements

Requirements for bug fix and polish release. Each maps to roadmap phases.

### Compatibility

- [x] **COMPAT-01**: App builds and runs with .NET 8 SDK
- [x] **COMPAT-02**: CI/CD pipeline builds with .NET 8 targeting
- [x] **COMPAT-03**: Published single-file EXE works on Windows Server 2019+

### UI Verification

- [ ] **UI-01**: App launches without crash on Windows
- [ ] **UI-02**: Dashboard populates with WSUS server status (or "Not Installed" gracefully)
- [ ] **UI-03**: Dark theme renders correctly (no white/broken panels)
- [ ] **UI-04**: All navigation panels switch correctly (Dashboard, Diagnostics, Database, WSUS Ops, Setup)
- [ ] **UI-05**: Log panel expands/collapses and shows operation output

### Core Operations

- [ ] **OPS-01**: Health check executes and reports results on real WSUS server
- [ ] **OPS-02**: Auto-repair fixes detected issues (services, firewall, permissions)
- [ ] **OPS-03**: Online sync executes with profile selection (Full/Quick/SyncOnly)
- [ ] **OPS-04**: Deep cleanup pipeline completes all 6 steps
- [ ] **OPS-05**: Database backup creates .bak file successfully
- [ ] **OPS-06**: Database restore from .bak file works

### Stability

- [ ] **STAB-01**: No unhandled exceptions during normal operation
- [ ] **STAB-02**: Operations can be cancelled without crash
- [ ] **STAB-03**: Concurrent operation blocking works (prevents double-click)

## Future Requirements

None — v4.1 is focused on making v4.0 work correctly.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New features | v4.1 is bug fix only — no new capabilities |
| .NET 9 upgrade | Dev machine has .NET 8 SDK; .NET 8 is LTS |
| Multi-server support | Deferred to future milestone |
| HTTPS configuration | Deferred to future milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| COMPAT-01 | Phase 8 | Complete |
| COMPAT-02 | Phase 8 | Complete |
| COMPAT-03 | Phase 8 | Complete |
| UI-01 | Phase 9 | Pending |
| UI-02 | Phase 9 | Pending |
| UI-03 | Phase 9 | Pending |
| UI-04 | Phase 9 | Pending |
| UI-05 | Phase 9 | Pending |
| OPS-01 | Phase 10 | Pending |
| OPS-02 | Phase 10 | Pending |
| OPS-03 | Phase 10 | Pending |
| OPS-04 | Phase 10 | Pending |
| OPS-05 | Phase 10 | Pending |
| OPS-06 | Phase 10 | Pending |
| STAB-01 | Phase 11 | Pending |
| STAB-02 | Phase 11 | Pending |
| STAB-03 | Phase 11 | Pending |

**Coverage:**
- v4.1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0 (100% coverage)

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 — traceability populated after roadmap creation*
