# Pitfalls Research

**Domain:** WPF runtime theming — adding a dynamic theme system to an existing C#/.NET 8 WPF application with established XAML
**Researched:** 2026-02-20
**Confidence:** HIGH (WPF StaticResource/DynamicResource behavior, BasedOn limitation, MergedDictionaries order rules verified via official Microsoft docs and community expert sources; code-behind color pitfall based on direct codebase audit of MainViewModel.cs)

---

## Critical Pitfalls

### Pitfall 1: StaticResource References Do Not Update When Theme Changes

**What goes wrong:**
`{StaticResource BgDark}` is resolved once at XAML parse time and permanently frozen. When you swap the `MergedDictionaries` entry at runtime, controls using `StaticResource` show the original color. They do not react to the dictionary swap. The visual result is a partially-themed UI: some elements update (those using `DynamicResource`), others retain the original dark palette, producing a broken mixed-theme state.

The current codebase uses `{StaticResource ...}` throughout all XAML files. Every reference must be audited before theming will work.

**Why it happens:**
`StaticResource` was the right default when there was one theme and it never changed. It is faster and simpler than `DynamicResource`. Migrating to theming requires deliberately converting all color and brush references — the WPF tooling does not flag unconverted `StaticResource` usages as errors, so it is easy to miss individual occurrences.

**How to avoid:**
Convert all brush and color resource references from `{StaticResource X}` to `{DynamicResource X}` in all `.xaml` files, for every resource key defined in the theme dictionaries (BgDark, BgSidebar, BgCard, BgInput, Border, Blue, Green, Orange, Red, Text1, Text2, Text3, ColorGreen, ColorOrange, ColorRed, ColorBlue, ColorText2). Style references (`{StaticResource NavBtn}`) do NOT need conversion — only brush/color values inside styles do.

Confirm completeness by grepping for `StaticResource` after migration:
```bash
grep -rn "StaticResource Bg\|StaticResource Text\|StaticResource Blue\|StaticResource Green\|StaticResource Orange\|StaticResource Red\|StaticResource Border\|StaticResource Color" src/
```
Zero results means the migration is complete.

**Warning signs:**
- After applying a new theme, main window background changes but sidebar stays dark
- Card backgrounds and borders retain previous theme colors
- Log panel TextBox background does not change

**Phase to address:**
Phase 1 (Infrastructure and XAML Migration) — This is the foundational change. All other theming work depends on it.

---

### Pitfall 2: Inline Hardcoded Hex Colors in XAML Cannot Be Themed

**What goes wrong:**
The current codebase contains raw hex colors set directly in XAML attribute values and `DataTrigger.Setter` values, bypassing the resource dictionary entirely:

- `MainWindow.xaml` — Four active nav highlight `DataTrigger` setters use hardcoded `#21262D`, `#58A6FF`, `#E6EDF3`
- `InstallDialog.xaml` line 65 — Validation error TextBlock uses `Foreground="#F85149"` directly
- `ScheduleTaskDialog.xaml` line 124 — Same `#F85149` hardcode
- `TransferDialog.xaml` line 130 — Same `#F85149` hardcode
- `DarkTheme.xaml` ControlTemplate triggers — `Background` value `#21262D` hardcoded in `NavBtn` template
- `DarkTheme.xaml` button styles — `#238636`, `#2EA043`, `#DA3633`, `#F85149` hardcoded in `Btn`, `BtnGreen`, `BtnRed` templates

These values are invisible to the theme swap. They will remain the dark theme's exact hex values regardless of which theme is active, producing colored artifacts in light themes.

**Why it happens:**
When there is one theme, the distinction between a named resource and a hardcoded hex value is invisible — both produce the same result. Developers reach for the inline hex value when it is faster than defining and referencing a named resource.

**How to avoid:**
Move every hardcoded color into a named resource key in the theme dictionaries, then reference it via `{DynamicResource X}`. Required additions per theme file:

```
BtnPrimaryBg         (#238636 green button background)
BtnPrimaryHover      (#2EA043 green button hover)
BtnDangerBg          (#DA3633 red button background)
BtnDangerHover       (#F85149 red button hover)
NavActiveBackground  (#21262D nav active background)
NavActiveAccent      (#58A6FF nav active border — per-theme accent)
NavActiveForeground  (#E6EDF3 nav active text)
TextError            (#F85149 validation error text)
```

