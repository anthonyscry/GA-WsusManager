---
phase: 09-launch-and-ui-verification
subsystem: app-startup, ui, dashboard
tags: [launch, ui, verification, bugfix, dark-theme]
key-files:
  read:
    - src/WsusManager.App/Program.cs
    - src/WsusManager.App/App.xaml
    - src/WsusManager.App/App.xaml.cs
    - src/WsusManager.App/Views/MainWindow.xaml
    - src/WsusManager.App/Views/MainWindow.xaml.cs
    - src/WsusManager.App/Themes/DarkTheme.xaml
    - src/WsusManager.App/ViewModels/MainViewModel.cs
    - src/WsusManager.App/WsusManager.App.csproj
    - src/WsusManager.Core/WsusManager.Core.csproj
    - src/WsusManager.Core/Services/DashboardService.cs
    - src/WsusManager.Core/Services/SettingsService.cs
    - src/WsusManager.Core/Logging/LogService.cs
    - src/WsusManager.Core/Models/AppSettings.cs
    - src/WsusManager.Tests/Integration/DiContainerTests.cs
    - src/WsusManager.Tests/ViewModels/MainViewModelTests.cs
---

# Phase 9 Context: Launch and UI Verification

## Goal

Verify that the application launches without crash, displays the correct dark theme,
populates the dashboard, and allows panel navigation and log panel interaction.
This phase is about verification and bug fixing, not new features.

## Current Build State

As of Phase 8 (completed 2026-02-20):
- All three projects target `net8.0-windows`
- `dotnet build` succeeds with 0 errors, 0 warnings
- 245 tests pass (Core, Integration, Services — not ViewModel or ExeValidation, which require Windows WPF runtime)
- No published EXE artifact yet in the `src/` tree (ExeValidation tests are deferred to CI)

---

## Startup Flow Analysis (UI-01)

**Entry point:** `src/WsusManager.App/Program.cs` — `Program.Main()`

The startup sequence is:
1. `LogService` is constructed directly (not via DI) — writes to `C:\WSUS\Logs\`
2. `Host.CreateApplicationBuilder` is called; all services are registered as singletons
3. `new App()` is created, `InitializeComponent()` called (loads App.xaml and DarkTheme.xaml)
4. `app.ConfigureServices(host.Services)` wires up global exception handlers
5. `host.Services.GetRequiredService<MainWindow>()` resolves the DI graph
6. `app.Run(window)` starts the WPF message loop
7. On `MainWindow.Loaded`, `_viewModel.InitializeAsync()` is called (loads settings, first dashboard refresh, starts timer)

**Potential crash vectors identified:**

### ISSUE-01: Log directory creation on non-WSUS server (non-fatal)
`LogService` and `Program.cs` both attempt to create `C:\WSUS\Logs` at startup.
`LogService` wraps directory creation in a try/catch and silences the error — Serilog
will degrade gracefully if the directory doesn't exist. This is non-fatal and correct.

### ISSUE-02: Serilog sink package missing from App project (potential build/runtime issue)
`Program.cs` creates a second Serilog `LoggerConfiguration` with `WriteTo.File(...)`.
The App project only references `Serilog.Extensions.Logging` (version 8.*).
It does NOT reference `Serilog.Sinks.File` directly.
`Serilog.Sinks.File` is a transitive dependency pulled from `WsusManager.Core`,
which DOES reference `Serilog.Sinks.File` version 6.*.

This means the App project relies on `Core` to provide the sink assembly at runtime.
Because publish is self-contained, all assemblies will be bundled — this works but
is fragile. If Core's dependency is ever removed or the package version changes,
the App project's Serilog configuration in `Program.cs` will throw `MissingMethodException`
at runtime. **Severity: Low** (currently works but should be documented).

### ISSUE-03: Duplicate "WSUS not installed" log message in InitializeAsync
In `MainViewModel.InitializeAsync()` (lines 865-883), the code prints the startup
message BEFORE calling `RefreshDashboard()` (which sets `IsWsusInstalled`), and then
prints the SAME message AFTER:

```csharp
// Before refresh (IsWsusInstalled is still false from default)
if (!IsWsusInstalled)
{
    AppendLog("WSUS is not installed on this server.");
    AppendLog("To get started, click 'Install WSUS' in the sidebar.");
    AppendLog("");
}

