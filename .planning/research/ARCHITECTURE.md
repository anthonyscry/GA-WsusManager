# Architecture Research

**Domain:** Windows Server administration GUI tool (WPF/.NET 8, WSUS + SQL Server Express)
**Researched:** 2026-02-19 (initial), 2026-02-20 (v4.3 theming addendum)
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                        Presentation Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │  MainWindow  │  │   Dialogs    │  │   XAML / Data Binding  │   │
│  │  (View-only) │  │  (View-only) │  │   (no code-behind)     │   │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬────────────┘   │
│         │                 │                       │                │
│  ┌──────▼─────────────────▼───────────────────────▼────────────┐  │
│  │                     MainViewModel                            │  │
│  │  [ObservableProperty] [RelayCommand] [NotifyCanExecuteChanged]│  │
│  └─────────────────────────────┬────────────────────────────────┘  │
└─────────────────────────────────┼──────────────────────────────────┘
                                  │ constructor injection
┌─────────────────────────────────┼──────────────────────────────────┐
│                        Service Layer                               │
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │  IWsusService  │  │ IDatabaseService │  │ IHealthService   │    │
│  │ (operations,   │  │ (SQL queries,    │  │ (diagnostics,    │    │
│  │  sync, cleanup)│  │  maintenance)    │  │  auto-repair)    │    │
│  └────────┬───────┘  └────────┬────────┘  └────────┬─────────┘    │
│  ┌────────┴───────┐  ┌────────┴────────┐  ┌────────┴─────────┐    │
│  │ IServiceMgr    │  │ IFirewallService │  │ ISettingsService │    │
│  │ (Win services: │  │ (netsh / rules   │  │ (JSON persist    │    │
│  │  SQL/WSUS/IIS) │  │  8530, 8531)     │  │  APPDATA)        │    │
│  └────────┬───────┘  └────────┬────────┘  └────────┬─────────┘    │
└───────────┼───────────────────┼───────────────────┼───────────────┘
            │                   │                   │
┌───────────┼───────────────────┼───────────────────┼───────────────┐
│                     Infrastructure Layer                           │
│  ┌────────▼───────┐  ┌────────▼────────┐  ┌───────▼──────────┐   │
│  │  ProcessRunner │  │  SqlHelper       │  │  FileSystem      │   │
│  │  (wsusutil,    │  │  (Microsoft.Data │  │  (C:\WSUS\,      │   │
│  │   netsh, sc)   │  │   .SqlClient)    │  │  content, logs)  │   │
│  └────────────────┘  └─────────────────┘  └──────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
            │
