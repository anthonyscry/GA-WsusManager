# Roadmap: GA-WsusManager

## Milestones

- ✅ **v4.0 C# Rewrite** — Phases 1-7 (shipped 2026-02-20)
- ✅ **v4.1 Bug Fixes & Polish** — Phases 8-11 (shipped 2026-02-20)
- ✅ **v4.2 UX & Client Management** — Phases 12-15 (shipped 2026-02-21)
- 🔲 **v4.3 Themes** — Phases 16-17 (active)

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

<details>
<summary>✅ v4.2 UX & Client Management (Phases 12-15) — SHIPPED 2026-02-21</summary>

- [x] Phase 12: Settings & Mode Override — Editable settings dialog, dashboard mode toggle with override (2026-02-21)
- [x] Phase 13: Operation Feedback & Dialog Polish — Progress bar, step tracking, banners, dialog validation (2026-02-21)
- [x] Phase 14: Client Management Core — WinRM remote operations, error code lookup, Client Tools panel (2026-02-21)
- [x] Phase 15: Client Management Advanced — Mass GPUpdate, Script Generator fallback (2026-02-21)

Full details: `.planning/milestones/v4.2-ROADMAP.md`

</details>

### v4.3 Themes (Phases 16-17)

- [x] **Phase 16: Theme Infrastructure** — Split styles/tokens, migrate StaticResource to DynamicResource, implement ThemeService (2026-02-21)
- [x] **Phase 17: Theme Content and Picker** — 5 additional theme files, Settings Appearance section with live-preview swatch picker (1 plan) (completed 2026-02-21)

## Phase Details

### Phase 16: Theme Infrastructure
**Goal**: The app's styling system supports runtime color-scheme swapping — structural styles are permanently loaded, color tokens are swappable, and all color references respond to a theme change
**Depends on**: Nothing (first phase of v4.3)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05
**Success Criteria** (what must be TRUE):
  1. App renders identically to v4.2 after all changes — no visual regressions on the default dark theme
  2. Changing the active color dictionary at runtime causes all colored UI elements to update immediately without restart
  3. Dashboard card status bars and connection dot colors update when the theme swaps (ViewModel brushes use TryFindResource, not hardcoded Color.FromRgb)
  4. App reads SelectedTheme from settings.json on startup and applies it before the main window appears — no theme flash on launch
  5. A grep for `StaticResource` on any color/brush resource key returns zero results across all 8 XAML files
**Plans**: 1 plan

Plans:
- [x] 16-01-PLAN.md — Split styles/tokens, DynamicResource migration, ViewModel brush migration, ThemeService (INFRA-01 through INFRA-05)

### Phase 17: Theme Content and Picker
**Goal**: Users can choose from 6 built-in color themes in Settings, see a live preview when clicking swatches, and have their selection persist across restarts
**Depends on**: Phase 16
**Requirements**: THEME-01, THEME-02, THEME-03, PICK-01, PICK-02, PICK-03, PICK-04, PICK-05, PICK-06
**Success Criteria** (what must be TRUE):
  1. Settings dialog shows an Appearance section with 6 color swatches labeled Default Dark, Just Black, Slate, Serenity, Rose, and Classic Blue
  2. Clicking any swatch immediately applies that theme to the entire application while Settings is still open (live preview)
  3. Clicking Cancel in Settings reverts the app to the theme that was active when Settings was opened
  4. Clicking Save persists the chosen theme to settings.json and restores it correctly after app restart
  5. The currently active theme swatch is visually distinguished from the others (highlighted border or checkmark indicator)
**Plans**: 1 plan

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
| 12. Settings & Mode Override | v4.2 | 2/2 | Complete | 2026-02-21 |
| 13. Operation Feedback & Dialog Polish | v4.2 | 2/2 | Complete | 2026-02-21 |
| 14. Client Management Core | v4.2 | 3/3 | Complete | 2026-02-21 |
| 15. Client Management Advanced | v4.2 | 2/2 | Complete | 2026-02-21 |
| 16. Theme Infrastructure | v4.3 | 1/1 | Complete | 2026-02-21 |
| 17. Theme Content and Picker | 1/1 | Complete    | 2026-02-21 | - |
