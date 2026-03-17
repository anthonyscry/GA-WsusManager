# UI-REVIEW.md — WSUS Manager v4.0.1

**Audit Date:** 2026-03-17
**Auditor:** 6-Pillar Visual Audit (Retroactive)
**Scope:** Full application — `Scripts/WsusManagementGui.ps1` (4140 lines), `Modules/WsusDialogs.psm1`, `Modules/WsusConfig.psm1`, plus 13 supporting modules
**Target:** PowerShell WPF desktop application (Windows Server admin tool)

---

## Overall Score: 15 / 24

| Pillar | Score | Rating |
|---|---|---|
| Copywriting | 3/4 | Good |
| Visuals | 2/4 | Adequate |
| Color | 3/4 | Good |
| Typography | 2/4 | Adequate |
| Spacing | 2/4 | Adequate |
| Experience Design | 3/4 | Good |

---

## 1. Copywriting — 3/4

### What works

- **Action-oriented nav labels.** "▶ Install WSUS", "🔍 Run Diagnostics", "🧹 Deep Cleanup" — verb-first, scannable at a glance. Section headers (SETUP, TRANSFER, MAINTENANCE, DIAGNOSTICS) group operations logically.
- **Status messages are precise.** Dashboard cards show "All Running", "3/3", "Critical!", "Healthy", "Low", "OK" — concise, no ambiguity. The health score combines a numeric value (0–100) with a human-readable grade (Green/Yellow/Red).
- **Error messages include context.** "Cannot find Invoke-WsusManagement.ps1" lists the paths that were searched and tells the user what to fix. Confirmation dialogs explain consequences: "This will remove superseded updates, optimize indexes, and shrink the database. This may take 30+ minutes."
- **Last sync is human-readable.** Shows both relative ("3 days ago") and absolute ("Jan 15, 2026 14:32") — IT admins can quickly assess staleness while having the precise timestamp for reports.
- **Help system is comprehensive.** Five topics (Overview, Dashboard, Operations, Air-Gap, Troubleshooting) with step-by-step instructions, path references, and port numbers. Troubleshooting includes actionable fix sequences.
- **Empty states communicate next actions.** "No operation history yet. Run an operation to start tracking." — tells the user what to do, not just that nothing exists.

### What to fix

| Issue | Location | Fix |
|---|---|---|
| **Inconsistent nav icon: `? Help`** uses a plain `?` while all other nav items use emoji (📜, 🔍, 🧹, etc.) | Line 396 | Change to `❓ Help` or pick a Unicode symbol from the same visual family (e.g., `ℹ` matches the about icon but then conflicts with "ℹ About") |
| **"Reset Content" lacks description** — what does it reset? Users must click to find out | Line 420, nav label | Add tooltip: "Re-verify all downloaded content files against the database" |
| **"SA Password" is opaque** to non-DBA admins | Lines 575-577 | Consider "SQL Admin Password (SA)" with helper text explaining this is the SQL Server system administrator account |
| **Hardcoded version strings in XAML** — "v3.8.3" (line 388) and "Version 3.8.10" (line 620) | XAML source | These are overwritten at runtime via `$controls.VersionLabel.Text` and `$controls.AboutVersion.Text`, but the XAML defaults should match `$script:AppVersion` to avoid confusion during development |
| **No microcopy on the Restore dialog** explaining data loss risk | `Show-RestoreDialog` | Add a warning TextBlock: "This will permanently replace the current SUSDB database. Create a backup first." below the title |

### Grade justification

Scores 3/4 because copywriting is clear, professional, and well-suited to the IT admin audience. Loses the 4th point for inconsistent icon treatment and a few labels that require users to click through to understand what they do.

---

## 2. Visuals — 2/4

### What works

