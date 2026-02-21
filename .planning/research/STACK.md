# Stack Research

**Domain:** WPF Runtime Theme Switching — v4.3 Theming Milestone
**Researched:** 2026-02-20
**Confidence:** HIGH (WPF theming patterns are stable, well-documented, and verified against official Microsoft docs)

---

## Milestone Scope

This research covers ONLY what is new or changed for v4.3. The base stack (C#/.NET 8, WPF, CommunityToolkit.Mvvm, Serilog, xUnit + Moq) is validated and unchanged.

**The single question this answers:** How do we add runtime color scheme switching to an existing WPF app where all XAML currently uses `StaticResource`?

---

## Decision Summary

**Use native WPF ResourceDictionary merging with DynamicResource bindings.**

No external theming library is needed. The existing `Themes/DarkTheme.xaml` file already establishes the correct architectural pattern — separate color brushes in a dedicated dictionary, referenced from all XAML. The v4.3 work is: (1) convert `StaticResource` to `DynamicResource` throughout, (2) create 5 additional theme XAML files using the same key names, (3) write a `ThemeService` that swaps the merged dictionary at runtime. That is the entire stack addition.

---

## Recommended Stack

### Core Technologies (unchanged)

No new core technologies. Runtime theme switching is a native WPF capability.

### New: Theme Infrastructure (zero new NuGet packages)

| Component | Type | Purpose | Why This Way |
|-----------|------|---------|--------------|
| `DynamicResource` bindings | WPF built-in | Allow resource values to update at runtime without re-rendering the visual tree | `StaticResource` is resolved once at XAML load time and never updates. `DynamicResource` observes resource changes and re-applies. Required for live theme switching. |
| Additional `*Theme.xaml` files | XAML files (Resource build action) | One file per color scheme (6 total including existing DarkTheme.xaml) | Each file defines the same set of brush/color keys with different values. Swapping which dictionary is merged changes all colors simultaneously. |
| `IThemeService` + `ThemeService` | C# class in WsusManager.Core or WsusManager.App | Encapsulates the dictionary swap logic, maps theme name to XAML URI | Keeps theme switching testable and callable from SettingsDialog ViewModel. |
| `ThemeName` property in `AppSettings` | String field in existing model | Persists selected theme across sessions | Slot into existing JSON persistence — no new infrastructure needed. |

### Supporting Libraries (unchanged)

No new NuGet packages required. WPF's `ResourceDictionary.MergedDictionaries` API handles everything natively.

---

## The Exact Implementation Pattern

### Pattern: Dictionary Swap at Runtime

This is the authoritative pattern for WPF runtime theme switching. It is documented in Microsoft's official WPF merged dictionaries docs (updated 2024-10-24) and corroborated by multiple community references.

**Step 1 — Theme XAML files all use identical resource keys.**

`Themes/DarkTheme.xaml` (existing — already correct structure):
```xml
<SolidColorBrush x:Key="BgDark"    Color="#0D1117"/>
<SolidColorBrush x:Key="BgSidebar" Color="#161B22"/>
<SolidColorBrush x:Key="BgCard"    Color="#21262D"/>
<!-- ... same keys in every theme file, different color values -->
```

`Themes/JustBlackTheme.xaml` (new — same keys, different values):
```xml
<SolidColorBrush x:Key="BgDark"    Color="#000000"/>
<SolidColorBrush x:Key="BgSidebar" Color="#0A0A0A"/>
<SolidColorBrush x:Key="BgCard"    Color="#141414"/>
<!-- ... -->
```

**Step 2 — All XAML uses `DynamicResource` (not `StaticResource`).**

```xml
<!-- Before (current state — does NOT update at runtime) -->
<Window Background="{StaticResource BgDark}">

<!-- After (required for live switching) -->
<Window Background="{DynamicResource BgDark}">
```

This change must be applied to all 283 `StaticResource` references across 8 XAML files.

**Step 3 — `ThemeService` swaps the merged dictionary.**

```csharp
public class ThemeService : IThemeService
{
    private static readonly Dictionary<string, Uri> ThemeUris = new()
    {
        ["DefaultDark"]  = new Uri("pack://application:,,,/WsusManager.App;component/Themes/DarkTheme.xaml"),
        ["JustBlack"]    = new Uri("pack://application:,,,/WsusManager.App;component/Themes/JustBlackTheme.xaml"),
        ["Slate"]        = new Uri("pack://application:,,,/WsusManager.App;component/Themes/SlateTheme.xaml"),
        ["Serenity"]     = new Uri("pack://application:,,,/WsusManager.App;component/Themes/SerenityTheme.xaml"),
        ["Rose"]         = new Uri("pack://application:,,,/WsusManager.App;component/Themes/RoseTheme.xaml"),
        ["ClassicBlue"]  = new Uri("pack://application:,,,/WsusManager.App;component/Themes/ClassicBlueTheme.xaml"),
    };

    public void ApplyTheme(string themeName)
    {
        if (!ThemeUris.TryGetValue(themeName, out var uri)) return;

        var mergedDicts = Application.Current.Resources.MergedDictionaries;

        // Remove existing theme dictionary (leave other merged dicts untouched)
        var existing = mergedDicts.FirstOrDefault(d =>
            d.Source != null && d.Source.ToString().Contains("/Themes/"));
        if (existing != null)
            mergedDicts.Remove(existing);

        // Add new theme dictionary — DynamicResource bindings update automatically
        mergedDicts.Add(new ResourceDictionary { Source = uri });
    }
}
```

**Step 4 — XAML files are embedded as `Resource` build action** (already the case for all XAML in the project — WPF default). Pack URI format: `pack://application:,,,/AssemblyName;component/Path/File.xaml`.

**Step 5 — `AppSettings` gains a `ThemeName` property** (string, default `"DefaultDark"`). Saved/loaded via existing JSON persistence in `ISettingsService`. No schema migration needed — JSON deserialization uses the default value when the key is absent.

---

## Critical Integration Constraint: StaticResource Migration

**All 283 `StaticResource` references in 8 XAML files must become `DynamicResource`.**

This is not optional. `StaticResource` is resolved once at XAML parse time and is permanently fixed. Only `DynamicResource` subscribes to the WPF resource system for updates.

**Current breakdown (verified by code analysis):**

| File | StaticResource count |
|------|---------------------|
| `MainWindow.xaml` | 157 |
| `SettingsDialog.xaml` | 18 |
| `ScheduleTaskDialog.xaml` | 26 |
| `TransferDialog.xaml` | 28 |
| `SyncProfileDialog.xaml` | 14 |
| `InstallDialog.xaml` | 15 |
| `GpoInstructionsDialog.xaml` | 7 |
| `DarkTheme.xaml` | 18 (internal — `BasedOn` refs, not color refs) |

**XAML styles in DarkTheme.xaml that use `StaticResource` internally** (e.g., `{StaticResource Text2}` inside a `Style`) also need to become `DynamicResource` for proper propagation. The `BasedOn="{StaticResource NavBtn}"` style inheritance references are fine as `StaticResource` — those reference style objects, not color resources, and don't change when the theme swaps.

**Performance note:** `DynamicResource` has a small overhead vs `StaticResource` — WPF maintains a lookup table and notifies dependents on change. For ~283 bindings on a single-screen admin tool, this is completely imperceptible. Microsoft's own guidance confirms the performance difference is negligible for typical UI sizes.

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| MaterialDesignInXamlToolkit | Imposes Material Design visual language on top of the existing custom dark theme. Would require rewriting all styles and controls to match MDIX conventions. Massive scope expansion. | Native ResourceDictionary swap — already exactly what's needed |
| MahApps.Metro | Same problem as MDIX — opinionated control library that would conflict with existing custom styles | Native ResourceDictionary swap |
| HandyControl | Different control library ecosystem; integration requires adapting all existing controls | Native ResourceDictionary swap |
| FluentWPF / Wpf.Ui | Fluent design library — conflicts with the existing custom GA-AppLocker-style dark theme | Native ResourceDictionary swap |
| `StaticResource` for color bindings | Cannot update at runtime — theme switch has no visible effect | `DynamicResource` for all color/brush references |
| External JSON theme files (loose files) | Requires deployment of additional files alongside EXE, breaking the single-EXE constraint. Also slower to load, no design-time support. | Embedded XAML `Resource` files (compiled into EXE assembly) |
| `Application.Current.Resources.MergedDictionaries.Clear()` | Clears ALL merged dictionaries, including any non-theme dictionaries added in future. | Remove only the theme dictionary by matching source URI pattern |

---

## Installation / Changes Required

### No new NuGet packages.

### New files to create:

```
src/WsusManager.App/Themes/
├── DarkTheme.xaml          (existing — unchanged)
├── JustBlackTheme.xaml     (new)
├── SlateTheme.xaml         (new)
├── SerenityTheme.xaml      (new)
├── RoseTheme.xaml          (new)
└── ClassicBlueTheme.xaml   (new)

src/WsusManager.Core/Services/
├── Interfaces/IThemeService.cs   (new)
└── ThemeService.cs               (new)
```

### Existing files to modify:

```
src/WsusManager.Core/Models/AppSettings.cs
  — Add: public string ThemeName { get; set; } = "DefaultDark";

src/WsusManager.App/App.xaml.cs  (or Program.cs)
  — Apply saved theme on startup before window shows

src/WsusManager.App/Views/SettingsDialog.xaml + .xaml.cs
  — Add theme picker UI section

src/WsusManager.App/ViewModels/MainViewModel.cs (or SettingsViewModel)
  — Wire ThemeService.ApplyTheme() to theme selection

All 8 XAML files:
  — Replace StaticResource → DynamicResource for color/brush keys
  — Keep StaticResource for Style references (BasedOn, TargetType)
```

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Native ResourceDictionary swap | MaterialDesignInXamlToolkit theming | MDIX theming controls the entire visual language. Our existing custom styles (NavBtn, BtnGreen, BtnRed, LogTextBox, etc.) would need full rewrites. Out-of-scope, high risk. |
| Native ResourceDictionary swap | Code-only theme (set brush colors in C#) | No XAML designer support. More complex code. No benefit over ResourceDictionary approach. |
| Embedded XAML theme files | Loose file themes (file:// URIs) | Breaks single-EXE distribution constraint. External files can be deleted/corrupted. |
| Single merged dict swap | Per-control style injection | Requires touching every control individually. Does not scale to 6 themes and 8 XAML files. |

---

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| `DynamicResource` bindings | All WPF versions including .NET 8 WPF | Fundamental WPF feature, no version concerns |
| Pack URI `pack://application:,,,/AssemblyName;component/...` | .NET 8 WPF | Standard format for embedded resources in single-file apps; verified to work with `PublishSingleFile=true` since WPF resources are compiled into the assembly before single-file bundling |
| `ResourceDictionary.MergedDictionaries` manipulation | .NET 8 WPF | Thread-safety: must be called on UI thread (use `Application.Current.Dispatcher.Invoke` if calling from a background thread) |

---

## Sources

- [Merged resource dictionaries — WPF .NET (Microsoft Learn, updated 2024-10-24)](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/systems/xaml-resources-merged-dictionaries?view=netdesktop-8.0) — Dictionary swap pattern, pack URI formats, Resource build action requirement (HIGH confidence)
- [Pack URIs in WPF — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/app-development/pack-uris-in-wpf) — Embedded resource URI format for single-file apps (HIGH confidence)
- [Changing WPF themes dynamically — Marko Devcic](https://www.markodevcic.com/post/Changing_WPF_themes_dynamically/) — DynamicResource requirement, dictionary clear-and-add runtime pattern (MEDIUM confidence — corroborates official docs)
- [WPF Complete Guide to Themes and Skins — Michael's Coding Spot](https://michaelscodingspot.com/wpf-complete-guide-themes-skins/) — StaticResource vs DynamicResource runtime behavior, SkinResourceDictionary pattern tradeoffs (MEDIUM confidence)
- Code analysis of existing codebase: 283 `StaticResource` refs, 0 `DynamicResource` refs across 8 XAML files (HIGH confidence — direct verification)

---

*Stack research for: v4.3 WPF theming system — runtime color scheme switching*
*Researched: 2026-02-20*
