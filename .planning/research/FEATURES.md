# Feature Research

**Domain:** WPF theming system — built-in color schemes with live-preview theme picker
**Researched:** 2026-02-20
**Confidence:** HIGH (WPF theming is a mature, well-documented domain; patterns are stable and verified against official docs and multiple implementation guides)

---

## Context: What This Milestone Adds

This research covers only the v4.3 theming milestone. The broader WSUS feature set is documented in the prior iteration of this file (the v4.0–4.2 feature landscape). The question here is: what does a good WPF theming system look like, and which features are table stakes vs differentiators for a theme picker in a desktop admin tool?

**Existing structure to build on:**
- `src/WsusManager.App/Themes/DarkTheme.xaml` — single ResourceDictionary with all brushes and styles
- `App.xaml` — merges `DarkTheme.xaml` via `MergedDictionaries`
- `AppSettings.cs` — JSON-persisted settings model, no `Theme` property yet
- `SettingsDialog.xaml` — modal dialog with server mode, refresh interval, content path, SQL instance
- All XAML currently uses `StaticResource` — must be converted to `DynamicResource` for live switching

**Critical discovery:** The existing codebase uses `StaticResource` throughout the XAML views. Live theme switching requires `DynamicResource` bindings. Migrating `StaticResource` to `DynamicResource` in styles and control templates is the foundational prerequisite — not just writing new theme files.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that any theme picker must have. Missing these makes the feature feel broken or unfinished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Multiple built-in themes (no custom builder) | Users expect shipped themes to pick from, not a color editor | LOW | 6 themes already planned: Default Dark, Just Black, Slate, Serenity, Rose, Classic Blue |
| Theme applies to the entire UI immediately | Partial theming (some panels change, others don't) looks broken | MEDIUM | Requires all resource keys covered in every theme file + DynamicResource bindings throughout |
| Selected theme persists across restarts | Preference lost on close = frustrating regression | LOW | Add `Theme` string field to `AppSettings.cs`, persist via existing `SettingsService` |
| Theme accessible from Settings dialog | Settings is already where configuration lives; theme must be there too | LOW | Add a "Appearance" section to the existing `SettingsDialog.xaml` |
| Visual swatch or preview in the picker | Text-only list of theme names doesn't help users choose | LOW | Color swatch (small rectangle showing accent + background color) beside each name |
| Default theme selected on first run | App must have a working theme out of the box | LOW | `AppSettings.Theme` defaults to `"DefaultDark"` |
| Theme names are human-readable | "theme_01" or "DarkTheme.xaml" are not acceptable labels | LOW | "Default Dark", "Just Black", "Slate", "Serenity", "Rose", "Classic Blue" |

### Differentiators (Competitive Advantage)

Features that go beyond the minimum. Worth building because they polish the experience for an admin tool that people use daily.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Live preview — theme applies before Save is clicked | Chrome-style instant feedback; users see the result before committing | MEDIUM | Apply theme when swatch is selected; revert if Cancel is clicked; confirm on Save |
| Active theme visually indicated in picker | Makes it obvious which theme is currently active without reading the name | LOW | Checkmark or highlight border on the currently active swatch |
| Theme designed with semantic intent (not just color) | Themes with coherent intent (e.g., "Serenity" = blue-green calming) feel curated, not random | LOW | Design choice, not implementation work — name and pick colors purposefully |
| Smooth transition on theme switch | Hard cut on theme change is jarring for a live-preview flow | MEDIUM | Optional: 150ms opacity fade on the main window; low risk, visible polish; skip if it adds complexity |
| Theme swap does not require restart | Modern expectation — restart to apply theme is a 2010-era pattern | MEDIUM | Requires DynamicResource migration; worth doing right |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Custom color editor / theme builder | Power users want to set any hex color | Huge scope: color picker UI, per-key overrides, export/import, validation, preventing illegible combinations | Provide 6 well-designed themes; cover the range of preferences (dark, black, neutral, warm, cool) |
| Per-section theming (different theme for sidebar vs main content) | "More control" | Visual incoherence; themes are only coherent when applied globally | Apply theme globally; design themes with appropriate contrast ratios throughout |
| Light themes | Some users prefer light mode | This is a server admin tool used in data centers and dimly lit server rooms; light themes conflict with the product's identity and the existing "dark is table stakes" finding from the v4.0 research | All 6 planned themes are dark-family; do not introduce light themes |
| Theme preview window (separate floating preview) | "See what it looks like before applying" | The live-preview-on-click approach covers this without added UI surface; a separate preview window is more work and worse UX | Live apply + Cancel revert is the right pattern |
| Importing external .xaml theme files | Extensibility for advanced users | External XAML execution is a code injection vector; single-file EXE deployment means no external files are expected; adds a file browser and validation UI | Ship 6 themes; cover the range; do not open the door to arbitrary XAML loading |
| Font size / font family picker | Accessibility or preference customization | Significantly complicates layout (fixed-height panels assume specific font sizes); DPI awareness already handles scale | DPI awareness covers the scale need; fixed fonts maintain layout integrity |

---

## Feature Dependencies

```
[DynamicResource Migration — PREREQUISITE]
    └──required by──> [Live Theme Switching]
    └──required by──> [Live Preview]
    (without DynamicResource, theme change requires restart at minimum
     and may not propagate to styles/templates at all)

[Theme ResourceDictionary Files (6 files)]
    └──required by──> [Theme Service]
    └──required by──> [Theme Picker UI]

[Theme Service]
    └──required by──> [Theme Picker UI — Apply action]
    └──required by──> [App startup — restore persisted theme]

[AppSettings.Theme field]
    └──required by──> [Theme persistence]
    └──required by──> [Theme Service — startup restore]
    └──depends on──> [existing SettingsService (already built)]

[Theme Picker UI (swatch grid in SettingsDialog)]
    └──uses──> [Theme Service]
    └──uses──> [AppSettings.Theme for active indicator]
    └──depends on──> [existing SettingsDialog (already built)]

[Live Preview]
    └──requires──> [Theme Service (apply without save)]
    └──requires──> [Cancel revert logic in SettingsDialog]
    └──enhances──> [Theme Picker UI]
```

### Dependency Notes

- **DynamicResource migration is the load-bearing prerequisite.** The existing codebase uses `StaticResource` everywhere. A swap of the MergedDictionary source at runtime will not propagate to controls that use `StaticResource` — they are baked at load time. Every `{StaticResource BgDark}`, `{StaticResource Text1}`, etc. in `.xaml` view files must become `{DynamicResource ...}`. This is the highest-risk work item. The `DarkTheme.xaml` style definitions that use `StaticResource` internally (e.g., hover triggers with hardcoded `#21262D`) also need to be converted to use named resources.

- **Theme Service is the pivot point.** It owns the swap logic (`Application.Current.Resources.MergedDictionaries`), knows all valid theme names, and is called by both the Settings dialog (live preview) and the app startup (restore). Keep it as a simple static class or singleton — it does not need async.

- **Live preview requires a revert path.** When the user hovers or clicks a swatch, the theme applies live. If they hit Cancel, the previous theme must be restored. The SettingsDialog must capture the "entry state" theme name on open and revert to it on Cancel.

- **AppSettings.Theme field does not exist yet.** It must be added to `AppSettings.cs` with a default of `"DefaultDark"` before the settings persistence path works.

---

## MVP Definition

This is a bounded milestone, not a product launch. MVP means: the feature ships and is usable, with the live-preview Chrome-style picker.

### Launch With (v4.3 — Themes milestone)

- [ ] DynamicResource migration in all `.xaml` view files — prerequisite; nothing else works without this
- [ ] 6 theme ResourceDictionary files with consistent key coverage — the deliverable
- [ ] Theme Service to swap themes at runtime — the mechanism
- [ ] `AppSettings.Theme` field + startup restore — persistence
- [ ] Theme picker section in Settings dialog with swatches and active indicator — the UX
- [ ] Live preview (apply on click, revert on Cancel) — the differentiator
- [ ] Hardcoded colors in `MainWindow.xaml` nav button trigger styles converted to named resources — blocks theming

### Add After Validation (v4.x)

- [ ] Smooth fade transition on theme switch — only if live preview lands smoothly; skip if it adds risk
- [ ] High-contrast accessibility theme — defer; requires accessibility audit

### Future Consideration (v5+)

- [ ] Theme import from external file — explicitly an anti-feature for now; revisit only if user demand is demonstrated

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| DynamicResource migration | HIGH (blocks all theming) | MEDIUM | P1 — prerequisite |
| 6 theme files | HIGH | LOW | P1 — the actual deliverable |
| Theme Service | HIGH | LOW | P1 — mechanism |
| AppSettings.Theme + persistence | HIGH | LOW | P1 — survival across restart |
| Settings dialog swatch picker | HIGH | LOW | P1 — the UX surface |
| Active theme indicator | MEDIUM | LOW | P1 — expected in any picker |
| Live preview with Cancel revert | HIGH | MEDIUM | P1 — the differentiator |
| Smooth fade transition | LOW | MEDIUM | P2 — polish only |
| Custom color editor | LOW | HIGH | P3 / anti-feature |
| External theme import | LOW | HIGH | Anti-feature — skip |

---

## How Chrome's Theme Picker Maps to WPF

Chrome's theme picker (in Settings > Appearance) is the reference model for this milestone. Here is how each Chrome concept maps to what we are building:

| Chrome Concept | Chrome Implementation | Our WPF Equivalent |
|----------------|-----------------------|--------------------|
| Theme color swatches grid | Row of colored circles; click to apply instantly | Row of rectangular swatches in SettingsDialog showing each theme's accent + background colors |
| Live preview on click | Entire browser chrome re-colors immediately | `ThemeService.Apply(themeName)` called on swatch click; no Save required for the visual change |
| Active theme checkmark | Filled checkmark on selected swatch | Border highlight or checkmark overlay on the active swatch |
| Cancel / no explicit revert | Chrome has no cancel; change is immediate and permanent | Our app has a Cancel button on SettingsDialog; it must revert to the entry-state theme |
| Theme name label | Small label below swatch | TextBlock below each swatch with the theme's display name |
| "Reset to default" | Separate button | Not needed for v4.3; Default Dark is always in the list |
| Custom color picker | Full-color wheel in Chrome 100+ | Anti-feature for us — not building |

The Chrome model works for a browser because any change is instantly reversible by picking another theme. In our app, Settings has a Save/Cancel contract. The right adaptation is: live-apply on swatch click, but respect Cancel by reverting. This is strictly better UX than "apply only after Save" with no preview.

---

## Implementation Notes for Roadmap

These findings directly inform phase ordering and task granularity:

1. **Start with DynamicResource migration, not theme files.** Writing beautiful themes before the plumbing works wastes effort. The migration task should be Phase 1 of this milestone.

2. **Hardcoded hex values in MainWindow.xaml are a blocker.** The `#21262D`, `#58A6FF`, and `#E6EDF3` values in the nav button trigger styles (not using named resources) will resist theme switching. These 15 occurrences across 4 view files must be extracted to named resource keys in each theme file.

3. **Theme file structure must be exact.** Every theme file must define all the same resource keys that `DarkTheme.xaml` defines. A missing key in one theme causes `{DynamicResource ...}` to silently fall back or throw at runtime. A checklist of required keys should gate each theme file.

4. **SettingsDialog needs a new section, not a new dialog.** The theme picker lives in the existing Settings dialog. Increase the dialog height and add an "Appearance" section above the buttons. This avoids the navigation cost of a second modal.

5. **Cancel revert is the trickiest part of live preview.** The SettingsDialog must capture `currentTheme` on open (before any swatch clicks) and restore it in the Cancel handler. This requires the SettingsDialog to know the active theme at construction time — pass it as a constructor parameter alongside `AppSettings`.

---

## Sources

- [WPF Complete Guide to Themes and Skins — Michael's Coding Spot](https://michaelscodingspot.com/wpf-complete-guide-themes-skins/) — MEDIUM confidence (blog, verified against official docs)
- [Changing WPF Themes Dynamically — Marko Devcic](https://www.markodevcic.com/post/Changing_WPF_themes_dynamically/) — MEDIUM confidence (community, multiple sources agree)
- [WPF How To Switching Themes at Runtime — Telerik Docs](https://docs.telerik.com/devtools/wpf/styling-and-appearance/how-to/styling-apperance-themes-runtime) — HIGH confidence (vendor documentation)
- [ResourceDictionary and XAML Resource References — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/style/xaml-resource-dictionary) — HIGH confidence (official Microsoft documentation)
- [StaticResource vs DynamicResource — CodeProject](https://www.codeproject.com/Articles/393086/WPF-StaticResource-vs-DynamicResource) — MEDIUM confidence (community, well-cited)
- [Mastering Dynamic Resources in WPF — Moldstud](https://moldstud.com/articles/p-mastering-dynamic-resources-in-wpf-a-comprehensive-guide-for-developers) — LOW confidence (single source, useful for general guidance)
- Existing codebase inspection: `DarkTheme.xaml`, `App.xaml`, `SettingsDialog.xaml`, `SettingsDialog.xaml.cs`, `AppSettings.cs`, `MainWindow.xaml` — HIGH confidence (direct code analysis)

---

*Feature research for: WPF theming system (v4.3 — GA-WsusManager)*
*Researched: 2026-02-20*
