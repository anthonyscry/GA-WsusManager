# Project Research Summary

**Project:** GA-WsusManager v4.3 — Runtime Theme Switching
**Domain:** WPF/.NET 8 runtime theming system for an existing C# admin GUI application
**Researched:** 2026-02-20
**Confidence:** HIGH

## Executive Summary

The v4.3 milestone adds a 6-theme runtime color scheme switcher to an existing C#/.NET 8 WPF application. The research verdict is clear and low-risk: native WPF `ResourceDictionary` merging with `DynamicResource` bindings is the correct and complete solution. No new NuGet packages are required. No external theming library should be considered. The foundation already exists — `Themes/DarkTheme.xaml` establishes the right architectural pattern; the v4.3 work is a migration and extension of what is already there.

The single highest-risk item is the foundational prerequisite: the existing codebase uses `{StaticResource}` throughout all 8 XAML files (283 total references). `StaticResource` is resolved once at XAML parse time and never updates. Every color/brush reference must become `{DynamicResource}` before a runtime theme swap has any visible effect. Additionally, `DarkTheme.xaml` currently mixes color token definitions with structural style definitions — these must be split into two separate files (`DarkTheme.xaml` for color tokens only, `SharedStyles.xaml` for all style blocks) before any non-default theme can work correctly. These two foundational changes gate all other work and must be completed and verified before writing a single non-default theme file.

The live-preview interaction pattern (apply theme immediately on swatch click, revert on Cancel) is the key differentiator identified in feature research and maps directly to Chrome's theme picker model. It is achievable with low implementation complexity once the infrastructure is correct, but requires careful Cancel-revert logic: the SettingsDialog must snapshot the active theme name on open and restore it if the user cancels. Six additional pitfalls are documented in PITFALLS.md — hardcoded hex values in XAML, hardcoded `SolidColorBrush` creation in `MainViewModel.cs`, `BasedOn` style inheritance constraints, theme flash on startup, missing keys in non-default themes, and ComboBox system-color bleed — each with concrete prevention strategies. None require significant rework if addressed in Phase 1.

---

## Key Findings

### Recommended Stack