**Warning signs:**
- Apply a light theme and nav bar active-page indicator stays dark
- Button hover backgrounds do not change with theme
- Validation error text stays red-on-dark even with a light background

**Phase to address:**
Phase 1 (Infrastructure and XAML Migration) — Must be addressed in the same pass as the `StaticResource` → `DynamicResource` conversion.

---

### Pitfall 3: Hardcoded SolidColorBrush in ViewModel Code-Behind Bypasses Theming

**What goes wrong:**
`MainViewModel.cs` creates `SolidColorBrush` objects directly in C# code using hardcoded `Color.FromRgb()` values. These include:

- Dashboard card bar colors (ServicesBarColor, DatabaseBarColor, DiskBarColor, TaskBarColor) — all initialized to `Color.FromRgb(0x8B, 0x94, 0x9E)` (Text2 gray)
- Status banner colors — Green `0x3F, 0xB9, 0x50`, Red `0xF8, 0x51, 0x49`, Orange `0xD2, 0x99, 0x22`
- Connection dot color — Green or Red depending on `IsOnline`
- Dashboard service/disk/task bar colors set from business logic using those same hex values

These brushes are set as `[ObservableProperty]` values and bound directly in XAML. The theme swap has no effect on them because they are never read from the resource dictionary at all.

**Why it happens:**
ViewModel code does not participate in XAML resource lookup. It creates brushes from constants because it needs to compute them based on state (e.g., "green if all services running, orange if some, red if none"). There is no obvious way to look up a theme resource from a ViewModel.

**How to avoid:**
Use `Application.Current.TryFindResource()` to look up brush resources by key from C# code:

```csharp
private static SolidColorBrush GetBrush(string key)
{
    return Application.Current.TryFindResource(key) as SolidColorBrush
        ?? new SolidColorBrush(Colors.Gray);
}

// Usage:
ServicesBarColor = allRunning
    ? GetBrush("Green")
    : someRunning
        ? GetBrush("Orange")
        : GetBrush("Red");
```

On theme change, the ViewModel must call `OnPropertyChanged` on all brush properties so bindings re-evaluate and call `GetBrush()` with the now-active theme. A `ThemeService.ThemeChanged` event subscription in the ViewModel handles this.

The semantic color names (Green, Orange, Red, Blue) remain constant across themes — only their actual color values change per theme. This means the logic stays correct: "green = healthy" remains true regardless of which green the active theme defines.

**Warning signs:**
- Apply a light theme and dashboard card status bars remain GitHub-dark green/red/orange
- Connection dot stays the dark-theme green even after theme switch
- Status banner after operations shows dark-theme color regardless of active theme

**Phase to address:**
Phase 1 (Infrastructure) — Requires establishing a `ThemeService` with a change event before any ViewModel color properties can be fixed.

---

### Pitfall 4: MergedDictionaries Clear-and-Replace Breaks Style Inheritance Chain

**What goes wrong:**
The recommended approach for runtime theme switching is to clear `Application.Current.Resources.MergedDictionaries` and add a new theme dictionary. If the base styles (NavBtn, Btn, BtnSec, etc.) are part of the cleared dictionary, all controls temporarily lose their entire style definition during the swap — visible as a white-flash or unstyled-controls flicker.

More critically: if the `DarkTheme.xaml` is cleared and only a color-only replacement is added, then styles defined in `DarkTheme.xaml` (like `NavBtn`, `LogTextBox`, the custom `ProgressBar` template) are lost entirely and controls revert to default WPF appearance.

**Why it happens:**
Developers start with a single `DarkTheme.xaml` that mixes both structural styles and color values. When switching themes, they swap the entire file, destroying the structural styles along with the colors.

**How to avoid:**
Split the single `DarkTheme.xaml` into two layers:

1. **`Themes/Base.xaml`** — All structural styles (NavBtn, Btn, BtnSec, BtnGreen, BtnRed, LogTextBox, ProgressBar template, ScrollBar style, etc.) — never swapped
2. **`Themes/Colors/DarkTheme.xaml`** — Only brush/color definitions — swapped on theme change

In `App.xaml`:
```xml
<Application.Resources>
    <ResourceDictionary>
        <ResourceDictionary.MergedDictionaries>
            <ResourceDictionary Source="Themes/Base.xaml"/>
            <ResourceDictionary Source="Themes/Colors/DarkTheme.xaml"/>
        </ResourceDictionary.MergedDictionaries>
    </ResourceDictionary>
</Application.Resources>
```