- **Clean sidebar + content layout.** The 180px sidebar with grouped navigation and a resizable main content area follows established desktop admin tool patterns (similar to Server Manager, MMC snap-ins).
- **Status card design.** Four dashboard cards with colored top bars (3px) provide at-a-glance system health. The color changes dynamically based on thresholds — green → orange → red.
- **Consistent border radius.** `CornerRadius="4"` applied uniformly across all cards, panels, dialogs, and buttons. No visual inconsistency.
- **Corporate branding.** GA-ASI logos appear in the sidebar (32×32) and About page (56×56). Custom `wsus-icon.ico` for the window and system tray.
- **Splash screen.** Shows progress through 4 startup stages (Loading interface → Checking services → Starting → Ready) with a 4px progress bar. Non-blocking, non-fatal.
- **System tray integration.** Minimize-to-tray with balloon notification, context menu (Restore/Exit), and double-click restore.

### What to fix

| Issue | Location | Fix |
|---|---|---|
| **Unicode emoji for nav icons render inconsistently** across Windows versions and DPI settings. 📜, 🧹, 🔍, ⇄ may appear as black-and-white Segoe UI Symbol glyphs on Server 2019 or as color emoji on Win 11 | Lines 395-420 | Replace with WPF `Path` data or embedded vector icons for consistent rendering. Alternatively, use Segoe MDL2 Assets icon font (available on all target Windows versions) |
| **No transitions between panels.** Switching from Dashboard to Install is an instant visibility toggle — feels jarring | `Show-Panel` function, line 1479 | Add a 150ms fade-in via `DoubleAnimation` on Opacity. Even a simple opacity transition from 0→1 adds perceived quality |
| **History view is a raw ListBox** with monospace text — no visual hierarchy | Line 691 | Use a styled `ItemTemplate` with separate columns for timestamp, status icon, operation name, and duration. Add alternating row backgrounds (`#161B22` / `#21262D`) |
| **Progress bars are 4px tall** — easy to miss during operations | Lines 579, 582, 603, 604 | Increase to 6-8px and add an indeterminate mode for operations where progress can't be measured. Consider placing a spinner/icon next to the status label |
| **No empty-state illustrations.** Dashboard cards show "..." during loading and "N/A" when WSUS isn't installed — visually barren | Lines 1089-1093, 1105-1108 | Add a simple icon or illustration for "Not Installed" / "Offline" states. Even a 24×24 status icon next to the text adds visual weight |
| **Dialog layouts are plain StackPanels** with no visual grouping or section dividers | All `Show-*Dialog` functions | Add separators (like `$notifSep` in Settings dialog) between logical groups. Use `GroupBox` or border-wrapped sections for related inputs |
| **No active state indicator for Quick Action buttons.** When "Start Services" is running, only the text changes to "Starting..." — button color stays the same | Lines 3822-3853 | Change button background to `#D29922` (orange) while operation is in progress, revert on completion |

### Grade justification

Scores 2/4 because the visual foundation (layout, cards, color coding) is solid but the execution lacks polish. Unicode emoji icons, instant panel switching, monospace history, and minimal progress indicators pull the perceived quality below what the well-organized color system and layout structure would suggest.

---

## 3. Color — 3/4

### What works

- **Organized palette in XAML Resource Dictionary.** 11 named brushes (lines 294-304) establish a single source of truth. Colors are referenced via `{StaticResource Blue}` throughout the XAML, preventing drift.
- **GitHub Dark-inspired palette.** `#0D1117` background, `#161B22` sidebar, `#21262D` cards — this is a proven, professional dark palette with proper surface hierarchy (3 distinct levels).
- **3-tier text hierarchy.** Primary (`#E6EDF3`, ~87% white), Secondary (`#8B949E`, ~54%), Tertiary (`#484F58`, ~28%). Each serves a clear purpose: values, labels, meta/muted.
- **Semantic traffic-light system.** Green (`#3FB950`) = healthy/running, Orange (`#D29922`) = warning/partial, Red (`#F85149`) = critical/error. Applied consistently across all 4 dashboard cards, health score, last sync, history entries, and button variants.
- **Blue accent (`#58A6FF`) signals interactivity.** Used for primary action buttons, active nav border, section headers, and hyperlink-style text (email). Clear affordance.
- **Dynamic card top bars.** The 3px colored bars on dashboard cards change from green → orange → red based on health thresholds, providing at-a-glance status without reading text.

