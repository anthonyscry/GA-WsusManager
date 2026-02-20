# GA-WsusManager v4 — Complete Rewrite

## What This Is

A ground-up rewrite of GA-WsusManager in a compiled language, replacing the current PowerShell/WPF implementation with a single-EXE application optimized for rock-solid stability and speed. It manages WSUS servers with SQL Server Express on Windows Server 2019+, including full air-gapped network support. Built for GA-ASI IT administrators who need reliable, zero-crash WSUS management tooling.

## Core Value

The application must be completely stable — zero crashes, no threading bugs, no UI freezes — so administrators trust it to manage critical WSUS infrastructure on production servers.

## Requirements

### Validated

<!-- These capabilities exist in the PowerShell v3.8.x and are proven valuable. -->

- ✓ GUI dashboard with auto-refresh (30s) showing WSUS health, DB size, sync status — existing
- ✓ Health check diagnostics with auto-repair (services, firewall, permissions, connectivity) — existing
- ✓ Deep cleanup (decline superseded, purge declined, rebuild indexes, shrink DB) — existing
- ✓ Export/Import workflow for air-gapped networks (full + differential) — existing
- ✓ Online Sync with profile selection (Full/Quick/Sync Only) — existing
- ✓ WSUS + SQL Express installation wizard — existing
- ✓ Database backup and restore — existing
- ✓ Scheduled task creation for automated maintenance — existing
- ✓ Service management (SQL Server, WSUS, IIS start/stop/status) — existing
- ✓ Firewall rule management (ports 8530, 8531) — existing
- ✓ Directory permissions checking and repair — existing
- ✓ Settings persistence (JSON) — existing
- ✓ Live terminal mode for operation output — existing
- ✓ Server mode toggle (Online vs Air-Gap) with context-aware menus — existing
- ✓ DPI-aware rendering — existing
- ✓ Admin privilege enforcement — existing
- ✓ GPO deployment scripts for domain controllers — existing
- ✓ Definition Updates auto-approval with safety threshold — existing
- ✓ SQL sysadmin permission checking — existing
- ✓ Content reset (wsusutil reset) for air-gap import fixes — existing

### Active

<!-- New capabilities for the rewrite. -->

- [ ] Single-file EXE distribution (no Scripts/ or Modules/ folder required)
- [ ] Sub-second application startup
- [ ] Native async operations (no threading hacks or dispatcher workarounds)
- [ ] Modernized dark theme UI (same layout, fresher look)
- [ ] Compiled language for type safety and compile-time error catching
- [ ] All existing PowerShell module functionality ported to native code
- [ ] Comprehensive test suite in the target language's testing framework

### Out of Scope

- Mobile or web-based interface — desktop-only for server administration
- Linux/macOS support — Windows Server only (WSUS is Windows-only)
- Server 2016 support — targeting 2019+ only
- Real-time multi-server management — single server at a time (same as current)
- PowerShell script backward compatibility — clean break from PS codebase
- The existing C# POC in CSharp/ — starting fresh, not building on it

## Context

### Current State
- PowerShell v3.8.12 is the production version with 3000+ LOC GUI, 11 modules (~180KB), 323 Pester tests
- 12+ documented WPF anti-patterns in CLAUDE.md (threading, closures, dispatcher, event handlers)
- C# POC exists at 90% feature parity but user wants a fresh start
- CI/CD pipeline exists with GitHub Actions (build, test, release)

### Technical Environment
- Windows Server 2019/2022 with WSUS role installed
- SQL Server Express 2022 (localhost\SQLEXPRESS) with 10GB limit
- SUSDB database for WSUS metadata
- Standard paths: C:\WSUS\ (content), C:\WSUS\Logs\ (logs)
- Ports: 8530 (HTTP), 8531 (HTTPS)
- Air-gapped networks require USB-based export/import workflow

### Known Pain Points from PowerShell Version
1. **Threading bugs**: WPF dispatcher issues, closure variable capture, event handler scope problems
2. **Slow startup**: 1-2 seconds due to PowerShell runtime + module imports
3. **Maintainability**: 12+ documented anti-patterns, complex async workarounds
4. **Fragile deployment**: EXE requires Scripts/ and Modules/ folders alongside it
5. **Memory usage**: 150-200MB due to PowerShell runtime overhead

## Constraints

- **Target OS**: Windows Server 2019+ (64-bit only)
- **Admin Required**: All operations require elevated privileges
- **SQL Express**: Must work with localhost\SQLEXPRESS and 10GB database limit
- **Air-Gap**: Export/import must work fully offline — no internet dependency
- **Single EXE**: Distribution must be a single executable file
- **WSUS APIs**: Must interact with Microsoft.UpdateServices.Administration and SUSDB directly
- **Language**: To be determined by research — optimized for stability, speed, and Windows native integration

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full rewrite (not incremental port) | PowerShell architecture has fundamental limitations (threading, deployment) | — Pending |
| Start fresh (ignore C# POC) | User preference for clean slate | — Pending |
| Single EXE deployment | Simplifies deployment on production servers | — Pending |
| Drop Server 2016 support | Allows targeting modern .NET/runtime versions | — Pending |
| Stability over speed | Zero crashes is more important than raw performance | — Pending |
| Language TBD | Research phase will determine optimal language | — Pending |

---
*Last updated: 2026-02-19 after initialization*