┌───────────▼────────────────────────────────────────────────────────┐
│                     External Systems                               │
│   SQL Server Express (SUSDB)   WSUS Windows Service (WsusService) │
│   IIS (port 8530/8531)         Windows Firewall  Windows SCM      │
└────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `MainWindow` (View) | XAML layout only, no logic | WPF Window with zero code-behind logic |
| `MainViewModel` | All UI state, commands, operation orchestration | CommunityToolkit.Mvvm 8.4, `[ObservableProperty]`, `[RelayCommand]` |
| `IWsusService` | WSUS-level operations: sync, cleanup, approve, export/import | C# class using `ProcessRunner` for wsusutil, direct SQL for DB ops |
| `IDatabaseService` | SQL operations against SUSDB: size check, index rebuild, shrink, cleanup queries | `Microsoft.Data.SqlClient` with async methods |
| `IHealthService` | Run diagnostics, detect problems, auto-repair | Orchestrates service/firewall/permissions checks |
| `IWindowsServiceManager` | Start/stop/status for SQL Server, WSUS, IIS services | `System.ServiceProcess.ServiceController` |
| `IFirewallService` | Check and configure firewall rules for 8530/8531 | `ProcessRunner` wrapping `netsh advfirewall` |
| `ISettingsService` | Persist/load settings JSON to `%APPDATA%\WsusManager\settings.json` | `System.Text.Json` |
| `ILogService` | Structured file logging to `C:\WSUS\Logs\` | Serilog with file sink |
| `ProcessRunner` | Launch external processes with captured stdout/stderr | `System.Diagnostics.Process` with `async` stream reading |
| `SqlHelper` | SQL connection factory, query execution, sysadmin checks | `Microsoft.Data.SqlClient` connection pooling |

---

## The WSUS COM API Problem

**Confidence: HIGH** — confirmed via community forum at social.technet.microsoft.com.

`Microsoft.UpdateServices.Administration` is a .NET Framework 4.x COM-interop assembly. It **does not load in .NET 8** (modern .NET). There are no plans from Microsoft to update it.

**Recommended strategy: Bypass the WSUS COM API entirely.**

The existing PowerShell v3 codebase already demonstrates this is viable. Nearly all operations use:
1. Direct SUSDB SQL queries (most maintenance, cleanup, index operations)
2. `wsusutil.exe` via shell (export, import, reset, checkhealth)
3. `WsusServerCleanup` via the built-in WSUS API through PowerShell (which runs in .NET Framework)

For v4.x in .NET 8, use the same two approaches natively — SQL queries via `Microsoft.Data.SqlClient` and `ProcessRunner` wrapping `wsusutil.exe`.

---

## Recommended Project Structure

```
WsusManager/
├── src/
│   ├── WsusManager.App/              # WPF application entry point
│   │   ├── App.xaml                  # Application definition (no StartupUri)
│   │   ├── App.xaml.cs               # DI host setup, startup
│   │   ├── Program.cs                # [STAThread] Main() bootstrapper
│   │   ├── Themes/
│   │   │   ├── DarkTheme.xaml        # Color tokens only (default theme)
│   │   │   ├── SharedStyles.xaml     # All styles/templates (permanent)
│   │   │   ├── JustBlackTheme.xaml   # Alternative themes
│   │   │   ├── SlateTheme.xaml
│   │   │   ├── SerenityTheme.xaml
│   │   │   ├── RoseTheme.xaml
│   │   │   └── ClassicBlueTheme.xaml
│   │   ├── Services/
│   │   │   ├── IThemeService.cs      # Theme switching interface (UI-layer only)
│   │   │   └── ThemeService.cs       # Swaps MergedDictionaries at runtime
│   │   ├── Views/
│   │   │   ├── MainWindow.xaml       # Main window (DynamicResource for colors)
│   │   │   ├── MainWindow.xaml.cs    # Constructor only
│   │   │   └── ...dialogs
│   │   ├── ViewModels/
│   │   │   └── MainViewModel.cs      # Primary ViewModel
│   │   └── Converters/               # IValueConverter implementations
│   │
│   └── WsusManager.Core/             # Business logic library (no WPF dependency)
│       ├── Services/
│       ├── Infrastructure/
│       ├── Models/
│       │   └── AppSettings.cs        # Includes SelectedTheme property
│       └── Logging/
│
├── tests/
│   └── WsusManager.Tests/
│
└── WsusManager.sln
```

---

## v4.3 Theming Architecture Addendum

**Confidence: HIGH** — Patterns confirmed by multiple authoritative WPF theming sources.

### Theming System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        WsusManager.App (UI)                          │
│                                                                       │
│  ┌──────────────┐  ┌────────────────────┐  ┌─────────────────────┐  │
│  │ MainWindow   │  │  SettingsDialog    │  │  Other Dialogs      │  │
│  │ .xaml        │  │  .xaml (extended)  │  │  (color refs →      │  │
│  │ DynamicRes   │  │  + ThemePickerPanel│  │   DynamicResource)  │  │
│  └──────┬───────┘  └────────┬───────────┘  └──────────────────── ┘  │
│         │                   │ DynamicResource bindings               │
│  ┌──────▼───────────────────▼────────────────────────────────────┐  │
│  │                      App.xaml Resources                         │  │
│  │   MergedDictionary[0] = Themes/{Active}Theme.xaml  (swappable) │  │
│  │   MergedDictionary[1] = Themes/SharedStyles.xaml   (permanent) │  │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────── ┐ │
│  │                     Themes/ Directory                            │ │
│  │  [0] DarkTheme.xaml     (color tokens only — 14 keys)           │ │
│  │  [0] JustBlackTheme.xaml                                        │ │
│  │  [0] SlateTheme.xaml                                            │ │
│  │  [0] SerenityTheme.xaml                                         │ │
│  │  [0] RoseTheme.xaml                                             │ │
│  │  [0] ClassicBlueTheme.xaml                                      │ │
│  │  [1] SharedStyles.xaml  (all styles — refs DynamicResource)     │ │
│  └──────────────────────────────────────────────────────────────── ┘ │
│                                                                       │
│  ┌──────────────────────┐   ┌────────────────────────────────────┐  │
│  │  MainViewModel.cs    │   │  ThemeService.cs (NEW)             │  │
│  │  + SelectedTheme     │   │  ApplyTheme(string themeName)      │  │
│  │  (applies on startup)│   │  AvailableThemes list              │  │
│  └──────────┬───────────┘   └────────────────────────────────────┘  │
│             │ injects IThemeService                                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼─────────────────────────────────┐
│                      WsusManager.Core (Services)                      │
│  AppSettings.cs + string SelectedTheme = "Default Dark"               │
│  SettingsService.cs — unchanged, already persists AppSettings         │
└─────────────────────────────────────────────────────────────────────┘
```