### What to fix

| Issue | Severity | Location | Fix |
|---|---|---|---|
| **Rogue green: `#238636`** used for Live Terminal "On" state, but the palette green is `#3FB950` | Medium | Lines 3865, 3942 | Replace `#238636` with `#3FB950` (or define it as a named brush if a "subtle green" is intended) |
| **Inline BrushConverter calls in dialogs** instead of StaticResource references. 150+ instances of `[System.Windows.Media.BrushConverter]::new().ConvertFrom("#...")` | Low (maintainability) | All `Show-*Dialog` functions | Programmatic dialogs can't use XAML StaticResources. Define script-scope brush variables: `$script:BrushBgDark = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")` and reference those instead of creating new converters each time |
| **No focus ring color defined.** WPF's default focus rectangle may be invisible against the dark background | Medium (a11y) | XAML styles | Add a `FocusVisualStyle` to button/textbox styles with a `#58A6FF` dashed border |
| **Disabled state contrast may be too low.** `#30363D` background + `#484F58` text = ~1.4:1 contrast ratio | Medium (a11y) | Lines 350-351 | Increase disabled text to `#6E7681` (~2.5:1) or add an icon overlay (e.g., 🔒) to signal disabled state through means beyond color alone |
| **`"White"` used directly** for some button foreground text instead of the named `Text1` resource | Low | Lines 334, 714, 940, 2494 | Replace `"White"` with `{StaticResource Text1}` or `#E6EDF3` for palette consistency |

### Grade justification

Scores 3/4 because the palette is well-organized, semantically consistent, and professionally selected. The surface hierarchy and text tiers are textbook-correct for a dark theme. Loses the 4th point for the rogue `#238636` green, missing focus indicators, and the contrast concern on disabled elements.

---

## 4. Typography — 2/4

### What works

- **Clear weight hierarchy.** Bold for titles/values (page title, card values, health score), SemiBold for section headers and button labels, Normal for body text and descriptions. Three weights create adequate differentiation.
- **Monospace for technical output.** `Consolas` at 11pt for log output, operation history, and console text. Appropriate for a sysadmin tool where users scan timestamps, paths, and error codes.
- **Size differentiation between levels.** Page title (20pt), card values (16pt), section headers (12-13pt), body text (11pt), sub-text (9-10pt). The jump from 11→16→20 creates visible hierarchy.

### What to fix

| Issue | Severity | Location | Fix |
|---|---|---|---|
| **12+ distinct font sizes.** Sizes used: 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24. Adjacent sizes (9, 10, 11, 12, 13) are barely distinguishable at normal viewing distance | High | Throughout XAML and dialogs | Consolidate to 6-7 sizes on a consistent scale. Recommended: **10** (caption/sub), **12** (body/nav), **14** (subhead), **16** (card value), **20** (page title), **24** (hero metric). Drop 9, 11, 13, 15, 18, 22 |
| **No explicit FontFamily declared.** The entire UI relies on WPF's system default (Segoe UI on Windows). If the system default changes or a different locale font substitutes, the layout may break | Medium | XAML Window element | Set `FontFamily="Segoe UI"` on the root `<Window>` element. This also documents intent explicitly |
| **LineHeight inconsistency.** Only `HelpText` (line 668) sets `LineHeight="20"`. All other multi-line text uses WPF's default (~1.2× font size), which can feel cramped for body text | Medium | Help text, About text, dialog descriptions | Set `LineHeight` on all TextBlocks containing descriptive paragraphs. Use 1.5× the font size as a baseline (e.g., 11pt body → LineHeight 16-17) |
| **Dialog inputs use 13pt** while the main window uses 11pt for equivalent content | Low | Schedule dialog XAML (lines 2355, 2418, 2429) | Standardize to 12pt for all inputs across both contexts, or define a `Style` resource for input controls |
| **Splash title (22pt) vs main window title (20pt)** — the splash has a larger title than the app itself | Low | Lines 814, 443 | Make both 20pt, or make the splash 24pt if it's intentionally a hero treatment |
| **Nav section headers (9pt Bold) are very small.** "SETUP", "TRANSFER", etc. at 9pt may strain readability | Medium | Lines 405, 410, 413, 418 | Increase to 10pt. Consider adding letter-spacing (CharacterSpacing in UWP, or Segoe UI Semibold at 10pt as a workaround) for small-caps labels |

