# Phase 17: Theme Content and Picker - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Create 5 additional dark-family theme color dictionaries (completing the set of 6 total with Default Dark from Phase 16) and build a Chrome-style Appearance section in the Settings dialog with a live-preview swatch picker. Users can click a swatch to preview, Save to persist, or Cancel to revert. Phase 16's ThemeService infrastructure handles the runtime swapping — this phase creates content and UI.

</domain>

<decisions>
## Implementation Decisions

### Theme palettes
- 6 themes total, all dark-family (no light themes — data center use case):
  - **Default Dark** — existing theme from Phase 16 (warm charcoal, blue accent)
  - **Just Black** — true OLED black backgrounds, minimal contrast borders
  - **Slate** — cool blue-gray tones, steel accent
  - **Serenity** — muted teal/cyan accent on dark background
  - **Rose** — warm rose/pink accent on dark background
  - **Classic Blue** — traditional navy/royal blue corporate feel
- Each theme file provides all 19 semantic color keys defined in Phase 16
- WCAG 2.1 AA contrast compliance: 4.5:1 ratio for text on backgrounds

### Swatch picker layout
- 3x2 grid of rectangular color swatches in Settings dialog Appearance section
- Each swatch shows the theme's primary background + accent color as a mini preview
- Theme name label below each swatch
- Active theme has a highlighted border (accent-colored) or checkmark indicator

### Live preview behavior
- Clicking any swatch calls ThemeService.ApplyTheme() immediately — entire app updates while Settings is still open
- No confirmation step between click and preview — instant feedback (Chrome model)
- Swatch active indicator updates to reflect the newly previewed theme

### Cancel/Save behavior
- On Settings dialog open: capture `ThemeService.CurrentTheme` as the entry-state theme name
- On Cancel: call `ThemeService.ApplyTheme(entryStateTheme)` to revert
- On Save: persist selected theme to settings.json via AppSettings, theme stays applied
- Theme persists across restarts (ThemeService reads from settings.json on startup — already built in Phase 16)

### Settings dialog integration
- Add "Appearance" section to existing SettingsDialog.xaml
- Position: above or below existing settings sections (Claude's discretion on exact placement)
- Section header: "Appearance" with theme picker grid below it

### Claude's Discretion
- Exact hex color values for each theme palette (as long as they meet WCAG AA contrast)
- Swatch rendering details (corner radius, size, spacing, shadow)
- Whether active indicator is a border highlight or a checkmark overlay
- Exact placement of Appearance section within Settings dialog layout
- Animation/transition when theme swaps (if any — keep subtle)

</decisions>

<specifics>
## Specific Ideas

- Chrome Settings > Appearance is the reference model: click a swatch, instant preview, no extra confirmation
- Swatches should feel like color chips — small, clean, immediately scannable
- All themes are dark-family only — light themes explicitly excluded (contradicts data center/server room use case)
- Research identified that SettingsDialog must capture currentTheme at construction for Cancel revert
- Theme names should be user-friendly labels, not technical identifiers

</specifics>

<deferred>
## Deferred Ideas

- Custom color editor (per-key overrides) — explicitly excluded as anti-feature (scope explosion)
- External theme file import — explicitly excluded (code injection risk, conflicts with single-EXE deployment)
- Font customization — excluded (DPI awareness is sufficient)
- Per-section theming — excluded (visual incoherence risk)

</deferred>

---

*Phase: 17-theme-content-and-picker*
*Context gathered: 2026-02-20*