### The Core Architectural Split: Tokens vs Styles

The existing `DarkTheme.xaml` mixes two concerns:

1. **Color tokens** — `SolidColorBrush` and `Color` resource definitions (14 keys: BgDark, BgSidebar, BgCard, BgInput, Border, Blue, Green, Orange, Red, Text1, Text2, Text3, ColorGreen, ColorOrange, ColorRed, ColorBlue, ColorText2)
2. **Style definitions** — `<Style>` blocks for NavBtn, NavBtnActive, Btn, BtnSec, BtnGreen, BtnRed, QuickActionBtn, CategoryLabel, CardTitle, CardValue, CardSubtext, LogTextBox, ProgressBar, ScrollBar

For runtime theme switching, these must be separated:

- **Theme files** (swappable) — color tokens only. One file per theme, all 14 keys defined identically.
- **SharedStyles.xaml** (permanent) — all `<Style>` blocks. References color tokens via `{DynamicResource}` so styles automatically adapt when the token dictionary swaps.

This split is required because WPF's `{StaticResource}` is resolved once at XAML parse time. Swapping the dictionary has no effect on elements that used `{StaticResource}`. Only `{DynamicResource}` responds to runtime dictionary changes.

### ThemeService Component

```csharp
// WsusManager.App/Services/IThemeService.cs
public interface IThemeService
{
    IReadOnlyList<string> AvailableThemes { get; }
    string CurrentTheme { get; }
    void ApplyTheme(string themeName);
}

// WsusManager.App/Services/ThemeService.cs
public class ThemeService : IThemeService
{
    // Position 0 in MergedDictionaries is always the swappable color token dict
    private const int ThemeDictionaryIndex = 0;

    private static readonly Dictionary<string, string> ThemeUris = new()
    {
        ["Default Dark"]  = "Themes/DarkTheme.xaml",
        ["Just Black"]    = "Themes/JustBlackTheme.xaml",
        ["Slate"]         = "Themes/SlateTheme.xaml",
        ["Serenity"]      = "Themes/SerenityTheme.xaml",
        ["Rose"]          = "Themes/RoseTheme.xaml",
        ["Classic Blue"]  = "Themes/ClassicBlueTheme.xaml",
    };

    public IReadOnlyList<string> AvailableThemes => ThemeUris.Keys.ToList();
    public string CurrentTheme { get; private set; } = "Default Dark";

    // MUST be called from UI thread — manipulates Application.Current.Resources
    public void ApplyTheme(string themeName)
    {
        if (!ThemeUris.TryGetValue(themeName, out var uri)) return;

        var dicts = Application.Current.Resources.MergedDictionaries;
        if (dicts.Count > ThemeDictionaryIndex)
            dicts.RemoveAt(ThemeDictionaryIndex);

        dicts.Insert(ThemeDictionaryIndex, new ResourceDictionary
        {
            Source = new Uri(uri, UriKind.Relative)
        });

        CurrentTheme = themeName;
    }
}
```

### What Changes in the Existing Codebase