### Grade justification

Scores 2/4 because while the weight hierarchy and monospace usage are solid, the lack of a type scale is the primary issue. Using nearly every point size between 9 and 24 creates visual noise rather than a clear hierarchy. There's no single source of truth for "what size should a body label be?" — it varies between 10, 11, and 12 depending on context.

---

## 5. Spacing — 2/4

### What works

- **Mostly 4px-multiple grid.** The majority of spacing values are multiples of 4: 4, 8, 12, 16, 20. This creates a perceived rhythm even without strict enforcement.
- **Consistent dialog margins.** All dialogs use `Margin="20"` for the outer StackPanel. This is one of the few truly consistent spacing values.
- **Card internal padding is uniform.** `Margin="12,14,12,12"` for all four dashboard card content areas. The 14px top accounts for the 3px colored bar.
- **Border radius consistency.** `CornerRadius="4"` everywhere — cards, panels, dialogs, buttons. No exceptions.
- **Section header pattern.** `Margin="16,14,0,4"` for all four nav section labels (SETUP, TRANSFER, MAINTENANCE, DIAGNOSTICS).

### What to fix

| Issue | Severity | Location | Fix |
|---|---|---|---|
| **11+ distinct spacing values** in active use: 1, 2, 4, 6, 8, 10, 12, 14, 16, 20, 32. Values like 1, 2, 6, 10, 14, 32 break the 4/8 grid | High | Throughout | Consolidate to a spacing scale: **4** (tight), **8** (compact), **12** (standard), **16** (section), **20** (panel), **32** (hero). Eliminate 1, 2, 6, 10, 14 |
| **Card-to-card margins are asymmetric.** First card: `Margin="0,0,8,0"`, middle cards: `Margin="4,0"`, last card: `Margin="8,0,0,0"`. The visual gap should be identical | Medium | Lines 457, 467, 477, 487 | Use `Margin="4,0"` for all cards. The `UniformGrid` parent distributes width; margins just need to create equal gaps |
| **Button padding varies across 4 sizes.** Primary: `14,8`, dialog: `14,6`, secondary small: `10,4`, log panel: `8,3` | Medium | Button styles and dialog code | Define 2 button sizes: Regular (`12,8`) and Small (`8,4`). Use XAML styles to enforce |
| **Main content margin `20,12` is inconsistent.** 20px horizontal but only 12px vertical — creates unbalanced breathing room | Low | Line 427 | Change to `20,16` or `16,16` for balanced padding |
| **Label-to-input spacing varies.** Three different values found: `"0,0,0,4"`, `"0,0,0,6"`, `"0,12,0,4"` for the same label→textbox relationship | Medium | Dialog functions | Standardize to `"0,0,0,4"` for label-to-input gap, `"0,0,0,12"` for field-to-field gap |
| **TextBox height is hardcoded (28px)** in XAML rather than derived from font size + padding | Low | Lines 572, 576, 578 | Remove explicit `Height="28"` and let the TextBox size itself from `Padding="6,4"` + font size. This is more robust across DPI scales |

### Grade justification

Scores 2/4 because the intent is clearly a 4px grid, but execution allows too many off-grid values. The asymmetric card margins and 4 different button padding values create subtle visual inconsistency that, while not immediately obvious, undermines the overall sense of precision.

