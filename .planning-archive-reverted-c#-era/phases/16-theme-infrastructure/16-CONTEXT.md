# Phase 16: Theme Infrastructure - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate the app's styling system to support runtime color-scheme swapping. Structural styles (ControlTemplates, layout definitions) are permanently loaded in SharedStyles.xaml. Color tokens (SolidColorBrush/Color resources) are placed in swappable theme dictionaries. All color references across 8 XAML files respond to a theme change without restart. The app must render identically to v4.2 on the default dark theme after migration — zero visual regressions.

Theme files themselves (beyond the default dark) and the Settings UI picker belong in Phase 17.

</domain>

<decisions>
## Implementation Decisions

### Color token naming
- Use semantic names that describe purpose, not appearance: `PrimaryBackground`, `SecondaryBackground`, `CardBackground`, `NavBackground`, `AccentBrush`, `AccentHover`, `TextPrimary`, `TextSecondary`, `TextMuted`, `BorderPrimary`, `BorderSubtle`, `StatusSuccess`, `StatusWarning`, `StatusError`
- Each key has both a `SolidColorBrush` resource (for XAML bindings) and a matching `Color` resource (for ViewModel lookups)
- 14 color keys identified from existing codebase analysis

### Dictionary split strategy
- `SharedStyles.xaml` retains all ControlTemplates, Styles, and layout definitions — references colors via `DynamicResource` only
- Each theme file (e.g., `DefaultDark.xaml`) contains only the 14 color key definitions as `SolidColorBrush` and `Color` resources
- Theme files are loaded into `Application.Current.Resources.MergedDictionaries` — clearing and re-adding swaps the entire color scheme at runtime
- The existing `DarkTheme.xaml` is refactored into `SharedStyles.xaml` (permanent) + `DefaultDark.xaml` (swappable color tokens)

### StaticResource to DynamicResource migration
- Every `StaticResource` reference to a color/brush key across all 8 XAML files must be converted to `DynamicResource`
- 15 hardcoded hex color values in MainWindow.xaml (nav button triggers, inline styles) must be extracted to named resource keys
- Target: `grep StaticResource` on any color/brush key returns zero results post-migration
- Estimated scope: ~265 color references across MainWindow.xaml (157), SettingsDialog.xaml (18), and 5 other dialog files

### ViewModel brush migration
- Replace all `Color.FromRgb()` / `new SolidColorBrush()` calls in ViewModels with `Application.Current.TryFindResource("KeyName")` lookups
- This ensures dashboard card status bars, connection dots, and any ViewModel-driven colors respond to theme changes
- Fallback: if resource lookup returns null, use a sensible default (avoids crash on missing key)

### ThemeService implementation
- Singleton service registered in DI container
- `ApplyTheme(string themeName)` method: clears color dictionary from MergedDictionaries, loads new theme dictionary, adds to MergedDictionaries
- `CurrentTheme` property for querying active theme
- Must execute on UI thread (Dispatcher)
- Reads `SelectedTheme` from AppSettings on construction

### Theme flash prevention
- ThemeService applies the persisted theme during `App.OnStartup()` BEFORE MainWindow is constructed
- This ensures the correct theme dictionary is in MergedDictionaries before any XAML binding resolves
- No visible flash of wrong theme on startup

### Claude's Discretion
- Exact ordering of migration steps (which XAML files first)
- Whether to batch the StaticResource migration or do it file-by-file
- Internal structure of ThemeService (method signatures, error handling)
- Test strategy for verifying DynamicResource migration completeness

</decisions>

<specifics>
## Specific Ideas

- Research observation #6591 identified 15 hardcoded hex values across 4 view files (MainWindow.xaml nav button triggers) that must be extracted
- Research observation #6592 defined the split dictionary pattern and confirmed DynamicResource is required inside ControlTemplate triggers
- The proven runtime swap pattern: clear `Application.Current.Resources.MergedDictionaries` color entry, add new theme ResourceDictionary
- Chrome's live-preview model (instant swap on click) is the target UX for Phase 17 — infrastructure must support this
- .NET 8 target framework (not .NET 9) due to confirmed WPF self-contained publish regression

</specifics>

<deferred>
## Deferred Ideas

- Theme picker UI in Settings dialog — Phase 17
- Additional theme files (Just Black, Slate, Serenity, Rose, Classic Blue) — Phase 17
- WCAG 2.1 AA contrast compliance validation — Phase 17
- Cancel/revert behavior in Settings — Phase 17

</deferred>

---

*Phase: 16-theme-infrastructure*
*Context gathered: 2026-02-20*