Runtime theme switching in WPF is entirely a native platform capability. The stack addition for v4.3 is zero new NuGet packages. The existing base stack (C#/.NET 8, WPF, CommunityToolkit.Mvvm, Serilog, xUnit + Moq) is unchanged. The mechanism is: (1) theme XAML files define color token resources with identical keys across all themes; (2) all color references in XAML views use `DynamicResource` instead of `StaticResource`; (3) a `ThemeService` class swaps the active theme dictionary in `Application.Current.Resources.MergedDictionaries` at runtime; (4) WPF's resource notification system automatically propagates the change to all bound elements.

All external theming libraries (MaterialDesignInXamlToolkit, MahApps.Metro, HandyControl, FluentWPF/Wpf.Ui) were explicitly researched and rejected. They impose opinionated control libraries that conflict with the existing custom GA-AppLocker-style dark theme and would require full style rewrites — out of scope and high risk. External JSON theme files (loose files on disk) were also rejected: they break the single-EXE deployment constraint and have no design-time support. Embedded XAML files with `Resource` build action are the correct approach — they compile into the EXE assembly and work correctly with `PublishSingleFile=true`.

**New components (zero new NuGet packages):**
- `DynamicResource` bindings (WPF built-in) — allows resource values to propagate to controls at runtime; replaces existing `StaticResource` for all color/brush keys
- `Themes/SharedStyles.xaml` (new XAML file) — structural styles extracted from `DarkTheme.xaml`; references color tokens via `{DynamicResource}`; merged permanently in `App.xaml`, never swapped
- 5 additional `*Theme.xaml` files (new XAML files, `Resource` build action) — one file per additional color scheme; all defining the same 22 token keys (14 original + 8 new for hardcoded hex extraction)
- `IThemeService` + `ThemeService` (new C# class in `WsusManager.App/Services/`) — encapsulates dictionary swap logic, maps theme name to XAML URI, tracks current theme, exposes `ThemeChanged` event
- `SelectedTheme` property on `AppSettings` (string, default `"Default Dark"`) — persists selected theme via existing `ISettingsService` JSON path; no new persistence infrastructure needed

**Version compatibility:** All mechanisms confirmed compatible with .NET 8 WPF and `PublishSingleFile=true`. Pack URI format `pack://application:,,,/AssemblyName;component/Themes/File.xaml` (or relative `new Uri("Themes/DarkTheme.xaml", UriKind.Relative)`) works correctly with single-file EXE publication — WPF resources are compiled into the assembly before bundling.

### Expected Features

The feature research identified the MVP for a theme picker in a daily-use server admin tool. Light themes were explicitly identified as an anti-feature for this product — all 6 themes are dark-family (appropriate for server rooms and data center environments where the existing dark-is-table-stakes identity must be maintained).

**Must have (table stakes):**
- 6 built-in themes — users expect shipped themes to pick from; planned: Default Dark, Just Black, Slate, Serenity, Rose, Classic Blue
- Theme applies to entire UI immediately — partial theming looks broken; requires DynamicResource migration throughout all 8 XAML files
- Selected theme persists across restarts — lost preference is a regression; `SelectedTheme` field in `AppSettings`
- Theme accessible from Settings dialog — configuration belongs in Settings; add an "Appearance" section
- Visual swatches in the picker — text-only theme names do not help users choose; 3x2 swatch grid showing each theme's colors
- Default theme on first run — `AppSettings.SelectedTheme` defaults to `"Default Dark"`
- Human-readable theme names — display names, not file names

**Should have (differentiators):**
- Live preview — theme applies before Save is clicked; Chrome-style instant feedback; revert on Cancel; this is the key UX differentiator
- Active theme indicator in picker — checkmark or highlight border on the currently active swatch
- Theme swap without restart — modern expectation; enabled by DynamicResource migration

**Defer to v4.x:**
- Smooth fade transition on theme switch — low value, medium complexity; skip if it adds risk
- High-contrast accessibility theme — defer; requires accessibility audit

**Anti-features (explicitly not building):**
- External theme file import — code injection vector; single-file EXE constraint; not building
- Custom color editor — enormous scope; 6 well-designed themes cover the range; not building
- Light themes — conflicts with product identity and server-room use case; not building
- Per-section theming — visual incoherence; themes are only coherent when applied globally

### Architecture Approach

The theming architecture follows a strict token/style split. Color token dictionaries (one per theme, swappable) define only the 22 brush and color resources. The `SharedStyles.xaml` dictionary (permanent, never swapped) defines all structural styles — `NavBtn`, `BtnGreen`, `BtnRed`, `LogTextBox`, custom `ProgressBar` template, `ScrollBar` style, etc. — referencing color tokens via `{DynamicResource}`. This split is the foundational architectural requirement: keeping styles in the swappable dictionary destroys and recreates them on every theme change, producing visual flicker and style loss on affected controls.

The `ThemeService` is a UI-layer singleton registered in `Program.cs`. It lives in `WsusManager.App/Services/`, not `WsusManager.Core`, because it has a direct dependency on `Application.Current.Resources` (a WPF runtime object). The `MainViewModel` and `SettingsDialog` receive `IThemeService` via constructor injection. Theme switching is always synchronous and always called on the UI thread — `MergedDictionaries` manipulation is not thread-safe.

**Major components:**
1. `Themes/SharedStyles.xaml` (permanent, index 0 in `MergedDictionaries`) — all structural styles; references color tokens via `{DynamicResource}`; never touched at runtime
2. `Themes/*Theme.xaml` (6 swappable color files, index 1 in `MergedDictionaries`) — 22 token keys each; swapped at runtime by `ThemeService`
3. `ThemeService` — holds the URI map for all 6 themes; executes the `MergedDictionaries[1]` swap; exposes `CurrentTheme`, `AvailableThemes`, and `ThemeChanged` event
4. `SettingsDialog` (extended) — captures `_originalTheme` on open; calls `ApplyTheme` on swatch click for live preview; reverts on Cancel via `_themeService.ApplyTheme(_originalTheme)`; passes selected theme in `Result`
5. `MainViewModel` (extended) — injects `IThemeService`; calls `ApplyTheme` in `ApplySettings()` during startup; `GetBrush(key)` helper using `TryFindResource` replaces all `Color.FromRgb()` constants for dashboard card colors; subscribes to `ThemeChanged` to refresh brush properties

**Data flows:**
- Swatch click → `SettingsDialog.OnThemeSelected` → `_themeService.ApplyTheme(name)` → `MergedDictionaries[1]` swapped → WPF propagates to all `DynamicResource` bindings automatically
- Cancel → `_themeService.ApplyTheme(_originalTheme)` → reverts to pre-dialog state; does not save to JSON
- Save → `Result.SelectedTheme` returned → `_settingsService.SaveAsync` → JSON persisted; theme already applied, no second call needed
- Startup → `App.xaml.cs` `OnStartup()` → `_settingsService.Load()` → `_themeService.ApplyTheme(settings.SelectedTheme)` → before `MainWindow.Show()` (prevents theme flash)

### Critical Pitfalls

1. **StaticResource references do not update on theme swap** — All 283 `{StaticResource}` color references across 8 XAML files must become `{DynamicResource}`. Style key references (`{StaticResource NavBtn}`) must stay as `StaticResource`. Verify completion with grep for `StaticResource Bg`, `StaticResource Text`, `StaticResource Blue`, etc. — zero results means complete.

2. **Inline hardcoded hex colors in XAML bypass the theming system** — `MainWindow.xaml` DataTrigger setters hardcode `#21262D`, `#58A6FF`, `#E6EDF3`. Multiple dialogs hardcode `#F85149`. `DarkTheme.xaml` ControlTemplate triggers hardcode `#238636`, `#2EA043`, `#DA3633`. All must be extracted to 8 new named resource keys added to all theme files: `NavActiveBackground`, `NavActiveAccent`, `NavActiveForeground`, `TextError`, `BtnPrimaryBg`, `BtnPrimaryHover`, `BtnDangerBg`, `BtnDangerHover`.

3. **Hardcoded SolidColorBrush in MainViewModel bypasses theming** — `MainViewModel.cs` creates brushes via `Color.FromRgb()` literals for dashboard card status bars and connection dot. These must be replaced with a `GetBrush(key)` helper using `Application.Current.TryFindResource(key)`. The `ThemeService` needs a `ThemeChanged` event so the ViewModel refreshes brush `ObservableProperty` values when the theme swaps.

4. **Styles in the swappable dictionary cause flash and style loss** — `DarkTheme.xaml` currently mixes color tokens and structural styles. Clearing the dictionary to swap themes destroys the structural styles. Must split into `SharedStyles.xaml` (permanent) and color-only theme files before implementing any non-default theme. This is the foundational architectural change that gates everything else.

5. **Live preview Cancel does not revert without an explicit snapshot** — SettingsDialog must capture `_originalTheme = _themeService.CurrentTheme` on open, before any swatch is clicked. Cancel handler must call `_themeService.ApplyTheme(_originalTheme)`. Without this, Cancel leaves the app in the last-previewed theme state until the next restart.

---

## Implications for Roadmap

Based on research, the work separates naturally into two phases with a strict dependency order. Phase 1 must be complete and verified before Phase 2 begins — writing theme files before the infrastructure is correct produces themes that appear to do nothing.

### Phase 1: Infrastructure and XAML Migration

**Rationale:** All theming work is blocked until the foundational plumbing is correct. The `StaticResource` migration and the token/style split are prerequisites for everything in Phase 2. This phase resolves Pitfalls 1, 2, 3, 4, 7, and 8 — the infrastructure-layer pitfalls — before any visible feature work begins. The app should render identically to today after Phase 1 completes; the only difference is that the architecture now supports runtime theme switching.

**Delivers:** A working single-theme app with correct theming infrastructure. `DarkTheme.xaml` contains only color tokens. `SharedStyles.xaml` contains all styles referencing color tokens via `DynamicResource`. All 8 XAML files use `DynamicResource` for color/brush references. `ThemeService` is registered and functional. `AppSettings` has `SelectedTheme`. Startup applies saved theme before window shows. `MainViewModel` retrieves brush colors from the resource dictionary, not from hardcoded constants.

**Work items:**
- Split `DarkTheme.xaml` into `SharedStyles.xaml` (styles) + `DarkTheme.xaml` (14 color tokens only); update `App.xaml` to merge both at indices 0 and 1
- Extract 8 hardcoded hex values from XAML setters and ControlTemplate triggers to new named resource keys; add all 8 to `DarkTheme.xaml`
- Migrate all 283 `{StaticResource}` color references to `{DynamicResource}` across 8 XAML files; keep style name references as `{StaticResource}`
- Implement `IThemeService` and `ThemeService` with URI map for all 6 themes and a `ThemeChanged` event; register as singleton in `Program.cs`
- Add `SelectedTheme` property to `AppSettings` (default: `"Default Dark"`)
- Apply saved theme in `App.xaml.cs` `OnStartup()` before `MainWindow` is created
- Replace `Color.FromRgb()` literals in `MainViewModel.cs` with `GetBrush(key)` via `TryFindResource`; subscribe to `ThemeChanged` to refresh brush `ObservableProperty` values
- Add debug-build key validation assertion covering all 22 required keys

**Avoids:** Pitfalls 1 (StaticResource), 2 (hardcoded hex), 3 (ViewModel brushes), 4 (styles in swappable dict), 7 (startup flash), 8 (duplicate keys after split)

**Research flag:** Standard WPF patterns — well-documented mechanisms. No phase research needed.

---

### Phase 2: Theme Files, Picker UI, and Live Preview

**Rationale:** Phase 1 establishes the correct infrastructure. Phase 2 delivers the visible feature: 5 additional theme color files and the Settings dialog picker with live preview. Writing theme files after the infrastructure is correct is purely mechanical — copy `DarkTheme.xaml`, change 22 color values, verify with the debug-build key assertion. The picker UI wires swatch clicks to an already-working `ThemeService`. Cancel revert is the trickiest implementation detail and is the primary risk in this phase.

**Delivers:** The complete v4.3 feature — 6 themes, Chrome-style live preview picker in Settings, active theme indicator, Cancel revert, and persistence across restarts.

**Work items:**
- Create 5 additional theme files (`JustBlackTheme.xaml`, `SlateTheme.xaml`, `SerenityTheme.xaml`, `RoseTheme.xaml`, `ClassicBlueTheme.xaml`), each defining all 22 required keys; verify each with WCAG 2.1 AA contrast ratio check (4.5:1 minimum) using https://webaim.org/resources/contrastchecker/
- Extend `SettingsDialog.xaml` with an "Appearance" section containing a 3x2 swatch grid; increase dialog height from 380px to ~500px; swatch colors are hardcoded in the picker XAML (presentational only — must show target theme while a different theme is active)
- Update `SettingsDialog.xaml.cs` to inject `IThemeService`, capture `_originalTheme` on open, wire swatch click to `ApplyTheme` for live preview, call `ApplyTheme(_originalTheme)` on Cancel, include `SelectedTheme` in `Result`
- Update `MainViewModel.cs` to inject `IThemeService`, call `ApplyTheme(settings.SelectedTheme)` in `ApplySettings()`
- Add implicit `ComboBox` and `TextBox` styles to `SharedStyles.xaml` to mitigate system-color bleed in dropdown popups (simplified approach — full ControlTemplate override deferred if not needed)
- Integration test all 4 scenarios: swatch click live preview, Cancel reverts, Save persists, restart restores

**Avoids:** Pitfalls 5 (BasedOn/DynamicResource — color values in derived styles use `DynamicResource`; `BasedOn` attribute remains `StaticResource`), 6 (Cancel revert with `_originalTheme` snapshot), 9 (missing keys — debug assertion from Phase 1 catches immediately), 10 (ComboBox system color — implicit style mitigation)

**Research flag:** Standard WPF patterns — no phase research needed. Color palette selection for 5 non-default themes is a design decision, not a research question.

---

### Phase Ordering Rationale

- **Infrastructure before themes:** Writing beautiful themes before the `StaticResource` → `DynamicResource` migration produces themes that appear to do nothing. The migration must be verified complete (grep returns zero results) before any non-default theme is authored.
- **Token/style split gates all theme files:** Adding a second theme without the split destroys the structural styles when the dictionary swaps. This is the most disorienting failure mode and hardest to debug after the fact. The split is the first task in Phase 1 for this reason.
- **ViewModel brush migration belongs in Phase 1:** The `ThemeService` needs a `ThemeChanged` event for `MainViewModel` brush properties to work. If deferred to Phase 2, the dashboard card status bars will be wrong for all non-default themes when Phase 2 ships. No user should ever see partially-themed dashboard bars.
- **5 additional theme files are the simplest part:** After the infrastructure is correct, writing a theme file is copy-paste-change-colors work. This is rightly the Phase 2 entry point, not the starting point.
- **Cancel revert is the trickiest Phase 2 item:** The `_originalTheme` snapshot must be captured before the first swatch click, not after. Requires care but is not complex once the pattern is clear.

### Research Flags

All implementation work follows well-documented WPF patterns. No phase requires a `/gsd:research-phase` call before implementation begins.

**Standard patterns — skip research phase for both phases:**
- Phase 1: WPF `DynamicResource` behavior, `MergedDictionaries` manipulation, and `TryFindResource` are Microsoft-official APIs with official documentation. The split/migration work is mechanical.
- Phase 2: Theme file authoring (color selection), swatch grid XAML layout, and `SettingsDialog` extension follow standard WPF patterns. The live preview + Cancel revert pattern is explicitly specified in the research.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Native WPF mechanisms verified against Microsoft official docs (updated 2024-10-24). Pack URI + `PublishSingleFile=true` compatibility confirmed. Zero new NuGet packages — no version uncertainty. |
| Features | HIGH | Feature set derived from Chrome's picker model (documented reference), WCAG 2.1 AA accessibility standards, and direct codebase audit. Anti-features clearly justified with rationale. |
| Architecture | HIGH | Token/style split pattern verified by multiple authoritative sources. `ThemeService` design follows established WPF singleton patterns. All 4 data flows traced (swatch click, Cancel, Save, startup). |
| Pitfalls | HIGH | All 10 pitfalls grounded in WPF's documented resource system behavior or direct codebase audit of `MainViewModel.cs`, `MainWindow.xaml`, `DarkTheme.xaml`, and all dialog `.xaml` files. Prevention strategies are specific and verifiable with grep or debug assertions. |

**Overall confidence:** HIGH

### Gaps to Address

- **Color palette design for 5 non-default themes** — The research specifies the theme names (Just Black, Slate, Serenity, Rose, Classic Blue) and the required key structure (22 keys) but does not specify exact hex color values. Color selection is a design decision, not a research question. Apply WCAG 2.1 AA contrast ratio (4.5:1 minimum) as the objective constraint. Use the WebAIM contrast checker (https://webaim.org/resources/contrastchecker/) during Phase 2 theme authoring.

- **ThemeChanged event design** — The research identifies that `MainViewModel.cs` brush `ObservableProperty` values must refresh when the theme changes, and that `ThemeService` needs a `ThemeChanged` event for this. The exact event signature and subscription pattern is left to Phase 1 implementation. Options: standard C# `event Action<string> ThemeChanged` on the service, or a messenger pattern via `CommunityToolkit.Mvvm.Messaging` (already in the project). Either approach is valid — resolve during Phase 1 implementation.

- **ComboBox/TextBox full ControlTemplate override** — The research recommends an implicit style approach as acceptable mitigation for Phase 2, with full `ControlTemplate` override deferred. If visual review during Phase 2 integration testing shows unacceptable system-color bleed in ComboBox dropdowns across non-default themes, the scope will need to expand. Flag during Phase 2 integration testing before declaring the milestone complete.

---

## Sources

### Primary (HIGH confidence)
- [Merged resource dictionaries — WPF .NET (Microsoft Learn, updated 2024-10-24)](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/systems/xaml-resources-merged-dictionaries?view=netdesktop-8.0) — dictionary swap pattern, pack URI formats, Resource build action requirement
- [Pack URIs in WPF — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/app-development/pack-uris-in-wpf) — embedded resource URI format for single-file apps
- [XAML resources overview — WPF | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/systems/xaml-resources-overview) — StaticResource vs DynamicResource resolution behavior
- [Styles and templates — WPF | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/styles-templates-overview?view=netdesktop-9.0) — BasedOn limitation, style inheritance chain
- [WPF How To Switching Themes at Runtime — Telerik UI for WPF](https://docs.telerik.com/devtools/wpf/styling-and-appearance/how-to/styling-apperance-themes-runtime) — runtime switching pattern (vendor documentation)
- [CommunityToolkit.Mvvm IoC documentation — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/ioc) — DI registration pattern
- [ResourceDictionary and XAML Resource References — Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/style/xaml-resource-dictionary) — general resource dictionary behavior
- GA-WsusManager codebase direct audit — 283 `StaticResource` refs across 8 XAML files; 15 `Color.FromRgb()` literals in `MainViewModel.cs`; 14 token keys in `DarkTheme.xaml`; complete hardcoded hex location inventory

### Secondary (MEDIUM confidence)
- [Changing WPF themes dynamically — Marko Devcic](https://www.markodevcic.com/post/Changing_WPF_themes_dynamically/) — DynamicResource requirement, dictionary swap runtime pattern; corroborates official docs
- [WPF Complete Guide to Themes and Skins — Michael's Coding Spot](https://michaelscodingspot.com/wpf-complete-guide-themes-skins/) — StaticResource vs DynamicResource runtime behavior, SkinResourceDictionary pattern tradeoffs
- [WPF Merged Dictionary problems and solutions — Michael's Coding Spot](https://michaelscodingspot.com/wpf-merged-dictionary-problemsandsolutions/) — BasedOn/DynamicResource limitation, duplicate key resolution order
- [WPF: StaticResource vs. DynamicResource — CodeProject](https://www.codeproject.com/Articles/393086/WPF-StaticResource-vs-DynamicResource) — authoritative reference on resolution timing
- [Color Contrast Accessibility WCAG 2025 Guide — AllAccessible](https://www.allaccessible.org/blog/color-contrast-accessibility-wcag-guide-2025) — WCAG 2.1 AA 4.5:1 contrast requirement
- [Offering a Dark Mode Doesn't Satisfy WCAG Color Contrast — BOIA](https://www.boia.org/blog/offering-a-dark-mode-doesnt-satisfy-wcag-color-contrast-requirements) — accessibility testing guidance

### Tertiary (LOW confidence)
- [Mastering Dynamic Resources in WPF — Moldstud](https://moldstud.com/articles/p-mastering-dynamic-resources-in-wpf-a-comprehensive-guide-for-developers) — general guidance, performance benchmarks; corroborated by official docs
- [StaticResource & DynamicResource in WPF — Medium](https://medium.com/@payton9609/staticresource-dynamicresource-in-wpf-c121b1a85574) — describes confirmed WPF behavior; single source

---

*Research completed: 2026-02-20*
*Ready for roadmap: yes*