// First dashboard refresh
await RefreshDashboard();  // This sets IsWsusInstalled correctly

// After refresh (may still print if WSUS really isn't installed)
if (!IsWsusInstalled)
{
    AppendLog("WSUS is not installed on this server.");
    AppendLog("To get started, click 'Install WSUS' in the sidebar.");
    AppendLog("All other operations require WSUS to be installed first.");
    AppendLog("");
}
```

The FIRST block always fires on startup because `IsWsusInstalled` defaults to `false`.
After `RefreshDashboard()` sets the actual value, the SECOND block fires only if
WSUS is truly not installed. But on a machine WITH WSUS installed, the user still sees
the spurious first message.

**Severity: Medium** — visible to users, breaks the "WSUS is installed" first impression.
**Fix required:** Remove the first block. Only show the message after the refresh.

### ISSUE-04: Missing Serilog.Sinks.File on App's own logger in Program.cs (investigation needed)
`Program.cs` creates its own Serilog logger for `Microsoft.Extensions.Logging`:
```csharp
var serilogLogger = new LoggerConfiguration()
    .WriteTo.File(...)   // Requires Serilog.Sinks.File
    .CreateLogger();
```

If this throws (e.g., missing sink), it will crash before the window opens with no
user-visible error (unless the AppDomain handler catches it). Since the test suite
passes with 245 tests and the build succeeds, this is likely fine via transitive
dependency, but worth verifying.

---

## Dark Theme Analysis (UI-03)

`src/WsusManager.App/Themes/DarkTheme.xaml` defines all resources used by
`MainWindow.xaml`. All resources referenced in the XAML were verified against
the theme file:

**Colors defined:**
- `BgDark` (#0D1117), `BgSidebar` (#161B22), `BgCard` (#21262D), `BgInput` (#0D1117), `Border` (#30363D)
- `Blue` (#58A6FF), `Green` (#3FB950), `Orange` (#D29922), `Red` (#F85149)
- `Text1` (#E6EDF3), `Text2` (#8B949E), `Text3` (#484F58)
- Raw color keys: `ColorGreen`, `ColorOrange`, `ColorRed`, `ColorBlue`, `ColorText2`

**Styles defined:**
- `NavBtn`, `NavBtnActive`, `Btn`, `BtnSec`, `BtnGreen`, `BtnRed`, `QuickActionBtn`
- `CategoryLabel`, `CardTitle`, `CardValue`, `CardSubtext`
- `LogTextBox`
- Global `ScrollBar` style (no key — applies to all ScrollBar elements)

**MainWindow.xaml resource cross-check:** All `{StaticResource ...}` references in
MainWindow.xaml map to keys defined in DarkTheme.xaml. No missing resource keys detected.

**App.xaml merge:** `App.xaml` correctly merges DarkTheme.xaml as a `MergedDictionary`,
making all resources available application-wide.

**Potential issue:** `NavBtnActive` style is defined in DarkTheme.xaml but never
referenced in `MainWindow.xaml`. There is no active-state visual for the selected
sidebar button — all nav buttons use `NavBtn` style regardless of current panel.
**Severity: Visual gap** — not a crash but the selected nav item has no visual indicator.

---

## Dashboard Population Analysis (UI-02)

`DashboardService.CollectAsync()` runs four checks in parallel:
1. **Services** — `ServiceController` queries for `MSSQL$SQLEXPRESS`, `WsusService`, `W3SVC`
2. **Database size** — SQL query `sys.database_files` with 5s timeout
3. **Disk space** — `DriveInfo` for the drive containing `ContentPath`
4. **Scheduled task** — `schtasks.exe /Query`

All four are wrapped in try/catch. On a machine without WSUS:
- Services check: `InvalidOperationException` is silently caught per service
- `IsWsusInstalled` is set to `false` when `WsusService` is not found
- Database check: `SqlException` is caught, `DatabaseSizeGB = -1`
- Disk check: Uses `contentPath[..1]` as drive letter — safe as long as `ContentPath` is non-empty (defaults to `C:\WSUS`)
- Task check: `schtasks.exe` returns non-zero, `TaskStatus = "Not Found"`
- Connectivity: Ping to 8.8.8.8 with 500ms timeout — returns `false` if offline

**No crash risk in dashboard collection.** All error paths degrade gracefully to
"N/A" / "Not Installed" display values.

**Performance concern:** `schtasks.exe` is spawned synchronously inside `Task.Run`,
with a 3-second `WaitForExit`. On a slow system, this can delay dashboard refresh
by up to 3 seconds per cycle (every 30 seconds). This is the same pattern as the
PowerShell version and is acceptable.

---

## Panel Navigation Analysis (UI-04)

The panel switching mechanism uses three `Visibility` properties computed from `CurrentPanel`:

```csharp
public Visibility IsDashboardVisible =>
    CurrentPanel == "Dashboard" ? Visibility.Visible : Visibility.Collapsed;