| File | Change | Detail |
|------|--------|--------|
| `Themes/DarkTheme.xaml` | Refactored | Remove all `<Style>` blocks — keep 14 color token keys only |
| `App.xaml` | Modified | Add `SharedStyles.xaml` as second `MergedDictionary` |
| `AppSettings.cs` | Modified | Add `string SelectedTheme = "Default Dark"` property |
| `MainWindow.xaml` | Modified | 157 color `{StaticResource}` → `{DynamicResource}` (style refs stay StaticResource) |
| `SettingsDialog.xaml` | Modified | Add ThemePicker section; increase Height |
| `SettingsDialog.xaml.cs` | Modified | Inject `IThemeService`, store `_originalTheme`, revert on Cancel, include theme in Result |
| `InstallDialog.xaml` | Modified | 15 color refs → `{DynamicResource}` |
| `TransferDialog.xaml` | Modified | 28 color refs → `{DynamicResource}` |
| `ScheduleTaskDialog.xaml` | Modified | 26 color refs → `{DynamicResource}` |
| `SyncProfileDialog.xaml` | Modified | 14 color refs → `{DynamicResource}` |
| `GpoInstructionsDialog.xaml` | Modified | 7 color refs → `{DynamicResource}` |
| `MainViewModel.cs` | Modified | Inject `IThemeService`, call `ApplyTheme` in `InitializeAsync` and `OpenSettings` |
| `Program.cs` | Modified | Register `IThemeService, ThemeService` as singleton |

**New files:**
- `Themes/SharedStyles.xaml` — all styles extracted from DarkTheme.xaml, colors → `{DynamicResource}`
- `Themes/JustBlackTheme.xaml`, `SlateTheme.xaml`, `SerenityTheme.xaml`, `RoseTheme.xaml`, `ClassicBlueTheme.xaml` — 5 color token files
- `Services/IThemeService.cs` + `Services/ThemeService.cs`

**What does NOT change:**
- All services in `WsusManager.Core` — theming is purely UI-layer
- `SettingsService.cs` — already persists `AppSettings` generically; adding a new field requires no code change
- All `*.cs` files in `Views/` except `SettingsDialog.xaml.cs`
- Test project — `ThemeService` has no testable logic (visual output, WPF runtime required)

### Theme File Structure (Color Tokens Only)

Every theme file must define all 14 keys. Missing a key causes `ResourceReferenceKeyNotFoundException` at the point where that resource is first accessed.

```xml
<!-- Themes/SlateTheme.xaml — cool grey variant example -->
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <!-- Background Colors -->
    <SolidColorBrush x:Key="BgDark"    Color="#1E2130"/>
    <SolidColorBrush x:Key="BgSidebar" Color="#252A3B"/>
    <SolidColorBrush x:Key="BgCard"    Color="#2D3348"/>
    <SolidColorBrush x:Key="BgInput"   Color="#1E2130"/>
    <SolidColorBrush x:Key="Border"    Color="#3A4060"/>

    <!-- Accent Colors -->
    <SolidColorBrush x:Key="Blue"   Color="#7B9CFF"/>
    <SolidColorBrush x:Key="Green"  Color="#4DC973"/>
    <SolidColorBrush x:Key="Orange" Color="#E0A030"/>
    <SolidColorBrush x:Key="Red"    Color="#FF5F56"/>

    <!-- Text Colors -->
    <SolidColorBrush x:Key="Text1" Color="#E8EEF8"/>
    <SolidColorBrush x:Key="Text2" Color="#8E99BB"/>
    <SolidColorBrush x:Key="Text3" Color="#4A5275"/>

    <!-- Raw Color Values (for code-behind / converter usage) -->
    <Color x:Key="ColorGreen">#4DC973</Color>
    <Color x:Key="ColorOrange">#E0A030</Color>
    <Color x:Key="ColorRed">#FF5F56</Color>
    <Color x:Key="ColorBlue">#7B9CFF</Color>
    <Color x:Key="ColorText2">#8E99BB</Color>
</ResourceDictionary>
```

### Data Flow for Theme Changes

**On theme selection in SettingsDialog (live preview):**
```
User clicks theme swatch
    ↓
SettingsDialog.OnThemeSelected(themeName)
    ↓
_themeService.ApplyTheme(themeName)  [UI thread — event handler]
    ↓
ThemeService swaps MergedDictionaries[0]
    ↓
WPF DynamicResource engine propagates to all bound elements
    ↓ (immediate, no manual refresh needed)
All open windows repaint with new colors
```