Only the second entry (the color dictionary) is swapped at runtime. `Base.xaml` is never touched.

**Warning signs:**
- Theme switch causes a visible flash of unstyled white controls
- After switching theme, buttons lose their custom template and revert to default Windows buttons
- Log panel TextBox loses its font/padding/dark styling after theme switch

**Phase to address:**
Phase 1 (Infrastructure) — The Base/Colors split is the foundational architectural decision. Must be done before implementing any themes.

---

### Pitfall 5: BasedOn Cannot Use DynamicResource — Derived Styles Break at Theme Change

**What goes wrong:**
WPF does not allow `BasedOn="{DynamicResource BaseStyleKey}"`. Attempting it throws a parse exception: `"DynamicResourceExtension is not valid for BasedOn."` Styles using `BasedOn="{StaticResource NavBtn}"` resolve the base style once at load time. When the theme dictionary is replaced at runtime, the base style is re-evaluated with new values, but derived styles using `BasedOn` may not fully re-inherit because the static base reference was already resolved.

The codebase has `NavBtnActive` and `QuickActionBtn` using `BasedOn="{StaticResource NavBtn}"` and `BasedOn="{StaticResource BtnSec}"` respectively. Additionally, `MainWindow.xaml` uses inline `<Style BasedOn="{StaticResource NavBtn}">` in four `DataTrigger` button styles.

**Why it happens:**
`BasedOn` is a fundamental WPF style composition mechanism and has no dynamic equivalent. This is a known WPF design limitation. Developers expecting full dynamic style inheritance discover the limitation only after implementing theming.

**How to avoid:**
Two strategies, choose based on style complexity:

Option A (for simple derived styles): Eliminate inheritance — duplicate the full style definition in each theme dictionary rather than using `BasedOn`. This is appropriate for `NavBtnActive` and `QuickActionBtn` which only add 1-2 properties to their base.

Option B (for complex inherited styles): Keep `BasedOn="{StaticResource ...}"` but ensure all brush/color values within the derived style's setters use `{DynamicResource ...}`. The derived style's non-color structural properties are inherited once; the color properties re-evaluate on theme change because they use `DynamicResource`. This works correctly for the existing codebase since only colors change between themes.

Option B is correct for this project. The structural layout (padding, borders, font size, template) does not change between themes — only the color values do. The inline `DataTrigger` styles in `MainWindow.xaml` must have their hardcoded hex values (covered in Pitfall 2) replaced with `DynamicResource` references; `BasedOn="{StaticResource NavBtn}"` itself remains valid and does not need to change.

**Warning signs:**
- XAML parse exception: `"DynamicResourceExtension cannot be set on the 'BasedOn' property"`
- Active nav button ignores the new theme's accent color after switch
- `NavBtnActive` style still shows the previous theme's blue accent

**Phase to address:**
Phase 1 (Infrastructure) — The `BasedOn` limitation must be understood before deciding the style split strategy.

---

### Pitfall 6: Live Preview Applies to Application, Not Just Settings Dialog

**What goes wrong:**
Live preview — showing the new theme while the user is still deciding in the Settings dialog — requires applying the theme to `Application.Current.Resources.MergedDictionaries` immediately. This means the theme change takes effect across the entire running application while the dialog is open, not just in a sandboxed preview area inside the dialog itself.

If the user cancels the dialog, the app is left with the preview theme applied. Without an explicit revert mechanism, the previously-saved theme is lost for the current session (though it will reload on next launch from JSON). If the user cancels repeatedly, this pattern can create orphaned resource dictionaries in the merged collection.