public Visibility IsDiagnosticsPanelVisible =>
    CurrentPanel == "Diagnostics" ? Visibility.Visible : Visibility.Collapsed;

public Visibility IsDatabasePanelVisible =>
    CurrentPanel == "Database" ? Visibility.Visible : Visibility.Collapsed;

public Visibility IsOperationPanelVisible =>
    CurrentPanel != "Dashboard" && CurrentPanel != "Diagnostics" && CurrentPanel != "Database"
        ? Visibility.Visible
        : Visibility.Collapsed;
```

`Navigate()` calls `OnPropertyChanged` for all four visibility properties after
updating `CurrentPanel`. This is correct and complete.

**Sidebar buttons** use `NavigateCommand` with parameters: "Dashboard", "Settings",
"Help", "About", "Diagnostics", "Database".

**Operation-triggering buttons** (Install, GPO, Transfer, Sync, Schedule) each call
their own dedicated commands that show a dialog first, THEN navigate — correct CLAUDE.md
pattern is followed.

**Issue:** The sidebar nav buttons that navigate to "Settings", "Help", "About" show
the generic `OperationPanel` which displays:
```
{PageTitle}
This operation will be available in a future update.
```
This is by design for now (placeholder panels). No fix needed here for Phase 9.

**No missing `OnPropertyChanged` calls detected** — all four visibility properties
are updated together in `Navigate()`.

---

## Log Panel Analysis (UI-05)

The log panel consists of:
- A header bar with "Output Log", current operation name, Cancel, Hide/Show, Clear, Save buttons
- A `TextBox` with `Style="{StaticResource LogTextBox}"` and `Height="{Binding LogPanelHeight}"`
- `LogPanelHeight` returns 250 when expanded, 0 when collapsed
- `TextChanged` event in code-behind calls `textBox.ScrollToEnd()` for auto-scroll

**Potential issue:** Using `Height=0` to hide the log panel instead of `Visibility=Collapsed`.
When height is 0, the TextBox still participates in layout measurement and event routing.
This is a minor inefficiency but not a crash risk. The `LogTextVisibility` binding
uses `Visibility.Collapsed` when collapsed, so the TextBox has both height=0 AND
Visibility=Collapsed. Both bindings exist and are correct.

**Log output accumulation:** `AppendLog` concatenates to `LogOutput` string:
```csharp
public void AppendLog(string line)
{
    LogOutput += line + Environment.NewLine;
}
```

For long operations this string grows unbounded. On a production WSUS server with
many cleanup operations, this could consume significant memory and slow the UI.
**Severity: Low** — acceptable for now, a future improvement would ring-buffer the log.

---

## DI Container Completeness

`Program.cs` registers 20 services (including `MainViewModel` and `MainWindow`).
`DiContainerTests.cs` verifies all 20 resolve correctly (including `All_17_Service_Interfaces_Resolve`).

The test registers services in the SAME order and with the SAME types as `Program.cs`.
This test passing guarantees the DI graph is acyclic and all constructor dependencies
are satisfiable.

**One discrepancy:** `Program.cs` uses `Host.CreateApplicationBuilder` (from
`Microsoft.Extensions.Hosting`) while `DiContainerTests.cs` uses a plain
`ServiceCollection`. Both result in equivalent service graphs for singleton registration.

---

## .NET 8 API Compatibility

The code was audited for .NET 9-specific APIs:

- `Ping.SendPingAsync` — available since .NET 5, fine on .NET 8
- `Host.CreateApplicationBuilder` — available since .NET 6, fine on .NET 8
- `ServiceController` — available since .NET 1.1, fine on .NET 8
- `DriveInfo` — available since .NET 2.0, fine on .NET 8
- `CommunityToolkit.Mvvm` 8.4.0 — supports .NET 8
- `Microsoft.Data.SqlClient` 6.1.4 — supports .NET 8
- `Serilog` 4.x — supports .NET 8

No .NET 9-specific APIs detected. All packages are version-pinned to .NET 8
compatible versions. The `Directory.Build.props` has `EnableWindowsTargeting=true`
which allows cross-compilation from Linux/WSL (CI-safe).

---

## Summary of Issues to Fix in Phase 9

| ID | Severity | Description | Fix |
|----|----------|-------------|-----|
| ISSUE-01 | Info | Log dir creation on non-WSUS machine | Already handled gracefully |
| ISSUE-02 | Low | `Serilog.Sinks.File` is transitive from Core, not explicit in App | Add explicit package ref (optional, low priority) |
| ISSUE-03 | Medium | Duplicate "WSUS not installed" log message at startup | Remove the pre-refresh block in `InitializeAsync` |
| ISSUE-04 | Low | App's own Serilog logger depends on transitive sink | Same as ISSUE-02 |
| ISSUE-05 | Visual | `NavBtnActive` style defined but never applied | Apply active style to current nav button |

### Issues That Do NOT Need Fixing in Phase 9
- Dashboard collection gracefully handles no-WSUS-server scenario (works correctly)
- All XAML resource references are valid (no `XamlParseException` risk)
- DI container is complete and verified by integration tests
- All four panels switch correctly via `NavigateCommand`
- Log panel collapse/expand works via `LogPanelHeight` + `LogTextVisibility`
- Auto-scroll via `TextChanged` event is correct

---

## Files to Modify in Phase 9

### Primary fix (ISSUE-03):
- `src/WsusManager.App/ViewModels/MainViewModel.cs`
  Remove the pre-refresh "WSUS not installed" block (lines 865-870)

### Optional enhancement (ISSUE-05 — active nav button highlight):
- `src/WsusManager.App/Views/MainWindow.xaml`
  The sidebar buttons need to dynamically apply `NavBtnActive` style based on `CurrentPanel`
  This requires a value converter or triggers. Skip if out of scope for Phase 9.

### Tests to verify:
- `src/WsusManager.Tests/ViewModels/MainViewModelTests.cs`
  If startup message fix is made, verify `InitializeAsync` doesn't emit duplicate messages.
  Currently no test covers the startup log message content specifically.

---

## Phase 9 Acceptance Criteria (from requirements)

- **UI-01 (Launches without crash):** Startup flow is clean. Only ISSUE-03 (duplicate log message)
  is a user-visible defect. No crash vectors identified.
- **UI-02 (Dashboard populates):** `DashboardService` handles all error cases gracefully.
  Cards show "N/A" / "Not Installed" when WSUS is absent. No crash risk.
- **UI-03 (Dark theme correct):** All `{StaticResource}` references verified against DarkTheme.xaml.
  No missing keys. Theme applies via App.xaml MergedDictionaries.
- **UI-04 (All panels switch):** `NavigateCommand` with all panel names works. All four
  `Visibility` properties are updated together. No missing `OnPropertyChanged`.
- **UI-05 (Log panel works):** Toggle, clear, save, auto-scroll all implemented and wired.
  No crash risk. Minor unbounded string growth is acceptable for Phase 9.