---

## 6. Experience Design — 3/4

### What works

- **Keyboard shortcuts with discoverability.** Ctrl+D (Diagnostics), Ctrl+S (Sync), Ctrl+H (History), Ctrl+R/F5 (Refresh). Tooltips on buttons hint at shortcuts. ESC closes all dialogs.
- **Operation concurrency guard.** Only one operation can run at a time. All buttons disable with 50% opacity. Cancel button appears. Status label updates. This prevents conflicts that could corrupt the WSUS database.
- **Context-aware button states.** When WSUS isn't installed, all operations except "Install WSUS" are disabled with a tooltip explaining why. When in Air-Gap mode, online-only operations (Sync, Schedule) are disabled.
- **Multi-mode operation execution.** Users can choose between embedded log (in-app output) and live terminal (external PowerShell console). Settings persist. This accommodates both "quick check" and "need to interact" workflows.
- **Dashboard auto-refresh (30s)** with refresh guard (prevents concurrent refreshes). Only refreshes when the dashboard panel is visible — doesn't waste cycles on other views.
- **Completion notifications.** 3-tier fallback: Windows 10 toast → balloon notification → log-only. Configurable beep. Shows operation name and duration.
- **Settings persistence.** All preferences (paths, mode, notifications, terminal mode, tray behavior) save to `%APPDATA%\WsusManager\settings.json` and restore on launch.
- **Internet status indicator.** Auto-detects online/offline status. Left-click toggles manual override. Right-click returns to auto-detect. Tooltip explains the interaction.
- **Password strength validation.** Real-time strength meter (hidden until typing), requirement text, confirm-password match. Install button stays disabled until all criteria met.
- **Confirmation dialogs for destructive operations.** Deep Cleanup, Reset Content, and Restore all show explicit confirmation dialogs explaining consequences and estimated duration.
- **DPI awareness.** Per-monitor DPI on Windows 8.1+, system-level fallback on Vista+. Graceful degradation if the API isn't available.
- **Global error handling.** Fatal exceptions show a user-friendly dialog with the error message, log the stack trace, and exit gracefully. E2E probe mode tracks popup events for automated testing.

### What to fix

| Issue | Severity | Location | Fix |
|---|---|---|---|
| **Dashboard cards show "..." during loading** — no skeleton or spinner indicates progress | Medium | Lines 462, 472, 482, 492 | Replace "..." with a pulsing animation or add a "Refreshing..." overlay. Even changing the text to "Loading..." is more informative |
| **History view has no search or filter.** Admins running 50+ operations need to find specific entries | Medium | History panel (lines 675-694) | Add a TextBox filter above the ListBox. Filter on operation type, result (Pass/Fail), or date range |
| **No progress percentage in embedded mode.** Long operations (Deep Cleanup: 30+ min, Sync: 120 min) show only scrolling log text | Medium | Embedded log operation handler | Parse progress indicators from CLI output (percentages, step counts) and update a progress bar or status label |
| **Panel switching is instant** with no visual transition | Low | `Show-Panel` function | See Visuals section — add a 150ms fade-in |
| **Tab order is not explicitly managed.** WPF assigns tab order by visual tree position, which may not match logical flow | Medium | XAML and dialog code | Set `TabIndex` on interactive controls in dialogs. Ensure the flow goes: title → inputs → primary button → cancel |
| **No visible focus indicators in dark theme.** The default WPF focus rectangle is nearly invisible against `#0D1117` | Medium (a11y) | XAML styles | Define `FocusVisualStyle` with a `#58A6FF` dashed or solid border for all focusable controls |
| **Help content is static text.** No expandable sections, no hyperlinks, no search | Low | Help panel (lines 650-672) | Consider `Expander` controls for each section, or add in-app links that navigate to the relevant panel (e.g., "Click Diagnostics" → opens Diagnostics) |
| **No estimated time remaining** for long operations | Low | Operation handlers | Show "Estimated: ~30 min" next to the status label based on `Get-WsusOperationTimeout` values |
| **Theme toggle reserved but not implemented.** `$script:ThemeMode = "Dark"` exists (line 100) but there's no light theme | Low | Settings dialog | Either implement the light theme or remove the variable to avoid confusion. If keeping the reservation, add a disabled "Light theme coming soon" toggle in Settings |