**Why it happens:**
True per-control-tree isolation for preview would require each control to have its own resource scope (ResourceDictionary attached to the element's `Resources`), which is architecturally complex and redundant. The simplest approach — just apply to `Application.Current` — has the cancel-revert problem.

**How to avoid:**
On dialog open, capture the current theme name. On preview, apply the new theme. On Save, persist the new theme name to JSON. On Cancel, re-apply the captured original theme name:

```csharp
// On dialog open:
var originalTheme = _settingsService.CurrentTheme;

// On each preview selection:
_themeService.ApplyTheme(selectedTheme);

// On Cancel:
_themeService.ApplyTheme(originalTheme);
// Do NOT save to JSON

// On Save:
_settingsService.SaveTheme(selectedTheme);
// Already applied; just persist
```

**Warning signs:**
- User clicks Cancel and the app stays on the last-previewed theme
- Application resources contains multiple theme color dictionaries after repeated preview cycles (leaked dictionary entries)
- Theme applied on preview but reverts incorrectly on Cancel (original not captured before first preview)

**Phase to address:**
Phase 2 (Theme Picker in Settings) — applies during the preview feature implementation.

---

## Moderate Pitfalls

### Pitfall 7: Theme Applied After Window Load Causes Initial Flash

**What goes wrong:**
If the theme name is loaded from JSON in `MainViewModel` constructor (or a deferred `InitializeAsync()`) rather than in `App.xaml.cs` before `Application.MainWindow` is shown, the window briefly renders with the default theme's colors before the saved theme is applied — a visible flash of the wrong theme.

**How to avoid:**
Apply the saved theme in `App.xaml.cs` `OnStartup()` before showing `MainWindow`:

```csharp
protected override void OnStartup(StartupEventArgs e)
{
    base.OnStartup(e);
    var settings = _settingsService.Load();
    _themeService.ApplyTheme(settings.Theme); // Before MainWindow creation
    var window = new MainWindow();
    window.Show();
}
```

The `MergedDictionaries` slot for colors must already be present in `App.xaml` (as a default) so the startup call replaces the right entry rather than appending a duplicate.

**Warning signs:**
- On launch, the app briefly shows dark colors before switching to the saved light theme
- Users with a saved non-default theme see the wrong theme for ~100ms on startup

**Phase to address:**
Phase 1 (Infrastructure) — the startup loading order must be locked in before any themes are tested.

---

### Pitfall 8: Duplicate Resource Keys in Merged Dictionary Stack

**What goes wrong:**
WPF's merged dictionary resolution order means the last-defined key wins. If a key appears in both `Base.xaml` and a color theme dictionary, the theme dictionary wins (since it is merged after Base). This is intentional for color overrides. However, if a key appears in `DarkTheme.xaml` that is NOT a color (e.g., a `ControlTemplate`), and the same key is also defined in `Base.xaml`, the `DarkTheme.xaml` version silently wins and may override the structural template with a partial or wrong version.

The current `DarkTheme.xaml` mixes both structural styles and colors. The split to Base/Colors must be done carefully to avoid leaving duplicate key definitions across the two files.

**How to avoid:**
After the Base/Colors split:
1. Each resource key should appear in exactly one file (either Base.xaml or exactly one Colors/*.xaml)
2. Run a quick audit to verify no key appears in both Base.xaml and any Colors file
3. Color-only resources (brushes, colors) belong exclusively in Colors/*.xaml
4. Template-only resources belong exclusively in Base.xaml

**Warning signs:**
- PSScriptAnalyzer equivalent (XAML lint): multiple definitions of the same key across files
- One theme renders a style differently from another despite both defining the same colors

**Phase to address:**
Phase 1 (Infrastructure) — part of the Base/Colors split work.

---

### Pitfall 9: Missing Resource Key in a Non-Default Theme Renders Silently as Default Value

**What goes wrong:**
When a `DynamicResource` reference cannot find its key in the current resource dictionary, WPF does not throw an exception — it silently applies the dependency property's default value. For `Foreground`, the default is `Black`. For `Background`, it is often `null` (transparent). In a dark theme, `Black` foreground on a dark background is invisible text. In a light theme, `null` (transparent) background shows the window background color unintentionally.

Each of the 6 themes must define every key used anywhere in the application. A theme that is missing even one key produces invisible or garbled UI in exactly that element.

**Why it happens:**
The non-default theme dictionaries are created by copying the default dark theme and modifying colors. If a new resource key is later added to `DarkTheme.xaml` for a new feature, it is easy to forget to add it to all 5 other themes.

**How to avoid:**
Establish a canonical list of all resource keys in a comment block at the top of each theme file — all 6 files must have the same list. Add a startup assertion in debug builds:

```csharp
#if DEBUG
private void ValidateThemeKeys()
{
    var requiredKeys = new[] {
        "BgDark", "BgSidebar", "BgCard", "BgInput", "Border",
        "Blue", "Green", "Orange", "Red",
        "Text1", "Text2", "Text3",
        "ColorGreen", "ColorOrange", "ColorRed", "ColorBlue", "ColorText2",
        "BtnPrimaryBg", "BtnPrimaryHover", "BtnDangerBg", "BtnDangerHover",
        "NavActiveBackground", "NavActiveAccent", "NavActiveForeground",
        "TextError"
    };
    foreach (var key in requiredKeys)
    {
        if (Application.Current.TryFindResource(key) == null)
            throw new InvalidOperationException($"Theme is missing required resource key: {key}");
    }
}
#endif
```

**Warning signs:**
- After applying a theme, a control's text becomes invisible (black on dark background)
- A panel's background disappears and shows the window chrome color instead
- Debug-build assertion fires immediately on launch with the non-default theme

**Phase to address:**
Phase 1 (Infrastructure) — define the canonical key list before creating the first non-default theme.

---

### Pitfall 10: ComboBox and TextBox Native Controls Use System Colors

**What goes wrong:**
WPF's built-in `ComboBox` and `TextBox` controls render parts of themselves using system colors, not application resources. Specifically:
- `ComboBox` dropdown popup background uses `SystemColors.Window` (white on Windows with light system theme)
- `TextBox` selection highlight uses `SystemColors.Highlight`
- `ComboBox` item hover background uses `SystemColors.HighlightBrush`
- Scrollbar inside `ComboBox` dropdown uses system scrollbar colors

The current `SettingsDialog.xaml` and `MainWindow.xaml` have `ComboBox` and `TextBox` controls with background/foreground manually set to the dark theme resources. These may partially work for the custom background, but the popup and selection rendering will diverge from the custom theme.

**How to avoid:**
Override the default `ComboBox` and `TextBox` `ControlTemplate` in `Base.xaml` with custom templates that use `{DynamicResource ...}` for all visual elements, including popup background, item hover, and selection highlight. This is more work than setting a few properties but is the only reliable way to achieve full theme coverage on these controls.

For the 6-theme scope of this milestone, a simpler acceptable mitigation is to add implicit styles for ComboBox and TextBox in `Base.xaml` that set the most common divergent properties:
```xml
<Style TargetType="ComboBox">
    <Setter Property="Background" Value="{DynamicResource BgInput}"/>
    <Setter Property="Foreground" Value="{DynamicResource Text1}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
</Style>
```
This will not fully theme the popup but prevents the most jarring color conflicts.

**Warning signs:**
- With a light theme active, ComboBox dropdown popup is light (matching system) but ComboBox header is themed dark
- ComboBox selected item text color does not match the theme's Text1
- TextBox selection color is Windows blue on a custom dark theme

**Phase to address:**
Phase 2 (Theme Implementation) — full ComboBox/TextBox template override may be deferred to a later milestone if the simplified implicit style approach is acceptable.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Leave some `StaticResource` brush references unconverted | Fewer changes, faster first theme | Those elements permanently locked to initial theme color; subtle bugs accumulate | Never — always convert all brush/color references |
| Skip the Base.xaml / Colors split; put everything in one file per theme | Simpler file structure | Every theme file must duplicate all structural styles; maintenance burden multiplies by 6 | Never — structural duplication is technical debt from day one |
| Keep hardcoded hex values in ControlTemplate triggers "for now" | Avoid refactoring template internals | Active nav state uses wrong color in non-default themes | Never — these are the most visible UI elements |
| Apply theme via `foreach` resource update instead of dictionary swap | Avoids clear-and-replace complexity | Leaks stale entries; resource lookup gets slower over time | Never |
| Validate theme key completeness only manually | Faster development | Missing keys produce invisible text silently in production | Never — add debug-build assertion |
| Compute ViewModel brush colors from hardcoded constants | No ThemeService dependency | Dashboard status indicators are permanently dark-theme colors | Never — ViewModel brushes must use `TryFindResource` |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `Application.Current.Resources.MergedDictionaries` | Appending a new dictionary instead of replacing index 1 | Always swap by index: `MergedDictionaries[1] = newDict` where index 0 is Base.xaml and index 1 is the current color theme |
| `ThemeService` + `ISettingsService` | Saving theme name before validating the theme dictionary loads without errors | Load and validate the dictionary before persisting; on failure, keep existing theme and show error |
| Settings JSON + Theme | Reading theme name in ViewModel init rather than App.xaml.cs `OnStartup` | Load and apply theme in `OnStartup` before first window creation to prevent launch flash |
| `TryFindResource` in ViewModel | Calling `TryFindResource` during ViewModel initialization before `App.xaml.cs` finishes loading resources | Call `TryFindResource` only after startup, or subscribe to `ThemeChanged` event and refresh on each change |
| Live preview + Cancel | Not capturing `originalTheme` before opening Settings dialog | Always snapshot current theme on dialog open; revert on Cancel without saving to JSON |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Too many `DynamicResource` references causing UI thread overhead | Slight lag on window resize, animation stutter | `DynamicResource` overhead is per-element, not per-reference; 200+ controls with `DynamicResource` on 4-5 properties is still negligible for a single-window admin tool | Not a real risk at this app's scale — ignore |
| Creating new `ResourceDictionary` on every theme switch instead of caching | Memory pressure if user switches themes repeatedly | Pre-instantiate one `ResourceDictionary` per theme on startup and cache them; swap by reference not by `Source` URI | Only visible if user switches themes 100+ times in a session |
| Calling `OnPropertyChanged` on every ViewModel property on theme change | Extra re-render cycle | Only call `OnPropertyChanged` for brush properties computed via `TryFindResource`; the rest update automatically via `DynamicResource` bindings | Minimal impact, but cleaner to be precise |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Theme preview changes entire UI immediately | Disorienting if user is mid-operation (log panel scrolling, progress visible) | Disable preview during active operations; show a tooltip "Changes preview when no operation is running" or use a static swatch preview inside the dialog instead |
| Theme names like "Serenity" mean nothing until seen | User must click each theme to understand it | Show a small color-swatch palette next to each theme name in the picker; 3-5 color dots representative of bg/accent/text |
| Light theme with dark-only icon assets | Icons designed for dark backgrounds look wrong on light themes | All 6 icons in DarkTheme.xaml are vector-based `SolidColorBrush` fills, not bitmaps, so they automatically inherit the theme's colors — verify this works; if any icon uses a hardcoded dark fill color, add it to the resource key list |
| Insufficient contrast ratio in "lighter" themes | Text unreadable for users with vision impairments | Target minimum 4.5:1 contrast ratio (WCAG 2.1 AA) for all text/background pairs; tool: https://webaim.org/resources/contrastchecker/ |
| Settings dialog changes theme but user does not notice app-wide change | Disorientation — user expects preview only inside dialog | Add a brief note in the Settings dialog: "Theme applies to the entire application immediately." |

---

## "Looks Done But Isn't" Checklist

- [ ] **StaticResource migration:** All brush/color resources use `{DynamicResource ...}` — verify with grep for `StaticResource Bg`, `StaticResource Text`, `StaticResource Blue`, `StaticResource Green`, `StaticResource Red`, `StaticResource Border`, `StaticResource Orange`, `StaticResource Color` in all `.xaml` files
- [ ] **Inline hex cleanup:** No raw `#RRGGBB` hex values in XAML `Setter.Value`, `Foreground=`, or `Background=` attributes — verify with grep for `#[0-9A-Fa-f]{6}` in `.xaml` files
- [ ] **ViewModel brushes:** All `SolidColorBrush` properties in `MainViewModel.cs` call `GetBrush(key)` using `TryFindResource`, not `Color.FromRgb()` literals — verify all 15 occurrences in `MainViewModel.cs` are converted
- [ ] **Cancel reverts:** Open Settings, select a different theme, click Cancel — app returns to previously saved theme immediately
- [ ] **Persistence survives restart:** Select a non-default theme, save, close and relaunch the EXE — the non-default theme is active from the first frame (no flash)
- [ ] **All 6 themes pass key validation:** Debug-build assertion fires zero times for all 6 theme dictionaries
- [ ] **NavBtn active state themes:** Navigate to each panel while each theme is active — the left-border accent matches the theme's accent color, not the hardcoded `#58A6FF`
- [ ] **Validation error text:** Trigger a validation error in InstallDialog while using a light theme — error text is readable (not red-on-light-red or invisible)
- [ ] **Dashboard status bars:** Switch to a non-dark theme, force a dashboard refresh — ServicesBarColor and other bar colors update to the theme's color values, not the dark-theme hex constants

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Realized mid-milestone that Base.xaml/Colors split was skipped | HIGH | All theme files must be restructured; all XAML referencing styles needs retesting; roughly 1-2 days of rework |
| ViewModel brush hardcodes missed — dashboard bars wrong after shipping | LOW | Add `TryFindResource` helper to ViewModel, convert affected properties, issue patch release |
| Missing resource key shipped in one theme (invisible text) | LOW | Add key to the missing theme dictionary; test all 6 themes in CI; patch release |
| Cancel-reverts not working — users stuck with preview theme | MEDIUM | Add `originalTheme` capture to Settings dialog open; requires theme service wiring; no data loss |
| StaticResource references missed in one dialog | LOW | Convert the missed references in that dialog; localized change; easily verifiable by grep |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| StaticResource not updating on theme change | Phase 1 (Infrastructure and XAML Migration) | Grep for `StaticResource Bg/Text/Blue/etc` returns zero results |
| Inline hardcoded hex in XAML | Phase 1 (Infrastructure and XAML Migration) | Grep for `#[0-9A-Fa-f]{6}` in `.xaml` returns zero results |
| Hardcoded SolidColorBrush in ViewModel | Phase 1 (Infrastructure) | `MainViewModel.cs` contains no `Color.FromRgb` literals; all brushes use `TryFindResource` |
| MergedDictionaries clear breaks styles | Phase 1 (Infrastructure) | Base.xaml and Colors split in place before first non-default theme is written |
| BasedOn + DynamicResource limitation | Phase 1 (Infrastructure) | Color values in derived styles use `DynamicResource`; `BasedOn` attribute left as `StaticResource` |
| Live preview cancel does not revert | Phase 2 (Theme Picker) | Manual test: open Settings, preview 3 themes, click Cancel — original theme restored |
| Theme flash on launch | Phase 1 (Infrastructure) | Launch with each of 6 themes saved; no flash visible on startup |
| Duplicate resource keys after split | Phase 1 (Infrastructure) | Build-time: no duplicate keys across Base.xaml and any Colors file |
| Missing key in non-default theme | Phase 2 (Theme Implementation) | Debug-build assertion runs on CI for all 6 themes; zero assertion failures |
| ComboBox/TextBox system color bleed | Phase 2 (Theme Implementation) | Visual review of Settings dialog with all 6 themes; no white-popup-on-dark mismatch |

---

## Sources

- [Merged resource dictionaries — WPF | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/systems/xaml-resources-merged-dictionaries) — HIGH confidence (Microsoft official)
- [XAML resources overview — WPF | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/systems/xaml-resources-overview) — HIGH confidence (Microsoft official)
- [Styles and templates — WPF | Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/styles-templates-overview?view=netdesktop-9.0) — HIGH confidence (Microsoft official)
- [Changing WPF themes dynamically — Marko Devcic](https://www.markodevcic.com/post/Changing_WPF_themes_dynamically/) — MEDIUM confidence (verified against official docs; StaticResource/DynamicResource behavior matches Microsoft docs exactly)
- [WPF Merged Dictionary problems and solutions — Michael's Coding Spot](https://michaelscodingspot.com/wpf-merged-dictionary-problemsandsolutions/) — MEDIUM confidence (well-researched community article; BasedOn/DynamicResource limitation confirmed by multiple sources)
- [WPF complete guide to Themes and Skins — Michael's Coding Spot](https://michaelscodingspot.com/wpf-complete-guide-themes-skins/) — MEDIUM confidence (runtime switching pattern is consistent with official docs)
- [WPF How To Switching Themes at Runtime — Telerik UI for WPF](https://docs.telerik.com/devtools/wpf/styling-and-appearance/how-to/styling-apperance-themes-runtime) — MEDIUM confidence (commercial component vendor; pattern is standard WPF)
- [StaticResource & DynamicResource in WPF — Medium](https://medium.com/@payton9609/staticresource-dynamicresource-in-wpf-c121b1a85574) — LOW confidence (WebSearch only; but describes confirmed WPF behavior)
- [Color Contrast Accessibility WCAG 2025 Guide — AllAccessible](https://www.allaccessible.org/blog/color-contrast-accessibility-wcag-guide-2025) — MEDIUM confidence (WCAG 2.1 AA 4.5:1 ratio requirement is a W3C standard)
- [Offering a Dark Mode Doesn't Satisfy WCAG Color Contrast — BOIA](https://www.boia.org/blog/offering-a-dark-mode-doesnt-satisfy-wcag-color-contrast-requirements) — MEDIUM confidence (accessibility testing organization)
- GA-WsusManager codebase direct audit (`MainViewModel.cs`, `MainWindow.xaml`, `DarkTheme.xaml`, all dialog `.xaml` files) — HIGH confidence (first-party source)

---

*Pitfalls research for: WPF runtime theming — adding 6-theme system to existing C#/.NET 8 WPF admin app*
*Researched: 2026-02-20*
