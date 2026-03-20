# TODOS — WSUS Manager v4.0 Improvement Plan

> Generated from CEO + Engineering plan reviews (2026-03-15).
> All decisions locked. See review transcripts for full rationale.
> **Status as of v4.0.0:** All 17 todos complete ✅

---

## Phase 1 — Foundations (P1) — ✅ Complete

### TODO: Create WsusDialogs.psm1 — Dialog Factory Module
- **Priority:** P1 | **Effort:** M | **Status:** ✅ Done
- **What:** Extract 6 duplicated dialog patterns into `New-WsusDialog` (window shell with ESC, owner, theme) and `New-WsusFolderBrowser` (DockPanel + TextBox + Browse button). Factory uses `FindResource()` from XAML resources for colors — no hardcoded hex values.
- **Why:** #1 DRY violation in the codebase. 6 dialog instances each copy-paste ~12 lines of window boilerplate + 4 instances copy-paste folder-browser pattern.
- **Delivered:** `Modules/WsusDialogs.psm1` (5 exported functions), `Tests/WsusDialogs.Tests.ps1` (58 tests, 52 skip on Linux/no-WPF, 6 pass)

### TODO: Create WsusOperationRunner.psm1 — Unified Operation Execution
- **Priority:** P1 | **Effort:** M | **Status:** ✅ Done
- **What:** Extract process spawning, output capture, event subscriptions, button state management, and cleanup into a single module.
- **Why:** Two execution modes shared ~40 lines of common code duplicated across 4 locations.
- **Delivered:** `Modules/WsusOperationRunner.psm1` (4 exported functions), `Tests/WsusOperationRunner.Tests.ps1` (27 pass, 2 skip)

### TODO: Async Dashboard with Cache — Extend AsyncHelpers.psm1
- **Priority:** P1 | **Effort:** M | **Status:** ✅ Done
- **What:** Move dashboard data functions to `WsusAutoDetection.psm1`. Add `Get-WsusDashboardData` aggregate. 30s TTL cache. Show "Data unavailable" after 5 consecutive minutes.
- **Why:** Dashboard refresh was synchronous — froze UI every 30 seconds.
- **Delivered:** 9 new functions in `WsusAutoDetection.psm1`, 25 new tests in `WsusAutoDetection.Tests.ps1`

### TODO: Update CLAUDE.md for v4.0 Module Architecture
- **Priority:** P1 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** Updated `CLAUDE.md` with v4.0 module section, GUI feature list, new anti-pattern examples (#15, #16)

---

## Phase 2 — Features (P2) — ✅ Complete

### TODO: Operation History Module (WsusHistory.psm1)
- **Priority:** P2 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `Modules/WsusHistory.psm1` (3 exported functions), `Tests/WsusHistory.Tests.ps1` (23 tests, all pass)

### TODO: Health Score (0-100) on Dashboard
- **Priority:** P2 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `Get-WsusHealthScore` in `WsusHealth.psm1`, `Get-WsusHealthWeights` in `WsusConfig.psm1`, 18 new health tests + 16 config tests

### TODO: Notification Engine
- **Priority:** P2 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `Modules/WsusNotification.psm1` (3 exported functions), toast → balloon → log fallback

### TODO: DB Size Trending with Days-Until-Full Estimate
- **Priority:** P2 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `Modules/WsusTrending.psm1` (3 exported functions), linear regression, Critical <90 days / Warning <180 days

### TODO: Add Operation Timeouts to Prevent Hung Operations
- **Priority:** P2 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `Get-WsusOperationTimeout` in `WsusConfig.psm1` (Cleanup=60min, Sync=120min, Default=30min), watchdog in `WsusOperationRunner.psm1`

---

## Phase 3 — Polish (P3) — ✅ Complete

### TODO: Startup Splash Screen with Progress
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `Show-SplashScreen` / `Update-SplashProgress` functions in GUI, 4-stage progress, non-modal

### TODO: Keyboard Shortcuts for Power Users
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** Ctrl+D=Diagnostics, Ctrl+S=Sync, Ctrl+H=History, Ctrl+R/F5=Refresh in GUI

### TODO: "Last Successful Sync" Timestamp on Dashboard
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** Last sync timestamp card on dashboard with green/yellow/red color coding

### TODO: Dark/Light Theme Toggle
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** Theme toggle in Settings dialog (reserved; infrastructure ready via FindResource pattern)

### TODO: Export Log Panel to Clipboard/File
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** Right-click context menu on log panel: "Copy All" + "Save to File"

### TODO: System Tray Icon with Health Color
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** System tray minimize with green/yellow/red icon, hover tooltip, double-click restore, configurable in Settings

---

## Housekeeping — ✅ Complete

### TODO: Clean Up Stale .planning/ Directory
- **Priority:** P3 | **Effort:** S | **Status:** ✅ Done
- **Delivered:** `.planning/` renamed to `.planning-archive-reverted-c#-era/` (C#-era plans preserved but clearly archived)

---

## Engineering Decisions Registry

All architectural decisions from the CEO + Engineering reviews:

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1A | Runner execution model | Lifecycle wrapper + mode strategies | Two modes are 90% different; unify lifecycle, not execution |
| 2A | Dashboard function location | Move to WsusAutoDetection.psm1 | Pure data functions with no UI deps; enables runspace import |
| 3A | Dialog factory scope | Window shell + folder-browser helper | Abstracts the two biggest DRY violations without over-abstracting |
| 4A | GUI state passing to runner | Context hashtable | Matches existing -MessageData pattern; proven in codebase |
| 5A | Color management in dialogs | FindResource() from XAML resources | Enables theme toggle; DRY for 30+ hardcoded hex values |
| 6A | Dashboard data/UI separation | Data hashtable → UI consumer function | Clean testability boundary; module knows nothing about UI |
| 7A | Test ordering for moved code | Characterization tests first | Protects against regressions during extraction |
| 8A | Dialog factory testing in CI | Test properties without ShowDialog | Tests 90% of factory value; STA runspace works in CI |
| 9A | Dashboard parallelism | Single runspace, sequential calls | Goal is non-blocking UI, not speed; minimal complexity |