### Grade justification

Scores 3/4 because the experience design is thoughtful and covers the important bases: concurrency safety, keyboard shortcuts, state persistence, multi-mode output, DPI awareness, and graceful error handling. This is above-average for an IT admin tool. Loses the 4th point for missing loading indicators, no history search, absent focus management, and the lack of progress tracking during long operations.

---

## Top 3 Fixes (Highest Impact)

1. **Consolidate the type scale to 6-7 sizes.** (Typography, High) The 12+ font sizes create visual noise. Define a systematic scale (10/12/14/16/20/24) and replace all ad-hoc sizes. This single change will make every screen feel more intentional.

2. **Consolidate the spacing scale to 6 values.** (Spacing, High) Standardize on 4/8/12/16/20/32 and fix the asymmetric card margins and varying button padding. Combined with the type scale fix, this establishes a visual grid that makes future changes predictable.

3. **Replace Unicode emoji nav icons with Segoe MDL2 Assets glyphs.** (Visuals, Medium) Unicode emoji render inconsistently across Windows Server versions. Segoe MDL2 Assets is available on all target platforms (Server 2019+, Win 10+) and renders at consistent weight and alignment. This eliminates the most visible source of visual inconsistency.

---

## Secondary Fixes

4. **Add focus indicators** (`FocusVisualStyle` with `#58A6FF` border) for accessibility compliance
5. **Fix the rogue `#238636` green** — replace with `#3FB950` or define as a named brush
6. **Add loading state to dashboard cards** — replace "..." with a shimmer or "Loading..." text
7. **Add search/filter to History view** — TextBox above ListBox filtering by type, result, or date
8. **Set explicit `FontFamily="Segoe UI"`** on the root Window element
9. **Standardize label-to-input spacing** at `"0,0,0,4"` across all dialogs
10. **Add 150ms fade-in** when switching panels for smoother navigation feel

---

## Appendix: Color Palette Reference

| Token | Hex | Usage |
|---|---|---|
| BgDark | `#0D1117` | Window/page background |
| BgSidebar | `#161B22` | Sidebar, log panel background |
| BgCard | `#21262D` | Cards, inputs, secondary buttons |
| Border | `#30363D` | Borders, dividers, disabled background |
| Blue | `#58A6FF` | Primary accent, active nav, links |
| Green | `#3FB950` | Success, healthy, running |
| Orange | `#D29922` | Warning, partial, caution |
| Red | `#F85149` | Error, critical, destructive |
| Text1 | `#E6EDF3` | Primary text (~87% white) |
| Text2 | `#8B949E` | Secondary text (~54%) |
| Text3 | `#484F58` | Tertiary/muted text (~28%) |
| *(rogue)* | `#238636` | Live Terminal "On" toggle — should use Green |

## Appendix: Font Size Inventory

| Current Size | Count | Proposed Scale |
|---|---|---|
| 9pt | 5 uses | → 10pt (caption) |
| 10pt | 12 uses | 10pt (caption) ✓ |
| 11pt | 25+ uses | → 12pt (body) |
| 12pt | 10 uses | 12pt (body) ✓ |
| 13pt | 8 uses | → 12pt or 14pt |
| 14pt | 6 uses | 14pt (subhead) ✓ |
| 15pt | 1 use | → 14pt or 16pt |
| 16pt | 4 uses | 16pt (card value) ✓ |
| 18pt | 2 uses | → 20pt |
| 20pt | 1 use | 20pt (page title) ✓ |
| 22pt | 1 use | → 20pt or 24pt |
| 24pt | 1 use | 24pt (hero metric) ✓ |