**On Cancel (revert live preview):**
```
User clicks Cancel
    ↓
SettingsDialog.BtnCancel_Click
    ↓
_themeService.ApplyTheme(_originalTheme)  [reverts to pre-dialog state]
    ↓
DialogResult = false; Close()
```

**On Save:**
```
User clicks Save
    ↓
SettingsDialog.Result includes SelectedTheme = current theme name
    ↓
MainViewModel.OpenSettings → updated._settings.SelectedTheme = Result.SelectedTheme
    ↓
_settingsService.SaveAsync(_settings)  [theme name persisted to JSON]
    ↓ (theme is already applied — no second ApplyTheme call needed)
```

**On application startup (restore saved theme):**
```
Program.cs → MainViewModel.InitializeAsync()
    ↓
_settingsService.LoadAsync() → AppSettings.SelectedTheme = "Slate"
    ↓
ApplySettings(settings) → _themeService.ApplyTheme(settings.SelectedTheme)
    ↓ (before MainWindow is shown — no flash of wrong theme)
```

### ThemePicker UI in SettingsDialog

The ThemePicker section sits below existing settings rows. Design constraints:

- 6 clickable color swatches arranged in a 3x2 grid (or single row with wrapping)
- Each swatch shows a small rectangle using the theme's primary color, plus a label
- Active selection shows a border/highlight ring
- Clicking applies live preview immediately via `_themeService.ApplyTheme()`
- SettingsDialog height increases from 380px to approximately 500px to accommodate

The swatch colors are hardcoded in the ThemePicker XAML (not dynamically bound) because they must show the target theme's color while a different theme is active. They are presentational only.

### Build Order for v4.3

Dependencies determine order. Each step must compile before the next:

1. **Split DarkTheme.xaml → DarkTheme.xaml (tokens) + SharedStyles.xaml (styles)** — Update `App.xaml` to merge both. Migrate all `{StaticResource}` color references in `SharedStyles.xaml` to `{DynamicResource}`. Verify app builds and renders correctly with default dark theme. This is the foundation — all other steps depend on the token/style separation being correct.

2. **Add `IThemeService` and `ThemeService`** — Define interface and implementation. Register in `Program.cs` as singleton. No UI changes yet. The service is functional once the token dictionary is properly separated (Step 1).

3. **Add `SelectedTheme` to `AppSettings`** — Single property with default value. Forward-compatible with existing `settings.json` files (JSON deserializer ignores missing properties and uses the default).

4. **Create 5 additional theme files** — Independent of each other. Requires the finalized list of 14 token keys from Step 1. Each file is a copy of `DarkTheme.xaml` with different color values.

5. **Migrate `{StaticResource}` → `{DynamicResource}` in all view XAML files** — Affects MainWindow.xaml (157 refs), SettingsDialog.xaml (18), InstallDialog.xaml (15), TransferDialog.xaml (28), ScheduleTaskDialog.xaml (26), SyncProfileDialog.xaml (14), GpoInstructionsDialog.xaml (7). Total: ~265 mechanical changes. Style key references (NavBtn, BtnSec, etc.) must stay as `{StaticResource}`. Color token references (BgDark, Text1, Blue, etc.) become `{DynamicResource}`. Verify each dialog opens correctly after migration.

6. **Update `MainViewModel`** — Add `IThemeService` constructor parameter. Call `_themeService.ApplyTheme(settings.SelectedTheme)` in `ApplySettings()`. No new commands needed — theme selection happens inside SettingsDialog.

7. **Extend `SettingsDialog`** — Add ThemePicker section to XAML. Update constructor to accept `IThemeService`. Store `_originalTheme` at open time. Wire swatch click handlers to call live preview. Pass `SelectedTheme` in `Result`. Handle Cancel revert.

8. **Integration test** — Switch theme → Save → reopen Settings (selection preserved) → restart app (theme restored from JSON). Test Cancel reverts the preview.

---

## Architectural Patterns

### Pattern 1: Generic Host + Constructor Injection

**What:** Use `Microsoft.Extensions.Hosting` `Host.CreateApplicationBuilder()` as the DI/logging/config container. Wire `MainWindow` and `MainViewModel` through the DI container so all service dependencies are injected automatically.

**When to use:** Always — this is the modern .NET 8 WPF startup pattern.

**Trade-offs:** Slightly more startup ceremony than `new App()`, but gains unified DI, structured logging (via `ILogger<T>`), and configuration for free.

### Pattern 2: Async Command Pattern with CancellationToken

**What:** All long-running operations in the ViewModel use `async Task` RelayCommands. Each operation accepts a `CancellationToken` from a shared `CancellationTokenSource` that the Cancel button triggers.

**When to use:** Every operation that runs for more than ~200ms (health check, cleanup, sync, export, install). Theme switching is synchronous and does not use this pattern.

### Pattern 3: Service Methods Return `OperationResult`

**What:** Every service method returns `OperationResult` (or `OperationResult<T>`) rather than throwing exceptions for expected failure conditions.

**When to use:** All public service methods in `WsusManager.Core`. `ThemeService.ApplyTheme` is void (theme switching cannot meaningfully fail except for missing XAML file, which is a programming error).

### Pattern 4: Split Token Dictionary + Stable Style Dictionary (Theming)

**What:** Color tokens (brush/color resource keys) live in a swappable `ResourceDictionary`. Style definitions live in a separate permanent dictionary that references color tokens via `{DynamicResource}`. Only the token dictionary is swapped at runtime.

**When to use:** Any WPF application requiring runtime theme switching.

**Trade-offs:** Requires migrating `{StaticResource}` → `{DynamicResource}` for color references in all XAML. `DynamicResource` has negligible overhead (<2% UI thread impact at typical admin tool density).

---

## Anti-Patterns

### Anti-Pattern 1: Dispatcher.Invoke in ViewModels or Services

**What people do:** Call `Application.Current.Dispatcher.Invoke()` to update UI from service code.

**Why it's wrong:** Creates hard WPF dependency in Core library, breaks unit testing. Properties on `ObservableObject` automatically marshal to the UI thread — no dispatcher calls needed.

**Do this instead:** Use `[ObservableProperty]` from CommunityToolkit.Mvvm. Use `IProgress<T>` for service-to-ViewModel reporting.

### Anti-Pattern 2: Keeping StaticResource for Color Tokens in Views

**What people do:** Leave `{StaticResource BgDark}` unchanged in XAML views after splitting the dictionaries.

**Why it's wrong:** `{StaticResource}` is resolved once at XAML load time. Swapping the merged dictionary at runtime has no effect on those elements. Theme changes appear to do nothing.

**Do this instead:** All color token references in view XAML use `{DynamicResource}`. Style name references (NavBtn, BtnSec, etc.) can stay `{StaticResource}` — styles themselves do not swap, only the colors inside them.

### Anti-Pattern 3: Putting Styles in the Swappable Dictionary

**What people do:** Keep styles in the theme file alongside color tokens so no reorganization is needed.

**Why it's wrong:** Styles that use `{StaticResource}` internally (for earlier-defined brushes in the same dictionary) break when that dictionary is cleared and replaced — the resource lookup scope no longer exists. WPF must also reparse all style templates on every theme change.

**Do this instead:** Styles go in `SharedStyles.xaml` (permanent). Colors go in the swappable theme files. Styles reference colors via `{DynamicResource}`.

### Anti-Pattern 4: Not Reverting Theme on Cancel

**What people do:** Apply live preview immediately on selection change, but do not restore the original theme when the user clicks Cancel.

**Why it's wrong:** Cancel means "nothing changed." If the theme changed during preview and is not reverted, the visual state diverges from `settings.json` until the next restart.

**Do this instead:** Store `_originalTheme` when the dialog opens. `BtnCancel_Click` calls `_themeService.ApplyTheme(_originalTheme)` before closing.

### Anti-Pattern 5: Calling ApplyTheme from a Background Thread

**What people do:** Call `ThemeService.ApplyTheme` from a `Task.Run` or async continuation.

**Why it's wrong:** `Application.Current.Resources.MergedDictionaries` is a UI-thread-only object. Modifying it from a background thread throws `InvalidOperationException`.

**Do this instead:** `ApplyTheme` is always called from UI thread — in SettingsDialog event handlers and in `MainViewModel.ApplySettings()` which runs synchronously on the UI thread at startup.

### Anti-Pattern 6: Hardcoding Colors in New UI Elements

**What people do:** Add ThemePicker UI in SettingsDialog using hardcoded hex values like `Background="#21262D"`.

**Why it's wrong:** Hardcoded colors bypass the theming system. The ThemePicker panel looks wrong in non-dark themes.

**Do this instead:** All color values in styles reference token keys via `{DynamicResource}`. New UI for the ThemePicker uses existing token keys (BgCard, Border, Text1, etc.).

### Anti-Pattern 7: Shared Mutable State Between Operations

**What people do:** Use class-level `bool _operationRunning` flags updated from multiple concurrent paths.

**Why it's wrong:** Race conditions when async operations complete out of order. Use `[ObservableProperty] private bool _isOperationRunning` as the single source of truth with `[NotifyCanExecuteChangedFor]`.

---

## Integration Points

### External Systems

| System | Integration Pattern | Notes |
|--------|---------------------|-------|
| SQL Server Express (SUSDB) | `Microsoft.Data.SqlClient` async ADO.NET | Connection string: `Data Source=localhost\SQLEXPRESS;Initial Catalog=SUSDB;Integrated Security=true;TrustServerCertificate=true` |
| WSUS Windows Service | `System.ServiceProcess.ServiceController` | Re-query status every time |
| IIS (W3SVC) | `ServiceController` + `ProcessRunner` wrapping `appcmd.exe` | Only for start/stop |
| Windows Firewall | `ProcessRunner` + `netsh advfirewall firewall` | Present on all Windows Server 2019+ targets |
| `wsusutil.exe` | `ProcessRunner` | Path: `%ProgramFiles%\Update Services\Tools\wsusutil.exe` |
| WPF Resource System | `Application.Current.Resources.MergedDictionaries` | Theme switching — UI thread only |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| ViewModel to Service | Constructor-injected interface, `async Task` calls | ViewModel never knows concrete types |
| `SettingsDialog` ↔ `ThemeService` | Direct call (DI injection) | Dialog gets `IThemeService` for live preview |
| `MainViewModel` ↔ `ThemeService` | Direct call (DI injection) | ViewModel applies theme on startup and after settings save |
| `ThemeService` ↔ WPF Resources | `Application.Current.Resources.MergedDictionaries` | Must run on UI thread — no async, no Task.Run |
| `AppSettings` ↔ theme names | `string SelectedTheme` property | ThemeService maps name → XAML URI internally |

---

## Single EXE Publication

The application publishes as a self-contained single-file EXE using .NET 8's `PublishSingleFile` + `SelfContained` options. Theme XAML files are embedded as application resources (Build Action: `Resource`) and referenced via relative URIs (`new Uri("Themes/DarkTheme.xaml", UriKind.Relative)`). This works correctly with single-file EXE publication — WPF resource packs are bundled into the EXE.

---

## Sources

- [Changing WPF themes dynamically — Marko Devcic](https://www.markodevcic.com/post/Changing_WPF_themes_dynamically/) — HIGH confidence (confirmed pattern)
- [WPF complete guide to Themes and Skins — Michael's Coding Spot](https://michaelscodingspot.com/wpf-complete-guide-themes-skins/) — HIGH confidence (SkinResourceDictionary pattern, XAML Designer considerations)
- [Mastering Dynamic Resources in WPF — Moldstud](https://moldstud.com/articles/p-mastering-dynamic-resources-in-wpf-a-comprehensive-guide-for-developers) — MEDIUM confidence (practical guidance, performance benchmarks)
- [WPF: StaticResource vs. DynamicResource — CodeProject](https://www.codeproject.com/Articles/393086/WPF-StaticResource-vs-DynamicResource) — HIGH confidence (authoritative reference)
- [CommunityToolkit.Mvvm IoC documentation](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/mvvm/ioc) — HIGH confidence
- [.NET Generic Host documentation](https://learn.microsoft.com/en-us/dotnet/core/extensions/generic-host) — HIGH confidence
- Existing codebase analysis: `DarkTheme.xaml` (14 token keys, 18 internal StaticResource cross-refs), `MainWindow.xaml` (157 StaticResource usages), `App.xaml` (single MergedDictionary structure), `AppSettings.cs` (existing settings model), `SettingsService.cs` (JSON persistence pattern)

---

*Architecture research for: C#/.NET 8 WPF WSUS management administration tool with v4.3 theming system*
*Initial research: 2026-02-19 | Theming addendum: 2026-02-20*
